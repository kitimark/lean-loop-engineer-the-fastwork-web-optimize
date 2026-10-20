import Fw.Engine.Core

/-!
# Lessons: why optimizations win, trade, give nothing or lose (research/findings/ledger.json)

The ledger's recurring lessons, lifted from single parts to theorems over every engine `E` (any `stagesOf`,
`compStages`, `base`). Each section names the ledger findings (`n`) it explains.

* **L1** moving a change to the compositor: lowers only stages outside `compStages`, never a `compStages` pass, and
  adds a `comp` unit; resident growth rules out "dominates" (n=6, 10, 11, 15, 23).
* **L2** a shift moves work and never removes it: framewise `≤` plus equal totals forces framewise equality, so an
  equal-total change is never a framewise win (n=12, 17, 21).
* **L3** a change confined to `Resident` (layer state only) leaves every per-frame count equal; the screen says
  "equal" and the claim is "noClaim" (n=7, 13, 14).
* **L4** removing a change whose stages the rest of the frame already touches saves no pass, only units
  (n=8, 11, 20, 22).
* **L5** pausing a compositor animation changes nothing outside `compStages`; with `compStages ⊆ {comp}` it saves no
  main-thread work (n=14, 25).
* **L6** removing one read saves a pass only when the flag is dirty at the read and the next flag access is a write;
  the batching closed form (n=1, 2, 22) lives in `Fw.Engine.Core` (`flagTotal_closed`, `flagTotal_remove_check`).
-/

namespace Fw.Engine

/-! ## Frame edits -/

/-- Add one main-thread change to a frame.

The frame with one more property change. -/
def FrameIn.addChange {P : Type} (f : FrameIn P) (c : Change P) : FrameIn P := { f with changes := c :: f.changes }

/-- Add one running compositor animation to a frame.

The frame with one more compositor animation. -/
def FrameIn.addAnim {P : Type} (f : FrameIn P) : FrameIn P := { f with compAnims := f.compAnims + 1 }

/-- A frame that updates keeps updating after a change is added, and a frame with a change always updates.

Adding a change always makes a rendering update. -/
theorem updates_addChange {P : Type} (f : FrameIn P) (c : Change P) : (f.addChange c).updates = true := by
  simp [FrameIn.addChange, FrameIn.updates]

/-- The stages touched after adding a change to an updating frame: the old ones plus the change's.

A change on an updating frame adds only its own stages. -/
theorem mem_touched_addChange {P M : Type} (E : Engine P M) (f : FrameIn P) (c : Change P) (s : Stage)
    (hu : f.updates = true) : s ∈ touched E (f.addChange c) ↔ s ∈ E.stagesOf c ∨ s ∈ touched E f := by
  have h2 : (f.addChange c).updates = true := updates_addChange f c
  have e1 : touched E (f.addChange c) = (c :: f.changes).flatMap E.stagesOf ++
      (if 0 < f.compAnims then E.compStages else []) ++ E.base ++ (if 0 < f.script then [.script] else []) := by
    unfold touched; rw [h2]; rfl
  have e2 : touched E f = f.changes.flatMap E.stagesOf ++
      (if 0 < f.compAnims then E.compStages else []) ++ E.base ++ (if 0 < f.script then [.script] else []) := by
    unfold touched; rw [hu]; rfl
  rw [e1, e2]
  simp only [List.flatMap_cons, List.mem_append]
  grind

/-- The stages touched after adding a compositor animation: the old ones plus `compStages`.

An animation adds only the compositor stages. -/
theorem mem_touched_addAnim {P M : Type} (E : Engine P M) (f : FrameIn P) (s : Stage) :
    s ∈ touched E f.addAnim ↔ s ∈ E.compStages ∨ s ∈ touched E f := by
  have e1 : touched E f.addAnim = f.changes.flatMap E.stagesOf ++ E.compStages ++
      (if f.updates then E.base else []) ++ (if 0 < f.script then [.script] else []) := by
    unfold touched; simp only [show 0 < f.addAnim.compAnims from Nat.succ_pos _, ↓reduceIte]; rfl
  rw [e1]
  unfold touched
  simp only [List.mem_append]
  by_cases h0 : 0 < f.compAnims
  · simp only [h0, ↓reduceIte]; grind
  · simp only [h0, ↓reduceIte, List.not_mem_nil, or_false]; grind

