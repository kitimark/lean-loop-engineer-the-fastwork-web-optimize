import Fw.Preset.V2Proved
/-!
# The `shipped` preset: the `v2-proved` members, then per part `v2-proved` leaves free the first linked flag whose look
the user accepted, whose kind ships, whose linked rows are proved and whose stored runs pass in Chromium and WebKit.
-/
namespace Fw.Preset.Shipped
open Fw.Preset
open Fw.Gate.Trajectory (Stored Family Walk)

/-- The flag is registered and every registered entry of it is `optimized` or `proposal`. -/
def kindAllows (reg : List Reg) (f : Flag) : Bool :=
  reg.any (·.flag == f) && reg.all fun r => r.flag != f || r.kind == .optimized || r.kind == .proposal

/-- The look-accepted route: accepted look, shipping kind, proved rows, passing trajectory. -/
def lookOk (accepted : Flag → Bool) (reg : List Reg) (links : List (Flag × List Key)) (ledger : List Row)
    (st : List Stored) (f : Flag) : Bool :=
  accepted f && kindAllows reg f && why links ledger f == .proved && trajWhy st f == .pass

def okShipped (accepted : Flag → Bool) (reg : List Reg) (links : List (Flag × List Key)) (ledger : List Row)
    (st : List Stored) (f : Flag) : Bool :=
  ok reg links ledger st f || lookOk accepted reg links ledger st f

def free (p l : List Flag) : List Flag := l.filter fun f => !p.any (·.part == f.part)

def extras (accepted : Flag → Bool) (reg : List Reg) (links : List (Flag × List Key)) (ledger : List Row)
    (st : List Stored) : List Flag :=
  pick (lookOk accepted reg links ledger st) (free (preset reg links ledger st) (links.map (·.1)))

/-- **The `shipped` preset**: `v2-proved`, then the look-accepted flags of the parts it leaves free. -/
def shipped (accepted : Flag → Bool) (reg : List Reg) (links : List (Flag × List Key)) (ledger : List Row)
    (st : List Stored) : List Flag :=
  preset reg links ledger st ++ extras accepted reg links ledger st

def generate (accepted : Flag → Bool) (reg : List Reg) (links : List (Flag × List Key)) (ledger : List Row)
    (st : List Stored) : Except String (List Flag) :=
  let p := shipped accepted reg links ledger st
  if closed reg p then .ok p
  else .error s!"shipped: the preset {(p.map (·.key))} violates a requires/conflicts rule"

/-! ## Blockers per preset -/

inductive Req | kind | proofs | gate (fam : Family) | look
deriving DecidableEq, Repr

def reqs : List Req := [.kind, .proofs, .gate .chromium, .gate .webkit, .look]

def gateMet (st : List Stored) (f : Flag) (fam : Family) : Bool := walks.all fun w => tcell st f fam w == .pass

def metV2 (reg : List Reg) (links : List (Flag × List Key)) (ledger : List Row) (st : List Stored) (f : Flag) :
    Req → Bool
  | .kind => isOpt reg f
  | .proofs => why links ledger f == .proved
  | .gate fam => gateMet st f fam
  | .look => !isLook reg f

def metLook (accepted : Flag → Bool) (reg : List Reg) (links : List (Flag × List Key)) (ledger : List Row)
    (st : List Stored) (f : Flag) : Req → Bool
  | .kind => kindAllows reg f
  | .proofs => why links ledger f == .proved
  | .gate fam => gateMet st f fam
  | .look => accepted f

def blockersV2 (reg : List Reg) (links : List (Flag × List Key)) (ledger : List Row) (st : List Stored) (f : Flag) :
    List Req :=
  reqs.filter fun r => !metV2 reg links ledger st f r

def blockersLook (accepted : Flag → Bool) (reg : List Reg) (links : List (Flag × List Key)) (ledger : List Row)
    (st : List Stored) (f : Flag) : List Req :=
  reqs.filter fun r => !metLook accepted reg links ledger st f r

