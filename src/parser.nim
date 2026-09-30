import std/algorithm
import std/strformat
import std/strutils
import errors
import lexer
import nodes
import tokens

type Parser = ref object
    ## A STARCH parser. Takes lexed tokens and converts them into an AST.
    tokens*: seq[Token]
    program*: Program
    filename*: string
    pos*: int

proc lookupPos(self: Parser, pos: int): tuple[line: int, col: int, content: string] {.inline.} =
    ## Get the text content of the current line.
    # Find the first line index greater than pos, then step back
    let line = self.program.lineIndex.lineStarts.upperBound(pos) - 1
    let col = (pos - self.program.lineIndex.lineStarts[line]) + 1 # 1-indexed column
    let ctx = ($self.program.source).splitLines()[line]

    return (line: line + 1, col: col, content: ctx)

proc error(self: Parser, kind: typedesc[StarchError], message: string): StarchError =
    ## Generates an error with intelligent position data.
    let (line, col, ctx) = self.lookupPos(self.current.pos)
    return newStarchError(
        kind = kind,
        msg = message,
        context = ctx,
        line = line,
        col = col,
        length = self.current.length,
        file = self.filename
    )

proc error(self: Parser, kind: typedesc[StarchError], message: string, node: Node): StarchError =
    ## Generates an error pointing at an already-parsed node rather than the current token.
    let (line, col, ctx) = self.lookupPos(node.pos)
    return newStarchError(
        kind = kind,
        msg = message,
        context = ctx,
        line = line,
        col = col,
        length = node.length,
        file = self.filename
    )

proc newParser*(tokens: seq[Token], filename: string, source: string, lineIndex: LineIndex): Parser =
    ## Creates a parser with default values.
    ## Comment tokens are stripped from the token stream up front and stored in
    ## Program.comments so that all helpers can ignore them entirely.
    var filteredTokens: seq[Token] = @[]
    var comments: seq[Token] = @[]
    for token in tokens:
        if token.kind == TokenType.comment:
            comments.add(token)
        else:
            filteredTokens.add(token)

    return Parser(
        tokens: filteredTokens,
        program: Program(
            source: source,
            lineIndex: lineIndex,
            comments: comments
        ),
        filename: filename
    )

proc current*(self: Parser): Token {.inline.} =
    ## Get the current token
    if self.pos >= len(self.tokens):
        when defined(debug):
            echo ".current oob; returning eof"
        return self.tokens[^1] # EOF
    return self.tokens[self.pos]

proc peek*(self: Parser, offset: int = 1): Token =
    ## Look at token self.pos + offset, without consuming it.
    let pos = self.pos + offset
    if pos >= len(self.tokens):
        when defined(debug):
            echo "peek oob; returning eof"
        return self.tokens[^1] # EOF token
    when defined(debug):
        echo &"peeked {offset}, returning {self.tokens[pos]}"
    return self.tokens[pos]

proc advance(self: Parser): Token =
    ## Advance past the current token, returning it.
    let token = self.current
    when defined(debug):
        echo "advancing past " & $token
    self.pos.inc()
    return token

proc expect(self: Parser, kind: TokenType): Token =
    ## Expect a token and consume it. Raises an error if the token is not expected.
    when defined(debug):
        echo &"validating for token {kind}"
    if self.current.kind != kind:
        raise self.error(StarchSyntaxError, &"expected {kind}, got {self.current.kind}")
    return self.advance()

proc terminate(self: Parser) =
    ## End a statement with a semicolon. Uses intelligent line positioning data for errors.
    when defined(debug):
        echo "=== terminating statement ==="
    if self.current.kind != TokenType.semicolon:
        let currentMeta = self.lookupPos(self.current.pos)
        let lastMeta = self.lookupPos(self.peek(-1).pos)
        let meta = if currentMeta.line != lastMeta.line: lastMeta
                   else: currentMeta
        let length = if currentMeta.line != lastMeta.line: self.peek(-1).length
                     else: self.current.length

        raise newStarchError(StarchSyntaxError, &"expected {TokenType.semicolon}", meta.content, meta.line, meta.col, length, self.filename)

    discard self.advance()

