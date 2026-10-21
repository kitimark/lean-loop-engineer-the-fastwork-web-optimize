import Fw.Oracle.Core
import Fw.Oracle.Redact
import Fw.Oracle.Body
/-! Whether one oracle question goes out: replay, refuse or send. -/
namespace Fw.Oracle

/-- The spend guard: calls per UTC day, and calls per calibration run. -/
structure Budget where
  dailyCap : Nat := 200
  runCap : Nat := 60
deriving Repr, DecidableEq

/-- The default spend guard: 200 calls a day, 60 per calibration run. -/
def defaultBudget : Budget := {}

def callsOn (today : String) (days : List String) : Nat := (days.filter (· == today)).length

/-! ## The gate -/

/-- **A declared state**: every field is one the question declares. -/
def declared (q : Question) (st : State) : Bool := st.all fun (k, _) => q.fields.contains k


def bodyCap : Nat := 65536

/-- The send decision: replay a logged answer, refuse with a failure, or send exactly the given body. -/
inductive Pre where
  | replay
  | refuse (f : Failure)
  | send (body : String)
deriving Repr, DecidableEq

/-- **The send gate.** Logged: replay. -/
def pre (bud : Budget) (q : Question) (names : List String) (st : State) (logged : Bool) (today : String)
    (days : List String) (ρ : Option Nat) : Pre :=
  if logged then .replay
  else if !declared q st then .refuse .undeclared
  else
    let st' := redactState names st
    let body := bodyText q st'
    if !isRedacted names st' then .refuse .unredacted
    else if bodyCap < bytes body then .refuse .tooLarge
    else if bud.dailyCap ≤ callsOn today days then .refuse .overBudget
    else match ρ with
      | some c => if bud.runCap ≤ c then .refuse .overBudget else .send body
      | none => .send body

theorem pre_logged (bud : Budget) (q : Question) (names : List String) (st : State) (today : String) (days : List String) (ρ : Option Nat) :
    pre bud q names st true today days ρ = .replay := rfl

theorem pre_send (bud : Budget) (q : Question) (names : List String) (st : State)
    (logged : Bool) (today : String) (days : List String)
    (ρ : Option Nat) (body : String) (h : pre bud q names st logged today days ρ = .send body) :
    logged = false ∧ declared q st = true ∧ body = bodyText q (redactState names st) ∧
      isRedacted names (redactState names st) = true ∧ bytes body ≤ bodyCap ∧
      callsOn today days < bud.dailyCap ∧ ∀ c, ρ = some c → c < bud.runCap := by
  unfold pre at h
  cases logged with
  | true => simp at h
  | false =>
    simp only [Bool.false_eq_true, ↓reduceIte] at h
    by_cases hs : declared q st = true
    · by_cases hr : isRedacted names (redactState names st) = true
      · by_cases hb : bodyCap < bytes (bodyText q (redactState names st))
        · simp [hs, hr, hb] at h
        · by_cases hd : bud.dailyCap ≤ callsOn today days
          · simp [hs, hr, hb, hd] at h
          · cases ρ with
            | none =>
              simp [hs, hr, hb, hd] at h
              subst h
              exact ⟨rfl, hs, rfl, hr, Nat.le_of_not_lt hb, Nat.lt_of_not_le hd, fun _ hc => by simp at hc⟩
            | some c =>
              by_cases hc : bud.runCap ≤ c
              · simp [hs, hr, hb, hd, hc] at h
              · simp [hs, hr, hb, hd, hc] at h
                subst h
                exact ⟨rfl, hs, rfl, hr, Nat.le_of_not_lt hb, Nat.lt_of_not_le hd, fun c' hc' => by
                  simp at hc'; subst hc'; exact Nat.lt_of_not_le hc⟩
      · simp [hs, hr] at h
    · simp [hs] at h

theorem body_from_lean (bud : Budget) (q : Question) (names : List String) (st : State)
    (logged : Bool) (today : String) (days : List String)
    (ρ : Option Nat) (body : String) (h : pre bud q names st logged today days ρ = .send body) :
    body = bodyText q (redactState names st) :=
  (pre_send bud q names st logged today days ρ body h).2.2.1

theorem capState_keys : ∀ (b : Nat) (S : List (String × List String)), (capState b S).map Prod.fst = S.map Prod.fst
  | _, [] => by simp [capState]
  | b, (k, L) :: S => by simp [capState, capState_keys _ S]

theorem send_fields (bud : Budget) (q : Question) (names : List String) (st : State)
    (logged : Bool) (today : String) (days : List String)
    (ρ : Option Nat) (body : String) (h : pre bud q names st logged today days ρ = .send body) :
    ∀ kl ∈ redactState names st, kl.1 ∈ q.fields := by
  intro kl hkl
  have hk : kl.1 ∈ (redactState names st).map Prod.fst := List.mem_map.mpr ⟨kl, hkl, rfl⟩
  simp only [redactState, capState_keys, List.map_map] at hk
  obtain ⟨kl0, h0, he⟩ := List.mem_map.mp hk
  have hs := (pre_send bud q names st logged today days ρ body h).2.1
  simp only [declared, List.all_eq_true, List.contains_iff_mem] at hs
  simp only [Function.comp_apply] at he
  rw [← he]; exact hs kl0 h0

