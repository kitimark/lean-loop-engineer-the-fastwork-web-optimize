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
