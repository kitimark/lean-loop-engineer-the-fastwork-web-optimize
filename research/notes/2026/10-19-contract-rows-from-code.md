---
id: contract-rows-from-code
kind: note
title: Contract rows from code - static part footprint, first diff against the declared rows, groups re-decided in Lean
status: MEASURED
created: 2026-10-19
topics: [lean, contracts, parts, extractor, independence]
---

# Contract rows from code

The extractor `apps/site/scripts/part-footprint.mjs` parses every part folder (TS with vite's oxc `parseSync`, CSS
with regexes) into 1127 accesses and 34 findings in `packages/contracts/golden/parts/footprint.gen.json`. Lean
(`Fw.Parts.Footprint`) sorts each access into a phase and wires. `Fw.Parts.Contract` compares the result with the 34
declared rows (`footprint-diff.gen.json`) and generates code rows (`lean/Fw/Parts/FootprintRows.lean`). Statuses:
the extraction counts are MEASURED (deterministic run); reasons are CONFIRMED by reading the cited line, else
INFERRED.

## Answer first
- The declared groups do not survive the code. When the table is widened by the code rows, the coupling components
  change (`codeGroups` in the diff golden, proved by `code_groups_partition`):
  - pain, pain.notes, people.card and people.o leave G1 and join the G2 block (commission, nav, platform,
    engine.scene), as does morph.columns, which was declared solo;
  - G1 is left with the six hero parts;
  - hero.countdown and morph.countdown form one group;
  - morph.mount becomes page-level.
  MEASURED.
- `code_groups_declared`: the new groups also separate the declared rows. Its proof uses `independent_antitone`
  (more inputs, outputs or targets can only add a conflict), so the code groups are a valid partition for both
  tables.
- The premise stays `declared-rows-unverified`. The code rows cover inputs, outputs, `onEvent`, targets and order.
  `moves`, `listAccess`, `schedules` and `plan` are still declared, and the extractor misses some accesses (limits
  below).

## First cases (task list)
| case | code says | status |
|---|---|---|
| people.o -> people.card `data-o-stack` | the row is right: people.o writes it, people.card reads it (`card.module.css`), no diff | MEASURED |
| people.carousel `rect:people` | the code reads `rect:people.card` (`#future-heading` is rendered by people.card); the row names the wrong owner | CONFIRMED |
| pain.notes `cardSelector` (index.tsx:72) | `.commission-card` is dead under CSS-module renaming (build.mjs:41); `[data-fw="commission-card"]` matches no static element, only hero.countdown's dynamic `data-fw={fwId}`, so the diff's `rect:hero.countdown` input is an extractor over-match and the card read is most likely always null | INFERRED |
| nav.hitTest `EXCLUDE_SELECTOR` | probe.ts:39-41,47 dead selectors, :51 dead alternative, :71 `closest(ALLOW_SELECTOR)` dynamic | MEASURED |

## Undeclared couplings in the diff
- morph.mount repins the page in its scroll-list callback (`morph.mount/index.tsx:103-106`, `window.scrollTo`). Its row
  has no `scrollY` output, and `scroll_writers` lists only morph.tween. CONFIRMED.
- pain.notes reads commission's `data-scene`, `data-render` and `--start-selling-intrinsic-block-size`, and writes the
  same variable on pain, which commission reads. Neither row lists these. MEASURED.
- hero.deck reads hero.orbit's `--ring-motion-blur`, `--orbit-*` and `data-done`. hero.orbit's row has no
  `data-done` output. MEASURED.
- morph.countdown writes the transform of an element rendered by hero.countdown (owner rule: the JSX folder). Its row
  targets itself. MEASURED.
- engine.scene's CSS reads `data-fw-hidden`, which morph.columns writes on its own stage through `watchHidden`
  (`morph.columns/index.tsx:42-48`). MEASURED.
- nav and nav.hitTest read `rect:people.deck`; nav has class outputs the extractor finds no reader for
  (`is-hero-pill`, `is-morphing`, ...). MEASURED.

## Extractor limits (accepted, listed in the diff as missing or extra)
- Unresolved targets (13): `createRange`, `activeElement`, refs passed through props or env objects
  (hero.countdown, hero.orbit, engine.scene's selector prop, morph.countdown). These give `rect:?` or `.../?` wires.
- Env-object callbacks are classified where they are defined, not where they are called. people.deck's
  `scrollTo` (index.tsx:55) has one caller, a tab click (`driver.ts:204-216`), but counts as frame-time, which makes
  people.deck page-level in `code_pageLevel`. CONFIRMED.
- `src/engine/**` is not scanned, so engine.scroll's declared inputs show as extra. The platform subparts' pause
  through `engine.scene/scene.module.css` and the drivers called through env objects show as extra as well.
- Media queries the extractor cannot name read both `vw` and `vh`. Neither has a writer, so this adds no coupling.
- Element scrolls (`scrollTo` on a deck or tab strip) are not the page scroll position (`Footprint.writes`). Boxes they
  move inside the element are not modelled.

## Reproduce
`node apps/site/scripts/part-footprint.mjs --write`; `lake build`; `lake env lean --run scripts/ContractsGolden.lean
--rows > Fw/Parts/FootprintRows.lean`; `lake build`; `... --diff > ../packages/contracts/golden/parts/footprint-diff.gen.json`.
`check.sh`'s contracts job (`--check`) and the site test `src/footprint.test.ts` fail when any of these is stale.
