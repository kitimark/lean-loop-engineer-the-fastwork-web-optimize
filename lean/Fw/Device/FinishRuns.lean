import Lean.Data.Json
import Fw.Device.StillRuns
/-!
# Finish-zone still runs, scrollY reversals and open lateness at the page end
Twin: `packages/measure-webkit/src/throttle/finish.mjs`; still runs come from `Fw.Device.StillRuns`.
-/
namespace Fw.Device.FinishRuns
open Lean
open Fw.Device.StillRuns (Arm mid bandRuns shortRuns exitFrames runs scan inBand count minBase dropDen sameHeight)

/-- One frame: `scrollY` and the largest `scrollY` (`scrollHeight - innerHeight`) in tenth px, and whether the morph panel is open. -/
structure Frame where
  y : Int
  mx : Int
  isOpen : Bool
  deriving DecidableEq, Repr

/-- The finish zone: the last 600 px of the page, in tenth px. -/
def zonePx : Int := 6000

/-- A frame is at the page end within 7 px, in tenth px. -/
def endPx : Int := 70

/-- Frames after the first open frame, and after reaching the end, in which reversals and the open are counted (3 s at 60 Hz). -/
def openWindow : Nat := 180

/-- The frame is inside the finish zone. -/
def inZone (f : Frame) : Bool := decide (f.mx - zonePx ≤ f.y)

/-- The frame is at the page end. -/
def atEnd (f : Frame) : Bool := decide (f.mx - endPx ≤ f.y)

/-- A zone value that `StillRuns.mid` accepts, and one it refuses. -/
def zoneValue (f : Frame) : Int := if inZone f then 500 else 0

/-- Each position paired with the zone value of the next frame, the shape `StillRuns.runs` reads. -/
def zoneRows : List Frame → List (Int × Int)
  | f :: g :: rest => (f.y, zoneValue g) :: zoneRows (g :: rest)
  | _ => []

/-- Still runs of 5 to 6 frames inside the finish zone. -/
def finishBand (fs : List Frame) : Nat := bandRuns (zoneRows fs)

/-- Still runs of 1 to 9 frames inside the finish zone. -/
def finishShort (fs : List Frame) : Nat := shortRuns (zoneRows fs)

/-- Frames inside the finish zone, the denominator of the band count. -/
def finishFrames (fs : List Frame) : Nat := exitFrames (zoneRows fs)

/-- The first stretch of open frames, at most `openWindow` of them. -/
def openPhase (fs : List Frame) : List Frame :=
  ((fs.dropWhile fun f => !f.isOpen).takeWhile fun f => f.isOpen).take openWindow

/-- Consecutive equal positions merged. -/
def dedupFrom (prev : Int) : List Int → List Int
  | [] => []
  | x :: xs => if x == prev then dedupFrom prev xs else x :: dedupFrom x xs

/-- Direction changes of a list whose neighbours differ. -/
def turnsFrom (a b : Int) : List Int → Nat
  | [] => 0
  | c :: rest => (if (b - a) * (c - b) < 0 then 1 else 0) + turnsFrom b c rest

/-- Direction changes of the distinct consecutive positions. -/
def turns : List Int → Nat
  | [] => 0
  | x :: xs => match dedupFrom x xs with
    | [] => 0
    | y :: ys => turnsFrom x y ys

/-- `scrollY` direction changes while the morph is open. -/
def reversals (fs : List Frame) : Nat := turns ((openPhase fs).map (·.y))

/-- Frames from reaching the page end to the first open frame, none when the page never reached the end or did not open within `openWindow`. -/
def lateness (fs : List Frame) : Option Nat := ((fs.dropWhile fun f => !atEnd f).take openWindow).findIdx? (·.isOpen)

/-- Whether any frame reached the page end. -/
def reached (fs : List Frame) : Bool := fs.any atEnd

/-- The counts of one pass. -/
structure Result where
  band : Nat
  short : Nat
  frames : Nat
  reversals : Nat
  reached : Bool
  late : Option Nat
  deriving DecidableEq, Repr

/-- Every count of one pass. -/
def reduce (fs : List Frame) : Result :=
  ⟨finishBand fs, finishShort fs, finishFrames fs, reversals fs, reached fs, lateness fs⟩

/-- The band runs and finish frames of an arm summed over its passes. -/
def armOf (rs : List Result) : Arm := ⟨(rs.map (·.band)).sum, (rs.map (·.frames)).sum⟩

