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

/-- The `store.gate` cases. -/
def gateCases : List (String × String × Json) := [
  ("the gate in its default configuration: all three inputs sent, nothing blocked", "store.gate", lit "{}"),
  ("one engine and a flag set", "store.gate", lit "{\"engines\":\"chromium\",\"fw\":[\"nav.hitTest:hit-skip\",\"morph.tween:waapi\"]}"),
  ("a preset of the rewrite arm", "store.gate", lit "{\"preset\":\"v2-proved\"}"),
  ("preset and flags are exclusive: a problem, no job", "store.gate", lit "{\"preset\":\"v2-proved\",\"fw\":[\"morph.tween:waapi\"]}"),
  ("an engines value the workflow does not list is a problem", "store.gate", lit "{\"engines\":\"webkit\"}"),
  ("a part given twice is a problem", "store.gate", lit "{\"fw\":[\"a.b:c\",\"a.b:d\"]}")]

/-- The `store.trajectory` cases. -/
def trajectoryCases : List (String × String × Json) := [
  ("the probe in its default configuration: four inputs sent, all widths", "store.trajectory", lit "{}"),
  ("one engine, a flag set and two widths", "store.trajectory",
   lit "{\"engines\":\"chromium\",\"fw\":[\"morph.tween:waapi\"],\"widths\":\"390,641\"}"),
  ("a preset of the rewrite arm", "store.trajectory", lit "{\"preset\":\"v2-proved\"}"),
  ("a width outside the allowlist is a problem, no job", "store.trajectory", lit "{\"widths\":\"390,800\"}"),
  ("a width given twice is a problem", "store.trajectory", lit "{\"widths\":\"390,390\"}"),
  ("preset and flags are exclusive", "store.trajectory", lit "{\"preset\":\"v2-proved\",\"fw\":[\"morph.tween:waapi\"]}")]

/-- The `store.plan` cases. -/
def planCases : List (String × String × Json) := [
  ("both engines, the original site in the default configuration: two jobs in canonical order, target sent to chromium, nothing blocked", "store.plan",
   lit s!"\{\"target\":\"original\",\"engines\":[\"webkit\",\"chromium\"],\"sha\":\"{sha}\"}"),
  ("duplicate engine names collapse to one job", "store.plan",
   lit s!"\{\"target\":\"original\",\"engines\":[\"chromium\",\"chromium\"],\"sha\":\"{sha}\",\"runs\":4}"),
  ("the rewrite with flags sorted by part (a camelCase part is allowed); both workflows take target, preset and fw, so nothing is blocked", "store.plan",
   lit s!"\{\"target\":\"rewrite\",\"preset\":\"original\",\"fw\":[\"nav.hitTest:hit-skip\",\"hero.countdown:strip\"],\"engines\":[\"chromium\",\"webkit\"],\"sha\":\"{sha}\"}"),
  ("another profile is an input of chromium-counts but not of webkit-sim: webkit is blocked on profile", "store.plan",
   lit s!"\{\"target\":\"original\",\"profile\":\"swipe-wheel-v1\",\"engines\":[\"chromium\",\"webkit\"],\"sha\":\"{sha}\"}"),
  ("digests and the store: one cache hit, one miss", "store.plan",
   lit s!"\{\"target\":\"original\",\"engines\":[\"chromium\",\"webkit\"],\"sha\":\"{sha}\",\"digests\":\{\"chromium\":\"aa00\",\"webkit\":\"bb11\"},\"present\":[\"aa00\"]}"),
  ("a pinned container image for chromium", "store.plan",
   lit s!"\{\"target\":\"original\",\"engines\":[\"chromium\"],\"sha\":\"{sha}\",\"images\":\{\"chromium\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\"}}"),
  ("a part given twice is a problem and plans no job", "store.plan",
   lit s!"\{\"target\":\"rewrite\",\"fw\":[\"a:x\",\"a:y\"],\"engines\":[\"chromium\"],\"sha\":\"{sha}\"}"),
  ("no engines, one run, a bad sha: three problems", "store.plan",
   lit "{\"target\":\"original\",\"engines\":[],\"sha\":\"zz\",\"runs\":1}"),
  ("an unknown engine is a problem", "store.plan",
   lit s!"\{\"target\":\"original\",\"engines\":[\"gecko\"],\"sha\":\"{sha}\"}"),
  ("a flag without a colon is refused as an id problem", "store.plan",
   lit s!"\{\"target\":\"rewrite\",\"fw\":[\"hero\"],\"engines\":[\"chromium\"],\"sha\":\"{sha}\"}"),
  ("the rewrite in its default configuration: same as the first case but target rewrite, so a different key", "store.plan",
   lit s!"\{\"target\":\"rewrite\",\"engines\":[\"webkit\",\"chromium\"],\"sha\":\"{sha}\"}"),
  ("target both is not one target: a problem, no job", "store.plan",
   lit s!"\{\"target\":\"both\",\"engines\":[\"chromium\"],\"sha\":\"{sha}\"}"),
  ("the original site takes no preset or flags: a problem, no job", "store.plan",
   lit s!"\{\"target\":\"original\",\"preset\":\"strip-demo\",\"fw\":[\"hero.countdown:strip\"],\"engines\":[\"chromium\"],\"sha\":\"{sha}\"}"),
  ("a request without target is refused", "store.plan",
   lit s!"\{\"engines\":[\"chromium\"],\"sha\":\"{sha}\"}"),
  ("2 runs: webkit is sent vms 2, chromium runs 2, and both keys carry the runs pair, so they differ from the 3-run keys", "store.plan",
   lit s!"\{\"target\":\"rewrite\",\"engines\":[\"webkit\",\"chromium\"],\"sha\":\"{sha}\",\"runs\":2}"),
  ("webkit-sim takes at most 3 VMs: 4 runs with webkit is a problem, no job", "store.plan",
   lit s!"\{\"target\":\"rewrite\",\"engines\":[\"webkit\",\"chromium\"],\"sha\":\"{sha}\",\"runs\":4}")]

