/-!
# Why `morph.tween:waapi-scoped` leaves the WebKit record count unchanged
One WebKit frame of the `--morph` tween: records per frame depend on acceleration, elements per record on the scope.
-/
namespace Fw.Measure.WaapiScopedWebkit

/-- The elements one RecalculateStyles record visits, as element ids. -/
abbrev Visit := List Nat

/-- The records of one frame. A custom property is never accelerated (`Style::Interpolation::isAccelerated` returns false
for an `AtomString`, `StyleInterpolation.cpp:256-265@862f17d`; `KeyframeEffect.cpp:1740-1768@862f17d` then sets
`AcceleratedProperties::None`), so the tween runs on the main thread and every frame holds one record (INFERRED from that
source, not a timeline count). An accelerated property gives no main-thread record. -/
def records (accelerated : Bool) (visit : Visit) : List Visit :=
  if accelerated then [] else [visit]

/-- The scoped arm: the non-inherited `--platform-morph` removes the platform subtree from the visit. -/
def scopedVisit (platform base : Visit) : Visit := base.filter (fun e => !platform.contains e)

/-- Elements visited in a frame. -/
def visited (rs : List Visit) : Nat := (rs.map List.length).sum

/-- Not accelerated: both arms have the same number of main-thread records per frame. -/
theorem records_len_eq (platform base : Visit) :
    (records false (scopedVisit platform base)).length = (records false base).length := rfl

/-- Not accelerated: one record per frame in each arm. -/
theorem records_len_one (v : Visit) : (records false v).length = 1 := rfl

/-- Accelerated: neither arm has a main-thread record, whatever the visit. -/
theorem records_accelerated (platform base : Visit) :
    records true (scopedVisit platform base) = [] ∧ records true base = [] := ⟨rfl, rfl⟩

/-- The scoped arm visits a subset of the base arm's elements, the only change. -/
theorem scoped_subset (platform base : Visit) {e : Nat} (h : e ∈ scopedVisit platform base) : e ∈ base :=
  (List.mem_filter.mp h).1

/-- The scoped arm never visits a platform element. -/
theorem scoped_avoids (platform base : Visit) {e : Nat} (h : e ∈ scopedVisit platform base) : e ∉ platform := by
  have := (List.mem_filter.mp h).2
  intro hp
  simp [hp] at this

/-- Not accelerated, element totals: scoped visits no more elements than base. -/
theorem visited_le (platform base : Visit) :
    visited (records false (scopedVisit platform base)) ≤ visited (records false base) := by
  simp only [visited, records, List.map, List.sum_cons, List.sum_nil, Nat.add_zero, Bool.false_eq_true, ite_false]
  exact List.length_filter_le _ _

/-- Accelerated, element totals: both arms visit nothing on the main thread. -/
theorem visited_accelerated (platform base : Visit) :
    visited (records true (scopedVisit platform base)) = 0 ∧ visited (records true base) = 0 := ⟨rfl, rfl⟩

/-- Element count and record count are separate: a scoped frame with fewer visits and equal records. -/
theorem fewer_visits_equal_records :
    ∃ platform base : Visit,
      visited (records false (scopedVisit platform base)) < visited (records false base) ∧
      (records false (scopedVisit platform base)).length = (records false base).length :=
  ⟨[1], [0, 1, 2], by decide, rfl⟩

end Fw.Measure.WaapiScopedWebkit