/-! ## L4: absorption (n=8, 11, 20, 22) -/

/-- **Pass absorption.** On an updating frame, adding a change adds a pass on stage `s` exactly when the change dirties
`s` and the frame did not touch `s` yet; its units grow by one on every stage the change dirties.

A change whose stages already run that frame costs units, not passes. -/
theorem passes_absorb {P M : Type} (E : Engine P M) (f : FrameIn P) (c : Change P) (s : Stage)
    (hu : f.updates = true) :
    (frameWork E (f.addChange c)).passes s =
        (frameWork E f).passes s + (if s ∈ E.stagesOf c ∧ s ∉ touched E f then 1 else 0) ∧
      stageUnits E (f.addChange c) s = stageUnits E f s + (if s ∈ E.stagesOf c then 1 else 0) := by
  have hm := mem_touched_addChange E f c s hu
  constructor
  · simp only [frameWork]
    have hf : forcedPasses (f.addChange c) s = forcedPasses f s := by
      cases s <;> rfl
    rw [hf]
    by_cases h1 : s ∈ touched E f
    · have : s ∈ touched E (f.addChange c) := hm.mpr (.inr h1)
      simp [h1, this]
    · by_cases h2 : s ∈ E.stagesOf c
      · have : s ∈ touched E (f.addChange c) := hm.mpr (.inl h2)
        simp [h1, h2, this]; omega
      · have : s ∉ touched E (f.addChange c) := fun h => (hm.mp h).elim h2 h1
        simp [h1, h2, this]
  · simp only [stageUnits, FrameIn.addChange, List.countP_cons]
    by_cases h2 : s ∈ E.stagesOf c <;> simp [h2] <;> omega

/-- **Absorption as stated in the ledger (n=8, 11).** If the added change's stages are among the stages the frame's
other changes dirty, and the frame has a change, every pass count is unchanged.

A change riding on a dominant change saves nothing when dropped. -/
theorem passes_absorb_changes {P M : Type} (E : Engine P M) (f : FrameIn P) (c : Change P)
    (hsub : ∀ s ∈ E.stagesOf c, s ∈ f.changes.flatMap E.stagesOf) (hne : f.changes ≠ []) :
    ∀ s, (frameWork E (f.addChange c)).passes s = (frameWork E f).passes s := by
  intro s
  have hu : f.updates = true := by
    cases h : f.changes with
    | nil => exact absurd h hne
    | cons _ _ => simp [FrameIn.updates, h]
  rw [(passes_absorb E f c s hu).1]
  have : ¬ (s ∈ E.stagesOf c ∧ s ∉ touched E f) := by
    rintro ⟨h1, h2⟩
    exact h2 (by simp only [touched, List.mem_append]; exact .inl (.inl (.inl (hsub s h1))))
  simp [this]

/-- **Removal form (n=22), with the hypothesis it needs.** Removing a change whose stages the remaining frame already
touches leaves every pass count equal, provided the remaining frame still updates. Without that hypothesis the
ledger's form fails: a change with no stages, removed from a frame where it is the only change and no callback runs,
drops the `base` stages (WebKit `commit`), as `absorb_needs_updates` shows.

Dropping an absorbed change saves no pass. -/
theorem passes_remove_absorbed {P M : Type} (E : Engine P M) (f : FrameIn P) (c : Change P)
    (hu : f.updates = true) (hsub : ∀ s ∈ E.stagesOf c, s ∈ touched E f) :
    ∀ s, (frameWork E (f.addChange c)).passes s = (frameWork E f).passes s := by
  intro s
  rw [(passes_absorb E f c s hu).1]
  have : ¬ (s ∈ E.stagesOf c ∧ s ∉ touched E f) := fun ⟨h1, h2⟩ => h2 (hsub s h1)
  simp [this]

/-- A one-engine witness: `commit` in `base`, no stages for the change.

A WebKit-like engine where every update pays `commit`. -/
def absorbWitnessE : Engine Unit Unit := ⟨(), fun _ => [], [.comp], [.commit]⟩

/-- **The removal form needs `updates`.** With an empty frame and a stage-less change, removing the change drops the
`commit` pass although the change's stage set is empty (so trivially covered).

