import Lean.Data.Json

/-!
# Run keys: which counts run answers which row variant

`apps/runner/src/engine-check.ts` matches a prediction row to the counts runs by a variant name. A run of the rewrite with a
flag set (`meta.search = "?fw=..."`) answered to both its own key and to `rewrite`, so a flag run filled the base series
of every row whose base is `rewrite` (`proof-nav-hittest.md`, `proof-countdown-strip.md`). This module fixes the rule:
a run has exactly one faithful key, and a row variant is answered by it, with one named alias (`hidden-pause`).
`packages/engine-check` stages each run under the variant its key answers, and is checked against `goldenJsonl`.
-/

namespace Fw.Engine.Keys

/-- The two harness arguments a counts run records in `meta` (`packages/measure-chromium/src/run.mjs:312-317`).

$$\mathrm{RunMeta} = \mathrm{String} \times \mathrm{String}\quad(\mathrm{target}, \mathrm{search})$$

The page a run measured: `original` or `rewrite`, and the rewrite's query string (empty for the default config). -/
structure RunMeta where
  target : String
  search : String
  deriving DecidableEq, Repr

/-- The target contains no `+`, the separator of the key.

$$\operatorname{NoPlus}(s) \iff \texttt{+} \notin \operatorname{chars}(s)$$ -/
def NoPlus (s : String) : Prop := '+' ∉ s.toList

instance (s : String) : Decidable (NoPlus s) := inferInstanceAs (Decidable ('+' ∉ s.toList))

/-- **The faithful key of a run.** The target alone for a run without a query, else the target, a `+` and the query.

$$\operatorname{runKey}(t, s) = \begin{cases} t & s = \varepsilon \\ t \mathbin{+\!\!+} \texttt{+} \mathbin{+\!\!+} s & s \ne \varepsilon \end{cases}$$

One string per run; the default rewrite is `rewrite`, a flag run is `rewrite+?fw=...`. -/
def runKey (m : RunMeta) : String :=
  if m.search = "" then m.target else m.target ++ "+" ++ m.search

/-- The three parts that have a `hidden-pause` arm (`apps/site/src/parts/*/part.json`).

$$\mathrm{hiddenPauseArms} = [\texttt{engine.scene:hidden-pause}, \texttt{morph.columns:hidden-pause}, \texttt{morph.countdown:hidden-pause}]$$ -/
def hiddenPauseArms : List String :=
  ["engine.scene:hidden-pause", "morph.columns:hidden-pause", "morph.countdown:hidden-pause"]

/-- The query is `?fw=` followed by a nonempty comma list of `hidden-pause` arms and nothing else.

$$\operatorname{hpSearch}(s) \iff s = \texttt{?fw=}\mathbin{+\!\!+}\operatorname{join}(\texttt{,}, F) \land F \ne [\,] \land F \subseteq \mathrm{hiddenPauseArms}$$

A run that sets some of the three arms and no other flag. The empty flag list splits to `[""]`, which is no arm. -/
def hpSearch (s : String) : Bool :=
  s.startsWith "?fw=" && ((s.drop 4).toString.splitOn ",").all hiddenPauseArms.contains

/-- **The run answers the row variant.** A row variant is answered by the run whose faithful key equals it; the name
`hidden-pause` is answered by a rewrite run whose flags are a nonempty subset of the three arms (INFERRED: the golden
rows of `HiddenPause.lean` are `=o` and `≤o`, which each arm keeps, `Fw.Parts.HiddenPause`).

$$\operatorname{answers}(m, v) \iff \operatorname{runKey}(m) = v \ \lor\ (v = \texttt{hidden-pause} \land m.\mathrm{target} = \texttt{rewrite} \land \operatorname{hpSearch}(m.\mathrm{search}))$$ -/
def answers (m : RunMeta) (v : String) : Bool :=
  runKey m == v || (v == "hidden-pause" && m.target == "rewrite" && hpSearch m.search)

theorem list_split_plus : ∀ (a b c d : List Char),
    '+' ∉ a → '+' ∉ c → a ++ '+' :: b = c ++ '+' :: d → a = c ∧ b = d := by
  intro a
  induction a with
  | nil =>
    intro b c d _ hc h
    cases c with
    | nil => simpa using h
    | cons x c' =>
      have hx : '+' = x := (by simpa using h : _ ∧ _).1
      exact absurd (hx ▸ List.mem_cons_self) hc
  | cons x a' ih =>
    intro b c d ha hc h
    cases c with
    | nil =>
      have hx : x = '+' := (by simpa using h : _ ∧ _).1
      exact absurd (hx ▸ List.mem_cons_self) ha
    | cons y c' =>
      obtain ⟨hxy, h'⟩ := List.cons.inj h
      have ha' : '+' ∉ a' := fun hm => ha (List.mem_cons_of_mem _ hm)
      have hc' : '+' ∉ c' := fun hm => hc (List.mem_cons_of_mem _ hm)
      obtain ⟨h1, h2⟩ := ih b c' d ha' hc' h'
      exact ⟨by rw [hxy, h1], h2⟩

