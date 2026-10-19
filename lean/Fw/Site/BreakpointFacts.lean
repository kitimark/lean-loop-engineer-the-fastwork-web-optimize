import Fw.Site.Breakpoints

/-!
# Facts about the 30 breakpoint conditions

* `*_iff`: each condition, unfolded to plain mathematics (the statement the user reviews);
* `catalogue_css`, `catalogue_edges`, `catalogue_features`: the catalogue reproduces the inventory's normal-form
  strings byte for byte and its edge lists (the generator re-checks both against `breakpoints.json`);
* overlaps (§3 of the inventory), the fractional gaps, and the JS composite gates.

Notation in every formula: `w` viewport width, `d_w` device (screen) width, both in CSS px as non-negative
rationals; `η` hover, `π` pointer, `μ` reduced-motion preference, `σ` colour scheme;
`touch(e) :⇔ η = none ∧ π = coarse`.
-/

namespace Fw.Site.Breakpoints

/-! ## The catalogue matches the inventory -/

/-- The catalogue has the inventory's 30 media conditions.

There are exactly thirty conditions. -/
theorem catalogue_length : catalogue.length = 30 := by decide

/-- Inventory ids and TS ids are pairwise distinct.

No two conditions share a name. -/
theorem catalogue_ids_nodup : (catalogue.map (·.id)).Nodup ∧ (catalogue.map (·.tsId)).Nodup := by decide

/-- No two catalogue entries are the same query.

The thirty conditions are syntactically distinct. -/
theorem catalogue_queries_nodup : (catalogue.map (·.query)).Nodup := by decide

/-- **Byte-exact CSS.** The printed normal form of every condition equals the inventory's `condition` string
(`breakpoints.json`, schema `fw.breakpoints/1`, ids `mq.*`).

Each condition prints exactly as the inventory writes it, under the listed TS id. -/
theorem catalogue_css : catalogue.map (fun c => (c.id, c.tsId, c.query.css)) = [
  ("mq.rm-reduce", "rmReduce", "(prefers-reduced-motion: reduce)"),
  ("mq.rm-nopref", "rmNopref", "(prefers-reduced-motion: no-preference)"),
  ("mq.hover-hover", "hoverHover", "(hover: hover)"),
  ("mq.hover-none", "hoverNone", "(hover: none)"),
  ("mq.dark", "dark", "(prefers-color-scheme: dark)"),
  ("mq.w-le-400", "wLe400", "(width<=400px)"),
  ("mq.w-le-461", "wLe461", "(width<=461px)"),
  ("mq.w-le-480", "wLe480", "(width<=480px)"),
  ("mq.w-le-600", "wLe600", "(width<=600px)"),
  ("mq.w-gt-600", "wGt600", "(width>600px)"),
  ("mq.w-601-1279", "w601to1279", "(width>=601px) and (width<=1279px)"),
  ("mq.w-601-1511", "w601to1511", "(width>=601px) and (width<=1511px)"),
  ("mq.w-le-640", "wLe640", "(width<=640px)"),
  ("mq.w-gt-640", "wGt640", "(width>640px)"),
  ("mq.w-641-1000", "w641to1000", "(width>=641px) and (width<=1000px)"),
  ("mq.w-le-720", "wLe720", "(width<=720px)"),
  ("mq.w-le-860", "wLe860", "(width<=860px)"),
  ("mq.w-ge-861", "wGe861", "(width>=861px)"),
  ("mq.w-ge-861-nopref", "wGe861Nopref", "(width>=861px) and (prefers-reduced-motion: no-preference)"),
  ("mq.w-861-1000", "w861to1000", "(width>=861px) and (width<=1000px)"),
  ("mq.w-le-960", "wLe960", "(width<=960px)"),
  ("mq.w-le-1000", "wLe1000", "(width<=1000px)"),
  ("mq.w-ge-1001", "wGe1001", "(width>=1001px)"),
  ("mq.w-ge-1001-nopref", "wGe1001Nopref", "(width>=1001px) and (prefers-reduced-motion: no-preference)"),
  ("mq.w-le-1100", "wLe1100", "(width<=1100px)"),
  ("mq.w-le-1200", "wLe1200", "(width<=1200px)"),
  ("mq.c860", "c860", "(width<=860px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)"),
  ("mq.c1000", "c1000", "(width<=1000px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)"),
  ("mq.c1030", "c1030", "(width<=1030px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)"),
  ("mq.c1000-nodw", "c1000Nodw", "(width<=1000px), (hover: none) and (pointer: coarse) and (width<=1200px)")
] := by decide