The rendering update itself costs passes. -/
theorem absorb_needs_updates :
    (frameWork absorbWitnessE (FrameIn.addChange ⟨0, 0, 0, 0, [], 0⟩ ⟨0, (), .none⟩)).passes .commit = 1 ∧
      (frameWork absorbWitnessE (⟨0, 0, 0, 0, [], 0⟩ : FrameIn Unit)).passes .commit = 0 := by
  decide

/-! ## L1: moving a change to the compositor (n=6, 10, 11, 15, 23) -/

/-- **Off the compositor stages, the move never costs more.** Replacing a main-thread change `c` by a compositor
animation does not raise passes or units on any stage outside `compStages`.

The saving lives outside the compositor stages. -/
theorem comp_move_le_off {P M : Type} (E : Engine P M) (f : FrameIn P) (c : Change P) (s : Stage)
    (hs : s ∉ E.compStages) :
    (frameWork E f.addAnim).passes s ≤ (frameWork E (f.addChange c)).passes s ∧
      stageUnits E f.addAnim s ≤ stageUnits E (f.addChange c) s := by
  have ha := mem_touched_addAnim E f s
  have hf1 : forcedPasses f.addAnim s = forcedPasses f s := by cases s <;> rfl
  have hf2 : forcedPasses (f.addChange c) s = forcedPasses f s := by cases s <;> rfl
  constructor
  · simp only [frameWork, hf1, hf2]
    by_cases h : s ∈ touched E f.addAnim
    · have hf : s ∈ touched E f := (ha.mp h).resolve_left hs
      have hc : s ∈ touched E (f.addChange c) := by
        simp only [touched, List.mem_append, FrameIn.addChange, List.mem_flatMap, List.mem_cons] at hf ⊢
        rcases hf with (((⟨d, hd, h⟩ | h) | h) | h)
        · exact .inl (.inl (.inl ⟨d, .inr hd, h⟩))
        · exact .inl (.inl (.inr h))
        · left; right
          split at h
          · simp only [FrameIn.updates, List.isEmpty_cons] at *; simpa using h
          · simp at h
        · exact .inr h
      simp [h, hc]
    · simp only [h, ↓reduceIte]; omega
  · simp only [stageUnits, FrameIn.addAnim, FrameIn.addChange, hs, ↓reduceIte, List.countP_cons]
    split <;> omega

/-- **On the compositor stages, the move never saves a pass.** Every `compStages` stage runs in the animated frame,
so its pass count is at least the main-thread variant's.

In the Chromium lane, where `compStages` holds `style`, the per-frame style pass never drops. -/
theorem comp_move_ge_on {P M : Type} (E : Engine P M) (f : FrameIn P) (c : Change P) (s : Stage)
    (hs : s ∈ E.compStages) :
    (frameWork E (f.addChange c)).passes s ≤ (frameWork E f.addAnim).passes s := by
  have ha : s ∈ touched E f.addAnim := (mem_touched_addAnim E f s).mpr (.inl hs)
  have hf1 : forcedPasses f.addAnim s = forcedPasses f s := by cases s <;> rfl
  have hf2 : forcedPasses (f.addChange c) s = forcedPasses f s := by cases s <;> rfl
  simp only [frameWork, hf1, hf2, ha, ↓reduceIte]
  split <;> omega

/-- **The move adds a compositor unit.** When `comp` is a compositor stage and the main-thread change does not dirty
`comp`, the animated frame has one more `comp` unit, so it is never framewise `≤` the main-thread frame.

A compositor move is a trade of stages, never a framewise win, unless the original already paid `comp`. -/
theorem comp_move_not_le {P M : Type} (E : Engine P M) (f : FrameIn P) (c : Change P)
    (hc : Stage.comp ∈ E.compStages) (hn : Stage.comp ∉ E.stagesOf c) :
    stageUnits E f.addAnim .comp = stageUnits E (f.addChange c) .comp + 1 ∧
      ¬ (frameWork E f.addAnim).le (frameWork E (f.addChange c)) := by
  have hu : stageUnits E f.addAnim .comp = stageUnits E (f.addChange c) .comp + 1 := by
    simp only [stageUnits, FrameIn.addAnim, FrameIn.addChange, hc, ↓reduceIte, List.countP_cons, hn,
      decide_false]
    simp; omega
  refine ⟨hu, fun h => ?_⟩
  have := (h.1 .comp).2
  simp only [frameWork] at this
  omega

