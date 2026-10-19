# port-fonts-check (round 1)

State: branch `worktree-wf_db541e00-01b-1`; CI branch `ci/port-fonts-check` (workflow visual-diff, head 4e62cce1 carries `[ci:visual-diff]`).
- Lean `lean/Fw/Port/Fonts.lean`: check 5 (leaf multisets plus loaded-face sets, Fastwork excluded) and, new, `split`: the lost and added leaves
  told apart as font changes (same section and text), ownership moves (same text and font, other section) and unpaired leaves
  (`pairOff`, `change_font_differs`, `move_sec_differs`, `split_missing_length`, `split_extra_length`, `split_empty_iff`). Pass is unchanged.
- Golden `packages/contracts/golden/port/fonts.jsonl` (16 cases, split included); twin `split` in `scripts/port/fonts.mjs`; test `apps/site/test/port-fonts.test.mjs`.
- Reader (TS stand-in, reports only): `fontsInPage` scrolls in steps and each section row into view (2 frames + pause; fixes the morph panel that
  mounted via IntersectionObserver after the sweep had already left), returns to the top (the deck follows scroll, so both arms show `sound-composer`),
  polls until leaves, deck tab and face states are equal 6 polls in a row (`settled`). Artifact `<engine>.fonts.json`: full lists, no cap, plus
  `changes`, `moves`, `lost`, `added`, `gaps`, `settled`, `polls`, `deckTab`. `node src/cli.mjs fonts-compare --in A,B` lines runs of one head up.
- Results file (per-cell verdicts and real counts): `research/notes/2026/10-19-port-fonts-check-cells.md`.
CI, head 4e62cce1, assets=none: push 39253450733, dispatch 39256117644; both green, advisory fonts step fails as before.
- Stable over the 2 runs, all 16 (engine, probe) pairs: the font-change pairs are identical (45 leaves at desk-1512..861, 72 at desk-641 and
  narrower), 1 ownership move (`people.o` "o" is in `people.card` in the port: the original's anchor `.start-selling-future-people-o` holds the
  sr-only "o", the port's `[data-fw=people-o]` span does not; a port markup gap, decided by the anchors), all reads settled, deck tab equal.
- Not stable: 0-6 unpaired lost/added leaves per probe, all time-driven text: `platform.entries` counters (130), `commission.typing` (33),
  `pain.notes` (1). Not font gaps; they stop wherever the scroll or timer left them. Follow-up: settle or pin them (an exclusion in `Fw.Port.Text`
  would also weaken check 2, so none was added).
- Gap list (font-change pairs only): buttons draw Arial (-webkit-standard in WebKit) instead of Google Sans in hero Join waitlist, hero.cue, morph.panel,
  people.carousel and people.deck items (people.deck 23/9 (400/500) at desk-1512..861, 37/22 at desk-641 and narrower; hero Join waitlist, hero.cue, morph.panel and people.carousel 1 leaf each at 500); hero.countdown (4) and morph.countdown (4) digits and one morph.panel text draw system-ui.
- Visual diff: the old "about 25 flips" was wrong: 63 of 496 cells hold no single verdict over the 3 old none runs (chromium 29, webkit 34). Inject baseline:
  0 P on both engines (chromium 0 P / 116 F; webkit 0 P / 121 F / 8 I). The new head's two runs differ in 14 (chromium) and 16 (webkit) cells.
  Webkit shows 16-19 invalid cells on the new head (the old runs had none), cause not looked at. tolerances.json unchanged. Flips are a settle follow-up.
- `port-fonts` is a job of its own because it needs a browser (`gate-engine`); `port` runs checks 1-4 without one (docs/team/tools/visual-diff.md).
Local: Lean `sh lean/scripts/check.sh` green; port, visual-diff, ci-paths tests green; land-inputs test passes only with a longer timeout under load
(`--testTimeout=900000`). One local Chrome read of the original arm (3 reads, equal). No work-graph.json write. `apps/runner/src/fw.ts` was reset to main.
Read first: `lean/Fw/Port/Fonts.lean`, then `scripts/port/fonts.mjs`.
