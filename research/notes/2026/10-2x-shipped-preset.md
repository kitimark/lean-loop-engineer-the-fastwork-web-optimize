# The `shipped` preset (task shipped-preset)

Answer: `shipped` today equals `v2-proved` (`engine.scroll:unthrottle`, `hero.exit:threaded`; key `fw` of
`apps/site/src/registry/presets/shipped.json`). The only accepted class L flag, `nav:earn-logical`, is blocked by
`gate webkit`: the macOS WebKit morph cell of run 40872462216 fails (key `blockers` of row 18 of
`packages/contracts/golden/preset/shipped.decisions.jsonl`). No CI or phone run in this task.

## 1. Rule (CONFIRMED, `lean/Fw/Preset/Shipped.lean`)

User decision 2026-10-29 ("Separate preset (Recommended)"): accepted look changes go into a second preset; `v2-proved`
stays same-look (`V2Proved.look_not_mem` unchanged).

- `okShipped f = ok f || lookOk f`, with `lookOk f = accepted f && kindAllows f && why f == proved && trajWhy f == pass`.
- `kindAllows`: the flag is registered and every registered entry of it is `optimized` or `proposal` (class L flags
  are never `optimized`, `Gen.parsePart` refuses that pair). Faithful, ablation and probe entries block (`kind_blocks`).
- `shipped = preset ++ extras`: `v2-proved` first, then, among the linked flags of parts `v2-proved` leaves free, the
  first `lookOk` flag per part. Putting `v2-proved` first is what makes it a subset: a per-part pick over `okShipped`
  could let an earlier accepted L flag shadow a `v2-proved` member.
- `accepted` in `Gen` is `lookAccepted`: a `lookDecisions` entry with decision `accepted` and review `done`.

| theorem | statement |
|---|---|
| `Shipped.preset_sub_shipped` | `v2-proved` ⊆ `shipped` |
| `Shipped.shipped_extra_accepted` | a member outside `v2-proved` has `accepted f` |
| `Shipped.shipped_look_accepted` | a class `l` member has `accepted f` |
| `Gen.shipped_extra_decided`, `Gen.shipped_look_decided` | the same, as an entry of `Gen.lookDecisions` (accepted, done) |
| `Shipped.shipped_part_unique` | one variant per part |
| `Shipped.generate_ok` | a generated `shipped` is the preset, every `requires` is in it, no `conflicts` is |
| `Shipped.shipped_proved`, `probe_not_mem_shipped` | members are proved and pass the trajectory; probes never enter |
| `Shipped.shipped_eq_preset` | with no accepted look, `shipped = v2-proved` |
| `blockersV2_nil_iff`, `blockersLook_nil_iff`, `blockersShipped_nil_iff` | no blockers exactly when the route admits the flag |

## 2. Generated files (Gen.run)

`Gen.run` writes `packages/contracts/golden/preset/shipped.json`, `shipped.decisions.jsonl` and
`apps/site/src/registry/presets/shipped.json`; `--check` (check.sh job `preset v2-proved check`) compares them.
Every `v2-proved.decisions.jsonl` row gains `entry.presets`: per preset `member` and `blockers` over `kind`, `proofs`,
`gate chromium`, `gate webkit`, `look` (for `v2-proved` look means "not class L", for `shipped` "accepted"). No other
field of that file changed. `shipped.decisions.jsonl` covers the decided flags plus the look-change candidates.

## 3. Current membership (MEASURED on the generated golden)

| flag | class | user look | route | shipped blockers | member |
|---|---|---|---|---|---|
| `engine.scroll:unthrottle` | none | none | v2-proved | none | yes |
| `hero.exit:threaded` | none | accepted 2026-10-24 | v2-proved | none | yes |
| `nav:earn-logical` | L | accepted 2026-10-25 | none | gate webkit | no |

Keys: `visClass`, `userDecision.decision`, `route`, `blockers`, `member` of `shipped.decisions.jsonl` rows 14, 17, 18.
For `nav:earn-logical`, `entry.presets` of `v2-proved.decisions.jsonl` row 18 reads `v2-proved` blockers
`kind, gate webkit, look` and `shipped` blockers `gate webkit`; its `trajectory.cells` show chromium hero and morph
pass, webkit hero pass, webkit morph fail (all run 40872462216, `10-2x-earn-logical-preset.md` §2).

## 4. Site

`apps/site/src/registry/index.ts` serves `?preset=shipped`; `apps/site/src/registry/presets/shipped.test.ts` checks the
file against the golden, `v2-proved` ⊆ `shipped`, the decision rows, and that the preset resolves and renders. The site
default preset is not switched (lead decides after the user sees it).
