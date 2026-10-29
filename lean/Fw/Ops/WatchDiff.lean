import Lean.Data.Json
import Fw.Ops.Wire
import Fw.Ops.WatchMem
/-!
# The alert stream of `fw watch --stream` and the identity of declared long-runners

`step` decides, per alert key, which alerts a check opens and closes against the stream's open set; `keepPids`
decides which processes are declared long-runners (exact pid and start time, or an allowlisted command line).
Consumers: `apps/runner/src/watch.ts` (`ops.watchDiff`, `ops.watchKeep`); goldens in
`packages/contracts/golden/ops/ops.watch{Diff,Keep}.jsonl`.
-/
namespace Fw.Ops.WatchDiff

/-- An alert key: the alert code and its subject. -/
structure Key where
  code : String
  subject : String
deriving DecidableEq, Repr

/-- One alert of a check: its key and a detail text that is printed but never compared. -/
structure Alert where
  key : Key
  detail : String
deriving DecidableEq, Repr

/-- The list with only the first occurrence of each element, in order. -/
def uniq {α : Type} [DecidableEq α] : List α → List α
  | [] => []
  | x :: xs => x :: (uniq xs).filter fun y => decide (y ≠ x)

/-- The distinct keys of a check's alerts, in first-seen order. -/
def keysOf (now : List Alert) : List Key := uniq (now.map (·.key))

/-- The detail of the first alert of a check with key `k`; the empty string when the check has none. -/
def detailOf (now : List Alert) (k : Key) : String :=
  match now.find? fun a => decide (a.key = k) with
  | some a => a.detail
  | none => ""

/-- The keys a check opens: present in the check, absent from the open set. -/
def openedKeys (prev : List Key) (now : List Alert) : List Key :=
  (keysOf now).filter fun k => decide (k ∉ prev)

/-- The keys a check closes: in the open set, absent from the check. -/
def closedKeys (prev : List Key) (now : List Alert) : List Key :=
  (uniq prev).filter fun k => decide (k ∉ now.map (·.key))

/-- The result of one check: the alerts it opens (with their detail), the keys it closes, the next open set. -/
structure Step where
  opened : List Alert
  closed : List Key
  next : List Key
deriving DecidableEq, Repr

/-- One check of the stream against the open set `prev`. -/
def step (prev : List Key) (now : List Alert) : Step :=
  { opened := (openedKeys prev now).map fun k => ⟨k, detailOf now k⟩
    closed := closedKeys prev now
    next := keysOf now }

/-- One printed line of the stream: `OPEN` with the alert, or `CLOSE` with the key. -/
inductive Ev where
  | opened (a : Alert)
  | closed (k : Key)
deriving DecidableEq, Repr

/-- The key a line is about. -/
def Ev.key : Ev → Key
  | .opened a => a.key
  | .closed k => k

/-- The lines of one check: its opens, then its closes. -/
def Step.events (s : Step) : List Ev := s.opened.map .opened ++ s.closed.map .closed

/-- A stream run from the open set `s` over the checks `ts`: every printed line, in order, and the final open set. -/
def run : List Key → List (List Alert) → List Ev × List Key
  | s, [] => ([], s)
  | s, now :: ts =>
    let st := step s now
    let r := run st.next ts
    (st.events ++ r.1, r.2)

/-- The lines about one key. -/
def proj (k : Key) (evs : List Ev) : List Ev := evs.filter fun e => decide (e.key = k)

/-- The lines about one key alternate between `OPEN` and `CLOSE`, starting from the given open flag. -/
def Alternates : Bool → List Ev → Prop
  | _, [] => True
  | b, .opened _ :: r => b = false ∧ Alternates true r
  | b, .closed _ :: r => b = true ∧ Alternates false r

/-- Whether a key is open after the given lines, starting from the given flag: the last line decides. -/
def openAfter : Bool → List Ev → Bool
  | b, [] => b
  | _, .opened _ :: r => openAfter true r
  | _, .closed _ :: r => openAfter false r

/-- `uniq` keeps exactly the members. -/
theorem mem_uniq {α : Type} [DecidableEq α] (l : List α) (a : α) : a ∈ uniq l ↔ a ∈ l := by
  induction l with
  | nil => simp [uniq]
  | cons x xs ih =>
    simp only [uniq, List.mem_cons, List.mem_filter, ih, decide_eq_true_eq]
    by_cases h : a = x <;> simp [h]

