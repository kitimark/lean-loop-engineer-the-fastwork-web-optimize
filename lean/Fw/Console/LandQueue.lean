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

/-- A queued land: the task and the branch to land.
$$e = (\mathit{task}, \mathit{branch})$$ -/
structure Entry where
  task : String
  branch : String
deriving DecidableEq, Repr

/-- A line of the queue log: an entry enqueued, or the final result of a task's land.
$$\mathrm{Ev} = \mathrm{enq}(e) \mid \mathrm{res}(t, k)$$ -/
inductive Ev where
  | enq (e : Entry)
  | res (task : String) (k : Kind)
deriving DecidableEq, Repr

/-- One event applied to the pending list: `enq` appends unless the task is pending, `res` removes the task.
$$\operatorname{step}(q, \mathrm{enq}(e)) = \begin{cases} q & e.\mathit{task} \in \operatorname{tasks}(q) \\ q \mathbin{+\!\!+} [e] & \text{else}\end{cases}\qquad \operatorname{step}(q, \mathrm{res}(t, k)) = [x \in q \mid x.\mathit{task} \ne t]$$ -/
def step (q : List Entry) : Ev → List Entry
  | .enq e => if q.any (·.task == e.task) then q else q ++ [e]
  | .res t _ => q.filter (·.task != t)

/-- The pending list of a log: the fold of `step` from the empty queue.
$$\operatorname{pending}(\ell) = \operatorname{foldl}(\operatorname{step}, [\,], \ell)$$ -/
def pending (log : List Ev) : List Entry := log.foldl step []

/-- The entry the runner lands next: the head of the pending list.
$$\operatorname{next}(q) = q_0$$ -/
def next (q : List Entry) : Option Entry := q.head?

/-- Is a branch a pending entry? This is the `landQueued` fact of `fw next` / `fw watch` (`Fw.Obs.Next.Branch.inLandQueue`).
$$\operatorname{queued}(q, b) \iff \exists x \in q.\ x.\mathit{branch} = b$$ -/
def queued (q : List Entry) (b : String) : Bool := q.any (·.branch == b)

/-- Appending an event to a log applies it to the pending list.
$$\operatorname{pending}(\ell \mathbin{+\!\!+} [v]) = \operatorname{step}(\operatorname{pending}(\ell), v)$$ -/
theorem pending_append (log : List Ev) (v : Ev) : pending (log ++ [v]) = step (pending log) v := by
  simp [pending, List.foldl_append]

/-- **Enqueueing twice is enqueueing once.**
$$\forall q, e:\quad \operatorname{step}(\operatorname{step}(q, \mathrm{enq}(e)), \mathrm{enq}(e)) = \operatorname{step}(q, \mathrm{enq}(e))$$ -/
theorem enq_idem (q : List Entry) (e : Entry) : step (step q (.enq e)) (.enq e) = step q (.enq e) := by
  by_cases h : q.any (·.task == e.task) = true
  · simp [step, h]
  · simp only [step, h, ite_false]
    simp

/-- The tasks of the pending list never repeat (the invariant behind the first-in-first-out theorems).
$$\forall q, v:\quad \operatorname{Nodup}(\operatorname{tasks}(q)) \Rightarrow \operatorname{Nodup}(\operatorname{tasks}(\operatorname{step}(q, v)))$$ -/
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

/-- The pending list of any log has no repeated task.
$$\forall \ell:\quad \operatorname{Nodup}(\operatorname{tasks}(\operatorname{pending}(\ell)))$$ -/
theorem pending_nodup (log : List Ev) : ((pending log).map (·.task)).Nodup := by
  unfold pending
  suffices ∀ (l : List Ev) (q : List Entry), (q.map (·.task)).Nodup → ((l.foldl step q).map (·.task)).Nodup from
    this log [] (by simp)
  intro l
  induction l with
  | nil => intro q h; simpa using h
  | cons v l ih => intro q h; exact ih _ (step_nodup q v h)