/-- **Edges.** The tagged edges read off each condition's syntax equal the inventory's `edges` list (feature,
lower pixel of the pair `N | N+1`).

Every condition has exactly the edges the inventory lists, in the same order. -/
theorem catalogue_edges : catalogue.map (fun c => (c.id, c.query.taggedEdges.map fun (a, n) => (a.str, n))) = [
  ("mq.rm-reduce", []),
  ("mq.rm-nopref", []),
  ("mq.hover-hover", []),
  ("mq.hover-none", []),
  ("mq.dark", []),
  ("mq.w-le-400", [("width", 400)]),
  ("mq.w-le-461", [("width", 461)]),
  ("mq.w-le-480", [("width", 480)]),
  ("mq.w-le-600", [("width", 600)]),
  ("mq.w-gt-600", [("width", 600)]),
  ("mq.w-601-1279", [("width", 600), ("width", 1279)]),
  ("mq.w-601-1511", [("width", 600), ("width", 1511)]),
  ("mq.w-le-640", [("width", 640)]),
  ("mq.w-gt-640", [("width", 640)]),
  ("mq.w-641-1000", [("width", 640), ("width", 1000)]),
  ("mq.w-le-720", [("width", 720)]),
  ("mq.w-le-860", [("width", 860)]),
  ("mq.w-ge-861", [("width", 860)]),
  ("mq.w-ge-861-nopref", [("width", 860)]),
  ("mq.w-861-1000", [("width", 860), ("width", 1000)]),
  ("mq.w-le-960", [("width", 960)]),
  ("mq.w-le-1000", [("width", 1000)]),
  ("mq.w-ge-1001", [("width", 1000)]),
  ("mq.w-ge-1001-nopref", [("width", 1000)]),
  ("mq.w-le-1100", [("width", 1100)]),
  ("mq.w-le-1200", [("width", 1200)]),
  ("mq.c860", [("width", 860), ("device-width", 500), ("width(touch)", 1200)]),
  ("mq.c1000", [("width", 1000), ("device-width", 500), ("width(touch)", 1200)]),
  ("mq.c1030", [("width", 1030), ("device-width", 500), ("width(touch)", 1200)]),
  ("mq.c1000-nodw", [("width", 1000), ("width(touch)", 1200)])
] := by decide

/-- The width edges and device-width edges used by `MQ.eval_congr` are exactly the tagged edge pixels (per
axis), and the tagged edges are the inventory's by `catalogue_edges`.

(and `E(q_i) = E^inv_i` by `catalogue_edges`).

The edges in the sufficiency theorem are the tagged edges, hence the inventory's edges, no more and no fewer. -/
theorem catalogue_axis_edges : catalogue.all (fun c =>
    (c.query.widthEdges.all fun n => c.query.taggedEdges.any fun t => t.1 != .deviceWidth && t.2 == n) &&
    (c.query.taggedEdges.all fun t => t.1 == .deviceWidth || c.query.widthEdges.contains t.2) &&
    (c.query.dwEdges.all fun n => c.query.taggedEdges.contains (.deviceWidth, n)) &&
    (c.query.taggedEdges.all fun t => t.1 != .deviceWidth || c.query.dwEdges.contains t.2)) = true := by
  decide

/-! ## Each condition as mathematics -/

/-- `mq.rm-reduce` = `(prefers-reduced-motion: reduce)`.

The condition matches exactly when the motion preference is reduce. -/
theorem rmReduce_iff (e : Env) : rmReduce.Holds e ↔ e.motion = .reduce := by
  simp [MQ.Holds, MQ.eval, Feature.holds, rmReduce]

/-- `mq.rm-nopref` = `(prefers-reduced-motion: no-preference)`.

The condition matches exactly when the motion preference is no-preference. -/
theorem rmNopref_iff (e : Env) : rmNopref.Holds e ↔ e.motion = .noPreference := by
  simp [MQ.Holds, MQ.eval, Feature.holds, rmNopref]

/-- `mq.hover-hover` = `(hover: hover)`.

The condition matches exactly when the primary input's hover capability is hover. -/
theorem hoverHover_iff (e : Env) : hoverHover.Holds e ↔ e.hover = .hover := by
  simp [MQ.Holds, MQ.eval, Feature.holds, hoverHover]

/-- `mq.hover-none` = `(hover: none)`.

The condition matches exactly when the primary input's hover capability is none. -/
theorem hoverNone_iff (e : Env) : hoverNone.Holds e ↔ e.hover = .none := by
  simp [MQ.Holds, MQ.eval, Feature.holds, hoverNone]