/-- In `uniq l` the elements equal to `k` are one `k` when `k ∈ l` and none otherwise. -/
theorem uniq_filter_eq {α : Type} [DecidableEq α] (l : List α) (k : α) :
    (uniq l).filter (fun x => decide (x = k)) = if k ∈ l then [k] else [] := by
  induction l with
  | nil => simp [uniq]
  | cons x xs ih =>
    simp only [uniq, List.filter_cons, List.filter_filter]
    by_cases hx : x = k
    · subst hx
      have : (uniq xs).filter (fun y => decide (y = x) && decide (y ≠ x)) = [] := by
        rw [List.filter_eq_nil_iff]; intro a _; by_cases h : a = x <;> simp [h]
      simp only [decide_true, ↓reduceIte, this]; simp
    · have hc : (uniq xs).filter (fun y => decide (y = k) && decide (y ≠ x)) =
          ((uniq xs).filter fun y => decide (y = k)).filter fun y => decide (y ≠ x) := by
        rw [List.filter_filter]; congr 1; funext y; exact Bool.and_comm _ _
      have hne : k ≠ x := fun h => hx h.symm
      simp only [decide_eq_true_eq, hx, ↓reduceIte]
      rw [hc, ih]
      by_cases hk : k ∈ xs <;> simp [hk, hne]

/-- A check's keys are exactly the keys of its alerts. -/
theorem mem_keysOf (now : List Alert) (k : Key) : k ∈ keysOf now ↔ k ∈ now.map (·.key) :=
  mem_uniq _ _

/-- Each key is decided on its own: whether a check opens it, closes it or keeps it open depends only on whether the
key is in the open set and in the check. Here `K_N = [ a.key : a ∈ N ]`.
-/
theorem diff_per_key (prev : List Key) (now : List Alert) (k : Key) :
    (k ∈ (step prev now).opened.map (·.key) ↔ k ∉ prev ∧ k ∈ now.map (·.key)) ∧
    (k ∈ (step prev now).closed ↔ k ∈ prev ∧ k ∉ now.map (·.key)) ∧
    (k ∈ (step prev now).next ↔ k ∈ now.map (·.key)) := by
  refine ⟨?_, ?_, mem_keysOf now k⟩
  · simp only [step, List.map_map, Function.comp_def, List.map_id', openedKeys, List.mem_filter, mem_keysOf,
      decide_eq_true_eq]
    exact ⟨fun ⟨a, b⟩ => ⟨b, a⟩, fun ⟨a, b⟩ => ⟨b, a⟩⟩
  · simp only [step, closedKeys, List.mem_filter, mem_uniq, decide_eq_true_eq]

/-- The lines of one check about one key: an `OPEN` when the key is new, a `CLOSE` when it went away, else none. Here
`K_N = [ a.key : a ∈ N ]`; the first two cases cannot both hold.
-/
theorem proj_step (prev : List Key) (now : List Alert) (k : Key) :
    proj k (step prev now).events =
      if k ∉ prev ∧ k ∈ now.map (·.key) then [.opened ⟨k, detailOf now k⟩]
      else if k ∈ prev ∧ k ∉ now.map (·.key) then [.closed k] else [] := by
  have ho : ((openedKeys prev now).filter fun x => decide (x = k)) =
      if k ∉ prev ∧ k ∈ now.map (·.key) then [k] else [] := by
    have : ((openedKeys prev now).filter fun x => decide (x = k)) =
        ((keysOf now).filter fun x => decide (x = k)).filter fun x => decide (x ∉ prev) := by
      simp only [openedKeys, List.filter_filter]; congr 1; funext y; exact Bool.and_comm _ _
    rw [this, keysOf, uniq_filter_eq]
    clear this
    by_cases h1 : k ∈ now.map (·.key) <;> by_cases h2 : k ∈ prev <;> simp_all
  have hc : ((closedKeys prev now).filter fun x => decide (x = k)) =
      if k ∈ prev ∧ k ∉ now.map (·.key) then [k] else [] := by
    have : ((closedKeys prev now).filter fun x => decide (x = k)) =
        ((uniq prev).filter fun x => decide (x = k)).filter fun x => decide (x ∉ now.map (·.key)) := by
      simp only [closedKeys, List.filter_filter]; congr 1; funext y; exact Bool.and_comm _ _
    rw [this, uniq_filter_eq]
    clear this ho
    by_cases h1 : k ∈ now.map (·.key) <;> by_cases h2 : k ∈ prev <;> simp_all
  have e1 : proj k ((step prev now).opened.map Ev.opened) =
      ((openedKeys prev now).filter fun x => decide (x = k)).map fun x => Ev.opened ⟨x, detailOf now x⟩ := by
    simp [proj, step, List.filter_map, Function.comp_def, Ev.key] <;> rfl
  have e2 : proj k ((step prev now).closed.map Ev.closed) =
      ((closedKeys prev now).filter fun x => decide (x = k)).map Ev.closed := by
    simp only [proj, step, List.filter_map, Function.comp_def, Ev.key] <;> rfl
  simp only [Step.events, proj, List.filter_append] at e1 e2 ⊢
  rw [e1, e2, ho, hc]
  by_cases h1 : k ∈ now.map (·.key) <;> by_cases h2 : k ∈ prev <;> simp [h1, h2]

