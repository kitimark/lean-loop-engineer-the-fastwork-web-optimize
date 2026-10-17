#!/bin/sh
# mutants.sh: mutation testing for the M0 Lean modules (PLAN §10.2 M0 "every M0 mutant killed", V-r, §5.4).
# Mechanical mutants (FwTest/Mutants/gen.mjs) and the hand-written design mutants (FwTest/Mutants/<Module>/*.patch,
# v1 bug classes put back) are applied to scratch copies under <repo>/.cache/mutants/ (gitignored); the real
# source tree is never written. Steps per mutant, first failure decides:
#   1 `lake build <mutated module>`   2 `lake build Fw FwTest.Mutants.Kill` (every theorem, no linking)
#   3 `lake build fwtest` + `lake test` (golden round trips)   4 `lake build fwcore` + golden/wire-replies.txt
# Verdicts: killed:proof (a theorem stops elaborating), killed:guard (a #guard fails), killed:build (another
# module's def stops type-checking), killed:test, killed:fwcore, killed:timeout; stillborn (the mutated def itself
# is ill-typed, so no test is needed); equivalent (survived, listed with a reason in FwTest/Mutants/equivalent.tsv);
# survived (a missing theorem or golden case: kill it in FwTest/Mutants/*.lean or argue equivalence).
#
# usage: scripts/mutants.sh [-j jobs] [-f Fw/X.lean]... [-p op,op] [-i ids.tsv] [-n limit] [-s strcap] [-r tag] [-b]
#   -j  parallel workers (default 3)           -f  only these files (repeatable; default: the M0 set)
#   -p  only these operators (design = the .patch mutants)
#   -i  only the (file, id) pairs of a TSV, e.g. a previous run's survivors.tsv
#   -n  first N mutants only (smoke test)       -s  at most N string-literal mutants per def (default 2)
#   -r  run tag: results in .cache/mutants/<tag>/{results,survivors}.tsv (default: run)
#   -b  own baseline .cache/mutants/base-<tag> (lets a second run go while another one uses base)
# Exit status 0 iff no mutant survived.
set -eu
cd "$(dirname "$0")/.."
LEAN=$(pwd -P)
ROOT=$(cd .. && pwd -P)
S=$ROOT/.cache/mutants
OWNBASE=0
GEN=$LEAN/FwTest/Mutants/gen.mjs
EQUIV=$LEAN/FwTest/Mutants/equivalent.tsv
M0="Fw/Console.lean Fw/Serve.lean Fw/Ops/Meter.lean Fw/Ops/PathCheck.lean Fw/Ops/SpawnGuard.lean Fw/Ops/Usage.lean Fw/Ops/Wire.lean Fw/Spec/DeviceQueue.lean Fw/Wire.lean"
# test fixtures, not logic: their contents define the goldens, so changing them is a different test, not a mutant
SKIP=boardCases,boardGolden,sampleRequests
LIBS="Fw FwTest.Mutants.Kill"
JOBS=3; FILES=""; OPS=""; IDS=""; LIMIT=0; STRCAP=2; TAG=run
while getopts j:f:p:i:n:s:r:b o; do
  case $o in
    j) JOBS=$OPTARG ;; f) FILES="$FILES $OPTARG" ;; p) OPS=$OPTARG ;; i) IDS=$OPTARG ;;
    n) LIMIT=$OPTARG ;; s) STRCAP=$OPTARG ;; r) TAG=$OPTARG ;; b) OWNBASE=1 ;; *) sed -n '2,23p' "$0"; exit 2 ;;
  esac
done
[ -n "$FILES" ] || FILES=$M0
R=$S/$TAG
B=$S/base; [ "$OWNBASE" = 0 ] || B=$S/base-$TAG
rm -rf "$R"; mkdir -p "$R"
t0=$(date +%s)

