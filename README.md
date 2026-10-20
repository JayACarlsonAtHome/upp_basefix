# upp_basefix

One pinned U++ for all the projects (jac317, jac313, Date_001, jText_GUI), plus the
fixes we need in it, kept as plain patch files, built and checked on their own.

- **Pin:** U++ build **18619** (the tree at `/run/media/jay/GFS/upp`, as it was before our
  edits). `pin/uppsrc-18619.sha256` lists the SHA-256 of all 3031 files of its `uppsrc`.
- **Patches** (`patches/`, applied in order with `patch -p1`):
  - `0001-heap-alignas.patch`: U++'s per-thread heap array gets `alignas(Heap)`
    (gcc -O3 programs crashed at start).
  - `0002-sqlite3mc-quiet-gcc.patch`: gcc-only pragma for the sqlite3mc false alarms
    (`docs/sqlite3mc_stringop_overread.md`).
  - `0003-explicit-this-capture.patch`: 71 lambdas `[=` -> `[=, this` (C++20 deprecates
    the implicit capture); made from clang's own fix-its.
  - `0004`-`0008`: bugs the checks found (GTK string leak, PNG shift by 32, Painter
    attributes, CoWork start-up order, Ctrl frame view); `0009`: bugs strict warnings
    found (surrogate pairs in CParser, Equalight, memory status); `0010`: indentation.
    Each is described in `docs/findings.md`.
- **Suppressions** (`supp/`): system-library reports (GLib/GTK under TSan, librsvg leaks)
  and `strict-reviewed.txt`, the U++ strict-warning sites read and found harmless
  (`docs/strict.md`).
- **Checks** (`check/`): `UppBaseCheck` (console: Core, Core/SSH, Draw, plugin/png,
  plugin/sqlite3; no display, fit for valgrind and sanitizers) and `UppBaseCheckGui`
  (CtrlLib window, `--smoke` closes it). Between them they build every U++ package the
  projects use.
- **Findings:** `docs/findings.md`.

## Use

    ./upp_basefix.sh pristine          # clean 18619 tree from /run/media/jay/GFS/upp, verified
    ./upp_basefix.sh patch             # + patches -> patched tree
    ./upp_basefix.sh test --clean      # gcc and clang: build, count warnings, run the checks
    ./upp_basefix.sh test --release
    ./upp_basefix.sh test --valgrind   # or --helgrind, --asan, --tsan (clang)
    ./upp_basefix.sh build --tree pristine   # the unpatched tree, to compare

Everything runs in the work area (`UPP_BASEFIX_WORK`, default `/home/jay/upp_basefix_work`):
the trees, its own copy of umk with its own object cache (never shared with another
project), `out/` and `logs/`. Nothing outside it is changed.

Or the window: `./upp_basefix.sh gui` builds UppBaseFixBuild and starts it (options,
checks, live output, a results table; double-click a build result for its log).

Status 2026-10-20: patched tree (0001-0010), gcc 15 and clang (C++26), debug and release,
strict and clean: ours 0, U++ 0 warnings (U++ house style counted apart, docs/strict.md);
UppBaseCheck 16/16 and the GUI smoke test pass alone and under ASan + UBSan, TSan,
valgrind and helgrind (the GUI is not run under helgrind). The pristine tree: 13/16.
