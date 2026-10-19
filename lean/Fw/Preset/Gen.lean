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

/-- **The link table**: each flag and the ledger rows that carry its proof, in priority order (the first qualifying flag
of a part wins). A row is named by its (part, candidate) text; $k_n$ below is the row of ledger entry $n$ (for $n = 8$
and $25$ the letter names which of the rows with that $n$). The mapping is read from the variants' code and the rows'
text (INFERRED); a flag absent here never enters the arm (`unlinked_not_mem`), and a curated flag is dropped from it
before the arm is decided (`links`).

$$\Lambda_0 = [(\mathrm{engine.scroll{:}batched}, [k_1]),\ (\mathrm{nav.hitTest{:}elements\text{-}skip}, [k_4]),\ (\mathrm{nav.hitTest{:}hit\text{-}skip}, [k_3]),\ (\mathrm{hero.countdown{:}strip}, [k_7]),\ (\mathrm{morph.countdown{:}strip}, [k_7, k_{13}]),\ (\mathrm{morph.countdown{:}hidden\text{-}pause}, [k_{8h}, k_{25m}]),\ (\mathrm{morph.columns{:}hidden\text{-}pause}, [k_{25h}]),\ (\mathrm{engine.scene{:}hidden\text{-}pause}, [k_{25h}]),\ (\mathrm{morph.mount{:}shift}, [k_{12}]),\ (\mathrm{morph.tween{:}waapi}, [k_9]),\ (\mathrm{pain.notes{:}visible}, [k_{21}]),\ (\mathrm{people.card{:}mq}, [k_{16}])]$$

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
has no link; the two strips share the row $k_7$ and leave by the C3 decision (`research/notes/2026/10-19-c3-decision.md`).

