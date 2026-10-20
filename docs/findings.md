# Findings in U++ 18619 (2026-10-20)

From `./upp_basefix.sh test` with each check (valgrind, helgrind, ASan + UBSan, TSan) and
strict builds (`-Wall -Wextra`), gcc 15 and clang, debug builds for the stacks.
"Ours" = upp_basefix's check programs: no finding is in them.

## Fixed by a patch (to report to the U++ owners)

| Patch | Found by | Where | What |
|---|---|---|---|
| 0001 | run, gcc -O3 | Core/sheap.cpp | per-thread heap byte array not aligned to Heap |
| 0002 | build, gcc -O2/-O3 | plugin/sqlite3 (sqlite3mc 2.2.7) | -Wstringop-overread false alarms: silenced, see sqlite3mc_stringop_overread.md |
| 0003 | build, C++20+ | 71 lambdas in Core, CtrlLib, CtrlCore, Painter | implicit `this` capture via `[=]` (deprecated); one SSH lambda also captured `ipinfo` it never used |
| 0004 | valgrind, LSan (GUI) | CtrlLib/ChGtk3.cpp `GtkSettingsString` | the string `g_object_get` returns is never `g_free`'d (13 bytes per call) |
| 0005 | UBSan | plugin/png/pngupp.cpp:436 | `(1 << bpp) - 1` with bpp 32: shift by 32 (undefined) |
| 0006 | UBSan (GUI) | Painter/Context.cpp | `Create` leaves `attr.onpath` unset, then copies attr (bool value 33); and `ImageFilterOp` stores the filter in `attr.invert` instead of `attr.filter` |
| 0007 | helgrind | Core/CoWork.cpp `Pool::Pool` | worker threads started before `quit` and the free list are set; safe only through the static-init guard, which helgrind cannot see |
| 0008 | valgrind (GUI) | CtrlCore/CtrlFrame.cpp `InsertFrame` | a control's second frame: the first frame's view is not copied, so the next layout compares an uninitialised Rect |
| 0009 | strict: -Wparentheses | Core/parser.cpp:457 | `𠀀` (U+20000 and up): `hi<<10 \| lo + 0x10000` is missing parentheses, so every code point with bit 16 set came out wrong; and `hex < 0xDBFF` missed the last high surrogate (U+10FC00..U+10FFFF) |
| 0009 | strict: -Wtype-limits | Draw/ImageOp.cpp `Equalight` | `size_t n` tested `n < 0`: never true, so Equalight always returned the image unchanged |
| 0009 | strict: -Wtype-limits | Core/Cpu.cpp `GetSystemMemoryStatus` | sysconf's -1 stored in uint64 before the `>= 0` test |
| 0010 | strict: -Wmisleading-indentation | Core/App.cpp `GetUserName` | space-indented block between tab-indented lines (reads as if the return were in the loop) |

UppBaseCheck checks 0009's three bugs directly: on the pristine tree it passes 13/16.

Not patched, for the report: RichText/ParseQtf.cpp `switch(*term++)` on an unexpected end
of text steps past the terminating NUL, so `Error()` reads one byte beyond the string.

## System libraries, not U++ (suppressed: supp/)

| Check | Where | What |
|---|---|---|
| valgrind, LSan (GUI) | librsvg (Rust) | 40 bytes kept for the process lifetime when GTK loads SVG icons |
| TSan (GUI) | GLib, GObject, GTK, GDK, gdk-pixbuf, ATK, dbus, GVFS, cairo, pango, ... | not built with -fsanitize=thread, so TSan cannot see their own locking (futexes, GMutex, g_slice) and reports their internal hand-offs; in every report the frames above U++'s call into GTK were all library frames |

Checked runs of the GUI also start it with `NO_AT_BRIDGE=1 GTK_A11Y=none GIO_USE_VFS=local`
(no accessibility bridge, no GVFS): fewer system threads; nothing of U++ is left out.

## Strict builds

See strict.md: what is counted as U++ house style, and why.