proc is_lambda(self: Parser): bool =
    ## Checks if the next tokens define a lambda function.
    var pos = self.pos + 1 # skip the left paren
    var depth = 1
    while pos < len(self.tokens):
        case self.tokens[pos].kind:
        of TokenType.lParen:
            depth.inc()
        of TokenType.rParen:
            depth.dec()
            if depth == 0:
                # Check bounds before looking ahead
                if pos + 1 < len(self.tokens):
                    return self.tokens[pos + 1].kind == TokenType.fatArrow
                return false
        else: discard
        pos += 1
    return false

# Stubs
proc parse_pipeline(self: Parser): Node
proc parse_unary(self: Parser): Node
proc parse_statement(self: Parser): Node

proc parse_expression(self: Parser): Node =
    ## Parse a STARCH expression.
    when defined(debug):
        echo "=== parsing expr ==="
    return self.parse_pipeline()

proc parse_block(self: Parser): seq[Node] =
    ## Parse several statements wrapped in braces.
    discard self.expect(TokenType.lBrace)
    result = @[]
    while self.current.kind != TokenType.rBrace:
        result.add(self.parse_statement())
    discard self.expect(TokenType.rBrace)

proc parse_type(self: Parser): Node =
    ## Parse a type hint, with support for unions, generics and optional types.
    let token = self.expect(TokenType.ident)
    # Start with the base identifier
    var currentType = node(token, self.peek(-1), NodeKind.identifier, name = token.value.strVal)

    if self.current.kind == TokenType.lBracket:
        # Generic — TypeA[T]
        discard self.advance()
        var parts = @[self.parse_type()]
        while self.current.kind == TokenType.comma:
            discard self.advance()
            parts.add(self.parse_type())
        discard self.expect(TokenType.rBracket)
        # Update currentType instead of returning
        currentType = node(token, self.peek(-1), NodeKind.genericType,
            genericKind = currentType,
            typeArgs = parts
        )

    if self.current.kind == TokenType.question:
        # Optional — TypeB? (equivalent to union with none)
        currentType = node(token, self.advance(), NodeKind.typeOptional, optionalKind = currentType)

    if self.current.kind == TokenType.pipe:
        # Union — TypeC | TypeD | TypeE
        var parts = @[currentType]
        while self.current.kind == TokenType.pipe:
            discard self.advance()
            parts.add(self.parse_type())
        return node(token, self.peek(-1), NodeKind.typeUnion, unionKinds = parts)

    # If not a union, return the current type
    return currentType

proc parse_params(self: Parser): seq[Node] =
    ## Parse parameters in a function definition.
    var params: seq[Node] = @[]
    while self.current.kind != TokenType.rParen:
        let name = self.expect(TokenType.ident)
        var hint: Node = nil
        var default: Node = nil

        if self.current.kind == TokenType.colon: # (x: int)
            discard self.advance()
            hint = self.parse_type()
        if self.current.kind == TokenType.default: # (name or "john")
            discard self.advance()
            default = self.parse_expression()
        params.add(node(name, self.peek(-1), NodeKind.parameter,
            paramName = node(name, name, NodeKind.identifier, name = name.value.strVal),
            paramHint = hint,
            paramDefault = default))

        if self.current.kind != TokenType.rParen:
            discard self.expect(TokenType.comma)
    return params

proc parse_args(self: Parser): seq[Node] =
    ## Parse arguments passed to a function call.
    var args: seq[Node] = @[]
    while self.current.kind != TokenType.rParen:
        args.add(self.parse_expression())
        if self.current.kind == TokenType.comma:
            discard self.advance()
    return args

