import Fw.Wire.Gate
import Std.Data.TreeMap.Raw.Lemmas

/-!
# The gate decoders ignore `declared`

`collectInPage` (`packages/gate-breakpoints/src/page.mjs:146-177`) reports, for each part and role, `count`,
`declared` (the property names the matching rules declare) and `items`. Only the Phase 0 property scan reads
`declared` (`run.mjs:104-119`); the gate's decoders read only `count` and `items` (`partRawOf`,
`lean/Fw/Wire/Gate.lean:190-196`). So a run may skip the `declared` scan at sweep and probe stops (or send any other
value there) without changing a `gate.state` or `gate.stale` reply.

Objects are `Std.TreeMap.Raw` maps; the lemmas about looking up a key after an insert need the map to be well formed
(`WF`), which every object built by the JSON parser or `Json.mkObj` is (built by inserts into the empty map), so the
role maps carry that premise.
-/

namespace Fw.Wire.Gate
open Lean Fw.Gate
open Fw.Wire.Ops (field opt asNat arr)

/-- Set (or add) the `declared` field of one role record; anything but an object is left as it is.

$$\operatorname{setD}_d(\{\dots\}) = \{\dots, \mathtt{declared}: d\}, \qquad \operatorname{setD}_d(j) = j \ \text{otherwise}$$

The one field the decoders ignore. -/
def setDeclared (d : Json) : Json → Json
  | .obj kvs => .obj (kvs.insert "declared" d)
  | j => j

/-- Set `declared` on every role of one part record, to $d(\mathit{role})$; anything but an object is left as it is.

$$\operatorname{setP}_d(\{r_1: j_1, \dots\}) = \{r_1: \operatorname{setD}_{d(r_1)}(j_1), \dots\}, \qquad \operatorname{setP}_d(j) = j \ \text{otherwise}$$

What a run that changes the `declared` scan writes for one part. -/
def setPartDeclared (dOf : String → Json) : Json → Json
  | .obj kvs => .obj (kvs.map fun role rj => setDeclared (dOf role) rj)
  | j => j

/-- Set `declared` on every role of every part of a `parts` record, to $d(\mathit{part}, \mathit{role})$.

$$\operatorname{setPs}_d(\{p_1: j_1, \dots\}) = \{p_1: \operatorname{setP}_{d(p_1, \cdot)}(j_1), \dots\}, \qquad \operatorname{setPs}_d(j) = j \ \text{otherwise}$$

One arm's `parts` with another `declared` everywhere. -/
def setPartsDeclared (dOf : String → String → Json) : Json → Json
  | .obj kvs => .obj (kvs.map fun pid pj => setPartDeclared (dOf pid) pj)
  | j => j

/-- Every role value of a part record that is an object is a well-formed map.

$$\operatorname{wf}_P(j) \iff \forall (r, v) \in j,\ \forall m,\ v = \mathrm{obj}(m) \implies \operatorname{WF}(m) \qquad (\top \text{ if } j \text{ is no object})$$

The premise of the lookup lemmas. -/
def RolesWF : Json → Prop
  | .obj kvs => ∀ p ∈ kvs.toList, ∀ m, p.2 = .obj m → m.WF
  | _ => True

/-- Every part value of a `parts` record satisfies `RolesWF`.

$$\operatorname{wf}_{Ps}(j) \iff \forall (p, v) \in j,\ \operatorname{wf}_P(v) \qquad (\top \text{ if } j \text{ is no object})$$

The premise for a whole arm. -/
def PartsWF : Json → Prop
  | .obj kvs => ∀ p ∈ kvs.toList, RolesWF p.2
  | _ => True

/-- Binding a success runs the continuation on its value.

$$\forall a, f,\quad (\mathrm{ok}(a) \gg\!= f) = f(a)$$

Helper (definitional). -/
theorem except_ok_bind {ε α β : Type} (a : α) (f : α → Except ε β) : (Except.ok a >>= f) = f a := rfl

/-- Setting `declared` keeps every other field of a well-formed role record.

$$\forall d, j, k,\quad (\forall m,\ j = \mathrm{obj}(m) \implies \operatorname{WF}(m)) \wedge k \ne \mathtt{declared} \implies \operatorname{get}(\operatorname{setD}_d(j), k) = \operatorname{get}(j, k)$$

