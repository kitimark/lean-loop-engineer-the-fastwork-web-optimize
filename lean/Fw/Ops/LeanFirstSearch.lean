import Fw.Search
import Fw.Ops.LeanFirstDecision

/-!
# Edge-case search for the lean-first gate (before the proofs)

Task `lfg-spec`, rule 5 applied to the gate itself: every property of `Fw.Ops.LeanFirstProps` gets a pointwise check
`q<P>` (the property is exactly "the check passes everywhere", `q<P>_iff`), an `Enum` instance over its inputs, and a
bounded search theorem (`<P>_iff_search`, from `Fw.Search.prop_iff_searchUpTo`). The guards run the search at bound 0
for the real implementation (no counterexample); `FwTest/Mutants/LeanFirst/` runs it for each mutant (a
counterexample exists) and proves each kill in kernel from one found point.

* `Enum Facts` lists, at every bound, the **fault grid** first: a clean `base` (which passes at every stage) with up
  to two of the faults in `Fault` applied (missing proof, a proof of an unreached stub, stale review, missing kill,
  hidden premise, unmarked branch, proof before search, legacy growth, missing source, unknown reach, exemptions read
  off main, a directory glob over decision code, a line break in a name, and more), with and without the
  `leanFirst` flag, and then every facts value whose lists are at most `n` long over strings of at most `n` characters
  (`Enum.ofSurj`, so the enumeration is complete).
* `Enum Evidence` lists evidence that repairs grid faults first, `Enum ThmFact` and `Enum PropFact` the grid's
  theorems and properties first.
-/
namespace Fw.Ops.LeanFirst

open Fw.Search Fw.Spec.Props

universe u v

/-! ## Enumeration helpers -/

/-- **Enumerate through a surjection**: list `f(b)` for every `b` listed at the bound. -/
@[reducible] def Enum.ofSurj {α : Type u} {β : Type v} [Enum β] (f : β → α) (g : α → β) (h : ∀ a, f (g a) = a) :
    Enum α where
  enum n := (Enum.enum n).map f
  mono hmn hx := by
    obtain ⟨b, hb, rfl⟩ := List.mem_map.mp hx
    exact List.mem_map.mpr ⟨b, Enum.mono hmn hb, rfl⟩
  complete a := by
    obtain ⟨n, hn⟩ := Enum.complete (g a)
    exact ⟨n, List.mem_map.mpr ⟨g a, hn, h a⟩⟩

/-- **Seeds first**: list the seeds at every bound, then the base enumeration. -/
@[reducible] def Enum.withSeeds {α : Type u} (seeds : List α) (E : Enum α) : Enum α where
  enum n := seeds ++ E.enum n
  mono hmn hx := by
    rcases List.mem_append.mp hx with h | h
    · exact List.mem_append.mpr (Or.inl h)
    · exact List.mem_append.mpr (Or.inr (E.mono hmn h))
  complete a := by
    obtain ⟨n, hn⟩ := E.complete a
    exact ⟨n, List.mem_append.mpr (Or.inr hn)⟩

/-- Characters by code point: the characters with code at most `n` (invalid codes map to `\0`). -/
instance instEnumChar : Enum Char := Enum.ofSurj (β := Nat) Char.ofNat Char.toNat Char.ofNat_toNat

/-- Strings: the strings of at most `n` characters with codes at most `n`. -/
instance instEnumString : Enum String :=
  Enum.ofSurj (β := List Char) String.ofList String.toList (fun _ => String.ofList_toList)

/-- The roles. -/
instance : EnumAll Role where
  all := [.math, .adversary]
  complete x := by cases x <;> simp

/-- The theorem classes. -/
instance : EnumAll ThmKind where
  all := [.general, .data, .kill]
  complete x := by cases x <;> simp

/-- The marks. -/
instance : EnumAll Mark where
  all := [.none, .op, .twin, .glueOk, .glueBad]
  complete x := by cases x <;> simp

/-- The premise statuses. -/
instance : EnumAll Status where
  all := [.measured, .untested, .refuted, .unmeasurable]
  complete x := by cases x <;> simp

/-- The stages. -/
instance : EnumAll Stage where
  all := [.shadow, .newTasks, .allNew, .ratchet]
  complete x := by cases x <;> simp

/-- Signoff rows from their fields: two strings, a role and a flag. -/
instance : Enum Signoff :=
  Enum.ofSurj (β := String × String × Role × Bool) (fun ⟨a, b, r, x⟩ => ⟨a, b, r, x⟩)
    (fun s => (s.decl, s.stmtHash, s.role, s.agree)) (fun _ => rfl)

/-- Kill rows from their fields. -/
instance : Enum KillRow :=
  Enum.ofSurj (β := String × String) (fun ⟨a, b⟩ => ⟨a, b⟩) (fun k => (k.target, k.hash)) (fun _ => rfl)

