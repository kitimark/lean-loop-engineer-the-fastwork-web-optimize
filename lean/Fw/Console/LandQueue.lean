import Lean.Data.Json
import Fw.Console.LandVerdict
/-!
# `fw land --queue`: lands in first-in-first-out order by one runner

Incident rows `inc-land-waiters-pgrep` (a shell queue deadlocked because `pgrep -f` matched its own command line),
`inc-land-retry-text-match` (the queue retried a finished land because a loose `busy` pattern matched a Lean warning that
named `dispatch_busy`) and `inc-watch-unlanded-queued` (`fw watch` raised `agent.unlanded` for branches already queued).

Model. The queue is an append-only log of events, `.fw-console/land-queue.jsonl`; nobody writes a "state". The pending list
is the fold of the log: `enq e` appends the entry unless its task is already pending (so enqueueing twice is one entry);
`res t k` removes the task's entry. The runner lands the head of the pending list; after an attempt that ended in kind `k`
it retries only for `busy` and `dirty`, at most `max` times, and otherwise records `res`. Process identity is the pair
(pid, start time) of the runner's lock, never a pattern of a command line.

Premises (registry rows in `premises`): appending one short line to a file is atomic for concurrent enqueuers, the start
time printed by `ps` identifies one incarnation of a pid, and a land's exit code and `VERDICT` line (not prose) carry its
kind (`Fw.Console.LandVerdict`).

Golden vectors: `packages/contracts/golden/console/land-queue.jsonl` (ops `landQueue.pending`, `landQueue.queued`,
`landQueue.retry`, `landQueue.live`). Write or check with `scripts/LandQueueGolden.lean`.
-/
namespace Fw.Console.LandQueue
open Fw.Console.LandVerdict

/-- A queued land: the task and the branch to land. -/
structure Entry where
  task : String
  branch : String
deriving DecidableEq, Repr

/-- A line of the queue log: an entry enqueued, or the final result of a task's land. -/
inductive Ev where
  | enq (e : Entry)
  | res (task : String) (k : Kind)
deriving DecidableEq, Repr

/-- One event applied to the pending list: `enq` appends unless the task is pending, `res` removes the task. -/
def step (q : List Entry) : Ev → List Entry
  | .enq e => if q.any (·.task == e.task) then q else q ++ [e]
  | .res t _ => q.filter (·.task != t)

/-- The pending list of a log: the fold of `step` from the empty queue. -/
def pending (log : List Ev) : List Entry := log.foldl step []

/-- The entry the runner lands next: the head of the pending list. -/
def next (q : List Entry) : Option Entry := q.head?

/-- Is a branch a pending entry? This is the `landQueued` fact of `fw next` / `fw watch` (`Fw.Obs.Next.Branch.inLandQueue`). -/
def queued (q : List Entry) (b : String) : Bool := q.any (·.branch == b)

/-- Appending an event to a log applies it to the pending list. -/
theorem pending_append (log : List Ev) (v : Ev) : pending (log ++ [v]) = step (pending log) v := by
  simp [pending, List.foldl_append]

/-- **Enqueueing twice is enqueueing once.** -/
theorem enq_idem (q : List Entry) (e : Entry) : step (step q (.enq e)) (.enq e) = step q (.enq e) := by
  by_cases h : q.any (·.task == e.task) = true
  · simp [step, h]
  · simp only [step, h, ite_false]
    simp

/-- The tasks of the pending list never repeat (the invariant behind the first-in-first-out theorems). -/
theorem step_nodup (q : List Entry) (v : Ev) (h : (q.map (·.task)).Nodup) : ((step q v).map (·.task)).Nodup := by
  cases v with
  | enq e =>
    by_cases hq : q.any (·.task == e.task) = true
    · simp [step, hq, h]
    · simp only [step, hq, Bool.false_eq_true, ite_false, List.map_append, List.map_cons, List.map_nil]
      rw [List.nodup_append]
      refine ⟨h, by simp, ?_⟩
      intro a ha b hb
      simp only [List.mem_singleton] at hb
      subst hb
      intro hab
      subst hab
      apply hq
      obtain ⟨x, hx, hxe⟩ := List.mem_map.mp ha
      simp only [List.any_eq_true, beq_iff_eq]
      exact ⟨x, hx, hxe⟩
  | res t k =>
    simp only [step]
    exact h.sublist ((List.filter_sublist).map _)

/-- The pending list of any log has no repeated task. -/
theorem pending_nodup (log : List Ev) : ((pending log).map (·.task)).Nodup := by
  unfold pending
  suffices ∀ (l : List Ev) (q : List Entry), (q.map (·.task)).Nodup → ((l.foldl step q).map (·.task)).Nodup from
    this log [] (by simp)
  intro l
  induction l with
  | nil => intro q h; simpa using h
  | cons v l ih => intro q h; exact ih _ (step_nodup q v h)

