# Strict builds (-Wall -Wextra)

U++'s own build methods use neither `-Wall` nor `-Wextra` (and its clang methods turn
`-Wlogical-op-parentheses` off, uppsrc/ide/Builders/Install.cpp). A strict build of the
check programs on 18619 + patches 0001-0010 gave 1,367 warning sites in 228 U++ files.
Patches 0011-0016 fix them in the code, using C++23/26 where it helps:

| Kind | Sites | Fix |
|---|---|---|
| -Wdeprecated-copy | 538 | 0011: `Size_`, `Point_`, `Rect_` get `operator=(const T&) = default` |
| -Wunused-parameter | 522 | 0013: name commented out; `[[maybe_unused]]` where ASSERT, LLOG or another platform uses it |
| `&&` within `\|\|` | 238 | 0012: parentheses (clang's own fix-its, same meaning) |
| -Wimplicit-fallthrough | 20 | 0014: `[[fallthrough]];`; ParseQtf's one was a bug (0015) |
| the rest | 40 | 0015, 0016: see findings.md |

Two of them were bugs (0015). Strict builds now give 0 warnings with gcc 15 and clang, debug
and release, plain and with each check; upp_basefix.sh counts every warning: ours, U++.

Warnings are counted from one file per compile (the build method runs the compiler
through `$WORK/bin/<compiler>-cc`, which keeps its messages in `$WORK/diag/`): umk's log
interleaves the lines of parallel compiles, so counting it splits some warnings.
Only files compiled in a run print warnings: tick Clean for the whole tree's count.