/-- **Resident growth rules out "dominates".** Whatever the screen says, a variant with more composited layers never
gets the claim "dominates"; at best (per-frame dominance) it is a "trade".

New layers make a compositor move a trade at best. -/
theorem claim_ne_dominates_of_layers (x : Except String Screen.Result) (rv ro : Resident)
    (h : ro.layers < rv.layers) : claim x rv ro ≠ .dominates := by
  intro hc
  have := ((claim_dominates_iff x rv ro).mp hc).2.1
  omega

/-- **The inverse move (n=15).** A variant that touches a stage the original never touches, with no fewer forced passes
there, is never framewise `≤` the original. Replacing a compositor animation by main-thread steps adds `commit`
(Chromium: `commit ∉ compStages`, `commit ∈ stagesOf` of every main-thread change), so the step frames are worse.

A new stage is a new pass. -/
theorem new_stage_not_le {P M : Type} (E : Engine P M) (v o : FrameIn P) (s : Stage)
    (hv : s ∈ touched E v) (ho : s ∉ touched E o) (hf : forcedPasses o s ≤ forcedPasses v s) :
    (frameWork E o).passes s < (frameWork E v).passes s ∧ ¬ (frameWork E v).le (frameWork E o) := by
  have hlt : (frameWork E o).passes s < (frameWork E v).passes s := by
    simp only [frameWork, hv, ho, ↓reduceIte]; omega
  exact ⟨hlt, fun h => absurd (h.1 s).1 (by omega)⟩

/-! ## L5: pausing a compositor animation (n=14, 25) -/

/-- **Pausing touches only the compositor stages.** Removing one running compositor animation leaves passes and units
of every stage outside `compStages` unchanged.

What a pause saves is confined to `compStages`. -/
theorem pause_off_comp {P M : Type} (E : Engine P M) (f : FrameIn P) (s : Stage) (hs : s ∉ E.compStages) :
    (frameWork E f.addAnim).passes s = (frameWork E f).passes s ∧
      stageUnits E f.addAnim s = stageUnits E f s := by
  have ha := mem_touched_addAnim E f s
  have hf1 : forcedPasses f.addAnim s = forcedPasses f s := by cases s <;> rfl
  constructor
  · simp only [frameWork, hf1]
    by_cases h : s ∈ touched E f
    · simp [h, ha.mpr (.inr h)]
    · have : s ∉ touched E f.addAnim := fun h' => (ha.mp h').elim hs h
      simp [h, this]
  · simp [stageUnits, FrameIn.addAnim, hs]

/-- **No main-thread saving.** If the compositor animation costs only `comp` (`compStages ⊆ {comp}`: real Chrome and
WebKit), pausing it changes nothing on any other stage. In the Chromium lane (`everyBeginFrameIsMainFrame`,
`compStages = [comp, style, props]`) the style and props savings are a ride-along artifact of the lane.

Pausing a compositor animation frees only the compositor. -/
theorem pause_no_main {P M : Type} (E : Engine P M) (f : FrameIn P) (hE : ∀ s ∈ E.compStages, s = .comp)
    (s : Stage) (hs : s ≠ .comp) :
    (frameWork E f.addAnim).passes s = (frameWork E f).passes s ∧
      stageUnits E f.addAnim s = stageUnits E f s :=
  pause_off_comp E f s fun h => hs (hE s h)

/-! ## L3: resident-only changes (n=7, 13, 14) -/

/-- **Same inputs, same work.** Two frames with the same scalar fields whose changes dirty the same stage lists, in
order, have the same work, whatever else (element, property, layer state) differs.

