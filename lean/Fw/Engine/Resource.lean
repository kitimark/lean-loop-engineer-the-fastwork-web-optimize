import Fw.Engine.WebKit

namespace Fw.Engine.Resource

open Fw.Engine Fw.Engine.WebKit

inductive Eng where
  | chromium | webkit
deriving Repr, DecidableEq, Inhabited

def Eng.name : Eng → String
  | .chromium => "chromium" | .webkit => "webkit"

inductive Res where
  | style | layout | paintRec | script | event | repaint | layers | composite | gpuMem | frames
deriving Repr, DecidableEq, Inhabited

def Res.all : List Res :=
  [.style, .layout, .paintRec, .script, .event, .repaint, .layers, .composite, .gpuMem, .frames]

def Res.name : Res → String
  | .style => "style" | .layout => "layout" | .paintRec => "paintRecords" | .script => "script"
  | .event => "eventDispatch" | .repaint => "repaintArea" | .layers => "layers" | .composite => "composite"
  | .gpuMem => "gpuMemory" | .frames => "framesRequested"

def Res.unit : Res → String
  | .repaint => "CSS px² x DPR² summed over a run" | .gpuMem => "bytes" | .layers => "layers"
  | .frames => "frames per run" | _ => "records per run"

def Res.gated : Res → Bool
  | .style | .layout | .paintRec | .script | .event | .repaint | .frames => true
  | .layers | .composite | .gpuMem => false

def Res.census : Res → Bool
  | .layers | .gpuMem => true
  | _ => false

def Res.stage : Eng → Res → String
  | _, .style => "style" | _, .layout => "layout" | _, .paintRec => "paint" | _, .repaint => "paint"
  | _, .script => "script" | _, .event => "script" | _, .frames => "script"
  | _, .layers => "commit" | _, .gpuMem => "commit"
  | .chromium, .composite => "comp" | .webkit, .composite => "commit"

inductive Sign where
  | down | same | up | unknown
deriving Repr, DecidableEq, Inhabited

def Sign.name : Sign → String
  | .down => "down" | .same => "same" | .up => "up" | .unknown => "unknown"

def signOf (b f : Nat) : Sign := if f < b then .down else if b < f then .up else .same

def pairSign (b f : Nat × Nat) : Sign :=
  if f = b then .same
  else if f.1 ≤ b.1 ∧ f.2 ≤ b.2 then .down
  else if b.1 ≤ f.1 ∧ b.2 ≤ f.2 then .up
  else .unknown

def stageSign (b f : Work) (s : Stage) : Sign := pairSign (b.passes s, b.units s) (f.passes s, f.units s)

theorem pairSign_not_up {b f : Nat × Nat} (h1 : f.1 ≤ b.1) (h2 : f.2 ≤ b.2) : pairSign b f ≠ .up := by
  unfold pairSign; split
  · simp
  · simp [h1, h2]

theorem pairSign_down {b f : Nat × Nat} (h1 : f.1 ≤ b.1) (h2 : f.2 ≤ b.2) (h : f.1 < b.1 ∨ f.2 < b.2) :
    pairSign b f = .down := by
  have hne : f ≠ b := by rintro rfl; omega
  simp [pairSign, hne, h1, h2]

theorem stageSign_le {b f : Work} (h : f.le b) (s : Stage) : stageSign b f s ≠ .up :=
  pairSign_not_up (h.1 s).1 (h.1 s).2

theorem stageSign_lt {b f : Work} (h : f.le b) (s : Stage) (hs : f.passes s < b.passes s ∨ f.units s < b.units s) :
    stageSign b f s = .down :=
  pairSign_down (h.1 s).1 (h.1 s).2 hs

#guard signOf 5 3 == .down && signOf 3 5 == .up && signOf 4 4 == .same
#guard pairSign (1, 4) (0, 4) == .down && pairSign (1, 4) (1, 5) == .up && pairSign (1, 4) (1, 4) == .same
#guard pairSign (1, 4) (0, 5) == .unknown

def repaintPx (dpr cssArea frames : Nat) : Nat := cssArea * dpr ^ 2 * frames

theorem repaintPx_mono {dpr a a' n n' : Nat} (ha : a ≤ a') (hn : n ≤ n') : repaintPx dpr a n ≤ repaintPx dpr a' n' :=
  Nat.mul_le_mul (Nat.mul_le_mul_right _ ha) hn

