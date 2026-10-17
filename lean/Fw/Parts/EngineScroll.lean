import Fw.Parts.EndFlags

/-!
# engine.scroll: frame structure of the shared scroll engine (M2 pilot part)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`
  * 2663-2666: a `Set` of entries, a map of observers, the pending frame id `tE`, the attached flag `nE`;
  * 2667-2669 `rE`: `tE ||= requestAnimationFrame(iE)` (one frame at most, however many events);
  * 2670-2673 `iE`: `tE = 0`, then every entry with `active` runs its callback, in `Set` (insertion) order;
  * 2674-2689 `aE`/`oE`: passive `scroll` + `resize` listeners attached on first use, removed when the set empties;
  * 2721-2724 `cE`: the IntersectionObserver (`rootMargin: 100% 0px`) toggles `active`;
  * 2749-2782 `dE`: register (append to the set), attach, `rE()`.
* Callers in the pilot: the nav (13090, `dE(L)`, never IO-gated) runs its reads and writes *inside* the callback,
  in the order `getComputedStyle` reads, two rects, nav rect, `pointer-events = none` write, `elementFromPoint`,
  restore write, hero-track rect (12955-13007). The hero exit (4239, `dE(c)`) only requests its own rAF in the
  callback; its body (rect read, two style writes, 4162-4171) runs as a separate rAF callback **before** the next
  `iE` (it was queued first), so in steady scrolling a frame is `[heroBody] ++ iE`.

The TS part (`apps/site/src/parts/engine.scroll/logic.ts`) adds a numeric `order` key with registration `seq` as
the tie break; with equal orders it is the original's insertion order (`orderCallbacks_registration`).
-/
namespace Fw.Parts.EngineScroll

/-! ## Callback order -/

/-- A registered callback: id, explicit order key (TS only) and registration sequence number.

$$e = (\mathit{id}, o, q) \in \mathrm{String} \times \mathbb{Z} \times \mathbb{Z}$$

One entry in the scroll engine's callback list. -/
structure Entry where
  id : String
  order : Int
  seq : Int
deriving Repr, BEq, DecidableEq

/-- Lexicographic `(order, seq)` comparison.

$$e \sqsubseteq e' \iff o < o' \lor (o = o' \land q \le q')$$

Whether entry `e` may run before entry `e'`. -/
def entryLe (a b : Entry) : Bool := a.order < b.order || (a.order == b.order && a.seq ≤ b.seq)

/-- Callback ids sorted by order, then registration (stable merge sort).

$$\operatorname{orderCallbacks}(es) = [\,e.\mathit{id} \mid e \in \operatorname{sort}_{\sqsubseteq}(es)\,]$$

The order in which one engine frame runs the callbacks. -/
def orderCallbacks (es : List Entry) : List String := (es.mergeSort entryLe).map (·.id)

#guard orderCallbacks [⟨"b", 2, 0⟩, ⟨"a", 1, 1⟩, ⟨"c", 1, 2⟩] == ["a", "c", "b"]
#guard orderCallbacks [] == []

/-- The `(order, seq)` comparison is transitive. $$\forall e_1, e_2, e_3:\ e_1 \sqsubseteq e_2 \land e_2 \sqsubseteq e_3 \Rightarrow e_1 \sqsubseteq e_3$$ -/
theorem entryLe_trans (a b c : Entry) (h1 : entryLe a b = true) (h2 : entryLe b c = true) : entryLe a c = true := by
  unfold entryLe at *
  simp only [Bool.or_eq_true, decide_eq_true_eq, Bool.and_eq_true, beq_iff_eq] at *
  omega

/-- The `(order, seq)` comparison is total. $$\forall e, e':\ e \sqsubseteq e' \lor e' \sqsubseteq e$$ -/
theorem entryLe_total (a b : Entry) : (entryLe a b || entryLe b a) = true := by
  unfold entryLe
  simp only [Bool.or_eq_true, decide_eq_true_eq, Bool.and_eq_true, beq_iff_eq]
  omega

/-- The engine order is a reordering of the registered ids (nothing dropped or duplicated).

$$\forall es:\quad \operatorname{orderCallbacks}(es) \sim [\,e.\mathit{id} \mid e \in es\,]$$

The frame order lists every registered callback exactly once (as often as it is registered); nothing is dropped or
duplicated. -/
theorem orderCallbacks_perm (es : List Entry) : List.Perm (orderCallbacks es) (es.map (·.id)) :=
  (List.mergeSort_perm es entryLe).map _

/-- With equal order keys and increasing registration numbers, the engine order is the registration order — the
original's `Set` iteration.

$$\forall es:\ \big(\forall i < j:\ o_i = o_j \land q_i \le q_j\big) \Rightarrow \operatorname{orderCallbacks}(es) = [\,e.\mathit{id} \mid e \in es\,]$$

Without explicit order keys the TS engine runs callbacks exactly in the order the original does. -/
theorem orderCallbacks_registration (es : List Entry)
    (h : es.Pairwise (fun a b => a.order = b.order ∧ a.seq ≤ b.seq)) :
    orderCallbacks es = es.map (·.id) := by
  unfold orderCallbacks
  rw [List.mergeSort_of_pairwise]
  refine h.imp ?_
  intro a b ⟨h1, h2⟩
  unfold entryLe; simp [h1, h2]

/-! ## Frame plans (TS model: each callback = one read step, optionally one write step) -/

/-- A step's kind. $$\mathit{op} \in \{\mathrm{read}, \mathrm{write}\}$$ Whether a step only reads layout or writes styles. -/
inductive Op | read | write
deriving Repr, BEq, DecidableEq

/-- A frame step: kind and callback index. $$(\mathit{op}, i) \in \mathit{Op} \times \mathbb{N}$$ One phase of one callback. -/
structure Step where
  op : Op
  i : Nat
deriving Repr, BEq, DecidableEq

/-- Engine variant. $$v \in \{\mathrm{faithful}, \mathrm{batched}\}$$ The two engine.scroll variants. -/
inductive Variant | faithful | batched
deriving Repr, BEq, DecidableEq

/-- Faithful plan from index `k`: read then (if it writes) write, callback by callback.

$$\operatorname{faithfulFrom}(k, [\,]) = [\,],\quad \operatorname{faithfulFrom}(k, w :: ws) = (\mathrm{R}, k) :: \big([(\mathrm{W}, k) \mid w] \mathbin{+\!\!+} \operatorname{faithfulFrom}(k + 1, ws)\big)$$

(here $[(\mathrm{W}, k) \mid w]$ is $[(\mathrm{W}, k)]$ if $w$ and $[\,]$ otherwise).

The original's interleaved order of reads and writes. -/
def faithfulFrom (k : Nat) : List Bool → List Step
  | [] => []
  | w :: ws => ⟨.read, k⟩ :: ((if w then [⟨.write, k⟩] else []) ++ faithfulFrom (k + 1) ws)

/-- All read steps from index `k`. $$\operatorname{readsFrom}(k, ws) = [(\mathrm{R}, k), \dots, (\mathrm{R}, k + |ws| - 1)]$$ Every callback's read phase in order. -/
def readsFrom (k : Nat) : List Bool → List Step
  | [] => []
  | _ :: ws => ⟨.read, k⟩ :: readsFrom (k + 1) ws

/-- All write steps from index `k`. $$\operatorname{writesFrom}(k, ws) = [(\mathrm{W}, k + i) \mid w_i]$$ The write phases of the callbacks that write, in order. -/
def writesFrom (k : Nat) : List Bool → List Step
  | [] => []
  | w :: ws => (if w then [⟨.write, k⟩] else []) ++ writesFrom (k + 1) ws

/-- The frame plan (TS `framePlan`): faithful interleaves, batched does every read, then every write.

$$\operatorname{framePlan}(v, ws) = \begin{cases} \operatorname{faithfulFrom}(0, ws) & v = \mathrm{faithful} \\ \operatorname{readsFrom}(0, ws) \mathbin{+\!\!+} \operatorname{writesFrom}(0, ws) & v = \mathrm{batched} \end{cases}$$

The step order one engine frame follows. -/
def framePlan (v : Variant) (writers : List Bool) : List Step :=
  match v with
  | .faithful => faithfulFrom 0 writers
  | .batched => readsFrom 0 writers ++ writesFrom 0 writers

#guard framePlan .faithful [true, false, true] ==
  [⟨.read, 0⟩, ⟨.write, 0⟩, ⟨.read, 1⟩, ⟨.read, 2⟩, ⟨.write, 2⟩]
