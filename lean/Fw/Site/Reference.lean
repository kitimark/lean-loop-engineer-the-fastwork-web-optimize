import Lean.Data.Json

/-!
# `Fw.Site.Reference`: the original's computed styles, extracted by a browser, as data

`packages/snapshot-extract` runs the unmodified snapshot in Chromium and in Playwright WebKit at the gate's whole-pixel
environments and records, for every probed (part, role, property), the computed value in each environment and where it
is declared: a stylesheet rule, an inline style, an ancestor it is inherited from (`body`, `html`, ...), or nowhere
(the initial value). Values are written down by a browser, not typed in, so a port value cannot be transcribed wrong.
The dataset is `packages/contracts/golden/site/reference-<engine>.jsonl` (schema `fw.snapshot-extract.reference/1`).

Notation. `E` = the environments of the dataset (indices `0..n-1`, widths `w_i`); a cell is
`c = (part, role, prop, v, s)` with `v_i ∈ String_⊥` (the computed value in
environment `i`, `⊥` = the element is absent) and `s_i ∈ Source_⊥` (where it is declared).

Premise (empirical, not provable here): the extraction is a deterministic function of the snapshot and the engine
version. It is tested by the CI jobs of `.github/workflows/snapshot-extract.yml` (three independent runs per engine, a
value is kept only when all three agree); the premise-tests id is `snapshot-extract.determinism`.
-/

namespace Fw.Site.Reference

open Lean

/-! ## The data model -/

/-- The two engines the reference is extracted in.

Chromium is Chrome Headless Shell; WebKit is Playwright's WebKit build. -/
inductive Engine where
  | chromium
  | webkit
  deriving DecidableEq, Repr

/-- Where a computed value comes from.

A winning stylesheet rule (with whether it sits in an `@media` block and whether it is `!important`), an inline style, the
nearest ancestor `a` (a tag name) that declares the property, `u` levels up, or nothing set (the initial or user-agent value). -/
inductive Source where
  | rule (sheet : String) (media imp : Bool)
  | inline
  | inherited (ancestor : String) (up : Nat)
  | initial
  deriving DecidableEq, Repr

/-- One probed (part, role, property): its value and source in every environment.

`none` means the element does not exist in that environment. -/
structure Cell where
  part : String
  role : String
  prop : String
  vals : List (Option String)
  srcs : List (Option Source)
  deriving DecidableEq, Repr

/-- The count row of a role: how many elements the selector matched in each environment.

`none` means the role was not measured in that environment. -/
structure RoleRow where
  part : String
  role : String
  counts : List (Option Nat)
  deriving DecidableEq, Repr

/-- A dataset: one engine, the widths of its environments, the role rows and the cells.

The environment index is the position in `widths`. -/
structure Dataset where
  engine : Engine
  widths : List Nat
  roles : List RoleRow
  cells : List Cell
  deriving Repr

/-- The key of a cell.

Two cells of one dataset never share a key (the extractor emits each once). -/
def Cell.key (c : Cell) : String × String × String := (c.part, c.role, c.prop)

/-- The cell of a dataset with the given key, if any.

A lookup by (part, role, property). -/
def Dataset.find? (d : Dataset) (k : String × String × String) : Option Cell :=
  d.cells.find? (fun c => c.key == k)

/-- The keys of a dataset, in order.

Every probed (part, role, property) of the dataset. -/
def Dataset.keys (d : Dataset) : List (String × String × String) := d.cells.map Cell.key

/-! ## Inheritance from `body` -/

/-- A source is inheritance from `body`.

The nearest ancestor that declares the property is the `body` element. -/
def Source.fromBodyB : Source → Bool
  | .inherited a _ => a == "body"
  | _ => false

/-- A cell is inherited from `body`: in every environment where the element exists, its value comes from `body`'s own
declaration, and the element exists in at least one.

This is the case the port misses when it never sets `body`'s colour or font. -/
def inheritedFromBody (c : Cell) : Prop :=
  (∃ s ∈ c.srcs, s ≠ none) ∧ ∀ s ∈ c.srcs, ∀ x, s = some x → x.fromBodyB = true

/-- The Boolean test of `inheritedFromBody`.

