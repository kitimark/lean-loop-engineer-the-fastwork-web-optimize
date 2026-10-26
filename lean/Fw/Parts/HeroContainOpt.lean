import Lean.Data.Json
import Fw.Parts.NavOofRoot
import Fw.Parts.HeroScenePause

namespace Fw.Parts.HeroContainOpt

open Lean (Json)
open Fw.Parts.NavOofRoot (Tree Pass view)
open Fw.Site.Breakpoints (Probe matrix)

/-- What Chromium's `ObjectIsRelayoutBoundary` reads of one object
(`third_party/blink/renderer/core/layout/layout_object.cc:1439-1560@f842f52`). -/
structure CrBox where
  box : Bool
  cached : Bool
  fragmentSafe : Bool
  propagated : Bool
  oofDescendants : Bool
  fcRoot : Bool
  selfPaintingLayer : Bool
  svgRoot : Bool
  tablePart : Bool
  oofStatic : Bool
  flexItem : Bool
  gridCb : Bool
  mathInner : Bool
  layoutContain : Bool
  sizeContain : Bool
  fixedTail : Bool
deriving DecidableEq, Repr

/-- The checks before the containment test, in source order (`layout_object.cc:1441-1533@f842f52`). -/
def CrBox.guards (b : CrBox) : Bool :=
  b.box && b.cached && b.fragmentSafe && !b.propagated && !b.oofDescendants && b.fcRoot &&
    (b.selfPaintingLayer || b.svgRoot) && !b.tablePart && !b.oofStatic && !b.flexItem && !b.gridCb && !b.mathInner

def crBoundary (b : CrBox) : Bool :=
  b.guards && (b.layoutContain && b.sizeContain || b.svgRoot || b.fixedTail)

theorem cr_contain (b : CrBox) (hg : b.guards = true) (hl : b.layoutContain = true) (hs : b.sizeContain = true) :
    crBoundary b = true := by
  simp [crBoundary, hg, hl, hs]

theorem cr_svg (b : CrBox) (hg : b.guards = true) (hv : b.svgRoot = true) : crBoundary b = true := by
  simp [crBoundary, hg, hv]

theorem cr_tail (b : CrBox) (hg : b.guards = true) (ht : b.fixedTail = true) : crBoundary b = true := by
  simp [crBoundary, hg, ht]

theorem cr_guards_false (b : CrBox) (hg : b.guards = false) : crBoundary b = false := by
  simp [crBoundary, hg]

theorem cr_flexItem (b : CrBox) (h : b.flexItem = true) : crBoundary b = false := by
  simp [crBoundary, CrBox.guards, h]

theorem cr_oofDescendants (b : CrBox) (h : b.oofDescendants = true) : crBoundary b = false := by
  simp [crBoundary, CrBox.guards, h]

theorem cr_propagated (b : CrBox) (h : b.propagated = true) : crBoundary b = false := by
  simp [crBoundary, CrBox.guards, h]

theorem cr_noLayer (b : CrBox) (hl : b.selfPaintingLayer = false) (hv : b.svgRoot = false) : crBoundary b = false := by
  simp [crBoundary, CrBox.guards, hl, hv]

theorem cr_none (b : CrBox) (hc : (b.layoutContain && b.sizeContain) = false) (hv : b.svgRoot = false)
    (ht : b.fixedTail = false) : crBoundary b = false := by
  simp only [crBoundary, hc, hv, ht]; simp

/-- What WebKit's `isLayoutBoundary` reads of one renderer
(`Source/WebCore/rendering/RenderObject.cpp:516-556@862f17d`). -/
structure WkBox where
  view : Bool
  textControl : Bool
  layoutContain : Bool
  sizeContain : Bool
  svgRoot : Bool
  clipTail : Bool
deriving DecidableEq, Repr

def wkBoundary (b : WkBox) : Bool :=
  b.view || b.textControl || (b.layoutContain && b.sizeContain) || b.svgRoot || b.clipTail

theorem wk_view (b : WkBox) (h : b.view = true) : wkBoundary b = true := by simp [wkBoundary, h]

theorem wk_textControl (b : WkBox) (h : b.textControl = true) : wkBoundary b = true := by simp [wkBoundary, h]

theorem wk_contain (b : WkBox) (hl : b.layoutContain = true) (hs : b.sizeContain = true) : wkBoundary b = true := by
  simp [wkBoundary, hl, hs]

theorem wk_svg (b : WkBox) (h : b.svgRoot = true) : wkBoundary b = true := by simp [wkBoundary, h]

