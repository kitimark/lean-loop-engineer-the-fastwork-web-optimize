import Fw.Ops.LeanFirstDecision

/-!
# Proofs of the lean-first gate properties

Task `lfg-spec`. The search guards and kills of `Fw.Ops.LeanFirstSearch` and `FwTest/Mutants/LeanFirst/` were
committed first; this module proves every property of `Fw.Ops.LeanFirstProps` of the real implementation
(`<P>_impl`). The core is `reasonsOf_nil_iff`: the reasons of a rule are empty exactly when the rule's spec holds,
and every reason of a rule carries that rule (`rule_of_mem_reasonsOf`).
-/
namespace Fw.Ops.LeanFirst

open Fw.Spec.Props

/-! ## Boolean helpers against the spec vocabulary -/

/-- `isNew` decides `New`.
$$\forall F\, t,\ \operatorname{new}(F, t) = \mathrm{true} \iff \operatorname{New}(F, t)$$ -/
theorem isNew_iff (F : Facts) (t : ThmFact) : isNew F t = true ↔ New F t := by
  simp [isNew, New]

/-- `hasKill` decides `KillAt` at the theorem's own name and hash.
$$\forall F\, t,\ \operatorname{hasKill}(F, t) = \mathrm{true} \iff \operatorname{KillAt}(F, t.\mathit{name}, t.\mathit{hash})$$ -/
theorem hasKill_iff (F : Facts) (t : ThmFact) : hasKill F t = true ↔ KillAt F t.name t.hash := by
  simp [hasKill, KillAt]

/-- `killedName` decides "some theorem of this name has a kill".
$$\forall F\, n,\ \operatorname{killed}(F, n) = \mathrm{true} \iff \exists v \in \mathit{thms},\ v.\mathit{name} = n \land \operatorname{KillAt}(F, v.\mathit{name}, v.\mathit{hash})$$ -/
theorem killedName_iff (F : Facts) (n : String) :
    killedName F n = true ↔ ∃ v ∈ F.thms, v.name = n ∧ KillAt F v.name v.hash := by
  simp only [killedName, List.any_eq_true, Bool.and_eq_true, beq_iff_eq, hasKill_iff]

/-- `exempt` decides `Exempt`.
$$\forall F\, t,\ \operatorname{exempt}(F, t) = \mathrm{true} \iff \operatorname{Exempt}(F, t)$$ -/
theorem exempt_iff (F : Facts) (t : ThmFact) : exempt F t = true ↔ Exempt F t := by
  simp only [exempt, Exempt, Bool.or_eq_true, bne_iff_ne, ne_eq, Bool.and_eq_true, isNew_iff, Bool.not_eq_true',
    List.any_eq_true, killedName_iff]
  constructor
  · rintro (h | ⟨⟨hn, hk⟩, u, hu, hv⟩)
    · exact Or.inl h
    · refine Or.inr ⟨hn, ?_, u, hu, hv⟩
      intro h; rw [← hasKill_iff] at h; simp [h] at hk
  · rintro (h | ⟨hn, hk, u, hu, hv⟩)
    · exact Or.inl h
    · refine Or.inr ⟨⟨hn, ?_⟩, u, hu, hv⟩
      cases h : hasKill F t
      · rfl
      · exact absurd ((hasKill_iff F t).mp h) hk

/-- `statusOf` is the status `StatusIs` reads.
$$\forall F\, p\, \mathit{st},\ \operatorname{status}(F, p) = \mathrm{some}(\mathit{st}) \iff \operatorname{StatusIs}(F, p, \mathit{st})$$ -/
theorem statusOf_iff (F : Facts) (p : String) (st : Status) : statusOf F p = some st ↔ StatusIs F p st := Iff.rfl

/-- `untestedOk` decides the untested-premise clause of `Discharges`.
$$\forall F\, t\, P,\ \operatorname{untestedOk}(F, t, P) = \mathrm{true} \iff \forall p \in t.\mathit{assumes},\ \operatorname{StatusIs}(F, p, \mathrm{untested}) \Rightarrow p \in P.\mathit{assumes}$$ -/
theorem untestedOk_iff (F : Facts) (t : ThmFact) (P : PropFact) :
    untestedOk F t P = true ↔ ∀ p ∈ t.assumes, StatusIs F p .untested → p ∈ P.assumes := by
  simp only [untestedOk, List.all_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq, List.contains_iff_mem,
    ← statusOf_iff]
  exact forall₂_congr fun p _ => by
    by_cases h : statusOf F p = some .untested <;> simp [h]