A decidable form for `#guard` and the report. -/
def inheritedFromBodyB (c : Cell) : Bool :=
  c.srcs.any Option.isSome &&
    c.srcs.all (fun s => match s with | none => true | some x => x.fromBodyB)

/-- The Boolean test decides the proposition.

So a checked fact about the data is the inheritance statement itself. -/
theorem inheritedFromBodyB_iff (c : Cell) : inheritedFromBodyB c = true ↔ inheritedFromBody c := by
  unfold inheritedFromBodyB inheritedFromBody
  simp only [Bool.and_eq_true, List.any_eq_true, List.all_eq_true]
  constructor
  · rintro ⟨⟨s, hs, hsome⟩, hall⟩
    refine ⟨⟨s, hs, ?_⟩, ?_⟩
    · intro h; subst h; simp at hsome
    · intro t ht x hx
      have := hall t ht
      subst hx
      simpa using this
  · rintro ⟨⟨s, hs, hne⟩, hall⟩
    refine ⟨⟨s, hs, ?_⟩, ?_⟩
    · cases s with
      | none => exact absurd rfl hne
      | some x => rfl
    · intro t ht
      cases t with
      | none => rfl
      | some x => exact hall _ ht x rfl

/-- The cell of `body` for the same property (the `engine.scroll` part, role `content`).

The anchor of the reference: `body` is the element whose own declarations the others inherit. -/
def Dataset.bodyCell (d : Dataset) (prop : String) : Option Cell :=
  d.find? ("engine.scroll", "content", prop)

/-- A cell inherited from `body` has a `body` cell that declares the property itself, in some environment.

Well-formedness of an extraction: "inherited from body" must have a declaring `body` behind it. -/
def Dataset.bodyDeclaresB (d : Dataset) (c : Cell) : Bool :=
  match d.bodyCell c.prop with
  | none => false
  | some b => b.srcs.any (fun s => match s with | some (.rule _ _ _) => true | some .inline => true | _ => false)

/-! ## Engine agreement and the cross-engine split -/

/-- The two engines agree on a cell: same value in every environment.

Sources are compared separately (`Split.sourceDiffers`). -/
def Agree (a b : Cell) : Prop := a.vals = b.vals

instance (a b : Cell) : Decidable (Agree a b) := inferInstanceAs (Decidable (a.vals = b.vals))

/-- How one key reads in the two engines.

`agree`: same values and same sources. `valueDiffers`: some environment has different values. `sourceDiffers`: same values,
different declared sources. `onlyChromium` / `onlyWebkit`: the key exists in one engine only. -/
inductive Split where
  | agree
  | valueDiffers
  | sourceDiffers
  | onlyChromium
  | onlyWebkit
  deriving DecidableEq, Repr

/-- The class of one key, given its cell in each engine.

A total function: every key lands in exactly one class. -/
def classify (a b : Option Cell) : Split :=
  match a, b with
  | none, none => .agree
  | some _, none => .onlyChromium
  | none, some _ => .onlyWebkit
  | some x, some y =>
    if x.vals ≠ y.vals then .valueDiffers else if x.srcs ≠ y.srcs then .sourceDiffers else .agree

/-- **The cross-engine split.** Every key falls in exactly one class, and each class means what its name says.

Used on the original itself: where Chromium and WebKit disagree about the same page (for example the stage background),
the disagreement is in the original, not in our port. -/
theorem crossEngine_split (a b : Option Cell) :
    (classify a b = .valueDiffers ↔ ∃ x y, a = some x ∧ b = some y ∧ x.vals ≠ y.vals) ∧
    (classify a b = .sourceDiffers ↔ ∃ x y, a = some x ∧ b = some y ∧ x.vals = y.vals ∧ x.srcs ≠ y.srcs) ∧
    (classify a b = .agree ↔ (a = none ∧ b = none) ∨
        ∃ x y, a = some x ∧ b = some y ∧ x.vals = y.vals ∧ x.srcs = y.srcs) ∧
    (classify a b = .onlyChromium ↔ (∃ x, a = some x) ∧ b = none) ∧
    (classify a b = .onlyWebkit ↔ a = none ∧ ∃ y, b = some y) := by
  cases a with
  | none =>
    cases b with
    | none => simp [classify]
    | some y => simp [classify]
  | some x =>
    cases b with
    | none => simp [classify]
    | some y =>
      by_cases hv : x.vals = y.vals <;> by_cases hs : x.srcs = y.srcs <;> simp [classify, hv, hs]

