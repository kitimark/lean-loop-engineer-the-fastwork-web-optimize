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
# The parallel jobs run in one Lake build slot, at most its width capped at the online cores at once (Lean
# Fw.Sched.LakeSlot.stage2Width, capped_stage2_with_build).
# The parallel jobs call the built binaries directly (.lake/build/bin/...), not `lake exe`, so none of them takes Lake's lock (the `lake env lean --run` jobs build nothing and take no lock).
# Every failing stage is reported (not just the first); exit non-zero if any failed. The verdict is the conjunction of the
# stage verdicts, independent of order and completion: Lean Fw.Console.LandSpeed.verdict_perm.
set -u
cd "$(dirname "$0")/.."
[ -z "${FW_SLOT_SELF_IN:-}" ] && [ -z "${CI:-}" ] && [ "${FW_SLOT_SELF:-}" != off ] && exec node ../scripts/slot-self.mjs check -- sh scripts/check.sh "$@"
[ -z "${FW_HEAVY_HELD:-}" ] && [ "${FW_HEAVY_LOCK:-}" != off ] && exec node ../scripts/heavy-lock.mjs run --kind check -- sh scripts/check.sh "$@"
. ../scripts/lake-slot-lib.sh
. ../scripts/span.sh
fails=""
serial() {  # serial <step> <cmd...>: a failing serial stage is recorded and the script goes on
  if ! span lean/check "$@"; then
    fails="$fails
  - $1"
    echo "check: FAILED stage: $1"
  fi
}
serial "grep gates" scripts/check-partial.sh
serial "check.sh one job per line" node ../scripts/lint-check-sh.mjs
serial "import check" node scripts/check-imports.mjs
lake_f=$(mktemp "${TMPDIR:-/tmp}/fwlakebuilt.XXXXXX")
export FW_LAKE_BUILT_FILE=$lake_f
span_more_file=$lake_f
if ! span lean/check "lake build" sh ../scripts/fwcore-build.sh; then
  rm -f "$lake_f"
  fails="$fails
  - lake build"
  echo "check: FAILED: $fails"
  exit 1
fi
unset FW_LAKE_BUILT_FILE
rm -f "$lake_f"

