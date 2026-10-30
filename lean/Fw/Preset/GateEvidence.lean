import Lean.Data.Json
import Fw.Preset.V2Proved
/-!
Breakpoint-gate evidence of preset members: the gate runs on record, the flag set each member entered its preset with, and
the rule that marks a member proved, pending (a named waiver) or unproved (the preset check fails).
-/
namespace Fw.Preset.GateEvidence
open Lean Fw.Preset

/-- A breakpoint-gate engine job: `chromium` or `playwright-webkit`. -/
inductive Engine | chromium | webkit
deriving DecidableEq, Repr

inductive Verdict | pass | fail
deriving DecidableEq, Repr

/-- One engine verdict of one breakpoint-gate run as its merge job printed it; `flags` is the run's exact `?fw=` set. -/
structure GateRun where
  run : Nat
  sha : String
  engine : Engine
  flags : List String
  verdict : Verdict
deriving DecidableEq, Repr

/-- The flag set `set` a preset held at `commit`, the commit that first wrote `flag` into it. -/
structure Admission where
  preset : String
  flag : Flag
  commit : String
  set : List String
deriving DecidableEq, Repr

/-- A member kept without gate evidence, with the reason the report shows. -/
structure Waiver where
  preset : String
  flag : Flag
  reason : String
deriving DecidableEq, Repr

def sameSet (a b : List String) : Bool := a.all b.contains && b.all a.contains

def onSet (rs : List GateRun) (s : List String) (e : Engine) : List GateRun :=
  rs.filter fun r => r.engine == e && sameSet r.flags s

def newest (rs : List GateRun) (s : List String) (e : Engine) : Option GateRun :=
  (onSet rs s e).find? fun r => (onSet rs s e).all fun q => decide (q.run ≤ r.run)

/-- The run id of the newest run of exactly set `s` on engine `e`, when that run passes. -/
def passOn (rs : List GateRun) (s : List String) (e : Engine) : Option Nat :=
  match newest rs s e with
  | some r => if r.verdict == .pass then some r.run else none
  | none => none

def admissionOf (ads : List Admission) (p : String) (f : Flag) : Option Admission :=
  ads.find? fun a => a.preset == p && a.flag == f

def waiverOf (ws : List Waiver) (p : String) (f : Flag) : Option String :=
  (ws.find? fun w => w.preset == p && w.flag == f).map (·.reason)

inductive Status
  | proved (chromium webkit : Nat)
  | pending (reason : String)
  | unproved (why : String)
deriving DecidableEq, Repr

/-- **The member rule**: proved when the newest gate run of exactly the admission set passes on both engines, else
pending when waived, else unproved; a member without an admission row, or whose admission set lacks it, is unproved. -/
def status (rs : List GateRun) (ads : List Admission) (ws : List Waiver) (p : String) (f : Flag) : Status :=
  match admissionOf ads p f with
  | none => .unproved s!"{p} {f.key}: no admission row"
  | some a =>
    if !a.set.contains f.key then .unproved s!"{p} {f.key}: admission set {a.set} lacks the member"
    else
      match passOn rs a.set .chromium, passOn rs a.set .webkit with
      | some c, some w => .proved c w
      | _, _ =>
        match waiverOf ws p f with
        | some r => .pending r
        | none => .unproved s!"{p} {f.key}: no passing breakpoint-gate run on both engines for {a.set}"

def isProved : Status → Bool
  | .proved _ _ => true
  | _ => false

/-- The preset check's objections for the members `ms` (preset, flag): unproved members, waivers and admissions of
non-members, waivers of proved members. -/
def problems (rs : List GateRun) (ads : List Admission) (ws : List Waiver) (ms : List (String × Flag)) : List String :=
  let isMember (p : String) (f : Flag) := ms.contains (p, f)
  (ms.filterMap fun (p, f) => match status rs ads ws p f with
    | .unproved why => some why
    | _ => none) ++
  (ws.filterMap fun w =>
    if !isMember w.preset w.flag then some s!"waiver for non-member {w.preset} {w.flag.key}"
    else if isProved (status rs ads ws w.preset w.flag) then some s!"waiver for proved member {w.preset} {w.flag.key}"
    else none) ++
  (ads.filterMap fun a =>
    if isMember a.preset a.flag then none else some s!"admission for non-member {a.preset} {a.flag.key}")

/-! ## The tables -/

def unthrottle : Flag := ⟨"engine.scroll", "unthrottle"⟩
def threaded : Flag := ⟨"hero.exit", "threaded"⟩
def fadedPause : Flag := ⟨"platform", "faded-pause"⟩

