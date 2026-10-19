import Lean.Data.Json
import Fw.Port.Svg
import Fw.Port.Attrs
import Fw.Port.Fonts

/-! Write (or with `--check`, verify) the port completeness goldens in `packages/contracts/golden/port/`:
`sections.json` (the section table and owner cases, Fw.Port.Sections), `exclusions.json` (the four exclusion lists),
`assets.jsonl` (Fw.Site.Assets cases), `svg.jsonl` (Fw.Port.Svg skeleton and match cases; synthetic path data
only) and `fonts.jsonl` (Fw.Port.Fonts cases). Consumers: `scripts/port/digest.mjs` and `apps/site/test/port-*.test.mjs`. Run from `lean/`:
`lake env lean --run scripts/PortGolden.lean [--check]`. -/

open Lean Fw.Port.Sections

/-- A list of strings as JSON. -/
def strs (l : List String) : Json := .arr (l.map Json.str).toArray

/-- An exclusion as JSON. -/
def exclJ (e : Excl) : Json :=
  Json.mkObj [("check", .str e.check.name), ("sec", .str e.sec), ("key", .str e.key), ("reason", .str e.reason)]

/-- A list of exclusions as JSON. -/
def exclsJ (E : List Excl) : Json := .arr (E.map exclJ).toArray

/-- The owner cases, ancestors innermost first. -/
def ownerCases : List (List (List String)) :=
  [[], [[], []], [[], ["hero.accent", "hero"], ["hero"]], [["nav", "hero"]], [[], [], ["pain"]]]

/-- `sections.json`. -/
def sectionsJ : Json :=
  Json.mkObj [("page", .str page),
    ("table", .arr (table.map fun r => Json.mkObj [("part", .str r.part), ("orig", .str r.orig),
      ("rewrite", .str r.rewrite), ("pageLevel", .bool r.pageLevel)]).toArray),
    ("dropped", .arr (dropped.map fun (i, r) => Json.mkObj [("part", .str i), ("reason", .str r)]).toArray),
    ("unrooted", strs unrooted),
    ("owner", .arr (ownerCases.map fun A => Json.mkObj [("ancestors", .arr (A.map strs).toArray),
      ("owner", .str (owner A))]).toArray)]

/-- `exclusions.json`: every check's list, in check order, and the crawl skips of check 3. -/
def exclusionsJ : Json :=
  Json.mkObj [
    ("entries", exclsJ (Fw.Port.Text.exclusions ++ Fw.Port.Attrs.exclusions ++ Fw.Site.Assets.exclusions ++
      Fw.Port.Svg.exclusions ++ Fw.Port.Fonts.exclusions)),
    ("crawlSkip", .arr (Fw.Site.Assets.crawlSkip.map fun (k, r) =>
      Json.mkObj [("prefix", .str k), ("reason", .str r)]).toArray)]

section Assets
open Fw.Site.Assets

/-- A manifest row as JSON. -/
def fileJ (f : File) : Json := Json.mkObj [("url", .str f.url), ("src", .str f.src)]

/-- The manifest of the asset cases. -/
def files : List File := [
  ⟨"/fonts/a.woff2", "snapshot/site/_app/immutable/assets/a.X1.woff2"⟩,
  ⟨"/selling/b.png", "snapshot/site/selling/b.png"⟩,
  ⟨"/selling/b2.png", "snapshot/site/selling/b.png"⟩,
  ⟨"/x/c.svg", "apps/site/c.svg"⟩]

/-- The exclusions of the asset cases. -/
def exclA : List Excl := [⟨.assets, "hero", "/selling/d.avif", "deferred"⟩, ⟨.svg, "hero", "/selling/e.png", "other check"⟩]

