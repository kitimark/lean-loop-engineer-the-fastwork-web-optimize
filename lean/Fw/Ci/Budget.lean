/-!
# GitHub API rate budget: one charged ledger for every `gh` call of the machine

Spec of the choke point `ghCharged` and the shared CI poller (design: `research/notes/2026/10-18-gh-rate-budget.md`
§3; wire ops in `Fw.Wire.Ci`, file `Fw/Ci/Wire.lean`). Every GitHub request our tools make is first *charged* to a
ledger shared by the whole machine. `reserve` (one-off calls) and `next` (the poller's tick) decide whether a call may
go now; `observe` folds the response headers back in. All times are integer seconds.

The ledger has two shares per window, so one-off calls (downloads, logs) can never starve the poller: ticks get
`B - R` per hour and `B_1 - R_1` per minute, one-offs `R` and `R_1`. A response that cost more requests than charged
is booked as a *correction* entry; corrections count against the share, so later calls wait until the window has room
again. Only the REST `core` bucket's headers update the remaining count (`x-ratelimit-resource: core`).

Proved here:
- (a) `window_bound`: in every reachable state and for every time `t`, the charged requests of each share in the
  3600 s and 60 s windows stay within the share, so all of them stay within `B` and `B_1`; `window_total`: the
  total over both kinds is at most `B`. Waiters never enter the ledger (`register_free`, `register_dup`), so the
  bound holds for every number of waiters `N`. `overrun_absorbed`: with corrections the window holds at most the
  share plus the corrections in it.
- (b) `no_issue_when_exhausted`, `next_no_issue_when_exhausted`: nothing is issued while `now < retryUntil`, nor while
  remaining `≤ F` before the reset. `guard_persists`: a `retry-after` or a 403/429 with remaining 0 blocks every
  issue until that time, along every later trace. `backoff_ge`, `backoff_mono`, `stop_after_fails`: the bare-failure
  backoff.
- (c) `poll_live`: whenever the guards allow and the interval has passed, `next` ticks and covers every watched run;
  `next_wait_interval`: otherwise it waits at most `P`; `wait_future`: no wait is in the past.
- (d) `interval_sound`: the interval `P` makes any ticks spaced `≥ P` fit both tick shares and the headroom before
  the reset; `per_agent_interval`, `oldRate_linear`: the old scheme (`N` pollers each on its own) grows linearly in
  `N` and needs `P ≥ W c N / B`.
- (e) `clock_monotone`: `now` never goes back.
- (f) `listed_within`, `listed_within_Pmin`: while the poller asks on time and the guards have room, a run completed
  after the last tick is listed by the next tick, at most `P` (with the gaps below `P_min`: `P_min`) after it
  completed, and a waiter reading every `slice` seconds sees it within `slice` more.
- (g) `budget_all_entries`: every ledger entry (charges and corrections) in a window plus the uncharged requests stays
  within GitHub's 5000 per hour per user account, given that corrections plus uncharged requests fit `margin`.
- (h) `bucket_core_only`, `remaining_no_rise`: headers of other buckets leave the remaining count alone, and within one
  reset window it never rises.
-/
namespace Fw.Ci.Budget

/-! ## Limits -/

/-- The budget's constants (generated to `packages/contracts/golden/ci-budget/limits.json`; TS reads them there). -/
structure Limits where
  /-- window length, s -/
  W : Nat := 3600
  /-- charged requests per window `W` -/
  B : Nat := 3000
  /-- the one-off share of `B` (ticks get `B - R`) -/
  R : Nat := 1200
  /-- short window, s (the secondary limit is 900 points per minute) -/
  W1 : Nat := 60
  /-- charged requests per short window -/
  B1 : Nat := 60
  /-- the one-off share of `B1` (ticks get `B1 - R1`) -/
  R1 : Nat := 40
  /-- header floor: no call while `remaining ≤ F` before the reset -/
  F : Nat := 500
  /-- minimum tick interval, s -/
  Pmin : Nat := 10
  /-- first backoff after a bare 403/429, s -/
  back0 : Nat := 60
  /-- longest backoff, s -/
  backMax : Nat := 3600
  /-- bare failures in a row before the poller stops -/
  maxFails : Nat := 6
  /-- requests per page of one tick: the poller's `gh run list` without `--workflow`, measured at 2 (82 ticks, no
  tick correction, 2026-10-19) -/
  listCost : Nat := 2
  /-- ticks that list a watched run's creation time without it before the watch is dropped -/
  missMax : Nat := 3
  /-- exclusive bound of a GitHub run id (ids are about 2.5e10 in 2026) -/
  maxRun : Nat := 10 ^ 13
deriving Repr, DecidableEq

/-- The default limits. -/
def defaults : Limits := {}

#guard defaults.B = 3000 && defaults.R = 1200 && defaults.F = 500 && defaults.Pmin = 10 && defaults.B1 = 60

/-- The two kinds of charged call: a poller tick, or a one-off call (dispatch, view, log, download, probe). -/
inductive Kind where
  | tick
  | oneoff
deriving Repr, DecidableEq

/-- The hourly share of a kind. -/
def share (L : Limits) : Kind → Nat
  | .tick => L.B - L.R
  | .oneoff => L.R

/-- The per-minute share of a kind. -/
def share1 (L : Limits) : Kind → Nat
  | .tick => L.B1 - L.R1
  | .oneoff => L.R1

#guard share defaults .tick = 1800 && share defaults .oneoff = 1200
#guard share1 defaults .tick = 20 && share1 defaults .oneoff = 40

/-! ## The ledger and its window sums -/

/-- One ledger entry: the time it was charged, its cost in requests, its kind, and whether it is a charge
(`true`) or a correction for a response that cost more than charged (`false`).
-/
structure Entry where
  time : Nat
  cost : Nat
  kind : Kind
  charged : Bool
deriving Repr, DecidableEq

/-- Is time `x` inside the window of length `W` ending at `t`, that is `x ∈ (t - W, t]`? -/
def inWin (W t x : Nat) : Bool := decide (x ≤ t) && decide (t < x + W)

/-- The cost of the selected entries of a ledger that lie in the window of length `W` ending at `t`. -/
def wsum (W t : Nat) (sel : Entry → Bool) : List Entry → Nat
  | [] => 0
  | e :: es => (if sel e && inWin W t e.time then e.cost else 0) + wsum W t sel es

/-- Entries of kind `k` (charges and corrections). -/
def ofKind (k : Kind) (e : Entry) : Bool := decide (e.kind = k)

/-- Charges of kind `k`. -/
def chargedOf (k : Kind) (e : Entry) : Bool := decide (e.kind = k) && e.charged

/-- Corrections of kind `k`. -/
def corrOf (k : Kind) (e : Entry) : Bool := decide (e.kind = k) && !e.charged

/-- Every charge, of either kind. -/
def isCharge (e : Entry) : Bool := e.charged

/-- The window sum of a concatenation is the sum of the window sums. -/
theorem wsum_append (W t : Nat) (sel : Entry → Bool) (a b : List Entry) :
    wsum W t sel (a ++ b) = wsum W t sel a + wsum W t sel b := by
  induction a with
  | nil => simp [wsum]
  | cons e es ih => simp only [List.cons_append, wsum, ih]; omega

/-- The window sum of one entry. -/
theorem wsum_single (W t : Nat) (sel : Entry → Bool) (e : Entry) :
    wsum W t sel [e] = if sel e && inWin W t e.time then e.cost else 0 := by
  simp [wsum]

/-- A weaker selector sums to no more. -/
theorem wsum_mono_sel (W t : Nat) (sel sel' : Entry → Bool) (l : List Entry)
    (h : ∀ e ∈ l, sel e = true → sel' e = true) : wsum W t sel l ≤ wsum W t sel' l := by
  induction l with
  | nil => simp [wsum]
  | cons e es ih =>
    simp only [wsum]
    have h1 := h e (by simp)
    have h2 := ih (fun x hx => h x (by simp [hx]))
    cases hs : sel e <;> cases hs' : sel' e <;> simp_all <;> split <;> omega

/-- Dropping entries does not increase a window sum. -/
theorem wsum_filter_le (W t : Nat) (sel p : Entry → Bool) (l : List Entry) :
    wsum W t sel (l.filter p) ≤ wsum W t sel l := by
  induction l with
  | nil => simp [wsum]
  | cons e es ih =>
    simp only [List.filter]
    cases p e <;> simp only [wsum] <;> omega

/-- When every entry is at or before `n`, a window ending later than `n` holds no more than the one ending at `n`. -/
theorem wsum_later (W t n : Nat) (sel : Entry → Bool) (l : List Entry)
    (hall : ∀ e ∈ l, e.time ≤ n) (hnt : n ≤ t) : wsum W t sel l ≤ wsum W n sel l := by
  induction l with
  | nil => simp [wsum]
  | cons e es ih =>
    simp only [wsum]
    have he := hall e (by simp)
    have h2 := ih (fun x hx => hall x (by simp [hx]))
    have hh : (if sel e && inWin W t e.time then e.cost else 0) ≤ (if sel e && inWin W n e.time then e.cost else 0) := by
      split <;> split <;> simp_all [inWin] <;> omega
    omega

/-- The window sum of a kind splits into its charges and its corrections. -/
theorem wsum_split (W t : Nat) (k : Kind) (l : List Entry) :
    wsum W t (ofKind k) l = wsum W t (chargedOf k) l + wsum W t (corrOf k) l := by
  induction l with
  | nil => simp [wsum]
  | cons e es ih =>
    rcases e with ⟨time, cost, kind, charged⟩
    simp only [wsum, ih, ofKind, chargedOf, corrOf]
    cases charged <;> simp <;> omega

/-- The charges of both kinds are the charges of ticks plus the charges of one-offs. -/
theorem wsum_charges (W t : Nat) (l : List Entry) :
    wsum W t isCharge l = wsum W t (chargedOf .tick) l + wsum W t (chargedOf .oneoff) l := by
  induction l with
  | nil => simp [wsum]
  | cons e es ih =>
    rcases e with ⟨time, cost, kind, charged⟩
    simp only [wsum, ih, isCharge, chargedOf]
    cases kind <;> simp <;> omega

/-! ## Headers -/

/-- The rate-limit facts of a response, as read from its header lines; `resource` names the bucket that `remaining`
and `reset` count (`core` for the REST API).
-/
structure Headers where
  status : Nat := 0
  remaining : Option Nat := none
  reset : Option Nat := none
  retryAfter : Option Nat := none
  etag : Option String := none
  resource : Option String := none
deriving Repr, DecidableEq

/-- A line with the debug prefix `< ` (httpretty's response marker) and the surrounding blanks removed. -/
def unprefix (s : String) : String :=
  let t := s.trimAscii.toString
  if t.startsWith "<" then (t.drop 1).trimAscii.toString else t

/-- The status code of a status line `HTTP/<v> <code> <text>`; `none` for any other line.

Here toNat? is Lean's `String.toNat?`, which reads decimal digits and also accepts `_` separators (`1_000` gives 1000).
-/
def statusOf (s : String) : Option Nat :=
  let t := unprefix s
  if t.startsWith "HTTP/" then
    match (t.splitOn " ").filter (· ≠ "") with
    | _ :: code :: _ => code.toNat?
    | _ => none
  else none

/-- A header line `Name: value` as (lower-case name, trimmed value); `none` for a line without a colon. -/
def headerOf (s : String) : Option (String × String) :=
  match (unprefix s).splitOn ":" with
  | name :: rest@(_ :: _) =>
    some (name.trimAscii.toString.toLower, (":".intercalate rest).trimAscii.toString)
  | _ => none

/-- Fold one line into the headers read so far; a later line overrides an earlier one, and a status line starts a
new response, so `remaining`, `reset` and `resource` always come from one response.
-/
def readLine (h : Headers) (s : String) : Headers :=
  match statusOf s with
  | some n => { h with status := n, remaining := none, reset := none, resource := none }
  | none =>
    match headerOf s with
    | some ("x-ratelimit-remaining", v) => match v.toNat? with | some n => { h with remaining := some n } | none => h
    | some ("x-ratelimit-reset", v) => match v.toNat? with | some n => { h with reset := some n } | none => h
    | some ("retry-after", v) => match v.toNat? with | some n => { h with retryAfter := some n } | none => h
    | some ("etag", v) => { h with etag := some v }
    | some ("x-ratelimit-resource", v) => { h with resource := some v }
    | _ => h

/-- The headers of a trace and the number of responses in it (status lines): `status`, `retryAfter` and `etag` are
the last values in the trace; `remaining`, `reset` and `resource` are those of the last response.
-/
def parse (ls : List String) : Headers × Nat :=
  (ls.foldl readLine {}, (ls.filter fun s => (statusOf s).isSome).length)

#guard parse ["< HTTP/2.0 200 OK", "< X-Ratelimit-Remaining: 4998", "< X-Ratelimit-Reset: 1760752800",
  "< Content-Type: application/json"] = ({ status := 200, remaining := some 4998, reset := some 1760752800 }, 1)
#guard parse ["HTTP/2.0 304 Not Modified", "Etag: W/\"abc\"", "x-ratelimit-remaining: 7"] =
  ({ status := 304, remaining := some 7, etag := some "W/\"abc\"" }, 1)
#guard parse ["< HTTP/2.0 200 OK", "< X-Ratelimit-Remaining: 10", "< HTTP/2.0 403 Forbidden", "< Retry-After: 60",
  "< X-Ratelimit-Remaining: 9"] = ({ status := 403, remaining := some 9, retryAfter := some 60 }, 2)
#guard parse ["* Request at 2026", "> GET /repos HTTP/1.1", "< X-Ratelimit-Remaining: x"] = ({}, 0)
#guard parse ["< HTTP/2.0 200 OK", "< X-Ratelimit-Remaining: 4913", "< X-Ratelimit-Reset: 900",
  "< X-Ratelimit-Resource: core", "< HTTP/2.0 200 OK", "< X-Ratelimit-Remaining: 4999", "< X-Ratelimit-Resource: graphql"] =
  ({ status := 200, remaining := some 4999, resource := some "graphql" }, 2)
