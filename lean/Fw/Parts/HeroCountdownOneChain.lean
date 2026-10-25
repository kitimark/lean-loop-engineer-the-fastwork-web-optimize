import Lean.Data.Json

/-!
# hero.countdown `one-chain`: the per-digit rAF chains run inside one shared-loop callback
Same steps, states, writes and frames as `faithful`; one rAF callback per frame instead of one per rolling digit.
-/
namespace Fw.Parts.HeroCountdownOneChain

section Frame
variable {σ W : Type}

/-- The digit states with digit `d` replaced by `x`. -/
def setAt (s : Nat → σ) (d : Nat) (x : σ) : Nat → σ := fun e => if e = d then x else s e

/-- Digit `d`'s spring step at frame time `t`: only `d`'s state changes, and `d`'s faces are written. -/
def stepDigit (f : Nat → Rat → σ → σ) (w : Nat → σ → List W) (t : Rat) (x : (Nat → σ) × List W) (d : Nat) :
    (Nat → σ) × List W :=
  let y := f d t (x.1 d)
  (setAt x.1 d y, x.2 ++ w d y)

/-- One frame of the engine: its rAF callbacks in registration order, each called once with the frame's timestamp,
each one FireAnimationFrame and one FunctionCall; callbacks registered during the frame wait for the next one
(Chromium `frame_request_callback_collection.cc:86,99-125`@f842f52, WebKit
`ScriptedAnimationController.cpp:156,162,178-200`@862f17d). -/
def runCbs (cbs : List ((Nat → σ) × List W → (Nat → σ) × List W)) (x : (Nat → σ) × List W) :
    (Nat → σ) × List W :=
  cbs.foldl (fun x c => c x) x

/-- `faithful`: one own rAF callback per registered chain. -/
def faithfulCbs (f : Nat → Rat → σ → σ) (w : Nat → σ → List W) (R : List Nat) (t : Rat) :
    List ((Nat → σ) × List W → (Nat → σ) × List W) :=
  R.map fun d x => stepDigit f w t x d

/-- `one-chain`: one shared-loop callback that steps the registered chains in order, none while there are none. -/
def oneChainCbs (f : Nat → Rat → σ → σ) (w : Nat → σ → List W) (R : List Nat) (t : Rat) :
    List ((Nat → σ) × List W → (Nat → σ) × List W) :=
  if R.isEmpty then [] else [fun x => R.foldl (stepDigit f w t) x]

theorem oneChain_frame_eq (f : Nat → Rat → σ → σ) (w : Nat → σ → List W) (R : List Nat) (t : Rat)
    (x : (Nat → σ) × List W) : runCbs (oneChainCbs f w R t) x = runCbs (faithfulCbs f w R t) x := by
  cases R with
  | nil => rfl
  | cons d ds => simp [runCbs, oneChainCbs, faithfulCbs, List.foldl_map]

theorem faithfulCbs_length (f : Nat → Rat → σ → σ) (w : Nat → σ → List W) (R : List Nat) (t : Rat) :
    (faithfulCbs f w R t).length = R.length := by simp [faithfulCbs]

theorem oneChainCbs_length (f : Nat → Rat → σ → σ) (w : Nat → σ → List W) (R : List Nat) (t : Rat) :
    (oneChainCbs f w R t).length = min 1 R.length := by
  cases R <;> simp [oneChainCbs]

/-- The states after stepping the digits of `o` in order. -/
def frameStates (f : Nat → Rat → σ → σ) (t : Rat) (o : List Nat) (s : Nat → σ) : Nat → σ :=
  o.foldl (fun s d => setAt s d (f d t (s d))) s

theorem stepDigit_states (f : Nat → Rat → σ → σ) (w : Nat → σ → List W) (t : Rat) :
    ∀ (o : List Nat) (s : Nat → σ) (ws : List W), (o.foldl (stepDigit f w t) (s, ws)).1 = frameStates f t o s
  | [], _, _ => rfl
  | _ :: ds, _, _ => stepDigit_states f w t ds _ _

theorem frameStates_not_mem (f : Nat → Rat → σ → σ) (t : Rat) (d : Nat) :
    ∀ (o : List Nat) (s : Nat → σ), d ∉ o → frameStates f t o s d = s d
  | [], _, _ => rfl
  | e :: es, s, h => by
    simp only [List.mem_cons, not_or] at h
    simp only [frameStates, List.foldl_cons]
    rw [← frameStates, frameStates_not_mem f t d es _ h.2]
    simp [setAt, h.1]