theorem repaintPx_dpr3 (a n : Nat) : repaintPx 3 a n = 9 * a * n := by
  simp [repaintPx, Nat.mul_comm, Nat.mul_left_comm]

def changePx (own : Bool) (hostPx a : Nat) (frontValid : Bool) : Nat := if own then 0 else displayPx hostPx a frontValid

theorem pushed_repaint (hostPx a : Nat) (v : Bool) (h : a ≤ hostPx) :
    changePx true hostPx a v = 0 ∧ a ≤ changePx false hostPx a v ∧ changePx false hostPx a v ≤ hostPx :=
  ⟨rfl, display_bounds hostPx a v h⟩

theorem pushed_rise (hostPx a : Nat) (v : Bool) (h : a ≤ hostPx) (ha : 0 < a) :
    changePx true hostPx a v < changePx false hostPx a v :=
  Nat.lt_of_lt_of_le ha (pushed_repaint hostPx a v h).2.1

theorem tween_repaint (a n : Nat) (l : List Bool) :
    a ≤ reattachPaint a (false :: true :: l) ∧ reattachPaint a (List.replicate n true) = 0 := by
  refine ⟨(promote_tween a l).1, ?_⟩
  have := strip_no_reattach a n false false
  simpa [coverageAttached] using this

#guard changePx true 10000 30 true == 0 && changePx false 10000 30 true == 30 && changePx false 10000 30 false == 10000
#guard repaintPx 3 100 2 == 1800

/-- One mebibyte (`WTF/wtf/StdLibExtras.h:148-150@862f17d`). -/
def MiB : Nat := 1024 * 1024

/-- The jetsam fallback when the process limit is unknown (`WTF/wtf/AvailableMemory.cpp:89-97@862f17d`). -/
def fallbackJetsam : Nat := 840 * MiB

/-- WebKit's RAM size under a jetsam limit: the limit rounded up to 128 MiB (`WTF/wtf/AvailableMemory.cpp:145-151@862f17d`,
`RAMSize.cpp:44-47`). -/
def ramUnder (lim : Nat) : Nat := (lim + 128 * MiB - 1) / (128 * MiB) * (128 * MiB)

/-- Half of min(3 GiB, RAM size) (`WTF/wtf/MemoryPressureHandler.cpp:46-48,155-156,375@862f17d`). -/
def conservativeAt (ram : Nat) : Nat := min (3 * 1024 * MiB) ram / 2

def budgetB : Nat := 210 * MiB

theorem budgetB_quarter : 4 * budgetB = fallbackJetsam := by decide

theorem conservative_fallback : conservativeAt (ramUnder fallbackJetsam) = 448 * MiB := by decide

theorem budgetB_le_half : 2 * budgetB ≤ conservativeAt (ramUnder fallbackJetsam) := by decide

theorem budgetB_bytes : budgetB = 220200960 := by decide

/-- Bytes per pixel of an RGBA8 backing store (`WC/platform/graphics/ContentsFormat.h:48-56@862f17d`). -/
def bytesPerPx : Nat := 4

/-- The tile side in device pixels (`WC/platform/graphics/ca/TileController.h:58@862f17d`). -/
def tileSide : Nat := 512

/-- The iOS width or height in CSS px above which a layer is tiled (`GraphicsLayerCA.cpp:100-101,4853-4856@862f17d`). -/
def tiledAbove : Nat := 1280

structure Layer where
  w : Nat
  h : Nat
  backed : Bool
  attached : Bool
deriving Repr, DecidableEq

def tileCount (side : Nat) : Nat := (side + tileSide - 1) / tileSide

def layerBytes (dpr : Nat) (l : Layer) : Nat :=
  if l.backed && l.attached then
    (if tiledAbove < max l.w l.h then tileCount (l.w * dpr) * tileCount (l.h * dpr) * tileSide ^ 2
      else l.w * dpr * (l.h * dpr)) * bytesPerPx
  else 0

def gpuBytes (dpr : Nat) (ls : List Layer) : Nat := (ls.map (layerBytes dpr)).sum

def memFits (B peak : Nat) : Bool := decide (peak ≤ B)

theorem unbacked_zero (dpr w h : Nat) (a : Bool) : layerBytes dpr ⟨w, h, false, a⟩ = 0 := by simp [layerBytes]

