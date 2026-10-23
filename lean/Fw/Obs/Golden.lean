import Fw.Ops.Golden
import Fw.Wire.Obs
import Fw.Obs.Fold
/-!
# Golden vectors of `obs.health`

`packages/contracts/golden/obs/health.jsonl`: one line per case, `{"name", "request", "response"}`, where `request`
carries its `op` and `response` is what `fwcore` replies (without the `id`). Generated from Lean, never by hand:

```
cd lean && lake env lean --run scripts/ObsGolden.lean           # write the file
cd lean && lake env lean --run scripts/ObsGolden.lean --check   # fail if it is stale
```

`lake test` runs the same check and also fails when the typed cases miss a state or an alert code. The cases cover
every state, every alert code, both sides of every threshold edge, the agent-order independence, ignored fields, and
refused requests. Consumers: `fw watch` (`watch-cli`) and the console Health tab (`watch-web`).
(Namespace `Fw.Wire.Obs.Golden`: wire code for the math view.)
-/
namespace Fw.Wire.Obs.Golden
open Lean
open Fw.Obs.Health
open Fw.Wire.Ops.Golden (lit withOp respond)

/-- The observation time of every typed case (ms since the epoch). -/
def t0 : Nat := 1760000000000

/-- A service with the given input groups, its code identified. -/
def sv (n : String) (i : List Fw.Obs.SvcInput) : Fw.Obs.Svc := { name := n, inputs := i }

/-- `m` minutes before `t0`, minus `ms` milliseconds more recent (so `ago 10 1` is 9 min 59.999 s before `t0`). -/
def ago (m : Nat) (ms : Nat := 0) : Nat := t0 - m * msPerMin + ms

/-- A live subagent with its last event `m` minutes ago, started an hour before `t0`. -/
def ag (id : String) (m : Nat) : Agent := { id, startedAt := ago 60, lastAt := ago m }

/-- A live teammate with its last event `m` minutes ago, started an hour before `t0`. -/
def tm (id : String) (m : Nat) : Agent := { ag id m with kind := .teammate }

/-- A live workflow agent with its last event `m` minutes ago, started an hour before `t0`. -/
def wf (id : String) (m : Nat) : Agent := { ag id m with kind := .workflow }

/-- A healthy system: 100 GB free, normal memory, no lock, containers or CI runs, 3 worktrees. -/
def okSys : System := { diskFreeGB := 100, worktrees := 3 }

/-- A stopped agent showing every bad sign (it must raise nothing). -/
def badDone : Agent :=
  { ag "a" 99 with stoppedAt := some (ago 1), errTail := 9, ctxTokens := some 400000,
                   inflight := some ⟨"Bash", ago 99⟩ }

/-- Three agents for the order cases: one stalled with an error streak, one active, one idle over `ctxResumeMax`. -/
def trio : List Agent :=
  [{ ag "x" 25 with errTail := 4 }, ag "y" 0, { ag "z" 12 with ctxTokens := some 260000 }]

/-- A CI run with no end time. -/
def run0 (w b st : String) (c : Option String) (t : Nat) (e : Option Nat := none) (sha : String := "") : CiRun :=
  { workflow := w, branch := b, status := st, conclusion := c, startedAt := t, endedAt := e, headSha := sha }

/-- The open Actions incident of 2026-10-19 (opened 15:49 UTC, impact critical). -/
def ghInc : Fw.Obs.GhIncident :=
  { name := "Degraded availability for GitHub Actions, GitHub Pages and Webhooks", status := "investigating",
    impact := "critical", createdAt := 1792424965828, updatedAt := 1792427429646,
    body := "We’re seeing recovery following mitigation and are continuing to monitor. Customers may still experience delays in GitHub Actions workflow status updates, GitHub Pages deployments, and check and workf",
    actions := true }

/-- A typed case: name, thresholds, observation. -/
structure Typed where
  name : String
  p    : Params := {}
  o    : Obs

