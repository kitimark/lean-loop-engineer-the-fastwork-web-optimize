import Fw.Ops.Golden

/-! Write (or with `--check`, verify) `packages/contracts/golden/ops/lspreap.jsonl`: `ops.lspReap` (Fw.Ops.Reap) cases,
`reap.jsonl` (the stop plan) and `reap-idle.jsonl` (branch D and the CPU baselines).
Consumer: `apps/runner/src/reap.ts`, replayed by `apps/runner/test/reap.test.ts` and `reap-idle.test.ts`. Run from `lean/`:
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

/-- A row of the worktree `wt` (`none`: the main checkout) with cwd inode 30, start 9 and a CPU time (centiseconds). -/
def ir (pid ppid pgid : Nat) (kind : String) (cpu : Option Nat) (wt : Option String := some "w") : Json :=
  match rowW pid ppid pgid 9 (some 30) kind wt with
  | .obj kvs => .obj ((kvs.insert "cpu" (match cpu with | some c => toJson c | none => .null)).insert "inRepo" (.bool true))
  | j => j

/-- A lean-lsp-mcp process with cwd inode 1 and the worktree its cwd lies in. -/
def mcpW (pid : Nat) (wt : Option String) : Json :=
  Json.mkObj [("pid", toJson pid), ("cwd", toJson 1), ("wt", match wt with | some w => .str w | none => .null)]

/-- A baseline of the identity (pid, start 9). -/
def bse (pid since cpu : Nat) (start : Nat := 9) : Json :=
  Json.mkObj [("pid", toJson pid), ("start", toJson start), ("since", toJson since), ("cpu", toJson cpu)]

/-- An idle-stack request: the live inodes (1 and 30 by default), live worktree `w`, the baselines, the locks `(id, holder)`
and `now`. -/
def idleReq (rows mcps bases : List Json) (locks : List (String × Option Nat) := []) (now : Nat := 5000)
    (protect : List Nat := []) (live : List Nat := [1, 30]) : Json :=
  match reqW rows live mcps [] ["w"] with
  | .obj kvs => .obj ((((kvs.insert "bases" (.arr bases.toArray)).insert "now" (toJson now)).insert "protect"
      (toJson protect)).insert "locks" (.arr (locks.map fun (id, h) => Json.mkObj [("id", .str id),
        ("holder", match h with | some p => toJson p | none => .null)]).toArray))
  | j => j

/-- An MCP stack of lean-lsp-mcp 400: `lake serve` 500, `lean --server` 501 (both group 500), workers 502 and 503 (own
groups), CPU 10, 600, 900, 100. -/
def stack (wt : Option String := some "w") (cpu502 : Option Nat := some 900) : List Json :=
  [ir 500 400 500 "lspServe" (some 10) wt, ir 501 500 500 "tool" (some 600) wt, ir 502 501 502 "tool" cpu502 wt,
    ir 503 501 503 "tool" (some 100) wt]

/-- The baselines of `stack`, set at second 1000 with the same CPU times. -/
def stackBases : List Json := [bse 500 1000 10, bse 501 1000 600, bse 502 1000 900, bse 503 1000 100]

