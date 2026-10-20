#!/usr/bin/env bash
# upp_basefix.sh: one pinned U++ (build 18761, github.com/ultimatepp/ultimatepp commit
# af8e133a7697) plus our patches, built and checked.
#
#   ./upp_basefix.sh pristine [--from DIR]   clean pinned tree in $WORK/pristine: the commit's
#                                             uppsrc from GitHub (downloaded once), or DIR's
#                                             uppsrc (*.orig files put back); checked vs pin/
#   ./upp_basefix.sh verify [DIR]             DIR/uppsrc against pin/uppsrc-$PIN.sha256
#   ./upp_basefix.sh patch                    $WORK/patched = pristine + patches/*.patch
#   ./upp_basefix.sh status [DIR]             which patches DIR/uppsrc has (default: patched)
#   ./upp_basefix.sh build [options]          build the check programs, count warnings
#        --compiler gcc|clang|both   (default both)      --release   (default debug)
#        --tree patched|pristine     (default patched)   --strict    (-Wall -Wextra)
#        --clean                     rebuild every package (umk -a)
#        --verbose                   the compiler's whole output while it builds (default: each
#                                    file compiled; warnings and errors listed after the build)
#   ./upp_basefix.sh test [options]           build, then run the checks
#        same options, plus one check:  --valgrind  --helgrind  --asan  --tsan
#        (--asan/--tsan need clang or gcc runtimes; valgrind needs valgrind)
#   ./upp_basefix.sh gui                      build the UppBaseFixBuild window (gcc release,
#                                             patched tree) and start it
#
# WORK (default /home/jay/upp_basefix_work) holds the trees, its own umk + object cache
# (umk/.cache/upp.out: never shared with other projects), out/ and logs/.
# Every step prints "step: ..." lines; build/test end with one "result:" line per run
# and a "summary:" line. The exit code is 0 only when everything asked for passed.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${UPP_BASEFIX_WORK:-/home/jay/upp_basefix_work}"
PIN=18761                                          # U++ build number: git commit count + 2270
PIN_COMMIT=af8e133a7697615f18693b071dac39992f9f7ace  # ultimatepp/ultimatepp master, 2026-10-19
PIN_URL="https://codeload.github.com/ultimatepp/ultimatepp/tar.gz/$PIN_COMMIT"
UMK_SOURCE="${UPP_BASEFIX_UMK:-/home/jay/u++/umk}"
step() { echo "step: $*"; }
die() { echo "error: $*" >&2; exit 2; }

tree_ok() { [ -f "$1/uppsrc/Core/Core.h" ]; }

cmd_verify() {
  local dir="${1:-$WORK/pristine}"
  tree_ok "$dir" || die "no U++ tree at $dir"
  step "verify $dir/uppsrc against pin/uppsrc-$PIN.sha256"
  local bad
  bad=$(cd "$dir" && sha256sum -c --quiet "$HERE/pin/uppsrc-$PIN.sha256" 2>&1 | grep -c ': FAILED' || true)
  local extra
  extra=$(cd "$dir" && comm -13 <(cut -c67- "$HERE/pin/uppsrc-$PIN.sha256" | LC_ALL=C sort) \
                               <(find uppsrc -type f ! -name '*.orig' | LC_ALL=C sort) | wc -l)
  echo "verify: $(wc -l < "$HERE/pin/uppsrc-$PIN.sha256") files pinned, $bad differ, $extra not in the pin"
  [ "$bad" = 0 ] && [ "$extra" = 0 ]
}

