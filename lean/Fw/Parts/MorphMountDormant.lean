import Lean.Data.Json
import Fw.Engine.Visual
import Fw.Parts.MorphMountOpt
/-!
# morph.mount, variant `shift-dormant`: `shift`, with the columns' marquee animation off until the original mounts
Proof note: research/notes/2026/10-20-morph-layers.md.
-/
namespace Fw.Parts.MorphMountDormant

open Fw.Engine Fw.Parts.MorphMount Fw.Parts.MorphMountOpt

/-! ## The decision -/

/-- Dormant at frame `t`: the variant has mounted the panel and the original has not. -/
def dormant (x : Nat → Tick) (t : Nat) : Bool := mountV x t && !mountO x t

#guard dormant (fun _ => ⟨false, false, true⟩) 0 == false
#guard dormant (fun _ => ⟨false, false, true⟩) 1 == true
#guard dormant (fun t => ⟨t == 3, false, t == 0⟩) 3 == true
#guard dormant (fun t => ⟨t == 3, false, t == 0⟩) 4 == false
#guard dormant (fun t => ⟨false, t == 2, false⟩) 3 == false
#guard dormant (fun t => ⟨t == 0, false, false⟩) 1 == false

theorem dormant_iff (x : Nat → Tick) (t : Nat) :
    dormant x t = true ↔ mountV x t = true ∧ mountO x t = false := by
  unfold dormant; cases mountV x t <;> cases mountO x t <;> simp

theorem not_dormant_of_mountO (x : Nat → Tick) (t : Nat) (h : mountO x t = true) : dormant x t = false := by
  simp [dormant, h]

theorem not_dormant_of_not_mountV (x : Nat → Tick) (t : Nat) (h : mountV x t = false) : dormant x t = false := by
  simp [dormant, h]

/-- The tracks animate exactly when the original has mounted the panel. -/
theorem animated_eq_mountO (x : Nat → Tick) (t : Nat) : (mountV x t && !dormant x t) = mountO x t := by
  unfold dormant
  cases h : mountO x t
  · cases mountV x t <;> rfl
  · rw [mountV_of_mountO x t h]; rfl

/-! ## The visual claim -/

/-- The variant's scene: mounted with the variant's history, animated with the original's. -/
def armD {Env : Type} (base : Env → Nat → Scene) (panel : Env → Nat → (Nat → Bool) → Scene)
    (x : Env → Nat → Tick) (env : Env) (t : Nat) : Scene :=
  sceneOf (base env t) (panel env t (mountO (x env))) (mountV (x env) t)

theorem visSame_dormant {Env : Type} (base : Env → Nat → Scene) (panel : Env → Nat → (Nat → Bool) → Scene)
    (x : Env → Nat → Tick) (vp : Env → Fw.Engine.Rect) (hh : HiddenBefore vp panel x) :
    VisSame E vp (armO base panel x) (armD base panel x) := by
  intro env t
  unfold E armO armD sceneOf
  cases h : mountO (x env) t with
  | true => rw [mountV_of_mountO (x env) t h]
  | false =>
    rw [visible_append, visible_append]
    cases mountV (x env) t
    · rfl
    · simp only [ite_true]; rw [hh env t _ h]; rfl

/-! ## Layerization -/

/-- A paint chunk: `space` is its nearest directly composited transform (0: none), `rect` its visual rect. -/
structure Chunk where
  space : Nat
  rect : Fw.Engine.Rect
deriving Repr, DecidableEq

/-- Why a layer exists: a direct compositing reason, overlap with an earlier layer, or neither. -/
inductive Why where
  | direct
  | overlap
  | plain
deriving Repr, DecidableEq

/-- A composited layer: its space, its bounds and its reason. -/
structure Layer where
  space : Nat
  rect : Fw.Engine.Rect
  why : Why
deriving Repr, DecidableEq

def inside (c r : Fw.Engine.Rect) : Bool :=
  decide (r.x ≤ c.x) && decide (r.y ≤ c.y) && decide (c.x + c.w ≤ r.x + r.w) && decide (c.y + c.h ≤ r.y + r.h)

def hull (r c : Fw.Engine.Rect) : Fw.Engine.Rect :=
  if inside c r then r
  else
    let x := if r.x ≤ c.x then r.x else c.x
    let y := if r.y ≤ c.y then r.y else c.y
    let x' := if c.x + c.w ≤ r.x + r.w then r.x + r.w else c.x + c.w
    let y' := if c.y + c.h ≤ r.y + r.h then r.y + r.h else c.y + c.h
    ⟨x, y, x' - x, y' - y⟩

inductive Step where
  | merged (ls : List Layer)
  | overlap
  | free

