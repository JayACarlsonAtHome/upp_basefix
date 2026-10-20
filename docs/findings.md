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
| 0011 | strict: -Wdeprecated-copy | Core/Gtypes.h | Size_, Point_, Rect_: one converting constructor is the copy constructor, so the implicit copy assignment is deprecated; now `= default` (538 sites) |
| 0012 | strict: -Wparentheses | 63 files | `&&` within `\|\|` spelled out with parentheses (same meaning) |
| 0013 | strict: -Wunused-parameter | 139 files | unused parameter names commented out (`int /*x*/`); `[[maybe_unused]]` where only ASSERT, LLOG or another platform's code uses one |
| 0014 | strict: -Wimplicit-fallthrough | 11 files | every intended fall-through marked `[[fallthrough]];` (each read: key press -> release, Home -> Ctrl+Home, ...) |
| 0015 | strict: -Wimplicit-fallthrough, ASan | RichText/ParseQtf.cpp | at an unexpected end of QTF text, `switch(*term++)` (and two more spots, one in `GetColor`) stepped past the NUL, so `Error()` and the parser read beyond the string; `Error` is `[[noreturn]]` |
| 0015 | strict: -Wunused-parameter | CtrlLib/StatusBar.cpp `InfoCtrl::GetTabOffset(int t)` | ignored `t` (a local `t` hid it) and returned the end of the last tab; now stops at tab `t` (no caller in U++) |
| 0016 | strict: the rest | 20 files | signed/unsigned compares (`findarg`/`decode` compare integers by value: no negative number equals an unsigned one), debug `CHECK` as one expression (it left an empty `else`), default member values for aggregates, `[[maybe_unused]]` SSH allocators, sized `operator delete`, enum/int in `?:`, `(const T)` casts, byte fields tested `>= 0` |

UppBaseCheck checks the bugs of 0009 and 0015 and the `findarg` rule of 0016 directly:
on the pristine tree it passes 13/19, on the patched tree 19/19.

## System libraries, not U++ (suppressed: supp/)

| Check | Where | What |
|---|---|---|
| valgrind, LSan (GUI) | librsvg (Rust) | 40 bytes kept for the process lifetime when GTK loads SVG icons |
| TSan (GUI) | GLib, GObject, GTK, GDK, gdk-pixbuf, ATK, dbus, GVFS, cairo, pango, ... | not built with -fsanitize=thread, so TSan cannot see their own locking (futexes, GMutex, g_slice) and reports their internal hand-offs; in every report the frames above U++'s call into GTK were all library frames |

Checked runs of the GUI also start it with `NO_AT_BRIDGE=1 GTK_A11Y=none GIO_USE_VFS=local`
(no accessibility bridge, no GVFS): fewer system threads; nothing of U++ is left out.

## Strict builds

With 0011-0016, strict builds (`-Wall -Wextra`) of the check programs give no warning at
all, gcc and clang, debug and release, and with each check: see strict.md.