/-- The typed cases (encoded with `reqJson`, so every field is written). -/
def typed : List Typed := [
  { name := "empty team, healthy system: no alerts", o := { now := t0, system := okSys } },
  { name := "dead session (alert-rules-fix): an agent whose session pid is not in the process table is done: no stalled, no toolHang, not counted live",
    o := { now := t0, agents := [{ ag "a" 99 with sessionPid := some 100, inflight := some ⟨"Bash", ago 99⟩ }, { ag "b" 99 with sessionPid := some 200, inflight := some ⟨"Bash", ago 99⟩ }],
           system := { okSys with alivePids := some [1, 200] } } },
  { name := "unread process table (alert-rules-fix): no agent is judged by its session pid",
    o := { now := t0, agents := [{ ag "a" 99 with sessionPid := some 100 }], system := okSys } },
  { name := "no session pid (alert-rules-fix): an agent without one is judged as before even when the table is read",
    o := { now := t0, agents := [ag "a" 99], system := { okSys with alivePids := some [1] } } },
  { name := "active: last event 9 min 59.999 s ago (idleMin 10)", o := { now := t0, agents := [{ ag "a" 0 with lastAt := ago 10 1 }], system := okSys } },
  { name := "idle: last event exactly 10 min ago", o := { now := t0, agents := [ag "a" 10], system := okSys } },
  { name := "idle: 19 min 59.999 s ago, just under stallMin 20", o := { now := t0, agents := [{ ag "a" 0 with lastAt := ago 20 1 }], system := okSys } },
  { name := "stalled: exactly 20 min, no tool in flight", o := { now := t0, agents := [ag "a" 20], system := okSys } },
  { name := "idle, not stalled: 20 min silent but its tool has run only 29 min 59.999 s (toolHangMin 30)",
    o := { now := t0, agents := [{ ag "a" 20 with inflight := some ⟨"Bash", ago 30 1⟩ }], system := okSys } },
  { name := "stalled and agent.toolHang: tool in flight exactly 30 min",
    o := { now := t0, agents := [{ ag "a" 30 with inflight := some ⟨"Bash", ago 30⟩ }], system := okSys } },
  { name := "active with agent.toolHang: recent event, tool in flight 45 min",
    o := { now := t0, agents := [{ ag "a" 1 with inflight := some ⟨"Bash", ago 45⟩ }], system := okSys } },
  { name := "parked: a teammate whose last tool was SendMessage, silent 99 min, with 400001 context tokens, raises nothing",
    o := { now := t0, system := okSys,
           agents := [{ tm "a" 99 with lastTool := some "SendMessage", lastToolAt := some (ago 99),
                                       ctxTokens := some 400001, errTail := 5 }] } },
  { name := "parked: a teammate whose TeammateIdle (50 min ago) is newer than its last tool (60 min ago)",
    o := { now := t0, system := okSys,
           agents := [{ tm "a" 50 with lastTool := some "Bash", lastToolAt := some (ago 60), idleAt := some (ago 50) }] } },
  { name := "parked: a teammate with a TeammateIdle and no tool event yet",
    o := { now := t0, system := okSys, agents := [{ tm "a" 45 with idleAt := some (ago 45) }] } },
  { name := "stalled, not parked: a teammate whose TeammateIdle is older than its last tool, or at the same ms",
    o := { now := t0, system := okSys,
           agents := [{ tm "a" 25 with lastTool := some "Bash", lastToolAt := some (ago 25), idleAt := some (ago 40) },
                      { tm "b" 25 with lastTool := some "Bash", lastToolAt := some (ago 25), idleAt := some (ago 25) }] } },
  { name := "stalled, not parked: a subagent whose last tool was SendMessage (only teammates park)",
    o := { now := t0, system := okSys,
           agents := [{ ag "a" 25 with lastTool := some "SendMessage", lastToolAt := some (ago 25) }] } },
  { name := "idle, not parked: a teammate whose last tool was SendMessage but has a tool in flight 25 min",
    o := { now := t0, system := okSys,
           agents := [{ tm "a" 25 with lastTool := some "SendMessage", lastToolAt := some (ago 26),
                                       inflight := some ⟨"Bash", ago 25⟩ }] } },
  { name := "done: a workflow agent whose workflow run finished",
    o := { now := t0, system := okSys, agents := [{ wf "a" 0 with workflowDone := true, errTail := 9 }] } },
  { name := "done: a transcript-only workflow agent silent exactly 30 min (wfQuietMin 30)",
    o := { now := t0, system := okSys, agents := [{ wf "a" 30 with transcriptOnly := true }] } },
  { name := "stalled, not done: a transcript-only workflow agent silent 29 min 59.999 s",
    o := { now := t0, system := okSys, agents := [{ wf "a" 0 with lastAt := ago 30 1, transcriptOnly := true }] } },
  { name := "stalled, not done: a transcript-only subagent silent 99 min (only workflow agents end by silence)",
    o := { now := t0, system := okSys, agents := [{ ag "a" 99 with transcriptOnly := true }] } },
  { name := "wait, not hang: an Agent call in flight 45 min with a live child; a SendMessage the same",
    o := { now := t0, system := okSys,
           agents := [{ tm "p" 1 with inflight := some ⟨"Agent", ago 45⟩ }, { ag "c" 0 with parent := some "p" },
                      { tm "q" 1 with inflight := some ⟨"SendMessage", ago 45⟩ }, { ag "d" 0 with parent := some "q" }] } },
  { name := "agent.toolHang: an Agent call in flight 45 min whose only child is done; a Bash call with a live child",
    o := { now := t0, system := okSys,
           agents := [{ tm "p" 1 with inflight := some ⟨"Agent", ago 45⟩ },
                      { ag "c" 0 with parent := some "p", stoppedAt := some (ago 2) },
                      { tm "q" 1 with inflight := some ⟨"Bash", ago 45⟩ }, { ag "d" 0 with parent := some "q" }] } },
  { name := "team.permissionWait: a Notification (3 min ago) newer than the lead's last tool call (5 min ago)",
    o := { now := t0, system := okSys, lead := { lastToolAt := some (ago 5), noteAt := some (ago 3) } } },
  { name := "team.permissionWait: a Notification and no lead tool event yet",
    o := { now := t0, system := okSys, lead := { noteAt := some (ago 7) } } },
  { name := "no alert: the lead called a tool after the Notification, or at the same ms",
    o := { now := t0, system := okSys, lead := { lastToolAt := some (ago 3), noteAt := some (ago 3) } } },
  { name := "done: a stopped agent with every bad sign raises nothing",
    o := { now := t0, system := okSys, agents := [badDone] } },
  { name := "lastAt after now: age 0, active", o := { now := t0, agents := [{ ag "a" 0 with lastAt := t0 + 5000 }], system := okSys } },
  { name := "errStreak 3: errTail 2 no alert, errTail 3 agent.errStreak",
    o := { now := t0, agents := [{ ag "a" 0 with errTail := 2 }, { ag "b" 0 with errTail := 3 }], system := okSys } },
  { name := "errStreak 0: errTail 0 still raises nothing, errTail 1 does", p := { errStreak := 0 },
    o := { now := t0, agents := [ag "a" 0, { ag "b" 0 with errTail := 1 }], system := okSys } },
  { name := "context edges: 200000 none, 200001 ctxWarn, 250000 ctxWarn, 250001 ctxHigh and ctxWarn, unknown none",
    o := { now := t0, system := okSys,
           agents := [{ ag "a" 0 with ctxTokens := some 200000 }, { ag "b" 0 with ctxTokens := some 200001 },
                      { ag "c" 0 with ctxTokens := some 250000 }, { ag "d" 0 with ctxTokens := some 250001 },
                      ag "e" 0] } },
  { name := "agentCap 10: 10 live non-lead agents, plus the lead, a stopped agent and a finished workflow agent, raise nothing",
    o := { now := t0, system := okSys,
           agents := (List.range 10).map (fun i => ag s!"w{i}" 0) ++
             [{ ag "lead" 0 with kind := .lead }, { ag "old" 0 with stoppedAt := some (ago 5) },
              { wf "wf-old" 0 with workflowDone := true }] } },
  { name := "agentCap 10: 11 live agents raise team.overCap, counted by kind and parent link",
    o := { now := t0, system := okSys,
           agents := (List.range 5).map (fun i => tm s!"t{i}" 0) ++
             (List.range 4).map (fun i => { ag s!"s{i}" 0 with parent := some "t0" }) ++
             (List.range 2).map (fun i => { wf s!"f{i}" 0 with parent := some "t1" }) } },
  { name := "diskMinGB 20: 20 GB free none", o := { now := t0, system := { okSys with diskFreeGB := 20 } } },
  { name := "diskMinGB 20: 19 GB free sys.diskLow", o := { now := t0, system := { okSys with diskFreeGB := 19 } } },
  { name := "memory warn: no alert", o := { now := t0, system := { okSys with memPressure := .warn } } },
  { name := "memory critical: sys.memCritical", o := { now := t0, system := { okSys with memPressure := .critical } } },
  { name := "sim lock held 29 min 59.999 s by a live agent (named by task): no alert",
    o := { now := t0, agents := [{ ag "a" 0 with task := some "wktr-local" }],
           system := { okSys with simLock := { holder := some "wktr-local", since := some (ago 30 1) } } } },
  { name := "sim lock held exactly 30 min by a live agent (named by id): sim.lockLong",
    o := { now := t0, agents := [ag "a" 0],
           system := { okSys with simLock := { holder := some "a", since := some (ago 30) } } } },
  { name := "sim lock holder is done: sim.lockOrphan",
    o := { now := t0, agents := [{ ag "a" 0 with name := some "sim-runner", stoppedAt := some (ago 2) }],
           system := { okSys with simLock := { holder := some "sim-runner", since := some (ago 5) } } } },
  { name := "sim lock holder names no agent: sim.lockOrphan",
    o := { now := t0, agents := [ag "a" 0], system := { okSys with simLock := { holder := some "ghost" } } } },
  { name := "svc.stale: only the inputs touched by main since the base commit are named: svc.stale lists the changed paths",
    o := { now := t0, system := { okSys with svcs := [
      sv "console-api" [⟨"apps/console-api/src", true⟩, ⟨"lean/Fw", false⟩, ⟨"apps/console-web/dist", false⟩]] } } },
  { name := "svc.stale: no input touched since the base commit (also a service with no inputs): no alert",
    o := { now := t0, system := { okSys with svcs := [
      sv "console-api" [⟨"apps/console-api/src", false⟩, ⟨"lean/Fw", false⟩], sv "fwcore" []] } } },
  { name := "svc.stale: console-api restarted but the fwcore binary not rebuilt: only fwcore is stale",
    o := { now := t0, system := { okSys with svcs := [
      sv "console-api" [⟨"apps/console-api/src", false⟩, ⟨"lean/Fw", false⟩], sv "fwcore" [⟨"lean/Fw", true⟩, ⟨"lean/lakefile.toml", false⟩]] } } },
  { name := "svc.stale: two stale services give two alerts in subject order",
    o := { now := t0, system := { okSys with svcs := [
      sv "fwcore" [⟨"lean/Fw", true⟩], sv "console-api" [⟨"apps/console-api/src", true⟩]] } } },
  { name := "svc.unknown: the build commit of the fwcore binary cannot be identified: an alert, not silence",
    o := { now := t0, system := { okSys with svcs := [
      { name := "fwcore", unknown := some "no main ref move at or before the binary" }] } } },
  { name := "svc.unknown and svc.stale together: console-api has a changed own input and an unidentifiable core child",
    o := { now := t0, system := { okSys with svcs := [
      { name := "console-api", inputs := [⟨"apps/console-api/src", true⟩], unknown := some "api.json records no core build commit" },
      sv "fwcore" [⟨"lean/Fw", false⟩]] } } },
  { name := "svc.sweepError: the console-api drain caught 3 fwcore throws: a counted alert, not silence (task task-state-truth)",
    o := { now := t0, system := { okSys with svcs := [
      { name := "console-api", inputs := [⟨"apps/console-api/src", false⟩], sweepErrors := 3 }, sv "fwcore" [⟨"lean/Fw", false⟩]] } } },
  { name := "sim lock with no holder: no alert",
    o := { now := t0, system := { okSys with simLock := { since := some (ago 90) } } } },
  { name := "ci: a failure superseded by a later success, a running run, a cancelled run: no alert",
    o := { now := t0, system := { okSys with ci := [
      ⟨"lean", "ci/x", "completed", some "failure", ago 30, none, ""⟩, ⟨"lean", "ci/x", "completed", some "success", ago 20, none, ""⟩,
      ⟨"lean", "ci/y", "in_progress", none, ago 3, none, ""⟩, ⟨"site", "ci/x", "completed", some "cancelled", ago 9, none, ""⟩] } } },
  { name := "ci: the latest run of lean@ci/x failed, of site@ci/x timed out: ci.failed twice",
    o := { now := t0, system := { okSys with ci := [
      ⟨"lean", "ci/x", "completed", some "success", ago 30, none, ""⟩, ⟨"lean", "ci/x", "completed", some "failure", ago 20, none, ""⟩,
      ⟨"site", "ci/x", "completed", some "timed_out", ago 9, none, ""⟩] } } },
  { name := "ci set: lean@ci/x@abc has one failed run among completed ones (cancelled, success): one ci.failed; a second failed run of the same set adds none",
    o := { now := t0, system := { okSys with ci := [
      run0 "lean" "ci/x" "completed" (some "failure") (ago 30) none "abc", run0 "lean" "ci/x" "completed" (some "cancelled") (ago 25) none "abc",
      run0 "lean" "ci/x" "completed" (some "failure") (ago 20) none "abc"] } } },
  { name := "ci set: a run of the same set still running makes the set pending: no ci.failed until it ends",
    o := { now := t0, system := { okSys with ci := [
      run0 "lean" "ci/x" "completed" (some "failure") (ago 30) none "abc", run0 "lean" "ci/x" "in_progress" none (ago 3) none "abc"] } } },
  { name := "ci set: a push (new sha) after a failure supersedes it; two shas of the failing branch, the older failed, the newer green: no alert",
    o := { now := t0, system := { okSys with ci := [
      run0 "lean" "ci/x" "completed" (some "failure") (ago 30) none "abc", run0 "lean" "ci/x" "completed" (some "success") (ago 10) none "def"] } } },
  { name := "ciSlowBy: breakpoint-gate may run 40 min (30 min in progress is fine), another workflow at 30 min is ci.slow",
    o := { now := t0, system := { okSys with ci := [run0 "breakpoint-gate" "ci/x" "in_progress" none (ago 30),
                                                    run0 "lean" "ci/x" "in_progress" none (ago 30)] } } },
  { name := "ciSlowBy [lean 10]: lean at 11 min in progress is ci.slow, breakpoint-gate (no entry) uses the global 20",
    p := { ciSlowBy := [("lean", 10)] },
    o := { now := t0, system := { okSys with ci := [run0 "lean" "ci/x" "in_progress" none (ago 11),
                                                    run0 "breakpoint-gate" "ci/x" "in_progress" none (ago 11)] } } },
  { name := "docker: a container older than every live agent is docker.orphan; one started after a live agent is not",
    o := { now := t0, agents := [{ ag "a" 0 with startedAt := ago 50 }, { ag "b" 0 with startedAt := ago 90, stoppedAt := some (ago 1) }],
           system := { okSys with docker := [⟨"c0ffee", "pg-old", ago 80⟩, ⟨"beef01", "pg-new", ago 50⟩] } } },
  { name := "worktreesMax 20: 20 worktrees none", o := { now := t0, system := { okSys with worktrees := 20 } } },
  { name := "worktreesMax 20: 21 worktrees worktrees.many", o := { now := t0, system := { okSys with worktrees := 21 } } },
  { name := "agent order A: three agents",
    o := { now := t0, system := okSys, agents := trio } },
  { name := "agent order B: the same agents reversed give the same alerts and counts (rows follow the input)",
    o := { now := t0, system := okSys, agents := trio.reverse } },
  { name := "gone: silent exactly 120 min is stalled, 120 min 0.001 s is gone (agent.gone on the first check); a gone agent leaves the cap (agentCap 1)",
    p := { agentCap := 1 },
    o := { now := t0, agents := [{ ag "a" 120 with startedAt := ago 200 }, { ag "b" 0 with startedAt := ago 200, lastAt := ago 120 - 1 }],
           system := okSys } },
  { name := "gone since the previous check (5 min ago): agent.gone for b only; c was already gone then",
    o := { now := t0, prevAt := some (ago 5),
           agents := [{ ag "b" 124 with startedAt := ago 200 }, { ag "c" 130 with startedAt := ago 200 }], system := okSys } },
  { name := "toolSlow 15: a Bash call in flight exactly 15 min is not slow, 15 min 0.001 s is agent.toolSlow",
    o := { now := t0, agents := [{ ag "a" 0 with inflight := some ⟨"Bash", ago 15⟩ },
                                 { ag "b" 0 with inflight := some ⟨"Bash", ago 15 - 1⟩ }], system := okSys } },
  { name := "ciSlowMin 20: in progress exactly 20 min is not slow, queued 20 min 0.001 s is ci.slow",
    o := { now := t0, system := { okSys with ci := [run0 "lean" "ci/x" "in_progress" none (ago 20),
                                                    run0 "site" "ci/y" "queued" none (ago 20 - 1)] } } },
  { name := "gh-status: Actions degraded_performance with an open Actions incident raises sys.ghDegraded, and the queued ci.slow run names the incident",
    o := { now := t0, system := { okSys with ci := [run0 "lean" "ci/x" "queued" none (ago 30)],
                                              gh := { actions := .degradedPerf, pages := .degradedPerf, webhooks := .degradedPerf,
                                                      incidents := [ghInc] } } } },
  { name := "gh-status: Actions operational closes the flag even when the previous pass flagged it; the slow run is unchanged",
    o := { now := t0, system := { okSys with ci := [run0 "lean" "ci/x" "queued" none (ago 30)],
                                              gh := { actions := .operational, prevDegraded := true, incidents := [ghInc] } } } },
  { name := "gh-status: fetch failure (unknown) after a flagged pass keeps sys.ghDegraded and the incident",
    o := { now := t0, system := { okSys with ci := [run0 "lean" "ci/x" "in_progress" none (ago 30)],
                                              gh := { prevDegraded := true, incidents := [ghInc] } } } },
  { name := "gh-status: fetch failure (unknown) after a clear pass raises nothing",
    o := { now := t0, system := { okSys with ci := [run0 "lean" "ci/x" "in_progress" none (ago 30)], gh := {} } } },
  { name := "ci data age: a run list 4 min old (the fresh limit) adds no note to the ci.slow detail",
    o := { now := t0, system := { okSys with ci := [run0 "lean" "ci/x" "in_progress" none (ago 30)],
                                              gh := { ciAgeMs := 240000 } } } },
  { name := "ci data age: a run list carried 22 min (a failed gh run list) ends the ci.slow detail with its age",
    o := { now := t0, system := { okSys with ci := [run0 "lean" "ci/x" "in_progress" none (ago 30)],
                                              gh := { ciAgeMs := 22 * 60000 + 5000 } } } },
  { name := "gh-status: partial_outage and major_outage flag Actions; an incident that does not touch Actions is not named",
    o := { now := t0, system := { okSys with ci := [run0 "lean" "ci/x" "queued" none (ago 30)],
                                              gh := { actions := .partialOutage, webhooks := .majorOutage,
                                                      incidents := [{ ghInc with name := "Webhooks delayed", actions := false }] } } } },
  { name := "gh-status: under_maintenance flags Actions",
    o := { now := t0, system := { okSys with gh := { actions := .maintenance, pages := .operational } } } },
  { name := "ci.finished: the run the previous check saw running 23 min ended since (success after 25 min); runs ended before that check or not yet slow then report nothing",
    o := { now := t0, prevAt := some (ago 2),
           system := { okSys with ci := [run0 "lean" "ci/x" "completed" (some "success") (ago 25) (some t0),
                                         run0 "site" "ci/x" "completed" (some "success") (ago 40) (some (ago 3)),
                                         run0 "e2e" "ci/z" "completed" (some "success") (ago 21) (some (ago 1))] } } },
  { name := "critical path [t1]: alerts of agent t1-2 and of a run on ci/t1 rank first (critical true)",
    o := { now := t0, critical := ["t1"],
           agents := [{ ag "a" 0 with errTail := 3 }, { ag "t1-2" 0 with errTail := 3 }, { ag "t10" 0 with errTail := 3 }],
           system := { okSys with ci := [run0 "lean" "ci/t2" "completed" (some "failure") (ago 9),
                                         run0 "lean" "ci/t1" "completed" (some "failure") (ago 9)] } } },
  { name := "procMaxMin 20: alive exactly 20 min is fine, 20 min 0.001 s is proc.long; a tree holding a service pid never is",
    o := { now := t0, system := { okSys with
             procs := [{ pid := 10, name := "node", startedAt := ago 20 },
                       { pid := 11, name := "sleep", startedAt := ago 20 - 1, pids := [12] },
                       { pid := 20, name := "node", startedAt := ago 90, pids := [21] }],
             services := [21] } } },
  { name := "declared long-runners never raise proc.long: caffeinate (allowlist), a tree holding a pid the lead declared (keep); an undeclared Python does",
    o := { now := t0, system := { okSys with
             procs := [{ pid := 30, name := "caffeinate", startedAt := ago 240, pids := [31] },
                       { pid := 40, name := "Python", startedAt := ago 90, pids := [41] },
                       { pid := 50, name := "Python", startedAt := ago 90, pids := [51] }],
             keep := [41] } } },
  { name := "owner: a live agent's sleep loop is quiet; trees of a stopped, a gone and an unknown agent are orphans (proc.long naming the agent); the lead's tree is proc.long",
    o := { now := t0,
           agents := [ag "live" 1, { ag "done" 30 with stoppedAt := some (ago 30) }, { ag "gone" 121 with startedAt := ago 300 }],
           system := { okSys with
             procs := [{ pid := 60, name := "sleep", startedAt := ago 50, pids := [61], agent := some "live" },
                       { pid := 70, name := "sleep", startedAt := ago 50, pids := [71], agent := some "done" },
                       { pid := 80, name := "sleep", startedAt := ago 150, pids := [81], agent := some "gone" },
                       { pid := 90, name := "gh", startedAt := ago 50, pids := [91], agent := some "lost" },
                       { pid := 95, name := "node", startedAt := ago 50, pids := [96] }] } } },
  { name := "owner: an orphan of a stopped agent alive exactly procMaxMin (20 min) is still fine",
    o := { now := t0,
           agents := [{ ag "done" 30 with stoppedAt := some (ago 30) }],
           system := { okSys with
             procs := [{ pid := 70, name := "sleep", startedAt := ago 20, pids := [71], agent := some "done" }] } } },
  { name := "review.feedback: a user comment opens an alert for its flag (open count and the newest text in the detail)",
    o := { now := t0, system := { okSys with feedback := [.post "nav:a" "fb-1" "look at the font" 100] } } },
  { name := "review.feedback: the lead's reply to the only open comment closes the alert",
    o := { now := t0, system := { okSys with feedback := [.post "nav:a" "fb-1" "look at the font" 100, .reply "nav:a" "fb-1" "done" 110] } } },
  { name := "review.feedback: one alert per flag with two open comments; the answered flag has none; a refused reply changes nothing",
    o := { now := t0, system := { okSys with feedback := [.post "nav:a" "fb-1" "one" 100, .post "hero:b" "fb-2" "x" 101,
             .post "nav:a" "fb-3" "two" 102, .reply "hero:b" "fb-2" "ok" 103, .reply "nav:a" "fb-9" "nope" 104] } } },
  { name := "step.question: a user question on a step opens an alert for step:<id> (and no review.feedback alert)",
    o := { now := t0, system := { okSys with feedback := [.post "step:s1" "fb-1" "what does this step change?" 100] } } },
  { name := "step.question: a question on a topic opens an alert for topic:<id>; the lead's reply to the only open one closes it",
    o := { now := t0, system := { okSys with feedback := [.post "topic:smoothness" "fb-1" "why this order?" 100, .post "topic:jev" "fb-2" "status?" 101,
             .reply "topic:smoothness" "fb-1" "because the phone" 110] } } },
  { name := "step.question: a step question beside a review comment gives one alert of each kind; a reply on the wrong subject changes nothing",
    o := { now := t0, system := { okSys with feedback := [.post "nav:a" "fb-1" "font" 100, .post "step:s1" "fb-2" "why" 101,
             .reply "step:other" "fb-2" "no" 102] } } },
  { name := "loadMax 150: load floor 149 is fine", o := { now := t0, system := { okSys with loadFloor := 149 } } },
  { name := "loadMax 150: load floor 150 is load.high", o := { now := t0, system := { okSys with loadFloor := 150 } } },
  { name := "contendedLoad 8: load floor 8 is not sys.contended", o := { now := t0, system := { okSys with loadFloor := 8 } } },
  { name := "contendedLoad 8: load floor 9 is sys.contended, with the builders and heavy jobs in the detail",
    o := { now := t0, system := { okSys with loadFloor := 9, load := { builders := 4, heavyJobs := 2 } } } },
  { name := "every code at once, with tight thresholds",
    p := { idleMin := 1, stallMin := 2, toolHangMin := 3, errStreak := 1, ctxResumeMax := 100, ctxWarn := 50,
           diskMinGB := 500, agentCap := 1, simLockMaxMin := 1, worktreesMax := 1 },
    o := { now := t0,
           agents := [{ ag "a" 5 with inflight := some ⟨"Bash", ago 5⟩, errTail := 1, ctxTokens := some 101 },
                      ag "b" 0, ag "c" 1, { ag "d" 0 with stoppedAt := some (ago 1) }],
           lead := { lastToolAt := some (ago 2), noteAt := some (ago 1) },
           system := { diskFreeGB := 100, memPressure := .critical, simLock := { holder := some "d", since := some (ago 1) },
                       docker := [⟨"c1", "orphan", ago 120⟩], worktrees := 2,
                       ci := [⟨"lean", "main", "completed", some "startup_failure", ago 3, none, ""⟩] } } },
  { name := "the same snapshot with default thresholds: fewer alerts (loosening never adds one)",
    o := { now := t0,
           agents := [{ ag "a" 5 with inflight := some ⟨"Bash", ago 5⟩, errTail := 1, ctxTokens := some 101 },
                      ag "b" 0, ag "c" 1, { ag "d" 0 with stoppedAt := some (ago 1) }],
           lead := { lastToolAt := some (ago 2), noteAt := some (ago 1) },
           system := { diskFreeGB := 100, memPressure := .critical, simLock := { holder := some "d", since := some (ago 1) },
                       docker := [⟨"c1", "orphan", ago 120⟩], worktrees := 2,
                       ci := [⟨"lean", "main", "completed", some "startup_failure", ago 3, none, ""⟩] } } }]