/-- Branches from their fields. -/
instance : Enum Branch :=
  Enum.ofSurj (β := String × Nat × Mark) (fun ⟨a, b, c⟩ => ⟨a, b, c⟩) (fun b => (b.file, b.line, b.mark))
    (fun _ => rfl)

/-- Registry rows from their fields. -/
instance : Enum PremRow :=
  Enum.ofSurj (β := String × Status × List String) (fun ⟨a, b, c⟩ => ⟨a, b, c⟩)
    (fun r => (r.id, r.status, r.carriers)) (fun _ => rfl)

/-- Source flags from their fields. -/
instance : Enum Present :=
  Enum.ofSurj (β := Bool × Bool × Bool) (fun ⟨a, b, c⟩ => ⟨a, b, c⟩) (fun p => (p.mathview, p.kills, p.tsLint))
    (fun _ => rfl)

/-! ## The fault grid -/

/-- The clean property of the grid: `P` at statement hash `hP`, no premises, search at `c1`, proof at `c2`. -/
def baseProp : PropFact :=
  { name := "P", stmtHash := "hP", assumes := [], searchAt := some "c1", proofAt := some "c2" }

/-- The clean proof of `P` in the grid, of the implementation `impl`, which the wire reaches. -/
def baseThm : ThmFact :=
  { name := "P_impl", hash := "hT", kind := .general, proves := some "P", implArg := some "impl",
    reachFromWire := some true, axiomsOk := true, usedBy := [], reach := ["impl"], assumes := [] }

/-- The kill witness of `P` in the grid (exempt by class). -/
def killThm : ThmFact :=
  { name := "P_rejects_m", hash := "hK", kind := .kill, proves := none, implArg := none, reachFromWire := none,
    axiomsOk := true, usedBy := [], reach := [], assumes := [] }

/-- A lemma that `P_impl` uses (no kill of its own, so exempt as a lemma). -/
def lemmaThm : ThmFact :=
  { name := "L", hash := "hL", kind := .general, proves := none, implArg := none, reachFromWire := none,
    axiomsOk := true, usedBy := ["P_impl"], reach := [], assumes := [] }

/-- A baseline theorem at its baseline hash (not new). -/
def oldThmFact : ThmFact := { lemmaThm with name := "Old", hash := "hO", usedBy := [] }

/-- A baseline theorem whose statement changed (new). -/
def changedThmFact : ThmFact := { lemmaThm with name := "Old", hash := "hO2", usedBy := [] }

/-- **The clean facts**: one decision write, one property proved of a reached implementation, signed by both roles
and killed, its proof killed, one marked branch, a three-row registry (measured, untested, refuted), one baseline
theorem, search before proof, equal legacy counts, every source present, exemptions read at main `m`. It passes at
every stage. -/
def base : Facts :=
  { leanFirst := true, writes := ["lean/Fw/Ops/X.lean", "docs/x.md"], props := [baseProp],
    thms := [baseThm, killThm],
    kills := [⟨"P_impl", "hT"⟩, ⟨"P", "hP"⟩],
    signoffs := [⟨"P", "hP", .math, true⟩, ⟨"P", "hP", .adversary, true⟩],
    branches := [⟨"apps/x/src/a.ts", 3, .op⟩],
    registry := [⟨"pm", .measured, ["cM"]⟩, ⟨"pu", .untested, ["cU"]⟩, ⟨"pr", .refuted, ["cR"]⟩],
    baseline := [("Old", "hO")], ancestry := [("c1", "c2")], legacyMain := 2, legacyHead := 2,
    present := ⟨true, true, true⟩, mainAt := "m", exemptAt := some "m" }

/-- One edit of the clean facts. -/
inductive Fault where
  | noProps | noDecision | unproved | badAxioms | stub | noImpl | unsignedMath | unsignedAdv | disagreeAdv | staleStmt
  | unkilledProp | noKill | lemma | lemmaProves | dataProof | oldThm | changedOld | unmarked | glueBad | glueOk
  | hidden | assumedOk | unregistered | refuted | untestedHidden | untestedShared | searchOrder | searchMissing
  | ratchet | ratchetDown | missingMathview | missingKills | missingLint | notLeanFirst | newlineName | dupSignoff
  | reachUnknown | exemptBranch | dirGlob | docsGlob
deriving DecidableEq, Repr