private def both (run : Nat) (sha : String) (flags : List String) (c w : Verdict) : List GateRun :=
  [⟨run, sha, .chromium, flags, c⟩, ⟨run, sha, .webkit, flags, w⟩]

/-- Every breakpoint-gate run on record for a preset member's flags. -/
def runs : List GateRun :=
  both 39774976109 "ff8c8cd1b80e296f59841614188d60996101604b" [threaded.key] .pass .fail ++
  both 40101370753 "0bd2a50c6687b99b952582a9c0a09209e8e56303" [unthrottle.key] .pass .pass ++
  both 40287895072 "5a82a546382d094f207d594dea0ef0da10afbbce" [fadedPause.key] .pass .pass ++
  both 41078004214 "72d0bfd916caf73bbeca9f4bea77702872cbda55" [unthrottle.key, threaded.key] .pass .fail ++
  both 41086902481 "31fdd85b60679a991ea0450a26d7138e3b27aa5b" [] .pass .pass ++
  both 41087718575 "31fdd85b60679a991ea0450a26d7138e3b27aa5b" [threaded.key] .pass .fail

/-- The admission of every member of `v2-proved` and `shipped`, read from the history of their golden files. -/
def admissions : List Admission :=
  [⟨"v2-proved", unthrottle, "8dae67ead587a268d3c5d49f6624bd2f6cf0af7a", [unthrottle.key]⟩,
   ⟨"v2-proved", threaded, "d6174ba8cf7ce14eaf48c0e9c652404750d181c2", [unthrottle.key, threaded.key]⟩,
   ⟨"v2-proved", fadedPause, "6f307554ec5c7f7a0d8ba5f538a050c9d665661b",
     [unthrottle.key, threaded.key, fadedPause.key]⟩,
   ⟨"shipped", unthrottle, "fb2934b2e80bb2d73ed731dffbc237afb639cb60", [unthrottle.key, threaded.key]⟩,
   ⟨"shipped", threaded, "fb2934b2e80bb2d73ed731dffbc237afb639cb60", [unthrottle.key, threaded.key]⟩,
   ⟨"shipped", fadedPause, "9446c6407979428b95b12371586d8418ceae6f66",
     [unthrottle.key, threaded.key, fadedPause.key]⟩]

def threadedReason : String := "webkit gate fail 41087718575; user decision step threaded-look"

def fadedReason : String :=
  "no breakpoint-gate run of its admission set, which holds hero.exit:threaded; fw=platform:faded-pause alone passes \
    both engines in 40287895072; user decision step threaded-look"

/-- The members admitted before this rule that lack gate evidence. -/
def waivers : List Waiver :=
  [⟨"v2-proved", threaded, threadedReason⟩,
   ⟨"v2-proved", fadedPause, fadedReason⟩,
   ⟨"shipped", unthrottle,
     "webkit gate fail 41078004214 on its admission set, which holds hero.exit:threaded; user decision step threaded-look"⟩,
   ⟨"shipped", threaded, threadedReason⟩,
   ⟨"shipped", fadedPause, fadedReason⟩]

/-- Gate verdicts of `runs`, `admissions` and `waivers` for the members `ms`. -/
def statuses (ms : List (String × Flag)) : List ((String × Flag) × Status) :=
  ms.map fun (p, f) => ((p, f), status runs admissions waivers p f)

def engineWord : Engine → String
  | .chromium => "chromium"
  | .webkit => "playwright-webkit"

def verdictWord : Verdict → String
  | .pass => "pass"
  | .fail => "fail"

def statusWord : Status → String
  | .proved .. => "proved"
  | .pending _ => "pending"
  | .unproved _ => "unproved"

def runJson (r : GateRun) : Json :=
  Json.mkObj [("run", r.run), ("sha", .str r.sha), ("engine", .str (engineWord r.engine)),
    ("flags", toJson r.flags), ("verdict", .str (verdictWord r.verdict))]