# 1. baseline: a copy of lean/ + the contract goldens, built without the shared Lake artifact cache (so mutant
#    builds never write into the toolchain cache), and green on every step the mutants are judged by.
# an own baseline starts as an APFS clone of the shared one, so only the changed files are rebuilt
[ "$OWNBASE" = 0 ] || [ -d "$B" ] || [ ! -d "$S/base" ] || cp -c -R "$S/base" "$B"
mkdir -p "$B/packages/contracts"
rsync -a --delete --exclude .lake "$LEAN/" "$B/lean/"
rsync -a --delete "$ROOT/packages/contracts/golden/" "$B/packages/contracts/golden/"
sed -i '' -e 's/^enableArtifactCache = true/enableArtifactCache = false/' "$B/lean/lakefile.toml"
echo "mutants: building the baseline in $B"
if ! (cd "$B/lean" && lake build $LIBS fwtest fwcore >"$S/base.log" 2>&1 && lake test >>"$S/base.log" 2>&1 \
    && LEAN_ABORT_ON_PANIC=1 .lake/build/bin/fwcore <golden/wire-requests.txt | diff -q - golden/wire-replies.txt >/dev/null); then
  tail -20 "$S/base.log"; echo "mutants: baseline is not green; fix it first"; exit 1
fi

# 2. the mutant list (TSV: file id op def line from to); design mutants: id patch:<Module>/<name>.patch
(cd "$B/lean" && node "$GEN" list --skip "$SKIP" --str-cap "$STRCAP" $FILES) >"$R/all.tsv"
for p in "$B"/lean/FwTest/Mutants/*/*.patch; do
  [ -e "$p" ] || continue
  f=$(sed -n 's#^+++ b/\([^	 ]*\).*#\1#p' "$p" | head -1)
  case " $FILES " in *" $f "*) ;; *) continue ;; esac
  rel=${p#"$B/lean/FwTest/Mutants/"}
  printf '%s\tpatch:%s\tdesign\t%s\t0\t-\t-\n' "$f" "$rel" "$(basename "$p" .patch)" >>"$R/all.tsv"
done
awk -F'\t' -v ops=",$OPS," -v ids="$IDS" -v lim="$LIMIT" '
  BEGIN { if (ids != "") while ((getline l < ids) > 0) { split(l, a, "\t"); want[a[1] "\t" a[2]] = 1 } }
  (ops == ",," || index(ops, "," $3 ",")) && (ids == "" || ($1 "\t" $2) in want) { if (lim > 0 && ++n > lim) exit; print }
' "$R/all.tsv" >"$R/todo.tsv"
N=$(wc -l <"$R/todo.tsv" | tr -d ' ')
echo "mutants: $N mutants, $JOBS workers"

# 3. workers: each mutant runs in a fresh APFS clone (cp -c, about 1 s) of the built baseline
step() { # $1 log, $2 limit (s), rest: command → sets rc; timeout(1) signals its whole process group (lake + lean)
  log=$1; lim=$2; shift 2
  rc=0; timeout "$lim" "$@" >"$log" 2>&1 || rc=$?
}
run_one() { # $1 scratch dir, $2 file, $3 id → prints "verdict<TAB>detail"
  w=$1; f=$2; id=$3
  case $id in
    patch:*) patch -s -p1 -d "$w/lean" <"$B/lean/FwTest/Mutants/${id#patch:}" >/dev/null ;;
    *) node "$GEN" apply "$B/lean/$f" "$id" "$w/lean/$f" ;;
  esac
  cd "$w/lean"
  mod=$(printf '%s' "$f" | sed -e 's/\.lean$//' -e 's#/#.#g')
  for s in "1 600 lake build $mod" "2 900 lake build $LIBS"; do
    set -- $s; n=$1; lim=$2; shift 2
    step "$w/m$n.log" "$lim" "$@"
    if [ $rc = 124 ]; then printf 'killed:timeout\t%s\n' "$*"; return; fi
    if [ $rc != 0 ]; then node "$GEN" classify "$w/m$n.log" "$w/lean" "$f"; return; fi
  done
  step "$w/m3.log" 900 lake build fwtest
  if [ $rc != 0 ]; then printf 'killed:%s\tlake build fwtest (rc %s)\n' "$([ $rc = 124 ] && echo timeout || echo build)" "$rc"; return; fi
  step "$w/m3.log" 600 lake test
  if [ $rc = 124 ]; then printf 'killed:timeout\tlake test\n'; return; fi
  if [ $rc != 0 ]; then
    printf 'killed:test\t%s\n' "$(grep -i 'fail\|mismatch\|differ\|error\|panic' "$w/m3.log" | head -1 | cut -c1-120 | tr '\t' ' ')"; return
  fi
  step "$w/m4.log" 900 lake build fwcore
  if [ $rc != 0 ]; then printf 'killed:build\tlake build fwcore (rc %s)\n' "$rc"; return; fi
  rc=0; LEAN_ABORT_ON_PANIC=1 timeout 120 .lake/build/bin/fwcore <golden/wire-requests.txt >"$w/m4.out" 2>/dev/null || rc=$?
  if [ $rc = 124 ]; then printf 'killed:timeout\tfwcore\n'; return; fi
  if [ $rc != 0 ] || ! diff -q "$w/m4.out" golden/wire-replies.txt >/dev/null; then
    printf 'killed:fwcore\tgolden/wire-replies.txt differs (rc %s)\n' "$rc"; return
  fi
  printf 'survived\t-\n'
}
worker() { # $1 index
  w=$R/w$1
  : >"$R/w$1.tsv"
  awk -v k="$1" -v j="$JOBS" 'NR % j == k' "$R/todo.tsv" | while IFS="$(printf '\t')" read -r f id op def line from to; do
    s=$(date +%s)
    rm -rf "$w"; cp -c -R "$B" "$w"
    v=$(run_one "$w" "$f" "$id")
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$v" "$(($(date +%s) - s))" "$f" "$id" "$op" "$def" "$line" "$from" "$to" >>"$R/w$1.tsv"
  done
  rm -rf "$w"
}
k=0; pids=""
while [ $k -lt "$JOBS" ]; do worker $k & pids="$pids $!"; k=$((k + 1)); done
trap 'kill $pids 2>/dev/null' INT TERM
wait

# 4. results: verdict detail secs file id op def line from to; survivors listed in equivalent.tsv become `equivalent`
cat "$R"/w*.tsv | awk -F'\t' -v OFS='\t' -v eq="$EQUIV" '
  BEGIN { while ((getline l < eq) > 0) { if (l ~ /^#/) continue; split(l, a, "\t"); e[a[1] "\t" a[2]] = a[3] } }
  { if ($1 == "survived" && ($4 "\t" $5) in e) { $1 = "equivalent"; $2 = e[$4 "\t" $5] } print }
' | sort -t"$(printf '\t')" -k4,4 -k8,8n >"$R/results.tsv"
awk -F'\t' -v OFS='\t' '$1 == "survived" { print $4, $5, $6, $7, $8, $9, $10 }' "$R/results.tsv" >"$R/survivors.tsv"
echo "mutants: per module (killed = proof+guard+build+test+fwcore+timeout)"
printf '%-26s %5s %6s %5s %5s %5s %4s %6s %4s %9s %5s %8s\n' module all killed proof guard build test fwcore time stillborn equiv survived
awk -F'\t' '
  { m = $4; t[m]++; split($1, v, ":"); if (v[1] == "killed") { k[m]++; by[m "," v[2]]++ } else c[m "," $1]++ }
  END { for (m in t) printf "%-26s %5d %6d %5d %5d %5d %4d %6d %4d %9d %5d %8d\n", m, t[m], k[m], by[m ",proof"], by[m ",guard"], by[m ",build"], by[m ",test"], by[m ",fwcore"], by[m ",timeout"], c[m ",stillborn"], c[m ",equivalent"], c[m ",survived"] }
' "$R/results.tsv" | sort
echo "mutants: $(wc -l <"$R/survivors.tsv" | tr -d ' ') survived; $R/results.tsv, $R/survivors.tsv; $(($(date +%s) - t0)) s"
[ ! -s "$R/survivors.tsv" ]
