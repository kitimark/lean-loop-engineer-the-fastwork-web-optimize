import Fw.Preset.V2Proved
/-!
# Look class from mid-animation evidence: a flag is `l` when a pixel lane or the morph trajectory sees a mid-animation
change, whatever the rest-state gate and the open/close cell say.
-/
namespace Fw.Preset.LookClass
open Fw.Preset (VisClass)

/-- The nav-clip cell grade of the open/close frames. -/
inductive Cell where
  | e
  | q
  | l
deriving DecidableEq, Repr

/-- What was seen for one flag: the rest-state gate, the open/close cell, the changed pixels mid-morph against the
later-load floor of the same lane, and whether the morph trajectory is red. -/
structure Seen where
  restGate : Bool
  cell : Cell
  midChanged : Nat
  midFloor : Nat
  morphRed : Bool
deriving Repr

/-- Whether the mid-morph pixel count is above the lane's own later-load floor. -/
def pxOver (s : Seen) : Bool := decide (s.midFloor < s.midChanged)

/-- The look class: `l` when the pixels, the morph trajectory or the cell see a change, else `q`. -/
def classOf (s : Seen) : VisClass :=
  if pxOver s || s.morphRed || s.cell == .l then .l else .q

theorem l_of_px {s : Seen} (h : s.midFloor < s.midChanged) : classOf s = .l := by
  simp [classOf, pxOver, h]

theorem l_of_traj {s : Seen} (h : s.morphRed = true) : classOf s = .l := by
  simp [classOf, h]

theorem l_of_cell {s : Seen} (h : s.cell = .l) : classOf s = .l := by
  simp [classOf, h]

theorem q_only_if_clean {s : Seen} (h : classOf s = .q) :
    s.midChanged ≤ s.midFloor ∧ s.morphRed = false ∧ s.cell ≠ .l := by
  unfold classOf at h
  by_cases h1 : (pxOver s || s.morphRed || s.cell == .l) = true
  · simp [h1] at h
  · simp [pxOver] at h1
    exact ⟨h1.1.1, h1.1.2, h1.2⟩

/-- **The rest-state gate cannot see it**: the class does not depend on the rest gate. -/
theorem rest_blind (s : Seen) (b : Bool) : classOf { s with restGate := b } = classOf s := rfl

/-- **An exact open/close cell cannot see it**: with pixels above the floor the class is `l` for every cell grade. -/
theorem cell_blind {s : Seen} (c : Cell) (h : s.midFloor < s.midChanged) :
    classOf { s with cell := c } = .l := l_of_px (s := { s with cell := c }) h

/-- clip-box, Simulator run gpu-safari-sim-2026-10-23T00-46-14-744Z, m0.5; CI run 39887328839 (morph path red). -/
def clipBox : Seen := { restGate := true, cell := .e, midChanged := 1020729, midFloor := 0, morphRed := true }
/-- bar-fixed, m0.5; CI run 39887331854. -/
def barFixed : Seen := { restGate := true, cell := .e, midChanged := 1021369, midFloor := 0, morphRed := true }
/-- logo-3d, m0.5; CI run 39887335005. -/
def logo3d : Seen := { restGate := true, cell := .e, midChanged := 1021646, midFloor := 0, morphRed := true }

theorem clipBox_l : classOf clipBox = .l := l_of_px (by decide)
theorem barFixed_l : classOf barFixed = .l := l_of_px (by decide)
theorem logo3d_l : classOf logo3d = .l := l_of_px (by decide)

end Fw.Preset.LookClass
