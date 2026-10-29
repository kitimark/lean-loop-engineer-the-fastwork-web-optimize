import Lean.Data.Json
/-! Recalc-bisect verdict: which subtree of the page carries the style recalc that runs every frame with nothing changing. -/
namespace Fw.Device.RecalcBisect
open Lean

/-- One idle arm: the frames read and the style recalcs counted in them. -/
structure Arm where
  frames : Nat
  recalcs : Nat
  deriving DecidableEq, Repr

def Arm.rpf100 (a : Arm) : Nat := if a.frames = 0 then 0 else a.recalcs * 100 / a.frames

/-- One page part with its own arm: `parent` is the path of the part it sits in ("" for the top level), `kids` its element children. -/
structure Part where
  path : String
  parent : String
  kids : Nat
  arm : Arm
  deriving DecidableEq, Repr

/-- `full` are arms with nothing hidden, `hidden` arms with the whole body hidden, `parts` one arm per part with that part hidden. -/
structure Job where
  full : List Arm
  hidden : List Arm
  parts : List Part
  deriving DecidableEq, Repr

def minFrames : Nat := 40

def minSpread : Nat := 50

def bandDen : Nat := 4

def maxDepth : Nat := 6

def minValid : Nat := 2

def Arm.ok (a : Arm) : Bool := minFrames ≤ a.frames

def readable (as : List Arm) : List Arm := as.filter (·.ok)

/-- The full rate is the lowest read full arm, so a drifting full arm narrows the spread instead of widening it. -/
def Job.hi (j : Job) : Nat := ((readable j.full).map (·.rpf100)).foldl min 100

/-- The hidden rate is the highest read hidden arm. -/
def Job.lo (j : Job) : Nat := ((readable j.hidden).map (·.rpf100)).foldl max 0

def Job.spread (j : Job) : Nat := j.hi - j.lo

def Job.band (j : Job) : Nat := j.spread / bandDen

def Job.hasFrames (j : Job) : Bool := !(readable j.full).isEmpty && !(readable j.hidden).isEmpty

def Job.contrast (j : Job) : Bool := minSpread ≤ j.spread

inductive Cls where
  | dropped | kept | between | unread
  deriving DecidableEq, Repr

def Cls.name : Cls → String
  | .dropped => "dropped" | .kept => "kept" | .between => "between" | .unread => "unread"

/-- `dropped`: the part's hide brought the rate to the hidden band; `kept`: it left the rate in the full band. -/
def Job.cls (j : Job) (a : Arm) : Cls :=
  if !a.ok then .unread
  else if a.rpf100 ≤ j.lo + j.band then .dropped
  else if j.hi - j.band ≤ a.rpf100 then .kept
  else .between

inductive Level where
  | named (p : String) | none | several | incomplete | leaf
  deriving DecidableEq, Repr

def Level.name : Level → String
  | .named p => s!"named {p}" | .none => "none" | .several => "several" | .incomplete => "incomplete" | .leaf => "leaf"

def Job.kids (j : Job) (parent : String) : List Part := j.parts.filter (·.parent == parent)

def Job.clsOf (j : Job) (parent : String) (c : Cls) : List Part := (j.kids parent).filter (j.cls ·.arm == c)

/-- A parent that has element children but no arm in this level is `incomplete`; the top level without parts is too. -/
def Job.level (j : Job) (parent : String) : Level :=
  if (j.kids parent).isEmpty then
    (if parent == "" then .incomplete else
      match j.parts.find? (·.path == parent) with
      | some p => if p.kids = 0 then .leaf else .incomplete
      | none => .incomplete)
  else if !(j.clsOf parent .unread).isEmpty then .incomplete
  else if (j.clsOf parent .dropped).length = 1 && (j.clsOf parent .between).isEmpty then
    match (j.clsOf parent .dropped).head? with
    | some p => .named p.path
    | none => .incomplete
  else if (j.clsOf parent .dropped).isEmpty && (j.clsOf parent .between).isEmpty then .none
  else .several

def Job.descend (j : Job) : Nat → String → List String × Level
  | 0, _ => ([], .incomplete)
  | n + 1, parent =>
    match j.level parent with
    | .named p => let r := j.descend n p; (p :: r.1, r.2)
    | l => ([], l)

inductive Res where
  | noFrames | noContrast | incomplete | found (path : List String) (stop : Level)
  deriving DecidableEq, Repr

def Res.name : Res → String
  | .noFrames => "no-frames" | .noContrast => "no-contrast" | .incomplete => "incomplete"
  | .found p s => s!"found {String.intercalate " > " p} {s.name}"