Here $\operatorname{get}$ is `Json.getObjVal?` (an error for a missing key or a non-object). -/
theorem getObjVal?_setDeclared (d j : Json) (k : String) (hwf : ∀ m, j = .obj m → m.WF)
    (hk : k ≠ "declared") : (setDeclared d j).getObjVal? k = j.getObjVal? k := by
  cases j with
  | obj kvs =>
    have hc : compare "declared" k ≠ .eq := fun h => hk (Std.LawfulEqCmp.eq_of_compare h).symm
    simp only [setDeclared, Json.getObjVal?, Std.TreeMap.Raw.get?_eq_getElem?,
      Std.TreeMap.Raw.getElem?_insert (hwf kvs rfl), hc, ite_false]
  | _ => rfl

/-- One role, decoded: the function `partRawOf` maps over the role entries.

$$\operatorname{role}(r, v) = \begin{cases} \mathrm{ok}(\mathrm{none}) & v = \mathrm{null} \\ \mathrm{some}(r, (\operatorname{count}(v), \operatorname{items}(v))) & \text{otherwise (or the first error)} \end{cases}$$

Restates the body of `partRawOf`. -/
def roleOf : String × Json → Except String (Option (String × RoleRaw)) := fun (role, rj) =>
  match rj with
  | .null => pure none
  | _ => do pure (some (role, (⟨← asNat "count" (← field rj "count"),
      ← (← arr rj "items").toList.mapM itemOf⟩ : RoleRaw)))

/-- `partRawOf` is `roleOf` over the entries.

$$\forall j,\quad \operatorname{partRaw}(j) = \operatorname{entries}(j) \gg\!= \operatorname{filterMapM}(\operatorname{role})$$

Unfolds the decoder. -/
theorem partRawOf_eq (j : Json) : partRawOf j = (entriesOf "part" j >>= fun es => es.filterMapM roleOf) := rfl

/-- Decoding one role ignores `declared` (for a well-formed role object).

$$\forall d, r, v,\quad (\forall m,\ v = \mathrm{obj}(m) \implies \operatorname{WF}(m)) \implies \operatorname{role}(r, \operatorname{setD}_d(v)) = \operatorname{role}(r, v)$$

Only `count` and `items` are read. -/
theorem roleOf_setDeclared (d : Json) (role : String) (rj : Json) (hwf : ∀ m, rj = .obj m → m.WF) :
    roleOf (role, setDeclared d rj) = roleOf (role, rj) := by
  cases rj with
  | obj kvs =>
    have hc := getObjVal?_setDeclared d (.obj kvs) "count" hwf (by decide)
    have hi := getObjVal?_setDeclared d (.obj kvs) "items" hwf (by decide)
    simp only [roleOf, field, arr, hc, hi]
    rfl
  | _ => rfl

/-- Mapping first and filter-mapping is filter-mapping with an equal function.

$$\forall F, g, l,\quad (\forall x \in l,\ F(g(x)) = F(x)) \implies \operatorname{filterMapM}(F, g(l)) = \operatorname{filterMapM}(F, l)$$

Helper (in `Except String`). -/
theorem filterMapM_map_congr {α β : Type} (F : α → Except String (Option β)) (g : α → α) :
    ∀ (l : List α), (∀ x ∈ l, F (g x) = F x) → (l.map g).filterMapM F = l.filterMapM F
  | [], _ => rfl
  | a :: l, h => by
    rw [List.map_cons, List.filterMapM_cons, List.filterMapM_cons, h a (by simp),
      filterMapM_map_congr F g l (fun x hx => h x (by simp [hx]))]

/-- **`partRawOf` ignores `declared`.** For a part record whose role objects are well formed, setting `declared` on
every role to any values leaves the decoded part (or the decoding error) unchanged.

$$\forall d, j,\quad \operatorname{wf}_P(j) \implies \operatorname{partRaw}(\operatorname{setP}_d(j)) = \operatorname{partRaw}(j)$$

The decoder reads only `count` and `items` (`lean/Fw/Wire/Gate.lean:190-196`). -/
theorem partRawOf_setPartDeclared (dOf : String → Json) (j : Json) (hwf : RolesWF j) :
    partRawOf (setPartDeclared dOf j) = partRawOf j := by
  cases j with
  | obj kvs =>
    rw [partRawOf_eq, partRawOf_eq]
    simp only [setPartDeclared, entriesOf, Std.TreeMap.Raw.toList_map]
    exact filterMapM_map_congr roleOf (fun p => (p.1, setDeclared (dOf p.1) p.2)) kvs.toList
      (fun x hx => roleOf_setDeclared _ x.1 x.2 (hwf x hx))
  | _ => rfl

/-- **`partsOf` ignores `declared`.** For an arm's `parts` record whose role objects are well formed, setting
`declared` on every role of every part leaves the decoded parts (or the decoding error) unchanged.