theorem wk_clipTail (b : WkBox) (h : b.clipTail = true) : wkBoundary b = true := by simp [wkBoundary, h]

theorem wk_none (b : WkBox) (hv : b.view = false) (ht : b.textControl = false)
    (hc : (b.layoutContain && b.sizeContain) = false) (hs : b.svgRoot = false) (hk : b.clipTail = false) :
    wkBoundary b = false := by
  simp only [wkBoundary, hv, ht, hc, hs, hk]; simp

def heroCr (contain : Bool) : CrBox :=
  { box := true, cached := true, fragmentSafe := true, propagated := false, oofDescendants := false, fcRoot := true,
    selfPaintingLayer := true, svgRoot := false, tablePart := false, oofStatic := false, flexItem := false,
    gridCb := false, mathInner := false, layoutContain := contain, sizeContain := contain, fixedTail := false }

def heroWk (contain : Bool) : WkBox :=
  { view := false, textControl := false, layoutContain := contain, sizeContain := contain, svgRoot := false,
    clipTail := false }

def svgWk : WkBox :=
  { view := false, textControl := false, layoutContain := false, sizeContain := false, svgRoot := true,
    clipTail := false }

theorem hero_cr_base : crBoundary (heroCr false) = false := by decide

theorem hero_cr_flag : crBoundary (heroCr true) = true := by decide

theorem hero_wk_base : wkBoundary (heroWk false) = false := by decide

theorem hero_wk_flag : wkBoundary (heroWk true) = true := by decide

theorem flexItem_engines_differ :
    crBoundary { heroCr true with flexItem := true } = false ∧ wkBoundary (heroWk true) = true := by decide

def heroContainer : Nat → Option Nat
  | 1 => some 0 | 2 => some 1 | 3 => some 2 | 4 => some 3 | 5 => some 3 | 6 => some 5 | 7 => some 6
  | 8 => some 7 | 9 => some 8 | 10 => some 9 | 11 => some 10 | 12 => some 11 | 13 => some 12 | 14 => some 13
  | 15 => some 14 | 16 => some 15 | 17 => some 10 | 18 => some 6 | 19 => some 18 | _ => none

def heroContainingBlock : Nat → Option Nat
  | 4 => some 0 | a => heroContainer a

def heroOof (a : Nat) : Bool := a == 4 || a == 13 || a == 14 || a == 15

def heroTree (_ : Unit := ()) : Tree where
  container := heroContainer
  containingBlock := heroContainingBlock
  oof := heroOof
  container_lt a p h := by
    unfold heroContainer at h; split at h <;> simp_all <;> omega
  containingBlock_lt a p h := by
    unfold heroContainingBlock heroContainer at h; split at h <;> (try split at h) <;> simp_all <;> omega

def hero : Nat := 8
def accent : Nat := 12
def svg : Nat := 15
def path : Nat := 16
def digit : Nat := 17
def nav : Nat := 4
def card : Nat := 19

def crB (contain : Bool) (a : Nat) : Bool := a == hero && crBoundary (heroCr contain)

def wkB (contain : Bool) (a : Nat) : Bool :=
  a == view || (a == svg && wkBoundary svgWk) || (a == hero && wkBoundary (heroWk contain))

def above (t : Tree) (a b : Nat) : Bool := t.climb (· == a) b == a

inductive Sched where
  | clean
  | full
  | roots (rs : List Nat)
deriving DecidableEq, Repr

def addRoot (rs : List Nat) (r : Nat) : List Nat := if rs.contains r then rs else rs ++ [r]

/-- Chromium: a root below the view joins the root list (`local_frame_view.cc:1706-1723@f842f52`); a walk that reaches
the view clears the list (`:1694`); once the view needs layout no root is taken (`layout_object.cc:1668-1669`). -/
def crStep (t : Tree) (B : Nat → Bool) : Sched → Nat → Sched
  | .full, _ => .full
  | .clean, x => if t.layoutRoot B x = view then .full else .roots [t.layoutRoot B x]
  | .roots rs, x => if t.layoutRoot B x = view then .full else .roots (addRoot rs (t.layoutRoot B x))

