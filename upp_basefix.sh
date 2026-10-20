#!/usr/bin/env bash
# upp_basefix.sh: one pinned U++ (build 18619) plus our patches, built and checked.
#
#   ./upp_basefix.sh pristine [--from DIR]   clean 18619 tree in $WORK/pristine (from DIR's
#                                             uppsrc; *.orig files put back), checked vs pin/
#   ./upp_basefix.sh verify [DIR]             DIR/uppsrc against pin/uppsrc-18619.sha256
#   ./upp_basefix.sh patch                    $WORK/patched = pristine + patches/*.patch
#   ./upp_basefix.sh status [DIR]             which patches DIR/uppsrc has (default: patched)
#   ./upp_basefix.sh build [options]          build the check programs, count warnings
#        --compiler gcc|clang|both   (default both)      --release   (default debug)
#        --tree patched|pristine     (default patched)   --strict    (-Wall -Wextra)
#        --clean                     rebuild every package (umk -a)
#        --verbose                   show every file compiled (default: packages + warnings)
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
PIN=18619
SOURCE_DEFAULT=/run/media/jay/GFS/upp
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
  local from="$SOURCE_DEFAULT"
  [ "${1:-}" = --from ] && from="${2:?--from DIR}"
  tree_ok "$from" || die "no U++ tree at $from"
  step "copy $from/uppsrc -> $WORK/pristine/uppsrc (without *.orig)"
  mkdir -p "$WORK/pristine"
  rsync -a --delete --exclude='*.orig' "$from/uppsrc/" "$WORK/pristine/uppsrc/" || die "rsync failed"
  local o rel
  while IFS= read -r o; do   # a patched source keeps its originals as *.orig: put them back
    rel=${o#$from/}
    step "original back: ${rel%.orig}"
    cp -p "$o" "$WORK/pristine/${rel%.orig}"
  done < <(find "$from/uppsrc" -name '*.orig')
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
  name="$c$([ "$strict" = 1 ] && echo -strict)$([ -n "$extra" ] && echo "-$(echo "$extra" | md5sum | cut -c1-6)")"
  mkdir -p "$WORK/bm"
  local add=""
  [ "$strict" = 1 ] && add=" -Wall -Wextra"
  [ -n "$extra" ] && add="$add $extra"
  sed -e "s|^COMMON_CPP_OPTIONS = \"\\(.*\\)\";|COMMON_CPP_OPTIONS = \"\\1$add\";|" \
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
  local p rc log ours upp t0 t1 show='^-----|error:|warning:'
  [ "$VERBOSE" = 1 ] && show='.'
  for p in UppBaseCheck UppBaseCheckGui; do
    log="$WORK/logs/build-$tag-$p.log"
    step "build $p with $c ($what) on the $TREE tree"
    t0=$(date +%s)
    # +USEMALLOC: sanitizers and valgrind need the system allocator, not U++'s heap
    local cfg=""; [ -n "$CHECK" ] && cfg="+USEMALLOC"
    "$WORK/umk/umk" "$HERE/check,$WORK/$TREE/uppsrc" "$p" "$bm" $flags $cfg "$BUILT_DIR/$p" 2>&1 | tee "$log" | grep --line-buffered -E "$show" | sed -u 's/^/  /'
    rc=${PIPESTATUS[0]}; t1=$(date +%s)
    ours=$(grep -E "^$HERE/.*warning:" "$log" | sort -u | wc -l)
    upp=$(grep -E "^$WORK/$TREE/uppsrc/.*warning:" "$log" | sort -u | wc -l)
    echo "result: build $p $c $MODE: $([ "$rc" = 0 ] && echo ok || echo FAILED) $((t1 - t0)) s  warnings: ours $ours, U++ $upp (unique)  log: $log"
    [ "$rc" = 0 ] || FAILS=$((FAILS + 1))
  done
}

run_checks() {
  local c=$1 out rc
  local run=()
  case $CHECK in
    valgrind) run=(valgrind --error-exitcode=99 --leak-check=full --errors-for-leak-kinds=definite -q) ;;
    helgrind) run=(valgrind --tool=helgrind --error-exitcode=99 -q) ;;
  esac
  step "run UppBaseCheck ($c${CHECK:+, $CHECK})"
  out=$("${run[@]}" "$BUILT_DIR/UppBaseCheck" 2>&1); rc=$?
  echo "$out" | sed 's/^/  /'
  echo "result: test UppBaseCheck $c $MODE${CHECK:+ $CHECK}: $([ "$rc" = 0 ] && echo ok || echo "FAILED (exit $rc)")  $(echo "$out" | grep -E '^(passed|FAILED):' | tail -1)"
  [ "$rc" = 0 ] || FAILS=$((FAILS + 1))
  if [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && [ "$CHECK" != helgrind ]; then
    step "run UppBaseCheckGui --smoke ($c${CHECK:+, $CHECK})"
    out=$(timeout 120 "${run[@]}" "$BUILT_DIR/UppBaseCheckGui" --smoke 2>&1); rc=$?
    echo "$out" | grep -v '^Gdk-Message' | sed 's/^/  /'
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
  UPP_BASEFIX_HOME="$HERE" setsid -f "$WORK/out/gui/UppBaseFixBuild" > /dev/null 2>&1 < /dev/null
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
  *) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
