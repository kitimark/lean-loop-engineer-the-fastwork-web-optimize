import Fw.Gate.Items
import Fw.Gate.PageRoot
import Lean.Data.Json
/-!
# Coverage of the breakpoint gate's probes by Lean sources (`lean-coverage`)

The part proofs model work (frames, flags, schedules), not static style values, so a hand-written port CSS value can
drift with no proof breaking: the integration fixes of run 39067170911 (nav border colour, font-family, commission
heights) were caught only by the gate. This module states, for every value the gate judges, where it comes from.

A **probe** is a quintuple $(\mathit{part}, \rho, \mathit{cls}, k, b)$: one key $k$ of role $\rho$ of a
part, of item kind $\mathit{cls} \in \{\mathrm{count}, \mathrm{box}, \mathrm{style}\}$, at one breakpoint class $b$
(a matrix block such as `desk`, `touch-rm`, or a sweep id). The probes of a part are exactly the keys
`Fw.Gate.partItems` can judge (`roleKeys`): the count, each declared dimension, each compared style property.

A **source** is `generated f` (the value is emitted by Lean into file $f$, which the site imports), `golden f` (a TS
logic value checked against the Lean golden vector file $f$) or `exempt w` with a reason from a closed list. A
**claim** names one part and patterns for role, kind, key and class, and a source. The TS glue
(`apps/runner/src/coverage.ts`) collects the **evidence**: the files that exist and are imported by the site
(generated) or read by a test (golden). An exemption needs no evidence.

`lint` is the list of probes no valid claim hits. Proved: `coverage_lint_sound` (lint is empty iff every probe has a
source), `lint_monotone` (more claims or more evidence never add a failure), `lint_append` (the per-part lints
concatenate to the whole), `sourceOf_sound` (a reported source comes from a valid claim that hits the probe),
`judged_mem_partProbes` and `lint_nil_judged_sourced` (an empty lint covers every item the gate can judge, in every
sampled state, at every listed class), `tally_total` (the per-source counts add up).

The golden vectors (`packages/contracts/golden/gate/coverage.jsonl`) are written by `Golden.run`; the TS mirror is
checked against them in `apps/runner/test/coverage.test.ts`.
-/
namespace Fw.Gate.Coverage
open Fw.Gate

/-! ## Sources -/

/-- Why a probed value may be neither generated nor golden (a closed list).

$$\mathrm{Exempt} = \{\mathrm{transcribedEmpiricalOnly},\ \mathrm{hoverDependent},\ \mathrm{eventCount},\ \mathrm{engineDefault}\}$$

`transcribedEmpiricalOnly`: hand-transcribed from the snapshot, checked only by the gate; `hoverDependent`: depends on
the pointer state the gate parks (gate-settle); `eventCount`: depends on how many events (frames, ticks, scroll
events) ran before the sample; `engineDefault`: not set by the rewrite, the engine's own layout or initial value. -/
inductive Exempt
  | transcribedEmpiricalOnly | hoverDependent | eventCount | engineDefault
  deriving DecidableEq, Repr, Inhabited

/-- Where a probed value comes from.

$$\mathrm{Source} = \mathrm{generated}(f) \mid \mathrm{golden}(f) \mid \mathrm{exempt}(w),\quad f \in \mathrm{String},\ w \in \mathrm{Exempt}$$

A Lean-emitted file the site imports, a Lean golden file a test checks, or a stated exemption. -/
inductive Source
  | generated (file : String)
  | golden (file : String)
  | exempt (why : Exempt)
  deriving DecidableEq, Repr, Inhabited

/-- The evidence: repository files that exist and are linked (imported by the site, or read by a test).

$$\mathrm{Evidence} = \mathrm{String}^{*}$$ -/
abbrev Evidence := List String

/-- A source is valid when its file is in the evidence; an exemption is always valid.

$$\forall E, f, w,\quad \operatorname{ok}_E(\mathrm{generated}(f)) \iff f \in E,\qquad \operatorname{ok}_E(\mathrm{golden}(f)) \iff f \in E,\qquad \operatorname{ok}_E(\mathrm{exempt}(w)) = \mathrm{true}$$

A file claim counts only when the repository shows the link. -/
def Source.ok (ev : Evidence) : Source → Bool
  | .generated f => ev.contains f
  | .golden f => ev.contains f
  | .exempt _ => true

/-! ## Probes and claims -/

/-- One probed value: part, role, item kind, key, breakpoint class.

$$p = (\mathit{part},\ \rho,\ \mathit{cls},\ k,\ b) \in \mathrm{String}^{2} \times \mathrm{Cls} \times \mathrm{String}^{2}$$ -/
structure Probe where
  part : String
  role : String
  cls : Cls
  key : String
  bp : String
  deriving DecidableEq, Repr, Inhabited

/-- A string pattern: anything, exactly one string, or every string with a prefix.

$$\mathrm{Pat} = \ast \mid \mathrm{is}(s) \mid \mathrm{pre}(s)$$ -/
inductive Pat
  | any
  | is (s : String)
  | pre (s : String)
  deriving DecidableEq, Repr, Inhabited

/-- Whether a pattern matches a string.

$$\ast \models x,\qquad \mathrm{is}(s) \models x \iff x = s,\qquad \mathrm{pre}(s) \models x \iff s \sqsubseteq x \ (\text{$s$ is a prefix of $x$})$$ -/
def Pat.ok : Pat → String → Bool
  | .any, _ => true
  | .is s, x => x == s
  | .pre s, x => x.startsWith s

/-- A claim: one part, patterns for role, key and class, an optional kind (`none` = every kind), a source.

$$c = (\mathit{part},\ P_\rho,\ \kappa,\ P_k,\ P_b,\ s) \in \mathrm{String} \times \mathrm{Pat} \times \mathrm{Cls}_\bot \times \mathrm{Pat}^{2} \times \mathrm{Source}$$ -/
structure Claim where
  part : String
  role : Pat
  cls : Option Cls
  key : Pat
  bp : Pat
  src : Source
  deriving DecidableEq, Repr, Inhabited

/-- A claim hits a probe when the part is equal and every pattern matches.

