import Lean.Data.Json
import Fw.Device.PhoneArms
/-!
# The phone thermal check: when a block of visits may start and when it must pause

The state is read as iOS exposes it: the Thermal State instrument of `xctrace` over USB, which reports the system
thermal state (Nominal, Fair, Serious, Critical). The battery temperature is a proxy that backs it up. A locked phone is a named
refusal, not a harness fault.
-/
namespace Fw.Device.Thermal
open Lean
open Fw.Device.PhoneArms (coolOk coolMin)

inductive Thermal where
  | nominal | fair | serious | critical
  deriving DecidableEq

def Thermal.name : Thermal → String
  | .nominal => "Nominal" | .fair => "Fair" | .serious => "Serious" | .critical => "Critical"

/-- The state named as the instrument prints it; any other text is unreadable. -/
def Thermal.ofName : String → Option Thermal
  | "Nominal" => some .nominal | "Fair" => some .fair | "Serious" => some .serious | "Critical" => some .critical
  | _ => none

theorem ofName_name (t : Thermal) : Thermal.ofName t.name = some t := by
  cases t <;> rfl

/-- Degrees Celsius above the session's first battery readout at which a block pauses. -/
def tempMarginC : Nat := 2

inductive Lock where
  | unlocked | locked | unknown
  deriving DecidableEq

def Lock.name : Lock → String
  | .unlocked => "unlocked" | .locked => "locked" | .unknown => "unknown"

/-- `devicectl device info lockState` reports `passcodeRequired`; true is read as a locked phone (INFERRED from the field name),
a missing field is unknown and does not refuse. -/
def lockOf : Option Bool → Lock
  | some true => .locked
  | some false => .unlocked
  | none => .unknown

inductive Verdict where
  | go
  | locked
  | thermal
  | battery
  | unreadable
  deriving DecidableEq

def Verdict.name : Verdict → String
  | .go => "go" | .locked => "locked" | .thermal => "thermal" | .battery => "battery" | .unreadable => "unreadable"

/-- Whether a visit may start now: the state is readable and nominal, and the battery is under the first readout plus the margin
(an unreadable battery or no first readout cannot raise the second trigger). -/
def gate (th : Option Thermal) (temp first : Option Nat) : Verdict :=
  match th with
  | none => .unreadable
  | some t =>
    if t ≠ .nominal then .thermal
    else match temp, first with
      | some c, some f => if f + tempMarginC ≤ c then .battery else .go
      | _, _ => .go

/-- The check before a block: a locked phone is refused first, then the gate. -/
def preflight (lock : Lock) (th : Option Thermal) (temp first : Option Nat) : Verdict :=
  if lock = .locked then .locked else gate th temp first

theorem gate_unreadable (temp first : Option Nat) : gate none temp first = .unreadable := rfl

theorem gate_fair (temp first : Option Nat) : gate (some .fair) temp first = .thermal := by
  simp [gate]

theorem gate_serious (temp first : Option Nat) : gate (some .serious) temp first = .thermal := by
  simp [gate]

theorem gate_critical (temp first : Option Nat) : gate (some .critical) temp first = .thermal := by
  simp [gate]

theorem gate_battery {c f : Nat} (h : f + tempMarginC ≤ c) : gate (some .nominal) (some c) (some f) = .battery := by
  simp [gate, h]

theorem gate_go {c f : Nat} (h : c < f + tempMarginC) : gate (some .nominal) (some c) (some f) = .go := by
  have : ¬ f + tempMarginC ≤ c := by omega
  simp [gate, this]

theorem gate_go_blind (temp first : Option Nat) (h : temp = none ∨ first = none) : gate (some .nominal) temp first = .go := by
  rcases h with rfl | rfl
  · cases first <;> simp [gate]
  · cases temp <;> simp [gate]

theorem gate_go_iff (th : Option Thermal) (temp first : Option Nat) :
    gate th temp first = .go ↔ th = some .nominal ∧ ∀ c f, temp = some c → first = some f → c < f + tempMarginC := by
  cases th with
  | none => simp [gate]
  | some t =>
    cases t <;> simp [gate]
    cases temp <;> cases first <;> simp

theorem preflight_locked (th : Option Thermal) (temp first : Option Nat) : preflight .locked th temp first = .locked := by
  simp [preflight]

theorem preflight_open {lock : Lock} (h : lock ≠ .locked) (th : Option Thermal) (temp first : Option Nat) :
    preflight lock th temp first = gate th temp first := by
  simp [preflight, h]

/-- A pass starts only on a `go` reading, so a block runs as many passes as it has leading `go` readings. -/
def passesRun : List Verdict → Nat
  | [] => 0
  | .go :: rs => passesRun rs + 1
  | _ :: _ => 0

