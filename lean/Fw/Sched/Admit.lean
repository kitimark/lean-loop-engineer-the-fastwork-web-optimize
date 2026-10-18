import Fw.Spec.DeviceQueue
import Fw.Ops.PathCheck

/-!
# Admission rule (docs/team/parallel-plan.md §3.1, §3.2)

A pure admission decision for workstreams (at spawn time) and heavy jobs (at command time) on one
machine: write prefixes must not overlap with an unrelated running item, devices are exclusive,
dependencies must have landed, the summed demand must stay within the machine budget, and an
aged item ahead in the queue may only be passed by work that does not compete with it (EASY-style
backfill). Aging, `eff` and `before` are reused from `Fw.DeviceQueue` ($A = 300$ s per level).

Proved: `admit_iff` (the decision is `admit` exactly when ready, free, fits and not held),
`unfit_reported`, `inv_step` and its consequences on every reachable state (`writes_disjoint`,
`devices_exclusive`, `deps_respected`, `done_grows`, `within_budget`), `aged_not_overtaken`,
`admit_conserving`, and the liveness bound `aged_admitted_by` (restated: the plan's $k$-term was
too small, see the counterexample at the end of the file).
-/
namespace Fw.Sched.Admit

open Fw.DeviceQueue (A)
open Fw.Ops.PathCheck (segs)

/-! ## Resources, devices, items -/

/-- The budgeted resource kinds: cores (in tenths), RAM (MB), the clean-build token and the
Docker-run token.

$$\mathcal R = \{\mathrm{cores},\ \mathrm{ram},\ \mathrm{cleanBuild},\ \mathrm{docker}\}$$
-/
inductive Res where
  | cores | ram | cleanBuild | docker
deriving DecidableEq, Repr

/-- Every resource kind, as a list.

$$\mathcal R = [\mathrm{cores},\ \mathrm{ram},\ \mathrm{cleanBuild},\ \mathrm{docker}]$$
-/
def Res.all : List Res := [.cores, .ram, .cleanBuild, .docker]

/-- The list `Res.all` holds every resource kind.

$$\forall r \in \mathcal R:\ r \in [\mathrm{cores},\ \mathrm{ram},\ \mathrm{cleanBuild},\ \mathrm{docker}]$$
-/
theorem Res.mem_all (r : Res) : r ∈ Res.all := by cases r <;> simp [Res.all]

/-- A demand or budget vector: one natural number per resource kind (missing fields are 0).

$$v : \mathcal R \to \mathbb N, \qquad v = (v(\mathrm{cores}),\ v(\mathrm{ram}),\ v(\mathrm{cleanBuild}),\ v(\mathrm{docker}))$$
-/
structure Vec where
  cores      : Nat := 0
  ram        : Nat := 0
  cleanBuild : Nat := 0
  docker     : Nat := 0
deriving DecidableEq, Repr

/-- The component of a vector at one resource kind.

$$\operatorname{get}(v, r) = v(r)$$
-/
def Vec.get (v : Vec) : Res → Nat
  | .cores => v.cores
  | .ram => v.ram
  | .cleanBuild => v.cleanBuild
  | .docker => v.docker

/-- The exclusive devices.

$$\mathcal V = \{\mathrm{simulator},\ \mathrm{phone}\}$$
-/
inductive Dev where
  | simulator | phone
deriving DecidableEq, Repr

/-- An item: a workstream or a heavy job. Its id, its parent workstream (jobs only), its write
prefixes $W(x)$ (paths; a directory prefix covers its subtree), the ids $D(x)$ it depends on, its
demand $d(x)$, the devices $V(x)$ it needs, the arrival number and enqueue time (stamped by
`enqueue`), the base priority (CP-slack rank for a workstream, `DeviceQueue` base for a job) and
the start time (stamped at admission).

$$x = (\mathit{id},\ \mathit{parent},\ W(x),\ D(x),\ d(x),\ V(x),\ \mathit{seq},\ \mathit{enq},\ \mathit{base},\ \mathit{start}) \in \mathrm{String} \times \mathrm{String}_\bot \times \mathrm{String}^{*} \times \mathrm{String}^{*} \times \mathbb N^{\mathcal R} \times \mathcal V^{*} \times \mathbb N^{4}$$
-/
structure Item where
  id      : String
  parent  : Option String := none
  writes  : List String := []
  deps    : List String := []
  demand  : Vec := {}
  devices : List Dev := []
  seq     : Nat := 0
  enq     : Nat := 0
  base    : Nat := 0
  start   : Nat := 0
deriving DecidableEq, Repr

/-- The `DeviceQueue` view of an item, for aging and order (duration unused).

$$\operatorname{job}(x) = (\mathit{seq}(x),\ \mathit{enq}(x),\ \mathit{base}(x),\ 0)$$
-/
def Item.job (x : Item) : Fw.DeviceQueue.Job := ⟨x.seq, x.enq, x.base, 0⟩

/-! ## Relations between items -/

/-- Path conflict: one path is a segment prefix of the other (paths split at `/` with
`PathCheck.segs`, so `lean/Fw/` covers `lean/Fw/Ops/A.lean`; the empty path covers everything).

$$p \bowtie q \iff \operatorname{segs}(p) \sqsubseteq \operatorname{segs}(q) \ \lor\ \operatorname{segs}(q) \sqsubseteq \operatorname{segs}(p)$$
-/
def pconf (p q : String) : Bool :=
  (segs p).isPrefixOf (segs q) || (segs q).isPrefixOf (segs p)

/-- Write conflict: some write prefix of `x` conflicts with some write prefix of `y`.

$$x \bowtie y \iff \exists p \in W(x),\ q \in W(y):\ p \bowtie q$$
-/
def wconf (x y : Item) : Bool := x.writes.any fun p => y.writes.any fun q => pconf p q

/-- Device overlap: some device is needed by both.

$$\operatorname{share}(x, y) \iff V(x) \cap V(y) \ne \emptyset$$
-/
def devShare (x y : Item) : Bool := x.devices.any fun v => y.devices.contains v

/-- Related: one item is the other's parent workstream (related pairs are exempt from the write
and device checks).

$$x \sim y \iff \mathit{parent}(x) = \mathit{id}(y) \ \lor\ \mathit{parent}(y) = \mathit{id}(x)$$
-/
def related (x y : Item) : Bool := x.parent == some y.id || y.parent == some x.id

/-- The summed demand of a list of items at one resource kind.

$$\operatorname{used}(L, r) = \sum_{y \in L} d(y)(r)$$
-/
def used : List Item → Res → Nat
  | [], _ => 0
  | y :: ys, r => y.demand.get r + used ys r

/-! ## State and the admission decision -/

/-- The scheduler state: running items, landed ids, the queue, the clock (s) and the next arrival
number.

$$\sigma = (\mathit{Run},\ \mathit{Done},\ Q,\ t,\ \mathit{next}), \qquad \sigma_0 = ([\,], [\,], [\,], 0, 0)$$
-/
structure State where
  run   : List Item := []
  done  : List String := []
  queue : List Item := []
  t     : Nat := 0
  next  : Nat := 0
deriving Repr

/-- Ready: every dependency has landed.

$$\mathrm{ready}(\sigma, x) \iff D(x) \subseteq \mathit{Done}$$
-/
def ready (σ : State) (x : Item) : Bool := x.deps.all fun e => σ.done.contains e

/-- Free: no unrelated running item has a conflicting write prefix or a shared device.

$$\mathrm{free}(\sigma, x) \iff \forall y \in \mathit{Run},\ \lnot(x \sim y):\ \lnot(x \bowtie y) \land V(x) \cap V(y) = \emptyset$$
-/
def free (σ : State) (x : Item) : Bool :=
  σ.run.all fun y => related x y || (!wconf x y && !devShare x y)

/-- Fits: adding `x` keeps every resource within the budget `B`.

$$\mathrm{fits}(B, \sigma, x) \iff \forall r \in \mathcal R:\ d(x)(r) + \sum_{y \in \mathit{Run}} d(y)(r) \le B(r)$$
-/
def fits (B : Vec) (σ : State) (x : Item) : Bool :=
  Res.all.all fun r => decide (x.demand.get r + used σ.run r ≤ B.get r)

/-- Never fits: some demand exceeds the whole budget.

$$\mathrm{unfit}(B, x) \iff \exists r \in \mathcal R:\ d(x)(r) > B(r)$$
-/
def unfit (B : Vec) (x : Item) : Bool := Res.all.any fun r => decide (B.get r < x.demand.get r)

/-- `z` competes with `x`: a write conflict, a shared device, or admitting both would overflow
some resource.

$$\mathrm{comp}(B, \sigma, z, x) \iff z \bowtie x \ \lor\ V(z) \cap V(x) \ne \emptyset \ \lor\ \exists r:\ d(x)(r) + d(z)(r) + \sum_{y \in \mathit{Run}} d(y)(r) > B(r)$$
-/
def comp (B : Vec) (σ : State) (z x : Item) : Bool :=
  wconf z x || devShare z x ||
    Res.all.any fun r => decide (B.get r < x.demand.get r + z.demand.get r + used σ.run r)

/-- Aged: the item has waited `A·base` seconds, so its effective priority is 0.

$$\mathrm{aged}(t, z) \iff \mathit{enq}(z) + A \cdot \mathit{base}(z) \le t$$
-/
def aged (t : Nat) (z : Item) : Bool := decide (z.enq + A * z.base ≤ t)

/-- The `DeviceQueue` order on items.

$$\operatorname{before}_t(z, x) \iff \operatorname{before}_t(\operatorname{job}(z), \operatorname{job}(x))$$
-/
def before (t : Nat) (z x : Item) : Bool := Fw.DeviceQueue.before t z.job x.job

/-- `z` holds `x` back: a different, aged, ready, fitting item ahead of `x` that competes with it.

$$\operatorname{heldBy}(B, \sigma, x, z) \iff \mathit{id}(z) \ne \mathit{id}(x) \land \operatorname{before}_t(z, x) \land \mathrm{aged}(t, z) \land \mathrm{ready}(\sigma, z) \land \lnot\mathrm{unfit}(B, z) \land \mathrm{comp}(B, \sigma, z, x)$$
-/
def heldBy (B : Vec) (σ : State) (x z : Item) : Bool :=
  z.id != x.id && before σ.t z x && aged σ.t z && ready σ z && !unfit B z && comp B σ z x

/-- Held by an aged item: some queued item holds `x` back.

$$\mathrm{held}(B, \sigma, x) \iff \exists z \in Q:\ \operatorname{heldBy}(B, \sigma, x, z)$$
-/
def held (B : Vec) (σ : State) (x : Item) : Bool := σ.queue.any fun z => heldBy B σ x z

/-- Why an item waits (the first failing check, with its witness).

$$\mathrm{Reason} = \mathrm{neverFits}(r) \mid \mathrm{depPending}(e) \mid \mathrm{writeConflict}(p, y) \mid \mathrm{deviceBusy}(v, y) \mid \mathrm{overBudget}(r, \mathit{need}, \mathit{free}) \mid \mathrm{behindAged}(z)$$
-/
inductive Reason where
  | neverFits (r : Res)
  | depPending (e : String)
  | writeConflict (p : String) (y : String)
  | deviceBusy (v : Dev) (y : String)
  | overBudget (r : Res) (need free : Nat)
  | behindAged (z : String)
deriving DecidableEq, Repr

/-- The admission answer.

$$\mathrm{Decision} = \mathrm{admit} \mid \mathrm{queue}(w),\ w \in \mathrm{Reason}$$
-/
inductive Decision where
  | admit
  | queue (why : Reason)
deriving DecidableEq, Repr

/-- The first resource whose budget is below the item's demand.

$$\operatorname{nfAt}(B, x) = \text{the first } r \in \mathcal R \text{ with } B(r) < d(x)(r), \text{ else } \bot$$
-/
def neverFitsAt (B : Vec) (x : Item) : Option Res := Res.all.find? fun r => decide (B.get r < x.demand.get r)

/-- The first dependency that has not landed.

$$\operatorname{depAt}(\sigma, x) = \text{the first } e \in D(x) \text{ with } e \notin \mathit{Done}, \text{ else } \bot$$
-/
def depAt (σ : State) (x : Item) : Option String := x.deps.find? fun e => !σ.done.contains e

/-- The first unrelated running item (in `Run` order) with a write conflict, and the first prefix of `x`
that conflicts with it.

$$\operatorname{wAt}(\sigma, x) = \begin{cases} (p, \mathit{id}(y)) & y = \text{the first } y \in \mathit{Run} \text{ with } \lnot(x \sim y) \land \exists p' \in W(x), q \in W(y):\ p' \bowtie q, \\ & p = \text{the first } p' \in W(x) \text{ with } \exists q \in W(y):\ p' \bowtie q \\ \bot & \text{if there is no such } y \end{cases}$$
-/
def writeAt (σ : State) (x : Item) : Option (String × String) :=
  σ.run.findSome? fun y =>
    if related x y then none else (x.writes.find? fun p => y.writes.any fun q => pconf p q).map (·, y.id)

/-- The first unrelated running item (in `Run` order) sharing a device, and the first device of `x` that it
shares.

$$\operatorname{vAt}(\sigma, x) = \begin{cases} (v, \mathit{id}(y)) & y = \text{the first } y \in \mathit{Run} \text{ with } \lnot(x \sim y) \land V(x) \cap V(y) \ne \emptyset, \\ & v = \text{the first } v \in V(x) \text{ with } v \in V(y) \\ \bot & \text{if there is no such } y \end{cases}$$
-/
def devAt (σ : State) (x : Item) : Option (Dev × String) :=
  σ.run.findSome? fun y =>
    if related x y then none else (x.devices.find? fun v => y.devices.contains v).map (·, y.id)

/-- The first resource that adding the item would overflow.

$$\operatorname{bAt}(B, \sigma, x) = \text{the first } r \in \mathcal R \text{ with } B(r) < d(x)(r) + \operatorname{used}(\mathit{Run}, r), \text{ else } \bot$$
-/
def budgetAt (B : Vec) (σ : State) (x : Item) : Option Res :=
  Res.all.find? fun r => decide (B.get r < x.demand.get r + used σ.run r)

/-- The first queued item that holds `x` back.

$$\operatorname{hAt}(B, \sigma, x) = \text{the first } z \in Q \text{ with } \operatorname{heldBy}(B, \sigma, x, z), \text{ else } \bot$$
-/
def heldAt (B : Vec) (σ : State) (x : Item) : Option Item := σ.queue.find? fun z => heldBy B σ x z

/-- The admission rule: the first failing check, in this order, gives the reason; otherwise admit.

$$\operatorname{admit}(B, \sigma, x) = \begin{cases} \mathrm{queue}(\mathrm{neverFits}(r)) & \operatorname{nfAt}(B, x) = r \\ \mathrm{queue}(\mathrm{depPending}(e)) & \text{else if } \operatorname{depAt}(\sigma, x) = e \\ \mathrm{queue}(\mathrm{writeConflict}(p, y)) & \text{else if } \operatorname{wAt}(\sigma, x) = (p, y) \\ \mathrm{queue}(\mathrm{deviceBusy}(v, y)) & \text{else if } \operatorname{vAt}(\sigma, x) = (v, y) \\ \mathrm{queue}(\mathrm{overBudget}(r, d(x)(r), B(r) \mathbin{\dot-} \operatorname{used}(\mathit{Run}, r))) & \text{else if } \operatorname{bAt}(B, \sigma, x) = r \\ \mathrm{queue}(\mathrm{behindAged}(\mathit{id}(z))) & \text{else if } \operatorname{hAt}(B, \sigma, x) = z \\ \mathrm{admit} & \text{otherwise} \end{cases}$$
-/
def admit (B : Vec) (σ : State) (x : Item) : Decision :=
  match neverFitsAt B x with
  | some r => .queue (.neverFits r)
  | none =>
    match depAt σ x with
    | some e => .queue (.depPending e)
    | none =>
      match writeAt σ x with
      | some (p, y) => .queue (.writeConflict p y)
      | none =>
        match devAt σ x with
        | some (v, y) => .queue (.deviceBusy v y)
        | none =>
          match budgetAt B σ x with
          | some r => .queue (.overBudget r (x.demand.get r) (B.get r - used σ.run r))
          | none =>
            match heldAt B σ x with
            | some z => .queue (.behindAged z.id)
            | none => .admit

/-! ## Characterisation of the decision -/

/-- No resource is named by `nfAt` exactly when the item is not unfit.

$$\forall B, x:\quad \operatorname{nfAt}(B, x) = \bot \iff \lnot\mathrm{unfit}(B, x)$$
-/
theorem neverFitsAt_none (B : Vec) (x : Item) : neverFitsAt B x = none ↔ unfit B x = false := by
  simp [neverFitsAt, unfit, List.find?_eq_none]

/-- No pending dependency is named exactly when the item is ready.

$$\forall \sigma, x:\quad \operatorname{depAt}(\sigma, x) = \bot \iff \mathrm{ready}(\sigma, x)$$
-/
theorem depAt_none (σ : State) (x : Item) : depAt σ x = none ↔ ready σ x = true := by
  simp [depAt, ready, List.find?_eq_none]

/-- No write conflict is named exactly when every running item is related or has no write conflict.

$$\forall \sigma, x:\quad \operatorname{wAt}(\sigma, x) = \bot \iff \forall y \in \mathit{Run}:\ x \sim y \ \lor\ \lnot(x \bowtie y)$$
-/
theorem writeAt_none (σ : State) (x : Item) :
    writeAt σ x = none ↔ ∀ y ∈ σ.run, related x y = true ∨ wconf x y = false := by
  simp only [writeAt, List.findSome?_eq_none_iff]
  apply forall_congr'; intro y; apply imp_congr_right; intro _
  by_cases h : related x y = true
  · simp [h]
  · simp [h, wconf, List.find?_eq_none]

/-- No busy device is named exactly when every running item is related or shares no device.

