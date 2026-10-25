import Lean.Data.Json

/-! hero.exit:threaded against the original: the scroll offset each arm shows per frame, what the trajectory probe compares,
and why the 25/40/40 new units of run 40156078840 are not an offset difference (research/notes/2026/10-2x-hero-exit-q6.md). -/
namespace Fw.Parts.HeroExitScrollOffset

open Lean (Json)

inductive Engine | chromium | webkit
deriving DecidableEq, Repr

/-- Where the threaded arm's view timeline is sampled. -/
inductive Path | accelerated | mainThread
deriving DecidableEq, Repr

/-- A frame of the original arm's writer: `first since` is the first frame after a scroll change, whose shown value its
last rAF body read `since` frames earlier; `steady` runs a body that reads the live offset; `inFrameScroll` is a frame in
which script scrolls after the animation update. -/
inductive Kind
  | first (since : Nat)
  | steady
  | inFrameScroll
deriving DecidableEq, Repr

/-- Frames the threaded arm's shown offset trails the offset drawn in that frame, when the main-thread offset trails it
by `lag` frames. -/
def threadedAge : Engine → Path → Nat → Kind → Nat
  -- RemoteProgressBasedTimeline.cpp:61-65@862f17d; cc/animation/scroll_timeline.cc:85-131@f842f52
  | _, .accelerated, _, _ => 0
  -- scroll_snapshot_timeline.cc:211-290@f842f52: the frame-start snapshot is validated after layout
  | .chromium, .mainThread, lag, _ => lag
  -- ViewTimeline.cpp:444-450,503-518 and ScrollTimeline.cpp:300-327@862f17d: cached at the animation update, refreshed
  -- only when the maximum scroll offset changes
  | .webkit, .mainThread, lag, .inFrameScroll => lag + 1
  | .webkit, .mainThread, lag, _ => lag

/-- Frames the original arm's shown offset trails the offset drawn in that frame. -/
def origAge (lag : Nat) : Kind → Nat
  | .first since => lag + since
  | .steady => lag
  | .inFrameScroll => lag

theorem threaded_older_iff {e : Engine} {p : Path} {lag : Nat} {k : Kind} :
    origAge lag k < threadedAge e p lag k ↔ e = .webkit ∧ p = .mainThread ∧ k = .inFrameScroll := by
  cases e <;> cases p <;> cases k <;> simp [origAge, threadedAge]

theorem threaded_never_older {e : Engine} {p : Path} {lag : Nat} {k : Kind}
    (h : ¬(e = .webkit ∧ p = .mainThread ∧ k = .inFrameScroll)) : threadedAge e p lag k ≤ origAge lag k :=
  Nat.not_lt.1 fun hl => h (threaded_older_iff.1 hl)

theorem threaded_older_inFrameScroll {lag : Nat} :
    threadedAge .webkit .mainThread lag .inFrameScroll = origAge lag .inFrameScroll + 1 := rfl

theorem accelerated_first_newer {e : Engine} {lag since : Nat} (h : 0 < since) :
    threadedAge e .accelerated lag (.first since) < origAge lag (.first since) := by
  cases e <;> simp [threadedAge, origAge] <;> omega

/-- The offset an arm shows in frame `n` when it is `age` frames old. -/
def shown (drawn : Nat → Nat) (n age : Nat) : Nat := drawn (n - age)

theorem shown_eq_of_still {drawn : Nat → Nat} {n w a : Nat} (hs : ∀ j ≤ w, drawn (n - j) = drawn n) (ha : a ≤ w) :
    shown drawn n a = drawn n := hs a ha

/-- Frames the probe's `settle` waits with an unchanged `scrollY` before a rest row (kit.mjs:206). -/
def stillFrames : Nat := 8

