import Fw.Gate.Scope

/-!
# Reduced sweeps: dropping stutter stops keeps every verdict cell (sweeps-lean)

A sweep stop whose key equals the previous stop's key adds nothing to the collapsed key history, so under hypothesis H
(`Fw.Gate.Scope`: a stop's verdict is a function of the collapsed key history up to it) it adds no new verdict.

* `mem_stopHist_iff`, `stopVerdicts_mem_of_collapse_eq`, `scopedVerdict_reduce`: any sweep with the same collapsed key
  history gives the same set of stop verdicts, hence the same scoped verdict (`rollup_congr`).
* `dropStutter` keeps the first stop of every run of equal keys; `map_dropStutter` says its keys are exactly the
  collapsed key history, and `dropStutter_history_comp` carries this to every key that is a function of the
  dropped-on key (`collapse_map_collapse`).
* The combined key `sweepKey` is the condition key $\kappa_T$ (the 30 catalogue conditions and the 4 neutral queries,
  the truth rows of `summary.mjs`) together with every pilot part key $\kappa_u$. `reduceSweep` drops its stutters;
  `reduceSweep_part_history` and `reduceSweep_cond_history` keep every history, so `reduced_scopedVerdict`,
  `reduced_scope_sound` and `reduced_cond_scopedVerdict` keep every verdict cell.
* `reducedDeskWidths`: the desktop sweep's 57 widths reduce to 45 (`reducedDeskWidths_eq`).
* Caveat (`reduced_desk_tally_ne`): the cells' verdicts are equal (`sweepCell_verdict_reduce`), the tally counts are
  not. The sweep column's `FAIL k/n` counts stops, so the reduced sweep shows smaller `k` and `n`.

The research note is `research/notes/2026/10-18-sweeps-speed.md` part B.
-/

namespace Fw.Gate
open Fw.Site.Breakpoints

/-! ## Collapse: prefixes and projections -/

section generic
variable {α κ μ : Type} [DecidableEq κ] [DecidableEq μ]

/-- The defining equation of `collapse` on two leading entries.

$$\forall a, b \in \kappa,\ \forall t \in \kappa^*,\quad \operatorname{collapse}(a :: b :: t) = \begin{cases} \operatorname{collapse}(b :: t) & a = b \\ a :: \operatorname{collapse}(b :: t) & a \ne b \end{cases}$$

Two equal neighbours merge into one. -/
theorem collapse_cons_cons (a b : κ) (t : List κ) :
    collapse (a :: b :: t) = if a = b then collapse (b :: t) else a :: collapse (b :: t) := rfl

/-- Collapsing keeps the first entry.

$$\forall l \in \kappa^*,\quad \operatorname{head?}(\operatorname{collapse}(l)) = \operatorname{head?}(l)$$

The history starts with the key of the first stop (and is empty only for no stops). -/
theorem collapse_head? : ∀ l : List κ, (collapse l).head? = l.head?
  | [] => rfl
  | [_] => rfl
  | a :: b :: t => by
    rw [collapse_cons_cons]
    split
    · next h => subst h; simpa using collapse_head? (a :: t)
    · simp

/-- Collapsing a cons only looks at the collapsed tail.

$$\forall a \in \kappa,\ \forall l \in \kappa^*,\quad \operatorname{collapse}(a :: l) = \begin{cases} \operatorname{collapse}(l) & \operatorname{head?}(\operatorname{collapse}(l)) = \mathrm{some}(a) \\ a :: \operatorname{collapse}(l) & \text{otherwise} \end{cases}$$

A new first entry is kept exactly when it differs from the history's first entry. -/
theorem collapse_cons (a : κ) (l : List κ) :
    collapse (a :: l) = if (collapse l).head? = some a then collapse l else a :: collapse l := by
  cases l with
  | nil => rfl
  | cons b t =>
    rw [collapse_cons_cons, collapse_head?]
    by_cases h : a = b
    · subst h; simp
    · have h' : ¬ (some b = some a) := fun e => h (Option.some.inj e).symm
      simp [h, h']

/-- Collapsing before a projection changes nothing.

$$\forall f : \kappa \to \mu,\ \forall l \in \kappa^*,\quad \operatorname{collapse}([f(x) \mid x \in \operatorname{collapse}(l)]) = \operatorname{collapse}([f(x) \mid x \in l])$$

A coarser key's history is determined by the finer key's history. -/
theorem collapse_map_collapse (f : κ → μ) : ∀ l : List κ, collapse ((collapse l).map f) = collapse (l.map f)
  | [] => rfl
  | a :: l => by
    have ih := collapse_map_collapse f l
    rw [collapse_cons a l]
    split
    · next h =>
      rw [ih, List.map_cons, collapse_cons (f a) (l.map f), collapse_head?]
      have hl : l.head? = some a := by rw [← collapse_head?]; exact h
      have : (l.map f).head? = some (f a) := by rw [List.head?_map, hl]; rfl
      rw [this]; simp
    · rw [List.map_cons, collapse_cons, ih, List.map_cons, collapse_cons (f a) (l.map f)]

/-- The collapsed histories the stops of a sweep see: stop $i$ sees the collapse of stops $0..i$.

$$\forall l \in \kappa^*,\quad \operatorname{stopHist}(l) = [\operatorname{collapse}(l_{0..i}) \mid 0 \le i < |l|]$$

One history per stop, in stop order. -/
def stopHist (l : List κ) : List (List κ) := (List.range l.length).map fun i => collapse (l.take (i + 1))

/-- The nonempty prefixes of a list, shortest first.

$$\forall c \in \kappa^*,\quad \operatorname{prefs}(c) = [c_{0..j} \mid 0 \le j < |c|]$$

The histories a stutter-free sweep's stops see. -/
def prefs (c : List κ) : List (List κ) := (List.range c.length).map fun j => c.take (j + 1)

#guard stopHist [1, 1, 2] = [[1], [1], [1, 2]]
#guard prefs [1, 2] = [[1], [1, 2]]
#guard prefs ([] : List Nat) = []

omit [DecidableEq κ] in
/-- The prefixes of a cons are the singleton and the extended prefixes of the tail.

$$\forall a, c, x,\quad x \in \operatorname{prefs}(a :: c) \iff x = [a] \lor \exists y \in \operatorname{prefs}(c),\ x = a :: y$$

Unfolds `prefs` one entry. -/
theorem mem_prefs_cons (a : κ) (c : List κ) (x : List κ) :
    x ∈ prefs (a :: c) ↔ x = [a] ∨ ∃ y ∈ prefs c, x = a :: y := by
  simp only [prefs, List.mem_map, List.mem_range, List.length_cons]
  constructor
  · rintro ⟨j, hj, rfl⟩
    cases j with
    | zero => left; simp
    | succ k => right; exact ⟨c.take (k + 1), ⟨k, by omega, rfl⟩, by simp⟩
  · rintro (rfl | ⟨y, ⟨k, hk, rfl⟩, rfl⟩)
    · exact ⟨0, by omega, by simp⟩
    · exact ⟨k + 1, by omega, by simp⟩

/-- The stop histories of a two-or-more stop list, from those of its tail.

$$\forall a, b, t, x,\quad x \in \operatorname{stopHist}(a :: b :: t) \iff x = [a] \lor \exists y \in \operatorname{stopHist}(b :: t),\ x = \begin{cases} y & a = b \\ a :: y & a \ne b \end{cases}$$

Unfolds `stopHist` one stop. -/
theorem mem_stopHist_cons (a b : κ) (t : List κ) (x : List κ) :
    x ∈ stopHist (a :: b :: t) ↔
      x = [a] ∨ ∃ y ∈ stopHist (b :: t), x = (if a = b then y else a :: y) := by
  simp only [stopHist, List.mem_map, List.mem_range, List.length_cons]
  constructor
  · rintro ⟨i, hi, rfl⟩
    cases i with
    | zero => left; rfl
    | succ k =>
      right
      refine ⟨collapse ((b :: t).take (k + 1)), ⟨k, by omega, rfl⟩, ?_⟩
      exact collapse_cons_cons a b (t.take k)
  · rintro (rfl | ⟨y, ⟨k, hk, rfl⟩, rfl⟩)
    · exact ⟨0, by omega, rfl⟩
    · refine ⟨k + 1, by omega, ?_⟩
      exact collapse_cons_cons a b (t.take k)

/-- A nonempty list collapses to a list with the same head.

$$\forall b, t,\ \exists c,\quad \operatorname{collapse}(b :: t) = b :: c$$

The first stop's key always opens the history. -/
theorem collapse_cons_eq (b : κ) (t : List κ) : ∃ c, collapse (b :: t) = b :: c := by
  have h := collapse_head? (b :: t)
  cases hc : collapse (b :: t) with
  | nil => simp [hc] at h
  | cons x c => simp [hc] at h; exact ⟨c, by rw [h]⟩

/-- **Stops see exactly the prefixes of the collapsed history.**

$$\forall l \in \kappa^*,\ \forall x \in \kappa^*,\quad x \in [\operatorname{collapse}(l_{0..i}) \mid 0 \le i < |l|] \iff x \in [\operatorname{collapse}(l)_{0..j} \mid 0 \le j < |\operatorname{collapse}(l)|]$$

The set of histories a sweep's stops see depends only on its collapsed history. -/
theorem mem_stopHist_iff : ∀ (l : List κ) (x : List κ), x ∈ stopHist l ↔ x ∈ prefs (collapse l)
  | [], x => by simp [stopHist, prefs, collapse]
  | [a], x => by simp [stopHist, prefs, collapse]
  | a :: b :: t, x => by
    rw [mem_stopHist_cons, collapse_cons_cons]
    have ih := mem_stopHist_iff (b :: t)
    obtain ⟨c, hc⟩ := collapse_cons_eq b t
    split
    · next h =>
      subst h
      simp only [exists_eq_right', ih]
      constructor
      · rintro (rfl | h)
        · rw [hc, mem_prefs_cons]; left; rfl
        · exact h
      · exact Or.inr
    · rw [mem_prefs_cons]
      simp only [ih]

/-- A sweep's stop verdicts, as a list, have one entry per stop.

$$\forall \kappa, \mathrm{hv}, s,\quad |\operatorname{stops}_{\kappa,\mathrm{hv}}(s)| = |s|$$

A sweep cell counts stops. -/
theorem stopVerdicts_length (key : Env → κ) (hv : List κ → Verdict) (s : List Env) :
    (stopVerdicts key hv s).length = s.length := by
  simp [stopVerdicts]

/-- **Collapse-equal sweeps give the same set of stop verdicts.**

$$\forall \kappa, \mathrm{hv}, s, s',\quad \operatorname{collapse}(\kappa(s)) = \operatorname{collapse}(\kappa(s')) \implies \forall v,\ \bigl(v \in \operatorname{stops}_{\kappa,\mathrm{hv}}(s) \iff v \in \operatorname{stops}_{\kappa,\mathrm{hv}}(s')\bigr)$$

Under H only the collapsed key history of a sweep matters, not how many stops repeat a key. -/
theorem stopVerdicts_mem_of_collapse_eq (key : Env → κ) (hv : List κ → Verdict) (s s' : List Env)
    (h : collapse (s.map key) = collapse (s'.map key)) (v : Verdict) :
    v ∈ stopVerdicts key hv s ↔ v ∈ stopVerdicts key hv s' := by
  have e : ∀ s : List Env, v ∈ stopVerdicts key hv s ↔ ∃ x ∈ prefs (collapse (s.map key)), v = hv x := by
    intro s
    have := mem_stopHist_iff (s.map key)
    simp only [stopHist, List.mem_map, List.mem_range, List.length_map] at this
    simp only [stopVerdicts, List.mem_map, List.mem_range, List.map_take]
    constructor
    · rintro ⟨i, hi, rfl⟩; exact ⟨_, (this _).mp ⟨i, hi, rfl⟩, rfl⟩
    · rintro ⟨x, hx, rfl⟩; obtain ⟨i, hi, rfl⟩ := (this x).mpr hx; exact ⟨i, hi, rfl⟩
  rw [e, e, h]

/-- **Reduced sweeps keep the part's verdict.** Replacing every sweep $w$ of the run by $r(w)$ with the same collapsed
key history keeps the scoped verdict.

$$\forall \rho, \kappa, \mathrm{hv}, S, K, r,\quad \bigl(\forall w \in K,\ \operatorname{collapse}([\kappa(e) \mid e \in \mathrm{stops}(r(w))]) = \operatorname{collapse}([\kappa(e) \mid e \in \mathrm{stops}(w)])\bigr) \implies V_{\rho,\kappa,\mathrm{hv}}(S, [r(w) \mid w \in K]) = V_{\rho,\kappa,\mathrm{hv}}(S, K)$$

A sweep can be shortened to any sweep with the same history. -/
theorem scopedVerdict_reduce (reach : Env → Option Reason) (key : Env → κ) (hv : List κ → Verdict)
    (S : List Probe) (K : List Sweep) (r : Sweep → Sweep)
    (hr : ∀ w ∈ K, collapse ((r w).stops.map key) = collapse (w.stops.map key)) :
    scopedVerdict reach key hv S (K.map r) = scopedVerdict reach key hv S K := by
  unfold scopedVerdict
  apply rollup_congr
  intro v
  simp only [List.mem_append, List.flatMap_map, List.mem_flatMap]
  refine or_congr Iff.rfl ⟨?_, ?_⟩
  · rintro ⟨w, hw, hv'⟩; exact ⟨w, hw, (stopVerdicts_mem_of_collapse_eq key hv _ _ (hr w hw) v).mp hv'⟩
  · rintro ⟨w, hw, hv'⟩; exact ⟨w, hw, (stopVerdicts_mem_of_collapse_eq key hv _ _ (hr w hw) v).mpr hv'⟩

/-- **A sweep cell keeps its verdict.** The sweep column's cell of a row is the tally of the row's stop verdicts
(`summary.mjs`, `gate.tally` with `block` false); its verdict depends only on the collapsed history.

$$\forall \kappa, \mathrm{hv}, s, s',\quad \operatorname{collapse}(\kappa(s)) = \operatorname{collapse}(\kappa(s')) \implies \operatorname{tally}(\operatorname{stops}_{\kappa,\mathrm{hv}}(s)).\mathrm{verdict} = \operatorname{tally}(\operatorname{stops}_{\kappa,\mathrm{hv}}(s')).\mathrm{verdict}$$

The pass / FAIL / NC word of a sweep cell survives the reduction. -/
theorem sweepCell_verdict_reduce (key : Env → κ) (hv : List κ → Verdict) (s s' : List Env)
    (h : collapse (s.map key) = collapse (s'.map key)) :
    (tally (stopVerdicts key hv s)).verdict = (tally (stopVerdicts key hv s')).verdict :=
  rollup_congr _ _ (stopVerdicts_mem_of_collapse_eq key hv s s' h)

/-! ## Dropping stutter stops -/

/-- Keep an entry only when its key differs from the key `prev` of the last kept entry.

$$\forall k, p,\quad \operatorname{drop}_k(p, [\,]) = [\,],\quad \operatorname{drop}_k(p, e :: t) = \begin{cases} \operatorname{drop}_k(p, t) & k(e) = p \\ e :: \operatorname{drop}_k(k(e), t) & k(e) \ne p \end{cases}$$

The tail of `dropStutter`. -/
def dropStutterFrom (k : α → κ) (prev : κ) : List α → List α
  | [] => []
  | e :: rest => if k e = prev then dropStutterFrom k prev rest else e :: dropStutterFrom k (k e) rest

/-- **Drop every stutter stop**: keep the first entry and every entry whose key differs from the previous entry's key.

$$\forall k,\quad \operatorname{dropStutter}_k([\,]) = [\,],\quad \forall e, t,\ \operatorname{dropStutter}_k(e :: t) = e :: \operatorname{drop}_k(k(e), t)$$

A resize that changes no key is left out; of every run of equal keys the first stop stays. -/
def dropStutter (k : α → κ) : List α → List α
  | [] => []
  | e :: rest => e :: dropStutterFrom k (k e) rest

#guard dropStutter (· / 10) [11, 12, 25, 21, 13, 14] = [11, 25, 13]
#guard dropStutter (· / 10) ([] : List Nat) = []
#guard dropStutter (· / 10) [5] = [5]

/-- The kept entries' keys after `prev` are the collapsed history.

$$\forall k, p, l,\quad p :: k(\operatorname{drop}_k(p, l)) = \operatorname{collapse}(p :: k(l))$$

The induction step of `map_dropStutter`. -/
theorem map_dropStutterFrom (k : α → κ) : ∀ (prev : κ) (l : List α),
    prev :: (dropStutterFrom k prev l).map k = collapse (prev :: l.map k)
  | _, [] => rfl
  | prev, e :: rest => by
    simp only [dropStutterFrom, List.map_cons]
    rw [collapse_cons_cons]
    by_cases h : k e = prev
    · simp only [h, ↓reduceIte]
      exact map_dropStutterFrom k prev rest
    · have h' : ¬ prev = k e := fun x => h x.symm
      simp only [h, h', ↓reduceIte, List.map_cons]
      rw [map_dropStutterFrom k (k e) rest]

/-- **The kept stops' keys are the collapsed key history.**

$$\forall k, l,\quad k(\operatorname{dropStutter}_k(l)) = \operatorname{collapse}(k(l))$$

The reduced sweep is stutter-free and has the full sweep's history. -/
theorem map_dropStutter (k : α → κ) : ∀ l : List α, (dropStutter k l).map k = collapse (l.map k)
  | [] => rfl
  | e :: rest => by
    simp only [dropStutter, List.map_cons]
    exact map_dropStutterFrom k (k e) rest

/-- **Every coarser key keeps its history.** For any key $f \circ k$ that factors through $k$, dropping $k$-stutters
keeps the collapsed $f \circ k$ history.

$$\forall k, f, l,\quad \operatorname{collapse}((f \circ k)(\operatorname{dropStutter}_k(l))) = \operatorname{collapse}((f \circ k)(l))$$

Dropping stutters of the combined key keeps the history of each of its parts. -/
theorem dropStutter_history_comp (k : α → κ) (f : κ → μ) (l : List α) :
    collapse ((dropStutter k l).map (fun e => f (k e))) = collapse (l.map fun e => f (k e)) := by
  have h1 : (dropStutter k l).map (fun e => f (k e)) = ((dropStutter k l).map k).map f := by simp
  have h2 : l.map (fun e => f (k e)) = (l.map k).map f := by simp
  rw [h1, h2, map_dropStutter, collapse_map_collapse]

/-- `dropStutter` commutes with relabelling the entries.

$$\forall k, g, l,\quad \operatorname{dropStutter}_k(g(l)) = g(\operatorname{dropStutter}_{k \circ g}(l))$$

The reduced sweep can be computed on widths and then turned into stops. -/
theorem dropStutter_map {β : Type} (k : α → κ) (g : β → α) (l : List β) :
    dropStutter k (l.map g) = (dropStutter (fun b => k (g b)) l).map g := by
  have aux : ∀ (p : κ) (l : List β),
      dropStutterFrom k p (l.map g) = (dropStutterFrom (fun b => k (g b)) p l).map g := by
    intro p l
    induction l generalizing p with
    | nil => rfl
    | cons b t ih =>
      simp only [List.map_cons, dropStutterFrom]
      split <;> simp [ih]
  cases l with
  | nil => rfl
  | cons b t => simp [dropStutter, aux]

/-- `dropStutter` keeps a sublist of the entries.

$$\forall k, l,\quad \operatorname{dropStutter}_k(l) \sqsubseteq l$$

(as a sublist: entries kept in order). The reduced sweep only removes stops. -/
theorem dropStutter_sublist (k : α → κ) (l : List α) : (dropStutter k l).Sublist l := by
  have aux : ∀ (p : κ) (l : List α), (dropStutterFrom k p l).Sublist l := by
    intro p l
    induction l generalizing p with
    | nil => exact List.Sublist.slnil
    | cons e t ih =>
      simp only [dropStutterFrom]
      split
      · exact (ih p).cons e
      · exact (ih (k e)).cons_cons e
  cases l with
  | nil => exact List.Sublist.slnil
  | cons e t => exact (aux (k e) t).cons_cons e

end generic

/-! ## The gate's combined key and the reduced sweeps -/

/-- The condition key $\kappa_T$: the value of each of the 30 catalogue conditions, then of each of the 4 neutral
queries, at an environment (what the matchMedia truth rows of `summary.mjs` read at every stop).

$$\forall e,\quad \kappa_T(e) = [\,e \models c \mid c \in \mathrm{catalogue}\,] \mathbin{+\!\!+} [\,e \models n \mid n \in \mathrm{neutral}\,]$$

The truth rows' key. -/
def condKey (e : Env) : List Bool := catalogue.map (·.query.eval e) ++ neutral.map (·.query.eval e)

/-- The combined sweep key: the condition key and every pilot part's key.

$$\forall e,\quad \kappa(e) = \bigl(\kappa_T(e),\ [\,\kappa_u(e) \mid u \in \mathrm{pilot}\,]\bigr)$$

Two stops with equal combined keys look the same to every row of the gate under H. -/
def sweepKey (e : Env) : List Bool × List (List Bool) := (condKey e, pilotParts.map (·.key e))

/-- A sweep with its stutter stops (under the combined key) dropped.

$$\forall w,\quad r(w) = (\mathrm{id}(w), \mathrm{blurb}(w), \operatorname{dropStutter}_\kappa(\mathrm{stops}(w)))$$

The reduced sweep keeps the id, so reports and merges see the same sweep. -/
def reduceSweep (w : Sweep) : Sweep := { w with stops := dropStutter sweepKey w.stops }

/-- Every pilot part key is a projection of the combined key.

$$\forall u \in \mathrm{pilot},\ \exists f,\ \forall e,\quad \kappa_u(e) = f(\kappa(e))$$

A part key factors through the combined key. -/
theorem partKey_factors (u : PartUse) (hu : u ∈ pilotParts) :
    ∃ f : List Bool × List (List Bool) → List Bool, ∀ e, u.key e = f (sweepKey e) := by
  obtain ⟨i, hi, rfl⟩ := List.getElem_of_mem hu
  refine ⟨fun x => (x.2[i]?).getD [], fun e => ?_⟩
  simp [sweepKey, hi]

/-- **The reduced sweep keeps every part key's history.**

$$\forall u \in \mathrm{pilot},\ \forall w,\quad \operatorname{collapse}(\kappa_u(r(w))) = \operatorname{collapse}(\kappa_u(w))$$

What `scopedVerdict_reduce` needs, for every pilot part. -/
theorem reduceSweep_part_history (u : PartUse) (hu : u ∈ pilotParts) (w : Sweep) :
    collapse ((reduceSweep w).stops.map u.key) = collapse (w.stops.map u.key) := by
  obtain ⟨f, hf⟩ := partKey_factors u hu
  have e : u.key = fun e => f (sweepKey e) := funext hf
  rw [e]
  exact dropStutter_history_comp sweepKey f w.stops

/-- **The reduced sweep keeps the condition key's history** (the truth rows' hypothesis $H_T$ sees the same input).

$$\forall w,\quad \operatorname{collapse}(\kappa_T(r(w))) = \operatorname{collapse}(\kappa_T(w))$$

The matchMedia rows see every condition change, in order, as before. -/
theorem reduceSweep_cond_history (w : Sweep) :
    collapse ((reduceSweep w).stops.map condKey) = collapse (w.stops.map condKey) :=
  dropStutter_history_comp sweepKey Prod.fst w.stops

/-- **Reduced sweeps keep each part's verdict.**

$$\forall u \in \mathrm{pilot},\ \forall \rho, \mathrm{hv}, S, K,\quad V_{\rho,\kappa_u,\mathrm{hv}}(S, \operatorname{map}\ r\ K) = V_{\rho,\kappa_u,\mathrm{hv}}(S, K)$$

Any run may replace its sweeps by the reduced ones. -/
theorem reduced_scopedVerdict (u : PartUse) (hu : u ∈ pilotParts) (reach : Env → Option Reason)
    (hv : List (List Bool) → Verdict) (S : List Probe) (K : List Sweep) :
    scopedVerdict reach u.key hv S (K.map reduceSweep) = scopedVerdict reach u.key hv S K :=
  scopedVerdict_reduce reach u.key hv S K reduceSweep fun w _ => reduceSweep_part_history u hu w

/-- **Reduced sweeps keep the truth rows' verdict** under $H_T$ (a truth row's stop verdict is a function
$\mathrm{hv}_T$ of the collapsed condition-key history).

$$\forall \rho, \mathrm{hv}_T, S, K,\quad V_{\rho,\kappa_T,\mathrm{hv}_T}(S, \operatorname{map}\ r\ K) = V_{\rho,\kappa_T,\mathrm{hv}_T}(S, K)$$

The matchMedia rows keep their verdict too. -/
theorem reduced_cond_scopedVerdict (reach : Env → Option Reason) (hv : List (List Bool) → Verdict)
    (S : List Probe) (K : List Sweep) :
    scopedVerdict reach condKey hv S (K.map reduceSweep) = scopedVerdict reach condKey hv S K :=
  scopedVerdict_reduce reach condKey hv S K reduceSweep fun w _ => reduceSweep_cond_history w

/-- **Scoped and reduced runs keep the full verdict.** For a pilot part $u$, a port $\pi$, an $\mathrm{hv}$ that never
says unreachable, and a run whose loads $S_r$ lie between the scope and the matrix and whose sweeps $K_r$ lie between
the sweep scope and all sweeps, running the reduced sweeps of $K_r$ gives the full matrix's verdict.

$$\begin{aligned} &\forall u \in \mathrm{pilot},\ \forall \pi \in \mathcal P,\ \forall \mathrm{hv},\ \forall S_r, K_r,\quad (\forall h,\ \neg\operatorname{isU}(\mathrm{hv}(h))) \wedge S(u) \subseteq S_r \subseteq M \wedge K(u) \subseteq K_r \subseteq W \\ &\quad\implies V_{\rho_\pi,\kappa_u,\mathrm{hv}}(S_r, \operatorname{map}\ r\ K_r) = V_{\rho_\pi,\kappa_u,\mathrm{hv}}(M, W) \end{aligned}$$

`scope_sound`, then `reduced_scopedVerdict`. -/
theorem reduced_scope_sound (u : PartUse) (hu : u ∈ pilotParts) (π : Port) (hv : List (List Bool) → Verdict)
    (hU : ∀ h, (hv h).isUnreachable = false) (S : List Probe) (K : List Sweep)
    (hS1 : ∀ p ∈ scopeProbes u, p ∈ S) (hS2 : ∀ p ∈ S, p ∈ matrix)
    (hK1 : ∀ w ∈ scopeSweeps u, w ∈ K) (hK2 : ∀ w ∈ K, w ∈ sweeps) :
    scopedVerdict (envReason π) u.key hv S (K.map reduceSweep) =
      scopedVerdict (envReason π) u.key hv matrix sweeps := by
  rw [reduced_scopedVerdict u hu]
  exact scope_sound u hu π hv hU S K hS1 hS2 hK1 hK2

/-! ## The reduced desktop sweep -/

/-- The desktop sweep's widths: down through every edge pair to 320 and back up.

$$D_{\mathrm{full}} = D \mathbin{+\!\!+} \operatorname{tail}(\operatorname{reverse}(D)),\quad D = \mathrm{deskSweepWidths}$$

The 57 widths of `desktop-1512-320-1512`. -/
def deskSweepFull : List Nat := deskSweepWidths ++ deskSweepWidths.reverse.drop 1

/-- The reduced desktop sweep widths: the stutter stops of the combined key dropped.

$$R = \operatorname{dropStutter}_{\kappa \circ \operatorname{deskStop}}(D_{\mathrm{full}})$$

What `gate-speed-impl` runs instead of the 57 widths (`sweeps.gen.json`). -/
def reducedDeskWidths (_ : Unit := ()) : List Nat := dropStutter (fun n => sweepKey (deskStop n)) deskSweepFull

/-- The desktop sweep is the first sweep, with stops `deskStop` of the full widths.

$$\operatorname{head}(W) = (\texttt{desktop-1512-320-1512}, \_, \operatorname{deskStop}(D_{\mathrm{full}}))$$

Ties `deskSweepFull` to `sweeps`. -/
theorem sweeps_head_desk :
    (sweeps.head?.map fun w => (w.id, w.stops)) =
      some ("desktop-1512-320-1512", deskSweepFull.map deskStop) := rfl

/-- The reduced desktop sweep, as a sweep, is `deskStop` of the reduced widths.

$$\forall w,\quad w = \operatorname{head}(W) \implies \mathrm{stops}(r(w)) = \operatorname{deskStop}(R)$$

The JSON's widths are exactly the reduced sweep's stops. -/
theorem reduceSweep_desk (w : Sweep) (h : sweeps.head? = some w) :
    (reduceSweep w).stops = reducedDeskWidths.map deskStop := by
  have : w.stops = deskSweepFull.map deskStop := by
    have := sweeps_head_desk; rw [h] at this; simp at this; exact this.2
  simp only [reduceSweep, this, reducedDeskWidths]
  exact dropStutter_map sweepKey deskStop deskSweepFull

/-- **The reduced desktop sweep has 45 stops** (22 down to 400, the turn at 320, 22 back up), down from 57: 12 of the 57
stops repeat the previous stop's combined key and are dropped. With every ported part in the scope the turn at 320 is
kept (a ported part's key tells 320 from 400); before the ports, 35 stops remained.

$$R = (1512, 1511, 1280, 1279, 1200, 1100, 1030, 1000, 960, 861, 860, 721, 720, 640, 601, 600, 481, 480, 462, 461, 401, 400, 320,\ 400, 401, 461, 462, 480, 481, 600, 601, 640, 641, 721, 860, 861, 960, 961, 1001, 1031, 1101, 1201, 1280, 1511, 1512)$$

The exact width list `sweeps.gen.json` carries. -/
theorem reducedDeskWidths_eq : reducedDeskWidths =
    [1512, 1511, 1280, 1279, 1200, 1100, 1030, 1000, 960, 861, 860, 721, 720, 640, 601, 600, 481, 480, 462, 461,
     401, 400, 320, 400, 401, 461, 462, 480, 481, 600, 601, 640, 641, 721, 860, 861, 960, 961, 1001, 1031, 1101,
     1201, 1280, 1511, 1512] := by
  decide +kernel

/-- The stop counts: 57 before, 45 after.

$$|D_{\mathrm{full}}| = 57 \wedge |R| = 45$$

12 resize stops fewer per engine. -/
theorem reducedDesk_length : deskSweepFull.length = 57 ∧ reducedDeskWidths.length = 45 := by
  rw [reducedDeskWidths_eq]; decide

/-- The reduced desktop sweep starts and ends where the full one does, so the first load and the hysteresis pair
(`Fw.Gate.stale`: the state after the last stop against a fresh load there) use the same environments.

$$\operatorname{last}(R) = \operatorname{last}(D_{\mathrm{full}}) = 1512 \wedge \operatorname{head}(R) = \operatorname{head}(D_{\mathrm{full}}) = 1512$$

The fresh-final load and the first load are unchanged. -/
theorem reducedDesk_ends : reducedDeskWidths.getLast? = some 1512 ∧ deskSweepFull.getLast? = some 1512 ∧
    reducedDeskWidths.head? = some 1512 ∧ deskSweepFull.head? = some 1512 := by
  rw [reducedDeskWidths_eq]; decide

/-- Every desktop sweep width, full or reduced, is the environment of a matrix probe, so the matchMedia `=Lean` row
(`spec.mjs` `expectFor`, which looks a stop up among the matrix probes) can find a vector at every stop of both.

$$\forall n \in D_{\mathrm{full}},\ \exists p \in M,\quad e(p) = \operatorname{deskStop}(n)$$

(and $R \sqsubseteq D_{\mathrm{full}}$ by `dropStutter_sublist`). The reduction loses no vector-carrying width class. -/
theorem deskSweep_has_probes : (deskSweepFull.all fun n => matrix.any fun p => p.env == deskStop n) = true := by
  decide +kernel

/-- The other three sweeps have no stutter stop: the reduction keeps all their stops.

$$\forall w \in \operatorname{tail}(W),\quad |\mathrm{stops}(r(w))| = |\mathrm{stops}(w)|$$

Only the desktop sweep gets shorter (with `dropStutter_sublist`, the other three are unchanged). -/
theorem reduceSweep_short :
    (sweeps.drop 1).all (fun w => (reduceSweep w).stops.length == w.stops.length) = true := by
  decide +kernel

/-! ## Caveat: the verdict cells are equal, the tally counts are not -/

/-- With every stop failing, a nonempty sweep's cell counts every stop as failing and compared.

$$\forall \kappa,\ \forall s \ne [\,],\quad \operatorname{tally}(\operatorname{stops}_{\kappa,\,h \mapsto \mathrm{fail}}(s)) = (\mathrm{fail}, |s|, |s|, 0)$$

Both numbers of a sweep cell's `FAIL k/n` count stops. -/
theorem tally_const_fail {κ : Type} [DecidableEq κ] (key : Env → κ) (s : List Env) (hs : s ≠ []) :
    tally (stopVerdicts key (fun _ => .fail) s) = ⟨.fail, s.length, s.length, 0⟩ := by
  have hrep : stopVerdicts key (fun _ => .fail) s = List.replicate s.length .fail := by
    simp [stopVerdicts, List.map_const']
  rw [hrep]
  have hr : rollup (List.replicate s.length Verdict.fail) = .fail := by
    rw [rollup_fail_iff, List.mem_replicate]
    exact ⟨by cases s with | nil => exact absurd rfl hs | cons _ _ => simp, rfl⟩
  simp only [tally, hr, List.countP_replicate]
  simp [Verdict.isComparable, Verdict.isUnreachable]

/-- **Caveat: a reduced sweep's cell has other counts.** The verdict of a sweep cell is the same after the reduction
whenever the row's key history is (`sweepCell_verdict_reduce`), but its counts are not: when every stop fails, the
full desktop sweep's cell is $(\mathrm{fail}, 57, 57, 0)$ and the reduced one's $(\mathrm{fail}, 45, 45, 0)$.

$$\forall \kappa,\quad \operatorname{tally}(\operatorname{stops}_{\kappa,\,h \mapsto \mathrm{fail}}(\operatorname{deskStop}(R))) = (\mathrm{fail}, 45, 45, 0) \wedge \operatorname{tally}(\operatorname{stops}_{\kappa,\,h \mapsto \mathrm{fail}}(\operatorname{deskStop}(D_{\mathrm{full}}))) = (\mathrm{fail}, 57, 57, 0)$$

So the report text changes from `FAIL 57/57` to `FAIL 45/45`. Reports that print counts change: the sweep column's
`FAIL k/n` (`summary.mjs` cell text) and the failure list's per-item stop counts. The verdict word of every cell
(`pass`, `FAIL`, `NC`), the probe blocks' cells (`blockCell`, no sweep stop in them) and the hysteresis pair
(`reducedDesk_ends`) do not change. -/
theorem reduced_desk_tally_ne {κ : Type} [DecidableEq κ] (key : Env → κ) :
    tally (stopVerdicts key (fun _ => .fail) (reducedDeskWidths.map deskStop)) = ⟨.fail, 45, 45, 0⟩ ∧
    tally (stopVerdicts key (fun _ => .fail) (deskSweepFull.map deskStop)) = ⟨.fail, 57, 57, 0⟩ := by
  have h1 : reducedDeskWidths.map deskStop ≠ [] := by rw [reducedDeskWidths_eq]; simp
  have h2 : deskSweepFull.map deskStop ≠ [] := by
    intro h; have := congrArg List.length h; simp [reducedDesk_length.1] at this
  rw [tally_const_fail _ _ h1, tally_const_fail _ _ h2, List.length_map, List.length_map, reducedDesk_length.1,
    reducedDesk_length.2]
  exact ⟨rfl, rfl⟩

end Fw.Gate
