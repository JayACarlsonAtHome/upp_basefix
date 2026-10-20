# Findings in U++ 18619 (2026-10-20)

From `./upp_basefix.sh test` with the checks, patched tree (0001-0003), gcc 15 and clang.
"Ours" = upp_basefix's check programs: no finding is in them.

| Check | Where | What | Plan |
|---|---|---|---|
| build, C++20+ | 71 lambdas in Core, CtrlLib, CtrlCore, Painter | implicit `this` capture via `[=]` (deprecated) | fixed: patch 0003 |
| build, gcc -O2/-O3 | plugin/sqlite3 (sqlite3mc 2.2.7 amalgamation) | -Wstringop-overread false alarms | silenced: patch 0002; see sqlite3mc_stringop_overread.md |
| run, gcc -O3 | Core/sheap.cpp | per-thread heap byte array not aligned to Heap | fixed: patch 0001 |
| valgrind (GUI) | CtrlLib/ChGtk3.cpp:24 `GtkSettingsString` | 13 bytes: the string from g_object_get is never g_free'd | to patch + report |
| valgrind (GUI) | librsvg (system) | 40 bytes lost inside librsvg | suppression |
| UBSan | plugin/png/pngupp.cpp:436 | `(1 << bpp) - 1` with bpp 32: shift by 32 | to patch + report |
| UBSan (GUI) | Painter/BufferPainter.h:151 | `invert` read before it is set (bool value 33) | to patch + report |
| LSan, TSan (GUI) | GTK / GLib internals (to confirm) | leaks, races at start-up | suppressions, if confirmed |
| helgrind | Core/CoWork.cpp:149 | "possible data race" on a pool flag; TSan reports nothing for the same program | likely benign; look closer |
