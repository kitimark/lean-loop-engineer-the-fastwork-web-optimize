import Lean.Data.Json
import Fw.Device.EndWktr
/-! End of page on the WKTR flip arm: which DOM writer carries the all-paused style-recalc floor.

The floor is the flip with every animation and SMIL paused (`pall` in `EndWktr`) and the nav held dark (the flip starts only once
`is-on-dark` is on, and a silenced write must not end the flip). A writer arm repeats the flip with the same pause and pin and one set
of DOM writes silenced; the mutation table of that arm must then hold none of the silenced keys. -/
namespace Fw.Device.EndFloor
open Lean Fw.Device.EndWktr

/-- A set of writes silenced together, named by its harness arm. -/
inductive Writer where
  | style | data | pub | cls | panel | plat | write
  deriving DecidableEq, Repr

def Writer.all : List Writer := [.style, .data, .pub, .cls, .panel, .plat, .write]

def Writer.arm : Writer → String
  | .style => "qstyle" | .data => "qdata" | .pub => "qpub" | .cls => "qclass" | .panel => "qpanel" | .plat => "qplat"
  | .write => "qwrite"

/-- The `part#what` mutation keys the arm silences (`what`: an attribute name, `style`, or `class`). -/
def Writer.keys : Writer → List String
  | .style => ["nav#style"]
  | .data => ["nav#data-fw-morph"]
  | .pub => ["nav#style", "nav#data-fw-morph"]
  | .cls => ["nav#class", "nav-earn#aria-hidden", "nav-earn#tabindex"]
  | .panel => ["morph-panel#aria-hidden", "morph-panel#data-expanded", "morph-panel#data-start-selling-scene", "morph-panel#tabindex"]
  | .plat => ["platform#style"]
  | .write => ["nav#style", "nav#data-fw-morph", "nav#class", "nav-earn#aria-hidden", "nav-earn#tabindex", "morph-panel#aria-hidden",
      "morph-panel#data-expanded", "morph-panel#data-start-selling-scene", "morph-panel#tabindex", "platform#style"]

/-- Every writer set is inside the reference arm `qwrite`, so the reference silences at least what any writer arm does. -/
theorem keys_in_write (w : Writer) : ∀ k ∈ w.keys, k ∈ Writer.write.keys := by
  cases w <;> decide

theorem pub_keys : Writer.pub.keys = Writer.style.keys ++ Writer.data.keys := rfl

/-- One frame of a flip window: style recalcs in it and the mutation keys seen in it. -/
structure Frame where
  r : Nat
  keys : List String
  deriving DecidableEq, Repr

def rate (fs : List Frame) : Nat := rpf100 (fs.map (·.r))

/-- Frames that carry a key the arm silenced: a write that got through. -/
def leaks (muted : List String) (fs : List Frame) : Nat := (fs.filter fun f => f.keys.any (muted.contains ·)).length

/-- Two floor reads (before and after the writer arms), the reference arm with every write silenced, and one writer arm. -/
structure Cell where
  pall : List (List Frame)
  all : List Frame
  var : List Frame
  muted : List String
  deriving DecidableEq, Repr

structure Nums where
  np : Nat
  na : Nat
  nv : Nat
  p : Nat
  a : Nat
  s : Nat
  spread : Nat
  leakV : Nat
  leakA : Nat
  deriving DecidableEq, Repr

def Cell.nums (c : Cell) : Nums where
  np := (c.pall.map List.length).sum
  na := c.all.length
  nv := c.var.length
  p := rate c.pall.flatten
  a := rate c.all
  s := rate c.var
  spread := spreadOf (c.pall.map rate)
  leakV := leaks c.muted c.var
  leakA := leaks Writer.write.keys c.all

/-- Recalcs per 100 frames the silenced writers can account for in all: floor minus reference. -/
def Nums.gap (x : Nums) : Nat := x.p - x.a

/-- Smallest difference the rule reads: a sixteenth of the gap, or the spread of the two floor reads when larger. -/
def Nums.band (x : Nums) : Nat := max (x.gap / bandDen) x.spread

/-- Recalcs per 100 frames removed by silencing this writer alone. -/
def Nums.cut (x : Nums) : Nat := x.p - x.s