/-- Projection distributes over a run's first check. -/
theorem proj_run_cons (s : List Key) (now : List Alert) (ts : List (List Alert)) (k : Key) :
    proj k (run s (now :: ts)).1 = proj k (step s now).events ++ proj k (run (keysOf now) ts).1 := by
  simp [run, proj, List.filter_append, step]

/-- Over any run, the lines about any key alternate `OPEN`, `CLOSE`, `OPEN`, ..., starting from whether the key is in
the initial open set: no key is printed open twice without a close between, nor closed twice without an open between. Here `[k ∈ S]` is `⊤` when `k ∈ S` and `⊥` otherwise.
-/
theorem opened_once (s : List Key) (ts : List (List Alert)) (k : Key) :
    Alternates (decide (k ∈ s)) (proj k (run s ts).1) := by
  induction ts generalizing s with
  | nil => simp [run, proj, Alternates]
  | cons now ts ih =>
    rw [proj_run_cons, proj_step]
    have hn := ih (keysOf now)
    rw [show decide (k ∈ keysOf now) = decide (k ∈ now.map (·.key)) by simp [mem_keysOf]] at hn
    by_cases h1 : k ∈ now.map (·.key) <;> by_cases h2 : k ∈ s <;>
      simp only [h1, h2, not_true_eq_false, not_false_eq_true, and_true, and_false, ↓reduceIte, decide_true, decide_false, List.nil_append, List.cons_append] at hn ⊢ <;> (try simp only [Alternates, true_and]) <;> exact hn

/-- After any run the final open set holds a key exactly when the key's last line is `OPEN` (or, with no line about
it, when the initial open set held it). Here `[k ∈ S]` is `⊤` when `k ∈ S` and `⊥` otherwise.
-/
theorem run_state_iff (s : List Key) (ts : List (List Alert)) (k : Key) :
    k ∈ (run s ts).2 ↔ openAfter (decide (k ∈ s)) (proj k (run s ts).1) = true := by
  induction ts generalizing s with
  | nil => simp [run, proj, openAfter]
  | cons now ts ih =>
    have hs : (run s (now :: ts)).2 = (run (keysOf now) ts).2 := rfl
    rw [hs, proj_run_cons, proj_step, ih (keysOf now)]
    rw [show decide (k ∈ keysOf now) = decide (k ∈ now.map (·.key)) by simp [mem_keysOf]]
    by_cases h1 : k ∈ now.map (·.key) <;> by_cases h2 : k ∈ s <;>
      simp only [h1, h2, not_true_eq_false, not_false_eq_true, and_true, and_false, ↓reduceIte, decide_true, decide_false, List.nil_append, List.cons_append] <;> simp only [openAfter]

/-- After a run whose last check is `N`, the open set is exactly the keys of `N`. -/
theorem run_last (s : List Key) (ts : List (List Alert)) (now : List Alert) (k : Key) :
    k ∈ (run s (ts ++ [now])).2 ↔ k ∈ now.map (·.key) := by
  induction ts generalizing s with
  | nil => simp [run, step, mem_keysOf]
  | cons t ts ih => exact ih (keysOf t)

/-- A key that ends open after lines starting closed has an `OPEN` line among them. -/
theorem exists_opened_of_openAfter (l : List Ev) (h : openAfter false l = true) : ∃ a, Ev.opened a ∈ l := by
  induction l with
  | nil => simp [openAfter] at h
  | cons e r ih =>
    cases e with
    | opened a => exact ⟨a, List.mem_cons_self⟩
    | closed k =>
      obtain ⟨a, ha⟩ := ih (by simpa [openAfter] using h)
      exact ⟨a, List.mem_cons_of_mem _ ha⟩

