/-!
# Expected module-cache misses after an edit (task mathview-ci-fix)

The `mathview-differential` CI job edits one module $x$ and checks which modules the module cache recomputes. By
`Fw.Console.LandSpeed.mkey_congr` and `mkey_sound` (with no hash collision), the key of $m$ changes exactly when a
module of the import cone of $m$ changes, so an edit of $x$ alone recomputes exactly the modules whose cone contains
$x$: its *dependents*. The job used to hard-code that set (`misses 2`) and broke when two more modules began to import
the edited one. Here the set is computed from the import graph in one pass over a topologically ordered module list
(every module after its imports, checked by `topoFrom`), and `mem_dependents` proves it is the set of dependents.
`lake exe mathview --dependents <x>` prints it; the job compares it with the `miss` lines of the cache stats.

The `mathview` binary links this module, so it imports nothing from `Fw`. It is not in `MathViewMain.toolSources`:
it decides only the `--dependents` output, never the lint or the export that the cache keys cover.
`Fw.Console.LandSpeed.inCone_iff_reach` links `Reach` to `InCone`.
-/

namespace Fw.Spec.ConeMiss

/-- `x` is reachable from `m` along imports (reflexive-transitive), i.e. `x` is in the import cone of `m`.
$$\forall \mathit{imp}, x, m:\ \mathrm{Reach}_{\mathit{imp}}(x, m) \iff x = m \lor \exists i \in \mathit{imp}(m):\ \mathrm{Reach}_{\mathit{imp}}(x, i)$$
(the least such relation). -/
inductive Reach (imp : String → List String) (x : String) : String → Prop
  | refl : Reach imp x x
  | step {m i : String} : i ∈ imp m → Reach imp x i → Reach imp x m

/-- One unfolding of `Reach`: `x` is in the cone of `m` iff it is `m` or in the cone of one of `m`'s imports.
$$\forall \mathit{imp}, x, m:\ \mathrm{Reach}_{\mathit{imp}}(x, m) \iff x = m \lor \exists i \in \mathit{imp}(m):\ \mathrm{Reach}_{\mathit{imp}}(x, i)$$ -/
theorem reach_iff (imp : String → List String) (x m : String) :
    Reach imp x m ↔ x = m ∨ ∃ i ∈ imp m, Reach imp x i := by
  constructor
  · intro h
    cases h with
    | refl => exact Or.inl rfl
    | step hi hr => exact Or.inr ⟨_, hi, hr⟩
  · rintro (rfl | ⟨i, hi, hr⟩)
    · exact .refl
    · exact .step hi hr

/-- Whether the list `ms`, read after the already placed modules `done`, lists every module after all of its imports.
$$\forall \mathit{imp}, D, m, \mathit{ms}:\quad \mathrm{topo}_{\mathit{imp}}(D, [\,]) = \top,\qquad \mathrm{topo}_{\mathit{imp}}(D, m :: \mathit{ms}) = \bigl(\forall i \in \mathit{imp}(m):\ i \in D\bigr) \land \mathrm{topo}_{\mathit{imp}}(D \mathbin{+\!\!+} [m], \mathit{ms})$$
The empty list is ordered; a module that imports itself or a module not yet placed makes it false. -/
def topoFrom (imp : String → List String) : List String → List String → Bool
  | _, [] => true
  | done, m :: ms => (imp m).all (fun i => done.contains i) && topoFrom imp (done ++ [m]) ms

/-- One pass over `ms`: append `m` to the accumulator `acc` when `m = x` or one of its imports is already in `acc`.
$$\forall \mathit{imp}, x, A, m, \mathit{ms}:\quad \mathrm{dep}_{\mathit{imp},x}(A, [\,]) = A,\qquad \mathrm{dep}_{\mathit{imp},x}(A, m :: \mathit{ms}) = \mathrm{dep}_{\mathit{imp},x}\bigl(\text{if } m = x \lor \exists i \in \mathit{imp}(m):\ i \in A \text{ then } A \mathbin{+\!\!+} [m] \text{ else } A,\ \mathit{ms}\bigr)$$
It returns `acc` unchanged on the empty list. -/
def depsFrom (imp : String → List String) (x : String) : List String → List String → List String
  | acc, [] => acc
  | acc, m :: ms =>
    depsFrom imp x (if m == x || (imp m).any (fun i => acc.contains i) then acc ++ [m] else acc) ms

/-- The modules of `order` whose import cone contains `x` (in the order of `order`): the modules an edit of `x`
recomputes.
$$\forall \mathit{imp}, O, x:\ \mathrm{dependents}(\mathit{imp}, O, x) = \mathrm{dep}_{\mathit{imp},x}([\,], O)$$
Empty when `x` does not occur in `order`. -/
def dependents (imp : String → List String) (order : List String) (x : String) : List String :=
  depsFrom imp x [] order

