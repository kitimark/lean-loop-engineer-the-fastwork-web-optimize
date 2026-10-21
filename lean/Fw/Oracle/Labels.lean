/-! # Label rules and the held-out split of the Jev replay sets (task `jev-datasets`)
Standalone: imports no other Fw module. -/
namespace Fw.Oracle.Labels

/-- FNV-1a 32-bit offset basis. -/
def fnvOffset : Nat := 2166136261

/-- FNV-1a 32-bit prime. -/
def fnvPrime : Nat := 16777619

/-- FNV-1a 32-bit hash of the UTF-8 bytes of a row id. -/
def fnv1a (s : String) : Nat :=
  s.toUTF8.data.toList.foldl (fun h b => ((h ^^^ b.toNat) * fnvPrime) % 4294967296) fnvOffset

/-- One row in `splitMod` is held out. -/
def splitMod : Nat := 4

/-- The row id is in the held-out side. -/
def heldOut (id : String) : Bool := fnv1a id % splitMod == 0

/-- The row id is in the calibration side. -/
def calibration (id : String) : Bool := !heldOut id

def heldOutRows {α : Type} (key : α → String) (rows : List α) : List α := rows.filter (heldOut ∘ key)

def calibrationRows {α : Type} (key : α → String) (rows : List α) : List α := rows.filter (calibration ∘ key)

theorem split_exclusive (id : String) : heldOut id = !calibration id := by
  simp [calibration]

theorem mem_heldOutRows {α : Type} (key : α → String) (rows : List α) (r : α) :
    r ∈ heldOutRows key rows ↔ r ∈ rows ∧ heldOut (key r) = true := by
  simp [heldOutRows]

theorem mem_calibrationRows {α : Type} (key : α → String) (rows : List α) (r : α) :
    r ∈ calibrationRows key rows ↔ r ∈ rows ∧ heldOut (key r) = false := by
  simp [calibrationRows, calibration]

theorem split_disjoint {α : Type} (key : α → String) (rows : List α) (r : α) :
    r ∈ heldOutRows key rows → r ∉ calibrationRows key rows := by
  intro h h'
  rw [mem_heldOutRows] at h
  rw [mem_calibrationRows] at h'
  have := h.2
  have := h'.2
  simp_all

theorem split_complete {α : Type} (key : α → String) (rows : List α) :
    (heldOutRows key rows).length + (calibrationRows key rows).length = rows.length := by
  induction rows with
  | nil => simp [heldOutRows, calibrationRows]
  | cons r t ih =>
    simp only [heldOutRows, calibrationRows] at ih ⊢
    by_cases h : heldOut (key r) = true <;> simp [calibration, h] <;> omega

/-- The mistake classes of the incident ledger and the mistake retro ledger. -/
def mistakeClasses : List String :=
  ["c-orphan-wait", "c-order-derived", "c-shared-no-lock", "c-quota", "c-proxy-verdict", "c-identity-heuristic",
   "c-late-check", "c-unearned-claim", "c-sample-validity", "c-env-assume", "c-spec-gap", "c-handcopy",
   "c-policy-prose", "c-mathdoc", "c-principle"]

/-- D1 label: the ledger class when it is a known class, else none. -/
def d1Label (cls : String) : Option String := if mistakeClasses.contains cls then some cls else none

theorem d1Label_known (c : String) (h : mistakeClasses.contains c = true) : d1Label c = some c := by
  unfold d1Label
  rw [h]
  simp

theorem d1Label_unknown (c : String) (h : mistakeClasses.contains c = false) : d1Label c = none := by
  unfold d1Label
  rw [h]
  simp

/-- The review severity grades of the pinned unit. -/
inductive Grade where
  | blocker
  | fixBeforeLand
  | followUp
  deriving DecidableEq, Repr

/-- Whether the grade vocabulary was the written one or a legacy word mapped onto it. -/
inductive Tier where
  | exact
  | legacy
  deriving DecidableEq, Repr

def wordTable : List (String × Grade) :=
  [("blocker", .blocker), ("blocking", .blocker), ("critical", .blocker), ("high", .blocker),
   ("fix-before-land", .fixBeforeLand), ("major", .fixBeforeLand),
   ("follow-up", .followUp), ("low", .followUp), ("minor", .followUp), ("nit", .followUp)]

/-- The words that are the written grade vocabulary. -/
def exactWords : List String := ["blocker", "fix-before-land", "follow-up"]

/-- The pattern occurs as a run of the characters. -/
def hasInfix (p l : List Char) : Bool := (List.range (l.length + 1)).any fun i => p.isPrefixOf (l.drop i)

/-- The explicit follow-up tag a reviewer writes in parentheses. -/
def followTag : String := "follow-up"

/-- Text lower-cased without surrounding whitespace, as characters. -/
def lowerTrim (s : String) : List Char :=
  let l := s.toList.map Char.toLower
  ((l.dropWhile Char.isWhitespace).reverse.dropWhile Char.isWhitespace).reverse

