import Fw.Console.BuildsOpen
import Fw.Console.Compose

namespace Fw.Parts.MorphEndReleaseConflict
open Fw.Console.BuildsOpen

def waapiKeys : List String := ["morph.tween:waapi", "morph.tween:waapi-scoped"]

def releaseRule : List (String × List String) := [("morph.end.release:on", waapiKeys)]

theorem mem_of_lookup_some {α : Type} [BEq α] [LawfulBEq α] {β : Type} (l : List (α × β)) (k : α) (v : β)
    (h : l.lookup k = some v) : (k, v) ∈ l := by
  induction l with
  | nil => simp [List.lookup] at h
  | cons a t ih =>
    obtain ⟨x, y⟩ := a
    simp only [List.lookup] at h
    by_cases hk : k == x
    · simp [hk] at h
      have := beq_iff_eq.1 hk
      subst this; subst h; simp
    · simp [hk] at h
      exact List.mem_cons_of_mem _ (ih h)

theorem finish_refuses (parts : List PartFact) (p : PartFact) (hp : p ∈ parts) (hid : p.id = "morph.end.release")
    (hc : p.conflicts.lookup "morph.end.release:on" = some waapiKeys) (st : St)
    (hr : st.sel.lookup "morph.end.release" = some "on") (b : String) (hb : b ∈ waapiKeys)
    (hw : (selected st.sel).contains b = true) : finish parts st ≠ [] := by
  by_cases he : st.errs = []
  · rw [finish_clean parts st he]
    refine ruleErrors_conflicts parts st.sel p hp b ?_ hw
    rw [hid, hr]
    simp [hc, hb]
  · exact finish_pos parts st (List.length_pos_iff.2 he)

theorem validate_ok_clean (parts presets) (s c : String) (h : validate parts presets s = .ok c) :
    searchErrors parts presets (params (body s)) = [] := by
  unfold validate at h
  split at h
  · cases h
  · split at h
    · cases h
    · dsimp only at h
      generalize hE : searchErrors parts presets (params (body s)) = es at h
      cases es with
      | nil => rfl
      | cons a t =>
        rw [verdictOf_refused _ _ _ _ (List.cons_ne_nil a t)] at h
        cases h

theorem accepted_no_release_waapi (parts presets) (s c : String) (h : validate parts presets s = .ok c)
    (p : PartFact) (hp : p ∈ parts) (hid : p.id = "morph.end.release")
    (hc : p.conflicts.lookup "morph.end.release:on" = some waapiKeys) (b : String) (hb : b ∈ waapiKeys) :
    ¬ ((((fwEntries (params (body s))).foldl (applyFwEntry parts)
          (stage1 parts presets (valuesOf "preset" (params (body s))))).sel.lookup "morph.end.release" = some "on") ∧
      (selected ((fwEntries (params (body s))).foldl (applyFwEntry parts)
          (stage1 parts presets (valuesOf "preset" (params (body s))))).sel).contains b = true) := by
  intro ⟨hr, hw⟩
  have h0 := validate_ok_clean parts presets s c h
  unfold searchErrors at h0
  have h1 := (List.append_eq_nil_iff.1 h0).1
  exact finish_refuses parts p hp hid hc _ hr b hb hw h1

theorem decided_no_release_waapi (parts : List Fw.Console.Compose.PartInfo) rows presets picks (c : String)
    (h : (Fw.Console.Compose.decide parts rows presets picks).link = some c)
    (p : PartFact) (hp : p ∈ parts.map (·.fact)) (hid : p.id = "morph.end.release")
    (hc : p.conflicts.lookup "morph.end.release:on" = some waapiKeys) (b : String) (hb : b ∈ waapiKeys) :
    ∃ c', validate (parts.map (·.fact)) [] c = .ok c' ∧
    ¬ ((((fwEntries (params (body c))).foldl (applyFwEntry (parts.map (·.fact)))
          (stage1 (parts.map (·.fact)) [] (valuesOf "preset" (params (body c))))).sel.lookup "morph.end.release" = some "on") ∧
      (selected ((fwEntries (params (body c))).foldl (applyFwEntry (parts.map (·.fact)))
          (stage1 (parts.map (·.fact)) [] (valuesOf "preset" (params (body c))))).sel).contains b = true) := by
  obtain ⟨c', hv⟩ := Fw.Console.Compose.link_resolves parts rows presets picks c h
  exact ⟨c', hv, accepted_no_release_waapi _ _ c c' hv p hp hid hc b hb⟩

end Fw.Parts.MorphEndReleaseConflict
