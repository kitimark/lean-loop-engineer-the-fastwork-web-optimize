/-!
# GitHub platform status: when Actions is down, say so

`fw watch` reads the public githubstatus summary once per pass. This module decides from it. Nothing here reads a clock.
-/

namespace Fw.Obs

/-- The state of one GitHub component; `unknown` is a failed or unreadable fetch. -/
inductive GhComp where
  | operational | degradedPerf | partialOutage | majorOutage | maintenance | unknown
deriving DecidableEq, Repr

/-- The wire name of a state. -/
def GhComp.name : GhComp → String
  | .operational => "operational" | .degradedPerf => "degraded_performance" | .partialOutage => "partial_outage"
  | .majorOutage => "major_outage" | .maintenance => "under_maintenance" | .unknown => "unknown"

/-- The state of a wire name; a name outside the five statuses is `unknown`. -/
def GhComp.ofName : String → GhComp
  | "operational" => .operational | "degraded_performance" => .degradedPerf | "partial_outage" => .partialOutage
  | "major_outage" => .majorOutage | "under_maintenance" => .maintenance | _ => .unknown

/-- The name decodes to its state. -/
theorem GhComp.ofName_name (g : GhComp) : GhComp.ofName g.name = g := by
  cases g <;> rfl

/-- An open GitHub incident: name, status, impact, creation time and time of its newest update (ms), the first 200
characters of that update, and whether it touches the Actions component.
-/
structure GhIncident where
  name      : String
  status    : String := ""
  impact    : String := ""
  createdAt : Nat := 0
  updatedAt : Nat := 0
  body      : String := ""
  actions   : Bool := false
deriving DecidableEq, Repr

/-- What the collector read: the Actions, Pages and Webhooks states, whether the previous pass left Actions flagged,
the open incidents, and the age in ms of the run list the CI facts come from (0 when this pass read it).
-/
structure Gh where
  actions      : GhComp := .unknown
  pages        : GhComp := .unknown
  webhooks     : GhComp := .unknown
  prevDegraded : Bool := false
  incidents    : List GhIncident := []
  ciAgeMs      : Nat := 0
deriving DecidableEq, Repr

/-- Whether Actions is flagged: degraded when it is not operational, clear when operational, and the previous
decision when the fetch failed.
-/
def ghOpenB (prev : Bool) : GhComp → Bool
  | .unknown => prev
  | .operational => false
  | _ => true

/-- A degraded Actions component opens the flag (each of the four non-operational states). -/
theorem ghOpenB_degraded (prev : Bool) (a : GhComp) (h1 : a ≠ .operational) (h2 : a ≠ .unknown) :
    ghOpenB prev a = true := by
  cases a <;> simp_all [ghOpenB]

/-- An operational Actions component closes the flag, whatever the previous decision was. -/
theorem ghOpenB_operational (prev : Bool) : ghOpenB prev .operational = false := rfl

/-- A failed fetch keeps the previous decision. -/
theorem ghOpenB_unknown (prev : Bool) : ghOpenB prev .unknown = prev := rfl

/-- Actions is flagged in this reading. -/
def Gh.degradedB (g : Gh) : Bool := ghOpenB g.prevDegraded g.actions

/-- The open Actions incident the alerts name: the first incident that touches Actions, only while Actions is flagged. -/
def Gh.incident (g : Gh) : Option GhIncident :=
  if g.degradedB then g.incidents.find? (·.actions) else none

/-- Without a flagged Actions there is no incident to name. -/
theorem Gh.incident_closed (g : Gh) (h : g.degradedB = false) : g.incident = none := by
  simp [Gh.incident, h]

/-- A named incident touches Actions and lies in the list. -/
theorem Gh.incident_mem (g : Gh) (i : GhIncident) (h : g.incident = some i) : i ∈ g.incidents ∧ i.actions = true := by
  unfold Gh.incident at h
  split at h
  · exact ⟨List.mem_of_find?_eq_some h, by simpa using List.find?_some h⟩
  · cases h

/-- A number below 100 as two digits. -/
def pad2 (n : Nat) : String := if n < 10 then "0" ++ toString n else toString n

/-- The UTC clock time `HH:MM` of a time in ms since the epoch. -/
def hhmm (t : Nat) : String :=
  let m := t / 60000 % 1440
  pad2 (m / 60) ++ ":" ++ pad2 (m % 60)

/-- The text a `ci.slow` detail gets while an Actions incident is open: its name and start time (empty outside one). -/
def Gh.suffix (g : Gh) : String :=
  match g.incident with
  | none => ""
  | some i => " (GitHub incident \"" ++ i.name ++ "\" since " ++ hhmm i.createdAt ++ " UTC)"

/-- Outside an open incident the suffix is empty. -/
theorem Gh.suffix_none (g : Gh) (h : g.incident = none) : g.suffix = "" := by
  simp [Gh.suffix, h]

/-- During an open incident the suffix contains its name. -/
theorem Gh.suffix_names (g : Gh) (i : GhIncident) (h : g.incident = some i) :
    ∃ a b, g.suffix = a ++ i.name ++ b := by
  refine ⟨" (GitHub incident \"", "\" since " ++ hhmm i.createdAt ++ " UTC)", ?_⟩
  simp [Gh.suffix, h, String.append_assoc]

/-- How old a run list may be before an alert says so: two watch passes of 120 s. -/
def ciFreshMs : Nat := 240000

/-- The text a `ci.slow` detail gets when its run list is older than `ciFreshMs`: the age in whole minutes. A failed
`gh run list` makes the collector carry the previous list forward, so a run that has finished since still reads as
running; the note tells the reader how old that reading is.
-/
def ciAgeNote (ageMs : Nat) : String :=
  if ageMs ≤ ciFreshMs then "" else " (CI data " ++ toString (ageMs / 60000) ++ " min old)"

/-- A run list read this pass or within `ciFreshMs` adds no note. -/
theorem ciAgeNote_fresh (a : Nat) (h : a ≤ ciFreshMs) : ciAgeNote a = "" := by
  simp [ciAgeNote, h]

/-- An older run list adds a note with its age in minutes. -/
theorem ciAgeNote_old (a : Nat) (h : ciFreshMs < a) :
    ciAgeNote a = " (CI data " ++ toString (a / 60000) ++ " min old)" := by
  have : ¬ a ≤ ciFreshMs := Nat.not_le.2 h
  simp [ciAgeNote, this]

/-- The note of this reading's run list. -/
def Gh.ciNote (g : Gh) : String := ciAgeNote g.ciAgeMs

/-- The detail of the `sys.ghDegraded` alert: the Actions state and, when one is open, the incident. -/
def Gh.detail (g : Gh) : String :=
  "Actions " ++ g.actions.name ++
    (match g.incident with | none => "" | some i => ": " ++ i.name)

end Fw.Obs