/-- The cases of branch D and of the baselines, `(op, name, request)`. -/
def idleCases : List (String × String × Json) := [
  ("ops.lspReap", "D: every process of an idle lean-lsp-mcp stack in a worktree with no live session is selected",
    idleReq (stack) [mcpW 400 none] stackBases),
  ("ops.reapPlan", "D plan: lake serve and lean --server are one group signal, each worker its own group",
    idleReq (stack) [mcpW 400 none] stackBases),
  ("ops.lspReap", "D: a worktree locked by a holder pid in the table (a live session) keeps the stack",
    idleReq (stack ++ [ir 300 1 300 "other" none none]) [mcpW 400 none] stackBases [("w", some 300)]),
  ("ops.lspReap", "D: a lock whose holder pid is gone (a dead session) does not keep the stack",
    idleReq (stack) [mcpW 400 none] stackBases [("w", some 300)]),
  ("ops.lspReap", "D: a lock whose reason names no pid keeps the stack",
    idleReq (stack) [mcpW 400 none] stackBases [("w", none)]),
  ("ops.lspReap", "D: a lock on another worktree does not keep the stack",
    idleReq (stack ++ [ir 300 1 300 "other" none none]) [mcpW 400 none] stackBases [("v", some 300)]),
  ("ops.lspReap", "D: a lean-lsp-mcp started in the worktree (its session works there) keeps the stack",
    idleReq (stack) [mcpW 400 (some "w")] stackBases),
  ("ops.lspReap", "D: a worker that used more than cpuTolCs since its baseline keeps the whole stack",
    idleReq (stack (cpu502 := some 1201)) [mcpW 400 none] stackBases),
  ("ops.lspReap", "D: a worker that used exactly cpuTolCs since its baseline is still quiet",
    idleReq (stack (cpu502 := some 1200)) [mcpW 400 none] stackBases),
  ("ops.lspReap", "D: a baseline younger than idleSec keeps the stack",
    idleReq (stack) [mcpW 400 none] stackBases (now := 2199)),
  ("ops.lspReap", "D: a stack seen for the first time (no baseline) is kept",
    idleReq (stack) [mcpW 400 none] []),
  ("ops.lspReap", "D: a row of the stack with an unread CPU time keeps the stack",
    idleReq (stack (cpu502 := none)) [mcpW 400 none] stackBases),
  ("ops.lspReap", "D: a stack in the main checkout (no worktree id) is kept",
    idleReq (stack (wt := none)) [mcpW 400 none] stackBases),
  ("ops.lspReap", "D: a serena-lean server (lean --server below a serena process) is kept, idle or not",
    idleReq [ir 600 1 600 "serena" (some 5) none, ir 601 600 601 "tool" (some 5)] [mcpW 400 none]
      [bse 600 1000 5, bse 601 1000 5]),
  ("ops.lspReap", "D: a lean-lsp-mcp stack below a serena process is kept",
    idleReq (ir 399 1 399 "serena" (some 5) none :: stack) [mcpW 400 none] stackBases),
  ("ops.lspReap", "D: a lake serve whose parent is no lean-lsp-mcp (an editor's) is kept",
    idleReq (stack) [] stackBases),
  ("ops.lspReap", "D: a protected pid (the stopper's chain) is kept, the rest of the stack is selected",
    idleReq (stack) [mcpW 400 none] stackBases (protect := [502])),
  ("ops.lspReap", "D: a stack in a removed worktree (cwd inode not live) is selected by A and B, not by D",
    idleReq (stack (wt := some "gone")) [mcpW 400 none] stackBases (live := [1])),
  ("ops.reapPlan", "D plan: an unselected shell in the lake serve group makes it a signal by pid",
    idleReq (stack ++ [ir 504 500 500 "other" (some 0)]) [mcpW 400 none] (stackBases ++ [bse 504 1000 0])),
  ("ops.reapIdle", "baselines: a quiet row keeps its own, a busy row and an unseen row get one at now, other rows none",
    idleReq (stack (cpu502 := some 1201) ++ [ir 700 1 700 "tool" (some 5)]) [mcpW 400 none]
      [bse 500 1000 10, bse 501 1000 600, bse 502 1000 900]),
  ("ops.reapIdle", "baselines: a reused pid (another start) gets a new baseline",
    idleReq (stack) [mcpW 400 none] [bse 500 1000 10 (start := 8), bse 501 1000 600, bse 502 1000 900, bse 503 1000 100])]

def rowE (pid ppid pgid start : Nat) (kind : String) (wt : Option String) (awaits : Option String := none)
    (callLive : Bool := false) (inode : String := "") : Json :=
  match rowW pid ppid pgid start (some 5) kind wt with
  | .obj kvs => .obj (((kvs.insert "awaits" (match awaits with | some a => .str a | none => .null)).insert "callLive" (.bool callLive)).insert "inode" (.str inode))
  | j => j

def waiterJ (pid start : Nat) (wt writes : String) (inode : String := "") : Json :=
  Json.mkObj [("pid", toJson pid), ("start", toJson start), ("wt", .str wt), ("writes", .str writes), ("inode", .str inode)]

def loopFact (r : Json) : Option Json :=
  match r.getObjVal? "awaits", r.getObjVal? "pid", r.getObjVal? "start", r.getObjVal? "callLive" with
  | .ok (.str a), .ok pid, .ok st, .ok cl =>
    some (Json.mkObj [("pid", pid), ("start", st), ("awaits", .str a), ("callLive", cl),
      ("inode", (r.getObjVal? "inode").toOption.getD (.str ""))])
  | _, _, _, _ => none

