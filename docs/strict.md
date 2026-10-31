# Strict builds (-Wall -Wextra)

U++'s own build methods use neither `-Wall` nor `-Wextra` (and its clang methods turn
`-Wlogical-op-parentheses` off, uppsrc/ide/Builders/Install.cpp). A strict build of the
check programs on 18619 + its first patches gave 1,367 warning sites in 228 U++ files; on
18761 the same fixes apply, plus a few for code new since then. Patches 0010-0015 fix
them in the code, using C++23/26 where it helps:

| Kind | Sites | Fix |
|---|---|---|
| -Wdeprecated-copy | 538 | 0010: `Size_`, `Point_`, `Rect_` get `operator=(const T&) = default` |
| -Wunused-parameter | 522 | 0012: name commented out; `[[maybe_unused]]` where ASSERT, LLOG or another platform uses it |
| `&&` within `\|\|` | 238 | 0011: parentheses (clang's own fix-its, same meaning) |
| -Wimplicit-fallthrough | 20 | 0013: `[[fallthrough]];`; ParseQtf's one was a bug (0014) |
| the rest | 40 | 0014, 0015: see findings.md |

Three of them were bugs (0014). Strict builds now give 0 warnings with gcc 15 and clang, debug
and release, plain and with each check; upp_basefix.sh counts every warning: ours, U++.

Warnings are counted from one file per compile (the build method runs the compiler
through `$WORK/bin/<compiler>-cc`, which keeps its messages in `$WORK/diag/`): umk's log
interleaves the lines of parallel compiles, so counting it splits some warnings.
Only files compiled in a run print warnings: tick Clean for the whole tree's count.

## Strict-full (jac313's warning set), from 2026-10-31

`--strict-full` adds what jac313 builds its own code with: `-Wpedantic -Wshadow
-Wnon-virtual-dtor -Wold-style-cast -Wcast-align -Woverloaded-virtual -Wimplicit-fallthrough
-Wformat=2 -Wconversion -Wsign-conversion` (jac313 also has `-Werror`). On 18761 + 0001-0016,
gcc 16 and clang 22 (Fedora 44), the check programs gave 5,964 warning sites:

| Kind | Sites | Patch |
|---|---|---|
| -Wold-style-cast | 2,725 | 0023, 0024: 0 |
| -Wsign-conversion, -Wconversion and clang's int / float / 64-to-32 kinds | 2,226 | 0020, 0021, 0022: 0 |
| -Wshadow | 900 | 0019 |
| the small kinds (cast-align, non-virtual-dtor, overloaded-virtual, format, fall-through, pedantic, ...) | 113 | 0018 (bugs: 0017) |

704 of them are in GLib's headers, which U++ includes as plain `-I` paths (pkg-config): not
ours to fix in GLib; U++'s build could give those paths as `-isystem`. After 0017 + 0018:
5,799 sites, none of the small kinds; `--strict` stays at 0 (gcc 16 release had 2, fixed in 0018).

0019 (2026-10-31): -Wshadow. The sites were renamed by a tool, not by hand: clang (libclang)
parses each file with its real compile command, finds the declaration at each warning, and
lists exactly the uses that resolve to it; those are renamed together, byte for byte (CRLF
kept). A file that does not parse cleanly is never used. Where `NAME_` would meet another
`NAME_` (an outer and an inner one), the inner one got a name of its own. After 0019:
4,896 sites, no -Wshadow in debug or release; --strict stays at 0, UppBaseCheck 23/23.

0020 (2026-10-31): the conversions made explicit, by a tool. clang prints the exact range of each
converted expression (`-fdiagnostics-print-source-range-info`, end exclusive) and gcc does in its
SARIF output (display columns: a tab counts to the next multiple of 8); each expression becomes
`static_cast<T>(expr)`, T the type the compiler converts to, written as clang / gcc spell it when
that name is safe at the spot (a built-in type or a U++ / C typedef such as size_t, dword, byte).
Left for a hand fix (0021): a site in a macro expansion or a template instantiation (one T would
be wrong for the others), `x op= y` on a narrower x, a range that is not a whole expression.
After 0020: 2,847 sites; the conversion kinds 168 (from 2,226); --strict 0, UppBaseCheck 23/23.

0021 (2026-10-31): `x op= y` on a narrower x, which 0020 left: C++ defines it as
`x = T(x op y)`, so the tool writes exactly that (y in parentheses unless a plain name), for
one-line statements whose x has no ++, -- or call. Slip, fixed by hand in the next patch: for a
-Wsign-conversion message gcc names the type the *operand* is converted to, not x's type, so a
few statements cast to that (e.g. `size.cy = static_cast<unsigned int>(size.cy | 0x80000000)`
with an int cy): the value stored is the same, but the line still warns. After 0021: 2,778 sites,
99 of them not old-style casts (hash constants, flag masks on 16-bit fields, FreeType's 64-bit
metrics, ASSERTs mixing uintptr_t and int, ...), each to be fixed by hand.

0022 (2026-10-31): the last conversions, by hand (see findings.md). Conversions are 0 in debug
and release with gcc 16 and clang 22. After 0022: 2,650 sites, all -Wold-style-cast (and GLib's
headers); --strict 0, UppBaseCheck 23/23.

0023 (2026-10-31): old-style casts, by a tool. clang gives the cast's `(` and the operand's exact
range; `(T)x` becomes `static_cast<T>(x)`. The compiler then picks the kind: a cast it rejects
as static_cast moves to reinterpret_cast ("not allowed") or const_cast ("casts away
qualifiers"), again until a syntax check of every file (debug) and a release build compile;
a template cast takes the kind every instantiation accepts. Left for 0025: casts written in
macros (227), casts no single kind fits (137, e.g. const away and a type change at once), and
47 that are not a plain `(T) operand`. After 0023: 1,111 sites, 716 in system headers (0024).

System headers (2026-10-31): umk gives the pkg-config include dirs (GTK, GLib, FreeType, X11,
HarfBuzz, ...) as plain -I, so their headers and macros counted as U++'s (716 sites). The build
methods upp_basefix makes and installs now also give those dirs with -isystem (system_includes
in upp_basefix.sh): gcc and clang then treat them as system headers. No U++ code changes.

0024 (2026-10-31): the last 330 casts. The tool's second pass fixes a cast written in a macro body
where clang's "expanded from macro" note points, reads a macro argument's operand from the line,
and, where neither a static, reinterpret nor const cast compiles, keeps const on the target or
spells const-away plus the type change as two casts; a few by hand (Value, Vector<void *>, GTK
ids), and OFFSETOF rewritten on offsetof.

**strict-full is 0** (2026-10-31): no warning in U++ or the checks, debug and release, gcc 16 and
clang 22, and --strict-full now builds with -Werror, as jac313 does. UppBaseCheck 23/23 in debug,
release, ASan + UBSan and valgrind.
