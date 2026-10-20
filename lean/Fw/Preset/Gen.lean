import Lean.Data.Json
import Fw.Preset.V2Proved
/-!
# `v2-proved` generator

Reads `research/findings/ledger.json` and `apps/site/src/parts/*/part.json`, decides the arm with
`Fw.Preset.generate`, and writes (or with `--check` compares) the preset and its decision rows. Run from `lean/`:
`printf 'import Fw.Preset.Gen\n#eval Fw.Preset.Gen.run ["--check"]\n' | lake env lean --stdin` (drop `--check` to write).
-/
namespace Fw.Preset.Gen
open Lean Fw.Preset
open Fw.Gate.Trajectory (Stored Engine Walk Family Group Outcome Unjudged UnitRow outcome groupsOf widthsOf)

/-- **The link table**: each flag and the ledger rows that carry its proof, in priority order (the first qualifying flag
of a part wins). A row is named by its (part, candidate) text; `k_n` below is the row of ledger entry `n` (for `n = 8`
and `25` the letter names which of the rows with that `n`). The mapping is read from the variants' code and the rows'
text (INFERRED); a flag absent here never enters the arm (`unlinked_not_mem`), and a curated flag is dropped from it
before the arm is decided (`links`).

Each flag points at the ledger rows that must all be proved for it to enter. -/
def linkTable : List (Flag × List Key) :=
  let k1 : Key := ("engine.scroll", "batched (all reads, then all returned writes, one pass per frame)")
  let k3 : Key := ("nav.hitTest", "hit-skip (skip the probe while morph > 0.2)")
  let k4 : Key := ("nav.hitTest", "elements-skip (elementsFromPoint with an allow-list, no pointer-events write)")
  let k7 : Key := ("hero.countdown (+ morph.countdown)",
    "strip (cd-strip, KD#12): 10 will-change faces per digit -> one 12-entry strip")
  let k8h : Key := ("hero.countdown / morph.countdown",
    "hidden-skip: skip face writes while the clock is not visible; the spring keeps integrating")
  let k9 : Key := ("morph.tween",
    "g0.0b: the rAF tween replaced by one WAAPI animation on a registered --morph with cubic-bezier(1/3,1,2/3,1)")
  let k12 : Key := ("morph.mount", "warm-up: mount the panel at a still moment near the end (v14, D1 always-built card)")
  let k13 : Key := ("morph.countdown",
    "strip (10 will-change faces per digit -> one 12-entry strip), reused from hero.countdown (KD#12, cd-strip)")
  let k25h : Key := ("engine.scene",
    "hidden pause of compositor marquees (morph.columns at m <= 0.08, scene off-screen), HiddenPause.lean")
  let k25m : Key := ("engine.scene",
    "morph.countdown hidden: keep the spring integrating, skip the 16 face writes per digit (HiddenPause skipWrites)")
  let k21 : Key := ("pain.notes",
    "arm the 3 s rotation interval only while visible (armed = inView and not narrow and not covered)")
  let k16 : Key := ("people.card",
    "MQ-gated shrink (KD#3): skip the --future-shrink write and the rAF re-request in the c860 band")
  [(⟨"engine.scroll", "batched"⟩, [k1]),
   (⟨"nav.hitTest", "elements-skip"⟩, [k4]),
   (⟨"nav.hitTest", "hit-skip"⟩, [k3]),
   (⟨"hero.countdown", "strip"⟩, [k7]),
   (⟨"morph.countdown", "strip"⟩, [k7, k13]),
   (⟨"morph.countdown", "hidden-pause"⟩, [k8h, k25m]),
   (⟨"morph.columns", "hidden-pause"⟩, [k25h]),
   (⟨"engine.scene", "hidden-pause"⟩, [k25h]),
   (⟨"morph.mount", "shift"⟩, [k12]),
   (⟨"morph.tween", "waapi"⟩, [k9]),
   (⟨"pain.notes", "visible"⟩, [k21]),
   (⟨"people.card", "mq"⟩, [k16])]

