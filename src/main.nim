import std/os
import std/monotimes
import std/times
import std/strformat
import errors
import lexer
import nodes
import parser
import tokens

proc main(): void =
    if paramCount() < 1:
        echo "Usage: starch <filename>"
        quit(1)

    let filename = paramStr(1)
    let content = filename.readFile()

    # Be as fair to the timer as possible; no
    # file reading or console flushing bottlenecks
    let start = getMonoTime()

    # Lex the file
    let lexer = newLexer(content, filename)
    let tokens = lexer.lex()

    # Parse the file
    let parser = newParser(tokens, filename, content, lexer.lines)
    let ast = parser.parse()

    let elapsed = (getMonoTime() - start).inNanoseconds

    for t in tokens:
        echo $t

    echo $ast

    echo()
    echo(&"Took {elapsed.float / 1_000_000.0}ms")

when isMainModule:
    try:
        main()
    except StarchError as e:
        # Return the error and quit gracefully
        stderr.writeLine(e.msg)
        quit(1)
