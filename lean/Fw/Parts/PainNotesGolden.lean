import Lean.Data.Json
import Fw.Parts.PainNotes
/-!
# Golden vectors for pain.notes

`PainNotesGolden.lines` is the content of `packages/contracts/golden/parts/pain.notes.jsonl` (same line format and
encodings as `Fw/Parts/Golden.lean`: `Rat` inputs as exact JSON decimals, `Rat` outputs in the wire form
`{"num","den"}`). It has no `main`: write it with a one-line driver, e.g. `lake env lean --run` on a file that does
`IO.FS.writeFile path (String.intercalate "\n" lines ++ "\n")`. `Golden.lean` can append `PainNotesGolden.lines` to its
own table in one line (left to the lead: shared file).
-/
namespace Fw.Parts.PainNotesGolden
open Lean Fw.Parts.PainNotes

/-- A rational input as an exact JSON decimal (denominators here divide $1000$).
$$q \mapsto q \cdot 10^3 \cdot 10^{-3}$$ -/
def rin (q : Rat) : Json := .num ⟨q.num * ((1000 / q.den : Nat) : Int), 3⟩

/-- The `Rat` output wire form. $$q \mapsto \{\mathrm{num}, \mathrm{den}\}$$ -/
def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- One golden line. $$(\mathit{fn}, \mathit{in}, \mathit{out}) \mapsto \text{JSON line}$$ -/
def line (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", .str fn), ("in", Json.mkObj inp), ("out", out)]).compress

/-- A box as an input. $$B \mapsto \{\ell, t, w, h\}$$ -/
def boxIn (b : Box) : Json :=
  Json.mkObj [("left", rin b.left), ("top", rin b.top), ("width", rin b.width), ("height", rin b.height)]

/-- A box as an output. $$B \mapsto \{\ell, t, w, h\}$$ with wire rationals. -/
def boxOut (b : Box) : Json :=
  Json.mkObj [("left", ratWire b.left), ("top", ratWire b.top), ("width", ratWire b.width), ("height", ratWire b.height)]

/-- A note as an output. $$n \mapsto \{\mathrm{id}, \mathrm{text}, \mathrm{bg}, \theta, \ell, t, z, \mathrm{extra}\}$$ -/
def noteOut (n : Note) : Json :=
  Json.mkObj [("id", .str n.id), ("text", .num ⟨n.text, 0⟩), ("bg", .str n.bg), ("rotate", .num ⟨n.rotate, 0⟩),
    ("left", ratWire n.left), ("top", ratWire n.top), ("z", .num ⟨n.z, 0⟩), ("extra", .bool n.extra)]

/-- Option of a note. $$\operatorname{some}(n) \mapsto n,\ \operatorname{none} \mapsto \mathrm{null}$$ -/
def noteOpt : Option Note → Json
  | some n => noteOut n
  | none => .null

/-- Option of a pair. $$\operatorname{some}(a, b) \mapsto [a, b],\ \operatorname{none} \mapsto \mathrm{null}$$ -/
def pairOpt : Option (Rat × Rat) → Json
  | some (a, b) => Json.arr #[ratWire a, ratWire b]
  | none => .null

/-- Tick name. $$t \mapsto \text{"skip"} \mid \text{"clear"} \mid \text{"add"}$$ -/
def tickName : Tick → String
  | .skip => "skip" | .clear => "clear" | .add => "add"

/-- Unsigned seed as a JSON integer. $$s \mapsto s \in \mathbb{N}$$ -/
def seedJ (s : UInt32) : Json := .num ⟨s.toNat, 0⟩

/-- Booleans. $$\mathbb B$$ -/
def bs : List Bool := [false, true]

/-- Sample numbers around the edges. $$X = \{-5, 0, 0.5, 3, 12.5, 50, 99.9, 100, 120\}$$ -/
def xs : List Rat := [-5, 0, 0.5, 3, 12.5, 50, 99.9, 100, 120]

/-- A session of `n` ticks from a seed: start from the base layout and run the tick; when it says `add`, add an
extra (JS 4590-4646 with visible, not dragging, wide, no reduced motion, card below the fold, the copy rect given).
$$\mathrm{session}(W_s, H_s, \mathit{seed}, c_t, c_h, s_t, n)$$ -/
def session (stageW stageH : Rat) (seed : UInt32) (copyTop copyH stageTop : Rat) (n : Nat) : List Note :=
  let avoid := [avoidBox copyTop copyH stageTop stageH]
  let base := baseLayout false stageW stageH
  let step := fun (acc : List Note × Nat × UInt32) (_ : Nat) =>
    let (extras, j, s) := acc
    match tick true false extras.length false false none 900 stageW stageH with
    | .add =>
      let (r, s') := (addExtra stageW stageH base extras avoid j).run s
      match r with
      | some note => (extras ++ [note], j + 1, s')
      | none => (extras, j, s')
    | _ => acc
  base ++ ((List.range n).foldl step ([], 0, seed)).1

/-- The golden lines. $$\text{lines}$$ Vectors the TS logic must reproduce. -/
def lines (_ : Unit := ()) : List String :=
  (xs.flatMap fun x => [(0, 100), (10, 90), (0, -3)].map fun (lo, hi) =>
    line "clampTo" [("x", rin x), ("lo", rin lo), ("hi", rin hi)] (ratWire (clampTo x lo hi))) ++
  (([(⟨0, 0, 10, 10⟩, ⟨5, 5, 10, 10⟩, 0), (⟨0, 0, 10, 10⟩, ⟨10, 0, 10, 10⟩, 0), (⟨0, 0, 10, 10⟩, ⟨10, 0, 10, 10⟩, 0.5),
    (⟨0, 0, 10, 10⟩, ⟨10.2, 0, 10, 10⟩, 1), (⟨0, 0, 10, 10⟩, ⟨0, 11.2, 10, 10⟩, 1.2), (⟨20, 20, 5, 5⟩, ⟨0, 0, 10, 10⟩, 0),
    (⟨0, 0, 100, 30⟩, ⟨40, 29.9, 10, 10⟩, 0), (⟨0, 0, 100, 30⟩, ⟨40, 30, 10, 10⟩, 0)] : List (Box × Box × Rat)).map fun (a, b, g) =>
    line "overlaps" [("a", boxIn a), ("b", boxIn b), ("gap", rin g)] (.bool (overlaps a b g))) ++
  (([(100, 100, 0, 500), (0, 100, 0, 500), (400, 80, 50, 528), (20, 100, 30, 528), (-100, 50, 0, 400)] : List (Rat × Rat × Rat × Rat)).map fun (a, b, c, d) =>
    line "avoidBox" [("copyTop", rin a), ("copyH", rin b), ("stageTop", rin c), ("stageH", rin d)] (boxOut (avoidBox a b c d))) ++
  (([(1440, 100), (780, 337.5), (749, 0), (780, -120), (1000, 803)] : List (Rat × Rat)).map fun (w, l) =>
    line "baseLeft" [("stageW", rin w), ("leftPx", rin l)] (ratWire (baseLeft w l))) ++
  (([(868, 100), (528, 337.5), (507, 0), (528, 292.5), (700, -50)] : List (Rat × Rat)).map fun (h, t) =>
    line "baseTop" [("stageH", rin h), ("topPx", rin t)] (ratWire (baseTop h t))) ++
  (([(1440, 900), (1000, 800), (861.5, 700), (860, 700), (390, 800), (320, 640), (1920, 1080)] : List (Rat × Rat)).map fun (w, h) =>
    line "baseLayout" [("narrow", .bool (decide (w ≤ 860))), ("stageW", rin w), ("stageH", rin h)]
      (Json.arr ((baseLayout (decide (w ≤ 860)) w h).map noteOut).toArray)) ++
  (bs.flatMap fun vis => bs.flatMap fun drag => ([0, 11, 12, 13] : List Nat).flatMap fun (n : Nat) => bs.flatMap fun nar => bs.flatMap fun red =>
    [(none : Option Rat), some 800, some 895, some 900].map fun c =>
    line "tick" [("visible", .bool vis), ("dragging", .bool drag), ("extras", .num ⟨n, 0⟩), ("narrow", .bool nar),
        ("reduced", .bool red), ("cardTop", match c with | some x => rin x | none => .null), ("vh", rin 900),
        ("stageW", rin 780), ("stageH", rin 528)]
      (.str (tickName (tick vis drag n nar red c 900 780 528)))) ++
  (([(780, 4), (780, 7.9), (7.9, 780), (0, 528), (780, 8)] : List (Rat × Rat)).map fun (w, h) =>
    line "tick" [("visible", .bool true), ("dragging", .bool false), ("extras", .num ⟨0, 0⟩), ("narrow", .bool false),
        ("reduced", .bool false), ("cardTop", .null), ("vh", rin 900), ("stageW", rin w), ("stageH", rin h)]
      (.str (tickName (tick true false 0 false false none 900 w h)))) ++
  (bs.flatMap fun i => [0, 0.11, 0.12, 0.5, 1].map fun r =>
    line "visible" [("intersecting", .bool i), ("ratio", rin r)] (.bool (visible i r))) ++
  ([0, 1, 42, 4294967295, 3735928559, 2718281828].map fun (s : UInt32) =>
    line "mulberry" [("seed", seedJ s)]
      (Json.mkObj [("state", seedJ (mulberry s).1), ("value", ratWire (mulberry s).2)])) ++
  (([(0, 1), (0.5, 7), (0.999, 7), (0.999, 12), (0.14, 7), (0.143, 7), (0, 12)] : List (Rat × Nat)).map fun (r, n) =>
    line "idx" [("r", rin r), ("n", .num ⟨n, 0⟩)] (.num ⟨idx r n, 0⟩)) ++
  (([([0.9, 0.1, 0.5, 0.3], [1, 2, 3, 4]), ([0, 0, 0], [5, 6, 7]), ([0.99, 0.99, 0.99], [5, 6, 7]),
    ([0.5, 0.5, 0.5, 0.5, 0.5], [10, 20, 30, 40, 50]), ([], [1, 2]), ([0.2], [])] : List (List Rat × List Nat)).map fun (rs, xs) =>
    line "permute" [("draws", Json.arr (rs.map rin).toArray), ("xs", Json.arr (xs.map fun (x : Nat) => (Json.num ⟨x, 0⟩)).toArray)]
      (Json.arr ((permute rs xs).map fun (x : Nat) => (Json.num ⟨x, 0⟩)).toArray)) ++
  (([(5, 0, 6), (5, 0.5, 6), (5, 0.9, 10), (-1, 0.5, 20), (50, 0.2, 80), (96, 0.9, 5)] : List (Rat × Rat × Rat)).map fun (c, r, s) =>
    line "jit" [("c", rin c), ("r", rin r), ("s", rin s)] (ratWire (jit c r s))) ++
  ([[], [12, 13, 14, 15, 16], [15, 21, 16, 12, 17, 13, 22, 14, 18, 20, 19], textPool].flatMap fun used =>
    [0, 0.2, 0.5, 0.99].map fun r =>
    line "pickText" [("used", Json.arr (used.map fun (x : Nat) => (Json.num ⟨x, 0⟩)).toArray), ("r", rin r)]
      (.num ⟨pickText used r, 0⟩)) ++
  (([(0, 900, 900), (4085, 4985, 900), (1801, 2701, 900), (1800, 2700, 900), (-1800, -901, 900), (-1801, -901, 900), (-1800, -900, 900)] : List (Rat × Rat × Rat)).map
    fun (t, b, h) => line "sceneActive" [("top", rin t), ("bottom", rin b), ("h", rin h)] (.bool (sceneActive t b h))) ++
  (bs.map fun a => line "renderObserves" [("active", .bool a)] (.bool (Render.after a).observes)) ++
  ((List.range 20).map fun (j : Nat) => line "rotation" [("j", .num ⟨j, 0⟩)] (.num ⟨rotation j, 0⟩)) ++
  (bs.flatMap fun c => ([0, 1] : List Nat).flatMap fun (b : Nat) => bs.map fun m =>
    line "dragAllowed" [("c860", .bool c), ("button", .num ⟨b, 0⟩), ("mouse", .bool m)] (.bool (dragAllowed c b m))) ++
  (([(10, 100, 150, 780, 30.7), (10, 100, 50, 780, 30.7), (60, 100, 400, 780, 30.7), (0, 0, 0, 780, 45.4), (10, 100, 150, 780, 120)] : List (Rat × Rat × Rat × Rat × Rat)).map
    fun (o, s, c, k, w) =>
    line "dragPos" [("origin", rin o), ("start", rin s), ("cur", rin c), ("container", rin k), ("sizePct", rin w)]
      (ratWire (dragPos o s c k w))) ++
  (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Enter", "a"].map fun k =>
    line "keyDelta" [("key", .str k)] (match keyDelta k with
      | some (a, b) => Json.arr #[ratWire a, ratWire b]
      | none => .null)) ++
  (([(10, -1.5, 30.7), (0, -1.5, 30.7), (69.3, 1.5, 30.7), (69, 1.5, 30.7), (50, 0, 30.7)] : List (Rat × Rat × Rat)).map fun (p, d, w) =>
    line "keyPos" [("pos", rin p), ("delta", rin d), ("sizePct", rin w)] (ratWire (keyPos p d w))) ++
  [line "stickTiming" []
    (Json.mkObj [("durationMs", ratWire stickMs), ("scaleFrom", ratWire stickScale0), ("x1", ratWire (33 / 100)),
      ("y1", ratWire 1), ("x2", ratWire (68 / 100)), ("y2", ratWire 1), ("opacityFrom", ratWire 0)])] ++
  (([(1440, 900, 1, 100, 100, 0, 3), (1440, 900, 7, 100, 100, 0, 14), (1100, 800, 42, 100, 100, 0, 14),
    (1099, 800, 5, 100, 100, 0, 14), (900, 800, 4294967295, 20, 100, 0, 6), (1440, 900, 99, 100, 100, 0, 0)] : List (Rat × Rat × UInt32 × Rat × Rat × Rat × Nat)).map fun (w, h, seed, ct, ch, st, n) =>
    line "session" [("stageW", rin w), ("stageH", rin h), ("seed", seedJ seed), ("copyTop", rin ct), ("copyH", rin ch),
        ("stageTop", rin st), ("ticks", .num ⟨n, 0⟩)]
      (Json.arr ((session w h seed ct ch st n).map noteOut).toArray))

#guard lines.length > 0

end Fw.Parts.PainNotesGolden