/-- Counting form of the split: the five classes of a key list cover it, without overlap.

For any classifier `f` into the five classes, the five class counts add up to the number of keys. -/
theorem split_partition {α : Type} (f : α → Split) (ks : List α) :
    ks.length = (ks.filter (fun k => f k == .agree)).length
      + (ks.filter (fun k => f k == .valueDiffers)).length
      + (ks.filter (fun k => f k == .sourceDiffers)).length
      + (ks.filter (fun k => f k == .onlyChromium)).length
      + (ks.filter (fun k => f k == .onlyWebkit)).length := by
  induction ks with
  | nil => simp
  | cons k ks ih =>
    cases h : f k <;> simp [h] <;> omega

/-- The class of a key in two datasets.

Chromium's dataset first, WebKit's second. -/
def splitOf (a b : Dataset) (k : String × String × String) : Split := classify (a.find? k) (b.find? k)

/-- Every key of either dataset, without repeats of the first's keys.

The key set the split ranges over. -/
def allKeys (a b : Dataset) : List (String × String × String) :=
  a.keys ++ b.keys.filter (fun k => !(a.keys.contains k))

/-- The keys whose class is not `agree`, with the class.

Where the engines read the original differently. -/
def disagreements (a b : Dataset) : List ((String × String × String) × Split) :=
  ((allKeys a b).map (fun k => (k, splitOf a b k))).filter (fun p => p.2 != .agree)

/-- The parts that contain a disagreement of a given class.

The list keeps the first occurrence of each part, in disagreement order; for `c = agree` it is `[]`.

The part-level view used in the findings (for example `platform.stageBg`). -/
def partsWith (a b : Dataset) (c : Split) : List String :=
  ((disagreements a b).filter (fun p => p.2 == c)).map (fun p => p.1.1) |>.eraseDups

/-- A disagreement is exactly a key whose class is not `agree`.

The list loses nothing and adds nothing. -/
theorem mem_disagreements (a b : Dataset) (k : String × String × String) (c : Split) :
    (k, c) ∈ disagreements a b ↔ k ∈ allKeys a b ∧ c = splitOf a b k ∧ c ≠ .agree := by
  unfold disagreements
  simp only [List.mem_filter, List.mem_map, bne_iff_ne, ne_eq]
  constructor
  · rintro ⟨⟨k', hk', heq⟩, hne⟩
    obtain ⟨rfl, rfl⟩ := Prod.mk.inj heq
    exact ⟨hk', rfl, hne⟩
  · rintro ⟨hk, rfl, hne⟩
    exact ⟨⟨k, hk, rfl⟩, hne⟩

/-! ## Determinism (premise-backed) and the stable dataset -/

/-- The premise-tests id of the determinism premise.

The statement `DeterministicExtractor` is tested by three independent CI runs per engine of
`.github/workflows/snapshot-extract.yml`; a cell that differs between runs is dropped (`stableCells`). -/
def premiseTestId : String := "snapshot-extract.determinism"

/-- The empirical premise: an extraction does not depend on the run (machine, time, scheduling).

`s` the snapshot, `v` the engine version, `r` the run. Tested by `premiseTestId`, not proved. -/
def DeterministicExtractor {Snapshot Version Run : Type} (ext : Snapshot → Version → Run → List Cell) : Prop :=
  ∀ s v r r', ext s v r = ext s v r'

/-- **Reference determinism**, under the premise: the same snapshot and the same engine version give the same dataset,
and so the same value for anything computed from it.

The premise `DeterministicExtractor` carries the premise-tests id `snapshot-extract.determinism` (`premiseTestId`). -/
theorem reference_deterministic {Snapshot Version Run : Type}
    (ext : Snapshot → Version → Run → List Cell) (h : DeterministicExtractor ext)
    (s : Snapshot) (v : Version) (r r' : Run) :
    ext s v r = ext s v r' ∧ ∀ {β : Type} (f : List Cell → β), f (ext s v r) = f (ext s v r') := by
  exact ⟨h s v r r', fun f => by rw [h s v r r']⟩

