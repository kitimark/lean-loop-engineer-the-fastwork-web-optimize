#!/bin/sh
set -u
cd "$(dirname "$0")/.."
[ -z "${FW_SLOT_HELD:-}" ] && [ -z "${CI:-}" ] && [ "${FW_SLOT_SELF:-}" != off ] && exec node ../scripts/slot-self.mjs check -- sh scripts/check.sh "$@"
[ -z "${FW_HEAVY_HELD:-}" ] && [ "${FW_HEAVY_LOCK:-}" != off ] && exec node ../scripts/heavy-lock.mjs run --kind check -- sh scripts/check.sh "$@"
. ../scripts/lake-slot-lib.sh
. ../scripts/span.sh
fails=""
serial() {
  if ! span lean/check "$@"; then
    fails="$fails
  - $1"
    echo "check: FAILED stage: $1"
  fi
}
serial "grep gates" scripts/check-partial.sh
serial "import check" node scripts/check-imports.mjs
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
job() {
  echo "$1" > "$tmp/$n.name"
  lake_slot_run span lean/check "$@" > "$tmp/$n.out" 2>&1
  pids="$pids $!"
  n=$((n + 1))
}
run_group() {
  job "props lint" sh -c 'mkdir -p "$1" && cp scripts/props-lint-cases/Adv.lean "$1/" &&
    lake env lean -R "$1" -o "$1/Adv.olean" "$1/Adv.lean" &&
    { lake env .lake/build/bin/propslint "$1" Adv > "$1/out"
      if grep -q "note: not built" "$1/out"; then echo "props-lint: a lib module is not built, so it was not linted:"; grep "note: not built" "$1/out"; exit 1; fi
      if sed -n "s/^props-lint: \([a-z-]*\) \([^:]*\):.*/\1 \2/p" "$1/out" | LC_ALL=C sort | diff scripts/props-lint-cases/Adv.expected.txt -
      then echo "props-lint: the findings are exactly scripts/props-lint-cases/Adv.expected.txt (the project itself has none)"
      else echo "props-lint: findings differ from scripts/props-lint-cases/Adv.expected.txt (< expected, > found); output:"; cat "$1/out"; exit 1; fi; }' _ "$tmp/plc"
  job "sweepsgen scope" $bin/fwcore sweepsgen --scope --check ../packages/gate-breakpoints/src/scope.gen.json
  job "shard golden check" lake env lean --run scripts/ShardGolden.lean --check
  job "init cost lint" lake env lean scripts/InitCostLint.lean
  job "init cost lint cases" sh -c 'mkdir -p "$1" && cp scripts/init-cost-cases/Adv.lean scripts/init-cost-cases/NoC.lean "$1/" &&
    lake env lean -R "$1" -o "$1/NoC.olean" "$1/NoC.lean" &&
    lake env lean -R "$1" -o "$1/Adv.olean" -c "$1/Adv.c" "$1/Adv.lean" &&
    { printf "import Fw.Lint.InitCostScan\nimport Adv\nimport NoC\nset_option maxHeartbeats 0 in\nrun_cmd Fw.Lint.InitCostScan.scan [\`Adv, \`NoC] [\".\"]\n" > "$1/AdvLint.lean"
      lake env sh -c "cd \"\$1\" && LEAN_PATH=\"\$1:\$LEAN_PATH\" lean AdvLint.lean" _ "$1" > "$1/out" 2>&1
      if sed -n "s/^init-cost: \([a-z]*\) \([^:]*\):.*/\1 \2/p" "$1/out" | LC_ALL=C sort | diff scripts/init-cost-cases/Adv.expected.txt -
      then echo "init-cost: the findings are exactly scripts/init-cost-cases/Adv.expected.txt"
      else echo "init-cost: findings differ from scripts/init-cost-cases/Adv.expected.txt (< expected, > found); output:"; cat "$1/out"; exit 1; fi; }' _ "$tmp/icc"
  job "contracts golden check" lake env lean --run scripts/ContractsGolden.lean --check ../packages/contracts/golden/parts/contracts.gen.json ../packages/measure-chromium/scenarios.gen.json
  job "axiom check" sh scripts/axiom-check.sh
  job "lake test" $bin/fwcore fwtest
  job "engine golden cite lint" lake env lean --run scripts/EngineCiteLint.lean
  job "port golden check" lake env lean --run scripts/PortGolden.lean --check
  job "lakegc golden check" lake env lean --run scripts/LakeGcGolden.lean --check
  job "diskgc golden check" lake env lean --run scripts/DiskGcGolden.lean --check
  job "rebuild golden check" lake env lean --run scripts/RebuildGolden.lean --check
  job "lspreap golden check" lake env lean --run scripts/ReapGolden.lean --check
  job "pool-caps golden check" lake env lean --run scripts/PoolCapsGolden.lean --check
  job "pool-key golden check" lake env lean --run scripts/PoolKeyGolden.lean --check
  job "pool-fallback golden check" lake env lean --run scripts/PoolFallbackGolden.lean --check
  job "pool-tier golden check" lake env lean --run scripts/PoolGolden.lean --check
  job "obs golden check" lake env lean --run scripts/ObsGolden.lean --check
  job "sup-health golden check" lake env lean --run scripts/SupHealthGolden.lean --check
  job "sup wire golden check" sh -c "printf 'import Fw.Wire.Sup\\n#eval Fw.Wire.Sup.Golden.gen [\"--check\"]\\n' | lake env lean --stdin"
  job "land-speed golden check" sh -c 'printf "import Fw.Console.LandSpeed\ndef main : IO UInt32 := do\n  if (← Fw.Console.LandSpeed.checkGolden) then return 0\n  IO.eprintln \042land-speed.jsonl differs from Fw.Console.LandSpeed.goldenText (regenerate with writeGolden)\042\n  return 1\n" > "$1/LandSpeedCheck.lean" && lake env lean --run "$1/LandSpeedCheck.lean"' _ "$tmp"
  job "ops golden check" lake env lean --run scripts/OpsGolden.lean --check
  job "oracle golden check" lake env lean --run scripts/OracleGolden.lean --check
  job "lane inputs check" lake env lean --run scripts/LaneInputs.lean --check
  job "engine goldens check" lake env lean --run scripts/EngineGoldens.lean
  job "provider golden check" lake env lean --run scripts/ProviderGolden.lean --check
  job "codemagic golden check" lake env lean --run scripts/CodemagicGolden.lean --check
  job "workflow-lint golden check" lake env lean --run scripts/WorkflowLintGolden.lean --check
  job "overflow golden check" lake env lean --run scripts/OverflowGolden.lean --check
  job "faithful golden check" lake env lean --run scripts/FaithfulGolden.lean --check
  job "stage-mode golden check" lake env lean --run scripts/StageModeGolden.lean --check ../packages/contracts/golden/parts/stage-mode.jsonl
  job "checkmap golden check" lake env lean --run scripts/CheckMapGolden.lean --check
  job "smooth golden check" lake env lean --run scripts/SmoothGolden.lean --check ../packages/contracts/golden/gate/smooth.jsonl
  job "exit golden check" lake env lean --run scripts/ExitGolden.lean --check ../packages/contracts/golden/gate/exit.jsonl
  job "preset v2-proved check" sh -c "printf 'import Fw.Preset.Gen\\n#eval Fw.Preset.Gen.run [\"--check\"]\\n' | lake env lean --stdin"
  job "ci telemetry golden check" lake env lean --run scripts/TelemetryGolden.lean --check
  job "mac telemetry golden check" lake env lean --run scripts/MacTelemetryGolden.lean --check
  job "webkit-screen golden check" lake env lean --run scripts/WebkitScreenGolden.lean --check ../packages/contracts/golden/gate/webkit-screen.jsonl
  job "path-pix golden check" lake env lean --run scripts/PathPixGolden.lean --check ../packages/contracts/golden/gate/path-pix.jsonl
  job "device-session golden check" lake env lean --run scripts/DeviceSessionGolden.lean --check ../packages/contracts/golden/device/session.jsonl
  job "device-stillruns golden check" lake env lean --run scripts/StillRunsGolden.lean --check ../packages/contracts/golden/device/stillruns.jsonl
  job "webkit-profile golden check" lake env lean --run scripts/WebkitProfileGolden.lean --check ../packages/contracts/golden/measure/webkit-profile.jsonl
  job "device-replay golden check" lake env lean --run scripts/DeviceReplayGolden.lean --check ../packages/contracts/golden/device/replay.jsonl
  job "webkit-lag golden check" lake env lean --run scripts/WebkitLagGolden.lean --check ../packages/contracts/golden/measure/webkit-lag.jsonl
  job "wkcost golden check" lake env lean --run scripts/WkCostGolden.lean --check ../packages/contracts/golden/measure/wkcost.jsonl
  job "census golden check" lake env lean --run scripts/CensusGolden.lean --check ../packages/contracts/golden/measure/census.jsonl
  job "stage golden check" lake env lean --run scripts/StageGolden.lean --check ../packages/contracts/golden/parts/stage.jsonl
  job "layer-opts golden check" lake env lean --run scripts/LayerOptsGolden.lean --check ../apps/site/src/registry/layer-opts.gen.ts ../packages/contracts/golden/console/layer-opts.jsonl
  job "reconcile-sched golden check" lake env lean --run scripts/ReconcileSchedGolden.lean --check
  job "dormant golden check" lake env lean --run scripts/MorphDormantGolden.lean --check ../packages/contracts/golden/parts/morph.mount.dormant.jsonl
  job "headgen check" lake env lean --run HeadgenMain.lean --check ../apps/site/src/head.gen.json
  job "search golden check" lake env lean --run scripts/SearchGolden.lean --check
  job "run-cite golden check" lake env lean --run scripts/RunCiteGolden.lean --check
  job "premise goldens check" lake env lean --run scripts/PremiseGolden.lean --check
  job "journal-cache golden check" lake env lean --run scripts/JournalCacheGolden.lean --check
  job "land-remote golden check" lake env lean --run scripts/LandRemoteGolden.lean --check
  job "engine premise golden check" lake env lean --run scripts/EnginePremiseGolden.lean --check
  job "salvage golden check" lake env lean --run scripts/SalvageGolden.lean --check
  job "exit scoped golden check" lake env lean --run scripts/ExitScopedGolden.lean --check ../packages/contracts/golden/parts/hero.exit.scoped.json
  job "exit threaded golden check" lake env lean --run scripts/ExitThreadedGolden.lean --check ../packages/contracts/golden/parts/hero-exit.threaded.jsonl
  job "timing golden check" lake env lean --run scripts/TimingGolden.lean --check
  job "slot-key golden check" lake env lean --run scripts/SlotKeyGolden.lean --check
  job "heavy golden check" lake env lean --run scripts/HeavyGolden.lean --check
  job "land-legs golden check" lake env lean --run scripts/LandLegsGolden.lean --check
  job "trajectory golden check" lake env lean --run scripts/TrajectoryGolden.lean --check
  job "trajectory-gpu golden check" lake env lean --run scripts/TrajectoryGpuGolden.lean --check ../packages/contracts/golden/gate/trajectory-gpu.jsonl
  job "trajectory-dispatch golden check" lake env lean --run scripts/TrajectoryDispatchGolden.lean --check
  job "trajectory-colour golden check" lake env lean --run scripts/ColourGolden.lean --check ../packages/contracts/golden/gate/trajectory-colour.jsonl
  job "run-perm golden check" lake env lean --run scripts/RunPermGolden.lean --check ../packages/contracts/golden/gate/run-perm.jsonl
  job "land-tier golden check" lake env lean --run scripts/LandTierGolden.lean --check
  job "lake-slot golden check" sh -c "printf 'import Fw.Sched.LakeSlot\\n#eval Fw.Sched.LakeSlot.gen [\"--check\"]\\n' | lake env lean --stdin"
  job "sup-route golden check" sh -c "printf 'import Fw.Sup.Route\\n#eval Fw.Sup.Route.gen [\"--check\"]\\n' | lake env lean --stdin"
  job "sup-adapt golden check" sh -c "printf 'import Fw.Sup.AdaptGolden\\n#eval Fw.Sup.Adapt.gen [\"--check\"]\\n' | lake env lean --stdin"
  job "sup-measure golden check" sh -c "printf 'import Fw.Sup.Measure\\n#eval Fw.Sup.Measure.gen [\"--check\"]\\n' | lake env lean --stdin"  job "node-budget golden check" lake env lean --run scripts/NodeBudgetGolden.lean --check
  job "tap golden check" lake env lean --run scripts/MorphTapGolden.lean --check ../packages/contracts/golden/parts/morph-mount-tap.jsonl
  job "hero-scene-pause golden check" lake env lean --run scripts/HeroScenePauseGolden.lean --check ../packages/contracts/golden/parts/hero-scene-pause.jsonl
  job "nav-earn golden check" lake env lean --run scripts/NavEarnGolden.lean --check ../packages/contracts/golden/parts/nav-earn.jsonl
  job "accent draw-one golden check" lake env lean --run scripts/AccentDrawOneGolden.lean --check ../packages/contracts/golden/parts/hero.accent.drawone.jsonl
  job "people-o preview golden check" lake env lean --run scripts/PeopleOPreviewGolden.lean --check ../packages/contracts/golden/parts/people-o-preview.jsonl
  job "image-arm golden check" lake env lean --run scripts/ImageArmGolden.lean --check ../packages/contracts/golden/gate/image-arm.jsonl
  job "steps golden check" lake env lean --run scripts/StepsGolden.lean --check
  job "oracle labels golden check" lake env lean --run scripts/OracleLabelsGolden.lean --check
  job "oracle expand golden check" lake env lean --run scripts/ExpandGolden.lean --check
  job "oracle retrieve golden check" lake env lean --run scripts/RetrieveGolden.lean --check
  job "breakgen check site" sh -c "$bin/breakgen --check ../apps/site/src/breakpoints.gen.json || echo 'check: WARNING apps/site/src/breakpoints.gen.json is not the Lean output yet'"
  job "sweepsgen sweeps golden" $bin/fwcore sweepsgen --sweeps-golden --check ../packages/contracts/golden/gate/sweeps.jsonl
  job "breakgen check lean" $bin/breakgen --check Fw/Site/breakpoints.gen.json
  job "sweepsgen sweeps site" $bin/fwcore sweepsgen --sweeps --check ../apps/site/src/sweeps.gen.json
  job "golden wire replay" sh -c "LEAN_ABORT_ON_PANIC=1 $bin/fwcore < golden/wire-requests.txt | diff - golden/wire-replies.txt && echo 'check: fwcore binary reproduces golden/wire-replies.txt'"
  job "sweepsgen sweeps lean" $bin/fwcore sweepsgen --sweeps --check Fw/Site/sweeps.gen.json
  i=0
  for p in $pids; do
    wait "$p" || echo "$i" >> "$tmp/failed"
    i=$((i + 1))
  done
}
lake_slot_hold ..
lake_slot_gate "$tmp/gate"
span lean/check "parallel group" run_group
lake_slot_release

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