/-- `discharges` decides `Discharges`.
$$\forall F\, t\, P,\ \operatorname{dis}(F, t, P) = \mathrm{true} \iff \operatorname{Dis}(F, t, P)$$ -/
theorem discharges_iff (F : Facts) (t : ThmFact) (P : PropFact) : discharges F t P = true ↔ Discharges F t P := by
  simp only [discharges, Discharges, Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true', untestedOk_iff, ← exempt_iff]
  simp only [Bool.not_eq_true, and_assoc, Option.isSome_iff_ne_none]

/-- `proved` decides "some theorem discharges the property".
$$\forall F\, P,\ \operatorname{proved}(F, P) = \mathrm{true} \iff \exists t \in \mathit{thms},\ \operatorname{Dis}(F, t, P)$$ -/
theorem proved_iff (F : Facts) (P : PropFact) : proved F P = true ↔ ∃ t ∈ F.thms, Discharges F t P := by
  simp only [proved, List.any_eq_true, discharges_iff]

/-- `provedReached` decides "a discharging theorem's own implementation is reached from the wire".
$$\forall F\, P,\ \operatorname{provedReached}(F, P) = \mathrm{true} \iff \exists t \in \mathit{thms},\ \operatorname{Dis}(F, t, P) \land t.\mathit{rw} = \mathrm{some}(\mathrm{true})$$ -/
theorem provedReached_iff (F : Facts) (P : PropFact) :
    provedReached F P = true ↔ ∃ t ∈ F.thms, Discharges F t P ∧ t.reachFromWire = some true := by
  simp only [provedReached, List.any_eq_true, Bool.and_eq_true, discharges_iff, beq_iff_eq]

/-- `reachUnknown` decides the negation of `ReachKnown`.
$$\forall F,\ \operatorname{reachUnknown}(F) = \mathrm{true} \iff \lnot\operatorname{ReachKnown}(F)$$ -/
theorem reachUnknown_iff (F : Facts) : reachUnknown F = true ↔ ¬ ReachKnown F := by
  simp only [reachUnknown, ReachKnown, List.any_eq_true, Bool.and_eq_true, Option.isNone_iff_eq_none,
    Option.isSome_iff_ne_none, beq_iff_eq]
  constructor
  · rintro ⟨t, ht, ⟨hr, hi⟩, Q, hQ, hq⟩ hk
    exact hk t ht hi ⟨Q, hQ, hq⟩ hr
  · intro hk
    apply Classical.byContradiction
    intro hn
    exact hk fun t ht hi hq hr => hn ⟨t, ht, ⟨hr, hi⟩, hq⟩

/-- `Signoff.matches` decides `At`.
$$\forall \sigma\, P\, r,\ \operatorname{at}(\sigma, P, r) = \mathrm{true} \iff \operatorname{At}(\sigma, P, r)$$ -/
theorem matches_iff (s : Signoff) (P : PropFact) (r : Role) : s.matches P r = true ↔ At s P r := by
  simp [Signoff.matches, At, and_assoc]

/-- `signed` decides `Signed`.
$$\forall F\, P\, r,\ \operatorname{signed}(F, P, r) = \mathrm{true} \iff \operatorname{Signed}(F, P, r)$$ -/
theorem signed_iff (F : Facts) (P : PropFact) (r : Role) : signed F P r = true ↔ Signed F P r := by
  simp only [signed, Signed, Bool.and_eq_true, List.any_eq_true, matches_iff, Bool.not_eq_true',
    List.any_eq_false, not_and]
  constructor
  · rintro ⟨h1, h2⟩
    refine ⟨h1, fun s hs hat => ?_⟩
    have := h2 s hs
    cases ha : s.agree <;> simp_all
  · rintro ⟨h1, h2⟩
    refine ⟨h1, fun s hs => ?_⟩
    by_cases hat : At s P r
    · simp [h2 s hs hat]
    · simp [hat]

/-- `propKilled` decides `KillAt` at the property's statement hash.
$$\forall F\, P,\ \operatorname{pKilled}(F, P) = \mathrm{true} \iff \operatorname{KillAt}(F, P.\mathit{name}, P.\mathit{stmt})$$ -/
theorem propKilled_iff (F : Facts) (P : PropFact) : propKilled F P = true ↔ KillAt F P.name P.stmtHash := by
  simp [propKilled, KillAt]

/-- `searchFirst` decides `SearchFirst`.
$$\forall F\, P,\ \operatorname{first}(F, P) = \mathrm{true} \iff \operatorname{First}(F, P)$$ -/
theorem searchFirst_iff (F : Facts) (P : PropFact) : searchFirst F P = true ↔ SearchFirst F P := by
  unfold searchFirst SearchFirst
  cases P.searchAt <;> cases P.proofAt <;> simp

/-- `decides` decides `Decides`.
$$\forall F,\ \operatorname{dec}(F) = \mathrm{true} \iff \operatorname{Dec}(F)$$ -/
theorem decides_iff (F : Facts) : decides F = true ↔ Decides F := by
  simp [decides, Decides, isDecisionWrite_iff]

/-- `registered` decides "some registry row has the id".
$$\forall F\, p,\ \operatorname{reg}(F, p) = \mathrm{true} \iff \exists \rho \in \mathit{reg},\ \rho.\mathit{id} = p$$ -/
theorem registered_iff (F : Facts) (p : String) : registered F p = true ↔ ∃ r ∈ F.registry, r.id = p := by
  simp [registered]

/-- `refutedId` decides `StatusIs … refuted`.
$$\forall F\, p,\ \operatorname{refuted}(F, p) = \mathrm{true} \iff \operatorname{StatusIs}(F, p, \mathrm{refuted})$$ -/
theorem refutedId_iff (F : Facts) (p : String) : refutedId F p = true ↔ StatusIs F p .refuted := by
  unfold refutedId; rw [beq_iff_eq]; rfl

/-- Membership in `carriersOf`.
$$\forall F\, t\, p,\ p \in \operatorname{carriers}(F, t) \iff \exists \rho \in \mathit{reg},\ (\exists c \in \rho.\mathit{carriers},\ c \in t.\mathit{reach}) \land \rho.\mathit{id} = p$$ -/
theorem mem_carriersOf (F : Facts) (t : ThmFact) (p : String) :
    p ∈ carriersOf F t ↔ ∃ r ∈ F.registry, (∃ c ∈ r.carriers, c ∈ t.reach) ∧ r.id = p := by
  simp [carriersOf, and_assoc]

/-! ## Each rule's reasons are empty exactly when the rule's spec holds -/

/-- The reasons of one property are empty exactly when the property is done.
$$\forall F\, P,\ \operatorname{reasons}_1(F, P) = [\,] \iff \operatorname{PropOk}(F, P)$$ -/
theorem propReasons_nil_iff (F : Facts) (P : PropFact) : propReasons F P = [] ↔ PropOk F P := by
  have himp : provedReached F P = true → proved F P = true := fun h => by
    obtain ⟨t, ht, hd, -⟩ := (provedReached_iff F P).1 h
    exact (proved_iff F P).2 ⟨t, ht, hd⟩
  rw [PropOk, ← provedReached_iff, ← signed_iff, ← signed_iff, ← propKilled_iff]
  unfold propReasons
  revert himp
  cases proved F P <;> cases provedReached F P <;> cases signed F P .math <;> cases signed F P .adversary <;>
    cases propKilled F P <;> simp

/-- The reason of one theorem under rule 2 is empty exactly when the theorem is old, killed or exempt.
$$\forall F\, t,\ \operatorname{reasons}_2(F, t) = [\,] \iff \bigl(\operatorname{New}(F, t) \Rightarrow \operatorname{KillAt}(F, t.\mathit{name}, t.\mathit{hash}) \lor \operatorname{Exempt}(F, t)\bigr)$$ -/
theorem killReasons_nil_iff (F : Facts) (t : ThmFact) :
    killReasons F t = [] ↔ (New F t → KillAt F t.name t.hash ∨ Exempt F t) := by
  rw [← isNew_iff, ← hasKill_iff, ← exempt_iff]
  unfold killReasons
  cases isNew F t <;> cases hasKill F t <;> cases exempt F t <;> simp

/-- The reason of one branch is empty exactly when its mark is accepted.
$$\forall b,\ \operatorname{reasons}_3(b) = [\,] \iff b.\mathit{mark} \in \{\mathrm{op}, \mathrm{twin}, \mathrm{glueOk}\}$$ -/
theorem branchReasons_nil_iff (b : Branch) :
    branchReasons b = [] ↔ (b.mark = .op ∨ b.mark = .twin ∨ b.mark = .glueOk) := by
  cases b with
  | mk file line mark => cases mark <;> simp [branchReasons, Mark.ok]

/-- The reasons of one theorem under rule 4 are empty exactly when the theorem is old or its premises are in order.
$$\forall F\, t,\ \operatorname{reasons}_4(F, t) = [\,] \iff \Bigl(\operatorname{New}(F, t) \Rightarrow (\forall \rho \in \mathit{reg},\ (\exists c \in \rho.\mathit{carriers},\ c \in t.\mathit{reach}) \Rightarrow \rho.\mathit{id} \in t.\mathit{assumes}) \land (\forall p \in t.\mathit{assumes},\ \exists \rho \in \mathit{reg},\ \rho.\mathit{id} = p) \land (\forall p \in t.\mathit{assumes},\ \lnot \operatorname{StatusIs}(F, p, \mathrm{refuted}))\Bigr)$$ -/
theorem premReasons_nil_iff (F : Facts) (t : ThmFact) :
    premReasons F t = [] ↔ (New F t →
      (∀ r ∈ F.registry, (∃ c ∈ r.carriers, c ∈ t.reach) → r.id ∈ t.assumes) ∧
      (∀ p ∈ t.assumes, ∃ r ∈ F.registry, r.id = p) ∧
      (∀ p ∈ t.assumes, ¬ StatusIs F p .refuted)) := by
  rw [← isNew_iff]
  unfold premReasons
  cases isNew F t
  · simp
  · simp only [ite_true, List.append_eq_nil_iff, List.map_eq_nil_iff, List.filter_eq_nil_iff, Bool.not_eq_true',
      forall_const]
    constructor
    · rintro ⟨⟨h1, h2⟩, h3⟩
      refine ⟨fun r hr hc => ?_, fun p hp => ?_, fun p hp hs => ?_⟩
      · have := h1 r.id ((mem_carriersOf F t r.id).2 ⟨r, hr, hc, rfl⟩)
        simpa using this
      · have := h2 p hp
        simpa [registered_iff] using this
      · exact h3 p hp ((refutedId_iff F p).2 hs)
    · rintro ⟨h1, h2, h3⟩
      refine ⟨⟨fun p hp => ?_, fun p hp => ?_⟩, fun p hp h => h3 p hp ((refutedId_iff F p).1 h)⟩
      · obtain ⟨r, hr, hc, rfl⟩ := (mem_carriersOf F t p).1 hp
        simpa using h1 r hr hc
      · simpa [registered_iff] using h2 p hp

/-- The reason of one property under rule 5 is empty exactly when its search came first.
$$\forall F\, P,\ \operatorname{reasons}_5(F, P) = [\,] \iff \operatorname{SearchFirst}(F, P)$$ -/
theorem searchReasons_nil_iff (F : Facts) (P : PropFact) : searchReasons F P = [] ↔ SearchFirst F P := by
  rw [← searchFirst_iff]
  unfold searchReasons
  cases searchFirst F P <;> simp

/-- **The rule lemma.** The reasons of a rule are empty exactly when the rule's spec holds.
$$\forall F\, r,\ \operatorname{reasonsOf}(F, r) = [\,] \iff \operatorname{RuleOk}(r, F)$$ -/
theorem reasonsOf_nil_iff (F : Facts) (r : Rule) : reasonsOf F r = [] ↔ RuleOk r F := by
  cases r
  · simp only [reasonsOf, RuleOk, PropsOk, List.append_eq_nil_iff, List.flatMap_eq_nil_iff, propReasons_nil_iff,
      ← decides_iff]
    cases decides F <;> cases h : F.props <;> simp
  · simp only [reasonsOf, RuleOk, KillsOk, List.flatMap_eq_nil_iff, killReasons_nil_iff]
  · simp only [reasonsOf, RuleOk, TwinsOk, List.flatMap_eq_nil_iff, branchReasons_nil_iff]
  · simp only [reasonsOf, RuleOk, PremOk, List.flatMap_eq_nil_iff, premReasons_nil_iff]
  · simp only [reasonsOf, RuleOk, SearchOk, List.flatMap_eq_nil_iff, searchReasons_nil_iff]
  · simp only [reasonsOf, RuleOk, RatchetOk]
    by_cases h : F.legacyHead ≤ F.legacyMain <;> simp [h]

/-- Every reason a rule gives carries that rule.
$$\forall F\, r\, \rho,\ \rho \in \operatorname{reasonsOf}(F, r) \Rightarrow \operatorname{rule}(\rho) = r$$ -/
theorem rule_of_mem_reasonsOf (F : Facts) (r : Rule) (ρ : Reason) (h : ρ ∈ reasonsOf F r) : ρ.rule = r := by
  cases r <;> simp only [reasonsOf, List.mem_append, List.mem_flatMap] at h
  · rcases h with h | ⟨P, _, h⟩
    · split at h <;> simp at h; subst h; rfl
    · unfold propReasons at h
      simp only [List.mem_append] at h
      repeat' rcases h with h | h
      all_goals (split at h <;> simp at h <;> first | (subst h; rfl) | (obtain ⟨-, rfl⟩ := h; rfl))
  · obtain ⟨t, _, h⟩ := h
    unfold killReasons at h; split at h <;> simp at h; subst h; rfl
  · obtain ⟨b, _, h⟩ := h
    unfold branchReasons at h; split at h <;> simp at h; subst h; rfl
  · obtain ⟨t, _, h⟩ := h
    unfold premReasons at h
    split at h
    · simp only [List.mem_append, List.mem_map] at h
      rcases h with (⟨_, _, rfl⟩ | ⟨_, _, rfl⟩) | ⟨_, _, rfl⟩ <;> rfl
    · simp at h
  · obtain ⟨P, _, h⟩ := h
    unfold searchReasons at h; split at h <;> simp at h; subst h; rfl
  · split at h <;> simp at h; subst h; rfl

/-- Every rule is in `Rule.all`. $$\forall r,\ r \in \mathrm{Rule.all}$$ -/
theorem mem_all (r : Rule) : r ∈ Rule.all := by cases r <;> decide

/-- The enforced reasons are empty exactly when every enforced rule holds.
$$\forall s\, F,\ [\,\rho \in \operatorname{reasons}(F) \mid \operatorname{enf}(s, F.\mathit{leanFirst}, \operatorname{rule}(\rho))\,] = [\,] \iff \forall r \in \mathrm{Rule.all},\ \operatorname{enf}(s, F.\mathit{leanFirst}, r) \Rightarrow \operatorname{RuleOk}(r, F)$$
The filter keeps the reasons whose rule is enforced at stage $s$. -/
theorem reasons_filter_nil_iff (s : Stage) (F : Facts) :
    (reasons F).filter (fun ρ => enforced s F.leanFirst ρ.rule) = [] ↔
      ∀ r ∈ Rule.all, enforced s F.leanFirst r = true → RuleOk r F := by
  rw [List.filter_eq_nil_iff]
  constructor
  · intro h r hr he
    rw [← reasonsOf_nil_iff, List.eq_nil_iff_forall_not_mem]
    intro ρ hρ
    have hrule := rule_of_mem_reasonsOf F r ρ hρ
    exact h ρ (List.mem_flatMap.2 ⟨r, hr, hρ⟩) (by rw [hrule]; exact he)
  · intro h ρ hρ he
    obtain ⟨r, hr, hρ'⟩ := List.mem_flatMap.1 hρ
    have hrule := rule_of_mem_reasonsOf F r ρ hρ'
    rw [hrule] at he
    rw [(reasonsOf_nil_iff F r).2 (h r hr he)] at hρ'
    simp at hρ'

/-- No fact is missing exactly when every fact is present.
$$\forall F,\ \operatorname{missing}(F) = [\,] \iff \operatorname{Present}(F)$$ -/
theorem missing_nil_iff (F : Facts) : missing F = [] ↔ AllPresent F := by
  have hr : ReachKnown F ↔ reachUnknown F = false := by
    rw [← Bool.not_eq_true, reachUnknown_iff, Classical.not_not]
  have he : F.exemptAt = some F.mainAt ↔ (F.exemptAt == some F.mainAt) = true := by simp
  unfold missing AllPresent
  rw [hr, he]
  cases F.present.mathview <;> cases F.present.kills <;> cases F.present.tsLint <;> cases reachUnknown F <;>
    cases (F.exemptAt == some F.mainAt) <;> simp

/-- Some rule is enforced exactly when `anyEnforced` says so.
$$\forall s\, \mathit{lf},\ \operatorname{anyEnforced}(s, \mathit{lf}) = \mathrm{true} \iff \exists r \in \mathrm{Rule.all},\ \operatorname{enf}(s, \mathit{lf}, r)$$ -/
theorem anyEnforced_iff (s : Stage) (lf : Bool) :
    anyEnforced s lf = true ↔ ∃ r ∈ Rule.all, enforced s lf r = true := by
  simp [anyEnforced]

/-! ## The verdict of `judge` -/

/-- With a source missing and some rule enforced, the verdict is pending on the missing sources.
$$\forall R\, s\, F,\ \lnot \operatorname{AllPresent}(F) \land (\exists r \in \mathrm{Rule.all},\ \operatorname{enf}(s, F.\mathit{lf}, r)) \Rightarrow \operatorname{judge}(R, s, F) = \mathrm{pending}(\operatorname{missing}(F))$$ -/
theorem judge_pending (R : Facts → List Reason) (s : Stage) (F : Facts) (hp : ¬ AllPresent F)
    (he : ∃ r ∈ Rule.all, enforced s F.leanFirst r = true) : judge R s F = .pending (missing F) := by
  have h1 : (missing F).isEmpty = false := by
    cases h : missing F
    · exact absurd ((missing_nil_iff F).1 h) hp
    · rfl
  have h2 := (anyEnforced_iff s F.leanFirst).2 he
  simp [judge, h1, h2]

/-- With the sources present (or no rule enforced), the verdict is the match on the enforced reasons.
$$\forall R\, s\, F,\ \bigl(\operatorname{AllPresent}(F) \lor \forall r \in \mathrm{Rule.all},\ \lnot\operatorname{enf}(s, F.\mathit{lf}, r)\bigr) \Rightarrow \bigl(\operatorname{judge}(R, s, F) = \mathrm{pass} \iff [\,\rho \in R(F) \mid \operatorname{enf}(s, F.\mathit{lf}, \operatorname{rule}(\rho))\,] = [\,]\bigr) \land \operatorname{refusals}(\operatorname{judge}(R, s, F)) = [\,\rho \in R(F) \mid \operatorname{enf}(s, F.\mathit{lf}, \operatorname{rule}(\rho))\,]$$
The filtered list holds the reasons of $R(F)$ whose rule is enforced at stage $s$. -/
theorem judge_settled (R : Facts → List Reason) (s : Stage) (F : Facts)
    (h : AllPresent F ∨ ∀ r ∈ Rule.all, enforced s F.leanFirst r = false) :
    (judge R s F = .pass ↔ (R F).filter (fun ρ => enforced s F.leanFirst ρ.rule) = []) ∧
      (judge R s F).refusals = (R F).filter (fun ρ => enforced s F.leanFirst ρ.rule) := by
  have hc : (!(missing F).isEmpty && anyEnforced s F.leanFirst) = false := by
    rcases h with h | h
    · rw [(missing_nil_iff F).2 h]; rfl
    · have : anyEnforced s F.leanFirst = false := by
        cases ha : anyEnforced s F.leanFirst
        · rfl
        · obtain ⟨r, hr, he⟩ := (anyEnforced_iff _ _).1 ha
          rw [h r hr] at he; exact absurd he (by decide)
      rw [this, Bool.and_false]
  unfold judge
  rw [hc]; simp only [Bool.false_eq_true, ↓reduceIte]
  split <;> simp_all [Verdict.refusals]

/-! ## The gate properties -/

/-- **`pass_iff` holds of the gate.**
$$\forall s\, F,\ \operatorname{gate}(s, F) = \mathrm{pass} \iff \operatorname{PassSpec}(s, F)$$
The gate passes exactly when the sources are present (or nothing is enforced) and every enforced rule holds. -/
theorem PassIff_impl : PassIff gate := by
  intro s F
  by_cases h : AllPresent F ∨ ∀ r ∈ Rule.all, enforced s F.leanFirst r = false
  · show judge reasons s F = .pass ↔ _
    rw [(judge_settled reasons s F h).1, reasons_filter_nil_iff]
    exact ⟨fun h' => ⟨h, h'⟩, fun h' => h'.2⟩
  · have hp : ¬ AllPresent F := fun h' => h (Or.inl h')
    have he : ∃ r ∈ Rule.all, enforced s F.leanFirst r = true := by
      apply Classical.byContradiction
      intro hn
      exact h (Or.inr fun r hr => by
        cases h' : enforced s F.leanFirst r
        · rfl
        · exact absurd ⟨r, hr, h'⟩ hn)
    show judge reasons s F = .pass ↔ _
    rw [judge_pending reasons s F hp he]
    exact ⟨(fun h' => nomatch h'), fun h' => absurd h'.1 h⟩

/-- A reason of an enforced rule, with the sources present, is a refusal of the gate.
$$\forall s\, F\, r\, \rho,\ \operatorname{AllPresent}(F) \land \rho \in \operatorname{reasonsOf}(F, r) \land \operatorname{enf}(s, F.\mathit{lf}, r) \Rightarrow \rho \in \operatorname{refusals}(\operatorname{gate}(s, F))$$ -/
theorem mem_refusals (s : Stage) (F : Facts) (r : Rule) (ρ : Reason) (hp : AllPresent F)
    (hρ : ρ ∈ reasonsOf F r) (he : enforced s F.leanFirst r = true) : ρ ∈ (gate s F).refusals := by
  show ρ ∈ (judge reasons s F).refusals
  rw [(judge_settled reasons s F (Or.inl hp)).2, List.mem_filter, rule_of_mem_reasonsOf F r ρ hρ]
  exact ⟨List.mem_flatMap.2 ⟨r, mem_all r, hρ⟩, he⟩

/-- **`refuses_unproved` holds of the gate.**
$$\forall s\, F,\ \operatorname{enf}(s, F.\mathit{lf}, \mathrm{props}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow \forall P \in F.\mathit{props},\ \lnot(\exists t \in F.\mathit{thms},\ \operatorname{Dis}(F, t, P)) \Rightarrow \mathrm{unproved}(P.\mathit{name}) \in \operatorname{refusals}(\operatorname{gate}(s, F))$$
An unproved property refuses the land, naming the property. -/
theorem RefusesUnproved_impl : RefusesUnproved gate := by
  intro s F he hp P hP hn
  have h : proved F P = false := Bool.eq_false_iff.2 fun h' => hn ((proved_iff F P).1 h')
  refine mem_refusals s F .props _ hp ?_ he
  exact List.mem_append_right _ (List.mem_flatMap.2 ⟨P, hP, by simp [propReasons, h]⟩)

/-- **`stale_review_refuses` holds of the gate.**
$$\forall s\, F,\ \operatorname{enf}(s, F.\mathit{lf}, \mathrm{props}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow \forall P \in F.\mathit{props},\ \forall r \in [\mathrm{math}, \mathrm{adversary}],\ \lnot\operatorname{Signed}(F, P, r) \Rightarrow \mathrm{unsigned}(P.\mathit{name}, r) \in \operatorname{refusals}(\operatorname{gate}(s, F))$$
A missing, stale or disagreeing review refuses the land, naming the property and the role. -/
theorem StaleReviewRefuses_impl : StaleReviewRefuses gate := by
  intro s F he hp P hP r hr hn
  have h : signed F P r = false := Bool.eq_false_iff.2 fun h' => hn ((signed_iff F P r).1 h')
  refine mem_refusals s F .props _ hp ?_ he
  refine List.mem_append_right _ (List.mem_flatMap.2 ⟨P, hP, ?_⟩)
  simp only [List.mem_cons, List.not_mem_nil, or_false] at hr
  rcases hr with rfl | rfl <;> simp [propReasons, h]

/-- **`land_refuses_unreached` holds of the gate.**
$$\forall s\, F,\ \operatorname{en}(s, F.\mathit{lf}, \mathrm{props}) \land \operatorname{Present}(F) \Rightarrow \forall P \in F.\mathit{props},\ (\exists t \in F.\mathit{thms},\ \operatorname{Dis}(F, t, P)) \land (\forall t \in F.\mathit{thms},\ \operatorname{Dis}(F, t, P) \Rightarrow t.\mathit{rw} \ne \mathrm{some}(\mathrm{true})) \Rightarrow \mathrm{unreached}(P.\mathit{name}) \in \operatorname{refusals}(\operatorname{gate}(s, F))$$
A property proved only of a stub refuses the land. -/
theorem RefusesUnreached_impl : RefusesUnreached gate := by
  intro s F he hp P hP hd hn
  have h1 : proved F P = true := (proved_iff F P).2 hd
  have h2 : provedReached F P = false := Bool.eq_false_iff.2 fun h' => by
    obtain ⟨t, ht, hdt, hr⟩ := (provedReached_iff F P).1 h'
    exact hn t ht hdt hr
  refine mem_refusals s F .props _ hp ?_ he
  exact List.mem_append_right _ (List.mem_flatMap.2 ⟨P, hP, by simp [propReasons, h1, h2]⟩)

/-- **`no_props_refuses` holds of the gate.**
$$\forall s\, F,\ \operatorname{en}(s, F.\mathit{lf}, \mathrm{props}) \land \operatorname{Present}(F) \land \operatorname{Dec}(F) \land F.\mathit{props} = [\,] \Rightarrow \exists w \in F.\mathit{writes},\ \operatorname{DecW}(w) \land \mathrm{noProps}(w) \in \operatorname{refusals}(\operatorname{gate}(s, F))$$
Writing decision code without stating a property refuses the land. -/
theorem NoPropsRefuses_impl : NoPropsRefuses gate := by
  intro s F he hp hd hnil
  obtain ⟨w, hw, hdw⟩ := hd
  cases hf : F.writes.find? isDecisionWrite with
  | none =>
    have := List.find?_eq_none.1 hf w hw
    exact absurd ((isDecisionWrite_iff w).2 hdw) (by simpa using this)
  | some v =>
    refine ⟨v, List.mem_of_find?_eq_some hf, (isDecisionWrite_iff v).1 (List.find?_some hf), ?_⟩
    refine mem_refusals s F .props _ hp ?_ he
    have hdec : decides F = true := (decides_iff F).2 ⟨w, hw, hdw⟩
    have hv : firstDecision F = v := by simp [firstDecision, hf]
    refine List.mem_append_left _ ?_
    simp [hdec, hnil, hv]

/-- **`mutant_kills_or_refuse` holds of the gate.**
$$\forall s\, F,\ \operatorname{enf}(s, F.\mathit{lf}, \mathrm{kills}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow \forall t \in F.\mathit{thms},\ \operatorname{New}(F, t) \Rightarrow \lnot\operatorname{KillAt}(F, t.\mathit{name}, t.\mathit{hash}) \Rightarrow \lnot\operatorname{Exempt}(F, t) \Rightarrow \mathrm{noKill}(t.\mathit{name}) \in \operatorname{refusals}(\operatorname{gate}(s, F))$$
A new theorem that no mutant kills refuses the land. -/
theorem MutantKillsOrRefuse_impl : MutantKillsOrRefuse gate := by
  intro s F he hp t ht hn hk hx
  have h1 : isNew F t = true := (isNew_iff F t).2 hn
  have h2 : hasKill F t = false := Bool.eq_false_iff.2 fun h' => hk ((hasKill_iff F t).1 h')
  have h3 : exempt F t = false := Bool.eq_false_iff.2 fun h' => hx ((exempt_iff F t).1 h')
  refine mem_refusals s F .kills _ hp (List.mem_flatMap.2 ⟨t, ht, ?_⟩) he
  simp [killReasons, h1, h2, h3]