#guard parse [] = ({}, 0)

/-! ## State -/

/-- A run some waiter is waiting on: its id, its creation time, and the last tick that covered it. -/
structure Watch where
  runId : Nat
  createdAt : Nat
  lastCovered : Option Nat := none
  /-- ticks in a row whose list covered `createdAt` and lacked the run -/
  misses : Nat := 0
deriving Repr, DecidableEq

/-- Why a watch was dropped: unseen in `missMax` covering lists, older than the newest pages a tick may read, or
left without a live waiter (`orphan`). -/
inductive Drop where
  | unseen
  | uncovered
  | orphan
deriving Repr, DecidableEq

/-- An incident: the run dropped, when, and why. -/
structure Incident where
  runId : Nat
  time : Nat
  why : Drop
deriving Repr, DecidableEq

/-- The budget state shared by the machine: the clock, the ledger, the last seen headers, the retry and failure
state, the watched runs, the last tick, the call in flight, and the pages one tick needs.
-/
structure State where
  now : Nat
  ledger : List Entry := []
  remaining : Option Nat := none
  reset : Option Nat := none
  retryUntil : Nat := 0
  fails : Nat := 0
  etag : Option String := none
  watched : List Watch := []
  lastTick : Option Nat := none
  pending : Option (Kind × Nat) := none
  pages : Nat := 1
  /-- watches dropped and not yet acknowledged (the poller logs them, then sends `ack`) -/
  incidents : List Incident := []
deriving Repr, DecidableEq

/-- The empty state at time `t`. -/
def init (t : Nat) : State := { now := t }

/-! ## Guards and costs -/

/-- Do the last seen headers leave room: remaining unknown, above the floor, or the reset already passed? -/
def headroom (L : Limits) (s : State) : Bool :=
  match s.remaining with
  | none => true
  | some r => decide (L.F < r) || (match s.reset with | some T => decide (T ≤ s.now) | none => false)

/-- The most pages one tick may read: the pages whose list cost fits the per-minute tick share (at least one). -/
def pageCap (L : Limits) : Nat := max 1 (share1 L .tick / L.listCost)

/-- The pages the next tick reads: those the state asks for, at least one, at most `pageCap`. -/
def pagesOf (L : Limits) (s : State) : Nat := min (pageCap L) (max 1 s.pages)

/-- The cost of one tick: the list cost per page times the pages it reads. -/
def tickCost (L : Limits) (s : State) : Nat := L.listCost * pagesOf L s

/-- Integer ceiling division (`0` when dividing by `0`, as Lean's `/`). -/
def ceilDiv (a b : Nat) : Nat := (a + b - 1) / b

#guard ceilDiv 3600 900 = 4 && ceilDiv 10 3 = 4 && ceilDiv 0 5 = 0 && ceilDiv 7 0 = 0

/-- The backoff after `k` bare failures in a row: `b_0 · 2^k`, at most `b_max`. -/
def backoff (L : Limits) (k : Nat) : Nat := min L.backMax (L.back0 * 2 ^ k)

#guard (List.range 8).map (backoff defaults) = [60, 120, 240, 480, 960, 1920, 3600, 3600]

/-- The gap between ticks that fits the hourly tick share. -/
def hourGap (L : Limits) (s : State) : Nat := ceilDiv L.W (max 1 (share L .tick / tickCost L s))

/-- The gap between ticks that fits the per-minute tick share. -/
def minuteGap (L : Limits) (s : State) : Nat := ceilDiv L.W1 (max 1 (share1 L .tick / tickCost L s))

/-- The gap that spreads the headroom above the floor until the reset, when the headers are known and the reset is
ahead; 0 otherwise.
-/
def spread (L : Limits) (s : State) : Nat :=
  match s.remaining, s.reset with
  | some r, some T => if s.now < T then ceilDiv (T - s.now) (max 1 ((r - L.F) / tickCost L s)) else 0
  | _, _ => 0

/-- The tick interval: the minimum interval, the gaps that fit both tick shares, and the gap that spreads the
headroom until the reset.
-/
def interval (L : Limits) (s : State) : Nat :=
  max L.Pmin (max (hourGap L s) (max (minuteGap L s) (spread L s)))

#guard interval defaults (init 0) = 10
#guard hourGap defaults (init 0) = 4 && minuteGap defaults (init 0) = 6 && spread defaults (init 0) = 0
-- 600 left above the floor for 3600 s at cost 2: 300 ticks, one per 12 s
#guard interval defaults { now := 0, remaining := some 1100, reset := some 3600 } = 12
-- 20 left above the floor for 3600 s: 10 ticks, one per 360 s
#guard interval defaults { now := 0, remaining := some 520, reset := some 3600 } = 360
-- a full list (100 rows) needs 2 pages: a tick costs 4, the minute share then spaces ticks 12 s apart
#guard tickCost defaults { init 0 with pages := 2 } = 4
#guard interval defaults { init 0 with pages := 2 } = 12
#guard ceilDiv 3600 defaults.Pmin * tickCost defaults { init 0 with pages := 2 } ≤ share defaults .tick
#guard ceilDiv 3600 (interval defaults { init 0 with pages := 2 }) * tickCost defaults { init 0 with pages := 2 } = 1200

/-- Why a call waits or stops. -/
inductive Reason where
  | failures
  | idle
  | tooBig
  | retryAfter
  | floor
  | hour
  | minute
  | interval
deriving Repr, DecidableEq

/-- A decision: issue the call (kind, charged cost, the state with the charge booked), wait until a time, or stop. -/
inductive Decision where
  | issue (k : Kind) (cost : Nat) (s' : State)
  | wait (untilT : Nat) (why : Reason)
  | stop (why : Reason)
deriving Repr

/-- The earliest time a window frees enough room for cost `c`: the first expiry time `e.time + W` after
`t` of a ledger entry at which the window sum plus `c` fits the cap, else `t + max(1, W)`.
-/
def freeAt (W t : Nat) (sel : Entry → Bool) (cap c : Nat) (l : List Entry) : Nat :=
  match l.find? (fun e => decide (t < e.time + W) && decide (wsum W (e.time + W) sel l + c ≤ cap)) with
  | some e => e.time + W
  | none => t + max 1 W

/-- When the floor guard blocks: the reset if it is ahead, else `b_0` (at least 1 s) from now. -/
def floorUntil (L : Limits) (s : State) : Nat :=
  match s.reset with
  | some T => if s.now < T then T else s.now + max 1 L.back0
  | none => s.now + max 1 L.back0

/-- Charge a call of kind `k` and cost `c`, first match wins: stop after `maxFails` bare failures; stop when `c`
exceeds a share (it could never go); wait for `retryUntil`; wait while the floor guard blocks; wait while the hour
or the minute share has no room for `c`; else issue, booking `(now, c, k, charged)`.
-/
def charge (L : Limits) (s : State) (k : Kind) (c : Nat) : Decision :=
  if L.maxFails ≤ s.fails then .stop .failures
  else if share L k < c ∨ share1 L k < c then .stop .tooBig
  else if s.now < s.retryUntil then .wait s.retryUntil .retryAfter
  else if headroom L s = false then .wait (floorUntil L s) .floor
  else if share L k < wsum L.W s.now (ofKind k) s.ledger + c then
    .wait (freeAt L.W s.now (ofKind k) (share L k) c s.ledger) .hour
  else if share1 L k < wsum L.W1 s.now (ofKind k) s.ledger + c then
    .wait (freeAt L.W1 s.now (ofKind k) (share1 L k) c s.ledger) .minute
  else .issue k c { s with ledger := s.ledger ++ [⟨s.now, c, k, true⟩], pending := some (k, c) }

/-- `reserve`: may a one-off call of cost `c` go now? It is charged at least 1 request. -/
def reserve (L : Limits) (s : State) (c : Nat) : Decision := charge L s .oneoff (max 1 c)

/-- Mark a tick at `now`: the last tick, and every watched run covered. -/
def cover (s : State) : State :=
  { s with lastTick := some s.now, watched := s.watched.map fun w => { w with lastCovered := some s.now } }

/-- Tick now if the charge allows it, covering every watched run. -/
def tickNow (L : Limits) (s : State) : Decision :=
  match charge L s .tick (tickCost L s) with
  | .issue k c s' => .issue k c (cover s')
  | d => d

/-- `next`: the poller's decision, first match wins: stop after `maxFails` failures; stop when nothing is watched;
wait until the last tick plus `P`; else tick now.
-/
def next (L : Limits) (s : State) : Decision :=
  if L.maxFails ≤ s.fails then .stop .failures
  else if s.watched = [] then .stop .idle
  else match s.lastTick with
    | some t0 => if s.now < t0 + interval L s then .wait (t0 + interval L s) .interval else tickNow L s
    | none => tickNow L s

/-- The oldest creation time among the watched runs: a tick lists the runs created since then
(`created>=…&per_page=100`), so one list call covers every watched run however many waiters there are.
-/
def since (s : State) : Option Nat := (s.watched.map (·.createdAt)).min?

/-! ## Responses and events -/

/-- Is the status a rate-limit refusal (403 or 429)? -/
def refused (n : Nat) : Bool := n == 403 || n == 429

/-- The time a response forbids calls until (0 for none): `now` plus its `retry-after`; its reset, on a refusal with
remaining 0; `now` plus the backoff, on a refusal with neither.
-/
def retryFrom (L : Limits) (s : State) (h : Headers) : Nat :=
  let ua := match h.retryAfter with
    | some a => s.now + a
    | none => 0
  let uz := if refused h.status && h.remaining == some 0 then h.reset.getD 0 else 0
  let ub := if refused h.status && h.retryAfter.isNone && !(h.remaining == some 0 && h.reset.isSome) then
    s.now + backoff L s.fails else 0
  max ua (max uz ub)

/-- The remaining count and reset kept after a response: a response of the REST `core` bucket that carries both
replaces them, except that within the same reset window the remaining count never rises (the smaller one is kept);
any other response (another bucket such as `graphql`, no `x-ratelimit-resource`, or a missing field) keeps them.
-/
def bucket (s : State) (h : Headers) : Option Nat × Option Nat :=
  if h.resource = some "core" then
    match h.remaining, h.reset with
    | some r, some T =>
      if s.reset = some T then (some (match s.remaining with | some r0 => min r r0 | none => r), some T)
      else (some r, some T)
    | _, _ => (s.remaining, s.reset)
  else (s.remaining, s.reset)

#guard bucket { init 0 with remaining := some 4841, reset := some 900 }
  { remaining := some 4913, reset := some 900, resource := some "core" } = (some 4841, some 900)
#guard bucket { init 0 with remaining := some 4841, reset := some 900 }
  { remaining := some 4990, reset := some 4500, resource := some "core" } = (some 4990, some 4500)
#guard bucket { init 0 with remaining := some 4841, reset := some 900 }
  { remaining := some 4999, reset := some 4500, resource := some "graphql" } = (some 4841, some 900)
#guard bucket (init 0) { remaining := some 4999, reset := some 4500 } = (none, none)
#guard bucket (init 0) { remaining := some 4999, resource := some "core" } = (none, none)

/-- Fold a response into the state: book a correction when the call took more responses than it was charged;
take the remaining count and reset from `bucket`; keep the etag when present; never lower `retryUntil`; count
refusals in a row.
-/
def observe (L : Limits) (s : State) (h : Headers) (actual : Nat) : State :=
  let p := s.pending.getD (.oneoff, 0)
  let ledger := if p.2 < actual then s.ledger ++ [⟨s.now, actual - p.2, p.1, false⟩] else s.ledger
  let fails := if refused h.status then s.fails + 1
    else if 200 ≤ h.status ∧ h.status < 400 then 0 else s.fails
  { s with ledger, pending := none,
           remaining := (bucket s h).1, reset := (bucket s h).2, etag := h.etag <|> s.etag,
           retryUntil := max s.retryUntil (retryFrom L s h), fails }

/-- The first id of the branch watches: a waiter on a branch (no run id yet) registers a sentinel
`sentinelBase + h`, with `h` a 32-bit hash of branch, workflow and commit.
-/
def sentinelBase : Nat := 10 ^ 15

/-- The number of sentinel ids. -/
def sentinelSpan : Nat := 2 ^ 32

/-- Is the id a branch watch's sentinel? -/
def isSentinel (r : Nat) : Bool := decide (sentinelBase ≤ r ∧ r < sentinelBase + sentinelSpan)

/-- Is the id a GitHub run id: positive and below `maxRun`? -/
def validRunId (L : Limits) (r : Nat) : Bool := decide (0 < r ∧ r < L.maxRun)

/-- May a waiter register this id: a GitHub run id or a branch sentinel? -/
def validWatch (L : Limits) (r : Nat) : Bool := validRunId L r || isSentinel r

#guard validWatch defaults 25000000000 && validWatch defaults 1000000000838323
#guard !validWatch defaults 0 && !validWatch defaults 5000000000000000 && !validWatch defaults (10 ^ 13)
#guard !validRunId defaults 1000000000838323

/-- Is a list full, i.e. cut at the page limit? `count` rows came back from `pagesRead` pages of 100 rows. -/
def isFull (count pagesRead : Nat) : Bool := decide (max 1 pagesRead * 100 ≤ count)

/-- Does a list cover the creation time of a watch? A list that is not full holds every run created since the
oldest watch (`since`, the `createdSince` of the tick); a full list (cut at the page limit) holds only the runs
created after its oldest row.
-/
def covers (rows : List (Nat × Nat)) (full : Bool) (since : Nat) (w : Watch) : Bool :=
  decide (since ≤ w.createdAt) &&
    (!full || (match (rows.map (·.2)).min? with | some f => decide (f < w.createdAt) | none => false))

/-- What one tick's list says of one watch, first match wins: a branch sentinel is not a run and stays; a run in
the list stays with its misses cleared; a run created before the list's window (`createdAt < since`, registered
after the tick began) is not judged and stays until the next tick; a run the list cannot cover is dropped
(`uncovered`); a covered run that is missing stays for `missMax - 1` ticks and is then dropped (`unseen`).
-/
def judge (L : Limits) (rows : List (Nat × Nat)) (full : Bool) (since : Nat) (w : Watch) : Drop ⊕ Watch :=
  if isSentinel w.runId then .inr w
  else if rows.any (·.1 == w.runId) then .inr { w with misses := 0 }
  else if w.createdAt < since then .inr w
  else if !covers rows full since w then .inl .uncovered
  else if L.missMax ≤ w.misses + 1 then .inl .unseen
  else .inr { w with misses := w.misses + 1 }