theorem send_no_home (bud : Budget) (q : Question) (names : List String) (st : State)
    (logged : Bool) (today : String) (days : List String)
    (ρ : Option Nat) (body : String) (h : pre bud q names st logged today days ρ = .send body) :
    ∀ kl ∈ redactState names st, ∀ x ∈ kl.2, ∀ p ∈ homePrefixes, ∀ u v : List Char, x.toList ≠ u ++ p ++ v :=
  redacted_no_home names _ (pre_send bud q names st logged today days ρ body h).2.2.2.1

theorem send_caps (bud : Budget) (q : Question) (names : List String) (st : State)
    (logged : Bool) (today : String) (days : List String)
    (ρ : Option Nat) (body : String) (h : pre bud q names st logged today days ρ = .send body) :
    (∀ kl ∈ redactState names st, ∀ x ∈ kl.2, x.length ≤ lineCap) ∧ stateBytes (redactState names st) ≤ stateCap ∧
      bytes body ≤ bodyCap :=
  have hp := pre_send bud q names st logged today days ρ body h
  ⟨(redacted_caps names _ hp.2.2.2.1).1, (redacted_caps names _ hp.2.2.2.1).2, hp.2.2.2.2.1⟩

#guard declared ciTriage [("job", ["a"]), ("log", ["x", "y"])]
#guard !declared ciTriage [("note", ["a"])]
#guard pre defaultBudget ciTriage [] [("log", ["/Users/x/y"])] false "d" [] none ==
  .send (bodyText ciTriage [("log", ["~/y"])])
#guard pre defaultBudget ciTriage [] [("note", ["a"])] false "d" [] none == .refuse .undeclared
#guard pre defaultBudget ciTriage [] [("note", ["a"])] true "d" [] none == .replay
#guard pre { dailyCap := 2 } ciTriage [] [] false "d" ["d", "e", "d"] none == .refuse .overBudget
#guard pre { dailyCap := 3 } ciTriage [] [] false "d" ["d", "e", "d"] none == .send (bodyText ciTriage [])
#guard pre defaultBudget ciTriage [] [] false "d" [] (some 60) == .refuse .overBudget
#guard pre defaultBudget ciTriage [] [] false "d" [] (some 59) == .send (bodyText ciTriage [])

/-! ## The replay run (`fw oracle send`) -/

/-- The caps of one `fw oracle send` run, on top of the daily cap. -/
structure RunBudget where
  maxRequests : Nat := 60
  maxInputTokens : Nat := 400000
deriving Repr, DecidableEq

/-- The default run guard: 60 sends and 400 000 estimated input tokens. -/
def defaultRunBudget : RunBudget := {}

/-- The input tokens a body counts as before sending: its UTF-8 bytes. -/
def estTokens (body : String) : Nat := bytes body

/-- The run has room for one more send of `body`. -/
def runOk (rb : RunBudget) (sent spent : Nat) (body : String) : Bool :=
  decide (sent < rb.maxRequests) && decide (spent + estTokens body ≤ rb.maxInputTokens)

/-- The send gate of a replay run: `pre`, and a send only when `runOk`. -/
def preRun (bud : Budget) (rb : RunBudget) (q : Question) (names : List String) (st : State) (logged : Bool)
    (today : String) (days : List String) (sent spent : Nat) : Pre :=
  match pre bud q names st logged today days none with
  | .send body => if runOk rb sent spent body then .send body else .refuse .overBudget
  | p => p

theorem preRun_send (bud : Budget) (rb : RunBudget) (q : Question) (names : List String) (st : State)
    (logged : Bool) (today : String) (days : List String) (sent spent : Nat) (body : String)
    (h : preRun bud rb q names st logged today days sent spent = .send body) :
    pre bud q names st logged today days none = .send body ∧ sent < rb.maxRequests ∧
      spent + estTokens body ≤ rb.maxInputTokens := by
  unfold preRun at h
  split at h
  · rename_i b hb
    by_cases hr : runOk rb sent spent b = true
    · simp only [hr, ite_true, Pre.send.injEq] at h
      subst h
      simp only [runOk, Bool.and_eq_true, decide_eq_true_eq] at hr
      exact ⟨hb, hr.1, hr.2⟩
    · simp [hr] at h
  · rename_i p hp
    exact absurd h (by intro e; exact hp body e)

theorem preRun_body (bud : Budget) (rb : RunBudget) (q : Question) (names : List String) (st : State)
    (logged : Bool) (today : String) (days : List String) (sent spent : Nat) (body : String)
    (h : preRun bud rb q names st logged today days sent spent = .send body) :
    body = bodyText q (redactState names st) :=
  body_from_lean bud q names st logged today days none body (preRun_send bud rb q names st logged today days sent
    spent body h).1