/-- WebKit keeps one subtree root: the same or a nested root keeps it, an enclosing root re-roots, a disjoint root
or the view gives a full layout (`Source/WebCore/page/LocalFrameViewLayoutContext.cpp:663-664,701-753@862f17d`). -/
def wkStep (t : Tree) (B : Nat → Bool) : Sched → Nat → Sched
  | .full, _ => .full
  | .clean, x => if t.layoutRoot B x = view then .full else .roots [t.layoutRoot B x]
  | .roots [s], x =>
    let r := t.layoutRoot B x
    if r = view then .full
    else if r = s then .roots [s]
    else if above t s r then .roots [s]
    else if above t r s then .roots [r]
    else .full
  | .roots _, _ => .full

def crFrame (t : Tree) (B : Nat → Bool) (xs : List Nat) : Sched := xs.foldl (crStep t B) .clean

def wkFrame (t : Tree) (B : Nat → Bool) (xs : List Nat) : Sched := xs.foldl (wkStep t B) .clean

theorem crStep_full (t : Tree) (B : Nat → Bool) (xs : List Nat) : xs.foldl (crStep t B) .full = .full := by
  induction xs with
  | nil => rfl
  | cons x xs ih => simpa [List.foldl, crStep] using ih

theorem wkStep_full (t : Tree) (B : Nat → Bool) (xs : List Nat) : xs.foldl (wkStep t B) .full = .full := by
  induction xs with
  | nil => rfl
  | cons x xs ih => simpa [List.foldl, wkStep] using ih

theorem crStep_view (t : Tree) (B : Nat → Bool) (s : Sched) (x : Nat) (h : t.layoutRoot B x = view) :
    crStep t B s x = .full := by
  cases s <;> simp [crStep, h]

theorem wkStep_view (t : Tree) (B : Nat → Bool) (s : Sched) (x : Nat) (h : t.layoutRoot B x = view) :
    wkStep t B s x = .full := by
  cases s with
  | clean => simp [wkStep, h]
  | full => rfl
  | roots rs =>
    match rs with
    | [] => rfl
    | [_] => simp [wkStep, h]
    | _ :: _ :: _ => rfl

theorem crFold_outside (t : Tree) (B : Nat → Bool) (x : Nat) (h : t.layoutRoot B x = view) :
    ∀ (xs : List Nat) (s : Sched), x ∈ xs → xs.foldl (crStep t B) s = .full := by
  intro xs
  induction xs with
  | nil => intro s hx; simp at hx
  | cons y ys ih =>
    intro s hx
    rcases List.mem_cons.mp hx with rfl | hy
    · simp only [List.foldl, crStep_view t B s _ h, crStep_full]
    · exact ih _ hy

theorem wkFold_outside (t : Tree) (B : Nat → Bool) (x : Nat) (h : t.layoutRoot B x = view) :
    ∀ (xs : List Nat) (s : Sched), x ∈ xs → xs.foldl (wkStep t B) s = .full := by
  intro xs
  induction xs with
  | nil => intro s hx; simp at hx
  | cons y ys ih =>
    intro s hx
    rcases List.mem_cons.mp hx with rfl | hy
    · simp only [List.foldl, wkStep_view t B s _ h, wkStep_full]
    · exact ih _ hy

theorem cr_outside_full (t : Tree) (B : Nat → Bool) (xs : List Nat) (x : Nat) (hx : x ∈ xs)
    (h : t.layoutRoot B x = view) : crFrame t B xs = .full :=
  crFold_outside t B x h xs .clean hx

theorem wk_outside_full (t : Tree) (B : Nat → Bool) (xs : List Nat) (x : Nat) (hx : x ∈ xs)
    (h : t.layoutRoot B x = view) : wkFrame t B xs = .full :=
  wkFold_outside t B x h xs .clean hx

theorem crFold_inside (t : Tree) (B : Nat → Bool) (r : Nat) (hr : r ≠ view) :
    ∀ xs : List Nat, (∀ x ∈ xs, t.layoutRoot B x = r) → xs.foldl (crStep t B) (.roots [r]) = .roots [r] := by
  intro xs
  induction xs with
  | nil => intro _; rfl
  | cons y ys ih =>
    intro h
    have hy := h y (List.mem_cons_self ..)
    simp only [List.foldl, crStep, hy, hr, ite_false, addRoot, List.contains_cons, beq_self_eq_true, Bool.true_or,
      ite_true]
    exact ih fun x hx => h x (List.mem_cons_of_mem _ hx)