/-- The invariant of the pass: if the accumulator holds exactly the dependents among the placed modules and the rest is
topologically ordered, the result holds exactly the dependents among all of them.
$$\forall \mathit{imp}, x, \mathit{ms}, D, A:\ \bigl(\forall y:\ y \in A \iff y \in D \land \mathrm{Reach}_{\mathit{imp}}(x, y)\bigr) \land \mathrm{topo}_{\mathit{imp}}(D, \mathit{ms}) \Rightarrow \forall y:\ \bigl(y \in \mathrm{dep}_{\mathit{imp},x}(A, \mathit{ms}) \iff y \in D \mathbin{+\!\!+} \mathit{ms} \land \mathrm{Reach}_{\mathit{imp}}(x, y)\bigr)$$ -/
theorem mem_depsFrom (imp : String → List String) (x : String) :
    ∀ (ms done acc : List String), (∀ y, y ∈ acc ↔ y ∈ done ∧ Reach imp x y) →
      topoFrom imp done ms = true →
      ∀ y, (y ∈ depsFrom imp x acc ms ↔ y ∈ done ++ ms ∧ Reach imp x y) := by
  intro ms
  induction ms with
  | nil => intro done acc hacc _ y; simpa [depsFrom] using hacc y
  | cons m ms ih =>
    intro done acc hacc htopo y
    simp only [topoFrom, Bool.and_eq_true, List.all_eq_true, List.contains_iff_mem] at htopo
    obtain ⟨himp, hrest⟩ := htopo
    -- the test of the pass decides `Reach x m`, since every import of `m` is placed
    have hm : (m == x || (imp m).any (fun i => acc.contains i)) = true ↔ Reach imp x m := by
      rw [reach_iff]
      simp only [Bool.or_eq_true, beq_iff_eq, List.any_eq_true, List.contains_iff_mem]
      constructor
      · rintro (h | ⟨i, hi, ha⟩)
        · exact Or.inl h.symm
        · exact Or.inr ⟨i, hi, ((hacc i).1 ha).2⟩
      · rintro (h | ⟨i, hi, hr⟩)
        · exact Or.inl h.symm
        · exact Or.inr ⟨i, hi, (hacc i).2 ⟨himp i hi, hr⟩⟩
    have hacc' : ∀ z, z ∈ (if m == x || (imp m).any (fun i => acc.contains i) then acc ++ [m] else acc) ↔
        z ∈ done ++ [m] ∧ Reach imp x z := by
      intro z
      by_cases hc : (m == x || (imp m).any (fun i => acc.contains i)) = true
      · have hr := hm.1 hc
        rw [ite_eq_left hc]
        simp only [List.mem_append, List.mem_singleton, hacc z]
        constructor
        · rintro (⟨hd, hz⟩ | rfl)
          · exact ⟨Or.inl hd, hz⟩
          · exact ⟨Or.inr rfl, hr⟩
        · rintro ⟨hd | rfl, hz⟩
          · exact Or.inl ⟨hd, hz⟩
          · exact Or.inr rfl
      · have hr : ¬ Reach imp x m := fun h => hc (hm.2 h)
        rw [ite_eq_right hc]
        simp only [List.mem_append, List.mem_singleton, hacc z]
        constructor
        · rintro ⟨hd, hz⟩
          exact ⟨Or.inl hd, hz⟩
        · rintro ⟨hd | rfl, hz⟩
          · exact ⟨hd, hz⟩
          · exact absurd hz hr
    have := ih (done ++ [m]) _ hacc' hrest y
    simpa [depsFrom, List.append_assoc] using this

/-- **Dependents are exactly the modules whose cone contains `x`.** For a topologically ordered module list, `y` is
listed by `dependents` iff `y` is in the list and `x` is in the import cone of `y`.
$$\forall \mathit{imp}, O, x, y:\ \mathrm{topo}_{\mathit{imp}}([\,], O) \Rightarrow \bigl(y \in \mathrm{dependents}(\mathit{imp}, O, x) \iff y \in O \land \mathrm{Reach}_{\mathit{imp}}(x, y)\bigr)$$ -/
theorem mem_dependents (imp : String → List String) (order : List String) (x y : String)
    (h : topoFrom imp [] order = true) :
    y ∈ dependents imp order x ↔ y ∈ order ∧ Reach imp x y := by
  have := mem_depsFrom imp x order [] [] (by simp) h y
  simpa [dependents] using this

/-- A sample import graph: `A` is a leaf, `B` and `C` import `A`, `D` imports `B`, `E` imports nothing, `F` imports
`D` and `E`; every other string (`A` and `E` included) imports nothing.
$$\mathit{imp}(s) = \begin{cases} [\texttt{"A"}] & s \in \{\texttt{"B"}, \texttt{"C"}\} \\ [\texttt{"B"}] & s = \texttt{"D"} \\ [\texttt{"D"}, \texttt{"E"}] & s = \texttt{"F"} \\ [\,] & \text{otherwise} \end{cases}$$ -/
def sampleImp : String → List String
  | "B" => ["A"] | "C" => ["A"] | "D" => ["B"] | "F" => ["D", "E"] | _ => []

#guard topoFrom sampleImp [] ["A", "B", "C", "D", "E", "F"] == true
#guard topoFrom sampleImp [] ["B", "A"] == false
#guard topoFrom sampleImp [] [] == true
#guard topoFrom (fun _ => ["A"]) [] ["A"] == false
#guard dependents sampleImp ["A", "B", "C", "D", "E", "F"] "A" == ["A", "B", "C", "D", "F"]
#guard dependents sampleImp ["A", "B", "C", "D", "E", "F"] "B" == ["B", "D", "F"]
#guard dependents sampleImp ["A", "B", "C", "D", "E", "F"] "E" == ["E", "F"]
#guard dependents sampleImp ["A", "B", "C", "D", "E", "F"] "F" == ["F"]
#guard dependents sampleImp ["A", "B", "C", "D", "E", "F"] "Z" == []
#guard dependents sampleImp [] "A" == []

end Fw.Spec.ConeMiss