/-- Literal cases: optional and ignored fields, and refused requests. -/
def literal : List (String × Json) := [
  ("params and lead omitted (defaults); ignored fields accepted: load1 (fractional), consolePids, stale, type, model, tools, errors, tokens, inflight.verb, and the retired depth and waitingPermission",
   lit "{\"now\":1760000000000,\"agents\":[{\"id\":\"a\",\"name\":null,\"task\":\"t1\",\"type\":\"lean-prover\",\"model\":\"opus\",\"depth\":1,\"startedAt\":1759999000000,\"lastAt\":1759999990000,\"stoppedAt\":null,\"tools\":12,\"errors\":1,\"errTail\":0,\"inflight\":{\"tool\":\"Bash\",\"verb\":\"lake build\",\"since\":1759999990000},\"waitingPermission\":false,\"ctxTokens\":null,\"tokens\":{\"in\":10,\"out\":20,\"cacheRead\":30,\"cacheWrite\":40}}],\"system\":{\"load1\":3.25,\"memPressure\":\"normal\",\"diskFreeGB\":120,\"simLock\":{\"holder\":null,\"since\":null},\"docker\":[],\"worktrees\":4,\"consolePids\":[123],\"stale\":[\"ci\"],\"ci\":[]}}"),
  ("minimal: only now and system.diskFreeGB", lit "{\"now\":0,\"system\":{\"diskFreeGB\":50}}"),
  ("refused: a fractional diskFreeGB (floor it)", lit "{\"now\":0,\"system\":{\"diskFreeGB\":20.5}}"),
  ("refused: unknown memPressure", lit "{\"now\":0,\"system\":{\"diskFreeGB\":50,\"memPressure\":\"high\"}}"),
  ("refused: system missing", lit "{\"now\":0,\"agents\":[]}"),
  ("refused: an unknown agent kind", lit "{\"now\":0,\"agents\":[{\"id\":\"a\",\"kind\":\"robot\",\"startedAt\":0,\"lastAt\":0}],\"system\":{\"diskFreeGB\":50}}"),
  ("lead given alone, kind and parent given: a teammate and its helper",
   lit "{\"now\":1760000000000,\"lead\":{\"lastToolAt\":1759999990000},\"agents\":[{\"id\":\"t\",\"kind\":\"teammate\",\"startedAt\":1759999000000,\"lastAt\":1759999990000,\"lastTool\":\"SendMessage\",\"lastToolAt\":1759999990000},{\"id\":\"h\",\"parent\":\"t\",\"startedAt\":1759999000000,\"lastAt\":1759999990000}],\"system\":{\"diskFreeGB\":50}}"),
  ("refused: an agent without lastAt", lit "{\"now\":0,\"agents\":[{\"id\":\"a\",\"startedAt\":0}],\"system\":{\"diskFreeGB\":50}}"),
  ("refused: a negative threshold", lit "{\"now\":0,\"params\":{\"idleMin\":-1},\"system\":{\"diskFreeGB\":50}}"),
  ("optional watch fields: prevAt null, critical omitted, a process without pids, a run with endedAt null",
   lit "{\"now\":1760000000000,\"prevAt\":null,\"system\":{\"diskFreeGB\":50,\"loadFloor\":3,\"procs\":[{\"pid\":5,\"name\":\"sh\",\"startedAt\":0}],\"services\":[7],\"ci\":[{\"workflow\":\"w\",\"branch\":\"b\",\"status\":\"completed\",\"conclusion\":\"success\",\"startedAt\":0,\"endedAt\":null}]}}"),
  ("watch-proc-allow fields: agent null and agent omitted are the lead's trees, keep omitted is empty, keep [9] declares a tree",
   lit "{\"now\":1760000000000,\"system\":{\"diskFreeGB\":50,\"procs\":[{\"pid\":5,\"name\":\"sh\",\"startedAt\":0,\"agent\":null},{\"pid\":8,\"name\":\"sh\",\"startedAt\":0,\"pids\":[9]},{\"pid\":10,\"name\":\"sh\",\"startedAt\":0,\"agent\":\"x\"}],\"keep\":[9]}}"),
  ("refused: a keep pid that is not a natural number",
   lit "{\"now\":0,\"system\":{\"diskFreeGB\":50,\"keep\":[\"9\"]}}"),
  ("refused: a fractional loadFloor (floor it)", lit "{\"now\":0,\"system\":{\"diskFreeGB\":50,\"loadFloor\":2.5}}")]