theorem arms_equal_at_rest {drawn : Nat → Nat} {n lag since : Nat} {e : Engine} {p : Path} {k : Kind}
    (hs : ∀ j ≤ stillFrames, drawn (n - j) = drawn n) (hk : k = .first since ∨ k = .steady ∨ k = .inFrameScroll)
    (hl : lag + since + 1 ≤ stillFrames) :
    shown drawn n (threadedAge e p lag k) = shown drawn n (origAge lag k) := by
  have ho : origAge lag k ≤ stillFrames := by
    rcases hk with rfl | rfl | rfl <;> simp [origAge] <;> omega
  have ht : threadedAge e p lag k ≤ stillFrames := by
    cases e <;> cases p <;> rcases hk with rfl | rfl | rfl <;> simp [threadedAge] <;> omega
  rw [shown_eq_of_still hs ht, shown_eq_of_still hs ho]

inductive Frame | move | rest
deriving DecidableEq, Repr

/-- One hero-path row pair of the probe: its frame and the `scrollY` each arm read. -/
structure Sample where
  step : String
  frame : Frame
  yOrig : Nat
  yCand : Nat
deriving DecidableEq, Repr

/-- The rows the reducer judges today: every rest row (reduce.mjs:643,656-657). -/
def judgedNow (s : Sample) : Bool := s.frame == .rest

/-- The equal-offset rule: a rest row is judged only when both arms read the same `scrollY`. -/
def judgedEqual (s : Sample) : Bool := s.frame == .rest && s.yOrig == s.yCand

theorem judgedEqual_same {s : Sample} (h : judgedEqual s = true) : s.yOrig = s.yCand := by
  simp [judgedEqual] at h
  exact h.2

theorem judgedEqual_rest {s : Sample} (h : judgedEqual s = true) : judgedNow s = true := by
  simp [judgedEqual, judgedNow] at h ⊢
  exact h.1

theorem judgedNow_unequal : ∃ s, judgedNow s = true ∧ s.yOrig ≠ s.yCand :=
  ⟨⟨"s25", .rest, 200, 211⟩, rfl, by decide⟩

theorem judged_agree_of_equal {s : Sample} (h : s.yOrig = s.yCand) : judgedNow s = judgedEqual s := by
  simp [judgedNow, judgedEqual, h]

def samples : List Sample :=
  [⟨"s25@1", .move, 53, 53⟩, ⟨"s25@2", .move, 104, 106⟩, ⟨"s25", .rest, 211, 211⟩, ⟨"s50@3", .move, 370, 317⟩,
   ⟨"s50", .rest, 422, 422⟩, ⟨"s90", .rest, 700, 760⟩, ⟨"b0", .rest, 0, 0⟩]

#guard (samples.filter judgedNow).map (·.step) == ["s25", "s50", "s90", "b0"]
#guard (samples.filter judgedEqual).map (·.step) == ["s25", "s50", "b0"]

inductive Lane | chromium | linuxWebkit | macWebkit
deriving DecidableEq, Repr

/-- One new-unit cell of run 40156078840: the elements of `node` with a non-empty rect in each arm, and per failing rest
step the `scrollY` of the original, of the candidate and the step's target. -/
structure Cell where
  lane : Lane
  width : Nat
  node : String
  prop : String
  paintedOrig : Nat
  paintedCand : Nat
  elements : Nat
  steps : List (String × Nat × Nat × Nat)
deriving Repr

