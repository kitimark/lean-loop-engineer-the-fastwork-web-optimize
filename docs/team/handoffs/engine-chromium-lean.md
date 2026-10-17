# engine-chromium-lean (handoff)
**Golden row schema** (`packages/contracts/golden/engine/chromium.jsonl`, 29 rows, keys sorted, one JSON per line):
- `{"kind":"signature","level","rank","stages":[stage…],"members":["<css-name>@<none|layer|own>"…]}`, one per `CrLevel`.
- `{"kind":"mode","mode":"lane|realChrome","threadedAnim","everyBeginFrameIsMainFrame","compStages":[…]}`.
- `{"kind":"stage","test":"F0|F1|F2","scenario","ref","mode":"lane","stage","counts":[count type…],"v","o","vUnits","oUnits","pred"}`:
  `v`/`o` = model passes per frame of scenario/ref (`vUnits`/`oUnits` = units), `pred ∈ {"=0","=o","<o","≤o","any"}`
  compares the scenario's per-frame count with the ref's (`predOf`: props → any; v<o → <o; v=o=0 → =0; v=o≠0 → ≤o;
  v>o → any). Scenarios = lane fixtures `rest`, `anim-compositor`, `anim-layout`. F0 rows read bit 0 of
  `trace.Animation.compositeFailedBits` (v = #animations with bit 0). Consumer drops quarantined count types.
**State:** `lean/Fw/Engine/Chromium.lean` + import in `lean/Fw/Engine.lean`, branch `worktree-agent-a963e4ca57a42b299`.
`lake build` green, mathview lint 0 failing, standard axioms only.
**API:** `CrKey` (plain props), `CrProp = css k | custom id readers | scroll repaint`, `CrLevel` chain
none<styleOnly<direct<ppFull<raster<paint<layoutPos<layoutFull, `keyLevel`, `crLevel` (custom = max over readers,
≥ styleOnly), `crStagesOf`, `CrMode`, `lane`, `realChrome`, `chromiumAt m`, `chromium := chromiumAt lane` (base = [],
compStages = comp (+ style, props when every BeginFrame is a main frame)). `CrAnim`, `failBits` (0,5,12,13,16),
`crThread`, `animFrame`, `jsWrite`, `cullPeriod`/`scrollPaints`/`scrollChange`.
**Theorems:** `crStages_mono`, `levelCover_coverB` (level ≤ pairwise → `coverB`), `custom_ge_reader`,
`custom_ge_styleOnly`, `foldl_max_ge`, `crThread_comp_iff`, `failBits_lane_no0` (F0), `compAnim_no_layout_paint`,
`transformAnim_comp`, `compTransform_no_layout_paint`, `jsTransform_le_topLeft` (via `frame_le_of_cover`),
`jsTransform_lt_topLeft`, `scrollPaints_moved` (paint ⇒ 512 ≤ k·d), `scroll_stages`.
**Regenerate golden:** no lakefile/script edit was allowed, so the exporter is `Fw.Engine.Chromium.goldenRun`; from
`lean/` run `lake env lean --run <file>` with `import Fw.Engine.Chromium` and
`def main (a : List String) : IO UInt32 := do return if (← Fw.Engine.Chromium.goldenRun "." (!a.contains "--check")) == 0 then 0 else 1`.
Open: add it as `lean/scripts/ChromiumGolden.lean` + a `lake test` check (lead decision).
**Open items:** paint-worklet compositing of background-color/clip-path not modelled (main here); units count
changes, not dirty objects/restyled subtree (R2); real-Chrome ride-along on main frames run for other reasons not
modelled; cull ratio r = 1 INFERRED; `raster` level and the lane's ride-along `props` INFERRED.
**Read first:** module doc of `Chromium.lean`, then design note §1.2/§3.3, then `Core.lean` `frame_le_of_cover`.
