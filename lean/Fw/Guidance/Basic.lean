import Fw.Engine
/-!
# Guidance proofs: shared frame algebra (task guidance-proofs)

`join` puts a second frame's inputs into a first; added inputs never lower frame work under any engine
(`frame_le_join`), and added script or an added stage unit raises it (`frame_lt_join_script`, `frame_lt_join_change`).
The rule files `Fw.Guidance.*` state each Chrome Modern Web Guidance rule through these lemmas.
-/
namespace Fw.Guidance

open Fw.Engine

/-- A frame with no input: no script, no forced pass, no hit test, no change, no compositor animation.

The empty frame. -/
def idle {P : Type} : FrameIn P := ⟨0, 0, 0, 0, [], 0⟩

/-- Two frames' inputs in one frame: counts add, change lists concatenate.

The frame that does what both frames do. -/
def join {P : Type} (f g : FrameIn P) : FrameIn P :=
  ⟨f.script + g.script, f.forcedStyle + g.forcedStyle, f.forcedLayout + g.forcedLayout, f.hits + g.hits,
    f.changes ++ g.changes, f.compAnims + g.compAnims⟩

/-- A frame of script callbacks only.

What a callback that writes nothing adds to a frame. -/
def scriptOnly {P : Type} (n : Nat) : FrameIn P := ⟨n, 0, 0, 0, [], 0⟩

/-- A frame of changes only.

What a style write outside script adds to a frame. -/
def changesOnly {P : Type} (cs : List (Change P)) : FrameIn P := ⟨0, 0, 0, 0, cs, 0⟩

/-- Every change list covers itself.

Each change's stages are its own stages. -/
theorem coverB_refl {P M : Type} (E : Engine P M) : ∀ l : List (Change P), coverB E l l = true
  | [] => rfl
  | c :: cs => by simp [coverB, coverB_refl E cs]

/-- Units add over `join`.

Every unit of either frame is a unit of the joined frame. -/
theorem units_join {P M : Type} (E : Engine P M) (f g : FrameIn P) (s : Stage) :
    stageUnits E (join f g) s = stageUnits E f s + stageUnits E g s := by
  simp only [stageUnits, join, List.countP_append]
  split <;> split <;> omega

/-- Forced passes add over `join`.

Every forced pass of either frame is a forced pass of the joined frame. -/
theorem forced_join {P : Type} (f g : FrameIn P) (s : Stage) :
    forcedPasses (join f g) s = forcedPasses f s + forcedPasses g s := by
  cases s <;> simp [forcedPasses, join]

/-- **Added inputs never lower work.**

Removing a frame's share of work never costs more, under every engine. -/
theorem frame_le_join {P M : Type} (E : Engine P M) (f g : FrameIn P) :
    (frameWork E f).le (frameWork E (join f g)) :=
  frame_le_of_cover E f.changes g.changes (by simp [join]) (coverB_refl E _)
    (Nat.le_add_right _ _) (Nat.le_add_right _ _) (Nat.le_add_right _ _) (Nat.le_add_right _ _)
    (Nat.le_add_right _ _)

/-- **Added inputs never lower work**, with the added frame first.

The second share alone is also at most the joined frame. -/
theorem frame_le_join_right {P M : Type} (E : Engine P M) (f g : FrameIn P) :
    (frameWork E g).le (frameWork E (join f g)) :=
  frame_le_of_cover E g.changes f.changes (by simp [join]; exact List.perm_append_comm) (coverB_refl E _)
    (Nat.le_add_left _ _) (Nat.le_add_left _ _) (Nat.le_add_left _ _) (Nat.le_add_left _ _)
    (Nat.le_add_left _ _)

/-- A strict order from `≤` and one stage with fewer units.

One smaller unit count makes `≤` strict. -/
theorem lt_of_le_units {a b : Work} (s : Stage) (h : a.le b) (hu : a.units s < b.units s) : a.lt b :=
  ⟨h, .inl ⟨s, .inr hu⟩⟩

/-- A strict step followed by a `≤` step is strict.

Strictness survives a further `≤`. -/
theorem lt_of_lt_of_le {a b c : Work} (h1 : a.lt b) (h2 : b.le c) : a.lt c := by
  refine ⟨Work.le_trans h1.1 h2, ?_⟩
  rcases h1.2 with ⟨s, hs | hs⟩ | hh
  · exact .inl ⟨s, .inl (Nat.lt_of_lt_of_le hs (h2.1 s).1)⟩
  · exact .inl ⟨s, .inr (Nat.lt_of_lt_of_le hs (h2.1 s).2)⟩
  · exact .inr (Nat.lt_of_lt_of_le hh h2.2)

/-- **Added units make it strict.** If the added frame has a unit on some stage, the joined frame is strictly more work.

