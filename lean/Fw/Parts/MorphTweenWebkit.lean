import Lean.Data.Json

/-!
# Classes of the nav recorder rows (waapi-tail-webkit-p2) and the verdict on the base window
Node twin: `packages/gate-breakpoints/src/trajectory/debug.mjs`; golden: `packages/contracts/golden/parts/morph-tween-webkit-rows.jsonl`.
-/

open Lean

namespace Fw.Parts.MorphTweenWebkit

/-- A transition event of the nav. -/
inductive TrEv where
  | run
  | start
  | finish
  | cancel
deriving Repr, DecidableEq

/-- One recorder row (times in whole ms, widths in thousandths of a px). -/
inductive Row where
  | data (t : Nat) (v : String)
  | base (t : Nat) (v : String)
  | cls (t : Nat) (on : Bool)
  | read (t : Nat)
  | size (t : Nat) (w : Nat)
  | raf (t ts : Nat)
  | tr (t : Nat) (ev : TrEv) (width : Bool)
deriving Repr, DecidableEq

/-- The time a row was logged. -/
def Row.time : Row → Nat
  | .data t _ | .base t _ | .cls t _ | .read t | .size t _ | .raf t _ | .tr t _ _ => t

/-- Slack in ms between a frame timestamp and the callback time of a row written in that frame. -/
def slack : Nat := 2

/-- Tolerance of a width in thousandths of a px (0.04 px). -/
def widthTol : Nat := 40

/-- Distance between two indices. -/
def dist (a b : Nat) : Nat := if a ≤ b then b - a else a - b

/-- The first close flip: the first `is-morphing` off row. -/
def flipIdx (rs : Array Row) : Option Nat :=
  rs.findIdx? fun r => match r with | .cls _ false => true | _ => false

/-- The last data row at or before index `i`: the write that carries the flip. -/
def carrier (rs : Array Row) (i : Nat) : Option Nat :=
  (List.range (i + 1)).reverse.find? fun k => match (rs[k]? : Option Row) with | some (.data _ _) => true | _ => false

/-- The value written by a data row. -/
def valueAt (rs : Array Row) (k : Nat) : Option String :=
  match (rs[k]? : Option Row) with | some (.data _ v) => some v | _ => none