/-- Every case as (name, request body). -/
def cases (_ : Unit := ()) : List (String × Json) := typed.map (fun c => (c.name, reqJson c.p c.o)) ++ literal

/-- Coverage gaps of the typed cases: states and alert codes no case produces (empty when complete). -/
def gaps (_ : Unit := ()) : List String :=
  let reps := typed.map fun c => health c.p c.o
  let states := reps.flatMap fun r => r.agents.map (·.state)
  let codes := reps.flatMap fun r => r.alerts.map (·.code)
  ([State.active, .idle, .parked, .stalled, .gone, .done].filter (!states.contains ·)).map (fun s => s!"state {Fw.Wire.Obs.stateName s}") ++
  (Code.all.filter (!codes.contains ·)).map (fun c => s!"code {c.name}")

#guard gaps == []

/-- The text of the golden file. -/
def fileText (_ : Unit := ()) : String :=
  String.join (cases.map fun (name, req) =>
    (Json.mkObj [("name", .str name), ("request", withOp "obs.health" req),
      ("response", respond "obs.health" req)]).compress ++ "\n")

/-- An `obs.backoff` case: name, params, core count, load, base deadline, ms already waited. -/
structure BackoffCase where
  name   : String
  p      : Fw.Obs.Backoff.Params := {}
  cores  : Nat := 8
  load   : Nat
  base   : Nat := 10000
  waited : Nat := 10000
  noParams : Bool := false

