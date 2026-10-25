import Fw.Gate.Trajectory
/-!
# The `v2-proved` arm: optimized flags whose linked ledger rows are proved and whose stored trajectory runs pass in
Chromium and WebKit on the hero and morph paths, the first such variant per part.
-/
namespace Fw.Preset
open Fw.Gate.Trajectory (Stored Family Walk Outcome outcome)

/-- A flag: a part id and one of its variants. -/
structure Flag where
  part : String
  variant : String
deriving DecidableEq, Repr, Inhabited

/-- The URL form `part:variant`. -/
def Flag.key (f : Flag) : String := f.part ++ ":" ++ f.variant

/-- The kind of a registered variant (`part.json` `kind`). -/
inductive Kind where
  | faithful
  | optimized
  | ablation
  | proposal
deriving DecidableEq, Repr

/-- How a variant's look relates to the faithful one (`part.json` `visClass`, PLAN §4.7 classes): `e` exact, `eS` exact
at every sample, `q` within the gate's tolerances, `l` a look change. -/
inductive VisClass where
  | e
  | eS
  | q
  | l
deriving DecidableEq, Repr

/-- One registered variant with its `requires` and `conflicts` lists and its look class (`none` when `part.json` names
none). -/
structure Reg where
  flag : Flag
  kind : Kind
  requires : List Flag
  conflicts : List Flag
  visClass : Option VisClass := none
deriving Repr

/-- The combined `fw engine-check` verdict a ledger row records for its flag (`fResult`). -/
inductive FRes where
  | pass
  | unusable
  | modelBug
deriving DecidableEq, Repr

/-- The fields of a findings-ledger row this module reads; `flag`, `fResult` and `visClass` are optional in the
ledger. -/
structure Row where
  part : String
  candidate : String
  status : String
  flag : Option String
  fResult : Option FRes
  visClass : Option VisClass := none
deriving Repr

/-- A ledger row's identity: its `part` and `candidate` text. -/
abbrev Key := String × String

/-- The rows of the ledger with key `k`, in ledger order. -/
def rowsOf (ledger : List Row) (k : Key) : List Row :=
  ledger.filter fun r => r.part == k.1 && r.candidate == k.2

/-- Why a flag is in the arm or not. -/
inductive Why where
  | proved
  | noLink
  | falsifiedFlag
  | rowCount (k : Key) (n : Nat)
  | notProved (k : Key) (status : String)
  | falsified (k : Key)
deriving DecidableEq, Repr

/-- Whether some ledger row names the flag in its `flag` field and reports `model-bug`. -/
def falsifiedBy (ledger : List Row) (f : Flag) : Bool :=
  ledger.any fun r => r.flag == some f.key && r.fResult == some .modelBug

/-- The objection of one linked key, `none` when the key has exactly one row, it says `proved` and it is not
falsified. -/
def rowWhy (ledger : List Row) (k : Key) : Option Why :=
  match rowsOf ledger k with
  | [r] =>
    if r.status != "proved" then some (.notProved k r.status)
    else if r.fResult == some .modelBug then some (.falsified k) else none
  | rs => some (.rowCount k rs.length)

/-- The ledger keys linked to a flag: the second component of the first link whose flag is `f`. -/
def linkOf (links : List (Flag × List Key)) (f : Flag) : Option (List Key) :=
  (links.find? (·.1 == f)).map (·.2)

/-- **Why a flag is or is not proved**: a `model-bug` row naming it first, then a missing or empty link, then the first
objection among its linked keys in link order, else `proved`. -/
def why (links : List (Flag × List Key)) (ledger : List Row) (f : Flag) : Why :=
  if falsifiedBy ledger f then .falsifiedFlag
  else match linkOf links f with
    | none => .noLink
    | some [] => .noLink
    | some ks => (ks.findSome? (rowWhy ledger)).getD .proved

/-- Whether a flag is a registered variant of kind `optimized`. -/
def isOpt (reg : List Reg) (f : Flag) : Bool :=
  reg.any fun r => r.flag == f && r.kind == .optimized