proc parse_primary(self: Parser): Node =
    ## Parse a primary expression (literals, identifiers, groups and lambdas).
    # TODO: This does not support comprehensions.
    let token = self.current
    case token.kind:
        of TokenType.number:
            discard self.advance()
            return node(token, self.peek(-1), NodeKind.literal,
                literalKind = LiteralKind.int,
                literalValue = token.value.strVal
            )
        of TokenType.float:
            discard self.advance()
            return node(token, self.peek(-1), NodeKind.literal,
                literalKind = LiteralKind.float,
                literalValue = token.value.strVal
            )
        of TokenType.string:
            discard self.advance()
            return node(token, self.peek(-1), NodeKind.literal,
                literalKind = LiteralKind.string,
                literalValue = token.value.strVal
            )
        of TokenType.bool:
            discard self.advance()
            return node(token, self.peek(-1), NodeKind.literal,
                literalKind = LiteralKind.bool,
                boolVal = token.value.boolVal
            )
        of TokenType.ident:
            discard self.advance()
            return node(token, self.peek(-1), NodeKind.identifier,
                name = token.value.strVal
            )

        of TokenType.null:
            discard self.advance()
            return node(token, token, NodeKind.null)

        of TokenType.lParen:
            # () - grouping/lambda
            if self.is_lambda():
                # () => {}
                discard self.advance()
                let params = self.parse_params()
                discard self.expect(TokenType.rParen)
                discard self.expect(TokenType.fatArrow)
                let body = self.parse_block()
                return node(token, self.peek(-1), NodeKind.lambda,
                    lambdaParams = params,
                    lambdaBody = body)
            # (x)
            discard self.advance()
            let expression = self.parse_expression()
            discard self.expect(TokenType.rParen)
            return expression

        of TokenType.lBrace:
            # {} - dict/set literal
            discard self.advance()
            # The next item should be an expression
            # After that, if it's a comma then it's a set,
            # if it's a colon it's a dictionary
            # and if it's a right brace it's a one-item set.
            if self.current.kind == TokenType.rBrace:
                # Empty dict
                return node(token, self.advance(), NodeKind.dictLiteral, dictPairs = @[])

            let first = self.parse_expression()
            case self.current.kind:
            of TokenType.rBrace:
                # One-item set
                discard self.advance()
                return node(token, self.peek(-1), NodeKind.setLiteral, setItems = @[first])
            of TokenType.comma:
                # Set
                discard self.advance() # consume the comma
                var items = @[first]

                while self.current.kind != TokenType.eof:
                    # Support trailing commas
                    if self.current.kind == TokenType.rBrace:
                        break

                    items.add(self.parse_expression())
                    if self.current.kind == TokenType.rBrace:
                        break
                    discard self.expect(TokenType.comma)

                discard self.expect(TokenType.rBrace)
                return node(token, self.peek(-1), NodeKind.setLiteral, setItems = items)
            of TokenType.colon:
                # Dictionary
                discard self.advance() # consume the colon
                let value = self.parse_expression()
                var items = @[(key: first, value: value)]

                while self.current.kind != TokenType.eof:
                    if self.current.kind == TokenType.rBrace:
                        break

                    discard self.expect(TokenType.comma)

                    if self.current.kind == TokenType.rBrace: # support trailing comma
                        break

                    let key = self.parse_expression()

                    discard self.expect(TokenType.colon)
                    items.add((key: key, value: self.parse_expression()))

                discard self.expect(TokenType.rBrace)
                return node(token, self.peek(-1), NodeKind.dictLiteral, dictPairs = items)
            else:
                raise self.error(StarchSyntaxError, &"unexpected token {self.current} in dict/set literal")

        of TokenType.lBracket:
            # [] — list literal
            discard self.advance()

            var items: seq[Node] = @[]
            while self.current.kind != TokenType.eof:
                if self.current.kind == TokenType.rBracket:
                    break

                items.add(self.parse_expression())
                if self.current.kind == TokenType.rBracket:
                    break
                discard self.expect(TokenType.comma)

            discard self.expect(TokenType.rBracket)
            return node(token, self.peek(-1), NodeKind.listLiteral, listElements = items) # "elements" is kinda inconsistent why is it elements with a list but items with a set??? whatever bro
        else:
            raise self.error(StarchSyntaxError, &"unexpected token {token.kind}")