/-- Single-function cases. -/
def fnCases : List Json :=
  (["/a/b.SVG", "/a.b/c", "/a/b.png?v=1", "", "/fonts/x.woff2", "/site.webmanifest", "/a/.png", "/x.js"].map fun u =>
    Json.mkObj [("fn", .str "ext"), ("in", .str u), ("out", .str (ext u)), ("isAsset", .bool (isAsset u))]) ++
  (["snapshot/site/_app/immutable/assets/a.X1.woff2", "snapshot/site/", "snapshot/x.png", "apps/site/x.png"].map fun s =>
    Json.mkObj [("fn", .str "origUrl"), ("in", .str s), ("out", match origUrl s with | some u => .str u | none => .null)]) ++
  (["/_app/immutable/assets/a.X1.woff2", "/selling/b.png", "/selling/z.png", "/x/c.svg"].map fun u =>
    Json.mkObj [("fn", .str "rename"), ("files", .arr (files.map fileJ).toArray), ("in", .str u),
      ("out", .str (rename files u))])

/-- Verdict cases: served URLs, original URLs. -/
def verdictCases : List (List String × List String) := [
  (["/fonts/a.woff2", "/selling/b.png"], ["/_app/immutable/assets/a.X1.woff2", "/selling/b.png", "/selling/b.png"]),
  (["/selling/b.png"], ["/selling/d.avif", "/selling/e.png", "/selling/b2.png"]),
  ([], []),
  (["/selling/b2.png"], ["/selling/b.png"])]

/-- Texts for `inlineNorm`: tags, quotes, runs, non-ASCII white space, empty and blank input. -/
def normCases : List String :=
  ["  <svg a=\"1\">\n  <g/>\t</svg>\n", "<p>a  \n b</p> > <", "\u00A0<svg>\u2003\n<g/>\u3000x\u2028y</svg>\uFEFF",
    "> >  <", "", " \n ", "<svg>\u0085\u200B<g/></svg>", "<a b='c'\r\n>\u000B<b/>"]

/-- Rename-row cases: original assets with identities, rewrite assets (served name, identity), manifest rows, the
original URLs to decide. The first is an svg inlined as text, the second an svg inlined as base64 (the `<text` branch),
the third a hashed copy that wins over a later inlined one, the fourth no hit (manifest row, then missing). -/
def rowCases : List (List (String × List String) × List (String × String) × List File × List String) := [
  ([("snapshot/site/a.svg", ["bytes:1", "svgtext:2"])], [("/x/z.png", "bytes:7"), (inlineName "svgtext:2", "svgtext:2")],
    [], ["/a.svg"]),
  ([("snapshot/site/t.svg", ["bytes:3", "svgtext:4"])], [(inlineName "bytes:3", "bytes:3")], [], ["/t.svg"]),
  ([("snapshot/site/c.png", ["bytes:5"]), ("snapshot/site/d.png", ["bytes:6"])],
    [("/x/c.H.png", "bytes:5"), (inlineName "bytes:5", "bytes:5")], [⟨"/m/c.png", "snapshot/site/c.png"⟩],
    ["/c.png", "/d.png"]),
  ([("snapshot/site/e.png", ["bytes:8"])], [("/x/f.png", "bytes:9")], [⟨"/m/e.png", "snapshot/site/e.png"⟩],
    ["/e.png", "/g.png"])]

/-- `assets.jsonl`. -/
def assetsText : String :=
  String.join ((fnCases ++
    normCases.map (fun t => Json.mkObj [("fn", .str "inlineNorm"), ("in", .str t), ("out", .str (inlineNorm t))]) ++
    rowCases.map (fun (O, W, M, U) =>
      let F := renameRows O W M
      let R := W.map (fun (w : String × String) => w.1)
      Json.mkObj [("fn", .str "renameRows"),
        ("orig", .arr (O.map fun (s, I) => Json.mkObj [("src", .str s), ("ids", strs I)]).toArray),
        ("rewrite", .arr (W.map fun (n, i) => Json.mkObj [("name", .str n), ("id", .str i)]).toArray),
        ("files", .arr (M.map fileJ).toArray), ("rows", .arr (F.map fileJ).toArray), ("urls", strs U),
        ("verdicts", strs (U.map fun u => (verdict F R [] u).name))]) ++
    verdictCases.map fun (R, O) =>
    Json.mkObj [("fn", .str "verdict"), ("files", .arr (files.map fileJ).toArray), ("served", strs R),
      ("excl", exclsJ exclA), ("orig", strs O),
      ("verdicts", strs (O.map fun u => (verdict files R exclA u).name)),
      ("missing", strs (missing files R exclA O)), ("pass", .bool (pass files R exclA O))]).map (fun j : Json => j.compress ++ "\n"))