def measured : List Cell := [
  ⟨.chromium, 390, "hero.orbit.card", "opacity", 0, 0, 10,
    [("s25", 211, 211, 211), ("s50", 422, 422, 422), ("s90", 760, 760, 760), ("b25", 211, 211, 211), ("b0", 0, 0, 0)]⟩,
  ⟨.chromium, 390, "hero.orbit.card", "translate", 0, 0, 10,
    [("s25", 211, 211, 211), ("s50", 422, 422, 422), ("s90", 760, 760, 760), ("b25", 211, 211, 211), ("b0", 0, 0, 0)]⟩,
  ⟨.chromium, 640, "hero.deck.card", "opacity", 0, 0, 4,
    [("s25", 211, 211, 211), ("s50", 422, 422, 422), ("s90", 760, 760, 760), ("b25", 211, 211, 211), ("b0", 0, 0, 0)]⟩,
  ⟨.chromium, 641, "hero.deck.card", "opacity", 0, 0, 4,
    [("s25", 225, 225, 225), ("s50", 450, 450, 450), ("s90", 810, 810, 810), ("b25", 225, 225, 225), ("b0", 0, 0, 0)]⟩,
  ⟨.chromium, 1280, "hero.deck.card", "opacity", 0, 0, 4,
    [("s25", 225, 225, 225), ("s50", 450, 450, 450), ("s90", 810, 810, 810), ("b25", 225, 225, 225), ("b0", 0, 0, 0)]⟩,
  ⟨.linuxWebkit, 390, "hero.orbit.card", "opacity", 0, 0, 10,
    [("s25", 211, 211, 211), ("s50", 422, 422, 422), ("s90", 760, 760, 760), ("s200", 1688, 1688, 1688),
     ("mid", 2551, 2551, 2551), ("hold", 2551, 2551, 2551), ("b50", 422, 422, 422), ("b25", 211, 211, 211)]⟩,
  ⟨.linuxWebkit, 390, "hero.orbit.card", "translate", 0, 0, 10,
    [("s25", 211, 211, 211), ("s50", 422, 422, 422), ("s90", 760, 760, 760), ("s200", 1688, 1688, 1688),
     ("mid", 2551, 2551, 2551), ("hold", 2551, 2551, 2551), ("b50", 422, 422, 422), ("b25", 211, 211, 211)]⟩,
  ⟨.linuxWebkit, 640, "hero.deck.card", "opacity", 0, 0, 4,
    [("s25", 211, 211, 211), ("s50", 422, 422, 422), ("s90", 760, 760, 760), ("s200", 1688, 1688, 1688),
     ("mid", 3084, 3084, 3084), ("hold", 3084, 3084, 3084), ("b50", 422, 422, 422), ("b25", 211, 211, 211)]⟩,
  ⟨.linuxWebkit, 641, "hero.deck.card", "opacity", 0, 0, 4,
    [("s25", 225, 225, 225), ("s50", 450, 450, 450), ("s90", 810, 810, 810), ("s200", 1800, 1800, 1800),
     ("mid", 2402, 2402, 2402), ("hold", 2402, 2402, 2402), ("b50", 450, 450, 450), ("b25", 225, 225, 225)]⟩,
  ⟨.linuxWebkit, 1280, "hero.deck.card", "opacity", 0, 0, 4,
    [("s25", 225, 225, 225), ("s50", 450, 450, 450), ("s90", 810, 810, 810), ("s200", 1800, 1800, 1800),
     ("mid", 4135, 4135, 4135), ("hold", 4135, 4135, 4135), ("b50", 450, 450, 450), ("b25", 225, 225, 225)]⟩,
  ⟨.macWebkit, 390, "hero.orbit.card", "opacity", 0, 0, 10,
    [("s25", 211, 211, 211), ("s50", 422, 422, 422), ("s90", 760, 760, 760), ("s200", 1688, 1688, 1688),
     ("mid", 2551, 2551, 2551), ("hold", 2551, 2551, 2551), ("b50", 422, 422, 422), ("b25", 211, 211, 211)]⟩,
  ⟨.macWebkit, 390, "hero.orbit.card", "translate", 0, 0, 10,
    [("s25", 211, 211, 211), ("s50", 422, 422, 422), ("s90", 760, 760, 760), ("s200", 1688, 1688, 1688),
     ("mid", 2551, 2551, 2551), ("hold", 2551, 2551, 2551), ("b50", 422, 422, 422), ("b25", 211, 211, 211)]⟩,
  ⟨.macWebkit, 640, "hero.deck.card", "opacity", 0, 0, 4,
    [("s25", 211, 211, 211), ("s50", 422, 422, 422), ("s90", 760, 760, 760), ("s200", 1688, 1688, 1688),
     ("mid", 3084, 3084, 3084), ("hold", 3084, 3084, 3084), ("b50", 422, 422, 422), ("b25", 211, 211, 211)]⟩,
  ⟨.macWebkit, 641, "hero.deck.card", "opacity", 0, 0, 4,
    [("s25", 225, 225, 225), ("s50", 450, 450, 450), ("s90", 810, 810, 810), ("s200", 1800, 1800, 1800),
     ("mid", 2402, 2402, 2402), ("hold", 2402, 2402, 2402), ("b50", 450, 450, 450), ("b25", 225, 225, 225)]⟩,
  ⟨.macWebkit, 1280, "hero.deck.card", "opacity", 0, 0, 4,
    [("s25", 225, 225, 225), ("s50", 450, 450, 450), ("s90", 810, 810, 810), ("s200", 1800, 1800, 1800),
     ("mid", 4135, 4135, 4135), ("hold", 4135, 4135, 4135), ("b50", 450, 450, 450), ("b25", 225, 225, 225)]⟩]

