import Fw.Spec.Frames
import Fw.Spec.Verdict
import Fw.Spec.Null
import Fw.Spec.Lease
import Fw.Spec.Flags
import Fw.Spec.Stage
import Fw.Spec.Cost
import Fw.Spec.Screen
import Fw.Spec.DeviceQueue
import Fw.Spec.ArtifactKey
import Fw.Console
import Fw.Board
import Fw.Wire
import Fw.Serve
import Fw.Site.Breakpoints
import Fw.Site.BreakpointFacts
import Fw.Site.BreakpointMatrix
import Fw.Site.BreakpointGen
import Fw.Site.Reference
import Fw.Parts.EngineScroll
import Fw.Parts.Contract
import Fw.Parts.NavHitTest
import Fw.Parts.NavHitTestOpt
import Fw.Parts.HeroCountdown
import Fw.Parts.HeroCountdownOpt
import Fw.Parts.HeroExit
import Fw.Parts.MorphTween
import Fw.Parts.MorphPanel
import Fw.Parts.Nav
import Fw.Parts.NavLangMenu
import Fw.Parts.NavGolden
import Fw.Parts.Commission
import Fw.Parts.CommissionTyping
import Fw.Parts.CommissionGolden
import Fw.Parts.Bezier
import Fw.Parts.OverlayDrawer
import Fw.Parts.OverlaySignup
import Fw.Parts.OverlayGolden
import Fw.Parts.HeroOrbit
import Fw.Parts.HeroAccent
import Fw.Parts.HeroDeck
import Fw.Parts.HeroGolden
import Fw.Parts.PeopleGolden
import Fw.Parts.PlatformGolden
import Fw.Parts.MorphTweenOpt
import Fw.Parts.HiddenPause
import Fw.Parts.MorphMountOpt
import Fw.Parts.HeroExitOpt
import Fw.Parts.PainNotes
import Fw.Parts.PainNotesGolden
import Fw.Parts.PeopleDeck
import Fw.Parts.PeopleCard
import Fw.Parts.PainNotesOpt
import Fw.Parts.MorphPanelOpt
import Fw.Parts.PeopleDeckOpt
import Fw.Parts.PeopleCardOpt
import Fw.Parts.HeroAccentOpt
import Fw.Measure.Zones
import Fw.Measure.Classes
import Fw.Measure.Quiet
import Fw.Measure.Tolerance
import Fw.Measure.WebKit
import Fw.Measure.Retry
import Fw.Measure.Viewport
import Fw.Measure.SimPlan
import Fw.Measure.Wire
import Fw.Ops.SpawnGuard
import Fw.Ops.Wait
import Fw.Ops.PathCheck
import Fw.Ops.Usage
import Fw.Ops.Meter
import Fw.Ops.Premise
import Fw.Ops.EnginePremise
import Fw.Ops.Identity
import Fw.Ops.Wire
import Fw.Ops.Salvage  -- workflow-salvage: a builder exit without a result (decide, golden text)
import Fw.Sched.Admit
import Fw.Sched.ParMetrics
import Fw.Wire.Sched
import Fw.Store.Layout
import Fw.Store.Reduce
import Fw.Wire.Store
import Fw.Gate.Rule
import Fw.Gate.Compare
import Fw.Gate.Items
import Fw.Gate.State
import Fw.Gate.Coverage
import Fw.Gate.Settle  -- gate-settle: when a gate sample is settled
import Fw.Gate.Freeze  -- gate-shard-balance r2: the settle wait under a frozen clock
import Fw.Gate.AlignEquiv
import Fw.Gate.Pixel
import Fw.Wire.Gate
import Fw.Wire.GateDeclared
import Fw.Engine
import Fw.Engine.Compose  -- compose-lean: units compose over parts, passes do not; Lego swap
import Fw.Parts.Bridge  -- indep-bridge: Independent rows to Flow-Indep, Lego swaps on isolated rows, S3 passes
import Fw.Guidance.Basic
import Fw.Guidance.Motion
import Fw.Guidance.Scroll
import Fw.Guidance.Tasks
import Fw.Guidance.Style
import Fw.Guidance.Stability
import Fw.Engine.Keys  -- model-checks: faithful run keys; a +search run never answers for the base
import Fw.Ci.Wire  -- ghb-lean: Fw.Ci.Budget and the ci.budget.* ops
import Fw.Plan.Lint  -- pa-evidence-lint: plan.lint
import Fw.Obs.Next  -- obs-next-lean: next action per agent (obs.next)
import Fw.Obs.Stale  -- console-stale: a service whose inputs changed on main after it started is stale
import Fw.Obs.Signals -- obs-signals: agent state from transcript signals (obs.signals)
import Fw.Plan.Incident  -- incident-lint: plan.incidentLint
import Fw.Plan.Workflow  -- workflow-claim: workflow runs as agent events
import Fw.Obs.Timing  -- timing-lean: slow / structural verdicts over timing samples
import Fw.Obs.Backoff  -- alert-rules-fix: wait or restart when an fwcore call misses its deadline
import Fw.Ci.Trigger  -- ci-trigger-lean: which workflows a push starts
import Fw.Ci.Intent  -- ci-own-trigger: a ci/* push starts only the lanes its head commit asks for
import Fw.Ci.Verdict  -- ci-own-trigger: a run passes only if its guard ran and some heavy job ran and all passed
import Fw.Ci.Cancel  -- ci-own-trigger: no concurrency group is shared on ci/**, so nothing cancels a ci/** run
import Fw.Gate.Exit  -- gate-exit-verdict: the summary exit code from the merged engine verdicts
import Fw.Spec.AxReach  -- mathview-axreach: shared-memo axiom reachability, exact on cycles
import Fw.Spec.ConeMiss  -- mathview-ci-fix: expected module-cache misses after an edit (dependents)
import Fw.Console.LandSpeed  -- land-speed-lean: result cache, lint_modular, pre-lock land, check verdict
import Fw.Console.Preview  -- task-preview: preview target, admission, ports, expiry
import Fw.Console.PreviewFacts  -- task-preview: GENERATED facts of the 25 tasks (apps/console-api/scripts/gen-preview-facts.ts)
import Fw.Console.PreviewTable -- task-preview: the 25-task target table, checked
import Fw.Console.LandVerdict  -- land-dry: VERDICT kinds, exit codes, retry rule
import Fw.Console.LandDry  -- land-dry: dry land stages and hand-back rule
import Fw.Console.WallClock  -- land-wallclock-off-gate: which literal ms bounds in land-selected tests the lint refuses
import Fw.Console.LandQueue  -- land-queue: FIFO land queue, bounded retry, runner identity
import Fw.Console.LandPool -- land-pool-fair: fair-share floor under poolSize, wired into land.ts by console.landPool and console.landRetry
import Fw.Ops.LedgerMerge  -- ledger-merge-driver: three-way id merge of the JSON ledgers (scripts/merge-ledger.mjs)
import Fw.Ops.Cache  -- gate-speed-ci: cache soundness (cache_sound, key_complete)
import Fw.Ops.LakeCache  -- site-build-cache: one Lake cache writer (cache_complete, rebuild_mono, table_complete)
import Fw.Site.GenRoute  -- site-build-cache: breakgen / sweepsgen split (split_agrees)
import Fw.Gate.Schedule  -- gate-speed-ci: Graham bound and the gate job split
import Fw.Gate.Shard  -- gate-shard-balance: LPT shard plan over measured unit costs
import Fw.Gate.ShardObs  -- gate-shard-balance: observed jobs of a CI run, reduced to the cost table (ShardCosts)
import Fw.Gate.Search  -- gate-preset-input: the search string of the gate rewrite arm from its fw and preset inputs
import Fw.Wire.ShardGolden  -- gate-shard-balance: golden/gate/shards.jsonl
import Fw.Measure.WktrLayout  -- wktr-fixture-speed: lane layout, premise gate, fixture assertions
import Fw.Measure.WktrVariance  -- wktr-serial-baseline: run-to-run variance of class kinds, findings, verdict
import Fw.Gate.PageOffset  -- fix-page-offset: page-level top-of-part check (proposal)
import Fw.Gate.PageRoot  -- gate-page-root-anchor: the page-root anchor scrollWidth <= requested width
import Fw.Spec.Props  -- lfg-props-shape: property-over-impl convention, Assume premise marker, kill-witness naming
import Fw.Search  -- lfg-props-shape: Enum, bounded counterexample search, link to properties
import Fw.Spec.LandDrySig  -- lfg-props-shape: the dry-run implementation signature (Out, DryImpl)
import Fw.Spec.Incidents  -- lfg-props-shape: the one incident registry (rows, Sig, registryFor, Convention)
import Fw.Spec.Props.LandDryDemo  -- lfg-props-shape: worked example (inc-land-dry-no-verdict)
import Fw.Ops.LeanFirst  -- lfg-spec: the lean-first land gate (Facts, reasons, stages, gate, out)
import Fw.Ops.LeanFirstProps  -- lfg-spec: the gate properties of section 7 over Gate/Render
import Fw.Ops.LeanFirstDecision  -- lfg-spec: the gate's decision-code test equals the allowlist rule
import Fw.Ops.LeanFirstSearch  -- lfg-spec: Enum Facts, fault grid, pointwise checks, search guards
import Fw.Ops.LeanFirstProofs  -- lfg-spec: proofs of every lean-first gate property (`<P>_impl`)
import Fw.Spec.Reach  -- lfg-mathview-facts: the closure/reach helpers shared by the props lint and the math-view facts
import Fw.Spec.MathFacts  -- lfg-mathview-facts: per-theorem facts (head, impl arg, assumes, kill, class, reach, wire)
import Fw.Spec.MathFactsGuards  -- lfg-mathview-facts: #guards of the facts on real declarations
import Fw.Preset.Gen  -- preset-v2-proved: the v2-proved arm from the findings ledger (V2Proved decides, Gen writes)
import Fw.Faithful.Band
import Fw.Faithful.Comparable
import Fw.Faithful.Zone
import Fw.Faithful.Wire
import Fw.Faithful.Golden
import Fw.Faithful.Measured
import Fw.Port.Sections  -- port-completeness-gate: section roots, exclusions, multiset difference
import Fw.Port.Text  -- port-completeness-gate: check 1, text digest
import Fw.Port.Attrs  -- port-completeness-gate: check 2, attribute multiset
import Fw.Site.Assets  -- port-completeness-gate: check 3, asset subset
import Fw.Port.Svg  -- port-completeness-gate: check 4, svg skeleton
