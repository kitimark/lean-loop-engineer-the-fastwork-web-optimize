# exit-scoped-inline handoff

State: branch `worktree-wf_a2e03981-f12-2` (round 2, merged main), last commit there; `ci/exit-scoped-inline` at 45a40e7b.

Verified:
- Bug A mechanism CONFIRMED from WebKit source @862f17d (cites in the note and ledger row hero.exit.scoped.inline).
- Lean `Fw.Parts.HeroExitOpt` section Scoped: `wkRun_inline`, `inline_visSame` (given the `.inline` branch of
  `wkResolve`, stated as the source premise), `inline_units`, `inline_touched`, `inline_lt_faithful`,
  `inline_narrow_delta` (90); against: `wkRun_chain_frozen`, `chain_stale_webkit`.
- MEASURED: hero path 0 new units on macOS WebKit, Linux WebKit and Chromium (runs 39448209903, 39452631146 at
  071906af, 39466179818 at 45a40e7b; A/A 39456741492, 39472217441); bug A was 187 / 228. Chromium counts 136 -> 45
  per exit frame, delta 90 (runs 39461009752, 39462188464). Tables and quoted Lean outcome lines: note, section CI.
- Readers: `liveReaders` (scope.ts) re-queries after a DOM change below the stage; jsdom test
  readers.component.test.ts; footprint regenerated (one new MutationObserver access; rows and diff unchanged).

Open:
- Flag admission: row hero.exit.scoped.falsified keeps fResult model-bug, so v2-proved still excludes the flag;
  clearing it and `Fw.Preset.Gen.record` of these runs write files outside this task (lead decision).
- docs/report/v2-report.md lines 124, 559 (14 isolated parts incl. hero.cue) are stale.
- Counts: 91 instead of 90 at scrollY 150-940 and -1 at 1400-1800 are not identified.
- Footprint resolves only the subject compound, so the `[data-fw="hero-deck"]` ancestor in READER_SELECTOR is no edge.
- In-flight transition units (close@0, close-hold@0, approach steps) recur in both arms: task
  trajectory-transition-window.

Conventions: the ledger row holds the measured result; the note holds the run tables. Outcomes were computed with
`storedOf` and `outcome` from a scratch script, not recorded.

Read first: the note research/notes/2026/10-20-exit-scoped-inline.md, then `section Scoped` in HeroExitOpt.lean.
