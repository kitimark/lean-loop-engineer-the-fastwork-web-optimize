import Lean.Data.Json
import Fw.Console.LandVerdict
namespace Fw.Console.LandDry
open Fw.Console.LandVerdict

structure Stages where
  scope : String → String → Bool
  merges : String → String → Bool
  readsSelected : String → String → Bool
  readsTest : String → String → Bool
  own : String → String → Bool
  lints : String → String → Bool

def Stages.reads (w : Stages) (m b : String) : Bool := !(w.readsSelected m b) || w.readsTest m b

inductive Stage where
  | scope | conflict | reads
deriving DecidableEq, Repr

def Stage.kind : Stage → Kind
  | .scope => .scope | .conflict => .conflict | .reads => .reads

def firstRefusal (s g r : Bool) : Option Stage :=
  if !s then some .scope else if !g then some .conflict else if !r then some .reads else none

def landStages (w : Stages) (h b : String) : Option Stage := firstRefusal (w.scope h b) (w.merges h b) (w.reads h b)

inductive Base where
  | contains | clean | conflict
deriving DecidableEq, Repr

def Base.name : Base → String
  | .contains => "contains" | .clean => "clean" | .conflict => "conflict"

def Base.of (behind mergeClean : Bool) : Base :=
  if !behind then .contains else if mergeClean then .clean else .conflict

#guard Base.of false false == .contains
#guard Base.of true true == .clean
#guard Base.of true false == .conflict

theorem of_behind_clean (c : Bool) : Base.of true c = .clean ↔ c = true := by cases c <;> decide

theorem of_conflict_iff (b c : Bool) : Base.of b c = .conflict ↔ (b = true ∧ c = false) := by
  cases b <;> cases c <;> decide

def dryKind (w : Stages) (base : Base) (m0 b : String) : Kind :=
  if !(w.own m0 b) then .empty else
  if base = .conflict then .conflict else
  match landStages w m0 b with
  | some s => s.kind
  | none => if w.lints m0 b then .dry else .lint

theorem firstRefusal_none_iff (s g r : Bool) : firstRefusal s g r = none ↔ (s = true ∧ g = true ∧ r = true) := by
  cases s <;> cases g <;> cases r <;> simp [firstRefusal]

theorem dry_pass_land_pass (w : Stages) (c : Base) (m0 h b : String) (hd : dryKind w c m0 b = .dry) (hh : h = m0) :
    landStages w h b = none := by
  subst hh
  cases c <;> cases ho : w.own h b <;> cases hl : landStages w h b <;> cases hn : w.lints h b <;>
    simp [dryKind, hl, ho, hn] at hd ⊢
  all_goals (rename_i s; cases s <;> simp [Stage.kind] at hd)

theorem dry_refusal_is_land_refusal (w : Stages) (c : Base) (hc : c ≠ .conflict) (m0 h b : String) (s : Stage)
    (hd : dryKind w c m0 b = s.kind) (hh : h = m0) : landStages w h b = some s := by
  subst hh
  cases ho : w.own h b
  · cases s <;> simp [dryKind, ho, Stage.kind] at hd
  · cases hl : landStages w h b with
    | none => cases hn : w.lints h b <;> cases s <;> simp [dryKind, hl, ho, hn, hc, Stage.kind] at hd
    | some s2 =>
      rw [Option.some.injEq]
      cases s <;> cases s2 <;> simp_all [dryKind, Stage.kind]

theorem dry_iff_land_pass (w : Stages) (c : Base) (hc : c ≠ .conflict) (m0 h b : String) (hh : h = m0) :
    dryKind w c m0 b = .dry ↔ (w.own m0 b = true ∧ landStages w h b = none ∧ w.lints m0 b = true) := by
  subst hh
  cases ho : w.own h b <;> cases hl : landStages w h b <;> cases hn : w.lints h b <;> simp [dryKind, hl, ho, hn, hc]
  all_goals (rename_i s; cases s <;> simp [Stage.kind])

theorem dry_pass_all (w : Stages) (c : Base) (m0 b : String) (hd : dryKind w c m0 b = .dry) :
    c ≠ .conflict ∧ w.own m0 b = true ∧ w.scope m0 b = true ∧ w.merges m0 b = true ∧ w.reads m0 b = true ∧
      w.lints m0 b = true := by
  have hl := dry_pass_land_pass w c m0 m0 b hd rfl
  have hf := (firstRefusal_none_iff _ _ _).mp (by simpa [landStages] using hl)
  cases c <;> cases ho : w.own m0 b <;> cases hn : w.lints m0 b <;> simp [dryKind, ho, hn] at hd ⊢
  all_goals (try cases hl2 : landStages w m0 b <;> simp [hl2] at hd)
  all_goals (try (rename_i s; cases s <;> simp [Stage.kind] at hd))
  all_goals simp_all

theorem never_stale (w : Stages) (c : Base) (m0 b : String) : dryKind w c m0 b ≠ .stale := by
  cases c <;> cases ho : w.own m0 b <;> cases hl : landStages w m0 b <;> cases hn : w.lints m0 b <;> simp [dryKind, hl, ho, hn]
  all_goals (rename_i s; cases s <;> simp [Stage.kind])

theorem clean_never_stale (w : Stages) (m0 b : String) : dryKind w .clean m0 b ≠ .stale := never_stale w .clean m0 b

