/-! Typed oracle questions and the proved policy over every outcome of an answer.
API facts: https://docs.typesafe.ai/api.md, https://docs.typesafe.ai/confidence.md. -/
namespace Fw.Oracle

/-! ## Questions and answers -/

/-- The answer type of an oracle question. -/
inductive Spec where
  | choice (options : List String) (noMatch : String)
  | noul
  | score (levels : List String)
deriving Repr, DecidableEq, Inhabited

/-- The tolerance on the sum of a reply's probabilities (the API returns floats that sum to 1 up to rounding). -/
def eps : Rat := 1 / 1000

/-- The probability keys a reply must carry. -/
def Spec.keys : Spec → List String
  | .choice os _ => os
  | .noul => []
  | .score ls => (List.range ls.length).map toString

/-- A well-formed question: distinct keys. -/
def Spec.wf : Spec → Bool
  | .choice os z => decide os.Nodup && os.contains z && decide (2 ≤ os.length) && decide (os.length ≤ 255)
  | .noul => true
  | .score ls => decide ((List.range ls.length).map toString).Nodup && decide (2 ≤ ls.length) &&
      decide (ls.length ≤ 10)

/-- A validated answer: the pick of a Choice with the probabilities of its options. -/
inductive Answer where
  | choice (pick : String) (dist : List Rat)
  | noul (p : Rat)
  | score (dist : List Rat)
deriving Repr, DecidableEq, Inhabited

/-- A probability lies in the closed unit interval. -/
def unit (p : Rat) : Bool := decide (0 ≤ p) && decide (p ≤ 1)

def sumOk (d : List Rat) : Bool := decide (1 - eps ≤ d.sum) && decide (d.sum ≤ 1 + eps)

def distOk (n : Nat) (d : List Rat) : Bool := d.length == n && d.all unit && sumOk d

def maxQ : List Rat → Rat
  | [] => 0
  | x :: xs => let m := maxQ xs; if x ≤ m then m else x

/-- A well-typed answer for a question. -/
def wt : Spec → Answer → Bool
  | .choice os _, .choice pk d => os.contains pk && distOk os.length d && d[os.idxOf pk]? == some (maxQ d)
  | .noul, .noul p => unit p
  | .score ls, .score d => distOk ls.length d
  | _, _ => false

/-- The answer object of a reply as the wire reads it. -/
structure Raw where
  type : String
  pick : Option String := none
  noul : Option Rat := none
  probs : List (String × Rat) := []
deriving Repr, DecidableEq

def lookupAll (l : List (String × Rat)) : List String → Option (List Rat)
  | [] => some []
  | k :: ks =>
    match l.lookup k, lookupAll l ks with
    | some v, some vs => some (v :: vs)
    | _, _ => none

def checkDist (keys : List String) (l : List (String × Rat)) : Except String (List Rat) :=
  if l.length ≠ keys.length then .error "probabilities: the keys differ from the question's" else
  match lookupAll l keys with
  | none => .error "probabilities: a key of the question is missing"
  | some d =>
    if !(d.all unit) then .error "probabilities: a value outside [0, 1]"
    else if !sumOk d then .error "probabilities: the sum is not 1 within eps"
    else .ok d

/-- Validate a raw answer against its question (the `oracle.validate` op): a schema-mismatch reason, or the typed answer. -/
def validate (s : Spec) (r : Raw) : Except String Answer :=
  if !s.wf then .error "the question is not well-formed" else
  match s with
  | .noul =>
    if r.type ≠ "noul" then .error s!"answer type {r.type}, expected noul" else
    match r.noul with
    | none => .error "noul: the probability is missing"
    | some p => if unit p then .ok (.noul p) else .error "noul: the probability is outside [0, 1]"
  | .choice os _ =>
    if r.type ≠ "choice" then .error s!"answer type {r.type}, expected choice" else
    match r.pick with
    | none => .error "choice: the pick is missing"
    | some pk =>
      if !os.contains pk then .error "choice: the pick is not an option" else
      match checkDist os r.probs with
      | .error e => .error e
      | .ok d =>
        if d[os.idxOf pk]? != some (maxQ d) then .error "choice: the pick is not the highest-probability option"
        else .ok (.choice pk d)
  | .score ls =>
    if r.type ≠ "score" then .error s!"answer type {r.type}, expected score" else
    match checkDist ((List.range ls.length).map toString) r.probs with
    | .error e => .error e
    | .ok d => .ok (.score d)