/-- Every fault, in declaration order. -/
def Fault.all : List Fault :=
  [.noProps, .noDecision, .unproved, .badAxioms, .stub, .noImpl, .unsignedMath, .unsignedAdv, .disagreeAdv, .staleStmt,
   .unkilledProp, .noKill, .lemma, .lemmaProves, .dataProof, .oldThm, .changedOld, .unmarked, .glueBad, .glueOk,
   .hidden, .assumedOk, .unregistered, .refuted, .untestedHidden, .untestedShared, .searchOrder, .searchMissing,
   .ratchet, .ratchetDown, .missingMathview, .missingKills, .missingLint, .notLeanFirst, .newlineName, .dupSignoff,
   .reachUnknown, .exemptBranch, .dirGlob, .docsGlob]

/-- Edit the proof `P_impl` wherever it is in the theorem list. -/
def mapImpl (F : Facts) (f : ThmFact → ThmFact) : Facts :=
  { F with thms := F.thms.map fun t => if t.name = "P_impl" then f t else t }

/-- Edit the property `P` wherever it is in the property list. -/
def mapProp (F : Facts) (f : PropFact → PropFact) : Facts :=
  { F with props := F.props.map fun P => if P.name = "P" then f P else P }

/-- Apply one fault: each constructor is one field edit (drop, append, or flip), listed case by case below. `stub`
re-targets the proof at an unreached `stub` and adds a reached lemma; `dirGlob` and `docsGlob` drop the property and
write a directory glob over decision code, resp. only allowlisted globs.
Below, `M(t ↦ t[...])` is `mapImpl(F, t ↦ t[...])`, `Π(...)` is `mapProp`,
and `thms_F`, `signoffs_F`, … are the fields of `F`; for every `F`.

Here `rw` is the field `reachFromWire` and ⏎ is a newline character. -/
def Fault.apply (F : Facts) : Fault → Facts
  | .noProps => { F with props := [] }
  | .noDecision => { F with writes := ["docs/x.md"], props := [] }
  | .unproved => { F with thms := F.thms.filter (·.name != "P_impl") }
  | .badAxioms => mapImpl F fun t => { t with axiomsOk := false }
  | .stub =>
    let F' := mapImpl F fun t => { t with implArg := some "stub", reachFromWire := some false }
    { F' with thms := F'.thms ++ [{ lemmaThm with implArg := some "impl", reachFromWire := some true }] }
  | .noImpl => mapImpl F fun t => { t with implArg := none }
  | .unsignedMath => { F with signoffs := F.signoffs.filter (·.role != .math) }
  | .unsignedAdv => { F with signoffs := F.signoffs.filter (·.role != .adversary) }
  | .disagreeAdv => { F with signoffs := F.signoffs ++ [⟨"P", "hP", .adversary, false⟩] }
  | .staleStmt => { F with signoffs := F.signoffs.map fun s => if s.role = .math then { s with stmtHash := "h0" } else s }
  | .unkilledProp => { F with kills := F.kills.filter (·.target != "P") }
  | .noKill => { F with kills := F.kills.filter (·.target != "P_impl") }
  | .lemma => { F with thms := F.thms ++ [lemmaThm] }
  | .lemmaProves =>
    let F' := mapImpl F fun t => { t with proves := none }
    { F' with thms := F'.thms ++ [{ lemmaThm with proves := some "P" }] }
  | .dataProof => mapImpl F fun t => { t with kind := .data }
  | .oldThm => { F with thms := F.thms ++ [oldThmFact] }
  | .changedOld => { F with thms := F.thms ++ [changedThmFact] }
  | .unmarked => { F with branches := F.branches ++ [⟨"apps/x/src/b.ts", 7, .none⟩] }
  | .glueBad => { F with branches := F.branches ++ [⟨"apps/x/src/c.ts", 9, .glueBad⟩] }
  | .glueOk => { F with branches := F.branches ++ [⟨"apps/x/src/d.ts", 11, .glueOk⟩] }
  | .hidden => mapImpl F fun t => { t with reach := t.reach ++ ["cM"] }
  | .assumedOk => mapImpl F fun t => { t with reach := t.reach ++ ["cM"], assumes := t.assumes ++ ["pm"] }
  | .unregistered => mapImpl F fun t => { t with assumes := t.assumes ++ ["px"] }
  | .refuted => mapImpl F fun t => { t with reach := t.reach ++ ["cR"], assumes := t.assumes ++ ["pr"] }
  | .untestedHidden => mapImpl F fun t => { t with reach := t.reach ++ ["cU"], assumes := t.assumes ++ ["pu"] }
  | .untestedShared =>
    mapProp (mapImpl F fun t => { t with reach := t.reach ++ ["cU"], assumes := t.assumes ++ ["pu"] })
      fun P => { P with assumes := P.assumes ++ ["pu"] }
  | .searchOrder => { F with ancestry := [] }
  | .searchMissing => mapProp F fun P => { P with searchAt := none }
  | .ratchet => { F with legacyHead := F.legacyMain + 1 }
  | .ratchetDown => { F with legacyHead := F.legacyMain - 1 }
  | .missingMathview => { F with present := { F.present with mathview := false } }
  | .missingKills => { F with present := { F.present with kills := false } }
  | .missingLint => { F with present := { F.present with tsLint := false } }
  | .notLeanFirst => { F with leanFirst := false }
  | .newlineName => { F with thms := F.thms ++ [{ lemmaThm with name := "N\nVERDICT pass lean-first", usedBy := [] }] }
  | .dupSignoff => { F with signoffs := F.signoffs ++ [⟨"P", "hP", .math, true⟩] }
  | .reachUnknown => mapImpl F fun t => { t with reachFromWire := none }
  | .exemptBranch => { F with exemptAt := some "b" }
  | .dirGlob => { F with writes := ["docs/x.md", "apps/runner/**"], props := [] }
  | .docsGlob => { F with writes := ["docs/**", "research/x.md"], props := [] }