/-- **A run key determines its run.** If neither target contains `+`, two runs with the same key have the same target and
the same query.

$$\forall m, m':\ \operatorname{NoPlus}(m.\mathrm{target}) \land \operatorname{NoPlus}(m'.\mathrm{target}) \land \operatorname{runKey}(m) = \operatorname{runKey}(m') \Rightarrow m = m'$$

No two different runs share a key. -/
theorem runKey_inj (m m' : RunMeta) (h : NoPlus m.target) (h' : NoPlus m'.target)
    (e : runKey m = runKey m') : m = m' := by
  obtain ⟨t, s⟩ := m
  obtain ⟨t', s'⟩ := m'
  simp only [NoPlus] at h h'
  by_cases hs : s = "" <;> by_cases hs' : s' = "" <;> simp only [runKey, hs, hs', ite_true, ite_false] at e
  · subst hs hs'; simp [e]
  · exfalso
    have := congrArg String.toList e
    simp [String.toList_append] at this
    have hp : '+' ∈ t.toList := by rw [this]; simp
    exact h hp
  · exfalso
    have := congrArg String.toList e.symm
    simp [String.toList_append] at this
    have hp : '+' ∈ t'.toList := by rw [this]; simp
    exact h' hp
  · have e2 := congrArg String.toList e
    simp only [String.toList_append, List.append_assoc] at e2
    have e3 : t.toList ++ '+' :: s.toList = t'.toList ++ '+' :: s'.toList := by simpa using e2
    obtain ⟨h1, h2⟩ := list_split_plus _ _ _ _ h h' e3
    simp [String.ext_iff, h1, h2]

/-- **A flag run never answers for the base.** A run with a nonempty query does not answer `rewrite`, and `rewrite`
is answered exactly by the default rewrite run.

$$\forall m:\ \operatorname{NoPlus}(m.\mathrm{target}) \Rightarrow \big(\operatorname{answers}(m, \texttt{rewrite}) \iff m = (\texttt{rewrite}, \varepsilon)\big)$$

The base series of a row never mixes in a `+search` run. -/
theorem answers_base_iff (m : RunMeta) (h : NoPlus m.target) :
    answers m "rewrite" = true ↔ m = ⟨"rewrite", ""⟩ := by
  have hk : runKey ⟨"rewrite", ""⟩ = "rewrite" := by simp [runKey]
  have hnp : NoPlus "rewrite" := by decide
  constructor
  · intro ha
    simp only [answers, Bool.or_eq_true, beq_iff_eq, Bool.and_eq_true] at ha
    rcases ha with ha | ⟨⟨hv, _⟩, _⟩
    · exact runKey_inj m ⟨"rewrite", ""⟩ h hnp (by rw [hk]; exact ha)
    · exact absurd hv (by decide)
  · intro e
    subst e
    simp [answers, hk]

/-- **The key of a flag run answers itself.** Any run answers the variant that is its own key.

$$\forall m:\ \operatorname{answers}(m, \operatorname{runKey}(m))$$ -/
theorem answers_self (m : RunMeta) : answers m (runKey m) = true := by simp [answers]

/-- **Without the alias, the key decides.** For a row variant other than `hidden-pause`, a run answers it iff its key
equals it.

$$\forall m, v:\ v \ne \texttt{hidden-pause} \Rightarrow (\operatorname{answers}(m, v) \iff \operatorname{runKey}(m) = v)$$ -/
theorem answers_exact (m : RunMeta) (v : String) (hv : v ≠ "hidden-pause") :
    answers m v = true ↔ runKey m = v := by
  simp [answers, hv]

#guard hpSearch "?fw=engine.scene:hidden-pause"
#guard hpSearch "?fw=morph.columns:hidden-pause,morph.countdown:hidden-pause"
#guard !hpSearch "?fw="
#guard !hpSearch ""
#guard !hpSearch "?fw=engine.scene:hidden-pause,nav.hitTest:hit-skip"
#guard !hpSearch "?preset=x&fw=engine.scene:hidden-pause"
#guard answers ⟨"rewrite", "?fw=morph.columns:hidden-pause"⟩ "hidden-pause"
#guard !answers ⟨"rewrite", ""⟩ "hidden-pause"
#guard !answers ⟨"original", ""⟩ "hidden-pause"
#guard !answers ⟨"rewrite", "?fw=morph.tween:waapi"⟩ "rewrite"
#guard answers ⟨"rewrite", ""⟩ "rewrite"
#guard answers ⟨"rewrite", "?fw=morph.tween:waapi"⟩ "rewrite+?fw=morph.tween:waapi"
#guard !answers ⟨"rewrite", "?fw=nav.hitTest:hit-skip"⟩ "rewrite+?fw=nav.hitTest:elements-skip"

/-- The runs of the golden vectors: the default rewrite, the flag runs of task model-checks, a mixed flag set and the original.

$$\mathrm{goldenRuns} = [(\texttt{rewrite}, \varepsilon), (\texttt{rewrite}, \texttt{?fw=}F), \dots, (\texttt{original}, \varepsilon)]$$ -/
def goldenRuns : List RunMeta :=
  [⟨"rewrite", ""⟩, ⟨"rewrite", "?fw=morph.tween:waapi"⟩, ⟨"rewrite", "?fw=engine.scene:hidden-pause"⟩,
   ⟨"rewrite", "?fw=morph.columns:hidden-pause"⟩, ⟨"rewrite", "?fw=morph.countdown:hidden-pause"⟩,
   ⟨"rewrite", "?fw=engine.scene:hidden-pause,morph.columns:hidden-pause,morph.countdown:hidden-pause"⟩,
   ⟨"rewrite", "?fw=morph.mount:shift"⟩, ⟨"rewrite", "?fw=hero.countdown:strip,morph.countdown:strip"⟩,
   ⟨"rewrite", "?fw=nav.hitTest:hit-skip"⟩, ⟨"rewrite", "?fw=nav.hitTest:elements-skip"⟩,
   ⟨"rewrite", "?fw=engine.scene:hidden-pause,nav.hitTest:hit-skip"⟩, ⟨"original", ""⟩]

/-- The row variants of the golden vectors: the base, an exact flag key, the alias, the original.

$$\mathrm{goldenVariants} = [\texttt{rewrite}, \texttt{rewrite+?fw=morph.tween:waapi}, \texttt{rewrite+?fw=nav.hitTest:hit-skip}, \dots, \texttt{hidden-pause}, \texttt{original}]$$ -/
def goldenVariants : List String :=
  ["rewrite", "rewrite+?fw=morph.tween:waapi", "rewrite+?fw=nav.hitTest:hit-skip",
   "rewrite+?fw=hero.countdown:strip,morph.countdown:strip", "hidden-pause", "original"]

/-- One vector as compact JSON.

$$\operatorname{row}(m, v) = \{\mathrm{answers}: [\![\operatorname{answers}(m, v)]\!],\ \mathrm{key}: \operatorname{runKey}(m),\ \mathrm{search}: m.\mathrm{search},\ \mathrm{target}: m.\mathrm{target},\ \mathrm{variant}: v\}$$ -/
def goldenRow (m : RunMeta) (v : String) : String :=
  (Lean.Json.mkObj [("target", .str m.target), ("search", .str m.search), ("variant", .str v),
    ("key", .str (runKey m)), ("answers", .bool (answers m v))]).compress

/-- The golden file `packages/engine-check/golden/keys.jsonl`: one vector per (run, variant), runs outer.

$$\mathrm{goldenJsonl} = \mathop{\Vert}_{m \in \mathrm{goldenRuns}}\ \mathop{\Vert}_{v \in \mathrm{goldenVariants}} \big(\operatorname{row}(m, v) \mathbin{+\!\!+} \texttt{\textbackslash n}\big)$$ -/
def goldenJsonl : String :=
  String.join (goldenRuns.flatMap fun m => goldenVariants.map fun v => goldenRow m v ++ "\n")

#guard (goldenJsonl.splitOn "\n").length == goldenRuns.length * goldenVariants.length + 1

/-- Exactly one golden run answers `rewrite`: the default rewrite.

$$|\{\,m \in \mathrm{goldenRuns} \mid \operatorname{answers}(m, \texttt{rewrite})\,\}| = 1$$ -/
theorem golden_base_unique :
    (goldenRuns.filter fun m => answers m "rewrite").length = 1 := by decide

end Fw.Engine.Keys