def Res.valid : Res → Bool
  | .found _ _ => true
  | _ => false

def Job.res (j : Job) : Res :=
  if !j.hasFrames then .noFrames
  else if !j.contrast then .noContrast
  else
    let r := j.descend maxDepth ""
    if r.1.isEmpty && r.2 == .incomplete then .incomplete else .found r.1 r.2

theorem res_noFrames (j : Job) (h : j.hasFrames = false) : j.res = .noFrames := by
  simp [Job.res, h]

theorem res_noContrast (j : Job) (h1 : j.hasFrames = true) (h : j.contrast = false) : j.res = .noContrast := by
  simp [Job.res, h1, h]

theorem res_incomplete (j : Job) (h1 : j.hasFrames = true) (h2 : j.contrast = true)
    (h : j.descend maxDepth "" = ([], .incomplete)) : j.res = .incomplete := by
  simp [Job.res, h1, h2, h]

theorem res_found (j : Job) (h1 : j.hasFrames = true) (h2 : j.contrast = true) (p : List String) (l : Level)
    (h : j.descend maxDepth "" = (p, l)) (hn : ¬ (p = [] ∧ l = .incomplete)) : j.res = .found p l := by
  have : (p.isEmpty && l == Level.incomplete) = false := by
    cases p with
    | nil => cases l <;> simp_all
    | cons a t => simp
  simp [Job.res, h1, h2, h, this]

theorem descend_zero (j : Job) (parent : String) : j.descend 0 parent = ([], .incomplete) := rfl

theorem descend_named (j : Job) (n : Nat) (parent p : String) (h : j.level parent = .named p) :
    j.descend (n + 1) parent = (p :: (j.descend n p).1, (j.descend n p).2) := by
  simp [Job.descend, h]

theorem descend_stop (j : Job) (n : Nat) (parent : String) (l : Level) (h : j.level parent = l)
    (hn : ∀ p, l ≠ .named p) : j.descend (n + 1) parent = ([], l) := by
  cases l with
  | named p => exact absurd rfl (hn p)
  | _ => simp [Job.descend, h]

theorem level_incomplete_unread (j : Job) (parent : String) (hk : (j.kids parent).isEmpty = false)
    (h : (j.clsOf parent .unread).isEmpty = false) : j.level parent = .incomplete := by
  simp [Job.level, hk, h]

theorem level_incomplete_noArms (j : Job) (hk : (j.kids "").isEmpty = true) : j.level "" = .incomplete := by
  simp [Job.level, hk]

theorem level_leaf (j : Job) (parent : String) (hp : parent ≠ "") (hk : (j.kids parent).isEmpty = true) (p : Part)
    (hf : j.parts.find? (·.path == parent) = some p) (h0 : p.kids = 0) : j.level parent = .leaf := by
  have : (parent == "") = false := by simpa using hp
  simp [Job.level, hk, this, hf, h0]

theorem level_incomplete_unreadKids (j : Job) (parent : String) (hp : parent ≠ "") (hk : (j.kids parent).isEmpty = true) (p : Part)
    (hf : j.parts.find? (·.path == parent) = some p) (h0 : p.kids ≠ 0) : j.level parent = .incomplete := by
  have : (parent == "") = false := by simpa using hp
  simp [Job.level, hk, this, hf, h0]

theorem level_named (j : Job) (parent : String) (hk : (j.kids parent).isEmpty = false)
    (hu : (j.clsOf parent .unread).isEmpty = true) (p : Part) (hd : j.clsOf parent .dropped = [p])
    (hpart : (j.clsOf parent .between).isEmpty = true) : j.level parent = .named p.path := by
  simp [Job.level, hk, hu, hd, hpart]

theorem level_none (j : Job) (parent : String) (hk : (j.kids parent).isEmpty = false)
    (hu : (j.clsOf parent .unread).isEmpty = true) (hd : (j.clsOf parent .dropped).isEmpty = true)
    (hpart : (j.clsOf parent .between).isEmpty = true) : j.level parent = .none := by
  have h1 : (j.clsOf parent .dropped).length ≠ 1 := by
    intro h; simp [List.isEmpty_iff_length_eq_zero.mp hd] at h
  simp [Job.level, hk, hu, hd, hpart, h1]

theorem level_several_twoDrops (j : Job) (parent : String) (hk : (j.kids parent).isEmpty = false)
    (hu : (j.clsOf parent .unread).isEmpty = true) (hd : 2 ≤ (j.clsOf parent .dropped).length) :
    j.level parent = .several := by
  have h1 : (j.clsOf parent .dropped).length ≠ 1 := by omega
  have h2 : (j.clsOf parent .dropped).isEmpty = false := by
    cases hl : j.clsOf parent .dropped with
    | nil => rw [hl] at hd; simp at hd
    | cons a t => rfl
  simp [Job.level, hk, hu, h1, h2]

