import std/macros
import std/sequtils
import std/strutils
import lexer
import tokens

type
    NodeKind* {.pure.} = enum
        parameter, varDeclaration, derivedVariable, literal,
        listLiteral, dictLiteral, setLiteral, identifier,
        functionCall, memberAccess, expressionStatement, unaryOp,
        binaryOp, lambda, `break`, `continue`, `return`, throw,
        `using`, importFrom, ifStatement, whileLoop, forLoop,
        watchStatement, assign, functionDeclaration, matchStatement,
        tryStatement, classDeclaration, indexAccess, ternaryIf,
        null, comprehension, declarativeObject, typeOptional,
        typeUnion, genericType, tupleLiteral, slice, `template`

    LiteralKind* {.pure.} = enum
        int, float, string, bool

    Node* = ref object
        ## An AST node.
        pos*, length*: int

        case kind*: NodeKind
        of NodeKind.parameter:
            paramName*: Node
            paramHint*: Node
            paramDefault*: Node

        of NodeKind.varDeclaration:
            varName*: Node
            varHint*: Node
            varValue*: Node
            varMutable*: bool

        of NodeKind.derivedVariable:
            derivedName*: Node
            derivedHint*: Node
            derivedValue*: Node

        of NodeKind.literal:
            case literalKind*: LiteralKind:
                of LiteralKind.bool: boolVal*: bool
                else: literalValue*: string

        of NodeKind.listLiteral:
            listElements*: seq[Node]

        of NodeKind.dictLiteral:
            dictPairs*: seq[tuple[key: Node, value: Node]]

        of NodeKind.identifier:
            name*: string

        of NodeKind.functionCall:
            callCallee*: Node
            callArgs*: seq[Node]

        of NodeKind.memberAccess:
            accessObj*: Node
            accessMember*: Node

        of NodeKind.expressionStatement:
            expression*: Node

        of NodeKind.unaryOp:
            unaryOperator*: TokenType
            unaryOperand*: Node
            unaryPrefix*: bool

        of NodeKind.binaryOp:
            binaryOperator*: TokenType
            binaryLeft*: Node
            binaryRight*: Node

        of NodeKind.lambda:
            lambdaParams*: seq[Node]
            lambdaBody*: seq[Node]
            lambdaHint*: Node

        of NodeKind.return:
            returnValue*: Node

        of NodeKind.throw:
            throwException*: Node

        of NodeKind.using:
            usingModules*: seq[tuple[module: string, alias: string]]

        of NodeKind.importFrom:
            importModule*: string
            importNames*: seq[string]

        of NodeKind.ifStatement:
            ifBranches*: seq[tuple[condition: Node, body: seq[Node]]]
            ifElseBody*: seq[Node]

        of NodeKind.whileLoop:
            whileCondition*: Node
            whileBody*: seq[Node]

        of NodeKind.forLoop:
            forVariable*: Node
            forCollection*: Node
            forBody*: seq[Node]

        of NodeKind.watchStatement:
            watchTarget*: Node
            watchBody*: seq[Node]

        of NodeKind.assign:
            assignVariable*: Node
            assignOperator*: TokenType # =, +=, -=, etc
            assignValue*: Node

        of NodeKind.functionDeclaration:
            funcName*: Node
            funcParams*: seq[Node]
            funcReturnKind*: Node
            funcBody*: seq[Node]

        of NodeKind.matchStatement:
            matchExpression*: Node
            matchCases*: seq[tuple[patterns: seq[Node], guard: Node, body: seq[Node]]]

        of NodeKind.tryStatement:
            tryBody*: seq[Node]
            tryCatches*: seq[tuple[kind: Node, variable: Node, body: seq[Node]]]
            tryFinallyBody*: seq[Node]

        of NodeKind.classDeclaration:
            className*: Node
            classParent*: Node
            classFields*: seq[Node]
            classMethods*: seq[Node]
            classWatchers*: seq[Node]
            classDerivatives*: seq[Node]

        of NodeKind.indexAccess:
            indexObj*: Node
            indexMember*: Node

        of NodeKind.slice:
            sliceObj*: Node
            sliceStart*: Node
            sliceStop*: Node
            sliceStep*: Node

        of NodeKind.ternaryIf:
            ternaryCondition*: Node
            ternaryTrue*: Node
            ternaryFalse*: Node

        of NodeKind.comprehension:
            comprehensionExpr*: Node
            comprehensionVars*: seq[Node]
            comprehensionCollection*: Node
            comprehensionCondition*: Node

        of NodeKind.declarativeObject:
            # Unimplemented.
            objFields*: seq[tuple[name: Node, value: Node]]
            objChildren*: seq[Node]

        of NodeKind.typeOptional:
            optionalKind*: Node

        of NodeKind.typeUnion:
            unionKinds*: seq[Node]

        of NodeKind.genericType:
            genericKind*: Node
            typeArgs*: seq[Node]

        of NodeKind.setLiteral:
            setItems*: seq[Node]

        of NodeKind.tupleLiteral:
            tupleItems*: seq[Node]

        of NodeKind.template:
            parts*: seq[Node]

        of NodeKind.break, NodeKind.continue, NodeKind.null:
            discard

    Program* = ref object
        ## A collection of statements.
        source*: string
        lineIndex*: LineIndex
        statements*: seq[Node]
        comments*: seq[Token] # dumping ground for comments to use later

    Entry = object
        ## A tree entry, for serialisation only
        label: string
        isNode: bool
        node: Node
        value: string