def headWord (l : List Char) : List Char := l.takeWhile (fun c => c.isAlpha || c == '-')

/-- The grade of a bare word. -/
def wordGrade (w : List Char) : Option Grade := (wordTable.find? (fun p => p.1.toList == w)).map (·.2)

/-- D2 label from a reviewer severity text: an explicit follow-up tag wins, else the leading word's grade. -/
def severity (s : String) : Option (Grade × Tier) :=
  let l := lowerTrim s
  let g? := if hasInfix followTag.toList l then some Grade.followUp else wordGrade (headWord l)
  g?.map fun g => (g, if exactWords.any (·.toList == l) then Tier.exact else Tier.legacy)

/-- The grade is inside the pinned unit. -/
def inUnit (g : Grade) : Bool := g != .followUp

theorem inUnit_iff (g : Grade) : inUnit g = true ↔ g ≠ .followUp := by
  simp [inUnit]

theorem severity_follow_tag (s : String) (h : hasInfix followTag.toList (lowerTrim s) = true) :
    (severity s).map (·.1) = some .followUp := by
  simp [severity, h]

theorem severity_word (s : String) (h : hasInfix followTag.toList (lowerTrim s) = false) :
    (severity s).map (·.1) = wordGrade (headWord (lowerTrim s)) := by
  simp [severity, h, Option.map_map, Function.comp_def]

theorem severity_none (s : String) (h : hasInfix followTag.toList (lowerTrim s) = false)
    (hw : wordGrade (headWord (lowerTrim s)) = none) : severity s = none := by
  simp [severity, h, hw]

theorem severity_blocker : severity "blocker" = some (.blocker, .exact) := by decide

theorem severity_fix_before_land : severity "fix-before-land" = some (.fixBeforeLand, .exact) := by decide

theorem severity_follow_up : severity "follow-up" = some (.followUp, .exact) := by decide

theorem severity_high : severity "High" = some (.blocker, .legacy) := by decide

theorem severity_major : severity "major (blocking)" = some (.fixBeforeLand, .legacy) := by decide

theorem severity_medium : severity "medium" = none := by decide

/-- A later grade replacing the reviewer's: another grade, or the finding dismissed. -/
inductive Regrade where
  | grade (g : Grade)
  | dismissed
  deriving DecidableEq, Repr

/-- The label after a regrade: no regrade keeps the reviewer's grade, a dismissed finding has none. -/
def applyRegrade (orig : Option Grade) : Option Regrade → Option Grade
  | none => orig
  | some (.grade g) => some g
  | some .dismissed => none

theorem applyRegrade_none (o : Option Grade) : applyRegrade o none = o := rfl

theorem applyRegrade_grade (o : Option Grade) (g : Grade) : applyRegrade o (some (.grade g)) = some g := rfl

theorem applyRegrade_dismissed (o : Option Grade) : applyRegrade o (some .dismissed) = none := rfl

/-- Phrases of a Fable classification line that dismiss the reviewer's finding. -/
def dismissPhrases : List String := ["reviewer error", "rule noise"]

/-- Phrases of a Fable classification line that demote the finding to a follow-up. -/
def lowValuePhrases : List String := ["low value", "real, low"]

/-- The lower-cased text contains any phrase. -/
def hasPhrase (phrases : List String) (text : String) : Bool :=
  let t := text.toList.map Char.toLower
  phrases.any fun p => hasInfix (p.toList.map Char.toLower) t

/-- The regrade a Fable classification line gives: dismissal first, then demotion, else none. -/
def fableRegrade (line : String) : Option Regrade :=
  if hasPhrase dismissPhrases line then some .dismissed
  else if hasPhrase lowValuePhrases line then some (.grade .followUp)
  else none

theorem fableRegrade_dismiss (line : String) (h : hasPhrase dismissPhrases line = true) :
    fableRegrade line = some .dismissed := by
  simp [fableRegrade, h]

