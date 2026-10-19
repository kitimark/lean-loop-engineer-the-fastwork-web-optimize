import Lean.Data.Json
import Fw.Port.Svg
import Fw.Port.Attrs

/-! Write (or with `--check`, verify) the port completeness goldens in `packages/contracts/golden/port/`:
`sections.json` (the section table and owner cases, Fw.Port.Sections), `exclusions.json` (the four exclusion lists),
`assets.jsonl` (Fw.Site.Assets cases) and `svg.jsonl` (Fw.Port.Svg skeleton and match cases; synthetic path data
only). Consumers: `scripts/port/digest.mjs` and `apps/site/test/port-*.test.mjs`. Run from `lean/`:
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
  [[], [[], []], [[], ["hero.accent", "hero"], ["hero"]], [["nav", "nav.hitTest"]], [[], [], ["pain"]]]

/-- `sections.json`. -/
def sectionsJ : Json :=
  Json.mkObj [("page", .str page),
    ("table", .arr (table.map fun r => Json.mkObj [("part", .str r.part), ("orig", .str r.orig),
      ("rewrite", .str r.rewrite), ("pageLevel", .bool r.pageLevel)]).toArray),
    ("owner", .arr (ownerCases.map fun A => Json.mkObj [("ancestors", .arr (A.map strs).toArray),
      ("owner", .str (owner A))]).toArray)]

/-- `exclusions.json`: every check's list, in check order. -/
def exclusionsJ : Json :=
  exclsJ (Fw.Port.Text.exclusions ++ Fw.Port.Attrs.exclusions ++ Fw.Site.Assets.exclusions ++ Fw.Port.Svg.exclusions)

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

/-- `assets.jsonl`. -/
def assetsText : String :=
  String.join ((fnCases ++ verdictCases.map fun (R, O) =>
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

/-- The golden files and their text. -/
def outputs : List (String × String) := [
  ("sections.json", sectionsJ.pretty ++ "\n"),
  ("exclusions.json", exclusionsJ.pretty ++ "\n"),
  ("assets.jsonl", assetsText),
  ("svg.jsonl", svgText)]

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
