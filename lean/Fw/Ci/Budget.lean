/-!
# GitHub API rate budget: one charged ledger for every `gh` call of the machine

Spec of the choke point `ghCharged` and the shared CI poller (design: `research/notes/2026/10-18-gh-rate-budget.md`
§3; wire ops in `Fw.Wire.Ci`, file `Fw/Ci/Wire.lean`). Every GitHub request our tools make is first *charged* to a
ledger shared by the whole machine. `reserve` (one-off calls) and `next` (the poller's tick) decide whether a call may
go now; `observe` folds the response headers back in. All times are integer seconds.

The ledger has two shares per window, so one-off calls (downloads, logs) can never starve the poller: ticks get
$B - R$ per hour and $B_1 - R_1$ per minute, one-offs $R$ and $R_1$. A response that cost more requests than charged
(`gh run list` without `--workflow` costs $2 + D$) is booked as a *correction* entry; corrections count against the
share, so later calls wait until the window has room again.

Proved here:
- (a) `window_bound`: in every reachable state and for every time $t$, the charged requests of each share in the
  3600 s and 60 s windows stay within the share, so all of them stay within $B$ and $B_1$; `window_total`: the
  total over both kinds is at most $B$. Waiters never enter the ledger (`register_free`, `register_dup`), so the
  bound holds for every number of waiters $N$. `overrun_absorbed`: with corrections the window holds at most the
  share plus the corrections in it.
- (b) `no_issue_when_exhausted`, `next_no_issue_when_exhausted`: nothing is issued while `now < retryUntil`, nor while
  remaining $\le F$ before the reset. `guard_persists`: a `retry-after` or a 403/429 with remaining 0 blocks every
  issue until that time, along every later trace. `backoff_ge`, `backoff_mono`, `stop_after_fails`: the bare-failure
  backoff.
- (c) `poll_live`: whenever the guards allow and the interval has passed, `next` ticks and covers every watched run;
  `next_wait_interval`: otherwise it waits at most $P$; `wait_future`: no wait is in the past.
- (d) `interval_sound`: the interval $P$ makes any ticks spaced $\ge P$ fit both tick shares and the headroom before
  the reset; `per_agent_interval`, `oldRate_linear`: the old scheme ($N$ pollers each on its own) grows linearly in
  $N$ and needs $P \ge W c N / B$.
- (e) `clock_monotone`: `now` never goes back.
-/
namespace Fw.Ci.Budget

/-! ## Limits -/

/-- The budget's constants (generated to `packages/contracts/golden/ci-budget/limits.json`; TS reads them there).

$$\mathrm{Limits} = (W, B, R, W_1, B_1, R_1, F, P_{\min}, b_0, b_{\max}, m, c_{\text{list}}) \in \mathbb{N}^{12}, \quad \text{defaults } (3600, 3000, 1200, 60, 60, 40, 500, 30, 60, 3600, 6, 2)$$
-/
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
  Pmin : Nat := 30
  /-- first backoff after a bare 403/429, s -/
  back0 : Nat := 60
  /-- longest backoff, s -/
  backMax : Nat := 3600
  /-- bare failures in a row before the poller stops -/
  maxFails : Nat := 6
  /-- requests per page of one tick (`gh run list --workflow`: 2) -/
  listCost : Nat := 2
deriving Repr, DecidableEq

/-- The default limits.

$$\mathit{defaults} = (3600, 3000, 1200, 60, 60, 40, 500, 30, 60, 3600, 6, 2)$$
-/
def defaults : Limits := {}

#guard defaults.B = 3000 && defaults.R = 1200 && defaults.F = 500 && defaults.Pmin = 30 && defaults.B1 = 60

/-- The two kinds of charged call: a poller tick, or a one-off call (dispatch, view, log, download, probe).

$$\mathrm{Kind} = \{\mathrm{tick}, \mathrm{oneoff}\}$$
-/
inductive Kind where
  | tick
  | oneoff
deriving Repr, DecidableEq

/-- The hourly share of a kind.

$$\operatorname{share}(L, \mathrm{tick}) = L.B \mathbin{\dot-} L.R, \qquad \operatorname{share}(L, \mathrm{oneoff}) = L.R$$
-/
def share (L : Limits) : Kind → Nat
  | .tick => L.B - L.R
  | .oneoff => L.R

/-- The per-minute share of a kind.

$$\operatorname{share}_1(L, \mathrm{tick}) = L.B_1 \mathbin{\dot-} L.R_1, \qquad \operatorname{share}_1(L, \mathrm{oneoff}) = L.R_1$$
-/
def share1 (L : Limits) : Kind → Nat
  | .tick => L.B1 - L.R1
  | .oneoff => L.R1

#guard share defaults .tick = 1800 && share defaults .oneoff = 1200
#guard share1 defaults .tick = 20 && share1 defaults .oneoff = 40

/-! ## The ledger and its window sums -/

/-- One ledger entry: the time it was charged, its cost in requests, its kind, and whether it is a charge
(`true`) or a correction for a response that cost more than charged (`false`).

$$\mathrm{Entry} = (\mathit{time}, \mathit{cost}, \mathit{kind}, \mathit{charged}) \in \mathbb{N}^2 \times \mathrm{Kind} \times \mathbb{B}$$
-/
structure Entry where
  time : Nat
  cost : Nat
  kind : Kind
  charged : Bool
deriving Repr, DecidableEq

/-- Is time $x$ inside the window of length $W$ ending at $t$, that is $x \in (t - W, t]$?

$$\operatorname{inWin}(W, t, x) \iff x \le t \land t < x + W$$
-/
def inWin (W t x : Nat) : Bool := decide (x ≤ t) && decide (t < x + W)

/-- The cost of the selected entries of a ledger that lie in the window of length $W$ ending at $t$.

$$\Sigma_W(\mathit{sel}, \ell, t) = \sum_{e \in \ell,\ \mathit{sel}(e),\ e.\mathit{time} \le t < e.\mathit{time} + W} e.\mathit{cost}$$
-/
def wsum (W t : Nat) (sel : Entry → Bool) : List Entry → Nat
  | [] => 0
  | e :: es => (if sel e && inWin W t e.time then e.cost else 0) + wsum W t sel es

/-- Entries of kind $k$ (charges and corrections).

$$\operatorname{ofKind}(k)(e) \iff e.\mathit{kind} = k$$
-/
def ofKind (k : Kind) (e : Entry) : Bool := decide (e.kind = k)

/-- Charges of kind $k$.

$$\operatorname{chargedOf}(k)(e) \iff e.\mathit{kind} = k \land e.\mathit{charged}$$
-/
def chargedOf (k : Kind) (e : Entry) : Bool := decide (e.kind = k) && e.charged

/-- Corrections of kind $k$.

$$\operatorname{corrOf}(k)(e) \iff e.\mathit{kind} = k \land \lnot e.\mathit{charged}$$
-/
def corrOf (k : Kind) (e : Entry) : Bool := decide (e.kind = k) && !e.charged

/-- Every charge, of either kind.

$$\operatorname{isCharge}(e) \iff e.\mathit{charged}$$
-/
def isCharge (e : Entry) : Bool := e.charged

/-- The window sum of a concatenation is the sum of the window sums.

$$\forall W, t, \mathit{sel}, a, b:\quad \Sigma_W(\mathit{sel}, a \mathbin{+\!\!+} b, t) = \Sigma_W(\mathit{sel}, a, t) + \Sigma_W(\mathit{sel}, b, t)$$
-/
theorem wsum_append (W t : Nat) (sel : Entry → Bool) (a b : List Entry) :
    wsum W t sel (a ++ b) = wsum W t sel a + wsum W t sel b := by
  induction a with
  | nil => simp [wsum]
  | cons e es ih => simp only [List.cons_append, wsum, ih]; omega

/-- The window sum of one entry.

$$\forall W, t, \mathit{sel}, e:\quad \Sigma_W(\mathit{sel}, [e], t) = \begin{cases} e.\mathit{cost} & \mathit{sel}(e) \land \operatorname{inWin}(W, t, e.\mathit{time}) \\ 0 & \text{otherwise} \end{cases}$$
-/
theorem wsum_single (W t : Nat) (sel : Entry → Bool) (e : Entry) :
    wsum W t sel [e] = if sel e && inWin W t e.time then e.cost else 0 := by
  simp [wsum]

/-- A weaker selector sums to no more.

$$\forall W, t, \mathit{sel}, \mathit{sel}', \ell:\quad (\forall e \in \ell:\ \mathit{sel}(e) \Rightarrow \mathit{sel}'(e)) \Rightarrow \Sigma_W(\mathit{sel}, \ell, t) \le \Sigma_W(\mathit{sel}', \ell, t)$$
-/
theorem wsum_mono_sel (W t : Nat) (sel sel' : Entry → Bool) (l : List Entry)
    (h : ∀ e ∈ l, sel e = true → sel' e = true) : wsum W t sel l ≤ wsum W t sel' l := by
  induction l with
  | nil => simp [wsum]
  | cons e es ih =>
    simp only [wsum]
    have h1 := h e (by simp)
    have h2 := ih (fun x hx => h x (by simp [hx]))
    cases hs : sel e <;> cases hs' : sel' e <;> simp_all <;> split <;> omega

/-- Dropping entries does not increase a window sum.

$$\forall W, t, \mathit{sel}, p, \ell:\quad \Sigma_W(\mathit{sel}, [\,e \in \ell \mid p(e)\,], t) \le \Sigma_W(\mathit{sel}, \ell, t)$$
-/
theorem wsum_filter_le (W t : Nat) (sel p : Entry → Bool) (l : List Entry) :
    wsum W t sel (l.filter p) ≤ wsum W t sel l := by
  induction l with
  | nil => simp [wsum]
  | cons e es ih =>
    simp only [List.filter]
    cases p e <;> simp only [wsum] <;> omega

/-- When every entry is at or before $n$, a window ending later than $n$ holds no more than the one ending at $n$.

$$\forall W, t, n, \mathit{sel}, \ell:\quad (\forall e \in \ell:\ e.\mathit{time} \le n) \land n \le t \Rightarrow \Sigma_W(\mathit{sel}, \ell, t) \le \Sigma_W(\mathit{sel}, \ell, n)$$
-/
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

/-- The window sum of a kind splits into its charges and its corrections.

$$\forall W, t, k, \ell:\quad \Sigma_W(\operatorname{ofKind}(k), \ell, t) = \Sigma_W(\operatorname{chargedOf}(k), \ell, t) + \Sigma_W(\operatorname{corrOf}(k), \ell, t)$$
-/
theorem wsum_split (W t : Nat) (k : Kind) (l : List Entry) :
    wsum W t (ofKind k) l = wsum W t (chargedOf k) l + wsum W t (corrOf k) l := by
  induction l with
  | nil => simp [wsum]
  | cons e es ih =>
    rcases e with ⟨time, cost, kind, charged⟩
    simp only [wsum, ih, ofKind, chargedOf, corrOf]
    cases charged <;> simp <;> omega

/-- The charges of both kinds are the charges of ticks plus the charges of one-offs.

$$\forall W, t, \ell:\quad \Sigma_W(\operatorname{isCharge}, \ell, t) = \Sigma_W(\operatorname{chargedOf}(\mathrm{tick}), \ell, t) + \Sigma_W(\operatorname{chargedOf}(\mathrm{oneoff}), \ell, t)$$
-/
theorem wsum_charges (W t : Nat) (l : List Entry) :
    wsum W t isCharge l = wsum W t (chargedOf .tick) l + wsum W t (chargedOf .oneoff) l := by
  induction l with
  | nil => simp [wsum]
  | cons e es ih =>
    rcases e with ⟨time, cost, kind, charged⟩
    simp only [wsum, ih, isCharge, chargedOf]
    cases kind <;> simp <;> omega

/-! ## Headers -/

/-- The rate-limit facts of one response, as read from its header lines.

$$\mathrm{Headers} = (\mathit{status}, \mathit{remaining}, \mathit{reset}, \mathit{retryAfter}, \mathit{etag}) \in \mathbb{N} \times \mathbb{N}_\bot^3 \times \mathrm{String}_\bot$$
-/
structure Headers where
  status : Nat := 0
  remaining : Option Nat := none
  reset : Option Nat := none
  retryAfter : Option Nat := none
  etag : Option String := none
deriving Repr, DecidableEq

/-- A line with the debug prefix `< ` (httpretty's response marker) and the surrounding blanks removed.

$$\operatorname{unprefix}(s) = \begin{cases} \operatorname{trim}(s') & \operatorname{trim}(s) = \texttt{<}\,s' \\ \operatorname{trim}(s) & \text{otherwise} \end{cases}$$
-/
def unprefix (s : String) : String :=
  let t := s.trimAscii.toString
  if t.startsWith "<" then (t.drop 1).trimAscii.toString else t

/-- The status code of a status line `HTTP/<v> <code> <text>`; `none` for any other line.

$$\operatorname{statusOf}(s) = \begin{cases} n & \operatorname{unprefix}(s) \text{ starts with } \texttt{HTTP/} \text{ and its 2nd non-empty } \texttt{␣}\text{-separated token } c \text{ has } \mathrm{toNat?}(c) = n \\ \bot & \text{otherwise (no such token, or } \mathrm{toNat?}(c) = \bot\text{)} \end{cases}$$

Here toNat? is Lean's `String.toNat?`, which reads decimal digits and also accepts `_` separators (`1_000` gives 1000).
-/
def statusOf (s : String) : Option Nat :=
  let t := unprefix s
  if t.startsWith "HTTP/" then
    match (t.splitOn " ").filter (· ≠ "") with
    | _ :: code :: _ => code.toNat?
    | _ => none
  else none

/-- A header line `Name: value` as (lower-case name, trimmed value); `none` for a line without a colon.

$$\operatorname{headerOf}(s) = \begin{cases} (\operatorname{lower}(\operatorname{trim}(a)), \operatorname{trim}(b)) & \operatorname{unprefix}(s) = a \mathbin{+\!\!+} \texttt{:} \mathbin{+\!\!+} b,\ \texttt{:} \notin a \\ \bot & \text{otherwise} \end{cases}$$
-/
def headerOf (s : String) : Option (String × String) :=
  match (unprefix s).splitOn ":" with
  | name :: rest@(_ :: _) =>
    some (name.trimAscii.toString.toLower, (":".intercalate rest).trimAscii.toString)
  | _ => none

/-- Fold one line into the headers read so far; a later line overrides an earlier one.

$$\operatorname{readLine}(h, s) = \begin{cases} h[\mathit{status} := n] & \operatorname{statusOf}(s) = n \\ h[\mathit{remaining} := v] & \operatorname{headerOf}(s) = (\texttt{x-ratelimit-remaining}, v),\ v \in \mathbb{N} \\ h[\mathit{reset} := v] & \operatorname{headerOf}(s) = (\texttt{x-ratelimit-reset}, v),\ v \in \mathbb{N} \\ h[\mathit{retryAfter} := v] & \operatorname{headerOf}(s) = (\texttt{retry-after}, v),\ v \in \mathbb{N} \\ h[\mathit{etag} := v] & \operatorname{headerOf}(s) = (\texttt{etag}, v) \\ h & \text{otherwise} \end{cases}$$
-/
def readLine (h : Headers) (s : String) : Headers :=
  match statusOf s with
  | some n => { h with status := n }
  | none =>
    match headerOf s with
    | some ("x-ratelimit-remaining", v) => match v.toNat? with | some n => { h with remaining := some n } | none => h
    | some ("x-ratelimit-reset", v) => match v.toNat? with | some n => { h with reset := some n } | none => h
    | some ("retry-after", v) => match v.toNat? with | some n => { h with retryAfter := some n } | none => h
    | some ("etag", v) => { h with etag := some v }
    | _ => h

/-- The headers of a trace (the last value of each field wins) and the number of responses in it (status lines).

$$\operatorname{parse}(\mathit{ls}) = \big(\operatorname{foldl}(\operatorname{readLine}, \mathbf{0}, \mathit{ls}),\ \lvert[\,s \in \mathit{ls} \mid \operatorname{statusOf}(s) \ne \bot\,]\rvert\big)$$
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
#guard parse [] = ({}, 0)

/-! ## State -/

/-- A run some waiter is waiting on: its id, its creation time, and the last tick that covered it.

$$\mathrm{Watch} = (\mathit{runId}, \mathit{createdAt}, \mathit{lastCovered}) \in \mathbb{N}^2 \times \mathbb{N}_\bot$$
-/
structure Watch where
  runId : Nat
  createdAt : Nat
  lastCovered : Option Nat := none
deriving Repr, DecidableEq

/-- The budget state shared by the machine: the clock, the ledger, the last seen headers, the retry and failure
state, the watched runs, the last tick, the call in flight, and the pages one tick needs.

$$\mathrm{State} = (\mathit{now}, \ell, \mathit{rem}, \mathit{reset}, \mathit{retryUntil}, \mathit{fails}, \mathit{etag}, \mathit{watched}, \mathit{lastTick}, \mathit{pending}, \mathit{pages}) \in \mathbb{N} \times \mathrm{Entry}^{*} \times \mathbb{N}_\bot^2 \times \mathbb{N}^2 \times \mathrm{String}_\bot \times \mathrm{Watch}^{*} \times \mathbb{N}_\bot \times (\mathrm{Kind} \times \mathbb{N})_\bot \times \mathbb{N}$$
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
deriving Repr, DecidableEq

/-- The empty state at time $t$.

$$\operatorname{init}(t) = (t, [\,], \bot, \bot, 0, 0, \bot, [\,], \bot, \bot, 1)$$
-/
def init (t : Nat) : State := { now := t }

/-! ## Guards and costs -/

/-- Do the last seen headers leave room: remaining unknown, above the floor, or the reset already passed?

$$\operatorname{headroom}(L, s) \iff s.\mathit{rem} = \bot \lor \exists r:\ \big(s.\mathit{rem} = r \land (L.F < r \lor \exists T:\ s.\mathit{reset} = T \land T \le s.\mathit{now})\big)$$
-/
def headroom (L : Limits) (s : State) : Bool :=
  match s.remaining with
  | none => true
  | some r => decide (L.F < r) || (match s.reset with | some T => decide (T ≤ s.now) | none => false)

/-- The cost of one tick: the list cost per page times the pages (at least one).

$$\operatorname{tickCost}(L, s) = L.c_{\text{list}} \cdot \max(1, s.\mathit{pages})$$
-/
def tickCost (L : Limits) (s : State) : Nat := L.listCost * max 1 s.pages

/-- Integer ceiling division ($0$ when dividing by $0$, as Lean's `/`).

$$\operatorname{ceilDiv}(a, b) = \Big\lfloor \frac{a + b \mathbin{\dot-} 1}{b} \Big\rfloor \quad (\text{and } 0 \text{ for } b = 0)$$
-/
def ceilDiv (a b : Nat) : Nat := (a + b - 1) / b

#guard ceilDiv 3600 900 = 4 && ceilDiv 10 3 = 4 && ceilDiv 0 5 = 0 && ceilDiv 7 0 = 0

/-- The backoff after $k$ bare failures in a row: $b_0 \cdot 2^k$, at most $b_{\max}$.

$$\operatorname{backoff}(L, k) = \min(L.b_{\max},\ L.b_0 \cdot 2^k)$$
-/
def backoff (L : Limits) (k : Nat) : Nat := min L.backMax (L.back0 * 2 ^ k)

#guard (List.range 8).map (backoff defaults) = [60, 120, 240, 480, 960, 1920, 3600, 3600]

/-- The tick interval: the minimum interval, the interval that fits both tick shares, and, when the headers are known
and the reset is ahead, the interval that spreads the headroom above the floor until the reset.

$$P(L, s) = \max\!\Big(P_{\min},\ \Big\lceil \frac{W}{\max(1, \lfloor (B \mathbin{\dot-} R)/c \rfloor)} \Big\rceil,\ \Big\lceil \frac{W_1}{\max(1, \lfloor (B_1 \mathbin{\dot-} R_1)/c \rfloor)} \Big\rceil,\ p_3\Big), \quad c = \operatorname{tickCost}(L, s),\ x / 0 = 0,$$
$$p_3 = \begin{cases} \Big\lceil \dfrac{T - s.\mathit{now}}{\max(1, \lfloor (r \mathbin{\dot-} F)/c \rfloor)} \Big\rceil & s.\mathit{rem} = r,\ s.\mathit{reset} = T,\ s.\mathit{now} < T \\ 0 & \text{otherwise} \end{cases}$$
-/
def interval (L : Limits) (s : State) : Nat :=
  let c := tickCost L s
  let p2 := ceilDiv L.W (max 1 (share L .tick / c))
  let p2' := ceilDiv L.W1 (max 1 (share1 L .tick / c))
  let p3 := match s.remaining, s.reset with
    | some r, some T => if s.now < T then ceilDiv (T - s.now) (max 1 ((r - L.F) / c)) else 0
    | _, _ => 0
  max L.Pmin (max p2 (max p2' p3))

#guard interval defaults (init 0) = 30
-- 600 left above the floor for 3600 s at cost 2: 300 ticks, one per 12 s, so the minimum 30 s governs
#guard interval defaults { now := 0, remaining := some 1100, reset := some 3600 } = 30
-- 20 left above the floor for 3600 s: 10 ticks, one per 360 s
#guard interval defaults { now := 0, remaining := some 520, reset := some 3600 } = 360

/-- Why a call waits or stops.

$$\mathrm{Reason} = \{\mathrm{failures}, \mathrm{idle}, \mathrm{tooBig}, \mathrm{retryAfter}, \mathrm{floor}, \mathrm{hour}, \mathrm{minute}, \mathrm{interval}\}$$
-/
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

/-- A decision: issue the call (kind, charged cost, the state with the charge booked), wait until a time, or stop.

$$\mathrm{Decision} = \mathrm{issue}(\mathrm{Kind}, \mathbb{N}, \mathrm{State}) \mid \mathrm{wait}(\mathbb{N}, \mathrm{Reason}) \mid \mathrm{stop}(\mathrm{Reason})$$
-/
inductive Decision where
  | issue (k : Kind) (cost : Nat) (s' : State)
  | wait (untilT : Nat) (why : Reason)
  | stop (why : Reason)
deriving Repr

/-- The earliest time a window frees enough room for cost $c$: the first expiry time $e.\mathit{time} + W$ after
$t$ of a ledger entry at which the window sum plus $c$ fits the cap, else $t + \max(1, W)$.

$$\operatorname{freeAt}(W, t, \mathit{sel}, \mathit{cap}, c, \ell) = \begin{cases} e.\mathit{time} + W & e = \text{the first } e \in \ell \text{ with } t < e.\mathit{time} + W \land \Sigma_W(\mathit{sel}, \ell, e.\mathit{time} + W) + c \le \mathit{cap} \\ t + \max(1, W) & \text{no such } e \end{cases}$$
-/
def freeAt (W t : Nat) (sel : Entry → Bool) (cap c : Nat) (l : List Entry) : Nat :=
  match l.find? (fun e => decide (t < e.time + W) && decide (wsum W (e.time + W) sel l + c ≤ cap)) with
  | some e => e.time + W
  | none => t + max 1 W

/-- When the floor guard blocks: the reset if it is ahead, else $b_0$ (at least 1 s) from now.

$$\operatorname{floorUntil}(L, s) = \begin{cases} T & s.\mathit{reset} = T \land s.\mathit{now} < T \\ s.\mathit{now} + \max(1, L.b_0) & \text{otherwise} \end{cases}$$
-/
def floorUntil (L : Limits) (s : State) : Nat :=
  match s.reset with
  | some T => if s.now < T then T else s.now + max 1 L.back0
  | none => s.now + max 1 L.back0

/-- Charge a call of kind $k$ and cost $c$, first match wins: stop after `maxFails` bare failures; stop when $c$
exceeds a share (it could never go); wait for `retryUntil`; wait while the floor guard blocks; wait while the hour
or the minute share has no room for $c$; else issue, booking $(\mathit{now}, c, k, \text{charged})$.

$$\operatorname{charge}(L, s, k, c) = \begin{cases} \mathrm{stop}(\mathrm{failures}) & L.m \le s.\mathit{fails} \\ \mathrm{stop}(\mathrm{tooBig}) & \text{else if } c > \operatorname{share}(L, k) \lor c > \operatorname{share}_1(L, k) \\ \mathrm{wait}(s.\mathit{retryUntil}, \mathrm{retryAfter}) & \text{else if } s.\mathit{now} < s.\mathit{retryUntil} \\ \mathrm{wait}(\operatorname{floorUntil}(L, s), \mathrm{floor}) & \text{else if } \lnot\operatorname{headroom}(L, s) \\ \mathrm{wait}(\operatorname{freeAt}(W, \mathit{now}, \operatorname{ofKind}(k), \operatorname{share}(L, k), c, \ell), \mathrm{hour}) & \text{else if } \Sigma_W(\operatorname{ofKind}(k), \ell, \mathit{now}) + c > \operatorname{share}(L, k) \\ \mathrm{wait}(\operatorname{freeAt}(W_1, \mathit{now}, \operatorname{ofKind}(k), \operatorname{share}_1(L, k), c, \ell), \mathrm{minute}) & \text{else if } \Sigma_{W_1}(\operatorname{ofKind}(k), \ell, \mathit{now}) + c > \operatorname{share}_1(L, k) \\ \mathrm{issue}\big(k, c, s[\ell := \ell \mathbin{+\!\!+} [(\mathit{now}, c, k, \top)],\ \mathit{pending} := (k, c)]\big) & \text{otherwise} \end{cases} \quad \text{where } \ell = s.\ell,\ \mathit{now} = s.\mathit{now}$$
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

/-- `reserve`: may a one-off call of cost $c$ go now? It is charged at least 1 request.

$$\operatorname{reserve}(L, s, c) = \operatorname{charge}(L, s, \mathrm{oneoff}, \max(1, c))$$
-/
def reserve (L : Limits) (s : State) (c : Nat) : Decision := charge L s .oneoff (max 1 c)

/-- Mark a tick at `now`: the last tick, and every watched run covered.

$$\operatorname{cover}(s) = s[\mathit{lastTick} := s.\mathit{now},\ \mathit{watched} := [\,w[\mathit{lastCovered} := s.\mathit{now}] \mid w \in s.\mathit{watched}\,]]$$
-/
def cover (s : State) : State :=
  { s with lastTick := some s.now, watched := s.watched.map fun w => { w with lastCovered := some s.now } }

/-- Tick now if the charge allows it, covering every watched run.

$$\operatorname{tickNow}(L, s) = \begin{cases} \mathrm{issue}(k, c, \operatorname{cover}(s')) & \operatorname{charge}(L, s, \mathrm{tick}, \operatorname{tickCost}(L, s)) = \mathrm{issue}(k, c, s') \\ d & \operatorname{charge}(L, s, \mathrm{tick}, \operatorname{tickCost}(L, s)) = d \text{ otherwise} \end{cases}$$
-/
def tickNow (L : Limits) (s : State) : Decision :=
  match charge L s .tick (tickCost L s) with
  | .issue k c s' => .issue k c (cover s')
  | d => d

/-- `next`: the poller's decision, first match wins: stop after `maxFails` failures; stop when nothing is watched;
wait until the last tick plus $P$; else tick now.

$$\operatorname{next}(L, s) = \begin{cases} \mathrm{stop}(\mathrm{failures}) & L.m \le s.\mathit{fails} \\ \mathrm{stop}(\mathrm{idle}) & \text{else if } s.\mathit{watched} = [\,] \\ \mathrm{wait}(t_0 + P(L, s), \mathrm{interval}) & \text{else if } s.\mathit{lastTick} = t_0 \land s.\mathit{now} < t_0 + P(L, s) \\ \operatorname{tickNow}(L, s) & \text{otherwise} \end{cases}$$
-/
def next (L : Limits) (s : State) : Decision :=
  if L.maxFails ≤ s.fails then .stop .failures
  else if s.watched = [] then .stop .idle
  else match s.lastTick with
    | some t0 => if s.now < t0 + interval L s then .wait (t0 + interval L s) .interval else tickNow L s
    | none => tickNow L s

/-- The oldest creation time among the watched runs: a tick lists the runs created since then
(`created>=…&per_page=100`), so one list call covers every watched run however many waiters there are.

$$\operatorname{since}(s) = \min_{w \in s.\mathit{watched}} w.\mathit{createdAt} \quad (\bot \text{ when nothing is watched})$$
-/
def since (s : State) : Option Nat := (s.watched.map (·.createdAt)).min?

/-! ## Responses and events -/

/-- Is the status a rate-limit refusal (403 or 429)?

$$\operatorname{refused}(n) \iff n \in \{403, 429\}$$
-/
def refused (n : Nat) : Bool := n == 403 || n == 429

/-- The time a response forbids calls until (0 for none): `now` plus its `retry-after`; its reset, on a refusal with
remaining 0; `now` plus the backoff, on a refusal with neither.

$$\operatorname{retryFrom}(L, s, h) = \max(u_a, u_z, u_b), \quad u_a = \begin{cases} s.\mathit{now} + a' & h.\mathit{retryAfter} = a' \\ 0 & \text{otherwise} \end{cases}, \quad u_z = \begin{cases} T & \operatorname{refused}(h.\mathit{status}) \land h.\mathit{rem} = 0 \land h.\mathit{reset} = T \\ 0 & \text{otherwise} \end{cases},$$
$$u_b = \begin{cases} s.\mathit{now} + \operatorname{backoff}(L, s.\mathit{fails}) & \operatorname{refused}(h.\mathit{status}) \land h.\mathit{retryAfter} = \bot \land \lnot(h.\mathit{rem} = 0 \land h.\mathit{reset} \ne \bot) \\ 0 & \text{otherwise} \end{cases}$$
-/
def retryFrom (L : Limits) (s : State) (h : Headers) : Nat :=
  let ua := match h.retryAfter with
    | some a => s.now + a
    | none => 0
  let uz := if refused h.status && h.remaining == some 0 then h.reset.getD 0 else 0
  let ub := if refused h.status && h.retryAfter.isNone && !(h.remaining == some 0 && h.reset.isSome) then
    s.now + backoff L s.fails else 0
  max ua (max uz ub)

/-- Fold a response into the state: book a correction when the call took more responses than it was charged;
keep each header field that is present; never lower `retryUntil`; count refusals in a row.

$$\begin{aligned} \operatorname{observe}(L, s, h, a) = s[\ & \ell := \ell \mathbin{+\!\!+} [(s.\mathit{now}, a \mathbin{\dot-} c, k, \bot) \mid c < a],\ \mathit{pending} := \bot, \\ & \mathit{rem} := h.\mathit{rem} \mathbin{?} s.\mathit{rem},\ \mathit{reset} := h.\mathit{reset} \mathbin{?} s.\mathit{reset},\ \mathit{etag} := h.\mathit{etag} \mathbin{?} s.\mathit{etag}, \\ & \mathit{retryUntil} := \max(s.\mathit{retryUntil}, \operatorname{retryFrom}(L, s, h)),\ \mathit{fails} := f\,], \\ (k, c) ={} & \begin{cases} p & s.\mathit{pending} = p \\ (\mathrm{oneoff}, 0) & s.\mathit{pending} = \bot \end{cases}, \qquad x \mathbin{?} y = \begin{cases} x & x \ne \bot \\ y & x = \bot \end{cases}, \\ f ={} & \begin{cases} s.\mathit{fails} + 1 & \operatorname{refused}(h.\mathit{status}) \\ 0 & \text{else if } 200 \le h.\mathit{status} < 400 \\ s.\mathit{fails} & \text{otherwise} \end{cases} \end{aligned}$$
-/
def observe (L : Limits) (s : State) (h : Headers) (actual : Nat) : State :=
  let p := s.pending.getD (.oneoff, 0)
  let ledger := if p.2 < actual then s.ledger ++ [⟨s.now, actual - p.2, p.1, false⟩] else s.ledger
  let fails := if refused h.status then s.fails + 1
    else if 200 ≤ h.status ∧ h.status < 400 then 0 else s.fails
  { s with ledger, pending := none,
           remaining := h.remaining <|> s.remaining, reset := h.reset <|> s.reset, etag := h.etag <|> s.etag,
           retryUntil := max s.retryUntil (retryFrom L s h), fails }

/-- The events that change the state without a call: the clock, a waiter registering or leaving a run, the pages a
tick needs, a response, and a manual resume after the poller stopped.

$$\mathrm{Event} = \mathrm{clock}(\mathbb{N}) \mid \mathrm{register}(\mathit{runId}, \mathit{createdAt}) \mid \mathrm{unregister}(\mathit{runId}) \mid \mathrm{pages}(\mathbb{N}) \mid \mathrm{response}(\mathrm{Headers}, \mathbb{N}) \mid \mathrm{resume}$$
-/
inductive Event where
  | clock (t : Nat)
  | register (runId createdAt : Nat)
  | unregister (runId : Nat)
  | pages (n : Nat)
  | response (h : Headers) (actual : Nat)
  | resume
deriving Repr

/-- Apply an event. The clock never goes back (`now := max(now, t)`) and drops ledger entries no window can see
again; a second waiter on a watched run changes nothing.

$$\begin{aligned} \operatorname{step}(L, s, \mathrm{clock}(t)) &= s[\mathit{now} := n,\ \ell := [\,e \in s.\ell \mid n < e.\mathit{time} + \max(W, W_1)\,]], \quad n = \max(s.\mathit{now}, t) \\ \operatorname{step}(L, s, \mathrm{register}(r, c)) &= \begin{cases} s & \exists w \in s.\mathit{watched}:\ w.\mathit{runId} = r \\ s[\mathit{watched} := s.\mathit{watched} \mathbin{+\!\!+} [(r, c, \bot)]] & \text{otherwise} \end{cases} \\ \operatorname{step}(L, s, \mathrm{unregister}(r)) &= s[\mathit{watched} := [\,w \in s.\mathit{watched} \mid w.\mathit{runId} \ne r\,]] \\ \operatorname{step}(L, s, \mathrm{pages}(n)) &= s[\mathit{pages} := \max(1, n)] \\ \operatorname{step}(L, s, \mathrm{response}(h, a)) &= \operatorname{observe}(L, s, h, a) \\ \operatorname{step}(L, s, \mathrm{resume}) &= s[\mathit{fails} := 0] \end{aligned}$$
-/
def step (L : Limits) (s : State) : Event → State
  | .clock t =>
    let n := max s.now t
    { s with now := n, ledger := s.ledger.filter fun e => decide (n < e.time + max L.W L.W1) }
  | .register r c =>
    if s.watched.any (·.runId == r) then s else { s with watched := s.watched ++ [⟨r, c, none⟩] }
  | .unregister r => { s with watched := s.watched.filter (·.runId != r) }
  | .pages n => { s with pages := max 1 n }
  | .response h a => observe L s h a
  | .resume => { s with fails := 0 }

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
-- one watched run: the first tick goes, and the next waits 30 s
#guard isIssue (next defaults (step defaults (init 100) (.register 7 90)))
#guard (match next defaults (step defaults (init 100) (.register 7 90)) with
  | .issue _ _ s' => waitOf (next defaults s') = some (130, .interval) | _ => false)
-- retry-after 60 at t = 100 blocks until 160
#guard waitOf (reserve defaults (observe defaults (init 100) { status := 403, retryAfter := some 60 } 1) 1) =
  some (160, .retryAfter)
-- remaining 0 with the reset at 900: the floor blocks until then
#guard waitOf (reserve defaults (observe defaults (init 100) { status := 403, remaining := some 0, reset := some 900 } 1) 1) =
  some (900, .retryAfter)
#guard waitOf (reserve defaults (observe defaults (init 100) { status := 200, remaining := some 500, reset := some 900 } 1) 1) =
  some (900, .floor)
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
#guard (step defaults (step defaults (init 0) (.register 7 0)) (.register 7 5)).watched = [⟨7, 0, none⟩]
#guard since (step defaults (step defaults (init 0) (.register 7 50)) (.register 8 20)) = some 20

/-! ## (e) The clock -/

/-- The clock never goes back: no event decreases `now`.

$$\forall L, s, e:\quad \operatorname{step}(L, s, e).\mathit{now} \ge s.\mathit{now}$$
-/
theorem clock_monotone (L : Limits) (s : State) (e : Event) : (step L s e).now ≥ s.now := by
  cases e with
  | clock t => simp only [step]; omega
  | register r c => simp only [step]; split <;> simp
  | response h a => simp [step, observe]
  | _ => simp [step]

/-- An issued charge keeps the clock, appends exactly the charge, and changes no guard field.

$$\forall L, s, k, c, k', c', s':\quad \operatorname{charge}(L, s, k, c) = \mathrm{issue}(k', c', s') \Rightarrow k' = k \land c' = c \land s'.\ell = s.\ell \mathbin{+\!\!+} [(s.\mathit{now}, c, k, \top)] \land s'.\mathit{now} = s.\mathit{now} \land s'.\mathit{retryUntil} = s.\mathit{retryUntil}$$
-/
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
and room for $c$ in both windows of its kind (corrections included).

$$\forall L, s, k, c, k', c', s':\quad \operatorname{charge}(L, s, k, c) = \mathrm{issue}(k', c', s') \Rightarrow s.\mathit{fails} < L.m \land s.\mathit{retryUntil} \le s.\mathit{now} \land \operatorname{headroom}(L, s) \land \Sigma_W(\operatorname{ofKind}(k), s.\ell, s.\mathit{now}) + c \le \operatorname{share}(L, k) \land \Sigma_{W_1}(\operatorname{ofKind}(k), s.\ell, s.\mathit{now}) + c \le \operatorname{share}_1(L, k)$$
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

$$\forall L, s, k, c, u, r:\quad \operatorname{charge}(L, s, k, c) = \mathrm{wait}(u, r) \Rightarrow s.\mathit{now} < u \land r \ne \mathrm{interval}$$
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

/-- `charge` never stops for a reason other than failures or a cost no share can hold.

$$\forall L, s, k, c, r:\quad \operatorname{charge}(L, s, k, c) = \mathrm{stop}(r) \Rightarrow (r = \mathrm{failures} \land L.m \le s.\mathit{fails}) \lor r = \mathrm{tooBig}$$
-/
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

/-- `headroom` spelled out.

$$\forall L, s:\quad \operatorname{headroom}(L, s) \iff s.\mathit{rem} = \bot \lor \exists r:\ s.\mathit{rem} = r \land \big(L.F < r \lor \exists T:\ s.\mathit{reset} = T \land T \le s.\mathit{now}\big)$$
-/
theorem headroom_iff (L : Limits) (s : State) :
    headroom L s = true ↔ s.remaining = none ∨
      ∃ r, s.remaining = some r ∧ (L.F < r ∨ ∃ T, s.reset = some T ∧ T ≤ s.now) := by
  unfold headroom
  cases hr : s.remaining <;> cases ht : s.reset <;> simp

/-- (b) A one-off call is issued only when `now` is at or after `retryUntil` and the headers leave room: remaining
unknown, above the floor $F$, or the reset already passed.

$$\forall L, s, c, k, c', s':\quad \operatorname{reserve}(L, s, c) = \mathrm{issue}(k, c', s') \Rightarrow s.\mathit{now} \ge s.\mathit{retryUntil} \land \Big(s.\mathit{rem} = \bot \lor \exists r:\ s.\mathit{rem} = r \land \big(r > F \lor \exists T:\ s.\mathit{reset} = T \land s.\mathit{now} \ge T\big)\Big)$$
-/
theorem no_issue_when_exhausted (L : Limits) (s : State) (c : Nat) (k : Kind) (c' : Nat) (s' : State)
    (h : reserve L s c = .issue k c' s') :
    s.retryUntil ≤ s.now ∧ (s.remaining = none ∨
      ∃ r, s.remaining = some r ∧ (L.F < r ∨ ∃ T, s.reset = some T ∧ T ≤ s.now)) := by
  have g := charge_issue_guards L s _ _ _ _ _ h
  exact ⟨g.2.1, (headroom_iff L s).1 g.2.2.1⟩

/-- The decisions of `next`: an issue is `tickNow`'s charge with the watched runs covered.

$$\forall L, s, k, c, s':\quad \operatorname{next}(L, s) = \mathrm{issue}(k, c, s') \Rightarrow \exists s'':\ \operatorname{charge}(L, s, \mathrm{tick}, \operatorname{tickCost}(L, s)) = \mathrm{issue}(k, c, s'') \land s' = \operatorname{cover}(s'')$$
-/
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

/-- (b) The poller ticks only under the same guards as `reserve`.

$$\forall L, s, k, c, s':\quad \operatorname{next}(L, s) = \mathrm{issue}(k, c, s') \Rightarrow s.\mathit{now} \ge s.\mathit{retryUntil} \land \Big(s.\mathit{rem} = \bot \lor \exists r:\ s.\mathit{rem} = r \land \big(r > F \lor \exists T:\ s.\mathit{reset} = T \land s.\mathit{now} \ge T\big)\Big)$$
-/
theorem next_no_issue_when_exhausted (L : Limits) (s : State) (k : Kind) (c : Nat) (s' : State)
    (h : next L s = .issue k c s') :
    s.retryUntil ≤ s.now ∧ (s.remaining = none ∨
      ∃ r, s.remaining = some r ∧ (L.F < r ∨ ∃ T, s.reset = some T ∧ T ≤ s.now)) := by
  obtain ⟨s'', hc, _⟩ := next_issue L s k c s' h
  have g := charge_issue_guards L s _ _ _ _ _ hc
  exact ⟨g.2.1, (headroom_iff L s).1 g.2.2.1⟩

/-! ## Reachable states -/

/-- The states reachable from $s_0$: events, issued charges of any kind and cost, and issued ticks with their cover
(a superset of what `reserve` and `next` do, so every theorem over it holds for them).

$$\begin{aligned} & s_0 \in \operatorname{Reach}(L, s_0) \\ & s \in \operatorname{Reach}(L, s_0) \Rightarrow \operatorname{step}(L, s, e) \in \operatorname{Reach}(L, s_0) \\ & s \in \operatorname{Reach}(L, s_0) \land \operatorname{charge}(L, s, k, c) = \mathrm{issue}(k, c, s') \Rightarrow s' \in \operatorname{Reach}(L, s_0) \\ & s \in \operatorname{Reach}(L, s_0) \land \operatorname{charge}(L, s, \mathrm{tick}, c) = \mathrm{issue}(\mathrm{tick}, c, s') \Rightarrow \operatorname{cover}(s') \in \operatorname{Reach}(L, s_0) \end{aligned}$$
-/
inductive Reach (L : Limits) (s0 : State) : State → Prop where
  | refl : Reach L s0 s0
  | step {s : State} (e : Event) : Reach L s0 s → Reach L s0 (step L s e)
  | charge {s s' : State} {k : Kind} {c : Nat} : Reach L s0 s → charge L s k c = .issue k c s' → Reach L s0 s'
  | cover {s s' : State} {c : Nat} : Reach L s0 s → charge L s .tick c = .issue .tick c s' → Reach L s0 (cover s')

/-- An issued `reserve` stays reachable.

$$\forall L, s_0, s, c, k, c', s':\quad s \in \operatorname{Reach}(L, s_0) \land \operatorname{reserve}(L, s, c) = \mathrm{issue}(k, c', s') \Rightarrow s' \in \operatorname{Reach}(L, s_0)$$
-/
theorem Reach.reserve {L : Limits} {s0 s : State} {c : Nat} {k : Kind} {c' : Nat} {s' : State}
    (hr : Reach L s0 s) (h : Fw.Ci.Budget.reserve L s c = .issue k c' s') : Reach L s0 s' := by
  have hi := charge_issue L s _ _ _ _ _ h
  obtain ⟨rfl, rfl, -⟩ := hi
  exact .charge hr h

/-- An issued `next` stays reachable.

$$\forall L, s_0, s, k, c, s':\quad s \in \operatorname{Reach}(L, s_0) \land \operatorname{next}(L, s) = \mathrm{issue}(k, c, s') \Rightarrow s' \in \operatorname{Reach}(L, s_0)$$
-/
theorem Reach.next {L : Limits} {s0 s : State} {k : Kind} {c : Nat} {s' : State}
    (hr : Reach L s0 s) (h : Fw.Ci.Budget.next L s = .issue k c s') : Reach L s0 s' := by
  obtain ⟨s'', hc, rfl⟩ := next_issue L s k c s' h
  have hi := charge_issue L s _ _ _ _ _ hc
  obtain ⟨rfl, rfl, -⟩ := hi
  exact .cover hr hc

/-! ## (a) The window bound -/

/-- The invariant: every ledger entry is at or before `now`, and for each kind and every time $t$ the charges in
both windows stay within the shares.

$$\operatorname{Inv}(L, s) \iff (\forall e \in s.\ell:\ e.\mathit{time} \le s.\mathit{now}) \land \forall k, t:\ \Sigma_W(\operatorname{chargedOf}(k), s.\ell, t) \le \operatorname{share}(L, k) \land \Sigma_{W_1}(\operatorname{chargedOf}(k), s.\ell, t) \le \operatorname{share}_1(L, k)$$
-/
def Inv (L : Limits) (s : State) : Prop :=
  (∀ e ∈ s.ledger, e.time ≤ s.now) ∧
    ∀ k t, wsum L.W t (chargedOf k) s.ledger ≤ share L k ∧ wsum L.W1 t (chargedOf k) s.ledger ≤ share1 L k

/-- Appending an entry the selector skips leaves the window sum unchanged.

$$\forall W, t, \mathit{sel}, \ell, e:\quad \lnot\mathit{sel}(e) \Rightarrow \Sigma_W(\mathit{sel}, \ell \mathbin{+\!\!+} [e], t) = \Sigma_W(\mathit{sel}, \ell, t)$$
-/
theorem wsum_append_skip (W t : Nat) (sel : Entry → Bool) (l : List Entry) (e : Entry) (h : sel e = false) :
    wsum W t sel (l ++ [e]) = wsum W t sel l := by
  rw [wsum_append, wsum_single]; simp [h]

/-- Appending a charge $(n, c, k)$ at the latest time $n$ keeps the charges of kind $k$ within the cap, when the
window ending at $n$ had room for $c$ (corrections included).

$$\forall W, \mathit{cap}, k, \ell, n, c:\quad (\forall e \in \ell:\ e.\mathit{time} \le n) \land (\forall t:\ \Sigma_W(\operatorname{chargedOf}(k), \ell, t) \le \mathit{cap}) \land \Sigma_W(\operatorname{ofKind}(k), \ell, n) + c \le \mathit{cap} \Rightarrow \forall t:\ \Sigma_W(\operatorname{chargedOf}(k), \ell \mathbin{+\!\!+} [(n, c, k, \top)], t) \le \mathit{cap}$$
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

/-- The invariant holds for the empty state at any time.

$$\forall L, t:\quad \operatorname{Inv}(L, \operatorname{init}(t))$$
-/
theorem inv_init (L : Limits) (t : Nat) : Inv L (init t) := by
  refine ⟨by simp [init], fun k t => ?_⟩
  simp [init, wsum]

/-- Every event keeps the invariant.

$$\forall L, s, e:\quad \operatorname{Inv}(L, s) \Rightarrow \operatorname{Inv}(L, \operatorname{step}(L, s, e))$$
-/
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

/-- An issued charge keeps the invariant.

$$\forall L, s, k, c, s':\quad \operatorname{Inv}(L, s) \land \operatorname{charge}(L, s, k, c) = \mathrm{issue}(k, c, s') \Rightarrow \operatorname{Inv}(L, s')$$
-/
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

/-- The invariant holds in every state reachable from a state where it holds.

$$\forall L, s_0, s:\quad \operatorname{Inv}(L, s_0) \land s \in \operatorname{Reach}(L, s_0) \Rightarrow \operatorname{Inv}(L, s)$$
-/
theorem inv_reach (L : Limits) (s0 s : State) (h0 : Inv L s0) (hr : Reach L s0 s) : Inv L s := by
  induction hr with
  | refl => exact h0
  | step e _ ih => exact inv_step L _ e ih
  | charge _ hc ih => exact inv_charge L _ _ _ _ ih hc
  | cover _ hc ih =>
    have := inv_charge L _ _ _ _ ih hc
    exact this

/-- (a) In every state reachable from an empty state, for each kind and every time $t$, the charged requests in the
window $(t - W, t]$ stay within the hourly share and those in $(t - W_1, t]$ within the per-minute share. No
hypothesis mentions the watched runs, so this holds for every number $N$ of waiters.

$$\forall L, t_0, s, k, t:\quad s \in \operatorname{Reach}(L, \operatorname{init}(t_0)) \Rightarrow \Sigma_W(\operatorname{chargedOf}(k), s.\ell, t) \le \operatorname{share}(L, k) \land \Sigma_{W_1}(\operatorname{chargedOf}(k), s.\ell, t) \le \operatorname{share}_1(L, k)$$
-/
theorem window_bound (L : Limits) (t0 : Nat) (s : State) (hr : Reach L (init t0) s) (k : Kind) (t : Nat) :
    wsum L.W t (chargedOf k) s.ledger ≤ share L k ∧ wsum L.W1 t (chargedOf k) s.ledger ≤ share1 L k :=
  (inv_reach L _ s (inv_init L t0) hr).2 k t

/-- (a) The total: with $R \le B$ and $R_1 \le B_1$, all charged requests in any 3600 s window stay within $B$ and
those in any 60 s window within $B_1$.

$$\forall L, t_0, s, t:\quad L.R \le L.B \land L.R_1 \le L.B_1 \land s \in \operatorname{Reach}(L, \operatorname{init}(t_0)) \Rightarrow \Sigma_W(\operatorname{isCharge}, s.\ell, t) \le L.B \land \Sigma_{W_1}(\operatorname{isCharge}, s.\ell, t) \le L.B_1$$
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

$$\forall L, t_0, s, k, t:\quad s \in \operatorname{Reach}(L, \operatorname{init}(t_0)) \Rightarrow \Sigma_W(\operatorname{ofKind}(k), s.\ell, t) \le \operatorname{share}(L, k) + \Sigma_W(\operatorname{corrOf}(k), s.\ell, t) \land \Sigma_{W_1}(\operatorname{ofKind}(k), s.\ell, t) \le \operatorname{share}_1(L, k) + \Sigma_{W_1}(\operatorname{corrOf}(k), s.\ell, t)$$
$$\forall L, s, k, c, s':\quad \operatorname{charge}(L, s, k, c) = \mathrm{issue}(k, c, s') \Rightarrow \Sigma_W(\operatorname{ofKind}(k), s.\ell, s.\mathit{now}) + c \le \operatorname{share}(L, k)$$
-/
theorem overrun_absorbed (L : Limits) (t0 : Nat) (s : State) (hr : Reach L (init t0) s) (k : Kind) (t : Nat) :
    (wsum L.W t (ofKind k) s.ledger ≤ share L k + wsum L.W t (corrOf k) s.ledger ∧
      wsum L.W1 t (ofKind k) s.ledger ≤ share1 L k + wsum L.W1 t (corrOf k) s.ledger) ∧
    ∀ (s1 : State) (c : Nat) (s' : State), charge L s1 k c = .issue k c s' →
      wsum L.W s1.now (ofKind k) s1.ledger + c ≤ share L k := by
  have a := window_bound L t0 s hr k t
  rw [wsum_split, wsum_split]
  refine ⟨⟨by omega, by omega⟩, fun s1 c s' hc => (charge_issue_guards L s1 k c k c s' hc).2.2.2.1⟩

/-- (a′) Waiters cost nothing: registering or unregistering a run leaves the ledger and the clock as they are.

$$\forall L, s, r, c:\quad \operatorname{step}(L, s, \mathrm{register}(r, c)).\ell = s.\ell \land \operatorname{step}(L, s, \mathrm{unregister}(r)).\ell = s.\ell \land \operatorname{step}(L, s, \mathrm{register}(r, c)).\mathit{now} = s.\mathit{now}$$
-/
theorem register_free (L : Limits) (s : State) (r c : Nat) :
    (step L s (.register r c)).ledger = s.ledger ∧ (step L s (.unregister r)).ledger = s.ledger ∧
      (step L s (.register r c)).now = s.now := by
  simp only [step]; split <;> simp

/-- (a′) Another waiter on a run already watched changes nothing: $N$ waiters on one run are one entry.

$$\forall L, s, r, c:\quad (\exists w \in s.\mathit{watched}:\ w.\mathit{runId} = r) \Rightarrow \operatorname{step}(L, s, \mathrm{register}(r, c)) = s$$
-/
theorem register_dup (L : Limits) (s : State) (r c : Nat) (h : ∃ w ∈ s.watched, w.runId = r) :
    step L s (.register r c) = s := by
  obtain ⟨w, hw, hr⟩ := h
  have : s.watched.any (·.runId == r) = true := List.any_eq_true.2 ⟨w, hw, by simp [hr]⟩
  simp [step, this]

/-- (a″) A tick's cost and interval do not depend on the watched runs: one list call covers them all.

$$\forall L, s, \mathit{ws}:\quad \operatorname{tickCost}(L, s[\mathit{watched} := \mathit{ws}]) = \operatorname{tickCost}(L, s) \land P(L, s[\mathit{watched} := \mathit{ws}]) = P(L, s)$$
-/
theorem tick_cost_indep_N (L : Limits) (s : State) (ws : List Watch) :
    tickCost L { s with watched := ws } = tickCost L s ∧ interval L { s with watched := ws } = interval L s := by
  constructor <;> rfl

/-! ## (b′, b″) Guards persist, and the backoff -/

/-- No event or issued charge lowers `retryUntil`.

$$\forall L, s_0, s:\quad s \in \operatorname{Reach}(L, s_0) \Rightarrow s_0.\mathit{retryUntil} \le s.\mathit{retryUntil}$$
-/
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
      | _ => simp [step]
    omega
  | charge _ hc ih =>
    have := (charge_issue L _ _ _ _ _ _ hc).2.2.2.2; omega
  | cover _ hc ih =>
    have := (charge_issue L _ _ _ _ _ _ hc).2.2.2.2; simp only [cover]; omega

/-- A response pushes `retryUntil` to at least `now` plus its `retry-after`, and a refusal with remaining 0 to at
least its reset.

$$\forall L, s, h, a:\quad (\forall a':\ h.\mathit{retryAfter} = a' \Rightarrow s.\mathit{now} + a' \le \operatorname{observe}(L, s, h, a).\mathit{retryUntil}) \land (\forall T:\ \operatorname{refused}(h.\mathit{status}) \land h.\mathit{rem} = 0 \land h.\mathit{reset} = T \Rightarrow T \le \operatorname{observe}(L, s, h, a).\mathit{retryUntil})$$
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

/-- (b′) After a response with `retry-after` $a'$ at time $t_0$, or a refusal with remaining 0 and reset $T$, no
call is issued along any later trace before $t_0 + a'$, or before $T$.

$$\forall L, s, h, a, s_2, k, c, s':\quad s_2 \in \operatorname{Reach}(L, \operatorname{step}(L, s, \mathrm{response}(h, a))) \land \operatorname{charge}(L, s_2, k, c) = \mathrm{issue}(k, c, s') \Rightarrow (\forall a':\ h.\mathit{retryAfter} = a' \Rightarrow s.\mathit{now} + a' \le s_2.\mathit{now}) \land (\forall T:\ \operatorname{refused}(h.\mathit{status}) \land h.\mathit{rem} = 0 \land h.\mathit{reset} = T \Rightarrow T \le s_2.\mathit{now})$$
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

/-- (b″) The backoff is at least $b_0$ (when $b_0 \le b_{\max}$).

$$\forall L, k:\quad L.b_0 \le L.b_{\max} \Rightarrow L.b_0 \le \operatorname{backoff}(L, k)$$
-/
theorem backoff_ge (L : Limits) (k : Nat) (h : L.back0 ≤ L.backMax) : L.back0 ≤ backoff L k := by
  unfold backoff
  have : L.back0 ≤ L.back0 * 2 ^ k := Nat.le_mul_of_pos_right _ (Nat.two_pow_pos k)
  omega

/-- (b″) The backoff never shrinks as failures accumulate.

$$\forall L, k, k':\quad k \le k' \Rightarrow \operatorname{backoff}(L, k) \le \operatorname{backoff}(L, k')$$
-/
theorem backoff_mono (L : Limits) (k k' : Nat) (h : k ≤ k') : backoff L k ≤ backoff L k' := by
  unfold backoff
  have : L.back0 * 2 ^ k ≤ L.back0 * 2 ^ k' := Nat.mul_le_mul_left _ (Nat.pow_le_pow_right (by omega) h)
  omega

/-- (b″) After `maxFails` failures in a row both decisions stop.

$$\forall L, s, c:\quad L.m \le s.\mathit{fails} \Rightarrow \operatorname{reserve}(L, s, c) = \mathrm{stop}(\mathrm{failures}) \land \operatorname{next}(L, s) = \mathrm{stop}(\mathrm{failures})$$
-/
theorem stop_after_fails (L : Limits) (s : State) (c : Nat) (h : L.maxFails ≤ s.fails) :
    reserve L s c = .stop .failures ∧ next L s = .stop .failures := by
  simp [reserve, charge, next, h]

/-! ## (c) Liveness -/

/-- (c) While the guards allow, the shares have room and the interval has passed, `next` ticks, and the tick covers
every watched run at `now`.

$$\begin{aligned} \forall L, s:\quad & s.\mathit{fails} < L.m \land s.\mathit{watched} \ne [\,] \land (\forall t_0:\ s.\mathit{lastTick} = t_0 \Rightarrow t_0 + P(L, s) \le s.\mathit{now}) \land s.\mathit{retryUntil} \le s.\mathit{now} \land \operatorname{headroom}(L, s) \\ & \land\ c \le \operatorname{share}(L, \mathrm{tick}) \land c \le \operatorname{share}_1(L, \mathrm{tick}) \land \Sigma_W(\operatorname{ofKind}(\mathrm{tick}), s.\ell, s.\mathit{now}) + c \le \operatorname{share}(L, \mathrm{tick}) \land \Sigma_{W_1}(\operatorname{ofKind}(\mathrm{tick}), s.\ell, s.\mathit{now}) + c \le \operatorname{share}_1(L, \mathrm{tick}) \\ & \Rightarrow \exists s':\ \operatorname{next}(L, s) = \mathrm{issue}(\mathrm{tick}, c, s') \land s'.\mathit{lastTick} = s.\mathit{now} \land \forall w \in s'.\mathit{watched}:\ w.\mathit{lastCovered} = s.\mathit{now} \\ & \text{where } c = \operatorname{tickCost}(L, s) \end{aligned}$$
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

/-- (c) The only other way `next` waits on the interval: it waits until the last tick plus $P$, which is after `now`
and at most $P$ after `now` when the last tick is not in the future.

$$\forall L, s, u:\quad \operatorname{next}(L, s) = \mathrm{wait}(u, \mathrm{interval}) \Rightarrow \exists t_0:\ s.\mathit{lastTick} = t_0 \land u = t_0 + P(L, s) \land s.\mathit{now} < u \land (t_0 \le s.\mathit{now} \Rightarrow u \le s.\mathit{now} + P(L, s))$$
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

/-- No wait is in the past: every `wait` from `reserve` or `next` is strictly after `now`.

$$\forall L, s, c, u, r:\quad (\operatorname{reserve}(L, s, c) = \mathrm{wait}(u, r) \Rightarrow s.\mathit{now} < u) \land (\operatorname{next}(L, s) = \mathrm{wait}(u, r) \Rightarrow s.\mathit{now} < u)$$
-/
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

/-- Times spaced at least $P$ apart, in order.

$$\operatorname{spaced}(P, [x_1, \dots, x_n]) \iff \forall i,\ 1 \le i < n:\ x_i + P \le x_{i+1} \quad (\text{true for } n \le 1)$$
-/
def spaced (P : Nat) : List Nat → Bool
  | x :: y :: r => decide (x + P ≤ y) && spaced P (y :: r)
  | _ => true

/-- The ceiling division times the divisor reaches the dividend.

$$\forall a, b:\quad 0 < b \Rightarrow a \le \operatorname{ceilDiv}(a, b) \cdot b$$
-/
theorem le_ceilDiv_mul (a b : Nat) (hb : 0 < b) : a ≤ ceilDiv a b * b := by
  unfold ceilDiv
  have := Nat.lt_mul_div_succ (a + b - 1) hb
  rw [Nat.mul_succ, Nat.mul_comm] at this
  omega

/-- The span of spaced times: $n$ steps of at least $P$ after the first one.

$$\forall P, x, r, h:\quad \operatorname{spaced}(P, x :: r) \land (\forall z \in x :: r:\ z \le h) \Rightarrow \lvert r \rvert \cdot P + x \le h$$
-/
theorem spaced_span (P : Nat) (x : Nat) (r : List Nat) (hi : Nat) (hs : spaced P (x :: r) = true)
    (hle : ∀ z ∈ x :: r, z ≤ hi) : r.length * P + x ≤ hi := by
  induction r generalizing x with
  | nil => simpa using hle x (by simp)
  | cons y r ih =>
    simp only [spaced, Bool.and_eq_true, decide_eq_true_eq] at hs
    have := ih y hs.2 (fun z hz => hle z (List.mem_cons_of_mem _ hz))
    simp only [List.length_cons, Nat.succ_mul]
    omega

/-- At most $\lceil W/P \rceil$ times spaced at least $P$ apart fit in a window $(t - W, t]$.

$$\forall P, W, t, \mathit{xs}:\quad 0 < P \land \operatorname{spaced}(P, \mathit{xs}) \land (\forall z \in \mathit{xs}:\ \operatorname{inWin}(W, t, z)) \Rightarrow \lvert \mathit{xs} \rvert \le \operatorname{ceilDiv}(W, P)$$
-/
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

/-- An interval at least $\lceil W / \max(1, \lfloor \mathit{cap}/c \rfloor) \rceil$ fits $\lceil W/P \rceil$ calls of
cost $c$ into the cap.

$$\forall W, \mathit{cap}, c, P:\quad 0 < c \le \mathit{cap} \land 0 < P \land \operatorname{ceilDiv}(W, \max(1, \lfloor \mathit{cap}/c \rfloor)) \le P \Rightarrow \operatorname{ceilDiv}(W, P) \cdot c \le \mathit{cap}$$
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

/-- (d) The interval formula is sound: for any $P \ge \operatorname{interval}(L, s)$ (and $P > 0$), ticks of cost $c$ spaced at least $P$
apart fit the hourly tick share in every window $(t - W, t]$, the per-minute tick share in every window
$(t - W_1, t]$, and, with remaining $r$ and the reset $T$ ahead, the headroom $r \mathbin{\dot-} F$ in $[\mathit{now}, T)$.

$$\begin{aligned} \forall L, s, P:\quad & \operatorname{interval}(L, s) \le P \land 0 < P \land 0 < c \Rightarrow \\ & \big(c \le \operatorname{share}(L, \mathrm{tick}) \Rightarrow \forall \mathit{xs}, t:\ \operatorname{spaced}(P, \mathit{xs}) \land (\forall z \in \mathit{xs}:\ \operatorname{inWin}(W, t, z)) \Rightarrow \lvert \mathit{xs} \rvert \cdot c \le \operatorname{share}(L, \mathrm{tick})\big) \\ & \land \big(c \le \operatorname{share}_1(L, \mathrm{tick}) \Rightarrow \forall \mathit{xs}, t:\ \operatorname{spaced}(P, \mathit{xs}) \land (\forall z \in \mathit{xs}:\ \operatorname{inWin}(W_1, t, z)) \Rightarrow \lvert \mathit{xs} \rvert \cdot c \le \operatorname{share}_1(L, \mathrm{tick})\big) \\ & \land \big(\forall r, T:\ s.\mathit{rem} = r \land s.\mathit{reset} = T \land s.\mathit{now} < T \land c \le r \mathbin{\dot-} F \Rightarrow \forall \mathit{xs}:\ \operatorname{spaced}(P, \mathit{xs}) \land (\forall z \in \mathit{xs}:\ s.\mathit{now} \le z < T) \Rightarrow \lvert \mathit{xs} \rvert \cdot c \le r \mathbin{\dot-} F\big) \\ & \text{where } c = \operatorname{tickCost}(L, s) \end{aligned}$$
-/
theorem interval_sound (L : Limits) (s : State) (P : Nat) (hP : interval L s ≤ P) (hP0 : 0 < P)
    (hc0 : 0 < tickCost L s) :
    (tickCost L s ≤ share L .tick → ∀ xs t, spaced P xs = true → (∀ z ∈ xs, inWin L.W t z = true) →
      xs.length * tickCost L s ≤ share L .tick) ∧
    (tickCost L s ≤ share1 L .tick → ∀ xs t, spaced P xs = true → (∀ z ∈ xs, inWin L.W1 t z = true) →
      xs.length * tickCost L s ≤ share1 L .tick) ∧
    (∀ r T, s.remaining = some r → s.reset = some T → s.now < T → tickCost L s ≤ r - L.F →
      ∀ xs, spaced P xs = true → (∀ z ∈ xs, s.now ≤ z ∧ z < T) → xs.length * tickCost L s ≤ r - L.F) := by
  unfold interval at hP
  simp only at hP
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

/-- The old scheme's requests per window: $N$ agents, each polling on its own at interval $P$ with cost $c$.

$$\operatorname{oldRate}(L, N, c, P) = N \cdot c \cdot \operatorname{ceilDiv}(W, P)$$
-/
def oldRate (L : Limits) (N c P : Nat) : Nat := N * (c * ceilDiv L.W P)

#guard oldRate defaults 12 2 30 = 2880      -- 12 agents, `gh run view` every 30 s
#guard oldRate defaults 1 4 3 = 4800        -- one `gh run watch` at 3 s with one job
#guard oldRate defaults 12 2 30 + oldRate defaults 1 4 3 > 5000   -- the 10-18 incident
#guard ceilDiv defaults.W 30 * defaults.listCost = 240               -- the shared poller at 30 s, for any N

/-- (d′) The old scheme grows linearly in the number of agents.

$$\forall L, N, c, P:\quad \operatorname{oldRate}(L, N, c, P) = N \cdot \operatorname{oldRate}(L, 1, c, P)$$
-/
theorem oldRate_linear (L : Limits) (N c P : Nat) : oldRate L N c P = N * oldRate L 1 c P := by
  simp [oldRate]

/-- (d′) $N$ independent pollers of cost $c$ stay within $B$ only if $P \ge W c N / B$.

$$\forall L, N, c, P:\quad 0 < P \land \operatorname{oldRate}(L, N, c, P) \le L.B \Rightarrow L.W \cdot c \cdot N \le L.B \cdot P$$
-/
theorem per_agent_interval (L : Limits) (N c P : Nat) (hP : 0 < P) (h : oldRate L N c P ≤ L.B) :
    L.W * c * N ≤ L.B * P := by
  unfold oldRate at h
  have h1 := le_ceilDiv_mul L.W P hP
  have h2 : L.W * c * N ≤ ceilDiv L.W P * P * c * N := Nat.mul_le_mul_right _ (Nat.mul_le_mul_right _ h1)
  have h3 : ceilDiv L.W P * P * c * N = N * (c * ceilDiv L.W P) * P := by
    simp only [Nat.mul_comm, Nat.mul_left_comm]
  have h4 : N * (c * ceilDiv L.W P) * P ≤ L.B * P := Nat.mul_le_mul_right _ h
  omega

end Fw.Ci.Budget