/-- Every alert a check sees was printed open by the end of that check: either its key was in the initial open set
or the stream printed an `OPEN` line with that key at that check or before.
-/
theorem every_open_reported (s : List Key) (ts : List (List Alert)) (now : List Alert) (k : Key)
    (hs : k ∉ s) (hn : k ∈ now.map (·.key)) : ∃ d, Ev.opened ⟨k, d⟩ ∈ (run s (ts ++ [now])).1 := by
  have h := (run_state_iff s (ts ++ [now]) k).1 ((run_last s ts now k).2 hn)
  rw [show decide (k ∈ s) = false by simp [hs]] at h
  obtain ⟨a, ha⟩ := exists_opened_of_openAfter _ h
  rw [proj, List.mem_filter] at ha
  obtain ⟨hm, hk⟩ := ha
  have hk' : a.key = k := of_decide_eq_true hk
  exact ⟨a.detail, by cases a; subst hk'; exact hm⟩

/-! ## Declared long-runners -/

/-- A declared long-runner in `keep.json`: its pid and its absolute start time (seconds since the epoch). -/
structure Entry where
  pid : Nat
  start : Nat
deriving DecidableEq, Repr

/-- A running process: pid, absolute start time (seconds since the epoch) and command line. -/
structure Row where
  pid : Nat
  start : Nat
  args : String
deriving DecidableEq, Repr

/-- The checked-in command lines that are long-runners without a declaration: the lead's Monitor stream. -/
def monitorShapes : List String := ["node apps/runner/src/fw.ts watch --interval 300 --stream"]

/-- Whether a running process has the declared pid and the declared start time. -/
def sameProcess (rows : List Row) (e : Entry) : Bool :=
  rows.any fun r => decide (r.pid = e.pid ∧ r.start = e.start)

/-- The declarations whose process still runs. -/
def liveEntries (rows : List Row) (entries : List Entry) : List Entry := entries.filter (sameProcess rows)

/-- The pids exempt as long-runners: those of live declarations and those running an allowlisted command line. -/
def keepPids (entries : List Entry) (rows : List Row) : List Nat :=
  uniq ((liveEntries rows entries).map (·.pid) ++ (rows.filter fun r => decide (r.args ∈ monitorShapes)).map (·.pid))

/-- The allowlist is one fixed command line. -/
theorem monitor_shape_iff (s : String) :
    s ∈ monitorShapes ↔ s = "node apps/runner/src/fw.ts watch --interval 300 --stream" := by
  simp [monitorShapes]

/-- A declaration stays live exactly while a process with its pid and its start time runs; no clock enters. -/
theorem keep_same_process (rows : List Row) (entries : List Entry) (e : Entry) :
    e ∈ liveEntries rows entries ↔ e ∈ entries ∧ ∃ r ∈ rows, r.pid = e.pid ∧ r.start = e.start := by
  simp [liveEntries, sameProcess]

/-- A pid is exempt exactly when a declaration with that pid matches a running process's start time, or a process with
that pid runs an allowlisted command line.
-/
theorem keep_iff (entries : List Entry) (rows : List Row) (p : Nat) :
    p ∈ keepPids entries rows ↔
      (∃ e ∈ entries, e.pid = p ∧ ∃ r ∈ rows, r.pid = p ∧ r.start = e.start) ∨
      (∃ r ∈ rows, r.pid = p ∧ r.args ∈ monitorShapes) := by
  simp only [keepPids, mem_uniq, List.mem_append, List.mem_map, List.mem_filter, decide_eq_true_eq,
    keep_same_process]
  constructor
  · rintro (⟨e, ⟨he, r, hr, hp, hs⟩, rfl⟩ | ⟨r, ⟨hr, ha⟩, rfl⟩)
    · exact .inl ⟨e, he, rfl, r, hr, hp, hs⟩
    · exact .inr ⟨r, hr, rfl, ha⟩
  · rintro (⟨e, he, rfl, r, hr, hp, hs⟩ | ⟨r, hr, rfl, ha⟩)
    · exact .inl ⟨e, ⟨he, r, hr, hp, hs⟩, rfl⟩
    · exact .inr ⟨r, ⟨hr, ha⟩, rfl⟩

/-- A reused pid is never exempt: when every running process with pid `p` started at a time no declaration of `p`
names, and none runs an allowlisted command line, `p` is not kept.
-/
theorem reused_pid_not_kept (entries : List Entry) (rows : List Row) (p : Nat)
    (h : ∀ r ∈ rows, r.pid = p → (∀ e ∈ entries, e.pid = p → e.start ≠ r.start) ∧ r.args ∉ monitorShapes) :
    p ∉ keepPids entries rows := by
  rw [keep_iff]
  rintro (⟨e, he, hep, r, hr, hp, hs⟩ | ⟨r, hr, hp, ha⟩)
  · exact (h r hr hp).1 e he hep hs.symm
  · exact (h r hr hp).2 ha

