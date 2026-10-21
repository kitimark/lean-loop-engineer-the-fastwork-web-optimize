import Fw.Console.Review
import Fw.Console.BuildsOpen
import Fw.Site.Breakpoints
/-!
# Preview a look-change review on this device and on the phone

An open look-change review (`Fw.Console.Review`) gets a Preview button. It opens the site at `main` in three views: with the
flag (`?fw=<flag key>`), the faithful rewrite (no flag), and the side-by-side compare at the flag. The views reuse the Builds
tab's main build (`BuildsOpen.mainSlot`, `BuildsOpen.path`): one build of `main` serves every arm, and the page-level hop
keeps the query.

Opening a view records `review.previewed {flag, device}` (`Fw.Console.Body.reviewPreviewed`). The device is decided here
from the viewport width the clicking page reports: phone when the width is at most the site's phone breakpoint `phoneMax`
(the `(width<=600px)` condition, `Fw.Site.Breakpoints.wLe600`), desktop otherwise. The card shows which devices were
previewed and, while one is missing, a line asking for it.
-/
namespace Fw.Console.ReviewPreview
open Fw.Preset (Flag)
open Fw.Console.Review

/-! ## Device from the viewport width -/

/-- The site's phone breakpoint in CSS px: a viewport at most this wide is a phone (the `(width<=600px)` condition). -/
def phoneMax : Nat := 600

/-- The phone breakpoint is the one edge of the site's `(width<=600px)` condition. -/
theorem phoneMax_is_wLe600 : Fw.Site.Breakpoints.wLe600.widthEdges = [phoneMax] := by decide

/-- The device a review was looked at on. -/
inductive Device | desktop | phone
deriving DecidableEq, Repr

/-- The word of a device (the event field and the wire value). -/
def Device.word : Device → String
  | .desktop => "desktop"
  | .phone => "phone"

/-- The device a word names. -/
def Device.ofWord : String → Option Device
  | "desktop" => some .desktop
  | "phone" => some .phone
  | _ => none

/-- Both devices, desktop first. -/
def devices : List Device := [.desktop, .phone]

/-- The device of a viewport width in CSS px: a phone when the width is at most `phoneMax`. -/
def deviceOf (width : Nat) : Device := if width ≤ phoneMax then .phone else .desktop

/-- **A phone at the breakpoint and below.** -/
theorem deviceOf_phone (w : Nat) (h : w ≤ phoneMax) : deviceOf w = .phone := by simp [deviceOf, h]

/-- **A desktop above the breakpoint.** -/
theorem deviceOf_desktop (w : Nat) (h : phoneMax < w) : deviceOf w = .desktop := by
  simp [deviceOf, Nat.not_le.mpr h]

/-- The device is the site's `(width<=600px)` condition at that viewport: a phone exactly when the CSS phone rules apply. -/
theorem phone_iff_wLe600 (w : Nat) :
    deviceOf w = .phone ↔ Fw.Site.Breakpoints.wLe600.eval (Fw.Site.Breakpoints.exEnv w w) = true := by
  simp [deviceOf, phoneMax, Fw.Site.Breakpoints.MQ.eval, Fw.Site.Breakpoints.wLe600,
    Fw.Site.Breakpoints.Feature.holds, Fw.Site.Breakpoints.Px.LeNat, Fw.Site.Breakpoints.exEnv,
    Fw.Site.Breakpoints.Px.ofNat]
  by_cases h : w ≤ 600 <;> simp [h]

/-- A device word round-trips. -/
theorem ofWord_word (d : Device) : Device.ofWord d.word = some d := by cases d <;> rfl

/-- Every device word is one the reducer accepts (`Fw.Console.previewDevices`). -/
theorem word_in_previewDevices (d : Device) : d.word ∈ Fw.Console.previewDevices := by
  cases d <;> decide

/-- The two classes cover every width. -/
theorem deviceOf_total (w : Nat) : deviceOf w = .phone ∨ deviceOf w = .desktop := by
  unfold deviceOf; split <;> simp

/-- The two classes share no width. -/
theorem deviceOf_exclusive (w : Nat) : ¬ (deviceOf w = .phone ∧ deviceOf w = .desktop) := by
  unfold deviceOf; split <;> simp

/-! ## The views and their URLs -/

/-- A view of the review: the flag on, the faithful rewrite (no flag), or the compare page at the flag. -/
inductive View | flag | faithful | compare
deriving DecidableEq, Repr

