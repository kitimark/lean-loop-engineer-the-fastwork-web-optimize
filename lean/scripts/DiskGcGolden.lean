import Fw.Ops.Golden

/-! Writes, or with `--check` verifies, `packages/contracts/golden/ops/diskgc.jsonl` (`ops.diskGc`, `ops.diskGcPath`).
Run from `lean/`: `lake env lean --run scripts/DiskGcGolden.lean [--check]`. -/

open Lean Fw.Wire.Ops.Golden

/-- The main checkout of the cases. -/
def repo : String := "/h/r"

/-- The roots of the cases. -/
def roots : Json := Json.mkObj [("repo", .str repo), ("lake", .str "/h/.elan/t/lake/cache/artifacts"),
  ("scratch", .str "/private/tmp/claude-1/-h-r"), ("devices", .str "/h/Library/Developer/CoreSimulator/Devices")]

/-- Now, in the cases: 10 days after the epoch. -/
def now : Nat := 864000

/-- Every fact family gathered and empty, every class enabled. -/
def base : List (String × Json) := [("roots", roots), ("classes", .arr ((#[1, 2, 3, 4, 5, 6] : Array Nat).map toJson)),
  ("uid", toJson 501), ("now", toJson now), ("opens", .arr #[]), ("procs", .arr #[]), ("queued", .arr #[]),
  ("cited", .arr #[]), ("named", .arr #[.str "fw-iphone-27"]), ("simLock", .bool false),
  ("lake", Json.mkObj [("checkouts", .arr #[]), ("procs", .arr #[]), ("outputs", .arr #[])])]

/-- A request: `base` with `extra` fields replacing its own, and the candidates. -/
def req (extra : List (String × Json)) (cands : List Json) : Json :=
  Json.mkObj ((base.filter fun (k, _) => !(extra.map (·.1)).contains k) ++ extra ++ [("cands", .arr cands.toArray)])

/-- A candidate with the common facts: owned by uid 501, not tracked, a directory unless `dir` is false. -/
def cand (cls : Nat) (path : String) (newest : Nat) (more : List (String × Json) := []) (dir := true) : Json :=
  Json.mkObj ([("cls", toJson cls), ("path", .str path), ("bytes", toJson 100), ("uid", toJson 501),
    ("tracked", .bool false), ("newest", toJson newest), ("dir", .bool dir)] ++ more)

/-- A Lake cache file candidate named `n` with link count `links`. -/
def lakeFile (n : String) (links : Nat) : Json :=
  cand 1 s!"/h/.elan/t/lake/cache/artifacts/{n}" 0 [("lake", Json.mkObj [("name", .str n), ("file", .bool true),
    ("links", toJson links), ("mtime", toJson 0), ("ctime", toJson 0), ("size", toJson 100)])] false

/-- A worktree candidate (class 2 or 3) at `rel` below the worktrees root. -/
def wt (cls : Nat) (rel : String) (newest : Nat) (merged dirty : Bool) (lock : Json := .str "free")
    (branch := "worktree-w1") : Json :=
  cand cls s!"{repo}/.claude/worktrees/{rel}" newest [("branch", .str branch), ("merged", .bool merged),
    ("dirty", .bool dirty), ("lock", lock)]

/-- A scratch directory candidate. -/
def scratch (d : String) (newest : Nat) (more : List (String × Json) := []) : Json :=
  cand 4 s!"/private/tmp/claude-1/-h-r/s1/scratchpad/{d}" newest more

/-- A device candidate. -/
def sim (udid name state : String) : Json :=
  cand 5 s!"/h/Library/Developer/CoreSimulator/Devices/{udid}" 0
    [("device", Json.mkObj [("name", .str name), ("state", .str state)])]

/-- A UDID of the cases. -/
def u1 : String := "0a1b2c3d-0000-1111-2222-333344445555"

/-- A live lock holder of the cases. -/
def holder : Json := Json.mkObj [("pid", toJson 7), ("start", .str "Mon Oct  9 04:10:25 2026")]

/-- The cases, `(name, op, request)`. -/
def gcCases : List (String × String × Json) := [
  ("class 1: an unlinked file no checkout names is listed; a linked one and a named one are kept", "ops.diskGc",
    req [("lake", Json.mkObj [("checkouts", .arr #[Json.mkObj [("path", .str repo), ("refs", .arr #[.str "n.olean"])]]),
      ("procs", .arr #[]), ("outputs", .arr #[])])] [lakeFile "a.o" 1, lakeFile "b.o" 2, lakeFile "n.olean" 1]),
  ("class 1: no process table, the LakeGc age floor decides", "ops.diskGc",
    req [("lake", Json.mkObj [("checkouts", .arr #[])])] [lakeFile "a.o" 1]),
  ("class 1: no lake facts: nothing listed", "ops.diskGc",
    req [("lake", .null)] [lakeFile "a.o" 1]),
  ("class 2: a merged, clean, unlocked worktree is listed; dirty and unmerged ones are kept", "ops.diskGc",
    req [] [wt 2 "w1" 0 true false, wt 2 "w2" 0 true true, wt 2 "w3" 0 false false]),
  ("class 2: a lock held by a live process keeps it; a lock whose holder is gone does not", "ops.diskGc",
    req [("procs", .arr #[Json.mkObj [("pid", toJson 7), ("start", .str "Mon Oct 9 04:10:25 2026")]])]
      [wt 2 "w1" 0 true false holder, wt 2 "w2" 0 true false (Json.mkObj [("pid", toJson 8),
        ("start", .str "Mon Oct  9 04:10:25 2026")])]),
  ("class 2: an unparsed lock, a missing lock or no process table keeps it", "ops.diskGc",
    req [("procs", .null)] [wt 2 "w1" 0 true false (.str "claude agent"), cand 2 s!"{repo}/.claude/worktrees/w2" 0
      [("branch", .str "b"), ("merged", .bool true), ("dirty", .bool false)], wt 2 "w3" 0 true false holder]),
  ("class 2: a queued land or an unread queue keeps it", "ops.diskGc",
    req [("queued", .arr #[.str "worktree-w1"])] [wt 2 "w1" 0 true false, wt 2 "w2" 0 true false .null "worktree-w2"]),
  ("class 2: queue not gathered", "ops.diskGc", req [("queued", .null)] [wt 2 "w1" 0 true false]),
  ("class 2: a detached worktree (no branch) is kept", "ops.diskGc", req [] [wt 2 "w1" 0 true false (.str "free") ""]),
  ("class 3: rebuildable folders of an unmerged worktree idle for 24 h are listed; its sources never", "ops.diskGc",
    req [] [wt 3 "w1/node_modules" 0 false true, wt 3 "w1/lean/.lake" 0 false true,
      wt 3 "w1/apps/site/node_modules" 0 false true, wt 3 "w1/lean" 0 false true, wt 3 "w1/src/node_modules" 0 false true]),
  ("class 3: a worktree touched within idleH, or merged, is kept", "ops.diskGc",
    req [] [wt 3 "w1/node_modules" (now - 3600) false true, wt 3 "w2/node_modules" 0 true false]),
  ("class 3: idleH 0 lists a folder touched now", "ops.diskGc",
    req [("idleH", toJson 0)] [wt 3 "w1/node_modules" now false true]),
  ("class 4: an old uncited directory is listed; cited, fable, young and file entries are kept", "ops.diskGc",
    req [("cited", .arr #[.str "scratchpad/kept"])] [scratch "old" 0, scratch "kept" 0, scratch "fable-x" 0,
      scratch "young" (now - 60), cand 4 "/private/tmp/claude-1/-h-r/s1/scratchpad/f.txt" 0 [] false]),
  ("class 4: a directory a process holds a file in, or works in, is kept", "ops.diskGc",
    req [("opens", .arr #[.str "/private/tmp/claude-1/-h-r/s1/scratchpad/a/x.log",
      .str "/private/tmp/claude-1/-h-r/s1/scratchpad/b", .str "/private/tmp/claude-1/-h-r/s1/scratchpad/cc"])]
      [scratch "a" 0, scratch "b" 0, scratch "c" 0]),
  ("class 4: no open-file table keeps everything", "ops.diskGc",
    req [("opens", .null)] [scratch "old" 0]),
  ("class 4: no citation list", "ops.diskGc", req [("cited", .null)] [scratch "old" 0]),
  ("class 4: paths outside the allowed shape are kept (.., nested, other root, .local)", "ops.diskGc",
    req [] [cand 4 "/private/tmp/claude-1/-h-r/s1/scratchpad/../x" 0, cand 4 "/private/tmp/claude-1/-h-r/s1/scratchpad/a/b" 0,
      cand 4 "/private/tmp/other/s1/scratchpad/a" 0, cand 4 "/private/tmp/claude-1/-h-r/s1/.local/a" 0,
      cand 4 "/private/tmp/claude-1/-h-r/s1/scratchpad//a" 0]),
  ("class 4: a scratch root whose parent is not claude-<uid> refuses the class", "ops.diskGc",
    req [("roots", Json.mkObj [("repo", .str repo), ("lake", .str "/h/.elan/t/lake/cache/artifacts"),
      ("scratch", .str "/private/tmp/-h-r"), ("devices", .str "/h/Library/Developer/CoreSimulator/Devices")])]
      [cand 4 "/private/tmp/-h-r/s1/scratchpad/old" 0]),
  ("class 5: a shut-down fw-* device nothing names is listed; named, booted, foreign and bad-UDID ones are kept",
    "ops.diskGc", req [] [sim u1 "fw-iphone-17" "Shutdown", sim "1a1b2c3d-0000-1111-2222-333344445555" "fw-iphone-27"
      "Shutdown", sim "2a1b2c3d-0000-1111-2222-333344445555" "fw-ipad" "Booted",
      sim "3a1b2c3d-0000-1111-2222-333344445555" "iPhone 17" "Shutdown", sim "not-a-udid" "fw-x" "Shutdown"]),
  ("class 5: the Simulator lock held, or not read, keeps every device", "ops.diskGc",
    req [("simLock", .bool true)] [sim u1 "fw-iphone-17" "Shutdown"]),
  ("class 5: sim lock unknown", "ops.diskGc", req [("simLock", .null)] [sim u1 "fw-iphone-17" "Shutdown"]),
  ("class 6: tmp entries and land logs older than keepDays are listed; young ones and other console files are kept",
    "ops.diskGc", req [] [cand 6 s!"{repo}/.fw-console/tmp/chromium-1" 0, cand 6 s!"{repo}/.fw-console/land-logs/t-abc1234.log" 0 [] false,
      cand 6 s!"{repo}/.fw-console/land-logs/u-abc1234.log" (now - 86400) [] false,
      cand 6 s!"{repo}/.fw-console/events.jsonl" 0 [] false, cand 6 s!"{repo}/.fw-console/tmp" 0]),
  ("every class: a tracked or foreign-owned candidate is kept", "ops.diskGc",
    req [] [cand 4 "/private/tmp/claude-1/-h-r/s1/scratchpad/t" 0 [("tracked", .bool true)],
      cand 6 s!"{repo}/.fw-console/tmp/x" 0 [("uid", toJson 0)]]),
  ("--class 2: only class 2 is decided; the other classes' candidates are kept", "ops.diskGc",
    req [("classes", .arr #[.str "landed"])] [wt 2 "w1" 0 true false, scratch "old" 0,
      cand 6 s!"{repo}/.fw-console/tmp/x" 0]),
  ("the post-land classes 1, 2, 6", "ops.diskGc",
    req [("classes", .arr #[.str "1", .str "2", .str "6"])] [lakeFile "a.o" 1, wt 2 "w1" 0 true false,
      wt 3 "w2/node_modules" 0 false true, scratch "old" 0, sim u1 "fw-iphone-17" "Shutdown",
      cand 6 s!"{repo}/.fw-console/tmp/x" 0]),
  ("an unknown class: refused", "ops.diskGc", req [("classes", .arr #[toJson 7])] []),
  ("cands missing: refused", "ops.diskGc", Json.mkObj base),
  ("recheck: allowed paths pass, others fail", "ops.diskGcPath",
    Json.mkObj [("roots", roots), ("items", .arr #[
      Json.mkObj [("cls", .str "scratch"), ("path", .str "/private/tmp/claude-1/-h-r/s1/scratchpad/old")],
      Json.mkObj [("cls", .str "landed"), ("path", .str s!"{repo}/.claude/worktrees/w1")],
      Json.mkObj [("cls", .str "landed"), ("path", .str repo)],
      Json.mkObj [("cls", .str "idle"), ("path", .str s!"{repo}/.claude/worktrees/w1/src")],
      Json.mkObj [("cls", .str "console"), ("path", .str s!"{repo}/.fw-console/secret")],
      Json.mkObj [("cls", .str "sim"), ("path", .str s!"/h/Library/Developer/CoreSimulator/Devices/{u1}")],
      Json.mkObj [("cls", .str "lake"), ("path", .str "/h/.elan/t/lake/cache/artifacts/x/y")]])])]

/-- The golden text. -/
def text : String :=
  String.join (gcCases.map fun (name, op, r) =>
    (Json.mkObj [("name", .str name), ("request", withOp op r), ("response", respond op r)]).compress ++ "\n")

/-- Write the golden file, or with `--check` exit 1 when it differs from the Lean output. -/
def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ops" / "diskgc.jsonl"
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"diskgc golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/DiskGcGolden.lean)"
      return 1
    IO.println s!"diskgc golden: {gcCases.length} cases, up to date"
    return 0
  IO.FS.writeFile p text
  IO.println s!"diskgc golden: {gcCases.length} cases written"
  return 0