/-- **The curated exclusions**: flags kept out of the arm whatever the ledger says, each with its reason. `hero.accent`
has no link; the two strips share the row `k_7` and leave by the C3 decision (`research/notes/2026/10-19-c3-decision.md`). -/
def curated : List (Flag × String) :=
  [(⟨"hero.accent", "steps"⟩,
    "ledger n = 15: a trade on Chromium and no win on WebKit (INFERRED); a follow-up makes the generator require an \
      engine-win field"),
   (⟨"hero.countdown", "strip"⟩,
    "C3 decision (research/notes/2026/10-19-c3-decision.md): modelled, not proved. Its only prediction (census.layers \
      below the original) is unchecked, and the strip arm MEASURED more pipeline work (UpdateLayoutTree.elementCount \
      11264 -> 22445, runs 39257533380, 39259074927)"),
   (⟨"morph.countdown", "strip"⟩,
    "C3 decision (research/notes/2026/10-19-c3-decision.md): requires hero.countdown:strip and rests on its row k7, \
      both out of the arm")]

/-- The reason a flag is curated out, `none` when it is not. -/
def reasonOf (f : Flag) : Option String := (curated.find? (·.1 == f)).map (·.2)

/-- **The links the arm is decided from**: the link table without the curated flags. -/
def links : List (Flag × List Key) := linkTable.filter fun l => (reasonOf l.1).isNone

/-- Dropping the curated flags changes no other link and removes every curated one.

The exclusion touches only the flags it names. -/
theorem linkOf_links (f : Flag) :
    linkOf links f = if (reasonOf f).isNone then linkOf linkTable f else none := by
  unfold links linkOf
  generalize linkTable = l
  induction l with
  | nil => split <;> rfl
  | cons a t ih =>
    rw [List.filter_cons]
    by_cases h : a.1 = f
    · subst h
      by_cases hr : (reasonOf a.1).isNone = true
      · simp only [hr, ite_true, List.find?_cons, beq_self_eq_true, Option.map_some]
      · simp only [hr, ih, Bool.false_eq_true, ite_false]
    · have hb : (a.1 == f) = false := by simpa using h
      by_cases hr : (reasonOf a.1).isNone = true
      · simp only [hr, ite_true, List.find?_cons, hb, ih]
      · simp only [hr, ih, Bool.false_eq_true, ite_false, List.find?_cons, hb]

/-- A flag that is not curated keeps its link-table link.

Every other flag is decided from the ledger exactly as before. -/
theorem linkOf_links_of_none {f : Flag} (h : reasonOf f = none) : linkOf links f = linkOf linkTable f := by
  simp [linkOf_links, h]

/-- **A curated flag never enters the arm**, whatever the registry and the ledger say.

A proved ledger row cannot bring an excluded flag back. -/
theorem curated_not_mem {reg : List Reg} {ledger : List Row} {st : List Stored} {f : Flag} (h : reasonOf f ≠ none) :
    f ∉ preset reg links ledger st :=
  unlinked_not_mem (by simp [linkOf_links, h])

/-- Parse `part:variant`: exactly one colon, both sides non-empty. -/
def parseFlag (s : String) : Except String Flag :=
  match s.splitOn ":" with
  | [p, v] => if p.isEmpty || v.isEmpty then .error s!"bad flag {s}" else .ok ⟨p, v⟩
  | _ => .error s!"bad flag {s}"

/-- Parse a `part.json` `kind` (allowlist). -/
def parseKind : String → Except String Kind
  | "faithful" => .ok .faithful
  | "optimized" => .ok .optimized
  | "ablation" => .ok .ablation
  | "proposal" => .ok .proposal
  | s => .error s!"unknown kind {s}"

/-- Parse a ledger `fResult`, the `fw engine-check` verdict words (allowlist). -/
def parseFRes : String → Except String FRes
  | "pass" => .ok .pass
  | "unusable" => .ok .unusable
  | "model-bug" => .ok .modelBug
  | s => .error s!"unknown fResult {s}"

/-- The verdict word of an `FRes`. -/
def fresWord : FRes → String
  | .pass => "pass"
  | .unusable => "unusable"
  | .modelBug => "model-bug"

/-- An optional string field: absent (also when `j` is not an object) or `null` is `none`, a string is `some`, anything
else an error. -/
def optStr (j : Json) (n : String) : Except String (Option String) :=
  match j.getObjVal? n with
  | .error _ => .ok none
  | .ok .null => .ok none
  | .ok (.str s) => .ok (some s)
  | .ok _ => .error s!"field {n} is not a string"