inductive W where
  | unread | leaked | noWrites | carries | raises | noEffect
  deriving DecidableEq, Repr

def W.name : W → String
  | .unread => "unread" | .leaked => "leaked" | .noWrites => "no writes" | .carries => "carries" | .raises => "raises"
  | .noEffect => "no effect"

def judge (x : Nums) : W :=
  if x.np < minFlip ∨ x.na < minFlip ∨ x.nv < minFlip then .unread
  else if 0 < x.leakV ∨ 0 < x.leakA then .leaked
  else if x.gap ≤ 2 * x.band then .noWrites
  else if x.s + x.band < x.p then .carries
  else if x.p + x.band < x.s then .raises
  else .noEffect

theorem judge_unread (x : Nums) (h : x.np < minFlip ∨ x.na < minFlip ∨ x.nv < minFlip) : judge x = .unread := by
  simp [judge, h]

theorem judge_leaked (x : Nums) (h0 : ¬(x.np < minFlip ∨ x.na < minFlip ∨ x.nv < minFlip)) (h : 0 < x.leakV ∨ 0 < x.leakA) :
    judge x = .leaked := by
  simp only [judge, h0, h, ite_true, ite_false]

theorem judge_noWrites (x : Nums) (h0 : ¬(x.np < minFlip ∨ x.na < minFlip ∨ x.nv < minFlip)) (h1 : ¬(0 < x.leakV ∨ 0 < x.leakA))
    (h : x.gap ≤ 2 * x.band) : judge x = .noWrites := by
  simp only [judge, h0, h1, h, ite_true, ite_false]

theorem judge_carries (x : Nums) (h0 : ¬(x.np < minFlip ∨ x.na < minFlip ∨ x.nv < minFlip)) (h1 : ¬(0 < x.leakV ∨ 0 < x.leakA))
    (h2 : ¬x.gap ≤ 2 * x.band) (h : x.s + x.band < x.p) : judge x = .carries := by
  simp only [judge, h0, h1, h2, h, ite_true, ite_false]

theorem judge_raises (x : Nums) (h0 : ¬(x.np < minFlip ∨ x.na < minFlip ∨ x.nv < minFlip)) (h1 : ¬(0 < x.leakV ∨ 0 < x.leakA))
    (h2 : ¬x.gap ≤ 2 * x.band) (h3 : ¬x.s + x.band < x.p) (h : x.p + x.band < x.s) : judge x = .raises := by
  simp only [judge, h0, h1, h2, h3, h, ite_true, ite_false]

theorem judge_noEffect (x : Nums) (h0 : ¬(x.np < minFlip ∨ x.na < minFlip ∨ x.nv < minFlip)) (h1 : ¬(0 < x.leakV ∨ 0 < x.leakA))
    (h2 : ¬x.gap ≤ 2 * x.band) (h3 : ¬x.s + x.band < x.p) (h4 : ¬x.p + x.band < x.s) : judge x = .noEffect := by
  simp only [judge, h0, h1, h2, h3, h4, ite_false]

/-- A `carries` verdict means the arm's rate is below the floor by more than the band, so the cut exceeds the band. -/
theorem carries_cut (x : Nums) (h : judge x = .carries) : x.band < x.cut := by
  by_cases h1 : x.np < minFlip ∨ x.na < minFlip ∨ x.nv < minFlip
  · simp [judge, h1] at h
  by_cases h2 : 0 < x.leakV ∨ 0 < x.leakA
  · simp [judge, h1, h2] at h
  by_cases h3 : x.gap ≤ 2 * x.band
  · simp [judge, h1, h2, h3] at h
  by_cases h4 : x.s + x.band < x.p
  · unfold Nums.cut
    omega
  by_cases h5 : x.p + x.band < x.s
  · simp [judge, h1, h2, h3, h4, h5] at h
  · simp [judge, h1, h2, h3, h4, h5] at h