/-- **First in, first out (enqueue).** A new task goes to the end of the pending list; the entries before it keep their order. -/
theorem enq_appends (log : List Ev) (e : Entry) (h : (pending log).any (·.task == e.task) = false) :
    pending (log ++ [.enq e]) = pending log ++ [e] := by
  rw [pending_append]
  simp [step, h]

/-- **First in, first out (land).** When the runner has landed the head of the pending list and records its result, the rest of
the list is what remains, in order. -/
theorem res_head (log : List Ev) (hd : Entry) (tl : List Entry) (k : Kind) (h : pending log = hd :: tl) :
    pending (log ++ [.res hd.task k]) = tl := by
  have hn := pending_nodup log
  rw [h] at hn
  rw [pending_append, h]
  simp only [step, List.filter_cons]
  have hnot : ∀ x ∈ tl, x.task ≠ hd.task := by
    intro x hx hxe
    simp only [List.map_cons, List.nodup_cons, List.mem_map] at hn
    exact hn.1 ⟨x, hx, hxe⟩
  simp only [bne_self_eq_false, Bool.false_eq_true, ite_false]
  apply List.filter_eq_self.mpr
  intro x hx
  simpa using hnot x hx

/-- A result removes its task: no pending entry has that task afterwards. -/
theorem res_removes (log : List Ev) (t : String) (k : Kind) (x : Entry) (hx : x ∈ pending (log ++ [.res t k])) :
    x.task ≠ t := by
  rw [pending_append] at hx
  simp only [step, List.mem_filter, bne_iff_ne, ne_eq] at hx
  exact hx.2