/-- Apply one tick's list (rows `(runId, createdAt)`; `full` when it hit the page limit; `since` the window start the
tick asked for) to every watch.
-/
def listed (L : Limits) (s : State) (rows : List (Nat × Nat)) (full : Bool) (since : Nat) : State :=
  { s with
    watched := s.watched.filterMap fun w => match judge L rows full since w with | .inr w' => some w' | .inl _ => none,
    incidents := s.incidents ++ s.watched.filterMap fun w =>
      match judge L rows full since w with | .inl d => some ⟨w.runId, s.now, d⟩ | .inr _ => none }

/-- What the glue read of one waiter marker: the run it waits on, whether `kill(pid, 0)` found the process (a process
of another user, `EPERM`, counts as found), the process start time the marker recorded when the waiter began, and the
start time of that pid now. A start time is an opaque token (the output of `ps -o lstart= -p <pid>`), compared only for
equality; `none` is a token that was not recorded or could not be read.
-/
structure Marker where
  runId : Nat
  killOk : Bool
  recorded : Option String := none
  now : Option String := none
deriving Repr, DecidableEq

/-- Is the waiter behind a marker alive? The process exists and, when both start times are known, it is the process
that wrote the marker (a reused pid has another start time). A marker written without a token (older code) is alive
when the process exists; accepted limit: a reused pid is then taken for the waiter. A marker with a token whose pid
`ps` cannot see now is dead. Two processes with one pid started within the token's resolution (1 s) are not told apart.
-/
def Marker.alive (m : Marker) : Bool :=
  m.killOk && (match m.recorded, m.now with | some a, some b => a == b | some _, none => false | none, _ => true)

/-- The run ids that have a live waiter.
-/
def aliveIds (ms : List Marker) : List Nat := (ms.filter Marker.alive).map (·.runId)

/-- Drop every watch with no live waiter, with an `orphan` incident; keep the others unchanged. The rule does not look
at the kind of the id: a real run nobody waits on has no reader either.
-/
def sweep (s : State) (alive : List Nat) : State :=
  { s with
    watched := s.watched.filter fun w => alive.contains w.runId,
    incidents := s.incidents ++ s.watched.filterMap fun w =>
      if alive.contains w.runId then none else some ⟨w.runId, s.now, .orphan⟩ }

/-- The events that change the state without a call: the clock, a waiter registering or leaving a run, the pages a
tick needs, a response, a manual resume after the poller stopped, one tick's list, and
the acknowledgement of logged incidents, and the sweep of watches without a live waiter.
-/
inductive Event where
  | clock (t : Nat)
  | register (runId createdAt : Nat)
  | unregister (runId : Nat)
  | pages (n : Nat)
  | response (h : Headers) (actual : Nat)
  | resume
  | listed (rows : List (Nat × Nat)) (count pagesRead since : Nat)
  | ack (n : Nat)
  | sweep (alive : List Nat)
deriving Repr

/-- Apply an event. The clock never goes back (`now := max(now, t)`) and drops ledger entries no window can see
again; an id that is neither a GitHub run id nor a branch sentinel is refused (the state stays), and a second waiter
on a watched run changes nothing.
-/
def step (L : Limits) (s : State) : Event → State
  | .clock t =>
    let n := max s.now t
    { s with now := n, ledger := s.ledger.filter fun e => decide (n < e.time + max L.W L.W1) }
  | .register r c =>
    if !validWatch L r || s.watched.any (·.runId == r) then s else { s with watched := s.watched ++ [{ runId := r, createdAt := c }] }
  | .unregister r => { s with watched := s.watched.filter (·.runId != r) }
  | .pages n => { s with pages := max 1 n }
  | .response h a => observe L s h a
  | .resume => { s with fails := 0 }
  | .listed rows count pagesRead since => listed L s rows (isFull count pagesRead) since
  | .ack n => { s with incidents := s.incidents.drop n }
  | .sweep alive => sweep s alive

/-! ## Examples -/

/-- `d` is an issue. -/
private def isIssue : Decision → Bool | .issue .. => true | _ => false
/-- The wait time and reason of `d`, if it waits. -/
private def waitOf : Decision → Option (Nat × Reason) | .wait t r => some (t, r) | _ => none
/-- The stop reason of `d`, if it stops. -/
private def stopOf : Decision → Option Reason | .stop r => some r | _ => none

-- a fresh state: a one-off goes; nothing watched, so the poller is idle
#guard isIssue (reserve defaults (init 100) 3)
#guard stopOf (next defaults (init 100)) = some .idle
-- one watched run: the first tick goes, and the next waits 10 s
#guard isIssue (next defaults (step defaults (init 100) (.register 7 90)))
#guard (match next defaults (step defaults (init 100) (.register 7 90)) with
  | .issue _ _ s' => waitOf (next defaults s') = some (110, .interval) | _ => false)
-- retry-after 60 at t = 100 blocks until 160
#guard waitOf (reserve defaults (observe defaults (init 100) { status := 403, retryAfter := some 60 } 1) 1) =
  some (160, .retryAfter)
-- remaining 0 with the reset at 900: the floor blocks until then
#guard waitOf (reserve defaults (observe defaults (init 100) { status := 403, remaining := some 0, reset := some 900 } 1) 1) =
  some (900, .retryAfter)
#guard waitOf (reserve defaults (observe defaults (init 100)
  { status := 200, remaining := some 500, reset := some 900, resource := some "core" } 1) 1) = some (900, .floor)
-- the same headers of another bucket leave the remaining count alone
#guard isIssue (reserve defaults (observe defaults (init 100)
  { status := 200, remaining := some 500, reset := some 900, resource := some "graphql" } 1) 1)
-- a bare 429 backs off 60 s; six in a row stop the poller
#guard waitOf (reserve defaults (observe defaults (init 100) { status := 429 } 1) 1) = some (160, .retryAfter)
#guard stopOf (reserve defaults { init 100 with fails := 6 } 1) = some .failures
-- a one-off larger than its minute share can never go
#guard stopOf (reserve defaults (init 100) 41) = some .tooBig
-- the minute share: 40 one-off requests go, the 41st waits until the first leaves the window
#guard waitOf (reserve defaults { init 100 with ledger := [⟨70, 40, .oneoff, true⟩] } 1) = some (130, .minute)
-- the hour share: 1200 one-off requests go, the next waits until the first leaves the window
#guard waitOf (reserve defaults { init 3000 with
  ledger := ([⟨100, 30, .oneoff, true⟩] ++ (List.range 39).map (fun i => ⟨200 + 60 * i, 30, .oneoff, true⟩)) } 1) =
  some (3700, .hour)
-- an overrun is booked as a correction
#guard (observe defaults { init 5 with pending := some (.tick, 2) } { status := 200 } 3).ledger = [⟨5, 1, .tick, false⟩]
#guard (observe defaults { init 5 with pending := some (.tick, 2) } { status := 200 } 2).ledger = []
-- registering the same run twice is one entry
#guard (step defaults (step defaults (init 0) (.register 7 0)) (.register 7 5)).watched = [⟨7, 0, none, 0⟩]
#guard since (step defaults (step defaults (init 0) (.register 7 50)) (.register 8 20)) = some 20

/-! ## (e) The clock -/

/-- The clock never goes back: no event decreases `now`. -/
theorem clock_monotone (L : Limits) (s : State) (e : Event) : (step L s e).now ≥ s.now := by
  cases e with
  | clock t => simp only [step]; omega
  | register r c => simp only [step]; split <;> simp
  | response h a => simp [step, observe]
  | _ => simp [step, listed, sweep]