theorem level_several_partial (j : Job) (parent : String) (hk : (j.kids parent).isEmpty = false)
    (hu : (j.clsOf parent .unread).isEmpty = true) (hpart : (j.clsOf parent .between).isEmpty = false) :
    j.level parent = .several := by
  simp [Job.level, hk, hu, hpart]

theorem level_named_inv (j : Job) (parent p : String) (h : j.level parent = .named p) :
    ∃ d, j.clsOf parent .dropped = [d] ∧ d.path = p ∧ (j.clsOf parent .between).isEmpty = true ∧
      (j.clsOf parent .unread).isEmpty = true := by
  unfold Job.level at h
  split at h
  · exfalso
    revert h
    split <;> (try split) <;> (try split) <;> simp
  · split at h
    · simp_all
    · split at h
      · rename_i h1 h2
        simp only [Bool.and_eq_true, decide_eq_true_eq] at h2
        obtain ⟨hl, hb⟩ := h2
        cases hd : j.clsOf parent .dropped with
        | nil => simp [hd] at hl
        | cons d t =>
          rw [hd] at hl
          have ht : t = [] := List.length_eq_zero_iff.mp (by simpa using hl)
          subst ht
          rw [hd] at h
          simp at h
          refine ⟨d, rfl, h, hb, ?_⟩
          simpa using h1
      · split at h <;> simp_all

/-- The sibling-stays condition of the task: a named part's siblings are all `kept`. -/
theorem named_siblings_kept (j : Job) (parent p : String) (h : j.level parent = .named p) (q : Part)
    (hq : q ∈ j.kids parent) (hne : q.path ≠ p) : j.cls q.arm = .kept := by
  obtain ⟨d, hd, hdp, hb, hu⟩ := level_named_inv j parent p h
  have hmem : ∀ c, q ∈ j.clsOf parent c ↔ j.cls q.arm = c := by
    intro c
    simp [Job.clsOf, hq]
  have e1 : j.cls q.arm ≠ .unread := fun hc => by
    have := (hmem .unread).mpr hc
    rw [List.isEmpty_iff.mp hu] at this
    simp at this
  have e2 : j.cls q.arm ≠ .between := fun hc => by
    have := (hmem .between).mpr hc
    rw [List.isEmpty_iff.mp hb] at this
    simp at this
  have e3 : j.cls q.arm ≠ .dropped := fun hc => by
    have := (hmem .dropped).mpr hc
    rw [hd] at this
    simp at this
    exact hne (this ▸ hdp)
  cases hc : j.cls q.arm <;> simp_all

theorem thresholds_sane : 0 < minFrames ∧ 2 * (minSpread / bandDen) < minSpread ∧ 0 < bandDen ∧ 0 < maxDepth ∧ 0 < minValid := by
  decide

theorem band_disjoint (j : Job) (h : j.contrast = true) : j.lo + j.band < j.hi - j.band := by
  unfold Job.contrast at h
  simp only [decide_eq_true_eq] at h
  unfold Job.band Job.spread at *
  unfold minSpread at h
  unfold bandDen
  omega

theorem cls_dropped_not_kept (j : Job) (a : Arm) (hd : j.cls a = .dropped) : j.cls a ≠ .kept := by
  rw [hd]; simp

inductive Verdict where
  | inconclusive | none | several | named (path : List String)
  deriving DecidableEq, Repr

def Verdict.name : Verdict → String
  | .inconclusive => "inconclusive" | .none => "none" | .several => "several"
  | .named p => s!"named {String.intercalate " > " p}"

def paths (rs : List Res) : List (List String) := rs.filterMap fun | .found p _ => some p | _ => none

def stops (rs : List Res) : List Level := rs.filterMap fun | .found _ s => some s | _ => none

def lead (rs : List Res) : List String := (paths rs).headD []

def samePath (rs : List Res) : Bool := (paths rs).all (· == lead rs)

def allNone (rs : List Res) : Bool := (stops rs).all (· == Level.none)

def overall (rs : List Res) : Verdict :=
  if (paths rs).length < minValid then .inconclusive
  else if samePath rs then
    (if (lead rs).isEmpty then (if allNone rs then .none else .several) else .named (lead rs))
  else .several

theorem overall_inconclusive (rs : List Res) (h : (paths rs).length < minValid) : overall rs = .inconclusive := by
  simp [overall, h]