def plainRow : Json → Json
  | .obj kvs => .obj (((kvs.erase "awaits").erase "callLive").erase "inode")
  | j => j

def reqE (rows waiters : List Json) (now : Nat) (simIdleSince : Option Nat := none) (simAcquired : Option Nat := none)
    (simHolders : Nat := 0) (ownSims : List (Nat × Nat) := []) (legacyHeld : Bool := false) (auto : Bool := false) : Json :=
  match reqW (rows.map plainRow) [1] [] [] ["agent"] with
  | .obj kvs =>
    .obj (((((((((kvs.insert "legacyHeld" (.bool legacyHeld)).insert "auto" (.bool auto)).insert "loops" (.arr (rows.filterMap loopFact).toArray)).insert "waiters" (.arr waiters.toArray)).insert "now"
      (toJson now)).insert "simIdleSince" (match simIdleSince with | some t => toJson t | none => .null)).insert "simAcquired"
      (match simAcquired with | some t => toJson t | none => .null)).insert "simHolders" (toJson simHolders)).insert "ownSims"
      (.arr (ownSims.map fun (p, s) => Json.mkObj [("pid", toJson p), ("start", toJson s)]).toArray))
  | j => j

def mwm : String := "/tmp/mwm-wait.log"

def oneCases : List (String × String × Json) :=
  let loop (pid : Nat) := rowE pid 1 pid 1000 "untilLoop" (some "agent") (some mwm)
  let ciWait := rowE 23868 1 23868 1100 "other" (some "agent")
  let sim := rowE 3100 1 3100 1000 "simDevice" none
  let own : List (Nat × Nat) := [(3100, 1000)]
  [("ops.lspReap", "E case 1: an until-loop (pid 2846) that outlived its tool call, no live writer, is selected with pid and start",
    reqE [loop 2846] [] 1720),
  ("ops.reapHeld", "E case 1: the watch alert names the same loop (pid 2846, start 1000)", reqE [loop 2846] [] 1720),
  ("ops.reapPlan", "E case 1: the stop plan TERMs the identity the alert names (pid 2846, start 1000)", reqE [loop 2846] [] 1720),
  ("ops.lspReap", "E case 2: the same loop (pid 40204) while a live fw ci wait of the same agent writes the awaited path is kept",
    reqE [loop 40204, ciWait] [waiterJ 23868 1100 "agent" mwm] 1720),
  ("ops.reapHeld", "E case 2: the watch alert names nothing for it", reqE [loop 40204, ciWait] [waiterJ 23868 1100 "agent" mwm] 1720),
  ("ops.lspReap", "E: a waiter whose pid was reused (another start) is no writer, the loop is selected",
    reqE [loop 40204, rowE 23868 1 23868 1500 "other" (some "agent")] [waiterJ 23868 1100 "agent" mwm] 1720),
  ("ops.lspReap", "E: a live waiter of another agent is no writer, the loop is selected",
    reqE [loop 40204, rowE 23868 1 23868 1100 "other" (some "other")] [waiterJ 23868 1100 "other" mwm] 1720),
  ("ops.lspReap", "E: a live waiter of the same agent that writes another path is no writer, the loop is selected",
    reqE [loop 40204, ciWait] [waiterJ 23868 1100 "agent" "/tmp/other.log"] 1720),
  ("ops.lspReap", "E: a loop whose tool call is still running is kept",
    reqE [rowE 2846 1 2846 1000 "untilLoop" (some "agent") (some mwm) (callLive := true)] [] 1720),
  ("ops.lspReap", "E: a loop younger than orphanMinSec is kept", reqE [loop 2846] [] 1059),
  ("ops.lspReap", "E: a loop that awaits no path is kept",
    reqE [rowE 2846 1 2846 1000 "untilLoop" (some "agent")] [] 1720),
  ("ops.lspReap", "F case 3: an own Simulator booted by the released run (acquired 900, booted 1000, released 1200), no slot held, idle 600 s, is selected with pid and start",
    reqE [sim] [] 1800 (simIdleSince := some 1200) (simAcquired := some 900) (ownSims := own)),
  ("ops.reapPlan", "F case 3: the stop plan names the Simulator identity (pid 3100, start 1000)",
    reqE [sim] [] 1800 (simIdleSince := some 1200) (simAcquired := some 900) (ownSims := own)),
  ("ops.lspReap", "F: a Simulator is kept while a sim slot is held",
    reqE [sim] [] 1800 (simIdleSince := some 1200) (simAcquired := some 900) (simHolders := 1) (ownSims := own)),
  ("ops.lspReap", "F: a Simulator booted after the last release is kept",
    reqE [sim] [] 1800 (simIdleSince := some 900) (simAcquired := some 800) (ownSims := own)),
  ("ops.lspReap", "F: a Simulator booted before the released run acquired its slot is kept (not booted by that run)",
    reqE [sim] [] 1800 (simIdleSince := some 1200) (simAcquired := some 1100) (ownSims := own)),
  ("ops.lspReap", "F: a Simulator whose identity is not in the own fw- device facts (other start, other pid) is kept",
    reqE [sim] [] 1800 (simIdleSince := some 1200) (simAcquired := some 900) (ownSims := [(3100, 1001), (3101, 1000)])),
  ("ops.lspReap", "F: a Simulator is kept until the slot rule's idle time (simIdleS 600) has passed since the release",
    reqE [sim] [] 1799 (simIdleSince := some 1200) (simAcquired := some 900) (ownSims := own)),
  ("ops.lspReap", "F: with no recorded release nothing is selected", reqE [sim] [] 1800 (simAcquired := some 900) (ownSims := own)),
  ("ops.lspReap", "F: with no recorded acquire second nothing is selected", reqE [sim] [] 1800 (simIdleSince := some 1200) (ownSims := own)),
  ("ops.lspReap", "E case 2, canonical facts: lsof says /private/tmp/mwm-wait.log, the loop argv says /tmp/mwm-wait.log; the glue sends one canonical path, the loop is kept",
    reqE [rowE 40204 1 40204 1000 "untilLoop" (some "agent") (some "/private/tmp/mwm-wait.log"), ciWait]
      [waiterJ 23868 1100 "agent" "/private/tmp/mwm-wait.log"] 1720),
  ("ops.lspReap", "all three cases at once: the orphan loop of agent2 and the Simulator are selected, the loop of agent with a live writer is kept",
    reqE [rowE 2846 1 2846 1000 "untilLoop" (some "agent2") (some mwm), loop 40204, ciWait, sim] [waiterJ 23868 1100 "agent" mwm] 1800
      (simIdleSince := some 1200) (simAcquired := some 900) (ownSims := own)),
  ("ops.reapPlan", "E case 1, watch tick (auto): the plan has no target, the loop stays selected as advice",
    reqE [loop 2846] [] 1720 (auto := true)),
  ("ops.reapHeld", "E case 1, watch tick (auto): the alert still names pid 2846 start 1000", reqE [loop 2846] [] 1720 (auto := true)),
  ("ops.reapHeld", "F case 3, watch tick (auto): heldSim names the booted Simulator (pid 3100, start 1000) and held names no loop",
    reqE [sim] [] 1800 (simIdleSince := some 1200) (simAcquired := some 900) (ownSims := own) (auto := true)),
  ("ops.reapPlan", "F case 3, watch tick (auto): the plan has no target, the Simulator stays selected as advice",
    reqE [sim] [] 1800 (simIdleSince := some 1200) (simAcquired := some 900) (ownSims := own) (auto := true)),
  ("ops.lspReap", "F: a Simulator is kept while the legacy sim-lock (.local/locks/sim) is held",
    reqE [sim] [] 1800 (simIdleSince := some 1200) (simAcquired := some 900) (ownSims := own) (legacyHeld := true)),
  ("ops.lspReap", "E: a loop awaiting the relative path out.log is kept",
    reqE [rowE 2846 1 2846 1000 "untilLoop" (some "agent") (some "out.log")] [] 1720),
  ("ops.lspReap", "E: a loop awaiting $HOME/x is kept", reqE [rowE 2846 1 2846 1000 "untilLoop" (some "agent") (some "$HOME/x")] [] 1720),
  ("ops.lspReap", "E: a loop awaiting /tmp/`x`.log (a backtick) is kept",
    reqE [rowE 2846 1 2846 1000 "untilLoop" (some "agent") (some "/tmp/`x`.log")] [] 1720),
  ("ops.lspReap", "E: a loop awaiting /tmp/*.log (a glob) is kept",
    reqE [rowE 2846 1 2846 1000 "untilLoop" (some "agent") (some "/tmp/*.log")] [] 1720),
  ("ops.lspReap", "E: a loop awaiting ~/x is kept", reqE [rowE 2846 1 2846 1000 "untilLoop" (some "agent") (some "~/x")] [] 1720),
  ("ops.lspReap", "E: a loop awaiting /tmp/[a].log is kept",
    reqE [rowE 2846 1 2846 1000 "untilLoop" (some "agent") (some "/tmp/[a].log")] [] 1720),
  ("ops.lspReap", "E inode: the waiter writes the awaited file under another name (same inode 16777220:55) and is a writer, the loop is kept",
    reqE [rowE 40204 1 40204 1000 "untilLoop" (some "agent") (some mwm) (inode := "16777220:55"), ciWait]
      [waiterJ 23868 1100 "agent" "/tmp/alias.log" "16777220:55"] 1720),
  ("ops.lspReap", "E inode: the waiter writes the same path string but another file (the file was replaced), the loop is selected",
    reqE [rowE 40204 1 40204 1000 "untilLoop" (some "agent") (some mwm) (inode := "16777220:55"), ciWait]
      [waiterJ 23868 1100 "agent" mwm "16777220:56"] 1720),
  ("ops.lspReap", "E inode: the awaited file does not exist yet (no inode), the path string decides and keeps the loop",
    reqE [rowE 40204 1 40204 1000 "untilLoop" (some "agent") (some mwm), ciWait]
      [waiterJ 23868 1100 "agent" mwm "16777220:55"] 1720),
  ("ops.lspReap", "E: a protected pid (the stopper's chain) is kept",
    match reqE [loop 2846] [] 1720 with
    | .obj kvs => .obj (kvs.insert "protect" (toJson [2846]))
    | j => j)]