/-- An enqueued task is pending (a second enqueue of it, with whatever branch, changes nothing). -/
theorem enq_pending (log : List Ev) (e : Entry) : ∃ x ∈ pending (log ++ [.enq e]), x.task = e.task := by
  rw [pending_append]
  by_cases h : (pending log).any (·.task == e.task) = true
  · simp only [List.any_eq_true, beq_iff_eq] at h
    obtain ⟨x, hx, hxe⟩ := h
    have h' : (pending log).any (·.task == e.task) = true := by
      simp only [List.any_eq_true, beq_iff_eq]; exact ⟨x, hx, hxe⟩
    refine ⟨x, ?_, hxe⟩
    simp only [step]
    rw [if_pos h']
    exact hx
  · exact ⟨e, by simp [step, h], rfl⟩

/-- **The watch fact.** A freshly enqueued task whose branch is the entry's own is queued, so `fw watch` raises no
`agent.unlanded` for it (`Fw.Obs.Next.no_unlanded_while_queued`) until its result is recorded. -/
theorem enq_queued (log : List Ev) (e : Entry) (h : (pending log).any (·.task == e.task) = false) :
    queued (pending (log ++ [.enq e])) e.branch = true := by
  rw [enq_appends log e h]
  simp [queued]

/-- Retry after an attempt that ended in kind `k` after `tries` attempts, at most `max` attempts in all. -/
def retryAfter (k : Kind) (tries max : Nat) : Bool := k.retryable && decide (tries < max)

/-- **Retry only busy and dirty, and only a bounded number of times.** -/
theorem retryAfter_iff (k : Kind) (tries max : Nat) :
    retryAfter k tries max = true ↔ (k = .busy ∨ k = .dirty) ∧ tries < max := by
  simp [retryAfter, retryable_iff]

/-- The runner never loops forever: from `max` attempts on it records the result. -/
theorem retryAfter_bounded (k : Kind) (tries max : Nat) (h : max ≤ tries) : retryAfter k tries max = false := by
  simp [retryAfter, Nat.not_lt.mpr h]

/-- A finished or refused-for-good land is never retried: not a success, not scope, reads, conflict, checks, stale, unknown. -/
theorem retryAfter_final (k : Kind) (tries max : Nat) (h : k.retryable = false) : retryAfter k tries max = false := by
  simp [retryAfter, h]

/-- Is the runner whose lock was written with start time `held` still alive, given the start time `probe` of the process now at
its pid (`none`: no such process)? Identity is the pair (pid, start time); a reused pid has another start time. -/
def runnerLive (held : String) (probe : Option String) : Bool := probe == some held

/-- The identity test is exactly equality of start times; it takes no command line, so no pattern can match another process. -/
theorem runnerLive_iff (held : String) (probe : Option String) : runnerLive held probe = true ↔ probe = some held := by
  simp [runnerLive]

/-- A reused pid (another start time) or a dead pid is not the runner. -/
theorem runnerLive_stale (held : String) (probe : Option String) (h : probe ≠ some held) : runnerLive held probe = false := by
  simpa [runnerLive] using h

/-- The reason a refusal prints and records: the message of the exception, or a fixed text when the message is empty. -/
def reasonOf (msg : String) : String := if msg.isEmpty then "no message" else msg

/-- The reason text itself is never empty, whatever the message. -/
theorem reasonOf_nonempty (msg : String) : (reasonOf msg).isEmpty = false := by
  unfold reasonOf
  by_cases h : msg.isEmpty <;> simp [h]

/-- A non-empty message is kept as it is. -/
theorem reasonOf_keeps (msg : String) (h : msg.isEmpty = false) : reasonOf msg = msg := by
  simp [reasonOf, h]

/-- The line printed to stderr before the `VERDICT` line. -/
def refusedLine (msg : String) : String := "REFUSED: " ++ reasonOf msg

/-- The reason the queue records for a result of kind `k` with an optional reason `r` from the attempt: a success keeps what it has,
a refusal always gets one (a missing or empty reason becomes the fixed text). -/
def refusalReason (k : Kind) (r : Option String) : Option String :=
  if k.ok then r.map reasonOf else some (reasonOf (r.getD ""))

/-- **A refusal always carries a non-empty reason**, for every refusal kind and every reason the attempt gave or did not give. -/
theorem refusal_has_reason (k : Kind) (r : Option String) (h : k.ok = false) :
    ∃ s, refusalReason k r = some s ∧ s.isEmpty = false := by
  refine ⟨reasonOf (r.getD ""), ?_, reasonOf_nonempty _⟩
  simp [refusalReason, h]

/-- The named reason of the preflight refusal. -/
def fwcoreStaleReason : String := "fwcore-stale: run sh scripts/fwcore-build.sh"

/-- Is the installed fwcore binary stale? `recorded` is the commit in its build record (`none`: no record), `same` says that commit is
`main`'s head, `moved` says a Lean source or the build script changed between the two (an unknown commit counts as moved). -/
def fwcoreStale (recorded : Option String) (same moved : Bool) : Bool := recorded.isNone || (!same && moved)

/-- Branch one: no build record is stale. -/
theorem fwcoreStale_noRecord (same moved : Bool) : fwcoreStale none same moved = true := by
  simp [fwcoreStale]

/-- Branch two: a record of another commit with changed Lean sources is stale. -/
theorem fwcoreStale_moved (c : String) : fwcoreStale (some c) false true = true := by
  simp [fwcoreStale]

/-- A record of main's own head is fresh. -/
theorem fwcoreFresh_same (c : String) (moved : Bool) : fwcoreStale (some c) true moved = false := by
  simp [fwcoreStale]

/-- A record of another commit whose Lean sources did not change is fresh. -/
theorem fwcoreFresh_unmoved (c : String) (same : Bool) : fwcoreStale (some c) same false = false := by
  simp [fwcoreStale]

/-! ## The queue rebuilds fwcore after a land that changed its sources (task land-queue-fwcore-rebuild)

Incident 2026-10-20: `land-fwcore-once` landed a change under `lean/`; the three entries queued behind it were each refused
`fwcore-stale` and only landed after a manual `sh scripts/fwcore-build.sh`. The step between two queue entries: after a `done` land
whose merged diff touches a path fwcore is built from (`lean/**`, the build script or its record rule `scripts/fwcore-record-rule.sh`), the queue rebuilds fwcore before the next
dequeue. If the rebuild fails the next entry gets the kind `rebuild` (never `stale`: its branch is fine) and the queue stops. -/

/-- Is a path one fwcore is built from? Lean `lean/**`, the build script or its record rule (TS `FWCORE_BUILD_READS`). -/
def coreSource (p : String) : Bool := p.startsWith "lean/" || p == "scripts/fwcore-build.sh" || p == "scripts/fwcore-record-rule.sh"

/-- Does a merged diff touch a path fwcore is built from? -/
def touchesCore (paths : List String) : Bool := paths.any coreSource

/-- Must the queue rebuild fwcore after a land of kind `k` whose merged diff is `paths`? Only a finished land that touched a core path. -/
def needsRebuild (k : Kind) (paths : List String) : Bool := k == .done && touchesCore paths

/-- What the queue does between two entries: carry on (with fwcore rebuilt or not), or stop. -/
inductive After where
  | proceed (rebuilt : Bool)
  | stop
deriving DecidableEq, Repr

/-- The step after a land: `ok` is the result of the rebuild and is read only when a rebuild is needed. -/
def afterLand (k : Kind) (paths : List String) (ok : Bool) : After :=
  if needsRebuild k paths then (if ok then .proceed true else .stop) else .proceed false

/-- The kind the next entry gets when the queue stops: `rebuild`; otherwise the entry is landed on its own merits. -/
def stopKind : After → Option Kind
  | .stop => some .rebuild
  | .proceed _ => none

/-- The reason recorded with the `rebuild` verdict. -/
def rebuildReason : String := "fwcore-rebuild-failed: sh scripts/fwcore-build.sh failed after a land that changed lean/"

/-- Branch one: no rebuild is needed, so the queue carries on whatever the rebuild result says. -/
theorem afterLand_noRebuild (k : Kind) (paths : List String) (ok : Bool) (h : needsRebuild k paths = false) :
    afterLand k paths ok = .proceed false := by
  simp [afterLand, h]

/-- Branch one, by the diff: a finished land with no core path in its diff does not rebuild. -/
theorem afterLand_noLeanChange (paths : List String) (ok : Bool) (h : touchesCore paths = false) :
    afterLand .done paths ok = .proceed false := by
  apply afterLand_noRebuild
  simp [needsRebuild, h]

/-- Branch one, by the kind: a land that did not finish never rebuilds. -/
theorem afterLand_notDone (k : Kind) (paths : List String) (ok : Bool) (h : k ≠ .done) :
    afterLand k paths ok = .proceed false := by
  apply afterLand_noRebuild
  cases k <;> simp_all [needsRebuild]

/-- Branch two: a finished land that touched a core path and a rebuild that worked: the queue carries on with fwcore rebuilt. -/
theorem afterLand_rebuilt (paths : List String) (h : touchesCore paths = true) :
    afterLand .done paths true = .proceed true := by
  simp [afterLand, needsRebuild, h]

/-- What the rebuild left behind: the exit status of `scripts/fwcore-build.sh` and the commit it recorded in `fwcore.commit` (none when it exits 0 without recording, e.g. a dirty tree). -/
structure RebuildOut where
  exit0 : Bool
  recorded : Option String

/-- The rebuild worked only if it exited 0 and recorded main's head (TS: exit 0 and `fwcorePreflight` finds no refusal). -/
def rebuildOk (o : RebuildOut) (head : String) : Bool := o.exit0 && o.recorded == some head

/-- Branch two, the point: if the queue proceeds with a rebuilt core, the rebuild exited 0 and recorded main's head, so the preflight of the next entry (record against head) finds fwcore fresh, whatever moved. -/
theorem afterLand_rebuilt_fresh (k : Kind) (paths : List String) (o : RebuildOut) (head : String) (moved : Bool)
    (h : afterLand k paths (rebuildOk o head) = .proceed true) :
    fwcoreStale o.recorded (o.recorded == some head) moved = false := by
  have hok : rebuildOk o head = true := by
    by_cases hk : rebuildOk o head = true
    · exact hk
    · have hf : rebuildOk o head = false := by simpa using hk
      simp [afterLand, hf] at h
      split at h <;> simp_all
  simp only [rebuildOk, Bool.and_eq_true, beq_iff_eq] at hok
  obtain ⟨_, h2⟩ := hok
  simp [fwcoreStale, h2]

/-- Branch three: a finished land that touched a core path and a failed rebuild: the queue stops. -/
theorem afterLand_stop (paths : List String) (h : touchesCore paths = true) :
    afterLand .done paths false = .stop := by
  simp [afterLand, needsRebuild, h]

/-- Branch three, the verdict: the stopped entry gets `rebuild`, a refusal that is neither `stale` nor retried. -/
theorem stopKind_rebuild : stopKind .stop = some .rebuild ∧ Kind.rebuild ≠ Kind.stale ∧ Kind.rebuild.ok = false ∧ Kind.rebuild.retryable = false := by
  refine ⟨rfl, by decide, rfl, rfl⟩

/-- Only a stop gives the next entry a verdict: a queue that carries on lands it on its own merits. -/
theorem stopKind_iff (a : After) : (stopKind a).isSome = true ↔ a = .stop := by
  cases a <;> simp [stopKind]

/-- The reason of the stopped entry is not empty. -/
theorem rebuildReason_nonempty : rebuildReason.isEmpty = false := by decide

/-! ## An unreachable console (task land-queue-unreachable)

Incident: six queue entries on 2026-10-20 ended `VERDICT unknown` with `REFUSED: fetch failed` 0.9 to 2.5 s after the
previous entry's result (after its fwcore rebuild); the failed attempt itself lasted 168 to 530 ms. The land's first request
(`GET /api/plan`) failed, and the thrown error became kind `unknown`, which is final. Timestamps rule out a console restart
(every restart span starts after its failure; one case had none, and another land reached the console 0.6 s after the
failure). Each failure follows 7 to 14 s without a console request, 4.6 to 11 s of it in synchronous calls (worktree
cleanup, `fwcore rebuild (queue)`); the console's 5 s `keepAliveTimeout` falls inside that window in all six. The likely
cause (INFERRED, reproduced only as a race) is the next fetch reusing the keep-alive socket the console had closed meanwhile
(ECONNRESET). The land's client now sends `connection: close`; this section is the second line.

Model. A console that is unreachable is a retryable condition of its own, not a kind of land. The queue waits for
`/api/health` on a fixed backoff schedule (`healthDelay`: 250 ms doubling to a 4000 ms cap, `healthPolls` polls, the last
at `healthBoundMs`). `back` is the time (ms after the failure) at which the console answers again and keeps answering;
`none` is a console that never returns (premise `land.consoleStaysUp`). -/

/-- Delay before poll `i + 1`: 250 ms doubling, capped at 4000 ms. -/
def healthDelay (i : Nat) : Nat := min 4000 (250 * 2 ^ i)

/-- Number of health polls of one wait. -/
def healthPolls : Nat := 20

/-- Time of poll `i`, ms after the first (the sum of the delays before it). -/
def pollTime : Nat → Nat
  | 0 => 0
  | i + 1 => pollTime i + healthDelay i

/-- The bound of one wait: the time of the last poll. -/
def healthBoundMs : Nat := pollTime (healthPolls - 1)

/-- Does some poll of the schedule find a console that is back at `back`? -/
def healthReached (back : Option Nat) : Bool :=
  (List.range healthPolls).any fun i => match back with | some b => decide (b ≤ pollTime i) | none => false

/-- **The wait is bounded**: 20 polls, every one at or before `healthBoundMs`, which is 63750 ms (a minute at least). -/
theorem health_bounded : healthPolls = 20 ∧ healthBoundMs = 63750 ∧ 60000 ≤ healthBoundMs ∧
    ∀ i, i < healthPolls → pollTime i ≤ healthBoundMs := by
  refine ⟨rfl, by decide, by decide, ?_⟩
  decide

/-- **A console that returns within the bound is found by the wait.** -/
theorem healthReached_within (b : Nat) (h : b ≤ healthBoundMs) : healthReached (some b) = true := by
  simp only [healthReached, List.any_eq_true, List.mem_range, decide_eq_true_eq]
  exact ⟨healthPolls - 1, by decide, h⟩

/-- **A console that never returns is never found.** -/
theorem healthReached_never : healthReached none = false := by
  simp [healthReached]

/-- A console that returns only after the bound is not found (the wait ends; it does not stretch). -/
theorem healthReached_late (b : Nat) (h : healthBoundMs < b) : healthReached (some b) = false := by
  have hb := health_bounded.2.2.2
  simp only [healthReached, Bool.eq_false_iff, ne_eq, List.any_eq_true, List.mem_range, decide_eq_true_eq, not_exists, not_and]
  intro i hi hle
  have := hb i hi
  omega

/-- The named reason of the refusal when the console does not come back. -/
def consoleUnreachableReason : String := "console-unreachable: console-api did not answer /api/health within the bounded wait (pnpm fw console status)"

/-- What one land attempt ended in: a land with its kind, or a console that could not be reached (no land step ran). -/
inductive Att where
  | landed (k : Kind)
  | unreachable
deriving DecidableEq, Repr

/-- What the runner does after an attempt: try again, or record a final kind with an optional reason. -/
inductive Next where
  | retry
  | final (k : Kind) (reason : Option String)
deriving DecidableEq, Repr

/-- The decision after an attempt number `tries` of at most `max`. A landed attempt follows `retryAfter`. An unreachable console
is retried when the bounded health wait finds it (`back`) and attempts remain; else the entry is refused as `busy` (nothing landed,
safe to queue again) with the reason `consoleUnreachableReason`, never as `unknown`. -/
def attemptNext (a : Att) (tries max : Nat) (back : Option Nat) : Next :=
  match a with
  | .landed k => if retryAfter k tries max then .retry else .final k none
  | .unreachable =>
    if healthReached back && decide (tries < max) then .retry else .final .busy (some consoleUnreachableReason)

/-- **Attempts are bounded**: a retry is only ever decided below `max` attempts. -/
theorem attemptNext_bounded (a : Att) (tries max : Nat) (back : Option Nat) (h : attemptNext a tries max back = .retry) :
    tries < max := by
  cases a with
  | landed k =>
    by_cases hr : retryAfter k tries max = true
    · simp only [retryAfter, Bool.and_eq_true, decide_eq_true_eq] at hr; exact hr.2
    · simp [attemptNext, hr] at h
  | unreachable =>
    by_cases hr : (healthReached back && decide (tries < max)) = true
    · simp only [Bool.and_eq_true, decide_eq_true_eq] at hr; exact hr.2
    · simp [attemptNext, hr] at h

/-- **An unreachable console is never a terminal `unknown`**, whatever the wait found. -/
theorem attemptNext_unreachable_not_unknown (tries max : Nat) (back : Option Nat) (r : Option String) :
    attemptNext .unreachable tries max back ≠ .final .unknown r := by
  by_cases h : (healthReached back && decide (tries < max)) = true <;> simp [attemptNext, h]

/-- **A console that returns within the bound is retried**, while attempts remain: never a terminal result. -/
theorem attemptNext_returns (tries max b : Nat) (hb : b ≤ healthBoundMs) (ht : tries < max) :
    attemptNext .unreachable tries max (some b) = .retry := by
  simp [attemptNext, healthReached_within b hb, ht]

/-- **A console that never returns yields the named refusal** `console-unreachable`. -/
theorem attemptNext_never (tries max : Nat) :
    attemptNext .unreachable tries max none = .final .busy (some consoleUnreachableReason) := by
  simp [attemptNext, healthReached_never]

/-- A console that returns only after the bound yields the named refusal. -/
theorem attemptNext_late (tries max b : Nat) (h : healthBoundMs < b) :
    attemptNext .unreachable tries max (some b) = .final .busy (some consoleUnreachableReason) := by
  simp [attemptNext, healthReached_late b h]

/-- With no attempts left an unreachable console yields the named refusal, even if it is back. -/
theorem attemptNext_exhausted (tries max : Nat) (back : Option Nat) (h : max ≤ tries) :
    attemptNext .unreachable tries max back = .final .busy (some consoleUnreachableReason) := by
  simp [attemptNext, Nat.not_lt.mpr h]

/-- A landed attempt decides exactly as before: `retryAfter` retries, else its own kind is final. -/
theorem attemptNext_landed (k : Kind) (tries max : Nat) (back : Option Nat) :
    attemptNext (.landed k) tries max back = if retryAfter k tries max then .retry else .final k none := rfl

/-- The refusal for an unreachable console has a non-empty reason, and its kind is not `unknown`. -/
theorem consoleUnreachable_refusal : consoleUnreachableReason.isEmpty = false ∧ Kind.busy ≠ Kind.unknown ∧ Kind.busy.ok = false := by
  refine ⟨by decide, by decide, by decide⟩

/-- Does the queue wait for the console's health before the next entry? After the rebuild it ran (`needsRebuild`). -/
def healthWaitAfter (k : Kind) (paths : List String) : Bool := needsRebuild k paths

/-- **After a land that changed a fwcore source, the queue waits for the console before the next entry**, and after no other. -/
theorem healthWaitAfter_iff (k : Kind) (paths : List String) :
    healthWaitAfter k paths = true ↔ k = .done ∧ touchesCore paths = true := by
  simp [healthWaitAfter, needsRebuild]

/-- A premise row: id, statement, the theorems that assume it, and the test that asserts it. -/
structure PremiseRow where
  id : String
  statement : String
  theorems : List String
  test : String

/-- The premises of this module (3 rows, distinct ids). -/
def premises : List PremiseRow := [
  ⟨"land.queueAppendAtomic", "appending one line (under 4096 bytes) to the queue log with O_APPEND is atomic, so concurrent enqueuers never interleave a line",
    ["enq_appends", "pending_nodup"],
    "apps/runner/test/land-queue.test.ts: 20 concurrent enqueues of distinct tasks leave 20 whole lines"⟩,
  ⟨"land.runnerStartTimeIdentifies", "the start time that `ps -o lstart= -p <pid>` prints identifies one incarnation of a pid",
    ["runnerLive_iff", "runnerLive_stale"],
    "apps/runner/test/land-queue.test.ts: a lock whose recorded start time differs from the live pid's is stale and is taken over"⟩,
  ⟨"land.exitCodeIsVerdict", "the exit code and the VERDICT line of `fw land` are the land's kind, so the runner reads the kind from them and never from the text",
    ["retryAfter_iff", "retryAfter_final"],
    "apps/runner/test/land-queue.test.ts: a land whose output names busy in prose but exits with checks is not retried"⟩,
  ⟨"land.consoleStaysUp", "a console that answers /api/health keeps answering for the rest of the queue run (a restart is a down window that ends, not a flap)",
    ["healthReached_within", "attemptNext_returns"],
    "apps/runner/test/land-queue-unreachable.test.ts: down ${downMs} ms then up: the entry lands (done, never unknown)"⟩]

#guard premises.length == 4
#guard (premises.map (·.id)).eraseDups.length == premises.length

#guard (pending [.enq ⟨"a", "wa"⟩, .enq ⟨"b", "wb"⟩, .enq ⟨"a", "wx"⟩]) == [⟨"a", "wa"⟩, ⟨"b", "wb"⟩]
#guard (pending [.enq ⟨"a", "wa"⟩, .enq ⟨"b", "wb"⟩, .res "a" .done]) == [⟨"b", "wb"⟩]
#guard retryAfter .busy 1 3 && !retryAfter .busy 3 3 && !retryAfter .checks 0 3

/-! ## Golden vectors (`packages/contracts/golden/console/land-queue.jsonl`) -/

open Lean

/-- A log event as JSON, the shape of a line of the queue file (the file lines carry more fields, which the fold ignores). -/
def evJson : Ev → Json
  | .enq e => Json.mkObj [("ev", "enq"), ("task", e.task), ("branch", e.branch)]
  | .res t k => Json.mkObj [("ev", "res"), ("task", t), ("kind", k.name)]

/-- One golden line: its name, the request object and the response object. -/
def line (name : String) (req resp : List (String × Json)) : Json :=
  Json.mkObj [("name", .str name), ("request", Json.mkObj req), ("response", Json.mkObj resp)]

/-- An entry as JSON. -/
def entryJson (e : Entry) : Json := Json.mkObj [("task", e.task), ("branch", e.branch)]

/-- A `landQueue.pending` case: the pending list of a log and the next entry. -/
def pendCase (name : String) (log : List Ev) : Json :=
  line name [("op", "landQueue.pending"), ("log", .arr (log.toArray.map evJson))]
    [("pending", .arr ((pending log).toArray.map entryJson)),
     ("next", match next (pending log) with | some e => entryJson e | none => Json.null)]

/-- A `landQueue.queued` case: whether a branch is a pending entry of a log. -/
def queuedCase (name : String) (log : List Ev) (b : String) : Json :=
  line name [("op", "landQueue.queued"), ("log", .arr (log.toArray.map evJson)), ("branch", b)]
    [("queued", .bool (queued (pending log) b))]

/-- A `landQueue.retry` case. -/
def retryCase (k : Kind) (tries max : Nat) : Json :=
  line s!"retry {k.name} {tries}/{max}" [("op", "landQueue.retry"), ("kind", k.name), ("tries", toJson tries), ("max", toJson max)]
    [("retry", .bool (retryAfter k tries max))]

/-- A `landQueue.live` case. -/
def liveCase (name : String) (held : String) (probe : Option String) : Json :=
  line name [("op", "landQueue.live"), ("held", held), ("probe", match probe with | some p => Json.str p | none => Json.null)]
    [("live", .bool (runnerLive held probe))]

/-- A `landQueue.reason` case: the reason and the stderr line of a refusal with a message. -/
def reasonCase (name : String) (msg : String) : Json :=
  line s!"reason: {name}" [("op", "landQueue.reason"), ("message", msg)] [("reason", reasonOf msg), ("line", refusedLine msg)]

/-- A `landQueue.refusalReason` case: the recorded reason of a kind with an optional reason. -/
def rrCase (k : Kind) (tag : String) (r : Option String) : Json :=
  line s!"refusal reason {k.name} {tag}" [("op", "landQueue.refusalReason"), ("kind", k.name), ("reason", match r with | some p => Json.str p | none => Json.null)]
    [("reason", match refusalReason k r with | some p => Json.str p | none => Json.null)]

/-- A `landQueue.fwcoreStale` case. -/
def staleCase (name : String) (recorded : Option String) (same moved : Bool) : Json :=
  line s!"fwcore stale: {name}" [("op", "landQueue.fwcoreStale"), ("recorded", match recorded with | some p => Json.str p | none => Json.null),
    ("same", .bool same), ("moved", .bool moved)] [("stale", .bool (fwcoreStale recorded same moved))]

/-- A `landQueue.afterLand` case. -/
def afterCase (name : String) (k : Kind) (paths : List String) (ok : Bool) : Json :=
  let a := afterLand k paths ok
  line s!"after land: {name}" [("op", "landQueue.afterLand"), ("kind", k.name), ("paths", Json.arr (paths.map Json.str).toArray), ("rebuildOk", .bool ok)]
    [("rebuild", .bool (needsRebuild k paths)), ("action", match a with | .stop => "stop" | .proceed _ => "proceed"),
     ("rebuilt", .bool (a == .proceed true)),
     ("nextKind", match stopKind a with | some n => Json.str n.name | none => Json.null),
     ("reason", match stopKind a with | some _ => Json.str rebuildReason | none => Json.null)]

/-- A `landQueue.health` case: does the bounded wait find a console that is back at `back`? -/
def healthCase (name : String) (back : Option Nat) : Json :=
  line name [("op", "landQueue.health"), ("back", match back with | some b => toJson b | none => Json.null)]
    [("reached", .bool (healthReached back))]

/-- A `landQueue.healthSchedule` case: the delays and poll times of the wait and its bound. -/
def scheduleCase : Json :=
  line "health wait schedule" [("op", "landQueue.healthSchedule")]
    [("polls", toJson healthPolls), ("delays", .arr ((List.range healthPolls).toArray.map fun i => toJson (healthDelay i))),
     ("times", .arr ((List.range healthPolls).toArray.map fun i => toJson (pollTime i))), ("boundMs", toJson healthBoundMs)]

/-- A `landQueue.attempt` case: the decision after an attempt (`kind` null: the console was unreachable). -/
def attemptCase (name : String) (a : Att) (tries max : Nat) (back : Option Nat) : Json :=
  let n := attemptNext a tries max back
  line name [("op", "landQueue.attempt"), ("kind", match a with | .landed k => Json.str k.name | .unreachable => Json.null),
      ("tries", toJson tries), ("max", toJson max), ("back", match back with | some b => toJson b | none => Json.null)]
    [("next", match n with | .retry => "retry" | .final _ _ => "final"),
     ("kind", match n with | .final k _ => Json.str k.name | .retry => Json.null),
     ("reason", match n with | .final _ (some r) => Json.str r | _ => Json.null)]

/-- A `landQueue.healthAfter` case: does the queue wait for the console after a land of this kind with these paths? -/
def healthAfterCase (name : String) (k : Kind) (paths : List String) : Json :=
  line s!"health wait after land: {name}" [("op", "landQueue.healthAfter"), ("kind", k.name), ("paths", Json.arr (paths.map Json.str).toArray)]
    [("wait", .bool (healthWaitAfter k paths))]

/-- The sample log of the golden cases: three tasks enqueued, one twice with another branch. -/
def sample : List Ev := [.enq ⟨"a", "wa"⟩, .enq ⟨"b", "wb"⟩, .enq ⟨"c", "wc"⟩]

/-- Every golden case: 6 pending, 4 queued, 14 retry (every kind, some at the bound), 4 live, 2 reason, 39 refusal reason (every kind with no reason, an empty one and a given one), 4 fwcore stale, 9 after land (`unreachableCases`: 1 health schedule, 5 health, 5 unreachable attempt, 4 landed attempt, 4 health wait after land). -/
def cases : List Json :=
  [pendCase "empty" [],
   pendCase "three enqueued, first in first out" sample,
   pendCase "enqueue twice is once (first branch kept)" (sample ++ [.enq ⟨"a", "other"⟩]),
   pendCase "result removes the head" (sample ++ [.res "a" .done]),
   pendCase "result of a middle task" (sample ++ [.res "b" .scope]),
   pendCase "re-enqueue after a result goes to the end" (sample ++ [.res "a" .reads, .enq ⟨"a", "wa2"⟩]),
   queuedCase "queued branch" sample "wb",
   queuedCase "unknown branch" sample "wz",
   queuedCase "finished branch is no longer queued" (sample ++ [.res "b" .done]) "wb",
   queuedCase "empty queue" [] "wa"] ++
  (Kind.all.map fun k => retryCase k 1 3) ++
  [retryCase .busy 3 3,
   liveCase "same start time" "Sat Oct 18 10:00:00 2026" (some "Sat Oct 18 10:00:00 2026"),
   liveCase "pid reused (other start time)" "Sat Oct 18 10:00:00 2026" (some "Sat Oct 18 11:00:00 2026"),
   liveCase "no such process" "Sat Oct 18 10:00:00 2026" none,
   liveCase "empty start time, no process" "" none] ++
  [reasonCase "thrown message kept" "unknown op console.landDigest",
   reasonCase "empty message gets a fixed reason" ""] ++
  (Kind.all.flatMap fun k => [rrCase k "none" none, rrCase k "empty" (some ""), rrCase k "given" (some "m")]) ++
  [
   staleCase "no record" none false false,
   staleCase "record is main's head" (some "abc") true false,
   staleCase "other commit, lean moved" (some "abc") false true,
   staleCase "other commit, lean unchanged" (some "abc") false false,
   afterCase "no lean change, no rebuild" .done ["apps/site/src/a.ts", "docs/x.md"] true,
   afterCase "no lean change, a rebuild result is not read" .done ["docs/x.md"] false,
   afterCase "lean change, rebuild ok" .done ["lean/Fw/A.lean", "docs/x.md"] true,
   afterCase "build script change, rebuild ok" .done ["scripts/fwcore-build.sh"] true,
   afterCase "lean change, rebuild fails" .done ["lean/Fw/A.lean"] false,
   afterCase "empty diff" .done [] true,
   afterCase "lean-like name outside lean/" .done ["apps/lean/x.ts", "leanx/y"] false,
   afterCase "refused land with a lean path" .checks ["lean/Fw/A.lean"] false,
   afterCase "empty land with a lean path" .empty ["lean/Fw/A.lean"] true]

/-- The golden cases of the unreachable console (a separate list: the start-time allocation bound of `cases`). -/
def unreachableCases : List Json :=
  [scheduleCase,
   healthCase "console back at once" (some 0),
   healthCase "console back after 5 s" (some 5000),
   healthCase "console back at the bound" (some healthBoundMs),
   healthCase "console back one ms after the bound" (some (healthBoundMs + 1)),
   healthCase "console never back" none,
   attemptCase "unreachable, back in 5 s" .unreachable 1 5 (some 5000),
   attemptCase "unreachable, back at the bound" .unreachable 4 5 (some healthBoundMs),
   attemptCase "unreachable, back after the bound" .unreachable 1 5 (some (healthBoundMs + 1)),
   attemptCase "unreachable, never back" .unreachable 1 5 none,
   attemptCase "unreachable, back but attempts used" .unreachable 5 5 (some 0),
   attemptCase "landed busy" (.landed .busy) 1 5 none,
   attemptCase "landed busy, attempts used" (.landed .busy) 5 5 none,
   attemptCase "landed unknown is final" (.landed .unknown) 1 5 (some 0),
   attemptCase "landed done" (.landed .done) 1 5 none,
   healthAfterCase "lean change" .done ["lean/Fw/A.lean"],
   healthAfterCase "build script change" .done ["scripts/fwcore-build.sh"],
   healthAfterCase "no core change" .done ["docs/x.md"],
   healthAfterCase "refused land with a lean path" .checks ["lean/Fw/A.lean"]]

#guard cases.length == 90
#guard unreachableCases.length == 19

/-- The golden file text: one compressed JSON line per case. -/
def goldenText : String := String.join ((cases ++ unreachableCases).map fun c => c.compress ++ "\n")

/-- The golden file, relative to `lean/`. -/
def goldenPath : System.FilePath := "../packages/contracts/golden/console/land-queue.jsonl"

/-- Write the golden file (IO). -/
def writeGolden : IO Unit := IO.FS.writeFile goldenPath goldenText

/-- Is the golden file the Lean output? (IO) -/
def checkGolden : IO Bool := do return (← IO.FS.readFile goldenPath) == goldenText

end Fw.Console.LandQueue