proc parse_call_or_access(self: Parser): Node =
    ## Parse a call or member access (function calls, indexes and dot notation).
    let start = self.current
    var expression = self.parse_primary()

    while true:
        case self.current.kind:
            of TokenType.lParen:
                # Function call
                discard self.advance()
                let args = self.parse_args()
                discard self.expect(TokenType.rParen)
                expression = node(start, self.peek(-1), NodeKind.functionCall, callCallee = expression, callArgs = args)

            of TokenType.lBracket:
                # Index access
                discard self.advance()
                var isSlice = false
                var index, stop, step: Node

                # Slot 1: Start/Index
                if not (self.current.kind in {TokenType.colon, TokenType.rBracket}):
                    index = self.parse_expression()

                # Slot 2: Stop
                if self.current.kind == TokenType.colon:
                    isSlice = true
                    discard self.advance()

                    if not (self.current.kind in {TokenType.colon, TokenType.rBracket}):
                        stop = self.parse_expression()

                # Slot 3: Step
                if self.current.kind == TokenType.colon:
                    discard self.advance()
                    if self.current.kind == TokenType.rBracket:
                        raise self.error(StarchSyntaxError, "expected expression")

                    step = self.parse_expression()

                discard self.expect(TokenType.rBracket)
                if isSlice and index == nil and stop == nil and step == nil:
                    raise self.error(StarchSyntaxError, "no slice values specified")

                if isSlice:
                    expression = node(start, self.peek(-1), NodeKind.slice, sliceObj = expression, sliceStart = index, sliceStop = stop, sliceStep = step)
                else:
                    expression = node(start, self.peek(-1), NodeKind.indexAccess, indexObj = expression, indexMember = index)

            of TokenType.dot:
                # Member access
                discard self.advance()
                let member = self.parse_expression()
                expression = node(start, self.peek(-1), NodeKind.memberAccess, accessObj = expression, accessMember = member)
            else:
                return expression

proc parse_exponent(self: Parser): Node =
    ## Parse an exponent.
    let base = self.parse_call_or_access()
    if self.current.kind == TokenType.caret:
        let token = self.advance()
        let exponent = self.parse_unary()
        return node(token, self.peek(-1), NodeKind.binaryOp,
            binaryOperator = token.kind,
            binaryLeft = base,
            binaryRight = exponent
        )
    return base

proc parse_unary(self: Parser): Node =
    ## Parse a unary (prefix) operation.
    let token = self.current
    if token.kind in {TokenType.minus, TokenType.bang, TokenType.await, TokenType.yield}:
        discard self.advance()
        let operand = self.parse_unary()
        return node(token, self.peek(-1), NodeKind.unaryOp, unaryOperator = token.kind, unaryOperand = operand)

    return self.parse_exponent()

proc parse_multiplicative(self: Parser): Node =
    ## Parse a multiplicative operation (*, /).
    var left = self.parse_unary()

    while self.current.kind in {TokenType.star, TokenType.slash, TokenType.percent}:
        let token = self.current
        let operator = self.advance().kind
        let right = self.parse_unary()
        left = node(token, self.peek(-1), NodeKind.binaryOp,
            binaryOperator = operator,
            binaryLeft = left,
            binaryRight = right
        )
    return left

proc parse_additive(self: Parser): Node =
    ## Parse an additive operation (+, -).
    var left = self.parse_multiplicative()

    while self.current.kind in {TokenType.plus, TokenType.minus}:
        let token = self.current
        let operator = self.advance().kind
        let right = self.parse_multiplicative()
        left = node(token, self.peek(-1), NodeKind.binaryOp,
            binaryOperator = operator,
            binaryLeft = left,
            binaryRight = right
        )
    return left

proc parse_range(self: Parser): Node =
    ## Parse the range operator (..).
    let token = self.current
    let left = self.parse_additive()

    if self.current.kind == TokenType.range:
        discard self.advance()
        let right = self.parse_additive()
        return node(token, self.peek(-1), NodeKind.binaryOp,
            binaryOperator = TokenType.range,
            binaryLeft = left,
            binaryRight = right
        )
    return left

