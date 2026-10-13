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

    # Lex the file
    let content = filename.readFile()
    let lexer = newLexer(content, filename)
    for t in lexer.lex():
        echo $t

    # Parse the file
    echo "----"
    let parser = newParser(lexer.tokens, filename, content, lexer.lines)
    echo $parser.parse()

when isMainModule:
    try:
        let start = getMonoTime()
        main()
        let elapsed = (getMonoTime() - start).inNanoseconds
        echo()
        echo(&"Took {elapsed.float / 1_000_000.0}ms")
    except StarchError as e:
        # Return the error and quit gracefully
        stderr.writeLine(e.msg)
        quit(1)
