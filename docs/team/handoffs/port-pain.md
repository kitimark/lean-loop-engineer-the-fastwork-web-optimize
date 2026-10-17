# Handoff: port-pain (pain + pain.notes, faithful)

Branch worktree-agent-a199a4ef3874fa11e (CI ref `ci/port-pain`). Commits: part commit, then "shared, additive" commit. Gate run id is in the report.
Verdict: `pain` faithful (static markup + CSS, content-driven height replaces the shell fit); `pain.notes` faithful except one deliberate delta:
randomness is a seeded stream (`mulberry32`, seed `NOTES_SEED`) and the shuffle draws without replacement (the original uses `Math.random` and a random-comparator sort). PLAN 4.3 requires this.

## Files
- Lean: `lean/Fw/Parts/Pain.lean` (stage width 748 < w <= 780 above 860, 0 at <=860; section >= 300svh; theorem `stageW_lt_split`: the 1100 px branch `ie` of the original is dead, so the scored placement never runs).
  `lean/Fw/Parts/PainNotes.lean` (tick rule, overlap, avoid box, jittered placement, text pick, base layout, drag/keys, mulberry, permute, stick curve `stick`/`stickScale`, ~25 theorems, all with `$$` math). `PainNotesGolden.lean` has `lines`; jsonl `packages/contracts/golden/parts/pain.notes.jsonl` (416 lines, made with a scratch driver `lake env lean --run`).
- TS: `apps/site/src/parts/pain/` (index, pain.module.css, media.ts/test, part.json), `apps/site/src/parts/pain.notes/` (logic.ts + golden test, driver.ts + driver.test.ts with a fake env, index.tsx, notes.module.css, media.ts/test, data.ts English strings, part.json).
- Pointer/key moves write element style directly (`writeNote`); React state changes only when the set of notes changes. 3 s tick = `clock.interval`; first layout = one own-rAF frame; card check = `registerScroll('pain.notes', 120)`.

## Shared edits (separate commit, additive)
`App.tsx` (Pain gets `notesVariant`), `registry/index.ts` (+pain.notes), `Scope.lean` (+2 PartUse), `scope.gen.json` (regenerated), `anchors.json` (+pain, +pain.notes).
Also `apps/site/scripts/gen-shells.mjs`: `PORTED = {'pain'}` skips writing/checking `parts/pain/box.module.css`; the fit stays in `boxes.gen.json` and `SECTION_IDS` (other ports: add your id to PORTED, do not touch model.ts).
Not done: `Golden.lean` does not import `PainNotesGolden` (shared; append `lines`), `Fw.lean` needs nothing (globs). Scope.lean docstring list of pilot parts not updated.

## Open
- `is-pain-dark` is a global class (`:global`) the people port must toggle on `[data-fw="pain"]` (original JS 11324); until then at <=860 the section is white like the original at first paint.
- The commission port must expose `[data-fw="commission-card"]` (or `.commission-card`) for the clear rule; absent now (rule inert).
- Fonts (Google Sans, Playpen Sans) are not shipped in the rewrite, so text boxes are compared with `layoutDerived` skips; the sticky box height uses one-line h2.
- Only the English dictionary is in `data.ts`.
- Read first: `Pain.lean` then `PainNotes.lean` module docstring, then `driver.ts`.