theorem passesRun_nil : passesRun [] = 0 := rfl

theorem passesRun_all_go : ∀ rs : List Verdict, (∀ v ∈ rs, v = .go) → passesRun rs = rs.length
  | [], _ => rfl
  | r :: rs, h => by
    have hr : r = .go := h r (by simp)
    subst hr
    have := passesRun_all_go rs (fun v hv => h v (by simp [hv]))
    simp [passesRun, this]

/-- A reading that is not `go` at index `k` stops the block before pass `k`: pass `k` and everything after it never start. -/
theorem passesRun_le_stop : ∀ (rs : List Verdict) (k : Nat) (v : Verdict), rs[k]? = some v → v ≠ .go → passesRun rs ≤ k
  | [], k, v, h, _ => by simp at h
  | r :: rs, 0, v, h, hv => by
    simp at h
    subst h
    cases r <;> simp_all [passesRun]
  | r :: rs, k + 1, v, h, hv => by
    have ih := passesRun_le_stop rs k v (by simpa using h) hv
    cases r <;> simp [passesRun] <;> omega

/-- The passes of a block whose readings (state, battery) come before each pass. -/
def blockPasses (rd : List (Option Thermal × Option Nat)) (first : Option Nat) : Nat :=
  passesRun (rd.map fun r => gate r.1 r.2 first)

theorem blockPasses_le_serious {rd : List (Option Thermal × Option Nat)} {first : Option Nat} {k : Nat} {c : Option Nat}
    (h : rd[k]? = some (some .serious, c)) : blockPasses rd first ≤ k := by
  refine passesRun_le_stop _ k .thermal (by simp [h, gate]) (by decide)

theorem blockPasses_le_critical {rd : List (Option Thermal × Option Nat)} {first : Option Nat} {k : Nat} {c : Option Nat}
    (h : rd[k]? = some (some .critical, c)) : blockPasses rd first ≤ k := by
  refine passesRun_le_stop _ k .thermal (by simp [h, gate]) (by decide)

/-- The first reading that trips the rule is taken at the end of the pass in progress (index `k`, so pass `k - 1`): at most one
pass runs after the trigger, because every reading from `k` on is not `go` only needs the first of them. -/
theorem blockPasses_one_after_trigger {rd : List (Option Thermal × Option Nat)} {first : Option Nat} {k : Nat} {r : Option Thermal × Option Nat}
    (h : rd[k]? = some r) (hv : gate r.1 r.2 first ≠ .go) : blockPasses rd first ≤ k :=
  passesRun_le_stop _ k _ (by simp [h]) hv