/-- The paths a member must pass on: no part is proved to move on one path only. -/
def walks : List Walk := [.hero, .morph]

/-- The engine families a member must pass in. -/
def families : List Family := [.chromium, .webkit]

/-- The stored runs whose flag set holds the flag, on one engine family and path. -/
def runsFor (st : List Stored) (f : Flag) (fam : Family) (w : Walk) : List Stored :=
  st.filter fun s => s.flags.contains f.key && s.engine.family == fam && s.walk == w

/-- The trajectory verdict of a flag on one engine family and path. -/
inductive TCell where
  | pass
  | fail
  | pending
deriving DecidableEq, Repr

/-- A cell: runs of the flag alone decide (fail first); else a shared run's fail leaves it pending and its pass passes. -/
def tcell (st : List Stored) (f : Flag) (fam : Family) (w : Walk) : TCell :=
  let rs := runsFor st f fam w
  let own := rs.filter (·.flags == [f.key])
  if own.any (outcome · == .fail) then .fail
  else if own.any (outcome · == .pass) then .pass
  else if rs.any (outcome · == .fail) then .pending
  else if rs.any (outcome · == .pass) then .pass
  else .pending

/-- The four cells of a flag, families outer, paths inner. -/
def cells (st : List Stored) (f : Flag) : List TCell :=
  families.flatMap fun fam => walks.map (tcell st f fam)

/-- The trajectory verdict of a flag. -/
inductive TWhy where
  | pass
  | pending
  | falsified
deriving DecidableEq, Repr

/-- **The trajectory verdict**: falsified when a cell fails, pass when all four pass, else pending. -/
def trajWhy (st : List Stored) (f : Flag) : TWhy :=
  if (cells st f).contains .fail then .falsified
  else if (cells st f).all (· == .pass) then .pass
  else .pending

/-- Whether some registered entry of the flag is a look change (`visClass` `l`). -/
def isLook (reg : List Reg) (f : Flag) : Bool :=
  reg.any fun r => r.flag == f && r.visClass == some .l

/-- A flag qualifies for the arm: registered as `optimized`, proved, passing its trajectory cells, and no look change. -/
def ok (reg : List Reg) (links : List (Flag × List Key)) (ledger : List Row) (st : List Stored) (f : Flag) : Bool :=
  isOpt reg f && why links ledger f == .proved && trajWhy st f == .pass && !isLook reg f

/-- The first flag of a list that satisfies `q` and belongs to part `p`. -/
def firstOk (q : Flag → Bool) (l : List Flag) (p : String) : Option Flag :=
  l.find? fun g => q g && g.part == p

/-- The elements of a list that are the first `q`-flag of their part. -/
def pick (q : Flag → Bool) (l : List Flag) : List Flag :=
  l.filter fun f => firstOk q l f.part == some f

/-- **The `v2-proved` preset**: in link order, each linked flag that qualifies and is the first qualifying flag of its
part. -/
def preset (reg : List Reg) (links : List (Flag × List Key)) (ledger : List Row) (st : List Stored) : List Flag :=
  pick (ok reg links ledger st) (links.map (·.1))

/-- The `requires` list of a flag (empty when the flag is not registered). -/
def reqOf (reg : List Reg) (f : Flag) : List Flag := ((reg.find? (·.flag == f)).map (·.requires)).getD []

/-- The `conflicts` list of a flag (empty when the flag is not registered). -/
def confOf (reg : List Reg) (f : Flag) : List Flag := ((reg.find? (·.flag == f)).map (·.conflicts)).getD []

/-- Whether a flag list meets its own `requires` and `conflicts`. -/
def closed (reg : List Reg) (p : List Flag) : Bool :=
  p.all fun f => (reqOf reg f).all (p.contains ·) && (confOf reg f).all (!p.contains ·)

/-- **The generator's verdict**: the preset when it meets its `requires` and `conflicts`, else an error naming the
preset (a finding, never patched). -/
def generate (reg : List Reg) (links : List (Flag × List Key)) (ledger : List Row) (st : List Stored) :
    Except String (List Flag) :=
  let p := preset reg links ledger st
  if closed reg p then .ok p
  else .error s!"v2-proved: the preset {(p.map (·.key))} violates a requires/conflicts rule"

