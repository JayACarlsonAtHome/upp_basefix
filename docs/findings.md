# Findings in U++ 18761 (2026-10-20)

Pin: github.com/ultimatepp/ultimatepp master at `af8e133a7697` (2026-10-19), build 18761.
From `./upp_basefix.sh test` with each check (valgrind, helgrind, ASan + UBSan, TSan) and
strict builds (`-Wall -Wextra`), gcc 15 and clang, debug builds for the stacks. Most were
found first on build 18619 and are still in 18761; "Ours" = upp_basefix's check programs:
no finding is in them.

## Fixed by a patch

| Patch | Found by | Where | What |
|---|---|---|---|
| 0001 | run, gcc -O3 | Core/sheap.cpp | per-thread heap byte array not aligned to Heap |
| 0002 | build, C++20+ | Core/SSH (7 files) | implicit `this` capture via `[=]` (deprecated); upstream has fixed the others since 18619; one lambda also captured `ipinfo` it never used |
| 0003 | valgrind, LSan (GUI) | CtrlLib/ChGtk3.cpp `GtkSettingsString` | the string `g_object_get` returns is never `g_free`'d (13 bytes per call) |
| 0004 | UBSan | plugin/png/pngupp.cpp | `(1 << bpp) - 1` with bpp 32: shift by 32 (undefined) |
| 0005 | UBSan (GUI) | Painter/Context.cpp | `Create` leaves `attr.onpath` unset, then copies attr (bool value 33); and `ImageFilterOp` stores the filter in `attr.invert` instead of `attr.filter` |
| 0006 | helgrind | Core/CoWork.cpp `Pool::Pool` | worker threads started before `quit` and the free list are set; safe only through the static-init guard, which helgrind cannot see |
| 0007 | valgrind (GUI) | CtrlCore/CtrlFrame.cpp `InsertFrame` | a control's second frame: the first frame's view is not copied, so the next layout compares an uninitialised Rect |
| 0008 | strict: -Wparentheses | Core/parser.cpp | U+20000 and up: `hi<<10 \| lo + 0x10000` is missing parentheses, so every code point with bit 16 set comes out wrong; and `hex < 0xDBFF` misses the last high surrogate (U+10FC00..U+10FFFF) |
| 0008 | strict: -Wtype-limits | Draw/ImageOp.cpp `Equalight` | `size_t n` tested `n < 0`: never true, so Equalight always returns the image unchanged |
| 0008 | strict: -Wtype-limits | Core/Cpu.cpp `GetSystemMemoryStatus` | sysconf's -1 stored in uint64 before the `>= 0` test |
| 0009 | strict | Core/Heap.h, PdfDraw, RichText/DiagramShape.cpp | values read before they are set in some paths (initialised now) |
| 0010 | strict: -Wdeprecated-copy | Core/Gtypes.h | Size_, Point_, Rect_: one converting constructor is the copy constructor, so the implicit copy assignment is deprecated; now `= default` (538 sites) |
| 0011 | strict: -Wparentheses | 64 files | `&&` within `\|\|` spelled out with parentheses (same meaning) |
| 0012 | strict: -Wunused-parameter | 140 files | unused parameter names commented out (`int /*x*/`); `[[maybe_unused]]` where only ASSERT, LLOG or another platform's code uses one |
| 0013 | strict: -Wimplicit-fallthrough | 11 files | every intended fall-through marked `[[fallthrough]];` (each read: key press -> release, Home -> Ctrl+Home, ...) |
| 0014 | strict: -Wimplicit-fallthrough, ASan | RichText/ParseQtf.cpp | at an unexpected end of QTF text, `switch(*term++)` (and two more spots, one in `GetColor`) steps past the NUL, so `Error()` and the parser read beyond the string; `Error` is `[[noreturn]]` |
| 0014 | strict: -Wunused-parameter | CtrlLib/StatusBar.cpp `InfoCtrl::GetTabOffset(int t)` | ignores `t` (a local `t` hides it) and returns the end of the last tab; now stops at tab `t` (no caller in U++) |
| 0014 | strict: -Wunused-parameter | Core/Regex.h (new since 18619) | `Regex(dword options, const char *pattern, int len)` and the `WRegex` one call `Set(pattern, len)`: the options (e.g. `PCRE2_CASELESS`) are dropped |
| 0015 | strict: the rest | 21 files | signed/unsigned compares (`findarg`/`decode` compare integers by value: no negative number equals an unsigned one), debug `CHECK` as one expression (it left an empty `else`), default member values for aggregates, `[[maybe_unused]]` SSH allocators, sized `operator delete`, enum/int in `?:`, `(const T)` casts, byte fields tested `>= 0`, two string-literal `?:` gcc -O3 + ASan misread |
| 0016 | bootstrap | Draw/Draw.upp | the system packages are declared for DPKG only (freetype, fontconfig, X11, xcb, expat); the RPM names are added |

UppBaseCheck checks the bugs of 0008 and 0014 and the `findarg` rule of 0015 directly:
on the pristine tree it passes 13/21, on the patched tree 21/21.

## Not in uppsrc, so not patched

| Where | What |
|---|---|
| `mkumk_gcc.sh` (repo root) | since the switch to system libraries (2026-10-14) it no longer links: it lacks `-llz4 -lzstd -llzma -lpcre2-8 -lpcre2-32 -lxxhash`; `upp_basefix.sh` adds them when it builds umk |

## System libraries, not U++ (suppressed: supp/)

| Check | Where | What |
|---|---|---|
| valgrind, LSan (GUI) | librsvg (Rust) | 40 bytes kept for the process lifetime when GTK loads SVG icons |
| TSan (GUI) | GLib, GObject, GTK, GDK, gdk-pixbuf, ATK, dbus, GVFS, cairo, pango, ... | not built with -fsanitize=thread, so TSan cannot see their own locking (futexes, GMutex, g_slice) and reports their internal hand-offs; in every report the frames above U++'s call into GTK were all library frames |

Checked runs of the GUI also start it with `NO_AT_BRIDGE=1 GTK_A11Y=none GIO_USE_VFS=local`
(no accessibility bridge, no GVFS): fewer system threads; nothing of U++ is left out.

## Strict builds

With 0010-0015, strict builds (`-Wall -Wextra`) of the check programs give no warning at
all, gcc and clang, debug and release, and with each check: see strict.md.