/-- A `noWrites` verdict means even silencing every write moves the floor by at most two bands. -/
theorem noWrites_gap (x : Nums) (h : judge x = .noWrites) : x.gap ≤ 2 * x.band := by
  by_cases h1 : x.np < minFlip ∨ x.na < minFlip ∨ x.nv < minFlip
  · simp [judge, h1] at h
  by_cases h2 : 0 < x.leakV ∨ 0 < x.leakA
  · simp [judge, h1, h2] at h
  by_cases h3 : x.gap ≤ 2 * x.band
  · exact h3
  by_cases h4 : x.s + x.band < x.p
  · simp [judge, h1, h2, h3, h4] at h
  by_cases h5 : x.p + x.band < x.s
  · simp [judge, h1, h2, h3, h4, h5] at h
  · simp [judge, h1, h2, h3, h4, h5] at h

/-- A writer arm with its verdict, the floor it was read against, and the cut. -/
structure Entry where
  w : Writer
  v : W
  p : Nat
  cut : Nat
  deriving DecidableEq, Repr

/-- The writer carries most of the floor: its arm is below the floor by more than the band and the cut is over half the floor. -/
def Entry.dominant (e : Entry) : Bool := e.v == .carries && e.p < 2 * e.cut

inductive F where
  | unread | noWrites | dominant (w : Writer) | several | spread | joint
  deriving DecidableEq, Repr

def F.name : F → String
  | .unread => "unread" | .noWrites => "no writes" | .dominant w => "dominant " ++ w.arm | .several => "several dominate"
  | .spread => "spread over writers" | .joint => "joint"

/-- One job: the reference arm's verdict, then the writer arms (the reference itself excluded). -/
def finding (allV : W) (es : List Entry) : F :=
  if allV = .unread ∨ allV = .leaked then .unread
  else if allV = .noWrites then .noWrites
  else match es.filter Entry.dominant with
    | [] => if es.any (·.v == .carries) then .spread else .joint
    | [e] => .dominant e.w
    | _ :: _ :: _ => .several

theorem finding_unread (allV : W) (es : List Entry) (h : allV = .unread ∨ allV = .leaked) : finding allV es = .unread := by
  simp [finding, h]

theorem finding_noWrites (es : List Entry) : finding .noWrites es = .noWrites := by
  simp [finding]

theorem finding_dominant (allV : W) (es : List Entry) (e : Entry) (h0 : ¬(allV = .unread ∨ allV = .leaked)) (h1 : allV ≠ .noWrites)
    (h : es.filter Entry.dominant = [e]) : finding allV es = .dominant e.w := by
  simp [finding, h0, h1, h]

theorem finding_several (allV : W) (es : List Entry) (a b : Entry) (t : List Entry) (h0 : ¬(allV = .unread ∨ allV = .leaked))
    (h1 : allV ≠ .noWrites) (h : es.filter Entry.dominant = a :: b :: t) : finding allV es = .several := by
  simp [finding, h0, h1, h]

theorem finding_spread (allV : W) (es : List Entry) (h0 : ¬(allV = .unread ∨ allV = .leaked)) (h1 : allV ≠ .noWrites)
    (h : es.filter Entry.dominant = []) (hc : es.any (·.v == .carries) = true) : finding allV es = .spread := by
  simp [finding, h0, h1, h, hc]

theorem finding_joint (allV : W) (es : List Entry) (h0 : ¬(allV = .unread ∨ allV = .leaked)) (h1 : allV ≠ .noWrites)
    (h : es.filter Entry.dominant = []) (hc : es.any (·.v == .carries) = false) : finding allV es = .joint := by
  simp [finding, h0, h1, h, hc]

/-- A dominant writer's own cut is over half the floor. -/
theorem dominant_half (e : Entry) (h : e.dominant = true) : e.p < 2 * e.cut := by
  simp only [Entry.dominant, Bool.and_eq_true, decide_eq_true_eq] at h
  exact h.2

/-- Two writers whose cuts do not overlap (their sum is at most the floor) cannot both dominate: a `several` finding means the writes share frames. -/
theorem several_overlap (p c₁ c₂ : Nat) (h₁ : p < 2 * c₁) (h₂ : p < 2 * c₂) : p < c₁ + c₂ := by omega

/-- Jobs whose findings are `unread` are left out; two or more others must name the same finding. -/
def overallF (fs : List F) : String := overallNames ((fs.filter fun f => f != .unread).map F.name)

