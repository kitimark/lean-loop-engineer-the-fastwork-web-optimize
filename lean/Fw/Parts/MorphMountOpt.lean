import Lean.Data.Json
import Fw.Engine.Chromium
import Fw.Engine.WebKit
import Fw.Engine.Visual
import Fw.Parts.MorphMount
import Fw.Parts.EndFlags
/-!
# morph.mount, variant `shift`: warm the panel up at a still moment (MM-S)

The original mounts the end-of-page panel on the first intersecting IntersectionObserver entry (`rootMargin 200%`)
or on the first accepted push (`MorphMount.mountNext`, JS 13015 and 13076-13086). The observer fires while the page
scrolls, so the mount (DOM insertion: style, layout and paint of the panel subtree, 42-106 ms in v1, design note
`research/notes/2026/10-18-engine-proof-design.md` §4.2 rank 6) lands in a *motion* frame. The variant keeps both
triggers and adds a third, `warm`: a still moment (no scroll, no push, no running motion) that mounts the panel
earlier. Design: the note's §3.1 ("Time alignment") and §4.2 (MM-S).

**Visual (E).** `mountV_of_mountO`: the variant is mounted whenever the original is (`mountNext_mono` is the
trigger). `E_after_mount`: from the original's mount on, both arms show equal scenes, for every environment (width
band, input, DPR) and every frame. `visSame_mount`: with the premise that the panel shows nothing before the original
would mount it, the arms are `VisSame E` at every frame.

**Work (shift).** The variant moves the mount frame's extra input `mnt` from the original's motion frame `k` to a
still frame `j`. For **every** engine table (`Fw.Engine.Engine`), hence for Chromium and WebKit:
* `shift_peak_lt`: over the motion window `K` the variant's peak work is strictly lower;
* `shift_units`, `shift_hits`: the run totals of every stage's units and of hit tests are equal, so the main-thread
  time of the run is equal for all unit costs (`shift_mainUs_total`);
* `shift_passes`: pipeline passes are equal per stage except where the still frame or the motion frame already ran
  that stage; the warm-up frame is one extra rendering update, so WebKit's and Chromium's `commit` count one more pass
  (`chromium_commit_extra`, `webkit_commit_extra`).

**Why the screen says `mixed` and `ShiftLt` is the claim.** `shift_screen_mixed`: `Screen.screen` compares frames by
index; the still frame `j` is heavier in the variant and the motion frame `k` is heavier in the original, so neither
run is framewise below the other and the screen answers `mixed`. "Dominates" would be false and "worse" would be
false; what is true is that the work moved out of motion (peak `<`) without growing (units total `=`). Core's
`Shift` asks in addition for equal pass totals, which the extra warm-up commit breaks (`chromium_not_shift`,
`webkit_not_shift`); `shift_of_passes` gives `Shift` whenever the pass totals match.

**Premises (not axioms).** DOM insertion of the panel = one change per inserted box at the engines' layout level
(`css width` on Chromium, `size` on WebKit: INFERRED, note §4.2); the panel is out of flow (the page's other boxes do
not depend on it; scenes are `base ++ panel`); the panel's look after mount does not depend on when it was mounted
(`PhaseFree`: no animation or timer whose phase starts at mount); before the original mounts, the panel draws nothing
in the viewport (`HiddenBefore`); the counting window contains the warm-up frame (for the golden totals).
-/
namespace Fw.Parts.MorphMountOpt

open Fw.Engine Fw.Parts.MorphMount

/-! ## The trigger -/

/-- What one frame offers the mount rule: an intersecting observer entry, an accepted push, and (variant only) a
still moment that warms the panel up.

The inputs of one frame. -/
structure Tick where
  near : Bool
  push : Bool
  warm : Bool
deriving Repr, DecidableEq

/-- The original's mount flag before frame `t`: unmounted at first, then `mountNext` over the frame inputs.

Whether the original has mounted the panel by frame `t`. -/
def mountO (x : Nat → Tick) : Nat → Bool
  | 0 => false
  | t + 1 => mountNext (mountO x t) (x t).near (x t).push

/-- The variant's mount flag: as the original's, with a still moment counted as a trigger too.

Whether the variant has mounted the panel by frame `t`. -/
def mountV (x : Nat → Tick) : Nat → Bool
  | 0 => false
  | t + 1 => mountNext (mountV x t) ((x t).near || (x t).warm) (x t).push

#guard mountO (fun _ => ⟨false, false, true⟩) 5 == false
#guard mountV (fun _ => ⟨false, false, true⟩) 5 == true
#guard mountO (fun t => ⟨t == 3, false, false⟩) 3 == false && mountO (fun t => ⟨t == 3, false, false⟩) 4 == true
#guard mountV (fun t => ⟨false, t == 2, false⟩) 3 == true

/-- Once mounted, the original stays mounted (`mountNext_mono`).

The panel is never unmounted. -/
theorem mountO_stays (x : Nat → Tick) : ∀ (t d : Nat), mountO x t = true → mountO x (t + d) = true
  | _, 0, h => h
  | t, d + 1, h => by
    show mountNext (mountO x (t + d)) _ _ = true
    rw [mountO_stays x t d h]
    exact mountNext_mono _ _

/-- **The trigger.** The variant is mounted whenever the original is.

Warming up early never leaves the variant unmounted where the original is mounted. -/
theorem mountV_of_mountO (x : Nat → Tick) : ∀ (t : Nat), mountO x t = true → mountV x t = true
  | 0, h => by simp [mountO] at h
  | t + 1, h => by
    simp only [mountO, mountV, mountNext, Bool.or_eq_true] at h ⊢
    rcases h with (h | h) | h
    · exact Or.inl (Or.inl (mountV_of_mountO x t h))
    · exact Or.inl (Or.inr (Or.inl h))
    · exact Or.inr h

/-! ## The visual claim -/

/-- The scene of one arm at one frame: the page's boxes, then the panel's boxes when mounted (the panel is out of
flow, so mounting it changes no other box).

What the page shows with or without the panel. -/
def sceneOf (base panel : Scene) (m : Bool) : Scene := base ++ if m then panel else []

/-- The original's scene: page `base`, and the panel `panel env t h`, which may depend on the whole mount history
`h` (for example an animation started at mount).

The original arm, frame by frame. -/
def armO {Env : Type} (base : Env → Nat → Scene) (panel : Env → Nat → (Nat → Bool) → Scene)
    (x : Env → Nat → Tick) (env : Env) (t : Nat) : Scene :=
  sceneOf (base env t) (panel env t (mountO (x env))) (mountO (x env) t)

/-- The variant's scene, with the variant's mount history.

The variant arm, frame by frame. -/
def armV {Env : Type} (base : Env → Nat → Scene) (panel : Env → Nat → (Nat → Bool) → Scene)
    (x : Env → Nat → Tick) (env : Env) (t : Nat) : Scene :=
  sceneOf (base env t) (panel env t (mountV (x env))) (mountV (x env) t)

/-- **Premise: phase-free panel.** Once mounted under either history, the panel looks the same: nothing in it starts
its phase at mount.