/-! ## Theorems -/

/-- `pick` keeps exactly the elements that are the first `q`-flag of their part.

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

/-- Every picked flag satisfies `q`.

Picking never admits a flag that fails the test. -/
theorem pick_ok {q : Flag → Bool} {l : List Flag} {f : Flag} (h : f ∈ pick q l) : q f = true := by
  have := List.find?_some (mem_pick.1 h)
  simp only [Bool.and_eq_true] at this
  exact this.1

/-- Two picked flags of one part are equal.

The pick holds at most one variant per part. -/
theorem pick_part_unique {q : Flag → Bool} {l : List Flag} {f g : Flag} (hf : f ∈ pick q l) (hg : g ∈ pick q l)
    (hp : f.part = g.part) : f = g := by
  have h1 := mem_pick.1 hf
  have h2 := mem_pick.1 hg
  rw [hp] at h1
  rw [h1] at h2
  exact Option.some.inj h2

/-- `rowWhy` never answers `proved`.

A key's objection is never the verdict `proved`. -/
theorem rowWhy_ne_proved (ledger : List Row) (k : Key) : rowWhy ledger k ≠ some .proved := by
  unfold rowWhy
  split
  · split
    · simp
    · split <;> simp
  · simp

/-- A key has no objection exactly when it has one row, that row says `proved`, and it is not `model-bug`.

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