/-- The console row of one member: its status, its admission, the proving run ids or the reason, and every recorded run
whose flag set holds it. -/
def memberJson (rs : List GateRun) (ads : List Admission) (ws : List Waiver) (p : String) (f : Flag) : Json :=
  let st := status rs ads ws p f
  let adm : Json := match admissionOf ads p f with
    | some a => Json.mkObj [("commit", .str a.commit), ("set", toJson a.set)]
    | none => .null
  let proving : Json := match st with
    | .proved c w => Json.mkObj [("chromium", c), ("playwright-webkit", w)]
    | _ => .null
  let reason : Json := match st with
    | .pending r | .unproved r => .str r
    | .proved .. => .null
  Json.mkObj [("preset", .str p), ("flag", .str f.key), ("status", .str (statusWord st)), ("admission", adm),
    ("runs", proving), ("reason", reason),
    ("related", .arr ((rs.filter (·.flags.contains f.key)).map runJson).toArray)]

def membersText (rs : List GateRun) (ads : List Admission) (ws : List Waiver) (ms : List (String × Flag)) : String :=
  String.join (ms.map fun (p, f) => (memberJson rs ads ws p f).compress ++ "\n")

/-- The report line of one member. -/
def reportLine (rs : List GateRun) (ads : List Admission) (ws : List Waiver) (p : String) (f : Flag) : String :=
  match status rs ads ws p f with
  | .proved c w => s!"gate evidence: {p} {f.key} proved (chromium run:{c}, playwright-webkit run:{w})"
  | .pending r => s!"gate evidence: {p} {f.key} pending ({r})"
  | .unproved r => s!"gate evidence: {p} {f.key} unproved ({r})"

/-! ## Theorems -/

theorem passOn_some {rs : List GateRun} {s : List String} {e : Engine} {n : Nat} (h : passOn rs s e = some n) :
    ∃ r ∈ rs, r.run = n ∧ r.engine = e ∧ sameSet r.flags s = true ∧ r.verdict = .pass ∧
      ∀ q ∈ rs, q.engine = e → sameSet q.flags s = true → q.run ≤ r.run := by
  unfold passOn newest at h
  split at h
  · rename_i r hr
    have hm := List.mem_of_find?_eq_some hr
    have hall := List.find?_some hr
    simp only [onSet, List.mem_filter, Bool.and_eq_true, beq_iff_eq] at hm
    simp only [List.all_eq_true, decide_eq_true_eq, onSet, List.mem_filter, Bool.and_eq_true, beq_iff_eq] at hall
    by_cases hv : r.verdict = .pass
    · simp only [hv, beq_self_eq_true, ↓reduceIte, Option.some.injEq] at h
      exact ⟨r, hm.1, h, hm.2.1, hm.2.2, hv, fun q hq he hs => hall q ⟨hq, he, hs⟩⟩
    · simp [hv] at h
  · simp at h

/-- A member without an admission row is unproved. -/
theorem status_of_no_admission {rs : List GateRun} {ads : List Admission} {ws : List Waiver} {p : String} {f : Flag}
    (h : admissionOf ads p f = none) : status rs ads ws p f = .unproved s!"{p} {f.key}: no admission row" := by
  simp [status, h]

/-- A member whose admission set lacks it is unproved. -/
theorem status_of_lacks {rs : List GateRun} {ads : List Admission} {ws : List Waiver} {p : String} {f : Flag}
    {a : Admission} (h : admissionOf ads p f = some a) (hl : f.key ∉ a.set) :
    status rs ads ws p f = .unproved s!"{p} {f.key}: admission set {a.set} lacks the member" := by
  simp [status, h, hl]

/-- A member whose admission set's newest gate run passes on both engines is proved. -/
theorem status_of_pass {rs : List GateRun} {ads : List Admission} {ws : List Waiver} {p : String} {f : Flag}
    {a : Admission} {c w : Nat} (h : admissionOf ads p f = some a) (hc : f.key ∈ a.set)
    (hpc : passOn rs a.set .chromium = some c) (hpw : passOn rs a.set .webkit = some w) :
    status rs ads ws p f = .proved c w := by
  simp [status, h, hc, hpc, hpw]

/-- A waived member without a passing pair is pending with the waiver's reason. -/
theorem status_of_waiver {rs : List GateRun} {ads : List Admission} {ws : List Waiver} {p : String} {f : Flag}
    {a : Admission} {r : String} (h : admissionOf ads p f = some a) (hc : f.key ∈ a.set)
    (hn : passOn rs a.set .chromium = none ∨ passOn rs a.set .webkit = none) (hw : waiverOf ws p f = some r) :
    status rs ads ws p f = .pending r := by
  rcases hn with hn | hn <;> simp [status, h, hc, hn, hw] <;> split <;> simp_all