#guard framePlan .batched [true, false, true] ==
  [⟨.read, 0⟩, ⟨.read, 1⟩, ⟨.read, 2⟩, ⟨.write, 0⟩, ⟨.write, 2⟩]
#guard framePlan .batched [] == []

/-- Is this step a read. $$\operatorname{isRead}(s) \iff s.\mathit{op} = \mathrm{read}$$ True for read steps. -/
def Step.isRead (s : Step) : Bool :=
  match s.op with
  | .read => true
  | .write => false

/-- Read steps are reads. $$\forall k \in \mathbb{N}:\ \operatorname{isRead}((\mathrm{R}, k)) = \top$$ A read step counts as a read. -/
@[simp] theorem isRead_read (k : Nat) : (⟨.read, k⟩ : Step).isRead = true := rfl

/-- Write steps are not reads. $$\forall k \in \mathbb{N}:\ \operatorname{isRead}((\mathrm{W}, k)) = \bot$$ A write step does not count as a read. -/
@[simp] theorem isRead_write (k : Nat) : (⟨.write, k⟩ : Step).isRead = false := rfl

/-- The read steps of the faithful plan are the batched read phase. $$\forall k, ws:\ \operatorname{filter}_{\mathrm{R}}(\operatorname{faithfulFrom}(k, ws)) = \operatorname{readsFrom}(k, ws)$$ -/
theorem filter_read_faithfulFrom (k : Nat) (ws : List Bool) :
    (faithfulFrom k ws).filter Step.isRead = readsFrom k ws := by
  induction ws generalizing k with
  | nil => rfl
  | cons w ws ih => cases w <;> simp [faithfulFrom, readsFrom, List.filter_cons, ih]

/-- The write steps of the faithful plan are the batched write phase. $$\forall k, ws:\ \operatorname{filter}_{\mathrm{W}}(\operatorname{faithfulFrom}(k, ws)) = \operatorname{writesFrom}(k, ws)$$ -/
theorem filter_write_faithfulFrom (k : Nat) (ws : List Bool) :
    (faithfulFrom k ws).filter (fun s => !s.isRead) = writesFrom k ws := by
  induction ws generalizing k with
  | nil => rfl
  | cons w ws ih => cases w <;> simp [faithfulFrom, writesFrom, ih]

/-- Batched is faithful with its reads moved to the front: the same steps, reads in order, then writes in order.

$$\forall ws:\quad \operatorname{framePlan}(\mathrm{batched}, ws) = \operatorname{filter}_{\mathrm{R}}(F) \mathbin{+\!\!+} \operatorname{filter}_{\mathrm{W}}(F),\quad F = \operatorname{framePlan}(\mathrm{faithful}, ws)$$

The batched engine does exactly the faithful work, only reordered. -/
theorem batched_eq_partition (ws : List Bool) :
    framePlan .batched ws =
      (framePlan .faithful ws).filter Step.isRead ++ (framePlan .faithful ws).filter (fun s => !s.isRead) := by
  simp [framePlan, filter_read_faithfulFrom, filter_write_faithfulFrom]

/-! ## Forced-layout cost model -/

/-- A DOM access: style read (`getComputedStyle` property), layout read (rect, hit test), style-only write
(e.g. `pointer-events`, opacity var), layout-affecting write (geometry).

$$a \in \{\mathrm{RS}, \mathrm{RL}, \mathrm{WS}, \mathrm{WL}\}$$

One read or write a callback performs against the page. -/
inductive Access | readStyle | readLayout | writeStyle | writeLayout
deriving Repr, BEq, DecidableEq

/-- Reads vs writes. $$\operatorname{isReadA}(a) \iff a \in \{\mathrm{RS}, \mathrm{RL}\}$$ True for the two kinds of read. -/
def Access.isRead : Access → Bool
  | .readStyle | .readLayout => true
  | _ => false

/-- How an access affects one dirty flag: it checks (and clears) it, sets it, or leaves it alone.

$$\rho \in \{\mathrm{check}, \mathrm{dirty}, \mathrm{neutral}\}$$

The role an access plays for one kind of pending work (style or layout). -/
inductive Role | check | dirty | neutral
deriving Repr, BEq, DecidableEq

/-- Forced updates of one kind: a `check` while dirty is one forced update and leaves the flag clean.

$$\operatorname{forced}_\rho(d, [\,]) = 0,\quad \operatorname{forced}_\rho(d, a :: as) = \begin{cases} [d] + \operatorname{forced}_\rho(\bot, as) & \rho(a) = \mathrm{check} \\ \operatorname{forced}_\rho(\top, as) & \rho(a) = \mathrm{dirty} \\ \operatorname{forced}_\rho(d, as) & \rho(a) = \mathrm{neutral} \end{cases}$$

How many times the browser must update style (or layout) synchronously during the sequence. -/
def forced (role : Access → Role) : Bool → List Access → Nat
  | _, [] => 0
  | d, a :: as =>
    match role a with
    | .check => (if d then 1 else 0) + forced role false as
    | .dirty => forced role true as
    | .neutral => forced role d as

/-- Style roles: any read checks style, any write dirties it.

$$\rho_S(\mathrm{RS}) = \rho_S(\mathrm{RL}) = \mathrm{check},\ \rho_S(\mathrm{WS}) = \rho_S(\mathrm{WL}) = \mathrm{dirty}$$

What each access does to pending style work. -/
def styleRole : Access → Role
  | .readStyle | .readLayout => .check
  | .writeStyle | .writeLayout => .dirty

/-- Layout roles: layout reads check, layout-affecting writes dirty, the rest is neutral.

$$\rho_L(\mathrm{RL}) = \mathrm{check},\ \rho_L(\mathrm{WL}) = \mathrm{dirty},\ \rho_L(\mathrm{RS}) = \rho_L(\mathrm{WS}) = \mathrm{neutral}$$

What each access does to pending layout work. -/
def layoutRole : Access → Role
  | .readLayout => .check
  | .writeLayout => .dirty
  | _ => .neutral

/-- A role assignment is *sound* when no write checks.

$$\operatorname{sound}(\rho) \iff \forall a:\ \lnot\operatorname{isRead}(a) \Rightarrow \rho(a) \ne \mathrm{check}$$

Writes never force work themselves. -/
def Sound (role : Access → Role) : Prop := ∀ a, a.isRead = false → role a ≠ .check

/-- Writes never check style. $$\operatorname{sound}(\rho_S)$$ -/
theorem styleRole_sound : Sound styleRole := by intro a h; cases a <;> simp_all [Access.isRead, styleRole]
/-- Writes never check layout. $$\operatorname{sound}(\rho_L)$$ -/
theorem layoutRole_sound : Sound layoutRole := by intro a h; cases a <;> simp_all [Access.isRead, layoutRole]

/-- More pending work never means fewer forced updates.

$$\forall \rho, as, d, e:\quad (d \Rightarrow e) \Rightarrow \operatorname{forced}_\rho(d, as) \le \operatorname{forced}_\rho(e, as)$$

Starting a sequence dirty can only add forced updates, never remove them. -/
theorem forced_mono (role : Access → Role) (as : List Access) :
    ∀ d e : Bool, (d = true → e = true) → forced role d as ≤ forced role e as := by
  induction as with
  | nil => intro d e _; simp [forced]
  | cons a as ih =>
    intro d e h
    simp only [forced]
    cases role a with
    | check => cases d <;> cases e <;> simp_all
    | dirty => exact Nat.le_refl _
    | neutral => exact ih d e h

/-- A run of writes forces nothing. $$\forall \rho \text{ sound},\ d,\ bs:\ (\forall b \in bs:\ \lnot\operatorname{isReadA}(b)) \Rightarrow \operatorname{forced}_\rho(d, bs) = 0$$ -/
theorem forced_writes_only (role : Access → Role) (hs : Sound role) (bs : List Access)
    (hb : ∀ b ∈ bs, b.isRead = false) (d : Bool) : forced role d bs = 0 := by
  induction bs generalizing d with
  | nil => simp [forced]
  | cons b bs ih =>
    have hb0 := hs b (hb b (by simp))
    simp only [forced]
    cases hr : role b with
    | check => exact absurd hr hb0
    | dirty => exact ih (fun x hx => hb x (by simp [hx])) _
    | neutral => exact ih (fun x hx => hb x (by simp [hx])) _