def seenJ (kind : String) (pid firstAt : Nat) (outcome : String) : Json :=
  Json.mkObj [("kind", .str kind), ("pid", toJson pid), ("start", toJson 100), ("firstAt", toJson firstAt), ("outcome", .str outcome)]

def exitReq (now : Nat) (seen : List Json) : Json :=
  Json.mkObj [("now", toJson now), ("seen", .arr seen.toArray)]

def exitCases : List (String × String × Json) :=
  let wk : Nat := 7 * 86400
  [("ops.reapExit", "E: seven days of log, one true orphan (stopped), no loop ended by itself: promoted",
    exitReq (1000 + wk) [seenJ "orphanLoop" 10 1000 "stopped", seenJ "orphanLoop" 11 2000 "alive"]),
  ("ops.reapExit", "E: one second short of seven days: kept out", exitReq (1000 + wk - 1) [seenJ "orphanLoop" 10 1000 "stopped"]),
  ("ops.reapExit", "E: seven days but no true orphan: kept out", exitReq (1000 + wk) [seenJ "orphanLoop" 10 1000 "alive"]),
  ("ops.reapExit", "E: a selected loop later ended by itself: kept out",
    exitReq (1000 + wk) [seenJ "orphanLoop" 10 1000 "stopped", seenJ "orphanLoop" 11 2000 "ended"]),
  ("ops.reapExit", "F: its own log decides; an ended loop of E does not block F",
    exitReq (1000 + wk) [seenJ "simBooted" 20 1000 "stopped", seenJ "orphanLoop" 11 2000 "ended"]),
  ("ops.reapExit", "F: an ended Simulator blocks F, E stays promoted",
    exitReq (1000 + wk) [seenJ "simBooted" 20 1000 "ended", seenJ "orphanLoop" 10 1000 "stopped"]),
  ("ops.reapExit", "an empty log promotes nothing", exitReq (1000 + wk) []),
  ("ops.reapExit", "a kind outside E and F is rejected as a log kind", exitReq (1000 + wk) [seenJ "removed" 10 1000 "stopped"])]