# ast -> tree
proc firstTokenAt(tokens: seq[Token], pos: int): int =
    ## Binary search to find the index of the first token starting at or after pos
    var low = 0
    var high = tokens.len
    while low < high:
        let mid = (low + high) div 2
        if tokens[mid].pos < pos: low = mid + 1
        else: high = mid
    return low

proc spanText(node: Node, tokens: seq[Token]): string =
    ## Inclusive span, in the format [1..3].
    let first = firstTokenAt(tokens, node.pos)
    let last = max(first, firstTokenAt(tokens, node.pos + max(node.length, 1)) - 1)
    "[" & $first & ".." & $last & "]"

proc leaf(label, value: string): Entry =
    Entry(label: label, value: value.multiReplace(("\n", "\\n"), ("\t", "\\t"), ("\r", "\\r")))

proc child(label: string, n: Node): Entry =
    Entry(label: label, isNode: true, node: n)

proc collect(node: Node): seq[Entry] =
    for fieldName, fieldValue in node[].fieldPairs:
        when fieldName notin ["kind", "pos", "length"]:
            when fieldValue is Node:
                result.add child(fieldName, fieldValue)

            elif fieldValue is seq[Node]:
                for i, n in fieldValue:
                    result.add child(fieldName & "[" & $i & "]", n)

            elif fieldValue is seq[tuple[key: Node, value: Node]]:
                for i, p in fieldValue:
                    let base = fieldName & "[" & $i & "]"
                    result.add child(base & ".key", p.key)
                    result.add child(base & ".value", p.value)

            elif fieldValue is seq[tuple[name: Node, value: Node]]:
                for i, p in fieldValue:
                    let base = fieldName & "[" & $i & "]"
                    result.add child(base & ".name", p.name)
                    result.add child(base & ".value", p.value)

            elif fieldValue is seq[tuple[module: string, alias: string]]:
                for i, m in fieldValue:
                    let alias = if m.alias == "": "" else: " as " & m.alias
                    result.add leaf(fieldName & "[" & $i & "]", m.module & alias)

            elif fieldValue is seq[tuple[condition: Node, body: seq[Node]]]:
                for i, b in fieldValue:
                    let base = fieldName & "[" & $i & "]"
                    result.add child(base & ".condition", b.condition)
                    for j, n in b.body:
                        result.add child(base & ".body[" & $j & "]", n)

            elif fieldValue is seq[tuple[patterns: seq[Node], guard: Node, body: seq[Node]]]:
                for i, c in fieldValue:
                    let base = fieldName & "[" & $i & "]"
                    for j, n in c.patterns:
                        result.add child(base & ".patterns[" & $j & "]", n)
                    result.add child(base & ".guard", c.guard)
                    for j, n in c.body:
                        result.add child(base & ".body[" & $j & "]", n)

            elif fieldValue is seq[tuple[kind: Node, variable: Node, body: seq[Node]]]:
                for i, c in fieldValue:
                    let base = fieldName & "[" & $i & "]"
                    result.add child(base & ".kind", c.kind)
                    result.add child(base & ".variable", c.variable)
                    for j, n in c.body:
                        result.add child(base & ".body[" & $j & "]", n)

            elif fieldValue is int | float | string | bool | enum:
                result.add leaf(fieldName, $fieldValue)

            elif fieldValue is seq[string]:
                result.add leaf(fieldName, $fieldValue)