/-- One new unit: a cell at one rest step. -/
structure NewUnit where
  lane : Lane
  width : Nat
  node : String
  prop : String
  step : String
  yOrig : Nat
  yCand : Nat
  target : Nat
  paintedOrig : Nat
  paintedCand : Nat
deriving Repr

def units : List NewUnit :=
  measured.flatMap fun c => c.steps.map fun (s, yo, yc, t) =>
    ⟨c.lane, c.width, c.node, c.prop, s, yo, yc, t, c.paintedOrig, c.paintedCand⟩

inductive Cause | offset | hidden | other
deriving DecidableEq, Repr

/-- What a unit judged at a settled rest row is explained by: the arms read different offsets, the node paints no box in
either arm, or neither. -/
def cause (u : NewUnit) : Cause :=
  if u.yOrig != u.yCand then .offset
  else if u.paintedOrig == 0 && u.paintedCand == 0 then .hidden
  else .other

theorem cause_offset_iff {u : NewUnit} : cause u = .offset ↔ u.yOrig ≠ u.yCand := by
  unfold cause
  by_cases h : u.yOrig = u.yCand <;> simp [h]
  split <;> simp

theorem cause_hidden_iff {u : NewUnit} :
    cause u = .hidden ↔ u.yOrig = u.yCand ∧ u.paintedOrig = 0 ∧ u.paintedCand = 0 := by
  unfold cause
  by_cases h : u.yOrig = u.yCand <;> simp [h]

theorem cause_other_iff {u : NewUnit} :
    cause u = .other ↔ u.yOrig = u.yCand ∧ ¬(u.paintedOrig = 0 ∧ u.paintedCand = 0) := by
  unfold cause
  by_cases h : u.yOrig = u.yCand <;> simp [h]

def count (l : Lane) : Nat := (units.filter (·.lane == l)).length

theorem measured_counts : count .chromium = 25 ∧ count .linuxWebkit = 40 ∧ count .macWebkit = 40 := by decide

theorem measured_at_target : ∀ u ∈ units, u.yOrig = u.target ∧ u.yCand = u.target := by decide

theorem measured_hidden : ∀ u ∈ units, cause u = .hidden := by decide

theorem measured_not_offset : ∀ u ∈ units, cause u ≠ .offset := fun u hu => by simp [measured_hidden u hu]

theorem measured_judgedEqual : ∀ u ∈ units, judgedEqual ⟨u.step, .rest, u.yOrig, u.yCand⟩ = true := by decide

#guard cause ⟨.chromium, 390, "n", "opacity", "s25", 200, 211, 211, 0, 0⟩ == .offset
#guard cause ⟨.chromium, 390, "n", "opacity", "s25", 211, 211, 211, 0, 0⟩ == .hidden
#guard cause ⟨.chromium, 390, "n", "opacity", "s25", 211, 211, 211, 10, 10⟩ == .other
#guard units.length == 105

