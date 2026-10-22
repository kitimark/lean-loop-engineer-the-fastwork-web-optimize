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

def dryKind (w : Stages) (contains : Bool) (m0 b : String) : Kind :=
  if !contains then .stale else
  if !(w.own m0 b) then .empty else
  match landStages w m0 b with
  | some s => s.kind
  | none => if w.lints m0 b then .dry else .lint

theorem firstRefusal_none_iff (s g r : Bool) : firstRefusal s g r = none ↔ (s = true ∧ g = true ∧ r = true) := by
  cases s <;> cases g <;> cases r <;> simp [firstRefusal]

theorem dry_pass_land_pass (w : Stages) (c : Bool) (m0 h b : String) (hd : dryKind w c m0 b = .dry) (hh : h = m0) :
    landStages w h b = none := by
  subst hh
  cases c <;> cases ho : w.own h b <;> cases hl : landStages w h b <;> cases hn : w.lints h b <;>
    simp [dryKind, hl, ho, hn] at hd ⊢
  all_goals (rename_i s; cases s <;> simp [Stage.kind] at hd)

theorem dry_refusal_is_land_refusal (w : Stages) (c : Bool) (m0 h b : String) (s : Stage)
    (hd : dryKind w c m0 b = s.kind) (hh : h = m0) : landStages w h b = some s := by
  subst hh
  cases c
  · cases s <;> simp [dryKind, Stage.kind] at hd
  · cases ho : w.own h b
    · cases s <;> simp [dryKind, ho, Stage.kind] at hd
    · cases hl : landStages w h b with
      | none => cases hn : w.lints h b <;> cases s <;> simp [dryKind, hl, ho, hn, Stage.kind] at hd
      | some s2 =>
        rw [Option.some.injEq]
        cases s <;> cases s2 <;> simp_all [dryKind, Stage.kind]

theorem dry_iff_land_pass (w : Stages) (m0 h b : String) (hh : h = m0) :
    dryKind w true m0 b = .dry ↔ (w.own m0 b = true ∧ landStages w h b = none ∧ w.lints m0 b = true) := by
  subst hh
  cases ho : w.own h b <;> cases hl : landStages w h b <;> cases hn : w.lints h b <;> simp [dryKind, hl, ho, hn]
  all_goals (rename_i s; cases s <;> simp [Stage.kind])

theorem dry_pass_all (w : Stages) (c : Bool) (m0 b : String) (hd : dryKind w c m0 b = .dry) :
    c = true ∧ w.own m0 b = true ∧ w.scope m0 b = true ∧ w.merges m0 b = true ∧ w.reads m0 b = true ∧ w.lints m0 b = true := by
  have hl := dry_pass_land_pass w c m0 m0 b hd rfl
  have hf := (firstRefusal_none_iff _ _ _).mp (by simpa [landStages] using hl)
  cases c <;> cases ho : w.own m0 b <;> cases hn : w.lints m0 b <;> simp [dryKind, ho, hn] at hd ⊢
  all_goals (try cases hl2 : landStages w m0 b <;> simp [hl2] at hd)
  all_goals (try (rename_i s; cases s <;> simp [Stage.kind] at hd))
  all_goals simp_all

theorem stale_iff (w : Stages) (c : Bool) (m0 b : String) : dryKind w c m0 b = .stale ↔ c = false := by
  cases c <;> cases ho : w.own m0 b <;> cases hl : landStages w m0 b <;> cases hn : w.lints m0 b <;> simp [dryKind, hl, ho, hn]
  all_goals (rename_i s; cases s <;> simp [Stage.kind])

def handbackAllowed (k : Kind) : Bool := k == .dry

theorem handback_pass_land_pass (w : Stages) (c : Bool) (m0 h b : String) (ha : handbackAllowed (dryKind w c m0 b) = true)
    (hh : h = m0) : landStages w h b = none := by
  apply dry_pass_land_pass w c m0 h b _ hh
  simpa [handbackAllowed] using ha

theorem moved_no_guarantee :
    ∃ (w : Stages) (m0 h b : String), dryKind w true m0 b = .dry ∧ h ≠ m0 ∧ landStages w h b ≠ none :=
  ⟨⟨fun m _ => m == "a", fun _ _ => true, fun _ _ => false, fun _ _ => true, fun _ _ => true, fun _ _ => true⟩, "a", "b", "t", by decide, by decide, by decide⟩

theorem dryKind_cases (w : Stages) (c : Bool) (m0 b : String) :
    dryKind w c m0 b = .stale ∨ dryKind w c m0 b = .empty ∨ dryKind w c m0 b = .scope ∨ dryKind w c m0 b = .conflict ∨
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

def Outcome.ofStages (w : Stages) (contains : Bool) (m0 b : String) : Outcome :=
  ⟨false, contains, w.own m0 b, w.scope m0 b, w.merges m0 b, w.reads m0 b, w.lints m0 b⟩

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