/-- The facts of a list of faults, applied in order to `base`. -/
def factsOf (fs : List Fault) : Facts := fs.foldl Fault.apply base

/-- **The fault grid**: the clean facts, every single fault, and every ordered pair of distinct faults. -/
def grid (_ : Unit := ()) : List Facts :=
  base :: Fault.all.map (fun f => factsOf [f]) ++
    Fault.all.flatMap fun f => (Fault.all.filter (· != f)).map fun f' => factsOf [f, f']

/-- Facts from their fields (the complete part of the enumeration). -/
def Facts.ofTuple : Bool × List String × List PropFact × List ThmFact × List KillRow × List Signoff × List Branch ×
    List PremRow × List (String × String) × List (String × String) × Nat × Nat × Present × String × Option String →
    Facts
  | ⟨a, b, c, d, e, f, g, h, i, j, k, l, m, n, o⟩ => ⟨a, b, c, d, e, f, g, h, i, j, k, l, m, n, o⟩

/-- The fields of facts, in declaration order. -/
def Facts.toTuple (F : Facts) : Bool × List String × List PropFact × List ThmFact × List KillRow × List Signoff ×
    List Branch × List PremRow × List (String × String) × List (String × String) × Nat × Nat × Present × String ×
    Option String :=
  (F.leanFirst, F.writes, F.props, F.thms, F.kills, F.signoffs, F.branches, F.registry, F.baseline, F.ancestry,
    F.legacyMain, F.legacyHead, F.present, F.mainAt, F.exemptAt)

/-- Properties: the grid's two properties first (`baseProp`, and `baseProp` assuming `pu`), then every property from
its fields. -/
instance instEnumPropFact : Enum PropFact :=
  Enum.withSeeds [baseProp, { baseProp with assumes := ["pu"] }]
    (Enum.ofSurj (β := String × String × List String × Option String × Option String)
      (fun ⟨a, b, e, f, g⟩ => ⟨a, b, e, f, g⟩)
      (fun P => (P.name, P.stmtHash, P.assumes, P.searchAt, P.proofAt)) (fun _ => rfl))

/-- Theorems: the grid's eight theorems first, then every theorem from its fields. -/
instance instEnumThmFact : Enum ThmFact :=
  Enum.withSeeds [baseThm, killThm, lemmaThm, { lemmaThm with proves := some "P" },
      { baseThm with kind := .data }, { baseThm with assumes := ["pu"] }, oldThmFact, changedThmFact]
    (Enum.ofSurj (β := String × String × ThmKind × Option String × Option String × Option Bool × Bool × List String ×
        List String × List String)
      (fun ⟨a, b, c, d, i, r, e, f, g, h⟩ => ⟨a, b, c, d, i, r, e, f, g, h⟩)
      (fun t => (t.name, t.hash, t.kind, t.proves, t.implArg, t.reachFromWire, t.axiomsOk, t.usedBy, t.reach,
        t.assumes)) (fun _ => rfl))

/-- **`Enum Facts`**: the fault grid first, then every facts value from its fields (complete). -/
instance instEnumFacts : Enum Facts where
  enum n := grid () ++ (Enum.ofSurj Facts.ofTuple Facts.toTuple (fun _ => rfl)).enum n
  mono := (Enum.withSeeds (grid ()) (Enum.ofSurj Facts.ofTuple Facts.toTuple (fun _ => rfl))).mono
  complete := (Enum.withSeeds (grid ()) (Enum.ofSurj Facts.ofTuple Facts.toTuple (fun _ => rfl))).complete