/-- The `obs.backoff` cases: both sides of `load = cores`, the wait, the restart after it, and the edges of the total. -/
def backoffCases : List BackoffCase := [
  { name := "not loaded (load 3): a call that missed its 10 s deadline restarts the child", load := 3 },
  { name := "8 cores, load 7, one under the core count: restart at the first deadline", load := 7 },
  { name := "8 cores, load 8 = cores: wait 20 s more (total 30 s) instead of killing", load := 8 },
  { name := "8 cores, load 10 (the 2026-10-20 replay incident): wait 20 s more", load := 10 },
  { name := "2 cores, load 2: wait 20 s more", cores := 2, load := 2 },
  { name := "64 cores, load 50: not loaded, restart", cores := 64, load := 50 },
  { name := "0 cores reads as 1: load 1 waits", cores := 0, load := 1 },
  { name := "load 115 (the sweepError storm): wait 20 s more", load := 115 },
  { name := "load 115, waited the whole 30 s: restart", load := 115, waited := 30000 },
  { name := "load 115, waited 29.999 s: wait the last 1 ms", load := 115, waited := 29999 },
  { name := "load fell to 3 while waiting: restart at once", load := 3, waited := 20000 },
  { name := "replay chunk (base 120 s), load 115: wait 240 s more", load := 115, base := 120000, waited := 120000 },
  { name := "no params in the request: the default extra 2 applies", load := 115, noParams := true },
  { name := "extra 0: loaded or not, restart at the first deadline", p := { extra := 0 }, load := 115 },
  { name := "extra 5, base 1 s, 10 cores, load 10: wait 5 s more", p := { extra := 5 }, cores := 10, load := 10, base := 1000, waited := 1000 }]