/-- Parse one findings-ledger row: `part`, `candidate`, `status` required strings; `flag` and `fResult` optional. With
`φ = ⊥` when `optStr(j, fResult) = ⊥` and `φ = parseFRes(s)` when
it is `s`, a missing or non-string required field, or any error of `optStr` or `parseFRes`, makes the row an error. -/
def parseRow (j : Json) : Except String Row := do
  let fr ← match ← optStr j "fResult" with
    | none => pure none
    | some s => some <$> parseFRes s
  return { part := ← j.getObjValAs? String "part", candidate := ← j.getObjValAs? String "candidate",
           status := ← j.getObjValAs? String "status", flag := ← optStr j "flag", fResult := fr }

/-- Parse the ledger: the rows of its `findings` array, in order; an error if `findings` is missing or not an array, or
any row is an error. -/
def parseLedger (j : Json) : Except String (List Row) := do
  let a ← (← j.getObjVal? "findings").getArr?
  a.toList.mapM parseRow

/-- Parse a list of `part:variant` strings; an error if `j` is not an array or any element is not a string `parseFlag`
accepts. -/
def parseFlags (j : Json) : Except String (List Flag) := do
  (← j.getArr?).toList.mapM fun x => do parseFlag (← x.getStr?)

/-- Parse one `part.json` into its registered variants in key order, each with its `requires` and `conflicts` lists.
A `requires` or `conflicts` field that is absent or not an object, or that lacks the variant's entry, counts as
empty. A missing or non-string `id`, a missing or non-object `variants`, a missing or unknown `kind`, or an entry that
is not a list `parseFlags` accepts is an error. -/
def parsePart (j : Json) : Except String (List Reg) := do
  let id ← j.getObjValAs? String "id"
  let vs ← (← j.getObjVal? "variants").getObj?
  let rel (field key : String) : Except String (List Flag) :=
    match j.getObjVal? field >>= (·.getObjVal? key) with
    | .ok x => parseFlags x
    | .error _ => .ok []
  vs.toList.mapM fun (v, d) => do
    let f : Flag := ⟨id, v⟩
    return { flag := f, kind := ← parseKind (← d.getObjValAs? String "kind"),
             requires := ← rel "requires" f.key, conflicts := ← rel "conflicts" f.key }

/-- The preset file: `{"extends":"original","fw":{part: variant},"name":"v2-proved"}` on one line. -/
def presetText (p : List Flag) : String :=
  (Json.mkObj [("name", "v2-proved"), ("extends", "original"),
    ("fw", Json.mkObj (p.map fun f => (f.part, .str f.variant)))]).compress ++ "\n"

/-- The JSON of a verdict: its verdict word, plus the ledger key `k = (k_1, k_2)` and the status or count it names. -/
def whyJson : Why → Json
  | .proved => Json.mkObj [("verdict", "proved")]
  | .noLink => Json.mkObj [("verdict", "no-link")]
  | .falsifiedFlag => Json.mkObj [("verdict", "falsified-flag")]
  | .rowCount k n => Json.mkObj [("verdict", "row-count"), ("part", .str k.1), ("candidate", .str k.2), ("count", n)]
  | .notProved k s => Json.mkObj [("verdict", "not-proved"), ("part", .str k.1), ("candidate", .str k.2),
      ("status", .str s)]
  | .falsified k => Json.mkObj [("verdict", "falsified"), ("part", .str k.1), ("candidate", .str k.2)]

/-- The inputs a row contributes: its status and `fResult` word (`null` when absent). -/
def rowJson (r : Row) : Json :=
  Json.mkObj [("status", .str r.status), ("fResult", match r.fResult with | some x => .str (fresWord x) | none => .null)]

/-- The verdict of a decision row: `excluded` with its reason for a curated flag, else the ledger verdict. -/
def verdictJson (ledger : List Row) (f : Flag) : Json :=
  match reasonOf f with
  | some r => Json.mkObj [("verdict", "excluded"), ("reason", .str r)]
  | none => whyJson (why links ledger f)