/-- A manifest as JSON text (valid for `target = "\"target\":\"original\""`, `extra = ""`). -/
def manifest (target extra : String) : String :=
  s!"\{\"engine\":\"chromium\",{target},\"preset\":\"original\",\"fw\":[],\"profile\":\"swipe-v1\",\"gitSha\":\"{sha}\",\"image\":\"runner:ubuntu-24.04-arm\",\"runs\":3,\"runId\":\"39033771018\"{extra},\"entries\":[\{\"name\":\"counts-run1.json\",\"digest\":\"{"ab".pushn 'c' 62}\",\"bytes\":10},\{\"name\":\"trace/run1.json\",\"digest\":\"{"cd".pushn 'e' 62}\",\"bytes\":20}]}"

/-- The target field of a manifest on the original site. -/
def O : String := "\"target\":\"original\""

/-- The target field of a manifest on the rewrite. -/
def R : String := "\"target\":\"rewrite\""

/-- The `store.manifest` cases. -/
def manifestCases : List (String × String × Json) := [
  ("a valid manifest: key pairs and one object path per entry", "store.manifest",
   lit s!"\{\"manifest\":{manifest O ""}}"),
  ("the same run on the rewrite: a different key (the target pair)", "store.manifest",
   lit s!"\{\"manifest\":{manifest R ""}}"),
  ("the same run with 2 runs instead of 3: a different key (the runs pair)", "store.manifest",
   lit s!"\{\"manifest\":{(manifest O "").replace "\"runs\":3" "\"runs\":2"}}"),
  ("an original run with flags is a problem (only the rewrite has flags); the key is still shown", "store.manifest",
   lit s!"\{\"manifest\":{(manifest O "").replace "\"fw\":[]" "\"fw\":[\"hero.countdown:strip\"]"}}"),
  ("unsorted entries and a name that escapes the run directory are problems", "store.manifest",
   lit "{\"manifest\":{\"engine\":\"webkit\",\"target\":\"rewrite\",\"preset\":\"original\",\"fw\":[\"hero.countdown:strip\"],\"profile\":\"swipe-v1\",\"gitSha\":\"0123456789abcdef0123456789abcdef01234567\",\"image\":\"runner:xcode-27\",\"runs\":2,\"runId\":\"1\",\"entries\":[{\"name\":\"b.json\",\"digest\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"bytes\":1},{\"name\":\"../a.json\",\"digest\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"bytes\":1}]}}"),
  ("unknown engine, target both, short sha, bad image, bad digest, no runs: every problem listed, no key", "store.manifest",
   lit "{\"manifest\":{\"engine\":\"gecko\",\"target\":\"both\",\"preset\":\"Original\",\"fw\":[\"b:x\",\"a:y\"],\"profile\":\"swipe-v1\",\"gitSha\":\"abc\",\"image\":\"docker\",\"runs\":0,\"runId\":\"x\",\"entries\":[{\"name\":\"a.json\",\"digest\":\"ABC\",\"bytes\":1}]}}"),
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

/-- The run metadata of a `both` run (two shards per target) with a changed field, as JSON text. -/
def ciRunJ (extra : String := "") (jobs : String := "[{\"name\":\"plan\",\"conclusion\":\"success\"},{\"name\":\"counts (original, r1)\",\"conclusion\":\"success\"},{\"name\":\"counts (original, r2)\",\"conclusion\":\"success\"},{\"name\":\"counts (rewrite, r2)\",\"conclusion\":\"success\"},{\"name\":\"counts (rewrite, r1)\",\"conclusion\":\"success\"},{\"name\":\"classify\",\"conclusion\":\"success\"}]") : String :=
  s!"\{\"runId\":\"42\",\"workflowName\":\"chromium-counts\",\"status\":\"completed\",\"conclusion\":\"success\",\"headSha\":\"{sha}\",\"jobs\":{jobs}{extra}}"

