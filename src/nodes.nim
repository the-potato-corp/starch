import std/macros
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

    TreeItem = object
        ## A printable tree node: a label plus children. Knows nothing about the AST.
        label: string
        kids: seq[TreeItem]

    TreeCtx = object
        ## Options threaded through the conversion.
        showSpans: bool

# generic tree printing

proc render(item: TreeItem, prefix: string, isLast: bool, output: var string) =
    ## The ONLY place connectors and indentation are drawn.
    output &= prefix & (if isLast: "└── " else: "├── ") & item.label & "\n"

    let childPrefix = prefix & (if isLast: "    " else: "│   ")
    for i, kid in item.kids:
        render(kid, childPrefix, i == item.kids.high, output)

# ast -> tree

proc toTree(node: Node, ctx: TreeCtx, role = ""): TreeItem

proc spanText(node: Node): string =
    ## Inclusive byte span, e.g. `[4..9]`. Zero-length nodes show as `[4..4]`.
    "[" & $node.pos & ".." & $(node.pos + max(node.length, 1) - 1) & "]"

proc nameOf(node: Node): string =
    ## Inline name for declarations (" foo"), or "" when absent / not an identifier.
    if node != nil and node.kind == NodeKind.identifier: " " & node.name else: ""

proc one(ctx: TreeCtx, node: Node, role = ""): seq[TreeItem] =
    if node != nil: @[toTree(node, ctx, role)] else: @[]

proc many(ctx: TreeCtx, nodes: seq[Node], role = ""): seq[TreeItem] =
    for n in nodes: result.add toTree(n, ctx, role)

proc group(ctx: TreeCtx, label: string, nodes: seq[Node]): seq[TreeItem] =
    ## A labelled container ("body", "else", ...). Omitted when empty.
    if nodes.len > 0:
        @[TreeItem(label: label, kids: many(ctx, nodes))]
    else:
        @[]

proc branch(label: string, kids: seq[TreeItem]): seq[TreeItem] =
    @[TreeItem(label: label, kids: kids)]