theorem fableRegrade_demote (line : String) (h : hasPhrase dismissPhrases line = false)
    (h' : hasPhrase lowValuePhrases line = true) : fableRegrade line = some (.grade .followUp) := by
  simp [fableRegrade, h, h']

theorem fableRegrade_none (line : String) (h : hasPhrase dismissPhrases line = false)
    (h' : hasPhrase lowValuePhrases line = false) : fableRegrade line = none := by
  simp [fableRegrade, h, h']

/-- Classification lines apply to a round's findings by position, only when their number equals the findings'. -/
def regradeApplies (nFindings nParsed : Nat) : Bool := 0 < nParsed && nFindings == nParsed

theorem regradeApplies_count (a b : Nat) (h : a ≠ b) : regradeApplies a b = false := by
  simp [regradeApplies, h]

/-- The causes of a CI failure. -/
inductive Cause where
  | ours
  | flake
  | infra
  deriving DecidableEq, Repr

/-- What is known of one failed run. -/
structure CiFacts where
  failure : Bool
  logKnown : Bool
  covered : Bool
  passedSameSha : Bool
  infraSig : Bool
  codeSig : Bool
  deriving DecidableEq, Repr

/-- Log phrases of an environment fault: network, runner, disk, registry. -/
def infraPhrases : List String :=
  ["ssl connect error", "could not download file", "econnreset", "etimedout", "enotfound", "econnrefused",
   "connection reset", "connection timed out", "could not resolve host", "shutdown signal",
   "no space left on device", "lost communication with the server", "502 bad gateway", "503 service unavailable",
   "rate limit", "unable to make request", "unexpected eof", "socket hang up", "unable to boot", "tls handshake"]

/-- Log phrases of a deterministic fault in our code or its checks. -/
def codePhrases : List String :=
  ["assertionerror", "err_module_not_found", "cannot find module", "syntaxerror", "referenceerror", "typeerror",
   "error ts", "unknown identifier", "type mismatch", "unsolved goals", "premises: failed", "trajectory-line: refused",
   "verdict fail", "verdict refuse", "verdict stale", "not ok "]

/-- D3 label: infra when only an environment phrase shows. -/
def ciCause (f : CiFacts) : Option Cause :=
  if !f.failure || !f.logKnown then none
  else if f.infraSig && !f.codeSig then some .infra
  else if !f.covered then none
  else if f.passedSameSha then some .flake
  else if f.codeSig && !f.infraSig then some .ours
  else none

theorem ciCause_not_failure (f : CiFacts) (h : f.failure = false) : ciCause f = none := by
  simp [ciCause, h]

theorem ciCause_no_log (f : CiFacts) (h : f.logKnown = false) : ciCause f = none := by
  simp [ciCause, h]

theorem ciCause_infra (f : CiFacts) (hf : f.failure = true) (hl : f.logKnown = true) (hi : f.infraSig = true)
    (hc : f.codeSig = false) : ciCause f = some .infra := by
  simp [ciCause, hf, hl, hi, hc]

theorem ciCause_uncovered (f : CiFacts) (h : f.covered = false) : ciCause f = none ∨ ciCause f = some .infra := by
  unfold ciCause
  by_cases h1 : (!f.failure || !f.logKnown) = true
  · simp [h1]
  · by_cases h2 : (f.infraSig && !f.codeSig) = true
    · simp [h1, h2]
    · simp [h1, h2, h]

theorem ciCause_flake (f : CiFacts) (hf : f.failure = true) (hl : f.logKnown = true) (hcov : f.covered = true)
    (hp : f.passedSameSha = true) (hn : (f.infraSig && !f.codeSig) = false) : ciCause f = some .flake := by
  simp [ciCause, hf, hl, hcov, hp, hn]

theorem ciCause_ours (f : CiFacts) (hf : f.failure = true) (hl : f.logKnown = true) (hcov : f.covered = true)
    (hp : f.passedSameSha = false) (hc : f.codeSig = true) (hi : f.infraSig = false) :
    ciCause f = some .ours := by
  simp [ciCause, hf, hl, hcov, hp, hc, hi]

/-- Who an alert step was posted for. -/
inductive Audience where
  | user
  | lead
  | unset
  deriving DecidableEq, Repr

/-- How an alert step ended. -/
inductive End where
  | userActed
  | leadCancelled
  | autoResolved
  | scriptCancelled
  | open
  deriving DecidableEq, Repr

/-- The triage decisions of a watch alert. -/
inductive Triage where
  | ignore
  | mitigate
  | askUser
  deriving DecidableEq, Repr

/-- D4 label: the audience decides when set; otherwise how the step ended, and a restart text means the lead mitigates. -/
def alertTriage (a : Audience) (e : End) (restartText : Bool) : Option Triage :=
  match a with
  | .user => some .askUser
  | .lead => some .mitigate
  | .unset =>
    match e with
    | .userActed => some .askUser
    | .autoResolved => some .mitigate
    | .leadCancelled => some .ignore
    | .scriptCancelled => if restartText then some .mitigate else none
    | .open => none

theorem alertTriage_user (e : End) (r : Bool) : alertTriage .user e r = some .askUser := rfl

theorem alertTriage_lead (e : End) (r : Bool) : alertTriage .lead e r = some .mitigate := rfl

theorem alertTriage_unset_user (r : Bool) : alertTriage .unset .userActed r = some .askUser := rfl

theorem alertTriage_unset_lead (r : Bool) : alertTriage .unset .leadCancelled r = some .ignore := rfl

theorem alertTriage_unset_auto (r : Bool) : alertTriage .unset .autoResolved r = some .mitigate := rfl

theorem alertTriage_unset_script (r : Bool) :
    alertTriage .unset .scriptCancelled r = if r then some .mitigate else none := by
  cases r <;> rfl

theorem alertTriage_unset_open (r : Bool) : alertTriage .unset .open r = none := rfl

end Fw.Oracle.Labels
