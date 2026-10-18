# Handoff: integrate-ports (phase 1, prep)

Branch `integrate-ports-2` (CI ref `ci/integrate-ports-2`), from `worktree-agent-afe5e7954b26806f5` (30734ae). Merged in order: main (b00519e), fix-nav (b8c380c), fix-commission (3ed01af), then the global base rule. Head: see `git log` (last pushed = the run below). Re-merge main before the final full gate (40 commits behind at the time of writing; why-parts edits the four *Opt modules: use `git merge -X find-renames main`, then diff `lean/Fw/Parts/{PeopleCard,PeopleDeck,PainNotes,HeroAccent}Opt.lean` against main's old-name files, which must differ only by the namespace line).

## Conventions
- Shared files are unions. Generated files are regenerated, never hand-merged: `scope.gen.json` (`lake build`, `scopegen.mjs`), `lake exe breakgen --sweeps` (lean/Fw/Site/sweeps.gen.json, apps/site/src/sweeps.gen.json), `--sweeps-golden`, `lake exe partsgolden`.
- Name clash: main's proofs of people.card, people.deck, pain.notes, hero.accent (optimization specs) now live in `Fw.Parts.{PeopleCard,PeopleDeck,PainNotes,HeroAccent}Opt` (files `*Opt.lean`); our faithful port specs keep the plain names. ledger.json points at the Opt namespaces. work-graph.json paths still old (lead fixes at land).
- SweepReduce.lean: with every ported part in the scope the reduced desktop sweep has 45 stops (turn at 320 kept), was 35; theorem, docstring math and goldens updated.
- Global base rule: `apps/site/src/styles/reset.css` (`@layer reset` body: colour #171717, Google Sans stack, 1rem/1.5, smoothing) plus the four `@font-face` rules; the nav-only copy is removed. Fonts are never committed under apps/site: `scripts/build.mjs` copies the 4 woff2 byte for byte from `snapshot/site/_app/immutable/assets/` into `dist/<engine>/fonts/`.

## Local
site tests 4998 pass; gate-breakpoints 51 pass; `lean/scripts/check.sh` green.

## CI: run 39075461722 (workflow_dispatch, all site parts, no morph/overlays/engine.scroll). Part names, not groups: `people` is not a part.
Chromium 5 failures, WebKit 6. All are known/open; no NEW cell.
| cell | engines | owner |
|---|---|---|
| pain.notes box note x (145 probes, e.g. 308.5 vs 249.9 at desktop sweep 1280) | both | open, nobody named yet (was in the old Left list) |
| commission style inner/rows margin-inline (3 probes: desk-1512, desk-rm-1511, dark-1440) | Chromium | gate-settle / possible real difference |
| platform.stageBg stage/bg/grain heights (WebKit) | WebKit | fix-stagebg-webkit |

Commission margins (raw chromium.json): orig inner 132px / rows 8px at desk-1512, rewrite 0px / 0px; at desk-1280 both give 16px / 8px. Rules are identical (`.commission-inner` margin-inline auto, max-width 1136; rows 1120), the deferral logic is the same (data-render active -> deferred after 2 frames, content-visibility:auto), section rect identical. So it depends on whether the skipped subtree was laid out at the 1512 width before it was skipped: the rewrite's last layout there is missing/at another width. Not a static CSS difference; not fixed. Suggest: log the section's data-render and a layout-forcing read at the first sample in the rewrite.

## Update: commission margin cell, Playpen Sans, stageBg merge
- Merged fix-stagebg-webkit (f007b85). Playpen Sans Start Selling @font-face added in reset.css (file copied from snapshot/site/selling/fonts/ by build.mjs).
- Run 39078198232 (Chromium only, 22 parts): 5 failures: pain.notes note x (145, gate-settle's resize-lag rule) and commission inner/rows margin-inline at 4 desktop probes (first: desk-1279, orig 15.5px / 8px, rewrite 0px / 0px).
- Commission margins are INTERMITTENT, not a stable port difference: run 39075461722 failed desk-1512, desk-rm-1511, dark-1440 (orig 132px); run 39078198232 fails desk-1279 and 3 others (orig 15.5px), other probes pass. Margin = (W_cb - min(W_cb, 1136)) / 2 with W_cb = W - 112 (card padding 56 + 56); it agrees with the original wherever the rewrite is laid out.
- Evidence it is a sample-state effect: CSS rules identical (inner: max-width 1136, margin-inline auto; rows 1120); driver logic identical (data-render active -> deferred after 2 frames, intrinsic size set from getBoundingClientRect); in the failing probes the rects and `contain-intrinsic-block-size` (auto 1002px) are equal on both arms, yet the rewrite's used margins read 0px (a skipped content-visibility subtree reports the last completed layout's margins). Local reproduction (puppeteer, full Chrome, fresh load and resize from 319/700/1280, and the gate harness on desk-1280/desk-1512 with the 22 parts) gives 132/8 and 16/8 on both arms, so it only appears on the CI headless shell under load.
- Not fixed. Next step for whoever owns it (fix-proofs / gate-settle): record `data-render` and a layout-forcing read (`el.offsetWidth`) before reading margins in the gate, or force `data-render=active` for the commission collect, and confirm the cell flips.
- Lean row for fix-proofs: margin_inline(W) = (W_cb - min(W_cb, 1136)) / 2 with W_cb = W - 112 for W >= 641 (card padding 56 each side), rows margin = (min(W_cb,1136) - min(min(W_cb,1136), 1120)) / 2 = 8 at full width; both 0 when W_cb <= 1136.
- Not done: comparison with snapshot-extract's port-vs-reference report (193 Chromium cells; branch worktree-agent-a9218b9a1500c50f7 was not on this branch). The global body rule and Google Sans should remove most of the font-family cells; re-run the comparison after landing.

## Update 3: merges (head after this note: see git log; gate run 39081429914 = full gate, both engines)
- Merged: main (why-parts, check-dag, snapshot-extract, engine.scene; the four *Opt modules re-taken from main's current files with the namespace renamed, ledger.json taken from main then renamed, App/registry/run.mjs unions), gate-settle (ea1433c; ee57e36 was the merge), gate-align-equiv (8d919c0) with its call-site hunks applied (run.mjs collectWith, verdict.mjs canonArm). Goldens replayed (partsgolden, scopegen, sweeps): no diffs. site 5012 tests, gate-breakpoints 103, lean check green.
- Registry: the placeholder `people` shell part is dropped (people.card/o/deck/carousel replace it); engine.scene is added.
- Commission desk-1279 margins: gate-settle's predicate does not explain the cell by itself (a skipped content-visibility subtree is stable, hence "settled", while its used margins are stale). gate-settle reports commission 86/46 failures as settled values, i.e. real. Reference comparison: the committed snapshot-extract datasets (reference-*.jsonl) cover only the 14 parts of main's anchors (no commission), so the original's desk-1279 values need a snapshot-extract CI run on this branch (anchors now include commission). Not run.
- premise-tests run 39078962730: its verdict step fails only with "console-api is not running" (infrastructure, no premises-verdict.txt written); neither a new finding nor the cv.auto-margin premise.