proc toTree(node: Node, prefix = "", isLast = true, label = "root", showSpans = false, tokens: seq[Token] = @[]): string =
    let connector = if isLast: "└── " else: "├── "
    if node == nil:
        return prefix & connector & label & ": nil\n"

    var header = prefix & connector & label
    if label != $node.kind:
        header &= " (" & $node.kind & ")"
    if showSpans:
        header &= " " & spanText(node, tokens)

    let entries = collect(node).filterIt(not (it.isNode and it.node == nil))

    if entries.allIt(not it.isNode):
        if entries.len == 0:
            return header & "\n"
        return header & " " & entries.mapIt(it.label & ": " & it.value).join(", ") & "\n"

    result = header & "\n"
    let childPrefix = prefix & (if isLast: "    " else: "│   ")
    for i, e in entries:
        let last = i == entries.high
        if e.isNode:
            result &= toTree(e.node, childPrefix, last, e.label, showSpans, tokens)
        else:
            let c = if last: "└── " else: "├── "
            result &= childPrefix & c & e.label & ": " & e.value & "\n"

# entry points
proc treeRepr*(node: Node, prefix: string, isLast: bool, showSpans = false, tokens: seq[Token] = @[]): string =
    ## Represent an AST node in a clean ASCII-style string.

    if node == nil: return ""
    return toTree(node, prefix, isLast, $node.kind, showSpans, tokens)

proc `$`*(node: Node): string =
    treeRepr(node, "", true)

proc `$`*(program: Program): string =
    result = "program\n"
    for i, node in program.statements:
        result &= treeRepr(node, "", i == program.statements.high)

proc tree*(program: Program, showSpans = false, tokens: seq[Token] = @[]): string =
    ## Represent the AST in a clean ASCII-style string.
    result = "program\n"
    for i, node in program.statements:
        result &= treeRepr(node, "", i == program.statements.high, showSpans, tokens)

macro node*(startToken, endToken, nodeKind: untyped, args: varargs[untyped]): untyped =
    ## Constructs a Node, deriving positional metadata from two tokens.
    ## startToken is the first token of the node; endToken is the last consumed token.
    ## The span is (endToken.pos + endToken.length) - startToken.pos
    let objConstr = newNimNode(nnkObjConstr)
    objConstr.add(ident("Node"))

    objConstr.add(newTree(nnkExprColonExpr, ident("kind"), nodeKind))
    objConstr.add(newTree(nnkExprColonExpr, ident("pos"), newDotExpr(startToken, ident("pos"))))

    # (endToken.pos + endToken.length) - startToken.pos
    # = byte span from the first character of startToken to the last character of endToken.
    let endPos = newTree(nnkInfix, ident("+"),
        newDotExpr(endToken, ident("pos")),
        newDotExpr(endToken, ident("length"))
    )
    let lengthExpr = newTree(nnkInfix, ident("-"), endPos,
        newDotExpr(startToken, ident("pos"))
    )
    objConstr.add(newTree(nnkExprColonExpr, ident("length"), lengthExpr))

    for arg in args:
        if arg.kind == nnkExprColonExpr or arg.kind == nnkExprEqExpr:
            let fieldName = arg[0]
            let value = arg[1]
            objConstr.add(newTree(nnkExprColonExpr, fieldName, value))
        else:
            discard

    result = objConstr
