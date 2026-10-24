import Fw.Sup.Adapt

/-! What a released `sim` lease shuts down: the devices it booted, unless the next queued sim holder takes them over
(docs/team/tools/slot.md, "Simulator release"). -/
namespace Fw.Sup.Adapt

/-- The devices booted since the lease began. -/
def simOurs (before booted : List String) : List String := booted.filter fun u => !before.contains u

/-- Whether a live queued sim ticket takes the devices over. -/
def simHandover (now : Nat) (queue : List Entry) : Bool := queue.any fun e => e.kind == .sim && live now e

/-- The udids to shut down and the record kept for the next holder. -/
def simSettle (before booted : List String) (handover : Bool) : List String × Option (List String) :=
  if handover then ([], some before) else (simOurs before booted, none)

/-- The list a new sim holder records at acquire. -/
def simRecord (inherited : Option (List String)) (booted : List String) : List String := inherited.getD booted

#guard simOurs ["A"] ["A", "B"] == ["B"]
#guard simSettle ["A"] ["A", "B"] false == (["B"], none)
#guard simSettle ["A"] ["A", "B"] true == ([], some ["A"])
#guard simRecord (some ["A"]) ["A", "B"] == ["A"]

theorem simOurs_mem (before booted : List String) (u : String) :
    u ∈ simOurs before booted ↔ u ∈ booted ∧ u ∉ before := by
  simp [simOurs]

theorem simSettle_preexisting_kept (before booted : List String) (h : Bool) {u : String} (hu : u ∈ before) :
    u ∉ (simSettle before booted h).1 := by
  unfold simSettle; split
  · simp
  · rw [simOurs_mem]; intro ⟨_, hn⟩; exact hn hu

theorem simSettle_shut_booted (before booted : List String) (h : Bool) {u : String}
    (hu : u ∈ (simSettle before booted h).1) : u ∈ booted := by
  unfold simSettle at hu; split at hu
  · simp at hu
  · exact ((simOurs_mem _ _ _).1 hu).1

theorem simSettle_release_clean (before booted : List String) {u : String} (hb : u ∈ booted)
    (hk : u ∉ (simSettle before booted false).1) : u ∈ before := by
  refine Classical.byContradiction fun hn => hk ?_
  simp [simSettle, (simOurs_mem _ _ _).2 ⟨hb, hn⟩]

theorem simSettle_release_clears (before booted : List String) : (simSettle before booted false).2 = none := by
  simp [simSettle]

theorem simSettle_handover (before booted : List String) :
    (simSettle before booted true).1 = [] ∧ (simSettle before booted true).2 = some before := by
  simp [simSettle]

theorem simHandover_keeps_for_live_holder (now : Nat) (queue : List Entry) (before booted : List String) {u : String}
    (hb : u ∈ booted) (hn : u ∉ before) (hk : u ∉ (simSettle before booted (simHandover now queue)).1) :
    ∃ e ∈ queue, e.kind = .sim ∧ now < e.till := by
  cases hh : simHandover now queue
  · exact absurd (by simp [simSettle, (simOurs_mem _ _ _).2 ⟨hb, hn⟩]) (hh ▸ hk)
  · simp only [simHandover, List.any_eq_true, Bool.and_eq_true, beq_iff_eq, live, decide_eq_true_eq] at hh
    obtain ⟨e, he, h1, h2⟩ := hh
    exact ⟨e, he, h1, h2⟩

theorem simRecord_inherits (before booted : List String) : simRecord (simSettle before booted true).2 booted = before := rfl

theorem simRecord_fresh (booted : List String) : simRecord none booted = booted := rfl

theorem simRecord_fresh_ours_empty (booted : List String) : simOurs (simRecord none booted) booted = [] := by
  simp [simOurs, simRecord]

end Fw.Sup.Adapt
