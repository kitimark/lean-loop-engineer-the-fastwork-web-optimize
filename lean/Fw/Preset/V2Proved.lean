/-!
# The `v2-proved` arm

Decides which registered flags enter the `v2-proved` preset: a flag enters when its linked findings-ledger rows say
`proved` and no row reports a falsified F-result (`fResult = model-bug`), at most one variant per part (the first in
`links` order). Inputs are parsed from `research/findings/ledger.json` and the `part.json` files by `Fw.Preset.Gen`.
-/
namespace Fw.Preset

/-- A flag: a part id and one of its variants.

$$\mathrm{Flag} = \mathrm{String} \times \mathrm{String}$$ -/
structure Flag where
  part : String
  variant : String
deriving DecidableEq, Repr, Inhabited

/-- The URL form `part:variant`.

$$\operatorname{key}(p, v) = p \mathbin{+\!\!+} \texttt{":"} \mathbin{+\!\!+} v$$ -/
def Flag.key (f : Flag) : String := f.part ++ ":" ++ f.variant

/-- The kind of a registered variant (`part.json` `kind`).

$$\mathrm{Kind} = \{\mathrm{faithful}, \mathrm{optimized}, \mathrm{ablation}, \mathrm{proposal}\}$$ -/
inductive Kind where
  | faithful
  | optimized
  | ablation
  | proposal
deriving DecidableEq, Repr

/-- One registered variant with its `requires` and `conflicts` lists.

$$\mathrm{Reg} = \mathrm{Flag} \times \mathrm{Kind} \times \mathrm{List}\ \mathrm{Flag} \times \mathrm{List}\ \mathrm{Flag}$$ -/
structure Reg where
  flag : Flag
  kind : Kind
  requires : List Flag
  conflicts : List Flag
deriving Repr

/-- The combined `fw engine-check` verdict a ledger row records for its flag (`fResult`).

$$\mathrm{FRes} = \{\mathrm{pass}, \mathrm{unusable}, \mathrm{modelBug}\}$$ -/
inductive FRes where
  | pass
  | unusable
  | modelBug
deriving DecidableEq, Repr

/-- The fields of a findings-ledger row this module reads; `flag` and `fResult` are optional in the ledger.

$$\mathrm{Row} = \mathrm{String}^3 \times \mathrm{Option}\ \mathrm{String} \times \mathrm{Option}\ \mathrm{FRes}$$ -/
structure Row where
  part : String
  candidate : String
  status : String
  flag : Option String
  fResult : Option FRes
deriving Repr

/-- A ledger row's identity: its `part` and `candidate` text.

$$\mathrm{Key} = \mathrm{String} \times \mathrm{String}$$ -/
abbrev Key := String × String

/-- The rows of the ledger with key $k$, in ledger order.

$$\operatorname{rowsOf}(L, k) = [\,r \in L \mid (r.\mathrm{part}, r.\mathrm{candidate}) = k\,]$$ -/
def rowsOf (ledger : List Row) (k : Key) : List Row :=
  ledger.filter fun r => r.part == k.1 && r.candidate == k.2

/-- Why a flag is in the arm or not.

$$\mathrm{Why} = \{\mathrm{proved}, \mathrm{noLink}, \mathrm{falsifiedFlag}\} \cup \{\mathrm{rowCount}(k, n), \mathrm{notProved}(k, s), \mathrm{falsified}(k)\}$$ -/
inductive Why where
  | proved
  | noLink
  | falsifiedFlag
  | rowCount (k : Key) (n : Nat)
  | notProved (k : Key) (status : String)
  | falsified (k : Key)
deriving DecidableEq, Repr

/-- Whether some ledger row names the flag in its `flag` field and reports `model-bug`.

$$\operatorname{falsifiedBy}(L, f) \iff \exists r \in L:\ r.\mathrm{flag} = \operatorname{key}(f) \land r.\mathrm{fResult} = \mathrm{modelBug}$$ -/
def falsifiedBy (ledger : List Row) (f : Flag) : Bool :=
  ledger.any fun r => r.flag == some f.key && r.fResult == some .modelBug

/-- The objection of one linked key, `none` when the key has exactly one row, it says `proved` and it is not
falsified.