/-- **`Enum Evidence`**: seven seeds first, then every evidence value from its fields. The seeds, as (kills,
signoffs, marks, sources): nothing; a disagreeing math signoff; an agreeing adversary signoff; both kills; the proof
kill; two marks; every source. -/
instance instEnumEvidence : Enum Evidence :=
  Enum.withSeeds
    [⟨[], [], [], ⟨false, false, false⟩⟩,
     ⟨[], [⟨"P", "hP", .math, false⟩], [], ⟨false, false, false⟩⟩,
     ⟨[], [⟨"P", "hP", .adversary, true⟩], [], ⟨false, false, false⟩⟩,
     ⟨[⟨"P", "hP"⟩, ⟨"P_impl", "hT"⟩], [], [], ⟨false, false, false⟩⟩,
     ⟨[⟨"P_impl", "hT"⟩], [], [], ⟨false, false, false⟩⟩,
     ⟨[], [], [.op, .twin], ⟨false, false, false⟩⟩,
     ⟨[], [], [], ⟨true, true, true⟩⟩]
    (Enum.ofSurj (β := List KillRow × List Signoff × List Mark × Present) (fun ⟨a, b, c, d⟩ => ⟨a, b, c, d⟩)
      (fun e => (e.kills, e.signoffs, e.marks, e.present)) (fun _ => rfl))

-- the grid: base passes at every stage; each fault gives its reason at the ratchet stage
#guard Fault.all.length == 40
#guard grid.length == 1 + 40 + 40 * 39
#guard [Stage.shadow, .newTasks, .allNew, .ratchet].all fun s => gate s base == .pass
#guard gate .ratchet (factsOf [.unproved]) == .refuse [.unproved "P"]
#guard gate .ratchet (factsOf [.noImpl]) == .refuse [.unproved "P"]
#guard gate .ratchet (factsOf [.stub]) == .refuse [.unreached "P"]
#guard gate .ratchet (factsOf [.reachUnknown]) == .pending [.reach]
#guard gate .ratchet (factsOf [.exemptBranch]) == .pending [.exempt]
#guard gate .ratchet (factsOf [.dirGlob]) == .refuse [.noProps "apps/runner/**"]
#guard gate .ratchet (factsOf [.docsGlob]) == .pass
#guard gate .ratchet (factsOf [.noProps]) == .refuse [.noProps "lean/Fw/Ops/X.lean"]
#guard gate .ratchet (factsOf [.noDecision]) == .pass
#guard gate .ratchet (factsOf [.lemma]) == .pass
#guard gate .ratchet (factsOf [.lemmaProves]) == .refuse [.unproved "P"]
#guard gate .ratchet (factsOf [.oldThm]) == .pass
#guard gate .ratchet (factsOf [.changedOld]) == .refuse [.noKill "Old"]
#guard gate .ratchet (factsOf [.untestedHidden]) == .refuse [.unproved "P"]
#guard gate .ratchet (factsOf [.untestedShared]) == .pass
#guard gate .ratchet (factsOf [.hidden]) == .refuse [.hidden "P_impl" "pm"]
#guard gate .ratchet (factsOf [.missingKills]) == .pending [.kills]
#guard gate .shadow (factsOf [.missingKills]) == .pass
#guard gate .newTasks (factsOf [.notLeanFirst, .unproved]) == .pass
#guard gate .allNew (factsOf [.notLeanFirst, .noKill]) == .refuse [.noKill "P_impl"]
#guard gate .allNew (factsOf [.ratchet]) == .pass
#guard gate .ratchet (factsOf [.ratchet]) == .refuse [.growth 2 3]

/-! ## Pointwise checks, their soundness, and the bounded search theorems -/

/-- The check of `PassIff`. -/
def qPassIff (g : Gate) : Stage × Facts → Bool := fun (s, F) => decide (g s F = .pass ↔ PassSpec s F)
/-- The check of `RefusesUnproved`. -/
def qRefusesUnproved (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .props = true → AllPresent F →
    ∀ P ∈ F.props, ¬ (∃ t ∈ F.thms, Discharges F t P) → Reason.unproved P.name ∈ (g s F).refusals)
/-- The check of `StaleReviewRefuses`. -/
def qStaleReviewRefuses (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .props = true → AllPresent F →
    ∀ P ∈ F.props, ∀ r ∈ [Role.math, Role.adversary], ¬ Signed F P r →
      Reason.unsigned P.name r ∈ (g s F).refusals)
/-- The check of `RefusesUnreached`. -/
def qRefusesUnreached (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .props = true → AllPresent F →
    ∀ P ∈ F.props, (∃ t ∈ F.thms, Discharges F t P) → (∀ t ∈ F.thms, Discharges F t P → t.reachFromWire ≠ some true) →
      Reason.unreached P.name ∈ (g s F).refusals)
/-- The check of `NoPropsRefuses`. -/
def qNoPropsRefuses (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .props = true → AllPresent F → Decides F → F.props = [] →
    ∃ w ∈ F.writes, DecisionWrite w ∧ Reason.noProps w ∈ (g s F).refusals)