The arm holds every qualifying flag except one shadowed by an earlier qualifying variant of its part. -/
theorem mem_preset_iff {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {st : List Stored} {f : Flag} :
    f ∈ preset reg links ledger st ↔ firstOk (ok reg links ledger st) (links.map (·.1)) f.part = some f :=
  mem_pick

/-- **The preset is a subset of the registered flags**: every member is a registered `optimized` variant.

No unregistered flag and no faithful, ablation or proposal variant enters the arm. -/
theorem preset_registered {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {st : List Stored} {f : Flag}
    (h : f ∈ preset reg links ledger st) : ∃ r ∈ reg, r.flag = f ∧ r.kind = .optimized := by
  have hq := pick_ok h
  simp only [ok, isOpt, Bool.and_eq_true, List.any_eq_true, beq_iff_eq] at hq
  obtain ⟨⟨⟨⟨r, hr, hf, hk⟩, _⟩, _⟩, _⟩ := hq
  exact ⟨r, hr, hf, hk⟩

/-- Every member of the preset is proved.

The arm holds only flags with the verdict `proved`. -/
theorem preset_proved {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {st : List Stored} {f : Flag}
    (h : f ∈ preset reg links ledger st) : why links ledger f = .proved := by
  have hq := pick_ok h
  simp only [ok, Bool.and_eq_true, beq_iff_eq] at hq
  exact hq.1.1.2

/-- **A falsified flag never enters**: if some ledger row names the flag and reports `model-bug`, the flag is not in
the preset.

A model-bug F-result recorded against a flag keeps it out of the arm. -/
theorem falsified_not_mem {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {st : List Stored} {f : Flag}
    (h : ∃ r ∈ ledger, r.flag = some f.key ∧ r.fResult = some .modelBug) : f ∉ preset reg links ledger st := by
  intro hm
  have hp := (why_proved_iff links ledger f).1 (preset_proved hm)
  obtain ⟨r, hr, h1, h2⟩ := h
  have : falsifiedBy ledger f = true :=
    List.any_eq_true.2 ⟨r, hr, by simp [h1, h2]⟩
  rw [hp.1] at this
  exact Bool.false_ne_true this

/-- **A linked row that is not proved or is falsified keeps the flag out**.

One unproved or falsified linked row is enough to exclude the flag. -/
theorem linked_row_blocks {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {st : List Stored} {f : Flag}
    {ks : List Key} {k : Key} {r : Row} (hl : linkOf links f = some ks) (hk : k ∈ ks) (hr : rowsOf ledger k = [r])
    (hbad : r.status ≠ "proved" ∨ r.fResult = some .modelBug) : f ∉ preset reg links ledger st := by
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

A registered flag the link table does not name stays out of the arm. -/
theorem unlinked_not_mem {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {st : List Stored} {f : Flag}
    (hl : linkOf links f = none) : f ∉ preset reg links ledger st := by
  intro hm
  obtain ⟨_, ks, hks, _⟩ := (why_proved_iff links ledger f).1 (preset_proved hm)
  rw [hl] at hks
  cases hks

/-- The preset holds at most one variant per part.

The preset is a function from parts to variants. -/
theorem preset_part_unique {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {st : List Stored} {f g : Flag}
    (hf : f ∈ preset reg links ledger st) (hg : g ∈ preset reg links ledger st) (hp : f.part = g.part) : f = g :=
  pick_part_unique hf hg hp

/-- **A generated preset is the preset and meets its rules**.

The generator emits nothing but the decided preset, and only when its requires and conflicts hold. -/
theorem generate_ok {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {st : List Stored} {p : List Flag}
    (h : generate reg links ledger st = .ok p) : p = preset reg links ledger st ∧ closed reg p = true := by
  unfold generate at h
  dsimp only at h
  split at h
  · rename_i hc
    cases h
    exact ⟨rfl, hc⟩
  · cases h

/-! ## Trajectory admission -/

/-- A run in `runsFor` holds the flag, is of the family and is on the path. -/
theorem mem_runsFor {st : List Stored} {f : Flag} {fam : Family} {w : Walk} {s : Stored} :
    s ∈ runsFor st f fam w ↔ s ∈ st ∧ f.key ∈ s.flags ∧ s.engine.family = fam ∧ s.walk = w := by
  simp [runsFor, and_assoc]

/-- A failing run of the flag alone fails the cell. -/
theorem tcell_own_fail {st : List Stored} {f : Flag} {fam : Family} {w : Walk} {s : Stored}
    (hs : s ∈ runsFor st f fam w) (ho : s.flags = [f.key]) (hf : outcome s = .fail) : tcell st f fam w = .fail := by
  have : ((runsFor st f fam w).filter (·.flags == [f.key])).any (outcome · == .fail) = true :=
    List.any_eq_true.2 ⟨s, List.mem_filter.2 ⟨hs, by simp [ho]⟩, by simp [hf]⟩
  simp only [tcell, this, ↓reduceIte]

/-- With no failing run of the flag alone, a passing one passes the cell. -/
theorem tcell_own_pass {st : List Stored} {f : Flag} {fam : Family} {w : Walk} {s : Stored}
    (hn : ((runsFor st f fam w).filter (·.flags == [f.key])).any (outcome · == .fail) = false)
    (hs : s ∈ runsFor st f fam w) (ho : s.flags = [f.key]) (hp : outcome s = .pass) : tcell st f fam w = .pass := by
  have : ((runsFor st f fam w).filter (·.flags == [f.key])).any (outcome · == .pass) = true :=
    List.any_eq_true.2 ⟨s, List.mem_filter.2 ⟨hs, by simp [ho]⟩, by simp [hp]⟩
  simp only [tcell, hn, this, Bool.false_eq_true, ↓reduceIte]

/-- With no decided run of the flag alone, a failing shared run leaves the cell pending. -/
theorem tcell_shared_fail {st : List Stored} {f : Flag} {fam : Family} {w : Walk}
    (hn : ((runsFor st f fam w).filter (·.flags == [f.key])).any (outcome · == .fail) = false)
    (hn' : ((runsFor st f fam w).filter (·.flags == [f.key])).any (outcome · == .pass) = false)
    (hf : (runsFor st f fam w).any (outcome · == .fail) = true) : tcell st f fam w = .pending := by
  simp only [tcell, hn, hn', hf, Bool.false_eq_true, ↓reduceIte]

/-- With no decided run of the flag alone and no failing run, a passing shared run passes the cell. -/
theorem tcell_shared_pass {st : List Stored} {f : Flag} {fam : Family} {w : Walk}
    (hn : ((runsFor st f fam w).filter (·.flags == [f.key])).any (outcome · == .fail) = false)
    (hn' : ((runsFor st f fam w).filter (·.flags == [f.key])).any (outcome · == .pass) = false)
    (hf : (runsFor st f fam w).any (outcome · == .fail) = false)
    (hp : (runsFor st f fam w).any (outcome · == .pass) = true) : tcell st f fam w = .pass := by
  simp only [tcell, hn, hn', hf, hp, Bool.false_eq_true, ↓reduceIte]

/-- A cell with no passing and no failing run is pending. -/
theorem tcell_undecided {st : List Stored} {f : Flag} {fam : Family} {w : Walk}
    (h : ∀ s ∈ runsFor st f fam w, outcome s ≠ .pass ∧ outcome s ≠ .fail) : tcell st f fam w = .pending := by
  have hf : (runsFor st f fam w).any (outcome · == .fail) = false :=
    List.any_eq_false.2 fun s hs => by simpa using (h s hs).2
  have hp : (runsFor st f fam w).any (outcome · == .pass) = false :=
    List.any_eq_false.2 fun s hs => by simpa using (h s hs).1
  have hof : ((runsFor st f fam w).filter (·.flags == [f.key])).any (outcome · == .fail) = false :=
    List.any_eq_false.2 fun s hs => by simpa using (h s (List.mem_filter.1 hs).1).2
  have hop : ((runsFor st f fam w).filter (·.flags == [f.key])).any (outcome · == .pass) = false :=
    List.any_eq_false.2 fun s hs => by simpa using (h s (List.mem_filter.1 hs).1).1
  simp only [tcell, hf, hp, hof, hop, Bool.false_eq_true, ↓reduceIte]

/-- **A passing cell has a passing stored run** of a flag set holding the flag, on its family and path. -/
theorem tcell_pass_run {st : List Stored} {f : Flag} {fam : Family} {w : Walk} (h : tcell st f fam w = .pass) :
    ∃ s ∈ st, f.key ∈ s.flags ∧ s.engine.family = fam ∧ s.walk = w ∧ outcome s = .pass := by
  have run : ∀ s ∈ runsFor st f fam w, outcome s = .pass →
      ∃ s ∈ st, f.key ∈ s.flags ∧ s.engine.family = fam ∧ s.walk = w ∧ outcome s = .pass := by
    intro s hs hp
    obtain ⟨h1, h2, h3, h4⟩ := mem_runsFor.1 hs
    exact ⟨s, h1, h2, h3, h4, hp⟩
  by_cases h1 : ((runsFor st f fam w).filter (·.flags == [f.key])).any (outcome · == .fail) = true
  · simp [tcell, h1] at h
  by_cases h2 : ((runsFor st f fam w).filter (·.flags == [f.key])).any (outcome · == .pass) = true
  · obtain ⟨s, hs, ho⟩ := List.any_eq_true.1 h2
    exact run s (List.mem_filter.1 hs).1 (by simpa using ho)
  by_cases h3 : (runsFor st f fam w).any (outcome · == .fail) = true
  · simp [tcell, h1, h2, h3] at h
  by_cases h4 : (runsFor st f fam w).any (outcome · == .pass) = true
  · obtain ⟨s, hs, ho⟩ := List.any_eq_true.1 h4
    exact run s hs (by simpa using ho)
  · simp [tcell, h1, h2, h3, h4] at h

/-- The trajectory verdict is pass exactly when every cell passes. -/
theorem trajWhy_pass_iff {st : List Stored} {f : Flag} :
    trajWhy st f = .pass ↔ ∀ fam ∈ families, ∀ w ∈ walks, tcell st f fam w = .pass := by
  have e : (∀ fam ∈ families, ∀ w ∈ walks, tcell st f fam w = .pass) ↔ (cells st f).all (· == .pass) = true := by
    simp [cells]
  rw [e]
  unfold trajWhy
  by_cases hf : (cells st f).contains .fail = true
  · simp only [hf, ↓reduceIte, reduceCtorEq, false_iff]
    intro ha
    have hm : TCell.fail ∈ cells st f := by simpa using hf
    have := List.all_eq_true.1 ha _ hm
    simp at this
  · simp only [hf, Bool.false_eq_true, ↓reduceIte]
    split
    · rename_i h
      exact iff_of_true rfl h
    · rename_i h
      exact iff_of_false (by simp) h

/-- The trajectory verdict is falsified exactly when some cell fails. -/
theorem trajWhy_falsified_iff {st : List Stored} {f : Flag} :
    trajWhy st f = .falsified ↔ ∃ fam ∈ families, ∃ w ∈ walks, tcell st f fam w = .fail := by
  have e : (∃ fam ∈ families, ∃ w ∈ walks, tcell st f fam w = .fail) ↔ (cells st f).contains .fail = true := by
    simp [cells]
  rw [e]
  unfold trajWhy
  split
  · simp_all
  · split <;> simp_all

/-- Every member passes its trajectory cells. -/
theorem preset_trajectory {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {st : List Stored}
    {f : Flag} (h : f ∈ preset reg links ledger st) : trajWhy st f = .pass := by
  have hq := pick_ok h
  simp only [ok, Bool.and_eq_true, beq_iff_eq] at hq
  exact hq.1.2

/-- **No member without stored passing runs**: each member has, in each engine family and on each path, a stored run of
a flag set holding it whose outcome is pass. -/
theorem member_needs_trajectory {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row}
    {st : List Stored} {f : Flag} (h : f ∈ preset reg links ledger st) (fam : Family) (w : Walk) :
    ∃ s ∈ st, f.key ∈ s.flags ∧ s.engine.family = fam ∧ s.walk = w ∧ outcome s = .pass := by
  apply tcell_pass_run
  apply trajWhy_pass_iff.1 (preset_trajectory h)
  · cases fam <;> simp [families]
  · cases w <;> simp [walks]

/-- A member's WebKit morph pass comes from macOS WebKit: Linux WebKit cannot decide that path. -/
theorem member_needs_mac_morph {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row}
    {st : List Stored} {f : Flag} (h : f ∈ preset reg links ledger st) :
    ∃ s ∈ st, f.key ∈ s.flags ∧ s.engine = .macWebkit ∧ s.walk = .morph ∧ outcome s = .pass := by
  obtain ⟨s, hs, hk, hf, hw, hp⟩ := member_needs_trajectory h .webkit .morph
  refine ⟨s, hs, hk, ?_, hw, hp⟩
  have hc := Fw.Gate.Trajectory.outcome_pass_covers s hp
  rw [hw] at hc
  cases he : s.engine <;> simp_all [Fw.Gate.Trajectory.Engine.family, Fw.Gate.Trajectory.covers]

/-- A falsified trajectory keeps the flag out. -/
theorem trajectory_falsified_not_mem {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row}
    {st : List Stored} {f : Flag} (h : trajWhy st f = .falsified) : f ∉ preset reg links ledger st := by
  intro hm
  rw [preset_trajectory hm] at h
  cases h

/-- A pending trajectory keeps the flag out. -/
theorem trajectory_pending_not_mem {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row}
    {st : List Stored} {f : Flag} (h : trajWhy st f = .pending) : f ∉ preset reg links ledger st := by
  intro hm
  rw [preset_trajectory hm] at h
  cases h

/-- **A look change never enters the arm**: a flag registered with `visClass` `l` is not in `v2-proved`, whatever its
kind, the ledger and the stored runs say.

`v2-proved` holds no variant whose look differs from the faithful one by its own registration. -/
theorem look_not_mem {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {st : List Stored} {f : Flag}
    (h : isLook reg f = true) : f ∉ preset reg links ledger st := by
  intro hm
  have hq := pick_ok hm
  simp [ok, h] at hq

/-! ## Examples -/

private def fa : Flag := ⟨"a", "x"⟩
private def fa2 : Flag := ⟨"a", "y"⟩
private def fb : Flag := ⟨"b", "x"⟩
private def regEx : List Reg :=
  [⟨⟨"a", "faithful"⟩, .faithful, [], [], none⟩, ⟨fa, .optimized, [], [], none⟩, ⟨fa2, .optimized, [], [], none⟩,
   ⟨fb, .optimized, [fa], [], none⟩]
private def rowP (c : String) : Row := ⟨"a", c, "proved", none, none, none⟩
private def run (ks : List String) (e : Fw.Gate.Trajectory.Engine) (w : Walk) (gs : List Fw.Gate.Trajectory.Group) :
    Stored := ⟨"1", "s", "?preset=x", ks, e, w, Fw.Gate.Trajectory.allowedWidths, gs⟩
private def four (ks : List String) : List Stored :=
  [run ks .chromium .hero [], run ks .chromium .morph [], run ks .linuxWebkit .hero [], run ks .macWebkit .morph []]
private def stEx : List Stored := four ["a:x", "a:y", "b:x"]
private def bad : List Fw.Gate.Trajectory.Group := [⟨"nav", "opacity", [390, 641], []⟩]

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
#guard preset regEx [(fa, [("a", "c")]), (fa2, [("a", "c")]), (fb, [("a", "c")])] [rowP "c"] stEx == [fa, fb]
#guard preset regEx [(fa, [("a", "d")]), (fa2, [("a", "c")])] [rowP "c"] stEx == [fa2]
#guard preset regEx [(⟨"a", "faithful"⟩, [("a", "c")])] [rowP "c"] stEx == []
#guard preset regEx [(⟨"z", "x"⟩, [("a", "c")])] [rowP "c"] stEx == []
#guard (generate regEx [(fb, [("a", "c")])] [rowP "c"] stEx).toOption.isNone
#guard (generate regEx [(fa, [("a", "c")]), (fb, [("a", "c")])] [rowP "c"] stEx).toOption == some [fa, fb]
#guard cells stEx fa == [.pass, .pass, .pass, .pass]
#guard trajWhy stEx fa == .pass
#guard trajWhy [] fa == .pending
#guard tcell (four ["a:x"]) fa .webkit .morph == .pass
#guard tcell [run ["a:x"] .linuxWebkit .morph []] fa .webkit .morph == .pending
#guard tcell [run ["a:x"] .chromium .morph bad] fa .chromium .morph == .fail
#guard tcell [run ["a:x"] .chromium .morph bad, run ["a:x"] .chromium .morph []] fa .chromium .morph == .fail
#guard tcell [run ["a:x", "b:x"] .chromium .morph bad, run ["a:x"] .chromium .morph []] fa .chromium .morph == .pass
#guard tcell [run ["a:x", "b:x"] .chromium .morph bad] fa .chromium .morph == .pending
#guard tcell [run ["a:x", "b:x"] .chromium .morph bad, run ["a:x", "c:x"] .chromium .morph []] fa .chromium .morph ==
  .pending
#guard tcell [run ["b:x"] .chromium .morph []] fa .chromium .morph == .pending
#guard trajWhy (run ["a:x"] .chromium .hero bad :: four ["a:x"]) fa == .falsified
#guard trajWhy (four ["a:x"]).tail fa == .pending
#guard preset regEx [(fa, [("a", "c")]), (fb, [("a", "c")])] [rowP "c"] (four ["b:x"]) == [fb]
#guard preset regEx [(fa, [("a", "c")]), (fa2, [("a", "c")])] [rowP "c"] (four ["a:x", "a:y"]).tail == []
#guard isLook [{ flag := fa, kind := .proposal, requires := [], conflicts := [], visClass := some .l }] fa
#guard !isLook regEx fa
#guard preset ({ flag := fa, kind := .optimized, requires := [], conflicts := [], visClass := some .l } :: regEx)
  [(fa, [("a", "c")]), (fb, [("a", "c")])] [rowP "c"] stEx == [fb]
#guard preset ({ flag := fa, kind := .optimized, requires := [], conflicts := [], visClass := some .q } :: regEx)
  [(fa, [("a", "c")]), (fb, [("a", "c")])] [rowP "c"] stEx == [fa, fb]

end Fw.Preset
