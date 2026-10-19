#!/bin/sh
# All lean/ gates (TL0) as a DAG (research/notes/2026/10-18-land-speed.md, P2):
#   serial   grep gates -> import check -> scripts/fwcore-build.sh (lake build + strip + the build record; proofs + #guard)
#   parallel axiom check | fwcore fwtest (golden round trips) | golden wire replay (real fwcore binary, LEAN_ABORT_ON_PANIC=1)
#            | breakgen checks x2, fwcore sweepsgen checks x4 (generated JSON equals the Lean output)
#            | engine golden cite lint (every golden/engine row cites a premise, Fw.Ops.Premise.citeLint; m175)
#            | engine goldens check (every golden/engine/*.jsonl equals its Lean generator; scripts/EngineGoldens.lean)
#            | premise goldens check (golden/ops/premise.jsonl and wktr-lane.jsonl equal the Lean output)
#            | checkmap golden check (golden/ops/checkmap.jsonl equals the Lean output; Fw.Ops.CheckMap)
#            | headgen check (the document head table equals the Lean output; Fw.Site.Head)
#            | preset v2-proved check (golden/preset/* and the site preset equal Fw.Preset.Gen.run on the findings ledger)
# The parallel jobs call the built binaries directly (.lake/build/bin/...), not `lake exe`, so none of them takes Lake's lock (the `lake env lean --run` jobs build nothing and take no lock).
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
if ! span lean/check "lake build" sh ../scripts/fwcore-build.sh; then
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
  job "axiom check" sh scripts/axiom-check.sh
  job "lake test" $bin/fwcore fwtest
  job "golden wire replay" sh -c "LEAN_ABORT_ON_PANIC=1 $bin/fwcore < golden/wire-requests.txt | diff - golden/wire-replies.txt && echo 'check: fwcore binary reproduces golden/wire-replies.txt'"
  job "breakgen check lean" $bin/breakgen --check Fw/Site/breakpoints.gen.json
  job "breakgen check site" sh -c "$bin/breakgen --check ../apps/site/src/breakpoints.gen.json || echo 'check: WARNING apps/site/src/breakpoints.gen.json is not the Lean output yet'"
  job "headgen check" lake env lean --run HeadgenMain.lean --check ../apps/site/src/head.gen.json  # the document head table (Fw.Site.Head)
  # the gate generators, split out of breakgen (task site-build-cache; the same bytes: Fw.Site.GenRoute.split_agrees)
  job "sweepsgen sweeps lean" $bin/fwcore sweepsgen --sweeps --check Fw/Site/sweeps.gen.json
  job "sweepsgen sweeps site" $bin/fwcore sweepsgen --sweeps --check ../apps/site/src/sweeps.gen.json
  job "sweepsgen sweeps golden" $bin/fwcore sweepsgen --sweeps-golden --check ../packages/contracts/golden/gate/sweeps.jsonl
  job "sweepsgen scope" $bin/fwcore sweepsgen --scope --check ../packages/gate-breakpoints/src/scope.gen.json
  job "engine golden cite lint" lake env lean --run scripts/EngineCiteLint.lean  # `lake env` builds nothing and takes no lock
  job "premise goldens check" lake env lean --run scripts/PremiseGolden.lean --check
  job "engine premise golden check" lake env lean --run scripts/EnginePremiseGolden.lean --check
  job "engine goldens check" lake env lean --run scripts/EngineGoldens.lean  # golden/engine/*.jsonl equal the Lean generators, one generator per file
  job "checkmap golden check" lake env lean --run scripts/CheckMapGolden.lean --check  # golden/ops/checkmap.jsonl (Fw.Ops.CheckMap)
  job "shard golden check" lake env lean --run scripts/ShardGolden.lean --check
  job "exit golden check" lake env lean --run scripts/ExitGolden.lean --check ../packages/contracts/golden/gate/exit.jsonl  # the exit verdict vectors cli.mjs is checked against (Fw.Gate.Exit)
  job "search golden check" lake env lean --run scripts/SearchGolden.lean --check  # the gate rewrite-arm search vectors gate-search.mjs is checked against (Fw.Gate.Search)
  job "contracts golden check" lake env lean --run scripts/ContractsGolden.lean --check ../packages/contracts/golden/parts/contracts.gen.json ../packages/measure-chromium/scenarios.gen.json  # part contract rows + per-part profiles (Fw.Parts.Contract)
  job "exit scoped golden check" lake env lean --run scripts/ExitScopedGolden.lean --check ../packages/contracts/golden/parts/hero.exit.scoped.json  # hero.exit:scoped reader list, inherit chain and units (Fw.Parts.HeroExitOpt)
  job "stage golden check"lake env lean --run scripts/StageGolden.lean --check ../packages/contracts/golden/parts/stage.jsonl  # the ?only= stage plans the site is checked against (Fw.Site.Stage)
  job "port golden check" lake env lean --run scripts/PortGolden.lean --check  # golden/port/* the port digest is checked against (Fw.Port.*, Fw.Site.Assets)
  job "stage-mode golden check" lake env lean --run scripts/StageModeGolden.lean --check ../packages/contracts/golden/parts/stage-mode.jsonl  # the part-page plan, accept and read decisions the Chromium driver is checked against (Fw.Site.StageMode)
  job "lakegc golden check" lake env lean --run scripts/LakeGcGolden.lean --check  # golden/ops/lakegc.jsonl (Fw.Ops.LakeGc)
  job "preset v2-proved check" sh -c "printf 'import Fw.Preset.Gen\\n#eval Fw.Preset.Gen.run [\"--check\"]\\n' | lake env lean --stdin"  # regenerates the v2-proved preset files from the findings ledger and the parts; any byte difference fails (Fw.Preset.Gen.run)
  job "salvage golden check" lake env lean --run scripts/SalvageGolden.lean --check  # golden/ops/salvage.jsonl (Fw.Ops.Salvage)
  job "obs golden check" lake env lean --run scripts/ObsGolden.lean --check  # golden/obs/health.jsonl and backoff.jsonl (Fw.Obs)
  job "timing golden check" lake env lean --run scripts/TimingGolden.lean --check  # golden/obs/timing.jsonl (Fw.Obs.Timing)
  job "ops golden check" lake env lean --run scripts/OpsGolden.lean --check  # golden/ops/*.jsonl incl. the obs life cases (Fw.Ops.Obs)
  job "land-tier golden check" lake env lean --run scripts/LandTierGolden.lean --check  # golden/console/land-tier.jsonl + lean/land-filter.txt (Fw.Console.LandTier)
  job "reconcile-sched golden check" lake env lean --run scripts/ReconcileSchedGolden.lean --check  # golden/console/reconcile-sched.jsonl
  job "faithful golden check" lake env lean --run scripts/FaithfulGolden.lean --check  # golden/faithful/faithful.{verdict,comparable}.jsonl (Fw.Faithful)
  # props lint (one registry in Fw.Spec.Incidents, rows match the ledger, properties do not name the impl), run once over
  # every lean_lib plus the test cases scripts/props-lint-cases/Adv.lean: the findings must be exactly Adv.expected.txt
  job "props lint" sh -c 'mkdir -p "$1" && cp scripts/props-lint-cases/Adv.lean "$1/" &&
    lake env lean -R "$1" -o "$1/Adv.olean" "$1/Adv.lean" &&
    { lake env lean --run scripts/PropsLint.lean "$1" Adv > "$1/out"
      if grep -q "note: not built" "$1/out"; then echo "props-lint: a lib module is not built, so it was not linted:"; grep "note: not built" "$1/out"; exit 1; fi
      if sed -n "s/^props-lint: \([a-z-]*\) \([^:]*\):.*/\1 \2/p" "$1/out" | LC_ALL=C sort | diff scripts/props-lint-cases/Adv.expected.txt -
      then echo "props-lint: the findings are exactly scripts/props-lint-cases/Adv.expected.txt (the project itself has none)"
      else echo "props-lint: findings differ from scripts/props-lint-cases/Adv.expected.txt (< expected, > found); output:"; cat "$1/out"; exit 1; fi; }' _ "$tmp/plc"
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