theorem conflict_refuses (w : Stages) (m0 b : String) (ho : w.own m0 b = true) : dryKind w .conflict m0 b = .conflict := by
  simp [dryKind, ho]

theorem conflict_not_dry (w : Stages) (m0 b : String) : dryKind w .conflict m0 b ≠ .dry := by
  cases ho : w.own m0 b <;> simp [dryKind, ho]

theorem conflict_land_refuses (w : Stages) (h b : String) (hm : w.merges h b = false) : landStages w h b ≠ none := by
  cases hs : w.scope h b <;> simp [landStages, firstRefusal, hs, hm]

theorem clean_is_contains (w : Stages) (m0 b : String) : dryKind w .clean m0 b = dryKind w .contains m0 b := by
  simp [dryKind]

def handbackAllowed (k : Kind) : Bool := k == .dry

theorem handback_pass_land_pass (w : Stages) (c : Base) (m0 h b : String) (ha : handbackAllowed (dryKind w c m0 b) = true)
    (hh : h = m0) : landStages w h b = none := by
  apply dry_pass_land_pass w c m0 h b _ hh
  simpa [handbackAllowed] using ha

theorem moved_no_guarantee :
    ∃ (w : Stages) (m0 h b : String), dryKind w .contains m0 b = .dry ∧ h ≠ m0 ∧ landStages w h b ≠ none :=
  ⟨⟨fun m _ => m == "a", fun _ _ => true, fun _ _ => false, fun _ _ => true, fun _ _ => true, fun _ _ => true⟩, "a", "b", "t", by decide, by decide, by decide⟩

theorem dryKind_cases (w : Stages) (c : Base) (m0 b : String) :
    dryKind w c m0 b = .empty ∨ dryKind w c m0 b = .scope ∨ dryKind w c m0 b = .conflict ∨
      dryKind w c m0 b = .reads ∨ dryKind w c m0 b = .lint ∨ dryKind w c m0 b = .dry := by
  cases c <;> cases ho : w.own m0 b <;> cases hl : landStages w m0 b <;> cases hn : w.lints m0 b <;> simp [dryKind, hl, ho, hn]
  all_goals (rename_i s; cases s <;> simp [Stage.kind])


inductive DStage where
  | exception | stale | empty | scope | conflict | reads | lint
deriving DecidableEq, Repr

def DStage.rank : DStage → Nat
  | .exception => 0 | .stale => 1 | .empty => 2 | .scope => 3 | .conflict => 4 | .reads => 5 | .lint => 6

def DStage.name : DStage → String
  | .exception => "exception" | .stale => "stale" | .empty => "empty" | .scope => "scope" | .conflict => "conflict"
  | .reads => "reads" | .lint => "lint"

def DStage.kind : DStage → Kind
  | .exception => .unknown | .stale => .stale | .empty => .empty | .scope => .scope | .conflict => .conflict
  | .reads => .reads | .lint => .lint

structure Outcome where
  threw : Bool
  fresh : Bool
  own : Bool
  scope : Bool
  merges : Bool
  reads : Bool
  lints : Bool

def Outcome.passes (o : Outcome) : DStage → Bool
  | .exception => !o.threw | .stale => o.fresh | .empty => o.own | .scope => o.scope | .conflict => o.merges
  | .reads => o.reads | .lint => o.lints

def DStage.order : List DStage := [.exception, .stale, .empty, .scope, .conflict, .reads, .lint]

def Outcome.first (o : Outcome) : Option DStage :=
  if o.threw then some .exception else if !o.fresh then some .stale else if !o.own then some .empty
  else if !o.scope then some .scope else if !o.merges then some .conflict else if !o.reads then some .reads
  else if !o.lints then some .lint else none

def Outcome.kind (o : Outcome) : Kind := match o.first with | some s => s.kind | none => .dry

def Outcome.log (o : Outcome) : List String := (DStage.order.takeWhile o.passes).map fun s => "dry: " ++ s.name ++ " ok"

def dryRun (o : Outcome) (task : String) : List String := o.log ++ [verdictLine o.kind task]

def Outcome.ofStages (w : Stages) (base : Base) (m0 b : String) : Outcome :=
  if base = .conflict then ⟨false, true, w.own m0 b, true, false, true, true⟩
  else ⟨false, true, w.own m0 b, w.scope m0 b, w.merges m0 b, w.reads m0 b, w.lints m0 b⟩