/-- An unwaived member without a passing pair is unproved. -/
theorem status_of_no_waiver {rs : List GateRun} {ads : List Admission} {ws : List Waiver} {p : String} {f : Flag}
    {a : Admission} (h : admissionOf ads p f = some a) (hc : f.key ∈ a.set)
    (hn : passOn rs a.set .chromium = none ∨ passOn rs a.set .webkit = none) (hw : waiverOf ws p f = none) :
    status rs ads ws p f = .unproved s!"{p} {f.key}: no passing breakpoint-gate run on both engines for {a.set}" := by
  rcases hn with hn | hn <;> simp [status, h, hc, hn, hw] <;> split <;> simp_all

/-- **Proved means gate evidence**: the member has an admission row whose set holds it, and on each engine the newest
run of exactly that set passes. -/
theorem proved_evidence {rs : List GateRun} {ads : List Admission} {ws : List Waiver} {p : String} {f : Flag}
    {c w : Nat} (h : status rs ads ws p f = .proved c w) :
    ∃ a ∈ ads, a.preset = p ∧ a.flag = f ∧ f.key ∈ a.set ∧
      (∃ r ∈ rs, r.run = c ∧ r.engine = .chromium ∧ sameSet r.flags a.set = true ∧ r.verdict = .pass ∧
        ∀ q ∈ rs, q.engine = .chromium → sameSet q.flags a.set = true → q.run ≤ r.run) ∧
      (∃ r ∈ rs, r.run = w ∧ r.engine = .webkit ∧ sameSet r.flags a.set = true ∧ r.verdict = .pass ∧
        ∀ q ∈ rs, q.engine = .webkit → sameSet q.flags a.set = true → q.run ≤ r.run) := by
  unfold status at h
  split at h
  · cases h
  · rename_i a ha
    have hm := List.mem_of_find?_eq_some ha
    have hk := List.find?_some ha
    simp only [Bool.and_eq_true, beq_iff_eq] at hk
    by_cases hc : a.set.contains f.key = true
    · simp only [hc, Bool.not_true, Bool.false_eq_true, ↓reduceIte] at h
      split at h
      · rename_i c' w' hpc hpw
        simp only [Status.proved.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨a, hm, hk.1, hk.2, List.contains_iff_mem.mp hc, passOn_some hpc, passOn_some hpw⟩
      · split at h <;> cases h
    · have hn : f.key ∉ a.set := by simpa using hc
      simp [hn] at h

/-- **No admission row, not proved.** -/
theorem not_proved_of_no_admission {rs : List GateRun} {ads : List Admission} {ws : List Waiver} {p : String}
    {f : Flag} (h : ∀ a ∈ ads, a.preset = p → a.flag ≠ f) : isProved (status rs ads ws p f) = false := by
  have : admissionOf ads p f = none := by
    simp only [admissionOf, List.find?_eq_none, Bool.and_eq_true, beq_iff_eq, not_and]
    exact h
  simp [status_of_no_admission this, isProved]

theorem passOn_none_of_no_run {rs : List GateRun} {s : List String} {e : Engine}
    (hr : ∀ r ∈ rs, sameSet r.flags s = false) : passOn rs s e = none := by
  cases h : passOn rs s e with
  | none => rfl
  | some n =>
    obtain ⟨r, hr', _, _, hs, _⟩ := passOn_some h
    simp [hr r hr'] at hs

/-- **No gate run, not proved**: a member whose admission set has no recorded run is not proved. -/
theorem not_proved_of_no_run {rs : List GateRun} {ads : List Admission} {ws : List Waiver} {p : String} {f : Flag}
    {a : Admission} (h : admissionOf ads p f = some a) (hr : ∀ r ∈ rs, sameSet r.flags a.set = false) :
    isProved (status rs ads ws p f) = false := by
  have hn : passOn rs a.set .chromium = none ∨ passOn rs a.set .webkit = none := .inl (passOn_none_of_no_run hr)
  by_cases hc : f.key ∈ a.set
  · cases hw : waiverOf ws p f with
    | none => simp [status_of_no_waiver h hc hn hw, isProved]
    | some r => simp [status_of_waiver h hc hn hw, isProved]
  · simp [status_of_lacks h hc, isProved]

/-- **A new member without evidence fails the preset check**: a member that is neither proved nor waived makes
`problems` non-empty. -/
theorem problems_of_unproved {rs : List GateRun} {ads : List Admission} {ws : List Waiver} {ms : List (String × Flag)}
    {p : String} {f : Flag} {why : String} (hm : (p, f) ∈ ms) (h : status rs ads ws p f = .unproved why) :
    problems rs ads ws ms ≠ [] := by
  intro he
  simp only [problems, List.append_eq_nil_iff, List.filterMap_eq_nil_iff] at he
  have := he.1.1 (p, f) hm
  simp [h] at this

/-- A member with no admission row fails the preset check, whatever the waivers. -/
theorem problems_of_no_admission {rs : List GateRun} {ads : List Admission} {ws : List Waiver}
    {ms : List (String × Flag)} {p : String} {f : Flag} (hm : (p, f) ∈ ms) (h : admissionOf ads p f = none) :
    problems rs ads ws ms ≠ [] :=
  problems_of_unproved hm (status_of_no_admission h)

/-- An unwaived member with an admission row but no passing pair fails the preset check. -/
theorem problems_of_no_pass {rs : List GateRun} {ads : List Admission} {ws : List Waiver} {ms : List (String × Flag)}
    {p : String} {f : Flag} {a : Admission} (hm : (p, f) ∈ ms) (h : admissionOf ads p f = some a)
    (hc : f.key ∈ a.set) (hn : passOn rs a.set .chromium = none ∨ passOn rs a.set .webkit = none)
    (hw : waiverOf ws p f = none) : problems rs ads ws ms ≠ [] :=
  problems_of_unproved hm (status_of_no_waiver h hc hn hw)

/-- The waived members are exactly the five admitted before the rule. -/
theorem waivers_pinned : waivers.map (fun w => (w.preset, w.flag.key)) =
    [("v2-proved", "hero.exit:threaded"), ("v2-proved", "platform:faded-pause"),
     ("shipped", "engine.scroll:unthrottle"), ("shipped", "hero.exit:threaded"),
     ("shipped", "platform:faded-pause")] := by decide

/-! ## Examples -/

private def members : List (String × Flag) :=
  [("v2-proved", unthrottle), ("v2-proved", threaded), ("v2-proved", fadedPause),
   ("shipped", unthrottle), ("shipped", threaded), ("shipped", fadedPause)]

#guard status runs admissions waivers "v2-proved" unthrottle == .proved 40101370753 40101370753
#guard status runs admissions waivers "v2-proved" threaded == .pending threadedReason
#guard status runs admissions waivers "v2-proved" fadedPause == .pending fadedReason
#guard status runs admissions waivers "shipped" threaded == .pending threadedReason
#guard problems runs admissions waivers members == []
#guard problems runs admissions waivers (members ++ [("v2-proved", ⟨"nav.earn", "x"⟩)]) ==
  ["v2-proved nav.earn:x: no admission row"]
#guard problems runs admissions waivers (members.take 5) ==
  ["waiver for non-member shipped platform:faded-pause", "admission for non-member shipped platform:faded-pause"]
#guard (problems runs admissions [] members).length == 5
#guard problems runs (admissions ++ [⟨"v2-proved", ⟨"nav.earn", "x"⟩, "0", ["engine.scroll:unthrottle"]⟩]) waivers
  (members ++ [("v2-proved", ⟨"nav.earn", "x"⟩)]) ==
  ["v2-proved nav.earn:x: admission set [engine.scroll:unthrottle] lacks the member"]
#guard reportLine runs admissions waivers "v2-proved" unthrottle ==
  "gate evidence: v2-proved engine.scroll:unthrottle proved (chromium run:40101370753, playwright-webkit run:40101370753)"
#guard reportLine runs admissions waivers "v2-proved" threaded ==
  "gate evidence: v2-proved hero.exit:threaded pending (webkit gate fail 41087718575; user decision step threaded-look)"
#guard ((memberJson runs admissions waivers "shipped" threaded).getObjValAs? String "status").toOption == some "pending"
#guard ((memberJson runs admissions waivers "shipped" threaded).getObjValAs? (Array Json) "related").toOption.map (·.size)
  == some 6
#guard passOn runs [threaded.key] .webkit == none
#guard passOn runs [threaded.key] .chromium == some 41087718575
#guard passOn runs [fadedPause.key] .webkit == some 40287895072
#guard passOn (runs ++ [⟨41100000000, "x", .webkit, [threaded.key], .pass⟩]) [threaded.key] .webkit == some 41100000000
#guard passOn (runs ++ [⟨41000000000, "x", .webkit, [threaded.key], .pass⟩]) [threaded.key] .webkit == none
#guard sameSet [threaded.key, unthrottle.key] [unthrottle.key, threaded.key]
#guard !sameSet [threaded.key] [unthrottle.key, threaded.key]

end Fw.Preset.GateEvidence