theorem frameStates_self (f : Nat → Rat → σ → σ) (t : Rat) (d : Nat) :
    ∀ (o : List Nat) (s : Nat → σ), o.Nodup → d ∈ o → frameStates f t o s d = f d t (s d)
  | [], _, _, h => by cases h
  | e :: es, s, hn, h => by
    simp only [List.nodup_cons] at hn
    simp only [frameStates, List.foldl_cons]
    rw [← frameStates]
    by_cases hde : d = e
    · subst hde
      rw [frameStates_not_mem f t d es _ hn.1]
      simp [setAt]
    · have hm : d ∈ es := by simpa [hde] using h
      rw [frameStates_self f t d es _ hn.2 hm]
      simp [setAt, hde]

theorem flatMap_congr_mem {α β : Type} (g h : α → List β) :
    ∀ l : List α, (∀ a ∈ l, g a = h a) → l.flatMap g = l.flatMap h
  | [], _ => rfl
  | a :: as, hl => by
    simp only [List.flatMap_cons]
    rw [hl a (by simp), flatMap_congr_mem g h as fun b hb => hl b (by simp [hb])]

theorem stepDigit_writes (f : Nat → Rat → σ → σ) (w : Nat → σ → List W) (t : Rat) :
    ∀ (o : List Nat) (s : Nat → σ) (ws : List W), o.Nodup →
      (o.foldl (stepDigit f w t) (s, ws)).2 = ws ++ o.flatMap fun d => w d (f d t (s d))
  | [], _, _, _ => by simp
  | d :: ds, s, ws, hn => by
    simp only [List.nodup_cons] at hn
    simp only [List.foldl_cons, stepDigit]
    rw [stepDigit_writes f w t ds _ _ hn.2, List.flatMap_cons, List.append_assoc]
    congr 2
    apply flatMap_congr_mem
    intro e he
    have : e ≠ d := fun h => hn.1 (h ▸ he)
    simp [setAt, this]

theorem setAt_step_comm (f : Nat → Rat → σ → σ) (t : Rat) (s : Nat → σ) (x y : Nat) :
    (fun s d => setAt s d (f d t (s d))) ((fun s d => setAt s d (f d t (s d))) s x) y =
      (fun s d => setAt s d (f d t (s d))) ((fun s d => setAt s d (f d t (s d))) s y) x := by
  by_cases hxy : x = y
  · subst hxy; rfl
  · funext e
    have hyx : y ≠ x := fun h => hxy h.symm
    by_cases hex : e = x
    · subst hex; simp [setAt, hxy]
    · by_cases hey : e = y
      · subst hey; simp [setAt, hyx]
      · simp [setAt, hex, hey]

/-- **Any iteration order of the active digits gives the same states and the same writes, up to order.** -/
theorem order_perm (f : Nat → Rat → σ → σ) (w : Nat → σ → List W) (t : Rat) (o R : List Nat) (hp : o.Perm R)
    (hn : R.Nodup) (s : Nat → σ) (ws : List W) :
    (o.foldl (stepDigit f w t) (s, ws)).1 = (R.foldl (stepDigit f w t) (s, ws)).1 ∧
      (o.foldl (stepDigit f w t) (s, ws)).2.Perm (R.foldl (stepDigit f w t) (s, ws)).2 := by
  have ho : o.Nodup := hp.nodup_iff.mpr hn
  refine ⟨?_, ?_⟩
  · rw [stepDigit_states, stepDigit_states]
    exact hp.foldl_eq' (fun x _ y _ z => setAt_step_comm f t z x y) s
  · rw [stepDigit_writes f w t o s ws ho, stepDigit_writes f w t R s ws hn]
    exact (hp.flatMap_right _).append_left ws

end Frame

#guard (oneChainCbs (σ := Nat) (W := Nat) (fun _ _ x => x) (fun _ _ => []) [] 0).length == 0
#guard (oneChainCbs (σ := Nat) (W := Nat) (fun _ _ x => x) (fun _ _ => []) [3, 4] 0).length == 1
#guard (faithfulCbs (σ := Nat) (W := Nat) (fun _ _ x => x) (fun _ _ => []) [3, 4] 0).length == 2