Pass and unit counters cannot see what does not change a stage list. -/
theorem work_eq_of_stages {P M : Type} (E : Engine P M) (v o : FrameIn P)
    (h1 : v.script = o.script) (h2 : v.forcedStyle = o.forcedStyle) (h3 : v.forcedLayout = o.forcedLayout)
    (h4 : v.hits = o.hits) (h5 : v.compAnims = o.compAnims)
    (h6 : v.changes.map E.stagesOf = o.changes.map E.stagesOf) :
    frameWork E v = frameWork E o := by
  have hlen : v.changes.length = o.changes.length := by
    have := congrArg List.length h6; simpa using this
  have hflat : v.changes.flatMap E.stagesOf = o.changes.flatMap E.stagesOf := by
    have key : ∀ (l1 l2 : List (Change P)), l1.map E.stagesOf = l2.map E.stagesOf →
        l1.flatMap E.stagesOf = l2.flatMap E.stagesOf := by
      intro l1
      induction l1 with
      | nil => intro l2 h; cases l2 <;> simp_all
      | cons x xs ih =>
        intro l2 h
        cases l2 with
        | nil => simp at h
        | cons y ys =>
          simp only [List.map_cons, List.cons.injEq] at h
          simp only [List.flatMap_cons, h.1, ih ys h.2]
    exact key _ _ h6
  have hupd : v.updates = o.updates := by
    simp only [FrameIn.updates, h1]
    cases hv : v.changes <;> cases ho : o.changes <;> simp_all
  have ht : touched E v = touched E o := by simp only [touched, hflat, h5, hupd, h1]
  have hcount : ∀ s, v.changes.countP (fun c => decide (s ∈ E.stagesOf c)) =
      o.changes.countP (fun c => decide (s ∈ E.stagesOf c)) := by
    intro s
    have : ∀ (l : List (Change P)), l.countP (fun c => decide (s ∈ E.stagesOf c)) =
        (l.map E.stagesOf).countP (fun L => decide (s ∈ L)) := by
      intro l; rw [List.countP_map]; rfl
    rw [this, this, h6]
  have hf : ∀ s, forcedPasses v s = forcedPasses o s := by intro s; cases s <;> simp [forcedPasses, h2, h3]
  simp only [frameWork, stageUnits, ht, hf, hcount, h5, h1, h4]

/-- **Equal changes give equal work (n=14).** Frames with the same fields have the same work under every engine.

Intrinsic image resolution, not being a frame input, cannot change the counts. -/
theorem work_eq_of_same_changes {P M : Type} (E : Engine P M) (v o : FrameIn P)
    (h1 : v.script = o.script) (h2 : v.forcedStyle = o.forcedStyle) (h3 : v.forcedLayout = o.forcedLayout)
    (h4 : v.hits = o.hits) (h5 : v.compAnims = o.compAnims) (h6 : v.changes = o.changes) :
    frameWork E v = frameWork E o :=
  work_eq_of_stages E v o h1 h2 h3 h4 h5 (by rw [h6])

/-- A run screened against itself is "equal".

Identical counts give the "equal" verdict. -/
theorem screen_self (r : Screen.Run) : Screen.screen r r = .ok .equal := by
  simp [Screen.screen, Screen.shapeEq]

/-- **Pass counters cannot see a resident-only change.** If the variant's frames have the same work as the
original's, the claim is "noClaim" whatever the resident states, so a layer promotion without per-frame effect can
neither win nor trade.

A change confined to `Resident` makes no claim. -/
theorem resident_only_noClaim (vs os : List Work) (rv ro : Resident) (h : toRun vs = toRun os) :
    claim (Screen.screen (toRun os) (toRun vs)) rv ro = .noClaim := by
  rw [h, screen_self]; rfl

/-! ## L2: shifts move work (n=12, 17, 21) -/

/-- Componentwise `≤` with equal sums forces equality, for two summands.

Nothing can be both moved down and kept in the sum. -/
theorem eqv_of_le_add {a b c d : Work} (hac : a.le c) (hbd : b.le d) (h : (Work.add a b).eqv (Work.add c d)) :
    a.eqv c ∧ b.eqv d := by
  obtain ⟨⟨h1, hh1⟩, ⟨h2, hh2⟩⟩ := h
  simp only [Work.add] at h1 h2 hh1 hh2
  refine ⟨⟨hac, fun s => ?_, ?_⟩, ⟨hbd, fun s => ?_, ?_⟩⟩
  · have := (hac.1 s); have := (hbd.1 s); have := h2 s; omega
  · have := hac.2; have := hbd.2; omega
  · have := (hac.1 s); have := (hbd.1 s); have := h2 s; omega
  · have := hac.2; have := hbd.2; omega

/-- Framewise `≤` gives `≤` on the totals.

