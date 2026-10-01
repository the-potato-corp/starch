import std/os
import std/monotimes
import std/times
import std/strformat
import errors
import lexer
import nodes
import parser
import tokens

proc ms(ns: int64): float = ns.float / 1_000_000.0

proc main(): void =
    if paramCount() < 1:
        echo "Usage: starch <filename>"
        quit(1)

    let filename = paramStr(1)
    let content = filename.readFile()

    # cold run
    let t0 = getMonoTime()
    let lexer = newLexer(content, filename)
    let tokens = lexer.lex()
    let t1 = getMonoTime()
    let parser = newParser(tokens, filename, content, lexer.lines)
    let ast = parser.parse()
    let t2 = getMonoTime()

    let coldLex = (t1 - t0).inNanoseconds
    let coldParse = (t2 - t1).inNanoseconds

    block:
        let l = newLexer(content, filename)
        let tk = l.lex()
        discard newParser(tk, filename, content, l.lines).parse()

    const iterations = 1000
    var lexTotal, parseTotal: int64
    var tokenCheck = 0  # consumes results so the loop can't be optimized away

    for _ in 0 ..< iterations:
        let a = getMonoTime()
        let l = newLexer(content, filename)
        let tk = l.lex()
        let b = getMonoTime()
        let p = newParser(tk, filename, content, l.lines)
        let tree = p.parse()
        let c = getMonoTime()

        lexTotal += (b - a).inNanoseconds
        parseTotal += (c - b).inNanoseconds
        tokenCheck += tk.len

    # output
    for t in tokens:
        echo $t

    echo $ast
    echo()

    let avgLex = ms(lexTotal) / iterations.float
    let avgParse = ms(parseTotal) / iterations.float
    let avgTotal = avgLex + avgParse

    let nTok = tokens.len.float
    let nChar = content.len.float   # bytes, not unicode characters

    # ms -> ns
    proc perUnit(avgMs, units: float): float = avgMs * 1_000_000.0 / units
    # bytes per ms -> mb/s
    proc mbPerSec(avgMs, bytes: float): float = bytes / avgMs / 1000.0

    echo "==================== Metrics ===================="
    echo &"Cold run:   lex {ms(coldLex):.3f}ms | parse {ms(coldParse):.3f}ms | total {ms(coldLex + coldParse):.3f}ms"
    echo &"Steady avg: lex {avgLex:.3f}ms | parse {avgParse:.3f}ms | total {avgTotal:.3f}ms  ({iterations} iterations)"
    echo()
    echo &"Input: {tokens.len} tokens, {content.len} bytes ({nChar / nTok:.1f} bytes/token)"
    echo()
    echo "                 ns/token    ns/byte    MB/s"
    echo &"Lexer          {perUnit(avgLex, nTok):9.1f}  {perUnit(avgLex, nChar):9.2f}  {mbPerSec(avgLex, nChar):7.1f}"
    echo &"Parser         {perUnit(avgParse, nTok):9.1f}  {perUnit(avgParse, nChar):9.2f}  {mbPerSec(avgParse, nChar):7.1f}"
    echo &"Combined       {perUnit(avgTotal, nTok):9.1f}  {perUnit(avgTotal, nChar):9.2f}  {mbPerSec(avgTotal, nChar):7.1f}"
    echo()
    echo &"(checksum: {tokenCheck})"

when isMainModule:
    try:
        main()
    except StarchError as e:
        # Return the error and quit gracefully
        stderr.writeLine(e.msg)
        quit(1)
