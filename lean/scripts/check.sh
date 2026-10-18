#!/bin/sh
# All lean/ gates (TL0) as a DAG (research/notes/2026/10-18-land-speed.md, P2):
#   serial   grep gates -> import check -> scripts/fwcore-build.sh (lake build + the build record; proofs + #guard; also builds fwtest)
#   parallel math-view lint | fwtest (golden round trips) | golden wire replay (real fwcore binary, LEAN_ABORT_ON_PANIC=1)
#            | breakgen checks x2, sweepsgen checks x4 (generated JSON equals the Lean output)
#            | engine golden cite lint (every golden/engine row cites a premise, Fw.Ops.Premise.citeLint; m175)
#            | premise goldens check (golden/ops/premise.jsonl and wktr-lane.jsonl equal the Lean output)
#            | checkmap golden check (golden/ops/checkmap.jsonl equals the Lean output; Fw.Ops.CheckMap)
#            | context lint, warn-only (Fw.Lint.Context; golden in Fw.Ops.Golden; docs/team/tools/context-lint.md)
# The parallel jobs call the built binaries directly (.lake/build/bin/...), not `lake exe`, so none of them takes Lake's lock.
# Every failing stage is reported (not just the first); exit non-zero if any failed. The verdict is the conjunction of the
# stage verdicts, independent of order and completion: Lean Fw.Console.LandSpeed.verdict_perm.
set -u
cd "$(dirname "$0")/.."
. ../scripts/span.sh  # span <tool> <step> <cmd...>: one timing line per stage in .fw-console/timings.jsonl (docs/team/tools/timings.md)
fails=""
serial() {  # serial <step> <cmd...>: a failing serial stage is recorded and the script goes on
  if ! span lean/check "$@"; then
    fails="$fails
  - $1"
    echo "check: FAILED stage: $1"
  fi
}
serial "grep gates" scripts/check-partial.sh
serial "import check" node scripts/check-imports.mjs  # every Fw module is imported by a root, none twice in Fw.lean (the union merge can repeat a line)
# the parallel stages read the products of lake build, so a failed build ends the run here
if ! span lean/check "lake build" sh -c 'sh ../scripts/fwcore-build.sh && lake build fwtest'; then
  fails="$fails
  - lake build"
  echo "check: FAILED: $fails"
  exit 1
fi

bin=.lake/build/bin
tmp=$(mktemp -d "${TMPDIR:-/tmp}/fwcheck.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM
n=0; pids=""
job() {  # job <step> <cmd...>: run in the background; output kept in $tmp/<n>.out, name in $tmp/<n>.name
  echo "$1" > "$tmp/$n.name"
  ( span lean/check "$@" ) > "$tmp/$n.out" 2>&1 &
  pids="$pids $!"
  n=$((n + 1))
}
run_group() {
  job "mathview lint" scripts/mathview-cached.sh   # lint; replayed from .lake/mathview-cache/ when the sources are unchanged
  job "lake test" $bin/fwtest
  job "golden wire replay" sh -c "LEAN_ABORT_ON_PANIC=1 $bin/fwcore < golden/wire-requests.txt | diff - golden/wire-replies.txt && echo 'check: fwcore binary reproduces golden/wire-replies.txt'"
  job "breakgen check lean" $bin/breakgen --check Fw/Site/breakpoints.gen.json
  job "breakgen check site" sh -c "$bin/breakgen --check ../apps/site/src/breakpoints.gen.json || echo 'check: WARNING apps/site/src/breakpoints.gen.json is not the Lean output yet'"
  # the gate generators, split out of breakgen (task site-build-cache; the same bytes: Fw.Site.GenRoute.split_agrees)
  job "sweepsgen sweeps lean" $bin/sweepsgen --sweeps --check Fw/Site/sweeps.gen.json
  job "sweepsgen sweeps site" $bin/sweepsgen --sweeps --check ../apps/site/src/sweeps.gen.json
  job "sweepsgen sweeps golden" $bin/sweepsgen --sweeps-golden --check ../packages/contracts/golden/gate/sweeps.jsonl
  job "sweepsgen scope" $bin/sweepsgen --scope --check ../packages/gate-breakpoints/src/scope.gen.json
  job "engine golden cite lint" lake env lean --run scripts/EngineCiteLint.lean  # `lake env` builds nothing and takes no lock
  job "premise goldens check" lake env lean --run scripts/PremiseGolden.lean --check
  job "engine premise golden check" lake env lean --run scripts/EnginePremiseGolden.lean --check
  job "checkmap golden check" lake env lean --run scripts/CheckMapGolden.lean --check  # golden/ops/checkmap.jsonl (Fw.Ops.CheckMap)
  job "context lint (warn-only)" node ../scripts/context-lint.mjs  # exits 0 on findings until the lead makes it --strict
  i=0
  for p in $pids; do
    wait "$p" || echo "$i" >> "$tmp/failed"
    i=$((i + 1))
  done
}
span lean/check "parallel group" run_group

i=0
while [ "$i" -lt "$n" ]; do
  if grep -qx "$i" "$tmp/failed" 2>/dev/null; then
    fails="$fails
  - $(cat "$tmp/$i.name")"
    echo "check: FAILED stage: $(cat "$tmp/$i.name")"
    cat "$tmp/$i.out"
  else
    grep -v '^$' "$tmp/$i.out" | tail -3
  fi
  i=$((i + 1))
done
if [ -n "$fails" ]; then echo "check: FAILED: $fails"; exit 1; fi
echo "check: all lean/ gates green"
