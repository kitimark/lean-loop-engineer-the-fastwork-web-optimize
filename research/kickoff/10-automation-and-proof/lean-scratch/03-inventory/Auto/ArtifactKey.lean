/-!
# Sketch 3: artifact cache keys (soundness and minimal invalidation)

An artifact depends on a list of named inputs (the plugin's `semantics`, the engine build, the
route's `servedHash`, the profile, the protocol). Every input has a current value (a version or a
content hash, here a `Nat`). The key is the canonical encoding of `[(input, value)]`, and the
stored key is `sha256(encoding)`.

math (for the reader):
  key_v(a) = ⟨(i, v(i)) : i ∈ deps(a)⟩                       -- the list of input names and values
  enc : List (List ℕ) → List ℕ,  enc(x₁…x_n) = ⟨|x₁|⟩ ⧺ x₁ ⧺ ⋯ ⧺ ⟨|x_n|⟩ ⧺ x_n   -- each field: its length, then the field
  dec(enc(x)) = x  ⇒  enc(x) = enc(y) ⇒ x = y                -- enc_inj: equal bytes ⇒ equal inputs
  v' = v[i ↦ w], w ≠ v(i)  ⇒  ( key_v(a) ≠ key_v'(a)  ⇔  i ∈ deps(a) )   -- stale_iff
  stale(A, i) = { a ∈ A : i ∈ deps(a) }                       -- exactly the dependants, no more, no less
  sha256 is collision-free on what we hash                    -- ASSUMPTION (not provable; L3)
-/
namespace Auto.ArtifactKey

abbrev Input := Nat          -- an input id, e.g. "tool:chromium.counts:semantics"
abbrev Val := Nat            -- a version or content hash

structure Artifact where
  deps : List Input
deriving Repr, DecidableEq

def key (v : Input → Val) (a : Artifact) : List (Input × Val) := a.deps.map (fun i => (i, v i))

def update (v : Input → Val) (i : Input) (w : Val) : Input → Val := fun j => if j = i then w else v j

/-- **Minimal invalidation.** Changing input `i` changes the key of `a` iff `a` depends on `i`. -/
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

/-- The stale set is a filter: computing it is a pure function of `deps` and the changed input. -/
def stale (as : List Artifact) (i : Input) : List Artifact := as.filter (fun a => i ∈ a.deps)

theorem stale_spec (v : Input → Val) (i : Input) (w : Val) (hw : w ≠ v i) (as : List Artifact)
    (a : Artifact) : a ∈ stale as i ↔ a ∈ as ∧ key v a ≠ key (update v i w) a := by
  simp [stale, stale_iff v i w hw]

/-! ## Canonical encoding: equal bytes ⇒ equal inputs -/

def enc : List (List Nat) → List Nat
  | [] => []
  | x :: xs => (x.length :: x) ++ enc xs

def dec (fuel : Nat) (bs : List Nat) : Option (List (List Nat)) :=
  match fuel, bs with
  | _, [] => some []
  | 0, _ :: _ => none
  | f + 1, n :: rest =>
    if n ≤ rest.length then (dec f (rest.drop n)).map (rest.take n :: ·) else none

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

/-- **Soundness of the key encoding**: two input lists with the same encoding are equal. -/
theorem enc_inj {xs ys : List (List Nat)} (h : enc xs = enc ys) : xs = ys := by
  have hx := dec_enc xs (xs.length + ys.length) (by omega)
  have hy := dec_enc ys (xs.length + ys.length) (by omega)
  rw [h] at hx
  rw [hx] at hy
  exact Option.some.inj hy

/-- Flatten a key to the field list that gets hashed. -/
def fields (k : List (Input × Val)) : List (List Nat) := k.flatMap (fun (i, x) => [[i], [x]])

theorem fields_inj : ∀ {k k' : List (Input × Val)}, fields k = fields k' → k = k'
  | [], [], _ => rfl
  | [], _ :: _, h => by simp [fields] at h
  | _ :: _, [], h => by simp [fields] at h
  | (i, x) :: k, (i', x') :: k', h => by
    simp only [fields, List.flatMap_cons, List.cons_append, List.nil_append, List.cons.injEq] at h
    obtain ⟨h1, h2, h3⟩ := h
    rw [h1.1, h2.1, fields_inj h3]

/-- Equal encoded keys ⇒ the artifact saw exactly the same inputs with the same values. -/
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

/-! ## Examples: plugin X semantics bump invalidates only X's artifacts -/
def semX : Input := 1   -- tool:X:semantics
def semY : Input := 2   -- tool:Y:semantics
def engine : Input := 3
def heroRoute : Input := 4
def artX : Artifact := ⟨[semX, engine, heroRoute]⟩
def artY : Artifact := ⟨[semY, engine, heroRoute]⟩
#guard stale [artX, artY] semX == [artX]
#guard stale [artX, artY] engine == [artX, artY]
#guard dec 10 (enc [[1, 2], [], [3]]) == some [[1, 2], [], [3]]

end Auto.ArtifactKey