theorem overall_several_paths (rs : List Res) (h : ¬ (paths rs).length < minValid) (hp : samePath rs = false) :
    overall rs = .several := by
  simp [overall, h, hp]

theorem overall_none (rs : List Res) (h : ¬ (paths rs).length < minValid) (hp : samePath rs = true)
    (h0 : (lead rs).isEmpty = true) (hs : allNone rs = true) : overall rs = .none := by
  simp [overall, h, hp, h0, hs]

theorem overall_several_top (rs : List Res) (h : ¬ (paths rs).length < minValid) (hp : samePath rs = true)
    (h0 : (lead rs).isEmpty = true) (hs : allNone rs = false) : overall rs = .several := by
  simp [overall, h, hp, h0, hs]

theorem overall_named (rs : List Res) (h : ¬ (paths rs).length < minValid) (hp : samePath rs = true)
    (h0 : (lead rs).isEmpty = false) : overall rs = .named (lead rs) := by
  simp [overall, h, hp, h0]

inductive Next where
  | readSource | splitHides | showOnly | rerun
  deriving DecidableEq

def Next.name : Next → String
  | .readSource => "read the WebKit path that restyles the named part, propose one same-look fix"
  | .splitHides => "one show-only arm per part"
  | .showOnly => "show-only arms: hiding one part does not drop the rate"
  | .rerun => "rerun with contrast or more valid jobs"

def Verdict.next : Verdict → Next
  | .named _ => .readSource
  | .several => .splitHides
  | .none => .showOnly
  | .inconclusive => .rerun

theorem next_read_iff (v : Verdict) : v.next = .readSource ↔ ∃ p, v = .named p := by
  cases v <;> simp [Verdict.next]

private def A (frames recalcs : Nat) : Arm := ⟨frames, recalcs⟩

private def P (path parent : String) (kids : Nat) (frames recalcs : Nat) : Part := ⟨path, parent, kids, A frames recalcs⟩

private def fullA : List Arm := [A 100 97, A 100 100]

private def hidA : List Arm := [A 100 0, A 100 5]

private def job (parts : List Part) : Job := ⟨fullA, hidA, parts⟩

def cases : List (String × Job) :=
  [("top named, leaf", job [P "nav" "" 0 100 98, P "page" "" 0 100 4, P "overlay" "" 0 100 99]),
   ("top named, child named, leaf", job [P "nav" "" 0 100 98, P "page" "" 3 100 4, P "page/hero" "page" 0 100 99, P "page/platform" "page" 0 100 3, P "page/pain" "page" 0 100 96]),
   ("child level several", job [P "page" "" 3 100 4, P "page/hero" "page" 0 100 5, P "page/pain" "page" 0 100 8, P "page/platform" "page" 0 100 99, P "nav" "" 0 100 98]),
   ("child level none", job [P "page" "" 3 100 4, P "page/hero" "page" 0 100 99, P "page/pain" "page" 0 100 97, P "nav" "" 0 100 98]),
   ("child level partial", job [P "page" "" 3 100 4, P "page/hero" "page" 0 100 55, P "page/pain" "page" 0 100 97, P "nav" "" 0 100 98]),
   ("child arms missing", job [P "page" "" 3 100 4, P "nav" "" 0 100 98]),
   ("child arm unread", job [P "page" "" 3 100 4, P "page/hero" "page" 0 100 99, P "page/pain" "page" 0 10 0, P "nav" "" 0 100 98]),
   ("top none", job [P "nav" "" 0 100 98, P "page" "" 3 100 96, P "overlay" "" 0 100 99]),
   ("top several, two drops", job [P "nav" "" 0 100 3, P "page" "" 3 100 4, P "overlay" "" 0 100 99]),
   ("top several, partial", job [P "nav" "" 0 100 98, P "page" "" 3 100 50, P "overlay" "" 0 100 99]),
   ("top unread", job [P "nav" "" 0 100 98, P "page" "" 3 39 0, P "overlay" "" 0 100 99]),
   ("top no arms", job []),
   ("no full frames", ⟨[A 39 39], hidA, [P "nav" "" 0 100 4]⟩),
   ("no hidden frames", ⟨fullA, [A 10 0], [P "nav" "" 0 100 4]⟩),
   ("no contrast", ⟨[A 100 60, A 100 70], [A 100 20], [P "nav" "" 0 100 4]⟩),
   ("contrast edge hit", ⟨[A 100 55], [A 100 5], [P "nav" "" 0 100 6, P "page" "" 0 100 53]⟩),
   ("contrast edge miss", ⟨[A 100 54], [A 100 5], [P "nav" "" 0 100 6, P "page" "" 0 100 53]⟩),
   ("full drift narrows", ⟨[A 100 100, A 100 80], [A 100 0], [P "nav" "" 0 100 18, P "page" "" 0 100 79]⟩),
   ("drop edge hit", ⟨[A 100 100], [A 100 0], [P "nav" "" 0 100 25, P "page" "" 0 100 100]⟩),
   ("drop edge miss", ⟨[A 100 100], [A 100 0], [P "nav" "" 0 100 26, P "page" "" 0 100 100]⟩),
   ("stay edge hit", ⟨[A 100 100], [A 100 0], [P "nav" "" 0 100 4, P "page" "" 0 100 75]⟩),
   ("stay edge miss", ⟨[A 100 100], [A 100 0], [P "nav" "" 0 100 4, P "page" "" 0 100 74]⟩),
   ("min frames edge", ⟨[A 100 100], [A 100 0], [P "nav" "" 0 100 4, P "page" "" 0 40 40]⟩),
   ("min frames edge miss", ⟨[A 100 100], [A 100 0], [P "nav" "" 0 100 4, P "page" "" 0 39 39]⟩),
   ("three deep", job [P "a" "" 2 100 3, P "z" "" 0 100 99, P "a/b" "a" 2 100 4, P "a/c" "a" 0 100 98, P "a/b/d" "a/b" 0 100 5, P "a/b/e" "a/b" 0 100 99]),
   ("named with kids but no arms", job [P "a" "" 2 100 3, P "z" "" 0 100 99, P "a/b" "a" 2 100 4, P "a/c" "a" 0 100 98])]