$$\operatorname{rowWhy}(L, k) = \begin{cases} \mathrm{notProved}(k, r.\mathrm{status}) & \operatorname{rowsOf}(L, k) = [r],\ r.\mathrm{status} \ne \texttt{"proved"} \\ \mathrm{falsified}(k) & \operatorname{rowsOf}(L, k) = [r],\ r.\mathrm{status} = \texttt{"proved"},\ r.\mathrm{fResult} = \mathrm{modelBug} \\ \bot & \operatorname{rowsOf}(L, k) = [r],\ r.\mathrm{status} = \texttt{"proved"},\ r.\mathrm{fResult} \ne \mathrm{modelBug} \\ \mathrm{rowCount}(k, |\operatorname{rowsOf}(L, k)|) & |\operatorname{rowsOf}(L, k)| \ne 1 \end{cases}$$ -/
def rowWhy (ledger : List Row) (k : Key) : Option Why :=
  match rowsOf ledger k with
  | [r] =>
    if r.status != "proved" then some (.notProved k r.status)
    else if r.fResult == some .modelBug then some (.falsified k) else none
  | rs => some (.rowCount k rs.length)

/-- The ledger keys linked to a flag: the second component of the first link whose flag is $f$.

$$\operatorname{linkOf}(\Lambda, f) = \begin{cases} \kappa & (f, \kappa) \text{ is the first pair of } \Lambda \text{ with flag } f \\ \bot & \text{no pair of } \Lambda \text{ has flag } f \end{cases}$$ -/
def linkOf (links : List (Flag × List Key)) (f : Flag) : Option (List Key) :=
  (links.find? (·.1 == f)).map (·.2)

/-- **Why a flag is or is not proved**: a `model-bug` row naming it first, then a missing or empty link, then the first
objection among its linked keys in link order, else `proved`.

$$\operatorname{why}(\Lambda, L, f) = \begin{cases} \mathrm{falsifiedFlag} & \operatorname{falsifiedBy}(L, f) \\ \mathrm{noLink} & \lnot\operatorname{falsifiedBy}(L, f),\ \operatorname{linkOf}(\Lambda, f) \in \{\bot, []\} \\ w & \lnot\operatorname{falsifiedBy}(L, f),\ \operatorname{linkOf}(\Lambda, f) = \kappa \ne [],\ w \text{ the first } \operatorname{rowWhy}(L, k) \ne \bot \text{ over } k \in \kappa \\ \mathrm{proved} & \lnot\operatorname{falsifiedBy}(L, f),\ \operatorname{linkOf}(\Lambda, f) = \kappa \ne [],\ \forall k \in \kappa:\ \operatorname{rowWhy}(L, k) = \bot \end{cases}$$ -/
def why (links : List (Flag × List Key)) (ledger : List Row) (f : Flag) : Why :=
  if falsifiedBy ledger f then .falsifiedFlag
  else match linkOf links f with
    | none => .noLink
    | some [] => .noLink
    | some ks => (ks.findSome? (rowWhy ledger)).getD .proved

/-- Whether a flag is a registered variant of kind `optimized`.

$$\operatorname{isOpt}(R, f) \iff \exists r \in R:\ r.\mathrm{flag} = f \land r.\mathrm{kind} = \mathrm{optimized}$$ -/
def isOpt (reg : List Reg) (f : Flag) : Bool :=
  reg.any fun r => r.flag == f && r.kind == .optimized

/-- A flag qualifies for the arm: registered as `optimized` and proved.

$$\operatorname{ok}(R, \Lambda, L, f) \iff \operatorname{isOpt}(R, f) \land \operatorname{why}(\Lambda, L, f) = \mathrm{proved}$$ -/
def ok (reg : List Reg) (links : List (Flag × List Key)) (ledger : List Row) (f : Flag) : Bool :=
  isOpt reg f && why links ledger f == .proved

/-- The first flag of a list that satisfies $q$ and belongs to part $p$.

$$\operatorname{firstOk}(q, \ell, p) = \begin{cases} g & g \text{ is the first element of } \ell \text{ with } q(g) \land g.\mathrm{part} = p \\ \bot & \text{no element of } \ell \text{ has } q(g) \land g.\mathrm{part} = p \end{cases}$$ -/
def firstOk (q : Flag → Bool) (l : List Flag) (p : String) : Option Flag :=
  l.find? fun g => q g && g.part == p

/-- The elements of a list that are the first $q$-flag of their part.

$$\operatorname{pick}(q, \ell) = [\,f \in \ell \mid \operatorname{firstOk}(q, \ell, f.\mathrm{part}) = f\,]$$ -/
def pick (q : Flag → Bool) (l : List Flag) : List Flag :=
  l.filter fun f => firstOk q l f.part == some f