proc toTree(node: Node, ctx: TreeCtx, role = ""): TreeItem =
    if node == nil:
        return TreeItem(label: (if role != "": role & ": " else: "") & "<nil>")

    var text: string
    var kids: seq[TreeItem]

    case node.kind
    of NodeKind.parameter:
        text = "parameter" & nameOf(node.paramName)
        kids = ctx.one(node.paramHint, "hint") & ctx.one(node.paramDefault, "default")

    of NodeKind.varDeclaration:
        text = "var" & (if node.varMutable: " (mut)" else: "")
        kids = ctx.one(node.varName, "name") & ctx.one(node.varHint, "hint") &
                ctx.one(node.varValue, "value")

    of NodeKind.derivedVariable:
        text = "derived" & nameOf(node.derivedName)
        kids = ctx.one(node.derivedHint, "hint") & ctx.one(node.derivedValue, "value")

    of NodeKind.literal:
        case node.literalKind
        of LiteralKind.bool:
            text = "literal (bool): " & $node.boolVal
        of LiteralKind.string:
            text = "literal (string): " & escape(node.literalValue)
        else:
            text = "literal (" & $node.literalKind & "): " & node.literalValue

    of NodeKind.listLiteral:
        text = "list"
        kids = ctx.many(node.listElements)

    of NodeKind.dictLiteral:
        text = "dict"
        for pair in node.dictPairs:
            kids &= branch("pair", ctx.one(pair.key, "key") & ctx.one(pair.value, "value"))

    of NodeKind.setLiteral:
        text = "set"
        kids = ctx.many(node.setItems)

    of NodeKind.tupleLiteral:
        text = "tuple"
        kids = ctx.many(node.tupleItems)

    of NodeKind.identifier:
        text = "identifier " & node.name

    of NodeKind.functionCall:
        text = "call"
        kids = ctx.one(node.callCallee, "callee") & ctx.many(node.callArgs, "arg")

    of NodeKind.memberAccess:
        text = "access"
        kids = ctx.one(node.accessObj, "object") & ctx.one(node.accessMember, "member")

    of NodeKind.expressionStatement:
        text = "exprStmt"
        kids = ctx.one(node.expression)

    of NodeKind.unaryOp:
        text = "unary " & (if node.unaryPrefix: "prefix" else: "postfix") &
                ": " & $node.unaryOperator
        kids = ctx.one(node.unaryOperand)

    of NodeKind.binaryOp:
        text = "binary: " & $node.binaryOperator
        kids = ctx.one(node.binaryLeft, "left") & ctx.one(node.binaryRight, "right")

    of NodeKind.lambda:
        text = "lambda"
        kids = ctx.many(node.lambdaParams, "param") & ctx.one(node.lambdaHint, "returns") &
                ctx.group("body", node.lambdaBody)

    of NodeKind.return:
        text = "return"
        kids = ctx.one(node.returnValue)

    of NodeKind.throw:
        text = "throw"
        kids = ctx.one(node.throwException)

    of NodeKind.using:
        text = "using"
        for m in node.usingModules:
            kids &= TreeItem(label: m.module & (if m.alias != "": " as " & m.alias else: ""))

    of NodeKind.importFrom:
        text = "import from: " & node.importModule
        for name in node.importNames:
            kids &= TreeItem(label: name)

    of NodeKind.ifStatement:
        text = "if"
        for i, b in node.ifBranches:
            kids &= branch(if i == 0: "if" else: "elif",
                ctx.one(b.condition, "condition") & ctx.group("body", b.body))
        kids &= ctx.group("else", node.ifElseBody)

    of NodeKind.whileLoop:
        text = "while"
        kids = ctx.one(node.whileCondition, "condition") & ctx.group("body", node.whileBody)

    of NodeKind.forLoop:
        text = "for"
        kids = ctx.one(node.forVariable, "variable") & ctx.one(node.forCollection, "in") &
                ctx.group("body", node.forBody)

    of NodeKind.watchStatement:
        text = "watch"
        kids = ctx.one(node.watchTarget, "target") & ctx.group("body", node.watchBody)

    of NodeKind.assign:
        text = "assign: " & $node.assignOperator
        kids = ctx.one(node.assignVariable, "target") & ctx.one(node.assignValue, "value")

    of NodeKind.functionDeclaration:
        text = "func" & nameOf(node.funcName)
        kids = ctx.many(node.funcParams, "param") & ctx.one(node.funcReturnKind, "returns") &
                ctx.group("body", node.funcBody)

    of NodeKind.matchStatement:
        text = "match"
        kids = ctx.one(node.matchExpression, "subject")
        for c in node.matchCases:
            kids &= branch("case",
                ctx.many(c.patterns, "pattern") & ctx.one(c.guard, "guard") &
                ctx.group("body", c.body))

    of NodeKind.tryStatement:
        text = "try"
        kids = ctx.group("body", node.tryBody)
        for c in node.tryCatches:
            kids &= branch("catch",
                ctx.one(c.kind, "type") & ctx.one(c.variable, "as") &
                ctx.group("body", c.body))
        kids &= ctx.group("finally", node.tryFinallyBody)

    of NodeKind.classDeclaration:
        text = "class" & nameOf(node.className)
        kids = ctx.one(node.classParent, "parent") &
                ctx.group("fields", node.classFields) &
                ctx.group("methods", node.classMethods) &
                ctx.group("watchers", node.classWatchers) &
                ctx.group("derived", node.classDerivatives)

    of NodeKind.indexAccess:
        text = "index"
        kids = ctx.one(node.indexObj, "object") & ctx.one(node.indexMember, "index")

    of NodeKind.slice:
        text = "slice"
        kids = ctx.one(node.sliceObj, "object")

        let laterThanStart = node.sliceStop != nil or node.sliceStep != nil
        if node.sliceStart != nil: kids &= ctx.one(node.sliceStart, "start")
        elif laterThanStart: kids &= TreeItem(label: "start: <empty>")

        if node.sliceStop != nil: kids &= ctx.one(node.sliceStop, "stop")
        elif node.sliceStep != nil: kids &= TreeItem(label: "stop: <empty>")

        kids &= ctx.one(node.sliceStep, "step")

    of NodeKind.ternaryIf:
        text = "ternary"
        kids = ctx.one(node.ternaryCondition, "condition") &
                ctx.one(node.ternaryTrue, "then") & ctx.one(node.ternaryFalse, "else")

    of NodeKind.comprehension:
        text = "comprehension"
        kids = ctx.one(node.comprehensionExpr, "expr") &
                ctx.many(node.comprehensionVars, "variable") &
                ctx.one(node.comprehensionCollection, "in") &
                ctx.one(node.comprehensionCondition, "if")

    of NodeKind.declarativeObject:
        text = "object"
        for f in node.objFields:
            kids &= branch("field", ctx.one(f.name, "name") & ctx.one(f.value, "value"))
        kids &= ctx.many(node.objChildren, "child")

    of NodeKind.typeOptional:
        text = "optional"
        kids = ctx.one(node.optionalKind)

    of NodeKind.typeUnion:
        text = "union"
        kids = ctx.many(node.unionKinds)

    of NodeKind.genericType:
        text = "generic"
        kids = ctx.one(node.genericKind, "base") & ctx.many(node.typeArgs, "arg")

    of NodeKind.template:
        text = "template"
        kids = ctx.many(node.parts, "part")

    of NodeKind.break:    text = "break"
    of NodeKind.continue: text = "continue"
    of NodeKind.null:     text = "null"

    var label = text
    if role != "": label = role & ": " & label
    if ctx.showSpans: label &= " " & spanText(node)

    TreeItem(label: label, kids: kids)

proc treeRepr(node: Node, prefix: string, isLast: bool, showSpans = false): string =
    ## Represent the AST in a clean ASCII-style string.
    # this function is black magic don't try to understand it

    if node == nil: return ""

    render(toTree(node, TreeCtx(showSpans: showSpans)), prefix, isLast, result)

proc `$`*(node: Node): string =
    treeRepr(node, "", true)

proc `$`*(program: Program): string =
    result = "program\n"
    for i, node in program.statements:
        result &= treeRepr(node, "", i == program.statements.high)

proc tree*(program: Program, showSpans = false): string =
    result = "program\n"
    for i, node in program.statements:
        result &= treeRepr(node, "", i == program.statements.high, showSpans)

macro node*(startToken, endToken, nodeKind: untyped, args: varargs[untyped]): untyped =
    ## Constructs a Node, deriving positional metadata from two tokens.
    ## `startToken` is the first token of the node; `endToken` is the last consumed token.
    ## The span is (endToken.pos + endToken.length) - startToken.pos, which correctly
    ## yields startToken.length when both arguments are the same token.
    let objConstr = newNimNode(nnkObjConstr)
    objConstr.add(ident("Node"))

    objConstr.add(newTree(nnkExprColonExpr, ident("kind"), nodeKind))
    objConstr.add(newTree(nnkExprColonExpr, ident("pos"), newDotExpr(startToken, ident("pos"))))

    # (endToken.pos + endToken.length) - startToken.pos
    # = byte span from the first character of startToken to the last character of endToken.
    # When startToken IS endToken this reduces to startToken.length (never zero).
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