The panel's look does not remember when it was mounted. -/
def PhaseFree {Env : Type} (panel : Env → Nat → (Nat → Bool) → Scene) : Prop :=
  ∀ env t (h h' : Nat → Bool), h t = true → h' t = true → panel env t h = panel env t h'

/-- **Premise: hidden before the original mounts.** While the original has not mounted the panel (the platform is
more than two viewports away and no push was taken), the panel draws nothing in the viewport, under any history.

Before the original would show it, the panel is invisible. -/
def HiddenBefore {Env : Type} (vp : Env → Fw.Engine.Rect) (panel : Env → Nat → (Nat → Bool) → Scene)
    (x : Env → Nat → Tick) : Prop :=
  ∀ env t (h : Nat → Bool), mountO (x env) t = false → visible (vp env) (panel env t h) = []

/-- `visible` distributes over concatenation.

Dropping invisible boxes works box by box. -/
theorem visible_append (vp : Fw.Engine.Rect) (s u : Scene) : visible vp (s ++ u) = visible vp s ++ visible vp u := by
  simp [visible, List.filter_append]

/-- **E after mount.** From the original's mount on, the two arms' visible scenes are equal, for every environment
(every width band) and every frame.

Once the original has mounted the panel, the variant shows exactly the same thing. -/
theorem E_after_mount {Env : Type} (base : Env → Nat → Scene) (panel : Env → Nat → (Nat → Bool) → Scene)
    (x : Env → Nat → Tick) (vp : Env → Fw.Engine.Rect) (hp : PhaseFree panel) :
    ∀ env t, mountO (x env) t = true →
      E (visible (vp env) (armO base panel x env t)) (visible (vp env) (armV base panel x env t)) := by
  intro env t h
  have hv := mountV_of_mountO (x env) t h
  unfold E armO armV sceneOf
  rw [h, hv, hp env t _ _ h hv]

/-- **E at every frame.** With the panel hidden before the original mounts it, the arms are `VisSame E`.

The early warm-up never changes what the viewer sees. -/
theorem visSame_mount {Env : Type} (base : Env → Nat → Scene) (panel : Env → Nat → (Nat → Bool) → Scene)
    (x : Env → Nat → Tick) (vp : Env → Fw.Engine.Rect) (hp : PhaseFree panel) (hh : HiddenBefore vp panel x) :
    VisSame E vp (armO base panel x) (armV base panel x) := by
  intro env t
  cases h : mountO (x env) t with
  | true => exact E_after_mount base panel x vp hp env t h
  | false =>
    unfold E armO armV sceneOf
    rw [h, visible_append, visible_append]
    cases mountV (x env) t
    · rfl
    · simp only [ite_true]; rw [hh env t _ h]; rfl

/-! ## Moving one frame's input -/

/-- Two frame inputs in one frame: counts add, change lists concatenate.

The mount's input added to a frame's own input. -/
def merge {P : Type} (f g : FrameIn P) : FrameIn P where
  script := f.script + g.script
  forcedStyle := f.forcedStyle + g.forcedStyle
  forcedLayout := f.forcedLayout + g.forcedLayout
  hits := f.hits + g.hits
  changes := f.changes ++ g.changes
  compAnims := f.compAnims + g.compAnims

/-- One arm of `n` frames: frame input `fs i`, plus the mount input `mnt` at frame `a`.

The original is `arm … k n` (mount in motion frame `k`), the variant `arm … j n` (mount in still frame `j`). -/
def arm {P M : Type} (E : Engine P M) (fs : Nat → FrameIn P) (mnt : FrameIn P) (a n : Nat) : List Work :=
  (List.range n).map fun i => frameWork E (if i = a then merge (fs i) mnt else fs i)

/-- Membership in the touched stages, without the `if`s.

A stage is touched through a change, a compositor animation, the base of an updating frame, or script. -/
theorem mem_touched {P M : Type} (E : Engine P M) (f : FrameIn P) (s : Stage) :
    s ∈ touched E f ↔ s ∈ f.changes.flatMap E.stagesOf ∨ (0 < f.compAnims ∧ s ∈ E.compStages) ∨
      (f.updates = true ∧ s ∈ E.base) ∨ (0 < f.script ∧ s = .script) := by
  simp only [touched, List.mem_append, List.append_assoc]
  by_cases h1 : 0 < f.compAnims <;> by_cases h2 : f.updates = true <;> by_cases h3 : 0 < f.script <;>
    simp [h1, h2, h3]

/-- A stage is touched by a merged frame exactly when one of the two inputs touches it.

Merging two inputs runs the union of their stages. -/
theorem mem_touched_merge {P M : Type} (E : Engine P M) (f g : FrameIn P) (s : Stage) :
    s ∈ touched E (merge f g) ↔ s ∈ touched E f ∨ s ∈ touched E g := by
  rw [mem_touched, mem_touched, mem_touched]
  have hu : (merge f g).updates = true ↔ f.updates = true ∨ g.updates = true := by
    cases hf : f.changes <;> cases hg : g.changes <;>
      simp [FrameIn.updates, merge, hf, hg] <;> omega
  have hc : 0 < (merge f g).compAnims ↔ 0 < f.compAnims ∨ 0 < g.compAnims := by simp only [merge]; omega
  have hs : 0 < (merge f g).script ↔ 0 < f.script ∨ 0 < g.script := by simp only [merge]; omega
  have hm : s ∈ (merge f g).changes.flatMap E.stagesOf ↔
      s ∈ f.changes.flatMap E.stagesOf ∨ s ∈ g.changes.flatMap E.stagesOf := by
    simp only [merge, List.flatMap_append, List.mem_append]
  rw [hu, hc, hs, hm]
  constructor
  · rintro ((h | h) | ⟨h1 | h1, h2⟩ | ⟨h1 | h1, h2⟩ | ⟨h1 | h1, h2⟩)
    · exact Or.inl (Or.inl h)
    · exact Or.inr (Or.inl h)
    · exact Or.inl (Or.inr (Or.inl ⟨h1, h2⟩))
    · exact Or.inr (Or.inr (Or.inl ⟨h1, h2⟩))
    · exact Or.inl (Or.inr (Or.inr (Or.inl ⟨h1, h2⟩)))
    · exact Or.inr (Or.inr (Or.inr (Or.inl ⟨h1, h2⟩)))
    · exact Or.inl (Or.inr (Or.inr (Or.inr ⟨h1, h2⟩)))
    · exact Or.inr (Or.inr (Or.inr (Or.inr ⟨h1, h2⟩)))
  · rintro ((h | ⟨h1, h2⟩ | ⟨h1, h2⟩ | ⟨h1, h2⟩) | (h | ⟨h1, h2⟩ | ⟨h1, h2⟩ | ⟨h1, h2⟩))
    · exact Or.inl (Or.inl h)
    · exact Or.inr (Or.inl ⟨Or.inl h1, h2⟩)
    · exact Or.inr (Or.inr (Or.inl ⟨Or.inl h1, h2⟩))
    · exact Or.inr (Or.inr (Or.inr ⟨Or.inl h1, h2⟩))
    · exact Or.inl (Or.inr h)
    · exact Or.inr (Or.inl ⟨Or.inr h1, h2⟩)
    · exact Or.inr (Or.inr (Or.inl ⟨Or.inr h1, h2⟩))
    · exact Or.inr (Or.inr (Or.inr ⟨Or.inr h1, h2⟩))

/-- Units add over a merge.

Every change, animation and callback of either input is counted once. -/
theorem units_merge {P M : Type} (E : Engine P M) (f g : FrameIn P) (s : Stage) :
    (frameWork E (merge f g)).units s = (frameWork E f).units s + (frameWork E g).units s := by
  simp only [frameWork, stageUnits, merge, List.countP_append]
  split <;> split <;> omega

/-- Forced passes add over a merge.

Forced style and layout passes of both inputs all run. -/
theorem forced_merge {P : Type} (f g : FrameIn P) (s : Stage) :
    forcedPasses (merge f g) s = forcedPasses f s + forcedPasses g s := by
  cases s <;> rfl

/-- The passes a merge adds to frame `f`: one for a stage only `g` touches, plus `g`'s forced passes.

What adding the mount to a frame costs in passes. -/
def extra {P M : Type} (E : Engine P M) (f g : FrameIn P) (s : Stage) : Nat :=
  (if s ∈ touched E g ∧ s ∉ touched E f then 1 else 0) + forcedPasses g s

/-- Passes of a merge.

A stage already run by the frame is not run again by the mount. -/
theorem passes_merge {P M : Type} (E : Engine P M) (f g : FrameIn P) (s : Stage) :
    (frameWork E (merge f g)).passes s = (frameWork E f).passes s + extra E f g s := by
  simp only [frameWork, extra, forced_merge]
  have := mem_touched_merge E f g s
  by_cases h1 : s ∈ touched E f <;> by_cases h2 : s ∈ touched E g <;> simp_all <;> omega

/-- A frame is below its merge with anything.

Adding the mount never removes work. -/
theorem le_merge {P M : Type} (E : Engine P M) (f g : FrameIn P) :
    (frameWork E f).le (frameWork E (merge f g)) := by
  refine ⟨fun s => ⟨?_, ?_⟩, ?_⟩
  · rw [passes_merge]; omega
  · rw [units_merge]; omega
  · show f.hits ≤ f.hits + g.hits; omega

/-! ## Sums, peaks and frame lookup -/

/-- Frame `i` of an arm: its own input (plus the mount at `a`), zero past the end.

Looking up a frame of an arm. -/
theorem frameAt_arm {P M : Type} (E : Engine P M) (fs : Nat → FrameIn P) (mnt : FrameIn P) (a n i : Nat) :
    frameAt (arm E fs mnt a n) i =
      if i < n then frameWork E (if i = a then merge (fs i) mnt else fs i) else Work.zero := by
  unfold frameAt arm
  by_cases h : i < n
  · simp [h, List.getD_eq_getElem?_getD]
  · simp [h, List.getD_eq_getElem?_getD]

/-- Stage `s` units of a run total.

Totals are sums, stage by stage. -/
theorem total_units (ws : List Work) (s : Stage) : (total ws).units s = (ws.map fun w => w.units s).sum := by
  induction ws with
  | nil => rfl
  | cons w ws ih => simp only [total, List.foldr_cons, List.map_cons, List.sum_cons] at ih ⊢; rw [← ih]; rfl

/-- Stage `s` passes of a run total.

Totals are sums, stage by stage. -/
theorem total_passes (ws : List Work) (s : Stage) : (total ws).passes s = (ws.map fun w => w.passes s).sum := by
  induction ws with
  | nil => rfl
  | cons w ws ih => simp only [total, List.foldr_cons, List.map_cons, List.sum_cons] at ih ⊢; rw [← ih]; rfl

/-- Hit tests of a run total.

Totals are sums. -/
theorem total_hits (ws : List Work) : (total ws).hits = (ws.map fun w => w.hits).sum := by
  induction ws with
  | nil => rfl
  | cons w ws ih => simp only [total, List.foldr_cons, List.map_cons, List.sum_cons] at ih ⊢; rw [← ih]; rfl

/-- Adding `x` at one index `a < n` adds `x` to the sum over `i < n`.

A one-frame addition shows up once in the total. -/
theorem sum_bump (c : Nat → Nat) (x a : Nat) :
    ∀ n, a < n → ((List.range n).map fun i => if i = a then c i + x else c i).sum = ((List.range n).map c).sum + x
  | 0, h => absurd h (Nat.not_lt_zero _)
  | n + 1, h => by
    simp only [List.range_succ, List.map_append, List.sum_append, List.map_cons, List.map_nil, List.sum_cons,
      List.sum_nil]
    by_cases hn : n = a
    · subst hn
      have hm : ((List.range n).map fun i => if i = n then c i + x else c i) = (List.range n).map c :=
        List.map_congr_left fun i hi => by simp [Nat.ne_of_lt (List.mem_range.mp hi)]
      rw [hm]; simp; omega
    · rw [sum_bump c x a n (by omega)]; simp [hn]; omega

/-- The componentwise maximum is monotone.

Raising both arguments raises the componentwise maximum. -/
theorem Work.max_le_max {a b c d : Work} (h1 : a.le c) (h2 : b.le d) : (a.max b).le (c.max d) := by
  have hm : ∀ w x y z : Nat, w ≤ y → x ≤ z → Nat.max w x ≤ Nat.max y z := by
    intro w x y z h h'; simp only [Nat.max_def]; split <;> split <;> omega
  exact ⟨fun s => ⟨hm _ _ _ _ (h1.1 s).1 (h2.1 s).1, hm _ _ _ _ (h1.1 s).2 (h2.1 s).2⟩, hm _ _ _ _ h1.2 h2.2⟩

/-- The peak over a window is monotone in the frames of the window.

A framewise-lower window has a lower peak. -/
theorem peak_mono {vs os : List Work} :
    ∀ (ks : List Nat), (∀ k ∈ ks, (frameAt vs k).le (frameAt os k)) → (peak ks vs).le (peak ks os)
  | [], _ => Work.le_refl _
  | k :: ks, h => by
    have ih := peak_mono ks fun i hi => h i (List.mem_cons_of_mem _ hi)
    have hk := h k (List.mem_cons_self ..)
    simp only [peak, List.foldr_cons] at ih ⊢
    exact Work.max_le_max hk ih

/-- If every frame of the window has fewer than `x > 0` units at `s`, so does the peak.

A bound on every frame bounds the peak. -/
theorem peak_units_lt (ws : List Work) (s : Stage) (x : Nat) (hx : 0 < x) :
    ∀ (ks : List Nat), (∀ k ∈ ks, (frameAt ws k).units s < x) → (peak ks ws).units s < x
  | [], _ => hx
  | k :: ks, h => by
    have ih := peak_units_lt ws s x hx ks fun i hi => h i (List.mem_cons_of_mem _ hi)
    have hk := h k (List.mem_cons_self ..)
    simp only [peak, List.foldr_cons] at ih ⊢
    exact Nat.max_lt.mpr ⟨hk, ih⟩

/-! ## The shift theorem, for every engine table -/

/-- **Strict shift.** Over the motion window `K` the variant's peak is strictly below the original's, and the run
totals of every stage's units and of the hit tests are equal (pass totals are left to `shift_passes`).

Work moved out of motion, none added. -/
def ShiftLt (win : List Nat) (vs os : List Work) : Prop :=
  (peak win vs).lt (peak win os) ∧ (∀ s, (total vs).units s = (total os).units s) ∧ (total vs).hits = (total os).hits

/-- **Units total equal.** Moving the mount from frame `k` to frame `j` (both inside the run) keeps every stage's
unit total.

Each arm pays for the mount exactly once. -/
theorem shift_units {P M : Type} (E : Engine P M) (fs : Nat → FrameIn P) (mnt : FrameIn P) {j k n : Nat}
    (hj : j < n) (hk : k < n) (s : Stage) :
    (total (arm E fs mnt j n)).units s = (total (arm E fs mnt k n)).units s := by
  have key : ∀ a, a < n → (total (arm E fs mnt a n)).units s =
      ((List.range n).map fun i => (frameWork E (fs i)).units s).sum + (frameWork E mnt).units s := by
    intro a ha
    rw [total_units, arm, List.map_map, ← sum_bump _ _ a n ha]
    congr 1
    refine List.map_congr_left fun i _ => ?_
    simp only [Function.comp]
    split <;> simp [units_merge]
  rw [key j hj, key k hk]

/-- **Hit tests total equal.**

Each arm runs the mount's hit tests once. -/
theorem shift_hits {P M : Type} (E : Engine P M) (fs : Nat → FrameIn P) (mnt : FrameIn P) {j k n : Nat}
    (hj : j < n) (hk : k < n) :
    (total (arm E fs mnt j n)).hits = (total (arm E fs mnt k n)).hits := by
  have key : ∀ a, a < n → (total (arm E fs mnt a n)).hits =
      ((List.range n).map fun i => (frameWork E (fs i)).hits).sum + (frameWork E mnt).hits := by
    intro a ha
    rw [total_hits, arm, List.map_map, ← sum_bump _ _ a n ha]
    congr 1
    refine List.map_congr_left fun i _ => ?_
    simp only [Function.comp]
    split <;> simp [frameWork, merge]
  rw [key j hj, key k hk]

/-- **Pass totals.** Per stage, the variant's pass total plus what the mount adds to the motion frame equals the
original's plus what it adds to the still frame.

Passes move with the mount, except a stage the motion frame already ran costs nothing extra there. -/
theorem shift_passes {P M : Type} (E : Engine P M) (fs : Nat → FrameIn P) (mnt : FrameIn P) {j k n : Nat}
    (hj : j < n) (hk : k < n) (s : Stage) :
    (total (arm E fs mnt j n)).passes s + extra E (fs k) mnt s =
      (total (arm E fs mnt k n)).passes s + extra E (fs j) mnt s := by
  have key : ∀ a, a < n → (total (arm E fs mnt a n)).passes s =
      ((List.range n).map fun i => (frameWork E (fs i)).passes s).sum + extra E (fs a) mnt s := by
    intro a ha
    rw [total_passes, arm, List.map_map]
    have := sum_bump (fun i => (frameWork E (fs i)).passes s) (extra E (fs a) mnt s) a n ha
    rw [← this]
    congr 1
    refine List.map_congr_left fun i _ => ?_
    simp only [Function.comp]
    split
    · next h => subst h; simp [passes_merge]
    · simp_all
  rw [key j hj, key k hk]; omega

/-- **Pass totals, untouched stages.** A stage that neither the still frame nor the motion frame runs on its own has
equal pass totals.

Style and layout passes keep their totals when the scroll runs neither. -/
theorem shift_passes_eq {P M : Type} (E : Engine P M) (fs : Nat → FrameIn P) (mnt : FrameIn P) {j k n : Nat}
    (hj : j < n) (hk : k < n) (s : Stage) (h1 : s ∉ touched E (fs j)) (h2 : s ∉ touched E (fs k)) :
    (total (arm E fs mnt j n)).passes s = (total (arm E fs mnt k n)).passes s := by
  have := shift_passes E fs mnt hj hk s
  simp only [extra, h1, h2, not_false_eq_true, and_true] at this
  omega

/-- **Pass totals, one extra pass.** A stage the motion frame runs anyway, the still frame does not, and the mount
does, costs the variant exactly one more pass (the warm-up frame's own rendering update).

The warm-up commit is the one pass the shift adds. -/
theorem shift_passes_succ {P M : Type} (E : Engine P M) (fs : Nat → FrameIn P) (mnt : FrameIn P) {j k n : Nat}
    (hj : j < n) (hk : k < n) (s : Stage) (h1 : s ∉ touched E (fs j)) (h2 : s ∈ touched E (fs k))
    (h3 : s ∈ touched E mnt) :
    (total (arm E fs mnt j n)).passes s = (total (arm E fs mnt k n)).passes s + 1 := by
  have := shift_passes E fs mnt hj hk s
  simp only [extra, h1, h2, h3, not_false_eq_true, and_true, not_true_eq_false, and_false, ite_false,
    ite_true] at this
  omega

/-- **Peak strictly lower.** If the still frame `j` is outside the motion window `K`, the motion frame `k` is inside
it and inside the run, and some stage `s` has more mount units than any motion frame has on its own, then the
variant's peak over `K` is strictly below the original's.

The mount no longer stacks on a motion frame. -/
theorem shift_peak_lt {P M : Type} (E : Engine P M) (fs : Nat → FrameIn P) (mnt : FrameIn P) {j k n : Nat}
    {K : List Nat} (hjK : j ∉ K) (hkK : k ∈ K) (hk : k < n) (s : Stage)
    (hs : ∀ i ∈ K, (frameWork E (fs i)).units s < (frameWork E mnt).units s) :
    (peak K (arm E fs mnt j n)).lt (peak K (arm E fs mnt k n)) := by
  have hx : 0 < (frameWork E mnt).units s := Nat.lt_of_le_of_lt (Nat.zero_le _) (hs k hkK)
  have hframe : ∀ i ∈ K, (frameAt (arm E fs mnt j n) i).le (frameAt (arm E fs mnt k n) i) := by
    intro i hi
    have hij : i ≠ j := fun e => hjK (e ▸ hi)
    rw [frameAt_arm, frameAt_arm]
    by_cases hin : i < n
    · by_cases hik : i = k
      · subst hik; simp only [hin, hij, ite_true, ite_false]; exact le_merge E _ _
      · simp only [hin, hij, hik, ite_true, ite_false]; exact Work.le_refl _
    · simp only [hin, ite_false]; exact Work.le_refl _
  refine ⟨peak_mono K hframe, Or.inl ⟨s, Or.inr ?_⟩⟩
  have hlo : (peak K (arm E fs mnt j n)).units s < (frameWork E mnt).units s := by
    refine peak_units_lt _ s _ hx K fun i hi => ?_
    have hij : i ≠ j := fun e => hjK (e ▸ hi)
    rw [frameAt_arm]
    by_cases hin : i < n
    · simp only [hin, hij, ite_true, ite_false]; exact hs i hi
    · simp only [hin, ite_false]; exact hx
  have hhi : (frameWork E mnt).units s ≤ (peak K (arm E fs mnt k n)).units s := by
    have := (le_peak (arm E fs mnt k n) K k hkK).1 s
    rw [frameAt_arm] at this
    simp only [hk, ite_true] at this
    rw [units_merge] at this
    omega
  omega

/-- **The shift theorem** (any engine table, any run, any width band's schedule): under the hypotheses of
`shift_peak_lt` with `j < n`, the variant `ShiftLt`s the original.

The warm-up lowers the motion peak and keeps the totals. -/
theorem mount_shift {P M : Type} (E : Engine P M) (fs : Nat → FrameIn P) (mnt : FrameIn P) {j k n : Nat}
    {K : List Nat} (hj : j < n) (hjK : j ∉ K) (hkK : k ∈ K) (hk : k < n) (s : Stage)
    (hs : ∀ i ∈ K, (frameWork E (fs i)).units s < (frameWork E mnt).units s) :
    ShiftLt K (arm E fs mnt j n) (arm E fs mnt k n) :=
  ⟨shift_peak_lt E fs mnt hjK hkK hk s hs, shift_units E fs mnt hj hk, shift_hits E fs mnt hj hk⟩

/-- **Main-thread time.** Under `ShiftLt`, for all unit costs: every motion frame of the variant costs at most the
original's peak, and the run totals are equal.

The cost model sees the peak drop and the total stay. -/
theorem shift_mainUs {ks : List Nat} {vs os : List Work} (h : ShiftLt ks vs os) (u : Cost.UnitCost) :
    (∀ k ∈ ks, Cost.mainUs u (toCost (frameAt vs k)) ≤ Cost.mainUs u (toCost (peak ks os))) ∧
      (vs.map fun w => Cost.mainUs u (toCost w)).sum = (os.map fun w => Cost.mainUs u (toCost w)).sum := by
  refine ⟨fun k hk => mainUs_toCost_le u (Work.le_trans (le_peak vs ks k hk) h.1.1), ?_⟩
  rw [← mainUs_total, ← mainUs_total]
  have : toCost (total vs) = toCost (total os) := by simp only [toCost, h.2.1]
  rw [this]

/-- **Into Core's `Shift`.** A strict shift with equal pass totals is a `Shift`.

When the warm-up adds no pass, Core's claim holds as well. -/
theorem shift_of_passes {ks : List Nat} {vs os : List Work} (h : ShiftLt ks vs os)
    (hp : ∀ s, (total vs).passes s = (total os).passes s) : Shift ks vs os :=
  ⟨h.1.1, ⟨fun s => ⟨Nat.le_of_eq (hp s), Nat.le_of_eq (h.2.1 s)⟩, Nat.le_of_eq h.2.2⟩,
    ⟨fun s => ⟨Nat.le_of_eq (hp s).symm, Nat.le_of_eq (h.2.1 s).symm⟩, Nat.le_of_eq h.2.2.symm⟩⟩

/-! ## The screen says `mixed` -/

/-- `leVec` is reflexive.

A count vector is below itself. -/
theorem leVec_refl : ∀ (x : Screen.Counts), Screen.leVec x x = true
  | [] => rfl
  | a :: as => by simp [Screen.leVec, leVec_refl as]

/-- `leRun` is reflexive.

A run is below itself. -/
theorem leRun_refl : ∀ (r : Screen.Run), Screen.leRun r r = true
  | [] => rfl
  | a :: as => by simp [Screen.leRun, leVec_refl a, leRun_refl as]

/-- `leVec` on count vectors gives `≤` on every stage's units.

The screen's order reads the units. -/
theorem units_of_leVec {a b : Work} (h : Screen.leVec (toCounts a) (toCounts b) = true) (s : Stage) :
    a.units s ≤ b.units s := by
  simp only [toCounts, Stage.all, List.map_cons, List.map_nil, List.cons_append, List.nil_append, Screen.leVec,
    Bool.and_eq_true, decide_eq_true_eq] at h
  cases s <;> omega

/-- `leRun` on two runs gives `≤` on every frame's units.

The screen's run order is framewise. -/
theorem units_of_leRun : ∀ {vs os : List Work}, Screen.leRun (toRun vs) (toRun os) = true →
    ∀ (i : Nat) (s : Stage), (frameAt vs i).units s ≤ (frameAt os i).units s
  | [], [], _, _, _ => Nat.le_refl _
  | [], _ :: _, h, _, _ => by simp [toRun, Screen.leRun] at h
  | _ :: _, [], h, _, _ => by simp [toRun, Screen.leRun] at h
  | v :: vs, o :: os, h, i, s => by
    simp only [toRun, List.map_cons, Screen.leRun, Bool.and_eq_true] at h
    cases i with
    | zero => exact units_of_leVec h.1 s
    | succ i => exact units_of_leRun (vs := vs) (os := os) h.2 i s

/-- An arm has `n` frames.

One work value per frame. -/
theorem arm_length {P M : Type} (E : Engine P M) (fs : Nat → FrameIn P) (mnt : FrameIn P) (a n : Nat) :
    (arm E fs mnt a n).length = n := by simp [arm]

/-- **The screen says `mixed`.** With `j ≠ k` inside the run and some stage where the mount has units, the still
frame `j` is heavier in the variant and the motion frame `k` heavier in the original, so the screen (baseline =
original) answers `mixed`, never `dominates`.

Framewise comparison cannot see a shift; `ShiftLt` is the claim to make. -/
theorem shift_screen_mixed {P M : Type} (E : Engine P M) (fs : Nat → FrameIn P) (mnt : FrameIn P) {j k n : Nat}
    (hj : j < n) (hk : k < n) (hjk : j ≠ k) (s : Stage) (hx : 0 < (frameWork E mnt).units s) :
    Screen.screen (toRun (arm E fs mnt k n)) (toRun (arm E fs mnt j n)) = .ok .mixed := by
  have hvo : Screen.leRun (toRun (arm E fs mnt j n)) (toRun (arm E fs mnt k n)) = false := by
    cases hc : Screen.leRun (toRun (arm E fs mnt j n)) (toRun (arm E fs mnt k n))
    · rfl
    · have := units_of_leRun hc j s
      rw [frameAt_arm, frameAt_arm] at this
      simp only [hj, ite_true, hjk, ite_false, units_merge] at this
      omega
  have hov : Screen.leRun (toRun (arm E fs mnt k n)) (toRun (arm E fs mnt j n)) = false := by
    cases hc : Screen.leRun (toRun (arm E fs mnt k n)) (toRun (arm E fs mnt j n))
    · rfl
    · have := units_of_leRun hc k s
      rw [frameAt_arm, frameAt_arm] at this
      simp only [hk, ite_true, Ne.symm hjk, ite_false, units_merge] at this
      omega
  have hshape : Screen.shapeEq (toRun (arm E fs mnt k n)) (toRun (arm E fs mnt j n)) = true := by
    simp [Screen.shapeEq, toRun_shape, arm_length]
  have hne : (toRun (arm E fs mnt j n) == toRun (arm E fs mnt k n)) = false := by
    cases hc : (toRun (arm E fs mnt j n) == toRun (arm E fs mnt k n))
    · rfl
    · have he : toRun (arm E fs mnt j n) = toRun (arm E fs mnt k n) := by simpa using hc
      rw [he, leRun_refl] at hvo; cases hvo
  unfold Screen.screen
  simp [hshape, hne, hvo, hov]

/-! ## Both engines -/

/-- The Chromium mount input: one `width`-level change (layoutFull) per inserted box, no layer, and one script
callback (the observer or idle callback that renders the panel).

DOM insertion of `c` boxes, as Chromium sees it (INFERRED). -/
def mountCr (c : Nat) : FrameIn Chromium.CrProp :=
  ⟨1, 0, 0, 0, (List.range c).map fun e => ⟨e, .css .width, .none⟩, 0⟩

/-- The WebKit mount input: one `size` change (Layout) per inserted box, no layer, one script callback.

DOM insertion of `c` boxes, as WebKit sees it (INFERRED). -/
def mountWk (c : Nat) : FrameIn WebKit.WkProp :=
  ⟨1, 0, 0, 0, (List.range c).map fun e => ⟨e, .size, .none⟩, 0⟩

/-- A Chromium scroll frame: one composited scroll change at `d` px per frame, frame `q` since the last cull update.

One frame of the swipe. -/
def scrollCr (d q : Nat) : FrameIn Chromium.CrProp := ⟨0, 0, 0, 0, [Chromium.scrollChange 0 d q], 0⟩

/-- A WebKit scroll frame: one scroll-position change on the composited scroller.

One frame of the swipe. -/
def scrollWk : FrameIn WebKit.WkProp := ⟨0, 0, 0, 0, [⟨0, .scrollPos, .own⟩], 0⟩

/-- The Chromium mount has `c` layout units.

Every inserted box is laid out once. -/
theorem mountCr_layout (c : Nat) : (frameWork Chromium.chromium (mountCr c)).units .layout = c := by
  simp only [frameWork, stageUnits, mountCr, List.countP_map]
  have : ∀ e, (Stage.layout ∈ Chromium.chromium.stagesOf ⟨e, .css .width, .none⟩) := fun e => by
    show Stage.layout ∈ Chromium.crStagesOf ⟨e, .css .width, .none⟩
    simp only [Chromium.crStagesOf]; decide
  rw [List.countP_eq_length.mpr (fun e _ => by simpa [Function.comp] using this e)]
  simp [Chromium.chromium, Chromium.chromiumAt]
  exact ite_self _


/-- The WebKit mount has `c` layout units.

Every inserted box is laid out once. -/
theorem mountWk_layout (c : Nat) : (frameWork WebKit.webkit (mountWk c)).units .layout = c := by
  simp only [frameWork, stageUnits, mountWk, List.countP_map]
  have : ∀ e, (Stage.layout ∈ WebKit.webkit.stagesOf ⟨e, .size, .none⟩) := fun _ =>
    (by decide : Stage.layout ∈ WebKit.webkit.stagesOf ⟨0, .size, .none⟩)
  rw [List.countP_eq_length.mpr (fun e _ => by simpa [Function.comp] using this e)]
  simp [WebKit.webkit, WebKit.webkitAt]

/-- A Chromium scroll frame has no layout units.

Scrolling never lays out. -/
theorem scrollCr_layout (d q : Nat) : (frameWork Chromium.chromium (scrollCr d q)).units .layout = 0 := by
  have h := (Chromium.scroll_stages 0 d q).2.2.2.1
  simp [frameWork, stageUnits, scrollCr, Chromium.chromium, Chromium.chromiumAt]
  exact ⟨decide_eq_false h, ite_self _⟩

/-- A WebKit scroll frame has no layout units.

Scrolling never lays out. -/
theorem scrollWk_layout : (frameWork WebKit.webkit scrollWk).units .layout = 0 := by
  have h : WebKit.wkStages ⟨0, .scrollPos, .own⟩ = [] := WebKit.scrollPos_stages .safari 0 .own
  simp [frameWork, stageUnits, scrollWk, h, WebKit.webkit, WebKit.webkitAt]

/-- **Shift on Chromium.** For any frame inputs whose motion window lays nothing out, moving the mount of `c > 0`
boxes from a motion frame `k` to a still frame `j` is a `ShiftLt`.

On Chromium the warm-up lowers the motion peak and keeps every unit and hit total. -/
theorem chromium_shift (fs : Nat → FrameIn Chromium.CrProp) {c j k n : Nat} {K : List Nat} (hc : 0 < c)
    (hj : j < n) (hjK : j ∉ K) (hkK : k ∈ K) (hk : k < n)
    (hz : ∀ i ∈ K, (frameWork Chromium.chromium (fs i)).units .layout = 0) :
    ShiftLt K (arm Chromium.chromium fs (mountCr c) j n) (arm Chromium.chromium fs (mountCr c) k n) :=
  mount_shift _ fs _ hj hjK hkK hk .layout (fun i hi => by rw [hz i hi, mountCr_layout]; exact hc)

/-- **Shift on WebKit.** The same statement under the WebKit model.

On WebKit the warm-up lowers the motion peak and keeps every unit and hit total. -/
theorem webkit_shift (fs : Nat → FrameIn WebKit.WkProp) {c j k n : Nat} {K : List Nat} (hc : 0 < c)
    (hj : j < n) (hjK : j ∉ K) (hkK : k ∈ K) (hk : k < n)
    (hz : ∀ i ∈ K, (frameWork WebKit.webkit (fs i)).units .layout = 0) :
    ShiftLt K (arm WebKit.webkit fs (mountWk c) j n) (arm WebKit.webkit fs (mountWk c) k n) :=
  mount_shift _ fs _ hj hjK hkK hk .layout (fun i hi => by rw [hz i hi, mountWk_layout]; exact hc)

/-- **Mixed on Chromium.** With `c > 0` boxes and two distinct frames inside the run, the screen says `mixed`.

Chromium's framewise screen cannot see the shift. -/
theorem chromium_mixed (fs : Nat → FrameIn Chromium.CrProp) {c j k n : Nat} (hc : 0 < c) (hj : j < n) (hk : k < n)
    (hjk : j ≠ k) :
    Screen.screen (toRun (arm Chromium.chromium fs (mountCr c) k n))
      (toRun (arm Chromium.chromium fs (mountCr c) j n)) = .ok .mixed :=
  shift_screen_mixed _ fs _ hj hk hjk .layout (by rw [mountCr_layout]; exact hc)

/-- **Mixed on WebKit.** The same statement under the WebKit model.

WebKit's framewise screen cannot see the shift. -/
theorem webkit_mixed (fs : Nat → FrameIn WebKit.WkProp) {c j k n : Nat} (hc : 0 < c) (hj : j < n) (hk : k < n)
    (hjk : j ≠ k) :
    Screen.screen (toRun (arm WebKit.webkit fs (mountWk c) k n))
      (toRun (arm WebKit.webkit fs (mountWk c) j n)) = .ok .mixed :=
  shift_screen_mixed _ fs _ hj hk hjk .layout (by rw [mountWk_layout]; exact hc)

/-! ## The swipe scenario (both engines)

Eight frames: frames 0-2 are still (nothing changes), frames 3-7 scroll. The original mounts the 12-box panel in
motion frame 5 (the swipe reaches it); the variant mounts it in still frame 1. The motion window is frames 3-7. -/

/-- A still frame: no script, no forced pass, no hit test, no change, no animation.

Nothing happens. -/
def idle {P : Type} : FrameIn P := ⟨0, 0, 0, 0, [], 0⟩

/-- The Chromium swipe: still before frame 3, a 40 px scroll step from frame 3 on.

Three still frames, then the swipe. -/
def swipeCr (i : Nat) : FrameIn Chromium.CrProp := if i < 3 then idle else scrollCr 40 (i - 3)

/-- The WebKit swipe: still before frame 3, a scroll step from frame 3 on.

Three still frames, then the swipe. -/
def swipeWk (i : Nat) : FrameIn WebKit.WkProp := if i < 3 then idle else scrollWk

/-- The motion window of the scenario.

The scrolled frames. -/
def motion : List Nat := [3, 4, 5, 6, 7]

/-- Chromium, original: mount 12 boxes in motion frame 5 of 8.

The faithful arm. -/
def crO : List Work := arm Chromium.chromium swipeCr (mountCr 12) 5 8

/-- Chromium, variant: mount 12 boxes in still frame 1 of 8.

The warm-up arm. -/
def crV : List Work := arm Chromium.chromium swipeCr (mountCr 12) 1 8

/-- WebKit, original: mount 12 boxes in motion frame 5 of 8.

The faithful arm. -/
def wkO : List Work := arm WebKit.webkit swipeWk (mountWk 12) 5 8

/-- WebKit, variant: mount 12 boxes in still frame 1 of 8.

The warm-up arm. -/
def wkV : List Work := arm WebKit.webkit swipeWk (mountWk 12) 1 8

/-- **The swipe shifts on Chromium.**

Lower motion peak, equal unit and hit totals. -/
theorem cr_swipe_shift : ShiftLt motion crV crO :=
  chromium_shift swipeCr (by decide) (by decide) (by decide) (by decide) (by decide) fun i hi => by
    have : ¬ i < 3 := by simp only [motion, List.mem_cons, List.mem_nil_iff, or_false] at hi; omega
    simp only [swipeCr, this, ite_false]; exact scrollCr_layout _ _

/-- **The swipe shifts on WebKit.**

Lower motion peak, equal unit and hit totals. -/
theorem wk_swipe_shift : ShiftLt motion wkV wkO :=
  webkit_shift swipeWk (by decide) (by decide) (by decide) (by decide) (by decide) fun i hi => by
    have : ¬ i < 3 := by simp only [motion, List.mem_cons, List.mem_nil_iff, or_false] at hi; omega
    simp only [swipeWk, this, ite_false]; exact scrollWk_layout

/-- **The swipe screens `mixed` on Chromium.**

Not `dominates`: frame 1 got heavier. -/
theorem cr_swipe_mixed : Screen.screen (toRun crO) (toRun crV) = .ok .mixed :=
  chromium_mixed swipeCr (by decide) (by decide) (by decide) (by decide)

/-- **The swipe screens `mixed` on WebKit.**

Not `dominates`: frame 1 got heavier. -/
theorem wk_swipe_mixed : Screen.screen (toRun wkO) (toRun wkV) = .ok .mixed :=
  webkit_mixed swipeWk (by decide) (by decide) (by decide) (by decide)

/-- **Not Core's `Shift` on Chromium.** The warm-up frame adds one commit pass, so the pass totals differ.

`ShiftLt`, not `Shift`, is the claim. -/
theorem chromium_not_shift : ¬ Shift motion crV crO := by decide

/-- **Not Core's `Shift` on WebKit.** The warm-up frame adds one commit pass, so the pass totals differ.

`ShiftLt`, not `Shift`, is the claim. -/
theorem webkit_not_shift : ¬ Shift motion wkV wkO := by decide

-- The warm-up adds exactly one commit pass on both engines, so Core's `Shift` (total ≡) fails while `ShiftLt` holds.
#guard (total crV).passes .commit == (total crO).passes .commit + 1
#guard (total wkV).passes .commit == (total wkO).passes .commit + 1
#guard !decide (Shift motion crV crO)
#guard !decide (Shift motion wkV wkO)
-- Style and layout pass totals are equal on both engines (no scroll frame runs them).
#guard (total crV).passes .style == (total crO).passes .style
#guard (total crV).passes .layout == (total crO).passes .layout
#guard (total wkV).passes .style == (total wkO).passes .style
#guard (total wkV).passes .layout == (total wkO).passes .layout
-- The motion peak drops by the 12 layout units on both engines.
#guard (peak motion crO).units .layout == 12 && (peak motion crV).units .layout == 0
#guard (peak motion wkO).units .layout == 12 && (peak motion wkV).units .layout == 0
#guard (match Screen.screen (toRun crO) (toRun crV) with | .ok .mixed => true | _ => false)

/-! ## Golden rows for `engine-check`

Each row compares the variant arm with the original arm on one count type. Frame-exact classes (`det`, stable
`k = 0`) are judged frame by frame; totals classes (stable `k ≥ 1`) by run totals. -/

/-- One count type: its name, the stage it counts, whether it counts units (else passes), and whether its class is
frame-exact (else judged by totals).

How a measured counter maps to the model. -/
structure CountType where
  name : String
  stage : Stage
  units : Bool
  exact : Bool

/-- The JSON name of a stage.

As in the engine golden files. -/
def stageName : Stage → String
  | .script => "script" | .style => "style" | .layout => "layout" | .props => "props"
  | .paint => "paint" | .raster => "raster" | .commit => "commit" | .comp => "comp"

#guard stageName .layout == "layout" && stageName .commit == "commit"

/-- The per-frame series of one count type over an arm.

What the counter would read frame by frame. -/
def series (ws : List Work) (t : CountType) : List Nat :=
  ws.map fun w => if t.units then w.units t.stage else w.passes t.stage

#guard series crO ⟨"x", .layout, true, false⟩ == [0, 0, 0, 0, 0, 12, 0, 0]
#guard series crV ⟨"x", .layout, true, false⟩ == [0, 12, 0, 0, 0, 0, 0, 0]

/-- **The prediction for one row**, first match: every variant frame zero gives `=0`; a frame-exact class gives `=o`
for an equal series, `<o` for a pointwise-below series of the same length, else `any`; a totals class gives `=o`
for equal sums, `≤o` for a smaller sum, else `any`.

The strongest claim the model makes for that count, within what the class can judge. -/
def predict (exact : Bool) (v o : List Nat) : String :=
  if v.all (· == 0) then "=0"
  else if exact then
    if v == o then "=o"
    else if v.length == o.length && (v.zip o).all (fun p => decide (p.1 ≤ p.2)) then "<o"
    else "any"
  else if v.sum == o.sum then "=o"
  else if v.sum < o.sum then "≤o"
  else "any"

#guard predict true [0, 0] [1, 2] == "=0"
#guard predict true [1, 2] [1, 2] == "=o"
#guard predict true [1, 1] [1, 2] == "<o"
#guard predict true [0, 3] [3, 0] == "any"
#guard predict false [0, 3] [3, 0] == "=o"
#guard predict false [0, 2] [3, 0] == "≤o"
#guard predict false [0, 4] [3, 0] == "any"

/-- The Chromium count types of the swipe profiles (classes from `classes.frozen.json`; `trace.Paint` is
quarantined and left out). Each entry is (name, stage, units, exact).

Which counter reads which stage. -/
def crTypes : List CountType :=
  [⟨"trace.FunctionCall", .script, true, true⟩, ⟨"trace.UpdateLayoutTree", .style, false, true⟩,
   ⟨"trace.Layout", .layout, false, false⟩, ⟨"trace.Layout.dirtyObjects", .layout, true, false⟩,
   ⟨"metric.LayoutCount", .layout, false, false⟩, ⟨"trace.PrePaint", .props, false, false⟩,
   ⟨"raster.invalidationAreaPx", .paint, true, false⟩, ⟨"trace.cc.Commit", .commit, false, true⟩]

/-- The WebKit count types (no frozen classes yet; judged by totals, an assumption to revisit when WebKit classes
freeze). Each entry is (name, stage, units, exact).

Which counter reads which stage. -/
def wkTypes : List CountType :=
  [⟨"RecalculateStyles", .style, false, false⟩, ⟨"Layout", .layout, false, false⟩,
   ⟨"Paint", .paint, false, false⟩, ⟨"Composite", .commit, false, false⟩]

/-- One JSON row, keys sorted.

The variant flag is `?fw=morph.mount:shift`; the base is the faithful rewrite. -/
def row (engine scenario : String) (t : CountType) (vs os : List Work) : String :=
  "{\"base\":\"rewrite\",\"countType\":\"" ++ t.name ++ "\",\"engine\":\"" ++ engine ++ "\",\"prediction\":\"" ++
    predict t.exact (series vs t) (series os t) ++ "\",\"scenario\":\"" ++ scenario ++ "\",\"stage\":\"" ++
    stageName t.stage ++ "\",\"variant\":\"rewrite+?fw=morph.mount:shift\"}"

/-- All golden rows: Chromium on `swipe-v1` and `swipe-touch-v1`, WebKit on `swipe-v1`.

The list comprehension runs `sc` outer and `t` inner, so there are `2 · 8 + 4 = 20` lines.
The file `packages/contracts/golden/engine/morph-mount.jsonl`, line by line. -/
def goldenLines : List String :=
  (["swipe-v1", "swipe-touch-v1"].flatMap fun sc => crTypes.map fun t => row "chromium" sc t crV crO) ++
    wkTypes.map fun t => row "webkit" "swipe-v1" t wkV wkO

/-- The golden file text: one row per line, trailing newline.

What the driver writes. -/
def goldenText : String := String.join (goldenLines.map (· ++ "\n"))

#guard goldenLines.length == 20
#guard (crTypes.map fun t => predict t.exact (series crV t) (series crO t)) ==
  ["any", "any", "=o", "=o", "=o", "any", "=o", "any"]
#guard (wkTypes.map fun t => predict t.exact (series wkV t) (series wkO t)) == ["=o", "=o", "=o", "any"]

/-! ## Under the frame-end pass (`frameWorkE`, ledger n=1)

The shift verdict (`mount_shift`, `shift_screen_mixed`) is stated on units and hit tests, which `frameWorkE` counts
exactly as `frameWork` does (`armE_units`, `armE_hits`). The mount and swipe frames only write (no forced pass), so
every touched stage ends dirty and the per-frame work is unchanged as well (`armE_eq_arm`). Verdict unchanged: a
shift, `mixed` on the screen, in both engines. -/

section EndPass

open Fw.Parts.EndFlags

/-- The arm's per-frame work under `frameWorkE`, with end flags `e_i` for frame `i`.

The mount arm with the frame-end pass counted. -/
def armE {P M : Type} (E : Engine P M) (fs : Nat → FrameIn P) (mnt : FrameIn P) (a n : Nat)
    (e : Nat → Stage → Bool) : List Work :=
  (List.range n).map fun i => frameWorkE E (if i = a then merge (fs i) mnt else fs i) (e i)

/-- **Units do not see the end flags.**

The shift's unit argument holds for every flag assignment. -/
theorem armE_units {P M : Type} (E : Engine P M) (fs : Nat → FrameIn P) (mnt : FrameIn P) (a n : Nat)
    (e : Nat → Stage → Bool) (s : Stage) :
    (armE E fs mnt a n e).map (fun w => w.units s) = (arm E fs mnt a n).map (fun w => w.units s) := by
  simp only [armE, arm, List.map_map]
  rfl

/-- **Hit tests do not see the end flags.**

Neither does the hit-test count. -/
theorem armE_hits {P M : Type} (E : Engine P M) (fs : Nat → FrameIn P) (mnt : FrameIn P) (a n : Nat)
    (e : Nat → Stage → Bool) :
    (armE E fs mnt a n e).map (fun w => w.hits) = (arm E fs mnt a n).map (fun w => w.hits) := by
  simp only [armE, arm, List.map_map]
  rfl

/-- **Read-free frames: the arm is unchanged.** If every frame's touched stages end dirty, `armE` is `arm`.

Frames that only write pay every touched stage at frame end, as `frameWork` assumed. -/
theorem armE_eq_arm {P M : Type} (E : Engine P M) (fs : Nat → FrameIn P) (mnt : FrameIn P) (a n : Nat)
    (e : Nat → Stage → Bool)
    (h : ∀ i, i < n → ∀ s, s ∈ touched E (if i = a then merge (fs i) mnt else fs i) → e i s = true) :
    armE E fs mnt a n e = arm E fs mnt a n := by
  unfold armE arm
  apply List.map_congr_left
  intro i hi
  exact frameWorkE_eq_of_dirty E _ (e i) (h i (List.mem_range.mp hi))

end EndPass

/-! ## The scroll stamp after mount (`tap`) -/

/-- Once mounted, the variant stays mounted. -/
theorem mountV_stays (x : Nat → Tick) : ∀ (t d : Nat), mountV x t = true → mountV x (t + d) = true
  | _, 0, h => h
  | t, d + 1, h => by
    show mountNext (mountV x (t + d)) _ _ = true
    rw [mountV_stays x t d h]
    exact mountNext_mono _ _

theorem mountV_prefix (x x' : Nat → Tick) (t0 : Nat) (hx : ∀ t, t < t0 → x t = x' t) :
    ∀ t, t ≤ t0 → mountV x t = mountV x' t
  | 0, _ => rfl
  | t + 1, h => by
    show mountNext (mountV x t) _ _ = mountNext (mountV x' t) _ _
    rw [mountV_prefix x x' t0 hx t (Nat.le_of_succ_le h), hx t h]

/-- Streams that agree before a frame where the variant is mounted give the same mount flag at every frame. -/
theorem mountV_tail_irrelevant (x x' : Nat → Tick) (t0 : Nat) (hx : ∀ t, t < t0 → x t = x' t)
    (hm : mountV x t0 = true) : ∀ t, mountV x t = mountV x' t := by
  intro t
  rcases Nat.lt_or_ge t t0 with h | h
  · exact mountV_prefix x x' t0 hx t (Nat.le_of_lt h)
  · have hm' : mountV x' t0 = true := (mountV_prefix x x' t0 hx t0 (Nat.le_refl _)) ▸ hm
    obtain ⟨d, rfl⟩ := Nat.exists_eq_add_of_le h
    rw [mountV_stays x t0 d hm, mountV_stays x' t0 d hm']

theorem armV_tail_irrelevant {Env : Type} (base : Env → Nat → Scene) (panel : Env → Nat → (Nat → Bool) → Scene)
    (x x' : Env → Nat → Tick) (t0 : Env → Nat) (hx : ∀ env t, t < t0 env → x env t = x' env t)
    (hm : ∀ env, mountV (x env) (t0 env) = true) : armV base panel x = armV base panel x' := by
  funext env t
  have h : mountV (x env) = mountV (x' env) := funext (mountV_tail_irrelevant _ _ _ (hx env) (hm env))
  simp only [armV, h]

/-- The original against a variant whose inputs change only after it has mounted: `VisSame E`, as for `shift`. -/
theorem visSame_tail {Env : Type} (base : Env → Nat → Scene) (panel : Env → Nat → (Nat → Bool) → Scene)
    (x x' : Env → Nat → Tick) (vp : Env → Fw.Engine.Rect) (hp : PhaseFree panel) (hh : HiddenBefore vp panel x)
    (t0 : Env → Nat) (hx : ∀ env t, t < t0 env → x env t = x' env t) (hm : ∀ env, mountV (x env) (t0 env) = true) :
    VisSame E vp (armO base panel x) (armV base panel x') := by
  rw [← armV_tail_irrelevant base panel x x' t0 hx hm]
  exact visSame_mount base panel x vp hp hh

theorem E_after_mount_tail {Env : Type} (base : Env → Nat → Scene) (panel : Env → Nat → (Nat → Bool) → Scene)
    (x x' : Env → Nat → Tick) (vp : Env → Fw.Engine.Rect) (hp : PhaseFree panel)
    (t0 : Env → Nat) (hx : ∀ env t, t < t0 env → x env t = x' env t) (hm : ∀ env, mountV (x env) (t0 env) = true) :
    ∀ env t, mountO (x env) t = true →
      E (visible (vp env) (armO base panel x env t)) (visible (vp env) (armV base panel x' env t)) := by
  rw [← armV_tail_irrelevant base panel x x' t0 hx hm]
  exact E_after_mount base panel x vp hp

/-- What one event step offers: its time in ms, an intersecting entry, a taken push, a wheel or touchmove event the
window listeners see (taken or not: `take` writes the stamp before it tests `takes`), a window scroll event, a run of
the warm check, and whether the morph is active. -/
structure Ev where
  ms : Nat
  near : Bool
  push : Bool
  input : Bool
  scroll : Bool
  check : Bool
  active : Bool
deriving Repr, DecidableEq, Inhabited

/-- `WARM_QUIET_MS` of `logic.ts`. -/
def warmQuietMs : Nat := 150

/-- `warmStill` of `logic.ts`: the morph is idle and the last motion is at least `warmQuietMs` old. -/
def warmStill (active : Bool) (quiet : Nat) : Bool := !active && decide (warmQuietMs ≤ quiet)

#guard warmStill false 150 && !warmStill false 149 && !warmStill true 500

/-- The scroll listener is attached: always under `shift`, until mount under `tap`. -/
def listening (tap mounted : Bool) : Bool := !tap || !mounted

#guard listening false true && listening true false && !listening true true

/-- The mount flag and the time of the last motion stamp. -/
structure Mnt where
  mounted : Bool
  last : Nat
deriving Repr, DecidableEq

/-- The warm check's trigger: it runs, the panel is not mounted, and the moment is still. -/
def warmAt (s : Mnt) (e : Ev) : Bool := e.check && !s.mounted && warmStill e.active (e.ms - s.last)

/-- One event step: mount on an entry, a push or a still warm check; stamp on a push, a wheel or touchmove input, or a
scroll the listener hears. -/
def step (tap : Bool) (e : Ev) (s : Mnt) : Mnt :=
  ⟨mountNext s.mounted (e.near || warmAt s e) e.push,
   if e.push || e.input || (e.scroll && listening tap s.mounted) then e.ms else s.last⟩

/-- The state before event step `t`; the effect starts unmounted with its stamp at time 0. -/
def run (tap : Bool) (e : Nat → Ev) : Nat → Mnt
  | 0 => ⟨false, 0⟩
  | t + 1 => step tap (e t) (run tap e t)

/-- The listener calls before step `n`: one per scroll event the listener hears. -/
def calls (tap : Bool) (e : Nat → Ev) : Nat → Nat
  | 0 => 0
  | n + 1 => calls tap e n + if (e n).scroll && listening tap (run tap e n).mounted then 1 else 0

/-- The scroll events before step `n` that arrive once `shift` has mounted. -/
def scrollsAfterMount (e : Nat → Ev) : Nat → Nat
  | 0 => 0
  | n + 1 => scrollsAfterMount e n + if (e n).scroll && (run false e n).mounted then 1 else 0

/-- The frame inputs (`Tick`) the event steps give the mount rule. -/
def tickOf (tap : Bool) (e : Nat → Ev) (t : Nat) : Tick := ⟨(e t).near, (e t).push, warmAt (run tap e t) (e t)⟩

theorem mnt_eq {a b : Mnt} (h1 : a.mounted = b.mounted) (h2 : a.last = b.last) : a = b := by
  cases a; cases b; cases h1; cases h2; rfl

theorem run_tap (e : Nat → Ev) : ∀ t, (run true e t).mounted = (run false e t).mounted ∧
    ((run false e t).mounted = false → (run true e t).last = (run false e t).last)
  | 0 => ⟨rfl, fun _ => rfl⟩
  | t + 1 => by
    obtain ⟨hm, hl⟩ := run_tap e t
    show (step true (e t) (run true e t)).mounted = (step false (e t) (run false e t)).mounted ∧
      ((step false (e t) (run false e t)).mounted = false →
        (step true (e t) (run true e t)).last = (step false (e t) (run false e t)).last)
    cases h : (run false e t).mounted with
    | false =>
      have hs : run true e t = run false e t := mnt_eq hm (hl h)
      have hstep : step true (e t) (run false e t) = step false (e t) (run false e t) := by
        simp [step, listening, h]
      rw [hs, hstep]
      exact ⟨rfl, fun _ => rfl⟩
    | true =>
      rw [h] at hm
      exact ⟨by simp [step, mountNext, hm, h], fun hf => by simp [step, mountNext, h] at hf⟩

/-- Detaching the listener at mount leaves the mount flag at every step unchanged. -/
theorem mounted_tap (e : Nat → Ev) (t : Nat) : (run true e t).mounted = (run false e t).mounted :=
  (run_tap e t).1

theorem warmAt_tap (e : Nat → Ev) (t : Nat) : warmAt (run true e t) (e t) = warmAt (run false e t) (e t) := by
  obtain ⟨hm, hl⟩ := run_tap e t
  unfold warmAt
  cases h : (run false e t).mounted with
  | false => rw [hm, hl h, h]
  | true => rw [hm, h]; simp

/-- The warm check never reads a stamp written after mount: the frame inputs are the same with or without the listener. -/
theorem tickOf_tap (e : Nat → Ev) : tickOf true e = tickOf false e := by
  funext t
  simp only [tickOf, warmAt_tap]

theorem mounted_eq_mountV (tap : Bool) (e : Nat → Ev) : ∀ t, (run tap e t).mounted = mountV (tickOf tap e) t
  | 0 => rfl
  | t + 1 => by
    show mountNext (run tap e t).mounted _ _ = mountNext (mountV (tickOf tap e) t) _ _
    rw [mounted_eq_mountV tap e t]
    rfl

/-- Under `tap` no scroll event writes the stamp after mount; only a push or a wheel or touchmove input still does. -/
theorem tap_no_stamp_after_mount (e : Nat → Ev) (t : Nat) (hm : (run true e t).mounted = true)
    (hp : (e t).push = false) (hi : (e t).input = false) : (run true e (t + 1)).last = (run true e t).last := by
  simp [run, step, listening, hm, hp, hi]

/-- Under `shift` every scroll event after mount writes the stamp, which nothing reads. -/
theorem shift_stamps_after_mount (e : Nat → Ev) (t : Nat) (hs : (e t).scroll = true) :
    (run false e (t + 1)).last = (e t).ms := by
  simp [run, step, listening, hs]

/-- `shift` calls the listener once more than `tap` for each scroll event after mount. -/
theorem calls_shift (e : Nat → Ev) : ∀ n, calls false e n = calls true e n + scrollsAfterMount e n
  | 0 => rfl
  | n + 1 => by
    simp only [calls, scrollsAfterMount, calls_shift e n, mounted_tap, listening]
    cases (e n).scroll <;> cases (run false e n).mounted <;> simp <;> omega

/-- Equal scenes at every frame, for every panel and environment, with or without the listener. -/
theorem armV_tap {Env : Type} (base : Env → Nat → Scene) (panel : Env → Nat → (Nat → Bool) → Scene)
    (ev : Env → Nat → Ev) :
    armV base panel (fun env => tickOf true (ev env)) = armV base panel (fun env => tickOf false (ev env)) := by
  simp only [tickOf_tap]

/-! ## Golden rows for the TS replay (`packages/contracts/golden/parts/morph-mount-tap.jsonl`) -/

/-- Event streams: warm mount then scrolls, scrolls delaying the warm mount, entry mount, push mount, active morph,
never mounted, untaken input delaying the warm mount then input and scrolls after it. -/
def tapStreams (_ : Unit := ()) : List (List Ev) :=
  let c (t : Nat) : Ev := ⟨t, false, false, false, false, true, false⟩
  let sc (t : Nat) : Ev := ⟨t, false, false, false, true, false, false⟩
  let wh (t : Nat) : Ev := ⟨t, false, false, true, false, false, false⟩
  [[c 150, c 167, sc 200, sc 217, c 230, sc 233, sc 250],
   [sc 100, sc 140, c 200, c 300, sc 316, sc 333, c 500],
   [sc 20, ⟨40, true, false, false, true, false, false⟩, sc 60, sc 80, c 300],
   [sc 30, ⟨45, false, true, true, false, false, false⟩, sc 60, c 300, sc 310],
   [⟨200, false, false, false, false, true, true⟩, sc 210, ⟨400, false, false, false, false, true, false⟩, sc 420],
   [sc 10, sc 20, c 100, sc 120, sc 130],
   [wh 100, c 200, c 250, wh 260, sc 270, c 500, sc 510]]

def streamOf (l : List Ev) (t : Nat) : Ev := l.getD t default

def evJson (e : Ev) : Lean.Json :=
  .arr #[.num e.ms, .bool e.near, .bool e.push, .bool e.input, .bool e.scroll, .bool e.check, .bool e.active]

def tapLine (fn : String) (inp : List (String × Lean.Json)) (out : Lean.Json) : String :=
  (Lean.Json.mkObj [("fn", .str fn), ("in", Lean.Json.mkObj inp), ("out", out)]).compress

def tapFrame (e : Nat → Ev) (t : Nat) : Lean.Json :=
  Lean.Json.mkObj [("m", .bool (run false e t).mounted), ("mt", .bool (run true e t).mounted),
    ("c", .num (calls false e t)), ("ct", .num (calls true e t))]

/-- The golden lines: `warmStill` around the 150 ms edge, then one replay row per stream. -/
def tapLines (_ : Unit := ()) : List String :=
  ([false, true].flatMap fun a => [0, 149, 150, 151, 1000].map fun (q : Nat) =>
      tapLine "warmStill" [("active", .bool a), ("quiet", .num (Lean.JsonNumber.fromNat q))] (.bool (warmStill a q))) ++
  (tapStreams ()).map fun l =>
    tapLine "tapRun" [("events", .arr (l.map evJson).toArray)]
      (.arr ((List.range (l.length + 1)).map (tapFrame (streamOf l))).toArray)

#guard (tapLines ()).length == 10 + 7
#guard (tapStreams ()).all fun l => let e := streamOf l
  (List.range (l.length + 1)).all fun t => (run true e t).mounted == (run false e t).mounted
#guard (run false (streamOf ((tapStreams ()).head!)) 2).mounted
#guard calls false (streamOf ((tapStreams ()).head!)) 7 == 4 && calls true (streamOf ((tapStreams ()).head!)) 7 == 0
#guard let e := streamOf ((tapStreams ()).getLast!)
  !(run false e 2).mounted && (run false e 3).mounted && (run true e 7).last == 260 && (run false e 7).last == 510

def tapText (_ : Unit := ()) : String := String.join ((tapLines ()).map (· ++ "\n"))

/-- Print the tap golden text, or with `--check <file>` compare it; exit 1 on a difference. -/
def tapMain (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == tapText () then
      IO.eprintln s!"tap golden: {path} is up to date ({(tapLines ()).length} lines)"
      return 0
    IO.eprintln s!"tap golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (tapText ())
    return 0

end Fw.Parts.MorphMountOpt