/-- The flags with a decision row: the link-table flags in link order, then the registered `optimized` flags without a
link-table link, sorted by key. -/
def decided (reg : List Reg) : List Flag :=
  linkTable.map (·.1) ++
    ((reg.filter fun r => r.kind == .optimized && (linkOf linkTable r.flag).isNone).map (·.flag)).mergeSort
      (fun a b => a.key ≤ b.key)

/-- The word of an engine in the stored-run file. -/
def engineWord : Engine → String
  | .chromium => "chromium"
  | .linuxWebkit => "linux-webkit"
  | .macWebkit => "mac-webkit"

/-- Parse an engine word (allowlist). -/
def parseEngine : String → Except String Engine
  | "chromium" => .ok .chromium
  | "linux-webkit" => .ok .linuxWebkit
  | "mac-webkit" => .ok .macWebkit
  | s => .error s!"unknown engine {s}"

/-- The word of a path. -/
def walkWord : Walk → String
  | .hero => "hero"
  | .morph => "morph"

/-- Parse a path word (allowlist). -/
def parseWalk : String → Except String Walk
  | "hero" => .ok .hero
  | "morph" => .ok .morph
  | s => .error s!"unknown path {s}"

/-- The word of an engine family. -/
def familyWord : Family → String
  | .chromium => "chromium"
  | .webkit => "webkit"

/-- The word of a stored run's outcome. -/
def outcomeWord : Outcome → String
  | .pass => "pass"
  | .fail => "fail"
  | .unjudged .coverage => "no verdict: coverage"
  | .unjudged .widths => "no verdict: widths"

/-- The word of a trajectory cell. -/
def tcellWord : TCell → String
  | .pass => "pass"
  | .fail => "fail"
  | .pending => "pending"

/-- The reason word of a trajectory verdict. -/
def twhyWord : TWhy → String
  | .pass => "pass"
  | .pending => "pending: trajectory"
  | .falsified => "falsified: trajectory"

/-- One line of the stored-run file. -/
def storedJson (s : Stored) : Json :=
  Json.mkObj [("run", .str s.run), ("sha", .str s.sha), ("search", .str s.search), ("flags", toJson s.flags),
    ("engine", .str (engineWord s.engine)), ("path", .str (walkWord s.walk)), ("widths", toJson s.widths),
    ("groups", .arr (s.groups.map fun g => Json.mkObj [("node", .str g.node), ("prop", .str g.prop),
      ("content", toJson g.content), ("coverage", toJson g.coverage)]).toArray)]

/-- Parse one line of the stored-run file; every field is required. -/
def parseStored (j : Json) : Except String Stored := do
  let gs ← (← j.getObjVal? "groups").getArr?
  let groups ← gs.toList.mapM fun g => do
    return ⟨← g.getObjValAs? String "node", ← g.getObjValAs? String "prop", ← g.getObjValAs? (List Nat) "content",
      ← g.getObjValAs? (List Nat) "coverage"⟩
  return { run := ← j.getObjValAs? String "run", sha := ← j.getObjValAs? String "sha",
           search := ← j.getObjValAs? String "search", flags := ← j.getObjValAs? (List String) "flags",
           engine := ← parseEngine (← j.getObjValAs? String "engine"),
           walk := ← parseWalk (← j.getObjValAs? String "path"), widths := ← j.getObjValAs? (List Nat) "widths",
           groups }

/-- Parse the stored-run file: one `parseStored` line per non-empty line. -/
def parseStoredText (t : String) : Except String (List Stored) :=
  ((t.splitOn "\n").filter (!·.isEmpty)).mapM fun l => do parseStored (← Json.parse l)

/-- The stored-run file: one compact line per run, sorted by run id, engine and path. -/
def storedText (st : List Stored) : String :=
  let key (s : Stored) := s.run ++ " " ++ engineWord s.engine ++ " " ++ walkWord s.walk
  String.join ((st.mergeSort fun a b => key a ≤ key b).map fun s => (storedJson s).compress ++ "\n")