/-- Blink's candidate walk, newest layer first (paint_artifact_compositor.cc:945-974@f842f52). -/
def walk (c : Chunk) : List Layer → Step
  | [] => .free
  | l :: ls =>
    if l.space == c.space then .merged ({ l with rect := hull l.rect c.rect } :: ls)
    else if l.rect.meets c.rect then .overlap
    else match walk c ls with
      | .merged ls' => .merged (l :: ls')
      | s => s

/-- One chunk into the layer list, newest first (paint_artifact_compositor.cc:927-938@f842f52). -/
def place (direct : Nat → Bool) (ls : List Layer) (c : Chunk) : List Layer :=
  if direct c.space && !(ls.any (·.space == c.space)) then ⟨c.space, c.rect, .direct⟩ :: ls
  else match walk c ls with
    | .merged ls' => ls'
    | .overlap => ⟨c.space, c.rect, .overlap⟩ :: ls
    | .free => ⟨c.space, c.rect, .plain⟩ :: ls

/-- The layers of a chunk list in paint order, newest first. -/
def layerize (direct : Nat → Bool) (cs : List Chunk) : List Layer := cs.foldl (place direct) []

theorem hull_within (r c : Fw.Engine.Rect) (h : inside c r = true) : hull r c = r := by
  simp [hull, h]

/-- Chunks inside the newest layer, in its space, change no layer. -/
def Absorbed (ls : List Layer) (cs : List Chunk) : Prop :=
  ∃ l rest, ls = l :: rest ∧ ∀ c ∈ cs, c.space = l.space ∧ inside c.rect l.rect = true

/-- `Absorbed`, decided. -/
def absorbedB (ls : List Layer) (cs : List Chunk) : Bool :=
  match ls with
  | [] => false
  | l :: _ => cs.all fun c => c.space == l.space && inside c.rect l.rect

theorem absorbed_of_absorbedB (ls : List Layer) (cs : List Chunk) (h : absorbedB ls cs = true) : Absorbed ls cs := by
  match ls, h with
  | l :: rest, h =>
    refine ⟨l, rest, rfl, fun c hc => ?_⟩
    simp only [absorbedB, List.all_eq_true, Bool.and_eq_true, beq_iff_eq] at h
    exact h c hc

theorem place_absorbed (direct : Nat → Bool) (l : Layer) (rest : List Layer) (c : Chunk)
    (hs : c.space = l.space) (hw : inside c.rect l.rect = true) : place direct (l :: rest) c = l :: rest := by
  simp [place, walk, hs, hull_within _ _ hw]

theorem foldl_absorbed (direct : Nat → Bool) (l : Layer) (rest : List Layer) :
    ∀ cs : List Chunk, (∀ c ∈ cs, c.space = l.space ∧ inside c.rect l.rect = true) →
      cs.foldl (place direct) (l :: rest) = l :: rest
  | [], _ => rfl
  | c :: cs, h => by
    have ⟨hs, hw⟩ := h c (by simp)
    simp only [List.foldl_cons, place_absorbed direct l rest c hs hw]
    exact foldl_absorbed direct l rest cs (fun d hd => h d (by simp [hd]))

/-- Absorbed chunks leave every later layer decision unchanged. -/
theorem layerize_absorbed (direct : Nat → Bool) (pre mid post : List Chunk)
    (h : Absorbed (layerize direct pre) mid) :
    layerize direct (pre ++ mid ++ post) = layerize direct (pre ++ post) := by
  obtain ⟨l, rest, hl, hc⟩ := h
  unfold layerize at *
  rw [List.foldl_append, List.foldl_append, List.foldl_append, hl, foldl_absorbed direct l rest mid hc]

/-- The chunks of one frame: page, then the panel (animated or not) when mounted, then the chunks painted after it. -/
def paint (pre post panelOn panelOff : List Chunk) (mounted animated : Bool) : List Chunk :=
  pre ++ (if mounted then (if animated then panelOn else panelOff) else []) ++ post

/-- **Layers.** Under `Absorbed`, the variant's layers equal the original's at every frame. -/
theorem layers_dormant_eq (direct : Nat → Bool) (pre post panelOn panelOff : List Chunk) (x : Nat → Tick)
    (h : Absorbed (layerize direct pre) panelOff) (t : Nat) :
    layerize direct (paint pre post panelOn panelOff (mountV x t) (mountV x t && !dormant x t)) =
      layerize direct (paint pre post panelOn panelOff (mountO x t) (mountO x t)) := by
  rw [animated_eq_mountO]
  cases hO : mountO x t with
  | true => rw [mountV_of_mountO x t hO]
  | false =>
    cases mountV x t
    · rfl
    · simp only [paint, ite_true, Bool.false_eq_true, ite_false, List.append_nil]
      exact layerize_absorbed direct pre panelOff post h

