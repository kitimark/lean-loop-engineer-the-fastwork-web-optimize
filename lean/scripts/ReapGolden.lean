import Fw.Ops.Golden

/-! Write (or with `--check`, verify) `packages/contracts/golden/ops/lspreap.jsonl`: `ops.lspReap` (Fw.Ops.Reap) cases.
Consumer: `apps/runner/src/reap.ts`, replayed by `apps/runner/test/reap.test.ts`. Run from `lean/`:
`lake env lean --run scripts/ReapGolden.lean [--check]`. -/

open Lean Fw.Wire.Ops.Golden

/-- A row as JSON. -/
def row (pid ppid pgid start : Nat) (cwd : Option Nat) (kind : String) : Json :=
  Json.mkObj [("pid", toJson pid), ("ppid", toJson ppid), ("pgid", toJson pgid), ("start", toJson start),
    ("cwd", match cwd with | some n => toJson n | none => .null), ("kind", .str kind)]

/-- A lean-lsp-mcp process as JSON. -/
def mcpJ (pid : Nat) (cwd : Option Nat) : Json :=
  Json.mkObj [("pid", toJson pid), ("cwd", match cwd with | some n => toJson n | none => .null)]

/-- A request: rows, live inodes, the mcp processes, the recorded console `(pid, record second)`. -/
def req (rows : List Json) (live : List Nat) (mcps : List Json) (keep : List (Nat × Nat) := []) : Json :=
  Json.mkObj [("rows", .arr rows.toArray), ("live", toJson live), ("mcps", .arr mcps.toArray),
    ("keep", .arr (keep.map fun (p, a) => Json.mkObj [("pid", toJson p), ("at", toJson a)]).toArray)]

/-- A row with a worktree id as JSON. -/
def rowW (pid ppid pgid start : Nat) (cwd : Option Nat) (kind : String) (wt : Option String) : Json :=
  match row pid ppid pgid start cwd kind with
  | .obj kvs => .obj ((kvs.insert "wt" (match wt with | some w => .str w | none => .null)).insert "inRepo" (.bool wt.isSome))
  | j => j

