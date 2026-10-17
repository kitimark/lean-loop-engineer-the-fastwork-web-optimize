import Fw.Ops.Golden
/-!
# Golden vectors of `store.*`

`packages/contracts/golden/store/<op>.jsonl`: one line per case, `{"name", "request", "response"}`
(`response` is what `fwcore` replies without the `id`). Generated from Lean, never by hand:

```
cd lean && lake env lean --run scripts/StoreGolden.lean           # write the files
cd lean && lake env lean --run scripts/StoreGolden.lean --check   # fail if a file is stale
```

`lake test` runs the same check. Consumers: the zod schemas in `packages/contracts/src/artifacts.ts`
(parse every request and response) and `apps/runner/src/run*.ts`.
-/
namespace Fw.Wire.Store.Golden
open Lean
open Fw.Wire.Ops.Golden (lit withOp respond)

/-- A git sha used by the cases. -/
def sha : String := "0123456789abcdef0123456789abcdef01234567"

/-- The `store.plan` cases. -/
def planCases : List (String × String × Json) := [
  ("both engines, default configuration: two jobs in canonical order, nothing blocked", "store.plan",
   lit s!"\{\"engines\":[\"webkit\",\"chromium\"],\"sha\":\"{sha}\"}"),
  ("duplicate engine names collapse to one job", "store.plan",
   lit s!"\{\"engines\":[\"chromium\",\"chromium\"],\"sha\":\"{sha}\",\"runs\":4}"),
  ("flags are sorted by part (a camelCase part is allowed); chromium-counts takes fw, webkit-sim does not, so only webkit is blocked", "store.plan",
   lit s!"\{\"preset\":\"original\",\"fw\":[\"nav.hitTest:hit-skip\",\"hero.countdown:strip\"],\"engines\":[\"chromium\",\"webkit\"],\"sha\":\"{sha}\"}"),
  ("another profile is an input of chromium-counts but not of webkit-sim", "store.plan",
   lit s!"\{\"profile\":\"swipe-wheel-v1\",\"engines\":[\"chromium\",\"webkit\"],\"sha\":\"{sha}\"}"),
  ("digests and the store: one cache hit, one miss", "store.plan",
   lit s!"\{\"engines\":[\"chromium\",\"webkit\"],\"sha\":\"{sha}\",\"digests\":\{\"chromium\":\"aa00\",\"webkit\":\"bb11\"},\"present\":[\"aa00\"]}"),
  ("a pinned container image for chromium", "store.plan",
   lit s!"\{\"engines\":[\"chromium\"],\"sha\":\"{sha}\",\"images\":\{\"chromium\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"}}"),
  ("a part given twice is a problem and plans no job", "store.plan",
   lit s!"\{\"fw\":[\"a:x\",\"a:y\"],\"engines\":[\"chromium\"],\"sha\":\"{sha}\"}"),
  ("no engines, one run, a bad sha: three problems", "store.plan",
   lit "{\"engines\":[],\"sha\":\"zz\",\"runs\":1}"),
  ("an unknown engine is a problem", "store.plan",
   lit s!"\{\"engines\":[\"gecko\"],\"sha\":\"{sha}\"}"),
  ("a flag without a colon is refused as an id problem", "store.plan",
   lit s!"\{\"fw\":[\"hero\"],\"engines\":[\"chromium\"],\"sha\":\"{sha}\"}")]

/-- A valid manifest as JSON text. -/
def manifest (extra : String) : String :=
  s!"\{\"engine\":\"chromium\",\"preset\":\"original\",\"fw\":[],\"profile\":\"swipe-v1\",\"gitSha\":\"{sha}\",\"image\":\"runner:ubuntu-24.04-arm\",\"runId\":\"39033771018\"{extra},\"entries\":[\{\"name\":\"counts-run1.json\",\"digest\":\"{"ab".pushn 'c' 62}\",\"bytes\":10},\{\"name\":\"trace/run1.json\",\"digest\":\"{"cd".pushn 'e' 62}\",\"bytes\":20}]}"

/-- The `store.manifest` cases. -/
def manifestCases : List (String × String × Json) := [
  ("a valid manifest: key pairs and one object path per entry", "store.manifest",
   lit s!"\{\"manifest\":{manifest ""}}"),
  ("unsorted entries and a name that escapes the run directory are problems", "store.manifest",
   lit "{\"manifest\":{\"engine\":\"webkit\",\"preset\":\"original\",\"fw\":[\"hero.countdown:strip\"],\"profile\":\"swipe-v1\",\"gitSha\":\"0123456789abcdef0123456789abcdef01234567\",\"image\":\"runner:xcode-27\",\"runId\":\"1\",\"entries\":[{\"name\":\"b.json\",\"digest\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"bytes\":1},{\"name\":\"../a.json\",\"digest\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"bytes\":1}]}}"),
  ("unknown engine, short sha, bad image, bad digest: every problem listed, no key", "store.manifest",
   lit "{\"manifest\":{\"engine\":\"gecko\",\"preset\":\"Original\",\"fw\":[\"b:x\",\"a:y\"],\"profile\":\"swipe-v1\",\"gitSha\":\"abc\",\"image\":\"docker\",\"runId\":\"x\",\"entries\":[{\"name\":\"a.json\",\"digest\":\"ABC\",\"bytes\":1}]}}"),
  ("missing field is refused", "store.manifest", lit "{\"manifest\":{\"engine\":\"chromium\"}}")]