$$\forall \sigma, x:\quad \operatorname{vAt}(\sigma, x) = \bot \iff \forall y \in \mathit{Run}:\ x \sim y \ \lor\ V(x) \cap V(y) = \emptyset$$
-/
theorem devAt_none (σ : State) (x : Item) :
    devAt σ x = none ↔ ∀ y ∈ σ.run, related x y = true ∨ devShare x y = false := by
  simp only [devAt, List.findSome?_eq_none_iff]
  apply forall_congr'; intro y; apply imp_congr_right; intro _
  by_cases h : related x y = true
  · simp [h]
  · simp [h, devShare, List.find?_eq_none]

/-- No overflowing resource is named exactly when the item fits.

$$\forall B, \sigma, x:\quad \operatorname{bAt}(B, \sigma, x) = \bot \iff \mathrm{fits}(B, \sigma, x)$$
-/
theorem budgetAt_none (B : Vec) (σ : State) (x : Item) : budgetAt B σ x = none ↔ fits B σ x = true := by
  simp [budgetAt, fits, List.find?_eq_none]

/-- No holding item is named exactly when the item is not held.

$$\forall B, \sigma, x:\quad \operatorname{hAt}(B, \sigma, x) = \bot \iff \lnot\mathrm{held}(B, \sigma, x)$$
-/
theorem heldAt_none (B : Vec) (σ : State) (x : Item) : heldAt B σ x = none ↔ held B σ x = false := by
  simp [heldAt, held, List.find?_eq_none]

/-- Free, unfolded: every unrelated running item has no write conflict and shares no device.

$$\forall \sigma, x:\quad \mathrm{free}(\sigma, x) \iff \forall y \in \mathit{Run}:\ \lnot(x \sim y) \Rightarrow \lnot(x \bowtie y) \land V(x) \cap V(y) = \emptyset$$
-/
theorem free_iff (σ : State) (x : Item) :
    free σ x = true ↔ ∀ y ∈ σ.run, related x y = false → wconf x y = false ∧ devShare x y = false := by
  simp only [free, List.all_eq_true]
  apply forall_congr'; intro y; apply imp_congr_right; intro _
  cases related x y <;> cases wconf x y <;> cases devShare x y <;> simp

/-- The decision is `admit` exactly when none of the six checks names anything.

$$\forall B, \sigma, x:\quad \operatorname{admit}(B, \sigma, x) = \mathrm{admit} \iff \operatorname{nfAt}(B, x) = \operatorname{depAt}(\sigma, x) = \operatorname{wAt}(\sigma, x) = \operatorname{vAt}(\sigma, x) = \operatorname{bAt}(B, \sigma, x) = \operatorname{hAt}(B, \sigma, x) = \bot$$
-/
theorem admit_eq_admit (B : Vec) (σ : State) (x : Item) :
    admit B σ x = .admit ↔ neverFitsAt B x = none ∧ depAt σ x = none ∧ writeAt σ x = none ∧
      devAt σ x = none ∧ budgetAt B σ x = none ∧ heldAt B σ x = none := by
  unfold admit
  cases h1 : neverFitsAt B x <;> simp only [reduceCtorEq, false_and, true_and]
  cases h2 : depAt σ x <;> simp only [reduceCtorEq, false_and, true_and]
  cases h3 : writeAt σ x with
  | some py => obtain ⟨p, y⟩ := py; simp
  | none =>
    simp only [true_and]
    cases h4 : devAt σ x with
    | some vy => obtain ⟨v, y⟩ := vy; simp
    | none =>
      simp only [true_and]
      cases h5 : budgetAt B σ x <;> simp only [reduceCtorEq, false_and, true_and]
      cases h6 : heldAt B σ x <;> simp

/-- An item that fits next to the running items fits the whole budget.

$$\forall B, \sigma, x:\quad \mathrm{fits}(B, \sigma, x) \Rightarrow \lnot\mathrm{unfit}(B, x)$$
-/
theorem fits_not_unfit {B : Vec} {σ : State} {x : Item} (h : fits B σ x = true) : unfit B x = false := by
  simp only [fits, List.all_eq_true, decide_eq_true_eq] at h
  simp only [unfit, List.any_eq_false, decide_eq_true_eq, Nat.not_lt]
  intro r hr; have := h r hr; omega

/-- **The decision is `admit` exactly when** the item is ready, free, fits, and not held (the
`neverFits` check is implied by `fits`).

$$\forall B, \sigma, x:\quad \operatorname{admit}(B, \sigma, x) = \mathrm{admit} \iff \mathrm{ready}(\sigma, x) \land \mathrm{free}(\sigma, x) \land \mathrm{fits}(B, \sigma, x) \land \lnot\mathrm{held}(B, \sigma, x)$$
-/
theorem admit_iff (B : Vec) (σ : State) (x : Item) :
    admit B σ x = .admit ↔
      ready σ x = true ∧ free σ x = true ∧ fits B σ x = true ∧ held B σ x = false := by
  rw [admit_eq_admit, neverFitsAt_none, depAt_none, writeAt_none, devAt_none, budgetAt_none,
    heldAt_none, free_iff]
  constructor
  · rintro ⟨_, h2, h3, h4, h5, h6⟩
    refine ⟨h2, ?_, h5, h6⟩
    intro y hy hr
    rcases h3 y hy with h | h
    · rw [hr] at h; cases h
    rcases h4 y hy with h' | h'
    · rw [hr] at h'; cases h'
    exact ⟨h, h'⟩
  · rintro ⟨h2, h3, h5, h6⟩
    refine ⟨fits_not_unfit h5, h2, ?_, ?_, h5, h6⟩
    · intro y hy
      cases hr : related x y
      · exact Or.inr (h3 y hy hr).1
      · exact Or.inl rfl
    · intro y hy
      cases hr : related x y
      · exact Or.inr (h3 y hy hr).2
      · exact Or.inl rfl

/-- **An item that never fits is named at once**: the decision is `neverFits` for some resource,
never a silent wait.

$$\forall B, \sigma, x:\quad \mathrm{unfit}(B, x) \;\Rightarrow\; \exists r \in \mathcal R:\ \operatorname{admit}(B, \sigma, x) = \mathrm{queue}(\mathrm{neverFits}(r)) \land d(x)(r) > B(r)$$
-/
theorem unfit_reported (B : Vec) (σ : State) (x : Item) (h : unfit B x = true) :
    ∃ r, admit B σ x = .queue (.neverFits r) ∧ B.get r < x.demand.get r := by
  cases hn : neverFitsAt B x with
  | none => rw [neverFitsAt_none] at hn; rw [hn] at h; cases h
  | some r =>
    refine ⟨r, by simp [admit, hn], ?_⟩
    have := List.find?_some hn
    simpa using this

/-! ## Steps: pick, admitStep, finish, enqueue, clock -/

/-- The most urgent item of a list by `before` (a left fold, as `DeviceQueue.pickFrom`).

$$\operatorname{pickFrom}_t(b, [\,]) = b, \qquad \operatorname{pickFrom}_t(b, k :: ks) = \operatorname{pickFrom}_t\big(\textbf{if } \operatorname{before}_t(k, b) \textbf{ then } k \textbf{ else } b,\ ks\big)$$
-/
def pickFrom (t : Nat) (best : Item) : List Item → Item
  | [] => best
  | k :: ks => pickFrom t (if before t k best then k else best) ks

/-- Pick from a list: nothing from an empty list, otherwise `pickFrom` seeded with the head.

$$\operatorname{pick}_t([\,]) = \bot, \qquad \operatorname{pick}_t(j :: js) = \operatorname{pickFrom}_t(j, js)$$
-/
def pick (t : Nat) : List Item → Option Item
  | [] => none
  | j :: js => some (pickFrom t j js)

/-- The fold returns its seed or one of the items it scanned.

$$\forall t, b, ks:\quad \operatorname{pickFrom}_t(b, ks) = b \ \lor\ \operatorname{pickFrom}_t(b, ks) \in ks$$
-/
theorem pickFrom_mem (t : Nat) (b : Item) (ks : List Item) :
    pickFrom t b ks = b ∨ pickFrom t b ks ∈ ks := by
  induction ks generalizing b with
  | nil => simp [pickFrom]
  | cons k ks ih =>
    simp only [pickFrom]
    split
    · rcases ih k with h | h <;> simp [h]
    · rcases ih b with h | h <;> simp [h]

/-- `pick` returns a member of the list.

$$\forall t, Q, j:\quad \operatorname{pick}_t(Q) = j \Rightarrow j \in Q$$
-/
theorem pick_mem {t : Nat} {q : List Item} {j : Item} (h : pick t q = some j) : j ∈ q := by
  cases q with
  | nil => cases h
  | cons a as =>
    simp only [pick, Option.some.injEq] at h; subst h
    rcases pickFrom_mem t a as with h | h
    · rw [h]; simp
    · simp [h]

/-- The item `admitStep` admits: the most urgent queued item whose decision is `admit`.

$$\operatorname{chosen}(B, \sigma) = \operatorname{pick}_t\big([\, x \in Q \mid \operatorname{admit}(B, \sigma, x) = \mathrm{admit} \,]\big)$$
-/
def chosen (B : Vec) (σ : State) : Option Item :=
  pick σ.t (σ.queue.filter fun x => admit B σ x == .admit)

/-- Admit one item: the chosen item joins `Run` with its start time stamped, and leaves `Q` (by
id); with nothing admissible the state is unchanged.

$$\operatorname{admitStep}(B, \sigma) = \begin{cases} \sigma[\mathit{Run} := x[\mathit{start} := t] :: \mathit{Run},\ Q := [\, y \in Q \mid \mathit{id}(y) \ne \mathit{id}(x) \,]] & \operatorname{chosen}(B, \sigma) = x \\ \sigma & \operatorname{chosen}(B, \sigma) = \bot \end{cases}$$
-/
def admitStep (B : Vec) (σ : State) : State :=
  match chosen B σ with
  | some x => { σ with run := { x with start := σ.t } :: σ.run, queue := σ.queue.filter (·.id != x.id) }
  | none => σ

/-- An item ends: it leaves `Run`; its id joins `Done` when it landed and was running.

$$\operatorname{finish}(\sigma, i, \ell) = \sigma\Big[\mathit{Run} := [\, y \in \mathit{Run} \mid \mathit{id}(y) \ne i \,],\ \mathit{Done} := \begin{cases} i :: \mathit{Done} & \ell \land \exists y \in \mathit{Run}:\ \mathit{id}(y) = i \\ \mathit{Done} & \text{otherwise} \end{cases}\Big]$$
-/
def finish (σ : State) (i : String) (landed : Bool) : State :=
  { σ with run := σ.run.filter (·.id != i),
           done := if landed && σ.run.any (·.id == i) then i :: σ.done else σ.done }

/-- Enqueue: a fresh id joins the end of `Q` with arrival number `next` and enqueue time `t`; an id
already running or queued is ignored.

$$\operatorname{enqueue}(\sigma, x) = \begin{cases} \sigma & \exists y \in \mathit{Run} \cup Q:\ \mathit{id}(y) = \mathit{id}(x) \\ \sigma[Q := Q \mathbin{+\!\!+} [x[\mathit{seq} := \mathit{next},\ \mathit{enq} := t]],\ \mathit{next} := \mathit{next} + 1] & \text{otherwise} \end{cases}$$
-/
def enqueue (σ : State) (x : Item) : State :=
  if (σ.run ++ σ.queue).any (·.id == x.id) then σ
  else { σ with queue := σ.queue ++ [{ x with seq := σ.next, enq := σ.t }], next := σ.next + 1 }

/-- The clock: time never runs backwards.

$$\operatorname{setTime}(\sigma, n) = \sigma[t := \max(t, n)]$$
-/
def setTime (σ : State) (now : Nat) : State := { σ with t := max σ.t now }

/-- One scheduler command.

$$\mathrm{Cmd} = \mathrm{admit} \mid \mathrm{finish}(i, \ell) \mid \mathrm{enqueue}(x) \mid \mathrm{tick}(n)$$
-/
inductive Cmd where
  | admit
  | finish (i : String) (landed : Bool)
  | enqueue (x : Item)
  | tick (now : Nat)
deriving Repr

/-- Apply one command.

$$\operatorname{step}(B, \sigma, \mathrm{admit}) = \operatorname{admitStep}(B, \sigma),\quad \operatorname{step}(B, \sigma, \mathrm{finish}(i, \ell)) = \operatorname{finish}(\sigma, i, \ell),\quad \operatorname{step}(B, \sigma, \mathrm{enqueue}(x)) = \operatorname{enqueue}(\sigma, x),\quad \operatorname{step}(B, \sigma, \mathrm{tick}(n)) = \operatorname{setTime}(\sigma, n)$$
-/
def step (B : Vec) (σ : State) : Cmd → State
  | .admit => admitStep B σ
  | .finish i l => finish σ i l
  | .enqueue x => enqueue σ x
  | .tick n => setTime σ n

/-- The states reachable from the empty state by any sequence of commands.

$$\mathrm{Reach}_B(\sigma_0), \qquad \mathrm{Reach}_B(\sigma) \Rightarrow \mathrm{Reach}_B(\operatorname{step}(B, \sigma, c))$$
-/
inductive Reachable (B : Vec) : State → Prop where
  | init : Reachable B {}
  | step {σ : State} (c : Cmd) : Reachable B σ → Reachable B (step B σ c)

/-! ## The invariant -/

/-- The invariant: ids and arrival numbers are unique over `Run` and `Q`, arrival numbers are below
`next`, running items started no later than now, unrelated running items have no write conflict
and share no device, running items are ready, and the budget holds.

$$\mathrm{Inv}(B, \sigma) \iff \begin{aligned}[t] & [\, \mathit{id}(x) \mid x \in \mathit{Run} \mathbin{+\!\!+} Q \,] \text{ and } [\, \mathit{seq}(x) \mid x \in \mathit{Run} \mathbin{+\!\!+} Q \,] \text{ have no repeats},\ \forall x \in \mathit{Run} \mathbin{+\!\!+} Q:\ \mathit{seq}(x) < \mathit{next},\ \ \forall x \in \mathit{Run}:\ \mathit{start}(x) \le t \land \mathrm{ready}(\sigma, x), \\ & \forall x, y \in \mathit{Run},\ \mathit{id}(x) \ne \mathit{id}(y),\ \lnot(x \sim y):\ \lnot(x \bowtie y) \land V(x) \cap V(y) = \emptyset,\ \ \forall r \in \mathcal R:\ \textstyle\sum_{x \in \mathit{Run}} d(x)(r) \le B(r) \end{aligned}$$
-/
structure Inv (B : Vec) (σ : State) : Prop where
  ids     : ((σ.run ++ σ.queue).map Item.id).Nodup
  seqs    : ((σ.run ++ σ.queue).map Item.seq).Nodup
  fresh   : ∀ x ∈ σ.run ++ σ.queue, x.seq < σ.next
  started : ∀ x ∈ σ.run, x.start ≤ σ.t
  writes  : ∀ x ∈ σ.run, ∀ y ∈ σ.run, x.id ≠ y.id → related x y = false → wconf x y = false
  devs    : ∀ x ∈ σ.run, ∀ y ∈ σ.run, x.id ≠ y.id → related x y = false → devShare x y = false
  deps    : ∀ x ∈ σ.run, ready σ x = true
  budget  : ∀ r, used σ.run r ≤ B.get r

/-- If the image list of `l` under `f` has no repeats, two members of `l` with the same image are equal.

$$\forall f, l, a, b:\quad [\, f(c) \mid c \in l \,] \text{ has no repeats} \ \land\ a, b \in l \ \land\ f(a) = f(b) \Rightarrow a = b$$
-/
theorem eq_of_nodup_map {α β : Type} (f : α → β) :
    ∀ {l : List α} {a b : α}, (l.map f).Nodup → a ∈ l → b ∈ l → f a = f b → a = b
  | [], _, _, _, ha, _, _ => by cases ha
  | c :: l, a, b, hn, ha, hb, hf => by
    simp only [List.map_cons, List.nodup_cons, List.mem_map, not_exists, not_and] at hn
    simp only [List.mem_cons] at ha hb
    rcases ha with rfl | ha <;> rcases hb with rfl | hb
    · rfl
    · exact absurd hf.symm (hn.1 b hb)
    · exact absurd hf (hn.1 a ha)
    · exact eq_of_nodup_map f hn.2 ha hb hf

/-- Write conflict is symmetric.

$$\forall x, y:\quad x \bowtie y \iff y \bowtie x$$
-/
theorem wconf_comm (x y : Item) : wconf x y = wconf y x := by
  have hp : ∀ p q, pconf p q = pconf q p := fun p q => by simp [pconf, Bool.or_comm]
  apply Bool.eq_iff_iff.mpr
  simp only [wconf, List.any_eq_true]
  constructor
  · rintro ⟨p, hp', q, hq, h⟩; exact ⟨q, hq, p, hp', by rw [hp]; exact h⟩
  · rintro ⟨p, hp', q, hq, h⟩; exact ⟨q, hq, p, hp', by rw [hp]; exact h⟩

/-- Device overlap is symmetric.

$$\forall x, y:\quad V(x) \cap V(y) \ne \emptyset \iff V(y) \cap V(x) \ne \emptyset$$
-/
theorem devShare_comm (x y : Item) : devShare x y = devShare y x := by
  apply Bool.eq_iff_iff.mpr
  simp only [devShare, List.any_eq_true, List.contains_iff_mem]
  constructor
  · rintro ⟨v, h1, h2⟩; exact ⟨v, h2, h1⟩
  · rintro ⟨v, h1, h2⟩; exact ⟨v, h2, h1⟩

/-- Relatedness is symmetric.

$$\forall x, y:\quad x \sim y \iff y \sim x$$
-/
theorem related_comm (x y : Item) : related x y = related y x := by
  simp [related, Bool.or_comm]

