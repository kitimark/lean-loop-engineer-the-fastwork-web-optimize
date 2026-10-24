import Fw.Parts.MorphTween
import Fw.Console.BuildsOpen

/-! The end-of-page morph as a reducer over browser events (original N2:13017-13090) and its three bricks.
Statements in plain words: `research/notes/2026/10-2x-morph-end-bricks.md`. -/
namespace Fw.Parts.MorphEnd

open Fw.Parts.MorphTween (St rest dir taken push)

/-- Part id of brick A, the pin clamped to the real end. -/
def clampId : String := "morph.end.clamp"
/-- Part id of brick B, the flip hysteresis. -/
def flipId : String := "morph.end.flip"
/-- Part id of brick C, the pin released when a close starts. -/
def releaseId : String := "morph.end.release"
/-- Variant name of a brick that is off. -/
def faithfulV : String := "faithful"
/-- Variant name of a brick that is on. -/
def onV : String := "on"
/-- Brick B: px of net finger travel against the current goal that a flip needs within one touch. -/
def flipN : Rat := 16

/-- What a move handler reads from the page in the same event. -/
structure Read where
  scrollY : Rat
  arm : Bool
  now : Rat
  reduced : Bool
deriving Repr, BEq, DecidableEq

/-- A browser event that reaches the morph; `scroll` and `resize` are one engine frame with its readings. -/
inductive Ev where
  | touchstart (y : Option Rat)
  | touchmove (y : Option Rat) (r : Read)
  | wheel (delta : Rat) (r : Read)
  | scroll (y maxY : Rat)
  | resize (y maxY : Rat)
  | tick (now : Rat)
deriving Repr, BEq, DecidableEq

/-- What one event does: `preventDefault`, a push toward `goal` (a `flip` when the morph was active), a `scrollTo`. -/
structure Out where
  prevent : Bool := false
  goal : Option Rat := none
  flip : Bool := false
  write : Option Rat := none
deriving Repr, BEq, DecidableEq

/-- Reducer state: the tween, the last touch y, the pin, brick B's counter and new-touch mark, brick C's mark. -/
structure S where
  tw : St
  touchY : Rat
  pin : Rat
  ctr : Rat
  fresh : Bool
  rel : Bool
deriving Repr, BEq, DecidableEq

/-- The state at mount: at rest, pinned at the page's scrollY. -/
def init (y : Rat) : S := ⟨rest, 0, y, 0, false, false⟩

/-- The three places a brick changes the step: the restore target, whether a flip may happen, whether a close releases. -/
structure Hooks where
  target : Rat → Rat → Rat
  allow : Bool → Rat → Bool
  release : Bool

/-- The hooks of the original. -/
def base : Hooks := ⟨fun p _ => p, fun _ _ => true, false⟩

def absR (d : Rat) : Rat := if 0 ≤ d then d else -d

/-- A delta's travel against the current goal: up the page while open, down the page while closed. -/
def away (target d : Rat) : Rat := if target = 1 then -d else d

#guard away 1 (-20) == 20 && away 0 20 == 20 && away 1 5 == -5

/-- Brick B's counter after a delta: net travel against the goal, never below 0. -/
def ctrAfter (s : S) (d : Rat) : Rat := max 0 (s.ctr + away s.tw.target d)

/-- Brick C holds: a close has started and no open since. -/
def free (h : Hooks) (s : S) : Bool := h.release && s.rel

/-- The pin after a taken move: kept while active and held, else the page's scrollY. -/
def pinAfter (h : Hooks) (s : S) (r : Read) : Rat := if s.tw.isActive && !free h s then s.pin else r.scrollY

/-- A push toward `g` changes nothing: already heading there, or a flip brick B refuses. -/
def blocked (h : Hooks) (s : S) (d g : Rat) : Bool :=
  decide (s.tw.target = g ∧ s.tw.t = g) || (s.tw.isActive && !h.allow s.fresh (ctrAfter s d))

def kept (h : Hooks) (s : S) (d : Rat) (r : Read) : S × Out :=
  ({ s with pin := pinAfter h s r, ctr := ctrAfter s d }, { prevent := !free h s })

def applied (h : Hooks) (s : S) (r : Read) (g : Rat) : S × Out :=
  ({ s with tw := push s.tw g r.reduced r.now, pin := pinAfter h s r, ctr := 0, fresh := false, rel := decide (g = 0) },
    { prevent := !(h.release && decide (g = 0)), goal := some g, flip := s.tw.isActive })

/-- One touchmove or wheel delta (N2 `A`, `M`, `k`, `D`, `E`). -/
def moveStep (h : Hooks) (s : S) (d : Rat) (r : Read) : S × Out :=
  if taken s.tw.isActive d r.arm then
    match dir d with
    | none => kept h s d r
    | some g => if blocked h s d g then kept h s d r else applied h s r g
  else ({ s with ctr := ctrAfter s d }, {})

theorem moveStep_cases (h : Hooks) (s : S) (d : Rat) (r : Read) :
    (taken s.tw.isActive d r.arm = false ∧ moveStep h s d r = ({ s with ctr := ctrAfter s d }, {})) ∨
    (taken s.tw.isActive d r.arm = true ∧ (∀ g, dir d = some g → blocked h s d g = true) ∧
      moveStep h s d r = kept h s d r) ∨
    (∃ g, taken s.tw.isActive d r.arm = true ∧ dir d = some g ∧ blocked h s d g = false ∧
      moveStep h s d r = applied h s r g) := by
  unfold moveStep
  cases ht : taken s.tw.isActive d r.arm
  · exact Or.inl ⟨rfl, rfl⟩
  · cases hd : dir d with
    | none => exact Or.inr (Or.inl ⟨rfl, by simp, rfl⟩)
    | some g =>
      cases hb : blocked h s d g
      · exact Or.inr (Or.inr ⟨g, rfl, rfl, hb, by simp [hb]⟩)
      · exact Or.inr (Or.inl ⟨rfl, by simpa using hb, by simp [hb]⟩)

/-- One scroll or resize frame (N2 `L`): while active and not released, put the page back on the target. -/
def frameOut (h : Hooks) (s : S) (y m : Rat) : Out :=
  let tgt := h.target s.pin m
  { write := if s.tw.isActive && !(h.release && s.rel) && decide (y ≠ tgt) then some tgt else none }