proc parse_concat(self: Parser): Node =
    ## Parse the concatenation operator (x ~ y).
    let token = self.current
    var left = self.parse_range()

    while self.current.kind == TokenType.concat:
        discard self.advance()
        let right = self.parse_range()
        left = node(token, self.peek(-1), NodeKind.binaryOp,
            binaryOperator = TokenType.concat,
            binaryLeft = left,
            binaryRight = right
        )

    return left

proc parse_comparison(self: Parser): Node =
    ## Parse comparative operators (<, >).
    let token = self.current
    var left = self.parse_concat()

    while self.current.kind in {
        TokenType.gt, TokenType.gte, TokenType.lt,
        TokenType.lte, TokenType.in, TokenType.notIn
    }:
        let operator = self.advance().kind
        let right = self.parse_concat()
        left = node(token, self.peek(-1), NodeKind.binaryOp,
            binaryOperator = operator,
            binaryLeft = left,
            binaryRight = right
        )
    return left

proc parse_equality(self: Parser): Node =
    ## Parse equality operators (==, is).
    let token = self.current
    var left = self.parse_comparison()

    while self.current.kind in {
        TokenType.eq, TokenType.neq, TokenType.approx,
        TokenType.is, TokenType.isNot
    }:
        let operator = self.advance().kind
        let right = self.parse_comparison()
        left = node(token, self.peek(-1), NodeKind.binaryOp,
            binaryOperator = operator,
            binaryLeft = left,
            binaryRight = right
        )
    return left

proc parse_and(self: Parser): Node =
    ## Parse the and operator (&&).
    let token = self.current
    var left = self.parse_equality()

    while self.current.kind == TokenType.and:
        discard self.advance()
        let right = self.parse_equality()
        left = node(token, self.peek(-1), NodeKind.binaryOp,
            binaryOperator = TokenType.and,
            binaryLeft = left,
            binaryRight = right
        )
    return left

proc parse_or(self: Parser): Node =
    ## Parse the or operator (||).
    let token = self.current
    var left = self.parse_and()

    while self.current.kind == TokenType.or:
        discard self.advance()
        let right = self.parse_and()
        left = node(token, self.peek(-1), NodeKind.binaryOp,
            binaryOperator = TokenType.or,
            binaryLeft = left,
            binaryRight = right
        )
    return left

proc parse_ternary(self: Parser): Node =
    ## Parse the ternary if operator (condition ? true : false)
    let token = self.current
    var condition = self.parse_or()

    if self.current.kind == TokenType.question:
        discard self.advance()
        let trueBranch = self.parse_expression()
        discard self.expect(TokenType.colon)
        let falseBranch = self.parse_ternary()
        condition = node(token, self.peek(-1), NodeKind.ternaryIf,
            ternaryCondition = condition,
            ternaryTrue = trueBranch,
            ternaryFalse = falseBranch
        )
    return condition

proc parse_pipeline(self: Parser): Node =
    ## Parse the pipeline operator (~>)
    let token = self.current
    var left = self.parse_ternary()

    while self.current.kind == TokenType.pipeline:
        discard self.advance()
        let right = self.parse_ternary()
        left = node(token, self.peek(-1), NodeKind.binaryOp,
            binaryOperator = TokenType.pipeline,
            binaryLeft = left,
            binaryRight = right
        )
    return left

proc parse_var_decl(self: Parser): Node =
    ## Parse a variable declaration.
    let token = self.advance()
    let name = self.parse_primary()
    var hint: Node = nil
    var value: Node = nil

    if name.kind notin {
        NodeKind.identifier,  # var x = 0;
        NodeKind.listLiteral, # var [a, b] = [1, 2]
        NodeKind.dictLiteral, # var {value: target} = {"name": "John"}
        NodeKind.setLiteral   # var {a, b} = {"a": 1, "b": 2}
    }:
        raise self.error(StarchSyntaxError, "invalid target for variable declaration")

    if self.current.kind == TokenType.colon:
        discard self.advance()
        hint = self.parse_type()

    if self.current.kind == TokenType.assign:
        discard self.advance()
        value = self.parse_expression()

    self.terminate()
    return node(token, self.peek(-1), NodeKind.varDeclaration,
        varName = name,
        varHint = hint,
        varValue = value,
        varMutable = token.kind == TokenType.var
    )