/-- Appending writes adds no forced work. $$\forall \rho \text{ sound},\ d,\ as,\ bs:\ (\forall b \in bs:\ \lnot\operatorname{isReadA}(b)) \Rightarrow \operatorname{forced}_\rho(d, as \mathbin{+\!\!+} bs) = \operatorname{forced}_\rho(d, as)$$ -/
theorem forced_append_writes (role : Access → Role) (hs : Sound role) (as bs : List Access)
    (hb : ∀ b ∈ bs, b.isRead = false) (d : Bool) : forced role d (as ++ bs) = forced role d as := by
  induction as generalizing d with
  | nil => simp [forced, forced_writes_only role hs bs hb]
  | cons a as ih =>
    simp only [List.cons_append, forced]
    cases role a <;> simp [ih]

/-- Dropping the writes never adds forced work. $$\forall \rho \text{ sound},\ d,\ as:\ \operatorname{forced}_\rho(d, \operatorname{filter}_{\mathrm{R}}(as)) \le \operatorname{forced}_\rho(d, as)$$ -/
theorem forced_filter_reads (role : Access → Role) (hs : Sound role) (as : List Access) (d : Bool) :
    forced role d (as.filter Access.isRead) ≤ forced role d as := by
  induction as generalizing d with
  | nil => simp [forced]
  | cons a as ih =>
    cases hra : a.isRead
    · -- a write: dropped by the filter; it only makes the state dirtier
      simp only [List.filter_cons, hra]
      have hc := hs a hra
      simp only [Bool.false_eq_true, ↓reduceIte, forced]
      cases hr : role a with
      | check => exact absurd hr hc
      | dirty => exact Nat.le_trans (ih d) (forced_mono role as d true (fun _ => rfl))
      | neutral => exact ih d
    · simp only [List.filter_cons, hra, ↓reduceIte, forced]
      cases role a with
      | check => have := ih false; dsimp only; omega
      | dirty => exact ih true
      | neutral => exact ih d

/-- Batching all reads before all writes never forces more updates, for any access sequence and any start state.

$$\forall \rho \text{ sound},\ d,\ as:\quad \operatorname{forced}_\rho\big(d, \operatorname{filter}_{\mathrm{R}}(as) \mathbin{+\!\!+} \operatorname{filter}_{\mathrm{W}}(as)\big) \le \operatorname{forced}_\rho(d, as)$$