def exitText : String :=
  String.join (exitCases.map fun (op, name, r) =>
    (Json.mkObj [("name", .str name), ("request", withOp op r), ("response", respond op r)]).compress ++ "\n")

/-- A `reap.held` row (`at` in milliseconds, as the runner writes it). -/
def heldRow (atMs : Nat) (kind : String) (pid start : Nat) : Json :=
  Json.mkObj [("type", .str "reap.held"), ("at", toJson atMs), ("kind", .str kind), ("pid", toJson pid), ("start", toJson start)]

/-- A `reap.stopped` row; `targets` are (pid, start) pairs, none for an old row with pids only. -/
def stoppedRow (atMs : Nat) (kind : String) (targets : List (Nat × Nat)) (old : Bool := false) : Json :=
  let base := [("type", Json.str "reap.stopped"), ("at", toJson atMs), ("kind", .str kind),
    ("pids", toJson (targets.map (·.1))), ("freedKb", toJson 0)]
  Json.mkObj (if old then base else base ++ [("targets", .arr (targets.map fun (p, s) => Json.mkObj [("pid", toJson p), ("start", toJson s)]).toArray)])

/-- A `reap.tick` row listing the E and F processes selected then. -/
def tickRow (atMs : Nat) (live : List (String × Nat × Nat)) : Json :=
  Json.mkObj [("type", .str "reap.tick"), ("at", toJson atMs),
    ("live", .arr (live.map fun (k, p, s) => Json.mkObj [("kind", .str k), ("pid", toJson p), ("start", toJson s)]).toArray)]