def toRaw (s : Spec) : Answer → Raw
  | .choice pk d => { type := "choice", pick := some pk, probs := s.keys.zip d }
  | .noul p => { type := "noul", noul := some p }
  | .score d => { type := "score", probs := s.keys.zip d }

/-! ### Validation is sound and complete -/

theorem lookupAll_length (l : List (String × Rat)) :
    ∀ (ks : List String) (d : List Rat), lookupAll l ks = some d → d.length = ks.length
  | [], d, h => by simp [lookupAll] at h; subst h; rfl
  | k :: ks, d, h => by
    unfold lookupAll at h
    split at h
    · rename_i v vs _ hvs
      simp at h; subst h
      simp [lookupAll_length l ks vs hvs]
    · exact absurd h (by simp)

theorem lookup_of_mem :
    ∀ (l : List (String × Rat)) (k : String) (v : Rat), (l.map Prod.fst).Nodup → (k, v) ∈ l → l.lookup k = some v
  | [], _, _, _, h => by simp at h
  | (k', v') :: t, k, v, hn, h => by
    simp only [List.map_cons, List.nodup_cons] at hn
    simp only [List.lookup_cons]
    rcases List.mem_cons.mp h with he | ht
    · simp at he; obtain ⟨rfl, rfl⟩ := he; simp
    · have hk : k ≠ k' := by
        intro hkk; subst hkk
        exact hn.1 (List.mem_map.mpr ⟨(k, v), ht, rfl⟩)
      have : (k == k') = false := by simp [hk]
      rw [this]
      exact lookup_of_mem t k v hn.2 ht

theorem lookupAll_of_sub (l : List (String × Rat)) (hn : (l.map Prod.fst).Nodup) :
    ∀ (ks : List String) (d : List Rat), ks.length = d.length → (∀ p ∈ ks.zip d, p ∈ l) → lookupAll l ks = some d
  | [], [], _, _ => rfl
  | [], _ :: _, h, _ => by simp at h
  | _ :: _, [], h, _ => by simp at h
  | k :: ks, v :: vs, h, hs => by
    simp only [List.length_cons, Nat.add_right_cancel_iff] at h
    have h1 : l.lookup k = some v := lookup_of_mem l k v hn (hs (k, v) (by simp))
    have h2 : lookupAll l ks = some vs :=
      lookupAll_of_sub l hn ks vs h fun p hp => hs p (by simp [hp])
    simp [lookupAll, h1, h2]

theorem lookupAll_zip (ks : List String) (d : List Rat) (hn : ks.Nodup) (h : ks.length = d.length) :
    lookupAll (ks.zip d) ks = some d := by
  apply lookupAll_of_sub
  · rw [List.map_fst_zip (Nat.le_of_eq h)]; exact hn
  · exact h
  · intro p hp; exact hp

theorem checkDist_sound (keys : List String) (l : List (String × Rat)) (d : List Rat)
    (h : checkDist keys l = .ok d) : distOk keys.length d = true := by
  unfold checkDist at h
  split at h
  · exact absurd h (by simp)
  · split at h
    · exact absurd h (by simp)
    · rename_i d' hd'
      split at h
      · exact absurd h (by simp)
      · split at h
        · exact absurd h (by simp)
        · rename_i hu hs
          simp at h; subst h
          simp only [Bool.not_eq_true'] at hu hs
          simp only [Bool.not_eq_false] at hu hs
          simp [distOk, lookupAll_length l keys d' hd', hu, hs]

theorem checkDist_complete (keys : List String) (d : List Rat) (hn : keys.Nodup) (h : distOk keys.length d = true) :
    checkDist keys (keys.zip d) = .ok d := by
  simp only [distOk, Bool.and_eq_true, beq_iff_eq] at h
  obtain ⟨⟨hl, hu⟩, hs⟩ := h
  have hz : (keys.zip d).length = keys.length := by simp [List.length_zip, hl]
  have hla := lookupAll_zip keys d hn hl.symm
  simp [checkDist, hz, hla, hu, hs]

theorem validate_sound (s : Spec) (r : Raw) (a : Answer) (h : validate s r = .ok a) :
    s.wf = true ∧ wt s a = true := by
  unfold validate at h
  split at h
  · exact absurd h (by simp)
  · rename_i hw
    simp only [Bool.not_eq_true', Bool.not_eq_false] at hw
    refine ⟨hw, ?_⟩
    split at h
    · split at h
      · exact absurd h (by simp)
      · split at h
        · exact absurd h (by simp)
        · split at h
          · simp at h; subst h; simp_all [wt]
          · exact absurd h (by simp)
    · rename_i os z
      split at h
      · exact absurd h (by simp)
      · split at h
        · exact absurd h (by simp)
        · rename_i pk _
          split at h
          · exact absurd h (by simp)
          · rename_i hc
            split at h
            · exact absurd h (by simp)
            · rename_i d hd
              split at h
              · exact absurd h (by simp)
              · rename_i hmax
                simp at h; subst h
                simp only [Bool.not_eq_true', Bool.not_eq_false] at hc
                have hm : pk ∈ os := by simpa using hc
                have hs := checkDist_sound os r.probs d hd
                simp only [bne_iff_ne, ne_eq, Decidable.not_not] at hmax
                simp [wt, hm, hs, hmax]
    · rename_i ls
      split at h
      · exact absurd h (by simp)
      · split at h
        · exact absurd h (by simp)
        · rename_i d hd
          simp at h; subst h
          have := checkDist_sound _ r.probs d hd
          simp at this
          simp [wt, this]

theorem validate_complete (s : Spec) (a : Answer) (hw : s.wf = true) (ht : wt s a = true) :
    validate s (toRaw s a) = .ok a := by
  cases s with
  | choice os z =>
    cases a with
    | choice pk d =>
      simp only [wt, Bool.and_eq_true] at ht
      simp only [Spec.wf, Bool.and_eq_true, decide_eq_true_eq] at hw
      have hc := checkDist_complete os d hw.1.1.1 (by simpa using ht.1.2)
      have hz : z ∈ os := by simpa using hw.1.1.2
      have hp : pk ∈ os := by simpa using ht.1.1
      have hmax : d[os.idxOf pk]? = some (maxQ d) := by simpa using ht.2
      simp [validate, toRaw, Spec.keys, Spec.wf, hw, hz, hp, hc, hmax]
    | noul _ => simp [wt] at ht
    | score _ => simp [wt] at ht
  | noul =>
    cases a with
    | noul p =>
      simp only [wt] at ht
      simp [validate, toRaw, Spec.wf, ht]
    | choice _ _ => simp [wt] at ht
    | score _ => simp [wt] at ht
  | score ls =>
    cases a with
    | score d =>
      simp only [wt] at ht
      have hw' := hw
      simp only [Spec.wf, Bool.and_eq_true, decide_eq_true_eq] at hw'
      have hc := checkDist_complete ((List.range ls.length).map toString) d hw'.1.1 (by simpa using ht)
      simp [validate, toRaw, Spec.keys, hw, hc]
    | choice _ _ => simp [wt] at ht
    | noul _ => simp [wt] at ht

#guard (validate (.choice ["flake", "real", "unknown"] "unknown")
  { type := "choice", pick := some "real", probs := [("flake", 97/100), ("real", 1/100), ("unknown", 2/100)] }) matches
  .error _
#guard (validate (.choice ["flake", "real", "unknown"] "unknown")
  { type := "choice", pick := some "real", probs := [("flake", 1/100), ("real", 2/100), ("unknown", 97/100)] }) matches
  .error _
#guard (validate (.choice ["flake", "real", "unknown"] "unknown")
  { type := "choice", pick := some "real", probs := [("flake", 1/2), ("real", 1/2), ("unknown", 0)] }).toOption ==
  some (.choice "real" [1/2, 1/2, 0])
#guard !wt (.choice ["a", "b"] "b") (.choice "a" [1/10, 9/10]) && wt (.choice ["a", "b"] "b") (.choice "b" [1/10, 9/10])

/-! ## Confidence (recomputed from the validated probabilities) -/

def absQ (q : Rat) : Rat := if q < 0 then -q else q

def argmax (d : List Rat) : Nat := d.findIdx (· == maxQ d)

/-- Σ over the list of `d_i · |i − c|` (indices from `i₀`): the probability-weighted distance from the level `c`. -/
def spread : List Rat → Rat → Nat → Rat
  | [], _, _ => 0
  | p :: ps, c, i => p * absQ ((i : Rat) - c) + spread ps c (i + 1)

def confChoice (d : List Rat) : Rat :=
  let n : Rat := d.length
  (maxQ d - 1 / n) / (1 - 1 / n)

def confScore (d : List Rat) : Rat :=
  let n := d.length
  let mad := spread (List.replicate n 1) (((n : Rat) - 1) / 2) 0 / (n : Rat)
  if mad ≤ 0 then 0 else
  let c := 1 - spread d (argmax d : Rat) 0 / mad
  if c < 0 then 0 else c

/-- The gate value of an answer: the confidence of a Choice or Score, the margin |2p − 1| of a Noul. -/
def gate : Answer → Rat
  | .choice _ d => confChoice d
  | .noul p => absQ (2 * p - 1)
  | .score d => confScore d

#guard confChoice [88/100, 12/100, 0] == 41/50
#guard confScore [0, 57/100, 43/100] == 71/200
#guard confScore [0, 1/2, 1/2] == 1/4
#guard confScore [1/2, 0, 1/2] == 0
#guard gate (.noul (95/100)) == 9/10
#guard confChoice [1/4, 1/4, 1/4, 1/4] == 0
#guard confChoice [1] == 0 && confChoice [] == 0
#guard argmax [1/10, 6/10, 3/10] == 1

/-! ## Outcomes, actions and the policy -/

/-- Why no answer came back: a timeout. -/
inductive Failure where
  | timeout
  | http (status : Nat)
  | malformed
  | schema (detail : String)
  | overBudget
  | noKey
  | unredacted
  | undeclared
  | tooLarge
deriving Repr, DecidableEq, Inhabited

/-- What one call produced: a validated answer or a failure. -/
inductive Outcome where
  | answer (a : Answer)
  | failure (f : Failure)
deriving Repr, DecidableEq

/-- The advice an oracle can give: a label only (an option, yes or no, a level index). -/
inductive Advice where
  | pick (option : String)
  | yes
  | no
  | level (i : Nat)
deriving Repr, DecidableEq, Inhabited

/-- Why an outcome escalates to a person. -/
inductive Reason where
  | failure (f : Failure)
  | uncalibrated
  | badThreshold (threshold : Rat)
  | below (gate threshold : Rat)
  | noMatch
deriving Repr, DecidableEq, Inhabited

/-- The whole action space of an oracle question: advise or escalate. -/
inductive Action where
  | advise (v : Advice)
  | escalate (r : Reason)
deriving Repr, DecidableEq, Inhabited

/-- Is the action an escalation? -/
def Action.isEscalate : Action → Bool
  | .escalate _ => true
  | .advise _ => false

/-- The advice an answer gives: the pick of a Choice, yes iff p ≥ 1/2 for a Noul, the most likely level of a Score. -/
def adviceOf : Answer → Advice
  | .choice pk _ => .pick pk
  | .noul p => if 1 / 2 ≤ p then .yes else .no
  | .score d => .level (argmax d)

/-- The answer picks the question's no-match option. -/
def isNoMatch : Spec → Answer → Bool
  | .choice _ z, .choice pk _ => pk == z
  | _, _ => false

/-- The policy (the `oracle.decide` op). -/
def policy (s : Spec) (t : Option Rat) : Outcome → Action
  | .failure f => .escalate (.failure f)
  | .answer a =>
    if !(s.wf && wt s a) then .escalate (.failure (.schema "the answer does not fit the question")) else
    match t with
    | none => .escalate .uncalibrated
    | some τ =>
      if !(decide (0 < τ) && decide (τ ≤ 1)) then .escalate (.badThreshold τ)
      else if gate a < τ then .escalate (.below (gate a) τ)
      else if isNoMatch s a then .escalate .noMatch
      else .advise (adviceOf a)

theorem policy_total (s : Spec) (t : Option Rat) (o : Outcome) :
    (∃ v, policy s t o = .advise v) ∨ (∃ r, policy s t o = .escalate r) := by
  cases h : policy s t o with
  | advise v => exact .inl ⟨v, rfl⟩
  | escalate r => exact .inr ⟨r, rfl⟩

theorem failure_escalates (s : Spec) (t : Option Rat) (f : Failure) :
    policy s t (.failure f) = .escalate (.failure f) := rfl

theorem uncalibrated_escalates (s : Spec) (o : Outcome) : ∃ r, policy s none o = .escalate r := by
  cases o with
  | failure f => exact ⟨_, rfl⟩
  | answer a =>
    by_cases hw : (s.wf && wt s a) = true <;> simp [policy, hw]

theorem escalate_below (s : Spec) (a : Answer) (τ : Rat) (h : gate a < τ) :
    ∃ r, policy s (some τ) (.answer a) = .escalate r := by
  by_cases hw : (s.wf && wt s a) = true <;> simp [policy, hw, h] <;> split <;> exact ⟨_, rfl⟩

theorem advise_sound (s : Spec) (t : Option Rat) (o : Outcome) (v : Advice) (h : policy s t o = .advise v) :
    ∃ a τ, o = .answer a ∧ t = some τ ∧ s.wf = true ∧ wt s a = true ∧ 0 < τ ∧ τ ≤ 1 ∧ τ ≤ gate a ∧
      isNoMatch s a = false ∧ v = adviceOf a := by
  cases o with
  | failure f => simp [policy] at h
  | answer a =>
    by_cases hw : (s.wf && wt s a) = true
    · simp only [Bool.and_eq_true] at hw
      cases t with
      | none => simp [policy, hw] at h
      | some τ =>
        by_cases hr : (0 < τ ∧ τ ≤ 1)
        · by_cases hg : gate a < τ
          · simp [policy, hw, hr, hg] at h
          · by_cases hn : isNoMatch s a = true
            · simp [policy, hw, hr, hg, hn] at h
            · simp [policy, hw, hr, hg, hn] at h
              exact ⟨a, τ, rfl, rfl, hw.1, hw.2, hr.1, hr.2, Rat.not_lt.mp hg, by simpa using hn, h.symm⟩
        · have : ¬(decide (0 < τ) && decide (τ ≤ 1)) = true := by simpa using hr
          simp [policy, hw, this] at h
    · simp [policy, hw] at h

theorem escalate_bad_threshold (s : Spec) (a : Answer) (τ : Rat) (h : ¬(0 < τ ∧ τ ≤ 1)) :
    ∃ r, policy s (some τ) (.answer a) = .escalate r := by
  cases hp : policy s (some τ) (.answer a) with
  | escalate r => exact ⟨r, rfl⟩
  | advise v =>
    obtain ⟨_, _, ho, ht, _, _, h0, h1, _⟩ := advise_sound s _ _ v hp
    simp at ho ht; subst ho; subst ht; exact absurd ⟨h0, h1⟩ h

/-! ## The action space holds no irreversible effect -/

/-- Every effect a tool of this repo can have on the world. -/
inductive Effect where
  | land
  | push
  | delete
  | cancel
  | kill
  | print
  | ask
deriving Repr, DecidableEq

def Effect.irreversible : Effect → Bool
  | .land | .push | .delete | .cancel | .kill => true
  | .print | .ask => false

/-- The only effect an oracle action has: an advice is printed, an escalation asks a person. -/
def Action.effect : Action → Effect
  | .advise _ => .print
  | .escalate _ => .ask

theorem action_reversible (x : Action) : x.effect.irreversible = false := by
  cases x <;> rfl

theorem never_irreversible (s : Spec) (t : Option Rat) (o : Outcome) :
    (policy s t o).effect.irreversible = false := action_reversible _

/-! ## Registered questions -/

/-- The pinned model id (aliases move; https://docs.typesafe.ai/models.md). -/
def model : String := "jev-1.13.0"

/-- A registered question: wire id. -/
structure Question where
  name : String
  instructions : String
  spec : Spec
  criteria : List (String × String)
  target : Rat
  perOption : Nat
  fields : List String
deriving Repr

end Fw.Oracle