theorem preRun_requests_full (bud : Budget) (rb : RunBudget) (q : Question) (names : List String) (st : State)
    (logged : Bool) (today : String) (days : List String) (spent : Nat) (body : String) :
    preRun bud rb q names st logged today days rb.maxRequests spent ≠ .send body := by
  intro h
  exact Nat.lt_irrefl _ (preRun_send bud rb q names st logged today days _ spent body h).2.1

theorem preRun_tokens_over (bud : Budget) (rb : RunBudget) (q : Question) (names : List String) (st : State)
    (logged : Bool) (today : String) (days : List String) (sent spent : Nat) (body : String)
    (ho : rb.maxInputTokens < spent + estTokens body) :
    preRun bud rb q names st logged today days sent spent ≠ .send body := by
  intro h
  exact Nat.lt_irrefl _ (Nat.lt_of_lt_of_le ho (preRun_send bud rb q names st logged today days sent spent body h).2.2)

theorem preRun_logged (bud : Budget) (rb : RunBudget) (q : Question) (names : List String) (st : State)
    (today : String) (days : List String) (sent spent : Nat) :
    preRun bud rb q names st true today days sent spent = .replay := rfl

#guard preRun defaultBudget defaultRunBudget ciTriage [] [] false "d" [] 59 0 == .send (bodyText ciTriage [])
#guard preRun defaultBudget defaultRunBudget ciTriage [] [] false "d" [] 60 0 == .refuse .overBudget
#guard preRun defaultBudget defaultRunBudget ciTriage [] [] false "d" [] 0 400000 == .refuse .overBudget
#guard preRun defaultBudget defaultRunBudget ciTriage [] [("note", ["a"])] false "d" [] 0 0 == .refuse .undeclared
#guard preRun { dailyCap := 1 } defaultRunBudget ciTriage [] [] false "d" ["d"] 0 0 == .refuse .overBudget
#guard preRun defaultBudget defaultRunBudget ciTriage [] [] true "d" [] 60 400000 == .replay

/-! ## The calibration run -/

/-- The ids of the labeled entries of a replay file, in file order. -/
def labeledIds {α : Type} (es : List (α × Bool)) : List α :=
  es.filterMap fun (i, lab) => if lab then some i else none

#guard labeledIds [("a", true), ("b", false), ("c", true)] == ["a", "c"]
#guard labeledIds ([] : List (String × Bool)) == []

/-- May a calibration run write its thresholds? Only when the labeled ids. -/
def mayWrite (split answered : List String) : Bool :=
  !split.isEmpty && decide split.Nodup && split.all (answered.contains ·)

theorem mayWrite_sound (split answered : List String) (h : mayWrite split answered = true) :
    split ≠ [] ∧ split.Nodup ∧ ∀ i ∈ split, i ∈ answered := by
  simp only [mayWrite, Bool.and_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff, decide_eq_true_eq,
    List.all_eq_true, List.contains_iff_mem] at h
  exact ⟨h.1.1, h.1.2, h.2⟩

theorem unanswered_no_write (split answered : List String) (i : String) (hi : i ∈ split) (hn : i ∉ answered) :
    mayWrite split answered = false := by
  cases hw : mayWrite split answered with
  | false => rfl
  | true => exact absurd ((mayWrite_sound split answered hw).2.2 i hi) hn

theorem empty_no_write (answered : List String) : mayWrite [] answered = false := rfl

#guard mayWrite ["a", "b"] ["b", "a", "c"]
#guard !mayWrite ["a", "b"] ["a"]
#guard !mayWrite [] ["a"]
#guard !mayWrite ["a", "a"] ["a"]

/-- The number of rows not in the answer log (each needs one send). -/
def missing (logged : List Bool) : Nat := (logged.filter (!·)).length

/-- Resume check (`fw oracle calibrate --resume`). -/
def resumable (runCap : Nat) (logged : List Bool) : Bool := decide (missing logged ≤ runCap)

theorem missing_take_lt : ∀ (logged : List Bool) (i : Nat), logged[i]? = some false →
    missing (logged.take i) < missing logged
  | [], _, h => by simp at h
  | g :: gs, 0, h => by simp at h; subst h; simp [missing]
  | g :: gs, i + 1, h => by
    have := missing_take_lt gs i (by simpa using h)
    cases g <;> simp_all [missing]

theorem resume_within_cap (runCap : Nat) (logged : List Bool) (h : resumable runCap logged = true) (i : Nat)
    (hi : logged[i]? = some false) : missing (logged.take i) < runCap := by
  have := missing_take_lt logged i hi
  simp only [resumable, decide_eq_true_eq] at h
  omega

#guard resumable 60 (List.replicate 60 true ++ List.replicate 10 false)
#guard !resumable 60 (List.replicate 70 false)

end Fw.Oracle
