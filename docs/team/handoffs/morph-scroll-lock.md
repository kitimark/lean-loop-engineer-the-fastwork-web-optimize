# Handoff: morph-scroll-lock (C4)

**State.** Branch `worktree-wf_22f9acfd-29a-1`, pushed as `ci/morph-scroll-lock`. Read first:
`research/notes/2026/10-21-morph-scroll-lock.md` (verdict, engine paths, CI runs, ledger row for the lead).

**Verified.**
- Lean MT-L in `lean/Fw/Parts/MorphTweenOpt.lean` (end of file): `runL_s`, `runL_locked`, `classic_writes`, `seen_eq`,
  `forced_le`, `forced_lt`, `shown_lock`, `ungated_eq`, `still_eq`, `work_le`, `work_still`, `work_ungated`, `gutter_same`,
  `gutter_shift`, `gutter_stable`, `lock_vis`. `sh lean/scripts/check.sh` green.
- Golden `packages/contracts/golden/parts/morph-tween-scroll-lock.jsonl` = `lockJsonl` (`#guard ... include_str`); TS
  `apps/site/src/parts/morph.tween/scroll-lock.golden.test.ts` replays it through the driver and `pin()`.
- Site tests and typecheck, `scripts/ci-paths.test.mjs`, runner `land-inputs` test green.

- CI at e01287a: flag runs 39496271199, 39498373119 and A/A run 39500347224. There is no unit beyond the A/A floor outside close@0,
  and mac morph is "no verdict: coverage" (table in the note).

**Open.**
- Ledger row: not applied (another task held `research/findings/ledger.json`); the JSON is in the note.
- iPhone premise refuted (UIKit pan in flight not stopped, INFERRED from `WKWebViewIOS.mm:1100-1104`@862f17d).
- The probe cannot show C4's gain: it pushes with one prevented wheel and never has a gesture in flight. A probe step with a
  trackpad gesture latched before the armed band is the follow-up that would measure it.
- Overlay or classic scrollbar on the macOS runner unknown; on classic the arm is the original.

**Conventions.**
- The arm is `visClass: "L"`, kind `proposal` (look change in a gesture in flight). `look-change.candidates.jsonl` was
  regenerated with `Fw.Preset.Gen.run`, and the footprint files with `apps/site/scripts/part-footprint.mjs --write`.
- To regenerate the golden: a scratch `main` that writes `Fw.Parts.MorphTweenOpt.lockJsonl`, run with
  `lake env lean --run` from `lean/`.
