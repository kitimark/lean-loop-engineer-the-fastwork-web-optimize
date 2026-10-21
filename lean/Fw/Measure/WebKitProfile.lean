import Lean.Data.Json
import Fw.Device.Session
import Fw.Gate.Smooth
/-!
# WebKit computation events per zone (`packages/measure-webkit/src/profile/reduce.mjs`)
Timeline records of one scroll window, put on the page clock, binned by the scroll position of the frame they fall in, tallied per zone.
-/
namespace Fw.Measure.WebKitProfile
open Lean Fw.Device.Session

/-- Session's scroll zones (this namespace has its own `Zone`). -/
abbrev DZone := Fw.Device.Session.Zone
/-- Session's arms. -/
abbrev DArm := Fw.Device.Session.Arm

/-! ## Record kinds -/

/-- The Timeline record types that are counted, in output order. -/
def kinds : List String :=
  ["RecalculateStyles", "Layout", "Paint", "Composite", "FunctionCall", "EvaluateScript", "TimerFire", "FireAnimationFrame",
    "EventDispatch", "ObserverCallback", "RenderingFrame"]

/-- The four kinds whose time is the render work of a frame. -/
def isRender (k : String) : Bool := k == "RecalculateStyles" || k == "Layout" || k == "Paint" || k == "Composite"

/-- One Timeline record: its type, start (hundredths of ms, Timeline clock), duration (hundredths of ms) and whether a render record encloses it. -/
structure Rec where
  kind : String
  t : Int
  dur : Nat
  nested : Bool
deriving Repr, BEq

/-- A record is nested when one of its ancestors' types is a render kind. -/
def nestedOf (ancestors : List String) : Bool := ancestors.any isRender

/-! ## The clock offset -/

/-- Largest disagreement between the start and end clock offsets of a window, hundredths of ms (5 ms; `performance.now` is coarsened to 1 ms). -/
def driftTol : Nat := 500

/-- The offset (Timeline clock minus page clock) from a mark seen on both clocks. -/
def offsetOf (tl page : Int) : Int := tl - page

/-- The two offsets of a window agree. -/
def driftOk (a b : Int) : Bool := decide ((a - b).natAbs ≤ driftTol)

/-- The offset used for a window: the mean of the start and end offsets. -/
def meanOffset (a b : Int) : Int := (a + b) / 2

theorem driftOk_comm (a b : Int) : driftOk a b = driftOk b a := by
  unfold driftOk
  have : (a - b).natAbs = (b - a).natAbs := by omega
  rw [this]

/-- The branch where the offsets agree: the window is kept. -/
theorem driftOk_keep {a b : Int} (h : (a - b).natAbs ≤ driftTol) : driftOk a b = true := by
  simp [driftOk, h]

/-- The branch where the offsets differ by more than the tolerance: the window is refused. -/
theorem driftOk_refuse {a b : Int} (h : driftTol < (a - b).natAbs) : driftOk a b = false := by
  simp [driftOk]
  omega

/-- The mean offset lies between the two offsets. -/
theorem meanOffset_between (a b : Int) : min a b ≤ meanOffset a b ∧ meanOffset a b ≤ max a b := by
  unfold meanOffset
  omega

/-- When the window is kept, the mean offset is within the tolerance of both. -/
theorem meanOffset_near {a b : Int} (h : driftOk a b = true) : (meanOffset a b - a).natAbs ≤ driftTol ∧ (meanOffset a b - b).natAbs ≤ driftTol := by
  simp only [driftOk, decide_eq_true_eq] at h
  unfold meanOffset
  omega

/-! ## Which zone a record belongs to -/