section Run
variable {σ W : Type}

/-- What the countdown does between frames: a refresh (driver retarget `g`, chains `started` (re)registered) or a
frame at time `t`. -/
inductive Ev (σ : Type) where
  | refresh (g : (Nat → σ) → (Nat → σ)) (started : List Nat)
  | frame (t : Rat)

/-- `stop(i)` then a new registration of `i`: the chain moves to the end (`startFaithful`). -/
def restart (R : List Nat) (i : Nat) : List Nat := R.filter (· != i) ++ [i]

/-- The registered chains after a refresh that starts `S`. -/
def refreshChains (R : List Nat) (S : List Nat) : List Nat := S.foldl restart R

#guard refreshChains [7] [6, 7] == [6, 7]
#guard refreshChains [6, 7] [7] == [6, 7]
#guard refreshChains [7, 6] [7] == [6, 7]
#guard refreshChains [] [] == []

/-- One event: new states and chains, the digits stepped in it, its writes and its rAF callback count. -/
def evStep (cbs : List Nat → Rat → List ((Nat → σ) × List W → (Nat → σ) × List W)) (done : Nat → σ → Bool) :
    (Nat → σ) × List Nat → Ev σ → ((Nat → σ) × List Nat) × (List Nat × List W) × Nat
  | (s, R), .refresh g S => ((g s, refreshChains R S), ([], []), 0)
  | (s, R), .frame t =>
    let x := runCbs (cbs R t) (s, [])
    ((x.1, R.filter fun d => !done d (x.1 d)), (R, x.2), (cbs R t).length)

/-- The outputs of a run of events from `sys`. -/
def run (cbs : List Nat → Rat → List ((Nat → σ) × List W → (Nat → σ) × List W)) (done : Nat → σ → Bool) :
    (Nat → σ) × List Nat → List (Ev σ) → List ((List Nat × List W) × Nat)
  | _, [] => []
  | sys, e :: es => let r := evStep cbs done sys e; r.2 :: run cbs done r.1 es

theorem evStep_oneChain (f : Nat → Rat → σ → σ) (w : Nat → σ → List W) (done : Nat → σ → Bool)
    (sys : (Nat → σ) × List Nat) (e : Ev σ) :
    (evStep (oneChainCbs f w) done sys e).1 = (evStep (faithfulCbs f w) done sys e).1 ∧
      (evStep (oneChainCbs f w) done sys e).2.1 = (evStep (faithfulCbs f w) done sys e).2.1 := by
  obtain ⟨s, R⟩ := sys
  cases e with
  | refresh g S => exact ⟨rfl, rfl⟩
  | frame t => simp [evStep, oneChain_frame_eq]

/-- **`oneChain_writes_eq`: per event, the same digits step, in the same order, with the same writes and values.** -/
theorem oneChain_writes_eq (f : Nat → Rat → σ → σ) (w : Nat → σ → List W) (done : Nat → σ → Bool) :
    ∀ (evs : List (Ev σ)) (sys : (Nat → σ) × List Nat),
      (run (oneChainCbs f w) done sys evs).map (·.1) = (run (faithfulCbs f w) done sys evs).map (·.1)
  | [], _ => rfl
  | e :: es, sys => by
    have h := evStep_oneChain f w done sys e
    simp only [run, List.map_cons, h.1, h.2, oneChain_writes_eq f w done es]

theorem run_rafs (cbs : List Nat → Rat → List ((Nat → σ) × List W → (Nat → σ) × List W)) (done : Nat → σ → Bool)
    (k : Nat → Nat) (hk0 : k 0 = 0) (hk : ∀ R t, (cbs R t).length = k R.length) :
    ∀ (evs : List (Ev σ)) (sys : (Nat → σ) × List Nat), ∀ o ∈ run cbs done sys evs, o.2 = k o.1.1.length
  | [], _, _, h => by cases h
  | e :: es, (s, R), o, h => by
    simp only [run, List.mem_cons] at h
    rcases h with h | h
    · subst h
      cases e with
      | refresh g S => simp [evStep, hk0]
      | frame t => simp [evStep, hk]
    · exact run_rafs cbs done k hk0 hk es _ o h