proc parse_derive(self: Parser): Node =
    ## Parse a derive statement.
    let token = self.expect(TokenType.derive)
    let ident = self.expect(TokenType.ident)
    let name = node(ident, ident, NodeKind.identifier, name = ident.value.strVal)
    var hint: Node = nil

    if self.current.kind == TokenType.colon:
        discard self.advance()
        hint = self.parse_type()

    discard self.expect(TokenType.assign)
    let value = self.parse_expression()
    self.terminate()

    return node(token, self.peek(-1), NodeKind.derivedVariable,
        derivedName = name,
        derivedHint = hint,
        derivedValue = value
    )

proc parse_if(self: Parser): Node =
    ## Parse an if-then block, including elif and else branches.
    let token = self.expect(TokenType.if)
    var branches: seq[tuple[condition: Node, body: seq[Node]]] = @[]

    branches.add((condition: self.parse_expression(), body: self.parse_block()))

    while self.current.kind == TokenType.elif:
        discard self.advance()
        branches.add((condition: self.parse_expression(), body: self.parse_block()))

    var else_block: seq[Node] = @[]
    if self.current.kind == TokenType.else:
        discard self.advance()
        else_block = self.parse_block()

    return node(token, self.peek(-1), NodeKind.ifStatement, ifBranches = branches, ifElseBody = else_block)

proc parse_while(self: Parser): Node =
    ## Parse a while loop.
    let token = self.expect(TokenType.while)
    let condition = self.parse_expression()
    let body = self.parse_block()
    return node(token, self.peek(-1), NodeKind.whileLoop, whileCondition = condition, whileBody = body)

proc parse_for(self: Parser): Node =
    ## Parse a for loop.
    let token = self.expect(TokenType.for)
    let ident = self.parse_primary()

    if ident.kind notin {
        NodeKind.identifier,  # for x in c {}
        NodeKind.listLiteral, # for [x, y] in c {}
        NodeKind.dictLiteral, # for {x: y} in c {}
        NodeKind.setLiteral   # var {x, y} in c {}
    }:
        raise self.error(StarchSyntaxError, "cannot assign to expression in for loop")

    discard self.expect(TokenType.in)
    let collection = self.parse_expression()
    let body = self.parse_block()
    return node(token, self.peek(-1), NodeKind.forLoop, forVariable = ident, forCollection = collection, forBody = body)

proc parse_watch(self: Parser): Node =
    ## Parse a watch statement.
    let token = self.expect(TokenType.watch)
    let ident = self.expect(TokenType.ident)
    let target = node(ident, ident, NodeKind.identifier, name = ident.value.strVal)
    let body = self.parse_block()
    return node(token, self.peek(-1), NodeKind.watchStatement, watchTarget = target, watchBody = body)

proc parse_function(self: Parser): Node =
    ## Parse a function declaration.
    let token = self.expect(TokenType.function)
    let ident = self.expect(TokenType.ident)
    let name = node(ident, ident, NodeKind.identifier, name = ident.value.strVal)
    discard self.expect(TokenType.lParen)
    let params = self.parse_params()
    discard self.expect(TokenType.rParen)

    var hint: Node = nil
    if self.current.kind == TokenType.arrow:
        discard self.advance()
        hint = self.parse_type()

    let body = self.parse_block()
    return node(token, self.peek(-1), NodeKind.functionDeclaration, funcName = name, funcParams = params, funcReturnKind = hint, funcBody = body)