/-- The trajectory field of a decision row: the verdict, and per cell its verdict and the stored runs it read. -/
def trajJson (st : List Stored) (f : Flag) : Json :=
  let cell (fam : Family) (w : Walk) : Json :=
    Json.mkObj [("family", .str (familyWord fam)), ("path", .str (walkWord w)), ("cell", .str (tcellWord (tcell st f fam w))),
      ("runs", .arr ((runsFor st f fam w).map fun s => Json.mkObj [("run", .str s.run),
        ("engine", .str (engineWord s.engine)), ("alone", .bool (s.flags == [f.key])),
        ("outcome", .str (outcomeWord (outcome s)))]).toArray)]
  Json.mkObj [("verdict", .str (twhyWord (trajWhy st f))),
    ("cells", .arr (families.flatMap fun fam => walks.map (cell fam)).toArray)]

/-- One decision row: the flag, whether it is registered `optimized`, its ledger verdict, its trajectory verdict,
membership, the flag that shadows it, and the ledger inputs it read (the rows of each linked key and the rows naming the
flag). -/
def decision (reg : List Reg) (ledger : List Row) (st : List Stored) (f : Flag) : Json :=
  let p := preset reg links ledger st
  let fs := links.map (·.1)
  let shadow : Json := if ok reg links ledger st f && !p.contains f then
      match firstOk (ok reg links ledger st) fs f.part with
      | some g => .str g.key
      | none => .null
    else .null
  let rows := ((linkOf linkTable f).getD []).map fun k =>
    Json.mkObj [("part", .str k.1), ("candidate", .str k.2), ("found", .arr ((rowsOf ledger k).map rowJson).toArray)]
  Json.mkObj [("flag", .str f.key), ("registered", .bool (isOpt reg f)), ("why", verdictJson ledger f),
    ("trajectory", trajJson st f), ("member", .bool (p.contains f)), ("shadowedBy", shadow),
    ("rows", .arr rows.toArray), ("flagRows", .arr ((ledger.filter (·.flag == some f.key)).map rowJson).toArray)]

/-- The decision file: one compact JSON line per decided flag. -/
def decisionsText (reg : List Reg) (ledger : List Row) (st : List Stored) : String :=
  String.join ((decided reg).map fun f => (decision reg ledger st f).compress ++ "\n")

/-- The ledger path, from `lean/`. -/
def ledgerPath : System.FilePath := ".." / "research" / "findings" / "ledger.json"
/-- The parts directory, from `lean/`. -/
def partsDir : System.FilePath := ".." / "apps" / "site" / "src" / "parts"
/-- The golden preset, from `lean/`. -/
def goldenPreset : System.FilePath := ".." / "packages" / "contracts" / "golden" / "preset" / "v2-proved.json"
/-- The golden decision rows, from `lean/`. -/
def goldenDecisions : System.FilePath :=
  ".." / "packages" / "contracts" / "golden" / "preset" / "v2-proved.decisions.jsonl"
/-- The site preset, from `lean/`. -/
def sitePreset : System.FilePath := ".." / "apps" / "site" / "src" / "registry" / "presets" / "v2-proved.json"
/-- The stored trajectory runs, from `lean/`; only `record` writes it. -/
def storedPath : System.FilePath :=
  ".." / "packages" / "contracts" / "golden" / "preset" / "v2-proved.trajectory.jsonl"

/-- Read the stored trajectory runs; a missing file or a bad line throws. -/
def readStored : IO (List Stored) := do
  IO.ofExcept ((parseStoredText (← IO.FS.readFile storedPath)).mapError fun e => s!"{storedPath}: {e}")

/-- Read and parse a JSON file; a parse error names the path. -/
def readJson (p : System.FilePath) : IO Json := do
  IO.ofExcept ((Json.parse (← IO.FS.readFile p)).mapError fun e => s!"{p}: {e}")

/-- Every registered variant: the `part.json` of each directory under the parts directory, directories sorted by
name; a directory without `part.json` is skipped. -/
def readRegistry : IO (List Reg) := do
  let ds := (← partsDir.readDir).qsort (·.fileName < ·.fileName)
  let mut out : List Reg := []
  for d in ds do
    let pj := d.path / "part.json"
    if ← pj.pathExists then
      out := out ++ (← IO.ofExcept ((parsePart (← readJson pj)).mapError fun e => s!"{pj}: {e}"))
  return out