/-- One event. -/
def step (h : Hooks) (s : S) : Ev → S × Out
  | .touchstart y => ({ s with touchY := y.getD 0, ctr := 0, fresh := true }, {})
  | .touchmove y r =>
    let y' := y.getD s.touchY
    moveStep h { s with touchY := y' } (s.touchY - y') r
  | .wheel d r => moveStep h s d r
  | .scroll y m => (s, frameOut h s y m)
  | .resize y m => (s, frameOut h s y m)
  | .tick now => (if s.tw.pending then { s with tw := Fw.Parts.MorphTween.frame s.tw now } else s, {})

/-- The state after a trace. -/
def final (h : Hooks) : S → List Ev → S
  | s, [] => s
  | s, e :: t => final h (step h s e).1 t

/-- Each event of a trace with what it did. -/
def trace (h : Hooks) : S → List Ev → List (Ev × Out)
  | _, [] => []
  | s, e :: t => (e, (step h s e).2) :: trace h (step h s e).1 t

def rd (y : Rat) (now : Rat) : Read := ⟨y, true, now, false⟩

#guard (step base (init 5227) (.touchmove (some 599) (rd 5292 0))).2 == {}
#guard (trace base (init 5000) [.touchstart (some 600), .touchmove (some 599) (rd 5292 0)]).map (·.2.goal) == [none, some 1]
#guard (trace base (init 5000) [.touchstart (some 600), .touchmove (some 599) (rd 5292 0), .scroll 5227 5227]).map (·.2.write)
  == [none, none, some 5292]
#guard (trace base (init 5000) [.touchstart (some 600), .touchmove (some 601) (rd 5292 0)]).map (·.2) == [{}, {}]
#guard (trace base (init 5000) [.touchstart (some 600), .touchmove (some (5995/10)) (rd 5292 0), .scroll 5227 5227]).map (·.2)
  == [{}, { prevent := true }, {}]
#guard (step base (init 5000) (.wheel 120 ⟨5100, false, 0, false⟩)).2 == {}
#guard (step base (init 5000) (.wheel 120 ⟨5100, true, 0, true⟩)).1.tw.value == 1

/-! ## The original -/

namespace Orig

/-- The original's state: tween, touch y `c`, pin `s`. -/
structure S where
  tw : St
  touchY : Rat
  pin : Rat
deriving Repr, BEq, DecidableEq

/-- N2 `A`/`M`: a taken push pins (from rest), prevents, and pushes toward its direction. -/
def move (s : S) (d : Rat) (r : Read) : S × Out :=
  let act := s.tw.isActive
  if taken act d r.arm then
    let s := { s with pin := if act then s.pin else r.scrollY }
    match dir d with
    | none => (s, { prevent := true })
    | some g =>
      if s.tw.target = g ∧ s.tw.t = g then (s, { prevent := true })
      else ({ s with tw := push s.tw g r.reduced r.now }, { prevent := true, goal := some g, flip := act })
  else (s, {})

/-- N2 `j`, `M`, `A`, `L`, `T`. -/
def step (s : S) : Ev → S × Out
  | .touchstart y => ({ s with touchY := y.getD 0 }, {})
  | .touchmove y r =>
    let y' := y.getD s.touchY
    move { s with touchY := y' } (s.touchY - y') r
  | .wheel d r => move s d r
  | .scroll y _ | .resize y _ =>
    (s, { write := if s.tw.isActive && decide (y ≠ s.pin) then some s.pin else none })
  | .tick now => (if s.tw.pending then { s with tw := Fw.Parts.MorphTween.frame s.tw now } else s, {})

def final : S → List Ev → S
  | s, [] => s
  | s, e :: t => final (step s e).1 t

def trace : S → List Ev → List (Ev × Out)
  | _, [] => []
  | s, e :: t => (e, (step s e).2) :: trace (step s e).1 t

end Orig

def S.orig (s : S) : Orig.S := ⟨s.tw, s.touchY, s.pin⟩

theorem orig_move (s : S) (d : Rat) (r : Read) :
    (moveStep base s d r).1.orig = (Orig.move s.orig d r).1 ∧ (moveStep base s d r).2 = (Orig.move s.orig d r).2 := by
  unfold moveStep Orig.move S.orig
  by_cases ht : taken s.tw.isActive d r.arm = true
  · simp only [ht, ite_true]
    cases hd : dir d with
    | none => simp [kept, pinAfter, free, base]
    | some g =>
      by_cases hs : s.tw.target = g ∧ s.tw.t = g
      · simp [hs, blocked, kept, pinAfter, free, base]
      · simp [hs, blocked, applied, pinAfter, free, base]
  · simp [ht]

theorem orig_step (s : S) (e : Ev) :
    (step base s e).1.orig = (Orig.step s.orig e).1 ∧ (step base s e).2 = (Orig.step s.orig e).2 := by
  cases e with
  | touchmove y r => exact orig_move _ _ _
  | wheel d r => exact orig_move _ _ _
  | tick now => cases hp : s.tw.pending <;> simp [step, Orig.step, S.orig, hp]
  | touchstart y => simp [step, Orig.step, S.orig]
  | scroll y m => refine ⟨rfl, ?_⟩; simp only [step, Orig.step, S.orig, frameOut, base]; by_cases ha : s.tw.isActive <;> by_cases hy : y = s.pin <;> simp [ha, hy]
  | resize y m => refine ⟨rfl, ?_⟩; simp only [step, Orig.step, S.orig, frameOut, base]; by_cases ha : s.tw.isActive <;> by_cases hy : y = s.pin <;> simp [ha, hy]

/-- With every brick at `faithful` the reducer is the original, event by event. -/
theorem faithful_eq_orig (s : S) (t : List Ev) :
    (final base s t).orig = Orig.final s.orig t ∧ trace base s t = Orig.trace s.orig t := by
  induction t generalizing s with
  | nil => exact ⟨rfl, rfl⟩
  | cons e t ih =>
    obtain ⟨h1, h2⟩ := orig_step s e
    obtain ⟨i1, i2⟩ := ih (step base s e).1
    refine ⟨?_, ?_⟩
    · simp only [final, Orig.final]; rw [i1, h1]
    · simp only [trace, Orig.trace]; rw [i2, h1, h2]