/-- `mq.dark` = `(prefers-color-scheme: dark)`.

The condition matches exactly when the colour scheme is dark. -/
theorem dark_iff (e : Env) : dark.Holds e ↔ e.scheme = .dark := by
  simp [MQ.Holds, MQ.eval, Feature.holds, dark]

/-- `mq.w-le-400` = `(width<=400px)`.

The condition matches exactly when the viewport is at most 400 px wide. -/
theorem wLe400_iff (e : Env) : wLe400.Holds e ↔ e.width.LeNat 400 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, wLe400]

/-- `mq.w-le-461` = `(width<=461px)`.

The condition matches exactly when the viewport is at most 461 px wide. -/
theorem wLe461_iff (e : Env) : wLe461.Holds e ↔ e.width.LeNat 461 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, wLe461]

/-- `mq.w-le-480` = `(width<=480px)`.

The condition matches exactly when the viewport is at most 480 px wide. -/
theorem wLe480_iff (e : Env) : wLe480.Holds e ↔ e.width.LeNat 480 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, wLe480]

/-- `mq.w-le-600` = `(width<=600px)`.

The condition matches exactly when the viewport is at most 600 px wide. -/
theorem wLe600_iff (e : Env) : wLe600.Holds e ↔ e.width.LeNat 600 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, wLe600]

/-- `mq.w-gt-600` = `(width>600px)`.

The condition matches exactly when the viewport is wider than 600 px. -/
theorem wGt600_iff (e : Env) : wGt600.Holds e ↔ e.width.GtNat 600 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, wGt600]

/-- `mq.w-601-1279` = `(width>=601px) and (width<=1279px)`.

The condition matches exactly when the viewport is at least 601 px wide and the viewport is at most 1279 px wide. -/
theorem w601to1279_iff (e : Env) : w601to1279.Holds e ↔ e.width.GeNat 601 ∧ e.width.LeNat 1279 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, w601to1279]

/-- `mq.w-601-1511` = `(width>=601px) and (width<=1511px)`.

The condition matches exactly when the viewport is at least 601 px wide and the viewport is at most 1511 px wide. -/
theorem w601to1511_iff (e : Env) : w601to1511.Holds e ↔ e.width.GeNat 601 ∧ e.width.LeNat 1511 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, w601to1511]

/-- `mq.w-le-640` = `(width<=640px)`.

The condition matches exactly when the viewport is at most 640 px wide. -/
theorem wLe640_iff (e : Env) : wLe640.Holds e ↔ e.width.LeNat 640 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, wLe640]

/-- `mq.w-gt-640` = `(width>640px)`.

The condition matches exactly when the viewport is wider than 640 px. -/
theorem wGt640_iff (e : Env) : wGt640.Holds e ↔ e.width.GtNat 640 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, wGt640]

/-- `mq.w-641-1000` = `(width>=641px) and (width<=1000px)`.

The condition matches exactly when the viewport is at least 641 px wide and the viewport is at most 1000 px wide. -/
theorem w641to1000_iff (e : Env) : w641to1000.Holds e ↔ e.width.GeNat 641 ∧ e.width.LeNat 1000 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, w641to1000]

/-- `mq.w-le-720` = `(width<=720px)`.

The condition matches exactly when the viewport is at most 720 px wide. -/
theorem wLe720_iff (e : Env) : wLe720.Holds e ↔ e.width.LeNat 720 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, wLe720]

/-- `mq.w-le-860` = `(width<=860px)`.

The condition matches exactly when the viewport is at most 860 px wide. -/
theorem wLe860_iff (e : Env) : wLe860.Holds e ↔ e.width.LeNat 860 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, wLe860]

/-- `mq.w-ge-861` = `(width>=861px)`.

The condition matches exactly when the viewport is at least 861 px wide. -/
theorem wGe861_iff (e : Env) : wGe861.Holds e ↔ e.width.GeNat 861 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, wGe861]

/-- `mq.w-ge-861-nopref` = `(width>=861px) and (prefers-reduced-motion: no-preference)`.

The condition matches exactly when the viewport is at least 861 px wide and the motion preference is no-preference. -/
theorem wGe861Nopref_iff (e : Env) : wGe861Nopref.Holds e ↔ e.width.GeNat 861 ∧ e.motion = .noPreference := by
  simp [MQ.Holds, MQ.eval, Feature.holds, wGe861Nopref]