$$\forall d, j,\quad \operatorname{wf}_{Ps}(j) \implies \operatorname{parts}(\operatorname{setPs}_d(j)) = \operatorname{parts}(j)$$

Every part goes through `partRawOf_setPartDeclared`. -/
theorem partsOf_setPartsDeclared (dOf : String → String → Json) (j : Json) (hwf : PartsWF j) :
    partsOf (setPartsDeclared dOf j) = partsOf j := by
  cases j with
  | obj kvs =>
    simp only [partsOf, setPartsDeclared, entriesOf, Std.TreeMap.Raw.toList_map]
    refine filterMapM_map_congr _ (fun p => (p.1, setPartDeclared (dOf p.1) p.2)) kvs.toList ?_
    intro x hx
    obtain ⟨pid, pj⟩ := x
    cases pj with
    | null => rfl
    | obj m =>
      simp only [partRawOf_setPartDeclared _ _ (hwf _ hx)]
      rfl
    | _ => rfl
  | _ => rfl

/-- **`gate.stale` ignores `declared`.** For one pair of `opStale`, the hysteresis counts decoded from the `after`
and `fresh` parts are the same whether or not `declared` was changed in either.

$$\forall c, d, d', A, F,\quad \operatorname{wf}_{Ps}(A) \wedge \operatorname{wf}_{Ps}(F) \implies \big(\operatorname{parts}(\operatorname{setPs}_d(A)), \operatorname{parts}(\operatorname{setPs}_{d'}(F))\big) \overset{\operatorname{stale}_c}{\mapsto} = \big(\operatorname{parts}(A), \operatorname{parts}(F)\big) \overset{\operatorname{stale}_c}{\mapsto}$$

That is, the do-block of `opStale` gives the same counts (or the same error) for both inputs. -/
theorem stale_setPartsDeclared (c : Ctx) (dA dF : String → String → Json) (A F : Json) (hA : PartsWF A)
    (hF : PartsWF F) :
    (do pure (stale c (← partsOf (setPartsDeclared dA A)) (← partsOf (setPartsDeclared dF F))) :
      Except String (Nat × Nat)) = (do pure (stale c (← partsOf A) (← partsOf F))) := by
  rw [partsOf_setPartsDeclared dA A hA, partsOf_setPartsDeclared dF F hF]

/-- **`armOf` (and so `gate.state`) ignores `declared`.** Two arm records that are the same well-formed map except
for their `parts`, where one has `declared` changed, decode to the same arm (or the same error).

$$\forall d, m, P,\quad \operatorname{WF}(m) \wedge \operatorname{wf}_{Ps}(P) \implies \operatorname{arm}(m[\mathtt{parts} := \operatorname{setPs}_d(P)]) = \operatorname{arm}(m[\mathtt{parts} := P])$$

`stateOf` reads the arms only through `armOf`, so each state of `gate.state` is evaluated the same. -/
theorem armOf_setPartsDeclared (dOf : String → String → Json) (m : Std.TreeMap.Raw String Json) (P : Json)
    (hm : m.WF) (hP : PartsWF P) :
    armOf (.obj (m.insert "parts" (setPartsDeclared dOf P))) = armOf (.obj (m.insert "parts" P)) := by
  have key : ∀ (Q : Json) (k : String), k ≠ "parts" →
      (Json.obj (m.insert "parts" Q)).getObjVal? k = (Json.obj m).getObjVal? k := by
    intro Q k hk
    have hc : compare "parts" k ≠ .eq := fun h => hk (Std.LawfulEqCmp.eq_of_compare h).symm
    simp only [Json.getObjVal?, Std.TreeMap.Raw.get?_eq_getElem?, Std.TreeMap.Raw.getElem?_insert hm, hc,
      ite_false]
  have hp : ∀ Q : Json, (Json.obj (m.insert "parts" Q)).getObjVal? "parts" = .ok Q := by
    intro Q
    simp only [Json.getObjVal?, Std.TreeMap.Raw.get?_eq_getElem?, Std.TreeMap.Raw.getElem?_insert hm,
      Std.ReflCmp.compare_self, ite_true]
    rfl
  simp only [armOf, field, opt, optRat, optBool, key _ "viewport" (by decide), key _ "observed" (by decide),
    key _ "truth" (by decide), key _ "truthLegacy" (by decide), key _ "neutral" (by decide), hp,
    except_ok_bind, partsOf_setPartsDeclared dOf P hP]

end Fw.Wire.Gate
