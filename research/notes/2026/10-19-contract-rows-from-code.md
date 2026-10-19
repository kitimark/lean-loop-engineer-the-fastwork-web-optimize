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
with regexes) into 1205 accesses and 62 findings in `packages/contracts/golden/parts/footprint.gen.json`. Lean
(`Fw.Parts.Footprint`) sorts each access into a phase and wires. `Fw.Parts.Contract` compares the result with the 34
declared rows (`footprint-diff.gen.json`) and generates code rows (`lean/Fw/Parts/FootprintRows.lean`). Statuses:
the extraction counts are MEASURED (deterministic run); reasons are CONFIRMED by reading the cited line, else
INFERRED.

## Answer first
- The code groups are a lower bound on coupling. When the table is widened by the code rows, the coupling components
  (`codeGroups` in the diff golden, proved by `code_groups_partition`) are one 27-part group, three solos
  (overlays.drawer, people, people.carousel) and four page-level parts (engine.scroll, morph.mount, morph.tween,
  people.deck). The 27-part group holds commission, commission.typing, engine.scene, the six hero parts,
  hero.countdown, the three morph parts columns, countdown and panel, nav, nav.hitTest, nav.langMenu,
  overlays.signup, pain, pain.notes, people.card, people.o and the six platform parts. MEASURED.
- **Merge (round 2):** round 1 had a 17-part group, the six hero parts, hero.countdown+morph.countdown and five solos.
  These all merged into the 27-part group. The cause is the animation seek at `engine.scene/index.tsx:13`: it
  writes `currentTime` on every animation of the scene stage, which the closed extractor now records as a `cssVar`
  write with name `?` on owners `?` (engine.scene) and `morph.columns`. Under the `same` rule below, a write with
  name `?` matches every `var()` read whose owner is `*`. Deleting both seek accesses from the data restores the
  round-1 groups exactly. Deleting only the engine.scene one still merges. MEASURED (scratch experiment).
- `code_groups_declared`: the groups also separate the declared rows (via `independent_antitone`). `flagged_total`:
  every access with name `?` or owner `?` has a finding at its own (part, file, line).
- The premise stays `declared-rows-unverified`. `moves`, `listAccess`, `schedules` and `plan` are still declared,
  and the declared rows are not fixed in this branch.

## Closed extractor (round 2)
- Every call, assignment or read on an element, element list, animation, `style` or `classList` receiver either
  maps through the `MODELLED` allowlist in `part-footprint.mjs` to an access or emits `unmodelled-api` at that line.
  New ops and mappings: `animate` and the WAAPI calls and times (`currentTime`, `startTime`, `playbackRate`) write
  `cssVar:?` on the target; `textContent`, `innerHTML` and the node insert or remove calls are `setContent` (box
  write of the owner); reflected attributes (`tabIndex`, `hidden`, `inert`, ...), `aria*` and `dataset.*` are
  `setAttr`; `showModal`/`show`/`close` and `.open` are the `open` attribute.
- Any name the extractor cannot read emits `dynamic-name` (24 sites).
- Remaining `unmodelled-api` (8): `anim.onfinish` (morph.tween/waapi.driver.ts:102), `el.contains`
  (nav.hitTest/probe.ts:71, nav.langMenu/index.tsx:60), `el.focus` (overlays.drawer/index.tsx:59,
  overlays.signup/index.tsx:75), `el.isConnected` (people.card/index.tsx:52), `textContent` read
  (platform/Visuals.tsx:219), `beginElement` (platform/Visuals.tsx:279). MEASURED.
- The six sites the round-1 review cited are now accesses (pinned in `apps/site/src/footprint.test.ts`):
  waapi.driver.ts:134-135, engine.scene/index.tsx:13, commission.typing/driver.ts:78-79,
  platform/Visuals.tsx:210,219 and nav/index.tsx:100.

## The `same` rule for name `?`
Two wires are the same signal when they are equal, or when both have an owner, the owners are equal or one is `*` or
`?`, and either the (kind:name) parts are equal or the kinds are equal and one name is `?` (`Footprint.same`).
A name of `?` is therefore a wildcard within its kind. This rule is sound (it never drops a coupling the code could
have) and is the cause of the merge above.

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

## Extractor limits (accepted, stated in the `code_groups_partition` docstring)
- `rect:?` couples nothing: a box read of an unresolved element matches no box write. It is in the rows of
  commission, nav, nav.hitTest and overlays.signup (and people.deck, page-level). Read conservatively, every box
  write reaches it, which couples those four with hero.accent and merges the six hero parts with them. On the round-2
  data this changes no group (`code_groups_rect_open`). On the round-1 rows it would have merged the hero group, the
  17-part group and overlays.signup. MEASURED.
- Hit tests (`elementFromPoint`) and computed-style reads (`getComputedStyle`, `getPropertyValue`) read no wire.
- A `setContent` with owner `?` writes no wire (`Footprint.writes`).
- Unresolved targets (10 `unresolved-target`): `createRange`, `activeElement`, refs passed through props or env
  objects. These give `rect:?` or `.../?` wires.
- Env-object callbacks are classified where they are defined, not where they are called. people.deck's
  `scrollTo` (index.tsx:55) has one caller, a tab click (`driver.ts:204-216`), but counts as frame-time, which makes
  people.deck page-level in `code_pageLevel`. CONFIRMED.
- `src/engine/**` is not scanned, so engine.scroll's declared inputs show as extra.
- Media queries the extractor cannot name read both `vw` and `vh`. Neither has a writer, so this adds no coupling.
- Element scrolls are not the page scroll position (`Footprint.writes`); boxes they move inside the element are not
  modelled.

## Follow-ups
fix-declared-rows; extractor-callsites (env callbacks, the seek's real targets); extractor-engine (`src/engine`);
generate moves, listAccess, schedules and plan; model the 8 `unmodelled-api` residues.

## Reproduce
`node apps/site/scripts/part-footprint.mjs --write`; `lake build`; `lake env lean --run scripts/ContractsGolden.lean
--rows > Fw/Parts/FootprintRows.lean`; `lake build`; `... --diff > ../packages/contracts/golden/parts/footprint-diff.gen.json`.
`check.sh`'s contracts job (`--check`) and the site test `src/footprint.test.ts` fail when any of these is stale.