/-- `mq.w-861-1000` = `(width>=861px) and (width<=1000px)`.

The condition matches exactly when the viewport is at least 861 px wide and the viewport is at most 1000 px wide. -/
theorem w861to1000_iff (e : Env) : w861to1000.Holds e ↔ e.width.GeNat 861 ∧ e.width.LeNat 1000 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, w861to1000]

/-- `mq.w-le-960` = `(width<=960px)`.

The condition matches exactly when the viewport is at most 960 px wide. -/
theorem wLe960_iff (e : Env) : wLe960.Holds e ↔ e.width.LeNat 960 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, wLe960]

/-- `mq.w-le-1000` = `(width<=1000px)`.

The condition matches exactly when the viewport is at most 1000 px wide. -/
theorem wLe1000_iff (e : Env) : wLe1000.Holds e ↔ e.width.LeNat 1000 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, wLe1000]

/-- `mq.w-ge-1001` = `(width>=1001px)`.

The condition matches exactly when the viewport is at least 1001 px wide. -/
theorem wGe1001_iff (e : Env) : wGe1001.Holds e ↔ e.width.GeNat 1001 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, wGe1001]

/-- `mq.w-ge-1001-nopref` = `(width>=1001px) and (prefers-reduced-motion: no-preference)`.

The condition matches exactly when the viewport is at least 1001 px wide and the motion preference is no-preference. -/
theorem wGe1001Nopref_iff (e : Env) : wGe1001Nopref.Holds e ↔ e.width.GeNat 1001 ∧ e.motion = .noPreference := by
  simp [MQ.Holds, MQ.eval, Feature.holds, wGe1001Nopref]

/-- `mq.w-le-1100` = `(width<=1100px)`.

The condition matches exactly when the viewport is at most 1100 px wide. -/
theorem wLe1100_iff (e : Env) : wLe1100.Holds e ↔ e.width.LeNat 1100 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, wLe1100]

/-- `mq.w-le-1200` = `(width<=1200px)`.

The condition matches exactly when the viewport is at most 1200 px wide. -/
theorem wLe1200_iff (e : Env) : wLe1200.Holds e ↔ e.width.LeNat 1200 := by
  simp [MQ.Holds, MQ.eval, Feature.holds, wLe1200]

/-- `mq.c860` = `(width<=860px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)`.

The condition matches exactly when the viewport is at most 860 px wide; or the screen is at most 500 px wide; or the primary input's hover capability is none and the primary pointer is coarse and the viewport is at most 1200 px wide. -/
theorem c860_iff (e : Env) : c860.Holds e ↔ e.width.LeNat 860 ∨ e.deviceWidth.LeNat 500 ∨ (e.hover = .none ∧ e.pointer = .coarse ∧ e.width.LeNat 1200) := by
  simp [MQ.Holds, MQ.eval, Feature.holds, c860, combo, touchArm]

/-- `mq.c1000` = `(width<=1000px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)`.

The condition matches exactly when the viewport is at most 1000 px wide; or the screen is at most 500 px wide; or the primary input's hover capability is none and the primary pointer is coarse and the viewport is at most 1200 px wide. -/
theorem c1000_iff (e : Env) : c1000.Holds e ↔ e.width.LeNat 1000 ∨ e.deviceWidth.LeNat 500 ∨ (e.hover = .none ∧ e.pointer = .coarse ∧ e.width.LeNat 1200) := by
  simp [MQ.Holds, MQ.eval, Feature.holds, c1000, combo, touchArm]

/-- `mq.c1030` = `(width<=1030px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)`.

The condition matches exactly when the viewport is at most 1030 px wide; or the screen is at most 500 px wide; or the primary input's hover capability is none and the primary pointer is coarse and the viewport is at most 1200 px wide. -/
theorem c1030_iff (e : Env) : c1030.Holds e ↔ e.width.LeNat 1030 ∨ e.deviceWidth.LeNat 500 ∨ (e.hover = .none ∧ e.pointer = .coarse ∧ e.width.LeNat 1200) := by
  simp [MQ.Holds, MQ.eval, Feature.holds, c1030, combo, touchArm]

/-- `mq.c1000-nodw` = `(width<=1000px), (hover: none) and (pointer: coarse) and (width<=1200px)`.

The condition matches exactly when the viewport is at most 1000 px wide; or the primary input's hover capability is none and the primary pointer is coarse and the viewport is at most 1200 px wide. -/
theorem c1000Nodw_iff (e : Env) : c1000Nodw.Holds e ↔ e.width.LeNat 1000 ∨ (e.hover = .none ∧ e.pointer = .coarse ∧ e.width.LeNat 1200) := by
  simp [MQ.Holds, MQ.eval, Feature.holds, c1000Nodw, combo, touchArm]