cmd_pristine() {
  local from=""
  [ "${1:-}" = --from ] && from="${2:?--from DIR}"
  mkdir -p "$WORK/pristine"
  if [ -z "$from" ]; then
    local tgz="$WORK/download/ultimatepp-$PIN_COMMIT.tar.gz"
    if [ ! -s "$tgz" ]; then
      step "download U++ $PIN (commit ${PIN_COMMIT:0:12}) from GitHub"
      mkdir -p "$WORK/download"
      curl -fsSL -o "$tgz.part" "$PIN_URL" && mv "$tgz.part" "$tgz" || die "download failed: $PIN_URL"
    fi
    step "unpack uppsrc -> $WORK/pristine/uppsrc"
    rm -rf "$WORK/pristine/uppsrc" "$WORK/pristine/ultimatepp-$PIN_COMMIT"
    tar -xzf "$tgz" -C "$WORK/pristine" "ultimatepp-$PIN_COMMIT/uppsrc" || die "unpack failed"
    mv "$WORK/pristine/ultimatepp-$PIN_COMMIT/uppsrc" "$WORK/pristine/uppsrc" && rmdir "$WORK/pristine/ultimatepp-$PIN_COMMIT"
  else
    tree_ok "$from" || die "no U++ tree at $from"
    step "copy $from/uppsrc -> $WORK/pristine/uppsrc (without *.orig)"
    rsync -a --delete --exclude='*.orig' "$from/uppsrc/" "$WORK/pristine/uppsrc/" || die "rsync failed"
    local o rel
    while IFS= read -r o; do   # a patched source keeps its originals as *.orig: put them back
      rel=${o#$from/}
      step "original back: ${rel%.orig}"
      cp -p "$o" "$WORK/pristine/${rel%.orig}"
    done < <(find "$from/uppsrc" -name '*.orig')
  fi
  cmd_verify "$WORK/pristine"
}

patch_applied() { patch -p1 -R --dry-run -s -f -d "$1" < "$2" > /dev/null 2>&1; }

cmd_patch() {
  tree_ok "$WORK/pristine" || die "no pristine tree: run ./upp_basefix.sh pristine"
  cmd_verify "$WORK/pristine" || die "the pristine tree does not match the pin"
  step "copy pristine -> $WORK/patched"
  mkdir -p "$WORK/patched"
  rsync -a --delete "$WORK/pristine/uppsrc/" "$WORK/patched/uppsrc/" || die "rsync failed"
  local p
  for p in "$HERE"/patches/*.patch; do
    step "apply $(basename "$p")"
    patch -p1 -s -f -d "$WORK/patched" < "$p" || die "$(basename "$p") does not apply"
  done
  # fresh mtimes on the patched files, so the object cache rebuilds them
  find "$WORK/patched/uppsrc" -newer "$WORK/pristine/uppsrc/Core/Core.h" -type f -exec touch {} + 2>/dev/null
  cmd_status "$WORK/patched"
}

cmd_status() {
  local dir="${1:-$WORK/patched}" p n=0 have=0
  tree_ok "$dir" || die "no U++ tree at $dir"
  for p in "$HERE"/patches/*.patch; do
    n=$((n + 1))
    if patch_applied "$dir" "$p"; then have=$((have + 1)); echo "status: applied  $(basename "$p")"
    else echo "status: missing  $(basename "$p")"; fi
  done
  echo "status: $have of $n patches in $dir"
  [ "$have" = "$n" ]
}

setup_umk() {
  [ -x "$WORK/umk/umk" ] && return 0
  [ -x "$UMK_SOURCE" ] || die "no umk at $UMK_SOURCE (set UPP_BASEFIX_UMK)"
  step "own umk + object cache in $WORK/umk"
  mkdir -p "$WORK/umk/.config/u++/theide" && cp "$UMK_SOURCE" "$WORK/umk/umk"
}

# bm COMPILER STRICT [EXTRA_CPP] [EXTRA_LINK] -> path of a build method in $WORK/bm
make_bm() {
  local c=$1 strict=$2 extra=${3:-} link=${4:-} src name
  case $c in gcc) src="$HERE/bm/GCC15.bm" ;; clang) src="$HERE/bm/CLANG26.bm" ;; *) die "compiler $c" ;; esac
  # tree and pin in the name: umk keeps objects per build method; the check programs'
  # sources are the same files for both trees, and a new pin's files can be older than
  # the objects of the last one
  name="$TREE-$PIN-$c$([ "$strict" = 1 ] && echo -strict)$([ -n "$extra" ] && echo "-$(echo "$extra" | md5sum | cut -c1-6)")"
  mkdir -p "$WORK/bm"
  local add=""
  [ "$strict" = 1 ] && add=" -Wall -Wextra"
  [ -n "$extra" ] && add="$add $extra"
  # the compiler through a wrapper: each compile's messages also go to a file of its own
  # in $UPP_BASEFIX_DIAG, so warnings are counted whole (umk's log interleaves the
  # parallel compiles' lines)
  local real; real=$(sed -n 's/^COMPILER = "\(.*\)";/\1/p' "$src")
  mkdir -p "$WORK/bin"
  cat > "$WORK/bin/$c-cc" <<EOW
#!/bin/bash
# upp_basefix: runs $real; with UPP_BASEFIX_DIAG set, keeps this compile's messages there
[ -n "\${UPP_BASEFIX_DIAG:-}" ] || exec "$real" "\$@"
f=\$(mktemp "\$UPP_BASEFIX_DIAG/XXXXXXXX")
"$real" "\$@" 2> "\$f"; rc=\$?
cat "\$f" >&2
exit \$rc
EOW
  chmod +x "$WORK/bin/$c-cc"
  sed -e "s|^COMPILER = \".*\";|COMPILER = \"$WORK/bin/$c-cc\";|" \
      -e "s|^COMMON_CPP_OPTIONS = \"\\(.*\\)\";|COMMON_CPP_OPTIONS = \"\\1$add\";|" \
      -e "s|^COMMON_C_OPTIONS = \"\\(.*\\)\";|COMMON_C_OPTIONS = \"\\1${extra:+ $extra}\";|" \
      -e "s|^COMMON_LINK = \"\\(.*\\)\";|COMMON_LINK = \"\\1${link:+ $link}\";|" "$src" > "$WORK/bm/$name.bm"
  echo "$WORK/bm/$name.bm"
}

COMPILERS="gcc clang"; MODE=debug; TREE=patched; STRICT=0; CLEAN=0; CHECK=""; VERBOSE=0
parse_build_opts() {
  while [ $# -gt 0 ]; do
    case $1 in
      --compiler) case ${2:-} in both) COMPILERS="gcc clang" ;; gcc|clang) COMPILERS=$2 ;; *) die "--compiler gcc|clang|both" ;; esac; shift 2 ;;
      --release) MODE=release; shift ;;
      --debug) MODE=debug; shift ;;
      --tree) case ${2:-} in patched|pristine) TREE=$2 ;; *) die "--tree patched|pristine" ;; esac; shift 2 ;;
      --strict) STRICT=1; shift ;;
      --clean) CLEAN=1; shift ;;
      --verbose) VERBOSE=1; shift ;;
      --valgrind|--helgrind|--asan|--tsan) CHECK=${1#--}; shift ;;
      *) die "unknown option $1" ;;
    esac
  done
}

# warning_lines DIAG_DIR -> every unique warning and error of a build, one per message
# (from the compiler's own message files: umk's log interleaves parallel compiles)
warning_lines() { cat "$1"/* 2> /dev/null | grep -E ': (warning|error|fatal error): |undefined reference' | sort -u; }

# count_warnings DIAG_DIR -> "ours upp": warnings in upp_basefix's code, and all others
count_warnings() {
  local all ours
  all=$(warning_lines "$1" | grep -E ': warning: ')
  ours=$(grep -cE "^$HERE/" <<< "$all")
  echo "$ours $(( $(grep -c . <<< "$all") - ours ))"
}

# show_lines: what the terminal and the window see while umk builds: umk's own lines
# (packages, each file compiled, linking); --verbose: everything, the compiler's messages
# too. The messages come whole after each build (warning_lines).
show_lines() {
  if [ "$VERBOSE" = 1 ]; then cat; return; fi
  grep --line-buffered -E '^(-----|BLITZ:|Linking|OK\. |There were errors|[^ /:]+\.(c|cc|cpp|cxx|icpp|m|mm)$)'
}

# build_one COMPILER -> builds both check programs; sets BUILT_DIR, prints result lines
FAILS=0
build_one() {
  local c=$1 extra="" link="" flags
  case $CHECK in
    asan) extra="-fsanitize=address,undefined -fno-omit-frame-pointer"; link="-fsanitize=address,undefined" ;;
    tsan) extra="-fsanitize=thread"; link="-fsanitize=thread" ;;
  esac
  local bm; bm=$(make_bm "$c" "$STRICT" "$extra" "$link")
  flags="bsH"; [ "$MODE" = release ] && flags="brsH"; [ "$CLEAN" = 1 ] && flags="a$flags"
  flags="-$flags"
  local what="$MODE"; [ "$STRICT" = 1 ] && what="$what, strict"; [ -n "$CHECK" ] && what="$what, $CHECK"
  local tag="$TREE-$c-$MODE$([ "$STRICT" = 1 ] && echo -strict)${CHECK:+-$CHECK}"
  BUILT_DIR="$WORK/out/$tag"; mkdir -p "$BUILT_DIR" "$WORK/logs"
  local p rc log ours upp t0 t1
  for p in UppBaseCheck UppBaseCheckGui; do
    log="$WORK/logs/build-$tag-$p.log"
    step "build $p with $c ($what) on the $TREE tree"
    t0=$(date +%s)
    # +USEMALLOC: sanitizers and valgrind need the system allocator, not U++'s heap
    local cfg=""; [ -n "$CHECK" ] && cfg="+USEMALLOC"
    local diag="$WORK/diag/$tag-$p"; rm -rf "$diag"; mkdir -p "$diag"
    rm -f "$BUILT_DIR/$p"   # a failed build must not leave the last one to be run
    UPP_BASEFIX_DIAG="$diag" "$WORK/umk/umk" "$HERE/check,$WORK/$TREE/uppsrc" "$p" "$bm" $flags $cfg "$BUILT_DIR/$p" 2>&1 | tee "$log" | show_lines | sed -u 's/^/  /'
    rc=${PIPESTATUS[0]}; t1=$(date +%s)
    local counts; counts=$(count_warnings "$diag")
    read -r ours upp <<< "$counts"
    [ "$VERBOSE" = 1 ] || warning_lines "$diag" | sed 's/^/  /'
    # Only files compiled in this run print warnings: a clean build counts the whole tree,
    # so its count is kept and shown next to an incremental build's.
    local wfile="$BUILT_DIR/$p.warnings" scope
    if [ "$CLEAN" = 1 ]; then
      [ "$rc" = 0 ] && echo "$counts" > "$wfile"
      scope="whole tree"
    elif [ -f "$wfile" ]; then
      scope="files compiled now; last clean build: ours $(cut -d' ' -f1 "$wfile"), U++ $(cut -d' ' -f2 "$wfile")"
    else
      scope="files compiled now; tick Clean for the whole tree"
    fi
    echo "result: build $p $c $MODE: $([ "$rc" = 0 ] && echo ok || echo FAILED) $((t1 - t0)) s  warnings: ours $ours, U++ $upp ($scope)  log: $log"
    [ "$rc" = 0 ] || FAILS=$((FAILS + 1))
  done
}

# UBSan reports and goes on (exit 0): a "runtime error:" in the output fails the run.
ub_fail() {
  local n; n=$(echo "$out" | grep -c 'runtime error:')
  [ "$n" -gt 0 ] && [ "$rc" = 0 ] && { rc=98; echo "  ($n UBSan runtime error(s): counted as a failure)"; }
}

run_checks() {
  local c=$1 out rc
  local run=()
  case $CHECK in
    valgrind) run=(valgrind --error-exitcode=99 --leak-check=full --errors-for-leak-kinds=definite --show-leak-kinds=definite -q
                            --suppressions="$HERE/supp/valgrind.supp") ;;
    helgrind) run=(valgrind --tool=helgrind --error-exitcode=99 -q --suppressions="$HERE/supp/valgrind.supp") ;;
  esac
  # system-library noise is suppressed (supp/); UBSan prints a stack for each report
  export TSAN_OPTIONS="suppressions=$HERE/supp/tsan.supp second_deadlock_stack=1" LSAN_OPTIONS="suppressions=$HERE/supp/lsan.supp print_suppressions=0"
  export UBSAN_OPTIONS="print_stacktrace=1"
  if [ ! -x "$BUILT_DIR/UppBaseCheck" ]; then
    echo "result: test UppBaseCheck $c $MODE${CHECK:+ $CHECK}: skipped (build failed)"
  else
    step "run UppBaseCheck ($c${CHECK:+, $CHECK})"
    out=$("${run[@]}" "$BUILT_DIR/UppBaseCheck" 2>&1); rc=$?
    echo "$out" | sed 's/^/  /'
    ub_fail
    echo "result: test UppBaseCheck $c $MODE${CHECK:+ $CHECK}: $([ "$rc" = 0 ] && echo ok || echo "FAILED (exit $rc)")  $(echo "$out" | grep -E '^(passed|FAILED):' | tail -1)"
    [ "$rc" = 0 ] || FAILS=$((FAILS + 1))
  fi
  if [ ! -x "$BUILT_DIR/UppBaseCheckGui" ]; then
    echo "result: test UppBaseCheckGui $c $MODE${CHECK:+ $CHECK}: skipped (build failed)"
  elif [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && [ "$CHECK" != helgrind ]; then
    step "run UppBaseCheckGui --smoke ($c${CHECK:+, $CHECK})"
    # checked runs: no accessibility bridge (dbus) or GVFS: system threads, not U++
    local quiet=(); [ -n "$CHECK" ] && quiet=(env NO_AT_BRIDGE=1 GTK_A11Y=none GIO_USE_VFS=local)
    out=$(timeout 120 "${quiet[@]}" "${run[@]}" "$BUILT_DIR/UppBaseCheckGui" --smoke 2>&1); rc=$?
    echo "$out" | grep -v '^Gdk-Message' | sed 's/^/  /'
    ub_fail
    echo "result: test UppBaseCheckGui $c $MODE${CHECK:+ $CHECK}: $([ "$rc" = 0 ] && echo ok || echo "FAILED (exit $rc)")"
    [ "$rc" = 0 ] || FAILS=$((FAILS + 1))
  else
    echo "result: test UppBaseCheckGui $c: skipped ($([ "$CHECK" = helgrind ] && echo 'helgrind: too slow for a GUI' || echo 'no display'))"
  fi
}

cmd_build() {
  local test=$1; shift
  parse_build_opts "$@"
  tree_ok "$WORK/$TREE" || die "no $TREE tree: run ./upp_basefix.sh $([ "$TREE" = patched ] && echo patch || echo pristine)"
  case $CHECK in valgrind|helgrind) command -v valgrind > /dev/null || die "valgrind is not installed" ;; esac
  [ -n "$CHECK" ] && [ "$test" = 0 ] && die "--$CHECK goes with test, not build"
  setup_umk
  local c t0; t0=$(date +%s)
  for c in $COMPILERS; do
    build_one "$c"
    [ "$test" = 1 ] && run_checks "$c"
  done
  echo "summary: $([ "$FAILS" = 0 ] && echo 'all good' || echo "$FAILS FAILED")  ($(( $(date +%s) - t0 )) s)"
  [ "$FAILS" = 0 ]
}

cmd_gui() {
  tree_ok "$WORK/patched" || die "no patched tree: run ./upp_basefix.sh pristine, then patch"
  setup_umk
  local bm log="$WORK/logs/build-gui.log"; bm=$(make_bm gcc 0)
  mkdir -p "$WORK/out/gui" "$WORK/logs"
  step "build UppBaseFixBuild with gcc (release) on the patched tree"
  "$WORK/umk/umk" "$HERE/gui,$WORK/patched/uppsrc" UppBaseFixBuild "$bm" -brsH "$WORK/out/gui/UppBaseFixBuild" > "$log" 2>&1 \
    || { grep -E 'error' "$log" | head -20; die "build failed: $log"; }
  echo "result: build UppBaseFixBuild gcc release: ok  warnings: $(grep -c 'warning:' "$log")  log: $log"
  [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] || die "no display to start it on"
  UPP_BASEFIX_HOME="$HERE" UPP_BASEFIX_WORK="$WORK" setsid -f "$WORK/out/gui/UppBaseFixBuild" > /dev/null 2>&1 < /dev/null
  step "started $WORK/out/gui/UppBaseFixBuild"
}

case "${1:-}" in
  pristine) shift; cmd_pristine "$@" ;;
  verify)   shift; cmd_verify "$@" ;;
  patch)    shift; cmd_patch ;;
  status)   shift; cmd_status "$@" ;;
  build)    shift; cmd_build 0 "$@" ;;
  test)     shift; cmd_build 1 "$@" ;;
  gui)      shift; cmd_gui ;;
  *) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
