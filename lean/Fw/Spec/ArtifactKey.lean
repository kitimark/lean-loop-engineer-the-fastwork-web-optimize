/-!
# Artifact cache keys (soundness and minimal invalidation)

Ported from the kickoff scratch `03-inventory/Auto/ArtifactKey.lean` (proofs unchanged).
An artifact depends on a list of named inputs (the plugin's `semantics`, the engine build, the
route's `servedHash`, the profile, the protocol). Every input has a current value (a version or a
content hash, here a `Nat`). The key is the canonical encoding of `[(input, value)]`, and the
stored key is `sha256(encoding)`; that sha256 is collision-free on what we hash is an assumption
(L3), not a theorem.
-/
namespace Fw.ArtifactKey

/-- An input id (for example "tool:chromium.counts:semantics"), numbered.

$$\mathrm{Input} = \mathbb{N}$$
-/
abbrev Input := Nat

/-- An input's value: a version or a content hash, numbered.

$$\mathrm{Val} = \mathbb{N}$$
-/
abbrev Val := Nat

/-- An artifact is described by the inputs it depends on, in a fixed order.

$$a = \mathit{deps}(a) \in \mathrm{Input}^{*}$$
-/
structure Artifact where
  deps : List Input
deriving Repr, DecidableEq

/-- The key of an artifact under the current values `v`: each input paired with its value.

$$\operatorname{key}_v(a) = \big[\, (i, v(i)) : i \in \mathit{deps}(a) \,\big]$$
-/
def key (v : Input → Val) (a : Artifact) : List (Input × Val) := a.deps.map (fun i => (i, v i))

/-- Change the value of one input (function update).

$$v[i \mapsto w](j) = \begin{cases} w & j = i \\ v(j) & j \ne i \end{cases}$$
-/
def update (v : Input → Val) (i : Input) (w : Val) : Input → Val := fun j => if j = i then w else v j

/-- **Minimal invalidation.** Changing input `i` to a new value changes the key of `a` iff `a`
depends on `i`.

$$\forall v, i, w, a:\quad w \ne v(i) \;\Rightarrow\; \Big(\operatorname{key}_v(a) \ne \operatorname{key}_{v[i \mapsto w]}(a) \iff i \in \mathit{deps}(a)\Big)$$
-/
theorem stale_iff (v : Input → Val) (i : Input) (w : Val) (hw : w ≠ v i) (a : Artifact) :
    key v a ≠ key (update v i w) a ↔ i ∈ a.deps := by
  unfold key update
  constructor
  · intro hne
    apply Classical.byContradiction
    intro hi
    apply hne
    apply List.map_congr_left
    intro j hj
    have : j ≠ i := fun e => hi (e ▸ hj)
    simp [this]
  · intro hi heq
    have := (List.map_inj_left.mp heq) i hi
    simp at this
    exact hw this.symm

/-- The stale set after input `i` changes: the artifacts that depend on `i`, in order.

$$\operatorname{stale}(As, i) = [\, a \in As \mid i \in \mathit{deps}(a) \,]$$
-/
def stale (as : List Artifact) (i : Input) : List Artifact := as.filter (fun a => i ∈ a.deps)

/-- The stale set is exactly the artifacts whose key changes: no more, no less.

$$\forall v, i, w, As, a:\quad w \ne v(i) \;\Rightarrow\; \Big(a \in \operatorname{stale}(As, i) \iff a \in As \ \land\ \operatorname{key}_v(a) \ne \operatorname{key}_{v[i \mapsto w]}(a)\Big)$$
-/
theorem stale_spec (v : Input → Val) (i : Input) (w : Val) (hw : w ≠ v i) (as : List Artifact)
    (a : Artifact) : a ∈ stale as i ↔ a ∈ as ∧ key v a ≠ key (update v i w) a := by
  simp [stale, stale_iff v i w hw]

/-! ## Canonical encoding: equal bytes ⇒ equal inputs -/

/-- The canonical encoding: each field is written as its length followed by the field.

$$\operatorname{enc}([\,]) = [\,], \qquad \operatorname{enc}(x :: xs) = |x| :: x \mathbin{+\!\!+} \operatorname{enc}(xs)$$
-/
def enc : List (List Nat) → List Nat
  | [] => []
  | x :: xs => (x.length :: x) ++ enc xs

/-- The decoder (with fuel, so it is structurally recursive): read a length, take that many
entries, repeat.

$$\operatorname{dec}(f, [\,]) = [\,], \qquad \operatorname{dec}(0, b :: bs) = \bot, \qquad \operatorname{dec}(f+1, n :: r) = \begin{cases} \operatorname{take}(n, r) :: \operatorname{dec}(f, \operatorname{drop}(n, r)) & \text{if } n \le |r| \\ \bot & \text{otherwise} \end{cases}$$