/-- **The `v2-proved` preset**: in link order, each linked flag that qualifies and is the first qualifying flag of its
part.

$$\operatorname{preset}(R, \Lambda, L) = \operatorname{pick}(\operatorname{ok}(R, \Lambda, L), [\,f \mid (f, \kappa) \in \Lambda\,])$$ -/
def preset (reg : List Reg) (links : List (Flag × List Key)) (ledger : List Row) : List Flag :=
  pick (ok reg links ledger) (links.map (·.1))

/-- The `requires` list of a flag (empty when the flag is not registered).

$$\operatorname{req}(R, f) = \begin{cases} r.\mathrm{requires} & r \text{ is the first element of } R \text{ with } r.\mathrm{flag} = f \\ [] & \text{no element of } R \text{ has flag } f \end{cases}$$ -/
def reqOf (reg : List Reg) (f : Flag) : List Flag := ((reg.find? (·.flag == f)).map (·.requires)).getD []

/-- The `conflicts` list of a flag (empty when the flag is not registered).

$$\operatorname{conf}(R, f) = \begin{cases} r.\mathrm{conflicts} & r \text{ is the first element of } R \text{ with } r.\mathrm{flag} = f \\ [] & \text{no element of } R \text{ has flag } f \end{cases}$$ -/
def confOf (reg : List Reg) (f : Flag) : List Flag := ((reg.find? (·.flag == f)).map (·.conflicts)).getD []

/-- Whether a flag list meets its own `requires` and `conflicts`.

$$\operatorname{closed}(R, P) \iff \forall f \in P:\ (\forall g \in \operatorname{req}(R, f):\ g \in P) \land (\forall g \in \operatorname{conf}(R, f):\ g \notin P)$$ -/
def closed (reg : List Reg) (p : List Flag) : Bool :=
  p.all fun f => (reqOf reg f).all (p.contains ·) && (confOf reg f).all (!p.contains ·)

/-- **The generator's verdict**: the preset when it meets its `requires` and `conflicts`, else an error naming the
preset (a finding, never patched).

$$\operatorname{generate}(R, \Lambda, L) = \begin{cases} \operatorname{ok}(\operatorname{preset}(R, \Lambda, L)) & \operatorname{closed}(R, \operatorname{preset}(R, \Lambda, L)) \\ \operatorname{error} & \text{otherwise} \end{cases}$$ -/
def generate (reg : List Reg) (links : List (Flag × List Key)) (ledger : List Row) : Except String (List Flag) :=
  let p := preset reg links ledger
  if closed reg p then .ok p
  else .error s!"v2-proved: the preset {(p.map (·.key))} violates a requires/conflicts rule"

/-! ## Theorems -/

/-- `pick` keeps exactly the elements that are the first $q$-flag of their part.

$$\forall q, \ell, f:\ f \in \operatorname{pick}(q, \ell) \iff \operatorname{firstOk}(q, \ell, f.\mathrm{part}) = f$$

A flag is picked exactly when it is the first qualifying flag of its part. -/
theorem mem_pick {q : Flag → Bool} {l : List Flag} {f : Flag} :
    f ∈ pick q l ↔ firstOk q l f.part = some f := by
  unfold pick
  rw [List.mem_filter]
  constructor
  · intro h
    simpa using h.2
  · intro h
    exact ⟨List.mem_of_find?_eq_some h, by simpa using h⟩

/-- Every picked flag satisfies $q$.

$$\forall q, \ell, f:\ f \in \operatorname{pick}(q, \ell) \Rightarrow q(f)$$

Picking never admits a flag that fails the test. -/
theorem pick_ok {q : Flag → Bool} {l : List Flag} {f : Flag} (h : f ∈ pick q l) : q f = true := by
  have := List.find?_some (mem_pick.1 h)
  simp only [Bool.and_eq_true] at this
  exact this.1

/-- Two picked flags of one part are equal.

$$\forall q, \ell, f, g:\ f \in \operatorname{pick}(q, \ell) \land g \in \operatorname{pick}(q, \ell) \land f.\mathrm{part} = g.\mathrm{part} \Rightarrow f = g$$

The pick holds at most one variant per part. -/
theorem pick_part_unique {q : Flag → Bool} {l : List Flag} {f g : Flag} (hf : f ∈ pick q l) (hg : g ∈ pick q l)
    (hp : f.part = g.part) : f = g := by
  have h1 := mem_pick.1 hf
  have h2 := mem_pick.1 hg
  rw [hp] at h1
  rw [h1] at h2
  exact Option.some.inj h2