proc parse_class(self: Parser): Node =
    ## Parse a class declaration.
    let token = self.expect(TokenType.class)
    let name_ident = self.expect(TokenType.ident)
    let name = node(name_ident, name_ident, NodeKind.identifier, name = name_ident.value.strVal)
    var parent: Node = nil

    if self.current.kind == TokenType.is:
        discard self.advance()
        let parent_ident = self.expect(TokenType.ident)
        parent = node(parent_ident, parent_ident, NodeKind.identifier, name = parent_ident.value.strVal)

    var fields, methods, overrides, watchers, derivatives: seq[Node] = @[]
    for statement in self.parse_block():
        case statement.kind:
            of NodeKind.varDeclaration:
                fields.add(statement)
            of NodeKind.functionDeclaration:
                methods.add(statement)
            of NodeKind.watchStatement:
                watchers.add(statement)
            of NodeKind.derivedVariable:
                derivatives.add(statement)
            else:
                raise self.error(StarchSyntaxError, "unexpected statement in class body", statement)

    return node(token, self.peek(-1), NodeKind.classDeclaration,
        className = name,
        classParent = parent,
        classFields = fields,
        classMethods = methods,
        classWatchers = watchers,
        classDerivatives = derivatives
    )

proc parse_using(self: Parser): Node =
    ## Parse a using (import) statement.
    ## using foo;               - import module foo
    ## using foo as bar;        - import module foo aliased as bar
    ## using foo, bar;          - import modules foo and bar
    ## using foo from bar;      - import name foo from module bar
    ## using foo, baz from bar; - import names foo and baz from module bar
    ## yeah it's weird so what??
    let token = self.advance()
    var names = @[self.expect(TokenType.ident).value.strVal]
    var alias = ""
    if self.current.kind == TokenType.as:
        discard self.advance()
        alias = self.expect(TokenType.ident).value.strVal

    while self.current.kind == TokenType.comma:
        discard self.advance()
        names.add(self.expect(TokenType.ident).value.strVal)

    if self.current.kind == TokenType.from:
        if alias != "":
            raise self.error(StarchSyntaxError, "cannot use 'as' alias with 'from' import")
        discard self.advance()
        let module = self.expect(TokenType.ident).value.strVal
        self.terminate()
        return node(token, self.peek(-1), NodeKind.importFrom, importModule = module, importNames = names)

    self.terminate()
    var modules: seq[tuple[module: string, alias: string]] = @[]
    for i, name in names:
        # Only the first name can have an alias (using foo as bar)
        modules.add((module: name, alias: if i == 0: alias else: ""))
    return node(token, self.peek(-1), NodeKind.using, usingModules = modules)

proc parse_match(self: Parser): Node =
    ## Parse a match case statement.
    let token = self.expect(TokenType.match)
    let expression = self.parse_expression()
    discard self.expect(TokenType.lBrace)

    var cases: seq[tuple[patterns: seq[Node], guard: Node, body: seq[Node]]] = @[]
    while self.current.kind == TokenType.case:
        let start = self.advance()
        var patterns = @[self.parse_expression()]
        while self.current.kind == TokenType.pipe:
            # double while loop is CRAZYYY
            discard self.advance()
            patterns.add(self.parse_expression())

        var guard: Node = nil
        if self.current.kind == TokenType.if:
            # guard condition
            discard self.advance()
            guard = self.parse_expression()

        let body = self.parse_block()
        cases.add((patterns: patterns, guard: guard, body: body))

    discard self.expect(TokenType.rBrace)
    return node(token, self.peek(-1), NodeKind.matchStatement, matchExpression = expression, matchCases = cases)

proc parse_try(self: Parser): Node =
    ## Parse a try-catch block.
    let token = self.expect(TokenType.try)
    let body = self.parse_block()
    var catches: seq[tuple[kind: Node, variable: Node, body: seq[Node]]] = @[]
    var finalBody: seq[Node] = @[]

    while self.current.kind == TokenType.catch:
        discard self.advance()
        case self.current.kind:
            of TokenType.lBrace:
                # catch {}
                let body = self.parse_block()
                catches.add((kind: nil, variable: nil, body: body))
            of TokenType.ident:
                # catch Exception {}
                # catch Exception as e {}
                let token = self.advance()
                let kind = node(token, token, NodeKind.identifier, name = token.value.strVal)

                var variable: Node = nil
                if self.current.kind == TokenType.as:
                    discard self.advance()
                    let ident = self.advance()
                    variable = node(ident, ident, NodeKind.identifier, name = ident.value.strVal)

                let body = self.parse_block()
                catches.add((kind: kind, variable: variable, body: body))
            else:
                raise self.error(StarchSyntaxError, "expected block for catch statement")

    if self.current.kind == TokenType.finally:
        discard self.advance()
        finalBody = self.parse_block()

    return node(token, self.peek(-1), NodeKind.tryStatement, tryBody = body, tryCatches = catches, tryFinallyBody = finalBody)