theorem detached_zero (dpr w h : Nat) (b : Bool) :
    layerBytes dpr ⟨w, h, b, coverageAttached false true false⟩ = 0 := by simp [layerBytes, coverageAttached]

theorem gpuBytes_append (dpr : Nat) (xs ys : List Layer) : gpuBytes dpr (xs ++ ys) = gpuBytes dpr xs + gpuBytes dpr ys := by
  simp [gpuBytes]

theorem gpuBytes_add_zero (dpr : Nat) (xs ys : List Layer) (h : ∀ y ∈ ys, layerBytes dpr y = 0) :
    gpuBytes dpr (xs ++ ys) = gpuBytes dpr xs := by
  rw [gpuBytes_append]
  have : gpuBytes dpr ys = 0 := by
    induction ys with
    | nil => rfl
    | cons y ys ih =>
      simp only [gpuBytes, List.map_cons, List.sum_cons] at ih ⊢
      rw [h y (List.mem_cons_self ..), ih (fun z hz => h z (List.mem_cons_of_mem _ hz))]
  omega

#guard layerBytes 3 ⟨100, 50, true, true⟩ == 300 * 150 * 4
#guard layerBytes 3 ⟨100, 50, true, false⟩ == 0 && layerBytes 3 ⟨100, 50, false, true⟩ == 0
#guard layerBytes 3 ⟨390, 1300, true, true⟩ == 3 * 8 * 512 ^ 2 * 4
#guard tileCount 1170 == 3 && tileCount 512 == 1 && tileCount 513 == 2
#guard memFits budgetB 211786247 && !memFits budgetB 220200961 && memFits budgetB budgetB

structure Range where
  lo : Nat
  hi : Nat
deriving Repr, DecidableEq

def measuredSign (b f : Range) (tol : Nat) : Sign :=
  if f.hi + tol < b.lo then .down else if b.hi + tol < f.lo then .up else .same

def slowWalk (baseHiMs armLoMs : Nat) : Bool := decide (3 * baseHiMs < 2 * armLoMs)

inductive Check where
  | agree | disagree | unresolved | unpredicted | confounded
deriving Repr, DecidableEq, Inhabited

def Check.name : Check → String
  | .agree => "agree" | .disagree => "disagree" | .unresolved => "unresolved" | .unpredicted => "unpredicted"
  | .confounded => "confounded"

def check (r : Res) (slow : Bool) (p m : Sign) : Check :=
  if slow && !r.census then .confounded
  else if p = .unknown then .unpredicted
  else if p = m then .agree
  else if m = .same then .unresolved
  else .disagree

theorem check_confounded (r : Res) (p m : Sign) (h : r.census = false) : check r true p m = .confounded := by
  simp [check, h]

theorem check_unpredicted (r : Res) (s : Bool) (m : Sign) (h : (s && !r.census) = false) :
    check r s .unknown m = .unpredicted := by
  simp [check, h]

theorem check_agree (r : Res) (s : Bool) (p : Sign) (h : (s && !r.census) = false) (hp : p ≠ .unknown) :
    check r s p p = .agree := by
  simp [check, h, hp]

theorem check_unresolved (r : Res) (s : Bool) (p : Sign) (h : (s && !r.census) = false) (hp : p ≠ .unknown)
    (hs : p ≠ .same) : check r s p .same = .unresolved := by
  simp [check, h, hp, hs]

theorem check_disagree_iff (r : Res) (s : Bool) (p m : Sign) :
    check r s p m = .disagree ↔ (s && !r.census) = false ∧ p ≠ .unknown ∧ p ≠ m ∧ m ≠ .same := by
  cases s <;> cases r <;> cases p <;> cases m <;> decide

#guard measuredSign ⟨1569, 1608⟩ ⟨1801, 1939⟩ 0 == .up && measuredSign ⟨646, 651⟩ ⟨627, 631⟩ 0 == .down
#guard measuredSign ⟨616, 632⟩ ⟨621, 631⟩ 0 == .same && measuredSign ⟨10, 12⟩ ⟨13, 14⟩ 1 == .same
#guard slowWalk 4077 6791 && !slowWalk 4077 3646
#guard check .style true .down .down == .confounded && check .layers true .down .down == .agree
#guard check .style false .unknown .up == .unpredicted && check .style false .down .same == .unresolved
#guard check .style false .down .up == .disagree && check .style false .same .up == .disagree

end Fw.Engine.Resource