def blockersShipped (accepted : Flag → Bool) (reg : List Reg) (links : List (Flag × List Key)) (ledger : List Row)
    (st : List Stored) (f : Flag) : List Req :=
  if ok reg links ledger st f then [] else blockersLook accepted reg links ledger st f

/-! ## Theorems -/

theorem gates_iff {st : List Stored} {f : Flag} :
    (gateMet st f .chromium && gateMet st f .webkit) = true ↔ trajWhy st f = .pass := by
  rw [trajWhy_pass_iff]
  simp [gateMet, families]

theorem kindAllows_iff {reg : List Reg} {f : Flag} :
    kindAllows reg f = true ↔
      (∃ r ∈ reg, r.flag = f) ∧ ∀ r ∈ reg, r.flag = f → r.kind = .optimized ∨ r.kind = .proposal := by
  simp only [kindAllows, Bool.and_eq_true, List.any_eq_true, beq_iff_eq, List.all_eq_true, Bool.or_eq_true,
    bne_iff_ne, ne_eq]
  constructor
  · rintro ⟨h1, h2⟩
    exact ⟨h1, fun r hr hf => by rcases h2 r hr with (h | h) | h <;> simp_all⟩
  · rintro ⟨h1, h2⟩
    refine ⟨h1, fun r hr => ?_⟩
    by_cases hf : r.flag = f
    · rcases h2 r hr hf with h | h <;> simp [h]
    · simp [hf]

theorem kind_blocks {reg : List Reg} {f : Flag} {r : Reg} (hr : r ∈ reg) (hf : r.flag = f)
    (hk : r.kind = .faithful ∨ r.kind = .ablation ∨ r.kind = .probe) : kindAllows reg f = false := by
  rw [Bool.eq_false_iff]
  intro h
  rcases (kindAllows_iff.1 h).2 r hr hf with h' | h' <;> rcases hk with hk | hk | hk <;> simp_all

theorem kind_unregistered {reg : List Reg} {f : Flag} (h : ∀ r ∈ reg, r.flag ≠ f) : kindAllows reg f = false := by
  rw [Bool.eq_false_iff]
  intro hk
  obtain ⟨r, hr, hf⟩ := (kindAllows_iff.1 hk).1
  exact h r hr hf

theorem okShipped_of_ok {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)}
    {ledger : List Row} {st : List Stored} {f : Flag} (h : ok reg links ledger st f = true) :
    okShipped accepted reg links ledger st f = true := by
  simp [okShipped, h]

theorem okShipped_of_lookOk {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)}
    {ledger : List Row} {st : List Stored} {f : Flag} (h : lookOk accepted reg links ledger st f = true) :
    okShipped accepted reg links ledger st f = true := by
  simp [okShipped, h]

theorem lookOk_iff {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row}
    {st : List Stored} {f : Flag} :
    lookOk accepted reg links ledger st f = true ↔ accepted f = true ∧ kindAllows reg f = true ∧
      why links ledger f = .proved ∧ trajWhy st f = .pass := by
  simp [lookOk, and_assoc]

theorem mem_shipped {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row}
    {st : List Stored} {f : Flag} :
    f ∈ shipped accepted reg links ledger st ↔ f ∈ preset reg links ledger st ∨ f ∈ extras accepted reg links ledger st :=
  List.mem_append

/-- **`v2-proved` ⊆ `shipped`**. -/
theorem preset_sub_shipped {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)}
    {ledger : List Row} {st : List Stored} {f : Flag} (h : f ∈ preset reg links ledger st) :
    f ∈ shipped accepted reg links ledger st :=
  mem_shipped.2 (.inl h)

theorem extras_lookOk {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row}
    {st : List Stored} {f : Flag} (h : f ∈ extras accepted reg links ledger st) :
    lookOk accepted reg links ledger st f = true :=
  pick_ok h

