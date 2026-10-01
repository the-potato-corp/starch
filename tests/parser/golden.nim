{.used.}

import std/os
import std/algorithm
import std/strutils
import std/strformat
import unittest2
import ../../src/lexer
import ../../src/parser
import ../../src/nodes

const cases = currentSourcePath().parentDir() / "cases"

proc firstDiff(expected, actual: string, context = 3): string =
    ## Describes the first differing line, with surrounding context.
    let e = expected.replace("\r\n", "\n").splitLines()
    let a = actual.replace("\r\n", "\n").splitLines()

    var i = 0
    while i < e.len and i < a.len and e[i] == a[i]:
        inc i

    if i == e.len and i == a.len:
        return ""  # identical

    result = &"first difference at line {i + 1}\n"
    for j in max(0, i - context) ..< i:
        result.add &"    {j + 1:>5} | {e[j]}\n"
    result.add &"  - {i + 1:>5} | {(if i < e.len: e[i] else: \"<end of file>\")}\n"
    result.add &"  + {i + 1:>5} | {(if i < a.len: a[i] else: \"<end of file>\")}\n"
    for j in i + 1 ..< min(max(e.len, a.len), i + 1 + context):
        if j < e.len:
            result.add &"    {j + 1:>5} | {e[j]}\n"
    result.add &"(expected {e.len} lines, got {a.len})"

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

            let expected = readFile(expectedPath)
            let diff = firstDiff(expected, ast)
            if diff != "":
                checkpoint(diff)
                fail()