/-- Ticks every `step` seconds from `lo` to `hi` (seconds), each listing `live`. -/
def ticksBetween (step lo hi : Nat) (live : List (String × Nat × Nat)) : List Json :=
  (List.range ((hi - lo) / step + 1)).map fun k => tickRow ((lo + k * step) * 1000) live

def foldReq (now : Nat) (recs : List Json) : Json :=
  Json.mkObj [("now", toJson now), ("recs", .arr recs.toArray)]

def logReq (recs : List Json) (selected : List (String × Nat × Nat)) : Json :=
  Json.mkObj [("recs", .arr recs.toArray),
    ("selected", .arr (selected.map fun (k, p, s) => Json.mkObj [("kind", .str k), ("pid", toJson p), ("start", toJson s)]).toArray)]

def foldCases : List (String × String × Json) :=
  let wk : Nat := 7 * 86400
  let t0 : Nat := 1000000
  let e : List (String × Nat × Nat) := [("orphanLoop", 10, 100)]
  let full := ticksBetween 300 t0 (t0 + wk) e
  [("ops.reapFold", "seven days of ticks every 300 s, the loop stopped once and never ended by itself: E is promoted",
    foldReq (t0 + wk) ([heldRow (t0 * 1000) "orphanLoop" 10 100] ++ full ++ [stoppedRow ((t0 + wk) * 1000) "orphanLoop" [(10, 100)]])),
  ("ops.reapFold", "the same log with the stop recorded as pids only (no start): no true orphan, E stays advice",
    foldReq (t0 + wk) ([heldRow (t0 * 1000) "orphanLoop" 10 100] ++ full ++ [stoppedRow ((t0 + wk) * 1000) "orphanLoop" [(10, 100)] (old := true)])),
  ("ops.reapFold", "a log of one day: not yet 7 days of coverage",
    foldReq (t0 + 86400) ([heldRow (t0 * 1000) "orphanLoop" 10 100] ++ ticksBetween 300 t0 (t0 + 86400) e ++ [stoppedRow ((t0 + 86400) * 1000) "orphanLoop" [(10, 100)]])),
  ("ops.reapFold", "seven days old but a tick gap of a day in the middle: coverage refused",
    foldReq (t0 + wk) ([heldRow (t0 * 1000) "orphanLoop" 10 100] ++ ticksBetween 300 t0 (t0 + 3 * 86400) e ++
      ticksBetween 300 (t0 + 4 * 86400) (t0 + wk) e ++ [stoppedRow ((t0 + wk) * 1000) "orphanLoop" [(10, 100)]])),
  ("ops.reapFold", "seven days of ticks but the first tick comes one hour late: coverage refused",
    foldReq (t0 + wk) ([heldRow (t0 * 1000) "orphanLoop" 10 100] ++ ticksBetween 300 (t0 + 3600) (t0 + wk) e ++
      [stoppedRow ((t0 + wk) * 1000) "orphanLoop" [(10, 100)]])),
  ("ops.reapFold", "a loop that left the selection without a stop (a tick after its first sight without it) is ended: E stays advice",
    foldReq (t0 + wk) ([heldRow (t0 * 1000) "orphanLoop" 10 100, heldRow ((t0 + 600) * 1000) "orphanLoop" 11 100] ++ full ++
      [tickRow ((t0 + 900) * 1000) [("orphanLoop", 10, 100)], stoppedRow ((t0 + wk) * 1000) "orphanLoop" [(10, 100)]])),
  ("ops.reapFold", "F has its own sightings: a stopped Simulator and covered days promote F, E has no orphan",
    foldReq (t0 + wk) ([heldRow (t0 * 1000) "simBooted" 30 5] ++ ticksBetween 300 t0 (t0 + wk) [("simBooted", 30, 5)] ++
      [stoppedRow ((t0 + wk) * 1000) "simBooted" [(30, 5)]])),
  ("ops.reapFold", "rows of other kinds and other types are not folded",
    foldReq (t0 + wk) ([heldRow (t0 * 1000) "removed" 7 7, stoppedRow (t0 * 1000) "lspServe" [(8, 8)],
      Json.mkObj [("type", .str "reap.note"), ("at", toJson 1)]] ++ full)),
  ("ops.reapFold", "an empty log", foldReq (t0 + wk) []),
  ("ops.reapLog", "a first sight is written once: the known identity (pid 10) is not written again, pid 12 is, twice listed once",
    logReq [heldRow (t0 * 1000) "orphanLoop" 10 100]
      [("orphanLoop", 10, 100), ("orphanLoop", 12, 100), ("orphanLoop", 12, 100), ("removed", 13, 1)]),
  ("ops.reapLog", "the same pid with another start is another identity",
    logReq [heldRow (t0 * 1000) "orphanLoop" 10 100] [("orphanLoop", 10, 101)]),
  ("ops.reapLog", "an identity known only from a stop record is known", logReq [stoppedRow (t0 * 1000) "simBooted" [(30, 5)]] [("simBooted", 30, 5)]),
  ("ops.reapLog", "no selection: nothing to write", logReq [] []),
  ("ops.reapSimNew", "the Simulator booted after the acquire is the run's; the one already booted is not",
    Json.mkObj [("before", toJson ["aaaa-1111"]), ("after", toJson ["AAAA-1111", "bbbb-2222"])]),
  ("ops.reapSimNew", "nothing booted at acquire: every booted device at release is new (upper-cased)",
    Json.mkObj [("before", toJson ([] : List String)), ("after", toJson ["x-1"])]),
  ("ops.reapSimNew", "the same set at both ends: none", Json.mkObj [("before", toJson ["a", "b"]), ("after", toJson ["B", "A"])])]