theorem extras_free {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row}
    {st : List Stored} {f g : Flag} (hf : f ∈ extras accepted reg links ledger st) (hg : g ∈ preset reg links ledger st) :
    f.part ≠ g.part := by
  intro he
  have hl : f ∈ free (preset reg links ledger st) (links.map (·.1)) := by
    have := (mem_pick.1 hf)
    exact List.mem_of_find?_eq_some this
  have := (List.mem_filter.1 hl).2
  simp only [Bool.not_eq_eq_eq_not, Bool.not_true, List.any_eq_false, beq_iff_eq] at this
  exact this g hg he.symm

theorem shipped_extra_lookOk {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)}
    {ledger : List Row} {st : List Stored} {f : Flag} (h : f ∈ shipped accepted reg links ledger st)
    (hn : f ∉ preset reg links ledger st) : lookOk accepted reg links ledger st f = true :=
  extras_lookOk ((mem_shipped.1 h).resolve_left hn)

/-- **Every member outside `v2-proved` has an accepted look decision**. -/
theorem shipped_extra_accepted {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)}
    {ledger : List Row} {st : List Stored} {f : Flag} (h : f ∈ shipped accepted reg links ledger st)
    (hn : f ∉ preset reg links ledger st) : accepted f = true :=
  (lookOk_iff.1 (shipped_extra_lookOk h hn)).1

/-- **No look change enters unaccepted**: a class `l` member of `shipped` has an accepted look decision. -/
theorem shipped_look_accepted {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)}
    {ledger : List Row} {st : List Stored} {f : Flag} (h : f ∈ shipped accepted reg links ledger st)
    (hl : isLook reg f = true) : accepted f = true :=
  shipped_extra_accepted h (look_not_mem hl)

theorem shipped_okShipped {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)}
    {ledger : List Row} {st : List Stored} {f : Flag} (h : f ∈ shipped accepted reg links ledger st) :
    okShipped accepted reg links ledger st f = true := by
  rcases mem_shipped.1 h with h | h
  · exact okShipped_of_ok (pick_ok h)
  · exact okShipped_of_lookOk (extras_lookOk h)

theorem shipped_proved {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)}
    {ledger : List Row} {st : List Stored} {f : Flag} (h : f ∈ shipped accepted reg links ledger st) :
    why links ledger f = .proved ∧ trajWhy st f = .pass := by
  rcases mem_shipped.1 h with h | h
  · exact ⟨preset_proved h, preset_trajectory h⟩
  · have := lookOk_iff.1 (extras_lookOk h)
    exact ⟨this.2.2.1, this.2.2.2⟩

theorem probe_not_mem_shipped {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)}
    {ledger : List Row} {st : List Stored} {f : Flag} (h : OnlyProbe reg f) :
    f ∉ shipped accepted reg links ledger st := by
  intro hm
  rcases mem_shipped.1 hm with hp | he
  · exact probe_not_mem h hp
  · obtain ⟨_, hk, _⟩ := lookOk_iff.1 (extras_lookOk he)
    obtain ⟨⟨r, hr, hf⟩, hall⟩ := kindAllows_iff.1 hk
    rcases hall r hr hf with hk' | hk' <;> rw [h r hr hf] at hk' <;> cases hk'

/-- **One variant per part** in `shipped`. -/
theorem shipped_part_unique {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)}
    {ledger : List Row} {st : List Stored} {f g : Flag} (hf : f ∈ shipped accepted reg links ledger st)
    (hg : g ∈ shipped accepted reg links ledger st) (hp : f.part = g.part) : f = g := by
  rcases mem_shipped.1 hf with hf | hf <;> rcases mem_shipped.1 hg with hg | hg
  · exact preset_part_unique hf hg hp
  · exact absurd hp.symm (extras_free hg hf)
  · exact absurd hp (extras_free hf hg)
  · exact pick_part_unique hf hg hp