/-- An issued charge keeps the clock, appends exactly the charge, and changes no guard field. -/
theorem charge_issue (L : Limits) (s : State) (k : Kind) (c : Nat) (k' : Kind) (c' : Nat) (s' : State)
    (h : charge L s k c = .issue k' c' s') :
    k' = k ∧ c' = c ∧ s'.ledger = s.ledger ++ [⟨s.now, c, k, true⟩] ∧ s'.now = s.now ∧
      s'.retryUntil = s.retryUntil := by
  unfold charge at h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h
  cases h
  exact ⟨rfl, rfl, rfl, rfl, rfl⟩


/-- An issued charge passed every guard: fewer than `maxFails` failures, `now` at or after `retryUntil`, headroom,
and room for `c` in both windows of its kind (corrections included).
-/
theorem charge_issue_guards (L : Limits) (s : State) (k : Kind) (c : Nat) (k' : Kind) (c' : Nat) (s' : State)
    (h : charge L s k c = .issue k' c' s') :
    s.fails < L.maxFails ∧ s.retryUntil ≤ s.now ∧ headroom L s = true ∧
      wsum L.W s.now (ofKind k) s.ledger + c ≤ share L k ∧ wsum L.W1 s.now (ofKind k) s.ledger + c ≤ share1 L k := by
  unfold charge at h
  split at h
  · cases h
  rename_i h1
  split at h
  · cases h
  split at h
  · cases h
  rename_i h3
  split at h
  · cases h
  rename_i h4
  split at h
  · cases h
  rename_i h5
  split at h
  · cases h
  rename_i h6
  refine ⟨by omega, by omega, ?_, by omega, by omega⟩
  cases hh : headroom L s <;> simp_all

/-- A wait is never in the past: every `wait` that `charge` returns is strictly after `now`, and it is never the
interval wait.
-/
theorem charge_wait (L : Limits) (s : State) (k : Kind) (c u : Nat) (r : Reason)
    (h : charge L s k c = .wait u r) : s.now < u ∧ r ≠ .interval := by
  unfold charge at h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h; constructor <;> first | omega | simp
  split at h
  · cases h
    refine ⟨?_, by simp⟩
    unfold floorUntil
    split
    · split <;> omega
    · omega
  have hfree : ∀ (W : Nat) (sel : Entry → Bool) (cap : Nat), s.now < freeAt W s.now sel cap c s.ledger := by
    intro W sel cap
    unfold freeAt
    split
    · rename_i e he
      have := List.find?_some he
      simp at this
      omega
    · omega
  split at h
  · cases h; exact ⟨hfree _ _ _, by simp⟩
  split at h
  · cases h; exact ⟨hfree _ _ _, by simp⟩
  · cases h

/-- `charge` never stops for a reason other than failures or a cost no share can hold. -/
theorem charge_stop (L : Limits) (s : State) (k : Kind) (c : Nat) (r : Reason)
    (h : charge L s k c = .stop r) : (r = .failures ∧ L.maxFails ≤ s.fails) ∨ r = .tooBig := by
  unfold charge at h
  split at h
  · cases h; left; constructor <;> first | rfl | assumption
  split at h
  · cases h; right; rfl
  repeat (split at h; · cases h)
  cases h

/-! ## (b) No call under a guard -/

/-- `headroom` spelled out. -/
theorem headroom_iff (L : Limits) (s : State) :
    headroom L s = true ↔ s.remaining = none ∨
      ∃ r, s.remaining = some r ∧ (L.F < r ∨ ∃ T, s.reset = some T ∧ T ≤ s.now) := by
  unfold headroom
  cases hr : s.remaining <;> cases ht : s.reset <;> simp

/-- (b) A one-off call is issued only when `now` is at or after `retryUntil` and the headers leave room: remaining
unknown, above the floor `F`, or the reset already passed.
-/
theorem no_issue_when_exhausted (L : Limits) (s : State) (c : Nat) (k : Kind) (c' : Nat) (s' : State)
    (h : reserve L s c = .issue k c' s') :
    s.retryUntil ≤ s.now ∧ (s.remaining = none ∨
      ∃ r, s.remaining = some r ∧ (L.F < r ∨ ∃ T, s.reset = some T ∧ T ≤ s.now)) := by
  have g := charge_issue_guards L s _ _ _ _ _ h
  exact ⟨g.2.1, (headroom_iff L s).1 g.2.2.1⟩

/-- The decisions of `next`: an issue is `tickNow`'s charge with the watched runs covered. -/
theorem next_issue (L : Limits) (s : State) (k : Kind) (c : Nat) (s' : State) (h : next L s = .issue k c s') :
    ∃ s'', charge L s .tick (tickCost L s) = .issue k c s'' ∧ s' = cover s'' := by
  have ht : tickNow L s = .issue k c s' → ∃ s'', charge L s .tick (tickCost L s) = .issue k c s'' ∧ s' = cover s'' := by
    intro ht
    unfold tickNow at ht
    split at ht
    · rename_i k0 c0 s0 hc
      cases ht
      exact ⟨s0, hc, rfl⟩
    · rename_i d hd
      exact (hd k c s' ht).elim
  unfold next at h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · split at h
    · cases h
    · exact ht h
  · exact ht h

/-- (b) The poller ticks only under the same guards as `reserve`. -/
theorem next_no_issue_when_exhausted (L : Limits) (s : State) (k : Kind) (c : Nat) (s' : State)
    (h : next L s = .issue k c s') :
    s.retryUntil ≤ s.now ∧ (s.remaining = none ∨
      ∃ r, s.remaining = some r ∧ (L.F < r ∨ ∃ T, s.reset = some T ∧ T ≤ s.now)) := by
  obtain ⟨s'', hc, _⟩ := next_issue L s k c s' h
  have g := charge_issue_guards L s _ _ _ _ _ hc
  exact ⟨g.2.1, (headroom_iff L s).1 g.2.2.1⟩

/-! ## Reachable states -/

/-- The states reachable from `s_0`: events, issued charges of any kind and cost, and issued ticks with their cover
(a superset of what `reserve` and `next` do, so every theorem over it holds for them).
-/
inductive Reach (L : Limits) (s0 : State) : State → Prop where
  | refl : Reach L s0 s0
  | step {s : State} (e : Event) : Reach L s0 s → Reach L s0 (step L s e)
  | charge {s s' : State} {k : Kind} {c : Nat} : Reach L s0 s → charge L s k c = .issue k c s' → Reach L s0 s'
  | cover {s s' : State} {c : Nat} : Reach L s0 s → charge L s .tick c = .issue .tick c s' → Reach L s0 (cover s')

/-- An issued `reserve` stays reachable. -/
theorem Reach.reserve {L : Limits} {s0 s : State} {c : Nat} {k : Kind} {c' : Nat} {s' : State}
    (hr : Reach L s0 s) (h : Fw.Ci.Budget.reserve L s c = .issue k c' s') : Reach L s0 s' := by
  have hi := charge_issue L s _ _ _ _ _ h
  obtain ⟨rfl, rfl, -⟩ := hi
  exact .charge hr h

/-- An issued `next` stays reachable. -/
theorem Reach.next {L : Limits} {s0 s : State} {k : Kind} {c : Nat} {s' : State}
    (hr : Reach L s0 s) (h : Fw.Ci.Budget.next L s = .issue k c s') : Reach L s0 s' := by
  obtain ⟨s'', hc, rfl⟩ := next_issue L s k c s' h
  have hi := charge_issue L s _ _ _ _ _ hc
  obtain ⟨rfl, rfl, -⟩ := hi
  exact .cover hr hc

/-! ## (a) The window bound -/

/-- The invariant: every ledger entry is at or before `now`, and for each kind and every time `t` the charges in
both windows stay within the shares.
-/
def Inv (L : Limits) (s : State) : Prop :=
  (∀ e ∈ s.ledger, e.time ≤ s.now) ∧
    ∀ k t, wsum L.W t (chargedOf k) s.ledger ≤ share L k ∧ wsum L.W1 t (chargedOf k) s.ledger ≤ share1 L k

/-- Appending an entry the selector skips leaves the window sum unchanged. -/
theorem wsum_append_skip (W t : Nat) (sel : Entry → Bool) (l : List Entry) (e : Entry) (h : sel e = false) :
    wsum W t sel (l ++ [e]) = wsum W t sel l := by
  rw [wsum_append, wsum_single]; simp [h]

/-- Appending a charge `(n, c, k)` at the latest time `n` keeps the charges of kind `k` within the cap, when the
window ending at `n` had room for `c` (corrections included).
-/
theorem charged_append_ok (W cap : Nat) (k : Kind) (l : List Entry) (n c : Nat)
    (hall : ∀ e ∈ l, e.time ≤ n) (hok : ∀ t, wsum W t (chargedOf k) l ≤ cap)
    (hadm : wsum W n (ofKind k) l + c ≤ cap) (t : Nat) :
    wsum W t (chargedOf k) (l ++ [⟨n, c, k, true⟩]) ≤ cap := by
  rw [wsum_append, wsum_single]
  simp only [chargedOf, decide_true, Bool.and_self, Bool.true_and]
  split
  · rename_i hw
    simp only [inWin, Bool.and_eq_true, decide_eq_true_eq] at hw
    have h1 := wsum_mono_sel W t (chargedOf k) (ofKind k) l (fun e _ he => by
      simp only [chargedOf, ofKind, Bool.and_eq_true] at he ⊢; exact he.1)
    have h2 := wsum_later W t n (ofKind k) l hall hw.1
    omega
  · have := hok t; omega

/-- The invariant holds for the empty state at any time. -/
theorem inv_init (L : Limits) (t : Nat) : Inv L (init t) := by
  refine ⟨by simp [init], fun k t => ?_⟩
  simp [init, wsum]

/-- Every event keeps the invariant. -/
theorem inv_step (L : Limits) (s : State) (e : Event) (h : Inv L s) : Inv L (step L s e) := by
  obtain ⟨hall, hok⟩ := h
  cases e with
  | clock t =>
    refine ⟨fun e he => ?_, fun k t' => ?_⟩
    · simp only [step, List.mem_filter] at he ⊢
      have := hall e he.1; omega
    · simp only [step]
      have := wsum_filter_le L.W t' (chargedOf k) (fun e => decide (max s.now t < e.time + max L.W L.W1)) s.ledger
      have := wsum_filter_le L.W1 t' (chargedOf k) (fun e => decide (max s.now t < e.time + max L.W L.W1)) s.ledger
      have := hok k t'
      omega
  | register r c =>
    simp only [step]; split
    · exact ⟨hall, hok⟩
    · exact ⟨hall, hok⟩
  | unregister r => exact ⟨hall, hok⟩
  | pages n => exact ⟨hall, hok⟩
  | resume => exact ⟨hall, hok⟩
  | listed rows count pagesRead since => exact ⟨hall, hok⟩
  | ack n => exact ⟨hall, hok⟩
  | sweep alive => exact ⟨hall, hok⟩
  | response hd a =>
    simp only [step, observe]
    refine ⟨fun e he => ?_, fun k t' => ?_⟩
    · split at he
      · simp only [List.mem_append, List.mem_singleton] at he
        rcases he with he | he
        · exact hall e he
        · subst he; simp
      · exact hall e he
    · split
      · rw [wsum_append_skip _ _ _ _ _ (by simp [chargedOf]), wsum_append_skip _ _ _ _ _ (by simp [chargedOf])]
        exact hok k t'
      · exact hok k t'

/-- An issued charge keeps the invariant. -/
theorem inv_charge (L : Limits) (s : State) (k : Kind) (c : Nat) (s' : State) (h : Inv L s)
    (hc : charge L s k c = .issue k c s') : Inv L s' := by
  obtain ⟨hall, hok⟩ := h
  obtain ⟨-, -, hl, hn, -⟩ := charge_issue L s k c k c s' hc
  obtain ⟨-, -, -, hw, hw1⟩ := charge_issue_guards L s k c k c s' hc
  refine ⟨fun e he => ?_, fun k' t => ?_⟩
  · rw [hl, List.mem_append, List.mem_singleton] at he
    rw [hn]
    rcases he with he | he
    · exact hall e he
    · subst he; simp
  · rw [hl]
    by_cases hk : k' = k
    · subst hk
      exact ⟨charged_append_ok _ _ _ _ _ _ hall (fun t => (hok k' t).1) hw t,
        charged_append_ok _ _ _ _ _ _ hall (fun t => (hok k' t).2) hw1 t⟩
    · have hs : chargedOf k' ⟨s.now, c, k, true⟩ = false := by
        simp only [chargedOf, Bool.and_true, decide_eq_false_iff_not]; exact fun h => hk h.symm
      rw [wsum_append_skip _ _ _ _ _ hs, wsum_append_skip _ _ _ _ _ hs]
      exact hok k' t

/-- The invariant holds in every state reachable from a state where it holds. -/
theorem inv_reach (L : Limits) (s0 s : State) (h0 : Inv L s0) (hr : Reach L s0 s) : Inv L s := by
  induction hr with
  | refl => exact h0
  | step e _ ih => exact inv_step L _ e ih
  | charge _ hc ih => exact inv_charge L _ _ _ _ ih hc
  | cover _ hc ih =>
    have := inv_charge L _ _ _ _ ih hc
    exact this

/-- (a) In every state reachable from an empty state, for each kind and every time `t`, the charged requests in the
window `(t - W, t]` stay within the hourly share and those in `(t - W_1, t]` within the per-minute share. No
hypothesis mentions the watched runs, so this holds for every number `N` of waiters.
-/
theorem window_bound (L : Limits) (t0 : Nat) (s : State) (hr : Reach L (init t0) s) (k : Kind) (t : Nat) :
    wsum L.W t (chargedOf k) s.ledger ≤ share L k ∧ wsum L.W1 t (chargedOf k) s.ledger ≤ share1 L k :=
  (inv_reach L _ s (inv_init L t0) hr).2 k t

/-- (a) The total: with `R ≤ B` and `R_1 ≤ B_1`, all charged requests in any 3600 s window stay within `B` and
those in any 60 s window within `B_1`.
-/
theorem window_total (L : Limits) (t0 : Nat) (s : State) (hR : L.R ≤ L.B) (hR1 : L.R1 ≤ L.B1)
    (hr : Reach L (init t0) s) (t : Nat) :
    wsum L.W t isCharge s.ledger ≤ L.B ∧ wsum L.W1 t isCharge s.ledger ≤ L.B1 := by
  have a := window_bound L t0 s hr .tick t
  have b := window_bound L t0 s hr .oneoff t
  simp only [share, share1] at a b
  rw [wsum_charges, wsum_charges]
  omega

/-- (a) Overruns: in every reachable state the requests of a kind in a window (charges and corrections) stay within
the share plus the corrections in that window, and a call is issued only when the whole window, corrections
included, has room for it.
-/
theorem overrun_absorbed (L : Limits) (t0 : Nat) (s : State) (hr : Reach L (init t0) s) (k : Kind) (t : Nat) :
    (wsum L.W t (ofKind k) s.ledger ≤ share L k + wsum L.W t (corrOf k) s.ledger ∧
      wsum L.W1 t (ofKind k) s.ledger ≤ share1 L k + wsum L.W1 t (corrOf k) s.ledger) ∧
    ∀ (s1 : State) (c : Nat) (s' : State), charge L s1 k c = .issue k c s' →
      wsum L.W s1.now (ofKind k) s1.ledger + c ≤ share L k := by
  have a := window_bound L t0 s hr k t
  rw [wsum_split, wsum_split]
  refine ⟨⟨by omega, by omega⟩, fun s1 c s' hc => (charge_issue_guards L s1 k c k c s' hc).2.2.2.1⟩

/-- (a′) Waiters cost nothing: registering or unregistering a run leaves the ledger and the clock as they are. -/
theorem register_free (L : Limits) (s : State) (r c : Nat) :
    (step L s (.register r c)).ledger = s.ledger ∧ (step L s (.unregister r)).ledger = s.ledger ∧
      (step L s (.register r c)).now = s.now := by
  simp only [step]; split <;> simp

/-- (a′) Another waiter on a run already watched changes nothing: `N` waiters on one run are one entry. -/
theorem register_dup (L : Limits) (s : State) (r c : Nat) (h : ∃ w ∈ s.watched, w.runId = r) :
    step L s (.register r c) = s := by
  obtain ⟨w, hw, hr⟩ := h
  have : s.watched.any (·.runId == r) = true := List.any_eq_true.2 ⟨w, hw, by simp [hr]⟩
  simp [step, this]

/-- (a″) A tick's cost and interval do not depend on the watched runs: one list call covers them all. -/
theorem tick_cost_indep_N (L : Limits) (s : State) (ws : List Watch) :
    tickCost L { s with watched := ws } = tickCost L s ∧ interval L { s with watched := ws } = interval L s := by
  constructor <;> rfl

/-! ## (b′, b″) Guards persist, and the backoff -/

/-- No event or issued charge lowers `retryUntil`. -/
theorem retry_mono (L : Limits) (s0 s : State) (hr : Reach L s0 s) : s0.retryUntil ≤ s.retryUntil := by
  induction hr with
  | refl => exact Nat.le_refl _
  | step e _ ih =>
    rename_i s1 _
    have : s1.retryUntil ≤ (step L s1 e).retryUntil := by
      cases e with
      | clock t => simp [step]
      | register r c => simp only [step]; split <;> simp
      | response hd a => simp only [step, observe]; exact Nat.le_max_left _ _
      | _ => simp [step, listed, sweep]
    omega
  | charge _ hc ih =>
    have := (charge_issue L _ _ _ _ _ _ hc).2.2.2.2; omega
  | cover _ hc ih =>
    have := (charge_issue L _ _ _ _ _ _ hc).2.2.2.2; simp only [cover]; omega

/-- A response pushes `retryUntil` to at least `now` plus its `retry-after`, and a refusal with remaining 0 to at
least its reset.
-/
theorem observe_retry (L : Limits) (s : State) (h : Headers) (a : Nat) :
    (∀ a', h.retryAfter = some a' → s.now + a' ≤ (observe L s h a).retryUntil) ∧
    (∀ T, refused h.status = true → h.remaining = some 0 → h.reset = some T →
      T ≤ (observe L s h a).retryUntil) := by
  constructor
  · intro a' ha
    simp only [observe, retryFrom, ha]
    omega
  · intro T hs hr ht
    simp only [observe, retryFrom, hr, ht, hs]
    simp
    omega

/-- (b′) After a response with `retry-after` `a'` at time `t_0`, or a refusal with remaining 0 and reset `T`, no
call is issued along any later trace before `t_0 + a'`, or before `T`.
-/
theorem guard_persists (L : Limits) (s : State) (h : Headers) (a : Nat) (s2 : State)
    (hr : Reach L (step L s (.response h a)) s2) (k : Kind) (c : Nat) (s' : State)
    (hc : charge L s2 k c = .issue k c s') :
    (∀ a', h.retryAfter = some a' → s.now + a' ≤ s2.now) ∧
    (∀ T, refused h.status = true → h.remaining = some 0 → h.reset = some T → T ≤ s2.now) := by
  have hm := retry_mono L _ _ hr
  have hg := (charge_issue_guards L s2 k c k c s' hc).2.1
  have ho := observe_retry L s h a
  simp only [step] at hm
  exact ⟨fun a' ha => by have := ho.1 a' ha; omega,
    fun T h1 h2 h3 => by have := ho.2 T h1 h2 h3; omega⟩

/-- (b″) The backoff is at least `b_0` (when `b_0 ≤ b_max`). -/
theorem backoff_ge (L : Limits) (k : Nat) (h : L.back0 ≤ L.backMax) : L.back0 ≤ backoff L k := by
  unfold backoff
  have : L.back0 ≤ L.back0 * 2 ^ k := Nat.le_mul_of_pos_right _ (Nat.two_pow_pos k)
  omega

/-- (b″) The backoff never shrinks as failures accumulate. -/
theorem backoff_mono (L : Limits) (k k' : Nat) (h : k ≤ k') : backoff L k ≤ backoff L k' := by
  unfold backoff
  have : L.back0 * 2 ^ k ≤ L.back0 * 2 ^ k' := Nat.mul_le_mul_left _ (Nat.pow_le_pow_right (by omega) h)
  omega

/-- (b″) After `maxFails` failures in a row both decisions stop. -/
theorem stop_after_fails (L : Limits) (s : State) (c : Nat) (h : L.maxFails ≤ s.fails) :
    reserve L s c = .stop .failures ∧ next L s = .stop .failures := by
  simp [reserve, charge, next, h]

/-! ## (c) Liveness -/

/-- (c) While the guards allow, the shares have room and the interval has passed, `next` ticks, and the tick covers
every watched run at `now`.
-/
theorem poll_live (L : Limits) (s : State) (hf : s.fails < L.maxFails) (hw : s.watched ≠ [])
    (hint : ∀ t0, s.lastTick = some t0 → t0 + interval L s ≤ s.now)
    (hg : s.retryUntil ≤ s.now) (hh : headroom L s = true)
    (hc : tickCost L s ≤ share L .tick) (hc1 : tickCost L s ≤ share1 L .tick)
    (ha : wsum L.W s.now (ofKind .tick) s.ledger + tickCost L s ≤ share L .tick)
    (ha1 : wsum L.W1 s.now (ofKind .tick) s.ledger + tickCost L s ≤ share1 L .tick) :
    ∃ s', next L s = .issue .tick (tickCost L s) s' ∧ s'.lastTick = some s.now ∧
      ∀ w ∈ s'.watched, w.lastCovered = some s.now := by
  have hch : charge L s .tick (tickCost L s) = .issue .tick (tickCost L s)
      { s with ledger := s.ledger ++ [⟨s.now, tickCost L s, .tick, true⟩], pending := some (.tick, tickCost L s) } := by
    have n1 : ¬ L.maxFails ≤ s.fails := by omega
    have n2 : ¬ (share L .tick < tickCost L s ∨ share1 L .tick < tickCost L s) := by omega
    have n3 : ¬ s.now < s.retryUntil := by omega
    have n4 : ¬ headroom L s = false := by simp [hh]
    have n5 : ¬ share L .tick < wsum L.W s.now (ofKind .tick) s.ledger + tickCost L s := by omega
    have n6 : ¬ share1 L .tick < wsum L.W1 s.now (ofKind .tick) s.ledger + tickCost L s := by omega
    unfold charge
    simp only [n1, n2, n3, hh, n5, n6, Bool.true_eq_false, ↓reduceIte]
  have htn : tickNow L s = .issue .tick (tickCost L s) (cover
      { s with ledger := s.ledger ++ [⟨s.now, tickCost L s, .tick, true⟩], pending := some (.tick, tickCost L s) }) := by
    unfold tickNow; rw [hch]
  refine ⟨?s', ?h1, ?h2, fun w hw' => ?h3⟩
  case h1 =>
    have n1 : ¬ L.maxFails ≤ s.fails := by omega
    unfold next
    simp only [n1, hw, ↓reduceIte]
    split
    · rename_i t0 ht0
      have n7 : ¬ s.now < t0 + interval L s := by have := hint t0 ht0; omega
      simp only [n7, ↓reduceIte]
      exact htn
    · exact htn
  case h3 =>
    simp only [cover, List.mem_map] at hw'
    obtain ⟨w0, -, rfl⟩ := hw'
    rfl
  all_goals rfl

/-- (c) The only other way `next` waits on the interval: it waits until the last tick plus `P`, which is after `now`
and at most `P` after `now` when the last tick is not in the future.
-/
theorem next_wait_interval (L : Limits) (s : State) (u : Nat) (h : next L s = .wait u .interval) :
    ∃ t0, s.lastTick = some t0 ∧ u = t0 + interval L s ∧ s.now < u ∧ (t0 ≤ s.now → u ≤ s.now + interval L s) := by
  have ht : ∀ u', tickNow L s = .wait u' .interval → False := by
    intro u' ht
    unfold tickNow at ht
    split at ht
    · cases ht
    · exact (charge_wait L s .tick _ u' .interval ht).2 rfl
  unfold next at h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · rename_i t0 ht0
    split at h
    · cases h
      exact ⟨t0, ht0, rfl, by omega, fun _ => by omega⟩
    · exact (ht u h).elim
  · exact (ht u h).elim

/-- No wait is in the past: every `wait` from `reserve` or `next` is strictly after `now`. -/
theorem wait_future (L : Limits) (s : State) (c u : Nat) (r : Reason) :
    (reserve L s c = .wait u r → s.now < u) ∧ (next L s = .wait u r → s.now < u) := by
  have ht : tickNow L s = .wait u r → s.now < u := by
    intro ht
    unfold tickNow at ht
    split at ht
    · cases ht
    · exact (charge_wait L s .tick _ u r ht).1
  refine ⟨fun h => (charge_wait L s _ _ u r h).1, fun h => ?_⟩
  unfold next at h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · split at h
    · cases h; omega
    · exact ht h
  · exact ht h

/-! ## (d) The interval formula, and the old scheme -/

/-- Times spaced at least `P` apart, in order. -/
def spaced (P : Nat) : List Nat → Bool
  | x :: y :: r => decide (x + P ≤ y) && spaced P (y :: r)
  | _ => true

/-- The ceiling division times the divisor reaches the dividend. -/
theorem le_ceilDiv_mul (a b : Nat) (hb : 0 < b) : a ≤ ceilDiv a b * b := by
  unfold ceilDiv
  have := Nat.lt_mul_div_succ (a + b - 1) hb
  rw [Nat.mul_succ, Nat.mul_comm] at this
  omega

/-- The span of spaced times: `n` steps of at least `P` after the first one. -/
theorem spaced_span (P : Nat) (x : Nat) (r : List Nat) (hi : Nat) (hs : spaced P (x :: r) = true)
    (hle : ∀ z ∈ x :: r, z ≤ hi) : r.length * P + x ≤ hi := by
  induction r generalizing x with
  | nil => simpa using hle x (by simp)
  | cons y r ih =>
    simp only [spaced, Bool.and_eq_true, decide_eq_true_eq] at hs
    have := ih y hs.2 (fun z hz => hle z (List.mem_cons_of_mem _ hz))
    simp only [List.length_cons, Nat.succ_mul]
    omega

/-- At most `⌈ W/P ⌉` times spaced at least `P` apart fit in a window `(t - W, t]`. -/
theorem spaced_count (P W t : Nat) (xs : List Nat) (hP : 0 < P) (hs : spaced P xs = true)
    (hw : ∀ z ∈ xs, inWin W t z = true) : xs.length ≤ ceilDiv W P := by
  cases xs with
  | nil => simp
  | cons x r =>
    have hx := hw x (by simp)
    simp only [inWin, Bool.and_eq_true, decide_eq_true_eq] at hx
    have hspan := spaced_span P x r t hs (fun z hz => by
      have := hw z hz; simp only [inWin, Bool.and_eq_true, decide_eq_true_eq] at this; exact this.1)
    have h1 : r.length * P ≤ W - 1 := by omega
    have h2 : r.length ≤ (W - 1) / P := (Nat.le_div_iff_mul_le hP).2 h1
    have h3 : (W - 1 + P) / P = (W - 1) / P + 1 := Nat.add_div_right _ hP
    simp only [List.length_cons, ceilDiv]
    have : W + P - 1 = W - 1 + P := by omega
    rw [this, h3]
    omega

/-- An interval at least `⌈ W / max(1, ⌊ cap/c ⌋) ⌉` fits `⌈ W/P ⌉` calls of
cost `c` into the cap.
-/
theorem ceilDiv_fit (W cap c P : Nat) (hc0 : 0 < c) (hc : c ≤ cap) (hP : 0 < P)
    (h : ceilDiv W (max 1 (cap / c)) ≤ P) : ceilDiv W P * c ≤ cap := by
  have hq : 1 ≤ cap / c := (Nat.le_div_iff_mul_le hc0).2 (by omega)
  have hm : max 1 (cap / c) = cap / c := by omega
  rw [hm] at h
  have h1 := le_ceilDiv_mul W (cap / c) (by omega)
  have h2 : W ≤ cap / c * P := by
    have := Nat.mul_le_mul_right (cap / c) h
    rw [Nat.mul_comm P] at this
    omega
  have h3 : ceilDiv W P ≤ cap / c := by
    unfold ceilDiv
    have : (W + P - 1) / P < cap / c + 1 := by
      rw [Nat.div_lt_iff_lt_mul hP, Nat.succ_mul]
      omega
    omega
  exact Nat.le_trans (Nat.mul_le_mul_right c h3) (Nat.div_mul_le_self cap c)

/-- (d) The interval formula is sound: for any `P ≥ interval(L, s)` (and `P > 0`), ticks of cost `c` spaced at least `P`
apart fit the hourly tick share in every window `(t - W, t]`, the per-minute tick share in every window
`(t - W_1, t]`, and, with remaining `r` and the reset `T` ahead, the headroom `r ∸ F` in `[now, T)`.
-/
theorem interval_sound (L : Limits) (s : State) (P : Nat) (hP : interval L s ≤ P) (hP0 : 0 < P)
    (hc0 : 0 < tickCost L s) :
    (tickCost L s ≤ share L .tick → ∀ xs t, spaced P xs = true → (∀ z ∈ xs, inWin L.W t z = true) →
      xs.length * tickCost L s ≤ share L .tick) ∧
    (tickCost L s ≤ share1 L .tick → ∀ xs t, spaced P xs = true → (∀ z ∈ xs, inWin L.W1 t z = true) →
      xs.length * tickCost L s ≤ share1 L .tick) ∧
    (∀ r T, s.remaining = some r → s.reset = some T → s.now < T → tickCost L s ≤ r - L.F →
      ∀ xs, spaced P xs = true → (∀ z ∈ xs, s.now ≤ z ∧ z < T) → xs.length * tickCost L s ≤ r - L.F) := by
  unfold interval hourGap minuteGap spread at hP
  refine ⟨fun hc xs t hs hw => ?_, fun hc xs t hs hw => ?_, fun r T hr hT hlt hc xs hs hw => ?_⟩
  · have := spaced_count P L.W t xs hP0 hs hw
    have hfit := ceilDiv_fit L.W (share L .tick) (tickCost L s) P hc0 hc hP0 (by omega)
    exact Nat.le_trans (Nat.mul_le_mul_right _ this) hfit
  · have := spaced_count P L.W1 t xs hP0 hs hw
    have hfit := ceilDiv_fit L.W1 (share1 L .tick) (tickCost L s) P hc0 hc hP0 (by omega)
    exact Nat.le_trans (Nat.mul_le_mul_right _ this) hfit
  · rw [hr, hT] at hP
    simp only [hlt, ite_true] at hP
    have := spaced_count P (T - s.now) (T - 1) xs hP0 hs (fun z hz => by
      have := hw z hz; simp only [inWin, Bool.and_eq_true, decide_eq_true_eq]; omega)
    have hfit := ceilDiv_fit (T - s.now) (r - L.F) (tickCost L s) P hc0 hc hP0 (by omega)
    exact Nat.le_trans (Nat.mul_le_mul_right _ this) hfit

/-- The old scheme's requests per window: `N` agents, each polling on its own at interval `P` with cost `c`. -/
def oldRate (L : Limits) (N c P : Nat) : Nat := N * (c * ceilDiv L.W P)

#guard oldRate defaults 12 2 30 = 2880      -- 12 agents, `gh run view` every 30 s
#guard oldRate defaults 1 4 3 = 4800        -- one `gh run watch` at 3 s with one job
#guard oldRate defaults 12 2 30 + oldRate defaults 1 4 3 > 5000   -- the 10-18 incident
#guard ceilDiv defaults.W defaults.Pmin * defaults.listCost = 720  -- the shared poller at P_min = 10 s, for any N

/-- (d′) The old scheme grows linearly in the number of agents. -/
theorem oldRate_linear (L : Limits) (N c P : Nat) : oldRate L N c P = N * oldRate L 1 c P := by
  simp [oldRate]

/-- (d′) `N` independent pollers of cost `c` stay within `B` only if `P ≥ W c N / B`. -/
theorem per_agent_interval (L : Limits) (N c P : Nat) (hP : 0 < P) (h : oldRate L N c P ≤ L.B) :
    L.W * c * N ≤ L.B * P := by
  unfold oldRate at h
  have h1 := le_ceilDiv_mul L.W P hP
  have h2 : L.W * c * N ≤ ceilDiv L.W P * P * c * N := Nat.mul_le_mul_right _ (Nat.mul_le_mul_right _ h1)
  have h3 : ceilDiv L.W P * P * c * N = N * (c * ceilDiv L.W P) * P := by
    simp only [Nat.mul_comm, Nat.mul_left_comm]
  have h4 : N * (c * ceilDiv L.W P) * P ≤ L.B * P := Nat.mul_le_mul_right _ h
  omega

/-! ## (f) Latency: when a finished run is listed and seen -/

/-- The waiter's re-read period in seconds (`SLICE` in `packages/gh-budget/src/wait.ts`, which a test checks
against `limits.json`).
-/
def slice : Nat := 2

/-- The first read at or after time `y` of a waiter that reads the runs-status file at `r_0, r_0 + q, r_0 + 2q, ...` (and `r_0` itself when `y ≤ r_0` or `q = 0`, since `ceilDiv(a, 0) = 0`). -/
def firstRead (r0 q y : Nat) : Nat := r0 + ceilDiv (y - r0) q * q

#guard firstRead 100 2 105 = 106 && firstRead 100 2 106 = 106 && firstRead 100 2 100 = 100

/-- A waiter that started reading by `y` reads at `y` or less than one period after it. -/
theorem firstRead_bound (r0 q y : Nat) (hq : 0 < q) (hy : r0 ≤ y) :
    y ≤ firstRead r0 q y ∧ firstRead r0 q y < y + q := by
  unfold firstRead
  have h1 := le_ceilDiv_mul (y - r0) q hq
  have h2 : ceilDiv (y - r0) q * q ≤ y - r0 + q - 1 := by
    unfold ceilDiv; exact Nat.div_mul_le_self _ _
  omega

/-- The clock moving forward does not lengthen the interval: the share gaps depend only on the pages, and the spread
gap shrinks as the reset comes closer.
-/
theorem interval_clock (L : Limits) (s : State) (t : Nat) : interval L (step L s (.clock t)) ≤ interval L s := by
  have hsp : spread L (step L s (.clock t)) ≤ spread L s := by
    unfold spread
    have htc : tickCost L (step L s (.clock t)) = tickCost L s := rfl
    simp only [step] at htc ⊢
    rw [htc]
    split
    · rename_i r T _ _
      by_cases hlt : max s.now t < T
      · have hlt' : s.now < T := by omega
        simp only [hlt, hlt', ↓reduceIte]
        unfold ceilDiv
        exact Nat.div_le_div_right (by omega)
      · simp only [hlt, ↓reduceIte]
        exact Nat.zero_le _
    · exact Nat.zero_le _
  have hh : hourGap L (step L s (.clock t)) = hourGap L s := rfl
  have hm : minuteGap L (step L s (.clock t)) = minuteGap L s := rfl
  unfold interval
  rw [hh, hm]
  omega

/-- Headroom stays when the clock moves forward. -/
theorem headroom_clock (L : Limits) (s : State) (t : Nat) (h : headroom L s = true) :
    headroom L (step L s (.clock t)) = true := by
  unfold headroom at h ⊢
  simp only [step]
  rcases hr : s.remaining with _ | r
  · rfl
  · rw [hr] at h
    rcases hT : s.reset with _ | T
    · rw [hT] at h; simpa using h
    · rw [hT] at h
      simp only [Bool.or_eq_true, decide_eq_true_eq] at h ⊢
      rcases h with h | h
      · exact Or.inl h
      · exact Or.inr (decide_eq_true (by omega))

/-- (f) Liveness with latency. Let the last tick be at `t_0` and `x = t_0 + P(L, s)` the next scheduled tick. If the
poller holds the lock and asks on time (`s.now ≤ x`), nothing but the clock happens before `x`, and the
guards have room at `x` (fewer than `m` failures, a run watched, no `retry-after` past `x`, headroom, and room for one
tick in both tick windows ending at `x`), then the poller ticks at `x`: at once when `s.now = x`, else after
waiting for the interval until `x`. The tick covers every watched run, so a run that completed at any `f` with
`t_0 ≤ f ≤ x` is listed at most `P(L, s)` after it completed.
-/
theorem listed_within (L : Limits) (s : State) (t0 : Nat)
    (hf : s.fails < L.maxFails) (hw : s.watched ≠ []) (hlast : s.lastTick = some t0)
    (hon : s.now ≤ t0 + interval L s) (hr : s.retryUntil ≤ t0 + interval L s) (hh : headroom L s = true)
    (ha : wsum L.W (t0 + interval L s) (ofKind .tick) s.ledger + tickCost L s ≤ share L .tick)
    (ha1 : wsum L.W1 (t0 + interval L s) (ofKind .tick) s.ledger + tickCost L s ≤ share1 L .tick) :
    ∃ s', ((s.now = t0 + interval L s ∧ next L s = .issue .tick (tickCost L s) s') ∨
        (next L s = .wait (t0 + interval L s) .interval ∧
          next L (step L s (.clock (t0 + interval L s))) = .issue .tick (tickCost L s) s')) ∧
      s'.lastTick = some (t0 + interval L s) ∧ (∀ w ∈ s'.watched, w.lastCovered = some (t0 + interval L s)) ∧
      ∀ f, t0 ≤ f → f ≤ t0 + interval L s → f ≤ t0 + interval L s ∧ t0 + interval L s ≤ f + interval L s := by
  have hfa : ∀ f, t0 ≤ f → f ≤ t0 + interval L s → f ≤ t0 + interval L s ∧ t0 + interval L s ≤ f + interval L s :=
    fun f h1 h2 => ⟨h2, by omega⟩
  by_cases hx : s.now = t0 + interval L s
  · obtain ⟨s', hn, hl, hc⟩ := poll_live L s hf hw (fun t ht => by rw [hlast] at ht; cases ht; omega)
      (by omega) hh (by omega) (by omega) (by rw [← hx] at ha; exact ha) (by rw [← hx] at ha1; exact ha1)
    exact ⟨s', Or.inl ⟨hx, hn⟩, by rw [hl, hx], fun w hw' => by rw [hc w hw', hx], hfa⟩
  · have hlt : s.now < t0 + interval L s := by omega
    have hwait : next L s = .wait (t0 + interval L s) .interval := by
      have n1 : ¬ L.maxFails ≤ s.fails := by omega
      unfold next
      simp only [n1, hw, hlast, hlt, ↓reduceIte]
    let s1 := step L s (.clock (t0 + interval L s))
    have hn1 : s1.now = t0 + interval L s := by simp only [s1, step]; omega
    have hc1 : tickCost L s1 = tickCost L s := rfl
    have hl1 : s1.lastTick = some t0 := hlast
    have hi1 : interval L s1 ≤ interval L s := interval_clock L s (t0 + interval L s)
    have hW : wsum L.W (t0 + interval L s) (ofKind .tick) s1.ledger ≤
        wsum L.W (t0 + interval L s) (ofKind .tick) s.ledger := wsum_filter_le _ _ _ _ _
    have hW1 : wsum L.W1 (t0 + interval L s) (ofKind .tick) s1.ledger ≤
        wsum L.W1 (t0 + interval L s) (ofKind .tick) s.ledger := wsum_filter_le _ _ _ _ _
    obtain ⟨s', hn, hl, hc⟩ := poll_live L s1 hf hw
      (fun t ht => by rw [hl1] at ht; cases ht; omega) (by simp only [s1, step]; omega)
      (headroom_clock L s _ hh) (by omega) (by omega)
      (by rw [hn1, hc1]; omega) (by rw [hn1, hc1]; omega)
    rw [hc1] at hn
    exact ⟨s', Or.inr ⟨hwait, hn⟩, by rw [hl, hn1], fun w hw' => by rw [hc w hw', hn1], hfa⟩

/-- When the three gaps are at most `P_min`, the interval is `P_min`. -/
theorem interval_eq_Pmin (L : Limits) (s : State) (h1 : hourGap L s ≤ L.Pmin) (h2 : minuteGap L s ≤ L.Pmin)
    (h3 : spread L s ≤ L.Pmin) : interval L s = L.Pmin := by
  unfold interval; omega

/-- (f) The latency at `P_min`. Under the hypotheses of `listed_within` with every gap at most `P_min` (the hour
and minute shares fit a tick every `P_min`, and the headroom above the floor lasts until the reset at that pace),
the poller ticks at `x = t_0 + P_min` and covers every watched run. A run that completed at any `f` with
`t_0 ≤ f ≤ x` is listed at most `P_min` after it completed; once the list is written `d` seconds after the tick
(the duration of the `gh` call), a waiter that has been reading every `slice` seconds since `r_0 ≤ x + d` reads it
before `f + P_min + d + slice`.
-/
theorem listed_within_Pmin (L : Limits) (s : State) (t0 : Nat)
    (hf : s.fails < L.maxFails) (hw : s.watched ≠ []) (hlast : s.lastTick = some t0)
    (hg1 : hourGap L s ≤ L.Pmin) (hg2 : minuteGap L s ≤ L.Pmin) (hg3 : spread L s ≤ L.Pmin)
    (hon : s.now ≤ t0 + L.Pmin) (hr : s.retryUntil ≤ t0 + L.Pmin) (hh : headroom L s = true)
    (ha : wsum L.W (t0 + L.Pmin) (ofKind .tick) s.ledger + tickCost L s ≤ share L .tick)
    (ha1 : wsum L.W1 (t0 + L.Pmin) (ofKind .tick) s.ledger + tickCost L s ≤ share1 L .tick) :
    ∃ s', ((s.now = t0 + L.Pmin ∧ next L s = .issue .tick (tickCost L s) s') ∨
        (next L s = .wait (t0 + L.Pmin) .interval ∧
          next L (step L s (.clock (t0 + L.Pmin))) = .issue .tick (tickCost L s) s')) ∧
      s'.lastTick = some (t0 + L.Pmin) ∧ (∀ w ∈ s'.watched, w.lastCovered = some (t0 + L.Pmin)) ∧
      ∀ f d r0, t0 ≤ f → f ≤ t0 + L.Pmin → r0 ≤ t0 + L.Pmin + d →
        f ≤ t0 + L.Pmin ∧ t0 + L.Pmin ≤ f + L.Pmin ∧ t0 + L.Pmin + d ≤ firstRead r0 slice (t0 + L.Pmin + d) ∧
        firstRead r0 slice (t0 + L.Pmin + d) < f + L.Pmin + d + slice := by
  have hP := interval_eq_Pmin L s hg1 hg2 hg3
  rw [← hP] at hon hr ha ha1
  obtain ⟨s', hcase, hl, hc, -⟩ := listed_within L s t0 hf hw hlast hon hr hh ha ha1
  rw [hP] at hcase hl hc
  refine ⟨s', hcase, hl, hc, fun f d r0 h1 h2 h3 => ?_⟩
  have hb := firstRead_bound r0 slice (t0 + L.Pmin + d) (by decide) h3
  refine ⟨h2, by omega, hb.1, by omega⟩

/-- With the default limits and one page, the share gaps are below `P_min`; only `spread` can lengthen the
interval, and only when the headroom above the floor runs short before the reset. -/
example : hourGap defaults (init 0) ≤ defaults.Pmin ∧ minuteGap defaults (init 0) ≤ defaults.Pmin := by decide

/-! ## (g) The budget against GitHub's limit -/

/-- GitHub's primary REST limit: requests per hour per user account, shared by all of that user's tokens
(docs.github.com, rate limits for the REST API).
-/
def ghLimit : Nat := 5000

/-- What the ledger's cap leaves of GitHub's limit, for corrections and for callers that skip the ledger. -/
def margin : Nat := ghLimit - defaults.B

#guard margin = 2000 && defaults.B + margin = ghLimit

/-- A correction entry (a response that cost more than charged). -/
def isCorrection (e : Entry) : Bool := !e.charged

/-- Every entry of a window is a charge or a correction. -/
theorem wsum_all (W t : Nat) (l : List Entry) :
    wsum W t (fun _ => true) l = wsum W t isCharge l + wsum W t isCorrection l := by
  induction l with
  | nil => simp [wsum]
  | cons e es ih =>
    rcases e with ⟨time, cost, kind, charged⟩
    simp only [wsum, ih, isCharge, isCorrection]
    cases charged <;> simp <;> omega

/-- (g) The budget over every ledger entry. In every reachable state with `R ≤ B` and `B + margin ≤ ghLimit`, for every time `t` and every count `u` of requests made in the window `(t - W, t]` by callers that
skip the ledger: if the corrections in that window plus `u` fit the margin, then all ledger entries in the window
(charges and corrections) plus `u` stay within `ghLimit = 5000` (GitHub's hourly limit when `W = 3600`, as
in the defaults). The margin is an assumption about the
corrections and the uncharged callers, not a result.
-/
theorem budget_all_entries (L : Limits) (t0 : Nat) (s : State) (hr : Reach L (init t0) s) (hR : L.R ≤ L.B)
    (hM : L.B + margin ≤ ghLimit) (t u : Nat) (hu : wsum L.W t isCorrection s.ledger + u ≤ margin) :
    wsum L.W t (fun _ => true) s.ledger + u ≤ ghLimit := by
  have a := (window_bound L t0 s hr .tick t).1
  have b := (window_bound L t0 s hr .oneoff t).1
  simp only [share] at a b
  rw [wsum_all, wsum_charges]
  omega

/-! ## (h) One bucket: the remaining count -/

/-- Headers of any other bucket than `core` (or without `x-ratelimit-resource`) leave the remaining count and the
reset as they were.
-/
theorem bucket_core_only (L : Limits) (s : State) (h : Headers) (a : Nat) (hc : h.resource ≠ some "core") :
    (observe L s h a).remaining = s.remaining ∧ (observe L s h a).reset = s.reset := by
  simp [observe, bucket, hc]

/-- An issued charge leaves the remaining count and the reset as they were. -/
theorem charge_bucket (L : Limits) (s : State) (k : Kind) (c : Nat) (k' : Kind) (c' : Nat) (s' : State)
    (h : charge L s k c = .issue k' c' s') : s'.remaining = s.remaining ∧ s'.reset = s.reset := by
  unfold charge at h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h
  cases h
  exact ⟨rfl, rfl⟩

/-- (h) Within one reset window the remaining count never rises: from a state with remaining `r` and reset `T`, every
event that leaves the reset at `T` leaves a remaining count of at most `r`, and an issued charge and a tick's cover
change neither.
-/
theorem remaining_no_rise (L : Limits) (s : State) (T r : Nat) (hT : s.reset = some T) (hr : s.remaining = some r) :
    (∀ e, (step L s e).reset = some T → ∃ r', r' ≤ r ∧ (step L s e).remaining = some r') ∧
    (∀ k c k' c' s', charge L s k c = .issue k' c' s' → s'.remaining = some r ∧ s'.reset = some T) ∧
    (cover s).remaining = some r ∧ (cover s).reset = some T := by
  refine ⟨fun e he => ?_, fun k c k' c' s' hc => ?_, by simp [cover, hr], by simp [cover, hT]⟩
  · cases e with
    | response h a =>
      simp only [step, observe, bucket] at he ⊢
      by_cases hc : h.resource = some "core"
      · simp only [hc, ↓reduceIte] at he ⊢
        split at he
        · rename_i r1 T1 _ _
          by_cases hTT : s.reset = some T1
          · simp only [hTT, ↓reduceIte, hr] at he ⊢
            exact ⟨min r1 r, Nat.min_le_right _ _, rfl⟩
          · simp only [hTT, ↓reduceIte, Option.some.injEq] at he
            subst he; exact absurd hT hTT
        · exact ⟨r, Nat.le_refl _, hr⟩
      · simp only [hc, ↓reduceIte]
        exact ⟨r, Nat.le_refl _, hr⟩
    | clock t => exact ⟨r, Nat.le_refl _, hr⟩
    | register rid c =>
      simp only [step]; split
      · exact ⟨r, Nat.le_refl _, hr⟩
      · exact ⟨r, Nat.le_refl _, hr⟩
    | unregister rid => exact ⟨r, Nat.le_refl _, hr⟩
    | pages n => exact ⟨r, Nat.le_refl _, hr⟩
    | resume => exact ⟨r, Nat.le_refl _, hr⟩
    | listed rows count pagesRead since => exact ⟨r, Nat.le_refl _, hr⟩
    | ack n => exact ⟨r, Nat.le_refl _, hr⟩
    | sweep alive => exact ⟨r, Nat.le_refl _, hr⟩
  · have := charge_bucket L s k c k' c' s' hc
    rw [this.1, this.2, hr, hT]; exact ⟨rfl, rfl⟩

/-! ## (i) Stale watches and the bounded tick

The incident of 2026-10-20: a branch watch (id `10^15 + h`) never finished, the list window `created >= createdAt`
stayed open for 4.5 h, a tick needed 11 pages (cost 22) and `charge` stopped the poller with `tooBig`, a stop only a
manual resume lifts. Three rules close it: an unknown id is refused at registration, a watch a list cannot find is dropped
with an incident, and a tick never reads more pages than its share allows. Section (j) adds the fourth: a watch whose
waiter is gone is dropped. -/

/-- (i-a) Registration refuses an id that is neither a GitHub run id nor a branch sentinel: the state stays. -/
theorem register_refused (L : Limits) (s : State) (r c : Nat) (h : validWatch L r = false) :
    step L s (.register r c) = s := by
  simp [step, h]

/-- (i-a) Registration accepts a valid id: the run is watched afterwards (a first registration appends it with no
misses, a second changes nothing).
-/
theorem register_accepted (L : Limits) (s : State) (r c : Nat) (h : validWatch L r = true) :
    ∃ w ∈ (step L s (.register r c)).watched, w.runId = r := by
  unfold step
  by_cases hd : s.watched.any (·.runId == r) = true
  · simp only [h, hd]
    simp only [List.any_eq_true, beq_iff_eq] at hd
    obtain ⟨w, hw, hwr⟩ := hd
    simpa using ⟨w, hw, hwr⟩
  · simp only [h, hd]
    simp

/-- (i-a) The stray id of the incident, `10^15 + 838323`, is a branch sentinel (the glue's `sentinelId`) and so is
accepted at registration. An id above the sentinel range is refused.
-/
theorem incident_id : validWatch defaults 1000000000838323 = true ∧ validRunId defaults 1000000000838323 = false ∧
    validWatch defaults (10 ^ 15 + 2 ^ 32) = false := by decide

/-- (i-b) Every watch is covered or dropped with an incident: after a list, each watch is still watched (under its
run id) or has an incident with its id at the current time.
-/
theorem listed_total (L : Limits) (s : State) (rows : List (Nat × Nat)) (full : Bool) (since : Nat) (w : Watch)
    (hw : w ∈ s.watched) :
    (∃ w' ∈ (listed L s rows full since).watched, w'.runId = w.runId) ∨
    ∃ d, (⟨w.runId, s.now, d⟩ : Incident) ∈ (listed L s rows full since).incidents := by
  cases hj : judge L rows full since w with
  | inl d =>
    right
    refine ⟨d, ?_⟩
    simp only [listed, List.mem_append, List.mem_filterMap]
    exact Or.inr ⟨w, hw, by simp [hj]⟩
  | inr w2 =>
    left
    refine ⟨w2, ?_, ?_⟩
    · simp only [listed, List.mem_filterMap]
      exact ⟨w, hw, by simp [hj]⟩
    · unfold judge at hj
      split at hj
      · simp at hj; subst hj; rfl
      · split at hj
        · simp at hj; subst hj; rfl
        · split at hj
          · simp at hj; subst hj; rfl
          · split at hj
            · simp at hj
            · split at hj
              · simp at hj
              · simp at hj; subst hj; rfl

/-- (i-b) Every kept watch is covered: after a list, each watch left in `watched` is a branch sentinel, is in the
list's rows, was created before the list's window (registered after the tick began, judged by the next tick), or is
covered by the list. A real run the list cannot cover is not kept. Accepted limit: a sentinel is kept without a
coverage check (it is not a run), and under a full, narrowed list a sentinel's run may lie outside the pages read;
a sentinel whose waiter died is dropped by `sweep`, not by a list.
-/
theorem listed_kept_covered (L : Limits) (s : State) (rows : List (Nat × Nat)) (full : Bool) (since : Nat)
    (w' : Watch) (hm : w' ∈ (listed L s rows full since).watched) :
    isSentinel w'.runId = true ∨ rows.any (·.1 == w'.runId) = true ∨ w'.createdAt < since ∨
      covers rows full since w' = true := by
  simp only [listed, List.mem_filterMap] at hm
  obtain ⟨w, -, hj⟩ := hm
  cases hjj : judge L rows full since w with
  | inl d => simp [hjj] at hj
  | inr w2 =>
    simp only [hjj, Option.some.injEq] at hj
    subst hj
    unfold judge at hjj
    split at hjj
    · simp at hjj; subst hjj; left; assumption
    · split at hjj
      · simp at hjj; subst hjj; right; left; assumption
      · split at hjj
        · simp at hjj; subst hjj; right; right; left; assumption
        · split at hjj
          · simp at hjj
          · split at hjj
            · simp at hjj
            · rename_i hcv _
              have h1 : covers rows full since w = true := by simpa using hcv
              simp at hjj; subst hjj; right; right; right
              exact h1

/-- (i-b) A run that the narrowed list cannot cover is dropped with an `uncovered` incident: on a full list, a
real run (not a sentinel) absent from the rows, inside the list's window, and created no later than the oldest row.
-/
theorem listed_uncovered (L : Limits) (s : State) (rows : List (Nat × Nat)) (since : Nat) (w : Watch)
    (hw : w ∈ s.watched)
    (hs : isSentinel w.runId = false) (hr : rows.any (·.1 == w.runId) = false) (hw0 : since ≤ w.createdAt)
    (hc : covers rows true since w = false) :
    (⟨w.runId, s.now, .uncovered⟩ : Incident) ∈ (listed L s rows true since).incidents := by
  have hj : judge L rows true since w = .inl .uncovered := by
    simp [judge, hs, hr, hc]; omega
  simp only [listed, List.mem_append, List.mem_filterMap]
  exact Or.inr ⟨w, hw, by simp [hj]⟩

/-- (i-b) A covered run missing from a list for the `missMax`-th tick in a row is dropped with an `unseen` incident. -/
theorem listed_unseen (L : Limits) (s : State) (rows : List (Nat × Nat)) (full : Bool) (since : Nat) (w : Watch)
    (hw : w ∈ s.watched) (hs : isSentinel w.runId = false) (hr : rows.any (·.1 == w.runId) = false)
    (hc : covers rows full since w = true) (hm : L.missMax ≤ w.misses + 1) :
    (⟨w.runId, s.now, .unseen⟩ : Incident) ∈ (listed L s rows full since).incidents := by
  have hw0 : since ≤ w.createdAt := by simpa [covers] using (Bool.and_eq_true_iff.mp hc).1
  have hj : judge L rows full since w = .inl .unseen := by simp [judge, hs, hr, hc, hm]; omega
  simp only [listed, List.mem_append, List.mem_filterMap]
  exact Or.inr ⟨w, hw, by simp [hj]⟩

/-- (i-b) Whether a list was cut is decided here, not by the glue: `count` rows from `pagesRead` pages is full
exactly when every page was full (`pagesRead * 100 ≤ count`, with at least one page).
-/
theorem isFull_iff (n p : Nat) : isFull n p = true ↔ max 1 p * 100 ≤ n := by
  simp [isFull]

/-- (i-b) The `listed` event applies the decision of `isFull`: a list of 100 rows from one page is full, 99 rows are
not, 200 rows from 2 pages are full.
-/
theorem isFull_cases : isFull 100 1 = true ∧ isFull 99 1 = false ∧ isFull 200 2 = true ∧ isFull 199 2 = false := by decide

/-- (i-c) The tick cost is at most the per-minute tick share, for every state, when one page fits the share. -/
theorem tickCost_le (L : Limits) (s : State) (h1 : L.listCost ≤ share1 L .tick) (h0 : 0 < L.listCost) :
    tickCost L s ≤ share1 L .tick := by
  unfold tickCost pagesOf pageCap
  have hq : 1 ≤ share1 L .tick / L.listCost := (Nat.le_div_iff_mul_le h0).2 (by omega)
  have hmax : max 1 (share1 L .tick / L.listCost) = share1 L .tick / L.listCost := Nat.max_eq_right hq
  rw [hmax]
  calc L.listCost * min (share1 L .tick / L.listCost) (max 1 s.pages)
      ≤ L.listCost * (share1 L .tick / L.listCost) := Nat.mul_le_mul_left _ (Nat.min_le_left _ _)
    _ ≤ share1 L .tick := Nat.mul_div_le _ _

/-- (i-c) The charge of a tick never stops `tooBig`: with one page within the per-minute tick share and the
per-minute share within the hourly one, `charge` of a tick answers `stop` only with `failures`, for any state and
any pages the state asks for.
-/
theorem tick_charge_no_tooBig (L : Limits) (s : State) (h0 : 0 < L.listCost) (h1 : L.listCost ≤ share1 L .tick)
    (h2 : share1 L .tick ≤ share L .tick) (r : Reason) (hr : charge L s .tick (tickCost L s) = .stop r) :
    r = .failures := by
  have hc := tickCost_le L s h1 h0
  unfold charge at hr
  by_cases hf : L.maxFails ≤ s.fails
  · simp [hf] at hr; exact hr.symm
  · have hn : ¬ (share L .tick < tickCost L s ∨ share1 L .tick < tickCost L s) := by omega
    simp only [hf, hn, ite_false] at hr
    split at hr <;> try simp at hr
    all_goals (split at hr <;> try simp at hr)
    all_goals (split at hr <;> try simp at hr)
    all_goals (split at hr <;> try simp at hr)

/-- (i-c) The poller never stops `tooBig`: under the same shape, `tickNow` stops only with `failures`, and `next`
only with `failures` or `idle`. A tick that would need more pages than the share allows reads `pageCap` pages
instead (and `listed` drops what the narrowed list cannot cover).
-/
theorem tick_no_tooBig (L : Limits) (s : State) (h0 : 0 < L.listCost) (h1 : L.listCost ≤ share1 L .tick)
    (h2 : share1 L .tick ≤ share L .tick) :
    (∀ r, tickNow L s = .stop r → r = .failures) ∧ (∀ r, next L s = .stop r → r = .failures ∨ r = .idle) := by
  have htick : ∀ r, tickNow L s = .stop r → r = .failures := by
    intro r hr
    unfold tickNow at hr
    cases hq : charge L s .tick (tickCost L s) with
    | issue k c s' => rw [hq] at hr; simp at hr
    | wait u w => rw [hq] at hr; simp at hr
    | stop w => rw [hq] at hr; simp at hr; subst hr; exact tick_charge_no_tooBig L s h0 h1 h2 w hq
  refine ⟨htick, fun r hr => ?_⟩
  unfold next at hr
  split at hr
  · simp at hr; exact Or.inl hr.symm
  · split at hr
    · simp at hr; exact Or.inr hr.symm
    · split at hr
      · split at hr
        · simp at hr
        · exact Or.inl (htick r hr)
      · exact Or.inl (htick r hr)

/-- (i-c) The default limits satisfy the shape the no-`tooBig` theorem needs: a page costs 2, within the per-minute
tick share 20, within the hourly tick share 1800. A tick reads at most `pageCap` = 10 pages.
-/
theorem defaults_shape : 0 < defaults.listCost ∧ defaults.listCost ≤ share1 defaults .tick ∧
    share1 defaults .tick ≤ share defaults .tick ∧ pageCap defaults = 10 := by decide

/-- (i-c) The incident's tick: a stale stored `pages` of 11 is capped at `pageCap` = 10 when the tick reads it, so the
tick costs 20 (pageCap 10 x listCost 2), the per-minute tick share, and `tick_no_tooBig` holds for it.
-/
theorem incident_tick : pagesOf defaults { init 0 with pages := 11 } = 10 ∧
    tickCost defaults { init 0 with pages := 11 } = 20 := by decide

/-- The incidents leave only through `ack`: acknowledging `n` incidents keeps the later ones, and the watches stay. -/
theorem ack_drops (L : Limits) (s : State) (n : Nat) :
    (step L s (.ack n)).incidents = s.incidents.drop n ∧ (step L s (.ack n)).watched = s.watched := by
  simp [step]

-- the incident replayed: a sentinel watch (createdAt 90000 as the window start) with 11 pages stored: the tick goes at
-- the capped 20 = pageCap 10 x listCost 2
#guard (match next defaults ((step defaults (step defaults (init 100000) (.register 1000000000838323 90000)) (.pages 11))) with
  | .issue _ c _ => c = 20 | _ => false)
#guard (step defaults (init 0) (.register 5000000000000000 0)).watched = []
-- three covered lists without the run drop it; a list holding it clears its misses
#guard (step defaults (step defaults (step defaults (step defaults (init 100) (.register 7 90))
  (.listed [] 0 1 80)) (.listed [] 0 1 80)) (.listed [] 0 1 80)).incidents = [⟨7, 100, .unseen⟩]
#guard (step defaults (step defaults (step defaults (init 100) (.register 7 90)) (.listed [] 0 1 80))
  (.listed [(7, 90)] 1 1 80)).watched = [⟨7, 90, none, 0⟩]
-- a full list (100 rows from 1 page) cut at created 95 cannot cover a run created at 90
#guard (step defaults (step defaults (init 100) (.register 7 90)) (.listed [(9, 95), (8, 99)] 100 1 80)).incidents =
  [⟨7, 100, .uncovered⟩]
-- the same two rows from 1 page are not full: the run stays with a miss
#guard (step defaults (step defaults (init 100) (.register 7 90)) (.listed [(9, 95), (8, 99)] 2 1 80)).watched =
  [⟨7, 90, none, 1⟩]
-- a run registered after the tick began (created before the window start 95) is not judged
#guard (step defaults (step defaults (init 100) (.register 7 90)) (.listed [(9, 95)] 100 1 95)).watched =
  [⟨7, 90, none, 0⟩]

/-! ## (j) Orphan watches: a watch is kept exactly while its waiter lives

The origin incident's sentinel stayed registered because its waiter had died, not because it was old. No age or
heartbeat constant can tell a slow workflow from a dead waiter; the identity of the waiter can: a watch is kept
exactly while a marker of a live waiter names its run. The glue reads the waiter directory under the state lock and
hands the markers to `ci.budget.next`; this section is the decision. -/

/-- (j-a) A dead process is a dead waiter, whatever the tokens say.
-/
theorem marker_dead (m : Marker) (h : m.killOk = false) : m.alive = false := by
  simp [Marker.alive, h]

/-- (j-a) A reused pid is a dead waiter: the process exists but its start time is not the one the marker recorded.
-/
theorem marker_reused (m : Marker) (a b : String) (hk : m.killOk = true) (ha : m.recorded = some a)
    (hb : m.now = some b) (hne : a ≠ b) : m.alive = false := by
  simp [Marker.alive, hk, ha, hb, hne]

/-- (j-a) A live process with the recorded start time is a live waiter.
-/
theorem marker_same (m : Marker) (a : String) (hk : m.killOk = true) (ha : m.recorded = some a)
    (hb : m.now = some a) : m.alive = true := by
  simp [Marker.alive, hk, ha, hb]

/-- (j-a) A marker without a recorded token (older code) is alive exactly when its process exists.
-/
theorem marker_tokenless (m : Marker) (h : m.recorded = none) : m.alive = m.killOk := by
  simp [Marker.alive, h]

/-- (j-a) A recorded token with a start time that cannot be read now (`ps` does not see the pid) is a dead waiter, even
when `kill` finds the process.
-/
theorem marker_unreadable (m : Marker) (a : String) (ha : m.recorded = some a) (h : m.now = none) :
    m.alive = false := by
  simp [Marker.alive, ha, h]

/-- (j-a) A run id has a live waiter exactly when some live marker names it.
-/
theorem mem_aliveIds (ms : List Marker) (r : Nat) :
    r ∈ aliveIds ms ↔ ∃ m ∈ ms, m.runId = r ∧ m.alive = true := by
  simp only [aliveIds, List.mem_map, List.mem_filter]
  constructor
  · rintro ⟨m, ⟨hm, ha⟩, rfl⟩; exact ⟨m, hm, rfl, ha⟩
  · rintro ⟨m, hm, rfl, ha⟩; exact ⟨m, ⟨hm, ha⟩, rfl⟩

/-- (j-b) A watch with a live waiter is kept, unchanged.
-/
theorem sweep_keeps_alive (s : State) (alive : List Nat) (w : Watch) (hw : w ∈ s.watched)
    (ha : w.runId ∈ alive) : w ∈ (sweep s alive).watched := by
  simp [sweep, List.mem_filter, hw, ha]

/-- (j-b) A watch with no live waiter is dropped and logged with an `orphan` incident at the current time. The rule has
no premise on the kind of id: a real run and a branch sentinel are treated alike.
-/
theorem sweep_drops_orphan (s : State) (alive : List Nat) (w : Watch) (hw : w ∈ s.watched)
    (ha : w.runId ∉ alive) :
    (∀ w' ∈ (sweep s alive).watched, w'.runId ≠ w.runId) ∧
    (⟨w.runId, s.now, .orphan⟩ : Incident) ∈ (sweep s alive).incidents := by
  refine ⟨fun w' hw' he => ?_, ?_⟩
  · simp only [sweep, List.mem_filter, List.contains_iff_mem] at hw'
    exact ha (he ▸ hw'.2)
  · simp only [sweep, List.mem_append, List.mem_filterMap]
    exact Or.inr ⟨w, hw, by simp [ha]⟩

/-- (j-b) Every watch is kept or has an incident: after a sweep, each watch is still watched under its run id, or an
`orphan` incident names its run at the current time.
-/
theorem sweep_total (s : State) (alive : List Nat) (w : Watch) (hw : w ∈ s.watched) :
    (∃ w' ∈ (sweep s alive).watched, w'.runId = w.runId) ∨
    (⟨w.runId, s.now, .orphan⟩ : Incident) ∈ (sweep s alive).incidents := by
  by_cases ha : w.runId ∈ alive
  · exact Or.inl ⟨w, sweep_keeps_alive s alive w hw ha, rfl⟩
  · exact Or.inr (sweep_drops_orphan s alive w hw ha).2

/-- (j-b) A sweep only removes watches, and only the orphans: the survivors are watches of the state, each with a live
waiter, and the incidents already logged stay.
-/
theorem sweep_only_orphans (s : State) (alive : List Nat) :
    (∀ w' ∈ (sweep s alive).watched, w' ∈ s.watched ∧ w'.runId ∈ alive) ∧
    ∃ t, (sweep s alive).incidents = s.incidents ++ t := by
  refine ⟨fun w' hw' => ?_, _, rfl⟩
  simp only [sweep, List.mem_filter, List.contains_iff_mem] at hw'
  exact hw'

/-- A charge changes no watch.
-/
theorem charge_watched (L : Limits) (s : State) (k : Kind) (c : Nat) (k' : Kind) (c' : Nat) (s' : State)
    (h : charge L s k c = .issue k' c' s') : s'.watched = s.watched := by
  unfold charge at h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h
  cases h
  rfl

/-- (j-c) The window comes from live waiters only: when the poller issues a tick after a sweep, the oldest creation time
it lists from (`createdSince`) is the creation time of a watch that has a live waiter, so an orphan never widens the
window.
-/
theorem next_window_from_live (L : Limits) (s : State) (alive : List Nat) (k : Kind) (c : Nat) (s' : State)
    (h : next L (step L s (.sweep alive)) = .issue k c s') (x : Nat) (hx : since s' = some x) :
    ∃ w ∈ s.watched, w.runId ∈ alive ∧ w.createdAt = x := by
  obtain ⟨s'', hc, rfl⟩ := next_issue L _ k c s' h
  have hw := charge_watched L _ _ _ _ _ _ hc
  have hm : x ∈ (cover s'').watched.map (·.createdAt) := List.min?_mem hx
  simp only [cover, List.map_map, List.mem_map, Function.comp] at hm
  obtain ⟨w, hw1, rfl⟩ := hm
  rw [hw] at hw1
  have hw2 : w ∈ (step L s (.sweep alive)).watched := hw1
  simp only [step, sweep, List.mem_filter, List.contains_iff_mem] at hw2
  exact ⟨w, hw2.1, hw2.2, rfl⟩

/-- (j-c) A sweep with no live waiter leaves no watch, so `next` stops idle afterwards (or on failures first) and a
dead waiter's tick cost ends with the sweep.
-/
theorem sweep_nobody (s : State) : (sweep s []).watched = [] := by
  simp [sweep]

-- a sentinel and a real run, one waiter alive: the dead one is dropped with an orphan incident at the clock
#guard (sweep { init 100 with watched := [⟨7, 90, none, 0⟩, ⟨1000000000838323, 80, none, 0⟩] } [7]).incidents =
  [⟨1000000000838323, 100, .orphan⟩]
#guard (sweep { init 100 with watched := [⟨7, 90, none, 0⟩, ⟨1000000000838323, 80, none, 0⟩] } [7]).watched =
  [⟨7, 90, none, 0⟩]
-- the dead sentinel does not widen the window: the oldest watch is 90, not 80
#guard (match next defaults (step defaults { init 100 with watched := [⟨7, 90, none, 0⟩, ⟨1000000000838323, 80, none, 0⟩] }
    (.sweep [7])) with
  | .issue _ _ s' => since s' = some 90 | _ => false)
-- nobody alive: the poller is idle
#guard stopOf (next defaults (step defaults { init 100 with watched := [⟨7, 90, none, 0⟩] } (.sweep []))) = some .idle
-- the marker cases: dead, live, reused pid, tokenless, recorded but unreadable now
#guard !(Marker.alive ⟨7, false, some "a", some "a"⟩) && Marker.alive ⟨7, true, some "a", some "a"⟩ &&
  !(Marker.alive ⟨7, true, some "a", some "b"⟩) && Marker.alive ⟨7, true, none, some "b"⟩ &&
  !(Marker.alive ⟨7, true, some "a", none⟩) && Marker.alive ⟨7, true, none, none⟩

end Fw.Ci.Budget