/-- `faithful` runs one rAF callback per stepped digit. -/
theorem faithful_rafs (f : Nat → Rat → σ → σ) (w : Nat → σ → List W) (done : Nat → σ → Bool) (evs : List (Ev σ))
    (sys : (Nat → σ) × List Nat) : ∀ o ∈ run (faithfulCbs f w) done sys evs, o.2 = o.1.1.length :=
  run_rafs _ done id rfl (faithfulCbs_length f w) evs sys

/-- `one-chain` runs one rAF callback in a frame with a stepped digit, none otherwise. -/
theorem oneChain_rafs (f : Nat → Rat → σ → σ) (w : Nat → σ → List W) (done : Nat → σ → Bool) (evs : List (Ev σ))
    (sys : (Nat → σ) × List Nat) : ∀ o ∈ run (oneChainCbs f w) done sys evs, o.2 = min 1 o.1.1.length :=
  run_rafs _ done (min 1) rfl (oneChainCbs_length f w) evs sys

end Run

/-! ## rAF callbacks per frame, `n` digits stepped -/

theorem oneChain_raf_le (n : Nat) : min 1 n ≤ n := Nat.min_le_right 1 n

/-- **`oneChain_raf`: fewer callbacks when two or more digits roll.** -/
theorem oneChain_raf (n : Nat) (h : 2 ≤ n) : min 1 n < n := by omega

theorem oneChain_raf_eq (n : Nat) (h : n ≤ 1) : min 1 n = n := by omega

theorem oneChain_raf_lt_iff (n : Nat) : min 1 n < n ↔ 2 ≤ n := by omega

/-- Page rAF callbacks with the countdown `faithful`: the shared loop's one if other shared subscribers run, the
other parts' own ones, and one per stepped digit (`rafRegistrationsPerFrame`). -/
def pageFaithful (sharedOthers : Bool) (own n : Nat) : Nat := (if sharedOthers then 1 else 0) + own + n

/-- Page rAF callbacks with `one-chain`: the shared loop runs if anyone shares it, the digits included. -/
def pageOneChain (sharedOthers : Bool) (own n : Nat) : Nat := (if sharedOthers || 0 < n then 1 else 0) + own

/-- Page rAF callbacks with `strip`'s scheduling: its shared subscriber is live in every frame. -/
def pageAlwaysOn (_sharedOthers : Bool) (own _n : Nat) : Nat := 1 + own

#guard pageFaithful false 3 2 == 5 && pageOneChain false 3 2 == 4 && pageAlwaysOn false 3 2 == 4
#guard pageFaithful true 3 1 == 5 && pageOneChain true 3 1 == 4
#guard pageFaithful false 3 0 == 3 && pageOneChain false 3 0 == 3 && pageAlwaysOn false 3 0 == 4

theorem page_le (sh : Bool) (own n : Nat) : pageOneChain sh own n ≤ pageFaithful sh own n := by
  cases sh <;> by_cases h : 0 < n <;> simp [pageOneChain, pageFaithful, h] <;> omega

theorem page_lt_two (sh : Bool) (own n : Nat) (h : 2 ≤ n) : pageOneChain sh own n < pageFaithful sh own n := by
  cases sh <;> simp [pageOneChain, pageFaithful, show 0 < n by omega] <;> omega

theorem page_lt_shared (own n : Nat) (h : 1 ≤ n) : pageOneChain true own n < pageFaithful true own n := by
  simp [pageOneChain, pageFaithful]; omega

theorem page_eq_alone (own n : Nat) (h : n ≤ 1) : pageOneChain false own n = pageFaithful false own n := by
  by_cases h0 : 0 < n
  · simp [pageOneChain, pageFaithful, h0]; omega
  · simp [pageOneChain, pageFaithful, h0]; omega

theorem page_eq_still (sh : Bool) (own : Nat) : pageOneChain sh own 0 = pageFaithful sh own 0 := by
  cases sh <;> simp [pageOneChain, pageFaithful]

/-- **`strip`'s scheduling is not `≤` the original's: a still frame pays its callback.** -/
theorem strip_schedule_still_gt (own : Nat) : pageFaithful false own 0 < pageAlwaysOn false own 0 := by
  simp [pageFaithful, pageAlwaysOn]