theorem wkFold_inside (t : Tree) (B : Nat → Bool) (r : Nat) (hr : r ≠ view) :
    ∀ xs : List Nat, (∀ x ∈ xs, t.layoutRoot B x = r) → xs.foldl (wkStep t B) (.roots [r]) = .roots [r] := by
  intro xs
  induction xs with
  | nil => intro _; rfl
  | cons y ys ih =>
    intro h
    have hy := h y (List.mem_cons_self ..)
    simp only [List.foldl, wkStep, hy, hr, ite_false, ite_true]
    exact ih fun x hx => h x (List.mem_cons_of_mem _ hx)

theorem cr_inside_root (t : Tree) (B : Nat → Bool) (r : Nat) (hr : r ≠ view) (x : Nat) (xs : List Nat)
    (h : ∀ y ∈ x :: xs, t.layoutRoot B y = r) : crFrame t B (x :: xs) = .roots [r] := by
  have hx := h x (List.mem_cons_self ..)
  simp only [crFrame, List.foldl, crStep, hx, hr, ite_false]
  exact crFold_inside t B r hr xs fun y hy => h y (List.mem_cons_of_mem _ hy)

theorem wk_inside_root (t : Tree) (B : Nat → Bool) (r : Nat) (hr : r ≠ view) (x : Nat) (xs : List Nat)
    (h : ∀ y ∈ x :: xs, t.layoutRoot B y = r) : wkFrame t B (x :: xs) = .roots [r] := by
  have hx := h x (List.mem_cons_self ..)
  simp only [wkFrame, List.foldl, wkStep, hx, hr, ite_false]
  exact wkFold_inside t B r hr xs fun y hy => h y (List.mem_cons_of_mem _ hy)

theorem wk_reroot (t : Tree) (B : Nat → Bool) (s x : Nat) (hr : t.layoutRoot B x ≠ view) (hs : t.layoutRoot B x ≠ s)
    (hn : above t s (t.layoutRoot B x) = false) (ha : above t (t.layoutRoot B x) s = true) :
    wkStep t B (.roots [s]) x = .roots [t.layoutRoot B x] := by
  simp [wkStep, hr, hs, hn, ha]

theorem wk_disjoint (t : Tree) (B : Nat → Bool) (s x : Nat) (hr : t.layoutRoot B x ≠ view) (hs : t.layoutRoot B x ≠ s)
    (hn : above t s (t.layoutRoot B x) = false) (ha : above t (t.layoutRoot B x) s = false) :
    wkStep t B (.roots [s]) x = .full := by
  simp [wkStep, hr, hs, hn, ha]

/-- Objects a frame's Layout trace counts: the whole tree for a full pass, the root subtrees otherwise
(`local_frame_view.cc:685-697@f842f52`). -/
def objects (size : Nat → Nat) : Sched → Nat
  | .clean => 0
  | .full => size view
  | .roots rs => (rs.map size).sum

def crSources (xs : List Nat) : List Nat := xs.filter (· != path)

def crRoot (contain : Bool) (x : Nat) : Nat := (heroTree ()).layoutRoot (crB contain) x

def wkRoot (contain : Bool) (x : Nat) : Nat := (heroTree ()).layoutRoot (wkB contain) x

theorem accent_cr_base : crRoot false accent = view := by decide +kernel

theorem accent_cr_flag : crRoot true accent = hero := by decide +kernel

theorem accent_wk_base : wkRoot false accent = view := by decide +kernel

theorem accent_wk_flag : wkRoot true accent = hero := by decide +kernel

theorem digit_cr_flag : crRoot true digit = hero := by decide +kernel

theorem digit_wk_flag : wkRoot true digit = hero := by decide +kernel

theorem path_wk_base : wkRoot false path = svg := by decide +kernel

theorem path_wk_flag : wkRoot true path = svg := by decide +kernel

theorem outside_view : ∀ c : Bool, ∀ x ∈ [nav, card, hero],
    crRoot c x = view ∧ wkRoot c x = view := by decide +kernel

theorem base_full : ∀ x ∈ [accent, digit, nav, card, hero], crRoot false x = view ∧ wkRoot false x = view := by
  decide +kernel

theorem drawOut_cr_clean : crFrame (heroTree ()) (crB true) (crSources [path]) = .clean := by decide +kernel

theorem drawIn_flag_hero :
    crFrame (heroTree ()) (crB true) [accent, digit] = .roots [hero] ∧
    wkFrame (heroTree ()) (wkB true) [path, accent] = .roots [hero] := by decide +kernel

theorem drawIn_base_full :
    crFrame (heroTree ()) (crB false) [accent, digit] = .full ∧
    wkFrame (heroTree ()) (wkB false) [path, accent] = .full := by decide +kernel