/-- The scroll position at a page time: the frame at or before it (Session's `yAt`). A record before the first frame takes the first frame's
position. -/
abbrev posAt (frames : List (Int × Int)) (tPage : Int) : Int := yAt frames tPage

/-- The zone of a record: that of the scroll position of the frame it started in. -/
def zoneOfRec (vh10 maxY10 : Int) (frames : List (Int × Int)) (off : Int) (r : Rec) : DZone :=
  Fw.Device.Session.zoneOf vh10 maxY10 (posAt frames (r.t - off))

/-- Before the first frame a record takes the first frame's position. -/
theorem posAt_before (f : Int × Int) (rest : List (Int × Int)) (t : Int) (h : ∀ g ∈ f :: rest, t < g.1) :
    posAt (f :: rest) t = f.2 := by
  have : ((f :: rest).filter fun g => decide (g.1 ≤ t)) = [] := by
    rw [List.filter_eq_nil_iff]
    intro g hg
    have := h g hg
    simp
    omega
  simp [posAt, yAt, this]

/-- After the last frame a record takes the last frame's position. -/
theorem posAt_after (fs : List (Int × Int)) (g : Int × Int) (t : Int) (hg : fs.getLast? = some g)
    (hle : ∀ f ∈ fs, f.1 ≤ g.1) (ht : g.1 ≤ t) : posAt fs t = g.2 := by
  have hall : (fs.filter fun f => decide (f.1 ≤ t)) = fs := by
    rw [List.filter_eq_self]
    intro f hf
    have := hle f hf
    simp
    omega
  simp [posAt, yAt, hall, hg]

/-- Between two frames a record takes the earlier frame's position. -/
theorem posAt_between (p s : List (Int × Int)) (a b : Int × Int) (t : Int) (hp : ∀ f ∈ p, f.1 ≤ t) (ha : a.1 ≤ t)
    (hb : t < b.1) (hs : ∀ f ∈ s, t < f.1) : posAt (p ++ a :: b :: s) t = a.2 := by
  have h1 : (p.filter fun f => decide (f.1 ≤ t)) = p := by
    rw [List.filter_eq_self]
    intro f hf
    simpa using hp f hf
  have h2 : (s.filter fun f => decide (f.1 ≤ t)) = [] := by
    rw [List.filter_eq_nil_iff]
    intro f hf
    have := hs f hf
    simp
    omega
  have h3 : ¬ b.1 ≤ t := by omega
  simp [posAt, yAt, List.filter_append, h1, h2, ha, h3]

/-! ## The window and the tallies -/

/-- A page time lies in one of the half-open windows. -/
def inWins (ws : List (Int × Int)) (t : Int) : Bool := ws.any fun w => decide (w.1 ≤ t ∧ t < w.2)

/-- The records of the window that fall in zone `z`. -/
def zoneRecs (vh10 maxY10 : Int) (frames : List (Int × Int)) (off : Int) (ws : List (Int × Int)) (z : DZone) (rs : List Rec) : List Rec :=
  rs.filter fun r => inWins ws (r.t - off) && zoneOfRec vh10 maxY10 frames off r == z

/-- The animation frames of the window that sit in zone `z`. -/
def zoneFrames (vh10 maxY10 : Int) (ws : List (Int × Int)) (z : DZone) (fs : List (Int × Int)) : List (Int × Int) :=
  fs.filter fun f => inWins ws f.1 && Fw.Device.Session.zoneOf vh10 maxY10 f.2 == z

/-- The three zones hold every record of the window once. -/
theorem zoneRecs_sum (vh10 maxY10 : Int) (frames : List (Int × Int)) (off : Int) (ws : List (Int × Int)) :
    ∀ rs : List Rec, (zoneRecs vh10 maxY10 frames off ws .hero rs).length + (zoneRecs vh10 maxY10 frames off ws .finish rs).length +
      (zoneRecs vh10 maxY10 frames off ws .rest rs).length = (rs.filter fun r => inWins ws (r.t - off)).length
  | [] => by simp [zoneRecs]
  | r :: rs => by
    have ih := zoneRecs_sum vh10 maxY10 frames off ws rs
    unfold zoneRecs at ih ⊢
    cases hw : inWins ws (r.t - off) <;> cases h : zoneOfRec vh10 maxY10 frames off r <;> simp [hw, h] <;> omega

/-- The three zones hold every frame of the window once. -/
theorem zoneFrames_sum (vh10 maxY10 : Int) (ws : List (Int × Int)) :
    ∀ fs : List (Int × Int), (zoneFrames vh10 maxY10 ws .hero fs).length + (zoneFrames vh10 maxY10 ws .finish fs).length +
      (zoneFrames vh10 maxY10 ws .rest fs).length = (fs.filter fun f => inWins ws f.1).length
  | [] => by simp [zoneFrames]
  | f :: fs => by
    have ih := zoneFrames_sum vh10 maxY10 ws fs
    unfold zoneFrames at ih ⊢
    cases hw : inWins ws f.1 <;> cases h : Fw.Device.Session.zoneOf vh10 maxY10 f.2 <;> simp [hw, h] <;> omega

/-- How many records of a kind, and their summed duration (hundredths of ms). -/
def cell (k : String) (rs : List Rec) : Nat × Nat :=
  let ks := rs.filter fun r => r.kind == k
  (ks.length, (ks.map (·.dur)).sum)

/-- The render work of records: summed duration of the render kinds that no render record encloses. -/
def renderWork (rs : List Rec) : Nat := ((rs.filter fun r => isRender r.kind && !r.nested).map (·.dur)).sum

/-- A nested record adds nothing to the render work. -/
theorem renderWork_nested (r : Rec) (rs : List Rec) (h : r.nested = true) : renderWork (r :: rs) = renderWork rs := by
  simp [renderWork, h]

/-- A record of another kind adds nothing to the render work. -/
theorem renderWork_other (r : Rec) (rs : List Rec) (h : isRender r.kind = false) : renderWork (r :: rs) = renderWork rs := by
  simp [renderWork, h]

/-- A top-level render record adds its duration. -/
theorem renderWork_top (r : Rec) (rs : List Rec) (h : isRender r.kind = true) (hn : r.nested = false) :
    renderWork (r :: rs) = r.dur + renderWork rs := by
  simp [renderWork, h, hn]

/-- Render work per frame in microseconds (hundredths of ms times 10, over the frames), 0 for a zone with no frame. -/
def perFrameUs (work frames : Nat) : Nat := if frames = 0 then 0 else 10 * work / frames

/-- No frame, no per-frame value. -/
theorem perFrameUs_no_frames (work : Nat) : perFrameUs work 0 = 0 := by simp [perFrameUs]

/-- The per-frame value never exceeds the whole work in microseconds. -/
theorem perFrameUs_le (work frames : Nat) : perFrameUs work frames ≤ 10 * work := by
  unfold perFrameUs
  split
  · omega
  · exact Nat.div_le_self _ _

/-- One zone of one window: its frames, the cells in `kinds` order, render work and render work per frame. -/
structure Prof where
  frames : Nat
  cells : List (String × Nat × Nat)
  work : Nat
  perFrame : Nat
deriving Repr, BEq

/-- The profile of zone `z` in the windows (page clock, half-open) from the records and the animation frames. -/
def profile (vh10 maxY10 : Int) (frames : List (Int × Int)) (off : Int) (ws : List (Int × Int)) (z : DZone) (rs : List Rec) : Prof :=
  let zr := zoneRecs vh10 maxY10 frames off ws z rs
  let n := (zoneFrames vh10 maxY10 ws z frames).length
  ⟨n, kinds.map fun k => (k, cell k zr), renderWork zr, perFrameUs (renderWork zr) n⟩

/-- The cells of a profile are in `kinds` order, one per kind. -/
theorem profile_cells_kinds (vh10 maxY10 : Int) (frames : List (Int × Int)) (off : Int) (ws : List (Int × Int)) (z : DZone) (rs : List Rec) :
    ((profile vh10 maxY10 frames off ws z rs).cells.map (·.1)) = kinds := by
  simp [profile, List.map_map, Function.comp_def]

/-! ## Reps and verdicts -/

/-- The element at index `n / 2` of the sorted values, 0 when there are none. -/
def medianNat (l : List Nat) : Nat := (l.mergeSort fun a b => decide (a ≤ b)).getD (l.length / 2) 0

/-- No values, median 0. -/
theorem medianNat_nil : medianNat [] = 0 := by simp [medianNat]

/-- The median is one of the values. -/
theorem medianNat_mem {l : List Nat} (h : l ≠ []) : medianNat l ∈ l := by
  have hl : l.length / 2 < (l.mergeSort fun a b => decide (a ≤ b)).length := by
    rw [List.length_mergeSort]
    have : 0 < l.length := List.length_pos_iff.2 h
    omega
  have hm : medianNat l ∈ l.mergeSort fun a b => decide (a ≤ b) := by
    unfold medianNat
    rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hl]
    exact List.getElem_mem _
  exact (List.mem_mergeSort).1 hm

