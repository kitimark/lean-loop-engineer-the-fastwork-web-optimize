# Handoff: morph-scroll-lock (C4), round 2

**State.** Branch `worktree-wf_22f9acfd-29a-1` (merge of main 01bb2a9a, code b4b8b377, note 5ee20980, final: this commit),
pushed as `ci/morph-scroll-lock` at b4b8b37. Read first: `research/notes/2026/10-21-morph-scroll-lock.md` (verdict, design,
per-lane engagement, reproduction of the outcome lines, ledger row for the lead).

**Verified.**
- Lean MT-L (`lean/Fw/Parts/MorphTweenOpt.lean`, end of file): one read per activation (`readsAt`, `stepR`, `runR_eq`,
  `reads_iff`), hover gate (`lockAllowed`, `engage`, `engage_on|touch|classic|off_writes`), two counters (`forced_*`,
  `style_passes`, `rootWrites_classic`); `work_le` removed. `sh lean/scripts/check.sh` green.
- Golden `morph-tween-scroll-lock.jsonl`: lock rows carry `read`; engage rows. The TS test counts `overlay()` calls per
  event (1 at the activating push, 0 per tick) and checks the read comes before the first style write.
- Site test and typecheck, `scripts/ci-paths.test.mjs`, runner `land-inputs` green.
- CI at b4b8b37: flag 39505188144 (`?fw=morph.tween:scroll-lock`), A/A 39505203727 (`''`), searches checked. Mac morph
  fails in both (close@0 repeats); nothing repeats beyond the A/A floor outside close@0 and approach steps.

**Open.**
- Ledger row not applied; the JSON is in the note.
- The probe cannot show the scrollTo saving (`still_eq`); a trackpad-gesture probe step that records engagement is the follow-up.
- macOS runner scrollbar kind unknown; the net of 2 root style passes per morph against the saved scrollTo calls is INFERRED.
- `fw run --trajectory` took the skipped push run 39505172794 as its dispatch and exited; dispatches were 39505188144
  (flag) and 39505203727 (A/A).

**Conventions.**
- Arm is `visClass: "L"`, kind `proposal`. Generated files: footprint (`part-footprint.mjs --write`),
  `look-change.candidates.jsonl` (`Fw.Preset.Gen.run`).
- Golden regen: drop the `include_str` `#guard` line, build, write `lockJsonl` from a scratch `main`
  (`lake env lean --run` in `lean/`), restore the line, rebuild.