theorem drawOut_wk_same :
    wkFrame (heroTree ()) (wkB false) [path] = .roots [svg] ∧
    wkFrame (heroTree ()) (wkB true) [path] = .roots [svg] := by decide +kernel

theorem drawIn_outside_full : ∀ o ∈ [nav, card, hero],
    crFrame (heroTree ()) (crB true) [accent, o] = .full ∧ crFrame (heroTree ()) (crB true) [o, accent] = .full ∧
    wkFrame (heroTree ()) (wkB true) [path, accent, o] = .full ∧
    wkFrame (heroTree ()) (wkB true) [o, path, accent] = .full := by decide +kernel

theorem objects_flag (size : Nat → Nat) (xs : List Nat) (x : Nat) (h : ∀ y ∈ x :: xs, crRoot true y = hero) :
    objects size (crFrame (heroTree ()) (crB true) (x :: xs)) = size hero := by
  rw [cr_inside_root (heroTree ()) (crB true) hero (by decide) x xs h]
  simp [objects]

theorem objects_outside (size : Nat → Nat) (xs : List Nat) (x : Nat) (hx : x ∈ xs) (h : crRoot true x = view) :
    objects size (crFrame (heroTree ()) (crB true) xs) = size view := by
  rw [cr_outside_full (heroTree ()) (crB true) xs x hx h]
  rfl

inductive Len where
  | px (v : Rat)
  | auto
deriving DecidableEq, Repr

structure SizeSpec where
  height : Len
  minHeight : Rat
  fillWidth : Bool
deriving DecidableEq, Repr

def usedHeight (s : SizeSpec) (sizeContain : Bool) (content : Rat) : Rat :=
  max s.minHeight (match s.height with | .px v => v | .auto => if sizeContain then 0 else content)

def usedWidth (s : SizeSpec) (sizeContain : Bool) (cb content : Rat) : Rat :=
  if s.fillWidth then cb else if sizeContain then 0 else min cb content

theorem height_definite (s : SizeSpec) (v : Rat) (h : s.height = .px v) (c : Rat) :
    usedHeight s true c = usedHeight s false c := by
  simp [usedHeight, h]

theorem width_fill (s : SizeSpec) (h : s.fillWidth = true) (cb c : Rat) : usedWidth s true cb c = usedWidth s false cb c := by
  simp [usedWidth, h]

theorem height_auto_differs : usedHeight ⟨.auto, 0, true⟩ true 100 ≠ usedHeight ⟨.auto, 0, true⟩ false 100 := by
  decide

def heroSpec (p : Probe) : SizeSpec :=
  ⟨.px (Fw.Parts.HeroScenePause.vhOf p), if Fw.Parts.HeroScenePause.le600Of p then Fw.Parts.HeroScenePause.vhOf p
    else 680, true⟩

theorem hero_same_box : ∀ p ∈ matrix, ∀ cb c : Rat,
    usedHeight (heroSpec p) true c = usedHeight (heroSpec p) false c ∧
    usedWidth (heroSpec p) true cb c = usedWidth (heroSpec p) false cb c := by
  intro p _ cb c
  exact ⟨height_definite _ _ rfl c, width_fill _ rfl cb c⟩

theorem hero_height_stage : ∀ p ∈ matrix, ∀ c : Rat,
    usedHeight (heroSpec p) true c = Fw.Parts.HeroScenePause.stageOf p := by
  intro p _ c
  simp only [usedHeight, heroSpec, Fw.Parts.HeroScenePause.stageOf, Fw.Parts.HeroExit.heroHeightPx]
  split <;> simp [Rat.max_def] <;> grind

def trackOf (p : Probe) : Rat :=
  if p.env.motion = .reduce then Fw.Parts.HeroScenePause.stageOf p else 2 * Fw.Parts.HeroScenePause.vhOf p

def excess (p : Probe) : Rat :=
  Fw.Parts.HeroScenePause.stageOf p + Fw.Parts.HeroScenePause.overflowOf p - trackOf p

theorem excess_lt_vh : ∀ p ∈ matrix, excess p < Fw.Parts.HeroScenePause.vhOf p := by
  intro p hp
  have hs := Fw.Parts.HeroScenePause.stage_fits p hp
  have hk := Fw.Parts.HeroScenePause.kMax_pos p hp
  unfold excess trackOf
  unfold Fw.Parts.HeroScenePause.kMax at hk
  split <;> grind

def extent (rest e : Rat) (contain : Bool) : Rat := if contain then rest else max rest e