bin=.lake/build/bin
tmp=$(mktemp -d "${TMPDIR:-/tmp}/fwcheck.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM
n=0; pids=""
job() {  # job <step> <cmd...>: run in the background; output kept in $tmp/<n>.out, name in $tmp/<n>.name
  echo "$1" > "$tmp/$n.name"
  lake_slot_run span lean/check "$@" > "$tmp/$n.out" 2>&1
  pids="$pids $!"
  n=$((n + 1))
}
run_group() {
  # props lint (one registry in Fw.Spec.Incidents, rows match the ledger, properties do not name the impl), run once over
  # every lean_lib plus the test cases scripts/props-lint-cases/Adv.lean: the findings must be exactly Adv.expected.txt
  job "props lint" sh -c 'mkdir -p "$1" && cp scripts/props-lint-cases/Adv.lean "$1/" &&
    lake env lean -R "$1" -o "$1/Adv.olean" "$1/Adv.lean" &&
    { lake env .lake/build/bin/propslint "$1" Adv > "$1/out"
      if grep -q "note: not built" "$1/out"; then echo "props-lint: a lib module is not built, so it was not linted:"; grep "note: not built" "$1/out"; exit 1; fi
      if sed -n "s/^props-lint: \([a-z-]*\) \([^:]*\):.*/\1 \2/p" "$1/out" | LC_ALL=C sort | diff scripts/props-lint-cases/Adv.expected.txt -
      then echo "props-lint: the findings are exactly scripts/props-lint-cases/Adv.expected.txt (the project itself has none)"
      else echo "props-lint: findings differ from scripts/props-lint-cases/Adv.expected.txt (< expected, > found); output:"; cat "$1/out"; exit 1; fi; }' _ "$tmp/plc"
  job "sweepsgen scope" $bin/fwcore sweepsgen --scope --check ../packages/gate-breakpoints/src/scope.gen.json
  job "shard golden check" lake env lean --run scripts/ShardGolden.lean --check
  # init-cost lint (Fw.Lint.InitCost): no constant fwcore evaluates at start allocates more than the bound; the cases
  # scripts/init-cost-cases/Adv.lean and NoC.lean (built with no C file) must yield exactly Adv.expected.txt
  job "init cost lint" lake env lean scripts/InitCostLint.lean
  job "init cost lint cases" sh -c 'mkdir -p "$1" && cp scripts/init-cost-cases/Adv.lean scripts/init-cost-cases/NoC.lean "$1/" &&
    lake env lean -R "$1" -o "$1/NoC.olean" "$1/NoC.lean" &&
    lake env lean -R "$1" -o "$1/Adv.olean" -c "$1/Adv.c" "$1/Adv.lean" &&
    { printf "import Fw.Lint.InitCostScan\nimport Adv\nimport NoC\nset_option maxHeartbeats 0 in\nrun_cmd Fw.Lint.InitCostScan.scan [\`Adv, \`NoC] [\".\"]\n" > "$1/AdvLint.lean"
      lake env sh -c "cd \"\$1\" && LEAN_PATH=\"\$1:\$LEAN_PATH\" lean AdvLint.lean" _ "$1" > "$1/out" 2>&1
      if sed -n "s/^init-cost: \([a-z]*\) \([^:]*\):.*/\1 \2/p" "$1/out" | LC_ALL=C sort | diff scripts/init-cost-cases/Adv.expected.txt -
      then echo "init-cost: the findings are exactly scripts/init-cost-cases/Adv.expected.txt"
      else echo "init-cost: findings differ from scripts/init-cost-cases/Adv.expected.txt (< expected, > found); output:"; cat "$1/out"; exit 1; fi; }' _ "$tmp/icc"
  job "init cost lint scale" sh -c 'mkdir -p "$1" && cp scripts/init-cost-cases/Many.lean "$1/" &&
    lake env lean -R "$1" -o "$1/Many.olean" -c "$1/Many.c" "$1/Many.lean" &&
    { printf "import Fw.Lint.InitCostScan\nimport Many\nset_option maxHeartbeats 0 in\nrun_cmd Fw.Lint.InitCostScan.scan [\`Many] [\".\"]\n" > "$1/ManyLint.lean"
      s=$(date +%s)
      if ! lake env sh -c "cd \"\$1\" && LEAN_PATH=\"\$1:\$LEAN_PATH\" lean ManyLint.lean" _ "$1" > "$1/out" 2>&1 ||
        ! grep -q "^init-cost: 8192 start-time constants" "$1/out"
      then echo "init-cost: the lint failed over 8192 constants; output:"; cat "$1/out"; exit 1; fi
      echo "init-cost: 8192 constants linted in $(($(date +%s) - s)) s"; }' _ "$tmp/ics"
  job "contracts golden check" lake env lean --run scripts/ContractsGolden.lean --check ../packages/contracts/golden/parts/contracts.gen.json ../packages/measure-chromium/scenarios.gen.json
  job "transition-list golden check" lake env lean --run scripts/TransitionListGolden.lean --check
  job "axiom check" sh scripts/axiom-check.sh
  job "lake test" $bin/fwcore fwtest
  job "engine golden cite lint" lake env lean --run scripts/EngineCiteLint.lean
  job "port golden check" lake env lean --run scripts/PortGolden.lean --check  # golden/port/* the port digest is checked against (Fw.Port.*, Fw.Site.Assets)
  job "lakegc golden check" lake env lean --run scripts/LakeGcGolden.lean --check  # golden/ops/lakegc.jsonl (Fw.Ops.LakeGc)
  job "diskgc golden check" lake env lean --run scripts/DiskGcGolden.lean --check  # golden/ops/diskgc.jsonl (Fw.Ops.DiskGc)
  job "writes-closure golden check" lake env lean --run scripts/WritesClosureGolden.lean --check
  job "rebuild golden check" lake env lean --run scripts/RebuildGolden.lean --check  # golden/ops/rebuild.jsonl: the Lake-graph rebuild set of each sampled land equals what CI built (Fw.Ops.Rebuild)
  job "lspreap golden check" lake env lean --run scripts/ReapGolden.lean --check  # golden/ops/lspreap.jsonl (Fw.Ops.Reap)
  job "pool-caps golden check" lake env lean --run scripts/PoolCapsGolden.lean --check  # golden/ci/pool-caps.jsonl (Fw.Ci.Pool.Caps), read by scripts/ci-paths.mjs
  job "pool-key golden check" lake env lean --run scripts/PoolKeyGolden.lean --check
  job "pool-fallback golden check" lake env lean --run scripts/PoolFallbackGolden.lean --check
  job "pool-tier golden check" lake env lean --run scripts/PoolGolden.lean --check
  job "land-inputs-cost golden check" lake env lean --run scripts/LandInputsCostGolden.lean --check
  job "obs golden check" lake env lean --run scripts/ObsGolden.lean --check
  job "sup-health golden check" lake env lean --run scripts/SupHealthGolden.lean --check
  job "sup wire golden check" sh -c "printf 'import Fw.Wire.Sup\\n#eval Fw.Wire.Sup.Golden.gen [\"--check\"]\\n' | lake env lean --stdin"
  job "land-speed golden check" sh -c 'printf "import Fw.Console.LandSpeed\ndef main : IO UInt32 := do\n  if (← Fw.Console.LandSpeed.checkGolden) then return 0\n  IO.eprintln \042land-speed.jsonl differs from Fw.Console.LandSpeed.goldenText (regenerate with writeGolden)\042\n  return 1\n" > "$1/LandSpeedCheck.lean" && lake env lean --run "$1/LandSpeedCheck.lean"' _ "$tmp"
  job "ops golden check" lake env lean --run scripts/OpsGolden.lean --check  # golden/ops/*.jsonl incl. the obs life cases (Fw.Ops.Obs)
  job "oracle golden check" lake env lean --run scripts/OracleGolden.lean --check  # golden/oracle/wire.jsonl and fixtures.jsonl (Fw.Wire.Oracle.Golden)
  job "lane inputs check" lake env lean --run scripts/LaneInputs.lean --check  # Fw.Store.Lane.inputs equal the workflow_dispatch inputs of chromium-counts, webkit-sim, breakpoint-gate
  job "engine goldens check" lake env lean --run scripts/EngineGoldens.lean  # golden/engine/*.jsonl equal the Lean generators, one generator per file
  job "provider golden check" lake env lean --run scripts/ProviderGolden.lean --check  # golden/ci/provider.jsonl (Fw.Ci.Provider)
  job "codemagic golden check" lake env lean --run scripts/CodemagicGolden.lean --check  # golden/ci/codemagic.jsonl (Fw.Ci.Codemagic)
  job "overflow golden check" lake env lean --run scripts/OverflowGolden.lean --check  # golden/ci/overflow.jsonl (Fw.Ci.Overflow: which land legs overflow from GitHub to CircleCI)
  job "faithful golden check" lake env lean --run scripts/FaithfulGolden.lean --check  # golden/faithful/faithful.{verdict,comparable}.jsonl (Fw.Faithful)
  job "stage-mode golden check" lake env lean --run scripts/StageModeGolden.lean --check ../packages/contracts/golden/parts/stage-mode.jsonl
  job "checkmap golden check" lake env lean --run scripts/CheckMapGolden.lean --check
  job "workflow-lint golden check" lake env lean --run scripts/WorkflowLintGolden.lean --check
  job "touchpush golden check" lake env lean --run scripts/TouchPushGolden.lean --check ../packages/contracts/golden/measure/touch-push.jsonl
  job "pushcycle golden check" lake env lean --run scripts/PushCycleGolden.lean --check ../packages/contracts/golden/measure/push-cycle.jsonl
  job "walkbudget golden check" lake env lean --run scripts/WalkBudgetGolden.lean --check ../packages/contracts/golden/measure/walk-budget.jsonl
  job "offscreen golden check" lake env lean --run scripts/OffscreenGolden.lean --check ../packages/contracts/golden/measure/offscreen.jsonl
  job "offscreen-webkit golden check" sh -c "printf 'import Fw.Measure.OffscreenWebKitGolden\\n#eval Fw.Measure.OffscreenWebKitGolden.checkRepo\\n' | lake env lean --stdin"
  job "offscreen-windows golden check" sh -c "printf 'import Fw.Measure.OffscreenWindowsGolden\\n#eval Fw.Measure.OffscreenWindowsGolden.checkRepo\\n' | lake env lean --stdin"
  job "swipe-end golden check" sh -c "printf 'import Fw.Measure.SwipeEndGolden\\n#eval Fw.Measure.SwipeEndGolden.checkRepo\\n' | lake env lean --stdin"
  job "sim-host golden check" sh -c "printf 'import Fw.Measure.SimHostGolden\\n#eval Fw.Measure.SimHostGolden.checkRepo\\n' | lake env lean --stdin"
  job "touchlock golden check" lake env lean --run scripts/TouchLockGolden.lean --check ../packages/contracts/golden/measure/touch-lock.jsonl
  job "smooth golden check" lake env lean --run scripts/SmoothGolden.lean --check ../packages/contracts/golden/gate/smooth.jsonl
  job "exit golden check" lake env lean --run scripts/ExitGolden.lean --check ../packages/contracts/golden/gate/exit.jsonl
  job "flag-delta golden check" lake env lean --run scripts/GateFlagDeltaGolden.lean --check ../packages/contracts/golden/gate/flag-delta.jsonl
  job "replaced golden check" lake env lean --run scripts/GateReplacedGolden.lean --check ../packages/contracts/golden/gate/replaced.jsonl
  job "preset v2-proved check" sh -c "printf 'import Fw.Preset.Gen\\n#eval Fw.Preset.Gen.run [\"--check\"]\\n' | lake env lean --stdin"
  job "ci telemetry golden check" lake env lean --run scripts/TelemetryGolden.lean --check
  job "mac telemetry golden check" lake env lean --run scripts/MacTelemetryGolden.lean --check
  job "webkit-screen golden check" lake env lean --run scripts/WebkitScreenGolden.lean --check ../packages/contracts/golden/gate/webkit-screen.jsonl  # the WebKit live-resize screen vectors engines.mjs is checked against (Fw.Gate.WebkitScreen)
  job "path-pix golden check" lake env lean --run scripts/PathPixGolden.lean --check ../packages/contracts/golden/gate/path-pix.jsonl  # the pixel-cell grade, premise and Accelerated vectors (Fw.Gate.PathPix)
  job "device-session golden check" lake env lean --run scripts/DeviceSessionGolden.lean --check ../packages/contracts/golden/device/session.jsonl
  job "device-stillruns golden check" lake env lean --run scripts/StillRunsGolden.lean --check ../packages/contracts/golden/device/stillruns.jsonl
  job "device-finishruns golden check" lake env lean --run scripts/FinishRunsGolden.lean --check ../packages/contracts/golden/device/finishruns.jsonl
  job "device-sim-touch golden check" lake env lean --run scripts/SimTouchGolden.lean --check ../packages/contracts/golden/device/sim-touch.jsonl
  job "morph-end-count golden check" lake env lean --run scripts/MorphEndCountGolden.lean --check ../packages/contracts/golden/device/morph-end-count.jsonl
  job "device-sim-relaunch golden check" lake env lean --run scripts/SimRelaunchGolden.lean --check ../packages/contracts/golden/device/sim-relaunch.jsonl
  job "paint-visible golden check" lake env lean --run scripts/PaintVisibleGolden.lean --check ../packages/contracts/golden/measure/paint-visible.jsonl
  job "unthrottle golden check" sh -c "printf 'import Fw.Parts.EngineScrollUnthrottle\\n#eval Fw.Parts.EngineScrollUnthrottle.run [\"--check\"]\\n' | lake env lean --stdin"
  job "unthrottle-follow golden check" sh -c "printf 'import Fw.Parts.EngineScrollFollowGolden\\n#eval Fw.Parts.EngineScrollFollowGolden.run [\"--check\"]\\n' | lake env lean --stdin"
  job "dormant-counts golden check" sh -c "printf 'import Fw.Parts.DormantCounts\\n#eval Fw.Parts.DormantCounts.gen [\"--check\"]\\n' | lake env lean --stdin"  # the shift-dormant verdicts per engine, zone and metric from results/dormant-counts/zones.json
  job "hittest elements golden check" sh -c "printf 'import Fw.Parts.NavHitTestElements\\n#eval Fw.Parts.NavHitTestElements.gen [\"--check\"]\\n' | lake env lean --stdin"  # the hit and is-on-dark class table apps/site/src/parts/nav.hitTest/elements.golden.test.ts replays (Fw.Parts.NavHitTestElements)
  job "webkit-profile golden check" lake env lean --run scripts/WebkitProfileGolden.lean --check ../packages/contracts/golden/measure/webkit-profile.jsonl  # the zone-binned Timeline profile vectors packages/measure-webkit/src/profile/reduce.mjs is checked against (Fw.Measure.WebKitProfile)
  job "path-pix golden check" lake env lean --run scripts/PathPixGolden.lean --check ../packages/contracts/golden/gate/path-pix.jsonl
  job "device-session golden check" lake env lean --run scripts/DeviceSessionGolden.lean --check ../packages/contracts/golden/device/session.jsonl
  job "device-stillruns golden check" lake env lean --run scripts/StillRunsGolden.lean --check ../packages/contracts/golden/device/stillruns.jsonl
  job "device-throttle-parts golden check" lake env lean --run scripts/ThrottlePartsGolden.lean --check ../packages/contracts/golden/device/throttle-parts.jsonl
  job "device-phone-arms golden check" lake env lean --run scripts/PhoneArmsGolden.lean --check ../packages/contracts/golden/device/phone-arms.jsonl
  job "device-thermal golden check" lake env lean --run scripts/DeviceThermalGolden.lean --check ../packages/contracts/golden/device/thermal.jsonl
  job "device-finishruns golden check" lake env lean --run scripts/FinishRunsGolden.lean --check ../packages/contracts/golden/device/finishruns.jsonl
  job "unthrottle golden check" sh -c "printf 'import Fw.Parts.EngineScrollUnthrottle\\n#eval Fw.Parts.EngineScrollUnthrottle.run [\"--check\"]\\n' | lake env lean --stdin"
  job "webkit-profile golden check" lake env lean --run scripts/WebkitProfileGolden.lean --check ../packages/contracts/golden/measure/webkit-profile.jsonl
  job "chromium profile golden check" lake env lean --run scripts/ProfileGolden.lean --check ../packages/contracts/golden/measure/profile.jsonl
  job "device-replay golden check" lake env lean --run scripts/DeviceReplayGolden.lean --check ../packages/contracts/golden/device/replay.jsonl
  job "webkit-lag golden check" lake env lean --run scripts/WebkitLagGolden.lean --check ../packages/contracts/golden/measure/webkit-lag.jsonl
  job "wkcost golden check" lake env lean --run scripts/WkCostGolden.lean --check ../packages/contracts/golden/measure/wkcost.jsonl
  job "wkcost sums check" lake env lean --run scripts/WkCostSums.lean --check ../packages/contracts/golden/measure/wkcost-sums.jsonl
  job "census golden check" lake env lean --run scripts/CensusGolden.lean --check ../packages/contracts/golden/measure/census.jsonl
  job "stage golden check" lake env lean --run scripts/StageGolden.lean --check ../packages/contracts/golden/parts/stage.jsonl
  job "layer-opts golden check" lake env lean --run scripts/LayerOptsGolden.lean --check ../apps/site/src/registry/layer-opts.gen.ts ../packages/contracts/golden/console/layer-opts.jsonl
  job "react-root-quiet golden check" lake env lean --run scripts/ReactRootQuietGolden.lean --check ../apps/site/src/parts/engine.events/quiet.gen.ts ../packages/contracts/golden/parts/react-root-quiet.jsonl
  job "reconcile-sched golden check" lake env lean --run scripts/ReconcileSchedGolden.lean --check  # golden/console/reconcile-sched.jsonl
  job "dormant golden check" lake env lean --run scripts/MorphDormantGolden.lean --check ../packages/contracts/golden/parts/morph.mount.dormant.jsonl
  job "headgen check" lake env lean --run HeadgenMain.lean --check ../apps/site/src/head.gen.json  # the document head table (Fw.Site.Head)
  job "search golden check" lake env lean --run scripts/SearchGolden.lean --check  # the gate rewrite-arm search vectors gate-search.mjs is checked against (Fw.Gate.Search)
  job "run-cite golden check" lake env lean --run scripts/RunCiteGolden.lean --check  # the gate.runCite vectors scripts/run-cite.test.mjs replays (Fw.Gate.RunCite)
  job "premise goldens check" lake env lean --run scripts/PremiseGolden.lean --check
  job "journal-cache golden check" lake env lean --run scripts/JournalCacheGolden.lean --check  # golden/console/journal-cache.jsonl
  job "land-remote golden check" lake env lean --run scripts/LandRemoteGolden.lean --check  # golden/console/land-remote.jsonl (Fw.Console.LandRemote)
  job "engine premise golden check" lake env lean --run scripts/EnginePremiseGolden.lean --check
  job "salvage golden check" lake env lean --run scripts/SalvageGolden.lean --check
  job "exit scoped golden check" lake env lean --run scripts/ExitScopedGolden.lean --check ../packages/contracts/golden/parts/hero.exit.scoped.json
  job "exit threaded golden check" lake env lean --run scripts/ExitThreadedGolden.lean --check ../packages/contracts/golden/parts/hero-exit.threaded.jsonl
  job "exit offset golden check" sh -c "printf 'import Fw.Parts.HeroExitScrollOffset\\n#eval Fw.Parts.HeroExitScrollOffset.gen [\"--check\"]\\n' | lake env lean --stdin"
  job "timing golden check" lake env lean --run scripts/TimingGolden.lean --check
  job "state-list golden check" lake env lean --run scripts/StateListGolden.lean --check
  job "ci-state golden check" lake env lean --run scripts/CiStateGolden.lean --check
  job "attempt-inflight golden check" sh -c "printf 'import Fw.Ci.AttemptGolden\\n#eval Fw.Ci.AttemptGolden.gen [\"--check\"]\\n' | lake env lean --stdin"
  job "slot-key golden check" lake env lean --run scripts/SlotKeyGolden.lean --check
  job "heavy golden check" lake env lean --run scripts/HeavyGolden.lean --check
  job "land-legs golden check" lake env lean --run scripts/LandLegsGolden.lean --check
  job "trajectory golden check" lake env lean --run scripts/TrajectoryGolden.lean --check  # the trajectory-probe verdict vectors reduce.mjs is checked against (Fw.Gate.Trajectory)
  job "trajectory-gpu golden check" lake env lean --run scripts/TrajectoryGpuGolden.lean --check ../packages/contracts/golden/gate/trajectory-gpu.jsonl
  job "trajectory-gpu raw cells" sh -c 'd=$(mktemp -d "${TMPDIR:-/tmp}/gpuraw.XXXXXX") && trap "rm -rf $d" EXIT &&
    lake env lean --run scripts/TrajectoryGpuGolden.lean --raw ../packages/contracts/fixtures/trajectory-gpu/raw-39823047557.json ../packages/contracts/fixtures/trajectory-gpu/raw-39852684450.json ../packages/contracts/fixtures/trajectory-gpu/raw-39861846900.json > $d/lean.txt &&
    node ../packages/gate-breakpoints/src/trajectory/cells-gpu-cli.mjs raw ../packages/contracts/fixtures/trajectory-gpu/raw-39823047557.json ../packages/contracts/fixtures/trajectory-gpu/raw-39852684450.json ../packages/contracts/fixtures/trajectory-gpu/raw-39861846900.json > $d/js.txt &&
    test -s $d/lean.txt && cmp $d/lean.txt $d/js.txt'
  job "trajectory-dispatch golden check" lake env lean --run scripts/TrajectoryDispatchGolden.lean --check  # the dispatch scope vectors run-pick.ts is checked against (Fw.Gate.Trajectory.Dispatch)
  job "trajectory-colour golden check" lake env lean --run scripts/ColourGolden.lean --check ../packages/contracts/golden/gate/trajectory-colour.jsonl  # the colour readings kit.mjs is checked against (Fw.Gate.Colour)
  job "run-perm golden check" lake env lean --run scripts/RunPermGolden.lean --check ../packages/contracts/golden/gate/run-perm.jsonl  # the run-level close-gap test closegap-did.mjs is checked against (Fw.Gate.RunPerm)
  job "land-tier golden check" lake env lean --run scripts/LandTierGolden.lean --check  # golden/console/land-tier.jsonl + lean/land-filter.txt (Fw.Console.LandTier)
  job "lake-slot golden check" sh -c "printf 'import Fw.Sched.LakeSlot\\n#eval Fw.Sched.LakeSlot.gen [\"--check\"]\\n' | lake env lean --stdin"  # golden/sched/lake-slot.gen.sh, sourced by scripts/lake-slot-lib.sh
  job "sup-route golden check" sh -c "printf 'import Fw.Sup.Route\\n#eval Fw.Sup.Route.gen [\"--check\"]\\n' | lake env lean --stdin"  # golden/sup/route.jsonl (Fw.Sup.Route.routeOf)
  job "sup-adapt golden check" sh -c "printf 'import Fw.Sup.AdaptGolden\\n#eval Fw.Sup.Adapt.gen [\"--check\"]\\n' | lake env lean --stdin"  # golden/sup/adapt.jsonl (Fw.Sup.Adapt)
  job "sup-measure golden check" sh -c "printf 'import Fw.Sup.Measure\\n#eval Fw.Sup.Measure.gen [\"--check\"]\\n' | lake env lean --stdin"
  job "node-budget golden check" lake env lean --run scripts/NodeBudgetGolden.lean --check
  job "tap golden check" lake env lean --run scripts/MorphTapGolden.lean --check ../packages/contracts/golden/parts/morph-mount-tap.jsonl
  job "hero-scene-pause golden check" lake env lean --run scripts/HeroScenePauseGolden.lean --check ../packages/contracts/golden/parts/hero-scene-pause.jsonl
  job "hero-contain golden check" lake env lean --run scripts/HeroContainGolden.lean --check ../packages/contracts/golden/parts/hero-contain.jsonl
  job "nav-earn golden check" lake env lean --run scripts/NavEarnGolden.lean --check ../packages/contracts/golden/parts/nav-earn.jsonl
  job "nav-earn-webkit golden check" lake env lean --run scripts/NavEarnWebkitGolden.lean --check ../packages/contracts/golden/parts/nav.earn.webkit.jsonl
  job "nav-earn-curve golden check" lake env lean --run scripts/NavEarnCurveGolden.lean --check ../packages/contracts/golden/parts/nav.earn.curve.jsonl
  job "accent draw-one golden check" lake env lean --run scripts/AccentDrawOneGolden.lean --check ../packages/contracts/golden/parts/hero.accent.drawone.jsonl
  job "accent nolayout golden check" lake env lean --run scripts/AccentNoLayoutGolden.lean --check ../packages/contracts/golden/parts/hero.accent.nolayout.jsonl
  job "classpos golden check" lake env lean --run scripts/ClassPosGolden.lean --check ../packages/contracts/golden/parts/footprint.classpos.jsonl
  job "people-o preview golden check" lake env lean --run scripts/PeopleOPreviewGolden.lean --check ../packages/contracts/golden/parts/people-o-preview.jsonl
  job "morph-idle-none golden check" lake env lean --run scripts/MorphIdleNoneGolden.lean --check ../packages/contracts/golden/parts/morph-idle-none.jsonl
  job "morph-panel-rest golden check" lake env lean --run scripts/MorphPanelRestGolden.lean --check ../packages/contracts/golden/parts/morph.panel.rest.jsonl
  job "const-bounds-counts golden check" lake env lean --run scripts/ConstBoundsCountsGolden.lean --check ../packages/contracts/golden/parts/const-bounds-counts.jsonl ../results/const-bounds-counts/tables.md
  job "morph-columns-scale golden check" lake env lean --run scripts/MorphColumnsScaleGolden.lean --check ../packages/contracts/golden/parts/morph.columns.final-scale.jsonl
  job "morph-end golden check" lake env lean --run scripts/MorphEndGolden.lean --check ../packages/contracts/golden/parts/morph.end.jsonl
  job "morph-end-nobounce golden check" lake env lean --run scripts/MorphEndNobounceGolden.lean --check ../packages/contracts/golden/parts/morph-end-nobounce.jsonl
  job "morph-stage golden check" lake env lean --run scripts/MorphStageGolden.lean --check ../packages/contracts/golden/parts/morph-stage.jsonl
  job "combo-scroll golden check" lake env lean --run scripts/ComboScrollGolden.lean --check ../packages/contracts/golden/parts/combo-scroll.jsonl
  job "platform-sweep-pause golden check" lake env lean --run scripts/PlatformSweepPauseGolden.lean --check ../packages/contracts/golden/parts/platform-sweep-pause.jsonl
  job "platform-sweep-layer golden check" lake env lean --run scripts/PlatformSweepLayerGolden.lean --check ../packages/contracts/golden/parts/platform-sweep-layer.jsonl
  job "platform-entries-fill golden check" lake env lean --run scripts/PlatformEntriesFillGolden.lean --check ../packages/contracts/golden/parts/platform-entries-fill.jsonl
  job "platform-glint-pause golden check" lake env lean --run scripts/PlatformGlintPauseGolden.lean --check ../packages/contracts/golden/parts/platform-glint-pause.jsonl
  job "platform-faded-pause golden check" lake env lean --run scripts/PlatformFadedPauseGolden.lean --check ../packages/contracts/golden/parts/platform-faded-pause.jsonl
  job "gpu-elapsed golden check" lake env lean --run scripts/GpuElapsedGolden.lean --check ../results/gpu-safari/lane/elapsed.golden.jsonl
  job "image-arm golden check" lake env lean --run scripts/ImageArmGolden.lean --check ../packages/contracts/golden/gate/image-arm.jsonl
  job "steps golden check" lake env lean --run scripts/StepsGolden.lean --check
  job "oracle labels golden check" lake env lean --run scripts/OracleLabelsGolden.lean --check
  job "lake-cache golden check" sh -c 'printf "import Fw.Ops.LakeCache\n#eval Fw.Ops.LakeCache.gen [\"--check\"]\n" | lake env lean --stdin'
  job "land-wt golden check" sh -c 'printf "import Fw.Console.LandWt\n#eval Fw.Console.LandWt.gen [\"--check\"]\n" | lake env lean --stdin'
  job "gate-engine-timing golden check" sh -c 'printf "import Fw.Ops.GateEngineTiming\n#eval Fw.Ops.GateEngineTiming.gen [\"--check\"]\n" | lake env lean --stdin'
  job "oracle expand golden check" lake env lean --run scripts/ExpandGolden.lean --check
  job "oracle retrieve golden check" lake env lean --run scripts/RetrieveGolden.lean --check
  job "breakgen check site" sh -c "$bin/breakgen --check ../apps/site/src/breakpoints.gen.json || echo 'check: WARNING apps/site/src/breakpoints.gen.json is not the Lean output yet'"
  job "sweepsgen sweeps golden" $bin/fwcore sweepsgen --sweeps-golden --check ../packages/contracts/golden/gate/sweeps.jsonl
  job "breakgen check lean" $bin/breakgen --check Fw/Site/breakpoints.gen.json
  job "sweepsgen sweeps site" $bin/fwcore sweepsgen --sweeps --check ../apps/site/src/sweeps.gen.json
  job "golden wire replay" sh -c "LEAN_ABORT_ON_PANIC=1 $bin/fwcore < golden/wire-requests.txt | diff - golden/wire-replies.txt && echo 'check: fwcore binary reproduces golden/wire-replies.txt'"
  # the gate generators, split out of breakgen (task site-build-cache; the same bytes: Fw.Site.GenRoute.split_agrees)
  job "sweepsgen sweeps lean" $bin/fwcore sweepsgen --sweeps --check Fw/Site/sweeps.gen.json
  i=0
  for p in $pids; do
    wait "$p" || echo "$i" >> "$tmp/failed"
    i=$((i + 1))
  done
  span_more=",\"slot\":{\"width\":$LAKE_SLOT_WIDTH,\"jobs\":$n}"
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