/-- The `store.objectPath` cases. -/
def pathCases : List (String × String × Json) := [
  ("fan-out by the first two hex digits", "store.objectPath",
   lit "{\"digest\":\"abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789\"}"),
  ("uppercase is refused", "store.objectPath",
   lit "{\"digest\":\"ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef0123456789\"}"),
  ("a short digest is refused", "store.objectPath", lit "{\"digest\":\"abcdef\"}")]

/-- Frames of one run with one count `a` per frame. -/
def run (vals : List Nat) : String :=
  "[" ++ ",".intercalate (vals.map fun v => s!"\{\"counts\":\{\"a\":{v}}}") ++ "]"

/-- The `store.reduce` cases. -/
def reduceCases : List (String × String × Json) := [
  ("variant does less on both engines: passes", "store.reduce",
   lit s!"\{\"kMax\":4,\"tMax\":24,\"arms\":[\{\"engine\":\"chromium\",\"base\":[{run [3, 3]},{run [3, 3]}],\"var\":[{run [1, 1]}]},\{\"engine\":\"webkit\",\"base\":[{run [5]},{run [5]}],\"var\":[{run [4]}]}]}"),
  ("variant does more in one frame of a deterministic type: fails, type named", "store.reduce",
   lit s!"\{\"kMax\":4,\"tMax\":24,\"arms\":[\{\"engine\":\"chromium\",\"base\":[{run [3, 3]},{run [3, 3]}],\"var\":[{run [3, 4]}]}]}"),
  ("a type only the variant has is judged (new work)", "store.reduce",
   lit "{\"kMax\":4,\"tMax\":24,\"arms\":[{\"engine\":\"chromium\",\"base\":[[{\"counts\":{\"a\":3}}],[{\"counts\":{\"a\":3}}]],\"var\":[[{\"counts\":{\"a\":3,\"b\":5}}]]}]}"),
  ("a stable type needs the 2t margin: runs [5,5] and [4,7] give t = 1; a variant total equal to the baseline fails", "store.reduce",
   lit s!"\{\"kMax\":4,\"tMax\":24,\"arms\":[\{\"engine\":\"chromium\",\"base\":[{run [5, 5]},{run [4, 7]}],\"var\":[{run [5, 5]}]}]}"),
  ("no arms is never a pass", "store.reduce", lit "{\"kMax\":4,\"tMax\":24,\"arms\":[]}"),
  ("one baseline run has no class: refused", "store.reduce",
   lit s!"\{\"kMax\":4,\"tMax\":24,\"arms\":[\{\"engine\":\"chromium\",\"base\":[{run [3]}],\"var\":[{run [3]}]}]}")]

/-- The files: (file stem, cases). -/
def files : List (String × List (String × String × Json)) :=
  [("plan", planCases), ("manifest", manifestCases), ("objectPath", pathCases), ("reduce", reduceCases)]

/-- The text of one golden file. -/
def fileText (cs : List (String × String × Json)) : String :=
  String.join (cs.map fun (name, op, req) =>
    (Json.mkObj [("name", .str name), ("request", withOp op req), ("response", respond op req)]).compress ++ "\n")

/-- The golden directory, relative to `lean/`. -/
def dir : System.FilePath := ".." / "packages" / "contracts" / "golden" / "store"

/-- Compare (or write) the golden files; returns the number of stale files. -/
def run' (root : System.FilePath) (write : Bool) : IO Nat := do
  let d := root / dir
  if write then IO.FS.createDirAll d
  let mut stale := 0
  for (stem, cs) in files do
    let p := d / s!"{stem}.jsonl"
    let text := fileText cs
    if write then
      IO.FS.writeFile p text
    else
      let cur ← try IO.FS.readFile p catch _ => pure ""
      if cur != text then
        IO.println s!"store golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/StoreGolden.lean)"
        stale := stale + 1
  let n := files.foldl (fun a c => a + c.2.length) 0
  IO.println s!"store golden: {files.length} files, {n} cases, {if write then "written" else s!"{stale} stale"}"
  return stale

end Fw.Wire.Store.Golden