/-- `rowWhy` never answers `proved`.

$$\forall L, k:\ \operatorname{rowWhy}(L, k) \ne \mathrm{proved}$$

A key's objection is never the verdict `proved`. -/
theorem rowWhy_ne_proved (ledger : List Row) (k : Key) : rowWhy ledger k ≠ some .proved := by
  unfold rowWhy
  split
  · split
    · simp
    · split <;> simp
  · simp

/-- A key has no objection exactly when it has one row, that row says `proved`, and it is not `model-bug`.

$$\forall L, k:\ \operatorname{rowWhy}(L, k) = \bot \iff \exists r:\ \operatorname{rowsOf}(L, k) = [r] \land r.\mathrm{status} = \texttt{"proved"} \land r.\mathrm{fResult} \ne \mathrm{modelBug}$$

A linked key passes only through its one proved, unfalsified row. -/
theorem rowWhy_none_iff (ledger : List Row) (k : Key) :
    rowWhy ledger k = none ↔
      ∃ r, rowsOf ledger k = [r] ∧ r.status = "proved" ∧ r.fResult ≠ some .modelBug := by
  unfold rowWhy
  split
  · rename_i r h
    by_cases hs : r.status = "proved"
    · by_cases hf : r.fResult = some .modelBug
      · simp only [hs, hf, bne_self_eq_false, Bool.false_eq_true, ↓reduceIte, beq_self_eq_true, reduceCtorEq,
          false_iff, not_exists, not_and]
        intro x hx _
        rw [h, List.cons.injEq] at hx
        rw [← hx.1]
        exact fun hne => hne hf
      · simp [hs, hf, h]
    · simp [hs, h]
  · rename_i rs h
    simp only [reduceCtorEq, false_iff, not_exists, not_and]
    intro r hr
    exact absurd hr (h r)

/-- **The verdict `proved`, characterised**: no `model-bug` row names the flag, its link is present and non-empty, and
every linked key has exactly one row, which says `proved` and is not `model-bug`.

$$\forall \Lambda, L, f:\ \operatorname{why}(\Lambda, L, f) = \mathrm{proved} \iff \lnot\operatorname{falsifiedBy}(L, f) \land \exists \kappa:\ \operatorname{linkOf}(\Lambda, f) = \kappa \land \kappa \ne [] \land \forall k \in \kappa\ \exists r:\ \operatorname{rowsOf}(L, k) = [r] \land r.\mathrm{status} = \texttt{"proved"} \land r.\mathrm{fResult} \ne \mathrm{modelBug}$$