/-- Reversals summed over the passes of an arm. -/
def reversalSum (rs : List Result) : Nat := (rs.map (·.reversals)).sum

theorem zoneRows_nil : zoneRows [] = [] := rfl

theorem zoneRows_single (f : Frame) : zoneRows [f] = [] := rfl

theorem zoneRows_length : ∀ fs : List Frame, (zoneRows fs).length = fs.length - 1
  | [] => rfl
  | [_] => rfl
  | f :: g :: rest => by
    have := zoneRows_length (g :: rest)
    simp only [zoneRows, List.length_cons] at this ⊢
    omega

theorem finishFrames_le (fs : List Frame) : finishFrames fs ≤ fs.length - 1 := by
  unfold finishFrames exitFrames
  have := List.length_filter_le (fun r : Int × Int => mid r.2) (zoneRows fs)
  have := zoneRows_length fs
  omega

theorem zoneValue_out {f : Frame} (h : inZone f = false) : zoneValue f = 0 := by
  simp [zoneValue, h]

theorem zoneRows_out : ∀ fs : List Frame, (∀ f ∈ fs.drop 1, inZone f = false) → ∀ p ∈ zoneRows fs, mid p.2 = false
  | [], _, _, hp => by simp [zoneRows] at hp
  | [_], _, _, hp => by simp [zoneRows] at hp
  | f :: g :: rest, h, p, hp => by
    simp only [zoneRows, List.mem_cons] at hp
    rcases hp with rfl | hp
    · have := zoneValue_out (h g (by simp))
      simp [this, mid]
    · exact zoneRows_out (g :: rest) (fun x hx => h x (by simp at hx ⊢; exact Or.inr hx)) p hp

theorem finishFrames_zero_of_out (fs : List Frame) (h : ∀ f ∈ fs.drop 1, inZone f = false) : finishFrames fs = 0 := by
  unfold finishFrames exitFrames
  rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
  intro p hp
  simp [zoneRows_out fs h p hp]

theorem scan_out (prev : Int) : ∀ (rows : List (Int × Int)) (k : Nat) (m : Bool),
    (0 < k → m = false) → (∀ p ∈ rows, mid p.2 = false) → ∀ r ∈ scan prev k m rows, r.mid = false
  | [], k, m, _, _, r, hr => by simp [scan] at hr
  | (y, v) :: rest, k, m, hk, hv, r, hr => by
    have hvv : mid v = false := hv (y, v) (by simp)
    have hrest : ∀ p ∈ rest, mid p.2 = false := fun p hp => hv p (by simp [hp])
    unfold scan at hr
    split at hr
    · exact scan_out prev rest (k + 1) (m && mid v) (fun _ => by simp [hvv]) hrest r hr
    · split at hr
      · exact scan_out y rest 0 true (fun h => by omega) hrest r hr
      · rename_i h1 h2
        simp only [List.mem_cons] at hr
        rcases hr with rfl | hr
        · have : 0 < k := by
            cases k with
            | zero => simp at h2
            | succ n => omega
          simpa using hk this
        · exact scan_out y rest 0 true (fun h => by omega) hrest r hr

theorem finishBand_zero_of_out (fs : List Frame) (h : ∀ f ∈ fs.drop 1, inZone f = false) : finishBand fs = 0 := by
  unfold finishBand bandRuns count
  rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
  intro r hr
  have hall := zoneRows_out fs h
  cases hrows : zoneRows fs with
  | nil => simp [hrows, runs] at hr
  | cons p rest =>
    rw [hrows] at hall hr
    have := scan_out p.1 rest 0 true (fun h => by omega) (fun q hq => hall q (by simp [hq])) r (by simpa [runs] using hr)
    simp [inBand, this]

theorem reversals_nil : reversals [] = 0 := rfl

theorem dedupFrom_const (v : Int) : ∀ l : List Int, (∀ y ∈ l, y = v) → dedupFrom v l = []
  | [], _ => rfl
  | x :: xs, h => by
    have hx : x = v := h x (by simp)
    simp [dedupFrom, hx, dedupFrom_const v xs (fun y hy => h y (by simp [hy]))]

theorem turns_const (v : Int) (l : List Int) (h : ∀ y ∈ l, y = v) : turns (v :: l) = 0 := by
  simp [turns, dedupFrom_const v l h]

theorem turnsFrom_le : ∀ (a b : Int) (l : List Int), turnsFrom a b l ≤ l.length
  | _, _, [] => by simp [turnsFrom]
  | a, b, c :: rest => by
    have := turnsFrom_le b c rest
    simp only [turnsFrom, List.length_cons]
    split <;> omega