theorem first_spec (o : Outcome) :
    (∀ s, o.first = some s → o.passes s = false ∧ ∀ s', s'.rank < s.rank → o.passes s' = true) ∧
    (o.first = none ↔ ∀ s, o.passes s = true) := by
  obtain ⟨a, b, c, d, e, f, g⟩ := o
  refine ⟨?_, ?_⟩
  · intro s h
    cases a <;> cases b <;> cases c <;> cases d <;> cases e <;> cases f <;> cases g <;> cases s <;>
      simp_all [Outcome.first, Outcome.passes] <;> intro s' <;> cases s' <;> simp_all [DStage.rank]
  · constructor
    · intro h s
      cases a <;> cases b <;> cases c <;> cases d <;> cases e <;> cases f <;> cases g <;> cases s <;>
        simp_all [Outcome.first, Outcome.passes]
    · intro h
      have h0 := h .exception; have h1 := h .stale; have h2 := h .empty; have h3 := h .scope
      have h4 := h .conflict; have h5 := h .reads; have h6 := h .lint
      simp_all [Outcome.passes, Outcome.first]

theorem dryRun_one_verdict (o : Outcome) (t : String) :
    ((dryRun o t).filter (·.startsWith "VERDICT ")).length = 1 ∧ (dryRun o t).getLast? = some (verdictLine o.kind t) := by
  have hlog : o.log.filter (·.startsWith "VERDICT ") = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro l hl
    simp only [Outcome.log, List.mem_map] at hl
    obtain ⟨s, _, rfl⟩ := hl
    cases s <;> decide +kernel
  refine ⟨?_, by simp [dryRun]⟩
  simp [dryRun, List.filter_append, hlog, verdictLine]

theorem kind_spec (o : Outcome) (k : Kind) :
    o.kind = k ↔ (k = .dry ∧ ∀ s, o.passes s = true) ∨
      ∃ s, k = s.kind ∧ o.passes s = false ∧ ∀ s', s'.rank < s.rank → o.passes s' = true := by
  have ⟨h1, h2⟩ := first_spec o
  constructor
  · intro h
    cases hf : o.first with
    | none => left; exact ⟨by simpa [Outcome.kind, hf] using h.symm, h2.mp hf⟩
    | some s => right; exact ⟨s, by simpa [Outcome.kind, hf] using h.symm, h1 s hf⟩
  · rintro (⟨rfl, h⟩ | ⟨s, rfl, hs, hb⟩)
    · simp [Outcome.kind, h2.mpr h]
    · cases hf : o.first with
      | none => have := h2.mp hf s; simp_all
      | some s2 =>
        have ⟨a1, a2⟩ := h1 s2 hf
        have : s = s2 := by
          refine Classical.byContradiction fun hne => ?_
          have hr : s.rank ≠ s2.rank := fun h => hne (by cases s <;> cases s2 <;> simp_all [DStage.rank])
          rcases Nat.lt_or_gt_of_ne hr with hl | hl
          · have := a2 s hl; simp_all
          · have := hb s2 hl; simp_all
        subst this; simp [Outcome.kind, hf]

theorem kind_ofStages (w : Stages) (c : Base) (m0 b : String) : (Outcome.ofStages w c m0 b).kind = dryKind w c m0 b := by
  cases c <;> cases ho : w.own m0 b <;> cases hs : w.scope m0 b <;> cases hm : w.merges m0 b <;> cases hr : w.reads m0 b <;>
    cases hn : w.lints m0 b <;>
    simp [Outcome.kind, Outcome.first, Outcome.ofStages, dryKind, landStages, firstRefusal, hs, hm, hr, ho, hn, DStage.kind, Stage.kind]



abbrev Tree := String → Option String

abbrev ContentMerge := Option String → Option String → Option String → Option (Option String)

def mergeVal (cm : ContentMerge) (a m t : Option String) : Option (Option String) :=
  if m = t then some m else if m = a then some t else if t = a then some m else cm a m t

def mergePath (cm : ContentMerge) (base main br : Tree) (p : String) : Option (Option String) :=
  mergeVal cm (base p) (main p) (br p)

theorem mergeVal_own (cm : ContentMerge) (a m t r : Option String) (h : mergeVal cm a m t = some r) (hd : r ≠ m) :
    t ≠ a := by
  rintro rfl
  by_cases h1 : m = t
  · subst h1; simp [mergeVal] at h; exact hd h.symm
  · simp [mergeVal, h1] at h; exact hd h.symm

theorem mergeVal_kept (cm : ContentMerge) (a m : Option String) : mergeVal cm a m a = some m := by
  by_cases h1 : m = a <;> simp [mergeVal, h1]

theorem mergeVal_main_same (cm : ContentMerge) (a t : Option String) : mergeVal cm a a t = some t := by
  by_cases h1 : a = t <;> simp [mergeVal, h1]

def mergedDiff (cm : ContentMerge) (base main br : Tree) (paths : List String) : Option (List String) :=
  if paths.all fun p => (mergePath cm base main br p).isSome then
    some (paths.filter fun p => mergePath cm base main br p != some (main p))
  else none

def ownPaths (base br : Tree) (paths : List String) : List String := paths.filter fun p => br p != base p

theorem merged_diff_own (cm : ContentMerge) (base main br : Tree) (p : String) (r : Option String)
    (h : mergePath cm base main br p = some r) (hd : r ≠ main p) : br p ≠ base p :=
  mergeVal_own cm _ _ _ r h hd

theorem main_alone_kept (cm : ContentMerge) (base main br : Tree) (p : String) (hb : br p = base p) :
    mergePath cm base main br p = some (main p) := by
  simp only [mergePath, hb, mergeVal_kept]

theorem one_side_diff_iff (cm : ContentMerge) (base main br : Tree) (p : String)
    (hs : main p = base p ∨ br p = base p) :
    mergePath cm base main br p ≠ some (main p) ↔ (br p ≠ base p ∧ br p ≠ main p) := by
  rcases hs with hm | hb
  · simp only [mergePath, hm, mergeVal_main_same, ne_eq, Option.some.injEq, and_self]
  · rw [main_alone_kept cm base main br p hb]; simp [hb]

theorem mergedDiff_sub_own (cm : ContentMerge) (base main br : Tree) (P D : List String)
    (h : mergedDiff cm base main br P = some D) : ∀ p ∈ D, p ∈ ownPaths base br P := by
  intro p hp
  unfold mergedDiff at h
  split at h
  · rename_i hall
    simp only [Option.some.injEq] at h; subst h
    have ⟨hpP, hne⟩ := List.mem_filter.mp hp
    have hs := List.all_eq_true.mp hall p hpP
    obtain ⟨r, hr⟩ := Option.isSome_iff_exists.mp hs
    have hrm : r ≠ main p := by intro e; simp [hr, e] at hne
    exact List.mem_filter.mpr ⟨hpP, by simpa using merged_diff_own cm base main br p r hr hrm⟩
  · cases h

theorem main_only_not_in_diff (cm : ContentMerge) (base main br : Tree) (P D : List String)
    (h : mergedDiff cm base main br P = some D) (p : String) (hb : br p = base p) : p ∉ D := by
  intro hp
  have := List.mem_filter.mp (mergedDiff_sub_own cm base main br P D h p hp)
  simp [hb] at this

theorem mergedDiff_eq_own (cm : ContentMerge) (base main br : Tree) (P : List String)
    (hs : ∀ p ∈ P, main p = base p ∨ br p = base p) : mergedDiff cm base main br P = some (ownPaths base br P) := by
  have hall : P.all (fun p => (mergePath cm base main br p).isSome) = true := by
    refine List.all_eq_true.mpr fun p hp => ?_
    rcases hs p hp with hm | hb
    · simp [mergePath, hm, mergeVal_main_same]
    · simp [main_alone_kept cm base main br p hb]
  simp only [mergedDiff, hall, ite_true, ownPaths, Option.some.injEq]
  refine List.filter_congr fun p hp => ?_
  rcases hs p hp with hm | hb
  · simp only [mergePath, hm, mergeVal_main_same]
    by_cases h : br p = base p
    · simp [h]
    · rw [bne_iff_ne.mpr (fun e => h (Option.some.inj e)), bne_iff_ne.mpr h]
  · simp [main_alone_kept cm base main br p hb, hb]

theorem contains_diff_is_own (cm : ContentMerge) (main br : Tree) (P : List String) :
    mergedDiff cm main main br P = some (ownPaths main br P) :=
  mergedDiff_eq_own cm main main br P fun _ _ => .inl rfl

theorem conflict_iff (cm : ContentMerge) (base main br : Tree) (P : List String) :
    mergedDiff cm base main br P = none ↔ ∃ p ∈ P, mergePath cm base main br p = none := by
  unfold mergedDiff
  split
  · rename_i hall
    simp only [reduceCtorEq, false_iff, not_exists, not_and]
    intro p hp hn
    have := List.all_eq_true.mp hall p hp
    simp [hn] at this
  · rename_i hall
    simp only [true_iff]
    simpa using hall

def noContentMerge : ContentMerge := fun _ _ _ => none

def treeOf (l : List (String × String)) : Tree := fun p => l.lookup p

def mergeBase (behind : Bool) (r : Option (List String)) : Base := Base.of behind r.isSome

theorem mergeBase_clean_diff (cm : ContentMerge) (base main br : Tree) (P : List String)
    (h : mergeBase true (mergedDiff cm base main br P) = .clean) :
    ∃ D, mergedDiff cm base main br P = some D ∧ ∀ p ∈ D, p ∈ ownPaths base br P := by
  cases hm : mergedDiff cm base main br P with
  | none => simp [hm, mergeBase, Base.of] at h
  | some D => exact ⟨D, rfl, mergedDiff_sub_own cm base main br P D hm⟩

theorem mergeBase_conflict (cm : ContentMerge) (base main br : Tree) (P : List String) :
    mergeBase true (mergedDiff cm base main br P) = .conflict ↔ ∃ p ∈ P, mergePath cm base main br p = none := by
  rw [← conflict_iff]; cases mergedDiff cm base main br P <;> simp [mergeBase, Base.of]

inductive Lint where
  | ciPaths | footprint | axioms
deriving DecidableEq, Repr

def Lint.argv : Lint → List String
  | .ciPaths => ["node", "scripts/ci-paths.mjs", "--check"]
  | .footprint => ["node", "apps/site/scripts/part-footprint.mjs", "--check"]
  | .axioms => ["sh", "-c", "cd lean && . ../scripts/lake-slot-lib.sh && (lake_slot .. lake build) >&2 && sh scripts/axiom-check.sh"]

def footprintInput (p : String) : Bool :=
  p.startsWith "apps/site/src/parts/" || p == "apps/site/src/App.tsx" || p == "apps/site/scripts/part-footprint.mjs" ||
    p == "lean/Fw/Parts/FootprintData.lean" || p == "packages/contracts/golden/parts/footprint.gen.json"

def basePlan (changed : List String) (hasCiPaths hasAxioms : Bool) : List Lint :=
  (if hasCiPaths then [Lint.ciPaths] else []) ++
  (if hasAxioms && changed.any (·.startsWith "lean/") then [Lint.axioms] else [])

def lintPlan (changed : List String) (hasCiPaths hasAxioms hasFootprint : Bool) : List Lint :=
  (if hasCiPaths then [Lint.ciPaths] else []) ++
  (if hasFootprint && changed.any footprintInput then [Lint.footprint] else []) ++
  (if hasAxioms && changed.any (·.startsWith "lean/") then [Lint.axioms] else [])

#guard lintPlan ["apps/site/src/parts/nav/index.tsx"] true true true == [.ciPaths, .footprint]
#guard lintPlan ["lean/Fw/Parts/FootprintData.lean"] true true true == [.ciPaths, .footprint, .axioms]
#guard lintPlan ["apps/site/src/partsx/a.ts"] true true true == [.ciPaths]
#guard lintPlan ["apps/site/src/App.tsx"] true true false == [.ciPaths]

theorem ciPaths_mem_plan (P : List String) (a v g : Bool) : Lint.ciPaths ∈ lintPlan P a v g ↔ a = true := by
  cases a <;> cases v <;> cases g <;> simp [lintPlan]

theorem axioms_mem_plan (P : List String) (a v g : Bool) :
    Lint.axioms ∈ lintPlan P a v g ↔ (v = true ∧ ∃ p ∈ P, p.startsWith "lean/" = true) := by
  cases a <;> cases v <;> cases g <;> simp [lintPlan]

theorem no_axioms_without_lean (P : List String) (a v g : Bool) (h : ∀ p ∈ P, p.startsWith "lean/" = false) :
    Lint.axioms ∉ lintPlan P a v g := by
  rw [axioms_mem_plan]
  rintro ⟨_, p, hp, hs⟩
  have := h p hp; simp_all

theorem footprint_mem_plan (P : List String) (a v g : Bool) :
    Lint.footprint ∈ lintPlan P a v g ↔ (g = true ∧ ∃ p ∈ P, footprintInput p = true) := by
  cases a <;> cases v <;> cases g <;> simp [lintPlan]

theorem gen_selected (P : List String) (a v : Bool) (p : String) (hp : p ∈ P) (hi : footprintInput p = true) :
    Lint.footprint ∈ lintPlan P a v true :=
  (footprint_mem_plan P a v true).mpr ⟨rfl, p, hp, hi⟩

theorem lintPlan_old (P : List String) (a v g : Bool) (h : ∀ p ∈ P, footprintInput p = false) :
    lintPlan P a v g = basePlan P a v := by
  have : P.any footprintInput = false := by simpa using h
  simp [lintPlan, basePlan, this]

theorem lintPlan_noScript (P : List String) (a v : Bool) : lintPlan P a v false = basePlan P a v := by
  simp [lintPlan, basePlan]

def lintsPass (plan : List Lint) (r : Lint → Bool) : Bool := plan.all r

theorem lintsPass_iff (plan : List Lint) (r : Lint → Bool) : lintsPass plan r = true ↔ ∀ l ∈ plan, r l = true := by
  simp [lintsPass]

def Stages.planned (w : Stages) (changed : String → String → List String) (a v g : Bool) (r : String → String → Lint → Bool) :
    Stages :=
  { w with lints := fun m b => lintsPass (lintPlan (changed m b) a v g) (r m b) }

theorem dry_pass_land_pass_planned (w : Stages) (ch : String → String → List String) (a v g : Bool) (r : String → String → Lint → Bool)
    (c : Base) (m0 h b : String) (hd : dryKind (w.planned ch a v g r) c m0 b = .dry) (hh : h = m0) : landStages w h b = none :=
  dry_pass_land_pass (w.planned ch a v g r) c m0 h b hd hh

theorem dry_refusal_is_land_refusal_planned (w : Stages) (ch : String → String → List String) (a v g : Bool)
    (r : String → String → Lint → Bool) (c : Base) (hc : c ≠ .conflict) (m0 h b : String) (s : Stage)
    (hd : dryKind (w.planned ch a v g r) c m0 b = s.kind) (hh : h = m0) : landStages w h b = some s :=
  dry_refusal_is_land_refusal (w.planned ch a v g r) c hc m0 h b s hd hh

theorem gen_stale_refuses (w : Stages) (ch : String → String → List String) (a v : Bool) (r : String → String → Lint → Bool)
    (c : Base) (m0 b p : String) (hp : p ∈ ch m0 b) (hi : footprintInput p = true) (hr : r m0 b .footprint = false) :
    dryKind (w.planned ch a v true r) c m0 b ≠ .dry := by
  intro hd
  have hl := (dry_pass_all _ c m0 b hd).2.2.2.2.2
  have := (lintsPass_iff _ _).mp hl .footprint (gen_selected _ a v p hp hi)
  simp_all


def runsLakeBuild (plan : List Lint) (fwcoreBuild : Bool) : Bool := plan.contains .axioms || fwcoreBuild

def dryTotalStep (plan : List Lint) (fwcoreBuild : Bool) : String :=
  if runsLakeBuild plan fwcoreBuild then "dry total lake" else "dry total"

theorem runsLakeBuild_iff (plan : List Lint) (b : Bool) : runsLakeBuild plan b = true ↔ Lint.axioms ∈ plan ∨ b = true := by
  simp [runsLakeBuild]

theorem lean_change_keyed_lake (P : List String) (a g : Bool) (b : Bool) (p : String) (hp : p ∈ P)
    (hl : p.startsWith "lean/" = true) : dryTotalStep (lintPlan P a true g) b = "dry total lake" := by
  have h := (axioms_mem_plan P a true g).2 ⟨rfl, p, hp, hl⟩
  simp [dryTotalStep, runsLakeBuild, h]

theorem no_lean_plain_key (P : List String) (a v g : Bool) (h : ∀ p ∈ P, p.startsWith "lean/" = false) :
    dryTotalStep (lintPlan P a v g) false = "dry total" := by
  have := no_axioms_without_lean P a v g h
  simp [dryTotalStep, runsLakeBuild, this]

theorem fwcore_build_keyed_lake (plan : List Lint) : dryTotalStep plan true = "dry total lake" := by
  simp [dryTotalStep, runsLakeBuild]

theorem dryTotalStep_ne (plan : List Lint) (b b' : Bool) (h : runsLakeBuild plan b = true) (h' : runsLakeBuild plan b' = false) :
    dryTotalStep plan b ≠ dryTotalStep plan b' := by
  simp [dryTotalStep, h, h']

def lintStages : List String := ["lake build", "axiom check"]

abbrev FailedCheck := Bool × List String

def checkFailKind (fs : List FailedCheck) : Kind :=
  if fs.any (·.1) then .reads
  else if !fs.isEmpty && fs.all (fun f => !f.2.isEmpty && f.2.all (· ∈ lintStages)) then .lint else .checks

inductive RealFailure where
  | scope | conflict | checks (fs : List FailedCheck)

def RealFailure.kind : RealFailure → Kind
  | .scope => .scope | .conflict => .conflict | .checks fs => checkFailKind fs

def DStage.real : DStage → Option RealFailure
  | .scope => some .scope | .conflict => some .conflict | .reads => some (.checks [(true, [])])
  | .lint => some (.checks [(false, lintStages)]) | _ => none

theorem dry_kind_is_real_kind (s : DStage) (r : RealFailure) (h : s.real = some r) : r.kind = s.kind := by
  cases s <;> simp [DStage.real] at h <;> subst h <;> decide

theorem lint_stages_are_lint (S : List String) (hne : S ≠ []) (h : ∀ n ∈ S, n ∈ lintStages) :
    checkFailKind [(false, S)] = .lint := by
  have : S.isEmpty = false := by cases S <;> simp_all
  simp [checkFailKind, this]; exact h

theorem other_check_is_checks : checkFailKind [(false, [])] = .checks := by decide

theorem empty_ok (w : Stages) (m0 b : String) (h : w.own m0 b = false) :
    dryKind w .contains m0 b = .empty ∧ Kind.exitCode .empty = 0 := by
  simp [dryKind, h, Kind.exitCode]

structure PremiseRow where
  id : String
  statement : String
  theorems : List String
  test : String

def premises : List PremiseRow := [
  ⟨"land.dryStagesAreLandStages", "the dry land's scope, merge and reads stages are the real land's, on the same commit tree",
    ["dry_pass_land_pass", "dry_refusal_is_land_refusal", "dry_iff_land_pass", "handback_pass_land_pass"],
    "apps/runner/test/land-dry.test.ts: for each of scope, conflict, reads and a pass, a fixture repo gives the dry kind and then the real land the same stage"⟩,
  ⟨"land.dryTakesNoLock", "a dry land creates no lock file, no queue entry and leaves main's HEAD and working tree unchanged",
    ["dryKind_cases"], "apps/runner/test/land-dry.test.ts: main's HEAD and tracked status, the lock file and the queue file are identical before and after"⟩,
  ⟨"land.mergeTreeIsMergePath", "git merge-tree --write-tree merges one-line files path by path as mergePath with noContentMerge, and git diff --name-only main tree lists the paths whose merged blob differs from main",
    ["merged_diff_own", "main_only_not_in_diff", "mergedDiff_eq_own", "mergeBase_conflict"],
    "apps/runner/test/land-dry.test.ts: every landDry.mergeTree row of land-dry-merge.jsonl is built as a fixture repo and merged by dryMerge"⟩]

#guard premises.length == 3
#guard (premises.map (·.id)).eraseDups.length == premises.length


open Lean

def line (name : String) (req resp : List (String × Json)) : Json :=
  Json.mkObj [("name", .str name), ("request", Json.mkObj req), ("response", Json.mkObj resp)]

def kindCase (k : Kind) (t : String) : Json :=
  line s!"kind {k.name}" [("op", "landVerdict.kind"), ("kind", k.name), ("task", t)]
    [("exit", toJson k.exitCode), ("ok", .bool k.ok), ("retry", .bool k.retryable), ("line", .str (verdictLine k t))]

def installCase (offlineOk onlineOk : Bool) : Json :=
  line s!"install {offlineOk} {onlineOk}" [("op", "landVerdict.install"), ("offlineOk", .bool offlineOk), ("onlineOk", .bool onlineOk)]
    [("runsOnline", .bool (installRunsOnline offlineOk)), ("kind", match installKind offlineOk onlineOk with | some k => .str k.name | none => .null)]

def flatStages (scope merges sel test own lints : Bool) : Stages :=
  ⟨fun _ _ => scope, fun _ _ => merges, fun _ _ => sel, fun _ _ => test, fun _ _ => own, fun _ _ => lints⟩

def dryCase (name : String) (scope merges sel test : Bool) (own lints : Bool := true) : Json :=
  line name [("op", "landDry.verdict"), ("containsMain", .bool true), ("scope", .bool scope), ("merges", .bool merges),
      ("readsSelected", .bool sel), ("readsTest", .bool test), ("own", .bool own), ("lints", .bool lints)]
    [("kind", .str (dryKind (flatStages scope merges sel test own lints) .contains "m" "b").name)]

def handbackCase (k : Kind) : Json :=
  line s!"handback {k.name}" [("op", "landDry.handback"), ("kind", k.name)] [("allowed", .bool (handbackAllowed k))]

def runCase (o : Outcome) (t : String) : Json :=
  line s!"run {o.threw} {o.fresh} {o.own} {o.scope} {o.merges} {o.reads} {o.lints}"
    [("op", "landDry.run"), ("threw", .bool o.threw), ("fresh", .bool o.fresh), ("own", .bool o.own), ("scope", .bool o.scope),
      ("merges", .bool o.merges), ("reads", .bool o.reads), ("lints", .bool o.lints), ("task", t)]
    [("lines", toJson (dryRun o t)), ("kind", .str o.kind.name), ("exit", toJson o.kind.exitCode)]

def outcomes : List Outcome :=
  let bs := [true, false]
  bs.flatMap fun a => bs.flatMap fun b => bs.flatMap fun c => bs.flatMap fun d => bs.flatMap fun e => bs.flatMap fun f =>
    bs.map fun g => ⟨a, b, c, d, e, f, g⟩

def planCase (name : String) (changed : List String) (a v : Bool) (g : Bool := true) : Json :=
  line name [("op", "landDry.lintPlan"), ("changed", toJson changed), ("hasCiPaths", .bool a), ("hasAxioms", .bool v),
      ("hasFootprint", .bool g)]
    [("argv", toJson ((lintPlan changed a v g).map Lint.argv))]

def ckCase (name : String) (fs : List FailedCheck) : Json :=
  line name [("op", "landDry.checkKind"), ("failed", toJson (fs.map fun f => Json.mkObj [("reads", .bool f.1), ("stages", toJson f.2)]))]
    [("kind", .str (checkFailKind fs).name)]

def cases (_ : Unit := ()) : List Json :=
  Kind.all.map (kindCase · "land-dry") ++
  [kindCase .dry "", installCase true true, installCase true false, installCase false true, installCase false false,
   dryCase "all pass" true true true true,
   dryCase "all pass, reads not selected (test not run)" true true false true,
   dryCase "scope refuses first" false false true false,
   dryCase "conflict refuses before reads" true false true false,
   dryCase "reads refuses" true true true false,
   dryCase "reads failing but not selected passes" true true false false,
   dryCase "scope and reads both fail: scope first" false true true false,
   dryCase "no own commits: empty" true true true true (own := false),
   dryCase "no own commits beats a failing scope" false false true false (own := false),
   dryCase "fast lint fails after all stages pass" true true true true (lints := false),
   dryCase "reads refuses before lint" true true true false (lints := false),
   dryCase "lint fails though reads not selected" true true false false (lints := false)] ++
  Kind.all.map handbackCase ++ outcomes.map (runCase · "land-dry") ++ [runCase ⟨false, true, true, true, true, true, true⟩ ""] ++
  [planCase "plan: no lean change" ["apps/x.ts"] true true, planCase "plan: lean change" ["apps/x.ts", "lean/Fw/X.lean"] true true,
   planCase "plan: lean change, no axiom-check script" ["lean/Fw/X.lean"] true false, planCase "plan: no ci-paths script" ["lean/Fw/X.lean"] false true,
   planCase "plan: nothing changed" [] true true, planCase "plan: lean-like prefix is not lean" ["leanx/a", "apps/lean/b"] true true,
   planCase "plan: no scripts" ["lean/a"] false false (g := false),
   planCase "plan: part source selects the footprint check" ["apps/site/src/parts/nav/index.tsx"] true true,
   planCase "plan: App.tsx selects the footprint check" ["apps/site/src/App.tsx"] true true,
   planCase "plan: the generator script selects the footprint check" ["apps/site/scripts/part-footprint.mjs"] true true,
   planCase "plan: the footprint golden selects the footprint check" ["packages/contracts/golden/parts/footprint.gen.json"] true true,
   planCase "plan: FootprintData.lean selects the footprint and axiom checks" ["lean/Fw/Parts/FootprintData.lean"] true true,
   planCase "plan: part source, no footprint script" ["apps/site/src/parts/nav/index.tsx"] true true (g := false),
   planCase "plan: site change outside the parts is the old plan" ["apps/site/src/main.tsx", "apps/site/scripts/other.mjs"] true true,
   planCase "plan: parts-like prefix is not a part" ["apps/site/src/partsx/a.ts", "x/apps/site/src/parts/a.ts"] true true,
   planCase "plan: part source and lean change, no ci-paths script" ["apps/site/src/parts/a/b.css", "lean/Fw/X.lean"] false true] ++
  [ckCase "real: reads wins" [(true, ["axiom check"]), (false, [])], ckCase "real: axiom check only" [(false, ["axiom check"])],
   ckCase "real: lake build only" [(false, ["lake build"])], ckCase "real: both lint stages" [(false, ["lake build", "axiom check"])],
   ckCase "real: lint and test" [(false, ["axiom check", "lake test"])], ckCase "real: no stage reported" [(false, [])],
   ckCase "real: lint check and a plain check" [(false, ["axiom check"]), (false, [])], ckCase "real: two lint checks" [(false, ["lake build"]), (false, ["axiom check"])],
   ckCase "real: no failed check" []]

#guard cases.length == 201

def baseCase (behind clean : Bool) : Json :=
  line s!"base behind={behind} clean={clean}" [("op", "landDry.base"), ("behind", .bool behind), ("mergeClean", .bool clean)]
    [("base", .str (Base.of behind clean).name)]

def outcomeJson (o : Outcome) : Json :=
  Json.mkObj [("threw", .bool o.threw), ("fresh", .bool o.fresh), ("own", .bool o.own), ("scope", .bool o.scope),
    ("merges", .bool o.merges), ("reads", .bool o.reads), ("lints", .bool o.lints)]

def baseKindCase (name : String) (base : Base) (scope merges sel test : Bool) (own lints : Bool := true) : Json :=
  let w := flatStages scope merges sel test own lints
  line name [("op", "landDry.baseKind"), ("base", .str base.name), ("scope", .bool scope), ("merges", .bool merges),
      ("readsSelected", .bool sel), ("readsTest", .bool test), ("own", .bool own), ("lints", .bool lints)]
    [("kind", .str (dryKind w base "m" "b").name), ("outcome", outcomeJson (Outcome.ofStages w base "m" "b"))]

abbrev Files := List (String × String)

def treePaths (b m t : Files) : List String :=
  ((b ++ m ++ t).map Prod.fst).eraseDups.mergeSort (fun x y => decide (x ≤ y))

def treeJson (f : Files) : Json := Json.mkObj (f.map fun (p, v) => (p, .str v))

def mergeCase (name : String) (b m t : Files) : Json :=
  let P := treePaths b m t
  let r := mergedDiff noContentMerge (treeOf b) (treeOf m) (treeOf t) P
  line name [("op", "landDry.mergeTree"), ("base", treeJson b), ("main", treeJson m), ("branch", treeJson t)]
    [("clean", .bool r.isSome), ("changed", toJson (r.getD [])), ("own", toJson (ownPaths (treeOf b) (treeOf t) P)),
      ("dryBase", .str (mergeBase true r).name)]

def mergeCases (_ : Unit := ()) : List Json :=
  [baseCase false true, baseCase false false, baseCase true true, baseCase true false] ++
  [.contains, .clean, .conflict].flatMap (fun base => [
    baseKindCase s!"{base.name}: all pass" base true true true true,
    baseKindCase s!"{base.name}: scope refuses" base false true true true,
    baseKindCase s!"{base.name}: merge stage refuses" base true false true true,
    baseKindCase s!"{base.name}: reads refuses" base true true true false,
    baseKindCase s!"{base.name}: lint refuses" base true true true true (lints := false),
    baseKindCase s!"{base.name}: no own commits" base false false true false (own := false)]) ++
  [mergeCase "main changed one file, the branch another" [("a", "1"), ("b", "1")] [("a", "2"), ("b", "1")] [("a", "1"), ("b", "2")],
   mergeCase "main added a file" [("a", "1")] [("a", "1"), ("n", "1")] [("a", "2")],
   mergeCase "main deleted a file the branch kept" [("a", "1"), ("d", "1")] [("a", "1")] [("a", "2"), ("d", "1")],
   mergeCase "both made the same change" [("a", "1"), ("b", "1")] [("a", "2"), ("b", "1")] [("a", "2"), ("b", "2")],
   mergeCase "the branch deleted a file main did not touch" [("a", "1"), ("b", "1")] [("a", "2"), ("b", "1")] [("a", "1")],
   mergeCase "the branch contains main" [("a", "1")] [("a", "1")] [("a", "2"), ("c", "1")],
   mergeCase "no change of the branch's own" [("a", "1")] [("a", "2")] [("a", "1")],
   mergeCase "both changed one file differently: conflict" [("a", "1"), ("b", "1")] [("a", "2"), ("b", "1")] [("a", "3"), ("b", "2")],
   mergeCase "main deleted what the branch changed: conflict" [("a", "1"), ("b", "1")] [("b", "1")] [("a", "2"), ("b", "1")],
   mergeCase "both added one path differently: conflict" [("a", "1")] [("a", "1"), ("n", "1")] [("a", "1"), ("n", "2")]]

#guard (mergeCases).length == 32
#guard mergedDiff noContentMerge (treeOf [("a", "1"), ("b", "1")]) (treeOf [("a", "2"), ("b", "1")])
  (treeOf [("a", "1"), ("b", "2")]) ["a", "b"] == some ["b"]
#guard mergedDiff noContentMerge (treeOf [("a", "1")]) (treeOf [("a", "2")]) (treeOf [("a", "3")]) ["a"] == none
#guard mergeBase true none == .conflict
#guard mergeBase false none == .contains

def goldenText (_ : Unit := ()) : String := String.join (cases.map fun c => c.compress ++ "\n")

def mergeGoldenText (_ : Unit := ()) : String := String.join (mergeCases.map fun c => c.compress ++ "\n")

def goldenPath : System.FilePath := "../packages/contracts/golden/console/land-dry.jsonl"

def mergeGoldenPath : System.FilePath := "../packages/contracts/golden/console/land-dry-merge.jsonl"

def writeGolden : IO Unit := do
  IO.FS.writeFile goldenPath goldenText
  IO.FS.writeFile mergeGoldenPath mergeGoldenText

def checkGolden : IO Bool := do
  return (← IO.FS.readFile goldenPath) == goldenText && (← IO.FS.readFile mergeGoldenPath) == mergeGoldenText

end Fw.Console.LandDry