/-! ## Bricks and their composition -/

/-- The three bricks. -/
inductive Brick where
  | clamp
  | flip
  | release
deriving Repr, DecidableEq

/-- The part id of a brick. -/
def Brick.id : Brick → String
  | .clamp => clampId
  | .flip => flipId
  | .release => releaseId

/-- What a brick does to the hooks: A clamps the target, B gates flips, C releases. -/
def Brick.apply : Brick → Hooks → Hooks
  | .clamp, h => { h with target := fun p m => min (h.target p m) m }
  | .flip, h => { h with allow := fun f c => h.allow f c && (f || decide (flipN ≤ c)) }
  | .release, h => { h with release := true }

def applyAll (l : List Brick) (h : Hooks) : Hooks := l.foldr Brick.apply h

theorem apply_comm (a b : Brick) (h : Hooks) : a.apply (b.apply h) = b.apply (a.apply h) := by
  cases a <;> cases b <;> rfl

theorem applyAll_perm {l l' : List Brick} (p : l.Perm l') (h : Hooks) : applyAll l h = applyAll l' h := by
  induction p with
  | nil => rfl
  | cons x _ ih => simp only [applyAll, List.foldr] at *; rw [ih]
  | swap x y l => exact apply_comm y x _
  | trans _ _ ih1 ih2 => exact ih1.trans ih2

/-- A pick of each brick part: `true` is the variant `on`. -/
structure Cfg where
  clamp : Bool
  flip : Bool
  release : Bool
deriving Repr, BEq, DecidableEq

def Cfg.bricks (c : Cfg) : List Brick :=
  (if c.clamp then [.clamp] else []) ++ (if c.flip then [.flip] else []) ++ (if c.release then [.release] else [])

/-- The hooks of a pick. -/
def Cfg.hooks (c : Cfg) : Hooks := applyAll c.bricks base

def Cfg.faithful : Cfg := ⟨false, false, false⟩

/-- All 8 picks. -/
def Cfg.all : List Cfg :=
  [false, true].flatMap fun a => [false, true].flatMap fun b => [false, true].map fun r => ⟨a, b, r⟩

def vname (on : Bool) : String := if on then onV else faithfulV

/-- The pick as `part:variant` entries. -/
def Cfg.picks (c : Cfg) : List (String × String) :=
  [(clampId, vname c.clamp), (flipId, vname c.flip), (releaseId, vname c.release)]

def Cfg.ofPicks (ps : List (String × String)) : Cfg :=
  ⟨ps.lookup clampId == some onV, ps.lookup flipId == some onV, ps.lookup releaseId == some onV⟩

#guard Cfg.all.length == 8
#guard Cfg.all.all fun c => Cfg.ofPicks c.picks == c
#guard (Cfg.picks ⟨true, false, true⟩) == [("morph.end.clamp", "on"), ("morph.end.flip", "faithful"), ("morph.end.release", "on")]
#guard (Cfg.hooks ⟨true, false, false⟩).target 5292 5227 == 5227
#guard (Cfg.hooks ⟨false, true, false⟩).allow false 15 == false
#guard (Cfg.hooks ⟨false, true, false⟩).allow true 0 == true

theorem all_nodup : Cfg.all.Nodup := by decide

theorem mem_all (c : Cfg) : c ∈ Cfg.all := by
  cases c with | mk a b r => cases a <;> cases b <;> cases r <;> simp [Cfg.all]

theorem ofPicks_picks (c : Cfg) : Cfg.ofPicks c.picks = c := by
  cases c with | mk a b r => cases a <;> cases b <;> cases r <;> decide

theorem faithful_hooks : Cfg.faithful.hooks = base := rfl

/-- Any order of the picked bricks gives the same hooks. -/
theorem order_free (c : Cfg) (l : List Brick) (p : l.Perm c.bricks) : applyAll l base = c.hooks :=
  applyAll_perm p base

theorem hooks_target (c : Cfg) (p m : Rat) : c.hooks.target p m = if c.clamp then min p m else p := by
  cases c with | mk a b r => cases a <;> cases b <;> cases r <;> rfl

theorem hooks_allow (c : Cfg) (f : Bool) (a : Rat) :
    c.hooks.allow f a = (!c.flip || f || decide (flipN ≤ a)) := by
  cases c with | mk a b r => cases a <;> cases b <;> cases r <;> cases f <;> rfl

theorem hooks_release (c : Cfg) : c.hooks.release = c.release := by
  cases c with | mk a b r => cases a <;> cases b <;> cases r <;> rfl

open Fw.Console.BuildsOpen in
/-- The registry facts of the three brick parts: two variants, no requires, no conflicts. -/
def brickParts : List PartFact :=
  [clampId, flipId, releaseId].map fun i =>
    { id := i, variants := [faithfulV, onV], impls := [], requires := [], conflicts := [] }

open Fw.Console.BuildsOpen in
/-- The bricks add no refusal to any selection of any registry, `engine.scroll:unthrottle` included. -/
theorem bricks_no_rules (ps : List PartFact) (sel : List (String × String)) :
    ruleErrors (ps ++ brickParts) sel = ruleErrors ps sel := by
  simp [ruleErrors, brickParts, partErrors, List.lookup]

open Fw.Console.BuildsOpen in
def scrollFact : PartFact :=
  { id := "engine.scroll", variants := ["faithful", "batched", "unthrottle", "throttle-lift"], impls := [], requires := [],
    conflicts := [] }

open Fw.Console.BuildsOpen in
#guard validate (brickParts ++ [scrollFact]) []
    "?fw=morph.end.clamp:on,morph.end.flip:on,morph.end.release:on,engine.scroll:unthrottle"
  == .ok "?fw=morph.end.clamp:on,morph.end.flip:on,morph.end.release:on,engine.scroll:unthrottle"

/-! ## Event cadence (`engine.scroll:unthrottle`) -/

def Ev.isFrame : Ev → Bool
  | .scroll .. | .resize .. => true
  | _ => false

theorem step_frame (h : Hooks) (s : S) (e : Ev) (he : e.isFrame = true) : (step h s e).1 = s := by
  cases e <;> simp_all [Ev.isFrame, step]