/-- Which of two arms does less render work per frame in a zone: the per-rep values against the A/A pair, by the hitch rule of
`Fw.Gate.Smooth` (lower is better; `first` is the first arm). -/
def zoneVerdict (a b aa1 aa2 : List Nat) : Fw.Gate.Smooth.Verdict := Fw.Gate.Smooth.hitchVerdict a b aa1 aa2

/-- Fewer than `minReps` reps in any of the four is no verdict. -/
theorem zoneVerdict_insufficient (a b aa1 aa2 : List Nat) (h : Fw.Gate.Smooth.okN a b aa1 aa2 = false) :
    zoneVerdict a b aa1 aa2 = .insufficient :=
  Fw.Gate.Smooth.hitchVerdict_insufficient a b aa1 aa2 h

/-- Judging the arms the other way round swaps the verdict. -/
theorem zoneVerdict_swap (a b aa1 aa2 : List Nat) : zoneVerdict b a aa1 aa2 = (zoneVerdict a b aa1 aa2).swap :=
  Fw.Gate.Smooth.hitchVerdict_swap a b aa1 aa2

/-! ## The arms -/

/-- The arms that stay from the resolved flags of the rewrite arms (Session's dedup); the A/A control is outside it. -/
def armsOf (xs : List (DArm × List String)) : List DArm := dedupArms xs

/-- A look arm whose flags are the faithful rewrite's is dropped, the rewrite stays first. -/
theorem armsOf_same_dropped (a : List String) :
    (armsOf [(.rewrite, a), (.v2, a), (.look, a)]).head? = some .rewrite ∧ Fw.Device.Session.Arm.v2 ∉ armsOf [(.rewrite, a), (.v2, a), (.look, a)] := by
  constructor
  · exact dedupArms_head _ _ _
  · simp [armsOf, dedupArms, dedupAux, sameFlags_refl]

/-! ## Golden -/

private def recJ (r : Rec) : Json := toJson [toJson r.kind, toJson r.t, toJson r.dur, toJson r.nested]

private def profJ (p : Prof) : Json :=
  Json.mkObj [("frames", p.frames), ("work", p.work), ("perFrame", p.perFrame),
    ("cells", Json.arr (p.cells.map fun c => toJson [toJson c.1, toJson c.2.1, toJson c.2.2]).toArray)]

private def framesJ (fs : List (Int × Int)) : Json := Json.arr (fs.map fun f => toJson [f.1, f.2]).toArray

private def synthFrames : List (Int × Int) :=
  [(1000, 0), (1160, 420), (1320, 840), (1480, 1260), (1640, 5000), (1800, 9000), (1960, 17000), (2120, 17000), (2280, 17000)]

private def synthRecs : List Rec :=
  [⟨"RecalculateStyles", 1010, 80, false⟩, ⟨"Layout", 1015, 40, true⟩, ⟨"Paint", 1170, 60, false⟩,
   ⟨"Composite", 1330, 30, false⟩, ⟨"FunctionCall", 1335, 20, false⟩, ⟨"FireAnimationFrame", 1490, 10, false⟩,
   ⟨"Layout", 1650, 120, false⟩, ⟨"Layout", 1990, 90, false⟩, ⟨"Paint", 2130, 70, false⟩, ⟨"Paint", 2290, 500, false⟩,
   ⟨"Composite", 990, 25, false⟩, ⟨"TimerFire", 2200, 15, false⟩]

private def synthWins : List (Int × Int) := [(1000, 1500), (1700, 2200)]

private def synthCases : List Json :=
  let off : Int := 100
  let recs := synthRecs.map fun r => { r with t := r.t + off }
  [Json.mkObj [("kind", "profile"), ("vh10", 8440), ("maxY10", 21000), ("off", off), ("ws", toJson [[1000, 1500], [1700, 2200]]),
    ("frames", framesJ synthFrames), ("recs", Json.arr (recs.map recJ).toArray),
    ("zones", Json.mkObj ([Fw.Device.Session.Zone.hero, Fw.Device.Session.Zone.finish, Fw.Device.Session.Zone.rest].map fun z =>
      (z.name, profJ (profile 8440 21000 synthFrames off synthWins z recs))))]]

private def driftCases : List (Int × Int) := [(1800, 1800), (1800, 2300), (1800, 2301), (2300, 1800), (-40, 3000), (0, 0)]

private def medianCases : List (List Nat) := [[], [5], [3, 1, 2], [4, 4, 1, 9], [10, 20, 30, 40, 50], [7, 7, 7, 7, 7, 7]]

private def verdictCases : List (List Nat × List Nat × List Nat × List Nat) :=
  [([100, 110, 120, 130, 140], [300, 310, 320, 330, 340], [200, 205, 210, 215, 220], [201, 206, 211, 216, 221]),
   ([300, 310, 320, 330, 340], [100, 110, 120, 130, 140], [200, 205, 210, 215, 220], [201, 206, 211, 216, 221]),
   ([100, 110, 120, 130, 140], [130, 150, 160, 170, 180], [200, 205, 210, 215, 220], [201, 206, 211, 216, 221]),
   ([100, 110, 120, 130], [300, 310, 320, 330, 340], [200, 205, 210, 215, 220], [201, 206, 211, 216, 221]),
   ([100, 110, 120, 130, 140], [300, 310, 320, 330, 340], [100, 110, 120, 130, 140], [300, 310, 320, 330, 340])]

private def armCases : List (List (DArm × List String)) :=
  [[(.rewrite, []), (.v2, []), (.look, ["morph.tween:scroll-lock", "nav:earn-no-transition"])],
   [(.rewrite, []), (.v2, ["a:b"]), (.look, ["a:b"])],
   [(.rewrite, []), (.v2, []), (.look, [])],
   [(.rewrite, ["x:y"]), (.v2, []), (.look, ["x:y"])]]

/-- The lines of `packages/contracts/golden/measure/webkit-profile.jsonl`. -/
def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "kinds"), ("kinds", toJson kinds), ("render", toJson (kinds.filter isRender)), ("driftTol", driftTol)]).compress] ++
  (["RecalculateStyles", "Layout", "FunctionCall"].map fun k =>
    (Json.mkObj [("kind", "nested"), ("ancestors", toJson [k]), ("nested", nestedOf [k])]).compress) ++
  [(Json.mkObj [("kind", "nested"), ("ancestors", toJson (["FireAnimationFrame", "FunctionCall"] : List String)),
     ("nested", nestedOf ["FireAnimationFrame", "FunctionCall"])]).compress] ++
  (driftCases.map fun (a, b) =>
    (Json.mkObj [("kind", "drift"), ("a", a), ("b", b), ("ok", driftOk a b), ("mean", meanOffset a b)]).compress) ++
  (synthCases.map (·.compress)) ++
  (medianCases.map fun l => (Json.mkObj [("kind", "median"), ("values", toJson l), ("median", medianNat l)]).compress) ++
  (verdictCases.map fun (a, b, c, d) =>
    (Json.mkObj [("kind", "verdict"), ("a", toJson a), ("b", toJson b), ("aa1", toJson c), ("aa2", toJson d),
      ("verdict", (zoneVerdict a b c d).name)]).compress) ++
  (armCases.map fun xs =>
    (Json.mkObj [("kind", "arms"), ("flags", Json.arr (xs.map fun x => toJson x.2).toArray),
      ("kept", toJson ((armsOf xs).map Fw.Device.Session.Arm.code))]).compress) ++
  [(Json.mkObj [("kind", "perFrame"), ("cases", toJson ([(0, 0), (500, 0), (500, 7), (1234, 11)].map fun (w, n) =>
    toJson [w, n, perFrameUs w n]))]).compress]

/-- The bytes of the golden. -/
def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

/-- Print the golden, or with `--check <file>` compare its bytes; exit 1 when they differ. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"webkit-profile golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"webkit-profile golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

#guard driftOk 1800 2300 == true
#guard driftOk 1800 2301 == false
#guard (profile 8440 21000 synthFrames 100 synthWins .hero (synthRecs.map fun r => { r with t := r.t + 100 })).frames == 5

end Fw.Measure.WebKitProfile