/-- Write the three files, or with `--check` throw when any differs from the Lean output and print a message when none
does; a ledger or part that does not parse, or a preset that is not closed, throws before anything is written. Each case
assumes the cases above it do not apply; a file that cannot be read reads as the empty string `ε`. Here
`P = generate(R, Λ, L, S)` and `outs = [(goldenPreset, presetText(P)), (sitePreset, presetText(P)), (goldenDecisions, decisionsText(R, L, S))]`, with `S` the stored trajectory runs. -/
def run (args : List String) : IO Unit := do
  let ledger ← IO.ofExcept ((parseLedger (← readJson ledgerPath)).mapError fun e => s!"{ledgerPath}: {e}")
  let reg ← readRegistry
  let st ← readStored
  let p ← IO.ofExcept (generate reg links ledger st)
  let outs := [(goldenPreset, presetText p), (sitePreset, presetText p),
    (goldenDecisions, decisionsText reg ledger st)]
  if args.contains "--check" then
    let mut stale : List String := []
    for (path, text) in outs do
      let cur ← try IO.FS.readFile path catch _ => pure ""
      if cur != text then stale := stale ++ [path.toString]
    unless stale.isEmpty do
      throw (IO.userError s!"v2-proved: stale {stale}; regenerate with Fw.Preset.Gen.run []")
    IO.println s!"v2-proved: up to date, {p.length} flags: {p.map (·.key)}"
  else
    for (path, text) in outs do
      IO.FS.createDirAll (path.parent.getD ".")
      IO.FS.writeFile path text
    IO.println s!"v2-proved: written, {p.length} flags: {p.map (·.key)}"

/-- The engine of a `trajectory-probe.yml` artifact directory (allowlist). -/
def engineOfArtifact : String → Except String Engine
  | "trajectory-chromium" => .ok .chromium
  | "trajectory-playwright-webkit" => .ok .linuxWebkit
  | "trajectory-apple" => .ok .macWebkit
  | s => .error s!"unknown trajectory artifact {s}"

/-- The units file name inside an artifact directory of the engine. -/
def unitsName : Engine → String
  | .chromium => "units-chromium.json"
  | _ => "units-playwright-webkit.json"

/-- The non-empty flags of a search: the keys of `?fw=k1,k2`, or of the given preset for `?preset=name` (allowlist). -/
def flagsOfSearch (search : String) (presetKeys : Option (List String)) : Except String (List String) := do
  let ks ← if search.startsWith "?fw=" then
      ((search.drop 4).toString.splitOn ",").mapM fun k => do pure (← parseFlag k).key
    else if search.startsWith "?preset=" && !(search.drop 8).toString.contains '&' then
      match presetKeys with
      | some ks => pure ks
      | none => throw s!"search {search} needs the preset file of the run's commit"
    else throw s!"search {search} is neither ?fw= nor ?preset="
  if ks.isEmpty then throw s!"search {search} names no flag" else pure ks

/-- The keys of a preset file that extends `original`, sorted. -/
def presetKeys (j : Json) : Except String (List String) := do
  unless (← j.getObjValAs? String "extends") == "original" do throw "preset does not extend original"
  let fw ← (← j.getObjVal? "fw").getObj?
  let ks ← fw.toList.mapM fun ((p, v) : String × Json) => do pure (p ++ ":" ++ (← v.getStr?))
  pure (ks.mergeSort (· ≤ ·))

/-- Parse one unit of a units file into a `UnitRow`. -/
def parseUnit (j : Json) : Except String UnitRow := do
  return { width := ← j.getObjValAs? Nat "width", walk := ← j.getObjValAs? String "path",
           node := ← j.getObjValAs? String "node", prop := ← j.getObjValAs? String "prop",
           coverage := (← j.getObjValAs? String "verdict") == "fail:coverage",
           isNew := (← j.getObjValAs? String "rel") == "new" }

/-- The stored runs of one units file: one per path it walked; a refused run is an error. -/
def storedOf (run sha : String) (e : Engine) (presetKeys : Option (List String)) (j : Json) :
    Except String (List Stored) := do
  if ← j.getObjValAs? Bool "refused" then throw s!"run {run} {engineWord e} was refused"
  let search ← j.getObjValAs? String "search"
  let flags ← flagsOfSearch search presetKeys
  let us ← (← (← j.getObjVal? "units").getArr?).toList.mapM parseUnit
  return [Walk.hero, .morph].filterMap fun w =>
    if us.any (·.walk == walkWord w) then
      some { run, sha, search, flags, engine := e, walk := w, widths := widthsOf (walkWord w) us,
             groups := groupsOf (walkWord w) us }
    else none