/-- The facts of one downloaded shard artifact. -/
def fact (name : String) (search : String := "") (more : String := "") : String :=
  s!"\{\"name\":\"{name}\",\"profile\":\"swipe-v1\",\"image\":\"runner:ubuntu-24.04-arm\",\"search\":\"{search}\"{more}}"

/-- The four shard artifacts of `ciRunJ` (the rewrite with query `q`). -/
def allArts (q : String := "") : String :=
  s!"[{fact "chromium-counts-original-r1"},{fact "chromium-counts-original-r2"},{fact "chromium-counts-rewrite-r1" q},{fact "chromium-counts-rewrite-r2" q}]"

/-- The `store.ciRun` cases. -/
def ciRunCases : List (String × String × Json) := [
  ("before the download: a complete run is accepted, one store key per target, shards sorted, no key inputs yet", "store.ciRun",
   lit s!"\{\"run\":{ciRunJ}}"),
  ("after the download: key inputs per target; the original takes the default configuration, so the two keys differ in the target pair", "store.ciRun",
   lit s!"\{\"run\":{ciRunJ},\"artifacts\":{allArts},\"classes\":[\"original\",\"rewrite\"]}"),
  ("the rewrite query gives preset and flags (sorted by part)", "store.ciRun",
   lit s!"\{\"run\":{ciRunJ},\"artifacts\":{allArts "?preset=strip-demo&fw=nav.hitTest:hit-skip,hero.countdown:strip"},\"classes\":[\"original\",\"rewrite\"]}"),
  ("a failed run is refused before the download and stores nothing", "store.ciRun",
   lit s!"\{\"run\":{(ciRunJ).replace "\"conclusion\":\"success\",\"headSha\"" "\"conclusion\":\"failure\",\"headSha\""}}"),
  ("a run still in progress (conclusion null) is refused", "store.ciRun",
   lit s!"\{\"run\":{(ciRunJ).replace "\"status\":\"completed\",\"conclusion\":\"success\"" "\"status\":\"in_progress\",\"conclusion\":null"}}"),
  ("another workflow is refused", "store.ciRun",
   lit s!"\{\"run\":{(ciRunJ).replace "\"workflowName\":\"chromium-counts\"" "\"workflowName\":\"webkit-sim\""}}"),
  ("a run without shard jobs is refused", "store.ciRun",
   lit s!"\{\"run\":{ciRunJ "" "[{\"name\":\"plan\",\"conclusion\":\"success\"}]"}}"),
  ("a failed and an unfinished shard job are refused, each named", "store.ciRun",
   lit s!"\{\"run\":{ciRunJ "" "[{\"name\":\"counts (original, r1)\",\"conclusion\":\"failure\"},{\"name\":\"counts (original, r2)\",\"conclusion\":null}]"}}"),
  ("a missing shard artifact is refused after the download", "store.ciRun",
   lit s!"\{\"run\":{ciRunJ},\"artifacts\":[{fact "chromium-counts-original-r1"},{fact "chromium-counts-original-r2"},{fact "chromium-counts-rewrite-r1"}],\"classes\":[\"original\",\"rewrite\"]}"),
  ("a missing chromium-classes directory is refused", "store.ciRun",
   lit s!"\{\"run\":{ciRunJ},\"artifacts\":{allArts},\"classes\":[\"original\"]}"),
  ("shards of one target that disagree on the image are refused", "store.ciRun",
   lit s!"\{\"run\":{ciRunJ},\"artifacts\":[{fact "chromium-counts-original-r1"},{(fact "chromium-counts-original-r2").replace "ubuntu-24.04-arm" "ubuntu-24.04"},{fact "chromium-counts-rewrite-r1"},{fact "chromium-counts-rewrite-r2"}],\"classes\":[\"original\",\"rewrite\"]}"),
  ("a shard that measured another target than its name says is refused", "store.ciRun",
   lit s!"\{\"run\":{ciRunJ},\"artifacts\":[{fact "chromium-counts-original-r1" "" ",\"target\":\"rewrite\""},{fact "chromium-counts-original-r2"},{fact "chromium-counts-rewrite-r1"},{fact "chromium-counts-rewrite-r2"}],\"classes\":[\"original\",\"rewrite\"]}"),
  ("a rewrite-only run: one store key", "store.ciRun",
   lit s!"\{\"run\":{ciRunJ "" "[{\"name\":\"counts (rewrite, r1)\",\"conclusion\":\"success\"}]"},\"artifacts\":[{fact "chromium-counts-rewrite-r1" "?fw=hero.countdown:strip"}],\"classes\":[\"rewrite\"]}"),
  ("a request without run is refused", "store.ciRun", lit "{\"artifacts\":[]}")]

/-- The files: (file stem, cases). -/
def files : List (String × List (String × String × Json)) :=
  [("plan", planCases), ("gate", gateCases), ("trajectory", trajectoryCases),("manifest", manifestCases), ("objectPath", pathCases), ("reduce", reduceCases), ("ciRun", ciRunCases)]

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