Reordering a frame's accesses into "all reads, then all writes" can only remove forced style or layout passes
(it may change what the reads see; that is the variant's parity question, not a cost question). -/
theorem batched_le_faithful (role : Access → Role) (hs : Sound role) (as : List Access) (d : Bool) :
    forced role d (as.filter Access.isRead ++ as.filter (fun a => !a.isRead)) ≤ forced role d as := by
  rw [forced_append_writes role hs]
  · exact forced_filter_reads role hs as d
  · intro b hb; simp [List.mem_filter] at hb; simpa using hb.2

/-- Batched costs at most one forced update per kind: the first read pays for what was pending at frame start.

$$\forall \rho \text{ sound with } (\forall a:\ \operatorname{isReadA}(a) \Rightarrow \rho(a) \ne \mathrm{dirty}),\ d,\ as:\quad \operatorname{forced}_\rho\big(d, \operatorname{filter}_{\mathrm{R}}(as) \mathbin{+\!\!+} \operatorname{filter}_{\mathrm{W}}(as)\big) \le 1$$

($\rho_S$ and $\rho_L$ both meet the side condition: no read dirties.) A batched frame forces style at most once and layout at most once. -/
theorem batched_le_one (role : Access → Role) (hs : Sound role) (as : List Access) (d : Bool)
    (hr : ∀ a, a.isRead = true → role a ≠ .dirty) :
    forced role d (as.filter Access.isRead ++ as.filter (fun a => !a.isRead)) ≤ 1 := by
  rw [forced_append_writes role hs]
  · have key : ∀ (bs : List Access) (d : Bool), (∀ b ∈ bs, b.isRead = true) →
        forced role d bs ≤ (if d then 1 else 0) := by
      intro bs
      induction bs with
      | nil => intro d _; simp [forced]
      | cons b bs ih =>
        intro d hb
        have hbr := hb b (by simp)
        have hrest : ∀ x ∈ bs, x.isRead = true := fun x hx => hb x (by simp [hx])
        simp only [forced]
        cases hrole : role b with
        | check => have := ih false hrest; cases d <;> simp_all
        | dirty => exact absurd hrole (hr b hbr)
        | neutral => exact ih d hrest
    have := key (as.filter Access.isRead) d (by intro b hb; simp [List.mem_filter] at hb; exact hb.2)
    split at this <;> omega
  · intro b hb; simp [List.mem_filter] at hb; simpa using hb.2

/-! ## The TS frame plan under the cost model -/

/-- A TS plan step as an access: a read phase reads layout, a write phase may change layout (worst case).

$$\operatorname{access}(\mathrm{R}, i) = \mathrm{RL},\quad \operatorname{access}(\mathrm{W}, i) = \mathrm{WL}$$

How each step of the TS frame plan is costed. -/
def Step.access (s : Step) : Access := if s.isRead then .readLayout else .writeLayout

/-- Forced layouts of a TS frame plan.

$$\operatorname{planLayouts}(d, P) = \operatorname{forced}_{\rho_L}(d, [\operatorname{access}(s) \mid s \in P])$$

How many synchronous layouts one engine frame forces. -/
def planLayouts (d : Bool) (p : List Step) : Nat := forced layoutRole d (p.map Step.access)

/-- **Batched ≤ faithful** for the TS frame plan, for every writer pattern and start state.

$$\forall d, ws:\quad \operatorname{planLayouts}(d, \operatorname{framePlan}(\mathrm{batched}, ws)) \le \operatorname{planLayouts}(d, \operatorname{framePlan}(\mathrm{faithful}, ws))$$

The batched engine never forces more layouts in a frame than the faithful one. -/
theorem framePlan_batched_le (d : Bool) (ws : List Bool) :
    planLayouts d (framePlan .batched ws) ≤ planLayouts d (framePlan .faithful ws) := by
  rw [batched_eq_partition]
  unfold planLayouts
  have hmap : ∀ p : List Step, (p.filter Step.isRead).map Step.access = (p.map Step.access).filter Access.isRead ∧
      (p.filter (fun s => !s.isRead)).map Step.access = (p.map Step.access).filter (fun a => !a.isRead) := by
    intro p
    induction p with
    | nil => simp
    | cons s p ih =>
      cases h : s.isRead <;> simp [List.filter_cons, h, Step.access, Access.isRead, ih.1, ih.2]
  rw [List.map_append, (hmap _).1, (hmap _).2]
  exact batched_le_faithful layoutRole layoutRole_sound _ d

/-- Faithful plan cost, one callback at a time: a read pays for the pending flag, then the callback's write sets it.

$$\forall d, k, w, ws:\ \operatorname{planLayouts}(d, \operatorname{faithfulFrom}(k, w :: ws)) = [d] + \operatorname{planLayouts}(w, \operatorname{faithfulFrom}(k + 1, ws))$$

Each callback's read forces a layout exactly when the previous callback wrote. -/
theorem planLayouts_faithfulFrom (d : Bool) (k : Nat) (w : Bool) (ws : List Bool) :
    planLayouts d (faithfulFrom k (w :: ws)) = (if d then 1 else 0) + planLayouts w (faithfulFrom (k + 1) ws) := by
  cases w <;> simp [planLayouts, faithfulFrom, forced, Step.access, Step.isRead, layoutRole]

/-- Number of `true` entries. $$\#_\top(ws) = |\{i : w_i\}|$$ How many callbacks write. -/
def countTrue (ws : List Bool) : Nat := (ws.filter id).length

/-- Faithful plan cost from any index. $$\forall d, k, ws:\ \operatorname{planLayouts}(d, \operatorname{faithfulFrom}(k, ws)) = [d \land ws \ne [\,]] + \#_\top(\operatorname{dropLast}(ws))$$ -/
theorem planLayouts_faithful_formula (d : Bool) (k : Nat) (ws : List Bool) :
    planLayouts d (faithfulFrom k ws) = (if d && !ws.isEmpty then 1 else 0) + countTrue ws.dropLast := by
  induction ws generalizing d k with
  | nil => simp [planLayouts, faithfulFrom, forced, countTrue]
  | cons w ws ih =>
    rw [planLayouts_faithfulFrom, ih]
    cases ws with
    | nil => cases d <;> simp [countTrue]
    | cons w' ws' =>
      cases d <;> cases w <;> simp [countTrue, List.dropLast_cons_cons] <;> omega

/-- Exact faithful cost: the frame-start layout (if dirty) plus one forced layout per writer that is followed by
another callback.

$$\forall d, ws:\quad \operatorname{planLayouts}(d, \operatorname{framePlan}(\mathrm{faithful}, ws)) = [d \land ws \ne [\,]] + \#_\top(\operatorname{dropLast}(ws))$$

In the faithful engine every writing callback except the last makes the next callback's read force a layout. -/
theorem framePlan_faithful_cost (d : Bool) (ws : List Bool) :
    planLayouts d (framePlan .faithful ws) = (if d && !ws.isEmpty then 1 else 0) + countTrue ws.dropLast :=
  planLayouts_faithful_formula d 0 ws

/-! ## Scheduling (rE / iE) and listeners (aE / oE) -/

/-- `rE`: request a frame iff none is pending (JS 2667-2669).

$$\operatorname{shouldSchedule}(p) = \lnot p$$

A scroll or resize event asks for a frame only when none is already queued. -/
def shouldSchedule (pending : Bool) : Bool := !pending

#guard shouldSchedule false == true && shouldSchedule true == false

/-- An engine input: a scroll/resize event, or a rendering frame. $$\mathit{ev} \in \{\mathrm{scroll}, \mathrm{frame}\}$$ What can happen to the engine between frames. -/
inductive Ev | scroll | frame
deriving Repr, BEq, DecidableEq

/-- Engine runs (`iE` calls) over an event trace, from a pending flag.

$$\operatorname{runs}(p, [\,]) = 0,\ \operatorname{runs}(p, \mathrm{scroll} :: es) = \operatorname{runs}(p \lor \operatorname{shouldSchedule}(p), es),\ \operatorname{runs}(p, \mathrm{frame} :: es) = [p] + \operatorname{runs}(\bot, es)$$

How many times the callbacks run for a sequence of events and frames. -/
def runs : Bool → List Ev → Nat
  | _, [] => 0
  | p, .scroll :: es => runs (p || shouldSchedule p) es
  | p, .frame :: es => (if p then 1 else 0) + runs false es

/-- Count of one event kind. $$\#_x(es) = |\{i : es_i = x\}|$$ How many events of a kind a trace has. -/
def countEv (x : Ev) (es : List Ev) : Nat := (es.filter (fun e => decide (e = x))).length

/-- Coalescing: at most one run per frame, and (from idle) at most one run per scroll event.

$$\forall p, es:\quad \operatorname{runs}(p, es) \le \#_{\mathrm{frame}}(es) \ \land\ \operatorname{runs}(p, es) \le [p] + \#_{\mathrm{scroll}}(es)$$

(Iverson bracket: $[p] = 1$ if a run is already pending, else $0$.)

However many scroll events arrive, the callbacks run at most once per frame, and never without a request. -/
theorem runs_le (p : Bool) (es : List Ev) :
    runs p es ≤ countEv .frame es ∧ runs p es ≤ (if p then 1 else 0) + countEv .scroll es := by
  induction es generalizing p with
  | nil => simp [runs, countEv]
  | cons e es ih =>
    cases e with
    | scroll =>
      have := ih true
      cases p <;> simp_all [runs, countEv, shouldSchedule] <;> omega
    | frame =>
      have := ih false
      cases p <;> simp_all [runs, countEv] <;> omega

#guard runs false [.scroll, .scroll, .scroll, .frame, .frame, .scroll, .frame] == 2

/-- Listener action (`aE`/`oE`): attach when callbacks exist and none attached; detach when the set is empty.

$$\operatorname{listenerAction}(a, n) = \begin{cases} \mathrm{attach} & n > 0 \land \lnot a \\ \mathrm{detach} & n = 0 \land a \\ \mathrm{none} & \text{otherwise} \end{cases}$$

Whether the engine must add or remove its scroll and resize listeners. -/
def listenerAction (attached : Bool) (size : Nat) : String :=
  if size > 0 && !attached then "attach" else if size == 0 && attached then "detach" else "none"

#guard listenerAction false 1 == "attach" && listenerAction true 2 == "none"
#guard listenerAction true 0 == "detach" && listenerAction false 0 == "none"

/-- The attached flag after applying an action. $$\operatorname{after}(a, x) = (x = \mathrm{attach}) \lor (a \land x \ne \mathrm{detach})$$ The listener state once the action is done. -/
def attachedAfter (attached : Bool) (action : String) : Bool :=
  action == "attach" || (attached && action != "detach")

/-- Listeners are attached exactly while callbacks are registered.

$$\forall a, n:\quad \operatorname{after}(a, \operatorname{listenerAction}(a, n)) \iff n > 0$$

After every registration change the engine listens exactly when it has something to run. -/
theorem listener_invariant (attached : Bool) (size : Nat) :
    attachedAfter attached (listenerAction attached size) = decide (size > 0) := by
  unfold attachedAfter listenerAction
  cases attached <;> cases size <;> simp

/-! ## The original's pilot callbacks under the cost model (INFERRED roles; see module doc) -/

/-- The nav callback `L` → `_` outside the morph (JS 12964-13007): `ee()` reads (`position`, `top`, two rects),
`F()` (nav rect, `pointer-events` write, `elementFromPoint`, restore write), then the hero-track rect.

$$\mathit{nav} = [\mathrm{RS}, \mathrm{RS}, \mathrm{RL}, \mathrm{RL}, \mathrm{RL}, \mathrm{WS}, \mathrm{RL}, \mathrm{WS}, \mathrm{RL}]$$

The nav's per-frame accesses in the original's order. -/
def navAccesses : List Access :=
  [.readStyle, .readStyle, .readLayout, .readLayout, .readLayout, .writeStyle, .readLayout, .writeStyle, .readLayout]

/-- The hero exit body (JS 4162-4171): track rect, `--exit-opacity` write, `pointer-events` write.

$$\mathit{hero} = [\mathrm{RL}, \mathrm{WS}, \mathrm{WS}]$$

The hero exit's per-frame accesses. -/
def heroExitAccesses : List Access := [.readLayout, .writeStyle, .writeStyle]

/-- Steady-scroll faithful frame: the hero body's own rAF (queued in the previous frame) runs before `iE`.

$$\mathit{frame} = \mathit{hero} \mathbin{+\!\!+} \mathit{nav}$$

The pilot part of one scrolling frame in the original. -/
def pilotFrame : List Access := heroExitAccesses ++ navAccesses

-- faithful: the hero write dirties style before the nav reads, and the nav's own write-read-write adds two more
#guard forced styleRole true pilotFrame == 4
#guard forced styleRole false pilotFrame == 3
#guard forced layoutRole true pilotFrame == 1
-- batched: one *forced* style pass at most; the frame-end lifecycle pass comes on top (`total`, below): 2 and 1
#guard forced styleRole true (pilotFrame.filter Access.isRead ++ pilotFrame.filter (fun a => !a.isRead)) == 1
#guard forced styleRole false (pilotFrame.filter Access.isRead ++ pilotFrame.filter (fun a => !a.isRead)) == 0

/-! ## Total passes: forced plus the frame-end pass (ledger n=1, 2, 22)

`forced` counts only the passes a read forces. The browser also runs one lifecycle pass at frame end when the flag
is still dirty (`Fw.Engine.frameWorkE`). The bridge maps a role assignment onto the Core flag machine, so
`Fw.Engine.flagTotal_closed` and `Fw.Engine.flagTotal_remove_check` apply to access sequences. With the frame-end
pass counted, batching is no longer "never worse": it merges write runs (a win), but when the frame starts dirty with
a write and has a read, the batched read pays the start flag alone and the writes are paid again at frame end. -/

section Total

open Fw.Engine (FlagOp flagForced flagEnd flagTotal firstFlag dirtyRuns flagTotal_closed flagTotal_remove_check
  flagTotal_append)

/-- A role as a Core flag operation.

$$\operatorname{flag}(\mathrm{check}) = \mathrm{check},\ \operatorname{flag}(\mathrm{dirty}) = \mathrm{dirty},\ \operatorname{flag}(\mathrm{neutral}) = \mathrm{neutral}$$

The same three roles, in the Core vocabulary. -/
def Role.toFlag : Role → FlagOp
  | .check => .check
  | .dirty => .dirty
  | .neutral => .neutral

/-- An access sequence as flag operations under a role assignment.

$$\operatorname{flags}_\rho(as) = [\operatorname{flag}(\rho(a))]_{a \in as}$$

What the sequence does to one stage's dirty flag. -/
def flags (ρ : Access → Role) (as : List Access) : List FlagOp := as.map fun a => (ρ a).toFlag

/-- `flags` distributes over concatenation.

$$\forall \rho,\ \forall as, bs:\ \operatorname{flags}_\rho(as \mathbin{+\!\!+} bs) = \operatorname{flags}_\rho(as) \mathbin{+\!\!+} \operatorname{flags}_\rho(bs)$$

Flags of consecutive runs are consecutive. -/
theorem flags_append (ρ : Access → Role) (as bs : List Access) : flags ρ (as ++ bs) = flags ρ as ++ flags ρ bs := by
  simp [flags]

/-- **The bridge.** `forced` is the Core flag machine's forced count on the role flags.

$$\forall \rho,\ \forall d \in \mathbb{B},\ \forall as:\ \operatorname{forced}_\rho(d, as) = \operatorname{fF}(d, \operatorname{flags}_\rho(as))$$

The part's cost model and Core's flag machine count the same forced passes. -/
theorem forced_eq_flagForced (ρ : Access → Role) : ∀ (d : Bool) (as : List Access),
    forced ρ d as = flagForced d (flags ρ as)
  | _, [] => rfl
  | d, a :: as => by
    have ih := fun e => forced_eq_flagForced ρ e as
    show _ = flagForced d ((ρ a).toFlag :: flags ρ as)
    cases h : ρ a <;> cases d <;> simp [forced, h, Role.toFlag, flagForced, ih]

/-- **Total passes of one stage in one frame**: forced passes plus the frame-end lifecycle pass when the flag ends
dirty (the trace count of the stage).

$$\operatorname{total}_\rho(d, as) = \operatorname{fT}(d, \operatorname{flags}_\rho(as)) = \operatorname{forced}_\rho(d, as) + [\operatorname{fE}(d, \operatorname{flags}_\rho(as))]$$

All passes the stage runs, not only the forced ones. -/
def total (ρ : Access → Role) (d : Bool) (as : List Access) : Nat := flagTotal d (flags ρ as)

/-- `total` is `forced` plus the end flag.

$$\forall \rho,\ \forall d,\ \forall as:\ \operatorname{total}_\rho(d, as) = \operatorname{forced}_\rho(d, as) + [\operatorname{fE}(d, \operatorname{flags}_\rho(as))]$$

The old count plus the frame-end pass. -/
theorem total_eq (ρ : Access → Role) (d : Bool) (as : List Access) :
    total ρ d as = forced ρ d as + (flagEnd d (flags ρ as)).toNat := by
  simp [total, flagTotal, forced_eq_flagForced]

/-- Maximal runs of writes in an access sequence (reads close a run); `p` says whether a run is open.

$$\operatorname{wruns}(p, [\,]) = 0,\quad \operatorname{wruns}(p, a :: as) = \begin{cases} \operatorname{wruns}(\bot, as) & a \text{ is a read} \\ [\lnot p] + \operatorname{wruns}(\top, as) & a \text{ is a write} \end{cases}$$

How many write batches the sequence makes. -/
def writeRuns : Bool → List Access → Nat
  | _, [] => 0
  | p, a :: as => if a.isRead then writeRuns false as else (!p).toNat + writeRuns true as

/-- Whether the sequence is empty or starts with a read.

$$\operatorname{headRead}([\,]) = \top,\quad \operatorname{headRead}(a :: as) = \operatorname{isRead}(a)$$

No leading write. -/
def headRead : List Access → Bool
  | [] => true
  | a :: _ => a.isRead

#guard writeRuns false pilotFrame == 3
#guard writeRuns false [.writeStyle, .writeLayout, .readStyle, .writeStyle] == 2
#guard headRead [] && headRead [.readLayout] && !headRead [.writeStyle]

/-- Write runs are the Core write runs of the style flags.

$$\forall p \in \mathbb{B},\ \forall as:\ \operatorname{wruns}(p, as) = \operatorname{runs}(p, \operatorname{flags}_{\rho_S}(as))$$

Under the style role every write dirties and every read checks. -/
theorem writeRuns_eq (p : Bool) (as : List Access) : writeRuns p as = dirtyRuns p (flags styleRole as) := by
  induction as generalizing p with
  | nil => rfl
  | cons a as ih =>
    cases a <;> simp [writeRuns, flags, Access.isRead, styleRole, Role.toFlag, dirtyRuns, ih] <;> rfl

/-- Under the style role the first flag is a write exactly when the sequence starts with a write.

$$\forall as:\ \operatorname{first}(\operatorname{flags}_{\rho_S}(as)) = \mathrm{dirty} \iff \lnot\operatorname{headRead}(as)$$

No access is neutral for style. -/
theorem firstFlag_style (as : List Access) :
    firstFlag (flags styleRole as) = some .dirty ↔ headRead as = false := by
  cases as with
  | nil => simp [flags, firstFlag, headRead]
  | cons a as => cases a <;> simp [flags, firstFlag, headRead, styleRole, Role.toFlag, Access.isRead]

/-- **Closed form of all style passes (ledger n=1 row 1).** A frame's style passes, forced plus frame-end, are its
write runs, plus one when it starts dirty and does not start with a write.

$$\forall d \in \mathbb{B},\ \forall as \in \mathrm{Access}^{*}:\ \operatorname{total}_{\rho_S}(d, as) = [d \land \operatorname{headRead}(as)] + \operatorname{wruns}(\bot, as)$$

Each write batch costs one style pass, whoever pays it; a dirty start costs one more unless a write absorbs it. -/
theorem total_style_closed (d : Bool) (as : List Access) :
    total styleRole d as = (if d = true ∧ headRead as = true then 1 else 0) + writeRuns false as := by
  rw [total, flagTotal_closed, writeRuns_eq]
  have h := firstFlag_style as
  by_cases hh : headRead as = true
  · have : firstFlag (flags styleRole as) ≠ some .dirty := by rw [Ne, h]; simp [hh]
    simp [this, hh]
  · have : firstFlag (flags styleRole as) = some .dirty := by rw [h]; simpa using hh
    simp [this, hh]

/-- **A dirty start costs at most one more pass, in total.** Starting dirty never lowers the total and raises it by at
most one.

$$\forall \rho,\ \forall as:\ \operatorname{total}_\rho(\bot, as) \le \operatorname{total}_\rho(\top, as) \le \operatorname{total}_\rho(\bot, as) + 1$$

The start flag is paid at most once, by a read or at frame end. -/
theorem total_start_bounds (ρ : Access → Role) (as : List Access) :
    total ρ false as ≤ total ρ true as ∧ total ρ true as ≤ total ρ false as + 1 := by
  simp only [total, flagTotal_closed]
  by_cases h : firstFlag (flags ρ as) = some .dirty <;> simp [h] <;> omega

/-! ### Batching under the frame-end pass -/

/-- Flag total of a sequence with no write followed by a sequence with no read.

$$\forall d,\ \forall w \in \mathrm{FlagOp}^{*}:\ \mathrm{check} \notin w \Rightarrow \operatorname{fT}(d, w) = [d \land \mathrm{dirty} \notin w] + [\mathrm{dirty} \in w]$$

A write-only stretch ends dirty once it writes. -/
theorem flagTotal_noCheck : ∀ (d : Bool) (w : List FlagOp), FlagOp.check ∉ w →
    flagTotal d w = (if d = true ∧ FlagOp.dirty ∉ w then 1 else 0) + (if FlagOp.dirty ∈ w then 1 else 0)
  | d, [], _ => by cases d <;> rfl
  | _, .check :: _, h => absurd (List.mem_cons_self ..) h
  | d, .dirty :: w, h => by
    have ih := flagTotal_noCheck true w (fun hm => h (List.mem_cons_of_mem _ hm))
    have hc : flagTotal d (.dirty :: w) = flagTotal true w := rfl
    rw [hc, ih]; by_cases hw : FlagOp.dirty ∈ w <;> simp [hw]
  | d, .neutral :: w, h => by
    have ih := flagTotal_noCheck d w (fun hm => h (List.mem_cons_of_mem _ hm))
    have hc : flagTotal d (.neutral :: w) = flagTotal d w := rfl
    rw [hc, ih]; simp

/-- **Reads first, then writes, in flags.** For a read stretch $r$ (no write) followed by a write stretch $w$ (no
read), the total is one pass for the writes plus one for a dirty start that a read pays or that no write absorbs.

$$\forall d,\ \forall r, w \in \mathrm{FlagOp}^{*}:\ \mathrm{dirty} \notin r \land \mathrm{check} \notin w \Rightarrow \operatorname{fT}(d, r \mathbin{+\!\!+} w) = [d \land (\mathrm{check} \in r \lor \mathrm{dirty} \notin w)] + [\mathrm{dirty} \in w]$$

A batched frame pays at most one pass for the start flag and one for its writes. -/
theorem flagTotal_reads_writes : ∀ (d : Bool) (r w : List FlagOp), FlagOp.dirty ∉ r → FlagOp.check ∉ w →
    flagTotal d (r ++ w) =
      (if d = true ∧ (FlagOp.check ∈ r ∨ FlagOp.dirty ∉ w) then 1 else 0) + (if FlagOp.dirty ∈ w then 1 else 0)
  | d, [], w, _, hw => by rw [List.nil_append, flagTotal_noCheck d w hw]; simp
  | d, .check :: r, w, hr, hw => by
    have hc : flagTotal d ((.check :: r) ++ w) = d.toNat + flagTotal false (r ++ w) := by
      simp only [List.cons_append, flagTotal, flagForced, flagEnd]; omega
    have hz := flagTotal_reads_writes false r w (fun hm => hr (List.mem_cons_of_mem _ hm)) hw
    rw [hc, hz]; cases d <;> simp
  | _, .dirty :: _, _, hr, _ => absurd (List.mem_cons_self ..) hr
  | d, .neutral :: r, w, hr, hw => by
    have ih := flagTotal_reads_writes d r w (fun hm => hr (List.mem_cons_of_mem _ hm)) hw
    have hc : flagTotal d ((.neutral :: r) ++ w) = flagTotal d (r ++ w) := rfl
    rw [hc, ih]; simp

/-- The first non-neutral flag is absent, a check, or a write, and it occurs in the list.

$$\forall F \in \mathrm{FlagOp}^{*}:\ (\operatorname{first}(F) = \mathrm{none} \land \mathrm{check} \notin F \land \mathrm{dirty} \notin F) \lor (\operatorname{first}(F) = \mathrm{check} \land \mathrm{check} \in F) \lor (\operatorname{first}(F) = \mathrm{dirty} \land \mathrm{dirty} \in F)$$

A list with no first non-neutral flag is all neutral. -/
theorem firstFlag_cases : ∀ F : List FlagOp,
    (firstFlag F = none ∧ FlagOp.check ∉ F ∧ FlagOp.dirty ∉ F) ∨
      (firstFlag F = some .check ∧ FlagOp.check ∈ F) ∨ (firstFlag F = some .dirty ∧ FlagOp.dirty ∈ F)
  | [] => by simp [firstFlag]
  | .check :: _ => by simp [firstFlag]
  | .dirty :: _ => by simp [firstFlag]
  | .neutral :: F => by rcases firstFlag_cases F with h | h | h <;> simp [firstFlag, h]

/-- Write runs vanish without a write.

$$\forall p,\ \forall F:\ \mathrm{dirty} \notin F \Rightarrow \operatorname{runs}(p, F) = 0$$

No write, no write batch. -/
theorem dirtyRuns_noDirty : ∀ (p : Bool) (F : List FlagOp), FlagOp.dirty ∉ F → dirtyRuns p F = 0
  | _, [], _ => rfl
  | _, .check :: F, h => dirtyRuns_noDirty false F (fun hm => h (List.mem_cons_of_mem _ hm))
  | _, .dirty :: _, h => absurd (List.mem_cons_self ..) h
  | p, .neutral :: F, h => dirtyRuns_noDirty p F (fun hm => h (List.mem_cons_of_mem _ hm))

/-- A write makes at least one write run.

$$\forall F:\ \mathrm{dirty} \in F \Rightarrow 1 \le \operatorname{runs}(\bot, F)$$

Some write starts a batch. -/
theorem dirtyRuns_pos : ∀ F : List FlagOp, FlagOp.dirty ∈ F → 1 ≤ dirtyRuns false F
  | [], h => absurd h (List.not_mem_nil)
  | .check :: F, h => dirtyRuns_pos F (by simpa using h)
  | .dirty :: F, _ => by simp [dirtyRuns]
  | .neutral :: F, h => dirtyRuns_pos F (by simpa using h)

/-- The batched order: all reads, then all writes, each in frame order.

$$\operatorname{batch}(as) = \operatorname{filter}_{\mathrm{R}}(as) \mathbin{+\!\!+} \operatorname{filter}_{\mathrm{W}}(as)$$

The "read everything, then write everything" frame. -/
def batch (as : List Access) : List Access := as.filter Access.isRead ++ as.filter (fun a => !a.isRead)

/-- **Batched total.** For a sound role assignment in which no read dirties, the batched frame pays one pass for its
writes and one for a dirty start that a read pays or that no write absorbs.

$$\forall \rho \text{ sound with } (\forall a:\ \operatorname{isReadA}(a) \Rightarrow \rho(a) \ne \mathrm{dirty}),\ \forall d,\ \forall as,\ F = \operatorname{flags}_\rho(as):\ \operatorname{total}_\rho(d, \operatorname{batch}(as)) = [d \land (\mathrm{check} \in F \lor \mathrm{dirty} \notin F)] + [\mathrm{dirty} \in F]$$

Batching makes at most one write run and one start-flag payment. -/
theorem total_batch (ρ : Access → Role) (hs : Sound ρ) (hr : ∀ a, a.isRead = true → ρ a ≠ .dirty) (d : Bool)
    (as : List Access) :
    total ρ d (batch as) =
      (if d = true ∧ (FlagOp.check ∈ flags ρ as ∨ FlagOp.dirty ∉ flags ρ as) then 1 else 0) +
        (if FlagOp.dirty ∈ flags ρ as then 1 else 0) := by
  have hR : FlagOp.dirty ∉ flags ρ (as.filter Access.isRead) := by
    simp only [flags, List.mem_map, List.mem_filter, not_exists, not_and, and_imp]
    intro a _ har h
    have := hr a har
    cases hh : ρ a <;> simp_all [Role.toFlag]
  have hW : FlagOp.check ∉ flags ρ (as.filter (fun a => !a.isRead)) := by
    simp only [flags, List.mem_map, List.mem_filter, not_exists, not_and, and_imp]
    intro a _ har h
    have := hs a (by simpa using har)
    cases hh : ρ a <;> simp_all [Role.toFlag]
  have hc : FlagOp.check ∈ flags ρ (as.filter Access.isRead) ↔ FlagOp.check ∈ flags ρ as := by
    simp only [flags, List.mem_map, List.mem_filter]
    constructor
    · rintro ⟨a, ⟨ha, _⟩, h⟩; exact ⟨a, ha, h⟩
    · rintro ⟨a, ha, h⟩
      refine ⟨a, ⟨ha, ?_⟩, h⟩
      cases hra : a.isRead
      · have := hs a hra; cases hh : ρ a <;> simp_all [Role.toFlag]
      · rfl
  have hd : FlagOp.dirty ∈ flags ρ (as.filter (fun a => !a.isRead)) ↔ FlagOp.dirty ∈ flags ρ as := by
    simp only [flags, List.mem_map, List.mem_filter]
    constructor
    · rintro ⟨a, ⟨ha, _⟩, h⟩; exact ⟨a, ha, h⟩
    · rintro ⟨a, ha, h⟩
      refine ⟨a, ⟨ha, ?_⟩, h⟩
      cases hra : a.isRead
      · rfl
      · have := hr a hra; cases hh : ρ a <;> simp_all [Role.toFlag]
  rw [total, batch, flags_append, flagTotal_reads_writes d _ _ hR hW]
  simp only [hc, hd]

/-- **The batching delta (ledger n=1 row 2, n=22).** With $F$ the role flags of the frame, batching changes the
total by the write runs it merges, minus one for the run it keeps, plus one when the frame starts dirty with a write
and has a read (stated additively, so no truncated subtraction).

$$\forall \rho \text{ sound with } (\forall a:\ \operatorname{isReadA}(a) \Rightarrow \rho(a) \ne \mathrm{dirty}),\ \forall d,\ \forall as,\ F = \operatorname{flags}_\rho(as):\ \operatorname{total}_\rho(d, \operatorname{batch}(as)) + \operatorname{runs}(\bot, F) = \operatorname{total}_\rho(d, as) + [\mathrm{dirty} \in F] + [d \land \operatorname{first}(F) = \mathrm{dirty} \land \mathrm{check} \in F]$$

Batching saves one pass per extra write run, and costs one when a leading write was absorbing the dirty start. -/
theorem total_batch_delta (ρ : Access → Role) (hs : Sound ρ) (hr : ∀ a, a.isRead = true → ρ a ≠ .dirty)
    (d : Bool) (as : List Access) :
    total ρ d (batch as) + dirtyRuns false (flags ρ as) =
      total ρ d as + (if FlagOp.dirty ∈ flags ρ as then 1 else 0) +
        (if d = true ∧ firstFlag (flags ρ as) = some .dirty ∧ FlagOp.check ∈ flags ρ as then 1 else 0) := by
  rw [total_batch ρ hs hr, total, flagTotal_closed]
  rcases firstFlag_cases (flags ρ as) with ⟨h1, h2, h3⟩ | ⟨h1, h2⟩ | ⟨h1, h2⟩
  · rw [dirtyRuns_noDirty false _ h3]; cases d <;> simp [h1, h2, h3]
  · cases d <;> simp [h1, h2] <;> omega
  · cases d <;> simp [h1, h2] <;> omega

/-- **When batching is worse.** Batching adds a pass exactly when the frame starts dirty, its first flag access is a
write, it has a read, and all its writes form one run.

$$\forall \rho \text{ sound with } (\forall a:\ \operatorname{isReadA}(a) \Rightarrow \rho(a) \ne \mathrm{dirty}),\ \forall d,\ \forall as,\ F = \operatorname{flags}_\rho(as):\ \operatorname{total}_\rho(d, as) < \operatorname{total}_\rho(d, \operatorname{batch}(as)) \iff d \land \operatorname{first}(F) = \mathrm{dirty} \land \mathrm{check} \in F \land \operatorname{runs}(\bot, F) = 1$$

A single write run that already absorbed the dirty start loses that absorption when the reads move first. -/
theorem total_batch_worse_iff (ρ : Access → Role) (hs : Sound ρ) (hr : ∀ a, a.isRead = true → ρ a ≠ .dirty)
    (d : Bool) (as : List Access) :
    total ρ d as < total ρ d (batch as) ↔
      (d = true ∧ firstFlag (flags ρ as) = some .dirty ∧ FlagOp.check ∈ flags ρ as ∧
        dirtyRuns false (flags ρ as) = 1) := by
  have hδ := total_batch_delta ρ hs hr d as
  rcases firstFlag_cases (flags ρ as) with ⟨h1, h2, h3⟩ | ⟨h1, h2⟩ | ⟨h1, h2⟩
  · rw [dirtyRuns_noDirty false _ h3] at hδ ⊢; cases d <;> simp [h1, h2, h3] at hδ ⊢ <;> omega
  · by_cases hD : FlagOp.dirty ∈ flags ρ as
    · have := dirtyRuns_pos _ hD; cases d <;> simp [h1, h2, hD] at hδ ⊢ <;> omega
    · rw [dirtyRuns_noDirty false _ hD] at hδ ⊢; cases d <;> simp [h1, h2, hD] at hδ ⊢ <;> omega
  · have := dirtyRuns_pos _ h2
    by_cases hC : FlagOp.check ∈ flags ρ as <;> cases d <;> simp [h1, h2, hC] at hδ ⊢ <;> omega

/-- **When batching wins.** Batching saves a pass exactly when the write runs outnumber the one run it keeps plus the
absorption it may lose.

$$\forall \rho \text{ sound with } (\forall a:\ \operatorname{isReadA}(a) \Rightarrow \rho(a) \ne \mathrm{dirty}),\ \forall d,\ \forall as,\ F = \operatorname{flags}_\rho(as):\ \operatorname{total}_\rho(d, \operatorname{batch}(as)) < \operatorname{total}_\rho(d, as) \iff [\mathrm{dirty} \in F] + [d \land \operatorname{first}(F) = \mathrm{dirty} \land \mathrm{check} \in F] < \operatorname{runs}(\bot, F)$$

Batching wins only by merging at least two write runs. -/
theorem total_batch_win_iff (ρ : Access → Role) (hs : Sound ρ) (hr : ∀ a, a.isRead = true → ρ a ≠ .dirty)
    (d : Bool) (as : List Access) :
    total ρ d (batch as) < total ρ d as ↔
      (if FlagOp.dirty ∈ flags ρ as then 1 else 0) +
        (if d = true ∧ firstFlag (flags ρ as) = some .dirty ∧ FlagOp.check ∈ flags ρ as then 1 else 0) <
        dirtyRuns false (flags ρ as) := by
  have hδ := total_batch_delta ρ hs hr d as
  omega

/-- No read dirties style.

$$\forall a:\ \operatorname{isReadA}(a) \Rightarrow \rho_S(a) \ne \mathrm{dirty}$$ -/
theorem styleRole_reads (a : Access) (h : a.isRead = true) : styleRole a ≠ .dirty := by
  cases a <;> simp_all [Access.isRead, styleRole]

/-- No read dirties layout.

$$\forall a:\ \operatorname{isReadA}(a) \Rightarrow \rho_L(a) \ne \mathrm{dirty}$$ -/
theorem layoutRole_reads (a : Access) (h : a.isRead = true) : layoutRole a ≠ .dirty := by
  cases a <;> simp_all [Access.isRead, layoutRole]

/-- Under the style role, a check flag means a read and a dirty flag means a write.

$$\forall as:\ (\mathrm{check} \in \operatorname{flags}_{\rho_S}(as) \iff \exists a \in as:\ \operatorname{isReadA}(a)) \land (\mathrm{dirty} \in \operatorname{flags}_{\rho_S}(as) \iff \exists a \in as:\ \lnot\operatorname{isReadA}(a))$$ -/
theorem flags_style_mem (as : List Access) :
    (FlagOp.check ∈ flags styleRole as ↔ as.any Access.isRead = true) ∧
      (FlagOp.dirty ∈ flags styleRole as ↔ as.all Access.isRead = false) := by
  induction as with
  | nil => simp [flags]
  | cons a as ih =>
    obtain ⟨ih1, ih2⟩ := ih
    simp only [flags, List.map_cons, List.mem_cons, List.any_cons, List.all_cons] at ih1 ih2 ⊢
    rw [ih1, ih2]
    cases a <;> simp [styleRole, Role.toFlag, Access.isRead]

/-- **The batching delta for style (ledger n=1 row 2), in access terms.** For a frame with a write: batched total plus
write runs equals the faithful total plus one, plus one more when the frame starts dirty with a write and has a read.

$$\forall d \in \mathbb{B},\ \forall as:\ (\exists a \in as:\ \lnot\operatorname{isReadA}(a)) \Rightarrow \operatorname{total}_{\rho_S}(d, \operatorname{batch}(as)) + \operatorname{wruns}(\bot, as) = \operatorname{total}_{\rho_S}(d, as) + 1 + [d \land \lnot\operatorname{headRead}(as) \land \exists a \in as:\ \operatorname{isReadA}(a)]$$

Batching wins only when it merges two or more write runs; with one run and a leading write on a dirty frame it is
worse by one. -/
theorem total_style_batch_delta (d : Bool) (as : List Access) (hw : as.all Access.isRead = false) :
    total styleRole d (batch as) + writeRuns false as =
      total styleRole d as + 1 +
        (if d = true ∧ headRead as = false ∧ as.any Access.isRead = true then 1 else 0) := by
  have h := total_batch_delta styleRole styleRole_sound styleRole_reads d as
  obtain ⟨hc, hd⟩ := flags_style_mem as
  have hD : FlagOp.dirty ∈ flags styleRole as := hd.mpr hw
  rw [writeRuns_eq]
  simp only [hD, ite_true, firstFlag_style, hc] at h
  exact h

/-- **Batching is worse on a dirty write-then-read frame (refutes the ledger n=22 claim "never more").** Starting
style-dirty, `[WS, RL]` costs one style pass (the write joins the pending flush, the read pays once); batched as
`[RL, WS]` it costs two (the read pays the start flag, the write is paid at frame end).

$$\operatorname{total}_{\rho_S}(\top, [\mathrm{WS}, \mathrm{RL}]) = 1 \ \land\ \operatorname{total}_{\rho_S}(\top, \operatorname{batch}[\mathrm{WS}, \mathrm{RL}]) = 2$$

Moving a read ahead of a write that a dirty frame would have absorbed adds a pass. -/
theorem batch_worse_example :
    total styleRole true [.writeStyle, .readLayout] = 1 ∧ total styleRole true (batch [.writeStyle, .readLayout]) = 2 := by
  decide

/-- **Forced-only counts hide it.** The same frame has one forced pass faithful and one batched, so
`batched_le_faithful` holds while the total grows.

$$\operatorname{forced}_{\rho_S}(\top, [\mathrm{WS}, \mathrm{RL}]) = 1 = \operatorname{forced}_{\rho_S}(\top, \operatorname{batch}[\mathrm{WS}, \mathrm{RL}])$$

The forced-pass order is not the trace order. -/
theorem batch_worse_forced_equal :
    forced styleRole true [.writeStyle, .readLayout] = 1 ∧ forced styleRole true (batch [.writeStyle, .readLayout]) = 1 := by
  decide

/-- The ledger n=22 shape "writes then reads" is equal only from a clean start; from a dirty start it is worse.

$$\operatorname{total}_{\rho_S}(\bot, [\mathrm{WS}, \mathrm{WS}, \mathrm{RL}, \mathrm{RL}]) = 1 = \operatorname{total}_{\rho_S}(\bot, \operatorname{batch}(\cdot)) \ \land\ \operatorname{total}_{\rho_S}(\top, [\mathrm{WS}, \mathrm{WS}, \mathrm{RL}, \mathrm{RL}]) = 1 < 2 = \operatorname{total}_{\rho_S}(\top, \operatorname{batch}(\cdot))$$

The forced layout is only moved from a clean start. -/
theorem batch_writes_then_reads :
    total styleRole false [.writeStyle, .writeStyle, .readLayout, .readLayout] = 1 ∧
      total styleRole false (batch [.writeStyle, .writeStyle, .readLayout, .readLayout]) = 1 ∧
      total styleRole true [.writeStyle, .writeStyle, .readLayout, .readLayout] = 1 ∧
      total styleRole true (batch [.writeStyle, .writeStyle, .readLayout, .readLayout]) = 2 := by
  decide

#guard total styleRole true pilotFrame == 4
#guard total styleRole false pilotFrame == 3
#guard total styleRole true (batch pilotFrame) == 2
#guard total styleRole false (batch pilotFrame) == 1
#guard total layoutRole true pilotFrame == 1 && total layoutRole true (batch pilotFrame) == 1

/-! ### The pilot: the engine moves only returned writes (ledger n=1 row 3) -/

/-- The TS engine's batch: a callback's *returned* accesses are split, its reads stay first and its writes run after
the inline callbacks; inline accesses keep their order.

$$\operatorname{retBatch}(r, i) = \operatorname{filter}_{\mathrm{R}}(r) \mathbin{+\!\!+} i \mathbin{+\!\!+} \operatorname{filter}_{\mathrm{W}}(r)$$

What the scroll engine can reorder: only the writes a callback hands back. -/
def retBatch (ret inline : List Access) : List Access :=
  ret.filter Access.isRead ++ inline ++ ret.filter (fun a => !a.isRead)

/-- The nav callback with the elements probe (`elementsFromPoint`, no `pointer-events` toggle).

$$\mathit{nav}_e = [\mathrm{RS}, \mathrm{RS}, \mathrm{RL}, \mathrm{RL}, \mathrm{RL}, \mathrm{RL}, \mathrm{RL}]$$

The nav's accesses under elements-skip. -/
def navElementsAccesses : List Access :=
  [.readStyle, .readStyle, .readLayout, .readLayout, .readLayout, .readLayout, .readLayout]

/-- **Pilot no-win (ledger n=1 row 3).** Moving the hero exit's returned writes after the nav leaves the style total
unchanged, with either nav probe: $3 + [d]$ with the faithful probe, $1 + [d]$ with the elements probe. The moved
pass comes back as the frame-end pass.

$$\forall d \in \mathbb{B}:\ \operatorname{total}_{\rho_S}(d, \mathit{hero} \mathbin{+\!\!+} \mathit{nav}) = \operatorname{total}_{\rho_S}(d, \operatorname{retBatch}(\mathit{hero}, \mathit{nav})) = 3 + [d] \ \land\ \operatorname{total}_{\rho_S}(d, \mathit{hero} \mathbin{+\!\!+} \mathit{nav}_e) = \operatorname{total}_{\rho_S}(d, \operatorname{retBatch}(\mathit{hero}, \mathit{nav}_e)) = 1 + [d]$$

The batched engine gives the pilot nothing on style. -/
theorem pilot_retBatch_noWin (d : Bool) :
    total styleRole d (heroExitAccesses ++ navAccesses) = total styleRole d (retBatch heroExitAccesses navAccesses) ∧
      total styleRole d (heroExitAccesses ++ navAccesses) = 3 + d.toNat ∧
      total styleRole d (heroExitAccesses ++ navElementsAccesses) =
        total styleRole d (retBatch heroExitAccesses navElementsAccesses) ∧
      total styleRole d (heroExitAccesses ++ navElementsAccesses) = 1 + d.toNat := by
  cases d <;> decide

/-- The pilot's layout total is the same faithful and engine-batched: only a dirty start is paid.

$$\forall d \in \mathbb{B}:\ \operatorname{total}_{\rho_L}(d, \mathit{hero} \mathbin{+\!\!+} \mathit{nav}) = \operatorname{total}_{\rho_L}(d, \operatorname{retBatch}(\mathit{hero}, \mathit{nav})) = [d]$$

No pilot access writes layout. -/
theorem pilot_retBatch_layout (d : Bool) :
    total layoutRole d (heroExitAccesses ++ navAccesses) = total layoutRole d (retBatch heroExitAccesses navAccesses) ∧
      total layoutRole d (heroExitAccesses ++ navAccesses) = d.toNat := by
  cases d <;> decide

/-! ### Reader removal (ledger n=2 row 1) -/

/-- **Removing one read**, in access terms: for a read that checks the flag, dropping it never adds a pass and saves
exactly one when the flag is dirty at the read and the next flag access after it is a write.

$$\forall \rho,\ \forall d,\ \forall p, q,\ \forall a:\ \rho(a) = \mathrm{check} \Rightarrow \operatorname{total}_\rho(d, p \mathbin{+\!\!+} a :: q) = \operatorname{total}_\rho(d, p \mathbin{+\!\!+} q) + [\operatorname{fE}(d, \operatorname{flags}_\rho(p)) \land \operatorname{first}(\operatorname{flags}_\rho(q)) = \mathrm{dirty}]$$

An observer that replaces a read saves a pass only when that read split a write batch in two. -/
theorem total_remove_read (ρ : Access → Role) (d : Bool) (p q : List Access) (a : Access) (ha : ρ a = .check) :
    total ρ d (p ++ a :: q) =
      total ρ d (p ++ q) +
        (if flagEnd d (flags ρ p) = true ∧ firstFlag (flags ρ q) = some .dirty then 1 else 0) := by
  have h := flagTotal_remove_check d (flags ρ p) (flags ρ q)
  have hf : flags ρ (p ++ a :: q) = flags ρ p ++ FlagOp.check :: flags ρ q := by
    simp [flags, ha, Role.toFlag]
  rw [total, total, hf, flags_append, h]

/-- **Reader removal for style.** Dropping a read saves a style pass exactly when the flag is dirty at the read and
the next access is a write.

$$\forall d,\ \forall p, q,\ \forall a:\ \operatorname{isReadA}(a) \Rightarrow \operatorname{total}_{\rho_S}(d, p \mathbin{+\!\!+} a :: q) = \operatorname{total}_{\rho_S}(d, p \mathbin{+\!\!+} q) + [\operatorname{fE}(d, \operatorname{flags}_{\rho_S}(p)) \land \lnot\operatorname{headRead}(q)]$$

In the nav callback every read is followed by a read or by the frame end except the two probe reads. -/
theorem total_style_remove_read (d : Bool) (p q : List Access) (a : Access) (ha : a.isRead = true) :
    total styleRole d (p ++ a :: q) =
      total styleRole d (p ++ q) + (if flagEnd d (flags styleRole p) = true ∧ headRead q = false then 1 else 0) := by
  have hc : styleRole a = .check := by cases a <;> simp_all [Access.isRead, styleRole]
  rw [total_remove_read styleRole d p q a hc]
  simp only [firstFlag_style]

#guard total styleRole false [.writeStyle, .readLayout, .writeStyle] == 2
#guard total styleRole false [.writeStyle, .writeStyle] == 1
#guard total styleRole false [.readLayout, .readLayout, .writeStyle] == 1
#guard total styleRole false [.readLayout, .writeStyle] == 1

end Total

end Fw.Parts.EngineScroll