/-- **`exempt_not_discharge` holds of `discharges`.**
$$\forall F\, t\, P,\ \operatorname{Exempt}(F, t) \Rightarrow \operatorname{dis}(F, t, P) = \mathrm{false}$$
A lemma, data lint or kill witness can never be the proof of a property. -/
theorem ExemptNotDischarge_impl : ExemptNotDischarge discharges := by
  intro F t P hx
  exact Bool.eq_false_iff.2 fun h => ((discharges_iff F t P).1 h).2.2.2.1 hx

/-- **`hidden_premise_refuses` holds of the gate.**
$$\forall s\, F,\ \operatorname{enf}(s, F.\mathit{lf}, \mathrm{premises}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow \forall t \in F.\mathit{thms},\ \operatorname{New}(F, t) \Rightarrow \forall \rho \in F.\mathit{reg},\ (\exists c \in \rho.\mathit{carriers},\ c \in t.\mathit{reach}) \Rightarrow \rho.\mathit{id} \notin t.\mathit{assumes} \Rightarrow \mathrm{hidden}(t.\mathit{name}, \rho.\mathit{id}) \in \operatorname{refusals}(\operatorname{gate}(s, F))$$
A premise hidden inside a definition the proof reaches refuses the land. -/
theorem HiddenPremiseRefuses_impl : HiddenPremiseRefuses gate := by
  intro s F he hp t ht hn r hr hc ha
  have h1 : isNew F t = true := (isNew_iff F t).2 hn
  refine mem_refusals s F .premises _ hp (List.mem_flatMap.2 ⟨t, ht, ?_⟩) he
  simp only [premReasons, h1, ite_true]
  refine List.mem_append_left _ (List.mem_append_left _ (List.mem_map.2 ⟨r.id, ?_, rfl⟩))
  exact List.mem_filter.2 ⟨(mem_carriersOf F t r.id).2 ⟨r, hr, hc, rfl⟩, by simpa using ha⟩

/-- **`unregistered_premise_refuses` holds of the gate.**
$$\forall s\, F,\ \operatorname{enf}(s, F.\mathit{lf}, \mathrm{premises}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow \forall t \in F.\mathit{thms},\ \operatorname{New}(F, t) \Rightarrow \forall p \in t.\mathit{assumes},\ \lnot(\exists \rho \in F.\mathit{reg},\ \rho.\mathit{id} = p) \Rightarrow \mathrm{unregistered}(t.\mathit{name}, p) \in \operatorname{refusals}(\operatorname{gate}(s, F))$$
A premise id that is not in the registry refuses the land. -/
theorem UnregisteredPremiseRefuses_impl : UnregisteredPremiseRefuses gate := by
  intro s F he hp t ht hn p hpa hr
  have h1 : isNew F t = true := (isNew_iff F t).2 hn
  have h2 : registered F p = false := Bool.eq_false_iff.2 fun h' => hr ((registered_iff F p).1 h')
  refine mem_refusals s F .premises _ hp (List.mem_flatMap.2 ⟨t, ht, ?_⟩) he
  simp only [premReasons, h1, ite_true]
  refine List.mem_append_left _ (List.mem_append_right _ (List.mem_map.2 ⟨p, ?_, rfl⟩))
  exact List.mem_filter.2 ⟨hpa, by simp [h2]⟩

/-- **`refuted_premise_refuses` holds of the gate.**
$$\forall s\, F,\ \operatorname{enf}(s, F.\mathit{lf}, \mathrm{premises}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow \forall t \in F.\mathit{thms},\ \operatorname{New}(F, t) \Rightarrow \forall p \in t.\mathit{assumes},\ \operatorname{StatusIs}(F, p, \mathrm{refuted}) \Rightarrow \mathrm{refuted}(t.\mathit{name}, p) \in \operatorname{refusals}(\operatorname{gate}(s, F))$$
A proof that rests on a refuted premise refuses the land. -/
theorem RefutedPremiseRefuses_impl : RefutedPremiseRefuses gate := by
  intro s F he hp t ht hn p hpa hs
  have h1 : isNew F t = true := (isNew_iff F t).2 hn
  refine mem_refusals s F .premises _ hp (List.mem_flatMap.2 ⟨t, ht, ?_⟩) he
  simp only [premReasons, h1, ite_true]
  exact List.mem_append_right _ (List.mem_map.2 ⟨p, List.mem_filter.2 ⟨hpa, (refutedId_iff F p).2 hs⟩, rfl⟩)

/-- **`untwinned_branch_refuses` holds of the gate.**
$$\forall s\, F,\ \operatorname{enf}(s, F.\mathit{lf}, \mathrm{twins}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow \forall b \in F.\mathit{branches},\ b.\mathit{mark} \in \{\mathrm{none}, \mathrm{glueBad}\} \Rightarrow \mathrm{branch}(b.\mathit{file}, b.\mathit{line}, b.\mathit{mark}) \in \operatorname{refusals}(\operatorname{gate}(s, F))$$
A TS decision branch with neither a Lean op, a twin nor accepted glue refuses the land. -/
theorem UntwinnedBranchRefuses_impl : UntwinnedBranchRefuses gate := by
  intro s F he hp b hb hm
  refine mem_refusals s F .twins _ hp (List.mem_flatMap.2 ⟨b, hb, ?_⟩) he
  rcases hm with hm | hm <;> simp [branchReasons, hm, Mark.ok]

/-- **`proof_before_search_refuses` holds of the gate.**
$$\forall s\, F,\ \operatorname{enf}(s, F.\mathit{lf}, \mathrm{search}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow \forall P \in F.\mathit{props},\ \lnot\operatorname{SearchFirst}(F, P) \Rightarrow \mathrm{searchOrder}(P.\mathit{name}) \in \operatorname{refusals}(\operatorname{gate}(s, F))$$
A proof committed before (or without) its edge-case search refuses the land. -/
theorem ProofBeforeSearchRefuses_impl : ProofBeforeSearchRefuses gate := by
  intro s F he hp P hP hn
  have h : searchFirst F P = false := Bool.eq_false_iff.2 fun h' => hn ((searchFirst_iff F P).1 h')
  refine mem_refusals s F .search _ hp (List.mem_flatMap.2 ⟨P, hP, ?_⟩) he
  simp [searchReasons, h]

/-- **`ratchet_refuses_growth` holds of the gate.**
$$\forall s\, F,\ \operatorname{enf}(s, F.\mathit{lf}, \mathrm{ratchet}) \Rightarrow \operatorname{AllPresent}(F) \Rightarrow F.\mathit{main} < F.\mathit{head} \Rightarrow \mathrm{growth}(F.\mathit{main}, F.\mathit{head}) \in \operatorname{refusals}(\operatorname{gate}(s, F))$$
The grandfathered gap count may only shrink. -/
theorem RatchetRefusesGrowth_impl : RatchetRefusesGrowth gate := by
  intro s F he hp hlt
  refine mem_refusals s F .ratchet _ hp ?_ he
  simp [reasonsOf, Nat.not_le.2 hlt]

/-- **`missing_fact_pending` holds of the gate.**
$$\forall s\, F,\ (\exists r \in \mathrm{rules},\ \operatorname{en}(s, F.\mathit{lf}, r)) \land \lnot\operatorname{Present}(F) \Rightarrow \operatorname{isPending}(\operatorname{gate}(s, F)) \land \bigwedge_{x \in \{\mathit{mathview}, \mathit{kills}, \mathit{tsLint}\}} (F.\mathit{present}.x = \mathrm{false} \iff x \in \operatorname{pendingOn}(\operatorname{gate}(s, F))) \land (\lnot\operatorname{ReachKnown}(F) \iff \mathrm{reach} \in \operatorname{pendingOn}(\operatorname{gate}(s, F))) \land (F.\mathit{exemptAt} \ne \mathrm{some}(F.\mathit{mainAt}) \iff \mathrm{exempt} \in \operatorname{pendingOn}(\operatorname{gate}(s, F)))$$
A missing fact fails closed as pending, never as a vacuous pass. -/
theorem MissingFactPending_impl : MissingFactPending gate := by
  intro s F he hp
  have hg : gate s F = .pending (missing F) := judge_pending reasons s F hp he
  have hr : ¬ ReachKnown F ↔ reachUnknown F = true := (reachUnknown_iff F).symm
  have hx : F.exemptAt ≠ some F.mainAt ↔ (F.exemptAt == some F.mainAt) = false := by simp
  rw [hg, hr, hx]
  simp only [Verdict.isPending, Verdict.pendingOn, missing, true_and]
  cases F.present.mathview <;> cases F.present.kills <;> cases F.present.tsLint <;> cases reachUnknown F <;>
    cases (F.exemptAt == some F.mainAt) <;> simp

/-- **`shadow_passes` holds of the gate.**
$$\forall F,\ \operatorname{gate}(\mathrm{shadow}, F) = \mathrm{pass}$$
The shadow stage never blocks a land. -/
theorem ShadowPasses_impl : ShadowPasses gate := by
  intro F
  rw [PassIff_impl]
  exact ⟨Or.inr fun r _ => rfl, fun r _ h => absurd h (by simp [enforced])⟩

/-! ## The output properties -/

/-- A tagged line is a VERDICT line exactly when its tag is `verdict`.
$$\forall t\, b,\ \operatorname{isVerdict}(\operatorname{line}(t, b)) = \mathrm{true} \iff t = \mathrm{verdict}$$ -/
theorem isVerdict_mkLine (t : Tag) (b : String) : isVerdict (mkLine t b) = true ↔ t = .verdict := by
  unfold isVerdict mkLine
  rw [String.startsWith_string_iff, String.toList_append]
  cases t
  · exact ⟨fun _ => rfl, fun _ => List.prefix_append _ _⟩
  all_goals
    refine ⟨fun h => ?_, fun h => nomatch h⟩
    have := h.head
    simp [Tag.text] at this

/-- A tagged line holds no line break.
$$\forall t\, b,\ \texttt{\textbackslash n} \notin \operatorname{line}(t, b) \land \texttt{\textbackslash r} \notin \operatorname{line}(t, b)$$ -/
theorem mkLine_no_break (t : Tag) (b : String) : '\n' ∉ (mkLine t b).toList ∧ '\r' ∉ (mkLine t b).toList := by
  unfold mkLine clean
  rw [String.toList_append, String.toList_map]
  have ht : '\n' ∉ t.text.toList ∧ '\r' ∉ t.text.toList := by cases t <;> decide
  refine ⟨fun h => ?_, fun h => ?_⟩
  all_goals
    rcases List.mem_append.1 h with h | h
    · first | exact ht.1 h | exact ht.2 h
    · obtain ⟨c, _, hc⟩ := List.mem_map.1 h
      by_cases h1 : c = '\n' <;> by_cases h2 : c = '\r' <;> simp [h1, h2] at hc <;> simp_all

/-- Every `LEANFIRST` line is a tagged line.
$$\forall s\, F\, l,\ l \in \operatorname{shadowLines}(s, F) \Rightarrow \exists b,\ l = \operatorname{line}(\mathrm{shadow}, b)$$ -/
theorem mem_shadowLines (s : Stage) (F : Facts) (l : String) (h : l ∈ shadowLines s F) :
    ∃ b, l = mkLine .shadow b := by
  unfold shadowLines at h
  split at h <;> (obtain ⟨_, _, rfl⟩ := List.mem_map.1 h; exact ⟨_, rfl⟩)

/-- Every `WARN` line is a tagged line.
$$\forall F\, l,\ l \in \operatorname{warnLines}(F) \Rightarrow \exists b,\ l = \operatorname{line}(\mathrm{warn}, b)$$ -/
theorem mem_warnLines (F : Facts) (l : String) (h : l ∈ warnLines F) : ∃ b, l = mkLine .warn b := by
  unfold warnLines at h
  obtain ⟨_, _, h⟩ := List.mem_flatMap.1 h
  obtain ⟨_, _, rfl⟩ := List.mem_map.1 h
  exact ⟨_, rfl⟩

/-- The printed lines are non-VERDICT tagged lines followed by one VERDICT line.
$$\forall s\, F,\ \exists L\, x,\ \operatorname{out}(s, F).\mathit{lines} = L \mathbin{+\!\!+} [\operatorname{line}(\mathrm{verdict}, x)] \land \forall l \in L,\ \exists t\, b,\ t \ne \mathrm{verdict} \land l = \operatorname{line}(t, b)$$ -/
theorem out_lines (s : Stage) (F : Facts) :
    ∃ L x, (out s F).lines = L ++ [mkLine .verdict x] ∧ ∀ l ∈ L, ∃ t b, t ≠ .verdict ∧ l = mkLine t b := by
  have hs : ∀ l ∈ shadowLines s F, ∃ t b, t ≠ .verdict ∧ l = mkLine t b := fun l h => by
    obtain ⟨b, rfl⟩ := mem_shadowLines s F l h; exact ⟨.shadow, b, nofun, rfl⟩
  have hw : ∀ l ∈ warnLines F, ∃ t b, t ≠ .verdict ∧ l = mkLine t b := fun l h => by
    obtain ⟨b, rfl⟩ := mem_warnLines F l h; exact ⟨.warn, b, nofun, rfl⟩
  unfold out
  generalize gate s F = v
  cases v with
  | pass =>
    refine ⟨shadowLines s F ++ warnLines F, _, rfl, fun l h => ?_⟩
    rcases List.mem_append.1 h with h | h
    · exact hs l h
    · exact hw l h
  | pending ms =>
    refine ⟨_, _, rfl, fun l h => ?_⟩
    obtain ⟨_, _, rfl⟩ := List.mem_map.1 h
    exact ⟨.reason, _, nofun, rfl⟩
  | refuse rs =>
    refine ⟨_ ++ shadowLines s F ++ warnLines F, _, rfl, fun l h => ?_⟩
    rcases List.mem_append.1 h with h | h
    · rcases List.mem_append.1 h with h | h
      · obtain ⟨_, _, rfl⟩ := List.mem_map.1 h
        exact ⟨.reason, _, nofun, rfl⟩
      · exact hs l h
    · exact hw l h

/-- **`one_verdict` holds of the renderer.**
$$\forall s\, F,\ \bigl|[\,l \in \operatorname{out}(s, F).\mathit{lines} \mid \operatorname{isVerdict}(l)\,]\bigr| = 1 \land \operatorname{isVerdict}(\operatorname{last}(\operatorname{out}(s, F).\mathit{lines}))$$
Every run prints one VERDICT line, as its last line. -/
theorem OneVerdict_impl : OneVerdict out := by
  intro s F
  obtain ⟨L, x, hl, hL⟩ := out_lines s F
  have hnv : L.filter isVerdict = [] := List.filter_eq_nil_iff.2 fun l h => by
    obtain ⟨t, b, ht, rfl⟩ := hL l h
    rw [isVerdict_mkLine]; exact ht
  have hv : isVerdict (mkLine .verdict x) = true := (isVerdict_mkLine _ _).2 rfl
  rw [hl]
  refine ⟨?_, ?_⟩
  · simp [verdictCount, List.filter_append, hnv, hv]
  · rw [List.getLast?_concat]; simp [hv]

/-- **`no_newline` holds of the renderer.**
$$\forall s\, F,\ \forall l \in \operatorname{out}(s, F).\mathit{lines},\ \texttt{\textbackslash n} \notin l \land \texttt{\textbackslash r} \notin l$$
A fact cannot forge an extra stdout line, such as a second VERDICT. -/
theorem NoNewline_impl : NoNewline out := by
  intro s F l hl
  obtain ⟨L, x, hlines, hL⟩ := out_lines s F
  rw [hlines] at hl
  rcases List.mem_append.1 hl with h | h
  · obtain ⟨t, b, _, rfl⟩ := hL l h
    exact mkLine_no_break t b
  · rw [List.mem_singleton] at h
    subst h
    exact mkLine_no_break _ _

/-- **`missing_fact_not_pass`, exit half, holds of the renderer.**
$$\forall s\, F,\ (\exists r \in \mathrm{Rule.all},\ \operatorname{enf}(s, F.\mathit{lf}, r)) \Rightarrow \lnot\operatorname{AllPresent}(F) \Rightarrow \operatorname{out}(s, F).\mathit{kind} = \mathrm{pending} \land \operatorname{out}(s, F).\mathit{exit} = 75$$
A missing fact source exits 75, the retry code. -/
theorem PendingExit_impl : PendingExit out := by
  intro s F he hp
  have hg : gate s F = .pending (missing F) := judge_pending reasons s F hp he
  unfold out
  rw [hg]
  exact ⟨rfl, rfl⟩

/-- **`exit_zero_iff` holds of the renderer.**
$$\forall s\, F,\ \operatorname{out}(s, F).\mathit{exit} = 0 \iff \operatorname{PassSpec}(s, F)$$
The check exits 0 exactly when the land passes the spec. -/
theorem ExitZeroIff_impl : ExitZeroIff out := by
  intro s F
  rw [← PassIff_impl s F]
  unfold out
  generalize gate s F = v
  cases v <;> simp

/-! ## Monotonicity -/

/-- Wherever the props rule is enforced, the kills rule is too.
$$\forall s\, \mathit{lf},\ \operatorname{enf}(s, \mathit{lf}, \mathrm{props}) \Rightarrow \operatorname{enf}(s, \mathit{lf}, \mathrm{kills})$$ -/
theorem kills_of_props (s : Stage) (lf : Bool) (h : enforced s lf .props = true) : enforced s lf .kills = true := by
  revert h; cases s <;> cases lf <;> decide

/-- A stricter stage enforces a superset of rules.
$$\forall s\, s'\, \mathit{lf}\, r,\ \operatorname{rank}(s) \le \operatorname{rank}(s') \Rightarrow \operatorname{enf}(s, \mathit{lf}, r) \Rightarrow \operatorname{enf}(s', \mathit{lf}, r)$$ -/
theorem enforced_mono (s s' : Stage) (lf : Bool) (r : Rule) (hle : s.rank ≤ s'.rank)
    (h : enforced s lf r = true) : enforced s' lf r = true := by
  revert hle h; cases s <;> cases s' <;> cases lf <;> cases r <;> decide

/-- More kill rows keep every kill.
$$\forall F\, e\, n\, h,\ \operatorname{KillAt}(F, n, h) \Rightarrow \operatorname{KillAt}(F + e, n, h)$$ -/
theorem killAt_add (F : Facts) (e : Evidence) (n h : String) (hk : KillAt F n h) : KillAt (F.add e) n h := by
  obtain ⟨k, hk, h1, h2⟩ := hk
  exact ⟨k, List.mem_append_left _ hk, h1, h2⟩

/-- "Killed or exempt" survives more evidence.
$$\forall F\, e\, t,\ \operatorname{KillAt}(F, t.\mathit{name}, t.\mathit{hash}) \lor \operatorname{Exempt}(F, t) \Rightarrow \operatorname{KillAt}(F + e, t.\mathit{name}, t.\mathit{hash}) \lor \operatorname{Exempt}(F + e, t)$$ -/
theorem killOrExempt_add (F : Facts) (e : Evidence) (t : ThmFact)
    (h : KillAt F t.name t.hash ∨ Exempt F t) : KillAt (F.add e) t.name t.hash ∨ Exempt (F.add e) t := by
  rcases h with h | h | ⟨hn, _, u, hu, v, hv, hvn, hvk⟩
  · exact Or.inl (killAt_add F e _ _ h)
  · exact Or.inr (Or.inl h)
  · by_cases hk : KillAt (F.add e) t.name t.hash
    · exact Or.inl hk
    · exact Or.inr (Or.inr ⟨hn, hk, u, hu, v, hv, hvn, killAt_add F e _ _ hvk⟩)

/-- Under rule 2, a discharge survives more evidence.
$$\forall F\, e\, t\, P,\ \operatorname{KillsOk}(F) \Rightarrow t \in F.\mathit{thms} \Rightarrow \operatorname{Dis}(F, t, P) \Rightarrow \operatorname{Dis}(F + e, t, P)$$ -/
theorem discharges_add (F : Facts) (e : Evidence) (t : ThmFact) (P : PropFact) (hK : KillsOk F)
    (ht : t ∈ F.thms) (h : Discharges F t P) : Discharges (F.add e) t P := by
  obtain ⟨h1, hi, h2, hx, h4⟩ := h
  refine ⟨h1, hi, h2, fun hx' => ?_, h4⟩
  rcases hx' with hg | ⟨hn, hnk, _⟩
  · exact hx (Or.inl hg)
  · rcases hK t ht hn with hk | hk
    · exact hnk (killAt_add F e _ _ hk)
    · exact hx hk

/-- A sign-off survives more evidence (added rows agree).
$$\forall F\, e\, P\, r,\ \operatorname{Signed}(F, P, r) \Rightarrow \operatorname{Signed}(F + e, P, r)$$ -/
theorem signed_add (F : Facts) (e : Evidence) (P : PropFact) (r : Role) (h : Signed F P r) :
    Signed (F.add e) P r := by
  obtain ⟨⟨s, hs, hat, hag⟩, hall⟩ := h
  refine ⟨⟨s, List.mem_append_left _ hs, hat, hag⟩, fun s' hs' hat' => ?_⟩
  rcases List.mem_append.1 hs' with h | h
  · exact hall s' h hat'
  · obtain ⟨_, _, rfl⟩ := List.mem_map.1 h
    rfl

/-- Filling marks changes no branch that already has one.
$$\forall bs\, ms,\ (\forall b \in bs,\ b.\mathit{mark} \ne \mathrm{none}) \Rightarrow \operatorname{fill}(bs, ms) = bs$$ -/
theorem fillMarks_of_marked (bs : List Branch) (ms : List Mark) (h : ∀ b ∈ bs, b.mark ≠ .none) :
    fillMarks bs ms = bs := by
  induction bs generalizing ms with
  | nil => cases ms <;> rfl
  | cons b bs ih =>
    cases ms with
    | nil => rfl
    | cons m ms =>
      simp only [fillMarks, h b (List.mem_cons_self ..), ite_false]
      rw [ih ms fun b' hb' => h b' (List.mem_cons_of_mem _ hb')]

/-- A rule that holds keeps holding with more evidence (props given rule 2).
$$\forall F\, e\, r,\ (r = \mathrm{props} \Rightarrow \operatorname{KillsOk}(F)) \Rightarrow \operatorname{RuleOk}(r, F) \Rightarrow \operatorname{RuleOk}(r, F + e)$$ -/
theorem ruleOk_add (F : Facts) (e : Evidence) (r : Rule) (hK : r = .props → KillsOk F) (h : RuleOk r F) :
    RuleOk r (F.add e) := by
  cases r
  · obtain ⟨h1, h2⟩ := h
    refine ⟨h1, fun P hP => ?_⟩
    obtain ⟨⟨t, ht, hd, hrw⟩, hm, ha, hk⟩ := h2 P hP
    exact ⟨⟨t, ht, discharges_add F e t P (hK rfl) ht hd, hrw⟩, signed_add F e P _ hm, signed_add F e P _ ha,
      killAt_add F e _ _ hk⟩
  · exact fun t ht hn => killOrExempt_add F e t (h t ht hn)
  · show ∀ b ∈ fillMarks F.branches e.marks, _
    rw [fillMarks_of_marked F.branches e.marks fun b hb => by rcases h b hb with h | h | h <;> rw [h] <;> nofun]
    exact h
  · exact h
  · exact h
  · exact h

/-- **`gate_mono` holds of the gate.**
$$\forall s\, F\, e,\ \operatorname{gate}(s, F) = \mathrm{pass} \Rightarrow \operatorname{gate}(s, F + e) = \mathrm{pass}$$
More evidence never refuses a land that passed. -/
theorem GateMono_impl : GateMono gate := by
  intro s F e h
  rw [PassIff_impl] at h ⊢
  obtain ⟨h1, h2⟩ := h
  refine ⟨?_, fun r hr he => ruleOk_add F e r (fun hr' => ?_) (h2 r hr he)⟩
  · rcases h1 with ⟨a, b, c⟩ | h1
    · exact Or.inl ⟨by simp [Facts.add, a], by simp [Facts.add, b], by simp [Facts.add, c.1], c.2.1, c.2.2⟩
    · exact Or.inr h1
  · subst hr'
    exact h2 .kills (mem_all _) (kills_of_props s F.leanFirst he)

/-- **`stage_mono` holds of the gate.**
$$\forall s\, s'\, F,\ \operatorname{rank}(s) \le \operatorname{rank}(s') \Rightarrow \operatorname{gate}(s', F) = \mathrm{pass} \Rightarrow \operatorname{gate}(s, F) = \mathrm{pass}$$
A stricter stage refuses a superset. -/
theorem StageMono_impl : StageMono gate := by
  intro s s' F hle h
  rw [PassIff_impl] at h ⊢
  obtain ⟨h1, h2⟩ := h
  refine ⟨?_, fun r hr he => h2 r hr (enforced_mono s s' _ r hle he)⟩
  rcases h1 with h1 | h1
  · exact Or.inl h1
  · refine Or.inr fun r hr => ?_
    cases hx : enforced s F.leanFirst r
    · rfl
    · have := h1 r hr
      rw [enforced_mono s s' _ r hle hx] at this
      exact absurd this (by decide)

/-! ## The baseline -/

/-- A pair in the baseline whose name has no other hash is what `lookup` finds.
$$\forall B\, n\, h,\ (n, h) \in B \Rightarrow (\forall p \in B,\ p.1 = n \Rightarrow p.2 = h) \Rightarrow \operatorname{lookup}(B, n) = \mathrm{some}(h)$$ -/
theorem lookup_of_mem (B : List (String × String)) (n h : String) (hm : (n, h) ∈ B)
    (hu : ∀ p ∈ B, p.1 = n → p.2 = h) : B.lookup n = some h := by
  induction B with
  | nil => simp at hm
  | cons a B ih =>
    obtain ⟨k, v⟩ := a
    rw [List.lookup_cons]
    by_cases hk : n = k
    · subst hk
      simp only [BEq.rfl]
      exact congrArg some (hu (n, v) (List.mem_cons_self ..) rfl)
    · have hb : (n == k) = false := by simpa using hk
      rw [hb]
      refine ih ?_ fun p hp => hu p (List.mem_cons_of_mem _ hp)
      rcases List.mem_cons.1 hm with h' | h'
      · exact absurd (Prod.mk.inj h').1 hk
      · exact h'

/-- What `lookup` finds is a pair of the list.
$$\forall B\, n\, h,\ \operatorname{lookup}(B, n) = \mathrm{some}(h) \Rightarrow (n, h) \in B$$ -/
theorem mem_of_lookup (B : List (String × String)) (n h : String) (hl : B.lookup n = some h) : (n, h) ∈ B := by
  induction B with
  | nil => simp at hl
  | cons a B ih =>
    obtain ⟨k, v⟩ := a
    rw [List.lookup_cons] at hl
    by_cases hk : n = k
    · subst hk
      simp only [BEq.rfl, Option.some.injEq] at hl
      subst hl
      exact List.mem_cons_self ..
    · have hb : (n == k) = false := by simpa using hk
      rw [hb] at hl
      exact List.mem_cons_of_mem _ (ih hl)

/-- **`baseline_not_new` holds of `isNew`.**
$$\forall F\, t,\ (t.\mathit{name}, t.\mathit{hash}) \in F.\mathit{baseline} \Rightarrow (\forall p \in F.\mathit{baseline},\ p.1 = t.\mathit{name} \Rightarrow p.2 = t.\mathit{hash}) \Rightarrow \operatorname{new}(F, t) = \mathrm{false}$$
An unchanged old theorem is not gated. -/
theorem BaselineNotNew_impl : BaselineNotNew isNew := by
  intro F t hm hu
  simp [isNew, lookup_of_mem F.baseline t.name t.hash hm hu]

/-- **`changed_is_new` holds of `isNew`.**
$$\forall F\, t,\ (t.\mathit{name}, t.\mathit{hash}) \notin F.\mathit{baseline} \Rightarrow \operatorname{new}(F, t) = \mathrm{true}$$
An edit to an old theorem's statement is gated like a new theorem. -/
theorem ChangedIsNew_impl : ChangedIsNew isNew := by
  intro F t hm
  rw [isNew_iff]
  exact fun hl => hm (mem_of_lookup F.baseline t.name t.hash hl)

end Fw.Ops.LeanFirst