/-- The text of the `obs.backoff` golden file. -/
def backoffText : String :=
  String.join (backoffCases.map fun c =>
    let params := if c.noParams then [] else
      [("params", Json.mkObj [("extra", toJson c.p.extra)])]
    let req := Json.mkObj ([("op", .str "obs.backoff")] ++ params ++
      [("cores", toJson c.cores), ("load", toJson c.load), ("baseMs", toJson c.base), ("waitedMs", toJson c.waited)])
    (Json.mkObj [("name", .str c.name), ("request", req),
      ("response", Json.mkObj (Fw.Wire.Obs.Backoff.decisionJson
        (Fw.Obs.Backoff.onTimeout c.p c.cores c.load c.base c.waited)))]).compress ++ "\n")

/-- The `obs.backoff` golden file, relative to `lean/`. -/
def backoffPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "obs" / "backoff.jsonl"

/-- The golden file, relative to `lean/`. -/
def path : System.FilePath := ".." / "packages" / "contracts" / "golden" / "obs" / "health.jsonl"

/-- Compare (or write) the golden file; returns the number of failures (stale file or coverage gaps). -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / path
  let mut bad := 0
  if write then
    IO.FS.createDirAll (root / ".." / "packages" / "contracts" / "golden" / "obs")
    IO.FS.writeFile p fileText
    IO.FS.writeFile (root / backoffPath) backoffText
    IO.FS.writeFile (root / Fw.Obs.Fold.goldenPath) Fw.Obs.Fold.goldenText
    IO.FS.writeFile (root / Fw.Obs.Fold.inflightGoldenPath) Fw.Obs.Fold.inflightGoldenText
    IO.FS.writeFile (root / Fw.Wire.Obs.Push.goldenPath) Fw.Wire.Obs.Push.goldenText
  else
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != fileText then
      IO.println s!"obs golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/ObsGolden.lean)"
      bad := bad + 1
    let curB ← try IO.FS.readFile (root / backoffPath) catch _ => pure ""
    if curB != backoffText then
      IO.println s!"obs golden: {root / backoffPath} is stale (regenerate: cd lean && lake env lean --run scripts/ObsGolden.lean)"
      bad := bad + 1
    let curF ← try IO.FS.readFile (root / Fw.Obs.Fold.goldenPath) catch _ => pure ""
    if curF != Fw.Obs.Fold.goldenText then
      IO.println s!"obs golden: {root / Fw.Obs.Fold.goldenPath} is stale (regenerate: cd lean && lake env lean --run scripts/ObsGolden.lean)"
      bad := bad + 1
    let curI ← try IO.FS.readFile (root / Fw.Obs.Fold.inflightGoldenPath) catch _ => pure ""
    if curI != Fw.Obs.Fold.inflightGoldenText then
      IO.println s!"obs golden: {root / Fw.Obs.Fold.inflightGoldenPath} is stale (regenerate: cd lean && lake env lean --run scripts/ObsGolden.lean)"
      bad := bad + 1
    let curP ← try IO.FS.readFile (root / Fw.Wire.Obs.Push.goldenPath) catch _ => pure ""
    if curP != Fw.Wire.Obs.Push.goldenText then
      IO.println s!"obs golden: {root / Fw.Wire.Obs.Push.goldenPath} is stale (regenerate: cd lean && lake env lean --run scripts/ObsGolden.lean)"
      bad := bad + 1
  for g in gaps do
    IO.println s!"obs golden: no case covers {g}"
    bad := bad + 1
  IO.println s!"obs golden: {cases.length} cases, {if write then "written" else s!"{bad} failures"}"
  return bad

end Fw.Wire.Obs.Golden