/-- The time of the last reading that was not `go` (the pause's own start if none): a cool gap counts from there. -/
def calmFrom (p : Nat) (rs : List (Nat × Verdict)) : Nat :=
  rs.foldl (fun c r => if r.2 = .go then c else r.1) p

theorem calmFrom_snoc_bad (p t : Nat) (rs : List (Nat × Verdict)) {v : Verdict} (h : v ≠ .go) :
    calmFrom p (rs ++ [(t, v)]) = t := by
  simp [calmFrom, List.foldl_append, h]

theorem calmFrom_snoc_go (p t : Nat) (rs : List (Nat × Verdict)) :
    calmFrom p (rs ++ [(t, .go)]) = calmFrom p rs := by
  simp [calmFrom, List.foldl_append]

/-- A paused block resumes at `now` when the latest reading is `go` and the cool gap since the last reading that was not `go` is over. -/
def resume (now p : Nat) (rs : List (Nat × Verdict)) : Bool :=
  match rs.getLast? with
  | some (_, .go) => coolOk (now - calmFrom p rs)
  | _ => false

theorem resume_needs_go {now p : Nat} {rs : List (Nat × Verdict)} (h : resume now p rs = true) :
    ∃ t, rs.getLast? = some (t, .go) := by
  unfold resume at h
  split at h
  · rename_i t _; exact ⟨t, by assumption⟩
  · simp at h

theorem resume_needs_gap {now p : Nat} {rs : List (Nat × Verdict)} (h : resume now p rs = true) :
    coolMin * 60 ≤ now - calmFrom p rs := by
  unfold resume at h
  split at h
  · exact of_decide_eq_true h
  · simp at h

theorem resume_after_bad {now p t : Nat} {rs : List (Nat × Verdict)} {v : Verdict} (hv : v ≠ .go) :
    resume now p (rs ++ [(t, v)]) = false := by
  unfold resume
  simp
  cases v <;> simp_all

theorem resume_too_soon {now p : Nat} {rs : List (Nat × Verdict)} (h : now - calmFrom p rs < coolMin * 60) :
    resume now p rs = false := by
  cases hr : resume now p rs
  · rfl
  · have := resume_needs_gap hr
    omega

section Golden

private def thJ : Option Thermal → Json
  | none => Json.null
  | some t => Json.str t.name

private def natJ : Option Nat → Json
  | none => Json.null
  | some n => toJson n

private def thCases : List (Option Thermal) := [none, some .nominal, some .fair, some .serious, some .critical]

private def tempCases : List (Option Nat × Option Nat) :=
  [(none, none), (some 33, none), (none, some 33), (some 33, some 33), (some 34, some 33), (some 35, some 33), (some 36, some 33),
   (some 30, some 33), (some 0, some 0), (some 1, some 0), (some 2, some 0)]

private def readingsCases : List (List (Option Thermal × Option Nat)) :=
  [[], [(some .nominal, some 33)], [(some .nominal, some 33), (some .nominal, some 34), (some .nominal, some 34)],
   [(some .nominal, some 33), (some .fair, some 34), (some .nominal, some 33)],
   [(some .nominal, some 33), (some .nominal, some 35), (some .nominal, some 33)],
   [(some .nominal, some 33), (some .nominal, some 33), (some .serious, some 34), (some .nominal, some 33)],
   [(some .critical, some 33), (some .nominal, some 33)], [(none, some 33), (some .nominal, some 33)],
   [(some .nominal, none), (some .nominal, none)]]

private def resumeCases : List (Nat × Nat × List (Nat × Verdict)) :=
  [(100, 0, []), (400, 0, [(100, .thermal)]), (399, 0, [(100, .thermal)]), (400, 0, [(100, .thermal), (200, .go)]),
   (500, 100, [(200, .thermal), (300, .go)]), (500, 100, [(200, .thermal), (300, .battery)]), (800, 0, [(200, .thermal), (300, .go), (400, .go)]),
   (800, 0, [(200, .thermal), (300, .go), (450, .thermal), (500, .go)]), (700, 0, [(200, .thermal), (300, .go), (450, .thermal), (500, .go)]),
   (800, 0, [(200, .thermal), (300, .unreadable)]), (500, 0, [(0, .go)]), (300, 0, [(0, .go)])]

private def verdictsJ (vs : List Verdict) : Json := Json.arr (vs.map fun v => Json.str v.name).toArray

def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("tempMarginC", tempMarginC), ("coolS", (coolMin * 60 : Nat))]).compress] ++
  ([("Nominal"), "Fair", "Serious", "Critical", "nominal", "", "Unknown", "Nominal "].map fun (s : String) =>
    (Json.mkObj [("kind", "parse"), ("text", s), ("state", thJ (Thermal.ofName s))]).compress) ++
  ([some true, some false, none].map fun (b : Option Bool) =>
    (Json.mkObj [("kind", "lock"), ("passcodeRequired", match b with | none => Json.null | some x => Json.bool x), ("lock", (lockOf b).name)]).compress) ++
  (thCases.flatMap fun (th : Option Thermal) => tempCases.map fun (tf : Option Nat × Option Nat) =>
    (Json.mkObj [("kind", "gate"), ("state", thJ th), ("tempC", natJ tf.1), ("firstC", natJ tf.2), ("verdict", (gate th tf.1 tf.2).name)]).compress) ++
  ([Lock.unlocked, .locked, .unknown].flatMap fun (l : Lock) => [none, some Thermal.nominal, some .serious].map fun (th : Option Thermal) =>
    (Json.mkObj [("kind", "preflight"), ("lock", l.name), ("state", thJ th), ("tempC", natJ (some 33)), ("firstC", natJ (some 33)),
      ("verdict", (preflight l th (some 33) (some 33)).name)]).compress) ++
  (readingsCases.map fun (rd : List (Option Thermal × Option Nat)) =>
    (Json.mkObj [("kind", "block"), ("firstC", natJ (some 33)),
      ("readings", Json.arr (rd.map fun r => Json.mkObj [("state", thJ r.1), ("tempC", natJ r.2)]).toArray),
      ("verdicts", verdictsJ (rd.map fun r => gate r.1 r.2 (some 33))), ("passes", blockPasses rd (some 33))]).compress) ++
  (resumeCases.map fun (c : Nat × Nat × List (Nat × Verdict)) =>
    (Json.mkObj [("kind", "resume"), ("nowS", c.1), ("pausedS", c.2.1),
      ("readings", Json.arr (c.2.2.map fun r => Json.mkObj [("atS", r.1), ("verdict", r.2.name)]).toArray),
      ("resume", resume c.1 c.2.1 c.2.2)]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"device-thermal golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"device-thermal golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Golden

end Fw.Device.Thermal