/-- A row inside this repo (an ancestor of its cwd path has the repo root's inode) but in no worktree id, e.g. a deleted
directory below the repo root. -/
def rr (pid ppid pgid start : Nat) (cwd : Option Nat) (kind : String) : Json :=
  match row pid ppid pgid start cwd kind with
  | .obj kvs => .obj (kvs.insert "inRepo" (.bool true))
  | j => j

/-- A selection request with the live worktree ids. -/
def reqW (rows : List Json) (live : List Nat) (mcps : List Json) (keep : List (Nat × Nat) := []) (ids : List String := []) :
    Json :=
  match req rows live mcps keep with
  | .obj kvs => .obj (kvs.insert "liveIds" (.arr (ids.map Json.str).toArray))
  | j => j

/-- A stop target as JSON. -/
def tgt (pid start : Nat) (group : Bool) : Json :=
  Json.mkObj [("pid", toJson pid), ("start", toJson start), ("group", .bool group)]

/-- A kill or verify request: the planned targets and the fresh rows. -/
def stopReq (planned : List Json) (rows : List Json) : Json :=
  Json.mkObj [("planned", .arr planned.toArray), ("rows", .arr rows.toArray)]

/-- A row whose cwd path lies in the removed worktree `gone` of this repo. -/
def rg (pid ppid pgid start : Nat) (cwd : Option Nat) (kind : String) : Json := rowW pid ppid pgid start cwd kind (some "gone")

/-- The cases, `(name, request)`. -/
def reapCases : List (String × Json) := [
  ("a lake serve under a repo mcp whose cwd inode is in no live checkout is selected as a group leader",
    reqW [rg 500 400 500 9 (some 11) "lspServe"] [1, 2] [mcpJ 400 (some 1)]),
  ("a lake serve in a live checkout (a reused path has a new inode, the old one is dead) is kept",
    reqW [rg 500 400 500 9 (some 1) "lspServe", rg 501 400 501 9 (some 11) "lspServe"] [1, 2] [mcpJ 400 (some 2)]),
  ("a lake serve in a nested Lean project of a live checkout (its inode is in live) is kept",
    reqW [rg 500 400 500 9 (some 3) "lspServe"] [1, 3] [mcpJ 400 (some 1)]),
  ("a lake serve under another repo's mcp (mcp cwd in no live checkout) in a removed worktree of this repo is selected by B as removed, not as lspServe",
    reqW [rg 500 400 500 9 (some 11) "lspServe"] [1] [mcpJ 400 (some 77)]),
  ("a lake serve under an mcp with an unreadable cwd, in a removed worktree of this repo, is selected by B as removed",
    reqW [rg 500 400 500 9 (some 11) "lspServe"] [1] [mcpJ 400 none]),
  ("a row whose pgid differs from its pid is selected without a group signal",
    reqW [rg 500 400 77 9 (some 11) "lspServe"] [1] [mcpJ 400 (some 1)]),
  ("a lake serve of another parent, in a removed worktree of this repo, is selected by B as removed", reqW [rg 500 123 500 9 (some 11) "lspServe"] [1] [mcpJ 400 (some 1)]),
  ("no mcp: a lake serve in a removed worktree is still selected by B as removed", reqW [rg 500 400 500 9 (some 11) "lspServe"] [1] []),
  ("an orphan console of a removed worktree is selected; a console with a live parent is kept",
    reqW [rg 600 1 600 9 (some 12) "console", rg 601 55 601 9 (some 12) "console"] [1] []),
  ("the main console (cwd inode live) is kept", reqW [rg 600 1 600 9 (some 1) "console"] [1] []),
  ("the recorded console started from a worktree (dead cwd, ppid 1, pid and record second match) is kept",
    reqW [rg 600 1 600 100 (some 12) "console"] [1] [] [(600, 101)]),
  ("a pid reused after the record (it started more than 60 s later) is not the recorded console",
    reqW [rg 600 1 600 500 (some 12) "console"] [1] [] [(600, 101)]),
  ("a recorded pid with another pid in the table does not keep an unrelated console",
    reqW [rg 601 1 601 100 (some 12) "console"] [1] [] [(600, 101)]),
  ("an unreadable cwd is kept",
    reqW [rg 600 1 600 9 none "console", rg 500 400 500 9 none "lspServe"] [1] [mcpJ 400 (some 1)]),
  ("an unnamed kind is kept", reqW [rg 700 1 700 9 (some 12) "other", rg 701 1 701 9 (some 12) "chrome"] [1] [mcpJ 1 (some 1)]),
  ("pid 1 is never selected", reqW [rg 1 1 1 9 (some 12) "console"] [] []),
  ("no rows", reqW [] [] []),
  ("a lake serve under another repo's mcp, in no worktree of this repo, is kept",
    reqW [rowW 500 400 500 9 (some 11) "lspServe" none] [1] [mcpJ 400 (some 77)]),
  ("a console outside this repo's worktrees is kept (cwd dead, ppid 1, but no worktree of this repo)",
    reqW [rowW 600 1 600 9 (some 12) "console" none] [1] []),
  ("a console in a live worktree id of this repo is kept",
    reqW [rowW 600 1 600 9 (some 12) "console" (some "live")] [1] [] [] ["live"]),
  ("a temp repo as top selects nothing of another repo: console, orphan lake serve and tools of another repo are kept",
    reqW [rowW 600 1 600 9 (some 12) "console" none, rowW 601 600 600 9 (some 12) "tool" none,
      rowW 602 1 602 9 (some 13) "lspServe" none, rowW 603 602 602 9 (some 13) "tool" none] [1] []),
  ("an orphan lake serve (ppid 1) in a removed worktree is selected as removed",
    reqW [rg 500 1 500 9 (some 11) "lspServe"] [1] []),
  ("an orphan lake serve (ppid 1) outside this repo is kept", reqW [rowW 500 1 500 9 (some 11) "lspServe" none] [1] []),
  ("the lean-lsp-mcp launcher itself is kept while its lake serve of a removed worktree is selected",
    reqW [rg 400 1 400 9 (some 11) "other", rg 500 400 500 9 (some 11) "lspServe"] [1] [mcpJ 400 (some 11)]),
  ("a lake serve below the recorded console is kept even in a removed worktree",
    reqW [rg 600 1 600 100 (some 12) "console", rg 601 600 600 100 (some 12) "lspServe"] [1] [mcpJ 601 (some 1)] [(600, 101)]),
  ("the recorded console and its fwcore are kept whatever the repo, a console of the same removed worktree is not",
    reqW [rg 600 1 600 100 (some 12) "console", rg 601 600 600 100 (some 12) "tool", rg 700 1 700 100 (some 12) "console"] [1] []
      [(600, 101)])]


/-- A guard request: the scope pids, the table just read and the target. -/
def guardReq (scope : List Nat) (rows : List Json) (t : Json) : Json :=
  Json.mkObj [("scope", toJson scope), ("rows", .arr rows.toArray), ("target", t)]

/-- The cases of the tool branches and the stop plan, `(op, name, request)`. Ids: `gone` is a removed worktree, `live` a live one. -/
def stopCases : List (String × String × Json) := [
  ("ops.lspReap", "B: a tool whose cwd path is in a removed worktree is selected as removed",
    reqW [rowW 800 1 800 9 (some 20) "tool" (some "gone")] [1] [] [] ["live"]),
  ("ops.lspReap", "B: a tool in a live worktree id is kept",
    reqW [rowW 800 1 800 9 (some 20) "tool" (some "live")] [1] [] [] ["live"]),
  ("ops.lspReap", "B: a tool with no worktree id (cwd elsewhere) is kept",
    reqW [rowW 800 1 800 9 (some 20) "tool" none] [1] [] [] ["live"]),
  ("ops.lspReap", "B: a tool whose cwd inode is a live checkout's is kept even when its path names a gone id",
    reqW [rowW 800 1 800 9 (some 1) "tool" (some "gone")] [1] [] [] ["live"]),
  ("ops.lspReap", "B: a tool with an unreadable cwd is kept",
    reqW [rowW 800 1 800 9 none "tool" (some "gone")] [1] [] [] ["live"]),
  ("ops.lspReap", "B: an MCP process of a removed worktree is never selected as a tool",
    reqW [rowW 800 1 800 9 (some 20) "tool" (some "gone")] [1] [mcpJ 800 (some 20)] [] ["live"]),
  ("ops.lspReap", "B: the stopper's own process and its ancestors (protect) are kept, a sibling is selected",
    match reqW [rowW 800 1 800 9 (some 20) "tool" (some "gone"), rowW 801 800 800 9 (some 20) "tool" (some "gone"),
        rowW 802 1 802 9 (some 20) "tool" (some "gone")] [1] [] [] [] with
    | .obj kvs => .obj (kvs.insert "protect" (toJson [800, 801]))
    | j => j),
  ("ops.lspReap", "B: pid 1 is never selected",
    reqW [rowW 1 1 1 9 (some 20) "tool" (some "gone")] [1] [] [] []),
  ("ops.lspReap", "B: the recorded console's own fwcore (child of the kept console) is kept, the console is kept",
    reqW [rowW 600 1 600 100 (some 20) "console" (some "gone"), rowW 601 600 600 100 (some 20) "tool" (some "gone")] [1] []
      [(600, 101)] []),
  ("ops.lspReap", "B: a tool below a shell below the recorded console is kept",
    reqW [rowW 600 1 600 100 (some 20) "console" (some "gone"), rowW 602 600 600 100 (some 20) "other" none,
      rowW 601 602 600 100 (some 20) "tool" (some "gone")] [1] [] [(600, 101)] []),
  ("ops.lspReap", "C: tools below a selected lake serve are selected as descendants, also through an unnamed shell",
    reqW [rowW 500 400 500 9 (some 11) "lspServe" (some "gone"), rr 501 500 500 9 (some 11) "tool",
      rowW 502 501 500 9 (some 11) "other" none, rr 503 502 500 9 (some 11) "tool"] [1] [mcpJ 400 (some 1)] [] []),
  ("ops.lspReap", "C: a tool below a live-checkout parent is kept (no selected ancestor)",
    reqW [rowW 500 400 500 9 (some 1) "lspServe" (some "gone"), rowW 501 500 500 9 (some 11) "tool" none] [1] [mcpJ 400 (some 1)] [] []),
  ("ops.lspReap", "C: a tool below a selected parent whose own cwd is live is kept",
    reqW [rowW 500 400 500 9 (some 11) "lspServe" (some "gone"), rowW 501 500 500 9 (some 1) "tool" (some "gone")] [1] [mcpJ 400 (some 1)] [] []),
  ("ops.lspReap", "C: an unnamed process below a selected parent is kept",
    reqW [rowW 500 400 500 9 (some 11) "lspServe" (some "gone"), rowW 501 500 500 9 (some 11) "other" (some "gone")] [1] [mcpJ 400 (some 1)] [] []),
  ("ops.lspReap", "C: a tool below a removed-worktree tool is selected",
    reqW [rowW 800 1 800 9 (some 20) "tool" (some "gone"), rr 801 800 800 9 (some 21) "tool"] [1] [] [] []),
  ("ops.lspReap", "C: a parent cycle in the table ends (fuel) and selects nothing unrooted",
    reqW [rowW 810 811 810 9 (some 21) "tool" none, rowW 811 810 811 9 (some 21) "tool" none] [1] [] [] []),
  ("ops.reapPlan", "plan: a group whose members are all selected is signalled as a group",
    reqW [rowW 800 1 800 9 (some 20) "tool" (some "gone"), rowW 801 800 800 9 (some 20) "tool" (some "gone")] [1] [] [] []),
  ("ops.reapPlan", "plan: a group with an unselected member (an unnamed shell) is signalled by pid",
    reqW [rowW 800 1 800 9 (some 20) "tool" (some "gone"), rowW 802 800 800 9 (some 20) "other" none] [1] [] [] []),
  ("ops.reapPlan", "plan: a selected row that is not its group leader is signalled by pid",
    reqW [rowW 801 1 700 9 (some 20) "tool" (some "gone")] [1] [] [] []),
  ("ops.reapPlan", "plan: nothing selected gives an empty plan, the script and the grace",
    reqW [] [] [] [] []),
  ("ops.reapKill", "kill: a planned identity present with the same start is killed",
    stopReq [tgt 800 9 false] [row 800 1 800 9 none "tool"]),
  ("ops.reapKill", "kill: a pid reused with a later start is not killed",
    stopReq [tgt 800 9 false] [row 800 1 800 50 none "tool"]),
  ("ops.reapKill", "kill: a planned identity that exited is not killed",
    stopReq [tgt 800 9 false] [row 900 1 900 9 none "tool"]),
  ("ops.reapKill", "kill: a group with a stranger now in it is killed by pid, not as a group",
    stopReq [tgt 800 9 true] [row 800 1 800 9 none "tool", row 900 1 800 70 none "other"]),
  ("ops.reapKill", "kill: a group whose rows are all planned stays a group",
    stopReq [tgt 800 9 true, tgt 801 9 false] [row 800 1 800 9 none "tool", row 801 800 800 9 none "tool"]),
  ("ops.lspReap", "C: a tool whose cwd is a deleted directory of this repo, below a selected owner, is selected as descendant",
    reqW [rg 800 1 800 9 (some 20) "tool", rr 801 800 800 9 (some 21) "tool"] [1] [] [] []),
  ("ops.lspReap", "C: a tool outside this repo below a selected owner is kept",
    reqW [rg 800 1 800 9 (some 20) "tool", rowW 801 800 800 9 (some 21) "tool" none] [1] [] [] []),
  ("ops.reapTerm", "term: a planned identity present with the same start in the pre-TERM read is TERMed",
    stopReq [tgt 800 9 false] [row 800 1 800 9 none "tool"]),
  ("ops.reapTerm", "term: a pid reused between the gather and the TERM (later start) is not TERMed",
    stopReq [tgt 800 9 false] [row 800 1 800 50 none "tool"]),
  ("ops.reapTerm", "term: a planned identity that exited before the TERM is not TERMed",
    stopReq [tgt 800 9 false] [row 900 1 900 9 none "tool"]),
  ("ops.reapTerm", "term: a group with a stranger now in it is TERMed by pid, not as a group",
    stopReq [tgt 800 9 true] [row 800 1 800 9 none "tool", row 900 1 800 70 none "other"]),
  ("ops.reapGuard", "guard: a pid in the scope is allowed",
    guardReq [800] [row 800 1 800 9 none "tool"] (tgt 800 9 false)),
  ("ops.reapGuard", "guard: a pid outside the scope is refused",
    guardReq [800] [row 900 1 900 9 none "tool"] (tgt 900 9 false)),
  ("ops.reapGuard", "guard: pid 1 and pid 0 are refused even in the scope",
    guardReq [0, 1] [] (tgt 1 9 false)),
  ("ops.reapGuard", "guard: a group signal with a member outside the scope is refused",
    guardReq [800] [row 800 1 800 9 none "tool", row 900 1 800 70 none "other"] (tgt 800 9 true)),
  ("ops.reapGuard", "guard: a group signal whose members are all in the scope is allowed",
    guardReq [800, 801] [row 800 1 800 9 none "tool", row 801 800 800 9 none "tool"] (tgt 800 9 true)),
  ("ops.reapVerify", "verify: a survivor is left, an exited target is gone",
    stopReq [tgt 800 9 false, tgt 801 9 false] [row 800 1 800 9 none "tool"]),
  ("ops.reapVerify", "verify: a reused pid is not a survivor",
    stopReq [tgt 800 9 false] [row 800 1 800 50 none "tool"])]

/-- The golden text of `lspreap.jsonl`. -/
def text : String :=
  String.join (reapCases.map fun (name, r) =>
    (Json.mkObj [("name", .str name), ("request", withOp "ops.lspReap" r), ("response", respond "ops.lspReap" r)]).compress
      ++ "\n")

/-- The golden text of `reap.jsonl`. -/
def stopText : String :=
  String.join (stopCases.map fun (op, name, r) =>
    (Json.mkObj [("name", .str name), ("request", withOp op r), ("response", respond op r)]).compress ++ "\n")

/-- Write the golden files, or with `--check` exit 1 when one differs from the Lean output. -/
def main (args : List String) : IO UInt32 := do
  let dir : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ops"
  let files : List (String × String × Nat) :=
    [("lspreap.jsonl", text, reapCases.length), ("reap.jsonl", stopText, stopCases.length)]
  if args.contains "--check" then
    let mut bad := false
    for (f, t, n) in files do
      let cur ← try IO.FS.readFile (dir / f) catch _ => pure ""
      if cur != t then
        IO.println s!"reap golden: {dir / f} is stale (regenerate: cd lean && lake env lean --run scripts/ReapGolden.lean)"
        bad := true
      else IO.println s!"reap golden: {f} {n} cases, up to date"
    return if bad then 1 else 0
  for (f, t, n) in files do
    IO.FS.writeFile (dir / f) t
    IO.println s!"reap golden: {f} {n} cases written"
  return 0
