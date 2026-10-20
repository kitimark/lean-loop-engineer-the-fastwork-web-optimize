import Lean.Data.Json
import Fw.Parts.PeopleCard
import Fw.Parts.PeopleO
import Fw.Parts.PeopleDeck
import Fw.Parts.PeopleCarousel
import Fw.Parts.PeopleDeckPanels
/-!
# Golden vectors for the People parts

`PeopleGolden.files` is the list of `(file name, lines)` for `people.card`, `people.o`, `people.deck` and
`people.carousel` (same line format and encodings as `Fw/Parts/Golden.lean`: `Rat` inputs as exact JSON decimals, `Rat`
outputs in the wire form `{"num","den"}`, integers as JSON integers). `Golden.lean` appends it to its own table.
-/
namespace Fw.Parts.PeopleGolden
open Lean

/-- Exact decimal JSON for a rational whose reduced denominator divides `10^12`, else the wire form. -/
def rin (q : Rat) : Json :=
  match (List.range 13).find? (fun e => (10 ^ e : Nat) % q.den == 0) with
  | some e => .num ⟨q.num * ((10 ^ e : Nat) / q.den : Nat), e⟩
  | none => Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- The `Rat` output wire form. -/
def ratWire (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- A natural number as JSON. -/
def jnat (n : Nat) : Json := .num ⟨(n : Int), 0⟩

/-- An integer as JSON. -/
def jint (z : Int) : Json := .num ⟨z, 0⟩

/-- One golden line. -/
def line (fn : String) (inp : List (String × Json)) (out : Json) : String :=
  (Json.mkObj [("fn", .str fn), ("in", Json.mkObj inp), ("out", out)]).compress

/-! ## people.card -/

section Card
open Fw.Parts.PeopleCard

/-- people.card lines. Conformance vectors for the card's reveal, shrink and lerp. -/
def cardLines (_ : Unit := ()) : List String :=
  let xs : List Rat := [-1, 0, 0.1, 0.25, 0.5, 0.75, 0.9, 1, 1.5]
  let vhs : List Rat := [0, 600, 900]
  (xs.map fun x => line "clamp01" [("x", rin x)] (ratWire (clamp01 x))) ++
  (xs.map fun x => line "smooth" [("x", rin x)] (ratWire (smooth x))) ++
  (vhs.flatMap fun vh => ([-100, 0, 100, 0.3 * vh, 0.35 * vh, 0.5 * vh, 0.6 * vh, 0.85 * vh, vh, 2 * vh] : List Rat).map fun z =>
    line "coverage" [("bottom", rin z), ("vh", rin vh)] (ratWire (coverage z vh))) ++
  ([false, true].flatMap fun rm => ([0, 0.2, 0.49, 0.5, 0.51, 1] : List Rat).map fun t =>
    line "target" [("reduced", .bool rm), ("t", rin t)] (ratWire (target rm t))) ++
  ([false, true].flatMap fun rm => ([(0, 1), (0.22, 1), (0.9, 1), (0.9992, 1), (1, 1), (1, 0), (0.5, 0), (0.0007, 0), (0.2, 0.2)] : List (Rat × Rat)).map fun (o, n) =>
    line "lerp" [("reduced", .bool rm), ("o", rin o), ("n", rin n)] (ratWire (lerp rm o n))) ++
  (([(1, 0), (1, 0.9991), (1, 0.9992), (0, 1), (0.5, 0.5)] : List (Rat × Rat)).map fun (n, o) =>
    line "pending" [("n", rin n), ("o", rin o)] (.bool (pending n o))) ++
  (([0, 0.04, 0.0401, 0.5, 1] : List Rat).map fun t => line "shrinking" [("t", rin t)] (.bool (shrinking t))) ++
  ([false, true].flatMap fun rm => ([(0, 1800, 900), (-647, 1800, 900), (-648, 1800, 900), (-900, 1800, 900), (0, 500, 900), (-1, 500, 900), (-20, 1000, 900)] : List (Rat × Rat × Rat)).map fun (top, h, vh) =>
    line "revealed" [("reduced", .bool rm), ("top", rin top), ("height", rin h), ("vh", rin vh)] (.bool (revealed rm top h vh))) ++
  (([0, 0.5, 1] : List Rat).map fun s => line "scale" [("s", rin s)] (ratWire (scale s))) ++
  ([false, true].flatMap fun nw => ([-5, 0, 0.5, 0.51, 700] : List Rat).map fun t =>
    line "painDark" [("narrow", .bool nw), ("headerTop", rin t)] (.bool (painDark nw t)))

end Card

/-! ## people.o -/

section O
open Fw.Parts.PeopleO

/-- people.o lines. Conformance vectors for the opening timeline and the preview position. -/
def oLines : List String :=
  ([false, true].flatMap fun rm => [false, true].flatMap fun sa =>
    ([0, 1, 119, 120, 121, 1299, 1300, 1301, 1419, 1420, 5000] : List Nat).map fun t =>
      let (s, e) := phase rm sa t
      line "phase" [("reduced", .bool rm), ("standalone", .bool sa), ("t", jnat t)]
        (Json.mkObj [("stack", .bool s), ("expanded", .bool e)])) ++
  (([320, 360, 375, 390, 861, 1280, 1920, 20] : List Rat).map fun vw =>
    line "cardWidth" [("vw", rin vw)] (ratWire (cardWidth vw))) ++
  (([(1280, 100, 56), (1280, 0, 56), (1280, 1270, 56), (375, 20, 40), (1000, 500.5, 56.25)] : List (Rat × Rat × Rat)).map fun (vw, x, s) =>
    line "cardLeft" [("vw", rin vw), ("x", rin x), ("s", rin s)] (ratWire (cardLeft vw x s))) ++
  (([(900, 50, 90), (900, 600, 640), (900, 448, 448.25), (700, 300, 340), (900, 0, 0)] : List (Rat × Rat × Rat)).map fun (vh, y, z) =>
    line "cardTop" [("vh", rin vh), ("y", rin y), ("z", rin z)] (ratWire (cardTop vh y z))) ++
  (([0, 1, 2, 5] : List Nat).map fun i => line "faceDelay" [("i", jnat i)] (jnat (faceDelay i)))

end O

/-! ## people.carousel -/

section Carousel
open Fw.Parts.PeopleCarousel

/-- A loop state as JSON. -/
def stJson (s : State) : Json := Json.mkObj [("x", jnat s.x), ("swapping", .bool s.swapping)]

/-- people.carousel lines. Conformance vectors for the avatar ring and the loop. -/
def carouselLines : List String :=
  (([0, 1, 2, 3, 4, 5, 6, 7, 11] : List Nat).flatMap fun x =>
    [line "restWindow" [("x", jnat x)] (.arr ((restWindow x).map jnat).toArray),
     line "swapWindow" [("x", jnat x)] (.arr ((swapWindow x).map jnat).toArray)]) ++
  (([0, 1, 2, 3, 4, 5] : List Nat).flatMap fun x => [false, true].flatMap fun w => [false, true].flatMap fun a =>
    [line "afterRest" [("x", jnat x), ("swapping", .bool w), ("active", .bool a)] (stJson (afterRest ⟨x, w⟩ a)),
     line "afterSwap" [("x", jnat x), ("swapping", .bool w), ("active", .bool a)] (stJson (afterSwap ⟨x, w⟩ a))]) ++
  (([0, 1, 799, 800, 801, 1019, 1020, 1021, 1819, 1820, 6119, 6120, 6121, 7140] : List Nat).map fun t =>
    line "stateAt" [("t", jnat t)] (stJson (stateAt t))) ++
  (([1, 2, 3, 4, 5] : List Nat).map fun k => line "rowPx" [("k", jnat k)] (jnat (rowPx k)))

end Carousel

/-! ## people.deck -/

section Deck
open Fw.Parts.PeopleDeck

/-- people.deck lines. Conformance vectors for the ease, ranges, targets, lerp steps and picks. -/
def deckLines (_ : Unit := ()) : List String :=
  let xs : List Rat := [-1, 0, 0.1, 0.25, 0.4999, 0.5, 0.6, 0.75, 0.9, 1, 1.5]
  (xs.map fun x => line "ae" [("x", rin x)] (ratWire (ae x))) ++
  (([600, 720, 900, 1080] : List Rat).flatMap fun vh => ([1, 2, 6] : List Nat).map fun n =>
    let (s, p, t) := ranges vh n
    line "ranges" [("vh", rin vh), ("n", jnat n)] (Json.mkObj [("shrink", ratWire s), ("prof", ratWire p), ("total", ratWire t)])) ++
  (([(-100, 3000), (48, 3000), (0, 3000), (-1000, 3000), (-5000, 3000), (-2500.5, 3000)] : List (Rat × Rat)).map fun (top, tot) =>
    line "progress" [("top", rin top), ("total", rin tot)] (ratWire (progress top tot))) ++
  (([(1280, 1328), (1280, 1000), (861, 800), (1920, 1328), (400, 200), (1280, 249)] : List (Rat × Rat)).map fun (vw, dw) =>
    line "fit" [("vw", rin vw), ("deckW", rin dw)] (ratWire (fit vw dw))) ++
  (([(248, 1105, 1, 50), (248, 1105, 1.22, 50), (248, 1105, 0.9, 100), (0, 800, 1.1, 25)] : List (Rat × Rat × Rat × Rat)).map fun (l, w, s, o) =>
    line "de" [("left", rin l), ("width", rin w), ("s", rin s), ("o", rin o)] (ratWire (de l w s o))) ++
  (([(1328, 248, 1105, 1.1, 50), (1328, 248, 1105, 1, 100)] : List (Rat × Rat × Rat × Rat × Rat)).map fun (dw, l, w, s, o) =>
    line "fe" [("deckW", rin dw), ("left", rin l), ("width", rin w), ("s", rin s), ("o", rin o)] (ratWire (fe dw l w s o))) ++
  (([0, 100, 1000, 1305, 1305.5, 1306, 2000, 3150] : List Rat).map fun y =>
    let t := tgt y 1305 1530 1.1 (-300)
    line "tgt" [("y", rin y), ("shrink", rin 1305), ("prof", rin 1530), ("fit", rin 1.1), ("delta", rin (-300))]
      (Json.mkObj [("scale", ratWire t.scale), ("offset", ratWire t.offset), ("origin", ratWire t.origin), ("railIn", .bool t.railIn), ("k", ratWire t.k)])) ++
  (let t := tgt 3000 1305 0 1.1 (-300)
   [line "tgt" [("y", rin 3000), ("shrink", rin 1305), ("prof", rin 0), ("fit", rin 1.1), ("delta", rin (-300))]
      (Json.mkObj [("scale", ratWire t.scale), ("offset", ratWire t.offset), ("origin", ratWire t.origin), ("railIn", .bool t.railIn), ("k", ratWire t.k)])]) ++
  ([(snapScale, "scale"), (snapOffset, "offset"), (snapOrigin, "origin")].flatMap fun (sn, _) =>
    ([(0, 0), (1.22, 1), (1, 1), (0.9996, 1), (0, 100), (99.9, 100), (-300, 0), (-0.3, 0)] : List (Rat × Rat)).flatMap fun (v, t) =>
      [line "step" [("snap", rin sn), ("v", rin v), ("t", rin t)] (ratWire (step sn v t)),
       line "settled" [("snap", rin sn), ("v", rin v), ("t", rin t)] (.bool (settled sn v t))]) ++
  (([-1.5, -0.5, -0.4999, 0, 0.4999, 0.5, 1.5, 2.5, 3.2] : List Rat).map fun x => line "rnd" [("x", rin x)] (jint (rnd x))) ++
  (([1, 2, 6] : List Nat).flatMap fun c => ([0, 0.1, 0.16, 0.17, 0.2, 0.34, 0.5, 0.66, 0.8, 0.9, 1] : List Rat).flatMap fun k =>
    ([0, 1, 2, 5] : List Int).map fun q =>
      line "pe" [("cnt", jnat c), ("k", rin k), ("cur", jint q)] (jint (pe c k q))) ++
  (([(3000, 1305, 1530), (0, 1305, 1530), (100.5, 1305.25, 1530)] : List (Rat × Rat × Rat)).flatMap fun (y, s, p) =>
    ([(6, 0), (6, 3), (6, 5), (2, 1), (1, 0)] : List (Nat × Nat)).map fun (c, i) =>
      line "gotoTop" [("showcaseY", rin y), ("shrink", rin s), ("prof", rin p), ("cnt", jnat c), ("idx", jnat i)] (jint (gotoTop y s p c i))) ++
  (([(100, [0, 90, 210]), (150, [0, 100, 200]), (0, []), (500, [100, 300, 700]), (-5, [-10, 5])] : List (Rat × List Rat)).map fun (t, cs) =>
    line "nearest" [("target", rin t), ("centers", .arr (cs.map rin).toArray)] (jint (nearest t cs)))

end Deck

/-! ## people.deck panels -/

section Panels
open Fw.Parts.PeopleDeckPanels

/-- A list of strings as JSON. -/
def jstrs (l : List String) : Json := .arr (l.map Json.str).toArray

/-- people.deck.panels lines. Conformance vectors for the feed panel dispatch, review filters, faces,
verdicts, stars and about sections. -/
def panelsLines : List String :=
  (["posts", "services", "reviews", "about", "", "x", "Posts"].map fun s =>
    line "tabOf" [("id", .str s)] (.str (tabOf s).id)) ++
  (([[], [("a", 0)], [("a", 3), ("b", 0), ("c", 1)], [("a", 1), ("b", 2)]] : List (List (String × Nat))).map fun ss =>
    line "filterIds" [("services", .arr (ss.map (fun (i, c) => Json.mkObj [("id", .str i), ("reviewCount", jnat c)])).toArray)]
      (jstrs (filterIds (ss.map fun (i, c) => { id := i, reviewCount := c })))) ++
  ((["all", "a", "b", "zz"].flatMap fun f => ([[], ["a", "b", "a"], ["b", "b"]] : List (List String)).map fun rs =>
    line "shown" [("filter", .str f), ("reviews", jstrs rs)] (jstrs (shown f rs)))) ++
  (([[], ["u1"], ["u1", "u2", "u1"], ["u1", "u2", "u3", "u4"], ["u1", "u1", "u1"]] : List (List String)).flatMap fun l =>
    [line "faces" [("avatars", jstrs l)] (jstrs (faces l))] ++
    ([0, 2, 20, 47] : List Nat).map fun t => line "more" [("total", jnat t), ("avatars", jstrs l)] (jnat (more t l))) ++
  (([0, 2.4, 2.5, 3.4, 3.5, 3.9, 4, 4.4, 4.5, 4.8, 5] : List Rat).flatMap fun x =>
    [line "verdict" [("score", rin x)] (.str (verdict x).name)] ++
    (List.range 5).map fun i => line "filled" [("score", rin x), ("i", jnat i)] (.bool (filled x i))) ++
  ((["Fastwork.co", "BuddyBBB", "phil_wc · artist project", "UCLA Extension, USA", "  a  ", "", "Moonshot Digital Co.,Ltd. (Rabbit Digital Group)", "x"].map fun n =>
    line "initials" [("name", .str n)] (.str (initials n)))) ++
  ([false, true].map fun b => line "flip" [("b", .bool b)] (.bool (flip b))) ++
  (([(1, 1, 2, 0), (0, 0, 0, 0), (1, 0, 0, 3), (0, 2, 1, 0)] : List (Nat × Nat × Nat × Nat)).map fun (e, c, l, a) =>
    line "sections" [("education", jnat e), ("certificates", jnat c), ("languages", jnat l), ("awards", jnat a)]
      (jstrs (sections { education := e, certificates := c, languages := l, awards := a })))

end Panels

/-- The golden files. -/
def files (_ : Unit := ()) : List (String × List String) :=
  [("people.card.jsonl", cardLines), ("people.o.jsonl", oLines), ("people.deck.jsonl", deckLines),
   ("people.carousel.jsonl", carouselLines), ("people.deck.panels.jsonl", panelsLines)]

end Fw.Parts.PeopleGolden
