import Fw.Oracle.Core
import Fw.Oracle.Redact
import Fw.Oracle.Body
/-!
# Fw.Oracle.Send: whether one oracle question goes out (replay, refuse or send), and what is sent

Before any network call (and before the client reads the API key) the client asks `pre` (the `oracle.pre` op). An
answer already in the answer log (keyed by the sha256 of the exact request body) is replayed with no call. Otherwise
every field of the state must be one the question declares (`Question.fields`, an allow-list of names; any other
field is refused as `undeclared`). `pre` then redacts the state itself (`redactState`), builds the request bytes
`bodyText q (redactState N S)` (at most `bodyCap` UTF-8 bytes, else `tooLarge`), applies the daily and run caps, and
returns the body with `send`, so the client sends exactly a string Lean built (`body_from_lean`).

What the gate cannot check: where the client got the state's text. Which texts are public enough to send is the
caller's choice in this module; a provenance check per field is a later task.

The calibration run (`fw oracle calibrate`) writes its table only when every labeled id has an answer (`mayWrite`);
the ids come from Lean (`labeledIds`), and `--resume` sends only when the rows missing from the answer log fit in the
run cap (`resume_within_cap`).
-/
namespace Fw.Oracle

/-- The spend guard: calls per UTC day, and calls per calibration run. -/
structure Budget where
  dailyCap : Nat := 200
  runCap : Nat := 60
deriving Repr, DecidableEq

/-- The default spend guard: 200 calls a day, 60 per calibration run. -/
def defaultBudget : Budget := {}

/-- The calls already made on day `today`, counted from the answer log's call dates. -/
def callsOn (today : String) (days : List String) : Nat := (days.filter (· == today)).length

/-! ## The gate -/

/-- **A declared state**: every field is one the question declares. -/
def declared (q : Question) (st : State) : Bool := st.all fun (k, _) => q.fields.contains k


/-- The most UTF-8 bytes a request body may have (64 KiB). -/
def bodyCap : Nat := 65536

/-- The send decision: replay a logged answer, refuse with a failure, or send exactly the given body. -/
inductive Pre where
  | replay
  | refuse (f : Failure)
  | send (body : String)
deriving Repr, DecidableEq

/-- **The send gate.** Logged: replay. A field the question does not declare: refuse. Otherwise, with the redacted
state and its body (the first check that fails decides): not redacted (never, `redactState_redacted`; a second layer)
refuse; body over 64 KiB refuse; daily cap reached refuse over budget; in a calibration run (`ρ = some c`) with `c`
calls made, refuse over budget once `c` reaches the run cap; else send `b`. -/
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

/-- **A logged question is replayed exactly, with no call.** -/
theorem pre_logged (bud : Budget) (q : Question) (names : List String) (st : State) (today : String) (days : List String) (ρ : Option Nat) :
    pre bud q names st true today days ρ = .replay := rfl

/-- **What a send certifies**: not logged, every field declared, the body is the one Lean builds from the redacted
state, that state redacted, the body at most 64 KiB, under the daily cap, and under the run cap of a calibration
run. -/
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

/-- **The body sent is the one Lean builds**: from the question and the redacted state, nothing the client wrote. -/
theorem body_from_lean (bud : Budget) (q : Question) (names : List String) (st : State)
    (logged : Bool) (today : String) (days : List String)
    (ρ : Option Nat) (body : String) (h : pre bud q names st logged today days ρ = .send body) :
    body = bodyText q (redactState names st) :=
  (pre_send bud q names st logged today days ρ body h).2.2.1

/-- Capping keeps the field names, in order. -/
theorem capState_keys : ∀ (b : Nat) (S : List (String × List String)), (capState b S).map Prod.fst = S.map Prod.fst
  | _, [] => by simp [capState]
  | b, (k, L) :: S => by simp [capState, capState_keys _ S]

/-- **Only declared field names are sent**: every field of the redacted state in a sent body is one the question
declares (the names are constants of this repository). -/
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