theorem dropWhile_all {α : Type} (p : α → Bool) : ∀ l : List α, (∀ x ∈ l, p x = true) → l.dropWhile p = []
  | [], _ => rfl
  | x :: xs, h => by
    rw [List.dropWhile_cons_of_pos (h x (by simp))]
    exact dropWhile_all p xs (fun y hy => h y (by simp [hy]))

theorem reversals_zero_of_steady (fs : List Frame) (s : Int) (h : ∀ f ∈ openPhase fs, f.y = s) : reversals fs = 0 := by
  unfold reversals
  cases hp : openPhase fs with
  | nil => simp [turns]
  | cons f rest =>
    rw [hp] at h
    have h0 : f.y = s := h f (by simp)
    apply turns_const
    intro y hy
    obtain ⟨g, hg, rfl⟩ := List.mem_map.mp hy
    show g.y = f.y
    rw [h g (by simp [hg]), h0]

theorem openPhase_closed (fs : List Frame) (h : ∀ f ∈ fs, f.isOpen = false) : openPhase fs = [] := by
  unfold openPhase
  have : fs.dropWhile (fun f => !f.isOpen) = [] := dropWhile_all _ fs fun f hf => by simp [h f hf]
  simp [this]

theorem openPhase_length (fs : List Frame) : (openPhase fs).length ≤ openWindow := by
  unfold openPhase
  rw [List.length_take]
  omega

theorem lateness_none_of_never_open (fs : List Frame) (h : ∀ f ∈ fs, f.isOpen = false) : lateness fs = none := by
  unfold lateness
  have : ∀ f ∈ (fs.dropWhile fun f => !atEnd f).take openWindow, f.isOpen = false := fun f hf =>
    h f (List.dropWhile_subset _ (List.mem_of_mem_take hf))
  cases hf : List.findIdx? (·.isOpen) ((fs.dropWhile fun f => !atEnd f).take openWindow) with
  | none => rfl
  | some n =>
    exfalso
    obtain ⟨hlt, hx⟩ := List.findIdx?_eq_some_iff_getElem.mp hf
    have := this _ (List.getElem_mem hlt)
    simp_all

theorem lateness_none_of_never_reached (fs : List Frame) (h : reached fs = false) : lateness fs = none := by
  have : fs.dropWhile (fun f => !atEnd f) = [] := dropWhile_all _ fs fun f hf => by
    have := List.any_eq_false.mp h f hf
    simpa using this
  simp [lateness, this]

theorem lateness_lt (fs : List Frame) (n : Nat) (h : lateness fs = some n) : n < openWindow := by
  unfold lateness at h
  obtain ⟨hlt, _⟩ := List.findIdx?_eq_some_iff_getElem.mp h
  simp only [List.length_take] at hlt
  omega

/-! ## The verdict -/

/-- What the finish zone shows about the lift arm against a baseline arm. -/
inductive Verdict where
  | lifted | notLifted | noSignature | noData
  deriving DecidableEq, Repr

/-- The word written in the output. -/
def Verdict.name : Verdict → String
  | .lifted => "lifted" | .notLifted => "not-lifted" | .noSignature => "no-signature" | .noData => "no-data"

/-- Both arms need finish frames; the baseline needs `minBase` band runs; then the lift arm's rate must be at most a `dropDen`th of the baseline's. -/
def verdict (base lift : Arm) : Verdict :=
  if base.frames == 0 || lift.frames == 0 then .noData
  else if base.runs < minBase then .noSignature
  else if lift.runs * base.frames * dropDen ≤ base.runs * lift.frames then .lifted
  else .notLifted

theorem verdict_noData {base lift : Arm} (h : base.frames = 0 ∨ lift.frames = 0) : verdict base lift = .noData := by
  rcases h with h | h <;> simp [verdict, h]

theorem verdict_noSignature {base lift : Arm} (h1 : 0 < base.frames) (h2 : 0 < lift.frames) (h : base.runs < minBase) :
    verdict base lift = .noSignature := by
  simp [verdict, Nat.pos_iff_ne_zero.mp h1, Nat.pos_iff_ne_zero.mp h2, h]