/-- The base row with value `v` nearest to index `i` (the earlier one on a tie): the flip's own base write. -/
def ownBase (rs : Array Row) (i : Nat) (v : String) : Option Nat :=
  ((List.range rs.size).filter fun k => match (rs[k]? : Option Row) with | some (.base _ v') => v' == v | _ => false).foldl
    (fun acc k => match acc with
      | none => some k
      | some a => if dist k i < dist a i then some k else some a) none

/-- Is there an index strictly between `lo` and `hi` whose row satisfies `p`? -/
def betweenAny (rs : Array Row) (lo hi : Nat) (p : Row → Bool) : Bool :=
  (List.range rs.size).any fun k => lo < k && k < hi && match (rs[k]? : Option Row) with | some r => p r | none => false

/-- A row that proves a style flush: the probe's own read. -/
def isRead : Row → Bool
  | .read _ => true
  | _ => false

/-- A row that proves a rendering update after layout: a size row, or a frame that began after time `t0`. -/
def isFrameAfter (t0 : Nat) : Row → Bool
  | .size _ _ => true
  | .raf _ ts => t0 + slack < ts
  | _ => false

/-- What the rows say about the flip's writes. -/
structure Facts where
  readBetween : Bool
  frameBetween : Bool
  baseBefore : Bool
deriving Repr, DecidableEq

/-- The class of the split between the flip and its base write. -/
inductive Split where
  | noFlip
  | noBase
  | probe
  | c1
  | c2
  | c0
deriving Repr, DecidableEq

/-- The facts of the flip at `i`: its data row `d`, its own base row `b`; none without them. -/
def factsAt (rs : Array Row) (i : Nat) : Option Facts :=
  match carrier rs i with
  | none => none
  | some d =>
    match valueAt rs d with
    | none => none
    | some v =>
      match ownBase rs i v with
      | none => none
      | some b =>
        let lo := min d (min i b)
        let hi := max d (max i b)
        let t0 := (rs[lo]?.map Row.time).getD 0
        some ⟨betweenAny rs lo hi isRead, betweenAny rs lo hi (isFrameAfter t0), decide (b < d)⟩

/-- The split class from the facts. -/
def splitOf : Option Facts → Split
  | none => .noBase
  | some f => if f.readBetween then .probe else if f.frameBetween then (if f.baseBefore then .c2 else .c1) else .c0

/-- Branch the flip has no data row or no base row of its value: no split can be named. -/
theorem splitOf_none : splitOf none = .noBase := rfl

/-- Branch a read row between the writes (C-probe): the probe's own flush split them, whatever else lies between. -/
theorem splitOf_probe (fr bb : Bool) : splitOf (some ⟨true, fr, bb⟩) = .probe := by
  simp [splitOf]

/-- Branch a frame or size row between and the base written first (C2). -/
theorem splitOf_c2 : splitOf (some ⟨false, true, true⟩) = .c2 := by
  simp [splitOf]

/-- Branch a frame or size row between and the base written after the data (C1). -/
theorem splitOf_c1 : splitOf (some ⟨false, true, false⟩) = .c1 := by
  simp [splitOf]

/-- Branch nothing between (C0): no split, whatever the write order. -/
theorem splitOf_c0 (bb : Bool) : splitOf (some ⟨false, false, bb⟩) = .c0 := by
  simp [splitOf]

/-- The split of the first close flip of a rep. -/
def splitRep (rs : Array Row) : Split :=
  match flipIdx rs with
  | none => .noFlip
  | some i => splitOf (factsAt rs i)

/-- Does the row cancel a width transition? -/
def isWidthCancel : Row → Bool
  | .tr _ .cancel true => true
  | _ => false

/-- Is the row a write of the page (a data or base row)? -/
def isWrite : Row → Bool
  | .data _ _ | .base _ _ => true
  | _ => false

/-- The nearest write before index `k`. -/
def lastWrite (rs : Array Row) (k : Nat) : Option Nat :=
  (List.range k).reverse.find? fun j => match (rs[j]? : Option Row) with | some r => isWrite r | none => false

/-- A cancel is caused by a write when at most one read row lies between that write and the cancel. -/
def causedAt (rs : Array Row) (k : Nat) : Bool :=
  match lastWrite rs k with
  | none => false
  | some w => decide ((((List.range k).filter fun j => w < j && ((rs[j]?.map isRead).getD false)).length) ≤ 1)

/-- The width cancels after index `i`, as (caused by a write, not caused). -/
def cancelCounts (rs : Array Row) (i : Nat) : Nat × Nat :=
  (List.range rs.size).foldl (fun (c, u) k =>
    match (rs[k]? : Option Row) with
    | some r => if i < k && isWidthCancel r then (if causedAt rs k then (c + 1, u) else (c, u + 1)) else (c, u)
    | none => (c, u)) (0, 0)

/-- Is there a width `transitionrun` after index `i`? -/
def runAfter (rs : Array Row) (i : Nat) : Bool :=
  (List.range rs.size).any fun k => i < k && match (rs[k]? : Option Row) with | some (.tr _ .run true) => true | _ => false

/-- The class of the transitions after the flip. -/
inductive Trans where
  | none
  | c3
  | c4
deriving Repr, DecidableEq

/-- C3: some width transition is cancelled by nothing the page wrote. C4: two or more width cancels, each by a base write. -/
def transOf (caused uncaused : Nat) : Trans :=
  if 1 ≤ uncaused then .c3 else if 2 ≤ caused then .c4 else .none

/-- Branch a cancel nothing explains (C3). -/
theorem transOf_c3 (c u : Nat) (h : 1 ≤ u) : transOf c u = .c3 := by
  simp [transOf, h]

/-- Branch no unexplained cancel and a train of cancels by base writes (C4). -/
theorem transOf_c4 (c : Nat) (h : 2 ≤ c) : transOf c 0 = .c4 := by
  simp [transOf, h]

/-- Branch no unexplained cancel and fewer than two cancels by base writes. -/
theorem transOf_none (c : Nat) (h : c < 2) : transOf c 0 = .none := by
  simp [transOf]
  omega

/-- The transition class of the first close flip of a rep. -/
def transRep (rs : Array Row) : Trans :=
  match flipIdx rs with
  | none => .none
  | some i => let (c, u) := cancelCounts rs i; transOf c u

/-- The class of a rep: the first that holds of C-probe, C3, C4, C1, C2, C0. -/
inductive Cls where
  | noFlip
  | noBase
  | cProbe
  | c3
  | c4
  | c1
  | c2
  | c0
deriving Repr, DecidableEq

/-- The class from the split and the transitions. -/
def clsOf (s : Split) (t : Trans) : Cls :=
  match s with
  | .noFlip => .noFlip
  | .noBase => .noBase
  | .probe => .cProbe
  | _ => match t with
    | .c3 => .c3
    | .c4 => .c4
    | .none => match s with | .c1 => .c1 | .c2 => .c2 | _ => .c0

/-- Branch a read between the writes: C-probe, whatever the transitions did. -/
theorem clsOf_probe (t : Trans) : clsOf .probe t = .cProbe := rfl

/-- Branch no read between and a transition class: that class. -/
theorem clsOf_c3 (s : Split) (h : s = .c0 ∨ s = .c1 ∨ s = .c2) : clsOf s .c3 = .c3 := by
  rcases h with rfl | rfl | rfl <;> rfl

/-- Branch no read between, no transition class: the split class. -/
theorem clsOf_split (s : Split) (h : s = .c0 ∨ s = .c1 ∨ s = .c2) :
    clsOf s .none = (match s with | .c1 => .c1 | .c2 => .c2 | _ => .c0) := by
  rcases h with rfl | rfl | rfl <;> rfl

/-- The rest width of a rep: the width of its last size row. -/
def restW (rs : Array Row) : Option Nat :=
  (List.range rs.size).reverse.findSome? fun k => match (rs[k]? : Option Row) with | some (.size _ w) => some w | _ => none

/-- The last size row before index `lo` and the first size row after index `hi`. -/
def sizesAround (rs : Array Row) (lo hi : Nat) : Option Nat × Option Nat :=
  ( (List.range lo).reverse.findSome? fun k => match (rs[k]? : Option Row) with | some (.size _ w) => some w | _ => none,
    (List.range rs.size).findSome? fun k => if hi < k then (match (rs[k]? : Option Row) with | some (.size _ w) => some w | _ => none) else none)

/-- Does the width stay above the rest width after the flip, as the original's transition does? -/
inductive Hold where
  | unseen
  | held
  | jumped
deriving Repr, DecidableEq

/-- Unseen when the width before is within `2 * widthTol` of rest; held when the width after keeps half the excess. -/
def holdOf (rest : Option Nat) (prev next : Option Nat) : Hold :=
  match rest, prev, next with
  | some r, some p, some n =>
    if p ≤ r + 2 * widthTol then .unseen else if (p - r) ≤ 2 * (n - r) ∧ r ≤ n then .held else .jumped
  | _, _, _ => .unseen

/-- Branch the width before the flip is no more than `2 * widthTol` above rest: nothing to hold, no decision. -/
theorem holdOf_flat (r p n : Nat) (h : p ≤ r + 2 * widthTol) : holdOf (some r) (some p) (some n) = .unseen := by
  simp [holdOf, h]

/-- Branch the width after keeps at least half of the excess: held. -/
theorem holdOf_held (r p n : Nat) (h : ¬ p ≤ r + 2 * widthTol) (h2 : p - r ≤ 2 * (n - r)) (h3 : r ≤ n) :
    holdOf (some r) (some p) (some n) = .held := by
  simp [holdOf, h, h2, h3]

/-- Branch the width after dropped below half of the excess: jumped. -/
theorem holdOf_jumped (r p n : Nat) (h : ¬ p ≤ r + 2 * widthTol) (h2 : 2 * (n - r) < p - r) :
    holdOf (some r) (some p) (some n) = .jumped := by
  have h3 : ¬ (p - r ≤ 2 * (n - r) ∧ r ≤ n) := fun hh => absurd hh.1 (Nat.not_le.mpr h2)
  simp only [holdOf, h, h3, ite_false]

/-- The hold of the first close flip of a rep. -/
def holdRep (rs : Array Row) : Hold :=
  match flipIdx rs with
  | none => .unseen
  | some i =>
    match carrier rs i with
    | none => .unseen
    | some d =>
      let (p, n) := sizesAround rs (min d i) (max d i)
      holdOf (restW rs) p n

/-- The verdict on the base window of one engine cell. -/
inductive Verdict where
  | needMore
  | keep
  | drop
deriving Repr, DecidableEq

/-- Keep iff some hit rep held, drop iff some jumped and none held, no claim under three runs. -/
def verdict (runs : Nat) (holds : List Hold) : Verdict :=
  if runs < 3 then .needMore
  else if holds.contains .held then .keep
  else if holds.contains .jumped then .drop
  else .needMore

/-- Branch fewer than three runs: no claim. -/
theorem verdict_needMore (runs : Nat) (holds : List Hold) (h : runs < 3) : verdict runs holds = .needMore := by
  simp [verdict, h]

/-- Branch three runs and one held rep: keep. -/
theorem verdict_keep (runs : Nat) (holds : List Hold) (h : 3 ≤ runs) (hh : Hold.held ∈ holds) : verdict runs holds = .keep := by
  have : ¬ runs < 3 := by omega
  simp [verdict, this, hh]

/-- Branch three runs, a jumped rep and no held rep: drop. -/
theorem verdict_drop (runs : Nat) (holds : List Hold) (h : 3 ≤ runs) (hh : Hold.held ∉ holds) (hj : Hold.jumped ∈ holds) :
    verdict runs holds = .drop := by
  have : ¬ runs < 3 := by omega
  simp [verdict, this, hh, hj]

/-- Branch three runs and every hit rep unseen: no claim. -/
theorem verdict_unseen (runs : Nat) (holds : List Hold) (h : 3 ≤ runs) (hh : Hold.held ∉ holds) (hj : Hold.jumped ∉ holds) :
    verdict runs holds = .needMore := by
  have : ¬ runs < 3 := by omega
  simp [verdict, this, hh, hj]

/-- **A drop never discards a held rep.** -/
theorem drop_no_held (runs : Nat) (holds : List Hold) (h : verdict runs holds = .drop) : Hold.held ∉ holds := by
  intro hh
  by_cases h3 : runs < 3
  · simp [verdict, h3] at h
  · simp [verdict, h3, hh] at h

/-! ## Rows from the raw JSON of the page -/

/-- A JSON number scaled by `s` and rounded to a whole number. -/
def scaled (s : Nat) (j : Json) : Option Nat :=
  match j.getNum? with
  | .ok n => if n.mantissa < 0 then none else some ((n.mantissa.toNat * s * 2 + 10 ^ n.exponent) / (2 * 10 ^ n.exponent))
  | .error _ => none

/-- The value text of a data or base row. -/
def valText (j : Json) : String := match j.getStr? with | .ok s => s | .error _ => ""

/-- One raw recorder row. Rows of an unknown kind give none. -/
def rowOfJson (j : Json) : Option Row := do
  let k ← (j.getObjVal? "k" >>= Json.getStr?).toOption
  let t ← (j.getObjVal? "t").toOption >>= scaled 1
  match k with
  | "data" => some (.data t (valText ((j.getObjVal? "v").toOption.getD .null)))
  | "base" => some (.base t (valText ((j.getObjVal? "v").toOption.getD .null)))
  | "cls" => some (.cls t ((j.getObjVal? "on" >>= Json.getBool?).toOption.getD false))
  | "read" => some (.read t)
  | "size" => do
    let w ← (j.getObjVal? "w").toOption >>= scaled 1000
    some (.size t w)
  | "raf" => do
    let ts ← (j.getObjVal? "ts").toOption >>= scaled 1
    some (.raf t ts)
  | "tr" =>
    let ev := match (j.getObjVal? "type" >>= Json.getStr?).toOption.getD "" with
      | "transitionrun" => some TrEv.run
      | "transitionstart" => some TrEv.start
      | "transitionend" => some TrEv.finish
      | "transitioncancel" => some TrEv.cancel
      | _ => none
    ev.map fun e => .tr t e (((j.getObjVal? "prop" >>= Json.getStr?).toOption.getD "") == "width")
  | _ => none

/-- The rows of a raw log (rows of an unknown kind are dropped). -/
def rowsOfJson (j : Json) : Array Row :=
  match j.getArr? with
  | .ok a => a.filterMap rowOfJson
  | .error _ => #[]

/-- A row as a JSON list for the golden. -/
def Row.toJson : Row → Json
  | .data t v => Json.arr #["data", t, v]
  | .base t v => Json.arr #["base", t, v]
  | .cls t on => Json.arr #["cls", t, on]
  | .read t => Json.arr #["read", t]
  | .size t w => Json.arr #["size", t, w]
  | .raf t ts => Json.arr #["raf", t, ts]
  | .tr t e w => Json.arr #["tr", t, (match e with | .run => "run" | .start => "start" | .finish => "end" | .cancel => "cancel"), w]

/-- The name of a class. -/
def Cls.name : Cls → String
  | .noFlip => "noFlip" | .noBase => "noBase" | .cProbe => "cProbe" | .c3 => "c3" | .c4 => "c4"
  | .c1 => "c1" | .c2 => "c2" | .c0 => "c0"

/-- The name of a hold. -/
def Hold.name : Hold → String
  | .unseen => "unseen" | .held => "held" | .jumped => "jumped"

/-- The name of a verdict. -/
def Verdict.name : Verdict → String
  | .needMore => "needMore" | .keep => "keep" | .drop => "drop"

/-- The class of a rep. -/
def classRep (rs : Array Row) : Cls := clsOf (splitRep rs) (transRep rs)

/-- The golden line of one case: its rows, class and hold. -/
def repLine (c : Json) : Json :=
  let rs := rowsOfJson ((c.getObjVal? "raw").toOption.getD .null)
  Json.mkObj [("kind", "rep"), ("name", (c.getObjVal? "name").toOption.getD .null),
    ("rows", Json.arr (rs.map Row.toJson)), ("class", (classRep rs).name), ("hold", (holdRep rs).name)]

/-- The golden line of a verdict case. -/
def verdictLine (runs : Nat) (holds : List Hold) : Json :=
  Json.mkObj [("kind", "verdict"), ("runs", runs), ("holds", Json.arr (holds.map fun h => (h.name : Json)).toArray),
    ("verdict", (verdict runs holds).name)]

/-- The verdict cases of the golden. -/
def verdictCases : List (Nat × List Hold) :=
  [(2, [.jumped]), (2, [.held]), (3, [.held, .jumped]), (3, [.jumped, .jumped]), (5, [.jumped, .unseen, .jumped]),
   (3, [.unseen]), (4, []), (3, [.held])]

/-- The golden: one line per case of `morph-tween-webkit-rows.cases.json`, then one per verdict case. -/
def goldenText (cases : String) : String :=
  let cs := match Json.parse cases with | .ok j => (j.getArr?.toOption.getD #[]).toList | .error _ => []
  String.join ((cs.map repLine ++ verdictCases.map fun (n, hs) => verdictLine n hs).map fun r => r.compress ++ "\n")

/-- **Measured:** runs 39571243779, 39572308204 and 39573516482 (macOS WebKit 1280) hold 15 jumped cand reps, no held one. -/
theorem drop_on_measured : verdict 3 (List.replicate 15 Hold.jumped) = .drop :=
  verdict_drop 3 _ (by omega) (by simp) (by simp)

#guard goldenText (include_str "../../../packages/contracts/golden/parts/morph-tween-webkit-rows.cases.json") ==
  include_str "../../../packages/contracts/golden/parts/morph-tween-webkit-rows.jsonl"

end Fw.Parts.MorphTweenWebkit