private def k (c s : String) : Key := ⟨c, s⟩
private def a (c s : String) (d : String := "") : Alert := ⟨⟨c, s⟩, d⟩

#guard step [] [a "x" "1" "d1", a "x" "1" "d2"] = ⟨[a "x" "1" "d1"], [], [k "x" "1"]⟩
#guard step [k "x" "1", k "y" "2"] [a "y" "2", a "z" "3"] = ⟨[a "z" "3"], [k "x" "1"], [k "y" "2", k "z" "3"]⟩
#guard step [k "x" "1", k "x" "1"] [] = ⟨[], [k "x" "1"], []⟩
#guard step [k "x" "1"] [a "x" "1"] = ⟨[], [], [k "x" "1"]⟩
#guard (run [] [[a "x" "1"], [a "x" "1"], [], [a "x" "1"]]).1 =
  [.opened (a "x" "1"), .closed (k "x" "1"), .opened (a "x" "1")]
#guard keepPids [⟨7, 100⟩, ⟨8, 100⟩] [⟨7, 100, "sleep"⟩, ⟨8, 101, "python"⟩] = [7]
#guard keepPids [] [⟨9, 5, "node apps/runner/src/fw.ts watch --interval 300 --stream"⟩, ⟨10, 5, "node apps/runner/src/fw.ts watch --interval 60 --stream"⟩] = [9]
#guard liveEntries [⟨7, 100, ""⟩] [⟨7, 100⟩, ⟨7, 99⟩] = [⟨7, 100⟩]

end Fw.Ops.WatchDiff

/-! ## Wire: `ops.watchDiff`, `ops.watchKeep` -/

namespace Fw.Wire.WatchDiff
open Lean Fw.Ops.WatchDiff Fw.Wire.Ops

/-- A key from `{code, subject}`. -/
def keyOf (j : Json) : Except String Key := do pure ⟨← str j "code", ← str j "subject"⟩

/-- An alert from `{code, subject, detail?}` (absent detail is empty). -/
def alertOf (j : Json) : Except String Alert := do pure ⟨← keyOf j, ← strD j "detail" ""⟩

/-- A key as `{code, subject}`. -/
def keyJson (x : Key) : Json := Json.mkObj [("code", .str x.code), ("subject", .str x.subject)]

/-- An alert as `{code, subject, detail}`. -/
def alertJson (x : Alert) : Json :=
  Json.mkObj [("code", .str x.key.code), ("subject", .str x.key.subject), ("detail", .str x.detail)]

/-- `ops.watchDiff`: `prev`? [{code, subject}] (the open set; absent is empty), `now` [{code, subject, detail?}] →
`opened` [{code, subject, detail}], `closed` [{code, subject}], `next` [{code, subject}]. -/
def opWatchDiff (req : Json) : Except String Reply := do
  let prev ← (← arrD req "prev").mapM keyOf
  let now ← (← arr req "now").toList.mapM alertOf
  let s := step prev now
  pure [("opened", .arr (s.opened.toArray.map alertJson)), ("closed", .arr (s.closed.toArray.map keyJson)),
    ("next", .arr (s.next.toArray.map keyJson))]

/-- `ops.watchKeep`: `entries` [{pid, start}], `rows` [{pid, start, args}] (start in seconds since the epoch) →
`live` (indices of the entries whose process runs), `keep` (exempt pids). -/
def opWatchKeep (req : Json) : Except String Reply := do
  let entries ← (← arrD req "entries").mapM fun j => do pure (Entry.mk (← nat j "pid") (← nat j "start"))
  let rows ← (← arrD req "rows").mapM fun j => do pure (Row.mk (← nat j "pid") (← nat j "start") (← strD j "args" ""))
  let live := (entries.zipIdx.filter fun (e, _) => sameProcess rows e).map fun (_, i) => toJson i
  pure [("live", .arr live.toArray), ("keep", .arr ((keepPids entries rows).toArray.map toJson))]

/-- The ops of this module. -/
def ops : List String := ["ops.watchDiff", "ops.watchKeep"] ++ Fw.Wire.WatchMem.ops

/-- Dispatch (`none` when the op is not one of these). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "ops.watchDiff" => some (opWatchDiff req)
  | "ops.watchKeep" => some (opWatchKeep req)
  | _ => Fw.Wire.WatchMem.handle op req

#guard ops.all fun o => (handle o (Json.mkObj [("now", .arr #[])])).isSome

end Fw.Wire.WatchDiff
