import Lean.Data.Json
import Fw.Ops.PathCheck
import Fw.Ops.Wire
/-!
# Check map: every tracked file kind has a static check run before commit (task check-map-lean)

Mistake class c-late-check (research/notes/2026/10-18-mistake-retro.md): `apps/site/scripts/shell-measure.mjs` was
committed and landed while it did not parse (`node --check` failed at line 112), because no stage ran `node --check`
on every tracked `.mjs`. This module maps each tracked path to a **kind** (by path prefix, extension or basename) and
each kind to a **static check**; `scripts/checkmap.mjs` (run by `scripts/hooks/pre-commit` on the staged files and by
`scripts/check.sh` on the changed files) asks `fwcore` for the plan (`ops.checkMap`), runs the commands and asks for
the verdict (`ops.checkVerdict`). The runner holds no decision: which file gets which command, and what an exit code
means, are decided here.

A path is classified on its segments `s` (`PathCheck.segs`) and the extension `e` of its last segment (the text after
the last `.`, empty when there is none; `d.ts`/`d.mts`/`d.cts` for a TypeScript declaration file: `extOf`), first
match wins:

| # | condition | kind | check |
|---|---|---|---|
| 1 | `s = []` | none (unmapped) | |
| 2 | `s₀ = snapshot` | `snapshot` (Fastwork's unmodified files) | exempt |
| 3 | `s` under `research/kickoff/` and (`e ∈ {lean, toml}` or basename `lean-toolchain`) | `sketch` (research Lean scratch projects) | exempt |
| 4 | `s = lean/lakefile.toml` or `s = lean/lean-toolchain` | `lakeConfig` | `lake build` |
| 5 | `s₀ = lean`, `e = lean`, under `lean/scripts/` | `leanScript` | `lake env lean <file>` |
| 6 | `s₀ = lean`, `e = lean` otherwise | `leanModule` | `lake build` |
| 7 | under `scripts/hooks/` and `e = ""` | `shell` | `sh -n` |
| 8 | `s = docs/team/work-graph.json` | `workGraph` | schema check (`graphCheck`) |
| 9 | `s = research/findings/ledger.json` | `findingsLedger` | preset `--check` (`presetCheck`) |
| 9a | under `.claude/workflows/`, `e = js` | `workflow` (a workflow body: top-level `return` and `await`, not a module) | body parsed as an `AsyncFunction` (`workflowParse`) |

| 10 | by extension (`byExt`) | see `byExt` | `checkOf` |
| 11 | `e = ""`, by basename (`byName`) | `prose` / `text` | exempt |

The preset check also runs when any other input of `Fw.Preset.Gen` is among the paths (`presetInput`), whatever its own kind, including the Lean modules it imports; a staged deletion of an input (`deleted`, `planStaged`) runs it too.

Proved: `checkOf_exempt_iff` (exactly the five exempt kinds have no check), `precommit_covers` (every path with a code
extension outside the snapshot and the research sketches has a non-exempt check), `tracked_mapped` (every
representative of `git ls-files` at c85c1b6 is mapped), `plan_covers` / `plan_sound` (the plan runs a command of the
file's check on every checked file, and nothing else), `verdict_ok_iff`, `verdict_strict`, `runOk_iff`.
-/
namespace Fw.Ops.CheckMap
open Fw.Ops.PathCheck (segs)

/-- A file kind.

The twenty-one kinds a tracked file can have.
-/
inductive Kind
  | jsMod | ts | tsDecl | tsx | leanModule | leanScript | lakeConfig | json | jsonl | yaml | shell | python | swift
  | workGraph | findingsLedger | workflow
  | snapshot | sketch | asset | prose | text
deriving DecidableEq, Repr

/-- A static check. `exempt`: no check (the kind is not code our tools parse or run).

The fifteen static checks, plus `exempt` for files with none.
-/
inductive Check
  | lakeBuild | leanElab | nodeCheck | tsStrip | tscProject | jsonParse | jsonlParse | yamlParse | shParse | pyParse
  | swiftParse | graphCheck | presetCheck | ledgerNotes | workflowParse | exempt
deriving DecidableEq, Repr

/-- The check of a kind.

Each kind of file is checked by the one static check that parses or builds it, and the five non-code kinds by none.
-/
def checkOf : Kind → Check
  | .jsMod => .nodeCheck | .ts => .tsStrip | .tsDecl => .tscProject | .tsx => .tscProject | .leanModule => .lakeBuild
  | .leanScript => .leanElab | .lakeConfig => .lakeBuild | .json => .jsonParse | .jsonl => .jsonlParse
  | .yaml => .yamlParse | .shell => .shParse | .python => .pyParse | .swift => .swiftParse
  | .workGraph => .graphCheck | .findingsLedger => .presetCheck | .workflow => .workflowParse
  | .snapshot => .exempt | .sketch => .exempt | .asset => .exempt | .prose => .exempt | .text => .exempt

/-- The kinds without a static check. -/
def exemptKinds : List Kind := [.snapshot, .sketch, .asset, .prose, .text]

/-- The kind of an extension (`extOf`).

An extension names its kind, and an unknown extension names none.
-/
def byExt : String → Option Kind
  | "mjs" | "js" | "cjs" => some .jsMod
  | "ts" | "mts" | "cts" => some .ts
  | "d.ts" | "d.mts" | "d.cts" => some .tsDecl
  | "tsx" => some .tsx
  | "json" | "webmanifest" => some .json
  | "jsonl" => some .jsonl
  | "yml" | "yaml" => some .yaml
  | "sh" => some .shell
  | "py" => some .python
  | "swift" => some .swift
  | "lean" => some .leanModule
  | "jpg" | "jpeg" | "png" | "avif" | "webp" | "gif" | "svg" | "ico" | "woff" | "woff2" | "ttf" | "otf" | "gz"
  | "br" => some .asset
  | "md" | "txt" => some .prose
  | "css" | "html" | "patch" | "tsv" | "toml" | "conf" | "gitignore" | "node-version" | "nvmrc" | "npmrc" | "gitattributes" | "dockerignore" => some .text
  | _ => none

/-- The kind of an extensionless basename.

A few known files without an extension have a kind, every other one has none.
-/
def byName : String → Option Kind
  | "LICENSE" | "NOTICE" => some .prose
  | "Dockerfile" | "lean-toolchain" => some .text
  | _ => none

/-- A research sketch: a Lean scratch project file under `research/kickoff/` (built by its own lakefile, not ours).

A path is a sketch exactly when it lies under research/kickoff and is a Lean source, a toml file or a lean-toolchain.
-/
def isSketch (s : List String) (e : String) : Bool :=
  s.take 2 == ["research", "kickoff"] && (e == "lean" || e == "toml" || s.getLast? == some "lean-toolchain")

/-- The kind of a path given as its segments `s` and extension `e` (the table of the module doc, first match wins).

The first matching row of the table gives the kind; a path no row matches has none.
-/
def classifyKey (s : List String) (e : String) : Option Kind :=
  if s.isEmpty then none
  else if s.head? == some "snapshot" then some .snapshot
  else if isSketch s e then some .sketch
  else if s == ["lean", "lakefile.toml"] || s == ["lean", "lean-toolchain"] then some .lakeConfig
  else if s.head? == some "lean" && e == "lean" then
    (if s.take 2 == ["lean", "scripts"] then some .leanScript else some .leanModule)
  else if s.take 2 == ["scripts", "hooks"] && e == "" then some .shell
  else if s == ["docs", "team", "work-graph.json"] then some .workGraph
  else if s == ["research", "findings", "ledger.json"] then some .findingsLedger
  else if s.take 2 == [".claude", "workflows"] && e == "js" then some .workflow
  else match byExt e with
    | some k => some k
    | none => if e == "" then byName (s.getLast?.getD "") else none

/-- The extension of a basename split at `.` into `b_0.b_1.....b_n`: the last part, except that a TypeScript
declaration file (`x.d.ts`, `x.d.mts`, `x.d.cts`) has extension `d.ts` / `d.mts` / `d.cts`; empty when there is no `.`.

The extension is whatever follows the last dot (so `.gitignore` has `gitignore` and `foo.` has the empty one), with the
declaration-file suffixes kept whole.
-/
def extOf (base : String) : String :=
  match (base.splitOn ".").reverse with
  | e :: "d" :: _ :: _ => if e == "ts" || e == "mts" || e == "cts" then "d." ++ e else e
  | e :: _ :: _ => e
  | _ => ""

/-- The kind of a path.

A path's kind is the kind of its segments and the extension of its last segment.
-/
def classify (p : String) : Option Kind :=
  let s := segs p
  classifyKey s (extOf (s.getLast?.getD ""))

/-- The check of a path: none when the path is unmapped or its kind is exempt.

A path gets the check of its kind unless it has no kind or its kind is exempt.
-/
def checkOfPath (p : String) : Option Check :=
  match classify p with
  | some k => if checkOf k = .exempt then none else some (checkOf k)
  | none => none

/-! ## The plan -/

/-- One command of the plan: its check, the directory it runs in (relative to the repository root), its argv and the
files it checks.

A command is a check, a working directory, an argv and the files it covers.
-/
structure Cmd where
  check : Check
  cwd : String
  argv : List String
  files : List String
deriving DecidableEq, Repr

/-- The checks that run, in plan order (`lakeBuild` before `leanElab`, which elaborates against the built modules). -/
def order : List Check :=
  [.lakeBuild, .leanElab, .nodeCheck, .tsStrip, .tscProject, .jsonParse, .jsonlParse, .yamlParse, .shParse, .pyParse,
    .swiftParse, .graphCheck, .presetCheck, .ledgerNotes, .workflowParse]

def heavy : Check → Bool
  | .lakeBuild | .leanElab | .presetCheck => true
  | .nodeCheck | .tsStrip | .tscProject | .jsonParse | .jsonlParse | .yamlParse | .shParse | .pyParse | .swiftParse
  | .graphCheck | .ledgerNotes | .workflowParse | .exempt => false

#guard order.filter heavy == [.lakeBuild, .leanElab, .presetCheck]
#guard !heavy .tscProject && !heavy .exempt

/-- A path relative to `lean/` (its segments without the first, joined by `/`). -/
def rel (p : String) : String := "/".intercalate ((segs p).drop 1)

/-- The package directory of a path: its first two segments joined by `/`. -/
def pkgOf (p : String) : String := "/".intercalate ((segs p).take 2)

/-- The YAML parse program (Ruby's Psych, which ships with macOS and the GitHub runners).

Ruby parses every file named on its command line as YAML.
-/
def yamlProg : String := "ARGV.each { |f| YAML.parse_file(f) }"

/-- Whether a path is an input of the preset generator `Fw.Preset.Gen.run`: the findings ledger, a file of
`packages/contracts/golden/preset/`, a site preset it writes (`v2-proved`, `shipped`), a `part.json` of
`apps/site/src/parts/<part>/`, the generator, or a Lean module the generator imports (`Fw.Preset.V2Proved`, which
imports `Fw.Gate.Trajectory`, and `Fw.Preset.Shipped`).

A path is an input exactly when it is one of the listed places.
-/
def presetInputKey (s : List String) : Bool :=
  s == ["research", "findings", "ledger.json"]
    || (s.take 4 == ["packages", "contracts", "golden", "preset"] && s.length == 5)
    || s == ["apps", "site", "src", "registry", "presets", "v2-proved.json"]
    || s == ["apps", "site", "src", "registry", "presets", "shipped.json"]
    || (s.take 4 == ["apps", "site", "src", "parts"] && s.length == 6 && s.getLast? == some "part.json")
    || s == ["lean", "Fw", "Preset", "Gen.lean"]
    || s == ["lean", "Fw", "Preset", "V2Proved.lean"]
    || s == ["lean", "Fw", "Gate", "Trajectory.lean"]
    || s == ["lean", "Fw", "Preset", "Shipped.lean"]

/-- `presetInputKey` of a path's segments. -/
def presetInput (p : String) : Bool := presetInputKey (segs p)

def ledgerInputKey (s : List String) : Bool := s == ["research", "findings", "ledger.json"]

def ledgerInput (p : String) : Bool := ledgerInputKey (segs p)

/-- The Python parse program (stdlib `ast`; writes no `__pycache__`).

Python parses every file named on its command line without running it.
-/
def pyProg : String := "import ast,sys\nfor f in sys.argv[1:]: ast.parse(open(f,'rb').read(), f)"

/-- The commands of one check over its files `fs` (argv of our own CLI `scripts/checkmap.mjs file <mode>` where no
standard tool parses the file).

Per-file checks get one command per file, project checks one per package, batch checks one for all files, and exempt
none.
-/
def cmdsFor (c : Check) (fs : List String) : List Cmd :=
  match c with
  | .lakeBuild => [⟨c, "lean", ["lake", "build"], fs⟩]
  | .leanElab => fs.map fun f => ⟨c, "lean", ["lake", "env", "lean", rel f], [f]⟩
  | .nodeCheck => fs.map fun f => ⟨c, ".", ["node", "--check", f], [f]⟩
  | .shParse => fs.map fun f => ⟨c, ".", ["sh", "-n", f], [f]⟩
  | .swiftParse => fs.map fun f => ⟨c, ".", ["swiftc", "-parse", f], [f]⟩
  | .tscProject => (fs.map pkgOf).eraseDups.map fun g =>
      ⟨c, ".", ["node", "scripts/checkmap.mjs", "file", "tsc", g], fs.filter (pkgOf · == g)⟩
  | .tsStrip => [⟨c, ".", ["node", "scripts/checkmap.mjs", "file", "ts"] ++ fs, fs⟩]
  | .jsonParse => [⟨c, ".", ["node", "scripts/checkmap.mjs", "file", "json"] ++ fs, fs⟩]
  | .jsonlParse => [⟨c, ".", ["node", "scripts/checkmap.mjs", "file", "jsonl"] ++ fs, fs⟩]
  | .yamlParse => [⟨c, ".", ["ruby", "-ryaml", "-e", yamlProg] ++ fs, fs⟩]
  | .pyParse => [⟨c, ".", ["python3", "-c", pyProg] ++ fs, fs⟩]
  | .graphCheck => [⟨c, ".", ["node", "scripts/checkmap.mjs", "file", "graph"] ++ fs, fs⟩]
  | .presetCheck => [⟨c, ".", ["node", "scripts/checkmap.mjs", "file", "preset"], fs⟩]
  | .ledgerNotes => [⟨c, ".", ["node", "scripts/checkmap.mjs", "file", "ledger"] ++ fs, fs⟩]
  | .workflowParse => [⟨c, ".", ["node", "scripts/checkmap.mjs", "file", "workflow"] ++ fs, fs⟩]
  | .exempt => []

def checkFiles (c : Check) (paths : List String) : List String :=
  if c == .presetCheck then paths.filter (fun p => presetInput p || checkOfPath p == some .presetCheck)
  else if c == .ledgerNotes then paths.filter ledgerInput
  else paths.filter (checkOfPath · == some c)

/-- The plan for the paths `P`: for each check in `order`, the commands over the paths of that check (in their
order); a check with no path gets no command.

Each check runs once over exactly the given paths that need it, in a fixed order.
-/
def plan (paths : List String) : List Cmd :=
  order.flatMap fun c =>
    let fs := checkFiles c paths
    if fs.isEmpty then [] else cmdsFor c fs

/-- The plan of a staged commit: the plan of the staged paths `P` that still exist, where the preset check also takes the
staged deletions `D` that were generator inputs.

A deleted file has no check of its own (nothing to parse), but the preset check must still judge the tree without it.
-/
def planStaged (paths deleted : List String) : List Cmd :=
  order.flatMap fun c =>
    let fs := checkFiles c paths ++ (if c == .presetCheck then deleted.filter presetInput else [])
    if fs.isEmpty then [] else cmdsFor c fs

/-- The unmapped paths: those with no kind, in their order. -/
def unmapped (paths : List String) : List String := paths.filter fun p => (classify p).isNone

/-! ## The verdict -/

/-- The verdict over the exit codes of the plan's commands: every command passed (exit 0), or, unless `strict`, its
tool was not installed (exit 127, the shell's "command not found"; the runner reports a spawn `ENOENT` as 127).

The checks pass when every command exited 0, where a missing tool is forgiven only outside strict mode.
-/
def verdict (strict : Bool) (codes : List Nat) : Bool :=
  codes.all fun x => x == 0 || (!strict && x == 127)

/-- The run's verdict: no path is unmapped and the commands pass (`verdict`). An unmapped path fails the run: a new
file kind must get a rule (and a check) here before it can be committed, which keeps `tracked_mapped` true.

The run passes exactly when no path is unmapped and every command passed.
-/
def runOk (strict : Bool) (unmappedCount : Nat) (codes : List Nat) : Bool :=
  unmappedCount == 0 && verdict strict codes

/-! ## Theorems -/

/-- Exactly the five exempt kinds have no static check.

A kind goes unchecked if and only if it is one of snapshot, sketch, asset, prose or text.
-/
theorem checkOf_exempt_iff (k : Kind) : checkOf k = .exempt ↔ k ∈ exemptKinds := by
  cases k <;> simp [checkOf, exemptKinds]

/-- The extensions of code our tools parse, run or build. -/
def codeExts : List String :=
  ["mjs", "js", "cjs", "ts", "mts", "cts", "d.ts", "d.mts", "d.cts", "tsx", "json", "webmanifest", "jsonl", "yml", "yaml",
    "sh", "py", "swift", "lean"]

/-- Every code extension names a kind with a static check.

Each extension in the code list maps to a kind that has a real check.
-/
theorem byExt_code (e : String) (h : e ∈ codeExts) : ∃ k, byExt e = some k ∧ checkOf k ≠ .exempt := by
  simp only [codeExts, List.mem_cons, List.not_mem_nil, or_false] at h
  rcases h with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    exact ⟨_, rfl, by simp [checkOf]⟩

/-- Pre-commit covers code: every non-empty path with a code extension, outside `snapshot/` and the research sketches,
has a kind whose check is not exempt.

Every source file of a parsed or built kind outside Fastwork's snapshot and the research sketches gets a real check.
-/
theorem precommit_covers (s : List String) (e : String) (hs : s ≠ []) (he : e ∈ codeExts)
    (hsnap : s.head? ≠ some "snapshot") (hsk : isSketch s e = false) :
    ∃ k, classifyKey s e = some k ∧ checkOf k ≠ .exempt := by
  have hsnap' : (s.head? == some "snapshot") = false := by simpa using hsnap
  have hs' : s.isEmpty = false := by simpa using hs
  unfold classifyKey
  simp only [hs', hsnap', hsk, Bool.false_eq_true, ite_false]
  split
  · exact ⟨_, rfl, by simp [checkOf]⟩
  split
  · split <;> exact ⟨_, rfl, by simp [checkOf]⟩
  split
  · exact ⟨_, rfl, by simp [checkOf]⟩
  split
  · exact ⟨_, rfl, by simp [checkOf]⟩
  split
  · exact ⟨_, rfl, by simp [checkOf]⟩
  split
  · exact ⟨_, rfl, by simp [checkOf]⟩
  obtain ⟨k, hk, hc⟩ := byExt_code e he
  exact ⟨k, by simp [hk], hc⟩

/-- One representative path (segments, extension) per distinct (first two directories, extension or basename) of
`git ls-files` at commit c85c1b6 (156 keys); generated, not hand-written. The `docs/plan` `mjs` key names
`check-lean-lessons.mjs`; the file listed at c85c1b6 was deleted.

The frozen list of tracked-file representatives that `tracked_mapped` covers.
-/
def trackedKeys : List (List String × String) := [
  ([".claude", "agents", "checker.md"], "md"),
  ([".claude", "settings.json"], "json"),
  ([".gitattributes"], "gitattributes"),
  ([".github", "README.md"], "md"),
  ([".github", "actionlint.yaml"], "yaml"),
  ([".github", "actions", "gate-engine", "action.yml"], "yml"),
  ([".github", "scripts", "cache-key.mjs"], "mjs"),
  ([".github", "scripts", "check-simulator.sh"], "sh"),
  ([".github", "workflows", "breakpoint-gate.yml"], "yml"),
  ([".gitignore"], "gitignore"),
  ([".mcp.json"], "json"),
  ([".serena", ".gitignore"], "gitignore"),
  ([".serena", "project.yml"], "yml"),
  (["CLAUDE.md"], "md"),
  (["LICENSE"], ""),
  (["NOTICE"], ""),
  (["apps", "console-api", "README.md"], "md"),
  (["apps", "console-api", "package.json"], "json"),
  (["apps", "console-api", "src", "app.ts"], "ts"),
  (["apps", "console-web", "components.json"], "json"),
  (["apps", "console-web", "index.html"], "html"),
  (["apps", "console-web", "src", "App.tsx"], "tsx"),
  (["apps", "console-web", "src", "index.css"], "css"),
  (["apps", "console-web", "src", "lib", "api.ts"], "ts"),
  (["apps", "console-web", "src", "vite-env.d.ts"], "d.ts"),
  (["apps", "runner", "hooks", "cap.d.mts"], "d.mts"),
  (["apps", "runner", "hooks", "cap.mjs"], "mjs"),
  (["apps", "runner", "package.json"], "json"),
  (["apps", "runner", "src", "card.ts"], "ts"),
  (["apps", "runner", "test", "e2e-land.sh"], "sh"),
  (["apps", "site", "README.md"], "md"),
  (["apps", "site", "index.html"], "html"),
  (["apps", "site", "package.json"], "json"),
  (["apps", "site", "scripts", "build.mjs"], "mjs"),
  (["apps", "site", "scripts", "census-hooks.js"], "js"),
  (["apps", "site", "src", "App.tsx"], "tsx"),
  (["apps", "site", "src", "breakpoints.ts"], "ts"),
  (["apps", "site", "src", "globals.d.ts"], "d.ts"),
  (["apps", "site", "src", "parts", "commission", "box.module.css"], "css"),
  (["docs", "plan", "PLAN.md"], "md"),
  (["docs", "plan", "loop-plan.html"], "html"),
  (["docs", "plan", "tools", "check-lean-lessons.mjs"], "mjs"),
  (["docs", "report", "v2-report.md"], "md"),
  (["docs", "team", "handoffs", "alert-steps.md"], "md"),
  (["docs", "team", "incidents", "ledger.json"], "json"),
  (["docs", "team", "tools", "agent-idle.py"], "py"),
  (["docs", "team", "tools", "load-sample.sh"], "sh"),
  (["lean", ".gitignore"], "gitignore"),
  (["lean", ".serena", ".gitignore"], "gitignore"),
  (["lean", ".serena", "project.yml"], "yml"),
  (["lean", "BreakgenMain.lean"], "lean"),
  (["lean", "Fw", "Board.lean"], "lean"),
  (["lean", "Fw", "Site", "README.md"], "md"),
  (["lean", "Fw", "Site", "breakpoints.gen.json"], "json"),
  (["lean", "FwTest", "CiBudget.lean"], "lean"),
  (["lean", "FwTest", "Mutants", "Console", "I-059-done-without-start.patch"], "patch"),
  (["lean", "FwTest", "Mutants", "equivalent.tsv"], "tsv"),
  (["lean", "FwTest", "Mutants", "gen.mjs"], "mjs"),
  (["lean", "README.md"], "md"),
  (["lean", "golden", "console-apply.jsonl"], "jsonl"),
  (["lean", "golden", "wire-replies.txt"], "txt"),
  (["lean", "lake-manifest.json"], "json"),
  (["lean", "lakefile.toml"], "toml"),
  (["lean", "lean-toolchain"], ""),
  (["lean", "scripts", "AlignEquivGolden.lean"], "lean"),
  (["lean", "scripts", "check-fast.sh"], "sh"),
  (["lean", "scripts", "check-imports.mjs"], "mjs"),
  (["packages", "contracts", "fixtures", "commands.golden.json"], "json"),
  (["packages", "contracts", "golden", "ci-budget", "fixtures", "bare-429.jsonl"], "jsonl"),
  (["packages", "contracts", "scripts", "gen-json-schema.ts"], "ts"),
  (["packages", "difftest", ".gitignore"], "gitignore"),
  (["packages", "difftest", "package.json"], "json"),
  (["packages", "difftest", "src", "arb.mjs"], "mjs"),
  (["packages", "gate-breakpoints", ".gitignore"], "gitignore"),
  (["packages", "gate-breakpoints", "README.md"], "md"),
  (["packages", "gate-breakpoints", "package.json"], "json"),
  (["packages", "gate-breakpoints", "scripts", "golden-cases.mjs"], "mjs"),
  (["packages", "gate-breakpoints", "src", "gaps", "wkzoom.swift"], "swift"),
  (["packages", "gh-budget", "package.json"], "json"),
  (["packages", "gh-budget", "src", "charged.ts"], "ts"),
  (["packages", "gh-budget", "test", "core-worker.mjs"], "mjs"),
  (["packages", "measure-chromium", ".dockerignore"], "dockerignore"),
  (["packages", "measure-chromium", ".gitignore"], "gitignore"),
  (["packages", "measure-chromium", "Dockerfile"], ""),
  (["packages", "measure-chromium", "README.md"], "md"),
  (["packages", "measure-chromium", "classes.frozen.json"], "json"),
  (["packages", "measure-chromium", "docker", "apt-manifest.txt"], "txt"),
  (["packages", "measure-chromium", "docker", "fonts.conf"], "conf"),
  (["packages", "measure-chromium", "fixtures", "anim-compositor", "index.html"], "html"),
  (["packages", "measure-chromium", "src", "classes.mjs"], "mjs"),
  (["packages", "measure-chromium", "src", "clock-shim.js"], "js"),
  (["packages", "measure-chromium", "src", "image-check.sh"], "sh"),
  (["packages", "measure-webkit", ".gitignore"], "gitignore"),
  (["packages", "measure-webkit", "README.md"], "md"),
  (["packages", "measure-webkit", "classes", "webkit-sim-v1.json"], "json"),
  (["packages", "measure-webkit", "fixtures", "seek.html"], "html"),
  (["packages", "measure-webkit", "scripts", "site-lane.sh"], "sh"),
  (["packages", "measure-webkit", "src", "align.mjs"], "mjs"),
  (["packages", "measure-wktr", "README.md"], "md"),
  (["packages", "measure-wktr", "classes.frozen.json"], "json"),
  (["packages", "measure-wktr", "fixtures", "control", "index.html"], "html"),
  (["packages", "measure-wktr", "fixtures", "lanes.mjs"], "mjs"),
  (["packages", "measure-wktr", "fixtures", "premises.sh"], "sh"),
  (["packages", "premise-tests", ".gitignore"], "gitignore"),
  (["packages", "premise-tests", "package.json"], "json"),
  (["packages", "premise-tests", "pages", "anim.list.html"], "html"),
  (["packages", "premise-tests", "src", "run.mjs"], "mjs"),
  (["packages", "snapshot-extract", "package.json"], "json"),
  (["packages", "snapshot-extract", "src", "cli.mjs"], "mjs"),
  (["packages", "visual-diff", "package.json"], "json"),
  (["packages", "visual-diff", "src", "assets.mjs"], "mjs"),
  (["pnpm-lock.yaml"], "yaml"),
  (["refs", "upstream", "PINS.md"], "md"),
  (["refs", "upstream", "sources.lock.yaml"], "yaml"),
  (["research", "findings", "ledger.json"], "json"),
  (["research", "kickoff", "01-prior-loop-lessons.md"], "md"),
  (["research", "kickoff", "05-lean-sketch", ".gitignore"], "gitignore"),
  (["research", "kickoff", "05-lean-sketch", "Fw.lean"], "lean"),
  (["research", "kickoff", "05-lean-sketch", "lake-manifest.json"], "json"),
  (["research", "kickoff", "05-lean-sketch", "lakefile.toml"], "toml"),
  (["research", "kickoff", "05-lean-sketch", "lean-toolchain"], ""),
  (["research", "kickoff", "10-automation-and-proof", "lean-scratch", "03-inventory", "Bench-shared-ref.lean.txt"], "txt"),
  (["research", "kickoff", "10-automation-and-proof", "lean-scratch", "03-inventory", "bench-roundtrip.mjs"], "mjs"),
  (["research", "kickoff", "10-automation-and-proof", "math-view-sample.html"], "html"),
  (["research", "kickoff", "10-automation-and-proof", "scripts", "agg.py"], "py"),
  (["research", "mistakes", "ledger.json"], "json"),
  (["research", "notes", "2026", "10-17-agent-observability-sources.md"], "md"),
  (["results", "baselines", "chromium", "README.md"], "md"),
  (["results", "baselines", "chromium", "swipe-touch-v1", "original.baseline.json"], "json"),
  (["results", "phone", "2026-10-17-s1", "README.md"], "md"),
  (["results", "phone", "2026-10-17-s1", "counts-compare.json"], "json"),
  (["results", "variant-regate.md"], "md"),
  (["scripts", "ci-paths.mjs"], "mjs"),
  (["scripts", "hooks", "pre-commit"], ""),
  (["scripts", "scrub-allow.json"], "json"),
  (["scripts", "sim-lock.sh"], "sh"),
  (["snapshot", "README.md"], "md"),
  (["snapshot", "site", ".mirror", "crawl.json"], "json"),
  (["snapshot", "site", ".mirror", "robots.txt"], "txt"),
  (["snapshot", "site", "__vendor", "cdn.amplitude.com", "libs", "analytics-browser-gtm-2.45.3-min.js.gz"], "gz"),
  (["snapshot", "site", "__vendor", "cdn.amplitude.com", "libs", "analytics-browser-gtm-wrapper-2.45.3.min.js.br"], "br"),
  (["snapshot", "site", "__vendor", "script.hotjar.com", "browser-perf.8417c6bba72228fa2e29.js"], "js"),
  (["snapshot", "site", "__vendor", "static.cloudflareinsights.com", "beacon.min.js", "v31edd6df95cf4e85bb4c19e7a9bdbcba1788362987495"], ""),
  (["snapshot", "site", "__vendor", "static.hotjar.com", "c", "hotjar-6772436.js.__q_f615f550be"], "__q_f615f550be"),
  (["snapshot", "site", "__vendor", "www.googletagmanager.com", "gtag", "js.__q_218232fe7c"], "__q_218232fe7c"),
  (["snapshot", "site", "__vendor", "www.googletagmanager.com", "gtm.js.__q_141790bd5c"], "__q_141790bd5c"),
  (["snapshot", "site", "_app", "immutable", "assets", "0.ChGpbVhU.css"], "css"),
  (["snapshot", "site", "_app", "immutable", "assets", "google-sans-latin-italic.XUjF_20c.woff2"], "woff2"),
  (["snapshot", "site", "apple-touch-icon.png"], "png"),
  (["snapshot", "site", "favicon.ico"], "ico"),
  (["snapshot", "site", "favicon.svg"], "svg"),
  (["snapshot", "site", "fonts", "fastwork-Bold.ttf"], "ttf"),
  (["snapshot", "site", "index.html"], "html"),
  (["snapshot", "site", "selling", "commission", "avatar-john.jpg"], "jpg"),
  (["snapshot", "site", "selling", "optimized", "external", "lawyer-consult-cover-240.avif"], "avif"),
  (["snapshot", "site", "site.webmanifest"], "webmanifest")
]

/-- Every tracked representative is mapped.

Each of the 156 representative tracked paths falls in some kind; `scripts/check.sh --tracked` checks the live tree.
-/
theorem tracked_mapped : ∀ x ∈ trackedKeys, (classifyKey x.1 x.2).isSome = true := by decide +kernel

/-- Every non-exempt check is in the plan order.

No real check is left out of the plan order.
-/
theorem mem_order (c : Check) (h : c ≠ .exempt) : c ∈ order := by
  cases c <;> simp_all [order]

/-- The commands of a non-exempt check cover every one of its files.

Every file handed to a real check is checked by one of that check's commands.
-/
theorem cmdsFor_covers (c : Check) (fs : List String) (f : String) (hc : c ≠ .exempt) (hf : f ∈ fs) :
    ∃ m ∈ cmdsFor c fs, m.check = c ∧ f ∈ m.files := by
  cases c <;> simp only [cmdsFor] <;> try contradiction
  all_goals first
    | exact ⟨_, List.mem_cons_self .., rfl, hf⟩
    | exact ⟨_, List.mem_map_of_mem hf, rfl, List.mem_singleton_self _⟩
    | exact ⟨_, List.mem_map_of_mem (List.mem_eraseDups.mpr (List.mem_map_of_mem hf)), rfl, by simp [hf]⟩

/-- The commands of a check check nothing but its files.

A check's commands carry that check and only files it was handed.
-/
theorem cmdsFor_sound (c : Check) (fs : List String) (m : Cmd) (hm : m ∈ cmdsFor c fs) :
    m.check = c ∧ ∀ f ∈ m.files, f ∈ fs := by
  cases c <;> simp [cmdsFor] at hm
  all_goals first
    | (rcases hm with rfl | rfl <;> exact ⟨rfl, fun _ h => h⟩)
    | (subst hm; exact ⟨rfl, fun _ h => h⟩)
    | (obtain ⟨f, hf, rfl⟩ := hm; exact ⟨rfl, fun _ h => by simp at h; subst h; exact hf⟩)
    | (obtain ⟨g, _, rfl⟩ := hm; exact ⟨rfl, fun _ h => (List.mem_filter.mp h).1⟩)

/-- No path's check is `exempt` (an exempt kind gives no check at all).

A path either has a real check or none.
-/
theorem checkOfPath_ne_exempt (p : String) : checkOfPath p ≠ some .exempt := by
  unfold checkOfPath
  split
  · rename_i k _; by_cases h : checkOf k = .exempt <;> simp [h]
  · simp

theorem checkOf_ne_ledgerNotes (k : Kind) : checkOf k ≠ .ledgerNotes := by
  cases k <;> simp [checkOf]

theorem checkOfPath_ne_ledgerNotes (p : String) : checkOfPath p ≠ some .ledgerNotes := by
  unfold checkOfPath
  split
  · rename_i k _; by_cases h : checkOf k = .exempt <;> simp [h, checkOf_ne_ledgerNotes k]
  · simp

/-- The plan covers: every given path that has a check gets a command of that check over it.

No checked file is skipped: the plan always runs its check on it.
-/
theorem plan_covers (paths : List String) (p : String) (hp : p ∈ paths) (c : Check) (hc : checkOfPath p = some c) :
    ∃ m ∈ plan paths, m.check = c ∧ p ∈ m.files := by
  have hne : c ≠ .exempt := by rintro rfl; exact checkOfPath_ne_exempt p hc
  have hf : p ∈ checkFiles c paths := by
    unfold checkFiles
    split
    · rename_i h
      have : c = .presetCheck := by simpa using h
      subst this
      exact List.mem_filter.mpr ⟨hp, by simp [hc]⟩
    · split
      · rename_i h2
        have : c = .ledgerNotes := by simpa using h2
        subst this
        exact absurd hc (checkOfPath_ne_ledgerNotes p)
      · exact List.mem_filter.mpr ⟨hp, by simp [hc]⟩
  obtain ⟨m, hm, h1, h2⟩ := cmdsFor_covers c _ p hne hf
  refine ⟨m, List.mem_flatMap.mpr ⟨c, mem_order c hne, ?_⟩, h1, h2⟩
  have : (checkFiles c paths).isEmpty = false := by
    cases h : checkFiles c paths with
    | nil => rw [h] at hf; cases hf
    | cons _ _ => rfl
  simp only [this, Bool.false_eq_true, ite_false]
  exact hm

/-- The plan is sound: every file a command checks is a given path, and either its check is the command's or the
command is the preset check and the file is a generator input, or the command is the ledger-notes check and the file is
the findings ledger.

The plan never checks a file it was not given, and never with a check other than the file's own, except that the
preset check also takes the generator's other inputs and the ledger-notes check takes the findings ledger.
-/
theorem plan_sound (paths : List String) (m : Cmd) (hm : m ∈ plan paths) (f : String) (hf : f ∈ m.files) :
    f ∈ paths ∧ (checkOfPath f = some m.check ∨ (m.check = .presetCheck ∧ presetInput f = true)
      ∨ (m.check = .ledgerNotes ∧ ledgerInput f = true)) := by
  obtain ⟨c, _, hc⟩ := List.mem_flatMap.mp hm
  dsimp only at hc
  split at hc
  · cases hc
  · obtain ⟨h1, h2⟩ := cmdsFor_sound c _ m hc
    have hmem := h2 f hf
    unfold checkFiles at hmem
    split at hmem
    · rename_i h
      have : c = .presetCheck := by simpa using h
      have := List.mem_filter.mp hmem
      have hc : c = .presetCheck := by simpa using h
      have hor := this.2
      simp only [Bool.or_eq_true, beq_iff_eq] at hor
      rcases hor with hi | hi
      · exact ⟨this.1, Or.inr (Or.inl ⟨by rw [h1]; exact hc, hi⟩)⟩
      · exact ⟨this.1, Or.inl (by rw [h1, hc]; exact hi)⟩
    · split at hmem
      · rename_i h
        have hc' : c = .ledgerNotes := by simpa using h
        have := List.mem_filter.mp hmem
        exact ⟨this.1, Or.inr (Or.inr ⟨by rw [h1]; exact hc', this.2⟩)⟩
      · have := List.mem_filter.mp hmem
        exact ⟨this.1, Or.inl (by rw [h1]; simpa using this.2)⟩

/-- Every generator input among the paths runs the preset check on it.

A staged add or change of any input of `Fw.Preset.Gen` runs `Fw.Preset.Gen.run --check`.
-/
theorem presetInput_planned (paths : List String) (p : String) (hp : p ∈ paths) (hi : presetInput p = true) :
    ∃ m ∈ plan paths, m.check = .presetCheck ∧ p ∈ m.files := by
  have hf : p ∈ checkFiles .presetCheck paths := by
    unfold checkFiles
    simp only [beq_self_eq_true, ite_true]
    exact List.mem_filter.mpr ⟨hp, by simp [hi]⟩
  obtain ⟨m, hm, h1, h2⟩ := cmdsFor_covers .presetCheck _ p (by decide) hf
  refine ⟨m, List.mem_flatMap.mpr ⟨.presetCheck, mem_order .presetCheck (by decide), ?_⟩, h1, h2⟩
  have : (checkFiles .presetCheck paths).isEmpty = false := by
    cases h : checkFiles .presetCheck paths with
    | nil => rw [h] at hf; cases hf
    | cons _ _ => rfl
  simp only [this, Bool.false_eq_true, ite_false]
  exact hm

theorem ledgerInput_ledger : ledgerInputKey ["research", "findings", "ledger.json"] = true := by decide +kernel

theorem ledgerInput_not :
    ledgerInputKey ["docs", "team", "incidents", "ledger.json"] = false ∧ ledgerInputKey ["research", "mistakes", "ledger.json"] = false
    ∧ ledgerInputKey ["research", "findings", "other.json"] = false ∧ ledgerInputKey ["apps", "runner", "test", "ledger-merge.test.ts"] = false := by
  decide +kernel

theorem ledgerInput_planned (paths : List String) (p : String) (hp : p ∈ paths) (hi : ledgerInput p = true) :
    ∃ m ∈ plan paths, m.check = .ledgerNotes ∧ p ∈ m.files := by
  have hf : p ∈ checkFiles .ledgerNotes paths := by
    unfold checkFiles
    simp only [beq_iff_eq, reduceCtorEq, ite_false, ite_true]
    exact List.mem_filter.mpr ⟨hp, hi⟩
  obtain ⟨m, hm, h1, h2⟩ := cmdsFor_covers .ledgerNotes _ p (by decide) hf
  refine ⟨m, List.mem_flatMap.mpr ⟨.ledgerNotes, mem_order .ledgerNotes (by decide), ?_⟩, h1, h2⟩
  have : (checkFiles .ledgerNotes paths).isEmpty = false := by
    cases h : checkFiles .ledgerNotes paths with
    | nil => rw [h] at hf; cases hf
    | cons _ _ => rfl
  simp only [this, Bool.false_eq_true, ite_false]
  exact hm

theorem ledgerInput_planStaged (paths deleted : List String) (p : String) (hp : p ∈ paths) (hi : ledgerInput p = true) :
    ∃ m ∈ planStaged paths deleted, m.check = .ledgerNotes ∧ p ∈ m.files := by
  have hf : p ∈ checkFiles .ledgerNotes paths := by
    unfold checkFiles
    simp only [beq_iff_eq, reduceCtorEq, ite_false, ite_true]
    exact List.mem_filter.mpr ⟨hp, hi⟩
  have hg : p ∈ checkFiles .ledgerNotes paths ++ (if (Check.ledgerNotes == .presetCheck) = true then deleted.filter presetInput else []) := by
    simp only [beq_iff_eq, reduceCtorEq, ite_false, List.append_nil]
    exact hf
  obtain ⟨m, hm, h1, h2⟩ := cmdsFor_covers .ledgerNotes _ p (by decide) hg
  refine ⟨m, List.mem_flatMap.mpr ⟨.ledgerNotes, mem_order .ledgerNotes (by decide), ?_⟩, h1, h2⟩
  have : (checkFiles .ledgerNotes paths ++ (if (Check.ledgerNotes == .presetCheck) = true then deleted.filter presetInput else [])).isEmpty = false := by
    cases h : (checkFiles .ledgerNotes paths ++ (if (Check.ledgerNotes == .presetCheck) = true then deleted.filter presetInput else [])) with
    | nil => rw [h] at hg; cases hg
    | cons _ _ => rfl
  simp only [beq_iff_eq, reduceCtorEq, ite_false, List.append_nil] at this hm ⊢
  simp only [this, Bool.false_eq_true, ite_false]
  exact hm

theorem findingsLedger_planned (paths deleted : List String) (h : "research/findings/ledger.json" ∈ paths) :
    (∃ m ∈ plan paths, m.check = .ledgerNotes ∧ "research/findings/ledger.json" ∈ m.files)
    ∧ ∃ m ∈ planStaged paths deleted, m.check = .ledgerNotes ∧ "research/findings/ledger.json" ∈ m.files := by
  have hi : ledgerInput "research/findings/ledger.json" = true := by
    have e : segs "research/findings/ledger.json" = ["research", "findings", "ledger.json"] := by
      simp (config := {decide := true}) [segs, String.splitOn, String.splitOnAux]
    unfold ledgerInput
    rw [e]
    exact ledgerInput_ledger
  exact ⟨ledgerInput_planned paths _ h hi, ledgerInput_planStaged paths deleted _ h hi⟩

theorem ledgerNotes_cmd (fs : List String) :
    cmdsFor .ledgerNotes fs = [⟨.ledgerNotes, ".", ["node", "scripts/checkmap.mjs", "file", "ledger"] ++ fs, fs⟩] := rfl

/-- A staged deletion of a generator input runs the preset check.

Deleting `part.json`, a golden preset file, the ledger or a generator module cannot slip past the check.
-/
theorem presetInput_deleted_planned (paths deleted : List String) (p : String) (hp : p ∈ deleted) (hi : presetInput p = true) :
    ∃ m ∈ planStaged paths deleted, m.check = .presetCheck ∧ p ∈ m.files := by
  have hf : p ∈ checkFiles .presetCheck paths ++ (if (Check.presetCheck == .presetCheck) = true then deleted.filter presetInput else []) := by
    simp only [beq_self_eq_true, ite_true]
    exact List.mem_append_right _ (List.mem_filter.mpr ⟨hp, hi⟩)
  obtain ⟨m, hm, h1, h2⟩ := cmdsFor_covers .presetCheck _ p (by decide) hf
  refine ⟨m, List.mem_flatMap.mpr ⟨.presetCheck, mem_order .presetCheck (by decide), ?_⟩, h1, h2⟩
  have : (checkFiles .presetCheck paths ++ (if (Check.presetCheck == .presetCheck) = true then deleted.filter presetInput else [])).isEmpty = false := by
    cases h : (checkFiles .presetCheck paths ++ (if (Check.presetCheck == .presetCheck) = true then deleted.filter presetInput else [])) with
    | nil => rw [h] at hf; cases hf
    | cons _ _ => rfl
  simp only [beq_self_eq_true, ite_true] at this ⊢
  simp only [this, Bool.false_eq_true, ite_false]
  exact hm

/-- A staged add or change of a generator input runs the preset check, also with staged deletions.

Whatever `deleted` holds, an input in `paths` is in the preset command of `planStaged`.
-/
theorem presetInput_planStaged (paths deleted : List String) (p : String) (hp : p ∈ paths) (hi : presetInput p = true) :
    ∃ m ∈ planStaged paths deleted, m.check = .presetCheck ∧ p ∈ m.files := by
  have hf : p ∈ checkFiles .presetCheck paths ++ (if (Check.presetCheck == .presetCheck) = true then deleted.filter presetInput else []) := by
    have h0 : p ∈ checkFiles .presetCheck paths := by
      unfold checkFiles
      simp only [beq_self_eq_true, ite_true]
      exact List.mem_filter.mpr ⟨hp, by simp [hi]⟩
    exact List.mem_append_left _ h0
  obtain ⟨m, hm, h1, h2⟩ := cmdsFor_covers .presetCheck _ p (by decide) hf
  refine ⟨m, List.mem_flatMap.mpr ⟨.presetCheck, mem_order .presetCheck (by decide), ?_⟩, h1, h2⟩
  have : (checkFiles .presetCheck paths ++ (if (Check.presetCheck == .presetCheck) = true then deleted.filter presetInput else [])).isEmpty = false := by
    cases h : (checkFiles .presetCheck paths ++ (if (Check.presetCheck == .presetCheck) = true then deleted.filter presetInput else [])) with
    | nil => rw [h] at hf; cases hf
    | cons _ _ => rfl
  simp only [beq_self_eq_true, ite_true] at this ⊢
  simp only [this, Bool.false_eq_true, ite_false]
  exact hm

/-- A staged deletion of a file that is not a generator input changes nothing.

An unrelated deletion leaves the plan as it was.
-/
theorem planStaged_not_input (paths deleted : List String) (h : ∀ p ∈ deleted, presetInput p = false) :
    planStaged paths deleted = plan paths := by
  have : deleted.filter presetInput = [] := List.filter_eq_nil_iff.mpr (by simpa using h)
  simp [planStaged, plan, this]

/-- The work graph is routed to the schema check, not to a plain JSON parse.

A commit that stages `docs/team/work-graph.json` runs the graph schema check.
-/
theorem workGraph_routed : (classifyKey ["docs", "team", "work-graph.json"] "json").map checkOf = some .graphCheck := by
  decide +kernel

/-- The findings ledger is routed to the preset check, so a ledger change that leaves `golden/preset/*` stale is refused.

A commit that stages `research/findings/ledger.json` runs `Fw.Preset.Gen.run --check` from `lean/`.
-/
theorem findingsLedger_routed :
    (classifyKey ["research", "findings", "ledger.json"] "json").map checkOf = some .presetCheck := by
  decide +kernel

/-- The incident ledger beside it keeps the plain JSON parse (the routing is by exact path).

Only the findings ledger runs the preset check.
-/
theorem incidentLedger_plain :
    (classifyKey ["docs", "team", "incidents", "ledger.json"] "json").map checkOf = some .jsonParse := by
  decide +kernel

/-- A workflow script is routed to the body parse, not to `node --check` (which reads it as a module and refuses its
top-level `return` on node 24.22).

A commit that stages a `.claude/workflows/*.js` file runs `checkmap file workflow` on it.
-/
theorem workflow_routed (n : String) :
    (classifyKey [".claude", "workflows", n] "js").map checkOf = some .workflowParse := by
  simp [classifyKey, isSketch, checkOf]

/-- The workflow check is `checkmap file workflow` over the files it was given.

Its one command parses every given workflow body.
-/
theorem workflowParse_cmd (fs : List String) :
    cmdsFor .workflowParse fs = [⟨.workflowParse, ".", ["node", "scripts/checkmap.mjs", "file", "workflow"] ++ fs, fs⟩] := rfl

/-- The preset check is `checkmap file preset` over the files it was given.

Its one command is the runner's preset mode (which judges the index tree when staged) over exactly the given files.
-/
theorem presetCheck_cmd (fs : List String) :
    cmdsFor .presetCheck fs = [⟨.presetCheck, ".", ["node", "scripts/checkmap.mjs", "file", "preset"], fs⟩] := rfl

/-- The ledger is a generator input (branch 1).

Staging the findings ledger runs the preset check. -/
theorem presetInput_ledger : presetInputKey ["research", "findings", "ledger.json"] = true := by decide +kernel

/-- A golden preset file is a generator input (branch 2).

Staging a file of `packages/contracts/golden/preset/` runs the preset check. -/
theorem presetInput_golden : presetInputKey ["packages", "contracts", "golden", "preset", "v2-proved.decisions.jsonl"] = true := by
  decide +kernel

/-- The site preset is a generator input (branch 3).

Staging `apps/site/src/registry/presets/v2-proved.json` runs the preset check. -/
theorem presetInput_site : presetInputKey ["apps", "site", "src", "registry", "presets", "v2-proved.json"] = true := by decide +kernel

theorem presetInput_site_shipped : presetInputKey ["apps", "site", "src", "registry", "presets", "shipped.json"] = true := by
  decide +kernel

/-- A part's `part.json` is a generator input (branch 4).

Staging `apps/site/src/parts/<part>/part.json` runs the preset check. -/
theorem presetInput_part : presetInputKey ["apps", "site", "src", "parts", "hero", "part.json"] = true := by decide +kernel

/-- The generator itself is a generator input (branch 5).

Staging `lean/Fw/Preset/Gen.lean` runs the preset check. -/
theorem presetInput_gen : presetInputKey ["lean", "Fw", "Preset", "Gen.lean"] = true := by decide +kernel

/-- A Lean module the generator imports is a generator input (branch 6).

Staging `lean/Fw/Preset/V2Proved.lean` runs the preset check. -/
theorem presetInput_v2proved : presetInputKey ["lean", "Fw", "Preset", "V2Proved.lean"] = true := by decide +kernel

/-- The module `Fw.Preset.V2Proved` imports is a generator input (branch 7).

Staging `lean/Fw/Gate/Trajectory.lean` runs the preset check. -/
theorem presetInput_trajectory : presetInputKey ["lean", "Fw", "Gate", "Trajectory.lean"] = true := by decide +kernel

theorem presetInput_shipped : presetInputKey ["lean", "Fw", "Preset", "Shipped.lean"] = true := by decide +kernel

/-- Other preset-named files are not inputs (the incident ledger, another preset, a part's other files).

The trigger is exact, not a prefix guess. -/
theorem presetInput_not :
    presetInputKey ["docs", "team", "incidents", "ledger.json"] = false ∧ presetInputKey ["apps", "site", "src", "registry", "presets", "original.json"] = false
    ∧ presetInputKey ["apps", "site", "src", "parts", "hero", "index.tsx"] = false ∧ presetInputKey ["packages", "contracts", "golden", "ops", "checkmap.jsonl"] = false
    ∧ presetInputKey ["lean", "Fw", "Preset", "Other.lean"] = false := by
  decide +kernel

/-- The graph check covers the graph files it was given.

Its one command is `checkmap file graph` over exactly the given files.
-/
theorem graphCheck_cmd (fs : List String) :
    cmdsFor .graphCheck fs = [⟨.graphCheck, ".", ["node", "scripts/checkmap.mjs", "file", "graph"] ++ fs, fs⟩] := rfl

/-- The verdict, unfolded.

The checks pass exactly when each exit code is 0, or 127 (tool missing) outside strict mode.
-/
theorem verdict_ok_iff (strict : Bool) (codes : List Nat) :
    verdict strict codes = true ↔ ∀ x ∈ codes, x = 0 ∨ (strict = false ∧ x = 127) := by
  simp [verdict]

/-- Strict mode passes only when every command exited 0.

With strict on, a missing tool fails the checks like a failed command.
-/
theorem verdict_strict (codes : List Nat) : verdict true codes = true ↔ ∀ x ∈ codes, x = 0 := by
  simp [verdict]

/-- The run's verdict, unfolded.

A run passes exactly when nothing is unmapped and each exit code is 0, or 127 outside strict mode.
-/
theorem runOk_iff (strict : Bool) (u : Nat) (codes : List Nat) :
    runOk strict u codes = true ↔ u = 0 ∧ ∀ x ∈ codes, x = 0 ∨ (strict = false ∧ x = 127) := by
  simp [runOk, verdict]

/-! ## Examples -/

#guard extOf "a.mjs" == "mjs" && extOf ".gitignore" == "gitignore" && extOf "foo." == "" && extOf "LICENSE" == ""
#guard extOf "a.b.jsonl" == "jsonl" && extOf "cap.d.mts" == "d.mts" && extOf "d.ts" == "ts" && extOf "a.d.json" == "json"
#guard classify "apps/runner/hooks/cap.d.mts" == some .tsDecl && checkOfPath "apps/runner/hooks/cap.d.mts" == some .tscProject
#guard classify "apps/site/scripts/shell-measure.mjs" == some .jsMod
#guard classify "snapshot/site/__vendor/a/gtm.js.__q_141790bd5c" == some .snapshot
#guard classify "snapshot/site/x.js" == some .snapshot
#guard classify "research/kickoff/05-lean-sketch/Fw.lean" == some .sketch
#guard classify "research/kickoff/05-lean-sketch/lean-toolchain" == some .sketch
#guard classify "research/kickoff/x.json" == some .json
#guard classify "lean/lakefile.toml" == some .lakeConfig && classify "lean/lean-toolchain" == some .lakeConfig
#guard classify "lean/scripts/OpsGolden.lean" == some .leanScript
#guard classify "lean/Fw/Ops/CheckMap.lean" == some .leanModule && classify "lean/Main.lean" == some .leanModule
#guard classify "scripts/hooks/pre-commit" == some .shell && classify "scripts/wt-prep.sh" == some .shell
#guard classify "apps/site/src/a.tsx" == some .tsx && classify "apps/runner/src/fw.ts" == some .ts
#guard classify "LICENSE" == some .prose && classify "packages/measure-chromium/Dockerfile" == some .text
#guard classify "docs/team/work-graph.json" == some .workGraph && checkOfPath "docs/team/work-graph.json" == some .graphCheck
#guard classify "research/findings/ledger.json" == some .findingsLedger && checkOfPath "research/findings/ledger.json" == some .presetCheck
#guard classify "docs/team/incidents/ledger.json" == some .json
#guard classify ".claude/workflows/build-review.js" == some .workflow && checkOfPath ".claude/workflows/build-review.js" == some .workflowParse
#guard classify ".claude/agents/x.md" == some .prose && classify ".claude/workflows/x.json" == some .json
#guard (plan [".claude/workflows/build-review.js", "a.mjs"]).map (·.argv) ==
  [["node", "--check", "a.mjs"], ["node", "scripts/checkmap.mjs", "file", "workflow", ".claude/workflows/build-review.js"]]
#guard (plan ["docs/team/work-graph.json", "a.json"]).map (·.argv) ==
  [["node", "scripts/checkmap.mjs", "file", "json", "a.json"], ["node", "scripts/checkmap.mjs", "file", "graph", "docs/team/work-graph.json"]]
#guard (plan ["research/findings/ledger.json"]).map (·.argv) ==
  [["node", "scripts/checkmap.mjs", "file", "preset"], ["node", "scripts/checkmap.mjs", "file", "ledger", "research/findings/ledger.json"]]
#guard (plan ["research/mistakes/ledger.json", "docs/team/incidents/ledger.json"]).map (·.check) == [.jsonParse]
#guard (planStaged ["a.mjs"] ["research/findings/ledger.json"]).map (·.check) == [.nodeCheck, .presetCheck]
#guard (plan ["research/findings/ledger.json", "packages/contracts/golden/preset/v2-proved.json"]).map (·.check) == [.jsonParse, .presetCheck, .ledgerNotes]
#guard (plan ["apps/site/src/parts/hero/part.json"]).map (·.check) == [.jsonParse, .presetCheck]
#guard (plan ["lean/Fw/Preset/Gen.lean"]).map (·.check) == [.lakeBuild, .presetCheck]
#guard (plan ["apps/site/src/registry/presets/v2-proved.json", "packages/contracts/golden/preset/v2-proved.decisions.jsonl"]).map (·.check) ==
  [.jsonParse, .jsonlParse, .presetCheck]
#guard (plan ["apps/site/src/registry/presets/original.json"]).map (·.check) == [.jsonParse]
#guard classify "x.unknownext" == none && classify "" == none && classify "Makefile" == none
#guard checkOfPath "docs/plan/PLAN.md" == none && checkOfPath "a.json" == some .jsonParse
#guard checkOfPath "x.unknownext" == none
#guard unmapped ["a.mjs", "b.zzz", "snapshot/x", "Makefile"] == ["b.zzz", "Makefile"]
#guard plan ["a.mjs", "b.md"] == [⟨.nodeCheck, ".", ["node", "--check", "a.mjs"], ["a.mjs"]⟩]
#guard plan [] == []
#guard plan ["a.json", "b.json"] ==
  [⟨.jsonParse, ".", ["node", "scripts/checkmap.mjs", "file", "json", "a.json", "b.json"], ["a.json", "b.json"]⟩]
#guard (plan ["apps/site/src/a.tsx", "apps/site/src/b.tsx", "apps/console-web/src/c.tsx"]).map (·.argv.getLast!) ==
  ["apps/site", "apps/console-web"]
#guard (plan ["lean/scripts/X.lean", "lean/Fw/A.lean", "a.mjs"]).map (·.argv) ==
  [["lake", "build"], ["lake", "env", "lean", "scripts/X.lean"], ["node", "--check", "a.mjs"]]
#guard verdict false [0, 127] && !verdict true [0, 127] && !verdict false [0, 1] && verdict true []
#guard runOk false 0 [0] && !runOk false 1 [0] && !runOk false 0 [2] && runOk true 0 []

end Fw.Ops.CheckMap

/-! ## Wire: `ops.checkMap`, `ops.checkVerdict` -/

namespace Fw.Wire.CheckMap
open Lean Fw.Ops.CheckMap Fw.Wire.Ops

/-- Kind wire names. -/
def kindName : Kind → String
  | .jsMod => "jsMod" | .ts => "ts" | .tsDecl => "tsDecl" | .tsx => "tsx" | .leanModule => "leanModule" | .leanScript => "leanScript"
  | .lakeConfig => "lakeConfig" | .json => "json" | .jsonl => "jsonl" | .yaml => "yaml" | .shell => "shell"
  | .workGraph => "workGraph" | .findingsLedger => "findingsLedger" | .workflow => "workflow"
  | .python => "python" | .swift => "swift" | .snapshot => "snapshot" | .sketch => "sketch" | .asset => "asset"
  | .prose => "prose" | .text => "text"

/-- Check wire names. -/
def checkName : Check → String
  | .lakeBuild => "lakeBuild" | .leanElab => "leanElab" | .nodeCheck => "nodeCheck" | .tsStrip => "tsStrip"
  | .tscProject => "tscProject" | .jsonParse => "jsonParse" | .jsonlParse => "jsonlParse" | .yamlParse => "yamlParse"
  | .shParse => "shParse" | .pyParse => "pyParse" | .swiftParse => "swiftParse" | .graphCheck => "graphCheck" | .presetCheck => "presetCheck" | .ledgerNotes => "ledgerNotes" | .workflowParse => "workflowParse" | .exempt => "exempt"

/-- A string list as JSON. -/
def strs (xs : List String) : Json := .arr (xs.toArray.map .str)

/-- `ops.checkMap`: `paths`, `deleted`? (staged deletions) → `cmds` [{check, cwd, argv, files}], `files` [{path, kind, check}] (kind and check null
when unmapped), `unmapped`. -/
def opCheckMap (req : Json) : Except String Reply := do
  let paths ← (← arr req "paths").toList.mapM (asStr "paths")
  let deleted ← match req.getObjValD "deleted" with
    | .null => pure []
    | _ => (← arr req "deleted").toList.mapM (asStr "deleted")
  let cmd (m : Cmd) : Json := Json.mkObj [("check", .str (checkName m.check)), ("cwd", .str m.cwd),
    ("argv", strs m.argv), ("files", strs m.files)]
  let file (p : String) : Json := match classify p with
    | some k => Json.mkObj [("path", .str p), ("kind", .str (kindName k)), ("check", .str (checkName (checkOf k)))]
    | none => Json.mkObj [("path", .str p), ("kind", .null), ("check", .null)]
  pure [("cmds", .arr ((planStaged paths deleted).toArray.map cmd)), ("files", .arr (paths.toArray.map file)),
    ("unmapped", strs (unmapped paths))]

/-- `ops.checkVerdict`: `codes` (exit codes, in plan order), `strict`? (default false), `unmapped`? (count, default 0)
→ `ok` (`runOk`), `failed` and `unavailable` (indices). -/
def opCheckVerdict (req : Json) : Except String Reply := do
  let strict ← boolD req "strict" false
  let u ← natD req "unmapped" 0
  let codes ← (← arr req "codes").toList.mapM (asNat "codes")
  let idx (f : Nat → Bool) : Json :=
    .arr ((codes.zipIdx.filter (f ·.1)).toArray.map fun (_, i) => toJson i)
  pure [("ok", .bool (runOk strict u codes)), ("failed", idx fun x => x != 0 && x != 127),
    ("unavailable", idx (· == 127))]

/-- The ops of this module. -/
def ops : List String := ["ops.checkMap", "ops.checkVerdict"]

/-- Dispatch (`none` when the op is not one of these). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "ops.checkMap" => some (opCheckMap req)
  | "ops.checkVerdict" => some (opCheckVerdict req)
  | _ => none

#guard ops.all fun o => (handle o (Json.mkObj [("paths", .arr #[]), ("codes", .arr #[])])).isSome

end Fw.Wire.CheckMap