def foldText : String :=
  String.join (foldCases.map fun (op, name, r) =>
    (Json.mkObj [("name", .str name), ("request", withOp op r), ("response", respond op r)]).compress ++ "\n")

def oneText : String :=
  String.join (oneCases.map fun (op, name, r) =>
    (Json.mkObj [("name", .str name), ("request", withOp op r), ("response", respond op r)]).compress ++ "\n")

def text : String :=
  String.join (reapCases.map fun (name, r) =>
    (Json.mkObj [("name", .str name), ("request", withOp "ops.lspReap" r), ("response", respond "ops.lspReap" r)]).compress
      ++ "\n")

/-- The golden text of `reap.jsonl`. -/
def stopText : String :=
  String.join (stopCases.map fun (op, name, r) =>
    (Json.mkObj [("name", .str name), ("request", withOp op r), ("response", respond op r)]).compress ++ "\n")

/-- The golden text of `reap-idle.jsonl`. -/
def idleText : String :=
  String.join (idleCases.map fun (op, name, r) =>
    (Json.mkObj [("name", .str name), ("request", withOp op r), ("response", respond op r)]).compress ++ "\n")

/-- Write the golden files, or with `--check` exit 1 when one differs from the Lean output. -/
def main (args : List String) : IO UInt32 := do
  let dir : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ops"
  let files : List (String × String × Nat) :=
    [("lspreap.jsonl", text, reapCases.length), ("reap.jsonl", stopText, stopCases.length),
      ("reap-idle.jsonl", idleText, idleCases.length), ("reap-one.jsonl", oneText, oneCases.length),
      ("reap-exit.jsonl", exitText, exitCases.length), ("reap-fold.jsonl", foldText, foldCases.length)]
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