end Assets

section Svg
open Fw.Port.Svg

/-- A skeleton as JSON; its compressed form (keys sorted) is the text the site hashes. -/
def skelJ (s : Skel) : Json :=
  Json.mkObj [("viewBox", .str s.viewBox), ("counts", .arr (s.counts.map toJson).toArray),
    ("paths", .arr (s.paths.map fun (n, l) => Json.arr #[toJson n, .str l]).toArray)]

/-- Synthetic svgs (no path data of the site). -/
def svgCases : List Svg := [
  ⟨"0 0 24 24", []⟩,
  ⟨"  0 0\n 24  24 ", [⟨"path", "M0 0h1v1z"⟩]⟩,
  ⟨"", [⟨"g", ""⟩, ⟨"path", "M0 0L1e-5 2c1 2 3 4 5 6z"⟩, ⟨"circle", ""⟩, ⟨"path", ""⟩, ⟨"lineargradient", ""⟩,
    ⟨"stop", ""⟩, ⟨"foreignobject", ""⟩, ⟨"title", ""⟩]⟩,
  ⟨"0 0 1 1", [⟨"path", "M0 0él1 1"⟩, ⟨"clippath", ""⟩, ⟨"use", ""⟩, ⟨"rect", ""⟩]⟩]

/-- Match cases: exclusions, original keys, rewrite keys. -/
def matchCases : List (List Excl × List String × List String) := [
  ([], ["a", "a", "b"], ["a", "c"]),
  ([⟨.svg, "nav", "b", "r"⟩], ["a", "b"], ["a"]),
  ([⟨.svg, "nav", "c", "r"⟩, ⟨.assets, "nav", "a", "r"⟩], ["a", "a"], ["c", "a"]),
  ([], [], []),
  ([], ["a", "b"], ["b", "a"])]

/-- `svg.jsonl`. -/
def svgText : String :=
  String.join ((svgCases.map (fun (s : Svg) => Json.mkObj [("fn", .str "skel"),
      ("in", Json.mkObj [("viewBox", .str s.viewBox),
        ("kids", .arr (s.kids.map fun (k : Kid) => Json.mkObj [("tag", .str k.tag), ("d", .str k.d)]).toArray)]),
      ("out", skelJ (skel s)), ("canon", .str (skelJ (skel s)).compress)]) ++
    matchCases.map fun (E, o, r) => Json.mkObj [("fn", .str "check"), ("excl", exclsJ E), ("orig", strs o),
      ("rewrite", strs r), ("missing", strs (check E o r).missing), ("extra", strs (check E o r).extra),
      ("pass", .bool (pass E o r))]).map (fun j : Json => j.compress ++ "\n"))

end Svg

section Fonts
open Fw.Port.Fonts

/-- A leaf as JSON. -/
def leafJ (l : Leaf) : Json :=
  Json.mkObj [("sec", .str l.sec), ("text", .str l.text), ("family", .str l.family), ("weight", .str l.weight),
    ("style", .str l.style)]

/-- A face as JSON. -/
def faceJ (f : Face) : Json :=
  Json.mkObj [("family", .str f.family), ("weight", .str f.weight), ("style", .str f.style), ("status", .str f.status)]

/-- A face triple as JSON. -/
def tripleJ (t : String × String × String) : Json := strs [t.1, t.2.1, t.2.2]

/-- An arm as JSON. -/
def armJ (a : Arm) : Json :=
  Json.mkObj [("leaves", .arr (a.leaves.map leafJ).toArray), ("faces", .arr (a.faces.map faceJ).toArray)]

/-- The original arm of the cases: body text, a script heading, a countdown and a sticky note. -/
def fOrig : Arm :=
  ⟨[⟨"page", "Hello  world", "Google Sans", "400", "normal"⟩, ⟨"pain.notes", " Note\n", "Playpen Sans Start Selling", "500", "normal"⟩,
    ⟨"hero.countdown", "01", "Google Sans", "700", "normal"⟩, ⟨"hero.accent", "soon", "Google Sans", "400", "italic"⟩,
    ⟨"page", "  ", "Times", "400", "normal"⟩],
   [⟨"Google Sans", "400 700", "normal", "loaded"⟩, ⟨"Google Sans", "400 700", "italic", "loaded"⟩,
    ⟨"Playpen Sans Start Selling", "400 600", "normal", "loaded"⟩, ⟨"Google Sans", "400 700", "normal", "unloaded"⟩,
    ⟨"Fastwork", "700", "normal", "unloaded"⟩]⟩

/-- The rewrite arms of the cases: each is the original with one change. -/
def fCases : List (String × Arm) := [
  ("same", fOrig),
  ("countdown text and white space differ", ⟨[⟨"page", "Hello world", "Google Sans", "400", "normal"⟩,
    ⟨"pain.notes", "Note", "Playpen Sans Start Selling", "500", "normal"⟩, ⟨"hero.countdown", "02", "Google Sans", "700", "normal"⟩,
    ⟨"hero.accent", "soon", "Google Sans", "400", "italic"⟩], fOrig.faces⟩),
  ("pain.notes falls back to Google Sans", ⟨[⟨"page", "Hello world", "Google Sans", "400", "normal"⟩,
    ⟨"pain.notes", "Note", "Google Sans", "500", "normal"⟩, ⟨"hero.countdown", "01", "Google Sans", "700", "normal"⟩,
    ⟨"hero.accent", "soon", "Google Sans", "400", "italic"⟩], fOrig.faces⟩),
  ("countdown weight differs", ⟨[⟨"page", "Hello world", "Google Sans", "400", "normal"⟩,
    ⟨"pain.notes", "Note", "Playpen Sans Start Selling", "500", "normal"⟩, ⟨"hero.countdown", "01", "Google Sans", "400", "normal"⟩,
    ⟨"hero.accent", "soon", "Google Sans", "400", "italic"⟩], fOrig.faces⟩),
  ("accent style differs", ⟨[⟨"page", "Hello world", "Google Sans", "400", "normal"⟩,
    ⟨"pain.notes", "Note", "Playpen Sans Start Selling", "500", "normal"⟩, ⟨"hero.countdown", "01", "Google Sans", "700", "normal"⟩,
    ⟨"hero.accent", "soon", "Google Sans", "400", "normal"⟩], fOrig.faces⟩),
  ("a leaf appears twice", ⟨[⟨"page", "Hello world", "Google Sans", "400", "normal"⟩,
    ⟨"pain.notes", "Note", "Playpen Sans Start Selling", "500", "normal"⟩, ⟨"hero.countdown", "01", "Google Sans", "700", "normal"⟩,
    ⟨"hero.accent", "soon", "Google Sans", "400", "italic"⟩, ⟨"page", "Hello world", "Google Sans", "400", "normal"⟩],
    fOrig.faces⟩),
  ("the italic face is not loaded", ⟨fOrig.leaves, fOrig.faces.drop 1⟩),
  ("an extra face is loaded", ⟨fOrig.leaves, fOrig.faces ++ [⟨"Roboto", "400", "normal", "loaded"⟩]⟩),
  ("the excluded family loads", ⟨fOrig.leaves, fOrig.faces ++ [⟨"Fastwork", "700", "normal", "loaded"⟩]⟩),
  ("a face that is only declared", ⟨fOrig.leaves, fOrig.faces ++ [⟨"Roboto", "400", "normal", "unloaded"⟩, ⟨"Roboto", "400", "normal", "error"⟩]⟩)]

/-- The leaves of the pairing cases: a button, the `o` of the heading, a deck item and an item that occurs twice. -/
def lBtn : Leaf := ⟨"hero", "Join waitlist", "Google Sans", "500", "normal"⟩
def lO : Leaf := ⟨"people.o", "o", "Google Sans", "500", "normal"⟩
def lDeck : Leaf := ⟨"people.deck", "Sound Composer", "Google Sans", "500", "normal"⟩
def lItem : Leaf := ⟨"page", "Item", "Google Sans", "400", "normal"⟩

/-- The original arm of the pairing cases. -/
def fOrig2 : Arm := ⟨[lBtn, lO, lDeck, lItem, lItem], fOrig.faces⟩

/-- The pairing cases, each with its own original arm. -/
def pCases : List (String × Arm × Arm) := [
  ("a button draws Arial", fOrig2, ⟨[{ lBtn with family := "Arial" }, lO, lDeck, lItem, lItem], fOrig.faces⟩),
  ("the o is owned by people.card", fOrig2, ⟨[lBtn, { lO with sec := "people.card" }, lDeck, lItem, lItem], fOrig.faces⟩),
  ("a text differs", fOrig2, ⟨[{ lBtn with text := "Join the waitlist" }, lO, lDeck, lItem, lItem], fOrig.faces⟩),
  ("a change, a move, a lost and an added leaf", fOrig2, ⟨[{ lBtn with family := "Arial" }, { lO with sec := "people.card" },
    lItem, { lItem with text := "Other" }], fOrig.faces⟩),
  ("one of two equal leaves changes", fOrig2, ⟨[lBtn, lO, lDeck, lItem, { lItem with family := "system-ui" }], fOrig.faces⟩),
  ("a leaf changes font and moves", fOrig2, ⟨[lBtn, lO, { lDeck with sec := "people.card", family := "Arial" }, lItem, lItem], fOrig.faces⟩)]

/-- The case lines of the golden file: the arms, the units, the check and its split. -/
def fontsLine (n : String) (O R : Arm) : String :=
  let v := check excl O R
  let sp : Split := split excl O R
  let pairJ := fun (x : Leaf × Leaf) => Json.arr #[leafJ x.1, leafJ x.2]
  (Json.mkObj [("name", .str n), ("excl", exclsJ excl), ("orig", armJ O), ("rewrite", armJ R),
    ("units", .arr ((units excl R.leaves).map leafJ).toArray), ("loaded", .arr ((loaded excl R.faces).map tripleJ).toArray),
    ("missing", .arr (v.missing.map leafJ).toArray), ("extra", .arr (v.extra.map leafJ).toArray),
    ("missingFaces", .arr (v.missingFaces.map tripleJ).toArray), ("extraFaces", .arr (v.extraFaces.map tripleJ).toArray),
    ("changes", .arr (sp.changes.map pairJ).toArray), ("moves", .arr (sp.moves.map pairJ).toArray),
    ("lost", .arr (sp.lost.map leafJ).toArray), ("added", .arr (sp.added.map leafJ).toArray),
    ("pass", .bool (pass excl O R))]).compress ++ "\n"

/-- `fonts.jsonl`: one line per case. -/
def fontsText : String :=
  String.join (fCases.map fun (n, R) => fontsLine n fOrig R) ++ String.join (pCases.map fun (n, O, R) => fontsLine n O R)

end Fonts

/-- The golden files and their text. -/
def outputs : List (String × String) := [
  ("sections.json", sectionsJ.pretty ++ "\n"),
  ("exclusions.json", exclusionsJ.pretty ++ "\n"),
  ("assets.jsonl", assetsText),
  ("svg.jsonl", svgText),
  ("fonts.jsonl", fontsText)]

/-- Write the golden files, or with `--check` exit 1 when one differs from the Lean output. -/
def main (args : List String) : IO UInt32 := do
  let dir : System.FilePath := ".." / "packages" / "contracts" / "golden" / "port"
  if args.contains "--check" then
    let mut bad := 0
    for (n, t) in outputs do
      let cur ← try IO.FS.readFile (dir / n) catch _ => pure ""
      if cur != t then
        IO.println s!"port golden: {dir / n} is stale (regenerate: cd lean && lake env lean --run scripts/PortGolden.lean)"
        bad := bad + 1
    if bad == 0 then IO.println s!"port golden: {outputs.length} files up to date"
    return (if bad == 0 then 0 else 1)
  IO.FS.createDirAll dir
  for (n, t) in outputs do IO.FS.writeFile (dir / n) t
  IO.println s!"port golden: {outputs.length} files written"
  return 0