/-- The summed demand of a filtered list is at most that of the list.

$$\forall p, l, r:\quad \operatorname{used}([\, y \in l \mid p(y) \,], r) \le \operatorname{used}(l, r)$$
-/
theorem used_filter_le (p : Item → Bool) (l : List Item) (r : Res) : used (l.filter p) r ≤ used l r := by
  induction l with
  | nil => simp [used]
  | cons y ys ih =>
    simp only [List.filter_cons]
    split <;> simp only [used] <;> omega

/-- `chosen` returns a queued item whose decision is `admit`.

$$\forall B, \sigma, x:\quad \operatorname{chosen}(B, \sigma) = x \Rightarrow x \in Q \land \operatorname{admit}(B, \sigma, x) = \mathrm{admit}$$
-/
theorem chosen_sound {B : Vec} {σ : State} {x : Item} (h : chosen B σ = some x) :
    x ∈ σ.queue ∧ admit B σ x = .admit := by
  have := pick_mem h
  simp only [List.mem_filter, beq_iff_eq] at this
  exact this

/-- **Work conservation.** If some queued item would be admitted, `admitStep` admits something.

$$\forall B, \sigma, x:\quad x \in Q \land \operatorname{admit}(B, \sigma, x) = \mathrm{admit} \Rightarrow \operatorname{chosen}(B, \sigma) \ne \bot$$
-/
theorem admit_conserving (B : Vec) (σ : State) (x : Item) (hx : x ∈ σ.queue)
    (ha : admit B σ x = .admit) : chosen B σ ≠ none := by
  have hm : x ∈ σ.queue.filter (fun x => admit B σ x == .admit) := by simp [hx, ha]
  unfold chosen
  cases hq : σ.queue.filter (fun x => admit B σ x == .admit) with
  | nil => rw [hq] at hm; cases hm
  | cons a as => simp [pick]

/-- Nodup of an image survives taking a sublist.