$$\operatorname{hits}(c, p) \iff c.\mathit{part} = p.\mathit{part} \wedge c.P_\rho \models p.\rho \wedge (c.\kappa = \bot \vee c.\kappa = p.\mathit{cls}) \wedge c.P_k \models p.k \wedge c.P_b \models p.b$$ -/
def Claim.hits (c : Claim) (p : Probe) : Bool :=
  c.part == p.part && c.role.ok p.role && c.cls.all (· == p.cls) && c.key.ok p.key && c.bp.ok p.bp

/-- A claim is usable for a probe when its source is valid and it hits the probe.

$$\operatorname{use}_E(c, p) \iff \operatorname{ok}_E(c.s) \wedge \operatorname{hits}(c, p)$$ -/
def usable (ev : Evidence) (c : Claim) (p : Probe) : Bool := c.src.ok ev && c.hits p

/-- A probe is covered when some claim is usable for it.

$$\operatorname{covered}_E(C, p) \iff \exists c \in C,\ \operatorname{use}_E(c, p)$$ -/
def covered (ev : Evidence) (cs : List Claim) (p : Probe) : Bool := cs.any fun c => usable ev c p

/-- The source reported for a probe: the source of the first usable claim, in list order.

$$\operatorname{sourceOf}_E(C, p) = \begin{cases} c.s & c \text{ is the first element of } C \text{ (in list order) with } \operatorname{use}_E(c, p) \\ \bot & \text{there is none} \end{cases}$$ -/
def sourceOf (ev : Evidence) (cs : List Claim) (p : Probe) : Option Source :=
  (cs.find? fun c => usable ev c p).map (·.src)

/-- The lint: the probes that no claim covers, in probe order.

$$\operatorname{lint}_E(C, P) = [\,p \in P \mid \neg\operatorname{covered}_E(C, p)\,]$$ -/
def lint (ev : Evidence) (cs : List Claim) (ps : List Probe) : List Probe :=
  ps.filter fun p => !covered ev cs p

/-! ## The probe set of a part -/

/-- The keys one role can be judged on: its count, each declared dimension, each compared style property.

$$\operatorname{roleKeys}(A, \rho, \Pi_\rho) = [(\mathrm{count}, \texttt{count})] \mathbin{+\!\!+} [(\mathrm{box}, d) \mid d \in \rho.D] \mathbin{+\!\!+} [(\mathrm{style}, k) \mid k \in \operatorname{compared}(A, \rho, R)],\quad R = \begin{cases} \Pi_\rho.P_{\mathrm{restated}} & \Pi_\rho \ne \bot \\ [\,] & \Pi_\rho = \bot \end{cases}$$