/-- The word of a view (the wire value). -/
def View.word : View → String
  | .flag => "flag" | .faithful => "faithful" | .compare => "compare"

/-- The view a word names. -/
def View.ofWord : String → Option View
  | "flag" => some .flag
  | "faithful" => some .faithful
  | "compare" => some .compare
  | _ => none

/-- The URL search of a view: the flag views carry exactly the review's flag, the faithful view carries none. -/
def searchOf (f : Flag) : View → String
  | .flag => "?fw=" ++ f.key
  | .faithful => ""
  | .compare => "?fw=" ++ f.key

/-- The arm of the Builds open a view uses: the rewrite arm, or the compare page. -/
def armOf : View → BuildsOpen.Arm
  | .compare => .compare
  | _ => .rewrite

/-- What a Preview click asks of the main build: the view, its search and arm, the slot (always the main build's) and the device. -/
structure Plan where
  view : View
  search : String
  arm : BuildsOpen.Arm
  slot : String
  device : Device
deriving DecidableEq, Repr

/-- The flags whose review is open: only these get a preview. -/
def openFlags (ds : List Row) (rs : List Rec) : List Flag := (openItems ds rs).map (·.flag)

/-- The plan of a Preview click on `f` in `view` from a viewport `width` wide: none unless the review is open. -/
def plan (ds : List Row) (rs : List Rec) (f : Flag) (view : View) (width : Nat) : Option Plan :=
  if (openFlags ds rs).contains f then
    some { view, search := searchOf f view, arm := armOf view, slot := BuildsOpen.mainSlot, device := deviceOf width }
  else none

/-- **Only an open look-change review gets a preview.** -/
theorem plan_some_open (ds rs f view width p) (h : plan ds rs f view width = some p) : f ∈ openFlags ds rs := by
  unfold plan at h
  split at h
  · rename_i hc; simpa using hc
  · cases h

/-- An open review gets a plan in every view. -/
theorem plan_isSome_of_open (ds rs f view width) (h : f ∈ openFlags ds rs) : (plan ds rs f view width).isSome = true := by
  simp [plan, h]

/-- A decided or unknown review gets no plan. -/
theorem plan_none_closed (ds rs f view width) (h : f ∉ openFlags ds rs) : plan ds rs f view width = none := by
  simp [plan, h]

/-- Every plan builds on the main build (the Builds tab's main slot), never on a task branch. -/
theorem plan_main_slot (ds rs f view width p) (h : plan ds rs f view width = some p) : p.slot = BuildsOpen.mainSlot := by
  unfold plan at h; split at h
  · cases h; rfl
  · cases h

/-- The faithful view has no search at all: no `fw` entry and no preset. -/
theorem faithful_search_empty (f : Flag) : searchOf f .faithful = "" := rfl

/-- The compare view is at the same search as the flag view. -/
theorem compare_search (f : Flag) : searchOf f .compare = searchOf f .flag := rfl

/-- The faithful view is the rewrite arm. -/
theorem armOf_faithful : armOf .faithful = .rewrite := rfl

/-- The compare view is the compare page. -/
theorem armOf_compare : armOf .compare = .compare := rfl

/-- The flag and faithful views differ: the flag view names a flag and the faithful one does not. -/
theorem flag_ne_faithful (f : Flag) : searchOf f .flag ≠ searchOf f .faithful := by
  simp [searchOf]

/-! ## What was previewed -/

/-- A `review.previewed` event as the projection reads it: the flag key and the device word. -/
abbrev Seen := String × String

/-- Whether a flag was previewed on a device. -/
def seenOn (evs : List Seen) (f : Flag) (d : Device) : Bool := evs.any fun e => e.1 == f.key && e.2 == d.word

/-- The devices a flag was not yet previewed on, desktop first. -/
def missing (evs : List Seen) (f : Flag) : List Device := devices.filter fun d => !seenOn evs f d

/-- The line that asks the user to check on a missing device. -/
def askText : Device → String
  | .desktop => "Not yet previewed on a computer: press Preview here, in the console on this machine."
  | .phone => "Not yet previewed on the phone: open the console at its LAN address on the phone and press Preview there."

/-- The ask lines of a flag, one per missing device. -/
def asks (evs : List Seen) (f : Flag) : List String := (missing evs f).map askText

/-- The key of the event a Preview click records (a repeated click on the same device is a no-op duplicate). -/
def eventKey (f : Flag) (d : Device) (round : String := "") : String := "review-previewed-" ++ f.key ++ "-" ++ d.word ++ round

/-- The key part of a review round: none for the first step of the flag (so a key recorded before rounds existed is the first
round's), `#k` for a later one. A later round must differ, or its first click would be dropped as the duplicate of the old one. -/
def roundTag (f : Flag) (step : String) : String := (step.drop (stepId f).length).toString

/-- The step of the open review of a flag: its current round. -/
def roundStep (ds : List Row) (rs : List Rec) (f : Flag) : String :=
  (((openItems ds rs).find? (·.flag == f)).map (·.step)).getD (stepId f)

/-- **A recorded preview is seen.** -/
theorem seenOn_record (evs : List Seen) (f : Flag) (d : Device) : seenOn (evs ++ [(f.key, d.word)]) f d = true := by
  simp [seenOn]

/-- **A recorded device is no longer missing.** -/
theorem not_missing_after (evs : List Seen) (f : Flag) (d : Device) : d ∉ missing (evs ++ [(f.key, d.word)]) f := by
  simp [missing, seenOn_record]

/-- Nothing recorded: both devices are missing. -/
theorem missing_nil (f : Flag) : missing [] f = [.desktop, .phone] := by
  simp [missing, seenOn, devices]

/-- When nothing is missing there is nothing to ask. -/
theorem asks_nil (evs : List Seen) (f : Flag) (h : missing evs f = []) : asks evs f = [] := by
  simp [asks, h]

/-- Recording never un-sees: previewed devices stay previewed when the log grows. -/
theorem seenOn_mono (evs ts : List Seen) (f : Flag) (d : Device) (h : seenOn evs f d = true) :
    seenOn (evs ++ ts) f d = true := by
  unfold seenOn at *
  simp [List.any_append, h]

/-- The event of a click, or why none is made: the review must be open, and the device is the width's class. -/
def record (ds : List Row) (rs : List Rec) (f : Flag) (width : Nat) : Except String (String × Device) :=
  if (openFlags ds rs).contains f then .ok (eventKey f (deviceOf width) (roundTag f (roundStep ds rs f)), deviceOf width)
  else .error "no open look-change review for this flag"

/-- A recorded click is for an open review and carries the width's device. -/
theorem record_ok_open (ds rs f width k d) (h : record ds rs f width = .ok (k, d)) :
    f ∈ openFlags ds rs ∧ d = deviceOf width := by
  unfold record at h
  split at h
  · rename_i hc; simp at h; exact ⟨by simpa using hc, h.2.symm⟩
  · cases h

/-- A closed review records nothing. -/
theorem record_error_closed (ds rs f width) (h : f ∉ openFlags ds rs) :
    record ds rs f width = .error "no open look-change review for this flag" := by
  simp [record, h]

/-! ## Which flags a search names -/

/-- The flag names a search carries: its `fw` entries, split at `,`, each a whole name. -/
def searchFlags (search : String) : List String :=
  BuildsOpen.fwEntries (BuildsOpen.params (BuildsOpen.body search))

/-- Whether a search names a flag: one of its entries is the flag's whole key. A flag whose key is the start of another
(`nav:earn` and `nav:earn-no-transition`) is not named by the other. -/
def searchHasFlag (search : String) (f : Flag) : Bool := (searchFlags search).contains f.key

/-- **Exact match.** A search names a flag exactly when an entry of it equals the flag's key; no part of an entry counts. -/
theorem searchHasFlag_iff (search : String) (f : Flag) :
    searchHasFlag search f = true ↔ f.key ∈ searchFlags search := by
  simp [searchHasFlag]

/-- A key that is no entry of the search is not named, whatever the entries contain. -/
theorem searchHasFlag_false (search : String) (f : Flag) (h : f.key ∉ searchFlags search) :
    searchHasFlag search f = false := by
  simpa [searchHasFlag] using h

/-- Whether a plan's search is the right one for its view: the flag and compare views name the flag, the faithful view does not. -/
def carries (f : Flag) (view : View) (search : String) : Bool :=
  match view with
  | .faithful => !searchHasFlag search f
  | _ => searchHasFlag search f

-- The faithful view's empty search names no flag: a #guard below, not a theorem (`String.splitOn` does not reduce in the kernel).

private def ex : Row :=
  { flag := ⟨"nav", "earn-no-transition"⟩, date := "d", decision := .kept, review := .pending }
private def exDone : Row := { ex with review := .done }
private def stOpen : List Rec := [⟨"review-nav:earn-no-transition", none, true⟩]

#guard phoneMax == 600
#guard deviceOf 390 == .phone && deviceOf 600 == .phone && deviceOf 601 == .desktop && deviceOf 1280 == .desktop && deviceOf 0 == .phone
#guard (plan [ex] stOpen ⟨"nav", "earn-no-transition"⟩ .flag 390).map (·.search) == some "?fw=nav:earn-no-transition"
#guard (plan [ex] stOpen ⟨"nav", "earn-no-transition"⟩ .faithful 390).map (·.search) == some ""
#guard (plan [ex] stOpen ⟨"nav", "earn-no-transition"⟩ .compare 1280).map (·.arm) == some .compare
#guard (plan [ex] stOpen ⟨"nav", "earn-no-transition"⟩ .compare 1280).map (·.device) == some .desktop
#guard (plan [ex] stOpen ⟨"nav", "other"⟩ .flag 390).isNone
#guard (plan [ex] [⟨"review-nav:earn-no-transition", some "keep", false⟩] ⟨"nav", "earn-no-transition"⟩ .flag 390).isNone
#guard (plan [exDone] [] ⟨"nav", "earn-no-transition"⟩ .flag 390).isNone
#guard missing [] ⟨"nav", "e"⟩ == [.desktop, .phone]
#guard missing [("nav:e", "desktop")] ⟨"nav", "e"⟩ == [.phone]
#guard missing [("nav:e", "desktop"), ("nav:e", "phone")] ⟨"nav", "e"⟩ == []
#guard missing [("nav:x", "phone")] ⟨"nav", "e"⟩ == [.desktop, .phone]
#guard eventKey ⟨"nav", "e"⟩ .phone == "review-previewed-nav:e-phone"
#guard roundTag ⟨"nav", "e"⟩ "review-nav:e" == "" && roundTag ⟨"nav", "e"⟩ "review-nav:e#1" == "#1"
#guard (record [ex] stOpen ⟨"nav", "earn-no-transition"⟩ 390) matches .ok ("review-previewed-nav:earn-no-transition-phone", .phone)
#guard (record [ex] [⟨"review-nav:earn-no-transition", none, false⟩, ⟨"review-nav:earn-no-transition#1", none, true⟩] ⟨"nav", "earn-no-transition"⟩ 390)
  matches .ok ("review-previewed-nav:earn-no-transition-phone#1", .phone)
-- The flag view of every recorded look decision carries exactly its flag as the one `fw` entry (a decided check over the finite set).
-- A theorem over any key is not stated: it is false for a key with `,`, `&` or `=`, and its proof needs `String.splitOn` lemmas that
-- Lean core lacks (`splitOn` is a well-founded scan the kernel does not reduce, so `decide +kernel` fails too). Accepted limit.
#guard Fw.Preset.Gen.lookDecisions.all fun d =>
  BuildsOpen.fwEntries (BuildsOpen.params (BuildsOpen.body (searchOf d.flag .flag))) == [d.flag.key]
#guard BuildsOpen.params (BuildsOpen.body (searchOf ⟨"nav", "e"⟩ .faithful)) == []
#guard searchHasFlag "?fw=nav:earn-no-transition" ⟨"nav", "earn-no-transition"⟩
#guard !searchHasFlag "?fw=nav:earn-no-transition" ⟨"nav", "earn"⟩
#guard !searchHasFlag "?fw=nav:earn" ⟨"nav", "earn-no-transition"⟩
#guard searchHasFlag "?fw=hero:a,nav:earn,nav:earn-no-transition" ⟨"nav", "earn"⟩
#guard searchHasFlag "?fw=hero:a&fw=nav:earn" ⟨"nav", "earn"⟩
#guard !searchHasFlag "?fw=nav:earn@x" ⟨"nav", "earn"⟩
#guard !searchHasFlag "" ⟨"nav", "earn"⟩
#guard carries ⟨"nav", "earn"⟩ .faithful ""
#guard Fw.Preset.Gen.lookDecisions.all fun d => carries d.flag .flag (searchOf d.flag .flag) && carries d.flag .compare (searchOf d.flag .compare) && carries d.flag .faithful (searchOf d.flag .faithful)

end Fw.Console.ReviewPreview
