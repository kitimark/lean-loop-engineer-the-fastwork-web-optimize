/-!
# Per-zone sums of raw per-frame counts (the counts lane's only reduction)

The Lean specification of `zoneSums` from `packages/measure-chromium/src/reduce.mjs` (the JS function
it replaces). A frame is `{n, phase, scrollY, counts}`; a frame with phase `swipe` belongs to the
zone `"y" ++ padStart5(⌊scrollY / h⌋ · h)` and any other frame to the zone named by its phase.
Each zone reports its number of frames, the scroll distance of its frames (each frame's scrollY
minus the previous frame's, the first one measured from 0), its first and last frame number, and
the sum of every count over its frames. Zones are listed in order of first appearance.

Counts and scroll positions are integers (`Int`: Performance.getMetrics deltas can be negative);
the zone height `h` is a natural number (the wire refuses `h = 0`). A count type missing from a
frame counts as 0, and a zone lists exactly the count types present in at least one of its frames.

Laws proved here: the zone lookups equal filter sums over the frames (`sumAt_spec`, …), additivity
over concatenation of frame lists (`sumAt_append`, `framesAt_append`, `scrolledAt_append`),
monotonicity (`sumAt_mono`, `sumAt_le_append`) and the partition laws (`zones_sum_total`,
`zones_frames_total`, `zones_scrolled_total`, `zoneIds_nodup`, `mem_zoneIds`).
-/
namespace Fw.Measure

/-! ## Data -/

/-- The counts of one frame as name–value entries (a JSON object's entries).

$$\mathrm{Counts} = (\Sigma^{*} \times \mathbb{Z})^{*}$$
-/
abbrev Counts := List (String × Int)

/-- One recorded frame: its number, its phase name, its scroll position after the frame and its
counts.

$$\mathrm{Frame} = \mathbb{N} \times \Sigma^{*} \times \mathbb{Z} \times \mathrm{Counts}$$
-/
structure Frame where
  n : Nat
  phase : String
  scrollY : Int
  counts : Counts
deriving Repr, DecidableEq

/-- An integer sum of a function over a list.

$$\operatorname{sumBy}(g, [x_1, \dots, x_m]) = \sum_{i=1}^{m} g(x_i) \in \mathbb{Z}$$
-/
def sumBy {α : Type} (g : α → Int) : List α → Int
  | [] => 0
  | a :: as => g a + sumBy g as

/-- The value of count type `k` in a list of entries: the sum of the values of the entries named
`k` (0 when there is none; a JSON object has at most one).

$$\operatorname{countIn}(C, k) = \sum_{(j, v) \in C,\ j = k} v$$
-/
def countIn : Counts → String → Int
  | [], _ => 0
  | (j, v) :: cs, k => (if j = k then v else 0) + countIn cs k

/-- The value of count type `k` in frame `f`.

$$c_f(k) = \operatorname{countIn}(f.\mathrm{counts}, k)$$
-/
def Frame.count (f : Frame) (k : String) : Int := countIn f.counts k

/-- Left-pad a string with `0` to at least 5 characters (JS `padStart(5, '0')`).

$$\operatorname{pad}_5(s) = 0^{\max(0,\, 5 - |s|)} \cdot s$$
-/
def padStart5 (s : String) : String := String.ofList (List.replicate (5 - s.length) '0') ++ s

#guard padStart5 "0" == "00000"
#guard padStart5 "500" == "00500"
#guard padStart5 "123456" == "123456"
#guard padStart5 "-500" == "0-500"

/-- The zone of a frame for zone height `h`: a swipe frame's zone is named after the start of its
`h`-pixel band (floor division, as JS `Math.floor`), any other frame's zone is its phase name.

$$\operatorname{zone}_h(f) = \begin{cases} \texttt{"y"} \cdot \operatorname{pad}_5\big(\operatorname{dec}(\lfloor f.\mathrm{scrollY} / h \rfloor \cdot h)\big) & f.\mathrm{phase} = \texttt{"swipe"} \\ f.\mathrm{phase} & \text{otherwise} \end{cases}\quad(\lfloor y/0 \rfloor := 0,\ \text{so } h = 0 \text{ gives } \texttt{"y00000"})$$
-/
def zoneId (h : Nat) (f : Frame) : String :=
  if f.phase = "swipe" then "y" ++ padStart5 (toString (f.scrollY / (h : Int) * (h : Int))) else f.phase

#guard zoneId 500 ⟨0, "swipe", 499, []⟩ == "y00000"
#guard zoneId 500 ⟨0, "swipe", 500, []⟩ == "y00500"
#guard zoneId 500 ⟨0, "swipe", 4626, []⟩ == "y04500"
#guard zoneId 500 ⟨0, "swipe", -1, []⟩ == "y0-500"
#guard zoneId 500 ⟨0, "tail", 4626, []⟩ == "tail"

/-- A frame tagged with its zone and its scroll increment (the internal row of the fold).

$$\mathrm{Tagged} = \Sigma^{*} \times \mathbb{N} \times \mathbb{Z} \times \mathrm{Counts}$$
-/
structure Tagged where
  id : String
  n : Nat
  dy : Int
  counts : Counts
deriving Repr, DecidableEq

/-- Tag every frame with its zone and its scroll increment, starting from scroll position `y`.

$$\operatorname{tag}_h(y, [f_1, \dots, f_m]) = [(\operatorname{zone}_h(f_i),\ f_i.n,\ f_i.\mathrm{scrollY} - y_{i-1},\ f_i.\mathrm{counts})]_{i=1}^{m},\quad y_0 = y,\ y_i = f_i.\mathrm{scrollY}$$
-/
def tag (h : Nat) : Int → List Frame → List Tagged
  | _, [] => []
  | y, f :: fs => ⟨zoneId h f, f.n, f.scrollY - y, f.counts⟩ :: tag h f.scrollY fs

/-- The scroll position after a list of frames, starting from `y`.

$$\operatorname{lastY}(y, [f_1, \dots, f_m]) = \begin{cases} y & m = 0 \\ f_m.\mathrm{scrollY} & m \ge 1 \end{cases}$$
-/
def lastY : Int → List Frame → Int
  | y, [] => y
  | _, f :: fs => lastY f.scrollY fs

/-! ## Order of first appearance, sorted keys -/

/-- The distinct strings of a list in order of first appearance.

$$\operatorname{firstSeen}(L) = [\,x \in L \text{ at its first occurrence}\,]$$
-/
def firstSeen (l : List String) : List String :=
  l.foldl (fun acc x => if x ∈ acc then acc else acc ++ [x]) []

#guard firstSeen ["a", "b", "a", "c", "b"] == ["a", "b", "c"]

/-- Insert a key into a sorted key list, keeping it sorted and without duplicates.

$$\operatorname{ins}(k, [\,]) = [k],\quad \operatorname{ins}(k, x :: xs) = \begin{cases} k :: x :: xs & k < x \\ x :: xs & k = x \\ x :: \operatorname{ins}(k, xs) & \text{otherwise} \end{cases}$$ so that $$\operatorname{ins}(k, L) = \operatorname{sort}(\{k\} \cup L) \text{ for strictly increasing } L$$
-/
def insKey (k : String) : List String → List String
  | [] => [k]
  | x :: xs => if k < x then k :: x :: xs else if k = x then x :: xs else x :: insKey k xs

/-- The sorted distinct count names occurring in a list of count lists.

$$\operatorname{keys}(C_1, \dots, C_m) = \operatorname{sort}\{\, j \mid \exists i, v:\ (j, v) \in C_i \,\}$$
-/
def keysOf : List Counts → List String
  | [] => []
  | cs :: css => cs.foldr (fun p acc => insKey p.1 acc) (keysOf css)

#guard keysOf [[("b", 1), ("a", 2)], [("c", 0), ("a", 5)]] == ["a", "b", "c"]

/-! ## Zones -/

/-- One zone of the output: name, number of frames, scrolled pixels, first and last frame number,
and the sum per count type.

$$\mathrm{Zone} = \Sigma^{*} \times \mathbb{N} \times \mathbb{Z} \times \mathbb{N} \times \mathbb{N} \times (\Sigma^{*} \times \mathbb{Z})^{*}$$
-/
structure Zone where
  id : String
  frames : Nat
  scrolledPx : Int
  firstFrame : Nat
  lastFrame : Nat
  sums : List (String × Int)
deriving Repr, DecidableEq

/-- The rows of zone `Z`.

$$\operatorname{rows}(R, Z) = [\, r \in R \mid r.\mathrm{id} = Z \,]$$
-/
def rowsOf (rs : List Tagged) (Z : String) : List Tagged := rs.filter (·.id == Z)

/-- The zone record of `Z` built from tagged rows `R` (first/last frame default to 0 for a zone
with no rows, which never occurs in the output).

$$\operatorname{zoneOf}(R, Z) = \Big(Z,\ |F|,\ \sum_{r \in F} r.dy,\ \operatorname{head}(F).n,\ \operatorname{last}(F).n,\ \big[(k, \textstyle\sum_{r \in F} \operatorname{countIn}(r.\mathrm{counts}, k))\big]_{k \in \operatorname{keys}(F)}\Big),\quad F = \operatorname{rows}(R, Z)$$
-/
def zoneOf (rs : List Tagged) (Z : String) : Zone :=
  let fs := rowsOf rs Z
  { id := Z, frames := fs.length, scrolledPx := sumBy (·.dy) fs,
    firstFrame := (fs.head?.map (·.n)).getD 0, lastFrame := (fs.getLast?.map (·.n)).getD 0,
    sums := (keysOf (fs.map (·.counts))).map fun k => (k, sumBy (fun r => countIn r.counts k) fs) }

/-- Per-zone sums, with the scroll distance measured from scroll position `y₀`.

$$\operatorname{zoneSums}_h(y_0, F) = [\operatorname{zoneOf}(R, Z)]_{Z \in \operatorname{firstSeen}(R.\mathrm{id})},\quad R = \operatorname{tag}_h(y_0, F)$$
-/
def zoneSumsFrom (h : Nat) (y₀ : Int) (fs : List Frame) : List Zone :=
  let rs := tag h y₀ fs
  (firstSeen (rs.map (·.id))).map (zoneOf rs)

/-- Per-zone sums of a run (`reduce.mjs` `zoneSums(frames, h)`): the scroll distance of the first
frame is measured from 0.

$$\operatorname{zoneSums}_h(F) = \operatorname{zoneSums}_h(0, F)$$
-/
def zoneSums (h : Nat) (fs : List Frame) : List Zone := zoneSumsFrom h 0 fs

/-- The sum of count type `k` in a zone record (0 if the zone does not list `k`).

$$\operatorname{sum}(z, k) = \begin{cases} v & (k, v) \text{ is the first entry named } k \text{ in } z.\mathrm{sums} \\ 0 & \text{none} \end{cases}$$
-/
def Zone.sum (z : Zone) (k : String) : Int := (z.sums.lookup k).getD 0

/-- Look up zone `Z` in a zone list (the first one with that id).

$$\operatorname{find}(Zs, Z) = \text{the first } z \in Zs \text{ with } z.\mathrm{id} = Z, \text{ if any}$$
-/
def findZone (zs : List Zone) (Z : String) : Option Zone := zs.find? (·.id == Z)

/-- The sum of count type `k` in zone `Z` of a zone list (0 if there is no such zone).

$$\operatorname{sumAt}(Zs, Z, k) = \begin{cases} \operatorname{sum}(z, k) & \operatorname{find}(Zs, Z) = z \\ 0 & \text{none} \end{cases}$$
-/
def sumAt (zs : List Zone) (Z k : String) : Int := ((findZone zs Z).map (·.sum k)).getD 0

/-- The number of frames of zone `Z` in a zone list (0 if there is no such zone).

$$\operatorname{framesAt}(Zs, Z) = \begin{cases} z.\mathrm{frames} & \operatorname{find}(Zs, Z) = z \\ 0 & \text{none} \end{cases}$$
-/
def framesAt (zs : List Zone) (Z : String) : Nat := ((findZone zs Z).map (·.frames)).getD 0

/-- The scrolled pixels of zone `Z` in a zone list (0 if there is no such zone).

$$\operatorname{scrolledAt}(Zs, Z) = \begin{cases} z.\mathrm{scrolledPx} & \operatorname{find}(Zs, Z) = z \\ 0 & \text{none} \end{cases}$$
-/
def scrolledAt (zs : List Zone) (Z : String) : Int := ((findZone zs Z).map (·.scrolledPx)).getD 0

/-- The seed vector of `test/pure.test.mjs`. -/
private def seed : List Frame :=
  [⟨0, "rest", 0, [("a", 1), ("b", 2)]⟩, ⟨1, "swipe", 10, [("a", 1), ("b", 0)]⟩,
   ⟨2, "swipe", 490, [("a", 2), ("b", 1)]⟩, ⟨3, "swipe", 500, [("a", 4), ("b", 1)]⟩,
   ⟨4, "tail", 500, [("a", 0), ("b", 7)]⟩]

#guard (zoneSums 500 seed).map (·.id) == ["rest", "y00000", "y00500", "tail"]
#guard (zoneSums 500 seed).map (·.frames) == [1, 2, 1, 1]
#guard (zoneSums 500 seed).map (·.scrolledPx) == [0, 490, 10, 0]
#guard (zoneSums 500 seed).map (·.sums) ==
  [[("a", 1), ("b", 2)], [("a", 3), ("b", 1)], [("a", 4), ("b", 1)], [("a", 0), ("b", 7)]]
#guard (zoneSums 500 seed).map (fun z => (z.firstFrame, z.lastFrame)) == [(0, 0), (1, 2), (3, 3), (4, 4)]
#guard sumBy (·.sum "a") (zoneSums 500 seed) == 8
#guard zoneSums 500 [] == []

/-! ## Lemmas -/

/-- A sum over a concatenation is the sum of the two sums.

$$\forall g, A, B:\ \operatorname{sumBy}(g, A \mathbin{+\!\!+} B) = \operatorname{sumBy}(g, A) + \operatorname{sumBy}(g, B)$$
-/
theorem sumBy_append {α : Type} (g : α → Int) (a b : List α) :
    sumBy g (a ++ b) = sumBy g a + sumBy g b := by
  induction a with
  | nil => simp [sumBy]
  | cons x xs ih => simp only [List.cons_append, sumBy, ih]; omega

/-- Summing zeros gives zero.

$$\forall L:\ \sum_{x \in L} 0 = 0$$
-/
theorem sumBy_zero {α : Type} : ∀ l : List α, sumBy (fun _ => (0 : Int)) l = 0
  | [] => rfl
  | _ :: xs => by simp [sumBy, sumBy_zero xs]

/-- Sums of functions that agree on the list are equal.

$$\forall g, g', L:\ (\forall x \in L:\ g(x) = g'(x)) \;\Rightarrow\; \sum_{x \in L} g(x) = \sum_{x \in L} g'(x)$$
-/
theorem sumBy_congr {α : Type} {g g' : α → Int} :
    ∀ {l : List α}, (∀ x ∈ l, g x = g' x) → sumBy g l = sumBy g' l
  | [], _ => rfl
  | x :: xs, h => by
    simp only [sumBy]
    rw [h x (by simp), sumBy_congr (fun y hy => h y (by simp [hy]))]

/-- Sums are monotone in the summand.

$$\forall g, g', L:\ (\forall x \in L:\ g(x) \le g'(x)) \;\Rightarrow\; \sum_{x \in L} g(x) \le \sum_{x \in L} g'(x)$$
-/
theorem sumBy_mono {α : Type} {g g' : α → Int} :
    ∀ {l : List α}, (∀ x ∈ l, g x ≤ g' x) → sumBy g l ≤ sumBy g' l
  | [], _ => Int.le_refl 0
  | x :: xs, h => by
    simp only [sumBy]
    have h1 := h x (by simp)
    have h2 := sumBy_mono (l := xs) (fun y hy => h y (by simp [hy]))
    omega

/-- A sum of non-negative terms is non-negative.

$$\forall g, L:\ (\forall x \in L:\ 0 \le g(x)) \;\Rightarrow\; 0 \le \sum_{x \in L} g(x)$$
-/
theorem sumBy_nonneg {α : Type} {g : α → Int} :
    ∀ {l : List α}, (∀ x ∈ l, 0 ≤ g x) → 0 ≤ sumBy g l
  | [], _ => Int.le_refl 0
  | x :: xs, h => by
    simp only [sumBy]
    have h1 := h x (by simp)
    have h2 := sumBy_nonneg (l := xs) (fun y hy => h y (by simp [hy]))
    omega

/-- Summing over a mapped list is summing the composite.

$$\forall g, f, L:\ \sum_{y \in [f(x)]_{x \in L}} g(y) = \sum_{x \in L} g(f(x))$$
-/
theorem sumBy_map {α β : Type} (g : β → Int) (f : α → β) :
    ∀ l : List α, sumBy g (l.map f) = sumBy (g ∘ f) l
  | [] => rfl
  | x :: xs => by simp [sumBy, sumBy_map g f xs]

/-- Summing ones counts the elements.

$$\forall L:\ \sum_{x \in L} 1 = |L|$$
-/
theorem sumBy_one {α : Type} : ∀ l : List α, sumBy (fun _ => (1 : Int)) l = l.length
  | [] => rfl
  | _ :: xs => by simp only [sumBy, sumBy_one xs, List.length_cons]; omega

/-- Tagging a concatenation tags the second part from where the first part ended.

$$\forall h, y, A, B:\ \operatorname{tag}_h(y, A \mathbin{+\!\!+} B) = \operatorname{tag}_h(y, A) \mathbin{+\!\!+} \operatorname{tag}_h(\operatorname{lastY}(y, A), B)$$
-/
theorem tag_append (h : Nat) :
    ∀ (y : Int) (a b : List Frame), tag h y (a ++ b) = tag h y a ++ tag h (lastY y a) b
  | _, [], _ => rfl
  | _, f :: fs, b => by simp [tag, lastY, tag_append h f.scrollY fs b]

/-- The zones of the tagged rows are the zones of the frames.

$$\forall h, y, F:\ [r.\mathrm{id}]_{r \in \operatorname{tag}_h(y, F)} = [\operatorname{zone}_h(f)]_{f \in F}$$
-/
theorem tag_ids (h : Nat) : ∀ (y : Int) (fs : List Frame),
    (tag h y fs).map (·.id) = fs.map (zoneId h)
  | _, [] => rfl
  | _, f :: fs => by simp [tag, tag_ids h f.scrollY fs]

/-- Rows of a zone, read back as frames: count sums do not depend on the scroll start.

$$\forall h, y, F, Z, k:\ \sum_{r \in \operatorname{rows}(\operatorname{tag}_h(y, F), Z)} \operatorname{countIn}(r.\mathrm{counts}, k) = \sum_{f \in F,\ \operatorname{zone}_h(f) = Z} c_f(k)$$
-/
theorem sumBy_rows_tag (h : Nat) (Z k : String) : ∀ (y : Int) (fs : List Frame),
    sumBy (fun r => countIn r.counts k) (rowsOf (tag h y fs) Z) =
      sumBy (fun f => f.count k) (fs.filter (zoneId h · == Z))
  | _, [] => rfl
  | _, f :: fs => by
    have ih := sumBy_rows_tag h Z k f.scrollY fs
    simp only [rowsOf] at ih ⊢
    simp only [tag, List.filter_cons]
    split <;> simp_all [sumBy, Frame.count]

/-- A zone has as many tagged rows as frames.

$$\forall h, y, F, Z:\ |\operatorname{rows}(\operatorname{tag}_h(y, F), Z)| = \big|[\, f \in F \mid \operatorname{zone}_h(f) = Z \,]\big|$$

(A list filter: repeated frames are counted each time.)
-/
theorem length_rows_tag (h : Nat) (Z : String) : ∀ (y : Int) (fs : List Frame),
    (rowsOf (tag h y fs) Z).length = (fs.filter (zoneId h · == Z)).length
  | _, [] => rfl
  | _, f :: fs => by
    have ih := length_rows_tag h Z f.scrollY fs
    simp only [rowsOf] at ih ⊢
    simp only [tag, List.filter_cons]
    split <;> simp_all

/-- Inserting a key adds exactly that key.

$$\forall k, x, L:\ x \in \operatorname{ins}(k, L) \iff x = k \lor x \in L$$
-/
theorem mem_insKey (k x : String) : ∀ l : List String, x ∈ insKey k l ↔ x = k ∨ x ∈ l
  | [] => by simp [insKey]
  | y :: ys => by
    unfold insKey
    split
    · simp
    · split
      · rename_i he; subst he; simp only [List.mem_cons]; constructor
        · intro h; exact Or.inr h
        · intro h; rcases h with h | h
          · exact Or.inl h
          · exact h
      · have := mem_insKey k x ys
        simp only [List.mem_cons, this]
        constructor <;> intro h <;> rcases h with h | h | h <;> simp [h]

/-- A name not among the inserted keys has count 0 and was not in the start list.

$$\forall k, C, A:\ k \notin \operatorname{foldr}(\operatorname{ins} \circ \pi_1, A, C) \;\Rightarrow\; \operatorname{countIn}(C, k) = 0 \land k \notin A$$
-/
theorem countIn_eq_zero_of_not_mem_foldr (k : String) :
    ∀ (cs : Counts) (acc : List String), k ∉ cs.foldr (fun p a => insKey p.1 a) acc →
      countIn cs k = 0 ∧ k ∉ acc
  | [], _, h => ⟨rfl, h⟩
  | (j, v) :: cs, acc, h => by
    simp only [List.foldr_cons, mem_insKey, not_or] at h
    obtain ⟨h1, h2⟩ := countIn_eq_zero_of_not_mem_foldr k cs acc h.2
    refine ⟨?_, h2⟩
    simp only [countIn, h1]
    have : ¬ j = k := fun e => h.1 e.symm
    simp [this]

/-- A count type that is not among the keys of a list of rows sums to 0 over those rows.

$$\forall k, R:\ k \notin \operatorname{keys}([r.\mathrm{counts}]_{r \in R}) \;\Rightarrow\; \sum_{r \in R} \operatorname{countIn}(r.\mathrm{counts}, k) = 0$$
-/
theorem sumBy_eq_zero_of_not_mem_keys (k : String) :
    ∀ fs : List Tagged, k ∉ keysOf (fs.map (·.counts)) → sumBy (fun r => countIn r.counts k) fs = 0
  | [], _ => rfl
  | r :: rs, h => by
    simp only [List.map_cons, keysOf] at h
    obtain ⟨h1, h2⟩ := countIn_eq_zero_of_not_mem_foldr k r.counts _ h
    simp [sumBy, h1, sumBy_eq_zero_of_not_mem_keys k rs h2]

/-- Looking up a key in a key-value list built from a key list.

$$\forall g, k, K:\ \operatorname{lookup}(k, [(j, g(j))]_{j \in K}) = \begin{cases} g(k) & k \in K \\ \bot & k \notin K \end{cases}$$
-/
theorem lookup_map_keys (g : String → Int) (k : String) : ∀ ks : List String,
    (ks.map (fun j => (j, g j))).lookup k = if k ∈ ks then some (g k) else none
  | [] => by simp
  | j :: js => by
    simp only [List.map_cons, List.lookup_cons, List.mem_cons]
    by_cases hj : k = j
    · subst hj; simp
    · have : (k == j) = false := by simp [hj]
      simp [this, hj, lookup_map_keys g k js]

/-- The sum of `k` in the record of zone `Z` is the sum of `k` over the rows of `Z`.

$$\forall R, Z, k:\ \operatorname{sum}(\operatorname{zoneOf}(R, Z), k) = \sum_{r \in \operatorname{rows}(R, Z)} \operatorname{countIn}(r.\mathrm{counts}, k)$$
-/
theorem zoneOf_sum (rs : List Tagged) (Z k : String) :
    (zoneOf rs Z).sum k = sumBy (fun r => countIn r.counts k) (rowsOf rs Z) := by
  simp only [Zone.sum, zoneOf, lookup_map_keys]
  split
  · rfl
  · rename_i hk; simp [sumBy_eq_zero_of_not_mem_keys k _ hk]

/-- Finding zone `Z` among zone records built from a name list.

$$\forall R, Z, L:\ \operatorname{find}([\operatorname{zoneOf}(R, j)]_{j \in L}, Z) = \begin{cases} \operatorname{zoneOf}(R, Z) & Z \in L \\ \bot & Z \notin L \end{cases}$$
-/
theorem find_map_zoneOf (rs : List Tagged) (Z : String) : ∀ L : List String,
    findZone (L.map (zoneOf rs)) Z = if Z ∈ L then some (zoneOf rs Z) else none
  | [] => by simp [findZone]
  | j :: js => by
    have ih := find_map_zoneOf rs Z js
    simp only [findZone] at ih ⊢
    simp only [List.map_cons, List.find?_cons, List.mem_cons]
    by_cases hj : j = Z
    · subst hj; simp [zoneOf]
    · have h1 : ((zoneOf rs j).id == Z) = false := by simp [zoneOf, hj]
      have h2 : ¬ Z = j := fun e => hj e.symm
      simp [h1, h2, ih]

/-- The first-appearance fold keeps a duplicate-free accumulator duplicate-free and collects exactly the accumulator and the list.

$$\forall A, L:\ \operatorname{nodup}(A) \;\Rightarrow\; \operatorname{nodup}(\operatorname{fold}(A, L)) \land \forall y:\ \big(y \in \operatorname{fold}(A, L) \iff y \in A \lor y \in L\big),\quad \operatorname{fold}(A, L) = \operatorname{foldl}\big((acc, x) \mapsto (acc \text{ if } x \in acc \text{ else } acc \mathbin{+\!\!+} [x]),\ A,\ L\big)$$
-/
theorem firstSeen_aux (l : List String) : ∀ acc : List String, acc.Nodup →
    (l.foldl (fun acc x => if x ∈ acc then acc else acc ++ [x]) acc).Nodup ∧
    ∀ y, y ∈ l.foldl (fun acc x => if x ∈ acc then acc else acc ++ [x]) acc ↔ y ∈ acc ∨ y ∈ l := by
  induction l with
  | nil => intro acc h; simp [h]
  | cons x xs ih =>
    intro acc hacc
    simp only [List.foldl_cons]
    split
    · rename_i hx
      obtain ⟨h1, h2⟩ := ih acc hacc
      refine ⟨h1, fun y => ?_⟩
      rw [h2]; simp only [List.mem_cons]
      constructor
      · intro h; rcases h with h | h
        · exact Or.inl h
        · exact Or.inr (Or.inr h)
      · intro h; rcases h with h | h | h
        · exact Or.inl h
        · subst h; exact Or.inl hx
        · exact Or.inr h
    · rename_i hx
      have hn : (acc ++ [x]).Nodup := by
        rw [List.nodup_append]
        refine ⟨hacc, by simp, ?_⟩
        intro a ha b hb; simp at hb; subst hb; intro e; subst e; exact hx ha
      obtain ⟨h1, h2⟩ := ih _ hn
      refine ⟨h1, fun y => ?_⟩
      rw [h2]; simp only [List.mem_append, List.mem_cons, List.not_mem_nil, or_false]
      constructor
      · intro h; rcases h with (h | h) | h
        · exact Or.inl h
        · exact Or.inr (Or.inl h)
        · exact Or.inr (Or.inr h)
      · intro h; rcases h with h | h | h
        · exact Or.inl (Or.inl h)
        · exact Or.inl (Or.inr h)
        · exact Or.inr h

/-- `firstSeen` has no duplicates.

$$\forall L:\ \operatorname{nodup}(\operatorname{firstSeen}(L))$$
-/
theorem firstSeen_nodup (l : List String) : (firstSeen l).Nodup :=
  (firstSeen_aux l [] List.nodup_nil).1

/-- `firstSeen` keeps exactly the elements of the list.

$$\forall L, y:\ y \in \operatorname{firstSeen}(L) \iff y \in L$$
-/
theorem mem_firstSeen (l : List String) (y : String) : y ∈ firstSeen l ↔ y ∈ l := by
  have := (firstSeen_aux l [] List.nodup_nil).2 y
  simp only [firstSeen, this, List.not_mem_nil, false_or]

/-- Summing over the zones of a duplicate-free list of names covering every row is summing over the rows.

$$\forall g, R, L:\ \operatorname{nodup}(L) \land (\forall r \in R:\ r.\mathrm{id} \in L) \;\Rightarrow\; \sum_{Z \in L} \sum_{r \in \operatorname{rows}(R, Z)} g(r) = \sum_{r \in R} g(r)$$
-/
theorem sum_partition (g : Tagged → Int) : ∀ (rs : List Tagged) (L : List String), L.Nodup →
    (∀ r ∈ rs, r.id ∈ L) → sumBy (fun Z => sumBy g (rowsOf rs Z)) L = sumBy g rs
  | [], L, _, _ => by
    simp only [rowsOf, List.filter_nil]
    exact sumBy_zero L
  | r :: rs, L, hL, hcov => by
    have ih := sum_partition g rs L hL (fun r' hr' => hcov r' (by simp [hr']))
    have hsplit : ∀ Z, sumBy g (rowsOf (r :: rs) Z) = (if r.id = Z then g r else 0) + sumBy g (rowsOf rs Z) := by
      intro Z; simp only [rowsOf, List.filter_cons]
      by_cases h : r.id = Z <;> simp [h, sumBy]
    rw [sumBy_congr (fun Z _ => hsplit Z)]
    have hadd : ∀ (l : List String), sumBy (fun Z => (if r.id = Z then g r else 0) + sumBy g (rowsOf rs Z)) l =
        sumBy (fun Z => if r.id = Z then g r else 0) l + sumBy (fun Z => sumBy g (rowsOf rs Z)) l := by
      intro l; induction l with
      | nil => rfl
      | cons _ _ ih' => simp only [sumBy, ih']; omega
    rw [hadd, ih]
    have hone : ∀ (l : List String), l.Nodup → r.id ∈ l → sumBy (fun Z => if r.id = Z then g r else 0) l = g r := by
      intro l; induction l with
      | nil => intro _ h; simp at h
      | cons j js ih' =>
        intro hn hm
        rw [List.nodup_cons] at hn
        simp only [sumBy]
        by_cases hj : r.id = j
        · subst hj
          have : sumBy (fun Z => if r.id = Z then g r else 0) js = 0 := by
            have hz : ∀ Z ∈ js, (if r.id = Z then g r else 0) = (fun _ => (0 : Int)) Z := by
              intro Z hZ; have : r.id ≠ Z := fun e => hn.1 (e ▸ hZ); simp [this]
            rw [sumBy_congr hz]; exact sumBy_zero js
          simp [this]
        · simp only [List.mem_cons] at hm
          rcases hm with hm | hm
          · exact absurd hm hj
          · simp [hj, ih' hn.2 hm]
    rw [hone L hL (hcov r (by simp))]
    simp [sumBy]

/-! ## Specification of the lookups -/

/-- A name that no row carries has no rows.

$$\forall R, Z:\ Z \notin [r.\mathrm{id}]_{r \in R} \;\Rightarrow\; \operatorname{rows}(R, Z) = [\,]$$
-/
theorem rowsOf_eq_nil_of_not_mem (rs : List Tagged) (Z : String) (h : Z ∉ rs.map (·.id)) :
    rowsOf rs Z = [] := by
  simp only [rowsOf, List.filter_eq_nil_iff, beq_iff_eq]
  intro r hr e; exact h (List.mem_map.mpr ⟨r, hr, e⟩)

/-- **Zone sums are filter sums.** The sum of count type $k$ that the zone list reports for zone
$Z$ is the sum of $k$ over exactly the frames whose zone is $Z$ (0 when no frame is in $Z$).

$$\forall h, y_0, F, Z, k:\quad \operatorname{sumAt}(\operatorname{zoneSums}_h(y_0, F), Z, k) = \sum_{f \in F,\ \operatorname{zone}_h(f) = Z} c_f(k)$$
-/
theorem sumAt_spec (h : Nat) (y₀ : Int) (fs : List Frame) (Z k : String) :
    sumAt (zoneSumsFrom h y₀ fs) Z k = sumBy (fun f => f.count k) (fs.filter (zoneId h · == Z)) := by
  simp only [sumAt, zoneSumsFrom, find_map_zoneOf, mem_firstSeen]
  split
  · simp [zoneOf_sum, sumBy_rows_tag]
  · rename_i hZ
    have := sumBy_rows_tag h Z k y₀ fs
    rw [rowsOf_eq_nil_of_not_mem _ _ hZ] at this
    simp [← this, sumBy]

/-- **Zone frame counts are filter lengths.** The number of frames reported for zone $Z$ is the
number of frames whose zone is $Z$.

$$\forall h, y_0, F, Z:\quad \operatorname{framesAt}(\operatorname{zoneSums}_h(y_0, F), Z) = \big|[\, f \in F \mid \operatorname{zone}_h(f) = Z \,]\big|$$

(A list filter: repeated frames are counted each time.)
-/
theorem framesAt_spec (h : Nat) (y₀ : Int) (fs : List Frame) (Z : String) :
    framesAt (zoneSumsFrom h y₀ fs) Z = (fs.filter (zoneId h · == Z)).length := by
  simp only [framesAt, zoneSumsFrom, find_map_zoneOf, mem_firstSeen]
  split
  · simp [zoneOf, length_rows_tag]
  · rename_i hZ
    have := length_rows_tag h Z y₀ fs
    rw [rowsOf_eq_nil_of_not_mem _ _ hZ] at this
    simp [← this]

/-- **Zone scroll distances are filter sums of increments.** The scrolled pixels reported for zone
$Z$ are the sum, over the frames of $Z$, of each frame's scroll position minus the previous
frame's (the first frame's predecessor position is $y_0$).

$$\forall h, y_0, F, Z:\quad \operatorname{scrolledAt}(\operatorname{zoneSums}_h(y_0, F), Z) = \sum_{r \in \operatorname{tag}_h(y_0, F),\ r.\mathrm{id} = Z} r.dy$$
-/
theorem scrolledAt_spec (h : Nat) (y₀ : Int) (fs : List Frame) (Z : String) :
    scrolledAt (zoneSumsFrom h y₀ fs) Z = sumBy (·.dy) (rowsOf (tag h y₀ fs) Z) := by
  simp only [scrolledAt, zoneSumsFrom, find_map_zoneOf, mem_firstSeen]
  split
  · simp [zoneOf]
  · rename_i hZ
    simp [rowsOf_eq_nil_of_not_mem _ _ hZ, sumBy]

/-! ## Additivity over concatenation -/

/-- **Additivity of sums.** Zone sums of a concatenation are the zone sums of the two parts added,
zone by zone and type by type (whatever the scroll starts).

$$\forall h, y_0, y_1, y_2, A, B, Z, k:\quad \operatorname{sumAt}(\operatorname{zoneSums}_h(y_0, A \mathbin{+\!\!+} B), Z, k) = \operatorname{sumAt}(\operatorname{zoneSums}_h(y_1, A), Z, k) + \operatorname{sumAt}(\operatorname{zoneSums}_h(y_2, B), Z, k)$$
-/
theorem sumAt_append (h : Nat) (y₀ y₁ y₂ : Int) (a b : List Frame) (Z k : String) :
    sumAt (zoneSumsFrom h y₀ (a ++ b)) Z k =
      sumAt (zoneSumsFrom h y₁ a) Z k + sumAt (zoneSumsFrom h y₂ b) Z k := by
  simp only [sumAt_spec, List.filter_append, sumBy_append]

/-- **Additivity of frame counts.** The frames of a zone in a concatenation are the frames of that
zone in the two parts added.

$$\forall h, y_0, y_1, y_2, A, B, Z:\quad \operatorname{framesAt}(\operatorname{zoneSums}_h(y_0, A \mathbin{+\!\!+} B), Z) = \operatorname{framesAt}(\operatorname{zoneSums}_h(y_1, A), Z) + \operatorname{framesAt}(\operatorname{zoneSums}_h(y_2, B), Z)$$
-/
theorem framesAt_append (h : Nat) (y₀ y₁ y₂ : Int) (a b : List Frame) (Z : String) :
    framesAt (zoneSumsFrom h y₀ (a ++ b)) Z =
      framesAt (zoneSumsFrom h y₁ a) Z + framesAt (zoneSumsFrom h y₂ b) Z := by
  simp only [framesAt_spec, List.filter_append, List.length_append]

/-- **Additivity of scroll distances.** The scrolled pixels of a zone in a concatenation are those
of the first part plus those of the second part measured from where the first part ended.

$$\forall h, y_0, A, B, Z:\quad \operatorname{scrolledAt}(\operatorname{zoneSums}_h(y_0, A \mathbin{+\!\!+} B), Z) = \operatorname{scrolledAt}(\operatorname{zoneSums}_h(y_0, A), Z) + \operatorname{scrolledAt}(\operatorname{zoneSums}_h(\operatorname{lastY}(y_0, A), B), Z)$$
-/
theorem scrolledAt_append (h : Nat) (y₀ : Int) (a b : List Frame) (Z : String) :
    scrolledAt (zoneSumsFrom h y₀ (a ++ b)) Z =
      scrolledAt (zoneSumsFrom h y₀ a) Z + scrolledAt (zoneSumsFrom h (lastY y₀ a) b) Z := by
  simp only [scrolledAt_spec, tag_append, rowsOf, List.filter_append, sumBy_append]

/-! ## Monotonicity -/

/-- Two frame lists that agree frame by frame on the zone and where the first's value of `k` is at
most the second's.

$$\operatorname{below}_{h,k}(F, G) \iff |F| = |G| \ \land\ \forall i:\ \operatorname{zone}_h(F_i) = \operatorname{zone}_h(G_i) \ \land\ c_{F_i}(k) \le c_{G_i}(k)$$
-/
def Below (h : Nat) (k : String) : List Frame → List Frame → Prop
  | [], [] => True
  | f :: fs, g :: gs => zoneId h f = zoneId h g ∧ f.count k ≤ g.count k ∧ Below h k fs gs
  | _, _ => False

/-- Filter sums are monotone under `below`.

$$\forall h, k, Z, F, G:\ \operatorname{below}_{h,k}(F, G) \;\Rightarrow\; \sum_{f \in F,\ \operatorname{zone}_h(f) = Z} c_f(k) \le \sum_{g \in G,\ \operatorname{zone}_h(g) = Z} c_g(k)$$
-/
theorem sumBy_filter_below (h : Nat) (k Z : String) : ∀ fs gs : List Frame, Below h k fs gs →
    sumBy (fun f => f.count k) (fs.filter (zoneId h · == Z)) ≤
      sumBy (fun f => f.count k) (gs.filter (zoneId h · == Z))
  | [], [], _ => Int.le_refl 0
  | [], _ :: _, hb => by simp [Below] at hb
  | _ :: _, [], hb => by simp [Below] at hb
  | f :: fs, g :: gs, hb => by
    simp only [Below] at hb
    obtain ⟨hz, hc, hr⟩ := hb
    have ih := sumBy_filter_below h k Z fs gs hr
    simp only [List.filter_cons, hz]
    split
    · simp only [sumBy]; omega
    · exact ih

/-- **Monotonicity in the counts.** Raising the value of one count type in some frames, without
changing any frame's zone, never lowers that type's sum in any zone.

$$\forall h, y_0, y_1, F, G, Z, k:\quad \operatorname{below}_{h,k}(F, G) \;\Rightarrow\; \operatorname{sumAt}(\operatorname{zoneSums}_h(y_0, F), Z, k) \le \operatorname{sumAt}(\operatorname{zoneSums}_h(y_1, G), Z, k)$$
-/
theorem sumAt_mono (h : Nat) (y₀ y₁ : Int) (fs gs : List Frame) (Z k : String)
    (hb : Below h k fs gs) :
    sumAt (zoneSumsFrom h y₀ fs) Z k ≤ sumAt (zoneSumsFrom h y₁ gs) Z k := by
  simp only [sumAt_spec]; exact sumBy_filter_below h k Z fs gs hb

/-- **Monotonicity in the frames.** Appending frames whose values of `k` are non-negative never
lowers the sum of `k` in any zone.

$$\forall h, y_0, y_1, A, B, Z, k:\quad (\forall f \in B:\ c_f(k) \ge 0) \;\Rightarrow\; \operatorname{sumAt}(\operatorname{zoneSums}_h(y_1, A), Z, k) \le \operatorname{sumAt}(\operatorname{zoneSums}_h(y_0, A \mathbin{+\!\!+} B), Z, k)$$
-/
theorem sumAt_le_append (h : Nat) (y₀ y₁ : Int) (a b : List Frame) (Z k : String)
    (hb : ∀ f ∈ b, 0 ≤ f.count k) :
    sumAt (zoneSumsFrom h y₁ a) Z k ≤ sumAt (zoneSumsFrom h y₀ (a ++ b)) Z k := by
  rw [sumAt_append h y₀ y₁ 0]
  have : 0 ≤ sumAt (zoneSumsFrom h 0 b) Z k := by
    rw [sumAt_spec]; exact sumBy_nonneg (fun f hf => hb f (List.mem_filter.mp hf).1)
  omega

/-! ## Partition -/

/-- The zone names of the output.

$$\operatorname{ids}(Zs) = [z.\mathrm{id}]_{z \in Zs}$$
-/
def zoneIds (zs : List Zone) : List String := zs.map (·.id)

/-- The output's zone names are the frames' zones in order of first appearance.

$$\forall h, y_0, F:\ \operatorname{ids}(\operatorname{zoneSums}_h(y_0, F)) = \operatorname{firstSeen}([\operatorname{zone}_h(f)]_{f \in F})$$
-/
theorem zoneIds_zoneSumsFrom (h : Nat) (y₀ : Int) (fs : List Frame) :
    zoneIds (zoneSumsFrom h y₀ fs) = firstSeen (fs.map (zoneId h)) := by
  simp only [zoneIds, zoneSumsFrom, List.map_map, tag_ids]
  have : (Zone.id ∘ zoneOf (tag h y₀ fs)) = id := by funext Z; simp [zoneOf]
  simp [this]

/-- **Each zone is listed once.** The output names no zone twice.

$$\forall h, y_0, F:\quad \operatorname{ids}(\operatorname{zoneSums}_h(y_0, F)) \text{ has no duplicates}$$
-/
theorem zoneIds_nodup (h : Nat) (y₀ : Int) (fs : List Frame) : (zoneIds (zoneSumsFrom h y₀ fs)).Nodup := by
  rw [zoneIds_zoneSumsFrom]; exact firstSeen_nodup _

/-- **Exactly the occupied zones are listed.** A name is a zone of the output if and only if some
frame lies in that zone.

$$\forall h, y_0, F, Z:\quad Z \in \operatorname{ids}(\operatorname{zoneSums}_h(y_0, F)) \iff \exists f \in F:\ \operatorname{zone}_h(f) = Z$$
-/
theorem mem_zoneIds (h : Nat) (y₀ : Int) (fs : List Frame) (Z : String) :
    Z ∈ zoneIds (zoneSumsFrom h y₀ fs) ↔ ∃ f ∈ fs, zoneId h f = Z := by
  rw [zoneIds_zoneSumsFrom, mem_firstSeen, List.mem_map]

/-- A sum over the output zones is a sum over their names.

$$\forall h, y_0, F, g:\ \sum_{z \in \operatorname{zoneSums}_h(y_0, F)} g(z) = \sum_{Z \in \operatorname{firstSeen}(R.\mathrm{id})} g(\operatorname{zoneOf}(R, Z)),\quad R = \operatorname{tag}_h(y_0, F)$$
-/
theorem sumBy_zones (h : Nat) (y₀ : Int) (fs : List Frame) (g : Zone → Int) :
    sumBy g (zoneSumsFrom h y₀ fs) =
      sumBy (fun Z => g (zoneOf (tag h y₀ fs) Z)) (firstSeen ((tag h y₀ fs).map (·.id))) := by
  simp only [zoneSumsFrom, sumBy_map]; rfl

/-- Every tagged row's zone is among the output names.

$$\forall h, y_0, F,\ \forall r \in R:\ r.\mathrm{id} \in \operatorname{firstSeen}(R.\mathrm{id}),\quad R = \operatorname{tag}_h(y_0, F)$$
-/
theorem cover_tag (h : Nat) (y₀ : Int) (fs : List Frame) :
    ∀ r ∈ tag h y₀ fs, r.id ∈ firstSeen ((tag h y₀ fs).map (·.id)) := by
  intro r hr; rw [mem_firstSeen]; exact List.mem_map.mpr ⟨r, hr, rfl⟩

/-- Tagging keeps the count totals.

$$\forall k, h, y, F:\ \sum_{r \in \operatorname{tag}_h(y, F)} \operatorname{countIn}(r.\mathrm{counts}, k) = \sum_{f \in F} c_f(k)$$
-/
theorem sumBy_tag_counts (k : String) : ∀ (h : Nat) (y : Int) (fs : List Frame),
    sumBy (fun r => countIn r.counts k) (tag h y fs) = sumBy (fun f => f.count k) fs
  | _, _, [] => rfl
  | h, _, f :: fs => by simp [tag, sumBy, Frame.count, sumBy_tag_counts k h f.scrollY fs]

/-- The scroll increments telescope to the final position minus the start.

$$\forall h, y, F:\ \sum_{r \in \operatorname{tag}_h(y, F)} r.dy = \operatorname{lastY}(y, F) - y$$
-/
theorem sumBy_tag_dy : ∀ (h : Nat) (y : Int) (fs : List Frame),
    sumBy (·.dy) (tag h y fs) = lastY y fs - y
  | _, _, [] => by simp [tag, sumBy, lastY]
  | h, y, f :: fs => by
    simp only [tag, sumBy, lastY, sumBy_tag_dy h f.scrollY fs]; omega

/-- Tagging keeps the number of frames.

$$\forall h, y, F:\ |\operatorname{tag}_h(y, F)| = |F|$$
-/
theorem length_tag : ∀ (h : Nat) (y : Int) (fs : List Frame), (tag h y fs).length = fs.length
  | _, _, [] => rfl
  | h, _, f :: fs => by simp [tag, length_tag h f.scrollY fs]

/-- **Partition of the sums.** For every count type, the zone sums add up to the run total.

$$\forall h, y_0, F, k:\quad \sum_{z \in \operatorname{zoneSums}_h(y_0, F)} \operatorname{sum}(z, k) = \sum_{f \in F} c_f(k)$$
-/
theorem zones_sum_total (h : Nat) (y₀ : Int) (fs : List Frame) (k : String) :
    sumBy (·.sum k) (zoneSumsFrom h y₀ fs) = sumBy (fun f => f.count k) fs := by
  rw [sumBy_zones]
  simp only [zoneOf_sum]
  rw [sum_partition _ _ _ (firstSeen_nodup _) (cover_tag h y₀ fs), sumBy_tag_counts]

/-- **Partition of the frames.** The zone frame counts add up to the number of frames.

$$\forall h, y_0, F:\quad \sum_{z \in \operatorname{zoneSums}_h(y_0, F)} z.\mathrm{frames} = |F|$$
-/
theorem zones_frames_total (h : Nat) (y₀ : Int) (fs : List Frame) :
    sumBy (fun z => (z.frames : Int)) (zoneSumsFrom h y₀ fs) = fs.length := by
  rw [sumBy_zones]
  have : ∀ Z, ((zoneOf (tag h y₀ fs) Z).frames : Int) = sumBy (fun _ => (1 : Int)) (rowsOf (tag h y₀ fs) Z) := by
    intro Z; simp [zoneOf, sumBy_one]
  simp only [this]
  rw [sum_partition _ _ _ (firstSeen_nodup _) (cover_tag h y₀ fs), sumBy_one, length_tag]

/-- **Partition of the scroll distance.** The zone scroll distances add up to the final scroll
position minus the starting one (from 0 for `zoneSums`: the final scroll position).

$$\forall h, y_0, F:\quad \sum_{z \in \operatorname{zoneSums}_h(y_0, F)} z.\mathrm{scrolledPx} = \operatorname{lastY}(y_0, F) - y_0$$
-/
theorem zones_scrolled_total (h : Nat) (y₀ : Int) (fs : List Frame) :
    sumBy (·.scrolledPx) (zoneSumsFrom h y₀ fs) = lastY y₀ fs - y₀ := by
  rw [sumBy_zones]
  have : ∀ Z, (zoneOf (tag h y₀ fs) Z).scrolledPx = sumBy (·.dy) (rowsOf (tag h y₀ fs) Z) := by
    intro Z; simp [zoneOf]
  simp only [this]
  rw [sum_partition _ _ _ (firstSeen_nodup _) (cover_tag h y₀ fs), sumBy_tag_dy]

end Fw.Measure