$$\forall f, l', l:\quad l' \text{ a sublist of } l \ \land\ [\, f(a) \mid a \in l \,] \text{ has no repeats} \Rightarrow [\, f(a) \mid a \in l' \,] \text{ has no repeats}$$
-/
theorem nodup_map_sublist {α β : Type} (f : α → β) {l' l : List α} (hs : l'.Sublist l)
    (h : (l.map f).Nodup) : (l'.map f).Nodup :=
  List.Pairwise.sublist (hs.map f) h

/-- Admitting `x` from `Q` keeps the image list free of repeats (the admitted copy keeps its image).

$$\forall f, R, Q, x, x':\quad x \in Q \land f(x') = f(x) \land [\, f(y) \mid y \in R \mathbin{+\!\!+} Q \,] \text{ has no repeats} \Rightarrow [\, f(y) \mid y \in x' :: R \mathbin{+\!\!+} [\, y \in Q \mid \mathit{id}(y) \ne \mathit{id}(x) \,] \,] \text{ has no repeats}$$
-/
theorem nodup_admit {β : Type} (f : Item → β) (run q : List Item) (x x' : Item) (hx : x ∈ q)
    (hf : f x' = f x) (h : ((run ++ q).map f).Nodup) :
    ((x' :: run ++ q.filter (·.id != x.id)).map f).Nodup := by
  have hsub : (run ++ q.filter (·.id != x.id)).Sublist (run ++ q) :=
    List.Sublist.append (List.Sublist.refl _) List.filter_sublist
  simp only [List.cons_append, List.map_cons, List.nodup_cons]
  refine ⟨?_, nodup_map_sublist f hsub h⟩
  rw [hf]
  intro hm
  simp only [List.mem_map, List.mem_append, List.mem_filter] at hm
  obtain ⟨y, hy, hyx⟩ := hm
  have hxl : x ∈ run ++ q := List.mem_append_right _ hx
  rcases hy with hy | ⟨hy, hne⟩
  · have hyl : y ∈ run ++ q := List.mem_append_left _ hy
    have := eq_of_nodup_map f h hyl hxl hyx
    subst this
    rw [List.map_append, List.nodup_append] at h
    exact h.2.2 (f y) (List.mem_map_of_mem hy) (f y) (List.mem_map_of_mem hx) rfl
  · have hyl : y ∈ run ++ q := List.mem_append_right _ hy
    have := eq_of_nodup_map f h hyl hxl hyx
    subst this
    simp at hne

/-- **The invariant is preserved by every command.**

$$\forall B, \sigma, c:\quad \mathrm{Inv}(B, \sigma) \Rightarrow \mathrm{Inv}(B, \operatorname{step}(B, \sigma, c))$$
-/
theorem inv_step (B : Vec) (σ : State) (c : Cmd) (h : Inv B σ) : Inv B (step B σ c) := by
  cases c with
  | admit =>
    simp only [step, admitStep]
    cases hc : chosen B σ with
    | none => exact h
    | some x =>
      obtain ⟨hxq, hadm⟩ := chosen_sound hc
      obtain ⟨hrd, hfr, hfit, _⟩ := (admit_iff B σ x).mp hadm
      rw [free_iff] at hfr
      have hrun_ids : ∀ y ∈ σ.run, y.id ≠ x.id := by
        intro y hy he
        have h1 := h.ids
        rw [List.map_append, List.nodup_append] at h1
        exact h1.2.2 _ (List.mem_map_of_mem hy) _ (List.mem_map_of_mem hxq) he
      have hsub : ∀ y ∈ σ.queue.filter (·.id != x.id), y ∈ σ.queue := fun y hy =>
        (List.mem_filter.mp hy).1
      refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
      · exact nodup_admit Item.id σ.run σ.queue x _ hxq rfl h.ids
      · exact nodup_admit Item.seq σ.run σ.queue x _ hxq rfl h.seqs
      · intro y hy
        simp only [List.cons_append, List.mem_cons, List.mem_append] at hy
        rcases hy with rfl | hy | hy
        · exact h.fresh x (List.mem_append_right _ hxq)
        · exact h.fresh y (List.mem_append_left _ hy)
        · exact h.fresh y (List.mem_append_right _ (hsub y hy))
      · intro y hy
        simp only [List.mem_cons] at hy
        rcases hy with rfl | hy
        · exact Nat.le_refl _
        · exact h.started y hy
      · intro a ha b hb hab hrel
        simp only [List.mem_cons] at ha hb
        rcases ha with rfl | ha <;> rcases hb with rfl | hb
        · exact absurd rfl hab
        · exact (hfr b hb (by simpa [related] using hrel)).1
        · rw [wconf_comm]; exact (hfr a ha (by rw [related_comm]; simpa [related] using hrel)).1
        · exact h.writes a ha b hb hab hrel
      · intro a ha b hb hab hrel
        simp only [List.mem_cons] at ha hb
        rcases ha with rfl | ha <;> rcases hb with rfl | hb
        · exact absurd rfl hab
        · exact (hfr b hb (by simpa [related] using hrel)).2
        · rw [devShare_comm]; exact (hfr a ha (by rw [related_comm]; simpa [related] using hrel)).2
        · exact h.devs a ha b hb hab hrel
      · intro y hy
        simp only [List.mem_cons] at hy
        rcases hy with rfl | hy
        · simpa [ready] using hrd
        · simpa [ready] using h.deps y hy
      · intro r
        simp only [fits, List.all_eq_true, decide_eq_true_eq] at hfit
        have := hfit r (Res.mem_all r)
        simp only [used]
        exact this
  | finish i l =>
    simp only [step, finish]
    have hs : (σ.run.filter (·.id != i)).Sublist σ.run := List.filter_sublist
    have hm : ∀ y ∈ σ.run.filter (·.id != i), y ∈ σ.run := fun y hy => (List.mem_filter.mp hy).1
    have hs2 : (σ.run.filter (·.id != i) ++ σ.queue).Sublist (σ.run ++ σ.queue) :=
      List.Sublist.append hs (List.Sublist.refl _)
    refine ⟨nodup_map_sublist _ hs2 h.ids, nodup_map_sublist _ hs2 h.seqs, ?_, ?_, ?_, ?_, ?_, ?_⟩
    · intro y hy; exact h.fresh y (hs2.subset hy)
    · intro y hy; exact h.started y (hm y hy)
    · intro a ha b hb; exact h.writes a (hm a ha) b (hm b hb)
    · intro a ha b hb; exact h.devs a (hm a ha) b (hm b hb)
    · intro y hy
      have := h.deps y (hm y hy)
      simp only [ready, List.all_eq_true, List.contains_iff_mem] at this ⊢
      intro e he
      have := this e he
      split <;> simp_all
    · intro r; exact Nat.le_trans (used_filter_le _ _ r) (h.budget r)
  | enqueue x =>
    simp only [step, enqueue]
    split
    · exact h
    · rename_i hfresh
      simp only [List.any_eq_true, beq_iff_eq, not_exists, not_and] at hfresh
      refine ⟨?_, ?_, ?_, h.started, h.writes, h.devs, h.deps, h.budget⟩
      · rw [← List.append_assoc, List.map_append, List.nodup_append]
        refine ⟨h.ids, by simp, ?_⟩
        intro a ha b hb hab
        simp only [List.map_cons, List.map_nil, List.mem_singleton] at hb
        subst hb
        simp only [List.mem_map] at ha
        obtain ⟨y, hy, rfl⟩ := ha
        exact hfresh y hy hab
      · rw [← List.append_assoc, List.map_append, List.nodup_append]
        refine ⟨h.seqs, by simp, ?_⟩
        intro a ha b hb hab
        simp only [List.map_cons, List.map_nil, List.mem_singleton] at hb
        subst hb
        simp only [List.mem_map] at ha
        obtain ⟨y, hy, rfl⟩ := ha
        have := h.fresh y hy
        omega
      · intro y hy
        rw [← List.append_assoc, List.mem_append] at hy
        rcases hy with hy | hy
        · have := h.fresh y hy; show y.seq < σ.next + 1; omega
        · simp at hy; subst hy; simp
  | tick n =>
    simp only [step, setTime]
    refine ⟨h.ids, h.seqs, h.fresh, ?_, h.writes, h.devs, h.deps, h.budget⟩
    intro y hy; have := h.started y hy; show y.start ≤ max σ.t n; omega

/-- The empty state satisfies the invariant.

$$\forall B:\quad \mathrm{Inv}(B, \sigma_0)$$
-/
theorem inv_init (B : Vec) : Inv B {} := by
  refine ⟨by simp, by simp, by simp, by simp, by simp, by simp, by simp, ?_⟩
  intro r; simp [used]

/-- Every reachable state satisfies the invariant.

$$\forall B, \sigma:\quad \mathrm{Reach}_B(\sigma) \Rightarrow \mathrm{Inv}(B, \sigma)$$
-/
theorem inv_reachable {B : Vec} {σ : State} (h : Reachable B σ) : Inv B σ := by
  induction h with
  | init => exact inv_init B
  | step c _ ih => exact inv_step B _ c ih

/-- **No two unrelated running items write the same file** (in every reachable state).

$$\forall B, \sigma:\quad \mathrm{Reach}_B(\sigma) \Rightarrow \forall x, y \in \mathit{Run}:\ x \ne y \land \lnot(x \sim y) \Rightarrow \lnot(x \bowtie y)$$
-/
theorem writes_disjoint {B : Vec} {σ : State} (h : Reachable B σ) :
    ∀ x ∈ σ.run, ∀ y ∈ σ.run, x ≠ y → related x y = false → wconf x y = false := by
  intro x hx y hy hne hrel
  have hi := inv_reachable h
  refine hi.writes x hx y hy (fun he => hne ?_) hrel
  exact eq_of_nodup_map Item.id hi.ids (List.mem_append_left _ hx) (List.mem_append_left _ hy) he

/-- **Devices are exclusive between unrelated running items** (in every reachable state).

$$\forall B, \sigma:\quad \mathrm{Reach}_B(\sigma) \Rightarrow \forall x, y \in \mathit{Run}:\ x \ne y \land \lnot(x \sim y) \Rightarrow V(x) \cap V(y) = \emptyset$$
-/
theorem devices_exclusive {B : Vec} {σ : State} (h : Reachable B σ) :
    ∀ x ∈ σ.run, ∀ y ∈ σ.run, x ≠ y → related x y = false → devShare x y = false := by
  intro x hx y hy hne hrel
  have hi := inv_reachable h
  refine hi.devs x hx y hy (fun he => hne ?_) hrel
  exact eq_of_nodup_map Item.id hi.ids (List.mem_append_left _ hx) (List.mem_append_left _ hy) he

/-- **Dependencies are respected**: every running item's dependencies have landed (in every
reachable state).

$$\forall B, \sigma:\quad \mathrm{Reach}_B(\sigma) \Rightarrow \forall x \in \mathit{Run},\ \forall e \in D(x):\ e \in \mathit{Done}$$
-/
theorem deps_respected {B : Vec} {σ : State} (h : Reachable B σ) :
    ∀ x ∈ σ.run, ∀ e ∈ x.deps, e ∈ σ.done := by
  intro x hx e he
  have := (inv_reachable h).deps x hx
  simp only [ready, List.all_eq_true, List.contains_iff_mem] at this
  exact this e he

/-- **`Done` only grows**: no command removes a landed id.

$$\forall B, \sigma, c:\quad \forall e \in \mathit{Done}(\sigma):\ e \in \mathit{Done}(\operatorname{step}(B, \sigma, c))$$
-/
theorem done_grows (B : Vec) (σ : State) (c : Cmd) : ∀ e ∈ σ.done, e ∈ (step B σ c).done := by
  intro e he
  cases c with
  | admit => simp only [step, admitStep]; split <;> exact he
  | finish i l => simp only [step, finish]; split <;> simp_all
  | enqueue x => simp only [step, enqueue]; split <;> exact he
  | tick n => exact he

/-- **The budget holds** in every reachable state.

$$\forall B, \sigma:\quad \mathrm{Reach}_B(\sigma) \Rightarrow \forall r \in \mathcal R:\ \sum_{x \in \mathit{Run}} d(x)(r) \le B(r)$$
-/
theorem within_budget {B : Vec} {σ : State} (h : Reachable B σ) : ∀ r, used σ.run r ≤ B.get r :=
  (inv_reachable h).budget

/-- **An aged item is never overtaken by a competitor.** If `z` is queued, aged, ready, not unfit
and goes before `x`, and `admitStep` admits `x` (with a different id), then `z` does not compete
with `x`.

$$\forall B, \sigma, z, x:\quad z \in Q,\ \mathrm{aged}(t, z),\ \mathrm{ready}(\sigma, z),\ \lnot\mathrm{unfit}(B, z),\ \operatorname{before}_t(z, x),\ \mathit{id}(z) \ne \mathit{id}(x),\ \operatorname{chosen}(B, \sigma) = x \;\Rightarrow\; \lnot\mathrm{comp}(B, \sigma, z, x)$$
-/
theorem aged_not_overtaken (B : Vec) (σ : State) (z x : Item) (hz : z ∈ σ.queue)
    (hage : aged σ.t z = true) (hrd : ready σ z = true) (hfit : unfit B z = false)
    (hbef : before σ.t z x = true) (hne : z.id ≠ x.id) (hc : chosen B σ = some x) :
    comp B σ z x = false := by
  have hadm := (chosen_sound hc).2
  have hnh := ((admit_iff B σ x).mp hadm).2.2.2
  simp only [held, List.any_eq_false] at hnh
  have := hnh z hz
  simp only [heldBy, hbef, hage, hrd, hfit, Bool.not_false, Bool.and_true] at this
  simpa [hne] using this

/-! ## Events and traces

A trace applies one command per event and then runs `admitStep` until nothing more is admissible
(`admitAll`), so `admitStep` runs after every finish, enqueue and clock tick. -/

/-- At most `n` admit steps, stopping early when nothing is admissible.

$$\operatorname{admitN}(B, 0, \sigma) = \sigma, \qquad \operatorname{admitN}(B, n+1, \sigma) = \begin{cases} \sigma & \operatorname{chosen}(B, \sigma) = \bot \\ \operatorname{admitN}(B, n, \operatorname{admitStep}(B, \sigma)) & \text{otherwise} \end{cases}$$
-/
def admitN (B : Vec) : Nat → State → State
  | 0, σ => σ
  | n + 1, σ =>
    match chosen B σ with
    | none => σ
    | some _ => admitN B n (admitStep B σ)

/-- Admit until quiescent (`|Q|` steps always suffice).

$$\operatorname{admitAll}(B, \sigma) = \operatorname{admitN}(B, |Q|, \sigma)$$
-/
def admitAll (B : Vec) (σ : State) : State := admitN B σ.queue.length σ

/-- One trace event: apply a command, then admit until quiescent.

$$\operatorname{event}(B, \sigma, c) = \operatorname{admitAll}(B, \operatorname{step}(B, \sigma, c))$$
-/
def event (B : Vec) (σ : State) (c : Cmd) : State := admitAll B (step B σ c)

/-- A trace of events in which every running item ends before `start + dmax`: an event may only
move the clock to a time before the deadline of every item running before it.

$$\mathrm{Trace}_{B,d}(\sigma, \sigma), \qquad \big(\forall x \in \mathit{Run}(\sigma):\ t(\operatorname{event}(B, \sigma, c)) < \mathit{start}(x) + d\big) \land \mathrm{Trace}_{B,d}(\operatorname{event}(B, \sigma, c), \tau) \Rightarrow \mathrm{Trace}_{B,d}(\sigma, \tau)$$
-/
inductive Trace (B : Vec) (dmax : Nat) : State → State → Prop where
  | refl (σ : State) : Trace B dmax σ σ
  | cons {σ τ : State} (c : Cmd) :
      (∀ x ∈ σ.run, (event B σ c).t < x.start + dmax) → Trace B dmax (event B σ c) τ →
      Trace B dmax σ τ

/-- Finite sequences of single commands (the micro steps inside events).

$$\mathrm{Steps}_B(\sigma, \sigma), \qquad \mathrm{Steps}_B(\operatorname{step}(B, \sigma, c), \tau) \Rightarrow \mathrm{Steps}_B(\sigma, \tau)$$
-/
inductive Steps (B : Vec) : State → State → Prop where
  | refl (σ : State) : Steps B σ σ
  | head {σ τ : State} (c : Cmd) : Steps B (step B σ c) τ → Steps B σ τ

/-- Micro-step sequences compose.

$$\forall B, \sigma, \tau, \upsilon:\quad \mathrm{Steps}_B(\sigma, \tau) \land \mathrm{Steps}_B(\tau, \upsilon) \Rightarrow \mathrm{Steps}_B(\sigma, \upsilon)$$
-/
theorem Steps.trans {B : Vec} {σ τ υ : State} (h1 : Steps B σ τ) (h2 : Steps B τ υ) :
    Steps B σ υ := by
  induction h1 with
  | refl => exact h2
  | head c _ ih => exact .head c (ih h2)

/-- `admitN` is a sequence of admit commands.

$$\forall B, n, \sigma:\quad \mathrm{Steps}_B(\sigma, \operatorname{admitN}(B, n, \sigma))$$
-/
theorem steps_admitN (B : Vec) : ∀ (n : Nat) (σ : State), Steps B σ (admitN B n σ)
  | 0, σ => .refl σ
  | n + 1, σ => by
    simp only [admitN]
    split
    · exact .refl σ
    · exact .head .admit (steps_admitN B n (admitStep B σ))

/-- An event is a sequence of commands.

$$\forall B, \sigma, c:\quad \mathrm{Steps}_B(\sigma, \operatorname{event}(B, \sigma, c))$$
-/
theorem steps_event (B : Vec) (σ : State) (c : Cmd) : Steps B σ (event B σ c) :=
  .head c (steps_admitN B _ _)

/-- Admitting removes the admitted item from the queue, so the queue shrinks.

$$\forall B, \sigma, x:\quad \operatorname{chosen}(B, \sigma) = x \Rightarrow |Q(\operatorname{admitStep}(B, \sigma))| < |Q(\sigma)|$$
-/
theorem admitStep_shrinks {B : Vec} {σ : State} {x : Item} (h : chosen B σ = some x) :
    (admitStep B σ).queue.length < σ.queue.length := by
  simp only [admitStep, h]
  apply List.length_filter_lt_length_iff_exists.mpr
  exact ⟨x, (chosen_sound h).1, by simp⟩

/-- After at least `|Q|` admit steps nothing is admissible.

$$\forall B, n, \sigma:\quad |Q(\sigma)| \le n \Rightarrow \operatorname{chosen}(B, \operatorname{admitN}(B, n, \sigma)) = \bot$$
-/
theorem chosen_admitN (B : Vec) : ∀ (n : Nat) (σ : State), σ.queue.length ≤ n →
    chosen B (admitN B n σ) = none
  | 0, σ, h => by
    have : σ.queue = [] := List.eq_nil_of_length_eq_zero (Nat.le_zero.mp h)
    simp [admitN, chosen, this, pick]
  | n + 1, σ, h => by
    simp only [admitN]
    split
    · assumption
    · rename_i x hx
      have := admitStep_shrinks hx
      exact chosen_admitN B n _ (by omega)

/-- Every event ends quiescent: nothing queued is admissible.

$$\forall B, \sigma, c:\quad \operatorname{chosen}(B, \operatorname{event}(B, \sigma, c)) = \bot$$
-/
theorem chosen_event (B : Vec) (σ : State) (c : Cmd) : chosen B (event B σ c) = none :=
  chosen_admitN B _ _ (Nat.le_refl _)

/-! ## Liveness bookkeeping -/

/-- `o` is an older item that can ever fit (an older possible competitor of `z`).

$$\operatorname{oldOk}(B, z, o) \iff \mathit{seq}(o) < \mathit{seq}(z) \land \lnot\mathrm{unfit}(B, o)$$
-/
def oldOk (B : Vec) (z o : Item) : Bool := decide (o.seq < z.seq) && !unfit B o

/-- Eligible: aged and ready.

$$\operatorname{elig}(\sigma, o) \iff \mathrm{aged}(t, o) \land \mathrm{ready}(\sigma, o)$$
-/
def elig (σ : State) (o : Item) : Bool := aged σ.t o && ready σ o

/-- The liveness measure of `z`: queued older possible competitors, counted once more while they
are not yet eligible.

$$\Psi_{B,z}(\sigma) = \big|[\, o \in Q \mid \operatorname{oldOk}(B, z, o) \,]\big| + \big|[\, o \in Q \mid \operatorname{oldOk}(B, z, o) \land \lnot\operatorname{elig}(\sigma, o) \,]\big| \quad (\text{list filters, repeats counted})$$
-/
def psi (B : Vec) (z : Item) (σ : State) : Nat :=
  (σ.queue.filter (oldOk B z)).length + (σ.queue.filter fun o => oldOk B z o && !elig σ o).length

/-- Qualified items for the ghost invariant: no newer than `z`, can ever fit, and eligible.

$$\operatorname{qual}(B, z, \sigma, e) \iff \mathit{seq}(e) \le \mathit{seq}(z) \land \lnot\mathrm{unfit}(B, e) \land \operatorname{elig}(\sigma, e)$$
-/
def qual (B : Vec) (z : Item) (σ : State) (e : Item) : Bool :=
  decide (e.seq ≤ z.seq) && !unfit B e && elig σ e

/-- Filtering by a weaker predicate keeps at least as many items.

$$\forall l, p, q:\quad (\forall a \in l:\ p(a) \Rightarrow q(a)) \Rightarrow |[\, a \in l \mid p(a) \,]| \le |[\, a \in l \mid q(a) \,]|$$
-/
theorem len_filter_mono {α : Type} (l : List α) (p q : α → Bool)
    (h : ∀ a ∈ l, p a = true → q a = true) : (l.filter p).length ≤ (l.filter q).length := by
  induction l with
  | nil => simp
  | cons a l ih =>
    have ih := ih (fun b hb => h b (List.mem_cons_of_mem _ hb))
    have ha := h a (List.mem_cons_self ..)
    simp only [List.filter_cons]
    by_cases hp : p a = true
    · simp [hp, ha hp]; exact ih
    · simp only [hp, Bool.false_eq_true, ↓reduceIte]
      split <;> simp <;> omega

/-- ... and strictly fewer when some item satisfies only the weaker predicate.

$$\forall l, p, q:\quad (\forall a \in l:\ p(a) \Rightarrow q(a)) \land (\exists a \in l:\ q(a) \land \lnot p(a)) \Rightarrow |[\, a \in l \mid p(a) \,]| < |[\, a \in l \mid q(a) \,]|$$
-/
theorem len_filter_lt {α : Type} (l : List α) (p q : α → Bool)
    (h : ∀ a ∈ l, p a = true → q a = true) (hw : ∃ a ∈ l, q a = true ∧ p a = false) :
    (l.filter p).length < (l.filter q).length := by
  induction l with
  | nil => obtain ⟨a, ha, _⟩ := hw; cases ha
  | cons a l ih =>
    have hm := len_filter_mono l p q (fun b hb => h b (List.mem_cons_of_mem _ hb))
    have ha := h a (List.mem_cons_self ..)
    obtain ⟨b, hb, hqb, hpb⟩ := hw
    simp only [List.filter_cons]
    rcases List.mem_cons.mp hb with rfl | hb
    · simp [hqb, hpb]; omega
    · have ih := ih (fun c hc => h c (List.mem_cons_of_mem _ hc)) ⟨b, hb, hqb, hpb⟩
      by_cases hp : p a = true
      · simp [hp, ha hp]; exact ih
      · simp only [hp, Bool.false_eq_true, ↓reduceIte]
        split <;> simp <;> omega

/-- Demand summed over a sublist is at most the sum over the list.

$$\forall l', l, r:\quad l' \text{ a sublist of } l \Rightarrow \operatorname{used}(l', r) \le \operatorname{used}(l, r)$$
-/
theorem used_sublist {l' l : List Item} (h : l'.Sublist l) (r : Res) : used l' r ≤ used l r := by
  induction h with
  | slnil => exact Nat.le_refl _
  | cons a _ ih => simp only [used]; omega
  | cons_cons a _ ih => simp only [used]; omega

/-- An item that is not unfit fits in the empty machine.

$$\forall B, x:\quad \lnot\mathrm{unfit}(B, x) \Rightarrow \forall r \in \mathcal R:\ d(x)(r) \le B(r)$$
-/
theorem le_of_not_unfit {B : Vec} {x : Item} (h : unfit B x = false) : ∀ r, x.demand.get r ≤ B.get r := by
  simp only [unfit, List.any_eq_false, decide_eq_true_eq, Nat.not_lt] at h
  exact fun r => h r (Res.mem_all r)

/-- Aged items have effective priority 0.

$$\forall t, z:\quad \mathrm{aged}(t, z) \Rightarrow \operatorname{eff}_t(z) = 0$$
-/
theorem eff_aged {t : Nat} {z : Item} (h : aged t z = true) : Fw.DeviceQueue.eff t z.job = 0 := by
  simp only [aged, decide_eq_true_eq] at h
  have hd : z.base ≤ (t - z.enq) / A := by
    apply (Nat.le_div_iff_mul_le (by decide)).mpr
    rw [Nat.mul_comm]; omega
  simp only [Fw.DeviceQueue.eff, Item.job]
  omega

/-- An aged item goes before every item with a larger or equal arrival number.

$$\forall t, e, x:\quad \mathrm{aged}(t, e) \land \mathit{seq}(e) \le \mathit{seq}(x) \Rightarrow \operatorname{before}_t(e, x)$$
-/
theorem before_of_aged {t : Nat} {e x : Item} (h : aged t e = true) (hs : e.seq ≤ x.seq) :
    before t e x = true := by
  have he := eff_aged h
  simp only [before, Fw.DeviceQueue.before, decide_eq_true_eq] at he ⊢
  simp only [Item.job] at he ⊢
  omega

/-- Between two aged items, `before` is arrival order.

$$\forall t, a, b:\quad \mathrm{aged}(t, a) \land \mathrm{aged}(t, b) \land \operatorname{before}_t(a, b) \Rightarrow \mathit{seq}(a) \le \mathit{seq}(b)$$
-/
theorem seq_le_of_before {t : Nat} {a b : Item} (ha : aged t a = true) (hb : aged t b = true)
    (h : before t a b = true) : a.seq ≤ b.seq := by
  have h1 := eff_aged ha
  have h2 := eff_aged hb
  simp only [before, Fw.DeviceQueue.before, decide_eq_true_eq] at h
  simp only [Item.job] at h h1 h2
  omega

/-- Aging is monotone in time.

$$\forall t, t', z:\quad \mathrm{aged}(t, z) \land t \le t' \Rightarrow \mathrm{aged}(t', z)$$
-/
theorem aged_mono {t t' : Nat} {z : Item} (h : aged t z = true) (ht : t ≤ t') : aged t' z = true := by
  simp only [aged, decide_eq_true_eq] at h ⊢; omega

/-- Readiness is monotone in the landed set.

$$\forall \sigma, \sigma', x:\quad \mathit{Done}(\sigma) \subseteq \mathit{Done}(\sigma') \land \mathrm{ready}(\sigma, x) \Rightarrow \mathrm{ready}(\sigma', x)$$
-/
theorem ready_mono {σ σ' : State} {x : Item} (hd : ∀ e ∈ σ.done, e ∈ σ'.done)
    (h : ready σ x = true) : ready σ' x = true := by
  simp only [ready, List.all_eq_true, List.contains_iff_mem] at h ⊢
  exact fun e he => hd e (h e he)

/-- Eligibility is monotone in time and in the landed set.

$$\forall \sigma, \sigma', o:\quad t(\sigma) \le t(\sigma') \land \mathit{Done}(\sigma) \subseteq \mathit{Done}(\sigma') \land \operatorname{elig}(\sigma, o) \Rightarrow \operatorname{elig}(\sigma', o)$$
-/
theorem elig_mono {σ σ' : State} {o : Item} (ht : σ.t ≤ σ'.t) (hd : ∀ e ∈ σ.done, e ∈ σ'.done)
    (h : elig σ o = true) : elig σ' o = true := by
  simp only [elig, Bool.and_eq_true] at h ⊢
  exact ⟨aged_mono h.1 ht, ready_mono hd h.2⟩

/-- The clock never runs backwards.

$$\forall B, \sigma, c:\quad t(\sigma) \le t(\operatorname{step}(B, \sigma, c))$$
-/
theorem t_step (B : Vec) (σ : State) (c : Cmd) : σ.t ≤ (step B σ c).t := by
  cases c with
  | admit => simp only [step, admitStep]; split <;> exact Nat.le_refl _
  | finish i l => exact Nat.le_refl _
  | enqueue x => simp only [step, enqueue]; split <;> exact Nat.le_refl _
  | tick n => exact Nat.le_max_left _ _

/-- `next` never decreases.

$$\forall B, \sigma, c:\quad \mathit{next}(\sigma) \le \mathit{next}(\operatorname{step}(B, \sigma, c))$$
-/
theorem next_step (B : Vec) (σ : State) (c : Cmd) : σ.next ≤ (step B σ c).next := by
  cases c with
  | admit => simp only [step, admitStep]; split <;> exact Nat.le_refl _
  | finish i l => exact Nat.le_refl _
  | enqueue x => simp only [step, enqueue]; split <;> simp
  | tick n => exact Nat.le_refl _

/-- Every item queued after a step was queued before, or is the newly enqueued item numbered
`next`.

$$\forall B, \sigma, c, y:\quad y \in Q(\operatorname{step}(B, \sigma, c)) \Rightarrow y \in Q(\sigma) \lor \mathit{seq}(y) = \mathit{next}(\sigma)$$
-/
theorem queue_step (B : Vec) (σ : State) (c : Cmd) (y : Item) (h : y ∈ (step B σ c).queue) :
    y ∈ σ.queue ∨ y.seq = σ.next := by
  cases c with
  | admit =>
    simp only [step, admitStep] at h; split at h
    · exact .inl (List.mem_filter.mp h).1
    · exact .inl h
  | finish i l => exact .inl h
  | enqueue x =>
    simp only [step, enqueue] at h; split at h
    · exact .inl h
    · simp only [List.mem_append, List.mem_singleton] at h
      rcases h with h | rfl
      · exact .inl h
      · exact .inr rfl
  | tick n => exact .inl h

/-- `z` has left the queue for good: its number is used and no queued item carries it.

$$\operatorname{gone}(z, \sigma) \iff \mathit{seq}(z) < \mathit{next} \land \forall y \in Q:\ \mathit{seq}(y) \ne \mathit{seq}(z)$$
-/
def Gone (z : Item) (σ : State) : Prop := z.seq < σ.next ∧ ∀ y ∈ σ.queue, y.seq ≠ z.seq

/-- Once gone, `z` stays gone along micro steps.

$$\forall B, z, \sigma, \tau:\quad \mathrm{Steps}_B(\sigma, \tau) \land \operatorname{gone}(z, \sigma) \Rightarrow \operatorname{gone}(z, \tau)$$
-/
theorem gone_steps {B : Vec} {z : Item} {σ τ : State} (h : Steps B σ τ) (hg : Gone z σ) : Gone z τ := by
  induction h with
  | refl => exact hg
  | head c _ ih =>
    apply ih
    rename_i σ0 _ _
    refine ⟨Nat.lt_of_lt_of_le hg.1 (next_step B σ0 c), fun y hy => ?_⟩
    rcases queue_step B σ0 c y hy with hy | hy
    · exact hg.2 y hy
    · have := hg.1; omega

/-- Once gone, `z` stays gone along a trace.

$$\forall B, d, z, \sigma, \tau:\quad \mathrm{Trace}_{B,d}(\sigma, \tau) \land \operatorname{gone}(z, \sigma) \Rightarrow \operatorname{gone}(z, \tau)$$
-/
theorem gone_trace {B : Vec} {dmax : Nat} {z : Item} {σ τ : State} (h : Trace B dmax σ τ)
    (hg : Gone z σ) : Gone z τ := by
  induction h with
  | refl => exact hg
  | cons c _ _ ih => exact ih (gone_steps (steps_event B _ c) hg)

/-- The frame of the liveness argument, relative to `z`, the arrival numbers `G` of the items
running at the start, and the start time `t0`.

$$\mathrm{Base}(B, z, G, t_0, \sigma) \iff \begin{aligned}[t] & \mathrm{Inv}(B, \sigma) \land \mathrm{aged}(t, z) \land \mathrm{ready}(\sigma, z) \land \mathit{seq}(z) < \mathit{next} \land \big(\forall g \in G:\ g < \mathit{next}\big) \\ & \land \big(\forall y \in Q:\ \mathit{seq}(y) \notin G\big) \land \big(\forall y \in \mathit{Run}:\ \mathit{seq}(y) \in G \Rightarrow \mathit{start}(y) \le t_0\big) \\ & \land \big(z \in Q \lor \forall y \in Q:\ \mathit{seq}(y) \ne \mathit{seq}(z)\big) \end{aligned}$$
-/
structure Base (B : Vec) (z : Item) (G : List Nat) (t0 : Nat) (σ : State) : Prop where
  inv    : Inv B σ
  zAged  : aged σ.t z = true
  zReady : ready σ z = true
  znext  : z.seq < σ.next
  gnext  : ∀ g ∈ G, g < σ.next
  qG     : ∀ y ∈ σ.queue, y.seq ∉ G
  rG     : ∀ y ∈ σ.run, y.seq ∈ G → y.start ≤ t0
  zq     : z ∈ σ.queue ∨ ∀ y ∈ σ.queue, y.seq ≠ z.seq

/-- The ghost invariant: every qualified queued item is free of, and fits beside, the items
started since the beginning (those whose number is not in `G`).

$$\mathrm{Ghost}(B, z, G, \sigma) \iff \forall e \in Q,\ \operatorname{qual}(B, z, \sigma, e):\ \big(\forall y \in \mathit{Run},\ \mathit{seq}(y) \notin G:\ \lnot(e \bowtie y) \land V(e) \cap V(y) = \emptyset\big) \land \forall r \in \mathcal R:\ d(e)(r) + \textstyle\sum_{y \in \mathit{Run},\ \mathit{seq}(y) \notin G} d(y)(r) \le B(r)$$
-/
structure Ghost (B : Vec) (z : Item) (G : List Nat) (σ : State) : Prop where
  conf : ∀ e ∈ σ.queue, qual B z σ e = true → ∀ y ∈ σ.run, y.seq ∉ G →
    wconf e y = false ∧ devShare e y = false
  room : ∀ e ∈ σ.queue, qual B z σ e = true → ∀ r,
    e.demand.get r + used (σ.run.filter fun y => !G.contains y.seq) r ≤ B.get r

/-- Two queued items with the same arrival number are equal (given the invariant).

$$\forall B, \sigma, a, b:\quad \mathrm{Inv}(B, \sigma) \land a, b \in Q \land \mathit{seq}(a) = \mathit{seq}(b) \Rightarrow a = b$$
-/
theorem eq_of_seq {B : Vec} {σ : State} {a b : Item} (h : Inv B σ) (ha : a ∈ σ.queue)
    (hb : b ∈ σ.queue) (hs : a.seq = b.seq) : a = b :=
  eq_of_nodup_map Item.seq h.seqs (List.mem_append_right _ ha) (List.mem_append_right _ hb) hs

/-- Two queued items with the same id are equal (given the invariant).

$$\forall B, \sigma, a, b:\quad \mathrm{Inv}(B, \sigma) \land a, b \in Q \land \mathit{id}(a) = \mathit{id}(b) \Rightarrow a = b$$
-/
theorem eq_of_id {B : Vec} {σ : State} {a b : Item} (h : Inv B σ) (ha : a ∈ σ.queue)
    (hb : b ∈ σ.queue) (hs : a.id = b.id) : a = b :=
  eq_of_nodup_map Item.id h.ids (List.mem_append_right _ ha) (List.mem_append_right _ hb) hs

/-- A queued item numbered like `z` is eligible (from the frame).

$$\forall B, z, G, t_0, \sigma, e:\quad \mathrm{Base}(B, z, G, t_0, \sigma) \land e \in Q \land \mathit{seq}(e) = \mathit{seq}(z) \Rightarrow \operatorname{elig}(\sigma, e)$$
-/
theorem elig_of_seq_eq {B : Vec} {z : Item} {G : List Nat} {t0 : Nat} {σ : State} {e : Item}
    (hb : Base B z G t0 σ) (he : e ∈ σ.queue) (hs : e.seq = z.seq) : elig σ e = true := by
  rcases hb.zq with hz | hz
  · rw [eq_of_seq hb.inv he hz hs]; simp [elig, hb.zAged, hb.zReady]
  · exact absurd hs (hz e he)

/-- The frame is preserved by every command.

$$\forall B, z, G, t_0, \sigma, c:\quad \mathrm{Base}(B, z, G, t_0, \sigma) \Rightarrow \mathrm{Base}(B, z, G, t_0, \operatorname{step}(B, \sigma, c))$$
-/
theorem base_step {B : Vec} {z : Item} {G : List Nat} {t0 : Nat} {σ : State} (c : Cmd)
    (hb : Base B z G t0 σ) : Base B z G t0 (step B σ c) := by
  have hinv := inv_step B σ c hb.inv
  have hnext := next_step B σ c
  have ht := t_step B σ c
  have hdone := done_grows B σ c
  have hzn := hb.znext
  refine ⟨hinv, aged_mono hb.zAged ht, ready_mono hdone hb.zReady, by omega,
    fun g hg => by have := hb.gnext g hg; omega, ?_, ?_, ?_⟩
  · intro y hy
    rcases queue_step B σ c y hy with hy | hy
    · exact hb.qG y hy
    · intro hg; have := hb.gnext _ hg; omega
  · cases c with
    | admit =>
      simp only [step, admitStep]; split
      · rename_i x hx
        intro y hy hg
        rcases List.mem_cons.mp hy with rfl | hy
        · exact absurd hg (hb.qG x (chosen_sound hx).1)
        · exact hb.rG y hy hg
      · exact hb.rG
    | finish i l =>
      intro y hy; exact hb.rG y (List.mem_filter.mp hy).1
    | enqueue x => simp only [step, enqueue]; split <;> exact hb.rG
    | tick n => exact hb.rG
  · cases c with
    | admit =>
      simp only [step, admitStep]; split
      · rename_i x hx
        by_cases hzx : z.id = x.id
        · right
          intro y hy hs
          obtain ⟨hyq, hyx⟩ := List.mem_filter.mp hy
          rcases hb.zq with hz | hz
          · have := eq_of_seq hb.inv hyq hz hs
            subst this; simp [hzx] at hyx
          · exact hz y hyq hs
        · rcases hb.zq with hz | hz
          · left; exact List.mem_filter.mpr ⟨hz, by simpa using hzx⟩
          · right; intro y hy; exact hz y (List.mem_filter.mp hy).1
      · exact hb.zq
    | finish i l => exact hb.zq
    | enqueue x =>
      simp only [step, enqueue]; split
      · exact hb.zq
      · rcases hb.zq with hz | hz
        · left; exact List.mem_append_left _ hz
        · right
          intro y hy
          simp only [List.mem_append, List.mem_singleton] at hy
          rcases hy with hy | rfl
          · exact hz y hy
          · have := hb.znext; simp only; omega
    | tick n => exact hb.zq

/-- The frame is preserved along micro steps.

$$\forall B, z, G, t_0, \sigma, \tau:\quad \mathrm{Steps}_B(\sigma, \tau) \land \mathrm{Base}(B, z, G, t_0, \sigma) \Rightarrow \mathrm{Base}(B, z, G, t_0, \tau)$$
-/
theorem base_steps {B : Vec} {z : Item} {G : List Nat} {t0 : Nat} {σ τ : State}
    (h : Steps B σ τ) (hb : Base B z G t0 σ) : Base B z G t0 τ := by
  induction h with
  | refl => exact hb
  | head c _ ih => exact ih (base_step c hb)

/-- When the queue is unchanged and eligibility only grows, the measure does not grow, and it
stays equal only if no older possible competitor became eligible.

$$\forall B, z, \sigma, \sigma':\quad Q(\sigma') = Q(\sigma) \land (\forall o:\ \operatorname{elig}(\sigma, o) \Rightarrow \operatorname{elig}(\sigma', o)) \Rightarrow \Psi(\sigma') \le \Psi(\sigma) \land \big(\Psi(\sigma') = \Psi(\sigma) \Rightarrow \forall o \in Q:\ \operatorname{oldOk}(B, z, o) \land \operatorname{elig}(\sigma', o) \Rightarrow \operatorname{elig}(\sigma, o)\big)$$
-/
theorem psi_elig {B : Vec} {z : Item} {σ σ' : State} (hq : σ'.queue = σ.queue)
    (he : ∀ o, elig σ o = true → elig σ' o = true) :
    psi B z σ' ≤ psi B z σ ∧ (psi B z σ' = psi B z σ →
      ∀ o ∈ σ.queue, oldOk B z o = true → elig σ' o = true → elig σ o = true) := by
  have hmono : ∀ a ∈ σ.queue, (oldOk B z a && !elig σ' a) = true → (oldOk B z a && !elig σ a) = true := by
    intro a _ h
    simp only [Bool.and_eq_true, Bool.not_eq_true'] at h ⊢
    refine ⟨h.1, ?_⟩
    cases hx : elig σ a
    · rfl
    · have := he a hx; rw [h.2] at this; cases this
  unfold psi; rw [hq]
  refine ⟨by have := len_filter_mono _ _ _ hmono; omega, fun heq o ho hok hel => ?_⟩
  cases hx : elig σ o
  · have := len_filter_lt _ _ _ hmono ⟨o, ho, by simp [hok, hx], by simp [hel]⟩
    omega
  · rfl

/-- Admitting `x` does not grow the measure, and strictly shrinks it when `x` is an older possible
competitor.

$$\forall B, z, \sigma, x:\quad \operatorname{chosen}(B, \sigma) = x \Rightarrow \Psi(\operatorname{admitStep}(B, \sigma)) \le \Psi(\sigma) \land \big(\operatorname{oldOk}(B, z, x) \Rightarrow \Psi(\operatorname{admitStep}(B, \sigma)) < \Psi(\sigma)\big)$$
-/
theorem psi_admit {B : Vec} {z : Item} {σ : State} {x : Item} (hc : chosen B σ = some x) :
    psi B z (admitStep B σ) ≤ psi B z σ ∧
      (oldOk B z x = true → psi B z (admitStep B σ) < psi B z σ) := by
  have hx := (chosen_sound hc).1
  have hel : ∀ a, elig (admitStep B σ) a = elig σ a := by
    intro a; simp only [admitStep, hc]; rfl
  have hQ : (admitStep B σ).queue = σ.queue.filter (·.id != x.id) := by simp [admitStep, hc]
  unfold psi
  simp only [hel, hQ, List.filter_filter]
  have e1 : ∀ a ∈ σ.queue, (oldOk B z a && (a.id != x.id)) = true → oldOk B z a = true := by
    intro a _ h; simp only [Bool.and_eq_true] at h; exact h.1
  have e2 : ∀ a ∈ σ.queue, ((oldOk B z a && !elig σ a) && (a.id != x.id)) = true →
      (oldOk B z a && !elig σ a) = true := by
    intro a _ h; simp only [Bool.and_eq_true] at h; simp only [Bool.and_eq_true]; exact h.1
  have m1 := len_filter_mono _ _ _ e1
  have m2 := len_filter_mono _ _ _ e2
  refine ⟨by omega, fun hok => ?_⟩
  have := len_filter_lt _ _ _ e1 ⟨x, hx, hok, by simp⟩
  omega

/-- The measure never grows under a command.

$$\forall B, z, G, t_0, \sigma, c:\quad \mathrm{Base}(B, z, G, t_0, \sigma) \Rightarrow \Psi(\operatorname{step}(B, \sigma, c)) \le \Psi(\sigma)$$
-/
theorem psi_step {B : Vec} {z : Item} {G : List Nat} {t0 : Nat} {σ : State} (c : Cmd)
    (hb : Base B z G t0 σ) : psi B z (step B σ c) ≤ psi B z σ := by
  cases c with
  | admit =>
    simp only [step]
    cases hc : chosen B σ with
    | none => simp [admitStep, hc]
    | some x => exact (psi_admit hc).1
  | finish i l =>
    exact (psi_elig (σ := σ) (σ' := step B σ (.finish i l)) rfl
      (fun o h => elig_mono (σ := σ) (Nat.le_refl _) (done_grows B σ _) h)).1
  | enqueue x =>
    simp only [step, enqueue]; split
    · exact Nat.le_refl _
    · simp only [psi, List.filter_append]
      have hz := hb.znext
      have : oldOk B z { x with seq := σ.next, enq := σ.t } = false := by
        simp [oldOk]; omega
      simp [this, elig, ready, aged]
  | tick n =>
    exact (psi_elig (σ := σ) (σ' := step B σ (.tick n)) rfl
      (fun o h => elig_mono (t_step B σ _) (fun _ h => h) h)).1

/-- The ghost invariant survives every command that leaves the measure unchanged.

$$\forall B, z, G, t_0, \sigma, c:\quad \mathrm{Base}(B, z, G, t_0, \sigma) \land \mathrm{Ghost}(B, z, G, \sigma) \land \Psi(\operatorname{step}(B, \sigma, c)) = \Psi(\sigma) \Rightarrow \mathrm{Ghost}(B, z, G, \operatorname{step}(B, \sigma, c))$$
-/
theorem ghost_step {B : Vec} {z : Item} {G : List Nat} {t0 : Nat} {σ : State} (c : Cmd)
    (hb : Base B z G t0 σ) (hg : Ghost B z G σ) (hpsi : psi B z (step B σ c) = psi B z σ) :
    Ghost B z G (step B σ c) := by
  -- qualified after a clock or landing step means qualified before
  have back : ∀ σ' : State, σ'.queue = σ.queue → (∀ o, elig σ o = true → elig σ' o = true) →
      psi B z σ' = psi B z σ → ∀ e ∈ σ.queue, qual B z σ' e = true → qual B z σ e = true := by
    intro σ' hq he heq e hm hqual
    have h2 := (psi_elig (z := z) hq he).2 heq
    simp only [qual, Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at hqual ⊢
    refine ⟨⟨hqual.1.1, hqual.1.2⟩, ?_⟩
    rcases Nat.lt_or_eq_of_le hqual.1.1 with hlt | heq'
    · exact h2 e hm (by simp [oldOk, hlt, hqual.1.2]) hqual.2
    · exact elig_of_seq_eq hb hm heq'
  cases c with
  | admit =>
    simp only [step] at hpsi ⊢
    cases hc : chosen B σ with
    | none => simp only [admitStep, hc]; exact hg
    | some x =>
      obtain ⟨hxq, hadm⟩ := chosen_sound hc
      obtain ⟨_, _, hfit, _⟩ := (admit_iff B σ x).mp hadm
      have hxok : oldOk B z x = false := by
        cases h : oldOk B z x
        · rfl
        · have := (psi_admit (z := z) hc).2 h; omega
      have hxs : z.seq ≤ x.seq := by
        simp [oldOk, fits_not_unfit hfit] at hxok; exact hxok
      have hqe : ∀ e, qual B z (admitStep B σ) e = qual B z σ e := by
        intro e; simp only [admitStep, hc]; rfl
      have hQ : (admitStep B σ).queue = σ.queue.filter (·.id != x.id) := by simp [admitStep, hc]
      have hR : (admitStep B σ).run = { x with start := σ.t } :: σ.run := by simp [admitStep, hc]
      clear hpsi
      -- each qualified queued `e` does not compete with `x`
      have hcomp : ∀ e ∈ σ.queue.filter (·.id != x.id), qual B z σ e = true → comp B σ e x = false := by
        intro e he hq
        obtain ⟨heq, hne⟩ := List.mem_filter.mp he
        simp only [bne_iff_ne, ne_eq] at hne
        simp only [qual, elig, Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at hq
        have hsne : e.seq ≠ x.seq := fun hs => hne (by rw [eq_of_seq hb.inv heq hxq hs])
        exact aged_not_overtaken B σ e x heq hq.2.1 hq.2.2 hq.1.2
          (before_of_aged hq.2.1 (by omega)) hne hc
      refine ⟨?_, ?_⟩
      · intro e he hq y hy hyG; rw [hQ] at he; rw [hR] at hy
        rw [hqe] at hq
        have hc' := hcomp e he hq
        simp only [comp, Bool.or_eq_false_iff] at hc'
        rcases List.mem_cons.mp hy with rfl | hy
        · exact ⟨hc'.1.1, hc'.1.2⟩
        · exact hg.conf e (List.mem_filter.mp he).1 hq y hy hyG
      · intro e he hq r; rw [hQ] at he; rw [hR]
        rw [hqe] at hq
        have hc' := hcomp e he hq
        simp only [comp, Bool.or_eq_false_iff, List.any_eq_false, decide_eq_true_eq,
          Nat.not_lt] at hc'
        have hr := hc'.2 r (Res.mem_all r)
        have hxG : (!G.contains x.seq) = true := by
          simpa using hb.qG x hxq
        simp only [List.filter_cons, hxG, ↓reduceIte, used]
        have := used_filter_le (fun y => !G.contains y.seq) σ.run r
        omega
  | finish i l =>
    have hq := back (step B σ (.finish i l)) rfl
      (fun o h => elig_mono (σ := σ) (Nat.le_refl _) (done_grows B σ _) h) hpsi
    refine ⟨fun e he hqe y hy hyG => hg.conf e he (hq e he hqe) y (List.mem_filter.mp hy).1 hyG,
      fun e he hqe r => ?_⟩
    have := hg.room e he (hq e he hqe) r
    have hs : ((σ.run.filter (·.id != i)).filter fun y => !G.contains y.seq).Sublist
        (σ.run.filter fun y => !G.contains y.seq) :=
      List.Sublist.filter _ List.filter_sublist
    have := used_sublist hs r
    simp only [step, finish]
    omega
  | enqueue x =>
    simp only [step, enqueue] at hpsi ⊢; split
    · exact hg
    · have hz := hb.znext
      refine ⟨fun e he hqe y hy hyG => ?_, fun e he hqe r => ?_⟩
      · simp only [List.mem_append, List.mem_singleton] at he
        rcases he with he | rfl
        · exact hg.conf e he hqe y hy hyG
        · simp [qual] at hqe; omega
      · simp only [List.mem_append, List.mem_singleton] at he
        rcases he with he | rfl
        · exact hg.room e he hqe r
        · simp [qual] at hqe; omega
  | tick n =>
    have hq := back (step B σ (.tick n)) rfl
      (fun o h => elig_mono (t_step B σ _) (fun _ h => h) h) hpsi
    exact ⟨fun e he hqe => hg.conf e he (hq e he hqe), fun e he hqe => hg.room e he (hq e he hqe)⟩

/-- Along micro steps the measure never grows, and the ghost invariant survives if the measure is
unchanged.

$$\forall B, z, G, t_0, \sigma, \tau:\quad \mathrm{Steps}_B(\sigma, \tau) \land \mathrm{Base}(B, z, G, t_0, \sigma) \Rightarrow \Psi(\tau) \le \Psi(\sigma) \land \big(\mathrm{Ghost}(B, z, G, \sigma) \land \Psi(\tau) = \Psi(\sigma) \Rightarrow \mathrm{Ghost}(B, z, G, \tau)\big)$$
-/
theorem ghost_steps {B : Vec} {z : Item} {G : List Nat} {t0 : Nat} {σ τ : State}
    (h : Steps B σ τ) (hb : Base B z G t0 σ) :
    psi B z τ ≤ psi B z σ ∧ (Ghost B z G σ → psi B z τ = psi B z σ → Ghost B z G τ) := by
  induction h with
  | refl => exact ⟨Nat.le_refl _, fun hg _ => hg⟩
  | head c _ ih =>
    rename_i σ0 _ _
    have h1 := psi_step c hb
    obtain ⟨ih1, ih2⟩ := ih (base_step c hb)
    refine ⟨by omega, fun hg heq => ih2 (ghost_step c hb hg (by omega)) (by omega)⟩

/-- **The stuck state is impossible.** In a quiescent state where the frame and the ghost invariant
hold, no item started before the beginning still runs, and `z` is queued, the least-numbered
qualified item would be admissible.

$$\forall B, z, G, t_0, \sigma:\quad \mathrm{Base} \land \mathrm{Ghost} \land \operatorname{chosen}(B, \sigma) = \bot \land (\forall y \in \mathit{Run}:\ \mathit{seq}(y) \notin G) \land z \in Q \land \lnot\mathrm{unfit}(B, z) \Rightarrow \bot$$
-/
theorem stuck_false {B : Vec} {z : Item} {G : List Nat} {t0 : Nat} {σ : State}
    (hb : Base B z G t0 σ) (hg : Ghost B z G σ) (hq : chosen B σ = none)
    (hgone : ∀ y ∈ σ.run, y.seq ∉ G) (hz : z ∈ σ.queue) (hfit : unfit B z = false) : False := by
  have key : ∀ n, ∀ e ∈ σ.queue, qual B z σ e = true → e.seq = n → False := by
    intro n
    induction n using Nat.strongRecOn with
    | _ n ih =>
      intro e he hqe hn
      have hadm : admit B σ e = .admit := by
        have hq' := hqe
        simp only [qual, elig, Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at hq'
        refine (admit_iff B σ e).mpr ⟨hq'.2.2, ?_, ?_, ?_⟩
        · rw [free_iff]
          intro y hy _
          exact hg.conf e he hqe y hy (hgone y hy)
        · have hf : (σ.run.filter fun y => !G.contains y.seq) = σ.run := by
            apply List.filter_eq_self.mpr
            intro y hy; simpa using hgone y hy
          have := hg.room e he hqe
          rw [hf] at this
          simp only [fits, List.all_eq_true, decide_eq_true_eq]
          exact fun r _ => this r
        · cases hh : held B σ e
          · rfl
          · exfalso
            simp only [held, List.any_eq_true] at hh
            obtain ⟨w, hw, hhw⟩ := hh
            simp only [heldBy, Bool.and_eq_true, bne_iff_ne, ne_eq, Bool.not_eq_true'] at hhw
            obtain ⟨⟨⟨⟨⟨hid, hbef⟩, hwag⟩, hwrd⟩, hwfit⟩, _⟩ := hhw
            have hle := seq_le_of_before hwag hq'.2.1 hbef
            have hne : w.seq ≠ e.seq := fun hs => hid (by rw [eq_of_seq hb.inv hw he hs])
            refine ih w.seq (by omega) w hw ?_ rfl
            simp [qual, elig, hwag, hwrd, hwfit]; omega
      exact admit_conserving B σ e he hadm hq
  have hqz : qual B z σ z = true := by simp [qual, elig, hfit, hb.zAged, hb.zReady]
  exact key z.seq z hz hqz rfl

/-- **One phase of the liveness argument.** Starting in a quiescent state inside the frame with
measure `k`, time before `t0 + dmax` and the ghost invariant, a trace that still has `z` queued
at its end either ends before `t0 + dmax`, or passes a quiescent state, before `t0 + dmax`, where
the measure has dropped below `k`.

$$\forall B, d, z, G, t_0, k, \sigma, \sigma_j:\quad \mathrm{Trace}_{B,d}(\sigma, \sigma_j) \land \mathrm{Base}(\sigma) \land \mathrm{Ghost}(\sigma) \land \Psi(\sigma) = k \land \operatorname{chosen}(B, \sigma) = \bot \land t(\sigma) < t_0 + d \land \lnot\mathrm{unfit}(B, z) \land z \in Q(\sigma_j) \Rightarrow t(\sigma_j) < t_0 + d \lor \exists \sigma_a:\ \mathrm{Trace}_{B,d}(\sigma_a, \sigma_j) \land \mathrm{Base}(\sigma_a) \land \operatorname{chosen}(B, \sigma_a) = \bot \land \Psi(\sigma_a) < k \land t(\sigma_a) < t_0 + d$$
-/
theorem phase {B : Vec} {dmax : Nat} {z : Item} {G : List Nat} {t0 k : Nat} {σ σj : State}
    (htr : Trace B dmax σ σj) (hb : Base B z G t0 σ) (hg : Ghost B z G σ) (hk : psi B z σ = k)
    (hq : chosen B σ = none) (ht : σ.t < t0 + dmax) (hfit : unfit B z = false)
    (hzj : z ∈ σj.queue) :
    σj.t < t0 + dmax ∨ ∃ σa, Trace B dmax σa σj ∧ Base B z G t0 σa ∧ chosen B σa = none ∧
      psi B z σa < k ∧ σa.t < t0 + dmax := by
  induction htr with
  | refl => exact .inl ht
  | cons c hside htr' ih =>
    rename_i σ0 _
    have hst := steps_event B σ0 c
    have hb1 := base_steps hst hb
    obtain ⟨hle, hgh⟩ := ghost_steps hst hb
    by_cases hlate : t0 + dmax ≤ (event B σ0 c).t
    · exfalso
      have hgone : ∀ y ∈ σ0.run, y.seq ∉ G := by
        intro y hy hyG
        have := hb.rG y hy hyG
        have := hside y hy
        omega
      rcases hb.zq with hz | hz
      · exact stuck_false hb hg hq hgone hz hfit
      · have := gone_trace (z := z) (.cons c hside htr') ⟨hb.znext, hz⟩
        exact this.2 z hzj rfl
    · have ht1 : (event B σ0 c).t < t0 + dmax := by omega
      by_cases hlt : psi B z (event B σ0 c) < k
      · exact .inr ⟨_, htr', hb1, chosen_event B σ0 c, hlt, ht1⟩
      · exact ih hb1 (hgh hg (by omega)) (by omega) (chosen_event B σ0 c) ht1 hzj

/-- **An aged job is admitted in bounded time** (restated `aged_admitted_by`). Take a quiescent
state satisfying the invariant in which `z` is queued, aged, ready and can ever fit. Along any
trace where every running job ends before `start + dmax` (with `dmax > 0`), every later state that
still has `z` queued has clock below `t + (1 + \Psi) \cdot dmax`, where `\Psi` counts the queued
older items that can ever fit, twice for those not yet eligible.

$$\forall B, d, \sigma_i, \sigma_j, z:\quad d > 0 \land \mathrm{Inv}(B, \sigma_i) \land \operatorname{chosen}(B, \sigma_i) = \bot \land z \in Q(\sigma_i) \land \mathrm{aged}(t(\sigma_i), z) \land \mathrm{ready}(\sigma_i, z) \land \lnot\mathrm{unfit}(B, z) \land \mathrm{Trace}_{B,d}(\sigma_i, \sigma_j) \land z \in Q(\sigma_j) \Rightarrow t(\sigma_j) < t(\sigma_i) + (1 + \Psi_{B,z}(\sigma_i)) \cdot d$$
-/
theorem aged_admitted_by (B : Vec) (dmax : Nat) (hd : 0 < dmax) :
    ∀ (σi σj : State) (z : Item), Inv B σi → chosen B σi = none → z ∈ σi.queue →
      aged σi.t z = true → ready σi z = true → unfit B z = false → Trace B dmax σi σj →
      z ∈ σj.queue → σj.t < σi.t + (1 + psi B z σi) * dmax := by
  intro σi σj z hinv hq hz hag hrd hfit htr hzj
  generalize hk : psi B z σi = k
  induction k using Nat.strongRecOn generalizing σi with
  | _ k ih =>
    let G := σi.run.map Item.seq
    have hsplit := hinv.seqs
    rw [List.map_append, List.nodup_append] at hsplit
    have hb : Base B z G σi.t σi := by
      refine ⟨hinv, hag, hrd, hinv.fresh z (List.mem_append_right _ hz), ?_, ?_, ?_, .inl hz⟩
      · intro g hg
        obtain ⟨y, hy, rfl⟩ := List.mem_map.mp hg
        exact hinv.fresh y (List.mem_append_left _ hy)
      · intro y hy hyG
        exact hsplit.2.2 _ hyG _ (List.mem_map_of_mem hy) rfl
      · intro y hy _; exact hinv.started y hy
    have hg : Ghost B z G σi := by
      have hnil : (σi.run.filter fun y => !G.contains y.seq) = [] := by
        apply List.filter_eq_nil_iff.mpr
        intro y hy; simpa [G] using List.mem_map_of_mem (f := Item.seq) hy
      refine ⟨fun e _ _ y hy hyG => absurd (List.mem_map_of_mem hy) hyG, fun e _ hqe r => ?_⟩
      rw [hnil]
      simp only [qual, Bool.and_eq_true, Bool.not_eq_true'] at hqe
      simp only [used]
      have := le_of_not_unfit hqe.1.2 r
      omega
    rcases phase htr hb hg hk hq (by omega) hfit hzj with h | ⟨σa, htra, hba, hqa, hlt, hta⟩
    · have : dmax ≤ (1 + k) * dmax := by
        rw [Nat.add_mul, Nat.one_mul]; exact Nat.le_add_right _ _
      omega
    · have hza : z ∈ σa.queue := by
        rcases hba.zq with h | h
        · exact h
        · exact absurd rfl ((gone_trace htra ⟨hba.znext, h⟩).2 z hzj)
      have := ih _ hlt σa hba.inv hqa hza hba.zAged hba.zReady htra rfl
      have hm : (1 + psi B z σa) * dmax ≤ k * dmax := Nat.mul_le_mul_right _ (by omega)
      have : (1 + k) * dmax = dmax + k * dmax := by rw [Nat.add_mul, Nat.one_mul]
      omega

/-! ## Running traces -/

/-- Run a list of commands as events.

$$\operatorname{run}(B, \sigma, [\,]) = \sigma, \qquad \operatorname{run}(B, \sigma, c :: cs) = \operatorname{run}(B, \operatorname{event}(B, \sigma, c), cs)$$
-/
def runTrace (B : Vec) : State → List Cmd → State
  | σ, [] => σ
  | σ, c :: cs => runTrace B (event B σ c) cs

/-- Check the trace side condition for a list of commands: each event keeps the clock below the
deadline of every item running before it.

$$\operatorname{ok}(B, d, \sigma, [\,]), \qquad \operatorname{ok}(B, d, \sigma, c :: cs) \iff \big(\forall x \in \mathit{Run}(\sigma):\ t(\operatorname{event}(B, \sigma, c)) < \mathit{start}(x) + d\big) \land \operatorname{ok}(B, d, \operatorname{event}(B, \sigma, c), cs)$$
-/
def okTrace (B : Vec) (dmax : Nat) : State → List Cmd → Bool
  | _, [] => true
  | σ, c :: cs =>
    σ.run.all (fun x => decide ((event B σ c).t < x.start + dmax)) && okTrace B dmax (event B σ c) cs

/-- A checked command list is a trace.

$$\forall B, d, cs, \sigma:\quad \operatorname{ok}(B, d, \sigma, cs) \Rightarrow \mathrm{Trace}_{B,d}(\sigma, \operatorname{run}(B, \sigma, cs))$$
-/
theorem okTrace_sound (B : Vec) (dmax : Nat) :
    ∀ (cs : List Cmd) (σ : State), okTrace B dmax σ cs = true → Trace B dmax σ (runTrace B σ cs)
  | [], σ, _ => .refl σ
  | c :: cs, σ, h => by
    simp only [okTrace, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq] at h
    exact .cons c h.1 (okTrace_sound B dmax cs _ h.2)

/-! ## Examples: one per reason, and admitStep -/

namespace Ex

/-- Budget for the examples: cores 4, RAM 8, no clean-build token, no Docker slot (small abstract numbers,
not the tenths-of-a-core and MB scale).
$$B = (4, 8, 0, 0)$$ -/
def B4 : Vec := { cores := 4, ram := 8 }
/-- A job writing one Lean file with 2 cores.
$$d(a) = (2, 0, 0, 0)$$ -/
def a : Item := { id := "a", writes := ["lean/Fw/A.lean"], demand := { cores := 2 } }
/-- A job writing the parent directory (a prefix conflict with `a`).
$$W(b) = \{\texttt{lean/Fw}\}$$ -/
def b : Item := { id := "b", writes := ["lean/Fw"], demand := { cores := 1 }, seq := 1 }
/-- A job needing 3 cores.
$$d(c) = (3, 0, 0, 0)$$ -/
def c : Item := { id := "c", writes := ["apps/site"], demand := { cores := 3 }, seq := 2 }
/-- A job needing more RAM than the machine has.
$$d(\mathit{big}) = (0, 9, 0, 0)$$ -/
def big : Item := { id := "big", demand := { ram := 9 } }
/-- A job depending on `a`.
$$D(\mathit{dep}) = \{a\}$$ -/
def dep : Item := { id := "dep", deps := ["a"] }
/-- Two jobs on the Simulator.
$$V(s_1) = V(s_2) = \{\mathrm{simulator}\}$$ -/
def s1 : Item := { id := "s1", devices := [.simulator], seq := 4 }
/-- See `s1`.
$$V(s_2) = \{\mathrm{simulator}\}$$ -/
def s2 : Item := { id := "s2", devices := [.simulator], seq := 5 }
/-- A child of `a` writing the same file (exempt).
$$\mathit{parent}(\mathit{kid}) = a$$ -/
def kid : Item := { id := "kid", parent := some "a", writes := ["lean/Fw/A.lean"], seq := 3 }
/-- An aged, ready queued job writing `apps/site` ahead of `x`.
$$W(o) = \{\texttt{apps/site}\}$$ -/
def o : Item := { id := "o", writes := ["apps/site"], demand := { cores := 1 } }
/-- A newer job conflicting with `o`.
$$W(x) = \{\texttt{apps/site/x}\}$$ -/
def x : Item := { id := "x", writes := ["apps/site/x"], seq := 1 }

end Ex

open Ex in
#guard admit B4 {} a == .admit
open Ex in
#guard admit B4 {} big == .queue (.neverFits .ram)
open Ex in
#guard admit B4 {} dep == .queue (.depPending "a")
open Ex in
#guard admit B4 { done := ["a"] } dep == .admit
open Ex in
#guard admit B4 { run := [a] } b == .queue (.writeConflict "lean/Fw" "a")
open Ex in
#guard admit B4 { run := [a] } kid == .admit
open Ex in
#guard admit B4 { run := [s1] } s2 == .queue (.deviceBusy .simulator "s1")
open Ex in
#guard admit B4 { run := [a] } c == .queue (.overBudget .cores 3 2)
open Ex in
#guard admit B4 { queue := [o, x] } x == .queue (.behindAged "o")
open Ex in
#guard admit B4 { queue := [o, x] } o == .admit
open Ex in
#guard (chosen B4 { queue := [x, o] }).map (·.id) == some "o"
open Ex in
#guard ((admitStep B4 { queue := [b, a], t := 5 }).run.map fun y => (y.id, y.start)) == [("a", 5)]
-- `c` is aged and over budget, so it reserves its room: `s1` and `s2` wait behind it
open Ex in
#guard ((admitAll B4 { queue := [a, b, c, s1, s2] }).run.map (·.id)) == ["a"]
open Ex in
#guard unfit B4 big && !unfit B4 a
open Ex in
#guard (finish { run := [a] } "a" true).done == ["a"] && (finish {} "a" true).done == []
open Ex in
#guard ((enqueue (enqueue {} a) a).queue.length, (enqueue (enqueue {} a) b).next) == (1, 2)

/-! ## The plan's original bound fails (counterexample)

The plan's bound counted only *aged competing* older items in `Q ∪ Run` at `t_aged`. Here `o` is
older than `z` and competes with it, but is not ready (it waits for `e`); a newer job `y` slips in
ahead of `o` and blocks it, so `z` waits for `o`'s whole run after `y`. With `dmax = 10` the plan's
bound is `0 + (1 + 1) · 10 = 20`, yet `z` is still queued at `t = 25`; the restated bound with
`Ψ = 2` (`o` counted twice, being not yet ready) is `30`, and `z` is admitted at `26`. -/

namespace Cex

/-- A running job holding `w1`.
$$W(r_1) = \{\texttt{w1}\}$$ -/
def r1 : Item := { id := "r1", writes := ["w1"], seq := 5 }
/-- A running job that `o` depends on.
$$\mathit{id}(e) = \texttt{e}$$ -/
def e : Item := { id := "e", writes := ["e"], seq := 6 }
/-- An older queued job that waits for `e` and competes with `z` on `p`.
$$D(o) = \{e\},\ W(o) = \{\texttt{p}, \texttt{q2}\}$$ -/
def o : Item := { id := "o", deps := ["e"], writes := ["p", "q2"], seq := 0 }
/-- The aged, ready job under study.
$$W(z) = \{\texttt{w1}, \texttt{p}\}$$ -/
def z : Item := { id := "z", writes := ["w1", "p"], seq := 1 }
/-- A newer job that blocks `o`.
$$W(y) = \{\texttt{q2}\}$$ -/
def y : Item := { id := "y", writes := ["q2"] }
/-- The start state (quiescent, all ages 0, no budget pressure); `next = 7` fixes the arrival number of `y`.
$$\sigma_i = (\mathit{Run} = [r_1, e],\ \mathit{Done} = [\,],\ Q = [o, z],\ t = 0,\ \mathit{next} = 7)$$ -/
def σi : State := { run := [r1, e], queue := [o, z], next := 7 }
/-- The events up to `t = 25`; every finish has landed (flag true).
$$[\mathrm{tick}(8), \mathrm{enqueue}(y), \mathrm{tick}(9), \mathrm{finish}(e, \mathrm{true}), \mathrm{finish}(r_1, \mathrm{true}), \mathrm{tick}(17), \mathrm{finish}(y, \mathrm{true}), \mathrm{tick}(25)]$$ -/
def cmds : List Cmd :=
  [.tick 8, .enqueue y, .tick 9, .finish "e" true, .finish "r1" true, .tick 17, .finish "y" true,
   .tick 25]
/-- The rest of the trace; the finish has landed (flag true).
$$[\mathrm{tick}(26), \mathrm{finish}(o, \mathrm{true})]$$ -/
def rest : List Cmd := [.tick 26, .finish "o" true]

end Cex

open Cex in
#guard chosen {} σi == none && okTrace {} 10 σi (cmds ++ rest)
-- the plan's k (aged competing older items in Q ∪ Run) is 1; our Ψ is 2
open Cex in
#guard ((σi.run ++ σi.queue).filter fun w =>
    comp {} σi w z && decide (w.seq < z.seq) && aged σi.t w).length == 1 && psi {} z σi == 2
-- z still queued at t = 25 ≥ 0 + (1 + 1)·10: the plan's bound fails
open Cex in
#guard (runTrace {} σi cmds).t == 25 && (runTrace {} σi cmds).queue.contains z
-- z admitted at t = 26 < 0 + (1 + 2)·10: within the restated bound
open Cex in
#guard (runTrace {} σi (cmds ++ rest)).run.map (fun w => (w.id, w.start)) == [("z", 26)]

end Fw.Sched.Admit

/-!
# Glob write sets, read sets and scratch names (task admit-reads)

Incident 2026-10-18 (research/notes/2026/10-18-mistake-retro.md, c-shared-no-lock): two tasks whose
write globs met in `packages/measure-wktr/**` ran at the same time; agents also shared scratch file
names. This section is the task-level admission rule on the work graph's globs (glob semantics of
`Fw.Ops.PathCheck`: a glob matches a path or one of its directory prefixes): a task starts only if
its write globs meet neither the write nor the declared read globs of any running task, and its
read globs meet no running write glob. The glob test is conservative (`gover_sound`); on literal
paths it is the prefix test `pconf` of the item model above (`gover_pconf`).

Proved: `gover_sound`, `gover_pconf`, `admits_iff`, `blockAt_none`, `mem_clashes`, `blockAt_sound`,
`admit_disjoint`, `reads_disjoint`, `admit_eventually`, `overlapPairs_nil`, `scratch_injective`,
`scratch_disjoint`.
-/
namespace Fw.Sched.Admit.Reads

open Fw.Ops.PathCheck (segs segMatch globMatch matchesPath segMatch_lit)

/-! ## The conservative glob overlap test -/

/-- A wildcard segment: it contains `*` (so `**` is one).

$$\operatorname{wild}(s) \iff \texttt{*} \in s$$
-/
def wild (s : String) : Bool := s.toList.contains '*'

/-- The literal prefix of a glob segment list: its segments before the first wildcard segment.

$$\operatorname{lit}(g) = \operatorname{takeWhile}(\lnot\operatorname{wild},\ g)$$
-/
def lit (g : List String) : List String := g.takeWhile fun s => !wild s

/-- Overlap test on glob segment lists: one literal prefix is a prefix of the other.

$$A \between B \iff \operatorname{lit}(A) \sqsubseteq \operatorname{lit}(B) \ \lor\ \operatorname{lit}(B) \sqsubseteq \operatorname{lit}(A)$$
-/
def goverL (A B : List String) : Bool := (lit A).isPrefixOf (lit B) || (lit B).isPrefixOf (lit A)

/-- Overlap test on two glob strings, split with `segs`.

$$g \between h \iff \operatorname{segs}(g) \between \operatorname{segs}(h)$$
-/
def gover (g h : String) : Bool := goverL (segs g) (segs h)

/-- The overlap test is symmetric.

$$\forall g, h:\quad g \between h \iff h \between g$$
-/
theorem gover_comm (g h : String) : gover g h = gover h g := by
  simp [gover, goverL, Bool.or_comm]

/-- A segment that is not wild is neither `**` nor contains `*`.

$$\forall s:\quad \lnot\operatorname{wild}(s) \Rightarrow s \ne \texttt{**} \land \texttt{*} \notin s$$
-/
theorem not_wild {s : String} (h : wild s = false) : s ≠ "**" ∧ '*' ∉ s.toList := by
  have hm : '*' ∉ s.toList := by simpa [wild] using h
  refine ⟨?_, hm⟩
  rintro rfl
  exact hm (by simp)

/-- A glob that matches a whole path starts the path with its literal prefix.

$$\forall g, y:\quad \mathrm{gm}(g, y) \Rightarrow \operatorname{lit}(g) \sqsubseteq y$$
-/
theorem lit_prefix (g y : List String) (h : globMatch g y = true) : lit g <+: y := by
  induction g generalizing y with
  | nil => simp [lit]
  | cons a g ih =>
    cases hw : wild a with
    | true => simp [lit, hw]
    | false =>
      obtain ⟨h1, h2⟩ := not_wild hw
      have hl : lit (a :: g) = a :: lit g := by simp [lit, hw]
      rw [hl]
      cases y with
      | nil => simp [globMatch] at h
      | cons b y =>
        have e : globMatch (a :: g) (b :: y) = (segMatch a.toList b.toList && globMatch g y) := by
          simp [globMatch]
        rw [e, Bool.and_eq_true, segMatch_lit _ _ h2, String.toList_inj] at h
        obtain ⟨rfl, hy⟩ := h
        exact (List.prefix_cons_inj _).mpr (ih y hy)

/-- A glob that matches a path (or one of its directory prefixes) starts the path with its literal
prefix.

$$\forall g, x:\quad \mathrm{mp}(g, x) \Rightarrow \operatorname{lit}(g) \sqsubseteq x$$
-/
theorem lit_prefix_path (g x : List String) (h : matchesPath g x = true) : lit g <+: x := by
  simp only [matchesPath, List.any_eq_true, List.mem_range] at h
  obtain ⟨k, _, hm⟩ := h
  exact (lit_prefix g _ hm).trans (List.take_prefix _ _)

/-- Soundness of the overlap test on segment lists: if two globs match a common path, the test says
overlap.

$$\forall A, B, x:\quad \mathrm{mp}(A, x) \land \mathrm{mp}(B, x) \Rightarrow A \between B$$
-/
theorem goverL_sound (A B x : List String) (ha : matchesPath A x = true) (hb : matchesPath B x = true) :
    goverL A B = true := by
  have := List.prefix_or_prefix_of_prefix (lit_prefix_path A x ha) (lit_prefix_path B x hb)
  simp only [goverL, Bool.or_eq_true, List.isPrefixOf_iff_prefix]
  exact this

/-- Glob-overlap soundness: if two glob strings can match a common path (segment list), the test
says overlap.

$$\forall g, h, x:\quad \mathrm{mp}(\operatorname{segs}(g), x) \land \mathrm{mp}(\operatorname{segs}(h), x) \Rightarrow g \between h$$
-/
theorem gover_sound (g h : String) (x : List String) (hg : matchesPath (segs g) x = true)
    (hh : matchesPath (segs h) x = true) : gover g h = true :=
  goverL_sound _ _ x hg hh

/-- A segment list without wild segments is its own literal prefix.

$$\forall A:\quad (\forall s \in A:\ \lnot\operatorname{wild}(s)) \Rightarrow \operatorname{lit}(A) = A$$
-/
theorem lit_self (A : List String) (h : ∀ s ∈ A, wild s = false) : lit A = A := by
  induction A with
  | nil => rfl
  | cons a A ih =>
    have ha := h a List.mem_cons_self
    have : lit (a :: A) = a :: lit A := by simp [lit, ha]
    rw [this, ih fun s m => h s (List.mem_cons_of_mem _ m)]

/-- On literal paths (no segment contains `*`) the glob test is the prefix conflict `pconf` of the
item model.

$$\forall g, h:\quad (\forall s \in \operatorname{segs}(g) \cup \operatorname{segs}(h):\ \lnot\operatorname{wild}(s)) \Rightarrow \big(g \between h \iff g \bowtie h\big)$$
-/
theorem gover_pconf (g h : String) (hg : ∀ s ∈ segs g, wild s = false) (hh : ∀ s ∈ segs h, wild s = false) :
    gover g h = pconf g h := by
  simp [gover, goverL, pconf, lit_self _ hg, lit_self _ hh]

/-! ## Tasks, clashes and the admission decision -/

/-- A task of the work graph: its id, its write globs $W(x)$ and its declared read globs $R(x)$
(empty when undeclared).

$$x = (\mathit{id},\ W(x),\ R(x)) \in \mathrm{String} \times \mathrm{String}^{*} \times \mathrm{String}^{*}$$
-/
structure Task where
  id : String
  writes : List String := []
  reads : List String := []
deriving DecidableEq, Repr

/-- The kind of a clash: the candidate's write against a running write (`ww`), the candidate's
write against a running read (`wr`), the candidate's read against a running write (`rw`).

$$\mathcal K = \{\mathrm{ww},\ \mathrm{wr},\ \mathrm{rw}\}$$
-/
inductive Kind where
  | ww | wr | rw
deriving DecidableEq, Repr

/-- Every clash kind, in report order.

$$\mathcal K = [\mathrm{ww},\ \mathrm{wr},\ \mathrm{rw}]$$
-/
def Kind.all : List Kind := [.ww, .wr, .rw]

/-- The candidate's side of a kind: its writes for `ww` and `wr`, its reads for `rw`.

$$\operatorname{mine}(x, \mathrm{ww}) = \operatorname{mine}(x, \mathrm{wr}) = W(x), \quad \operatorname{mine}(x, \mathrm{rw}) = R(x)$$
-/
def mine (x : Task) : Kind → List String
  | .ww => x.writes
  | .wr => x.writes
  | .rw => x.reads

/-- The running task's side of a kind: its writes for `ww` and `rw`, its reads for `wr`.

$$\operatorname{theirs}(y, \mathrm{ww}) = \operatorname{theirs}(y, \mathrm{rw}) = W(y), \quad \operatorname{theirs}(y, \mathrm{wr}) = R(y)$$
-/
def theirs (y : Task) : Kind → List String
  | .ww => y.writes
  | .wr => y.reads
  | .rw => y.writes

/-- Two glob lists meet: some glob of the first overlaps some glob of the second.

$$\operatorname{meet}(A, B) \iff \exists a \in A,\ b \in B:\ a \between b$$
-/
def meet (A B : List String) : Bool := A.any fun a => B.any fun b => gover a b

/-- Task conflict: for some kind, the candidate's side meets the running task's side.

$$x \between y \iff \exists k \in \mathcal K:\ \operatorname{meet}(\operatorname{mine}(x, k),\ \operatorname{theirs}(y, k))$$

that is, $W(x)$ meets $W(y)$, or $W(x)$ meets $R(y)$, or $R(x)$ meets $W(y)$.
-/
def conf (x y : Task) : Bool := Kind.all.any fun k => meet (mine x k) (theirs y k)

/-- `meet` is symmetric.

$$\forall A, B:\quad \operatorname{meet}(A, B) \iff \operatorname{meet}(B, A)$$
-/
theorem meet_comm (A B : List String) : meet A B = meet B A := by
  apply Bool.eq_iff_iff.mpr
  simp only [meet, List.any_eq_true]
  constructor
  · rintro ⟨a, ha, b, hb, h⟩; exact ⟨b, hb, a, ha, by rw [gover_comm]; exact h⟩
  · rintro ⟨b, hb, a, ha, h⟩; exact ⟨a, ha, b, hb, by rw [gover_comm]; exact h⟩

/-- Task conflict is symmetric (the `wr` and `rw` kinds swap).

$$\forall x, y:\quad x \between y \iff y \between x$$
-/
theorem conf_comm (x y : Task) : conf x y = conf y x := by
  simp only [conf, Kind.all, mine, theirs, List.any_cons, List.any_nil, Bool.or_false]
  rw [meet_comm x.writes y.writes, meet_comm x.writes y.reads, meet_comm x.reads y.writes]
  cases meet y.writes x.writes <;> cases meet y.reads x.writes <;> cases meet y.writes x.reads <;> rfl

/-- A clash: the running task's id, the kind, the candidate's glob and the running task's glob.

$$c = (\mathit{task},\ k,\ \mathit{mine},\ \mathit{theirs}) \in \mathrm{String} \times \mathcal K \times \mathrm{String} \times \mathrm{String}$$
-/
structure Clash where
  task : String
  kind : Kind
  mine : String
  theirs : String
deriving DecidableEq, Repr

/-- The overlapping pairs of two glob lists, in order (first by $A$, then by $B$).

$$\operatorname{pairs}(A, B) = [\,(a, b) \mid a \in A,\ b \in B,\ a \between b\,]$$
-/
def pairsOf (A B : List String) : List (String × String) :=
  A.flatMap fun a => (B.filter fun b => gover a b).map fun b => (a, b)

/-- The clashes of candidate $x$ with running task $y$, by kind (`ww`, `wr`, `rw`), then by pair.

$$\operatorname{clashes}(x, y) = [\,(\mathit{id}(y), k, a, b) \mid k \in \mathcal K,\ (a, b) \in \operatorname{pairs}(\operatorname{mine}(x, k), \operatorname{theirs}(y, k))\,]$$
-/
def clashes (x y : Task) : List Clash :=
  Kind.all.flatMap fun k => (pairsOf (mine x k) (theirs y k)).map fun p => ⟨y.id, k, p.1, p.2⟩

/-- The first clash of candidate $x$ with the running list, in running order (`none`: admitted).

$$\operatorname{blockAt}(\mathit{Run}, x) = \operatorname{head}\big(\operatorname{clashes}(x, y_1) \mathbin{+\!\!+} \dots \mathbin{+\!\!+} \operatorname{clashes}(x, y_n)\big), \quad \mathit{Run} = [y_1, \dots, y_n], \quad \operatorname{head}([\,]) = \bot$$
-/
def blockAt (run : List Task) (x : Task) : Option Clash := (run.flatMap (clashes x)).head?

/-- The admission decision: $x$ conflicts with no running task.

$$\operatorname{admits}(\mathit{Run}, x) \iff \forall y \in \mathit{Run}:\ \lnot(x \between y)$$
-/
def admits (run : List Task) (x : Task) : Bool := run.all fun y => !conf x y

/-- `admits` is the stated rule.

$$\forall \mathit{Run}, x:\quad \operatorname{admits}(\mathit{Run}, x) \iff \forall y \in \mathit{Run}:\ \lnot(x \between y)$$
-/
theorem admits_iff (run : List Task) (x : Task) : admits run x = true ↔ ∀ y ∈ run, conf x y = false := by
  simp [admits]

/-- Membership in `pairsOf`.

$$\forall A, B, a, b:\quad (a, b) \in \operatorname{pairs}(A, B) \iff a \in A \land b \in B \land a \between b$$
-/
theorem mem_pairsOf (A B : List String) (a b : String) :
    (a, b) ∈ pairsOf A B ↔ a ∈ A ∧ b ∈ B ∧ gover a b = true := by
  simp only [pairsOf, List.mem_flatMap, List.mem_map, List.mem_filter, Prod.mk.injEq]
  constructor
  · rintro ⟨a', ha, b', ⟨hb, hg⟩, rfl, rfl⟩; exact ⟨ha, hb, hg⟩
  · rintro ⟨ha, hb, hg⟩; exact ⟨a, ha, b, ⟨hb, hg⟩, rfl, rfl⟩

/-- Membership in `clashes`: a clash names the running task, and its globs are on the two sides of
its kind and overlap.

$$\forall x, y, c:\quad c \in \operatorname{clashes}(x, y) \iff \mathit{task}(c) = \mathit{id}(y) \land \mathit{mine}(c) \in \operatorname{mine}(x, k(c)) \land \mathit{theirs}(c) \in \operatorname{theirs}(y, k(c)) \land \mathit{mine}(c) \between \mathit{theirs}(c)$$
-/
theorem mem_clashes (x y : Task) (c : Clash) :
    c ∈ clashes x y ↔ c.task = y.id ∧ c.mine ∈ mine x c.kind ∧ c.theirs ∈ theirs y c.kind ∧
      gover c.mine c.theirs = true := by
  obtain ⟨t, k, m, th⟩ := c
  simp only [clashes, List.mem_flatMap, List.mem_map]
  constructor
  · rintro ⟨k', _, ⟨p1, p2⟩, hp, he⟩
    simp only [Clash.mk.injEq] at he
    obtain ⟨rfl, rfl, rfl, rfl⟩ := he
    exact ⟨rfl, (mem_pairsOf _ _ _ _).mp hp⟩
  · rintro ⟨rfl, hm, ht, hg⟩
    exact ⟨k, by cases k <;> simp [Kind.all], (m, th), (mem_pairsOf _ _ _ _).mpr ⟨hm, ht, hg⟩, rfl⟩

/-- No clash with $y$ exactly when $x$ does not conflict with $y$.

$$\forall x, y:\quad \operatorname{clashes}(x, y) = [\,] \iff \lnot(x \between y)$$
-/
theorem clashes_nil (x y : Task) : clashes x y = [] ↔ conf x y = false := by
  rw [List.eq_nil_iff_forall_not_mem]
  simp only [conf, meet, List.any_eq_false, Bool.not_eq_true]
  constructor
  · intro h k _ a ha b hb
    cases hg : gover a b
    · rfl
    · exact absurd ((mem_clashes _ _ _).mpr ⟨rfl, ha, hb, hg⟩) (h ⟨y.id, k, a, b⟩)
  · intro h c hc
    obtain ⟨_, hm, ht, hg⟩ := (mem_clashes _ _ _).mp hc
    have := h c.kind (by cases c.kind <;> simp [Kind.all]) c.mine hm c.theirs ht
    rw [hg] at this
    exact absurd this (by decide)

/-- No first clash exactly when the task is admitted.

$$\forall \mathit{Run}, x:\quad \operatorname{blockAt}(\mathit{Run}, x) = \bot \iff \operatorname{admits}(\mathit{Run}, x)$$
-/
theorem blockAt_none (run : List Task) (x : Task) : blockAt run x = none ↔ admits run x = true := by
  rw [blockAt, List.head?_eq_none_iff, List.flatMap_eq_nil_iff, admits_iff]
  exact forall₂_congr fun y _ => clashes_nil x y

/-- The reported clash is real: it names a running task, its globs lie on the two sides of its kind,
and they overlap.

$$\forall \mathit{Run}, x, c:\quad \operatorname{blockAt}(\mathit{Run}, x) = c \ne \bot \Rightarrow \exists y \in \mathit{Run}:\ \mathit{task}(c) = \mathit{id}(y) \land \mathit{mine}(c) \in \operatorname{mine}(x, k(c)) \land \mathit{theirs}(c) \in \operatorname{theirs}(y, k(c)) \land \mathit{mine}(c) \between \mathit{theirs}(c)$$
-/
theorem blockAt_sound (run : List Task) (x : Task) (c : Clash) (h : blockAt run x = some c) :
    ∃ y ∈ run, c.task = y.id ∧ c.mine ∈ mine x c.kind ∧ c.theirs ∈ theirs y c.kind ∧
      gover c.mine c.theirs = true := by
  have hm := List.mem_of_head? h
  rw [List.mem_flatMap] at hm
  obtain ⟨y, hy, hc⟩ := hm
  exact ⟨y, hy, (mem_clashes _ _ _).mp hc⟩

/-! ## Running set: start and finish -/

/-- A command: start a task (it joins the running set only if admitted) or finish a task by id.

$$c \in \{\operatorname{start}(x),\ \operatorname{finish}(i)\}$$
-/
inductive Cmd where
  | start (x : Task)
  | finish (id : String)

/-- One step on the running list: an admitted start is prepended, a refused start changes nothing,
a finish removes every running task with that id.

$$\operatorname{step}(\mathit{Run}, \operatorname{start}(x)) = \begin{cases} x :: \mathit{Run} & \operatorname{admits}(\mathit{Run}, x) \\ \mathit{Run} & \text{otherwise} \end{cases}, \qquad \operatorname{step}(\mathit{Run}, \operatorname{finish}(i)) = [\, y \in \mathit{Run} : \mathit{id}(y) \ne i \,]$$
-/
def stepT (run : List Task) : Cmd → List Task
  | .start x => if admits run x then x :: run else run
  | .finish i => run.filter fun y => y.id != i

/-- Run a list of commands from left to right.

$$\operatorname{steps}(\mathit{Run}, [\,]) = \mathit{Run}, \qquad \operatorname{steps}(\mathit{Run}, c :: cs) = \operatorname{steps}(\operatorname{step}(\mathit{Run}, c), cs)$$
-/
def stepsT : List Task → List Cmd → List Task
  | run, [] => run
  | run, c :: cs => stepsT (stepT run c) cs

/-- The running lists reachable from the empty one by steps.

$$\mathrm{Reach}([\,]), \qquad \mathrm{Reach}(\mathit{Run}) \Rightarrow \mathrm{Reach}(\operatorname{step}(\mathit{Run}, c))$$
-/
inductive ReachT : List Task → Prop where
  | init : ReachT []
  | step {run : List Task} (c : Cmd) : ReachT run → ReachT (stepT run c)

/-- Every step keeps the running list pairwise conflict-free.

$$\forall \mathit{Run}, c:\quad \big(\forall i < j < |\mathit{Run}|:\ \lnot(\mathit{Run}_i \between \mathit{Run}_j)\big) \Rightarrow \forall i < j < |\mathit{Run}'|:\ \lnot(\mathit{Run}'_i \between \mathit{Run}'_j), \quad \mathit{Run}' = \operatorname{step}(\mathit{Run}, c)$$
-/
theorem pairwise_stepT (run : List Task) (c : Cmd) (h : run.Pairwise fun a b => conf a b = false) :
    (stepT run c).Pairwise fun a b => conf a b = false := by
  cases c with
  | start x =>
    simp only [stepT]
    split
    · next ha => exact List.pairwise_cons.mpr ⟨(admits_iff run x).mp ha, h⟩
    · exact h
  | finish i => exact h.sublist List.filter_sublist

/-- Every reachable running list is pairwise conflict-free.

$$\forall \mathit{Run}:\quad \mathrm{Reach}(\mathit{Run}) \Rightarrow \forall i < j < |\mathit{Run}|:\ \lnot(\mathit{Run}_i \between \mathit{Run}_j)$$
-/
theorem pairwise_reach {run : List Task} (h : ReachT run) : run.Pairwise fun a b => conf a b = false := by
  induction h with
  | init => exact List.Pairwise.nil
  | step c _ ih => exact pairwise_stepT _ c ih

/-- Task $t$ writes path $p$: some write glob of $t$ matches $p$.

$$\operatorname{wr}(t, p) \iff \exists g \in W(t):\ \mathrm{mp}(\operatorname{segs}(g), p)$$
-/
def hitsW (t : Task) (p : List String) : Prop := ∃ g ∈ t.writes, matchesPath (segs g) p = true

/-- Task $t$ reads path $p$: some declared read glob of $t$ matches $p$.

$$\operatorname{rd}(t, p) \iff \exists g \in R(t):\ \mathrm{mp}(\operatorname{segs}(g), p)$$
-/
def hitsR (t : Task) (p : List String) : Prop := ∃ g ∈ t.reads, matchesPath (segs g) p = true

/-- If two glob lists do not meet, no path is matched by a glob of each.

$$\forall A, B, p:\quad \lnot\operatorname{meet}(A, B) \Rightarrow \lnot\big((\exists a \in A:\ \mathrm{mp}(\operatorname{segs}(a), p)) \land (\exists b \in B:\ \mathrm{mp}(\operatorname{segs}(b), p))\big)$$
-/
theorem meet_false_disjoint {A B : List String} (h : meet A B = false) (p : List String)
    (ha : ∃ a ∈ A, matchesPath (segs a) p = true) (hb : ∃ b ∈ B, matchesPath (segs b) p = true) : False := by
  obtain ⟨a, ha, hpa⟩ := ha
  obtain ⟨b, hb, hpb⟩ := hb
  have : meet A B = true := by
    simp only [meet, List.any_eq_true]
    exact ⟨a, ha, b, hb, gover_sound a b p hpa hpb⟩
  rw [h] at this
  exact absurd this (by decide)

/-- The parts of a task conflict.

$$\forall x, y:\quad \lnot(x \between y) \iff \lnot\operatorname{meet}(W(x), W(y)) \land \lnot\operatorname{meet}(W(x), R(y)) \land \lnot\operatorname{meet}(R(x), W(y))$$
-/
theorem conf_false_iff (x y : Task) : conf x y = false ↔
    meet x.writes y.writes = false ∧ meet x.writes y.reads = false ∧ meet x.reads y.writes = false := by
  simp [conf, Kind.all, mine, theirs]

/-- Two admitted running tasks never write a common path.

$$\forall \mathit{Run}:\quad \mathrm{Reach}(\mathit{Run}) \Rightarrow \forall i < j < |\mathit{Run}|,\ \forall p:\ \lnot\big(\operatorname{wr}(\mathit{Run}_i, p) \land \operatorname{wr}(\mathit{Run}_j, p)\big)$$
-/
theorem admit_disjoint {run : List Task} (h : ReachT run) :
    run.Pairwise fun a b => ∀ p, ¬ (hitsW a p ∧ hitsW b p) :=
  (pairwise_reach h).imp fun hc p ⟨ha, hb⟩ =>
    meet_false_disjoint ((conf_false_iff _ _).mp hc).1 p ha hb

/-- No admitted running task writes a path that another one reads (either order).

$$\forall \mathit{Run}:\quad \mathrm{Reach}(\mathit{Run}) \Rightarrow \forall i < j < |\mathit{Run}|,\ \forall p:\ \lnot\big(\operatorname{wr}(\mathit{Run}_i, p) \land \operatorname{rd}(\mathit{Run}_j, p)\big) \land \lnot\big(\operatorname{rd}(\mathit{Run}_i, p) \land \operatorname{wr}(\mathit{Run}_j, p)\big)$$
-/
theorem reads_disjoint {run : List Task} (h : ReachT run) :
    run.Pairwise fun a b => ∀ p, ¬ (hitsW a p ∧ hitsR b p) ∧ ¬ (hitsR a p ∧ hitsW b p) :=
  (pairwise_reach h).imp fun hc p =>
    have hc := (conf_false_iff _ _).mp hc
    ⟨fun ⟨ha, hb⟩ => meet_false_disjoint hc.2.1 p ha hb, fun ⟨ha, hb⟩ => meet_false_disjoint hc.2.2 p ha hb⟩

/-- Finishing a list of ids removes exactly the running tasks with those ids.

$$\forall \mathit{Run}, I:\quad \operatorname{steps}(\mathit{Run}, [\operatorname{finish}(i) \mid i \in I]) = [\, y \in \mathit{Run} : \mathit{id}(y) \notin I \,]$$
-/
theorem stepsT_finish (run : List Task) (ids : List String) :
    stepsT run (ids.map Cmd.finish) = run.filter fun y => !ids.contains y.id := by
  induction ids generalizing run with
  | nil => simp only [stepsT, List.map_nil]; exact (List.filter_eq_self.mpr (by simp)).symm
  | cons i ids ih =>
    simp only [List.map_cons, stepsT, stepT, ih, List.filter_filter]
    congr 1
    funext y
    by_cases h : y.id = i <;> simp [h]

/-- Admission never blocks a task forever when the running set drains: once every running task
that conflicts with $x$ has finished (finishes only, no new starts), $x$ is admitted and starts.

$$\forall \mathit{Run}, x, I:\quad \big(\forall y \in \mathit{Run}:\ x \between y \Rightarrow \mathit{id}(y) \in I\big) \Rightarrow \operatorname{admits}(\mathit{Run}', x) \land \operatorname{step}(\mathit{Run}', \operatorname{start}(x)) = x :: \mathit{Run}', \quad \mathit{Run}' = \operatorname{steps}(\mathit{Run}, [\operatorname{finish}(i) \mid i \in I])$$
-/
theorem admit_eventually (run : List Task) (x : Task) (ids : List String)
    (h : ∀ y ∈ run, conf x y = true → y.id ∈ ids) :
    admits (stepsT run (ids.map Cmd.finish)) x = true ∧
      stepT (stepsT run (ids.map Cmd.finish)) (.start x) = x :: stepsT run (ids.map Cmd.finish) := by
  have ha : admits (stepsT run (ids.map Cmd.finish)) x = true := by
    rw [admits_iff, stepsT_finish]
    intro y hy
    rw [List.mem_filter] at hy
    cases hc : conf x y with
    | false => rfl
    | true =>
      have := h y hy.1 hc
      simp [this] at hy
  exact ⟨ha, by simp [stepT, ha]⟩

/-- The empty running set admits every task.

$$\forall x:\quad \operatorname{admits}([\,], x)$$
-/
theorem admits_nil (x : Task) : admits [] x = true := rfl

/-! ## Replay: the overlapping pairs of a task list -/

/-- The overlapping pairs of a task list, each with its first clash: for $i < j$, the pair
$(\mathit{id}(t_i), c)$ where $c$ is the first clash of $t_i$ (as candidate) with $t_j$ (as running).

$$\operatorname{overlaps}([t_1, \dots, t_n]) = [\,(\mathit{id}(t_i), c) \mid i < j,\ c = \operatorname{head}(\operatorname{clashes}(t_i, t_j)) \ne \bot\,]$$
-/
def overlapPairs : List Task → List (String × Clash)
  | [] => []
  | a :: rest => rest.filterMap (fun b => (clashes a b).head?.map fun c => (a.id, c)) ++ overlapPairs rest

/-- No pair is reported exactly when the list is pairwise conflict-free.

$$\forall T:\quad \operatorname{overlaps}(T) = [\,] \iff \forall i < j < |T|:\ \lnot(T_i \between T_j)$$
-/
theorem overlapPairs_nil (ts : List Task) :
    overlapPairs ts = [] ↔ ts.Pairwise fun a b => conf a b = false := by
  induction ts with
  | nil => simp [overlapPairs]
  | cons a rest ih =>
    simp only [overlapPairs, List.append_eq_nil_iff, ih, List.pairwise_cons, List.filterMap_eq_nil_iff,
      Option.map_eq_none_iff, List.head?_eq_none_iff, clashes_nil]

/-! ## Scratch names -/

/-- The scratch directory of an agent, relative to the session scratchpad root.

$$\operatorname{scratch}(a) = \texttt{scratchpad/} \mathbin{+\!\!+} a \mathbin{+\!\!+} \texttt{/}$$
-/
def scratch (agent : String) : String := "scratchpad/" ++ agent ++ "/"

/-- Scratch directory names are injective in the agent name.

$$\forall a, b:\quad \operatorname{scratch}(a) = \operatorname{scratch}(b) \Rightarrow a = b$$
-/
theorem scratch_injective (a b : String) (h : scratch a = scratch b) : a = b := by
  have := congrArg String.toList h
  simp only [scratch, String.toList_append] at this
  exact String.toList_inj.mp (List.append_cancel_left (List.append_cancel_right this))

/-- The scratch trees of two different agents (names without `*`) share no path: no path is
matched by both `scratchpad/a` and `scratchpad/b` (each covers its subtree).

$$\forall a, b, x:\quad \texttt{*} \notin a \land \texttt{*} \notin b \land a \ne b \Rightarrow \lnot\big(\mathrm{mp}([\texttt{scratchpad}, a], x) \land \mathrm{mp}([\texttt{scratchpad}, b], x)\big)$$
-/
theorem scratch_disjoint (a b : String) (x : List String) (ha : '*' ∉ a.toList) (hb : '*' ∉ b.toList)
    (hne : a ≠ b) : ¬ (matchesPath ["scratchpad", a] x = true ∧ matchesPath ["scratchpad", b] x = true) := by
  rintro ⟨h1, h2⟩
  have hs := goverL_sound _ _ x h1 h2
  have hw : ∀ s, '*' ∉ s.toList → wild s = false := fun s h => by simpa [wild] using h
  have hsp : wild "scratchpad" = false := hw _ (by simp)
  rw [goverL, lit_self _ (by simp [hsp, hw a ha]), lit_self _ (by simp [hsp, hw b hb])] at hs
  simp [List.isPrefixOf, hne, Ne.symm hne] at hs

/-! ## Examples -/

/-- The incident pair of 2026-10-18, first task (write globs abridged to three).

$$\mathit{wf} = (\texttt{wktr-fixture-speed},\ [\texttt{packages/measure-wktr/fixtures/**},\ \texttt{packages/measure-wktr/src/**},\ \texttt{lean/Fw/Measure/WktrLayout.lean}],\ [\,])$$
-/
def wf : Task :=
  { id := "wktr-fixture-speed"
    writes := ["packages/measure-wktr/fixtures/**", "packages/measure-wktr/src/**", "lean/Fw/Measure/WktrLayout.lean"] }

/-- The incident pair of 2026-10-18, second task (write globs abridged to three).

$$\mathit{ep} = (\texttt{engine-premise-measure},\ [\texttt{lean/Fw/Ops/Premise.lean},\ \texttt{packages/measure-*/**},\ \texttt{packages/premise-tests/**}],\ [\,])$$
-/
def ep : Task :=
  { id := "engine-premise-measure"
    writes := ["lean/Fw/Ops/Premise.lean", "packages/measure-*/**", "packages/premise-tests/**"] }

/-- A reader of the WKTR CLI.

$$\mathit{rd} = (\texttt{rd},\ [\texttt{docs/x.md}],\ [\texttt{packages/measure-wktr/src/cli.mjs}])$$
-/
def rd : Task := { id := "rd", writes := ["docs/x.md"], reads := ["packages/measure-wktr/src/cli.mjs"] }

#guard gover "packages/measure-wktr/**" "packages/measure-*/**"
#guard !gover "packages/measure-wktr/**" "packages/measure-chromium/**"
#guard gover "lean/Fw" "lean/Fw/Sched/Admit.lean" && !gover "lean/Fw/A.lean" "lean/Fw/B.lean"
#guard gover "**" "apps/site/x" && gover "" "apps"
#guard !admits [wf] ep && blockAt [wf] ep == some ⟨"wktr-fixture-speed", .ww, "packages/measure-*/**",
  "packages/measure-wktr/fixtures/**"⟩
#guard !admits [wf] rd && (blockAt [wf] rd).map (·.kind) == some .rw
#guard !admits [rd] wf && (blockAt [rd] wf).map (·.kind) == some .wr
#guard !admits [rd] ep && admits [{ id := "z", writes := ["apps/site/**"] }] wf
#guard stepT [wf] (.start ep) == [wf] && stepsT [wf] [.finish "wktr-fixture-speed", .start ep] == [ep]
#guard (overlapPairs [wf, ep, rd]).map (fun p => (p.1, p.2.task)) ==
  [("wktr-fixture-speed", "engine-premise-measure"), ("wktr-fixture-speed", "rd"), ("engine-premise-measure", "rd")]
#guard overlapPairs [rd, { id := "z", writes := ["apps/site/**"] }] == []
#guard segs (scratch "admit-reads") == ["scratchpad", "admit-reads"] && scratch "a" != scratch "b"

end Fw.Sched.Admit.Reads
