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

/-- The tracks' animation starts at the frame where the original mounts the panel. -/
theorem animStart_eq_mountStart (x : Nat → Tick) (t : Nat) :
    ((mountV x (t + 1) && !dormant x (t + 1)) && !(mountV x t && !dormant x t)) =
      (mountO x (t + 1) && !mountO x t) := by
  rw [animated_eq_mountO, animated_eq_mountO]

/-! ## The visual claim -/

/-- The panel at frame `t`, given the history its timed state starts from and whether it is mounted now. -/
abbrev Panel (Env : Type) := Env → Nat → (Nat → Bool) → Bool → Scene

/-- The panel as `MorphMountOpt` sees it: one mount history drives both inputs. -/
def single {Env : Type} (p : Panel Env) : Env → Nat → (Nat → Bool) → Scene := fun env t h => p env t h (h t)

/-- The variant's scene: mounted with the variant's history, timed state woken with the original's. -/
def armD {Env : Type} (base : Env → Nat → Scene) (p : Panel Env) (x : Env → Nat → Tick) (env : Env) (t : Nat) :
    Scene :=
  sceneOf (base env t) (p env t (mountO (x env)) (mountV (x env) t)) (mountV (x env) t)

/-- While the original has not mounted it, the panel draws nothing in the viewport, whatever its inputs. -/
def Hidden {Env : Type} (vp : Env → Fw.Engine.Rect) (p : Panel Env) (x : Env → Nat → Tick) : Prop :=
  ∀ env t (w : Nat → Bool) (b : Bool), mountO (x env) t = false → visible (vp env) (p env t w b) = []

theorem hiddenBefore_of_hidden {Env : Type} (vp : Env → Fw.Engine.Rect) (p : Panel Env) (x : Env → Nat → Tick)
    (hh : Hidden vp p x) : HiddenBefore vp (single p) x :=
  fun env t h hO => hh env t h (h t) hO

theorem visSame_dormant {Env : Type} (base : Env → Nat → Scene) (p : Panel Env) (x : Env → Nat → Tick)
    (vp : Env → Fw.Engine.Rect) (hh : Hidden vp p x) :
    VisSame E vp (armO base (single p) x) (armD base p x) := by
  intro env t
  unfold E armO armD sceneOf single
  cases h : mountO (x env) t with
  | true => rw [mountV_of_mountO (x env) t h]
  | false =>
    rw [visible_append, visible_append]
    cases mountV (x env) t
    · rfl
    · simp only [ite_true]; rw [hh env t _ _ h]; rfl

/-- A panel whose state reads only the current mount bit. -/
def Untimed {Env : Type} (p : Panel Env) : Prop := ∀ env t (w w' : Nat → Bool) b, p env t w b = p env t w' b

theorem phaseFree_of_untimed {Env : Type} (p : Panel Env) (hu : Untimed p) : PhaseFree (single p) := by
  intro env t h h' ht ht'
  unfold single
  rw [ht, ht', hu env t h h' true]

/-! ## The countdown's clock -/

/-- Frames up to `t` in which `w` holds. -/
def since (w : Nat → Bool) (t : Nat) : Nat := ((List.range (t + 1)).filter w).length

/-- The frame of the clock's latest refresh: it refreshes on waking and every `P` frames after. -/
def lastRefresh (P : Nat) (w : Nat → Bool) (t : Nat) : Nat := t + 1 - since w t + (since w t - 1) / P * P

#guard lastRefresh 2 (fun _ => true) 2 == 2
#guard lastRefresh 2 (fun t => t ≥ 1) 2 == 1
#guard lastRefresh 2 (fun t => t ≥ 1) 3 == 3
#guard lastRefresh 3 (fun t => t ≥ 2) 7 == 5

def clockBox (shown : Nat) : Fw.Engine.BoxVis :=
  ⟨⟨0, 0, 10, 10⟩, ⟨0, 0, 10, 10⟩, [("refreshed", toString shown)], ⟨1, 0, 0, 1, 0, 0⟩, 1, none, [], 0⟩

/-- A panel holding only the countdown, refreshed every `P` frames from the first frame of `w`. -/
def clockPanel (P : Nat) : Panel Unit := fun _ t w b => if b then [("clock", clockBox (lastRefresh P w t))] else []

/-- The countdown is timed: with the clock started at mount, two mount frames give two scenes. -/
theorem clock_not_phaseFree : ¬ PhaseFree (single (clockPanel 2)) := by
  intro hp
  have := hp () 2 (fun _ => true) (fun t => decide (t ≥ 1)) rfl rfl
  simp [single, clockPanel, lastRefresh, since, clockBox] at this
  exact absurd this (by decide)

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

theorem absorbed_nil (l : Layer) (rest : List Layer) : Absorbed (l :: rest) [] :=
  ⟨l, rest, rfl, fun _ h => absurd h List.not_mem_nil⟩

#guard (layerize (· == 1) [⟨0, ⟨0, 0, 100, 100⟩⟩, ⟨1, ⟨0, 0, 10, 10⟩⟩, ⟨0, ⟨50, 50, 10, 10⟩⟩]).map (·.why) ==
  [.direct, .plain]
#guard (layerize (· == 1) [⟨0, ⟨0, 0, 100, 100⟩⟩, ⟨1, ⟨0, 0, 10, 10⟩⟩, ⟨0, ⟨5, 5, 10, 10⟩⟩]).map (·.why) ==
  [.overlap, .direct, .plain]
#guard (layerize (fun _ => false) [⟨0, ⟨0, 0, 100, 100⟩⟩, ⟨0, ⟨5, 5, 10, 10⟩⟩]).length == 1
#guard absorbedB [⟨0, ⟨0, 0, 100, 100⟩, .plain⟩] [⟨0, ⟨5, 5, 10, 10⟩⟩]
#guard !absorbedB [⟨0, ⟨0, 0, 100, 100⟩, .plain⟩] [⟨1, ⟨5, 5, 10, 10⟩⟩]
#guard !absorbedB [⟨0, ⟨0, 0, 100, 100⟩, .plain⟩] [⟨0, ⟨95, 5, 10, 10⟩⟩]
#guard absorbedB [⟨0, ⟨0, 0, 100, 100⟩, .plain⟩] []
#guard !absorbedB [] []

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