/-- Replace the stored runs of the same run, engine and path by the new ones. -/
def merge (old new : List Stored) : List Stored :=
  old.filter (fun s => !new.any fun n => n.run == s.run && n.engine == s.engine && n.walk == s.walk) ++ new

/-- `record [run, sha, presetFile or "-", artifactDir...]`: store each artifact's paths and print their outcomes. -/
def record (args : List String) : IO Unit := do
  let (run, sha, pf, dirs) ← match args with
    | r :: s :: p :: d :: ds => pure (r, s, p, d :: ds)
    | _ => throw (IO.userError "usage: record [run, sha, presetFile or -, artifactDir...]")
  unless !run.isEmpty && run.all Char.isDigit do throw (IO.userError s!"bad run id {run}")
  unless sha.length == 40 && sha.all fun c => c.isDigit || ('a' ≤ c && c ≤ 'f') do
    throw (IO.userError s!"bad sha {sha}")
  let keys ← if pf == "-" then pure none else some <$> IO.ofExcept (presetKeys (← readJson pf))
  let mut new : List Stored := []
  for d in dirs do
    let dir : System.FilePath := d
    let e ← IO.ofExcept (engineOfArtifact (dir.fileName.getD ""))
    let j ← readJson (dir / unitsName e)
    new := new ++ (← IO.ofExcept ((storedOf run sha e keys j).mapError fun m => s!"{dir}: {m}"))
  IO.FS.writeFile storedPath (storedText (merge (← readStored) new))
  for s in new do
    IO.println s!"record: run {s.run} {engineWord s.engine} {walkWord s.walk}: {outcomeWord (outcome s)}"

#guard (parseFlag "nav.hitTest:hit-skip").toOption == some ⟨"nav.hitTest", "hit-skip"⟩
#guard (parseFlag "nav.hitTest").toOption.isNone
#guard (parseFlag "a:b:c").toOption.isNone
#guard (parseFlag ":b").toOption.isNone
#guard (parseKind "optimized").toOption == some .optimized
#guard (parseKind "Optimized").toOption.isNone
#guard (parseFRes "model-bug").toOption == some .modelBug
#guard (parseFRes "falsified").toOption.isNone
#guard (parseRow (Json.mkObj [("part", "a"), ("candidate", "c"), ("status", "proved")])).toOption.map (·.fResult)
  == some none
#guard (parseRow (Json.mkObj [("part", "a"), ("candidate", "c"), ("status", "proved"), ("fResult", "model-bug"),
  ("flag", "a:x")])).toOption.map (fun r => (r.flag, r.fResult)) == some (some "a:x", some .modelBug)
#guard (parseRow (Json.mkObj [("part", "a"), ("candidate", "c"), ("status", "proved"), ("fResult", "bug")])).toOption.isNone
#guard (parseRow (Json.mkObj [("part", "a"), ("status", "proved")])).toOption.isNone
#guard ((parsePart (Json.mkObj [("id", "m"), ("variants", Json.mkObj [("faithful", Json.mkObj [("kind", "faithful")]),
    ("s", Json.mkObj [("kind", "optimized")])]), ("requires", Json.mkObj [("m:s", Json.arr #["h:s"])]),
    ("conflicts", Json.mkObj [])])).toOption.map fun rs => rs.map fun r => (r.flag.key, r.requires.map (·.key)))
  == some [("m:faithful", []), ("m:s", ["h:s"])]
#guard presetText [⟨"b", "x"⟩, ⟨"a", "y"⟩] == "{\"extends\":\"original\",\"fw\":{\"a\":\"y\",\"b\":\"x\"},\"name\":\"v2-proved\"}\n"
#guard (reasonOf ⟨"hero.countdown", "strip"⟩).isSome
#guard (reasonOf ⟨"morph.countdown", "strip"⟩).isSome
#guard (reasonOf ⟨"hero.accent", "steps"⟩).isSome
#guard (reasonOf ⟨"morph.countdown", "hidden-pause"⟩).isNone
#guard (reasonOf ⟨"hero.countdown", "hidden-pause"⟩).isNone
#guard links.map (·.1.key) == ["engine.scroll:batched", "nav.hitTest:elements-skip", "nav.hitTest:hit-skip",
  "morph.countdown:hidden-pause", "morph.columns:hidden-pause", "engine.scene:hidden-pause", "morph.mount:shift",
  "morph.tween:waapi", "pain.notes:visible", "people.card:mq"]
