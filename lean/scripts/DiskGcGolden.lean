import Fw.Ops.Golden

open Lean Fw.Wire.Ops.Golden

def repo : String := "/h/r"

def roots : Json := Json.mkObj [("repo", .str repo), ("lake", .str "/h/.elan/t/lake/cache/artifacts"),
  ("scratch", .str "/private/tmp/claude-1/-h-r"), ("devices", .str "/h/Library/Developer/CoreSimulator/Devices"),
  ("utmp", .str "/private/var/folders/ab/cd/T")]

def now : Nat := 864000

def base : List (String × Json) := [("roots", roots), ("classes", .arr ((#[1, 2, 3, 4, 5, 6, 7] : Array Nat).map toJson)),
  ("uid", toJson 501), ("now", toJson now), ("opens", .arr #[]), ("procs", .arr #[]), ("queued", .arr #[]),
  ("cited", .arr #[]), ("named", .arr #[.str "fw-iphone-27"]), ("simLock", .bool false),
  ("landSubjects", .arr #[.str "land worktree-w1", .str "land worktree-w2", .str "land b"]),
  ("liveRuns", .arr #[]), ("landedRuns", .arr #[]),
  ("lake", Json.mkObj [("checkouts", .arr #[]), ("procs", .arr #[]), ("outputs", .arr #[])])]

def req (extra : List (String × Json)) (cands : List Json) : Json :=
  Json.mkObj ((base.filter fun (k, _) => !(extra.map (·.1)).contains k) ++ extra ++ [("cands", .arr cands.toArray)])

def cand (cls : Nat) (path : String) (newest : Nat) (more : List (String × Json) := []) (dir := true) : Json :=
  Json.mkObj ([("cls", toJson cls), ("path", .str path), ("bytes", toJson 100), ("uid", toJson 501),
    ("tracked", .bool false), ("newest", toJson newest), ("dir", .bool dir)] ++
    (if cls ≥ 6 && !(more.map (·.1)).contains "sym" then [("sym", .bool false)] else []) ++ more)

def lakeFile (n : String) (links : Nat) : Json :=
  cand 1 s!"/h/.elan/t/lake/cache/artifacts/{n}" 0 [("lake", Json.mkObj [("name", .str n), ("file", .bool true),
    ("links", toJson links), ("mtime", toJson 0), ("ctime", toJson 0), ("size", toJson 100)])] false

def wt (cls : Nat) (rel : String) (newest : Nat) (merged dirty : Bool) (lock : Json := .str "free")
    (branch := "worktree-w1") : Json :=
  let branch := if cls == 2 && !merged && branch == "worktree-w1" then "worktree-open" else branch
  cand cls s!"{repo}/.claude/worktrees/{rel}" newest [("branch", .str branch), ("merged", .bool merged),
    ("dirty", .bool dirty), ("lock", lock)]

def scratch (d : String) (newest : Nat) (more : List (String × Json) := []) : Json :=
  cand 4 s!"/private/tmp/claude-1/-h-r/s1/scratchpad/{d}" newest more

def tmp (n : String) (newest : Nat := 0) (more : List (String × Json) := []) (dir := true) : Json :=
  cand 7 s!"/private/var/folders/ab/cd/T/{n}" newest more dir

def owned (d : String) (newest : Nat) : Json :=
  scratch d newest [("owner", Json.mkObj [("task", .str "t1"), ("run", .str "r1")])]

def sim (udid name state : String) : Json :=
  cand 5 s!"/h/Library/Developer/CoreSimulator/Devices/{udid}" 0
    [("device", Json.mkObj [("name", .str name), ("state", .str state)])]

def ev (seq : Nat) (type : String) (more : List (String × String) := []) : Json :=
  Json.mkObj ([("seq", toJson seq), ("type", .str type)] ++ more.map fun (k, v) => (k, Json.str v))

def facts (es : List Json) : Json := Json.mkObj [("events", .arr es.toArray)]

def u1 : String := "0a1b2c3d-0000-1111-2222-333344445555"

def holder : Json := Json.mkObj [("pid", toJson 7), ("start", .str "Mon Oct  9 04:10:25 2026")]

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
  ("class 2 (inc-gc-landed-ff): a fast-forward onto a landed branch has no land commit of its own and is kept",
    "ops.diskGc", req [("landSubjects", .arr #[.str "land worktree-wf_efb32ee2-da5-1"])]
      [wt 2 "wf_1f18354c-dfd-1" 0 true false (.str "free") "worktree-wf_1f18354c-dfd-1",
       wt 2 "wf_efb32ee2-da5-1" 0 true false (.str "free") "worktree-wf_efb32ee2-da5-1"]),
  ("class 2 (inc-gc-landed-ff): a worktree a live agent's run owns is kept, also with a land commit", "ops.diskGc",
    req [("liveRuns", .arr #[.str "wf_1f18354c-dfd"])] [wt 2 "wf_1f18354c-dfd-1" 0 true false, wt 2 "w1" 0 true false]),
  ("class 2 (inc-gc-landed-ff): a live agent's run owns it, the landed-task identity is kept too", "ops.diskGc",
    req [("landSubjects", .arr #[]), ("landedRuns", .arr #[.str "wf_1f18354c-dfd"]), ("liveRuns", .arr #[.str "wf_1f18354c-dfd"])]
      [wt 2 "wf_1f18354c-dfd-1" 0 false false]),
  ("class 2 (inc-gc-landed-ff): the landed task owning the worktree selects it once no agent runs", "ops.diskGc",
    req [("landSubjects", .arr #[]), ("landedRuns", .arr #[.str "wf_1f18354c-dfd"])]
      [wt 2 "wf_1f18354c-dfd-1" 0 false false, wt 2 "wf_1f18354c-df-1" 0 false false]),
  ("class 2 (inc-gc-landed-ff): unread land subjects keep it", "ops.diskGc",
    req [("landSubjects", .null)] [wt 2 "w1" 0 true false]),
  ("class 2 (inc-gc-landed-ff): live runs not gathered keep it", "ops.diskGc",
    req [("liveRuns", .null)] [wt 2 "w1" 0 true false]),
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
  ("class 7: our own names older than tmpH are listed; other names, young entries and links are kept", "ops.diskGc",
    req [] [tmp "fw-land-abc", tmp "oracle1", tmp "ghb2", tmp "engine-check-x", tmp "premises-1", tmp "land-base-1",
      tmp "lint9", tmp "var3", tmp "instruments-1.ktrace" 0 [] false, tmp "instruments-1.trace", tmp "com.apple.x",
      tmp "xfw", tmp ".fw1", tmp "fw-young" (now - 600), tmp "fw-link" 0 [("sym", .bool true)] false]),
  ("class 7: the folder itself, a nested path and a dotted path are kept", "ops.diskGc",
    req [] [cand 7 "/private/var/folders/ab/cd/T" 0, cand 7 "/private/var/folders/ab/cd/T/fw1/x" 0,
      cand 7 "/private/var/folders/ab/cd/T/../fw1" 0, cand 7 "/private/var/folders/ab/cd/T/" 0,
      cand 7 "/private/var/folders/ab/cd/Tfw1" 0]),
  ("class 7: a file a process holds open, or no open-file table, keeps the entry", "ops.diskGc",
    req [("opens", .arr #[.str "/private/var/folders/ab/cd/T/fw-a/log"])] [tmp "fw-a", tmp "fw-b"]),
  ("class 7: no open-file table", "ops.diskGc", req [("opens", .null)] [tmp "fw-a"]),
  ("class 7: tmpH 0 lists an entry touched now", "ops.diskGc",
    req [("tmpH", toJson 0)] [tmp "fw-a" now]),
  ("class 7: a root that is not .../folders/<a>/<b>/T lists nothing", "ops.diskGc",
    req [("roots", Json.mkObj [("repo", .str repo), ("lake", .str "/h/.elan/t/lake/cache/artifacts"),
      ("scratch", .str "/private/tmp/claude-1/-h-r"), ("devices", .str "/h/Library/Developer/CoreSimulator/Devices"),
      ("utmp", .str "/private/tmp")])] [cand 7 "/private/tmp/fw-a" 0]),
  ("every class: a candidate whose owner is unknown (absent or negative uid) is kept; the rest of the run proceeds",
    "ops.diskGc", req [] [Json.mkObj [("cls", toJson 7), ("path", .str "/private/var/folders/ab/cd/T/fw-a"),
      ("bytes", toJson 1), ("tracked", .bool false), ("newest", toJson 0), ("dir", .bool true)],
      Json.mkObj [("cls", toJson 7), ("path", .str "/private/var/folders/ab/cd/T/fw-b"), ("bytes", toJson 1),
        ("uid", toJson (-1 : Int)), ("tracked", .bool false), ("newest", toJson 0), ("dir", .bool true)], tmp "fw-c"]),
  ("class 4 pressure: under pressure an idle directory of 2 h is listed, not a running agent's, not a young one", "ops.diskGc",
    req [("pressure", .bool true), ("liveAgents", .arr #[.str "busy"])] [scratch "mid" (now - 3 * 3600),
      scratch "busy" (now - 3 * 3600), scratch "young" (now - 3600), scratch "old" 0]),
  ("class 4 pressure: without pressure the 2 h floor is not used", "ops.diskGc",
    req [("liveAgents", .arr #[])] [scratch "mid" (now - 3 * 3600)]),
  ("class 4 pressure: the agent list is not gathered", "ops.diskGc",
    req [("pressure", .bool true)] [scratch "mid" (now - 3 * 3600)]),
  ("class 4 owner: a directory of a landed task and a finished run is listed after 1 h; each other fact keeps it",
    "ops.diskGc", req [("landedTasks", .arr #[.str "t1"]), ("finishedRuns", .arr #[.str "r1"])]
      [owned "m" (now - 7200), owned "young" (now - 60), scratch "nomarker" (now - 7200)]),
  ("class 4 owner: the task not landed, the run not finished, or either list not gathered keeps it", "ops.diskGc",
    req [("landedTasks", .arr #[.str "t2"]), ("finishedRuns", .arr #[.str "r1"])] [owned "a" (now - 7200)]),
  ("class 4 owner: run not finished", "ops.diskGc",
    req [("landedTasks", .arr #[.str "t1"]), ("finishedRuns", .arr #[])] [owned "a" (now - 7200)]),
  ("class 4 owner: lists not gathered", "ops.diskGc", req [] [owned "a" (now - 7200)]),
  ("class 6: a symbolic link is kept", "ops.diskGc",
    req [] [cand 6 s!"{repo}/.fw-console/tmp/link" 0 [("sym", .bool true)] false]),
  ("classes 6 and 7: a candidate without a sym fact is kept", "ops.diskGc",
    req [] [Json.mkObj [("cls", toJson 6), ("path", .str s!"{repo}/.fw-console/tmp/nosym"), ("bytes", toJson 100),
        ("uid", toJson 501), ("tracked", .bool false), ("newest", toJson 0), ("dir", .bool true)],
      Json.mkObj [("cls", toJson 7), ("path", .str "/private/var/folders/ab/cd/T/fw-nosym"), ("bytes", toJson 100),
        ("uid", toJson 501), ("tracked", .bool false), ("newest", toJson 0), ("dir", .bool true)]]),
  ("class 7: the extended mkdtemp prefixes are listed, near misses are kept", "ops.diskGc",
    req [] [tmp "dryl-a1", tmp "jev-x", tmp "jevd2-y", tmp "cm-test-1", tmp "slots-1", tmp "difftest-1", tmp "rr-1",
      tmp "replay-1", tmp "wkrep-1", tmp "wkraw-1", tmp "vd-root-1", tmp "compose-1", tmp "graph-check-1",
      tmp "dryl1", tmp "rr", tmp "graph", tmp "vdx", tmp "cm"]),
  ("facts: a label alone is live, a stop ends it, a later spawn resumes it", "ops.diskGcFacts",
    facts [ev 1 "agent.label" [("agent", "a"), ("name", "mid")], ev 2 "agent.label" [("agent", "b"), ("name", "gone")],
      ev 3 "agent.stop" [("agent", "b")], ev 4 "agent.label" [("agent", "c"), ("name", "back")],
      ev 5 "agent.stop" [("agent", "c")], ev 6 "agent.spawn" [("agent", "c")]]),
  ("facts: events are judged by seq, not file order: a spawn newer than the stop resumes, a stop newer than the spawn ends", "ops.diskGcFacts",
    facts [ev 2 "agent.stop" [("agent", "a")], ev 5 "agent.spawn" [("agent", "a")], ev 1 "agent.label" [("agent", "a"), ("name", "x")],
      ev 5 "agent.spawn" [("agent", "b")], ev 7 "agent.stop" [("agent", "b")], ev 2 "agent.label" [("agent", "b"), ("name", "y")]]),
  ("facts: a finished run ends its agents; done tasks and runs are listed once", "ops.diskGcFacts",
    facts [ev 1 "agent.label" [("agent", "a"), ("name", "m"), ("key", "wfid-label:wf_12345678-abc:a:t")],
      ev 2 "agent.label" [("agent", "b"), ("name", "n"), ("key", "wfid-label:wf_87654321-def:b:t")],
      ev 3 "agent.stop" [("agent", "wf:wf_12345678-abc"), ("key", "wfr-end:wf_12345678-abc")],
      ev 4 "agent.stop" [("agent", "z"), ("key", "wfr-end:wf_12345678-abc")], ev 5 "task.done" [("task", "t1")],
      ev 6 "task.done" [("task", "t1")], ev 7 "task.done" [], ev 8 "agent.stop" [("key", "wfr-end:wf_")]]),
  ("facts: live runs are the runs of running agents; landed runs are runs labelled with a done task", "ops.diskGcFacts",
    facts [ev 1 "agent.label" [("agent", "a"), ("name", "t1"), ("key", "wfid-label:wf_12345678-abc:a:t1")],
      ev 2 "agent.label" [("agent", "b"), ("name", "t2"), ("key", "wfid-label:wf_87654321-def:b:t2")],
      ev 3 "agent.stop" [("agent", "b")], ev 4 "task.done" [("task", "t2")], ev 5 "task.done" [("task", "t1")]]),
  ("facts: a label without an agent or a name is ignored", "ops.diskGcFacts",
    facts [ev 1 "agent.label" [("name", "x")], ev 2 "agent.label" [("agent", "a")]]),
  ("facts: an event without a seq is refused", "ops.diskGcFacts",
    Json.mkObj [("events", .arr #[Json.mkObj [("type", .str "agent.stop")]])]),
  ("an unknown class: refused", "ops.diskGc", req [("classes", .arr #[toJson 8])] []),
  ("cands missing: refused", "ops.diskGc", Json.mkObj base),
  ("recheck: allowed paths pass, others fail", "ops.diskGcPath",
    Json.mkObj [("roots", roots), ("items", .arr #[
      Json.mkObj [("cls", .str "scratch"), ("path", .str "/private/tmp/claude-1/-h-r/s1/scratchpad/old")],
      Json.mkObj [("cls", .str "landed"), ("path", .str s!"{repo}/.claude/worktrees/w1")],
      Json.mkObj [("cls", .str "landed"), ("path", .str repo)],
      Json.mkObj [("cls", .str "idle"), ("path", .str s!"{repo}/.claude/worktrees/w1/src")],
      Json.mkObj [("cls", .str "console"), ("path", .str s!"{repo}/.fw-console/secret")],
      Json.mkObj [("cls", .str "sim"), ("path", .str s!"/h/Library/Developer/CoreSimulator/Devices/{u1}")],
      Json.mkObj [("cls", .str "lake"), ("path", .str "/h/.elan/t/lake/cache/artifacts/x/y")],
      Json.mkObj [("cls", .str "usertmp"), ("path", .str "/private/var/folders/ab/cd/T/fw-a")],
      Json.mkObj [("cls", .str "usertmp"), ("path", .str "/private/var/folders/ab/cd/T")],
      Json.mkObj [("cls", .str "usertmp"), ("path", .str "/private/var/folders/ab/cd/T/other")]])])]

def text : String :=
  String.join (gcCases.map fun (name, op, r) =>
    (Json.mkObj [("name", .str name), ("request", withOp op r), ("response", respond op r)]).compress ++ "\n")

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