/-- **A sent state holds no home path** (`/Users/`, `/home/`, `\Users\`, `-Users-`) in any line. -/
theorem send_no_home (bud : Budget) (q : Question) (names : List String) (st : State)
    (logged : Bool) (today : String) (days : List String)
    (ρ : Option Nat) (body : String) (h : pre bud q names st logged today days ρ = .send body) :
    ∀ kl ∈ redactState names st, ∀ x ∈ kl.2, ∀ p ∈ homePrefixes, ∀ u v : List Char, x.toList ≠ u ++ p ++ v :=
  redacted_no_home names _ (pre_send bud q names st logged today days ρ body h).2.2.2.1

/-- **A send is within the size caps**: every line of the redacted state at most 500 characters, its lines at most
32 KiB in total, and the body at most 64 KiB, all in UTF-8 bytes where bytes are meant. -/
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

/-! ## The calibration run -/

/-- The ids of the labeled entries of a replay file, in file order. An entry is `(id, labeled)`; an id may be of any
type (`oracle.plan` also takes row positions). -/
def labeledIds {α : Type} (es : List (α × Bool)) : List α :=
  es.filterMap fun (i, lab) => if lab then some i else none

#guard labeledIds [("a", true), ("b", false), ("c", true)] == ["a", "c"]
#guard labeledIds ([] : List (String × Bool)) == []

/-- **May a calibration run write its thresholds?** Only when the labeled ids (from `labeledIds`, both parts of the
split) are not empty, have no repeated id, and every one of them has an answer row: a refused row (the run cap cut the
set, or a field was undeclared), a missing key or a failed call leaves the result printed but not written. -/
def mayWrite (split answered : List String) : Bool :=
  !split.isEmpty && decide split.Nodup && split.all (answered.contains ·)

/-- **Written thresholds saw every row of the split answered.** -/
theorem mayWrite_sound (split answered : List String) (h : mayWrite split answered = true) :
    split ≠ [] ∧ split.Nodup ∧ ∀ i ∈ split, i ∈ answered := by
  simp only [mayWrite, Bool.and_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff, decide_eq_true_eq,
    List.all_eq_true, List.contains_iff_mem] at h
  exact ⟨h.1.1, h.1.2, h.2⟩

/-- **An unanswered id of the split blocks the write.** -/
theorem unanswered_no_write (split answered : List String) (i : String) (hi : i ∈ split) (hn : i ∉ answered) :
    mayWrite split answered = false := by
  cases hw : mayWrite split answered with
  | false => rfl
  | true => exact absurd ((mayWrite_sound split answered hw).2.2 i hi) hn

/-- **An empty split writes nothing.** -/
theorem empty_no_write (answered : List String) : mayWrite [] answered = false := rfl

#guard mayWrite ["a", "b"] ["b", "a", "c"]
#guard !mayWrite ["a", "b"] ["a"]
#guard !mayWrite [] ["a"]
#guard !mayWrite ["a", "a"] ["a"]

/-- The number of rows not in the answer log (each needs one send). -/
def missing (logged : List Bool) : Nat := (logged.filter (!·)).length

/-- **Resume check** (`fw oracle calibrate --resume`): one run completes when the rows missing from the answer log
fit in the run cap. -/
def resumable (runCap : Nat) (logged : List Bool) : Bool := decide (missing logged ≤ runCap)

/-- The rows missing before a missing row are fewer than all missing rows. -/
theorem missing_take_lt : ∀ (logged : List Bool) (i : Nat), logged[i]? = some false →
    missing (logged.take i) < missing logged
  | [], _, h => by simp at h
  | g :: gs, 0, h => by simp at h; subst h; simp [missing]
  | g :: gs, i + 1, h => by
    have := missing_take_lt gs i (by simpa using h)
    cases g <;> simp_all [missing]

/-- **A resumable run is never cut by the run cap**: when the missing rows fit in the cap, every missing row is
asked with fewer than `r` calls made before it (logged rows replay and cost no call), so the gate's run cap never
refuses it. -/
theorem resume_within_cap (runCap : Nat) (logged : List Bool) (h : resumable runCap logged = true) (i : Nat)
    (hi : logged[i]? = some false) : missing (logged.take i) < runCap := by
  have := missing_take_lt logged i hi
  simp only [resumable, decide_eq_true_eq] at h
  omega

#guard resumable 60 (List.replicate 60 true ++ List.replicate 10 false)
#guard !resumable 60 (List.replicate 70 false)

end Fw.Oracle