/-- Frames change no decision: dropping or adding scroll and resize frames leaves the state. -/
theorem cadence_final (h : Hooks) (s : S) (t : List Ev) : final h s t = final h s (t.filter (!·.isFrame)) := by
  induction t generalizing s with
  | nil => rfl
  | cons e t ih =>
    by_cases he : e.isFrame = true
    · simp only [final, List.filter, he, Bool.not_true]; rw [step_frame h s e he]; exact ih s
    · simp only [final, List.filter, he, Bool.not_false]; exact ih _

/-- Frames change no decision: every other event does the same at any frame cadence. -/
theorem cadence_trace (h : Hooks) (s : S) (t : List Ev) :
    (trace h s t).filter (!·.1.isFrame) = trace h s (t.filter (!·.isFrame)) := by
  induction t generalizing s with
  | nil => rfl
  | cons e t ih =>
    by_cases he : e.isFrame = true
    · simp only [trace, List.filter, he, Bool.not_true]; rw [step_frame h s e he]; exact ih s
    · simp only [trace, List.filter, he, Bool.not_false]; rw [ih]

theorem frame_write (h : Hooks) (s : S) (y m : Rat) :
    step h s (.scroll y m) = (s, frameOut h s y m) ∧ step h s (.resize y m) = (s, frameOut h s y m) := ⟨rfl, rfl⟩

theorem mem_trace (h : Hooks) (s : S) (t : List Ev) (e : Ev) (o : Out) (hm : (e, o) ∈ trace h s t) :
    ∃ s', o = (step h s' e).2 := by
  induction t generalizing s with
  | nil => simp [trace] at hm
  | cons e' t ih =>
    simp only [trace, List.mem_cons, Prod.mk.injEq] at hm
    rcases hm with ⟨rfl, rfl⟩ | hm
    · exact ⟨s, rfl⟩
    · exact ih _ hm

/-! ## Hooks each part of the step reads -/