theorem oneChain_le_alwaysOn (sh : Bool) (own n : Nat) : pageOneChain sh own n ≤ pageAlwaysOn sh own n := by
  simp only [pageOneChain, pageAlwaysOn]; split <;> omega

/-! ## Where in the frame the digits run (swipe-touch-v1 frame 499 and frames 13-34)

A layout read (`window.scrollY`) flushes the dirty style at once (Chromium `local_dom_window.cc:1877`@f842f52;
WebKit `LocalDOMWindow.cpp:1476-1480`@862f17d, for a nonzero scroll). A flush recalculates the elements dirty at that
moment; a subtree restyle (`walk`) visits all `m` elements below it, the `f` digit faces included; other dirt is `o`
elements apart from the faces. -/

/-- What happens to style: a layout read, a write of the digit faces, a subtree restyle, a write elsewhere. -/
inductive FEv where
  | read
  | faces
  | mutate
  | other

/-- The dirty style: whether the faces are dirty, whether a subtree restyle is, whether other elements are. -/
structure Dirt where
  faces : Bool
  walk : Bool
  other : Bool

/-- Elements one flush recalculates: the whole subtree (`m`) if it is dirty, else the faces (`f`) and the others
(`o`) as far as they are dirty. -/
def flushElems (f o m : Nat) (d : Dirt) : Nat :=
  if d.walk then m else (if d.faces then f else 0) + (if d.other then o else 0)

/-- One event on (dirt, flushes, elements): a read flushes only when something is dirty. -/
def fstep (f o m : Nat) (x : Dirt × Nat × Nat) : FEv → Dirt × Nat × Nat
  | .read =>
    if x.1.faces || x.1.walk || x.1.other then (⟨false, false, false⟩, x.2.1 + 1, x.2.2 + flushElems f o m x.1)
    else x
  | .faces => ({ x.1 with faces := true }, x.2)
  | .mutate => ({ x.1 with walk := true }, x.2)
  | .other => ({ x.1 with other := true }, x.2)

/-- (flushes, elements) of a frame's events, then the frame's own style update (one more read). -/
def frameCost (f o m : Nat) (evs : List FEv) : Nat × Nat :=
  let r := (evs ++ [FEv.read]).foldl (fstep f o m) (⟨false, false, false⟩, 0, 0)
  (r.2.1, r.2.2)

/-- A frame kind: events before the animation-frame callbacks, the shared subscribers (each runs whole), and whether
the original's digit callbacks run before them (`faithfulFirst`) or after. The order is the rAF registration order,
which the shared loop's restart changes (`createRafClock`: a loop that stopped re-registers behind the chains). -/
structure Kind where
  pre : List FEv
  subs : List (List FEv)
  faithfulFirst : Bool

/-- The frame's events with the digits before every shared subscriber (`true`) or after every one (`false`). -/
def place (k : Kind) (first : Bool) : List FEv :=
  k.pre ++ (if first then FEv.faces :: k.subs.flatten else k.subs.flatten ++ [FEv.faces])

/-- `faithful`: the order of the original in this kind of frame. -/
def orderFaithful (k : Kind) : List FEv := place k k.faithfulFirst

/-- `one-chain` as first built, at its subscribe position: before the scroll tick, which a scroll event adds after it. -/
def orderAtSubscriber (k : Kind) : List FEv := place k true

/-- `one-chain` with the digits behind every other shared subscriber. -/
def orderLast (k : Kind) : List FEv := place k false

/-- Frame 499: the scroll engine's tick reads layout, then dirties a subtree; the original's digits come after it. -/
def kind499 : Kind := ⟨[], [[FEv.read, FEv.mutate]], false⟩

/-- Frames 13-34: other style is dirty before the callbacks (INFERRED: input handlers), one shared subscriber reads,
and the original's digits come before it. -/
def kindEarly : Kind := ⟨[FEv.other], [[FEv.read]], true⟩

/-- **Frame 499, faithful: one flush of `m` elements.** The tick's read finds nothing dirty. -/
theorem frame499_faithful (f o m : Nat) : frameCost f o m (orderFaithful kind499) = (1, m) := by
  simp [frameCost, orderFaithful, place, kind499, fstep, flushElems]