theorem overallF_inconclusive (fs : List F) (h : (fs.filter fun f => f != .unread).length < minValid) : overallF fs = "inconclusive" := by
  simpa [overallF] using overallNames_inconclusive _ (by simpa using h)

/-- Verdicts of one writer over the jobs: `unread` and `leaked` jobs are left out; two or more others must agree. -/
def overallW (vs : List W) : String := overallNames ((vs.filter fun v => v != .unread && v != .leaked).map W.name)

theorem overallW_inconclusive (vs : List W) (h : (vs.filter fun v => v != .unread && v != .leaked).length < minValid) :
    overallW vs = "inconclusive" := by
  simpa [overallW] using overallNames_inconclusive _ (by simpa using h)

private def fr (r : Nat) (ks : List String := []) : Frame := ⟨r, ks⟩

private def quiet (k : Nat) : List Frame := (List.range k).map fun _ => fr 0

/-- `k` frames of which `n` out of every 20 carry `r` recalcs and the keys. -/
private def mixed (k n r : Nat) (ks : List String) : List Frame :=
  (List.range k).map fun i => if i % 20 < n then fr r ks else fr 0

private def listJ (xs : List Nat) : Json := Json.arr (xs.map fun x => toJson x).toArray

private def frameJ (f : Frame) : Json := Json.arr #[toJson f.r, Json.arr (f.keys.map Json.str).toArray]

private def framesJ (fs : List Frame) : Json := Json.arr (fs.map frameJ).toArray

private def keysJ (ks : List String) : Json := Json.arr (ks.map Json.str).toArray

private def cellJ (c : Cell) : Json :=
  Json.mkObj [("pall", Json.arr (c.pall.map framesJ).toArray), ("all", framesJ c.all), ("var", framesJ c.var), ("muted", keysJ c.muted)]

private def numsJ (x : Nums) : Json :=
  Json.mkObj [("np", x.np), ("na", x.na), ("nv", x.nv), ("p", x.p), ("a", x.a), ("s", x.s), ("spread", x.spread), ("leakV", x.leakV),
    ("leakA", x.leakA)]

private def pub : List String := Writer.pub.keys

/-- Two floor reads of 100 frames at 80 recalcs per 100 frames; the reference arms below sit at 0. -/
private def floorReads : List (List Frame) := [mixed 100 16 1 pub, mixed 100 16 1 pub]

private def cellCases : List (String × Cell) :=
  [("writer carries all", ⟨floorReads, quiet 100, quiet 100, Writer.pub.keys⟩),
   ("writer carries nothing", ⟨floorReads, quiet 100, mixed 100 16 1 pub, Writer.cls.keys⟩),
   ("no writes in the floor", ⟨[quiet 100, quiet 100], quiet 100, quiet 100, Writer.pub.keys⟩),
   ("write leaked", ⟨floorReads, quiet 100, mixed 100 4 1 pub, Writer.pub.keys⟩),
   ("reference leaked", ⟨floorReads, mixed 100 1 1 ["nav#class"], quiet 100, Writer.pub.keys⟩),
   ("too few frames", ⟨floorReads, quiet 100, quiet 10, Writer.pub.keys⟩),
   ("raises", ⟨floorReads, quiet 100, mixed 100 100 1 [], Writer.cls.keys⟩)]

private def numsCases : List (String × Nums) :=
  let ok : Nums := ⟨100, 100, 100, 100, 0, 0, 0, 0, 0⟩
  [("edge carries", { ok with s := 93 }), ("edge no effect below", { ok with s := 94 }), ("edge no effect above", { ok with s := 106 }),
   ("edge raises", { ok with s := 107 }), ("spread widens the band", { ok with s := 80, spread := 20 }),
   ("reference equals floor", { ok with a := 100, s := 0 }), ("edge no writes", { ok with a := 80, s := 0, spread := 10 }),
   ("edge writes", { ok with a := 79, s := 0, spread := 10 }), ("writes", { ok with a := 50, s := 0 }),
   ("edge unread", { ok with nv := 11 }), ("edge read", { ok with nv := 12 }), ("leaked writer", { ok with leakV := 1 }),
   ("leaked reference", { ok with leakA := 1 })]