theorem kind_ofStages (w : Stages) (c : Bool) (m0 b : String) : (Outcome.ofStages w c m0 b).kind = dryKind w c m0 b := by
  cases c <;> cases ho : w.own m0 b <;> cases hs : w.scope m0 b <;> cases hm : w.merges m0 b <;> cases hr : w.reads m0 b <;>
    cases hn : w.lints m0 b <;>
    simp [Outcome.kind, Outcome.first, Outcome.ofStages, dryKind, landStages, firstRefusal, hs, hm, hr, ho, hn, DStage.kind, Stage.kind]


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
    (c : Bool) (m0 h b : String) (hd : dryKind (w.planned ch a v g r) c m0 b = .dry) (hh : h = m0) : landStages w h b = none :=
  dry_pass_land_pass (w.planned ch a v g r) c m0 h b hd hh

theorem dry_refusal_is_land_refusal_planned (w : Stages) (ch : String → String → List String) (a v g : Bool)
    (r : String → String → Lint → Bool) (c : Bool) (m0 h b : String) (s : Stage) (hd : dryKind (w.planned ch a v g r) c m0 b = s.kind)
    (hh : h = m0) : landStages w h b = some s :=
  dry_refusal_is_land_refusal (w.planned ch a v g r) c m0 h b s hd hh

theorem gen_stale_refuses (w : Stages) (ch : String → String → List String) (a v : Bool) (r : String → String → Lint → Bool)
    (c : Bool) (m0 b p : String) (hp : p ∈ ch m0 b) (hi : footprintInput p = true) (hr : r m0 b .footprint = false) :
    dryKind (w.planned ch a v true r) c m0 b ≠ .dry := by
  intro hd
  have hl := (dry_pass_all _ c m0 b hd).2.2.2.2.2
  have := (lintsPass_iff _ _).mp hl .footprint (gen_selected _ a v p hp hi)
  simp_all


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
    dryKind w true m0 b = .empty ∧ Kind.exitCode .empty = 0 := by
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
    ["dryKind_cases"], "apps/runner/test/land-dry.test.ts: main's HEAD and tracked status, the lock file and the queue file are identical before and after"⟩]

#guard premises.length == 2
#guard (premises.map (·.id)).eraseDups.length == premises.length


open Lean

def line (name : String) (req resp : List (String × Json)) : Json :=
  Json.mkObj [("name", .str name), ("request", Json.mkObj req), ("response", Json.mkObj resp)]

def kindCase (k : Kind) (t : String) : Json :=
  line s!"kind {k.name}" [("op", "landVerdict.kind"), ("kind", k.name), ("task", t)]
    [("exit", toJson k.exitCode), ("ok", .bool k.ok), ("retry", .bool k.retryable), ("line", .str (verdictLine k t))]

def dryCase (name : String) (contains scope merges sel test : Bool) (own lints : Bool := true) : Json :=
  let w : Stages := ⟨fun _ _ => scope, fun _ _ => merges, fun _ _ => sel, fun _ _ => test, fun _ _ => own, fun _ _ => lints⟩
  line name [("op", "landDry.verdict"), ("containsMain", .bool contains), ("scope", .bool scope), ("merges", .bool merges),
      ("readsSelected", .bool sel), ("readsTest", .bool test), ("own", .bool own), ("lints", .bool lints)]
    [("kind", .str (dryKind w contains "m" "b").name)]

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
  [kindCase .dry "",
   dryCase "all pass" true true true true true,
   dryCase "all pass, reads not selected (test not run)" true true true false true,
   dryCase "scope refuses first" true false false true false,
   dryCase "conflict refuses before reads" true true false true false,
   dryCase "reads refuses" true true true true false,
   dryCase "reads failing but not selected passes" true true true false false,
   dryCase "stale beats scope" false false true true true,
   dryCase "stale though all stages pass" false true true true true,
   dryCase "scope and reads both fail: scope first" true false true true false,
   dryCase "no own commits: empty" true true true true true (own := false),
   dryCase "no own commits beats a failing scope" true false false true false (own := false),
   dryCase "stale beats empty" false true true true true (own := false),
   dryCase "fast lint fails after all stages pass" true true true true true (lints := false),
   dryCase "reads refuses before lint" true true true true false (lints := false),
   dryCase "lint fails though reads not selected" true true true false false (lints := false)] ++
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

#guard cases.length == 198

def goldenText (_ : Unit := ()) : String := String.join (cases.map fun c => c.compress ++ "\n")

def goldenPath : System.FilePath := "../packages/contracts/golden/console/land-dry.jsonl"

def writeGolden : IO Unit := IO.FS.writeFile goldenPath goldenText

def checkGolden : IO Bool := do return (← IO.FS.readFile goldenPath) == goldenText

end Fw.Console.LandDry
