import strformat
import unittest2
import ../../src/errors
import ../../src/lexer
import ../../src/tokens
import ../../src/parser
import ../../src/nodes

proc sexpr(node: Node): string =
    if node.isNil():
        return "_"

    case node.kind:
        of NodeKind.parameter:
            let name = sexpr(node.paramName)
            let hint = sexpr(node.paramHint)
            let default = sexpr(node.paramDefault)
            return &"(parameter {name} {hint} {default})"

        of NodeKind.varDeclaration:
            let mutable = if node.varMutable: "mut" else: "const"
            let name = sexpr(node.varName)
            let hint = sexpr(node.varHint)
            let value = sexpr(node.varValue)
            return &"(var {mutable} {name} {hint} {value})"

        of NodeKind.derivedVariable:
            let name = sexpr(node.derivedName)
            let hint = sexpr(node.derivedHint)
            let value = sexpr(node.derivedValue)
            return &"(derived {name} {hint} {value})"

        of NodeKind.literal:
            if node.literalKind == LiteralKind.bool:
                return $node.boolVal
            else:
                return node.literalValue # until now i had not realised the sheer stupidity of the variety of my variable names...

        of NodeKind.listLiteral:
            return ""

        of NodeKind.identifier:
            return node.name
        else:
            return &"({$node.kind})"