/-- Layer count of a run of `n` frames. -/
def census (layersAt : Nat → Nat) (n : Nat) : Nat := ((List.range n).map layersAt).sum

theorem census_dormant_eq (direct : Nat → Bool) (pre post panelOn panelOff : List Chunk) (x : Nat → Tick)
    (h : Absorbed (layerize direct pre) panelOff) (n : Nat) :
    census (fun t => (layerize direct (paint pre post panelOn panelOff (mountV x t) (mountV x t && !dormant x t))).length) n =
      census (fun t => (layerize direct (paint pre post panelOn panelOff (mountO x t) (mountO x t))).length) n := by
  unfold census
  congr 1
  exact List.map_congr_left (fun t _ => by rw [layers_dormant_eq direct pre post panelOn panelOff x h t])

/-! ## A ≤ 640 frame in the model -/

/-- Spaces 2, 3, 4: the three tracks, each with an active transform animation; space 1: the fixed nav header. -/
def exDirect (s : Nat) : Bool := s ≥ 1 && s ≤ 4

def exHeader : Fw.Engine.Rect := ⟨16, 8, 398, 52⟩
def exPre : List Chunk := [⟨0, ⟨0, 0, 430, 3000⟩⟩, ⟨1, exHeader⟩]
def exPost : List Chunk := [⟨1, ⟨16, 8, 398, 52⟩⟩]
def exOn : List Chunk :=
  [⟨2, ⟨20, -40, 135, 1348⟩⟩, ⟨1, ⟨150, 8, 136, 52⟩⟩, ⟨3, ⟨157, -40, 136, 1340⟩⟩, ⟨1, ⟨290, 8, 135, 52⟩⟩,
   ⟨4, ⟨294, -40, 135, 1612⟩⟩]
def exOff : List Chunk := [⟨1, ⟨20, 8, 135, 52⟩⟩, ⟨1, ⟨157, 8, 136, 52⟩⟩, ⟨1, ⟨294, 8, 120, 52⟩⟩]

#guard (layerize exDirect (exPre ++ exPost)).length == 2
#guard (layerize exDirect (exPre ++ exOff ++ exPost)).length == 2
#guard (layerize exDirect (exPre ++ exOn ++ exPost)).length == 8
#guard (layerize exDirect (exPre ++ exOn ++ exPost)).map (·.why) ==
  [.overlap, .direct, .overlap, .direct, .overlap, .direct, .direct, .plain]

#guard absorbedB (layerize exDirect exPre) exOff
#guard !absorbedB (layerize exDirect exPre) exOn
#guard !absorbedB [] exOff

/-! ## Golden rows for the TS replay -/

def tickSeqs : List (List (Bool × Bool × Bool)) :=
  [[(false, false, false), (false, false, true), (false, false, false), (true, false, false), (false, false, false)],
   [(true, false, false), (false, false, true), (false, false, false)],
   [(false, false, true), (false, true, false), (false, false, false)],
   [(false, false, false), (false, false, false)],
   [(false, false, true), (false, false, true), (false, false, false), (false, false, false)]]

def toTick (l : List (Bool × Bool × Bool)) (t : Nat) : Tick :=
  match l[t]? with
  | some (n, p, w) => ⟨n, p, w⟩
  | none => ⟨false, false, false⟩

def frameJson (x : Nat → Tick) (t : Nat) : Lean.Json :=
  Lean.Json.mkObj [("v", .bool (mountV x t)), ("o", .bool (mountO x t)), ("d", .bool (dormant x t))]

def line (fn : String) (inp : List (String × Lean.Json)) (out : Lean.Json) : String :=
  (Lean.Json.mkObj [("fn", .str fn), ("in", Lean.Json.mkObj inp), ("out", out)]).compress

/-- The golden lines `packages/contracts/golden/parts/morph.mount.dormant.jsonl`. -/
def lines : List String :=
  ([false, true].flatMap fun v => [false, true].map fun o =>
      line "dormant" [("mountedV", .bool v), ("mountedO", .bool o)] (.bool (v && !o))) ++
  tickSeqs.map fun s =>
    let x := toTick s
    line "dormantRun"
      [("ticks", .arr (s.map fun (n, p, w) => .arr #[.bool n, .bool p, .bool w]).toArray)]
      (.arr ((List.range (s.length + 1)).map (frameJson x)).toArray)

def goldenText : String := String.join (lines.map (· ++ "\n"))

/-- Print the golden text, or with `--check <file>` compare it; exit 1 on a difference. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText then
      IO.eprintln s!"dormant golden: {path} is up to date ({lines.length} lines)"
      return 0
    IO.eprintln s!"dormant golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print goldenText
    return 0

end Fw.Parts.MorphMountDormant