/-- **First in, first out (enqueue).** A new task goes to the end of the pending list; the entries before it keep their order.
$$\forall \ell, e:\quad e.\mathit{task} \notin \operatorname{tasks}(\operatorname{pending}(\ell)) \Rightarrow \operatorname{pending}(\ell \mathbin{+\!\!+} [\mathrm{enq}(e)]) = \operatorname{pending}(\ell) \mathbin{+\!\!+} [e]$$ -/
theorem enq_appends (log : List Ev) (e : Entry) (h : (pending log).any (·.task == e.task) = false) :
    pending (log ++ [.enq e]) = pending log ++ [e] := by
  rw [pending_append]
  simp [step, h]

/-- **First in, first out (land).** When the runner has landed the head of the pending list and records its result, the rest of
the list is what remains, in order.
$$\forall \ell, h, t, k:\quad \operatorname{pending}(\ell) = h :: t \Rightarrow \operatorname{pending}(\ell \mathbin{+\!\!+} [\mathrm{res}(h.\mathit{task}, k)]) = t$$ -/
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

/-- A result removes its task: no pending entry has that task afterwards.
$$\forall \ell, t, k, x:\quad x \in \operatorname{pending}(\ell \mathbin{+\!\!+} [\mathrm{res}(t, k)]) \Rightarrow x.\mathit{task} \ne t$$ -/
theorem res_removes (log : List Ev) (t : String) (k : Kind) (x : Entry) (hx : x ∈ pending (log ++ [.res t k])) :
    x.task ≠ t := by
  rw [pending_append] at hx
  simp only [step, List.mem_filter, bne_iff_ne, ne_eq] at hx
  exact hx.2

/-- An enqueued task is pending (a second enqueue of it, with whatever branch, changes nothing).
$$\forall \ell, e:\quad \exists x \in \operatorname{pending}(\ell \mathbin{+\!\!+} [\mathrm{enq}(e)]).\ x.\mathit{task} = e.\mathit{task}$$ -/
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
`agent.unlanded` for it (`Fw.Obs.Next.no_unlanded_while_queued`) until its result is recorded.
$$\forall \ell, e:\quad e.\mathit{task} \notin \operatorname{tasks}(\operatorname{pending}(\ell)) \Rightarrow \operatorname{queued}(\operatorname{pending}(\ell \mathbin{+\!\!+} [\mathrm{enq}(e)]), e.\mathit{branch})$$ -/
theorem enq_queued (log : List Ev) (e : Entry) (h : (pending log).any (·.task == e.task) = false) :
    queued (pending (log ++ [.enq e])) e.branch = true := by
  rw [enq_appends log e h]
  simp [queued]

/-- Retry after an attempt that ended in kind `k` after `tries` attempts, at most `max` attempts in all.
$$\operatorname{retry}(k, n, m) = \operatorname{retryable}(k) \wedge n < m$$ -/
def retryAfter (k : Kind) (tries max : Nat) : Bool := k.retryable && decide (tries < max)

/-- **Retry only busy and dirty, and only a bounded number of times.**
$$\operatorname{retry}(k, n, m) \iff (k = \mathrm{busy} \vee k = \mathrm{dirty}) \wedge n < m$$ -/
theorem retryAfter_iff (k : Kind) (tries max : Nat) :
    retryAfter k tries max = true ↔ (k = .busy ∨ k = .dirty) ∧ tries < max := by
  simp [retryAfter, retryable_iff]

/-- The runner never loops forever: from `max` attempts on it records the result.
$$\forall k, n, m:\quad m \le n \Rightarrow \lnot\operatorname{retry}(k, n, m)$$ -/
theorem retryAfter_bounded (k : Kind) (tries max : Nat) (h : max ≤ tries) : retryAfter k tries max = false := by
  simp [retryAfter, Nat.not_lt.mpr h]

/-- A finished or refused-for-good land is never retried: not a success, not scope, reads, conflict, checks, stale, unknown.
$$\forall k, n, m:\quad k \notin \{\mathrm{busy}, \mathrm{dirty}\} \Rightarrow \lnot\operatorname{retry}(k, n, m)$$ -/
theorem retryAfter_final (k : Kind) (tries max : Nat) (h : k.retryable = false) : retryAfter k tries max = false := by
  simp [retryAfter, h]

