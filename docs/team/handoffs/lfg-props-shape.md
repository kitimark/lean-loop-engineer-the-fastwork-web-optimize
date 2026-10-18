# lfg-props-shape handoff

State: round 4 (final) on branch worktree-wf_b82902f8-8e2-1, code head f1ed99b, main merged after it. check.sh green
with new stage `props lint`; `fw land --dry` VERDICT dry; key theorems standard axioms only. check.sh now declares
its ledger read (`LandSpeed.checkShReads`, land-speed golden, land.ts `CHECK_SH_READS`).

Round 4 (lead decisions 1-3):
- One registry, `lean/Fw/Spec/Incidents.lean`: row `LandDry.incLandDryNoVerdict`, closed `Sig`, `Sig.Dom/Cod`,
  `registryFor`, `vocab`. `Kills s P`, `Faithful s impl`, `Convention s impl P` are per-signature abbrevs (no class)
  over `KillsAt`/`ConventionAt` (renamed in Props.lean). Signature types in `lean/Fw/Spec/LandDrySig.lean`.
- Ledger inc-land-dry-no-verdict gains `leanPred`/`leanReplay`. Replay prints only `[pathLine]` (placeholder,
  INFERRED), no VERDICT; exit code kept real (the ledger records none).
- `lean/scripts/PropsLint.lean` (check.sh `props lint`, ~11 s): registry-outside, convention-at-outside,
  prop-mentions-impl (P's closure ∩ (impl ∪ closure(impl) \ closure(vocab s))), vocab-has-impl, ledger (row id in
  ledger, entry names pred/replay). Reserved names (`x.eq_1`) count as their base declaration.
- Kills limit stated in Props.lean module doc and lean-first.md step 3: separation, not aboutness; reviewer checks
  P against `leanReason`.

Round-3 probe ported (scratchpad lfg4/Refute4.lean; `lake env lean -R d -o d/Refute4.olean d/Refute4.lean`), then
`lake env lean --run scripts/PropsLint.lean <d> Refute4` exits 1, 13 findings, among them:
  registry-outside Refute.fakeInc / fakeReg / emptyReg / Silly_convention_inline: builds ...Registry.mk outside ...
  convention-at-outside Refute.Silly_convention_fake: states ConventionAt; state ...Convention s impl P
  prop-mentions-impl Refute.PinImpl_convention: the property Refute.PinImpl reaches [...dryOut, ...dryRun, ...]
  prop-mentions-impl Refute.PinRun_convention: the property Refute.PinRun reaches [...dryRun, ...]

Open items / stated limits:
- `TaskSensitive r := ∀ o, lines(r o "a") ≠ lines(r o "b")` kills with no finding; an inline restatement of impl
  is not caught either. Both are review items. `Strict` rules out only the everywhere-true predicate.
- No checker spawned (no agent tool); docstrings self-reviewed (binders quantified).
Read first: Props.lean module doc, Incidents.lean, lean-first.md step 3, then PropsLint.lean rules.
