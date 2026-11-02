/-!
# Why `morph.tween:waapi-scoped` leaves the WebKit record count unchanged
One WebKit frame of the `--morph` tween: records per frame depend on acceleration, elements per record on the scope.
-/
namespace Fw.Measure.WaapiScopedWebkit

abbrev Visit := List Nat

/-- The records of one frame. A custom property is never accelerated (`Style::Interpolation::isAccelerated` returns false
for an `AtomString`, `StyleInterpolation.cpp:256-265@862f17d`; `KeyframeEffect.cpp:1740-1768@862f17d` then sets
`AcceleratedProperties::None`), so the tween runs on the main thread and every frame holds one record (INFERRED from that
source, not a timeline count). An accelerated property gives no main-thread record. -/
def records (accelerated : Bool) (visit : Visit) : List Visit :=
  if accelerated then [] else [visit]

def scopedVisit (platform base : Visit) : Visit := base.filter (fun e => !platform.contains e)

def visited (rs : List Visit) : Nat := (rs.map List.length).sum

theorem records_len_eq (platform base : Visit) :
    (records false (scopedVisit platform base)).length = (records false base).length := rfl

theorem records_len_one (v : Visit) : (records false v).length = 1 := rfl

theorem records_accelerated (platform base : Visit) :
    records true (scopedVisit platform base) = [] ∧ records true base = [] := ⟨rfl, rfl⟩

theorem scoped_subset (platform base : Visit) {e : Nat} (h : e ∈ scopedVisit platform base) : e ∈ base :=
  (List.mem_filter.mp h).1

theorem scoped_avoids (platform base : Visit) {e : Nat} (h : e ∈ scopedVisit platform base) : e ∉ platform := by
  have := (List.mem_filter.mp h).2
  intro hp
  simp [hp] at this

theorem visited_le (platform base : Visit) :
    visited (records false (scopedVisit platform base)) ≤ visited (records false base) := by
  simp only [visited, records, List.map, List.sum_cons, List.sum_nil, Nat.add_zero, Bool.false_eq_true, ite_false]
  exact List.length_filter_le _ _

theorem visited_accelerated (platform base : Visit) :
    visited (records true (scopedVisit platform base)) = 0 ∧ visited (records true base) = 0 := ⟨rfl, rfl⟩

theorem fewer_visits_equal_records :
    ∃ platform base : Visit,
      visited (records false (scopedVisit platform base)) < visited (records false base) ∧
      (records false (scopedVisit platform base)).length = (records false base).length :=
  ⟨[1], [0, 1, 2], by decide, rfl⟩

end Fw.Measure.WaapiScopedWebkit