private def entryCases : List (String × W × List Entry) :=
  let e (w : Writer) (v : W) (cut : Nat) : Entry := ⟨w, v, 80, cut⟩
  [("one dominates", .carries, [e .style .noEffect 0, e .data .noEffect 0, e .pub .carries 50, e .cls .carries 10, e .panel .noEffect 0]),
   ("edge half is not most", .carries, [e .pub .carries 40, e .cls .carries 20]),
   ("edge most", .carries, [e .pub .carries 41, e .cls .carries 20]),
   ("several", .carries, [e .pub .carries 45, e .cls .carries 45]),
   ("spread", .carries, [e .pub .carries 30, e .cls .carries 20, e .panel .carries 10]),
   ("joint", .carries, [e .style .noEffect 0, e .data .noEffect 0, e .cls .noEffect 0]),
   ("no writes", .noWrites, [e .pub .noEffect 0]),
   ("unread reference", .unread, [e .pub .carries 60]),
   ("leaked reference", .leaked, [e .pub .carries 60]),
   ("carries unread arm does not dominate", .carries, [e .pub .unread 60, e .cls .carries 10])]

private def overallWCases : List (String × List W) :=
  [("three carry", [.carries, .carries, .carries]), ("two carry one leaked", [.carries, .leaked, .carries]),
   ("one judged", [.carries, .unread, .unread]), ("mixed", [.carries, .noEffect, .carries]), ("three no effect", [.noEffect, .noEffect, .noEffect])]

private def overallCases : List (String × List F) :=
  [("three alike", [.dominant .pub, .dominant .pub, .dominant .pub]), ("two alike one unread", [.joint, .unread, .joint]),
   ("one job", [.spread]), ("mixed", [.dominant .pub, .dominant .cls, .dominant .pub]),
   ("dominant against spread", [.dominant .pub, .spread, .dominant .pub])]

def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("minFlip", minFlip), ("bandDen", bandDen), ("minValid", minValid)]).compress] ++
  (Writer.all.map fun w =>
    (Json.mkObj [("kind", "writer"), ("writer", Json.str w.arm), ("keys", keysJ w.keys)]).compress) ++
  (numsCases.map fun (n, x) =>
    (Json.mkObj [("kind", "judge"), ("name", n), ("nums", numsJ x), ("gap", x.gap), ("band", x.band), ("cut", x.cut),
      ("verdict", Json.str (judge x).name)]).compress) ++
  (cellCases.map fun (n, c) =>
    let x := c.nums
    (Json.mkObj [("kind", "cell"), ("name", n), ("cell", cellJ c), ("nums", numsJ x), ("gap", x.gap), ("band", x.band), ("cut", x.cut),
      ("verdict", Json.str (judge x).name)]).compress) ++
  (entryCases.map fun (n, allV, es) =>
    (Json.mkObj [("kind", "finding"), ("name", n), ("all", Json.str allV.name),
      ("entries", Json.arr (es.map fun e => Json.arr #[Json.str e.w.arm, Json.str e.v.name, toJson e.p, toJson e.cut]).toArray),
      ("finding", Json.str (finding allV es).name)]).compress) ++
  (overallWCases.map fun (n, vs) =>
    (Json.mkObj [("kind", "overallW"), ("name", n), ("verdicts", Json.arr (vs.map fun v => Json.str v.name).toArray),
      ("overall", Json.str (overallW vs))]).compress) ++
  (overallCases.map fun (n, fs) =>
    (Json.mkObj [("kind", "overall"), ("name", n), ("findings", Json.arr (fs.map fun f => Json.str f.name).toArray),
      ("overall", Json.str (overallF fs))]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "device" / "end-floor.jsonl"

def checkRepo : IO Unit := do
  let cur ← IO.FS.readBinFile goldenPath
  if cur.data != (goldenText ()).toUTF8.data then throw (IO.userError s!"device-end-floor golden differs: {goldenPath}")
  IO.println s!"device-end-floor golden: up to date ({(goldenLines ()).length} lines)"

def writeRepo : IO Unit := IO.FS.writeFile goldenPath (goldenText ())

end Fw.Device.EndFloor
