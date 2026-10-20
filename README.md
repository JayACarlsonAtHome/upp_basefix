# upp_basefix

One pinned U++ for all the projects (jac317, jac313, Date_001, jText_GUI), plus the
fixes we need in it, kept as plain patch files, built and checked on their own.

- **Pin:** U++ build **18761**: github.com/ultimatepp/ultimatepp master at commit
  `af8e133a7697615f18693b071dac39992f9f7ace` (2026-10-19). `./upp_basefix.sh pristine`
  downloads it once; `pin/uppsrc-18761.sha256` lists the SHA-256 of all 2782 files of its
  `uppsrc`. (U++ build number = git commit count + 2270.)
- **System libraries:** since 2026-10 U++ uses the system's zlib, lz4, xxHash, PCRE2,
  sqlite3, libpng, OpenSSL, ... instead of bundled copies. On RHEL 9: `lz4-devel`,
  `xxhash-devel` (EPEL), `pcre2-devel`, `sqlite-devel`, `libpng-devel`, `openssl-devel`,
  `zlib-devel`, plus `gtk3-devel` for the GUI.
- **Patches** (`patches/`, applied in order with `patch -p1`):
  - `0001`: U++'s per-thread heap array gets `alignas(Heap)` (gcc -O3 programs crashed).
  - `0002`: lambdas `[=` -> `[=, this` in Core/SSH (C++20 deprecates the implicit capture).
  - `0003`-`0007`: bugs the checks found (GTK string leak, PNG shift by 32, Painter
    attributes, CoWork start-up order, Ctrl frame view); `0008`: bugs strict warnings
    found (surrogate pairs in CParser, Equalight, memory status); `0009`: initialisations.
  - `0010`-`0015`: every strict (`-Wall -Wextra`) warning fixed in the code, by kind
    (copy assignment, parentheses, unused parameters, fall-through, bugs, the rest);
    `0014` holds three bugs: ParseQtf reading past the end of the text,
    InfoCtrl::GetTabOffset, Regex dropping its options.
  - Each is described in `docs/findings.md`; how the warnings were fixed: `docs/strict.md`.
- **Suppressions** (`supp/`): system-library reports only (GLib/GTK under TSan, librsvg
  leaks).
- **Checks** (`check/`): `UppBaseCheck` (console: Core, Core/SSH, Draw, plugin/png,
  plugin/sqlite3, RichText; no display, fit for valgrind and sanitizers) and
  `UppBaseCheckGui` (CtrlLib window, `--smoke` closes it). Between them they build every
  U++ package the projects use.

## Use

    ./upp_basefix.sh pristine          # the pinned tree from GitHub, verified
    ./upp_basefix.sh patch             # + patches -> patched tree
    ./upp_basefix.sh test --clean      # gcc and clang: build, count warnings, run the checks
    ./upp_basefix.sh test --release
    ./upp_basefix.sh test --valgrind   # or --helgrind, --asan, --tsan (clang)
    ./upp_basefix.sh build --tree pristine   # the unpatched tree, to compare

Everything runs in the work area (`UPP_BASEFIX_WORK`, default `/home/jay/upp_basefix_work`):
the trees, its own copy of umk with its own object cache (never shared with another
project), `out/` and `logs/`. Nothing outside it is changed.

Or the window: `./upp_basefix.sh gui` builds UppBaseFixBuild and starts it (options,
checks; column 1: the commands, each file compiled, the messages; column 2: steps and
results; double-click a build result for its log). It logs what it shows to
`$WORK/logs/gui-latest.log` (the last run) and `gui-history.log` (all runs).

Status 2026-10-20: patched tree (0001-0015), gcc 15 and clang (C++26), debug and release,
strict (`-Wall -Wextra`) and clean: 0 warnings, ours and U++, plain and with every check;
UppBaseCheck 21/21. The pristine tree: 13/21 (the eight checks of bugs the patches fix
fail there).

The 18619 version of this project is kept in jac315 (work area
`/home/jay/upp_basefix_work_18619`).
