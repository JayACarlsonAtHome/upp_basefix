# upp_basefix

A pinned [U++ (Ultimate++)](https://www.ultimatepp.org) tree plus a set of fixes, kept as
plain patch files, built and checked on their own: gcc 15 and clang, C++26, strict warnings
(`-Wall -Wextra`), AddressSanitizer + UBSan, ThreadSanitizer, valgrind memcheck and helgrind.

With the patches, the U++ packages below build with **0 warnings** under `-Wall -Wextra` with
both compilers, debug and release, and every check runs clean. Along the way the checks and
the warnings found real bugs, each with a patch and, where it can be tested, a check that
fails without the patch (`docs/findings.md`).

Everything here is offered to the U++ project to use as it sees fit, under U++'s own license
model (BSD 2-Clause, `LICENSE`).

## What is pinned

U++ build **18761**: github.com/ultimatepp/ultimatepp master at commit
`af8e133a7697615f18693b071dac39992f9f7ace` (2026-10-19). `pin/uppsrc-18761.sha256` lists the
SHA-256 of all 2782 files of its `uppsrc`. (U++ build number = git commit count + 2270.)

Checked packages: Core, Core/SSH, Draw, Painter, PdfDraw, RichText, Sql, CtrlCore (GTK),
CtrlLib, plugin/png, plugin/sqlite3, plugin/bmp.

## Patches (`patches/`, applied in order with `patch -p1`)

| Patch | What |
|---|---|
| 0001 | Core/sheap.cpp: per-thread heap array gets `alignas(Heap)` (gcc -O3 programs crashed at start) |
| 0002 | Core/SSH: lambdas `[=` -> `[=, this` (C++20 deprecates the implicit capture) |
| 0003 | CtrlLib/ChGtk3.cpp: string from `g_object_get` never freed (valgrind, LSan) |
| 0004 | plugin/png: `1 << 32` for 32-bit images (UBSan) |
| 0005 | Painter: an attribute left unset, and `ImageFilterOp` storing the filter in the wrong field (UBSan) |
| 0006 | Core/CoWork.cpp: worker threads started before the pool is set up (helgrind) |
| 0007 | CtrlCore/CtrlFrame.cpp: a second frame loses the first frame's view (valgrind) |
| 0008 | bugs strict warnings found: CParser surrogate pairs (U+20000 and up decode wrong), `Equalight` never changes the image, `GetSystemMemoryStatus` with sysconf's -1 |
| 0009 | values read before they are set on some paths |
| 0010 | Core/Gtypes.h: `Size_`, `Point_`, `Rect_` get a defaulted copy assignment (538 -Wdeprecated-copy sites) |
| 0011 | `&&` within `\|\|` spelled out with parentheses (same meaning) |
| 0012 | unused parameters: names commented out, `[[maybe_unused]]` where only ASSERT, LLOG or another platform uses one |
| 0013 | intended fall-throughs marked `[[fallthrough]]` |
| 0014 | bugs: ParseQtf reads past the end of truncated QTF text; `InfoCtrl::GetTabOffset` ignores its argument; `Regex`/`WRegex(options, pattern, len)` drop the options |
| 0015 | the remaining strict warnings (signed/unsigned compares, debug `CHECK` as one expression, default member values, sized `operator delete`, ...) |
| 0016 | Draw/Draw.upp: the RPM names of its system packages (it lists only the Debian ones) |
| 0017 | bugs strict-full and gcc 16 found: `Sprintf` cut results at 1500 characters, `WwwFormat` put the zone text in the format, a stream `long` loaded only its low half where long is 64 bits, `memset8__`/`memcpy8__` formed a pointer before the block |
| 0018 | strict-full, the small kinds: fall-through, format, pedantic, virtual destructors, hidden overloads, cast-align (see `docs/strict.md`) |

Details for each: `docs/findings.md`; how the strict warnings were fixed: `docs/strict.md`.

## Use (Linux: Fedora/RHEL with dnf, or Debian/Ubuntu with apt)

    ./upp_basefix.sh bootstrap --install   # system packages (sudo), the pinned tree from
                                           # GitHub, umk built from it, the patched tree
    ./upp_basefix.sh test --clean          # gcc and clang: build, count warnings, run the checks
    ./upp_basefix.sh test --release --strict
    ./upp_basefix.sh build --strict-full --clean   # jac313's whole warning set: the count to work down
    ./upp_basefix.sh test --asan           # or --tsan (clang), --valgrind, --helgrind
    ./upp_basefix.sh test --tree pristine  # the unpatched tree, to compare
    ./upp_basefix.sh gui                   # the same in a window

`./upp_basefix.sh` with no arguments lists every command and option.

Everything runs in a work area (`UPP_BASEFIX_WORK`, default `~/upp_basefix_work`): the
download, the pristine and patched trees, its own umk with its own object cache, the
programs and the logs. Nothing outside it is changed. Compilers: the paths in `bm/` if they
exist (gcc-toolset-15 on RHEL), else `g++` / `clang++` from PATH; `UPP_BASEFIX_GCC` and
`UPP_BASEFIX_CLANG` override. On RHEL, `xxhash-devel` comes from EPEL.

The window (`gui/UppBaseFixBuild`) shows the options and checks, the commands, each file
compiled and any message (column 1), and the steps and results (column 2); it logs what it
shows to `logs/gui-latest.log` in the work area.

## Checks (`check/`)

- `UppBaseCheck`: console checks of Core, Core/SSH, Draw, plugin/png, plugin/sqlite3,
  RichText, including one per bug the patches fix that can be tested (21 checks; the
  pristine tree passes 13 of them).
- `UppBaseCheckGui`: opens and closes a CtrlLib window (`--smoke`).

`supp/` holds the suppressions for reports from system libraries (GLib/GTK under TSan,
librsvg), never for U++ code.

## Status

2026-10-20, RHEL 9.8, gcc 15.2 (gcc-toolset-15) and clang 21: the patched tree builds with
0 warnings (strict, clean, debug and release) and passes all checks alone and under each
tool. The pristine tree fails the 8 checks of the bugs the patches fix.