/-- **Frame 499, digits at their subscriber: one more flush and `f` more elements.** The read after the face write
flushes the `f` faces; the later restyle visits them again. -/
theorem frame499_atSubscriber (f o m : Nat) : frameCost f o m (orderAtSubscriber kind499) = (2, f + m) := by
  simp [frameCost, orderAtSubscriber, place, kind499, fstep, flushElems]

/-- **Frame 499, digits last: the faithful cost.** -/
theorem frame499_last (f o m : Nat) : frameCost f o m (orderLast kind499) = (1, m) := by
  simp [frameCost, orderLast, place, kind499, fstep, flushElems]

/-- **Early frames, faithful: one flush of the others and the faces.** The shared read flushes both. -/
theorem early_faithful (f o m : Nat) : frameCost f o m (orderFaithful kindEarly) = (1, f + o) := by
  simp [frameCost, orderFaithful, place, kindEarly, fstep, flushElems]

/-- **Early frames, digits at their subscriber: the faithful cost.** -/
theorem early_atSubscriber (f o m : Nat) : frameCost f o m (orderAtSubscriber kindEarly) = (1, f + o) := by
  simp [frameCost, orderAtSubscriber, place, kindEarly, fstep, flushElems]

/-- **Early frames, digits last: one more flush and the same elements.** The read flushes the others, the frame's
own update then flushes the faces alone: `+1` update, `+0` elements, the Chromium delta of frames 13-34. -/
theorem early_last (f o m : Nat) : frameCost f o m (orderLast kindEarly) = (2, f + o) := by
  simp [frameCost, orderLast, place, kindEarly, fstep, flushElems, Nat.add_comm]

/-- **No fixed order wins both kinds.** Each of the two fixed orders adds a style update on one kind: the digits
at their subscriber on frame 499, the digits last on the early frames. -/
theorem no_fixed_order (f o m : Nat) (first : Bool) :
    (frameCost f o m (place kind499 first)).1 > (frameCost f o m (orderFaithful kind499)).1 ∨
    (frameCost f o m (place kindEarly first)).1 > (frameCost f o m (orderFaithful kindEarly)).1 := by
  cases first <;> simp [frameCost, orderFaithful, place, kind499, kindEarly, fstep, flushElems]

/-- The digits at their subscriber add no update on the early frames and one on frame 499; last the reverse. -/
theorem extra_updates (f o m : Nat) :
    (frameCost f o m (orderAtSubscriber kind499)).1 = (frameCost f o m (orderFaithful kind499)).1 + 1 ∧
    (frameCost f o m (orderAtSubscriber kindEarly)).1 = (frameCost f o m (orderFaithful kindEarly)).1 ∧
    (frameCost f o m (orderLast kind499)).1 = (frameCost f o m (orderFaithful kind499)).1 ∧
    (frameCost f o m (orderLast kindEarly)).1 = (frameCost f o m (orderFaithful kindEarly)).1 + 1 := by
  simp [frameCost, orderAtSubscriber, orderLast, orderFaithful, place, kind499, kindEarly, fstep, flushElems]

#guard frameCost 10 134 320 (orderFaithful kind499) == (1, 320)
#guard frameCost 10 134 320 (orderAtSubscriber kind499) == (2, 330)
#guard frameCost 10 134 320 (orderLast kind499) == (1, 320)
#guard frameCost 10 134 320 (orderFaithful kindEarly) == (1, 144)
#guard frameCost 10 134 320 (orderAtSubscriber kindEarly) == (1, 144)
#guard frameCost 10 134 320 (orderLast kindEarly) == (2, 144)

/-! ## Golden rows (`packages/contracts/golden/parts/hero.countdown.onechain.jsonl`) -/

/-- A golden event: a refresh starting digits with their remaining spring frames, or a frame at a time in ms. -/
inductive GEv where
  | refresh (started : List (Nat × Nat))
  | frame (t : Nat)

/-- The golden instance: a digit's state is its remaining spring frames; a step takes one, done at 0. -/
def toEv : GEv → Ev Nat
  | .refresh ss => .refresh (fun s => ss.foldl (fun s p => setAt s p.1 p.2) s) (ss.map (·.1))
  | .frame t => .frame t

def gStep : Nat → Rat → Nat → Nat := fun _ _ x => x - 1
def gWrites : Nat → Nat → List Nat := fun d _ => (List.range 10).map (10 * d + ·)
def gDone : Nat → Nat → Bool := fun _ x => x == 0