theorem verdict_lifted {base lift : Arm} (h1 : 0 < base.frames) (h2 : 0 < lift.frames) (h3 : minBase ≤ base.runs)
    (h4 : lift.runs * base.frames * dropDen ≤ base.runs * lift.frames) : verdict base lift = .lifted := by
  have : ¬ base.runs < minBase := by omega
  simp [verdict, Nat.pos_iff_ne_zero.mp h1, Nat.pos_iff_ne_zero.mp h2, this, h4]

theorem verdict_notLifted {base lift : Arm} (h1 : 0 < base.frames) (h2 : 0 < lift.frames) (h3 : minBase ≤ base.runs)
    (h4 : ¬ lift.runs * base.frames * dropDen ≤ base.runs * lift.frames) : verdict base lift = .notLifted := by
  have : ¬ base.runs < minBase := by omega
  simp [verdict, Nat.pos_iff_ne_zero.mp h1, Nat.pos_iff_ne_zero.mp h2, this, h4]

theorem lifted_rate {base lift : Arm} (h : verdict base lift = .lifted) :
    lift.runs * base.frames * dropDen ≤ base.runs * lift.frames := by
  unfold verdict at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · split at h
      · assumption
      · simp at h

theorem verdict_lifted_iff_still {base lift : Arm} (h1 : 0 < base.frames) (h2 : 0 < lift.frames) (h3 : minBase ≤ base.runs) :
    verdict base lift = .lifted ↔ Fw.Device.StillRuns.verdict [] base lift = .lifted := by
  have : ¬ base.runs < minBase := by omega
  simp [verdict, Fw.Device.StillRuns.verdict, sameHeight, Nat.pos_iff_ne_zero.mp h1, Nat.pos_iff_ne_zero.mp h2, this]

/-! ## The golden -/

private def frameJ (f : Frame) : Json := Json.arr #[toJson f.y, toJson f.mx, toJson (if f.isOpen then 1 else 0)]

private def framesJ (fs : List Frame) : Json := Json.arr (fs.map frameJ).toArray

private def pairsJ (l : List (Int × Int)) : Json := Json.arr (l.map fun p => toJson [p.1, p.2]).toArray

private def mk (l : List (Int × Int × Bool)) : List Frame := l.map fun (y, mx, o) => ⟨y, mx, o⟩

private def still (n : Nat) (y mx : Int) (o : Bool := false) : List (Int × Int × Bool) := List.replicate n (y, mx, o)

/-- A throttled approach: positions held for 5 frames, then stepping to the end, then open and bouncing. -/
private def steps (ys : List Int) (p : Nat) (mx : Int) : List (Int × Int × Bool) := ys.flatMap fun y => still p y mx

private def passCases : List (String × List Frame) :=
  [("empty", []), ("single", mk (still 1 50000 52000)),
   ("outside the zone", mk (steps [0, 100, 200, 300] 6 52000)),
   ("throttled in the zone", mk (steps [48000, 48100, 48200, 48300] 6 52000 ++ still 1 48400 52000)),
   ("long stills in the zone", mk (steps [48000, 48100, 48200] 8 52000 ++ still 1 48300 52000)),
   ("zone edge", mk (steps [46000, 46100, 46200] 6 52000 ++ still 1 46300 52000)),
   ("zone edge out", mk (steps [45800, 45900, 45990] 6 52000 ++ still 1 46200 52000)),
   ("mx moves with the toolbar", mk (steps [46200, 46300] 6 52000 ++ steps [46350, 46380] 6 52400 ++ still 1 46400 52400)),
   ("never reached", mk (still 20 40000 52000)),
   ("reached, never open", mk (still 4 51900 52000 ++ still 30 51950 52000)),
   ("open at once", mk (still 3 49000 52000 ++ [(51950, 52000, true)] ++ still 5 51950 52000 true)),
   ("open late", mk (still 3 49000 52000 ++ still 4 51950 52000 ++ still 9 51950 52000 true)),
   ("open before the end", mk (still 2 50000 52000 ++ still 6 50000 52000 true ++ still 2 51950 52000 true)),
   ("restore fights", mk ([(51950, 52000, false), (52100, 52000, true), (52000, 52000, true), (52100, 52000, true), (52000, 52000, true),
      (52100, 52000, true), (52000, 52000, true)])),
   ("monotone open", mk ([(51900, 52000, false), (51950, 52000, true), (52000, 52000, true), (52050, 52000, true), (52100, 52000, true)])),
   ("one bounce", mk ([(51900, 52000, false), (52100, 52000, true), (52000, 52000, true), (52100, 52000, true)])),
   ("steady open", mk ([(51900, 52000, false)] ++ still 12 52000 52000 true)),
   ("open past the window", mk (still 2 51950 52000 ++ still 200 51950 52000 false ++ still 3 51950 52000 true)),
   ("open at the window edge", mk (still 1 51950 52000 ++ still 179 51950 52000 false ++ still 3 51950 52000 true)),
   ("open inside the window", mk (still 1 51950 52000 ++ still 178 51950 52000 false ++ still 3 51950 52000 true)),
   ("closes and reopens", mk (still 1 51950 52000 ++ [(51950, 52000, true), (52100, 52000, true), (52000, 52000, false), (52100, 52000, true), (52000, 52000, true)]))]