Dropping a share that does anything is a strict saving. -/
theorem frame_lt_join_units {P M : Type} (E : Engine P M) (f g : FrameIn P) (s : Stage)
    (h : 0 < stageUnits E g s) : (frameWork E f).lt (frameWork E (join f g)) := by
  refine lt_of_le_units s (frame_le_join E f g) ?_
  show stageUnits E f s < stageUnits E (join f g) s
  rw [units_join]; omega

/-- **Added script makes it strict.**

Dropping a callback is a strict saving. -/
theorem frame_lt_join_script {P M : Type} (E : Engine P M) (f g : FrameIn P) (h : 0 < g.script) :
    (frameWork E f).lt (frameWork E (join f g)) := by
  refine frame_lt_join_units E f g .script ?_
  simp only [stageUnits, ↓reduceIte]
  omega

/-- **An added change makes it strict.**

Dropping a change that dirties any stage is a strict saving. -/
theorem frame_lt_join_change {P M : Type} (E : Engine P M) (f g : FrameIn P) (c : Change P) (hc : c ∈ g.changes)
    (s : Stage) (hs : s ∈ E.stagesOf c) : (frameWork E f).lt (frameWork E (join f g)) := by
  refine frame_lt_join_units E f g s ?_
  have : 0 < g.changes.countP (fun c => decide (s ∈ E.stagesOf c)) :=
    List.countP_pos_iff.mpr ⟨c, hc, by simpa using hs⟩
  simp only [stageUnits]
  omega

/-- `≤` on every stage but one, plus `≤` on hit tests.

The order with one stage, usually `comp`, left out. -/
def offLe (x : Stage) (a b : Work) : Bool :=
  Stage.all.all (fun s => s == x || (decide (a.passes s ≤ b.passes s) && decide (a.units s ≤ b.units s))) &&
    decide (a.hits ≤ b.hits)

/-- The Boolean check is the order off one stage.

What `offLe` checks, spelled out. -/
theorem offLe_iff (x : Stage) (a b : Work) :
    offLe x a b = true ↔ (∀ s, s ≠ x → a.passes s ≤ b.passes s ∧ a.units s ≤ b.units s) ∧ a.hits ≤ b.hits := by
  simp only [offLe, Bool.and_eq_true, List.all_eq_true, Bool.or_eq_true, beq_iff_eq, decide_eq_true_eq]
  constructor
  · rintro ⟨h, hh⟩
    refine ⟨fun s hs => ?_, hh⟩
    rcases h s (Stage.mem_all s) with h' | h'
    · exact absurd h' hs
    · exact h'
  · rintro ⟨h, hh⟩
    refine ⟨fun s _ => ?_, hh⟩
    by_cases hs : s = x
    · exact .inl hs
    · exact .inr (h s hs)

#guard offLe .comp (frameWork (Fw.Engine.Chromium.chromiumAt Fw.Engine.Chromium.realChrome) idle)
  (frameWork (Fw.Engine.Chromium.chromiumAt Fw.Engine.Chromium.realChrome) (scriptOnly 1))
#guard !offLe .comp (frameWork (Fw.Engine.Chromium.chromiumAt Fw.Engine.Chromium.realChrome) (scriptOnly 1))
  (frameWork (Fw.Engine.Chromium.chromiumAt Fw.Engine.Chromium.realChrome) idle)

/-- `n` copies of a frame's inputs in one frame.

A handler that runs `n` times in one frame. -/
def rep {P : Type} : Nat → FrameIn P → FrameIn P
  | 0, _ => idle
  | n + 1, h => join (rep n h) h

/-- More copies never lower work.

Fewer handler runs per frame never cost more. -/
theorem rep_le {P M : Type} (E : Engine P M) (h : FrameIn P) (k : Nat) :
    ∀ n, k ≤ n → (frameWork E (rep k h)).le (frameWork E (rep n h))
  | 0, hk => by rw [Nat.le_zero.mp hk]; exact Work.le_refl _
  | n + 1, hk => by
    rcases Nat.lt_or_ge k (n + 1) with hlt | hge
    · exact Work.le_trans (rep_le E h k n (by omega)) (frame_le_join E (rep n h) h)
    · rw [show k = n + 1 by omega]; exact Work.le_refl _

/-- More copies of a callback are strictly more work.

Each dropped handler run is a strict saving. -/
theorem rep_lt {P M : Type} (E : Engine P M) (h : FrameIn P) (hs : 0 < h.script) (k : Nat) :
    ∀ n, k < n → (frameWork E (rep k h)).lt (frameWork E (rep n h))
  | 0, hk => absurd hk (Nat.not_lt_zero _)
  | n + 1, hk => by
    have step : (frameWork E (rep n h)).lt (frameWork E (rep (n + 1) h)) := frame_lt_join_script E (rep n h) h hs
    rcases Nat.lt_or_ge k n with hlt | hge
    · exact lt_of_lt_of_le (rep_lt E h hs k n hlt) step.1
    · rw [show k = n by omega]; exact step

end Fw.Guidance
