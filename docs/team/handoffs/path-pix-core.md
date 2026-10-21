# path-pix-core (lean-prover) handoff

State: branch worktree-wf_cb4e1c99-106-1, main merged; `sh lean/scripts/check.sh` green via the check slot.

What exists (`lean/Fw/Gate/PathPix.lean`, namespace `Fw.Gate.PathPix`)
- Accelerated (l.16-55): `always` = the 7 properties WebKit animates on both the accelerated and threaded paths
  (CSSProperties.json@862f17d, cited in the docstring); offset-* and custom properties are threaded-only, so not accelerated.
- Grades E < E1 < Q < L, plus invalid (l.57-75). `grade` (l.382) for one cell, decided in this order: invalid, outside change → L,
  unaccepted text hold → L, inside byte-equal with every premise closed → E, within 1 with Near1 backing → E1,
  within 1 or within the control's noise → Q, otherwise L. One theorem per branch (l.390-515).
- Premises (l.108-200): `premises eng claim` lists P1 (composited), P2-P4, S1/T1 (snap), C1 (text that resamples,
  or text that translates without snap), C2 (resamples), C5 (translates without snap), C6 (filters ∧ webkit ∧ composited).
  The open exceptions C1/C2/C5/C6 are never closed, so a byte-equal cell with any of them is at most Q.
- Snap: `snap_exact` (l.259): a whole-device-pixel shift resamples exactly; S1 (`Cell.s1`, `onGrid`) allows 1/10000 px of
  census print noise, which no theorem covers. Near1 (l.271),
  `double_round_le1` (l.279), `shown_near1` (l.307) from `PathPremisesNear1`.
- Golden: `packages/contracts/golden/gate/path-pix.jsonl` (54 lines: 31 grade, 12 accelerated, 11 premises), written by
  `lean/scripts/PathPixGolden.lean`; check.sh job "path-pix golden check"; `goldenLines` takes Unit (init-cost lint).
- `lean/Fw/Ci/Trigger.lean` lean.yml row lists path-pix.jsonl; `packages/contracts/golden/ci/triggers.jsonl` regenerated.

Accepted limits: pixel noise and the CA blur stay measured hypotheses (C6 is never closed); no lane code; the blur fit
belongs to ca-blur-fit.

Open items (follow-ups)
- Sample matrix: Lean-generated t/offset samples per cell.
- TS twin checked against path-pix.jsonl; lanes that fill `Cell` from CI captures; census; `member_needs_pathpix` admission.

Read first: `grade` and its branch theorems, then `premises` and `Cell.closed`.