proc parse_expression_statement(self: Parser): Node =
    ## Parse an ExpressionStatement or Assignment node.
    let token = self.current
    # LHS
    let expression = self.parse_expression()

    if self.current.kind == TokenType.assign:
        if not (expression.kind in {
            NodeKind.identifier,   # bar = baz
            NodeKind.memberAccess, # foo.bar = baz
            NodeKind.listLiteral,  # [foo, bar] = baz
            NodeKind.dictLiteral,  # {foo: bar} = baz
            NodeKind.setLiteral    # {foo, bar} = baz
        }):
            raise self.error(StarchSyntaxError, "invalid assignment target")

        # Consume the = operator
        discard self.advance()
        # RHS
        let value = self.parse_expression()
        self.terminate()
        return node(token, self.peek(-1), NodeKind.assign,
            assignVariable = expression,
            assignOperator = TokenType.assign,
            assignValue = value
        )

    if self.current.kind in {
        TokenType.plusAssign,
        TokenType.minusAssign,
        TokenType.starAssign,
        TokenType.slashAssign
    }:
        if not (expression.kind in {NodeKind.identifier, NodeKind.memberAccess}):
            raise self.error(StarchSyntaxError, "invalid assignment target")

        let operator = case self.advance().kind:
            of TokenType.plusAssign: TokenType.plus
            of TokenType.minusAssign: TokenType.minus
            of TokenType.starAssign: TokenType.star
            of TokenType.slashAssign: TokenType.slash
            else: TokenType.eof # unreachable

        let value = self.parse_expression()
        self.terminate()
        # Gets desugared later
        return node(token, self.peek(-1), NodeKind.assign,
            assignVariable = expression,
            assignOperator = operator,
            assignValue = value
        )

    self.terminate()
    return node(token, self.peek(-1), NodeKind.expressionStatement, expression = expression)

proc parse_statement(self: Parser): Node =
    ## Parse a statement.
    case self.current.kind:
        of TokenType.var, TokenType.const:
            return self.parse_var_decl()
        of TokenType.derive:
            return self.parse_derive()
        of TokenType.if:
            return self.parse_if()
        of TokenType.while:
            return self.parse_while()
        of TokenType.for:
            return self.parse_for()
        of TokenType.watch:
            return self.parse_watch()
        of TokenType.function:
            return self.parse_function()
        of TokenType.class:
            # Well this ought to be fun...
            return self.parse_class()
        of TokenType.break:
            let token = self.advance()
            let statement = node(token, token, NodeKind.break)
            self.terminate()
            return statement
        of TokenType.continue:
            let token = self.advance()
            let statement = node(token, token, NodeKind.continue)
            self.terminate()
            return statement
        of TokenType.return:
            let token = self.advance()
            var expression: Node = nil
            if self.current.kind != TokenType.semicolon:
                expression = self.parse_expression()
            self.terminate()
            return node(token, self.peek(-1), NodeKind.return, returnValue = expression)
        of TokenType.throw:
            let token = self.advance()
            let expression = self.parse_expression()
            self.terminate()
            return node(token, token, NodeKind.throw, throwException = expression)
        of TokenType.using:
            return self.parse_using()
        of TokenType.match:
            return self.parse_match()
        of TokenType.try:
            return self.parse_try()
        else:
            return self.parse_expression_statement()

proc parse*(self: Parser): Program =
    ## Parse the program.
    while self.current.kind != TokenType.eof:
        self.program.statements.add(self.parse_statement())
    when defined(debug):
        echo "---"
    return self.program
