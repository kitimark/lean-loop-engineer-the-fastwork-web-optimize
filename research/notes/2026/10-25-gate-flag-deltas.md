# Gate flag deltas: per-flag computed-style changes excused item by item

**Answer.** Both runs now pass in both engines when re-judged offline with the new rule (MEASURED: the
CI artifacts were re-summarised with the branch's `summary.mjs`; no new CI run). Every excused item is one of 5
allowlisted tuples, and no other failure remains.

| Run | Flag | Engine | Before | After | Readings excused | Items excused |
|---|---|---|---|---|---|---|
| 40174477871 | morph.panel:rest | Chromium | fail | pass | 392 (196 platform, 196 engine.scene) | 392 |
| 40174477871 | morph.panel:rest | WebKit | fail | pass | 376 (188 platform, 188 engine.scene) | 376 |
| 40156380619 | morph.columns:final-scale | Chromium | fail | pass | 112 | 1680 (560 each of flex-basis, -grow, -shrink) |
| 40156380619 | morph.columns:final-scale | WebKit | fail | pass | 109 | 1635 (545 each) |

In all four cases the re-judgement leaves 0 failing items, 0 unsettled states, 0 not-rendered parts and 0 failing
probes (MEASURED, `scratchpad/gfd/counts.mjs` over the re-judged `summary.json`). The readings tables still cover the
full universe of 7056 readings in Chromium (7049 pass, 7 excused by exit.jsonl) and in WebKit (6765 pass, 291 excused).

## Rule

Specification: `lean/Fw/Gate/FlagDelta.lean`. Golden: `packages/contracts/golden/gate/flag-delta.jsonl`. TS twin:
`packages/gate-breakpoints/src/flag-delta.mjs`, applied in `summary.mjs` (`applyFlagDeltas`).

- `deltas` lists exact tuples (flag, part, role, property, orig value, rewrite value), each with its look class and a
  premise naming a Lean theorem. The list is written out entry by entry and contains no patterns.
- A failing part reading becomes a pass only when it has at least one failing item and every failing item matches a
  tuple whose flag is in the run's flags. A matching item is a style item with status `differ`, not decided by its
  rect, with the same role, property and both values. Any other item keeps the reading failing.
- Flags come from `header.flags.search` (`flagsOfSearch`), which `run.mjs` already checks against the page's
  `data-fw-config`. They never come from the command line. A search that cannot be read yields no flags.
- The rule runs on part rows before masks and the settle check. Excused items are printed only for settled states, in
  a "Flag deltas" section of `summary.md` with one line per excused reading.

| Tuple | Part / role | Property | orig → rewrite | Look | Premise |
|---|---|---|---|---|---|
| panel-rest-section-filter | platform / section | filter | blur(0px) → none | E | `Fw.Parts.MorphPanelOpt.rest_visSame_E` |
| panel-rest-scene-filter | engine.scene / scene | filter | blur(0px) → none | E | same |
| final-scale-col-flex-basis | morph.columns / col | flex-basis | 0px → auto | L | `Fw.Parts.MorphColumnsScale.layout_const` |
| final-scale-col-flex-grow | morph.columns / col | flex-grow | 1 → 0 | L | same |
| final-scale-col-flex-shrink | morph.columns / col | flex-shrink | 1 → 0 | L | same |

## Theorems (all in `Fw.Gate.FlagDelta`, standard axioms only)

| Claim | Theorem |
|---|---|
| An item is excused only when its flag is on | `excused_only_flag_on` |
| One failing item that is not allowlisted keeps the reading failing | `unlisted_item_fails` |
| An excuse is always an entry of the enumerated list, matched exactly | `deltas_enumerated` |
| With none of the tuple flags on, the gate verdict is unchanged | `flags_off_unchanged`, `no_flags_unchanged` |
| The rule can only turn fail into pass | `readingVerdict_changes` |
| Every item of an excused reading is printed with its tuple | `excused_all_printed` |
| The rule equals `cellVerdict` over items relabelled from excused to equal | `readingVerdict_relabel` |

## Limits

- The re-judgement is offline over the existing artifacts. The lead re-dispatches a CI gate run after the land.
- The class L tuples (final-scale) are excused only for the gate. They stay look changes for the user's visual review.
- Playwright WebKit stands in for Safari.
- `cli.mjs` has no class for flag-delta readings, so they appear as `pass` in `readings-<engine>.json` and the gate
  verdict line. The excused list appears only in `summary.md` and `summary.json` (`flagDelta`).