/-- `omega` after recording that the width and device-width denominators of the `Env` in context are positive. -/
local macro "pomega" : tactic =>
  `(tactic| (have _ := (‹Env›).width.den_pos; have _ := (‹Env›).deviceWidth.den_pos; omega))

/-! ## Inputs no condition reads -/

/-- Height, device height and DPR never change any condition.

The page has no height, device-height or resolution media query, so these inputs never change a media condition
(height can still change layout through vh units and JS viewport-height reads). -/
theorem MQ.eval_indep_height_dpr (q : MQ) (e : Env) (h dh r : Px) :
    q.eval { e with height := h, deviceHeight := dh, dpr := r } = q.eval e :=
  MQ.eval_congr ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩ (fun _ _ => ⟨Iff.rfl, Iff.rfl⟩) (fun _ _ => ⟨Iff.rfl, Iff.rfl⟩)

/-! ## Combos -/

/-- The touch predicate: primary input cannot hover and has a coarse pointer.

A phone or tablet in the media-query sense. -/
def Touch (e : Env) : Prop := e.hover = .none ∧ e.pointer = .coarse

/-- The combos are nested: combo 860 implies combo 1000, which implies combo 1030.

A wider combo matches wherever a narrower one does. -/
theorem c860_le_c1000_le_c1030 (e : Env) :
    (c860.Holds e → c1000.Holds e) ∧ (c1000.Holds e → c1030.Holds e) := by
  rw [c860_iff, c1000_iff, c1030_iff]
  simp only [Px.LeNat]
  constructor
  · rintro (h | h | h)
    · exact Or.inl (by pomega)
    · exact Or.inr (Or.inl h)
    · exact Or.inr (Or.inr h)
  · rintro (h | h | h)
    · exact Or.inl (by pomega)
    · exact Or.inr (Or.inl h)
    · exact Or.inr (Or.inr h)

/-- `c1000Nodw` implies `c1000`, and they differ exactly for a small screen, a viewport above 1000 px, and no
matching touch arm.

The countdown's combo is the commission combo minus the device-width arm, and only that arm separates them. -/
theorem c1000Nodw_vs_c1000 (e : Env) :
    (c1000Nodw.Holds e → c1000.Holds e) ∧
    (c1000.Holds e ∧ ¬ c1000Nodw.Holds e ↔
      e.deviceWidth.LeNat 500 ∧ e.width.GtNat 1000 ∧ ¬ (Touch e ∧ e.width.LeNat 1200)) := by
  rw [c1000_iff, c1000Nodw_iff]
  simp only [Touch, Px.LeNat, Px.GtNat]
  constructor
  · rintro (h | h)
    · exact Or.inl h
    · exact Or.inr (Or.inr h)
  · constructor
    · rintro ⟨h | h | h, hn⟩
      · exact absurd (Or.inl h) hn
      · refine ⟨h, ?_, ?_⟩
        · have : ¬ e.width.num ≤ 1000 * e.width.den := fun h' => hn (Or.inl h')
          pomega
        · rintro ⟨⟨a, b⟩, c⟩; exact hn (Or.inr ⟨a, b, c⟩)
      · exact absurd (Or.inr h) hn
    · rintro ⟨h1, h2, h3⟩
      refine ⟨Or.inr (Or.inl h1), ?_⟩
      rintro (h | ⟨a, b, c⟩)
      · pomega
      · exact h3 ⟨⟨a, b⟩, c⟩

/-! ## Overlaps (inventory §3, `overlaps` in the JSON) -/

/-- **Overlap C860 / `>=861`.** Both match exactly on a viewport of at least 861 px with a small screen or a
touch input up to 1200 px.

A touch tablet at 861-1200 px or a phone in landscape takes both the compact and the desktop rules. -/
theorem overlap_c860_wGe861 (e : Env) :
    c860.Holds e ∧ wGe861.Holds e ↔
      e.width.GeNat 861 ∧ (e.deviceWidth.LeNat 500 ∨ (Touch e ∧ e.width.LeNat 1200)) := by
  rw [c860_iff, wGe861_iff]
  simp only [Touch, Px.LeNat, Px.GeNat]
  constructor
  · rintro ⟨h | h | ⟨a, b, c⟩, hw⟩
    · pomega
    · exact ⟨hw, Or.inl h⟩
    · exact ⟨hw, Or.inr ⟨⟨a, b⟩, c⟩⟩
  · rintro ⟨hw, h | ⟨⟨a, b⟩, c⟩⟩
    · exact ⟨Or.inr (Or.inl h), hw⟩
    · exact ⟨Or.inr (Or.inr ⟨a, b, c⟩), hw⟩

/-- **Overlap C1000 / `>=1001`.** Both match exactly on a viewport of at least 1001 px with a small screen or a
touch input up to 1200 px.

Commission compact and the desktop platform mission title apply together on a touch tablet at 1001-1200 px. -/
theorem overlap_c1000_wGe1001 (e : Env) :
    c1000.Holds e ∧ wGe1001.Holds e ↔
      e.width.GeNat 1001 ∧ (e.deviceWidth.LeNat 500 ∨ (Touch e ∧ e.width.LeNat 1200)) := by
  rw [c1000_iff, wGe1001_iff]
  simp only [Touch, Px.LeNat, Px.GeNat]
  constructor
  · rintro ⟨h | h | ⟨a, b, c⟩, hw⟩
    · pomega
    · exact ⟨hw, Or.inl h⟩
    · exact ⟨hw, Or.inr ⟨⟨a, b⟩, c⟩⟩
  · rintro ⟨hw, h | ⟨⟨a, b⟩, c⟩⟩
    · exact ⟨Or.inr (Or.inl h), hw⟩
    · exact ⟨Or.inr (Or.inr ⟨a, b, c⟩), hw⟩

/-- **Overlap C1000 / `>=1001 and no-preference`.** As `overlap_c1000_wGe1001`, plus motion allowed.

The sticky desktop commission and the compact commission both match on a touch tablet at 1001-1200 px with motion on. -/
theorem overlap_c1000_wGe1001Nopref (e : Env) :
    c1000.Holds e ∧ wGe1001Nopref.Holds e ↔
      e.width.GeNat 1001 ∧ e.motion = .noPreference ∧
        (e.deviceWidth.LeNat 500 ∨ (Touch e ∧ e.width.LeNat 1200)) := by
  have h := overlap_c1000_wGe1001 e
  rw [wGe1001_iff] at h
  rw [wGe1001Nopref_iff]
  constructor
  · rintro ⟨hc, hw, hm⟩
    obtain ⟨hw', hx⟩ := h.mp ⟨hc, hw⟩
    exact ⟨hw', hm, hx⟩
  · rintro ⟨hw, hm, hx⟩
    exact ⟨(h.mpr ⟨hw, hx⟩).1, hw, hm⟩

/-- **Never mix pure 860 and C860.** C860 holds while `(width<=860px)` fails exactly above 860 px with a small
screen or a touch input up to 1200 px.

Pure-width users take the desktop path where combo users take the compact path, so one cannot stand in for the other. -/
theorem c860_not_wLe860 (e : Env) :
    c860.Holds e ∧ ¬ wLe860.Holds e ↔
      e.width.GtNat 860 ∧ (e.deviceWidth.LeNat 500 ∨ (Touch e ∧ e.width.LeNat 1200)) := by
  rw [c860_iff, wLe860_iff]
  simp only [Touch, Px.LeNat, Px.GtNat]
  constructor
  · rintro ⟨h | h | ⟨a, b, c⟩, hn⟩
    · exact absurd h hn
    · exact ⟨by pomega, Or.inl h⟩
    · exact ⟨by pomega, Or.inr ⟨⟨a, b⟩, c⟩⟩
  · rintro ⟨hw, h | ⟨⟨a, b⟩, c⟩⟩
    · exact ⟨Or.inr (Or.inl h), by pomega⟩
    · exact ⟨Or.inr (Or.inr ⟨a, b, c⟩), by pomega⟩

/-- `(width<=860px)` implies C860 (the converse fails, see `c860_not_wLe860`).

Every phone-width viewport is also in the combo. -/
theorem wLe860_imp_c860 (e : Env) : wLe860.Holds e → c860.Holds e := by
  rw [c860_iff, wLe860_iff]; exact Or.inl

/-! ## JS composite gates (inventory §3) -/

/-- The desktop scroll-driven deck gate (`N2:10783`): `>=861` and not C860 and not reduced motion.

The JS check that picks the desktop people deck. -/
def DeskDeck (e : Env) : Prop := wGe861.Holds e ∧ ¬ c860.Holds e ∧ ¬ rmReduce.Holds e

/-- The desktop deck runs exactly on a viewport of at least 861 px, a screen wider than 500 px, no touch arm,
and motion allowed.

The JS resolves the CSS overlap in favour of the compact deck on touch tablets and small screens. -/
theorem deskDeck_iff (e : Env) :
    DeskDeck e ↔ e.width.GeNat 861 ∧ e.deviceWidth.GtNat 500 ∧ ¬ (Touch e ∧ e.width.LeNat 1200) ∧
      e.motion ≠ .reduce := by
  unfold DeskDeck
  rw [wGe861_iff, c860_iff, rmReduce_iff]
  simp only [Touch, Px.LeNat, Px.GeNat, Px.GtNat]
  constructor
  · rintro ⟨hw, hc, hm⟩
    refine ⟨hw, ?_, fun ⟨⟨a, b⟩, c⟩ => hc (Or.inr (Or.inr ⟨a, b, c⟩)), hm⟩
    have : ¬ e.deviceWidth.num ≤ 500 * e.deviceWidth.den := fun h => hc (Or.inr (Or.inl h))
    pomega
  · rintro ⟨hw, hd, ht, hm⟩
    refine ⟨hw, ?_, hm⟩
    rintro (h | h | ⟨a, b, c⟩)
    · pomega
    · pomega
    · exact ht ⟨⟨a, b⟩, c⟩

/-- On a touch tablet at 861-1200 px the CSS overlap holds and the JS desktop deck is off.

Touch tablets get the compact JS deck while both CSS paths match. -/
theorem touchTablet_overlap (e : Env) (ht : Touch e) (h1 : e.width.GeNat 861) (h2 : e.width.LeNat 1200) :
    c860.Holds e ∧ wGe861.Holds e ∧ ¬ DeskDeck e :=
  ⟨((overlap_c860_wGe861 e).mpr ⟨h1, Or.inr ⟨ht, h2⟩⟩).1, ((overlap_c860_wGe861 e).mpr ⟨h1, Or.inr ⟨ht, h2⟩⟩).2,
   fun hd => ((deskDeck_iff e).mp hd).2.2.1 ⟨ht, h2⟩⟩

/-- On a small screen (phone landscape) above 860 px the CSS overlap holds and the JS desktop deck is off.

A phone in landscape takes both CSS paths and the compact JS deck. -/
theorem smallScreen_overlap (e : Env) (hd : e.deviceWidth.LeNat 500) (h1 : e.width.GeNat 861) :
    c860.Holds e ∧ wGe861.Holds e ∧ ¬ DeskDeck e := by
  refine ⟨((overlap_c860_wGe861 e).mpr ⟨h1, Or.inl hd⟩).1, ((overlap_c860_wGe861 e).mpr ⟨h1, Or.inl hd⟩).2, ?_⟩
  intro hdd
  have := ((deskDeck_iff e).mp hdd).2.1
  simp only [Px.LeNat, Px.GtNat] at hd this
  pomega

/-- The JS splash / chrome gate: `(max-width: 600px)` OR reduced motion.

The ring splash is skipped (and the nav chrome is ready at once) on phone widths or with reduced motion. -/
def SplashSkip (e : Env) : Prop := wLe600.Holds e ∨ rmReduce.Holds e

/-! ## Fractional gaps (inventory §3, `fractionalGaps`) -/

/-- **The gaps are real.** For every edge `N`, a width strictly between `N` and `N+1` matches neither
`(width<=Npx)` nor `(width>=N+1px)`, and those are exactly the widths that match neither.

Between the last pixel of a band and the first pixel of the next lies an open interval that neither side claims. -/
theorem gap_iff (N : Nat) (w : Px) :
    (¬ w.LeNat N ∧ ¬ w.GeNat (N + 1) ↔ w.GtNat N ∧ ¬ w.GeNat (N + 1)) ∧
      (Px.half N).GtNat N ∧ ¬ (Px.half N).GeNat (N + 1) := by
  simp only [Px.LeNat, Px.GeNat, Px.GtNat, Px.half]
  refine ⟨⟨fun ⟨a, b⟩ => ⟨by omega, b⟩, fun ⟨a, b⟩ => ⟨by omega, b⟩⟩, by omega, by omega⟩

/-- At whole-pixel widths there is no gap: `(width<=Npx)` and `(width>=N+1px)` are complementary.

Integer probes can never land in a fractional gap. -/
theorem no_gap_ofNat (N k : Nat) : (Px.ofNat k).LeNat N ↔ ¬ (Px.ofNat k).GeNat (N + 1) := by
  simp only [Px.LeNat, Px.GeNat, Px.ofNat]; omega

/-- A length of value `N + 1/2` lies strictly between `N` and `N+1`, in any representation.

A half-pixel width is never a whole pixel and never reaches the next one. -/
theorem half_bounds (N x y : Nat) (h : 2 * x = (2 * N + 1) * y) (hy : 0 < y) : N * y < x ∧ x < (N + 1) * y := by
  constructor <;> grind

/-- The probe `Px.half N` has value `N + 1/2` in the form the gap theorems take.

`Px.half N` satisfies the hypothesis of `gap600` … `gap1000` for its `N`. -/
theorem half_value (N : Nat) : 2 * (Px.half N).num = (2 * N + 1) * (Px.half N).den :=
  Nat.mul_comm 2 (2 * N + 1)

/-- Gap 600 at any width whose value is 600.5: `<=600`, `601-1279` and `601-1511` all fail, while `>600` matches.

At 600.5 px (in any representation, e.g. `Px.half 600` or 2402/4) the hero has neither its phone rules nor its 601+
orbit rules, but `>600` rules apply. -/
theorem gap600 (e : Env) (h : 2 * e.width.num = 1201 * e.width.den) :
    ¬ wLe600.Holds e ∧ ¬ w601to1279.Holds e ∧ ¬ w601to1511.Holds e ∧ wGt600.Holds e := by
  rw [wLe600_iff, w601to1279_iff, w601to1511_iff, wGt600_iff]
  simp only [Px.LeNat, Px.GeNat, Px.GtNat]
  obtain ⟨_, _⟩ := half_bounds 600 _ _ h e.width.den_pos
  clear h
  and_intros <;> omega

/-- Gap 640 at any width whose value is 640.5: `<=640` and `641-1000` fail, while `>640` matches.

At 640.5 px (in any representation) neither the phone geometry nor the commission tablet band applies, but the
`>640` nav background does. -/
theorem gap640 (e : Env) (h : 2 * e.width.num = 1281 * e.width.den) :
    ¬ wLe640.Holds e ∧ ¬ w641to1000.Holds e ∧ wGt640.Holds e := by
  rw [wLe640_iff, w641to1000_iff, wGt640_iff]
  simp only [Px.LeNat, Px.GeNat, Px.GtNat]
  obtain ⟨_, _⟩ := half_bounds 640 _ _ h e.width.den_pos
  clear h
  and_intros <;> omega

/-- Gap 860 at any width whose value is 860.5: `<=860`, `>=861`, `>=861 and no-preference` and `861-1000` all fail.

At 860.5 px (in any representation) neither the pure-width phone path nor the desktop path matches, in CSS and
in JS. -/
theorem gap860 (e : Env) (h : 2 * e.width.num = 1721 * e.width.den) :
    ¬ wLe860.Holds e ∧ ¬ wGe861.Holds e ∧ ¬ wGe861Nopref.Holds e ∧ ¬ w861to1000.Holds e := by
  rw [wLe860_iff, wGe861_iff, wGe861Nopref_iff, w861to1000_iff]
  simp only [Px.LeNat, Px.GeNat]
  obtain ⟨_, _⟩ := half_bounds 860 _ _ h e.width.den_pos
  clear h
  and_intros <;> omega

/-- Gap 1000 at any width whose value is 1000.5: `<=1000`, `>=1001`, `>=1001 and no-preference`, `641-1000` and
`861-1000` all fail (the combos `c1000` and `c1000-nodw` lose their `(width<=1000px)` arm).

At 1000.5 px (in any representation) none of the five rules (width<=1000px), (width>=1001px), (width>=1001px) and
no-preference, 641-1000 and 861-1000 matches; the combos c1000 / c1000-nodw lose their (width<=1000px) arm but can
still match through the device-width or touch arm. -/
theorem gap1000 (e : Env) (h : 2 * e.width.num = 2001 * e.width.den) :
    ¬ wLe1000.Holds e ∧ ¬ wGe1001.Holds e ∧ ¬ wGe1001Nopref.Holds e ∧ ¬ w641to1000.Holds e ∧
      ¬ w861to1000.Holds e := by
  rw [wLe1000_iff, wGe1001_iff, wGe1001Nopref_iff, w641to1000_iff, w861to1000_iff]
  simp only [Px.LeNat, Px.GeNat]
  obtain ⟨_, _⟩ := half_bounds 1000 _ _ h e.width.den_pos
  clear h
  and_intros <;> omega

end Fw.Site.Breakpoints