private def lcg (s : Nat) : Nat := (s * 1103515245 + 12345) % 2147483648

/-- A pseudo-random pass near the end: positions step or stay, mx wobbles by the toolbar height, the morph opens late and stays. -/
private def noisy (n : Nat) : List Frame :=
  ((List.range n).foldl (fun (acc : Nat × Int × List Frame) i =>
    let s := lcg acc.1
    let y := if s % 7 < 3 then acc.2.1 else acc.2.1 + ((s / 7 % 90 : Nat) : Int) + 10
    let mx : Int := if s / 3 % 5 == 0 then 52400 else 52000
    (s, y, ⟨y, mx, decide (n / 2 ≤ i)⟩ :: acc.2.2)) (11, 46000, [])).2.2.reverse

private def verdictCases : List (Arm × Arm) :=
  [(⟨83, 430⟩, ⟨2, 410⟩), (⟨83, 430⟩, ⟨83, 400⟩), (⟨83, 430⟩, ⟨17, 430⟩), (⟨83, 430⟩, ⟨16, 430⟩), (⟨9, 430⟩, ⟨0, 400⟩),
   (⟨10, 430⟩, ⟨0, 400⟩), (⟨0, 430⟩, ⟨0, 400⟩), (⟨83, 0⟩, ⟨0, 400⟩), (⟨83, 430⟩, ⟨0, 0⟩), (⟨0, 0⟩, ⟨0, 0⟩), (⟨12, 100⟩, ⟨1, 50⟩)]

private def resultJ (r : Result) : Json :=
  Json.mkObj [("band", r.band), ("short", r.short), ("frames", r.frames), ("reversals", r.reversals), ("reached", r.reached),
    ("late", match r.late with | some n => toJson n | none => Json.null)]

private def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("zonePx", zonePx), ("endPx", endPx), ("openWindow", openWindow), ("minBase", minBase),
    ("dropDen", dropDen)]).compress] ++
  ((passCases ++ [("noisy 120", noisy 120), ("noisy 400", noisy 400)]).map fun (name, fs) =>
    (Json.mkObj [("kind", "pass"), ("name", name), ("frames", framesJ fs), ("rows", pairsJ (zoneRows fs)),
      ("result", resultJ (reduce fs))]).compress) ++
  ([[], [5], [5, 5, 5], [1, 2, 3], [1, 3, 2], [1, 3, 3, 2, 2, 5], [3, 1, 3, 1, 3], [0, 4, 4, 0, 0, 4]].map fun l =>
    (Json.mkObj [("kind", "turns"), ("positions", toJson l), ("turns", turns l)]).compress) ++
  (verdictCases.map fun (b, l) =>
    (Json.mkObj [("kind", "verdict"), ("base", Json.mkObj [("runs", b.runs), ("frames", b.frames)]),
      ("lift", Json.mkObj [("runs", l.runs), ("frames", l.frames)]), ("verdict", (verdict b l).name)]).compress) ++
  ([[reduce (mk (steps [48000, 48100, 48200, 48300] 6 52000 ++ still 1 48400 52000)),
     reduce (mk (still 1 51950 52000 ++ [(52100, 52000, true), (52000, 52000, true), (52100, 52000, true)]))],
    [], [reduce []]].map fun rs =>
    (Json.mkObj [("kind", "arm"), ("results", Json.arr (rs.map resultJ).toArray),
      ("arm", Json.mkObj [("runs", (armOf rs).runs), ("frames", (armOf rs).frames)]), ("reversals", reversalSum rs)]).compress)

/-- The bytes of `packages/contracts/golden/device/finishruns.jsonl`. -/
def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

/-- Print the golden, or with `--check <file>` compare its bytes; exit 1 when they differ. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"device-finishruns golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"device-finishruns golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Device.FinishRuns