private def caseJob (n : String) : Job := ((cases.find? (·.1 == n)).map (·.2)).getD ⟨[], [], []⟩

def combos : List (String × List String) :=
  [("three same path", ["top named, child named, leaf", "top named, child named, leaf", "top named, child named, leaf"]),
   ("two same one void", ["top named, child named, leaf", "no contrast", "top named, child named, leaf"]),
   ("one valid", ["top named, child named, leaf", "no contrast", "no full frames"]),
   ("different depth", ["top named, leaf", "top named, child named, leaf", "top named, leaf"]),
   ("different parts", ["top named, leaf", "three deep", "top named, leaf"]),
   ("three none", ["top none", "top none", "top none"]),
   ("none and several", ["top none", "top several, two drops", "top none"]),
   ("none at two depths", ["top none", "child level none", "top none"]),
   ("named and none", ["top named, leaf", "top none", "top named, leaf"]),
   ("incomplete top void", ["top no arms", "top unread", "top named, leaf"]),
   ("no jobs", [])]

private def armJ (a : Arm) : Json := Json.mkObj [("frames", a.frames), ("recalcs", a.recalcs)]

private def partJ (p : Part) : Json :=
  Json.mkObj [("path", p.path), ("parent", p.parent), ("kids", p.kids), ("arm", armJ p.arm)]

private def jobJ (j : Job) : Json :=
  Json.mkObj [("full", Json.arr (j.full.map armJ).toArray), ("hidden", Json.arr (j.hidden.map armJ).toArray),
    ("parts", Json.arr (j.parts.map partJ).toArray)]

private def strs (xs : List String) : Json := Json.arr (xs.map Json.str).toArray

private def pathJ : Res → Json
  | .found p _ => strs p
  | _ => Json.null

private def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("minFrames", minFrames), ("minSpread", minSpread), ("bandDen", bandDen), ("maxDepth", maxDepth),
    ("minValid", minValid)]).compress] ++
  (cases.map fun (n, j) =>
    let r := j.res
    (Json.mkObj [("kind", "job"), ("name", n), ("job", jobJ j), ("hi", j.hi), ("lo", j.lo), ("band", j.band),
      ("classes", strs (j.parts.map fun p => (j.cls p.arm).name)), ("why", r.name), ("valid", r.valid), ("path", pathJ r)]).compress) ++
  (combos.map fun (n, ns) =>
    let v := overall (ns.map fun m => (caseJob m).res)
    (Json.mkObj [("kind", "overall"), ("name", n), ("jobs", strs ns), ("verdict", v.name), ("next", v.next.name)]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"device-recalc-bisect golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"device-recalc-bisect golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "device" / "recalc-bisect.jsonl"

def checkRepo : IO Unit := do
  if (← run ["--check", goldenPath.toString]) != 0 then throw (IO.userError "device-recalc-bisect golden differs")

end Fw.Device.RecalcBisect