Only a linked flag whose every row is proved and unfalsified gets `proved`. -/
theorem why_proved_iff (links : List (Flag × List Key)) (ledger : List Row) (f : Flag) :
    why links ledger f = .proved ↔
      falsifiedBy ledger f = false ∧ ∃ ks, linkOf links f = some ks ∧ ks ≠ [] ∧
        ∀ k ∈ ks, ∃ r, rowsOf ledger k = [r] ∧ r.status = "proved" ∧ r.fResult ≠ some .modelBug := by
  unfold why
  by_cases hb : falsifiedBy ledger f = true
  · simp [hb]
  · have hb' : falsifiedBy ledger f = false := by simpa using hb
    simp only [hb', Bool.false_eq_true, ↓reduceIte, true_and]
    split
    · rename_i h
      simp [h]
    · rename_i h
      simp [h]
    · rename_i ks hne h
      constructor
      · intro hw
        refine ⟨ks, h, ?_, ?_⟩
        · intro he
          exact hne he
        · intro k hk
          apply (rowWhy_none_iff ledger k).1
          cases hfs : ks.findSome? (rowWhy ledger) with
          | none => exact List.findSome?_eq_none_iff.1 hfs k hk
          | some w =>
            rw [hfs] at hw
            obtain ⟨a, _, ha⟩ := List.exists_of_findSome?_eq_some hfs
            simp only [Option.getD_some] at hw
            subst hw
            exact absurd ha (rowWhy_ne_proved ledger a)
      · rintro ⟨ks', hks', _, hall⟩
        rw [h] at hks'
        cases hks'
        have hn : ks.findSome? (rowWhy ledger) = none :=
          List.findSome?_eq_none_iff.2 fun k hk => (rowWhy_none_iff ledger k).2 (hall k hk)
        simp [hn]

/-- **Membership**: a flag is in the preset exactly when it is the first qualifying linked flag of its part.

$$\forall R, \Lambda, L, f:\ f \in \operatorname{preset}(R, \Lambda, L) \iff \operatorname{firstOk}(\operatorname{ok}(R, \Lambda, L), [\,g \mid (g, \kappa) \in \Lambda\,], f.\mathrm{part}) = f$$

The arm holds every qualifying flag except one shadowed by an earlier qualifying variant of its part. -/
theorem mem_preset_iff {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {f : Flag} :
    f ∈ preset reg links ledger ↔ firstOk (ok reg links ledger) (links.map (·.1)) f.part = some f :=
  mem_pick

/-- **The preset is a subset of the registered flags**: every member is a registered `optimized` variant.

$$\forall R, \Lambda, L, f:\ f \in \operatorname{preset}(R, \Lambda, L) \Rightarrow \exists r \in R:\ r.\mathrm{flag} = f \land r.\mathrm{kind} = \mathrm{optimized}$$

No unregistered flag and no faithful, ablation or proposal variant enters the arm. -/
theorem preset_registered {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {f : Flag}
    (h : f ∈ preset reg links ledger) : ∃ r ∈ reg, r.flag = f ∧ r.kind = .optimized := by
  have hq := pick_ok h
  simp only [ok, isOpt, Bool.and_eq_true, List.any_eq_true, beq_iff_eq] at hq
  obtain ⟨⟨r, hr, hf, hk⟩, _⟩ := hq
  exact ⟨r, hr, hf, hk⟩

/-- Every member of the preset is proved.

$$\forall R, \Lambda, L, f:\ f \in \operatorname{preset}(R, \Lambda, L) \Rightarrow \operatorname{why}(\Lambda, L, f) = \mathrm{proved}$$

The arm holds only flags with the verdict `proved`. -/
theorem preset_proved {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {f : Flag}
    (h : f ∈ preset reg links ledger) : why links ledger f = .proved := by
  have hq := pick_ok h
  simp only [ok, Bool.and_eq_true, beq_iff_eq] at hq
  exact hq.2

/-- **A falsified flag never enters**: if some ledger row names the flag and reports `model-bug`, the flag is not in
the preset.

$$\forall R, \Lambda, L, f:\ (\exists r \in L:\ r.\mathrm{flag} = \operatorname{key}(f) \land r.\mathrm{fResult} = \mathrm{modelBug}) \Rightarrow f \notin \operatorname{preset}(R, \Lambda, L)$$

A model-bug F-result recorded against a flag keeps it out of the arm. -/
theorem falsified_not_mem {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {f : Flag}
    (h : ∃ r ∈ ledger, r.flag = some f.key ∧ r.fResult = some .modelBug) : f ∉ preset reg links ledger := by
  intro hm
  have hp := (why_proved_iff links ledger f).1 (preset_proved hm)
  obtain ⟨r, hr, h1, h2⟩ := h
  have : falsifiedBy ledger f = true :=
    List.any_eq_true.2 ⟨r, hr, by simp [h1, h2]⟩
  rw [hp.1] at this
  exact Bool.false_ne_true this

/-- **A linked row that is not proved or is falsified keeps the flag out**.

$$\forall R, \Lambda, L, f, \kappa, k, r:\ \operatorname{linkOf}(\Lambda, f) = \kappa \land k \in \kappa \land \operatorname{rowsOf}(L, k) = [r] \land (r.\mathrm{status} \ne \texttt{"proved"} \lor r.\mathrm{fResult} = \mathrm{modelBug}) \Rightarrow f \notin \operatorname{preset}(R, \Lambda, L)$$

One unproved or falsified linked row is enough to exclude the flag. -/
theorem linked_row_blocks {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {f : Flag}
    {ks : List Key} {k : Key} {r : Row} (hl : linkOf links f = some ks) (hk : k ∈ ks) (hr : rowsOf ledger k = [r])
    (hbad : r.status ≠ "proved" ∨ r.fResult = some .modelBug) : f ∉ preset reg links ledger := by
  intro hm
  obtain ⟨_, ks', hks', _, hall⟩ := (why_proved_iff links ledger f).1 (preset_proved hm)
  rw [hl] at hks'
  cases hks'
  obtain ⟨r', hr', hs, hf⟩ := hall k hk
  rw [hr] at hr'
  cases hr'
  rcases hbad with hb | hb
  · exact hb hs
  · exact hf hb

/-- An unlinked flag never enters.

$$\forall R, \Lambda, L, f:\ \operatorname{linkOf}(\Lambda, f) = \bot \Rightarrow f \notin \operatorname{preset}(R, \Lambda, L)$$

A registered flag the link table does not name stays out of the arm. -/
theorem unlinked_not_mem {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {f : Flag}
    (hl : linkOf links f = none) : f ∉ preset reg links ledger := by
  intro hm
  obtain ⟨_, ks, hks, _⟩ := (why_proved_iff links ledger f).1 (preset_proved hm)
  rw [hl] at hks
  cases hks

/-- The preset holds at most one variant per part.

$$\forall R, \Lambda, L, f, g:\ f, g \in \operatorname{preset}(R, \Lambda, L) \land f.\mathrm{part} = g.\mathrm{part} \Rightarrow f = g$$

The preset is a function from parts to variants. -/
theorem preset_part_unique {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {f g : Flag}
    (hf : f ∈ preset reg links ledger) (hg : g ∈ preset reg links ledger) (hp : f.part = g.part) : f = g :=
  pick_part_unique hf hg hp

/-- **A generated preset is the preset and meets its rules**.

$$\forall R, \Lambda, L, P:\ \operatorname{generate}(R, \Lambda, L) = \operatorname{ok}(P) \Rightarrow P = \operatorname{preset}(R, \Lambda, L) \land \operatorname{closed}(R, P)$$

The generator emits nothing but the decided preset, and only when its requires and conflicts hold. -/
theorem generate_ok {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {p : List Flag}
    (h : generate reg links ledger = .ok p) : p = preset reg links ledger ∧ closed reg p = true := by
  unfold generate at h
  dsimp only at h
  split at h
  · rename_i hc
    cases h
    exact ⟨rfl, hc⟩
  · cases h

/-! ## Examples -/

private def fa : Flag := ⟨"a", "x"⟩
private def fa2 : Flag := ⟨"a", "y"⟩
private def fb : Flag := ⟨"b", "x"⟩
private def regEx : List Reg :=
  [⟨⟨"a", "faithful"⟩, .faithful, [], []⟩, ⟨fa, .optimized, [], []⟩, ⟨fa2, .optimized, [], []⟩,
   ⟨fb, .optimized, [fa], []⟩]
private def rowP (c : String) : Row := ⟨"a", c, "proved", none, none⟩

#guard Flag.key ⟨"nav.hitTest", "hit-skip"⟩ == "nav.hitTest:hit-skip"
#guard rowWhy [rowP "c"] ("a", "c") == none
#guard rowWhy [rowP "c", rowP "c"] ("a", "c") == some (.rowCount ("a", "c") 2)
#guard rowWhy [] ("a", "c") == some (.rowCount ("a", "c") 0)
#guard rowWhy [{ rowP "c" with status := "partly-proved" }] ("a", "c") == some (.notProved ("a", "c") "partly-proved")
#guard rowWhy [{ rowP "c" with fResult := some .modelBug }] ("a", "c") == some (.falsified ("a", "c"))
#guard rowWhy [{ rowP "c" with fResult := some .unusable }] ("a", "c") == none
#guard why [(fa, [("a", "c")])] [rowP "c"] fa == .proved
#guard why [(fa, [])] [rowP "c"] fa == .noLink
#guard why [] [rowP "c"] fa == .noLink
#guard why [(fa, [("a", "c")])] [rowP "c", { rowP "z" with flag := some "a:x", fResult := some .modelBug }] fa ==
  .falsifiedFlag
#guard why [(fa, [("a", "c")])] [rowP "c", { rowP "z" with flag := some "a:x", fResult := some .pass }] fa == .proved
#guard why [(fa, [("a", "c"), ("a", "d")])] [rowP "c", { rowP "d" with status := "not-proved" }] fa ==
  .notProved ("a", "d") "not-proved"
#guard preset regEx [(fa, [("a", "c")]), (fa2, [("a", "c")]), (fb, [("a", "c")])] [rowP "c"] == [fa, fb]
#guard preset regEx [(fa, [("a", "d")]), (fa2, [("a", "c")])] [rowP "c"] == [fa2]
#guard preset regEx [(⟨"a", "faithful"⟩, [("a", "c")])] [rowP "c"] == []
#guard preset regEx [(⟨"z", "x"⟩, [("a", "c")])] [rowP "c"] == []
#guard (generate regEx [(fb, [("a", "c")])] [rowP "c"]).toOption.isNone
#guard (generate regEx [(fa, [("a", "c")]), (fb, [("a", "c")])] [rowP "c"]).toOption == some [fa, fb]

end Fw.Preset
