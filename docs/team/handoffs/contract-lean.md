# contract-lean handoff

State: branch `worktree-wf_ed01bde3-026-2` (main merged in, with Fw.Engine.Compose), round 2 commit
"contract-lean r2: affects relation, derived pageLevel".

Delivered
- `lean/Fw/Parts/Contract.lean`: 34 `PartSpec` rows, `affects`, `effOut` (outputs ++ moves as rects), `i1`-`i4`,
  `independent`, derived `pageLevel` (schedules or writes scrollY), `groupKey`, `scenariosFor`, JSON render, `run`.
  Theorems by `decide`: `parts_ids`, `groups_partition` (over non-page-level parts), `g4_couples`,
  `scroll_writer_couples`, `scroll_writers` (= morph.tween), `pagelevel_env_only`, `layoutLocal_iff`, `moved_eq`
  (unchanged), `scenarios_known`. Axioms: propext only.
- `lean/scripts/ContractsGolden.lean`; goldens `packages/contracts/golden/parts/contracts.gen.json` (rows gain
  `pageLevel`) and `packages/measure-chromium/scenarios.gen.json` (unchanged bytes). Job in `lean/scripts/check.sh`.
- Round-2 row edits: commission (entering/shrinking/titleWrapped/underline classes, runway height, vw, clock), nav
  (rect people.deck, dead selectors noted), nav.hitTest (dead selectors noted), people.card (data-fw-pain-dark),
  morph.countdown (data-start-selling-scene input), morph.mount (vh), people.o (vw, vh, hover note), morph.panel note.

Verified: `lake build Fw.Parts.Contract` ok, golden `--check` exit 0, `sh lean/scripts/check.sh` green (30 s),
row LaTeX equals the golden rows (script cross-check, 34/34).

Finding: morph.tween's pin writes scrollY, which moves every rect, so it couples to every rect reader
(`scroll_writer_couples`) and is page-level like engine.scroll. No regrouping: G1 9, G2 14, 10 solos. Its own variants
are measured only on whole-page swipe runs; a G2 stage runs it faithful.

Conventions: `cssVar`/`className` names are `<name>/<owner part>`; rows are frame-time may-traces under the faithful
engine; accepted limits are listed in the `PartSpec` and `groups_partition` docstrings.

Open: part-io-lint (code ⊆ row drift check); morph-group-integrate edits the morph.panel/countdown rows (panel's
`data-start-selling-scene` becomes an output) and regenerates the goldens; contract-compose-bridge
(`Independent P Q → Indep`); a content lane restoring global class names adds className/rect inputs for hero,
people.card, pain, commission, platform to nav/nav.hitTest. plan-rev11 uses 34 parts.
Read first: `affects`, `i3`, `pageLevel`, the `groups_partition` docstring, then `moved_eq`.
