import Fw.Measure.MorphEndCount
import Fw.Faithful.Zone
/-!
# Fw.Measure.VerdictEvidence: an empty side is never a win, for verdicts whose modules this audit does not edit
-/
namespace Fw.Measure.VerdictEvidence

theorem morphEnd_win_needs_cost (base cand : List MorphEndCount.TbPass) (h : MorphEndCount.flagVerdict base cand = .win) :
    MorphEndCount.costKnown base cand = true := by
  cases hk : MorphEndCount.costKnown base cand
  · exact absurd h (MorphEndCount.flagVerdict_cost_unknown_not_win base cand hk)
  · rfl

theorem faithful_findZ_nil (Z : String) : Fw.Faithful.findZ [] Z = none := rfl

theorem faithful_regionPass_empty_a (tb : Freeze.Table) (rs : List Fw.Faithful.ZBase) :
    Fw.Faithful.regionPass tb [] rs = false := by
  simp [Fw.Faithful.regionPass, Fw.Faithful.regionZones, Fw.Faithful.zoneVerdict, faithful_findZ_nil,
    Fw.Faithful.ZoneVerdict.pass]

theorem faithful_regionPass_empty_r (tb : Freeze.Table) (as : List Fw.Faithful.ZBase) :
    Fw.Faithful.regionPass tb as [] = false := by
  simp only [Fw.Faithful.regionPass, Fw.Faithful.regionZones, List.all_eq_false]
  exact ⟨"tail", by simp, by simp [Fw.Faithful.not_pass_of_absent tb as [] "tail" (Or.inr (faithful_findZ_nil _))]⟩

end Fw.Measure.VerdictEvidence