theorem shipped_eq_preset {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)}
    {ledger : List Row} {st : List Stored} (h : ∀ f, accepted f = false) :
    shipped accepted reg links ledger st = preset reg links ledger st := by
  have he : extras accepted reg links ledger st = [] := by
    rw [List.eq_nil_iff_forall_not_mem]
    intro f hf
    have := (lookOk_iff.1 (extras_lookOk hf)).1
    rw [h f] at this
    cases this
  simp [shipped, he]

/-- **A generated `shipped` is the preset and composes**: every member's `requires` is in it, no member's `conflicts`
is. -/
theorem generate_ok {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row}
    {st : List Stored} {p : List Flag} (h : generate accepted reg links ledger st = .ok p) :
    p = shipped accepted reg links ledger st ∧
      ∀ f ∈ p, (∀ g ∈ reqOf reg f, g ∈ p) ∧ ∀ g ∈ confOf reg f, g ∉ p := by
  unfold generate at h
  dsimp only at h
  split at h
  · rename_i hc
    cases h
    refine ⟨rfl, fun f hf => ?_⟩
    have := (List.all_eq_true.1 hc) f hf
    simp only [Bool.and_eq_true, List.all_eq_true, List.contains_iff_mem, Bool.not_eq_eq_eq_not, Bool.not_true]
      at this
    refine ⟨this.1, fun g hg hm => ?_⟩
    have h2 := this.2 g hg
    rw [List.contains_iff_mem.2 hm] at h2
    cases h2
  · cases h

theorem blockersV2_nil_iff {reg : List Reg} {links : List (Flag × List Key)} {ledger : List Row} {st : List Stored}
    {f : Flag} : blockersV2 reg links ledger st f = [] ↔ ok reg links ledger st f = true := by
  simp only [blockersV2, List.filter_eq_nil_iff, reqs, List.mem_cons, List.not_mem_nil, or_false, forall_eq_or_imp,
    forall_eq, Bool.not_eq_eq_eq_not, Bool.not_true, metV2, Bool.eq_false_iff, ne_eq, Classical.not_not]
  simp only [ok, Bool.and_eq_true, Bool.not_eq_true', beq_iff_eq, ← gates_iff]
  constructor
  · rintro ⟨h1, h2, h3, h4, h5⟩
    exact ⟨⟨⟨h1, h2⟩, h3, h4⟩, by simpa using h5⟩
  · rintro ⟨⟨⟨h1, h2⟩, h3, h4⟩, h5⟩
    exact ⟨h1, h2, h3, h4, by simpa using h5⟩

theorem blockersLook_nil_iff {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)}
    {ledger : List Row} {st : List Stored} {f : Flag} :
    blockersLook accepted reg links ledger st f = [] ↔ lookOk accepted reg links ledger st f = true := by
  simp only [blockersLook, List.filter_eq_nil_iff, reqs, List.mem_cons, List.not_mem_nil, or_false, forall_eq_or_imp,
    forall_eq, metLook, Bool.not_eq_eq_eq_not, Bool.not_true, Bool.eq_false_iff, ne_eq, Classical.not_not]
  simp only [lookOk, Bool.and_eq_true, beq_iff_eq, ← gates_iff]
  constructor
  · rintro ⟨h1, h2, h3, h4, h5⟩
    exact ⟨⟨⟨h5, h1⟩, h2⟩, h3, h4⟩
  · rintro ⟨⟨⟨h5, h1⟩, h2⟩, h3, h4⟩
    exact ⟨h1, h2, h3, h4, h5⟩

theorem blockersShipped_nil_iff {accepted : Flag → Bool} {reg : List Reg} {links : List (Flag × List Key)}
    {ledger : List Row} {st : List Stored} {f : Flag} :
    blockersShipped accepted reg links ledger st f = [] ↔ okShipped accepted reg links ledger st f = true := by
  unfold blockersShipped okShipped
  by_cases h : ok reg links ledger st f = true
  · simp [h]
  · simp only [Bool.not_eq_true] at h
    simp [h, blockersLook_nil_iff]