/-- The check of `MutantKillsOrRefuse`. -/
def qMutantKillsOrRefuse (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .kills = true → AllPresent F →
    ∀ t ∈ F.thms, New F t → ¬ KillAt F t.name t.hash → ¬ Exempt F t → Reason.noKill t.name ∈ (g s F).refusals)
/-- The check of `ExemptNotDischarge`. -/
def qExemptNotDischarge (d : Facts → ThmFact → PropFact → Bool) : Facts × ThmFact × PropFact → Bool :=
  fun (F, t, P) => decide (Exempt F t → d F t P = false)
/-- The check of `HiddenPremiseRefuses`. -/
def qHiddenPremiseRefuses (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .premises = true → AllPresent F →
    ∀ t ∈ F.thms, New F t → ∀ r ∈ F.registry, (∃ c ∈ r.carriers, c ∈ t.reach) → r.id ∉ t.assumes →
      Reason.hidden t.name r.id ∈ (g s F).refusals)
/-- The check of `UnregisteredPremiseRefuses`. -/
def qUnregisteredPremiseRefuses (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .premises = true → AllPresent F →
    ∀ t ∈ F.thms, New F t → ∀ p ∈ t.assumes, ¬ (∃ r ∈ F.registry, r.id = p) →
      Reason.unregistered t.name p ∈ (g s F).refusals)
/-- The check of `RefutedPremiseRefuses`. -/
def qRefutedPremiseRefuses (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .premises = true → AllPresent F →
    ∀ t ∈ F.thms, New F t → ∀ p ∈ t.assumes, StatusIs F p .refuted →
      Reason.refuted t.name p ∈ (g s F).refusals)
/-- The check of `UntwinnedBranchRefuses`. -/
def qUntwinnedBranchRefuses (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .twins = true → AllPresent F →
    ∀ b ∈ F.branches, (b.mark = .none ∨ b.mark = .glueBad) → Reason.branch b.file b.line b.mark ∈ (g s F).refusals)
/-- The check of `ProofBeforeSearchRefuses`. -/
def qProofBeforeSearchRefuses (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .search = true → AllPresent F →
    ∀ P ∈ F.props, ¬ SearchFirst F P → Reason.searchOrder P.name ∈ (g s F).refusals)