theorem moveStep_congr (h h' : Hooks) (ha : h.allow = h'.allow) (hr : h.release = h'.release) (s : S) (d : Rat)
    (r : Read) : moveStep h s d r = moveStep h' s d r := by
  obtain ⟨t, a, l⟩ := h
  obtain ⟨t', a', l'⟩ := h'
  cases ha; cases hr; rfl

theorem step_congr (h h' : Hooks) (ha : h.allow = h'.allow) (hr : h.release = h'.release) (s : S) (e : Ev) :
    (step h s e).1 = (step h' s e).1 := by
  cases e <;> simp only [step] <;> (try rw [moveStep_congr h h' ha hr])

theorem move_no_write (h : Hooks) (s : S) (d : Rat) (r : Read) : (moveStep h s d r).2.write = none := by
  rcases moveStep_cases h s d r with ⟨-, he⟩ | ⟨-, -, he⟩ | ⟨g, -, -, -, he⟩ <;> rw [he] <;> rfl

theorem write_frame (h : Hooks) (s : S) (e : Ev) (w : Rat) (hw : (step h s e).2.write = some w) :
    ∃ y m, (e = .scroll y m ∨ e = .resize y m) ∧ (step h s e).2 = frameOut h s y m := by
  cases e with
  | touchstart => simp [step] at hw
  | touchmove y r => simp only [step] at hw; rw [move_no_write] at hw; cases hw
  | wheel d r => simp only [step] at hw; rw [move_no_write] at hw; cases hw
  | scroll y m => exact ⟨y, m, Or.inl rfl, rfl⟩
  | resize y m => exact ⟨y, m, Or.inr rfl, rfl⟩
  | tick => simp [step] at hw

/-! ## Brick A: the clamp -/

/-- A: no restore write targets a scrollY above the frame's maxY. -/
theorem clamp_le (c : Cfg) (hc : c.clamp = true) (s : S) (e : Ev) (w : Rat) (hw : (step c.hooks s e).2.write = some w) :
    ∃ y m, (e = .scroll y m ∨ e = .resize y m) ∧ w ≤ m := by
  obtain ⟨y, m, he, ho⟩ := write_frame _ _ _ _ hw
  refine ⟨y, m, he, ?_⟩
  rw [ho] at hw
  simp only [frameOut, hooks_target, hc, ite_true] at hw
  split at hw
  · cases hw; exact Std.min_le_right
  · cases hw

theorem clamp_le_trace (c : Cfg) (hc : c.clamp = true) (s : S) (t : List Ev) (e : Ev) (o : Out) (w : Rat)
    (hm : (e, o) ∈ trace c.hooks s t) (hw : o.write = some w) : ∃ y m, (e = .scroll y m ∨ e = .resize y m) ∧ w ≤ m := by
  obtain ⟨s', rfl⟩ := mem_trace _ _ _ _ _ hm
  exact clamp_le c hc s' e w hw

/-- A: once the page rests at the real end below an overscroll pin, nothing is written. -/
theorem clamp_rest (c : Cfg) (hc : c.clamp = true) (s : S) (m : Rat) (hp : m ≤ s.pin) :
    (step c.hooks s (.scroll m m)).2.write = none := by
  have hm : min s.pin m = m := by grind
  simp [step, frameOut, hooks_target, hc, hm]

/-- Without A the same frame writes the overscroll pin back: the spring-back fight. -/
theorem faithful_fight (c : Cfg) (hc : c.clamp = false) (s : S) (m : Rat) (ha : s.tw.isActive = true)
    (hf : (c.release && s.rel) = false) (hp : m < s.pin) : (step c.hooks s (.scroll m m)).2.write = some s.pin := by
  have : m ≠ s.pin := fun h => by rw [h] at hp; exact Rat.lt_irrefl hp
  simp [step, frameOut, hooks_target, hooks_release, hc, ha, hf, this]

theorem clamp_hooks (c : Cfg) :
    { c with clamp := true }.hooks.allow = { c with clamp := false }.hooks.allow ∧
      { c with clamp := true }.hooks.release = { c with clamp := false }.hooks.release := by
  refine ⟨?_, ?_⟩
  · funext f a; simp [hooks_allow]
  · simp [hooks_release]

/-- A changes no state and no event other than a frame's write. -/
theorem clamp_only_writes (c : Cfg) (s : S) (t : List Ev) :
    final { c with clamp := true }.hooks s t = final { c with clamp := false }.hooks s t ∧
      (trace { c with clamp := true }.hooks s t).filter (!·.1.isFrame) =
        (trace { c with clamp := false }.hooks s t).filter (!·.1.isFrame) := by
  obtain ⟨ha, hr⟩ := clamp_hooks c
  induction t generalizing s with
  | nil => exact ⟨rfl, rfl⟩
  | cons e t ih =>
    have hs := step_congr _ _ ha hr s e
    obtain ⟨i1, i2⟩ := ih (step { c with clamp := true }.hooks s e).1
    refine ⟨?_, ?_⟩
    · simp only [final]; rw [i1, hs]
    · by_cases he : e.isFrame = true
      · simp only [trace, List.filter, he, Bool.not_true]; rw [i2, hs]
      · simp only [trace, List.filter, he, Bool.not_false]
        rw [i2, hs]
        cases e with
        | touchmove y r => simp only [step]; rw [moveStep_congr _ _ ha hr]
        | wheel d r => simp only [step]; rw [moveStep_congr _ _ ha hr]
        | _ => simp_all [Ev.isFrame, step]

/-- A writes what the original writes whenever the pin is at or below the frame's maxY. -/
theorem clamp_same_below (c : Cfg) (s : S) (y m : Rat) (hp : s.pin ≤ m) :
    frameOut { c with clamp := true }.hooks s y m = frameOut { c with clamp := false }.hooks s y m := by
  have hm : min s.pin m = s.pin := by grind
  simp [frameOut, hooks_target, hooks_release, hm]

/-! ## Brick B: the flip hysteresis -/

/-- Shape of every reachable state: the goal is 0 or 1, the tween aims at it, the counter is not negative. -/
def Inv (s : S) : Prop := (s.tw.target = 0 ∨ s.tw.target = 1) ∧ s.tw.t = s.tw.target ∧ 0 ≤ s.ctr

theorem inv_init (y : Rat) : Inv (init y) := by
  exact ⟨Or.inl rfl, rfl, Rat.le_refl⟩

theorem push_target (tw : St) (g : Rat) (red : Bool) (now : Rat) (hg : g = 0 ∨ g = 1) (ht : tw.t = tw.target) :
    ((push tw g red now).target = 0 ∨ (push tw g red now).target = 1) ∧ (push tw g red now).t = (push tw g red now).target := by
  unfold push
  split
  · exact ⟨by rename_i h; rw [h.1]; exact hg, ht⟩
  · split <;> exact ⟨hg, rfl⟩

theorem inv_move (h : Hooks) (s : S) (d : Rat) (r : Read) (hi : Inv s) : Inv (moveStep h s d r).1 := by
  obtain ⟨h1, h2, h3⟩ := hi
  have hc : 0 ≤ ctrAfter s d := by unfold ctrAfter; grind
  rcases moveStep_cases h s d r with ⟨-, he⟩ | ⟨-, -, he⟩ | ⟨g, -, hd, -, he⟩ <;> rw [he]
  · exact ⟨h1, h2, hc⟩
  · exact ⟨h1, h2, hc⟩
  · obtain ⟨p1, p2⟩ := push_target s.tw g r.reduced r.now (Fw.Parts.MorphTween.dir_target d g hd) h2
    exact ⟨p1, p2, Rat.le_refl⟩

theorem inv_step (h : Hooks) (s : S) (e : Ev) (hi : Inv s) : Inv (step h s e).1 := by
  cases e with
  | touchstart y => exact ⟨hi.1, hi.2.1, Rat.le_refl⟩
  | touchmove y r => exact inv_move _ _ _ _ hi
  | wheel d r => exact inv_move _ _ _ _ hi
  | scroll => exact hi
  | resize => exact hi
  | tick now =>
    simp only [step]
    split
    · exact hi
    · exact hi

theorem inv_final (h : Hooks) (s : S) (t : List Ev) (hi : Inv s) : Inv (final h s t) := by
  induction t generalizing s with
  | nil => exact hi
  | cons e t ih => exact ih _ (inv_step h s e hi)

/-- B: a flip under B needs a new touch since the last push, or the counter at `flipN`. -/
theorem flip_needs (c : Cfg) (hc : c.flip = true) (s : S) (d : Rat) (r : Read)
    (hf : (moveStep c.hooks s d r).2.flip = true) : s.fresh = true ∨ flipN ≤ ctrAfter s d := by
  rcases moveStep_cases c.hooks s d r with ⟨-, he⟩ | ⟨-, -, he⟩ | ⟨g, -, -, hb, he⟩ <;> rw [he] at hf
  · cases hf
  · cases hf
  · simp only [applied] at hf
    simp only [blocked, hooks_allow, hc, hf, Bool.not_true, Bool.false_or, Bool.true_and, Bool.or_eq_false_iff,
      Bool.not_eq_false', Bool.or_eq_true, decide_eq_true_eq] at hb
    exact hb.2

theorem dir_one (d : Rat) (h : dir d = some 1) : 1 ≤ d := by
  unfold dir Fw.Parts.MorphTween.deadzone at h
  by_cases h1 : (if 0 ≤ d then d else -d) < 1
  · simp [h1] at h
  · by_cases h2 : 0 < d
    · split at h1 <;> grind
    · simp [h1, h2] at h

theorem dir_zero (d : Rat) (h : dir d = some 0) : d ≤ -1 := by
  unfold dir Fw.Parts.MorphTween.deadzone at h
  by_cases h1 : (if 0 ≤ d then d else -d) < 1
  · simp [h1] at h
  · by_cases h2 : 0 < d
    · simp [h1, h2] at h
    · split at h1 <;> grind

theorem dir_small (d : Rat) (h : absR d < 1) : dir d = none := by
  unfold dir Fw.Parts.MorphTween.deadzone
  unfold absR at h
  simp [h]

/-- A flip's travel against the goal is the size of its delta. -/
theorem away_flip (s : S) (d g : Rat) (hi : Inv s) (hd : dir d = some g) (hn : ¬ (s.tw.target = g ∧ s.tw.t = g)) :
    away s.tw.target d = absR d := by
  obtain ⟨h1, h2, -⟩ := hi
  rcases Fw.Parts.MorphTween.dir_target d g hd with rfl | rfl
  · have := dir_zero d hd
    rcases h1 with h1 | h1
    · exact absurd ⟨h1, h2.trans h1⟩ hn
    · simp [away, absR, h1]; grind
  · have := dir_one d hd
    rcases h1 with h1 | h1
    · simp [away, absR, h1]; grind
    · exact absurd ⟨h1, h2.trans h1⟩ hn

theorem flip_hooks (c : Cfg) : { c with flip := true }.hooks.release = { c with flip := false }.hooks.release := by
  simp [hooks_release]

theorem flip_same_move (c : Cfg) (s : S) (d : Rat) (r : Read) (hi : Inv s) (hd : absR d < 1 ∨ flipN ≤ absR d) :
    moveStep { c with flip := true }.hooks s d r = moveStep { c with flip := false }.hooks s d r := by
  have hb : ∀ g, dir d = some g → blocked { c with flip := true }.hooks s d g = blocked { c with flip := false }.hooks s d g := by
    intro g hdir
    rcases hd with hd | hd
    · rw [dir_small d hd] at hdir; cases hdir
    · by_cases hn : s.tw.target = g ∧ s.tw.t = g
      · simp [blocked, hn]
      · have ha := away_flip s d g hi hdir hn
        have hle : flipN ≤ ctrAfter s d := by
          unfold ctrAfter; rw [ha]; have := hi.2.2; grind
        simp [blocked, hooks_allow, hle]
  unfold moveStep
  simp only [kept, applied, pinAfter, free, hooks_release]
  split
  · cases hdir : dir d with
    | none => rfl
    | some g => simp only [hb g hdir]
  · rfl

/-- The delta a move event carries in a given state. -/
def moveDelta (s : S) : Ev → Option Rat
  | .touchmove y _ => some (s.touchY - y.getD s.touchY)
  | .wheel d _ => some d
  | _ => none

theorem flip_same_step (c : Cfg) (s : S) (e : Ev) (hi : Inv s)
    (hd : ∀ d, moveDelta s e = some d → absR d < 1 ∨ flipN ≤ absR d) :
    step { c with flip := true }.hooks s e = step { c with flip := false }.hooks s e := by
  cases e with
  | touchmove y r =>
    simp only [step]
    exact flip_same_move c _ _ r hi (hd _ rfl)
  | wheel d r => exact flip_same_move c _ _ r hi (hd _ rfl)
  | _ => simp [step, frameOut, hooks_target, hooks_release]

/-- Every move of the trace, in the state it meets, is below the dead zone or at least `flipN`. -/
def AllBig (h : Hooks) : S → List Ev → Prop
  | _, [] => True
  | s, e :: t => (∀ d, moveDelta s e = some d → absR d < 1 ∨ flipN ≤ absR d) ∧ AllBig h (step h s e).1 t

/-- B: when every move is below the dead zone or at least `flipN`, B decides exactly as without it. -/
theorem flip_same (c : Cfg) (s : S) (t : List Ev) (hi : Inv s) (hb : AllBig { c with flip := false }.hooks s t) :
    trace { c with flip := true }.hooks s t = trace { c with flip := false }.hooks s t ∧
      final { c with flip := true }.hooks s t = final { c with flip := false }.hooks s t := by
  induction t generalizing s with
  | nil => exact ⟨rfl, rfl⟩
  | cons e t ih =>
    obtain ⟨h1, h2⟩ := hb
    have he := flip_same_step c s e hi h1
    obtain ⟨i1, i2⟩ := ih _ (inv_step _ s e hi) h2
    refine ⟨?_, ?_⟩
    · simp only [trace]; rw [he, i1]
    · simp only [final]; rw [he, i2]

/-- The counter's bound for a finger inside `[lo, hi]`: the room left against the current goal. -/
def room (lo hi : Rat) (s : S) : Rat := if s.tw.target = 1 then s.touchY - lo else hi - s.touchY

/-- A touch-only trace whose finger stays in `[lo, hi]`: moves, frames and tween frames, no new touch. -/
def InBand (lo hi : Rat) : Ev → Prop
  | .touchmove y _ => ∀ v, y = some v → lo ≤ v ∧ v ≤ hi
  | .scroll .. | .resize .. | .tick _ => True
  | _ => False

structure Band (lo hi : Rat) (s : S) : Prop where
  lo_le : lo ≤ s.touchY
  le_hi : s.touchY ≤ hi
  ctr_le : s.ctr ≤ room lo hi s
  not_fresh : s.fresh = false

theorem band_move (c : Cfg) (hc : c.flip = true) (lo hi : Rat) (hw : hi - lo < flipN) (s : S) (y : Option Rat)
    (r : Read) (hb : Band lo hi s) (hy : ∀ v, y = some v → lo ≤ v ∧ v ≤ hi) :
    (step c.hooks s (.touchmove y r)).2.flip = false ∧ Band lo hi (step c.hooks s (.touchmove y r)).1 := by
  obtain ⟨b1, b2, b3, b4⟩ := hb
  have hy' : lo ≤ y.getD s.touchY ∧ y.getD s.touchY ≤ hi := by
    cases y with
    | none => exact ⟨b1, b2⟩
    | some v => exact hy v rfl
  simp only [step]
  generalize y.getD s.touchY = v at hy' ⊢
  have hroom : ctrAfter { s with touchY := v } (s.touchY - v) ≤ room lo hi { s with touchY := v } := by
    unfold room at b3 ⊢; unfold ctrAfter away
    by_cases ht : s.tw.target = 1 <;> simp only [ht, ite_true, ite_false] at b3 ⊢ <;> grind
  have hsmall : ctrAfter { s with touchY := v } (s.touchY - v) < flipN := by
    unfold room at hroom; split at hroom <;> grind
  rcases moveStep_cases c.hooks { s with touchY := v } (s.touchY - v) r with
    ⟨-, he⟩ | ⟨-, -, he⟩ | ⟨g, -, hd, hbl, he⟩ <;> rw [he]
  · exact ⟨rfl, ⟨hy'.1, hy'.2, hroom, b4⟩⟩
  · exact ⟨rfl, ⟨hy'.1, hy'.2, hroom, b4⟩⟩
  · have hact : s.tw.isActive = false := by
      cases hact : s.tw.isActive
      · rfl
      · simp only [blocked, hooks_allow, hc, b4, hact, Bool.not_true, Bool.false_or, Bool.true_and,
          Bool.or_eq_false_iff, Bool.not_eq_false', decide_eq_true_eq] at hbl
        exact absurd hbl.2 (by grind)
    have h0 : ∀ s' : S, s'.touchY = v → 0 ≤ room lo hi s' := by
      intro s' hv; unfold room; split <;> grind
    exact ⟨by simp [applied, hact], ⟨hy'.1, hy'.2, h0 _ rfl, rfl⟩⟩

/-- B: a finger that wiggles inside a band narrower than `flipN`, with no new touch, never flips the goal. -/
theorem flip_band (c : Cfg) (hc : c.flip = true) (lo hi : Rat) (hw : hi - lo < flipN) (s : S) (t : List Ev)
    (hb : Band lo hi s) (ht : ∀ e ∈ t, InBand lo hi e) : ∀ p ∈ trace c.hooks s t, p.2.flip = false := by
  induction t generalizing s with
  | nil => simp [trace]
  | cons e t ih =>
    have he := ht e (List.mem_cons_self ..)
    have hrest := fun e' h => ht e' (List.mem_cons_of_mem _ h)
    have hstep : (step c.hooks s e).2.flip = false ∧ Band lo hi (step c.hooks s e).1 := by
      cases e with
      | touchmove y r => exact band_move c hc lo hi hw s y r hb he
      | scroll => exact ⟨rfl, hb⟩
      | resize => exact ⟨rfl, hb⟩
      | tick now =>
        simp only [step]
        refine ⟨by simp, ?_⟩
        obtain ⟨b1, b2, b3, b4⟩ := hb
        split
        · exact ⟨b1, b2, by unfold room at b3 ⊢; exact b3, b4⟩
        · exact ⟨b1, b2, b3, b4⟩
      | touchstart => exact absurd he id
      | wheel => exact absurd he id
    intro p hp
    simp only [trace, List.mem_cons] at hp
    rcases hp with rfl | hp
    · exact hstep.1
    · exact ih _ hstep.2 hrest p hp

/-- Right after any push the counter is 0 and no touch is new, so a band trace from there never flips. -/
theorem band_after_push (lo hi : Rat) (s : S) (h1 : lo ≤ s.touchY) (h2 : s.touchY ≤ hi) (hc : s.ctr = 0)
    (hf : s.fresh = false) : Band lo hi s := by
  refine ⟨h1, h2, ?_, hf⟩
  unfold room; rw [hc]; split <;> grind

/-! ## Brick C: the release -/

theorem release_rel (h : Hooks) (s : S) (e : Ev) (hr : s.rel = true) (hg : (step h s e).2.goal ≠ some 1) :
    (step h s e).1.rel = true := by
  have hm : ∀ s' : S, ∀ d r, s'.rel = true → (moveStep h s' d r).2.goal ≠ some 1 → (moveStep h s' d r).1.rel = true := by
    intro s' d r hr' hg'
    rcases moveStep_cases h s' d r with ⟨-, he⟩ | ⟨-, -, he⟩ | ⟨g, -, hd, -, he⟩ <;> rw [he] at hg' ⊢
    · exact hr'
    · exact hr'
    · rcases Fw.Parts.MorphTween.dir_target d g hd with rfl | rfl
      · simp [applied]
      · exact absurd rfl hg'
  cases e with
  | touchmove y r => exact hm _ _ _ hr hg
  | wheel d r => exact hm _ _ _ hr hg
  | tick now => simp only [step]; split <;> exact hr
  | _ => exact hr

/-- C: a close start releases the pin. -/
theorem release_starts (h : Hooks) (s : S) (e : Ev) (hg : (step h s e).2.goal = some 0) : (step h s e).1.rel = true := by
  have hm : ∀ s' : S, ∀ d r, (moveStep h s' d r).2.goal = some 0 → (moveStep h s' d r).1.rel = true := by
    intro s' d r hg'
    rcases moveStep_cases h s' d r with ⟨-, he⟩ | ⟨-, -, he⟩ | ⟨g, -, -, -, he⟩ <;> rw [he] at hg' ⊢
    · simp at hg'
    · simp [kept] at hg'
    · simp only [applied, Option.some.injEq] at hg'; subst hg'; simp [applied]
  cases e with
  | touchmove y r => exact hm _ _ _ hg
  | wheel d r => exact hm _ _ _ hg
  | tick now => simp only [step] at hg; cases hg
  | touchstart => simp [step] at hg
  | scroll => simp [step, frameOut] at hg
  | resize => simp [step, frameOut] at hg

/-- C: the close start itself and every later move until a re-open leave the page free to scroll. -/
theorem release_close_free (c : Cfg) (hc : c.release = true) (s : S) (e : Ev) (hg : (step c.hooks s e).2.goal = some 0) :
    (step c.hooks s e).2.prevent = false := by
  have hm : ∀ s' : S, ∀ d r, (moveStep c.hooks s' d r).2.goal = some 0 → (moveStep c.hooks s' d r).2.prevent = false := by
    intro s' d r hg'
    rcases moveStep_cases c.hooks s' d r with ⟨-, he⟩ | ⟨-, -, he⟩ | ⟨g, -, -, -, he⟩ <;> rw [he] at hg' ⊢ <;>
      simp_all [kept, applied, hooks_release]
  cases e with
  | touchmove y r => exact hm _ _ _ hg
  | wheel d r => exact hm _ _ _ hg
  | tick now => simp only [step] at hg; cases hg
  | touchstart => simp [step] at hg
  | scroll => simp [step, frameOut] at hg
  | resize => simp [step, frameOut] at hg

/-- C: once released, no restore write until the next open. -/
theorem release_quiet (c : Cfg) (hc : c.release = true) (s : S) (t : List Ev) (hr : s.rel = true)
    (hno : ∀ p ∈ trace c.hooks s t, p.2.goal ≠ some 1) : ∀ p ∈ trace c.hooks s t, p.2.write = none := by
  induction t generalizing s with
  | nil => simp [trace]
  | cons e t ih =>
    have hg : (step c.hooks s e).2.goal ≠ some 1 := hno (e, (step c.hooks s e).2) (by simp [trace])
    have hr' := release_rel _ s e hr hg
    have hw : (step c.hooks s e).2.write = none := by
      cases hwe : (step c.hooks s e).2.write with
      | none => rfl
      | some w =>
        obtain ⟨y, m, -, ho⟩ := write_frame _ _ _ _ hwe
        rw [ho] at hwe
        simp [frameOut, hooks_release, hc, hr] at hwe
    intro p hp
    simp only [trace, List.mem_cons] at hp
    rcases hp with rfl | hp
    · exact hw
    · exact ih _ hr' (fun q hq => hno q (by simp only [trace, List.mem_cons]; exact Or.inr hq)) p hp

/-- C: after a close starts, no restore write until the next open. -/
theorem release_after_close (c : Cfg) (hc : c.release = true) (s : S) (e : Ev) (t : List Ev)
    (hg : (step c.hooks s e).2.goal = some 0) (hno : ∀ p ∈ trace c.hooks (step c.hooks s e).1 t, p.2.goal ≠ some 1) :
    ∀ p ∈ trace c.hooks (step c.hooks s e).1 t, p.2.write = none :=
  release_quiet c hc _ t (release_starts _ s e hg) hno

theorem release_hooks (c : Cfg) :
    { c with release := true }.hooks.allow = { c with release := false }.hooks.allow ∧
      ∀ p m, { c with release := true }.hooks.target p m = { c with release := false }.hooks.target p m := by
  refine ⟨?_, ?_⟩
  · funext f a; simp [hooks_allow]
  · intro p m; simp [hooks_target]

theorem release_same_step (c : Cfg) (s : S) (e : Ev) (hr : s.rel = false)
    (hg : (step { c with release := false }.hooks s e).2.goal ≠ some 0) :
    step { c with release := true }.hooks s e = step { c with release := false }.hooks s e ∧
      (step { c with release := false }.hooks s e).1.rel = false := by
  obtain ⟨ha, ht⟩ := release_hooks c
  have hm : ∀ s' : S, ∀ d r, s'.rel = false → (moveStep { c with release := false }.hooks s' d r).2.goal ≠ some 0 →
      moveStep { c with release := true }.hooks s' d r = moveStep { c with release := false }.hooks s' d r ∧
        (moveStep { c with release := false }.hooks s' d r).1.rel = false := by
    intro s' d r hr' hg'
    have hb : ∀ g, blocked { c with release := true }.hooks s' d g = blocked { c with release := false }.hooks s' d g := by
      intro g; simp only [blocked, ha]
    have hk : kept { c with release := true }.hooks s' d r = kept { c with release := false }.hooks s' d r := by
      simp [kept, pinAfter, free, hr']
    rcases moveStep_cases { c with release := false }.hooks s' d r with ⟨ht, he⟩ | ⟨ht, hbl, he⟩ | ⟨g, ht, hd, hbl, he⟩
    · rw [he]; exact ⟨by simp [moveStep, ht], hr'⟩
    · rw [he]
      refine ⟨?_, hr'⟩
      simp only [moveStep, ht, ↓reduceIte]
      split
      · exact hk
      · rename_i g hd
        simp only [hb, hbl g hd, ↓reduceIte]; exact hk
    · rw [he] at hg' ⊢
      have hg0 : g ≠ 0 := by simpa [applied] using hg'
      refine ⟨?_, by simp [applied, hg0]⟩
      simp only [moveStep, ht, ↓reduceIte, hd, hb, hbl, Bool.false_eq_true]
      simp [applied, pinAfter, free, hr', hooks_release, hg0]
  cases e with
  | touchmove y r => exact hm _ _ _ hr hg
  | wheel d r => exact hm _ _ _ hr hg
  | scroll y m => simp [step, frameOut, ht, hooks_release, hr]
  | resize y m => simp [step, frameOut, ht, hooks_release, hr]
  | touchstart => exact ⟨rfl, hr⟩
  | tick now => refine ⟨rfl, ?_⟩; simp only [step]; split <;> exact hr

/-- C: a trace with no close start decides exactly as without C (the open path is unchanged). -/
theorem release_open_same (c : Cfg) (s : S) (t : List Ev) (hr : s.rel = false)
    (hno : ∀ p ∈ trace { c with release := false }.hooks s t, p.2.goal ≠ some 0) :
    trace { c with release := true }.hooks s t = trace { c with release := false }.hooks s t ∧
      final { c with release := true }.hooks s t = final { c with release := false }.hooks s t := by
  induction t generalizing s with
  | nil => exact ⟨rfl, rfl⟩
  | cons e t ih =>
    have hg := hno _ (by simp only [trace, List.mem_cons]; exact Or.inl rfl)
    obtain ⟨he, hr'⟩ := release_same_step c s e hr hg
    obtain ⟨i1, i2⟩ := ih _ hr' (fun q hq => hno q (by simp only [trace, List.mem_cons]; exact Or.inr hq))
    refine ⟨?_, ?_⟩
    · simp only [trace]; rw [he, i1]
    · simp only [final]; rw [he, i2]

/-! ## Every combination -/

/-- The 8 picks, each brick's claim holds whatever the other two are, and all are valid in the registry. -/
theorem all_combinations (c : Cfg) :
    c ∈ Cfg.all ∧
      (∀ l : List Brick, l.Perm c.bricks → applyAll l base = c.hooks) ∧
      (c.clamp = true → ∀ s e w, (step c.hooks s e).2.write = some w → ∃ y m, (e = .scroll y m ∨ e = .resize y m) ∧ w ≤ m) ∧
      (c.flip = true → ∀ s d r, (moveStep c.hooks s d r).2.flip = true →
        s.fresh = true ∨ flipN ≤ ctrAfter s d) ∧
      (c.release = true → ∀ s e t, (step c.hooks s e).2.goal = some 0 →
        (∀ p ∈ trace c.hooks (step c.hooks s e).1 t, p.2.goal ≠ some 1) →
        ∀ p ∈ trace c.hooks (step c.hooks s e).1 t, p.2.write = none) ∧
      (∀ ps sel, Fw.Console.BuildsOpen.ruleErrors (ps ++ brickParts) sel = Fw.Console.BuildsOpen.ruleErrors ps sel) :=
  ⟨mem_all c, fun l p => order_free c l p, fun hc s e w hw => clamp_le c hc s e w hw,
    fun hc s d r hf => flip_needs c hc s d r hf, fun hc s e t hg hno => release_after_close c hc s e t hg hno,
    bricks_no_rules⟩

end Fw.Parts.MorphEnd