/-! ## Examples -/

private def fa : Flag := ⟨"a", "x"⟩
private def fl : Flag := ⟨"a", "look"⟩
private def gl : Flag := ⟨"b", "look"⟩
private def regEx : List Reg :=
  [⟨fa, .optimized, [], [], none⟩, ⟨fl, .proposal, [], [], some .l⟩, ⟨gl, .proposal, [], [], some .l⟩,
   ⟨⟨"c", "probe"⟩, .probe, [], [], none⟩, ⟨⟨"d", "abl"⟩, .ablation, [], [], some .l⟩]
private def linksEx : List (Flag × List Key) :=
  [(fl, [("a", "c")]), (fa, [("a", "c")]), (gl, [("a", "c")]), (⟨"c", "probe"⟩, [("a", "c")]),
   (⟨"d", "abl"⟩, [("a", "c")])]
private def rowP : Row := ⟨"a", "c", "proved", none, none, none⟩
private def run (ks : List String) (e : Fw.Gate.Trajectory.Engine) (w : Walk) : Stored :=
  ⟨1, "s", "", "?preset=x", ks, e, w, Fw.Gate.Trajectory.allowedWidths, []⟩
private def four (ks : List String) : List Stored :=
  [run ks .chromium .hero, run ks .chromium .morph, run ks .linuxWebkit .hero, run ks .macWebkit .morph]
private def stEx : List Stored := four ["a:x", "a:look", "b:look", "c:probe", "d:abl"]
private def accEx (f : Flag) : Bool := f == fl || f == gl || f == ⟨"c", "probe"⟩ || f == ⟨"d", "abl"⟩

#guard preset regEx linksEx [rowP] stEx == [fa]
#guard shipped accEx regEx linksEx [rowP] stEx == [fa, gl]
#guard shipped (fun _ => false) regEx linksEx [rowP] stEx == [fa]
#guard shipped (· == fl) regEx linksEx [rowP] stEx == [fa]
#guard shipped accEx regEx linksEx [rowP] (four ["a:x", "c:probe", "d:abl"]) == [fa]
#guard shipped accEx regEx linksEx [rowP] (four ["a:x"] ++ (four ["b:look"]).take 3) == [fa]
#guard shipped accEx regEx linksEx [] stEx == []
#guard kindAllows regEx fl && !kindAllows regEx ⟨"c", "probe"⟩ && !kindAllows regEx ⟨"d", "abl"⟩
#guard !kindAllows regEx ⟨"z", "x"⟩
#guard !kindAllows (⟨fl, .ablation, [], [], none⟩ :: regEx) fl
#guard blockersV2 regEx linksEx [rowP] stEx gl == [.kind, .look]
#guard blockersShipped accEx regEx linksEx [rowP] stEx gl == []
#guard blockersShipped (fun _ => false) regEx linksEx [rowP] stEx gl == [.look]
#guard blockersShipped accEx regEx linksEx [rowP] ((four ["b:look"]).take 3) gl == [.gate .webkit]
#guard blockersShipped accEx regEx linksEx [rowP] stEx ⟨"c", "probe"⟩ == [.kind]
#guard blockersShipped accEx regEx linksEx [] stEx fa == [.proofs, .look]
#guard blockersV2 regEx linksEx [rowP] stEx fa == [] && blockersShipped accEx regEx linksEx [] stEx fa != []
#guard (generate accEx regEx linksEx [rowP] stEx).toOption == some [fa, gl]
#guard (generate accEx (⟨gl, .proposal, [], [fa], some .l⟩ :: regEx) linksEx [rowP] stEx).toOption.isNone
#guard (generate accEx (⟨gl, .proposal, [⟨"e", "x"⟩], [], some .l⟩ :: regEx) linksEx [rowP] stEx).toOption.isNone

end Fw.Preset.Shipped