Summing preserves the order. -/
theorem total_le_of_leAll : ∀ {vs os : List Work}, leAll vs os = true → (total vs).le (total os)
  | [], [], _ => Work.le_refl _
  | [], _ :: _, h => by simp [leAll] at h
  | _ :: _, [], h => by simp [leAll] at h
  | v :: vs, o :: os, h => by
    simp only [leAll, Bool.and_eq_true] at h
    have hv : v.le o := (Work.leb_iff v o).mp h.1
    have hr := total_le_of_leAll h.2
    show (Work.add v (total vs)).le (Work.add o (total os))
    refine ⟨fun s => ⟨?_, ?_⟩, ?_⟩
    · have := (hv.1 s).1; have := (hr.1 s).1; simp only [Work.add]; omega
    · have := (hv.1 s).2; have := (hr.1 s).2; simp only [Work.add]; omega
    · have := hv.2; have := hr.2; simp only [Work.add]; omega

/-- **A shift never removes work.** If every frame of the variant is `≤` its original frame and the totals are
equivalent, every frame is equivalent: an equal-total change that is not framewise equal is never framewise `≤`.

Moving work between frames cannot be a framewise win. -/
theorem shift_framewise_eqv : ∀ {vs os : List Work}, leAll vs os = true → (total vs).eqv (total os) →
    ∀ p ∈ vs.zip os, p.1.eqv p.2
  | [], [], _, _ => by simp
  | [], _ :: _, h, _ => by simp [leAll] at h
  | _ :: _, [], h, _ => by simp [leAll] at h
  | v :: vs, o :: os, h, ht => by
    simp only [leAll, Bool.and_eq_true] at h
    have hv : v.le o := (Work.leb_iff v o).mp h.1
    have hrest := total_le_of_leAll h.2
    have ht' : (Work.add v (total vs)).eqv (Work.add o (total os)) := ht
    obtain ⟨he, hre⟩ := eqv_of_le_add hv hrest ht'
    intro p hp
    simp only [List.zip_cons_cons, List.mem_cons] at hp
    rcases hp with rfl | hp
    · exact he
    · exact shift_framewise_eqv h.2 hre p hp

/-- **A shift is never a framewise win.** With equivalent totals, `leAll` and `someLt` cannot both hold: the screen's
"dominates" needs a strictly smaller frame, which an equal total forbids.

Equal totals mean the work moved, not shrank. -/
theorem shift_not_dominates {vs os : List Work} (ht : (total vs).eqv (total os)) :
    ¬ (leAll vs os = true ∧ someLt vs os = true) := by
  rintro ⟨hle, hlt⟩
  have heq := shift_framewise_eqv hle ht
  simp only [someLt, List.any_eq_true] at hlt
  obtain ⟨p, hp, hlt⟩ := hlt
  have hl := (Work.ltb_iff p.1 p.2).mp hlt
  obtain ⟨_, hb⟩ := heq p hp
  rcases hl.2 with ⟨s, hs | hs⟩ | hs
  · have := (hb.1 s).1; omega
  · have := (hb.1 s).2; omega
  · have := hb.2; omega

/-! ## L6: one read between two write runs (n=1, 2, 22) -/

/-- **Removing a reader saves at most one pass, never adds one.** Corollary of `flagTotal_remove_check`: the saving is
one exactly when the flag is dirty at the read and the next non-neutral access is a write.

A read costs a pass only when it splits a write batch. -/
theorem reader_removal (d : Bool) (p q : List FlagOp) :
    flagTotal d (p ++ q) ≤ flagTotal d (p ++ .check :: q) ∧
      flagTotal d (p ++ .check :: q) ≤ flagTotal d (p ++ q) + 1 ∧
      (flagTotal d (p ++ .check :: q) = flagTotal d (p ++ q) + 1 ↔
        flagEnd d p = true ∧ firstFlag q = some .dirty) := by
  rw [flagTotal_remove_check]
  by_cases h : flagEnd d p = true ∧ firstFlag q = some .dirty <;> simp [h]

#guard flagTotal false [.dirty, .check, .dirty] == 2
#guard flagTotal false [.dirty, .dirty] == 1
#guard flagTotal true [.check, .check] == 1
#guard flagTotal true [.check] == flagTotal true [] -- a leading read only moves the pass of the dirty start
#guard (frameWork absorbWitnessE (⟨0, 0, 0, 0, [], 1⟩ : FrameIn Unit)).passes .comp == 1

end Fw.Engine