where $x :: \bot = \bot$.
-/
def dec (fuel : Nat) (bs : List Nat) : Option (List (List Nat)) :=
  match fuel, bs with
  | _, [] => some []
  | 0, _ :: _ => none
  | f + 1, n :: rest =>
    if n ≤ rest.length then (dec f (rest.drop n)).map (rest.take n :: ·) else none

/-- Decoding inverts encoding, given enough fuel.

$$\forall xs \in (\mathbb{N}^{*})^{*},\ \forall f \in \mathbb{N}:\quad |xs| \le f \;\Rightarrow\; \operatorname{dec}(f, \operatorname{enc}(xs)) = xs$$
-/
theorem dec_enc (xs : List (List Nat)) : ∀ f, xs.length ≤ f → dec f (enc xs) = some xs := by
  induction xs with
  | nil => intro f _; cases f <;> rfl
  | cons x xs ih =>
    intro f hf
    cases f with
    | zero => simp at hf
    | succ f =>
      simp only [enc, List.cons_append, dec, List.length_append, Nat.le_add_right, ite_true,
        List.drop_left, List.take_left]
      rw [ih f (by simp at hf; omega)]
      rfl

/-- **Soundness of the key encoding**: two field lists with the same encoding are equal.

$$\forall xs, ys \in (\mathbb{N}^{*})^{*}:\quad \operatorname{enc}(xs) = \operatorname{enc}(ys) \;\Rightarrow\; xs = ys$$
-/
theorem enc_inj {xs ys : List (List Nat)} (h : enc xs = enc ys) : xs = ys := by
  have hx := dec_enc xs (xs.length + ys.length) (by omega)
  have hy := dec_enc ys (xs.length + ys.length) (by omega)
  rw [h] at hx
  rw [hx] at hy
  exact Option.some.inj hy

/-- Flatten a key to the field list that gets hashed: each input and each value is one field.

$$\operatorname{fields}\big([(i_1, x_1), \dots, (i_n, x_n)]\big) = [[i_1], [x_1], \dots, [i_n], [x_n]]$$
-/
def fields (k : List (Input × Val)) : List (List Nat) := k.flatMap (fun (i, x) => [[i], [x]])

/-- Flattening loses nothing.

$$\forall k, k' \in (\mathrm{Input} \times \mathrm{Val})^{*}:\quad \operatorname{fields}(k) = \operatorname{fields}(k') \;\Rightarrow\; k = k'$$
-/
theorem fields_inj : ∀ {k k' : List (Input × Val)}, fields k = fields k' → k = k'
  | [], [], _ => rfl
  | [], _ :: _, h => by simp [fields] at h
  | _ :: _, [], h => by simp [fields] at h
  | (i, x) :: k, (i', x') :: k', h => by
    simp only [fields, List.flatMap_cons, List.cons_append, List.nil_append, List.cons.injEq] at h
    obtain ⟨h1, h2, h3⟩ := h
    rw [h1.1, h2.1, fields_inj h3]

/-- Equal encoded keys mean the two artifacts saw exactly the same inputs with the same values.

$$\forall v, v' : \mathrm{Input} \to \mathrm{Val},\ \forall a, b \in \mathrm{Artifact}:\quad \operatorname{enc}\big(\operatorname{fields}(\operatorname{key}_v(a))\big) =\operatorname{enc}\big(\operatorname{fields}(\operatorname{key}_{v'}(b))\big) \;\Rightarrow\; \mathit{deps}(a) = \mathit{deps}(b) \ \land\ \forall i \in \mathit{deps}(a):\ v(i) = v'(i)$$
-/
theorem key_sound (v v' : Input → Val) (a b : Artifact)
    (h : enc (fields (key v a)) = enc (fields (key v' b))) :
    a.deps = b.deps ∧ ∀ i ∈ a.deps, v i = v' i := by
  have hk := fields_inj (enc_inj h)
  unfold key at hk
  have hd : a.deps = b.deps := by
    have := congrArg (List.map Prod.fst) hk
    simpa [List.map_map, Function.comp_def] using this
  refine ⟨hd, ?_⟩
  rw [← hd] at hk
  intro i hi
  have := (List.map_inj_left.mp hk) i hi
  simpa using this

/-! ## Examples: a plugin X semantics bump (input 1) invalidates only X's artifacts;
an engine bump (input 3) invalidates both. -/
#guard stale [⟨[1, 3, 4]⟩, ⟨[2, 3, 4]⟩] 1 == [⟨[1, 3, 4]⟩]
#guard stale [⟨[1, 3, 4]⟩, ⟨[2, 3, 4]⟩] 3 == [⟨[1, 3, 4]⟩, ⟨[2, 3, 4]⟩]
#guard dec 10 (enc [[1, 2], [], [3]]) == some [[1, 2], [], [3]]
#guard dec 10 [5, 1] == none

end Fw.ArtifactKey
