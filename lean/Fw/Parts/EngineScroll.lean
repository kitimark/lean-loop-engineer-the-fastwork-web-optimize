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
-- batched: one style pass and one layout pass at most
#guard forced styleRole true (pilotFrame.filter Access.isRead ++ pilotFrame.filter (fun a => !a.isRead)) == 1
#guard forced styleRole false (pilotFrame.filter Access.isRead ++ pilotFrame.filter (fun a => !a.isRead)) == 0

end Fw.Parts.EngineScroll