/-- The cells that every run agrees on.

What the merge step keeps; a cell on which runs differ is dropped and listed as unstable. -/
def stableCells (runs : List (List Cell)) : List Cell :=
  match runs with
  | [] => []
  | r :: rest => r.filter (fun c => rest.all (fun r' => r'.contains c))

/-- Identical runs keep every cell.

A deterministic extraction loses no cell to the merge. -/
theorem stableCells_same (r : List Cell) : stableCells [r, r, r] = r := by
  simp [stableCells, List.filter_eq_self]

/-! ## Loading the dataset

The JSON-lines files are read at build time (`include_str`), parsed by the code below and checked by `#guard`s. The
parser is plain data shaping; the dataset format is `fw.snapshot-extract.reference/1` (header line, then `role` rows
`{part, role, n: [{x, e}]}` and `cell` rows `{part, role, prop, v: [{x, e}], s: [{x, e}]}`, `e` = `"all"` or the list of
environment indices). -/

/-- Read one source object.

Here `j.media or ⊥` is the boolean field when present and a boolean, else false (the same for
`imp`); `sheet` must be a string and `up` a natural number.

A parse of the four source kinds of the dataset. -/
def parseSource (j : Json) : Except String Source := do
  match (← j.getObjValAs? String "k") with
  | "rule" =>
    return .rule (← j.getObjValAs? String "sheet") ((j.getObjValAs? Bool "media").toOption.getD false)
      ((j.getObjValAs? Bool "imp").toOption.getD false)
  | "inline" => return .inline
  | "inherited" => return .inherited (← j.getObjValAs? String "from") (← j.getObjValAs? Nat "up")
  | "initial" => return .initial
  | k => throw s!"unknown source kind {k}"

/-- Expand grouped values to one entry per environment.

The groups are applied in order, so a later group overrides an earlier one and `all` overwrites every index; an
index `≥ n` in some `e_g` is ignored. The result is an error when the input is not an array, a group lacks `x` or
`e`, `dec(x_g)` fails, or `e_g` is neither `"all"` nor an array of natural numbers.

The inverse of the extractor's grouping; `none` also stands for an absent element. -/
def expandGroups {α : Type} (n : Nat) (dec : Json → Except String (Option α)) (j : Json) :
    Except String (List (Option α)) := do
  let groups ← j.getArr?
  let mut out : Array (Option α) := Array.replicate n none
  for g in groups do
    let x ← dec (← g.getObjVal? "x")
    let e ← g.getObjVal? "e"
    match e with
    | .str "all" => out := Array.replicate n x
    | _ =>
      for i in (← e.getArr?) do
        let i ← i.getNat?
        out := out.set! i x
  return out.toList

/-- Decode a nullable string.

A value or an absent element. -/
def decStr (j : Json) : Except String (Option String) :=
  match j with
  | .null => pure none
  | _ => do return some (← j.getStr?)

/-- Decode a nullable source.

A source or an absent element. -/
def decSrc (j : Json) : Except String (Option Source) :=
  match j with
  | .null => pure none
  | _ => do return some (← parseSource j)

/-- Decode a nullable count.

An element count or "not measured". -/
def decNat (j : Json) : Except String (Option Nat) :=
  match j with
  | .null => pure none
  | _ => do return some (← j.getNat?)

/-- Parse a dataset from the text of a `reference-<engine>.jsonl` file.

The result is an error when there is no non-empty line, a line is not JSON, the header has no `envs` array of objects
with a natural `width`, a row lacks a string `part`, `role` or `t`, a row field fails to decode, or `t` is neither
`role` nor `cell`. Rows keep their file order within each list.