$$\Xi = [(\mathrm{hero.accent{:}steps}, \rho_{15}),\ (\mathrm{hero.countdown{:}strip}, \rho_{C3}),\ (\mathrm{morph.countdown{:}strip}, \rho_{C3}')]$$ -/
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

/-- The reason a flag is curated out, `none` when it is not.

$$\operatorname{reasonOf}(f) = \begin{cases} \rho & (f, \rho) \text{ is the first pair of } \Xi \text{ with flag } f \\ \bot & \text{no pair of } \Xi \text{ has flag } f \end{cases}$$ -/
def reasonOf (f : Flag) : Option String := (curated.find? (·.1 == f)).map (·.2)

/-- **The links the arm is decided from**: the link table without the curated flags.

$$\Lambda = [\,(f, \kappa) \in \Lambda_0 \mid \operatorname{reasonOf}(f) = \bot\,]$$ -/
def links : List (Flag × List Key) := linkTable.filter fun l => (reasonOf l.1).isNone

/-- Dropping the curated flags changes no other link and removes every curated one.

$$\forall f:\ \operatorname{linkOf}(\Lambda, f) = \begin{cases} \operatorname{linkOf}(\Lambda_0, f) & \operatorname{reasonOf}(f) = \bot \\ \bot & \operatorname{reasonOf}(f) \ne \bot \end{cases}$$

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

$$\forall f:\ \operatorname{reasonOf}(f) = \bot \Rightarrow \operatorname{linkOf}(\Lambda, f) = \operatorname{linkOf}(\Lambda_0, f)$$

Every other flag is decided from the ledger exactly as before. -/
theorem linkOf_links_of_none {f : Flag} (h : reasonOf f = none) : linkOf links f = linkOf linkTable f := by
  simp [linkOf_links, h]

/-- **A curated flag never enters the arm**, whatever the registry and the ledger say.

$$\forall R, L, f:\ \operatorname{reasonOf}(f) \ne \bot \Rightarrow f \notin \operatorname{preset}(R, \Lambda, L)$$

A proved ledger row cannot bring an excluded flag back. -/
theorem curated_not_mem {reg : List Reg} {ledger : List Row} {f : Flag} (h : reasonOf f ≠ none) :
    f ∉ preset reg links ledger :=
  unlinked_not_mem (by simp [linkOf_links, h])

/-- Parse `part:variant`: exactly one colon, both sides non-empty.

$$\operatorname{parseFlag}(s) = \begin{cases} (p, v) & s = p \mathbin{+\!\!+} \texttt{":"} \mathbin{+\!\!+} v,\ p \ne \varepsilon,\ v \ne \varepsilon,\ \texttt{":"} \notin p, v \\ \operatorname{error} & \text{otherwise} \end{cases}$$ -/
def parseFlag (s : String) : Except String Flag :=
  match s.splitOn ":" with
  | [p, v] => if p.isEmpty || v.isEmpty then .error s!"bad flag {s}" else .ok ⟨p, v⟩
  | _ => .error s!"bad flag {s}"

/-- Parse a `part.json` `kind` (allowlist).

$$\operatorname{parseKind}(s) = \begin{cases} \mathrm{faithful} & s = \texttt{"faithful"} \\ \mathrm{optimized} & s = \texttt{"optimized"} \\ \mathrm{ablation} & s = \texttt{"ablation"} \\ \mathrm{proposal} & s = \texttt{"proposal"} \\ \operatorname{error} & \text{otherwise} \end{cases}$$ -/
def parseKind : String → Except String Kind
  | "faithful" => .ok .faithful
  | "optimized" => .ok .optimized
  | "ablation" => .ok .ablation
  | "proposal" => .ok .proposal
  | s => .error s!"unknown kind {s}"

/-- Parse a ledger `fResult`, the `fw engine-check` verdict words (allowlist).

$$\operatorname{parseFRes}(s) = \begin{cases} \mathrm{pass} & s = \texttt{"pass"} \\ \mathrm{unusable} & s = \texttt{"unusable"} \\ \mathrm{modelBug} & s = \texttt{"model-bug"} \\ \operatorname{error} & \text{otherwise} \end{cases}$$ -/
def parseFRes : String → Except String FRes
  | "pass" => .ok .pass
  | "unusable" => .ok .unusable
  | "model-bug" => .ok .modelBug
  | s => .error s!"unknown fResult {s}"

/-- The verdict word of an `FRes`.

$$\operatorname{fresWord}(\mathrm{pass}) = \texttt{"pass"},\ \operatorname{fresWord}(\mathrm{unusable}) = \texttt{"unusable"},\ \operatorname{fresWord}(\mathrm{modelBug}) = \texttt{"model-bug"}$$ -/
def fresWord : FRes → String
  | .pass => "pass"
  | .unusable => "unusable"
  | .modelBug => "model-bug"

/-- An optional string field: absent (also when $j$ is not an object) or `null` is `none`, a string is `some`, anything
else an error.

$$\operatorname{optStr}(j, n) = \begin{cases} \bot & j \text{ not an object, or } j.n \text{ absent or null} \\ s & j.n = s \in \mathrm{String} \\ \operatorname{error} & \text{otherwise} \end{cases}$$ -/
def optStr (j : Json) (n : String) : Except String (Option String) :=
  match j.getObjVal? n with
  | .error _ => .ok none
  | .ok .null => .ok none
  | .ok (.str s) => .ok (some s)
  | .ok _ => .error s!"field {n} is not a string"

/-- Parse one findings-ledger row: `part`, `candidate`, `status` required strings; `flag` and `fResult` optional. With
$\varphi = \bot$ when $\operatorname{optStr}(j, \mathrm{fResult}) = \bot$ and $\varphi = \operatorname{parseFRes}(s)$ when
it is $s$, a missing or non-string required field, or any error of `optStr` or `parseFRes`, makes the row an error.

$$\operatorname{parseRow}(j) = \begin{cases} (j.\mathrm{part}, j.\mathrm{candidate}, j.\mathrm{status}, \operatorname{optStr}(j, \mathrm{flag}), \varphi) & \text{all three required fields are strings and no step errs} \\ \operatorname{error} & \text{otherwise} \end{cases}$$ -/
def parseRow (j : Json) : Except String Row := do
  let fr ← match ← optStr j "fResult" with
    | none => pure none
    | some s => some <$> parseFRes s
  return { part := ← j.getObjValAs? String "part", candidate := ← j.getObjValAs? String "candidate",
           status := ← j.getObjValAs? String "status", flag := ← optStr j "flag", fResult := fr }

/-- Parse the ledger: the rows of its `findings` array, in order; an error if `findings` is missing or not an array, or
any row is an error.

$$\operatorname{parseLedger}(j) = [\,\operatorname{parseRow}(x) \mid x \in j.\mathrm{findings}\,]$$ -/
def parseLedger (j : Json) : Except String (List Row) := do
  let a ← (← j.getObjVal? "findings").getArr?
  a.toList.mapM parseRow

/-- Parse a list of `part:variant` strings; an error if $j$ is not an array or any element is not a string `parseFlag`
accepts.

$$\operatorname{parseFlags}(j) = [\,\operatorname{parseFlag}(s) \mid s \in j\,]$$ -/
def parseFlags (j : Json) : Except String (List Flag) := do
  (← j.getArr?).toList.mapM fun x => do parseFlag (← x.getStr?)

/-- Parse one `part.json` into its registered variants in key order, each with its `requires` and `conflicts` lists.
A `requires` or `conflicts` field that is absent or not an object, or that lacks the variant's entry, counts as
empty. A missing or non-string `id`, a missing or non-object `variants`, a missing or unknown `kind`, or an entry that
is not a list `parseFlags` accepts is an error.

$$\rho(n, v) = \begin{cases} \operatorname{parseFlags}(j.n[\operatorname{key}(j.\mathrm{id}, v)]) & j.n \text{ is an object holding the entry } \operatorname{key}(j.\mathrm{id}, v) \\ [] & j.n \text{ absent or not an object, or the entry absent} \end{cases}$$

$$\operatorname{parsePart}(j) = [\,((j.\mathrm{id}, v), \operatorname{parseKind}(j.\mathrm{variants}.v.\mathrm{kind}), \rho(\mathrm{requires}, v), \rho(\mathrm{conflicts}, v)) \mid v \in \operatorname{keys}(j.\mathrm{variants})\,]$$ -/
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

/-- The preset file: `{"extends":"original","fw":{part: variant},"name":"v2-proved"}` on one line.

$$\operatorname{presetText}(P) = \operatorname{json}(\{\mathrm{extends}: \texttt{original},\ \mathrm{fw}: \{f.\mathrm{part} \mapsto f.\mathrm{variant} \mid f \in P\},\ \mathrm{name}: \texttt{v2-proved}\}) \mathbin{+\!\!+} \texttt{"\textbackslash n"}$$ -/
def presetText (p : List Flag) : String :=
  (Json.mkObj [("name", "v2-proved"), ("extends", "original"),
    ("fw", Json.mkObj (p.map fun f => (f.part, .str f.variant)))]).compress ++ "\n"

/-- The JSON of a verdict: its verdict word, plus the ledger key $k = (k_1, k_2)$ and the status or count it names.

$$\operatorname{whyJson}(w) = \begin{cases} \{\mathrm{verdict}: \texttt{proved}\} & w = \mathrm{proved} \\ \{\mathrm{verdict}: \texttt{no-link}\} & w = \mathrm{noLink} \\ \{\mathrm{verdict}: \texttt{falsified-flag}\} & w = \mathrm{falsifiedFlag} \\ \{\mathrm{verdict}: \texttt{row-count},\ \mathrm{part}: k_1,\ \mathrm{candidate}: k_2,\ \mathrm{count}: n\} & w = \mathrm{rowCount}(k, n) \\ \{\mathrm{verdict}: \texttt{not-proved},\ \mathrm{part}: k_1,\ \mathrm{candidate}: k_2,\ \mathrm{status}: s\} & w = \mathrm{notProved}(k, s) \\ \{\mathrm{verdict}: \texttt{falsified},\ \mathrm{part}: k_1,\ \mathrm{candidate}: k_2\} & w = \mathrm{falsified}(k) \end{cases}$$ -/
def whyJson : Why → Json
  | .proved => Json.mkObj [("verdict", "proved")]
  | .noLink => Json.mkObj [("verdict", "no-link")]
  | .falsifiedFlag => Json.mkObj [("verdict", "falsified-flag")]
  | .rowCount k n => Json.mkObj [("verdict", "row-count"), ("part", .str k.1), ("candidate", .str k.2), ("count", n)]
  | .notProved k s => Json.mkObj [("verdict", "not-proved"), ("part", .str k.1), ("candidate", .str k.2),
      ("status", .str s)]
  | .falsified k => Json.mkObj [("verdict", "falsified"), ("part", .str k.1), ("candidate", .str k.2)]

/-- The inputs a row contributes: its status and `fResult` word (`null` when absent).

$$\operatorname{rowJson}(r) = \{\mathrm{status}: r.\mathrm{status},\ \mathrm{fResult}: r.\mathrm{fResult}\}$$ -/
def rowJson (r : Row) : Json :=
  Json.mkObj [("status", .str r.status), ("fResult", match r.fResult with | some x => .str (fresWord x) | none => .null)]

/-- The verdict of a decision row: `excluded` with its reason for a curated flag, else the ledger verdict.

$$\operatorname{verdictJson}(L, f) = \begin{cases} \{\mathrm{verdict}: \texttt{excluded},\ \mathrm{reason}: \rho\} & \operatorname{reasonOf}(f) = \rho \\ \operatorname{whyJson}(\operatorname{why}(\Lambda, L, f)) & \operatorname{reasonOf}(f) = \bot \end{cases}$$ -/
def verdictJson (ledger : List Row) (f : Flag) : Json :=
  match reasonOf f with
  | some r => Json.mkObj [("verdict", "excluded"), ("reason", .str r)]
  | none => whyJson (why links ledger f)

/-- The flags with a decision row: the link-table flags in link order, then the registered `optimized` flags without a
link-table link, sorted by key.

$$\operatorname{decided}(R) = [\,f \mid (f, \kappa) \in \Lambda_0\,] \mathbin{+\!\!+} \operatorname{sort}_{\operatorname{key}}[\,r.\mathrm{flag} \mid r \in R,\ r.\mathrm{kind} = \mathrm{optimized},\ \operatorname{linkOf}(\Lambda_0, r.\mathrm{flag}) = \bot\,]$$ -/
def decided (reg : List Reg) : List Flag :=
  linkTable.map (·.1) ++
    ((reg.filter fun r => r.kind == .optimized && (linkOf linkTable r.flag).isNone).map (·.flag)).mergeSort
      (fun a b => a.key ≤ b.key)

/-- One decision row: the flag, whether it is registered `optimized`, its verdict, membership, the flag that shadows
it, and the ledger inputs it read (the rows of each linked key and the rows naming the flag).

$$\operatorname{decision}(R, L, f) = \{\mathrm{flag}: \operatorname{key}(f), \mathrm{registered}: \operatorname{isOpt}(R, f), \mathrm{why}: \operatorname{verdictJson}(L, f), \mathrm{member}: f \in \operatorname{preset}(R, \Lambda, L), \mathrm{shadowedBy}, \mathrm{rows}, \mathrm{flagRows}\}$$

$$\mathrm{shadowedBy} = \begin{cases} \operatorname{key}(g) & \operatorname{ok}(R, \Lambda, L, f) \land f \notin \operatorname{preset}(R, \Lambda, L) \land \operatorname{firstOk}(\operatorname{ok}(R, \Lambda, L), [\,h \mid (h, \kappa) \in \Lambda\,], f.\mathrm{part}) = g \\ \mathrm{null} & \text{otherwise} \end{cases}$$

$$\mathrm{rows} = [\,\{\mathrm{part}: k_1,\ \mathrm{candidate}: k_2,\ \mathrm{found}: [\operatorname{rowJson}(r) \mid r \in \operatorname{rowsOf}(L, k)]\} \mid k \in \operatorname{linkOf}(\Lambda_0, f) \text{, or } [] \text{ when } \operatorname{linkOf}(\Lambda_0, f) = \bot\,],\quad \mathrm{flagRows} = [\,\operatorname{rowJson}(r) \mid r \in L,\ r.\mathrm{flag} = \operatorname{key}(f)\,]$$ -/
def decision (reg : List Reg) (ledger : List Row) (f : Flag) : Json :=
  let p := preset reg links ledger
  let fs := links.map (·.1)
  let shadow : Json := if ok reg links ledger f && !p.contains f then
      match firstOk (ok reg links ledger) fs f.part with
      | some g => .str g.key
      | none => .null
    else .null
  let rows := ((linkOf linkTable f).getD []).map fun k =>
    Json.mkObj [("part", .str k.1), ("candidate", .str k.2), ("found", .arr ((rowsOf ledger k).map rowJson).toArray)]
  Json.mkObj [("flag", .str f.key), ("registered", .bool (isOpt reg f)), ("why", verdictJson ledger f),
    ("member", .bool (p.contains f)), ("shadowedBy", shadow), ("rows", .arr rows.toArray),
    ("flagRows", .arr ((ledger.filter (·.flag == some f.key)).map rowJson).toArray)]

/-- The decision file: one compact JSON line per decided flag.

$$\operatorname{decisionsText}(R, L) = \mathop{+\!\!+}_{f \in \operatorname{decided}(R)} \bigl(\operatorname{json}(\operatorname{decision}(R, L, f)) \mathbin{+\!\!+} \texttt{"\textbackslash n"}\bigr)$$ -/
def decisionsText (reg : List Reg) (ledger : List Row) : String :=
  String.join ((decided reg).map fun f => (decision reg ledger f).compress ++ "\n")

/-- The ledger path, from `lean/`.

$$\mathrm{ledgerPath} = \texttt{../research/findings/ledger.json}$$ -/
def ledgerPath : System.FilePath := ".." / "research" / "findings" / "ledger.json"
/-- The parts directory, from `lean/`.

$$\mathrm{partsDir} = \texttt{../apps/site/src/parts}$$ -/
def partsDir : System.FilePath := ".." / "apps" / "site" / "src" / "parts"
/-- The golden preset, from `lean/`.

$$\mathrm{goldenPreset} = \texttt{../packages/contracts/golden/preset/v2-proved.json}$$ -/
def goldenPreset : System.FilePath := ".." / "packages" / "contracts" / "golden" / "preset" / "v2-proved.json"
/-- The golden decision rows, from `lean/`.

$$\mathrm{goldenDecisions} = \texttt{../packages/contracts/golden/preset/v2-proved.decisions.jsonl}$$ -/
def goldenDecisions : System.FilePath :=
  ".." / "packages" / "contracts" / "golden" / "preset" / "v2-proved.decisions.jsonl"
/-- The site preset, from `lean/`.

$$\mathrm{sitePreset} = \texttt{../apps/site/src/registry/presets/v2-proved.json}$$ -/
def sitePreset : System.FilePath := ".." / "apps" / "site" / "src" / "registry" / "presets" / "v2-proved.json"

/-- Read and parse a JSON file; a parse error names the path.

$$\operatorname{readJson}(p) = \operatorname{parse}(\operatorname{read}(p))$$ -/
def readJson (p : System.FilePath) : IO Json := do
  IO.ofExcept ((Json.parse (← IO.FS.readFile p)).mapError fun e => s!"{p}: {e}")

/-- Every registered variant: the `part.json` of each directory under the parts directory, directories sorted by
name; a directory without `part.json` is skipped.

$$\operatorname{readRegistry} = \mathop{+\!\!+}_{d \in \operatorname{sort}(\mathrm{partsDir}),\ d/\texttt{part.json} \text{ exists}} \operatorname{parsePart}(\operatorname{readJson}(d/\texttt{part.json}))$$ -/
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
assumes the cases above it do not apply; a file that cannot be read reads as the empty string $\varepsilon$. Here
$P = \operatorname{generate}(R, \Lambda, L)$ and $\mathrm{outs} = [(\mathrm{goldenPreset}, \operatorname{presetText}(P)),\ (\mathrm{sitePreset}, \operatorname{presetText}(P)),\ (\mathrm{goldenDecisions}, \operatorname{decisionsText}(R, L))]$.

$$\operatorname{run}(a) = \begin{cases} \operatorname{throw} & L \text{ or } R \text{ fails to parse, or } \operatorname{generate}(R, \Lambda, L) = \operatorname{error} \\ \operatorname{throw} & \texttt{--check} \in a,\ \exists (p, t) \in \mathrm{outs}:\ \operatorname{read}(p) \ne t \\ \text{no write} & \texttt{--check} \in a,\ \forall (p, t) \in \mathrm{outs}:\ \operatorname{read}(p) = t \\ \operatorname{write}(\mathrm{outs}) & \texttt{--check} \notin a \end{cases}$$ -/
def run (args : List String) : IO Unit := do
  let ledger ← IO.ofExcept ((parseLedger (← readJson ledgerPath)).mapError fun e => s!"{ledgerPath}: {e}")
  let reg ← readRegistry
  let p ← IO.ofExcept (generate reg links ledger)
  let outs := [(goldenPreset, presetText p), (sitePreset, presetText p), (goldenDecisions, decisionsText reg ledger)]
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

end Fw.Preset.Gen