theorem extent_same (rest e : Rat) (h : e ≤ rest) : extent rest e true = extent rest e false := by
  simp [extent, Rat.max_def]; grind

theorem excess_lt_454 : ∀ p ∈ matrix, excess p < 454 := by decide +kernel

def restMin : Rat := 3902

theorem extent_same_matrix : ∀ p ∈ matrix, ∀ rest : Rat, restMin ≤ rest →
    extent rest (excess p) true = extent rest (excess p) false := by
  intro p hp rest h
  have := excess_lt_454 p hp
  exact extent_same rest (excess p) (by unfold restMin at h; grind)

structure Effects where
  stacking : Bool
  absCb : Bool
  ownFc : Bool
deriving DecidableEq, Repr

def effects (sticky flex contain : Bool) : Effects := ⟨sticky || contain, sticky || contain, flex || contain⟩

theorem effects_same : effects true true true = effects true true false := by decide

def heroPositions : List String := ["relative", "absolute"]

theorem no_fixed_descendant : "fixed" ∉ heroPositions ∧ "sticky" ∉ heroPositions := by decide

def jb (b : Bool) : Json := .bool b
def jn (n : Nat) : Json := .num ⟨n, 0⟩
def jr (q : Rat) : Json := .str (toString q)

def schedJson : Sched → Json
  | .clean => .str "clean"
  | .full => .str "full"
  | .roots rs => Json.mkObj [("roots", .arr (rs.map jn).toArray)]

def line (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", .str fn), ("in", Json.mkObj inp), ("out", out)]).compress

def named : List (String × Nat) :=
  [("accent", accent), ("digit", digit), ("path", path), ("nav", nav), ("card", card), ("hero", hero)]

def frames : List (List Nat) :=
  [[accent, digit], [path, accent], [path], [accent, nav], [card, accent], [path, accent, hero]]

def lines (_ : Unit := ()) : List String :=
  [false, true].flatMap (fun c =>
    [line "boundary" [("engine", .str "chromium"), ("contain", jb c)] (jb (crBoundary (heroCr c))),
     line "boundary" [("engine", .str "webkit"), ("contain", jb c)] (jb (wkBoundary (heroWk c)))]) ++
  [false, true].flatMap (fun c => named.flatMap fun (n, x) =>
    [line "root" [("engine", .str "chromium"), ("contain", jb c), ("source", .str n)] (jn (crRoot c x)),
     line "root" [("engine", .str "webkit"), ("contain", jb c), ("source", .str n)] (jn (wkRoot c x))]) ++
  [false, true].flatMap (fun c => frames.flatMap fun xs =>
    [line "frame" [("engine", .str "chromium"), ("contain", jb c), ("sources", .arr ((crSources xs).map jn).toArray)]
      (schedJson (crFrame (heroTree ()) (crB c) (crSources xs))),
     line "frame" [("engine", .str "webkit"), ("contain", jb c), ("sources", .arr (xs.map jn).toArray)]
      (schedJson (wkFrame (heroTree ()) (wkB c) xs))]) ++
  matrix.map fun p =>
    line "box" [("probe", .str p.id)] (Json.mkObj
      [("height", jr (usedHeight (heroSpec p) true 0)), ("overflow", jr (Fw.Parts.HeroScenePause.overflowOf p)),
       ("track", jr (2 * Fw.Parts.HeroScenePause.vhOf p))])

def goldenText (_ : Unit := ()) : String := String.join ((lines ()).map (· ++ "\n"))

def run (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"hero-contain golden: {path} is up to date ({(lines ()).length} lines)"
      return 0
    IO.eprintln s!"hero-contain golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

#guard crRoot true accent == hero
#guard crRoot false accent == view
#guard wkRoot true path == svg
#guard crFrame (heroTree ()) (crB true) [] == .clean
#guard crFrame (heroTree ()) (crB true) [accent, accent] == .roots [hero]
#guard crFrame (heroTree ()) (crB true) [accent, card] == .full
#guard wkFrame (heroTree ()) (wkB true) [accent, path] == .roots [hero]
#guard wkFrame (heroTree ()) (wkB false) [path, accent] == .full
#guard above (heroTree ()) hero svg
#guard !above (heroTree ()) svg hero
#guard objects (fun a => if a = view then 1590 else 400) (.roots [hero]) == 400
#guard objects (fun _ => 1590) .full == 1590
#guard (lines ()).length == 4 + 24 + 24 + matrix.length

end Fw.Parts.HeroContainOpt