The first line is the header (its `envs` give the widths); the others are role and cell rows. -/
def parseDataset (engine : Engine) (text : String) : Except String Dataset := do
  let lines := (text.splitOn "\n").filter (fun l => l.length > 0)
  match lines with
  | [] => throw "empty dataset"
  | head :: rest =>
    let h ← Json.parse head
    let widths ← (← (← h.getObjVal? "envs").getArr?).toList.mapM (fun e => do (← e.getObjVal? "width").getNat?)
    let n := widths.length
    let mut roles : Array RoleRow := #[]
    let mut cells : Array Cell := #[]
    for l in rest do
      let j ← Json.parse l
      let part ← j.getObjValAs? String "part"
      let role ← j.getObjValAs? String "role"
      match (← j.getObjValAs? String "t") with
      | "role" => roles := roles.push ⟨part, role, ← expandGroups n decNat (← j.getObjVal? "n")⟩
      | "cell" =>
        cells := cells.push ⟨part, role, ← j.getObjValAs? String "prop",
          ← expandGroups n decStr (← j.getObjVal? "v"), ← expandGroups n decSrc (← j.getObjVal? "s")⟩
      | t => throw s!"unknown row type {t}"
    return ⟨engine, widths, roles.toList, cells.toList⟩

/-- The text of the Chromium reference dataset.

Embedded at build time from `packages/contracts/golden/site/`. -/
def referenceChromiumText : String :=
  include_str "../../../packages/contracts/golden/site/reference-chromium.jsonl"

/-- The text of the WebKit reference dataset.

Embedded at build time from `packages/contracts/golden/site/`. -/
def referenceWebkitText : String :=
  include_str "../../../packages/contracts/golden/site/reference-webkit.jsonl"

/-- The Chromium reference dataset (empty if the file does not parse; the `#guard`s below fail then).

The original's computed styles in Chrome Headless Shell. -/
def referenceChromium : Dataset :=
  match parseDataset .chromium referenceChromiumText with
  | .ok d => d
  | .error _ => ⟨.chromium, [], [], []⟩

/-- The WebKit reference dataset (empty if the file does not parse; the `#guard`s below fail then).

The original's computed styles in Playwright WebKit. -/
def referenceWebkit : Dataset :=
  match parseDataset .webkit referenceWebkitText with
  | .ok d => d
  | .error _ => ⟨.webkit, [], [], []⟩

#guard (parseDataset .chromium referenceChromiumText).toOption.isSome
#guard (parseDataset .webkit referenceWebkitText).toOption.isSome

/-- Every cell has one entry per environment.

A dataset-shape check, run at build time. -/
def Dataset.wellShapedB (d : Dataset) : Bool :=
  d.cells.all (fun c => c.vals.length == d.widths.length && c.srcs.length == d.widths.length)

#guard referenceChromium.wellShapedB
#guard referenceWebkit.wellShapedB

/-! ## Facts about the extracted data (checked at build time)

These `#guard`s state what the committed datasets contain. A regenerated dataset that changes any of them fails the
build, which is the signal to re-read the findings. Cells that WebKit quarantined as unstable (running animations such
as `animation-play-state`, `will-change`) are missing there and read as `onlyChromium`. -/

-- 116 whole-pixel environments and 47 (part, role) rows in both engines.
#guard referenceChromium.widths.length == 116 && referenceWebkit.widths.length == 116
#guard referenceChromium.roles.length == 47 && referenceWebkit.roles.length == 47
-- Kept cells: 1290 in Chromium, 1243 in WebKit (the rest were quarantined by the three-run check or absent there).
#guard referenceChromium.cells.length == 1290
#guard referenceWebkit.cells.length == 1243
-- The original sets its colour, font and background on `body`; 54 Chromium cells are inherited from it, and each has a
-- declaring `body` cell behind it, in both engines.
#guard (referenceChromium.cells.filter inheritedFromBodyB).length == 54
#guard referenceChromium.cells.all (fun c => !inheritedFromBodyB c || referenceChromium.bodyDeclaresB c)
#guard referenceWebkit.cells.all (fun c => !inheritedFromBodyB c || referenceWebkit.bodyDeclaresB c)
-- The engines disagree on 231 keys; `platform.stageBg` is among the parts whose values differ, and only `platform` and
-- `platform.stageBg` differ in declared source alone.
#guard (disagreements referenceChromium referenceWebkit).length == 231
#guard (partsWith referenceChromium referenceWebkit .valueDiffers).contains "platform.stageBg"
#guard partsWith referenceChromium referenceWebkit .sourceDiffers == ["platform", "platform.stageBg"]

end Fw.Site.Reference