/-- Golden scenarios: mount, a ones roll, a tens roll, a minute roll, a restart mid-roll, a still second. -/
def scenarios : List (String × List GEv) :=
  [("mount", [.refresh ((List.range 8).map (·, 1)), .frame 16, .frame 32]),
   ("ones", [.refresh [(7, 3)], .frame 16, .frame 32, .frame 48, .frame 64]),
   ("tens", [.refresh [(6, 4), (7, 3)], .frame 16, .frame 32, .frame 48, .frame 64, .frame 80]),
   ("minute", [.refresh [(4, 5), (5, 4), (6, 3), (7, 3)], .frame 16, .frame 32, .frame 48, .frame 64, .frame 80,
     .frame 96]),
   ("restart", [.refresh [(7, 3)], .frame 16, .refresh [(6, 2), (7, 3)], .frame 32, .frame 48, .frame 64,
     .frame 80]),
   ("still", [.refresh [], .frame 16, .frame 32])]

/-- Per frame of a scenario: the digits stepped in order, and the rAF callbacks of `faithful` and `one-chain`. -/
def frames (evs : List GEv) : List (List Nat × Nat × Nat) :=
  let sys : (Nat → Nat) × List Nat := (fun _ => 0, [])
  let es := evs.map toEv
  let fa := run (faithfulCbs gStep gWrites) gDone sys es
  let oc := run (oneChainCbs gStep gWrites) gDone sys es
  ((evs.zip (fa.zip oc)).filter fun p => match p.1 with | .frame _ => true | _ => false).map fun p =>
    (p.2.1.1.1, p.2.1.2, p.2.2.2)

#guard (frames [.refresh [(6, 4), (7, 3)], .frame 16, .frame 32, .frame 48, .frame 64, .frame 80]) ==
  [([6, 7], 2, 1), ([6, 7], 2, 1), ([6, 7], 2, 1), ([6], 1, 1), ([], 0, 0)]
#guard (frames [.refresh [(7, 3)], .frame 16, .refresh [(6, 2), (7, 3)], .frame 32, .frame 48, .frame 64]) ==
  [([7], 1, 1), ([6, 7], 2, 1), ([6, 7], 2, 1), ([7], 1, 1)]

def evJson : GEv → Lean.Json
  | .refresh ss => Lean.Json.mkObj [("refresh", Lean.toJson (ss.map fun p => [p.1, p.2]))]
  | .frame t => Lean.Json.mkObj [("frame", t)]

def row (sc : String × List GEv) : Lean.Json :=
  Lean.Json.mkObj
    [("scenario", sc.1), ("events", Lean.Json.arr (sc.2.map evJson).toArray),
     ("frames", Lean.Json.arr ((frames sc.2).map fun x => Lean.Json.mkObj
        [("steps", Lean.toJson x.1), ("faithful", x.2.1), ("oneChain", x.2.2)]).toArray)]

/-- The order row: (flushes, elements) per frame kind of the faithful order, the digits at their subscriber and the
digits last, for `f = 10` faces, `o = 134` other elements and a `m = 320` element subtree (the Chromium counts of
frame 499 and frames 13-34). -/
def orderRow : Lean.Json :=
  let c := fun (o : List FEv) => let r := frameCost 10 134 320 o; Lean.toJson [r.1, r.2]
  let kj := fun (k : Kind) =>
    Lean.Json.mkObj [("faithful", c (orderFaithful k)), ("atSubscriber", c (orderAtSubscriber k)), ("last", c (orderLast k))]
  Lean.Json.mkObj [("scenario", "orders"), ("frame499", kj kind499), ("early", kj kindEarly)]

def goldenText : String := String.join (scenarios.map fun sc => (row sc).compress ++ "\n") ++ orderRow.compress ++ "\n"

/-- Print the golden, or with `--check <file>` exit 1 unless the file equals it byte for byte. -/
def goldenMain (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText then
      IO.eprintln s!"countdown one-chain golden: {path} is up to date ({scenarios.length} lines)"
      return 0
    IO.eprintln s!"countdown one-chain golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print goldenText
    return 0

end Fw.Parts.HeroCountdownOneChain
