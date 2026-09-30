import std/macros
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

    let connector = if isLast: "└── " else: "├── "
    let childPrefix = prefix & (if isLast: "    " else: "│   ")
    let header = prefix & connector

    proc child(n: Node, last: bool): string =
        treeRepr(n, childPrefix, last)

    proc children(nodes: seq[Node]): string =
        for i, n in nodes:
            result &= treeRepr(
                n,
                childPrefix,
                i == nodes.high
            )

    proc namedChild(label: string, n: Node, last: bool): string =
        if n == nil:
            return ""

        let conn = if last: "└── " else: "├── "
        result = childPrefix & conn & label & "\n"

        let p = childPrefix & (if last: "    " else: "│   ")
        result &= treeRepr(n, p, true)

    proc leaf(label: string, last: bool): string =
        childPrefix &
            (if last: "└── " else: "├── ") &
            label & "\n"

    case node.kind:
        of NodeKind.parameter:
            result = header & "parameter"
            if node.paramName != nil:
                result &= ": " & node.paramName.name
            result &= "\n"

            let hasHint = node.paramHint != nil
            let hasDefault = node.paramDefault != nil

            if hasHint:
                result &= treeRepr(
                    node.paramHint,
                    childPrefix,
                    not hasDefault
                )

            if hasDefault:
                result &= treeRepr(
                    node.paramDefault,
                    childPrefix,
                    true
                )

        of NodeKind.varDeclaration:
            result = header & "var"
            if node.varMutable:
                result &= " (mut)"
            result &= "\n"

            let hasName = node.varName != nil
            let hasHint = node.varHint != nil
            let hasValue = node.varValue != nil

            var remaining = 0
            if hasName: remaining.inc
            if hasHint: remaining.inc
            if hasValue: remaining.inc

            var index = 0

            if hasName:
                index.inc
                result &= treeRepr(
                    node.varName,
                    childPrefix,
                    index == remaining
                )

            if hasHint:
                index.inc
                result &= treeRepr(
                    node.varHint,
                    childPrefix,
                    index == remaining
                )

            if hasValue:
                result &= treeRepr(
                    node.varValue,
                    childPrefix,
                    true
                )

        of NodeKind.derivedVariable:
            result = header & "derived"
            if node.derivedName != nil:
                result &= ": " & node.derivedName.name
            result &= "\n"

            let hasHint = node.derivedHint != nil
            let hasValue = node.derivedValue != nil

            if hasHint:
                result &= treeRepr(
                    node.derivedHint,
                    childPrefix,
                    not hasValue
                )

            if hasValue:
                result &= treeRepr(
                    node.derivedValue,
                    childPrefix,
                    true
                )

        of NodeKind.literal:
            result = header & "literal: "

            case node.literalKind:
            of LiteralKind.bool:
                result &= $node.boolVal
            else:
                result &= node.literalValue

            result &= "\n"

        of NodeKind.listLiteral:
            result = header & "list\n"
            result &= children(node.listElements)

        of NodeKind.dictLiteral:
            result = header & "dict\n"

            for i, pair in node.dictPairs:
                let pairLast = i == node.dictPairs.high
                let pairConn = if pairLast: "└── " else: "├── "
                let pairPrefix = childPrefix &
                    pairConn

                result &= pairPrefix & "pair\n"

                let pairChildPrefix = childPrefix &
                    (if pairLast: "    " else: "│   ")

                result &= treeRepr(pair.key, pairChildPrefix, false)
                result &= treeRepr(pair.value, pairChildPrefix, true)

        of NodeKind.identifier:
            result = header & "identifier: " & node.name & "\n"

        of NodeKind.functionCall:
            result = header & "call\n"

            let hasArgs = node.callArgs.len > 0

            if node.callCallee != nil:
                result &= treeRepr(
                    node.callCallee,
                    childPrefix,
                    not hasArgs
                )

            result &= children(node.callArgs)

        of NodeKind.memberAccess:
            result = header & "access\n"
            result &= treeRepr(node.accessObj, childPrefix, false)
            result &= treeRepr(node.accessMember, childPrefix, true)

        of NodeKind.expressionStatement:
            result = header & "exprStmt\n"
            result &= treeRepr(node.expression, childPrefix, true)

        of NodeKind.unaryOp:
            result = header &
                "unary " &
                (if node.unaryPrefix: "prefix" else: "postfix") &
                ": " &
                $node.unaryOperator &
                "\n"

            result &= treeRepr(
                node.unaryOperand,
                childPrefix,
                true
            )

        of NodeKind.binaryOp:
            result = header &
                "binary: " &
                $node.binaryOperator &
                "\n"

            result &= treeRepr(
                node.binaryLeft,
                childPrefix,
                false
            )

            result &= treeRepr(
                node.binaryRight,
                childPrefix,
                true
            )

        of NodeKind.lambda:
            result = header & "lambda\n"

            let paramCount = node.lambdaParams.len
            let hasHint = node.lambdaHint != nil
            let bodyCount = node.lambdaBody.len

            var total = paramCount + (if hasHint: 1 else: 0) + bodyCount
            var index = 0

            for param in node.lambdaParams:
                index.inc
                result &= treeRepr(
                    param,
                    childPrefix,
                    index == total
                )

            if hasHint:
                index.inc
                result &= treeRepr(
                    node.lambdaHint,
                    childPrefix,
                    index == total
                )

            for body in node.lambdaBody:
                index.inc
                result &= treeRepr(
                    body,
                    childPrefix,
                    index == total
                )

        of NodeKind.return:
            result = header & "return\n"

            if node.returnValue != nil:
                result &= treeRepr(
                    node.returnValue,
                    childPrefix,
                    true
                )

        of NodeKind.throw:
            result = header & "throw\n"
            result &= treeRepr(
                node.throwException,
                childPrefix,
                true
            )

        of NodeKind.using:
            result = header & "using\n"

            for i, module in node.usingModules:
                let last = i == node.usingModules.high

                result &= childPrefix &
                    (if last: "└── " else: "├── ") &
                    module.module

                if module.alias != "":
                    result &= " as " & module.alias

                result &= "\n"

        of NodeKind.importFrom:
            result = header &
                "import from: " &
                node.importModule &
                "\n"

            for i, name in node.importNames:
                result &= childPrefix &
                    (if i == node.importNames.high: "└── " else: "├── ") &
                    name &
                    "\n"

        of NodeKind.ifStatement:
            result = header & "if\n"

            let branchCount = node.ifBranches.len
            let hasElse = node.ifElseBody.len > 0
            let totalBranches = branchCount + (if hasElse: 1 else: 0)

            for i, branch in node.ifBranches:
                let branchLast = i == totalBranches - 1
                let branchConn = if branchLast: "└── " else: "├── "
                let branchPrefix = childPrefix &
                    branchConn

                result &= branchPrefix & "branch\n"

                let branchChildPrefix = childPrefix &
                    (if branchLast: "    " else: "│   ")

                result &= treeRepr(
                    branch.condition,
                    branchChildPrefix,
                    branch.body.len == 0
                )

                for j, stmt in branch.body:
                    result &= treeRepr(
                        stmt,
                        branchChildPrefix,
                        j == branch.body.high
                    )

            if hasElse:
                result &= childPrefix & "└── else\n"

                for i, stmt in node.ifElseBody:
                    result &= treeRepr(
                        stmt,
                        childPrefix & "    ",
                        i == node.ifElseBody.high
                    )

        of NodeKind.whileLoop:
            result = header & "while\n"

            let hasBody = node.whileBody.len > 0

            result &= treeRepr(
                node.whileCondition,
                childPrefix,
                not hasBody
            )

            result &= children(node.whileBody)

        of NodeKind.forLoop:
            result = header & "for\n"

            result &= treeRepr(
                node.forVariable,
                childPrefix,
                false
            )

            result &= treeRepr(
                node.forCollection,
                childPrefix,
                node.forBody.len == 0
            )

            result &= children(node.forBody)

        of NodeKind.watchStatement:
            result = header & "watch\n"

            result &= treeRepr(
                node.watchTarget,
                childPrefix,
                node.watchBody.len == 0
            )

            result &= children(node.watchBody)

        of NodeKind.assign:
            result = header &
                "assign: " &
                $node.assignOperator &
                "\n"

            result &= treeRepr(
                node.assignVariable,
                childPrefix,
                false
            )

            result &= treeRepr(
                node.assignValue,
                childPrefix,
                true
            )

        of NodeKind.functionDeclaration:
            result = header &
                "func: " &
                node.funcName.name &
                "\n"

            let hasReturn = node.funcReturnKind != nil
            let paramCount = node.funcParams.len
            let hasBody = node.funcBody.len > 0
            let total = paramCount +
                (if hasReturn: 1 else: 0) +
                node.funcBody.len

            var index = 0

            for param in node.funcParams:
                index.inc
                result &= treeRepr(
                    param,
                    childPrefix,
                    index == total
                )

            if hasReturn:
                index.inc
                result &= treeRepr(
                    node.funcReturnKind,
                    childPrefix,
                    index == total
                )

            for stmt in node.funcBody:
                index.inc
                result &= treeRepr(
                    stmt,
                    childPrefix,
                    index == total
                )

        of NodeKind.matchStatement:
            result = header & "match\n"

            let hasCases = node.matchCases.len > 0

            result &= treeRepr(
                node.matchExpression,
                childPrefix,
                not hasCases
            )

            for i, c in node.matchCases:
                let caseLast = i == node.matchCases.high
                let caseConn = if caseLast: "└── " else: "├── "
                let casePrefix = childPrefix & caseConn

                result &= casePrefix & "case\n"

                let caseChildPrefix = childPrefix &
                    (if caseLast: "    " else: "│   ")

                let hasGuard = c.guard != nil
                let hasBody = c.body.len > 0

                for j, pattern in c.patterns:
                    let patternLast =
                        j == c.patterns.high and
                        not hasGuard and
                        not hasBody

                    result &= treeRepr(
                        pattern,
                        caseChildPrefix,
                        patternLast
                    )

                if hasGuard:
                    result &= treeRepr(
                        c.guard,
                        caseChildPrefix,
                        not hasBody
                    )

                for j, stmt in c.body:
                    result &= treeRepr(
                        stmt,
                        caseChildPrefix,
                        j == c.body.high
                    )

        of NodeKind.tryStatement:
            result = header & "try\n"

            let hasCatches = node.tryCatches.len > 0
            let hasFinally = node.tryFinallyBody.len > 0

            # try body
            for i, stmt in node.tryBody:
                let isLast =
                    i == node.tryBody.high and
                    not hasCatches and
                    not hasFinally

                result &= treeRepr(
                    stmt,
                    childPrefix,
                    isLast
                )

            # catches
            for i, c in node.tryCatches:
                let catchLast =
                    i == node.tryCatches.high and
                    not hasFinally

                let catchConn =
                    if catchLast: "└── "
                    else: "├── "

                result &= childPrefix &
                    catchConn &
                    "catch"

                if c.variable != nil:
                    result &= ": " & c.variable.name

                result &= "\n"

                let catchPrefix =
                    childPrefix &
                    (if catchLast: "    " else: "│   ")

                let hasKind = c.kind != nil

                if hasKind:
                    result &= treeRepr(
                        c.kind,
                        catchPrefix,
                        c.body.len == 0
                    )

                for j, stmt in c.body:
                    result &= treeRepr(
                        stmt,
                        catchPrefix,
                        j == c.body.high
                    )

            # finally
            if hasFinally:
                result &= childPrefix & "└── finally\n"

                for i, stmt in node.tryFinallyBody:
                    result &= treeRepr(
                        stmt,
                        childPrefix & "    ",
                        i == node.tryFinallyBody.high
                    )

        of NodeKind.classDeclaration:
            result = header & "class"

            if node.className != nil:
                result &= ": " & node.className.name

            result &= "\n"

            let hasParent = node.classParent != nil

            if hasParent:
                let hasMore =
                    node.classFields.len > 0 or
                    node.classMethods.len > 0 or
                    node.classWatchers.len > 0 or
                    node.classDerivatives.len > 0

                result &= treeRepr(
                    node.classParent,
                    childPrefix,
                    not hasMore
                )

            let total =
                node.classFields.len +
                node.classMethods.len +
                node.classWatchers.len +
                node.classDerivatives.len

            var index = 0

            for field in node.classFields:
                index.inc
                result &= treeRepr(
                    field,
                    childPrefix,
                    index == total
                )

            for `method` in node.classMethods:
                index.inc
                result &= treeRepr(
                    `method`,
                    childPrefix,
                    index == total
                )

            for watcher in node.classWatchers:
                index.inc
                result &= treeRepr(
                    watcher,
                    childPrefix,
                    index == total
                )

            for derivative in node.classDerivatives:
                index.inc
                result &= treeRepr(
                    derivative,
                    childPrefix,
                    index == total
                )

        of NodeKind.indexAccess:
            result = header & "index\n"

            result &= treeRepr(
                node.indexObj,
                childPrefix,
                false
            )

            result &= treeRepr(
                node.indexMember,
                childPrefix,
                true
            )

        of NodeKind.slice:
            result = header & "slice\n"

            let hasStart = node.sliceStart != nil
            let hasStop = node.sliceStop != nil
            let hasStep = node.sliceStep != nil

            let showStart = hasStart or hasStop or hasStep   # real or <empty start>
            let showStop = hasStop or hasStep                # real or <empty stop>

            let total = 1 + ord(showStart) + ord(showStop) + ord(hasStep)
            var index = 0

            index.inc
            result &= treeRepr(node.sliceObj, childPrefix, index == total)

            if showStart:
                index.inc
                result &= (if hasStart: treeRepr(node.sliceStart, childPrefix, index == total)
                           else: leaf("<empty start>", index == total))

            if showStop:
                index.inc
                result &= (if hasStop: treeRepr(node.sliceStop, childPrefix, index == total)
                           else: leaf("<empty stop>", index == total))

            if hasStep:
                index.inc
                result &= treeRepr(node.sliceStep, childPrefix, true)

        of NodeKind.ternaryIf:
            result = header & "ternary\n"

            result &= treeRepr(
                node.ternaryCondition,
                childPrefix,
                false
            )

            result &= treeRepr(
                node.ternaryTrue,
                childPrefix,
                false
            )

            result &= treeRepr(
                node.ternaryFalse,
                childPrefix,
                true
            )

        of NodeKind.comprehension:
            result = header & "comprehension\n"

            result &= treeRepr(
                node.comprehensionExpr,
                childPrefix,
                false
            )

            for i, v in node.comprehensionVars:
                result &= treeRepr(
                    v,
                    childPrefix,
                    i == node.comprehensionVars.high and
                    node.comprehensionCondition == nil
                )

            let hasCondition = node.comprehensionCondition != nil

            result &= treeRepr(
                node.comprehensionCollection,
                childPrefix,
                not hasCondition
            )

            if hasCondition:
                result &= treeRepr(
                    node.comprehensionCondition,
                    childPrefix,
                    true
                )

        of NodeKind.declarativeObject:
            result = header & "object\n"

            let total =
                node.objFields.len +
                node.objChildren.len

            var index = 0

            for field in node.objFields:
                index.inc

                let fieldLast = index == total
                let fieldConn =
                    if fieldLast: "└── "
                    else: "├── "

                result &= childPrefix &
                    fieldConn &
                    "field\n"

                let fieldPrefix =
                    childPrefix &
                    (if fieldLast: "    " else: "│   ")

                result &= treeRepr(
                    field.name,
                    fieldPrefix,
                    false
                )

                result &= treeRepr(
                    field.value,
                    fieldPrefix,
                    true
                )

            for childNode in node.objChildren:
                index.inc

                result &= treeRepr(
                    childNode,
                    childPrefix,
                    index == total
                )

        of NodeKind.typeOptional:
            result = header & "optional\n"
            result &= treeRepr(
                node.optionalKind,
                childPrefix,
                true
            )

        of NodeKind.typeUnion:
            result = header & "union\n"
            result &= children(node.unionKinds)

        of NodeKind.genericType:
            result = header & "generic\n"

            result &= treeRepr(
                node.genericKind,
                childPrefix,
                node.typeArgs.len == 0
            )

            result &= children(node.typeArgs)

        of NodeKind.setLiteral:
            result = header & "set\n"
            result &= children(node.setItems)

        of NodeKind.tupleLiteral:
            result = header & "tuple\n"
            result &= children(node.tupleItems)

        of NodeKind.template:
            result = header & "template\n"
            result &= children(node.parts)

        of NodeKind.break:
            result = header & "break\n"

        of NodeKind.continue:
            result = header & "continue\n"

        of NodeKind.null:
            result = header & "null\n"

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
