{.used.}

import std/os
import std/algorithm
import unittest2
import ../../src/lexer
import ../../src/parser
import ../../src/nodes

const cases = currentSourcePath().parentDir() / "cases"

suite "Parsing: Golden files":
    var files: seq[string]
    for f in walkFiles(cases / "*.starch"):
        files.add(f)
    files.sort() # deterministicisation it

    for path in files:
        let name = path.splitFile().name
        test name:
            let source = readFile(path)
            let expectedPath = path.changeFileExt("expected") # ok but genuinely WHY is this a method

            let lexer = newLexer(source, path)
            let parser = newParser(lexer.lex(), path, source, lexer.lines)
            let ast = parser.parse().tree(true, parser.tokens)

            check fileExists(expectedPath)
            check ast == readFile(expectedPath)