/-- Is the runner whose lock was written with start time `held` still alive, given the start time `probe` of the process now at
its pid (`none`: no such process)? Identity is the pair (pid, start time); a reused pid has another start time.
$$\operatorname{live}(s, p) \iff p = s$$ -/
def runnerLive (held : String) (probe : Option String) : Bool := probe == some held

/-- The identity test is exactly equality of start times; it takes no command line, so no pattern can match another process.
$$\operatorname{live}(s, p) \iff p = \mathrm{some}(s)$$ -/
theorem runnerLive_iff (held : String) (probe : Option String) : runnerLive held probe = true ↔ probe = some held := by
  simp [runnerLive]

/-- A reused pid (another start time) or a dead pid is not the runner.
$$p = \mathrm{some}(s') \wedge s' \ne s \ \vee\ p = \bot \Rightarrow \lnot\operatorname{live}(s, p)$$ -/
theorem runnerLive_stale (held : String) (probe : Option String) (h : probe ≠ some held) : runnerLive held probe = false := by
  simpa [runnerLive] using h

/-- A premise row: id, statement, the theorems that assume it, and the test that asserts it.
$$p = (\mathit{id},\ \mathit{statement},\ \mathit{theorems},\ \mathit{test})$$ -/
structure PremiseRow where
  id : String
  statement : String
  theorems : List String
  test : String

/-- The premises of this module (3 rows, distinct ids).
$$\mathrm{premises} = [p_1, p_2, p_3]$$ -/
def premises : List PremiseRow := [
  ⟨"land.queueAppendAtomic", "appending one line (under 4096 bytes) to the queue log with O_APPEND is atomic, so concurrent enqueuers never interleave a line",
    ["enq_appends", "pending_nodup"],
    "apps/runner/test/land-queue.test.ts: 20 concurrent enqueues of distinct tasks leave 20 whole lines"⟩,
  ⟨"land.runnerStartTimeIdentifies", "the start time that `ps -o lstart= -p <pid>` prints identifies one incarnation of a pid",
    ["runnerLive_iff", "runnerLive_stale"],
    "apps/runner/test/land-queue.test.ts: a lock whose recorded start time differs from the live pid's is stale and is taken over"⟩,
  ⟨"land.exitCodeIsVerdict", "the exit code and the VERDICT line of `fw land` are the land's kind, so the runner reads the kind from them and never from the text",
    ["retryAfter_iff", "retryAfter_final"],
    "apps/runner/test/land-queue.test.ts: a land whose output names busy in prose but exits with checks is not retried"⟩]

#guard premises.length == 3
#guard (premises.map (·.id)).eraseDups.length == premises.length

#guard (pending [.enq ⟨"a", "wa"⟩, .enq ⟨"b", "wb"⟩, .enq ⟨"a", "wx"⟩]) == [⟨"a", "wa"⟩, ⟨"b", "wb"⟩]
#guard (pending [.enq ⟨"a", "wa"⟩, .enq ⟨"b", "wb"⟩, .res "a" .done]) == [⟨"b", "wb"⟩]
#guard retryAfter .busy 1 3 && !retryAfter .busy 3 3 && !retryAfter .checks 0 3

/-! ## Golden vectors (`packages/contracts/golden/console/land-queue.jsonl`) -/

open Lean

/-- A log event as JSON, the shape of a line of the queue file (the file lines carry more fields, which the fold ignores).
$$\mathrm{evJson}(\mathrm{enq}(e)) = \{ev: enq, task, branch\}\qquad \mathrm{evJson}(\mathrm{res}(t,k)) = \{ev: res, task, kind\}$$ -/
def evJson : Ev → Json
  | .enq e => Json.mkObj [("ev", "enq"), ("task", e.task), ("branch", e.branch)]
  | .res t k => Json.mkObj [("ev", "res"), ("task", t), ("kind", k.name)]

/-- One golden line: its name, the request object and the response object.
$$\operatorname{line}(n, q, r) = \{\texttt{name}: n,\ \texttt{request}: q,\ \texttt{response}: r\}$$ -/
def line (name : String) (req resp : List (String × Json)) : Json :=
  Json.mkObj [("name", .str name), ("request", Json.mkObj req), ("response", Json.mkObj resp)]

/-- An entry as JSON.
$$\mathrm{entryJson}(e) = \{task, branch\}$$ -/
def entryJson (e : Entry) : Json := Json.mkObj [("task", e.task), ("branch", e.branch)]

/-- A `landQueue.pending` case: the pending list of a log and the next entry.
$$\operatorname{pendCase}(n, \ell) = \operatorname{line}(n, \{\ell\}, \{\operatorname{pending}(\ell), \operatorname{next}\})$$ -/
def pendCase (name : String) (log : List Ev) : Json :=
  line name [("op", "landQueue.pending"), ("log", .arr (log.toArray.map evJson))]
    [("pending", .arr ((pending log).toArray.map entryJson)),
     ("next", match next (pending log) with | some e => entryJson e | none => Json.null)]

/-- A `landQueue.queued` case: whether a branch is a pending entry of a log.
$$\operatorname{queuedCase}(n, \ell, b) = \operatorname{line}(n, \{\ell, b\}, \{\operatorname{queued}(\operatorname{pending}(\ell), b)\})$$ -/
def queuedCase (name : String) (log : List Ev) (b : String) : Json :=
  line name [("op", "landQueue.queued"), ("log", .arr (log.toArray.map evJson)), ("branch", b)]
    [("queued", .bool (queued (pending log) b))]

/-- A `landQueue.retry` case.
$$\operatorname{retryCase}(k, n, m) = \operatorname{line}(\ldots, \{k, n, m\}, \{\operatorname{retry}(k, n, m)\})$$ -/
def retryCase (k : Kind) (tries max : Nat) : Json :=
  line s!"retry {k.name} {tries}/{max}" [("op", "landQueue.retry"), ("kind", k.name), ("tries", toJson tries), ("max", toJson max)]
    [("retry", .bool (retryAfter k tries max))]

/-- A `landQueue.live` case.
$$\operatorname{liveCase}(s, p) = \operatorname{line}(\ldots, \{s, p\}, \{\operatorname{live}(s, p)\})$$ -/
def liveCase (name : String) (held : String) (probe : Option String) : Json :=
  line name [("op", "landQueue.live"), ("held", held), ("probe", match probe with | some p => Json.str p | none => Json.null)]
    [("live", .bool (runnerLive held probe))]

/-- The sample log of the golden cases: three tasks enqueued, one twice with another branch.
$$\ell_0 = [\mathrm{enq}(a), \mathrm{enq}(b), \mathrm{enq}(c)]$$ -/
def sample : List Ev := [.enq ⟨"a", "wa"⟩, .enq ⟨"b", "wb"⟩, .enq ⟨"c", "wc"⟩]

/-- Every golden case: 6 pending, 4 queued, 11 retry (every kind, one at the bound), 4 live.
$$\mathrm{cases} = \mathrm{pend}_{1..6} \mathbin{+\!\!+} \mathrm{queued}_{1..4} \mathbin{+\!\!+} \mathrm{retry}_{1..11} \mathbin{+\!\!+} \mathrm{live}_{1..4}$$ -/
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
   liveCase "empty start time, no process" "" none]

#guard cases.length == 26

/-- The golden file text: one compressed JSON line per case.
$$\mathrm{goldenText} = \operatorname{concat}[\, \operatorname{compress}(c) \mathbin{+\!\!+} \text{"\textbackslash n"} \,]_{c \in \mathrm{cases}}$$ -/
def goldenText : String := String.join (cases.map fun c => c.compress ++ "\n")

/-- The golden file, relative to `lean/`.
$$\mathrm{goldenPath} = \texttt{../packages/contracts/golden/console/land-queue.jsonl}$$ -/
def goldenPath : System.FilePath := "../packages/contracts/golden/console/land-queue.jsonl"

/-- Write the golden file (IO).
$$\mathrm{writeGolden}:\ \mathrm{goldenPath} \leftarrow \mathrm{goldenText}$$ -/
def writeGolden : IO Unit := IO.FS.writeFile goldenPath goldenText

/-- Is the golden file the Lean output? (IO)
$$\mathrm{checkGolden} \iff \operatorname{read}(\mathrm{goldenPath}) = \mathrm{goldenText}$$ -/
def checkGolden : IO Bool := do return (← IO.FS.readFile goldenPath) == goldenText

end Fw.Console.LandQueue