/-- The check of `MissingFactPending`. -/
def qMissingFactPending (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide ((∃ r ∈ Rule.all, enforced s F.leanFirst r = true) → ¬ AllPresent F →
    (g s F).isPending = true ∧
    (F.present.mathview = false ↔ Missing.mathview ∈ (g s F).pendingOn) ∧
    (F.present.kills = false ↔ Missing.kills ∈ (g s F).pendingOn) ∧
    (F.present.tsLint = false ↔ Missing.tsLint ∈ (g s F).pendingOn) ∧
    (¬ ReachKnown F ↔ Missing.reach ∈ (g s F).pendingOn) ∧
    (F.exemptAt ≠ some F.mainAt ↔ Missing.exempt ∈ (g s F).pendingOn))
/-- The check of `PendingExit`. -/
def qPendingExit (o : Render) : Stage × Facts → Bool := fun (s, F) =>
  decide ((∃ r ∈ Rule.all, enforced s F.leanFirst r = true) → ¬ AllPresent F →
    (o s F).kind = .pending ∧ (o s F).exit = 75)
/-- The check of `OneVerdict`. -/
def qOneVerdict (o : Render) : Stage × Facts → Bool := fun (s, F) =>
  decide (verdictCount (o s F).lines = 1 ∧ (o s F).lines.getLast?.map isVerdict = some true)
/-- The check of `ExitZeroIff`. -/
def qExitZeroIff (o : Render) : Stage × Facts → Bool := fun (s, F) => decide ((o s F).exit = 0 ↔ PassSpec s F)
/-- The check of `GateMono`. -/
def qGateMono (g : Gate) : Stage × Facts × Evidence → Bool := fun (s, F, e) =>
  decide (g s F = .pass → g s (F.add e) = .pass)
/-- The check of `StageMono`. -/
def qStageMono (g : Gate) : Stage × Stage × Facts → Bool := fun (s, s', F) =>
  decide (s.rank ≤ s'.rank → g s' F = .pass → g s F = .pass)
/-- The check of `BaselineNotNew`. -/
def qBaselineNotNew (ν : Facts → ThmFact → Bool) : Facts × ThmFact → Bool := fun (F, t) =>
  decide ((t.name, t.hash) ∈ F.baseline → (∀ p ∈ F.baseline, p.1 = t.name → p.2 = t.hash) → ν F t = false)
/-- The check of `ChangedIsNew`. -/
def qChangedIsNew (ν : Facts → ThmFact → Bool) : Facts × ThmFact → Bool := fun (F, t) =>
  decide ((t.name, t.hash) ∉ F.baseline → ν F t = true)
/-- The check of `RatchetRefusesGrowth`. -/
def qRatchetRefusesGrowth (g : Gate) : Stage × Facts → Bool := fun (s, F) =>
  decide (enforced s F.leanFirst .ratchet = true → AllPresent F → F.legacyMain < F.legacyHead →
    Reason.growth F.legacyMain F.legacyHead ∈ (g s F).refusals)
/-- The check of `ShadowPasses`. -/
def qShadowPasses (g : Gate) : Facts → Bool := fun F => decide (g .shadow F = .pass)
/-- The check of `NoNewline`. -/
def qNoNewline (o : Render) : Stage × Facts → Bool := fun (s, F) =>
  decide (∀ l ∈ (o s F).lines, '\n' ∉ l.toList ∧ '\r' ∉ l.toList)

/-- `qPassIff` is exact for `PassIff`. -/
theorem qPassIff_iff (g : Gate) : PassIff g ↔ ∀ x, qPassIff g x = true := ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qRefusesUnproved` is exact for `RefusesUnproved`. -/
theorem qRefusesUnproved_iff (g : Gate) : RefusesUnproved g ↔ ∀ x, qRefusesUnproved g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qStaleReviewRefuses` is exact for `StaleReviewRefuses`. -/
theorem qStaleReviewRefuses_iff (g : Gate) : StaleReviewRefuses g ↔ ∀ x, qStaleReviewRefuses g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qRefusesUnreached` is exact for `RefusesUnreached`. -/
theorem qRefusesUnreached_iff (g : Gate) : RefusesUnreached g ↔ ∀ x, qRefusesUnreached g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qNoPropsRefuses` is exact for `NoPropsRefuses`. -/
theorem qNoPropsRefuses_iff (g : Gate) : NoPropsRefuses g ↔ ∀ x, qNoPropsRefuses g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qMutantKillsOrRefuse` is exact for `MutantKillsOrRefuse`. -/
theorem qMutantKillsOrRefuse_iff (g : Gate) : MutantKillsOrRefuse g ↔ ∀ x, qMutantKillsOrRefuse g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qExemptNotDischarge` is exact for `ExemptNotDischarge`. -/
theorem qExemptNotDischarge_iff (d : Facts → ThmFact → PropFact → Bool) :
    ExemptNotDischarge d ↔ ∀ x, qExemptNotDischarge d x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2.1 x.2.2), fun h F t P => of_decide_eq_true (h (F, t, P))⟩
/-- `qHiddenPremiseRefuses` is exact for `HiddenPremiseRefuses`. -/
theorem qHiddenPremiseRefuses_iff (g : Gate) : HiddenPremiseRefuses g ↔ ∀ x, qHiddenPremiseRefuses g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qUnregisteredPremiseRefuses` is exact for `UnregisteredPremiseRefuses`. -/
theorem qUnregisteredPremiseRefuses_iff (g : Gate) :
    UnregisteredPremiseRefuses g ↔ ∀ x, qUnregisteredPremiseRefuses g x = true := ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qRefutedPremiseRefuses` is exact for `RefutedPremiseRefuses`. -/
theorem qRefutedPremiseRefuses_iff (g : Gate) : RefutedPremiseRefuses g ↔ ∀ x, qRefutedPremiseRefuses g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qUntwinnedBranchRefuses` is exact for `UntwinnedBranchRefuses`. -/
theorem qUntwinnedBranchRefuses_iff (g : Gate) :
    UntwinnedBranchRefuses g ↔ ∀ x, qUntwinnedBranchRefuses g x = true := ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qProofBeforeSearchRefuses` is exact for `ProofBeforeSearchRefuses`. -/
theorem qProofBeforeSearchRefuses_iff (g : Gate) :
    ProofBeforeSearchRefuses g ↔ ∀ x, qProofBeforeSearchRefuses g x = true := ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qMissingFactPending` is exact for `MissingFactPending`. -/
theorem qMissingFactPending_iff (g : Gate) : MissingFactPending g ↔ ∀ x, qMissingFactPending g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qPendingExit` is exact for `PendingExit`. -/
theorem qPendingExit_iff (o : Render) : PendingExit o ↔ ∀ x, qPendingExit o x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qOneVerdict` is exact for `OneVerdict`. -/
theorem qOneVerdict_iff (o : Render) : OneVerdict o ↔ ∀ x, qOneVerdict o x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qExitZeroIff` is exact for `ExitZeroIff`. -/
theorem qExitZeroIff_iff (o : Render) : ExitZeroIff o ↔ ∀ x, qExitZeroIff o x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qGateMono` is exact for `GateMono`. -/
theorem qGateMono_iff (g : Gate) : GateMono g ↔ ∀ x, qGateMono g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2.1 x.2.2), fun h s F e => of_decide_eq_true (h (s, F, e))⟩
/-- `qStageMono` is exact for `StageMono`. -/
theorem qStageMono_iff (g : Gate) : StageMono g ↔ ∀ x, qStageMono g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2.1 x.2.2), fun h s s' F => of_decide_eq_true (h (s, s', F))⟩
/-- `qBaselineNotNew` is exact for `BaselineNotNew`. -/
theorem qBaselineNotNew_iff (ν : Facts → ThmFact → Bool) : BaselineNotNew ν ↔ ∀ x, qBaselineNotNew ν x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qChangedIsNew` is exact for `ChangedIsNew`. -/
theorem qChangedIsNew_iff (ν : Facts → ThmFact → Bool) : ChangedIsNew ν ↔ ∀ x, qChangedIsNew ν x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qRatchetRefusesGrowth` is exact for `RatchetRefusesGrowth`. -/
theorem qRatchetRefusesGrowth_iff (g : Gate) : RatchetRefusesGrowth g ↔ ∀ x, qRatchetRefusesGrowth g x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩
/-- `qShadowPasses` is exact for `ShadowPasses`. -/
theorem qShadowPasses_iff (g : Gate) : ShadowPasses g ↔ ∀ x, qShadowPasses g x = true :=
  ⟨fun h F => decide_eq_true (h F), fun h F => of_decide_eq_true (h F)⟩
/-- `qNoNewline` is exact for `NoNewline`. -/
theorem qNoNewline_iff (o : Render) : NoNewline o ↔ ∀ x, qNoNewline o x = true :=
  ⟨fun h x => decide_eq_true (h x.1 x.2), fun h a b => of_decide_eq_true (h (a, b))⟩

/-- **The bounded search theorem for the gate** (`pass_iff` over `Enum Facts`): for every gate, `PassIff` holds
exactly when the search finds no counterexample at any bound. -/
theorem PassIff_iff_search (g : Gate) : PassIff g ↔ ∀ n, searchUpTo n (qPassIff g) = none :=
  prop_iff_searchUpTo PassIff qPassIff qPassIff_iff g

/-- **The bounded search theorem for evidence** (`gate_mono` over `Enum Facts` and `Enum Evidence`). -/
theorem GateMono_iff_search (g : Gate) : GateMono g ↔ ∀ n, searchUpTo n (qGateMono g) = none :=
  prop_iff_searchUpTo GateMono qGateMono qGateMono_iff g

/-- **The bounded search theorem for the output** (`one_verdict` over `Enum Facts`). -/
theorem OneVerdict_iff_search (o : Render) : OneVerdict o ↔ ∀ n, searchUpTo n (qOneVerdict o) = none :=
  prop_iff_searchUpTo OneVerdict qOneVerdict qOneVerdict_iff o

/-! ## Guards: no counterexample for the real gate at bound 0 (the grid plus the empty-list facts) -/

#guard (searchUpTo 0 (qPassIff gate)).isNone
#guard (searchUpTo 0 (qRefusesUnproved gate)).isNone
#guard (searchUpTo 0 (qStaleReviewRefuses gate)).isNone
#guard (searchUpTo 0 (qRefusesUnreached gate)).isNone
#guard (searchUpTo 0 (qNoPropsRefuses gate)).isNone
#guard (searchUpTo 0 (qMutantKillsOrRefuse gate)).isNone
#guard (searchUpTo 0 (qExemptNotDischarge discharges)).isNone
#guard (searchUpTo 0 (qHiddenPremiseRefuses gate)).isNone
#guard (searchUpTo 0 (qUnregisteredPremiseRefuses gate)).isNone
#guard (searchUpTo 0 (qRefutedPremiseRefuses gate)).isNone
#guard (searchUpTo 0 (qUntwinnedBranchRefuses gate)).isNone
#guard (searchUpTo 0 (qProofBeforeSearchRefuses gate)).isNone
#guard (searchUpTo 0 (qMissingFactPending gate)).isNone
#guard (searchUpTo 0 (qPendingExit out)).isNone
#guard (searchUpTo 0 (qOneVerdict out)).isNone
#guard (searchUpTo 0 (qExitZeroIff out)).isNone
#guard (searchUpTo 0 (qGateMono gate)).isNone
#guard (searchUpTo 0 (qStageMono gate)).isNone
#guard (searchUpTo 0 (qBaselineNotNew isNew)).isNone
#guard (searchUpTo 0 (qChangedIsNew isNew)).isNone
#guard (searchUpTo 0 (qRatchetRefusesGrowth gate)).isNone
#guard (searchUpTo 0 (qShadowPasses gate)).isNone
#guard (searchUpTo 0 (qNoNewline out)).isNone

end Fw.Ops.LeanFirst