($\Pi_\rho$ is the role's optional recorded-property record, $\bot$ when the run recorded none.) -/
def roleKeys (a : Anchors) (rs : RoleSpec) (props : Option RoleProps) : List (Cls × String) :=
  (Cls.count, "count") :: (rs.dims.map fun d => (Cls.box, d)) ++
    ((comparedProps a rs ((props.map (·.restated)).getD [])).map fun k => (Cls.style, k))

/-- The probes of one part: per role (declared order), per key, per breakpoint class.

$$\operatorname{probes}(A, \pi, \Pi, B) = [\,(\pi.\mathit{id}, \rho.\mathrm{role}, \kappa, k, b) \mid \rho \in \pi.\mathrm{roles},\ (\kappa, k) \in \operatorname{roleKeys}(A, \rho, \Pi[\rho.\mathrm{role}]),\ b \in B\,]$$

($\Pi[\rho]$ is the first entry with key $\rho$, $\bot$ if none; list comprehension in nesting order.) -/
def partProbes (a : Anchors) (spec : PartSpec) (props : PartProps) (bps : List String) : List Probe :=
  spec.roles.flatMap fun rs => (roleKeys a rs (props.lookup rs.role)).flatMap fun ck =>
    bps.map fun b => ⟨spec.id, rs.role, ck.1, ck.2, b⟩

/-- The probes of all parts: the parts' probes concatenated in part order; a part with no recorded properties has
only count and box probes.

$$\operatorname{allProbes}(A, [\pi_1, \dots, \pi_n], \Pi, B) = \operatorname{probes}(A, \pi_1, \Pi[\pi_1.\mathit{id}], B) \mathbin{+\!\!+} \cdots \mathbin{+\!\!+} \operatorname{probes}(A, \pi_n, \Pi[\pi_n.\mathit{id}], B),$$

($\Pi$ is an association list; $\Pi[x]$ is the value of its first entry with key $x$, $[\,]$ if none; for $n = 0$ the
result is $[\,]$.) -/
def allProbes (a : Anchors) (specs : List PartSpec) (props : List (String × PartProps))
    (bps : List String) : List Probe :=
  specs.flatMap fun s => partProbes a s ((props.lookup s.id).getD []) bps

/-! ## Tally -/

/-- Counts per source kind.

$$t = (n_{\mathrm{gen}},\ n_{\mathrm{gold}},\ n_{\mathrm{ex}},\ n_{\mathrm{unc}}) \in \mathbb N^{4}$$ -/
structure Tally where
  generated : Nat
  golden : Nat
  exempt : Nat
  uncovered : Nat
  deriving DecidableEq, Repr, Inhabited

/-- Add one probe's reported source to a tally.

$$\operatorname{bump}(t, \mathrm{generated}(\_)) = t + e_{\mathrm{gen}},\ \operatorname{bump}(t, \mathrm{golden}(\_)) = t + e_{\mathrm{gold}},\ \operatorname{bump}(t, \mathrm{exempt}(\_)) = t + e_{\mathrm{ex}},\ \operatorname{bump}(t, \bot) = t + e_{\mathrm{unc}}$$ -/
def Tally.bump (t : Tally) : Option Source → Tally
  | some (.generated _) => { t with generated := t.generated + 1 }
  | some (.golden _) => { t with golden := t.golden + 1 }
  | some (.exempt _) => { t with exempt := t.exempt + 1 }
  | none => { t with uncovered := t.uncovered + 1 }

/-- The tally of a probe list: each probe counted once, by its reported source.

$$\operatorname{tally}_E(C, P) = \operatorname{foldl}(\lambda t\,p.\ \operatorname{bump}(t, \operatorname{sourceOf}_E(C, p)),\ (0,0,0,0),\ P)$$ -/
def tally (ev : Evidence) (cs : List Claim) (ps : List Probe) : Tally :=
  ps.foldl (fun t p => t.bump (sourceOf ev cs p)) ⟨0, 0, 0, 0⟩

/-! ## Theorems -/

/-- A probe is in the lint exactly when it is a probe and no claim covers it.

$$\forall E, C, P, p,\quad p \in \operatorname{lint}_E(C, P) \iff p \in P \wedge \neg\operatorname{covered}_E(C, p)$$

The lint reports uncovered probes and nothing else. -/
theorem mem_lint (ev : Evidence) (cs : List Claim) (ps : List Probe) (p : Probe) :
    p ∈ lint ev cs ps ↔ p ∈ ps ∧ covered ev cs p = false := by
  simp [lint, List.mem_filter]

/-- Covered means some claim in the list has a valid source and hits the probe.

$$\forall E, C, p,\quad \operatorname{covered}_E(C, p) \iff \exists c \in C,\ \operatorname{ok}_E(c.s) \wedge \operatorname{hits}(c, p)$$ -/
theorem covered_iff (ev : Evidence) (cs : List Claim) (p : Probe) :
    covered ev cs p = true ↔ ∃ c ∈ cs, c.src.ok ev = true ∧ c.hits p = true := by
  simp [covered, usable, List.any_eq_true]

/-- **Soundness of the lint.** The lint is empty exactly when every probe has a source.

$$\forall E, C, P,\quad \operatorname{lint}_E(C, P) = [\,] \iff \forall p \in P,\ \exists c \in C,\ \operatorname{ok}_E(c.s) \wedge \operatorname{hits}(c, p)$$

An empty lint means every probed value has a generated, golden or exempt source. -/
theorem coverage_lint_sound (ev : Evidence) (cs : List Claim) (ps : List Probe) :
    lint ev cs ps = [] ↔ ∀ p ∈ ps, ∃ c ∈ cs, c.src.ok ev = true ∧ c.hits p = true := by
  constructor
  · intro h p hp
    cases hc : covered ev cs p
    · have : p ∈ lint ev cs ps := (mem_lint ev cs ps p).mpr ⟨hp, hc⟩
      rw [h] at this
      cases this
    · exact (covered_iff ev cs p).mp hc
  · intro h
    apply List.eq_nil_iff_forall_not_mem.mpr
    intro p hp
    obtain ⟨hp, hc⟩ := (mem_lint ev cs ps p).mp hp
    have := (covered_iff ev cs p).mpr (h p hp)
    rw [hc] at this
    cases this

/-- The reported source exists exactly when the probe is covered.

$$\forall E, C, p,\quad \operatorname{sourceOf}_E(C, p) \ne \bot \iff \operatorname{covered}_E(C, p)$$ -/
theorem sourceOf_isSome_iff (ev : Evidence) (cs : List Claim) (p : Probe) :
    (sourceOf ev cs p).isSome = true ↔ covered ev cs p = true := by
  simp only [sourceOf, Option.isSome_map, covered]
  rw [List.find?_isSome]
  simp [List.any_eq_true]

/-- The lint is empty exactly when every probe has a reported source.

$$\forall E, C, P,\quad \operatorname{lint}_E(C, P) = [\,] \iff \forall p \in P,\ \operatorname{sourceOf}_E(C, p) \ne \bot$$ -/
theorem lint_nil_iff_sourceOf (ev : Evidence) (cs : List Claim) (ps : List Probe) :
    lint ev cs ps = [] ↔ ∀ p ∈ ps, (sourceOf ev cs p).isSome = true := by
  rw [coverage_lint_sound]
  refine forall_congr' fun p => forall_congr' fun _ => ?_
  rw [sourceOf_isSome_iff, covered_iff]

/-- A reported source comes from a claim in the list whose source is valid and that hits the probe.

$$\forall E, C, p, s,\quad \operatorname{sourceOf}_E(C, p) = s \implies \exists c \in C,\ c.s = s \wedge \operatorname{ok}_E(s) \wedge \operatorname{hits}(c, p)$$

The table never shows a source that the claims and the evidence do not give. -/
theorem sourceOf_sound (ev : Evidence) (cs : List Claim) (p : Probe) (s : Source)
    (h : sourceOf ev cs p = some s) : ∃ c ∈ cs, c.src = s ∧ s.ok ev = true ∧ c.hits p = true := by
  simp only [sourceOf, Option.map_eq_some_iff] at h
  obtain ⟨c, hf, rfl⟩ := h
  have hm := List.mem_of_find?_eq_some hf
  have hu := List.find?_some hf
  simp only [usable, Bool.and_eq_true] at hu
  exact ⟨c, hm, rfl, hu.1, hu.2⟩

/-- Filtering with a weaker condition keeps a sublist.

$$\forall \alpha,\ \forall P \in \alpha^{*},\ \forall q, q' : \alpha \to \mathbb{B},\quad (\forall p,\ q'(p) \implies q(p)) \implies [\,p \in P \mid q'(p)\,] \text{ is a sublist of } [\,p \in P \mid q(p)\,]$$

(The brackets are order-preserving list filters.) -/
theorem filter_sublist_of_imp {α : Type} (ps : List α) (q q' : α → Bool)
    (h : ∀ p, q' p = true → q p = true) : (ps.filter q').Sublist (ps.filter q) := by
  induction ps with
  | nil => exact List.Sublist.slnil
  | cons x xs ih =>
    by_cases hx : q' x = true
    · have hq := h x hx
      simp only [List.filter_cons, hx, hq, ite_true]
      exact ih.cons_cons x
    · simp only [List.filter_cons, hx]
      by_cases hq : q x = true
      · simp only [hq, ite_true, Bool.false_eq_true, ite_false]; exact ih.cons x
      · simp only [hq, Bool.false_eq_true, ite_false]; exact ih

/-- **Monotonicity.** More claims and more evidence never add a failure: the new lint is a sublist of the old one.

$$\forall E, E', C, C', P,\quad E \subseteq E' \wedge C \subseteq C' \implies \operatorname{lint}_{E'}(C', P) \text{ is a sublist of } \operatorname{lint}_E(C, P)$$

($\subseteq$ is membership inclusion of lists.) Adding a source can only remove probes from the lint. -/
theorem lint_monotone (ev ev' : Evidence) (cs cs' : List Claim) (ps : List Probe)
    (hev : ∀ f, f ∈ ev → f ∈ ev') (hcs : ∀ c, c ∈ cs → c ∈ cs') :
    (lint ev' cs' ps).Sublist (lint ev cs ps) := by
  apply filter_sublist_of_imp
  intro p h
  simp only [Bool.not_eq_eq_eq_not, Bool.not_true] at h ⊢
  cases e : covered ev cs p
  · rfl
  · obtain ⟨c, hc, hok, hhit⟩ := (covered_iff ev cs p).mp e
    have hok' : c.src.ok ev' = true := by
      cases hs : c.src with
      | generated f => rw [hs] at hok; simp [Source.ok] at hok ⊢; exact hev f hok
      | golden f => rw [hs] at hok; simp [Source.ok] at hok ⊢; exact hev f hok
      | exempt w => rfl
    have := (covered_iff ev' cs' p).mpr ⟨c, hcs c hc, hok', hhit⟩
    rw [h] at this
    cases this

/-- Adding one claim never adds a failure.

$$\forall E, C, c, P,\quad \operatorname{lint}_E(c :: C, P) \text{ is a sublist of } \operatorname{lint}_E(C, P)$$ -/
theorem lint_cons_sublist (ev : Evidence) (c : Claim) (cs : List Claim) (ps : List Probe) :
    (lint ev (c :: cs) ps).Sublist (lint ev cs ps) :=
  lint_monotone ev ev cs (c :: cs) ps (fun _ h => h) (fun _ h => List.mem_cons_of_mem c h)

/-- The lint of concatenated probe lists is the concatenation of the lints (the per-part lints make the whole).

$$\forall E, C, P, Q,\quad \operatorname{lint}_E(C, P \mathbin{+\!\!+} Q) = \operatorname{lint}_E(C, P) \mathbin{+\!\!+} \operatorname{lint}_E(C, Q)$$ -/
theorem lint_append (ev : Evidence) (cs : List Claim) (ps qs : List Probe) :
    lint ev cs (ps ++ qs) = lint ev cs ps ++ lint ev cs qs := by
  simp [lint, List.filter_append]

/-- Claims of other parts never cover a probe: covering is decided by the probe's own part's claims.

$$\forall E, C, p,\quad \operatorname{covered}_E(C, p) = \operatorname{covered}_E([\,c \in C \mid c.\mathit{part} = p.\mathit{part}\,], p)$$ -/
theorem covered_part_local (ev : Evidence) (cs : List Claim) (p : Probe) :
    covered ev cs p = covered ev (cs.filter fun c => c.part == p.part) p := by
  apply Bool.eq_iff_iff.mpr
  rw [covered_iff, covered_iff]
  constructor
  · rintro ⟨c, hc, hok, hhit⟩
    refine ⟨c, List.mem_filter.mpr ⟨hc, ?_⟩, hok, hhit⟩
    simp only [Claim.hits, Bool.and_eq_true] at hhit
    exact hhit.1.1.1.1
  · rintro ⟨c, hc, hok, hhit⟩
    exact ⟨c, (List.mem_filter.mp hc).1, hok, hhit⟩

/-! ## The probe set matches what the gate judges -/

/-- Every compared item of a role is one of the role's keys.

$$\forall A, \rho, \Pi_\rho, q_o, q_r, o, r,\ \forall it \in \operatorname{roleItems}(A, \rho, \Pi_\rho, q_o, q_r, o, r),\quad it.\mathrm{cls} \ne \mathrm{info} \implies it.\rho = \rho.\mathrm{role} \wedge (it.\mathrm{cls}, it.k) \in \operatorname{roleKeys}(A, \rho, \Pi_\rho)$$

($\Pi_\rho$ is the role's optional recorded-property record.) -/
theorem roleItems_mem_roleKeys {a : Anchors} {rs : RoleSpec} {props : Option RoleProps}
    {refO refR : Option Rect} {o r : Option RoleRaw} {it : PItem}
    (h : it ∈ roleItems a rs props refO refR o r) (hc : it.cls ≠ .info) :
    it.role = rs.role ∧ (it.cls, it.key) ∈ roleKeys a rs props := by
  unfold roleItems at h
  split at h
  · simp only [List.mem_cons] at h
    rcases h with rfl | h
    · exact ⟨rfl, by simp [roleKeys]⟩
    · obtain ⟨j, x, y, hj⟩ := mem_pairs h
      simp only [itemAt, List.mem_append, List.mem_map] at hj
      rcases hj with (⟨d, hd, rfl⟩ | ⟨p, hp, rfl⟩) | ⟨p, hp, rfl⟩
      · refine ⟨rfl, ?_⟩
        simp only [roleKeys, List.mem_cons, List.mem_append, List.mem_map]
        exact .inl (.inr ⟨d, hd, rfl⟩)
      · refine ⟨rfl, ?_⟩
        simp only [roleKeys, List.mem_cons, List.mem_append, List.mem_map]
        exact .inr ⟨p, cmpAt_subset _ _ _ _ hp, rfl⟩
      · exact absurd rfl hc
  · simp only [List.mem_singleton] at h
    subst h
    exact ⟨rfl, by simp [roleKeys]⟩

/-- **The probe set is complete.** Every item the gate can judge for a part, in any sampled state, is a probe of
the part at every listed class.

$$\forall A, \pi, o, r, \Pi, B,\ \forall it \in \operatorname{partItems}(A, \pi, o, r, \Pi),\ \forall b \in B,\quad it.\mathrm{cls} \ne \mathrm{info} \implies (\pi.\mathit{id}, it.\rho, it.\mathrm{cls}, it.k, b) \in \operatorname{probes}(A, \pi, \Pi, B)$$ -/
theorem judged_mem_partProbes (a : Anchors) (spec : PartSpec) (o r : Option PartRaw) (props : PartProps)
    (bps : List String) (it : PItem) (hit : it ∈ partItems a spec o r props) (hc : it.cls ≠ .info)
    (b : String) (hb : b ∈ bps) :
    (⟨spec.id, it.role, it.cls, it.key, b⟩ : Probe) ∈ partProbes a spec props bps := by
  simp only [partItems, List.mem_flatMap] at hit
  obtain ⟨rs, hrs, hit⟩ := hit
  obtain ⟨hrole, hk⟩ := roleItems_mem_roleKeys hit hc
  simp only [partProbes, List.mem_flatMap, List.mem_map]
  exact ⟨rs, hrs, (it.cls, it.key), hk, b, hb, by rw [hrole]⟩

/-- **An empty lint covers every judged item.** If the lint of a part's probes is empty, then every item the gate
can judge for that part, in any sampled state, at any listed class, has a valid source.

$$\forall E, C, A, \pi, \Pi, B,\quad \operatorname{lint}_E(C, \operatorname{probes}(A, \pi, \Pi, B)) = [\,] \implies \forall o, r,\ \forall it \in \operatorname{partItems}(A, \pi, o, r, \Pi),\ \forall b \in B,\ it.\mathrm{cls} \ne \mathrm{info} \implies \exists c \in C,\ \operatorname{ok}_E(c.s) \wedge \operatorname{hits}(c, (\pi.\mathit{id}, it.\rho, it.\mathrm{cls}, it.k, b))$$ -/
theorem lint_nil_judged_sourced (ev : Evidence) (cs : List Claim) (a : Anchors) (spec : PartSpec)
    (props : PartProps) (bps : List String) (h : lint ev cs (partProbes a spec props bps) = [])
    (o r : Option PartRaw) (it : PItem) (hit : it ∈ partItems a spec o r props) (b : String)
    (hb : b ∈ bps) (hc : it.cls ≠ .info) :
    ∃ c ∈ cs, c.src.ok ev = true ∧ c.hits ⟨spec.id, it.role, it.cls, it.key, b⟩ = true :=
  (coverage_lint_sound ev cs _).mp h _ (judged_mem_partProbes a spec o r props bps it hit hc b hb)

/-- The lint of all parts is the concatenation of the per-part lints.

$$\forall E, C, A, \Pi, B,\ \forall \pi_1, \dots, \pi_n,\quad \operatorname{lint}_E(C, \operatorname{allProbes}(A, [\pi_1, \dots, \pi_n], \Pi, B)) = \operatorname{lint}_E(C, \operatorname{probes}(A, \pi_1, \Pi[\pi_1.\mathit{id}], B)) \mathbin{+\!\!+} \cdots \mathbin{+\!\!+} \operatorname{lint}_E(C, \operatorname{probes}(A, \pi_n, \Pi[\pi_n.\mathit{id}], B))$$

($\Pi[x]$ is the value of the first entry of $\Pi$ with key $x$, $[\,]$ if none; both sides are $[\,]$ for $n = 0$.) The per-part table loses and adds nothing. -/
theorem lint_allProbes (ev : Evidence) (cs : List Claim) (a : Anchors) (specs : List PartSpec)
    (props : List (String × PartProps)) (bps : List String) :
    lint ev cs (allProbes a specs props bps) =
      specs.flatMap fun s => lint ev cs (partProbes a s ((props.lookup s.id).getD []) bps) := by
  induction specs with
  | nil => rfl
  | cons s ss ih => simp only [allProbes, List.flatMap_cons, lint_append] at ih ⊢; rw [ih]

/-! ## Tally -/

/-- The total of a tally.

$$\operatorname{total}(t) = n_{\mathrm{gen}} + n_{\mathrm{gold}} + n_{\mathrm{ex}} + n_{\mathrm{unc}}$$ -/
def Tally.total (t : Tally) : Nat := t.generated + t.golden + t.exempt + t.uncovered

/-- One bump adds one to the total.

$$\forall t, s,\quad \operatorname{total}(\operatorname{bump}(t, s)) = \operatorname{total}(t) + 1$$ -/
theorem Tally.total_bump (t : Tally) (s : Option Source) : (t.bump s).total = t.total + 1 := by
  cases s with
  | none => simp [Tally.bump, Tally.total]; omega
  | some s => cases s <;> simp [Tally.bump, Tally.total] <;> omega

/-- The uncovered count grows exactly on an absent source.

$$\forall t, s,\quad \operatorname{bump}(t, s).n_{\mathrm{unc}} = t.n_{\mathrm{unc}} + \begin{cases} 1 & s = \bot \\ 0 & s \ne \bot \end{cases}$$ -/
theorem Tally.uncovered_bump (t : Tally) (s : Option Source) :
    (t.bump s).uncovered = t.uncovered + (if s.isNone then 1 else 0) := by
  cases s with
  | none => rfl
  | some s => cases s <;> rfl

/-- Folding the tally from a start adds the probe count to the start's total.

$$\forall E, C, P, t_0,\quad \operatorname{total}(\operatorname{foldl}(\lambda t\,p.\ \operatorname{bump}(t, \operatorname{sourceOf}_E(C, p)),\ t_0,\ P)) = \operatorname{total}(t_0) + |P|$$ -/
theorem tally_foldl_total (ev : Evidence) (cs : List Claim) (ps : List Probe) (t : Tally) :
    (ps.foldl (fun t p => t.bump (sourceOf ev cs p)) t).total = t.total + ps.length := by
  induction ps generalizing t with
  | nil => rfl
  | cons p ps ih => simp only [List.foldl_cons, List.length_cons]; rw [ih, Tally.total_bump]; omega

/-- Folding the tally from a start adds the lint length to the start's uncovered count.

$$\forall E, C, P, t_0,\quad \operatorname{foldl}(\lambda t\,p.\ \operatorname{bump}(t, \operatorname{sourceOf}_E(C, p)),\ t_0,\ P).n_{\mathrm{unc}} = t_0.n_{\mathrm{unc}} + |\operatorname{lint}_E(C, P)|$$ -/
theorem tally_foldl_uncovered (ev : Evidence) (cs : List Claim) (ps : List Probe) (t : Tally) :
    (ps.foldl (fun t p => t.bump (sourceOf ev cs p)) t).uncovered =
      t.uncovered + (lint ev cs ps).length := by
  induction ps generalizing t with
  | nil => rfl
  | cons p ps ih =>
    simp only [List.foldl_cons]
    rw [ih, Tally.uncovered_bump]
    have hs : (sourceOf ev cs p).isNone = !covered ev cs p := by
      have := sourceOf_isSome_iff ev cs p
      cases hc : covered ev cs p <;> cases ho : sourceOf ev cs p <;> simp_all
    rw [hs]
    simp only [lint, List.filter_cons]
    cases covered ev cs p <;> simp <;> omega

/-- **The tally adds up.** Every probe is counted exactly once, and the uncovered count is the lint length.

$$\forall E, C, P,\quad \operatorname{total}(\operatorname{tally}_E(C, P)) = |P| \ \wedge\ \operatorname{tally}_E(C, P).n_{\mathrm{unc}} = |\operatorname{lint}_E(C, P)|$$ -/
theorem tally_total (ev : Evidence) (cs : List Claim) (ps : List Probe) :
    (tally ev cs ps).total = ps.length ∧ (tally ev cs ps).uncovered = (lint ev cs ps).length := by
  constructor
  · rw [tally, tally_foldl_total]; simp [Tally.total]
  · rw [tally, tally_foldl_uncovered]; simp

/-! ## The claims of the repository

Seeded by `lean-coverage` (2026-10-18) from the parts on `ci/integrate-ports`: a `golden` claim only where the part's
driver writes that property on that role from a function its `logic.test.ts` checks against the part's golden file
(INFERRED from the source, element to role by reading `index.tsx`/`driver.ts`), and `engineDefault` for the
document boxes whose width is the viewport. Everything else is uncovered on purpose: no hand value is exempted here.
`fix-proofs` adds claims (generated or golden) part by part. -/

/-- The golden vector file of a part.

$$\operatorname{partGolden}(\pi) = \mathrm{golden}(\texttt{packages/contracts/golden/parts/}\,\pi\,\texttt{.jsonl})$$ -/
def partGolden (part : String) : Source := .golden s!"packages/contracts/golden/parts/{part}.jsonl"

/-- A golden claim on one style property of one role, at every class.

$$\operatorname{styleGolden}(\pi, \rho, k) = (\pi,\ \mathrm{is}(\rho),\ \mathrm{style},\ \mathrm{is}(k),\ \mathrm{any},\ \operatorname{partGolden}(\pi))$$ -/
def styleGolden (part role key : String) : Claim :=
  ⟨part, .is role, some .style, .is key, .any, partGolden part⟩

/-- The repository's claims (see the section header for how they were chosen).

$$C_{\mathrm{repo}} = [\,c_1, \dots, c_{n}\,] \quad \text{(the literal list below)}$$

The source table `fw coverage` lints the gate's probes against. -/
def claims : List Claim :=
  [ -- engine layout: the document's width is the viewport width (one claim per role: no wildcard over engine.scroll)
    ⟨"engine.scroll", .is "scroller", some .box, .is "w", .any, .exempt .engineDefault⟩,
    ⟨"engine.scroll", .is "content", some .box, .is "w", .any, .exempt .engineDefault⟩,
    -- the page-root anchor (Fw.Gate.PageRoot): the clip rule is transcribed from the snapshot, only the gate checks it
    ⟨"engine.scroll", .is "pageRoot", some .box, .is Fw.Gate.PageRoot.itemKey, .any, .exempt .transcribedEmpiricalOnly⟩,
    ⟨"morph.tween", .is "scroller", some .box, .is "w", .any, .exempt .engineDefault⟩,
    -- driver-written values from golden-checked logic
    styleGolden "commission" "runway" "height",
    styleGolden "commission" "section" "--commission-enter-shrink",
    styleGolden "commission" "section" "--commission-shrink",
    styleGolden "commission.typing" "progress" "width",
    styleGolden "commission.typing" "scale" "--visual-scale",
    styleGolden "hero.countdown" "digit" "transform",
    -- the variant role of `strip` (`Fw.Gate.partItems_variant_role`): one strip per digit, the digit count from `digitPlaces`
    ⟨"hero.countdown", .is "strip", some .count, .is "count", .any, partGolden "hero.countdown"⟩,
    styleGolden "hero.exit" "hero" "--exit-opacity",
    styleGolden "hero.exit" "hero" "pointer-events",
    styleGolden "hero.orbit" "card" "--orbit-enter-x",
    styleGolden "hero.orbit" "card" "--orbit-enter-y",
    styleGolden "hero.orbit" "card" "--orbit-start-rot",
    styleGolden "hero.orbit" "orbit" "--ring-motion-blur",
    styleGolden "overlays.signup" "dialog" "--dialog-dir-x",
    styleGolden "overlays.signup" "dialog" "--dialog-dir-y",
    styleGolden "pain.notes" "note" "left",
    styleGolden "pain.notes" "note" "top",
    styleGolden "pain.notes" "note" "z-index",
    styleGolden "people.card" "section" "--future-shrink",
    styleGolden "people.deck" "shell" "transform",
    styleGolden "people.deck" "shell" "transform-origin",
    styleGolden "people.deck" "sticky" "--profile-scale",
    styleGolden "platform" "section" "--platform-shrink" ]

/-- **No wildcard over `engine.scroll`.** Every claim of part `engine.scroll` names its role, so a role added to the part is
uncovered until a claim names it.

$$\forall c \in C_{\mathrm{repo}},\ c.\mathit{part} = \texttt{engine.scroll} \implies c.P_\rho \ne \ast$$ -/
theorem engine_scroll_no_wildcard : ∀ c ∈ claims, c.part = "engine.scroll" → c.role ≠ Pat.any := by
  decide

/-- **The page-root anchor has its row.** Every item `Fw.Gate.PageRoot` adds to a state, at every breakpoint class and under
any evidence, is covered by a claim of the repository.

$$\forall E, q, o, r, b,\ \forall it \in \operatorname{items}_q(o, r),\ \operatorname{covered}_E(C_{\mathrm{repo}}, (\texttt{engine.scroll}, it.\rho, it.\mathrm{cls}, it.k, b))$$ -/
theorem pageRootItems_covered (ev : Evidence) (req : Rat) (o r : Option Rat) (b : String)
    (it : PItem) (h : it ∈ PageRoot.pageRootItems req o r) :
    covered ev claims ⟨PageRoot.partId, it.role, it.cls, it.key, b⟩ = true := by
  unfold PageRoot.pageRootItems at h
  split at h
  · simp at h
  · simp only [List.mem_singleton] at h
    subst h
    simp [covered, claims, usable, Claim.hits, Pat.ok, PageRoot.partId, PageRoot.itemKey, PageRoot.pageRootItem, Source.ok, styleGolden]

/-- A pattern is wire-safe unless it is an exact pattern that ends in `*` (the wire spelling of `any` and of a prefix).

$$\operatorname{wireSafe}(\mathrm{is}(s)) \iff \neg(\texttt{*} \text{ is a suffix of } s) \wedge s \ne \texttt{*},\qquad \operatorname{wireSafe}(\mathrm{any}) = \operatorname{wireSafe}(\mathrm{pre}(s)) = \mathrm{true}$$ -/
def patWireSafe : Pat → Bool
  | .is s => !s.endsWith "*" && s != "*"
  | _ => true

#guard claims.all fun c => patWireSafe c.role && patWireSafe c.key && patWireSafe c.bp

/-! ## Examples -/

#guard Pat.any.ok "x" && (Pat.is "a").ok "a" && !(Pat.is "a").ok "ab" && (Pat.pre "trans").ok "transform" &&
  !(Pat.pre "trans").ok "tran"

/-- Example anchors: skip prefix `animation`, skip set `layout = [width]`.

$$A_{\mathrm{ex}} = (\text{prefixes } [\texttt{animation}],\ \text{sets } [\texttt{layout} \mapsto [\texttt{width}]])$$ -/
def exA : Anchors := ⟨[⟨"animation", "owned elsewhere"⟩], [⟨"layout", ["width"], "layout"⟩]⟩

/-- Example part: role `r` with dimension `h`, skip set `layout`, skipped `top`.

$$\pi_{\mathrm{ex}} = (\texttt{p},\ [\,(\texttt{r},\ D = [\texttt{h}],\ \text{sets } [\texttt{layout}],\ \text{skip } [\texttt{top}])\,])$$ -/
def exSpec : PartSpec := ⟨"p", [⟨"r", none, ["h"], ["layout"], ["top"], [], "example"⟩]⟩

#guard roleKeys exA exSpec.roles[0]! (some ⟨["color", "width", "top", "animation-name"], []⟩) ==
  [(.count, "count"), (.box, "h"), (.style, "color")]
#guard roleKeys exA exSpec.roles[0]! none == [(.count, "count"), (.box, "h")]
#guard (partProbes exA exSpec [] ["d", "t"]).length == 4
#guard partProbes exA exSpec [] [] == []

/-- Example probe.

$$p_{\mathrm{ex}} = (\texttt{p}, \texttt{r}, \mathrm{style}, \texttt{color}, \texttt{d})$$ -/
def exP : Probe := ⟨"p", "r", .style, "color", "d"⟩

#guard (⟨"p", .any, none, .any, .any, .exempt .engineDefault⟩ : Claim).hits exP
#guard !(⟨"q", .any, none, .any, .any, .exempt .engineDefault⟩ : Claim).hits exP
#guard !(⟨"p", .any, some .box, .any, .any, .exempt .engineDefault⟩ : Claim).hits exP
#guard !(⟨"p", .any, none, .any, .is "t", .exempt .engineDefault⟩ : Claim).hits exP
#guard !covered [] [⟨"p", .any, none, .any, .any, .golden "g"⟩] exP
#guard covered ["g"] [⟨"p", .any, none, .any, .any, .golden "g"⟩] exP
#guard sourceOf ["g"] [⟨"p", .any, none, .any, .any, .generated "f"⟩, ⟨"p", .any, none, .any, .any, .golden "g"⟩] exP ==
  some (.golden "g")
#guard lint [] [] [exP] == [exP] && lint [] [⟨"p", .any, none, .pre "co", .any, .exempt .hoverDependent⟩] [exP] == []
#guard tally [] [] [exP, exP] == ⟨0, 0, 0, 2⟩
#guard (allProbes exA [exSpec] [("p", [("r", ⟨["color"], []⟩)])] ["d"]).length == 3

end Fw.Gate.Coverage

/-! ## Golden vectors (`packages/contracts/golden/gate/coverage.jsonl`)

Serialisation only, so it lives under `Fw.Wire` (outside the math view, like the other golden writers). -/

namespace Fw.Wire.Coverage.Golden
open Lean Fw.Gate Fw.Gate.Coverage

-- Wire name of an item kind.
def clsName : Cls → String
  | .count => "count" | .box => "box" | .style => "style" | .info => "info"

-- Wire name of an exemption reason.
def exemptName : Exempt → String
  | .transcribedEmpiricalOnly => "transcribedEmpiricalOnly" | .hoverDependent => "hoverDependent"
  | .eventCount => "eventCount" | .engineDefault => "engineDefault"

-- Every exemption reason, in declaration order.
def exemptAll : List Exempt := [.transcribedEmpiricalOnly, .hoverDependent, .eventCount, .engineDefault]

-- Wire spelling of a pattern: `*`, `s*` (prefix) or `s`.
def patStr : Pat → String
  | .any => "*" | .pre s => s ++ "*" | .is s => s

-- A source as JSON.
def sourceJson : Source → Json
  | .generated f => Json.mkObj [("kind", "generated"), ("file", .str f)]
  | .golden f => Json.mkObj [("kind", "golden"), ("file", .str f)]
  | .exempt w => Json.mkObj [("kind", "exempt"), ("why", .str (exemptName w))]

-- A claim as JSON.
def claimJson (c : Claim) : Json :=
  Json.mkObj [("part", .str c.part), ("role", .str (patStr c.role)),
    ("cls", .str ((c.cls.map clsName).getD "*")), ("key", .str (patStr c.key)), ("bp", .str (patStr c.bp)),
    ("src", sourceJson c.src)]

-- A probe as JSON.
def probeJson (p : Probe) : Json :=
  Json.mkObj [("part", .str p.part), ("role", .str p.role), ("cls", .str (clsName p.cls)), ("key", .str p.key),
    ("bp", .str p.bp)]

-- A list of strings as JSON.
def strs (l : List String) : Json := .arr (l.map Json.str).toArray

-- Anchors and part specs in the `anchors.json` shape (`style`, `parts`).
def anchorsJson (a : Anchors) (specs : List PartSpec) : Json :=
  Json.mkObj [
    ("style", Json.mkObj [
      ("skipPrefixes", .arr (a.skipPrefixes.map fun q => Json.mkObj [("prefix", .str q.pre), ("why", .str q.why)]).toArray),
      ("skipSets", Json.mkObj (a.skipSets.map fun s => (s.name, Json.mkObj [("props", strs s.props), ("why", .str s.why)])))]),
    ("parts", Json.mkObj (specs.map fun s => (s.id, Json.mkObj [("roles", .arr (s.roles.map fun r =>
      Json.mkObj [("role", .str r.role), ("boxRel", Json.null), ("dims", strs r.dims), ("skipSets", strs r.skipSets),
        ("skipProps", strs r.skipProps), ("skipIfInline", strs r.skipIfInline), ("why", .str r.why)]).toArray)])))]

-- Recorded properties in the run-header shape (`header.props`).
def propsJson (props : List (String × PartProps)) : Json :=
  Json.mkObj (props.map fun (pid, pp) => (pid, Json.mkObj (pp.map fun (role, rp) =>
    (role, Json.mkObj [("restated", strs rp.restated), ("originOnly", strs rp.originOnly)]))))

-- One golden case: anchors, specs (sorted by id, as a JSON object reads back), recorded properties, classes,
-- evidence, claims.
structure Case where
  name : String
  a : Anchors
  specs : List PartSpec
  props : List (String × PartProps)
  bps : List String
  ev : Evidence
  cs : List Claim

-- A case and Lean's outputs as one JSON line.
def caseJson (k : Case) : Json :=
  let ps := allProbes k.a k.specs k.props k.bps
  let t := tally k.ev k.cs ps
  Json.mkObj [("kind", "case"), ("name", .str k.name),
    ("input", Json.mkObj [("anchors", anchorsJson k.a k.specs), ("props", propsJson k.props),
      ("bps", strs k.bps), ("evidence", strs k.ev), ("claims", .arr (k.cs.map claimJson).toArray)]),
    ("output", Json.mkObj [("probes", .arr (ps.map probeJson).toArray),
      ("lint", .arr ((lint k.ev k.cs ps).map probeJson).toArray),
      ("sources", .arr (ps.map fun p => ((sourceOf k.ev k.cs p).map sourceJson).getD Json.null).toArray),
      ("tally", Json.mkObj [("generated", toJson t.generated), ("golden", toJson t.golden),
        ("exempt", toJson t.exempt), ("uncovered", toJson t.uncovered)])])]

-- Two parts: `a` (prefix skip, skip set, own skip, a dimension) and `b` (two roles, one without properties).
def specs2 : List PartSpec :=
  [⟨"a", [⟨"r", none, ["h", "w"], ["layout"], ["top"], [], "role r"⟩]⟩,
   ⟨"b", [⟨"x", none, [], [], [], [], "role x"⟩, ⟨"y", none, ["x"], [], [], [], "role y"⟩]⟩]

-- Recorded properties for `specs2`: role `b.y` has none.
def props2 : List (String × PartProps) :=
  [("a", [("r", ⟨["animation-name", "color", "top", "transition-delay", "transition-duration", "width"], ["margin"]⟩)]),
   ("b", [("x", ⟨["--k", "opacity"], []⟩)])]

-- The golden cases.
def cases : List Case :=
  [ ⟨"no claims: every probe uncovered", exA, specs2, props2, ["desk", "touch"], [], []⟩,
    ⟨"no classes: no probes", exA, specs2, props2, [], [], [⟨"a", .any, none, .any, .any, .exempt .eventCount⟩]⟩,
    ⟨"no recorded properties: count and box only", exA, specs2, [], ["desk"], [], []⟩,
    ⟨"mixed claims and evidence", exA, specs2, props2, ["desk", "touch"], ["gold/a.jsonl"],
      [ ⟨"a", .is "r", some .style, .pre "transition-", .any, .golden "gold/a.jsonl"⟩,
        ⟨"a", .any, some .box, .is "h", .is "touch", .generated "gen/a.gen.css"⟩,
        ⟨"a", .any, some .box, .is "w", .any, .generated "gen/missing.gen.css"⟩,
        ⟨"a", .any, some .count, .any, .any, .exempt .engineDefault⟩,
        ⟨"b", .is "x", none, .is "--k", .any, .exempt .hoverDependent⟩,
        ⟨"b", .any, none, .any, .is "desk", .exempt .transcribedEmpiricalOnly⟩,
        ⟨"c", .any, none, .any, .any, .exempt .eventCount⟩ ]⟩,
    ⟨"first usable claim is reported", exA, specs2, props2, ["desk"], ["gen/a.gen.css", "gold/a.jsonl"],
      [ ⟨"a", .any, none, .is "color", .any, .generated "gen/absent.gen.css"⟩,
        ⟨"a", .any, none, .is "color", .any, .golden "gold/a.jsonl"⟩,
        ⟨"a", .any, none, .any, .any, .generated "gen/a.gen.css"⟩ ]⟩,
    ⟨"repository claims on a commission slice", ⟨[], []⟩,
      [⟨"commission", [⟨"runway", none, ["h"], [], [], [], "runway"⟩, ⟨"section", none, ["h"], [], [], [], "section"⟩]⟩],
      [("commission", [("runway", ⟨["height", "display"], []⟩), ("section", ⟨["--commission-shrink", "height"], []⟩)])],
      ["desktop"], ["packages/contracts/golden/parts/commission.jsonl"], claims⟩ ]

-- The golden text: a meta line, the repository claims, then one line per case.
def text : String :=
  let hd := Json.mkObj [("kind", "meta"), ("schema", "fw.gate.coverage/1"),
    ("exemptReasons", strs (exemptAll.map exemptName)),
    ("generatedBy", "lean/Fw/Gate/Coverage.lean (Fw.Wire.Coverage.Golden.run)")]
  let cl := Json.mkObj [("kind", "claims"), ("claims", .arr (claims.map claimJson).toArray)]
  String.join ((hd :: cl :: cases.map caseJson).map fun j => j.compress ++ "\n")

-- The golden file, relative to the repository root.
def path : System.FilePath := "packages" / "contracts" / "golden" / "gate" / "coverage.jsonl"

-- Write (or check) the golden file under `root` (the repository root); returns 1 when the check finds it stale.
def run (root : System.FilePath) (write : Bool) : IO UInt32 := do
  let p := root / path
  if write then
    IO.FS.writeFile p text
    IO.println s!"coverage golden: wrote {p} ({cases.length} cases, {claims.length} claims)"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur == text then
    IO.println s!"coverage golden: {p} is current"
    return 0
  IO.println s!"coverage golden: {p} is stale (regenerate: see docs/team/tools/coverage.md)"
  return 1

end Fw.Wire.Coverage.Golden