def q6Text : String :=
  "answered (Fw.Parts.HeroExitScrollOffset): the threaded arm is never older than the original \
    (threaded_never_older) except in a WebKit main-thread frame with an in-frame script scroll (threaded_older_iff); \
    after the probe's 8 still frames both arms show the drawn offset (arms_equal_at_rest); the 25/40/40 new units of \
    run 40156078840 were judged at equal offsets on nodes that paint no box (measured_judgedEqual, measured_hidden), \
    so unequal offsets do not explain them; the reducer judges rest rows without comparing offsets \
    (judgedNow_unequal), and judgedEqual is the follow-up rule"

def engineWord : Engine → String
  | .chromium => "chromium"
  | .webkit => "webkit"

def pathWord : Path → String
  | .accelerated => "accelerated"
  | .mainThread => "main-thread"

def kindJson : Kind → Json
  | .first since => Json.mkObj [("frame", .str "first"), ("since", .num since)]
  | .steady => Json.mkObj [("frame", .str "steady")]
  | .inFrameScroll => Json.mkObj [("frame", .str "in-frame-scroll")]

def frameWord : Frame → String
  | .move => "move"
  | .rest => "rest"

def laneWord : Lane → String
  | .chromium => "chromium"
  | .linuxWebkit => "linux-webkit"
  | .macWebkit => "mac-webkit"

def causeWord : Cause → String
  | .offset => "offset"
  | .hidden => "hidden"
  | .other => "other"

def ageLine (e : Engine) (p : Path) (lag : Nat) (k : Kind) : String :=
  (Json.mkObj [("fn", .str "age"),
    ("in", Json.mkObj [("engine", .str (engineWord e)), ("path", .str (pathWord p)), ("lag", .num lag), ("kind", kindJson k)]),
    ("out", Json.mkObj [("threaded", .num (threadedAge e p lag k)), ("orig", .num (origAge lag k)),
      ("threadedOlder", .bool (decide (origAge lag k < threadedAge e p lag k)))])]).compress

def sampleLine (s : Sample) : String :=
  (Json.mkObj [("fn", .str "judged"),
    ("in", Json.mkObj [("step", .str s.step), ("frame", .str (frameWord s.frame)), ("yOrig", .num s.yOrig),
      ("yCand", .num s.yCand)]),
    ("out", Json.mkObj [("now", .bool (judgedNow s)), ("equal", .bool (judgedEqual s))])]).compress

def unitLine (u : NewUnit) : String :=
  (Json.mkObj [("fn", .str "cause"),
    ("in", Json.mkObj [("lane", .str (laneWord u.lane)), ("width", .num u.width), ("node", .str u.node),
      ("prop", .str u.prop), ("step", .str u.step), ("yOrig", .num u.yOrig), ("yCand", .num u.yCand),
      ("target", .num u.target), ("paintedOrig", .num u.paintedOrig), ("paintedCand", .num u.paintedCand)]),
    ("out", Json.mkObj [("cause", .str (causeWord (cause u)))])]).compress

def goldenLines (_ : Unit := ()) : List String :=
  ([Engine.chromium, .webkit].flatMap fun e => [Path.accelerated, .mainThread].flatMap fun p =>
    [0, 1].flatMap fun lag => [Kind.first 1, .steady, .inFrameScroll].map (ageLine e p lag)) ++
  samples.map sampleLine ++ units.map unitLine

#guard goldenLines.length == 24 + 7 + 105

def path : String := "../packages/contracts/golden/parts/hero-exit-offset.jsonl"

def text (_ : Unit := ()) : String := String.join (goldenLines.map (· ++ "\n"))

def gen (args : List String) : IO Unit := do
  if args.contains "--check" then
    let disk ← IO.FS.readFile path
    if disk != text then
      throw (IO.userError s!"hero-exit-offset: {path} is stale; regenerate with Fw.Parts.HeroExitScrollOffset.gen []")
    IO.println s!"hero-exit-offset: {path} equals the Lean output, {goldenLines.length} lines"
  else
    IO.FS.writeFile path text

end Fw.Parts.HeroExitScrollOffset
