import std/macros
import std/sequtils
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

proc treeRepr(node: Node, prefix: string, isLast: bool): string =
    ## Represent the AST in a clean ASCII-style string.
    # this function is black magic don't try to understand it
    if node == nil: return ""

    let
        connector = if isLast: "└── " else: "├── "
        childPrefix = if isLast: "    " else: "│   "

    proc branch(label: string, children: seq[string], p: string): string =
        result = p & connector & label & "\n"
        for i, child in children:
            result &= child

    proc leaf(label: string): string =
        prefix & connector & label & "\n"

    proc childNode(n: Node, p: string, last: bool): string =
        treeRepr(n, p, last)

    proc childNodes(nodes: seq[Node], p: string): string =
        for i, n in nodes:
            result &= treeRepr(n, p, i == nodes.high)

    proc childSeqStr(label: string, items: seq[string], p: string, last: bool): string =
        let conn = if last: "└── " else: "├── "
        let cp   = if last: "    " else: "│   "
        result = p & conn & label & "\n"
        for i, s in items:
            let lconn = if i == items.high: "└── " else: "├── "
            result &= p & cp & lconn & s & "\n"

    let p = prefix & childPrefix
    let header = prefix & connector

    case node.kind:
    of NodeKind.parameter:
        result = header & "parameter: " & node.paramName.name & "\n"
        if node.paramHint   != nil: result &= treeRepr(node.paramHint,    p, node.paramDefault == nil)
        if node.paramDefault != nil: result &= treeRepr(node.paramDefault, p, true)

    of NodeKind.varDeclaration:
        result = header & "var" & (if node.varMutable: " (mut)" else: "") & ":\n"
        result &= treeRepr(                         node.varName,  p, false)
        if node.varHint  != nil: result &= treeRepr(node.varHint,  p, node.varValue == nil)
        if node.varValue != nil: result &= treeRepr(node.varValue, p, true)

    of NodeKind.derivedVariable:
        result = header & "derived: " & node.derivedName.name & "\n"
        if node.derivedHint  != nil: result &= treeRepr(node.derivedHint,  p, node.derivedValue == nil)
        if node.derivedValue != nil: result &= treeRepr(node.derivedValue, p, true)

    of NodeKind.literal:
        result = header & "literal: " & (case node.literalKind
            of LiteralKind.bool:   $node.boolVal
            else:                  node.literalValue) & "\n"

    of NodeKind.listLiteral:
        result = header & "list\n" & childNodes(node.listElements, p)

    of NodeKind.dictLiteral:
        result = header & "dict\n"
        for i, pair in node.dictPairs:
            let last = i == node.dictPairs.high
            let pconn = if last: "└── " else: "├── "
            let pp    = if last: "    " else: "│   "
            result &= p & pconn & "pair\n"
            result &= treeRepr(pair.key,   p & pp, false)
            result &= treeRepr(pair.value, p & pp, true)

    of NodeKind.identifier:
        result = header & "identifier: " & node.name & "\n"

    of NodeKind.functionCall:
        result = header & "call\n"
        result &= treeRepr(node.callCallee, p, node.callArgs.len == 0)
        result &= childNodes(node.callArgs, p)

    of NodeKind.memberAccess:
        result = header & "access:\n"
        result &= treeRepr(node.accessObj,    p, false)
        result &= treeRepr(node.accessMember, p, true)

    of NodeKind.expressionStatement:
        result = header & "exprStmt\n"
        result &= treeRepr(node.expression, p, true)

    of NodeKind.unaryOp:
        result = header & "unary " & (if node.unaryPrefix: "prefix" else: "postfix") & " : " & $node.unaryOperator & "\n"
        result &= treeRepr(node.unaryOperand, p, true)

    of NodeKind.binaryOp:
        result = header & "binary: " & $node.binaryOperator & "\n"
        result &= treeRepr(node.binaryLeft,  p, false)
        result &= treeRepr(node.binaryRight, p, true)

    of NodeKind.lambda:
        result = header & "lambda\n"
        result &= childNodes(node.lambdaParams, p)
        if node.lambdaHint != nil: result &= treeRepr(node.lambdaHint, p, node.lambdaBody.len == 0)
        result &= childNodes(node.lambdaBody, p)

    of NodeKind.return:
        result = header & "return\n"
        if node.returnValue != nil: result &= treeRepr(node.returnValue, p, true)

    of NodeKind.throw:
        result = header & "throw\n"
        result &= treeRepr(node.throwException, p, true)

    of NodeKind.using:
        result = header & "using\n"
        let moduleStrs = node.usingModules.mapIt(
            if it.alias != "": it.module & " as " & it.alias
            else: it.module
        )
        result &= childSeqStr("modules", moduleStrs, p, true)

    of NodeKind.importFrom:
        result = header & "import from: " & node.importModule & "\n"
        result &= childSeqStr("names", node.importNames, p, true)

    of NodeKind.ifStatement:
        result = header & "if\n"
        for i, branch in node.ifBranches:
            let last = i == node.ifBranches.high and node.ifElseBody.len == 0
            let bconn = if last: "└── " else: "├── "
            let bp    = if last: "    " else: "│   "
            result &= p & bconn & "branch\n"
            result &= treeRepr(branch.condition, p & bp, false)
            result &= childNodes(branch.body,    p & bp)
        if node.ifElseBody.len > 0:
            result &= p & "└── else\n"
            result &= childNodes(node.ifElseBody, p & "    ")

    of NodeKind.whileLoop:
        result = header & "while\n"
        result &= treeRepr(node.whileCondition, p, false)
        result &= childNodes(node.whileBody, p)

    of NodeKind.forLoop:
        result = header & "for\n"
        result &= treeRepr(node.forVariable, p, false)
        result &= treeRepr(node.forCollection, p, false)
        result &= childNodes(node.forBody, p)

    of NodeKind.watchStatement:
        result = header & "watch" & "\n"
        result &= treeRepr(node.watchTarget, p, false)
        result &= childNodes(node.watchBody, p)

    of NodeKind.assign:
        result = header & "assign: " & $node.assignOperator & "\n"
        result &= treeRepr(node.assignVariable, p, false)
        result &= treeRepr(node.assignValue,    p, true)

    of NodeKind.functionDeclaration:
        result = header & "func: " & node.funcName.name & "\n"
        let hasReturn = node.funcReturnKind != nil
        let hasBody   = node.funcBody.len > 0
        for i, param in node.funcParams:
            result &= treeRepr(param, p, i == node.funcParams.high and not hasReturn and not hasBody)
        if hasReturn: result &= treeRepr(node.funcReturnKind, p, not hasBody)
        result &= childNodes(node.funcBody, p)

    of NodeKind.matchStatement:
        result = header & "match\n"
        result &= treeRepr(node.matchExpression, p, node.matchCases.len == 0)
        for i, c in node.matchCases:
            let last  = i == node.matchCases.high
            let cconn = if last: "└── " else: "├── "
            let cp2   = if last: "    " else: "│   "
            result &= p & cconn & "case\n"
            let hasGuard = c.guard != nil
            let hasBody  = c.body.len > 0
            for j, pattern in c.patterns:
                result &= treeRepr(pattern, p & cp2, j == c.patterns.high and not hasGuard and not hasBody)
            if hasGuard: result &= treeRepr(c.guard, p & cp2, not hasBody)
            result &= childNodes(c.body, p & cp2)

    of NodeKind.tryStatement:
        result = header & "try\n"
        let hasCatches = node.tryCatches.len > 0
        let hasFinally = node.tryFinallyBody.len > 0

        for i, stmt in node.tryBody:
            let isLastStmt = i == node.tryBody.high
            let isLastOverall = isLastStmt and not hasCatches and not hasFinally
            result &= treeRepr(stmt, p, isLastOverall)

        for i, c in node.tryCatches:
            let isLastCatch = i == node.tryCatches.high
            let isLastOverall = isLastCatch and not hasFinally

            let cconn = if isLastOverall: "└── " else: "├── "
            let cp = if isLastOverall: "    " else: "│   "

            result &= p & cconn & "catch"
            if c.variable != nil:
                result &= ": " & c.variable.name
            result &= "\n"

            let hasKind = c.kind != nil
            let hasBody = c.body.len > 0

            if hasKind:
                result &= treeRepr(c.kind, p & cp, not hasBody)

            for j, stmt in c.body:
                let isLast = j == c.body.high
                result &= treeRepr(stmt, p & cp, isLast)

        if hasFinally:
            result &= p & "└── finally\n"
            result &= childNodes(node.tryFinallyBody, p & "    ")

    of NodeKind.classDeclaration:
        result = header & "class: " & (if node.className != nil: node.className.name else: "?") & "\n"
        if node.classParent != nil: result &= treeRepr(node.classParent, p, node.classFields.len == 0 and node.classMethods.len == 0 and node.classWatchers.len == 0 and node.classDerivatives.len == 0)
        result &= childNodes(node.classFields,      p)
        result &= childNodes(node.classMethods,     p)
        result &= childNodes(node.classWatchers,    p)
        result &= childNodes(node.classDerivatives, p)

    of NodeKind.indexAccess:
        result = header & "index\n"
        result &= treeRepr(node.indexObj,    p, false)
        result &= treeRepr(node.indexMember, p, true)

    of NodeKind.slice:
        result = header & "slice\n"

        # sliceObj is always first, never last
        result &= treeRepr(node.sliceObj, p, false)

        # Determine which fields are non-nil so we know if there are more items after each
        let hasStop = node.sliceStop != nil
        let hasStep = node.sliceStep != nil

        if node.sliceStart != nil:
            result &= treeRepr(node.sliceStart, p, not hasStop and not hasStep)
        elif hasStop or hasStep:
            result &= p & "├── " & "<empty start>" & "\n"

        if node.sliceStop != nil:
            result &= treeRepr(node.sliceStop, p, not hasStep)
        elif hasStep:
            result &= p & "├── " & "<empty stop>" & "\n"

        if node.sliceStep != nil:
            result &= treeRepr(node.sliceStep, p, true)

    of NodeKind.ternaryIf:
        result = header & "ternary\n"
        result &= treeRepr(node.ternaryCondition, p, false)
        result &= treeRepr(node.ternaryTrue,      p, false)
        result &= treeRepr(node.ternaryFalse,     p, true)

    of NodeKind.comprehension:
        result = header & "comprehension\n"
        result &= treeRepr(node.comprehensionExpr,       p, false)
        result &= childNodes(node.comprehensionVars,     p)
        result &= treeRepr(node.comprehensionCollection, p, node.comprehensionCondition == nil)
        if node.comprehensionCondition != nil:
            result &= treeRepr(node.comprehensionCondition, p, true)

    of NodeKind.declarativeObject:
        result = header & "object\n"
        for i, field in node.objFields:
            let last  = i == node.objFields.high and node.objChildren.len == 0
            let fconn = if last: "└── " else: "├── "
            let fp    = if last: "    " else: "│   "
            result &= p & fconn & "field\n"
            result &= treeRepr(field.name,  p & fp, false)
            result &= treeRepr(field.value, p & fp, true)
        result &= childNodes(node.objChildren, p)

    of NodeKind.typeOptional:
        result = header & "optional\n"
        result &= treeRepr(node.optionalKind, p, true)

    of NodeKind.typeUnion:
        result = header & "union\n"
        result &= childNodes(node.unionKinds, p)

    of NodeKind.genericType:
        result = header & "generic\n"
        result &= treeRepr(node.genericKind, p, node.typeArgs.len == 0)
        result &= childNodes(node.typeArgs, p)

    of NodeKind.template:
        result = header & "template\n"
        result &= childNodes(node.parts, p)

    of NodeKind.setLiteral:
        result = header & "set\n" & childNodes(node.setItems, p)
    of NodeKind.tupleLiteral:
        result = header & "tuple\n" & childNodes(node.tupleItems, p)
    else: result = header & $node.kind & "\n"

proc `$`*(node: Node): string =
    treeRepr(node, "", true)

proc `$`*(program: Program): string =
    result = "program\n"
    for i, node in program.statements:
        result &= treeRepr(node, "", i == program.statements.high)

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