#guard ((verdictJson [] ⟨"hero.countdown", "strip"⟩).getObjValAs? String "verdict").toOption == some "excluded"
#guard ((verdictJson [] ⟨"morph.countdown", "hidden-pause"⟩).getObjValAs? String "verdict").toOption == some "row-count"
#guard presetText [] == "{\"extends\":\"original\",\"fw\":{},\"name\":\"v2-proved\"}\n"

private def stEx : Stored :=
  ⟨"7", "s", "?fw=a:x", ["a:x"], .macWebkit, .morph, [390, 641], [⟨"nav", "opacity", [390], [641]⟩]⟩
private def stBad : Stored :=
  { stEx with engine := .chromium, widths := Fw.Gate.Trajectory.allowedWidths,
              groups := [⟨"nav", "opacity", [390, 641], []⟩] }
private def unitJ (w : Nat) (p v r : String) : Json :=
  Json.mkObj [("width", w), ("path", .str p), ("node", "nav"), ("prop", "opacity"), ("verdict", .str v), ("rel", .str r)]
private def unitsJ (refused : Bool) (search : String) : Json :=
  Json.mkObj [("refused", .bool refused), ("search", .str search), ("units", .arr #[unitJ 390 "morph" "pass" "new",
    unitJ 641 "morph" "fail:coverage" "new", unitJ 641 "morph" "pass" "ok", unitJ 390 "hero" "pass" "ok"])]

#guard (parseStoredText (storedText [stEx, { stEx with run := "6" }])).toOption == some [{ stEx with run := "6" }, stEx]
#guard (parseStoredText "{\"run\":\"1\"}\n").toOption.isNone
#guard (parseEngine "apple").toOption.isNone
#guard (parseWalk "exit").toOption.isNone
#guard (engineOfArtifact "trajectory-apple").toOption == some .macWebkit
#guard (engineOfArtifact "telemetry-site").toOption.isNone
#guard (flagsOfSearch "?fw=a:x,b:y" none).toOption == some ["a:x", "b:y"]
#guard (flagsOfSearch "?fw=a" none).toOption.isNone
#guard (flagsOfSearch "" none).toOption.isNone
#guard (flagsOfSearch "?preset=v2-proved" none).toOption.isNone
#guard (flagsOfSearch "?preset=v2-proved" (some ["a:x"])).toOption == some ["a:x"]
#guard (flagsOfSearch "?preset=v2-proved" (some [])).toOption.isNone
#guard (flagsOfSearch "?preset=v2-proved&fw=b:y" (some ["a:x"])).toOption.isNone
#guard (presetKeys (Json.mkObj [("extends", "original"), ("fw", Json.mkObj [("b", "y"), ("a", "x")])])).toOption ==
  some ["a:x", "b:y"]
#guard (presetKeys (Json.mkObj [("extends", "v2-proved"), ("fw", Json.mkObj [])])).toOption.isNone
#guard (storedOf "7" "s" .chromium none (unitsJ true "?fw=a:x")).toOption.isNone
#guard ((storedOf "7" "s" .chromium none (unitsJ false "?fw=a:x")).toOption.map fun l => l.map fun s =>
  (walkWord s.walk, s.widths, s.groups)) ==
  some [("hero", [390], []), ("morph", [390, 641], [⟨"nav", "opacity", [390], [641]⟩])]
#guard (merge [stEx, { stEx with walk := .hero }] [{ stEx with groups := [] }]).map (·.groups.length) == [1, 0]
#guard ((trajJson [stEx] ⟨"a", "x"⟩).getObjValAs? String "verdict").toOption == some "pending: trajectory"
#guard ((trajJson [stBad] ⟨"a", "x"⟩).getObjValAs? String "verdict").toOption == some "falsified: trajectory"

end Fw.Preset.Gen
