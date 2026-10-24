branch: worktree-wf_e1ce08cb-1bf-1
worktree: .claude/worktrees/wf_e1ce08cb-1bf-1
last commit: see git log (round 2: site-level markers, glue opens the site)
CI runs: none (accepted limit: no CI run)

State: one class-position rule in Lean, mirrored by the extractor branch for branch.
- Rule: lean/Fw/Parts/ClassPos.lean `go`, `marker` (site-level lost token named after the form, kept whatever the
  operands), `wordToks` (glue), `methodToks`/`joinToks`, `helpers`, `isSep`, `Kind.opens`, `writes`/`findings`.
- Markers: `call <name>` (non-helper call), `method <name>` (non-join method, or join on a non-array receiver),
  `join separator` (join on an array with a separator that is not whitespace), `spread` (call/array arg or object
  property), `other`. A glued word (`'btn-' + size`) also adds `setClass ?`.
- Theorems: `call_other`, `method_other`, `join_unmodelled`, `join_glued`, `spread_arg`, `spread_lost`, `other_lost`,
  `obj_spread_marker`, and the `*_open` family (`call_other_open`, `method_other_open`, `join_unmodelled_open`,
  `join_glued_open`, `spread_open`, `obj_spread_open`, `other_open`, `glued_word_open`): `setClass ?` with no
  hypothesis on literals. `opens_open`, `lost_open`, `glued_open` on token lists.
- Golden: packages/contracts/golden/parts/footprint.classpos.jsonl (generator lean/scripts/ClassPosGolden.lean, after
  `lake build Fw.Parts.ClassPos`). Rows include getClass(variant), cls.trim(), items.map(f).join(' '), clsx(...xs).
- JS: apps/site/scripts/part-footprint.mjs `collectClassTokens` (`marker`, `SpreadElement` case) / `classReport`
  (`?` when any finding). Test: part-footprint.classpos.test.mjs.
- Regen chain: `node apps/site/scripts/part-footprint.mjs --write`, then in lean/ `ContractsGolden.lean --rows` into
  Fw/Parts/FootprintRows.lean, rebuild, `--diff` into footprint-diff.gen.json.

Footprint change (round 2): nav/index.tsx:133 (`${boxClass}is-hero-pill`) now emits `setClass ?`: +1 access row,
+1 finding `dynamic-name setClass`; findings 76 -> 77; footprint-diff: 15 rows change (className:?/nav becomes a
missing input of 14 parts; nav outputs.extra drops its 3 className entries, covered by `?`).
Bridge: lean/Fw/Parts/Bridge.lean codeAdj row 16 (nav) 6 -> 20 edges, chain pairs 341 -> 322, `chainTargets_code`
retabled; isolated and independent rows unchanged. Bridge.lean is outside the graph writes: dry land prints
`VERDICT scope classpos-model-align` until the lead adds it. docs/report/v2-report.md:557 already cites 299 (stale).
Checks at 0ad5a4e9f + main merge: check.sh green, site test + typecheck, ci-paths, runner land-inputs green.

Follow-ups: arrays/objects outside helper args, Unicode whitespace splitting, identifiers in className, computed
CSS-module keys `v[\`dot${..}\`]` (resolve to `#null`, platform/Visuals.tsx:446-448).
