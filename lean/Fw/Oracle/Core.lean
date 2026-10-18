/-!
# Fw.Oracle.Core: typed questions to a System One model, and a proved policy over every outcome

An *oracle question* asks TypeSafe's Jev (a System One model: typed answers with probabilities, no free text) for a
judgement no script can make. This module fixes what we DO with any outcome, never whether the model is right:

- `Spec` is the answer type of a question (Choice over a finite option list with a no-match option, Noul, Score over
  ordered levels); `Raw` is the loosely-typed reply the wire parses; `validate` accepts exactly the well-typed answers
  (`validate_sound`, `validate_complete`).
- `policy` maps every outcome (an answer, or a failure: timeout, HTTP error, malformed, schema mismatch, over budget,
  no key, unredacted state) to an `Action`: `advise` or `escalate`. There is no other action, so oracle output can
  never be a land, push, delete, cancel or kill (`never_irreversible`, by the type).
- `calibrate` picks the least observed confidence whose precision on labeled replay rows reaches a target with at
  least `n` covered rows, or `none`; `none` means every answer escalates (`calibrate_none_escalates`).

Accuracy is MEASURED on replay data, never proved here: the theorems hold for every possible answer, right or wrong.

API facts used (CONFIRMED, https://docs.typesafe.ai/api.md and https://docs.typesafe.ai/confidence.md, read
2026-10-18): a Choice answer has `choice` (the highest-probability option) and `probabilities` (every option mapped to
a float, the floats sum to 1); a Noul answer has `noul` in [0, 1] and no confidence; a Score answer has
`probabilities` keyed by level index strings `"0"`…`"n-1"`; Choice confidence is
(p_max − 1/n)/(1 − 1/n), the Noul analogue is |2p − 1|, Score confidence is max(0, 1 − Σ p_i|i − m| / MAD_unif).
We recompute confidence from the validated probabilities and ignore the reported number.
-/
namespace Fw.Oracle

/-! ## Questions and answers -/

/-- The answer type of an oracle question: one option of a finite list (the list includes a no-match option `z`),
a yes/no probability, or a position on ordered levels (lowest first).

$$\mathrm{Spec} ::= \mathrm{choice}(O, z) \mid \mathrm{noul} \mid \mathrm{score}(L), \quad O, L \in \mathrm{String}^{*},\ z \in \mathrm{String}$$ -/
inductive Spec where
  | choice (options : List String) (noMatch : String)
  | noul
  | score (levels : List String)
deriving Repr, DecidableEq, Inhabited

/-- The tolerance on the sum of a reply's probabilities (the API returns floats that sum to 1 up to rounding).

$$\varepsilon = \tfrac{1}{1000}$$ -/
def eps : Rat := 1 / 1000

/-- The probability keys a reply must carry: the options of a Choice, the level indices `"0"`…`"n-1"` of a Score,
none for a Noul.

$$\mathrm{keys}(\mathrm{choice}(O, z)) = O, \quad \mathrm{keys}(\mathrm{noul}) = [\,], \quad \mathrm{keys}(\mathrm{score}(L)) = [\,\mathrm{str}(i) : 0 \le i < |L|\,]$$ -/
def Spec.keys : Spec → List String
  | .choice os _ => os
  | .noul => []
  | .score ls => (List.range ls.length).map toString

/-- A well-formed question: distinct keys; a Choice has 2 to 255 options (the API's maximum) and its no-match
option among them; a Score has 2 to 10 levels (the API's range).

$$\mathrm{wf}(\mathrm{choice}(O, z)) \iff \mathrm{nodup}(O) \land z \in O \land 2 \le |O| \le 255, \quad \mathrm{wf}(\mathrm{noul}), \quad \mathrm{wf}(\mathrm{score}(L)) \iff \mathrm{nodup}(\mathrm{keys}) \land 2 \le |L| \le 10$$ -/
def Spec.wf : Spec → Bool
  | .choice os z => decide os.Nodup && os.contains z && decide (2 ≤ os.length) && decide (os.length ≤ 255)
  | .noul => true
  | .score ls => decide ((List.range ls.length).map toString).Nodup && decide (2 ≤ ls.length) &&
      decide (ls.length ≤ 10)

/-- A validated answer: the pick of a Choice with the probabilities of its options (in option order), the yes
probability of a Noul, or the probabilities of a Score's levels (in level order).

$$\mathrm{Answer} ::= \mathrm{choice}(o, d) \mid \mathrm{noul}(p) \mid \mathrm{score}(d), \quad o \in \mathrm{String},\ d \in \mathbb{Q}^{*},\ p \in \mathbb{Q}$$ -/
inductive Answer where
  | choice (pick : String) (dist : List Rat)
  | noul (p : Rat)
  | score (dist : List Rat)
deriving Repr, DecidableEq, Inhabited

/-- A probability lies in the closed unit interval.

$$\mathrm{unit}(p) \iff 0 \le p \le 1$$ -/
def unit (p : Rat) : Bool := decide (0 ≤ p) && decide (p ≤ 1)

/-- The probabilities sum to 1 within `eps`.

$$\mathrm{sumOk}(d) \iff 1 - \varepsilon \le \textstyle\sum_i d_i \le 1 + \varepsilon$$ -/
def sumOk (d : List Rat) : Bool := decide (1 - eps ≤ d.sum) && decide (d.sum ≤ 1 + eps)

/-- A distribution over `n` outcomes: `n` values, each in [0, 1], summing to 1 within `eps`.

$$\mathrm{distOk}(n, d) \iff |d| = n \land (\forall p \in d:\ 0 \le p \le 1) \land \mathrm{sumOk}(d)$$ -/
def distOk (n : Nat) (d : List Rat) : Bool := d.length == n && d.all unit && sumOk d

/-- A well-typed answer for a question: the same primitive, a Choice's pick is one of its options, and the
distribution has one probability per key.

$$\mathrm{wt}(\mathrm{choice}(O, z), \mathrm{choice}(o, d)) \iff o \in O \land \mathrm{distOk}(|O|, d), \quad \mathrm{wt}(\mathrm{noul}, \mathrm{noul}(p)) \iff 0 \le p \le 1, \quad \mathrm{wt}(\mathrm{score}(L), \mathrm{score}(d)) \iff \mathrm{distOk}(|L|, d),$$
$$\text{and } \mathrm{wt}(s, a) \text{ is false for every other pair}$$ -/
def wt : Spec → Answer → Bool
  | .choice os _, .choice pk d => os.contains pk && distOk os.length d
  | .noul, .noul p => unit p
  | .score ls, .score d => distOk ls.length d
  | _, _ => false

/-- The answer object of a reply as the wire reads it, before validation: the `type` string, the optional
`choice` and `noul` fields, and the `probabilities` map as a key list.

$$\mathrm{Raw} = \mathrm{String} \times \mathrm{Option}(\mathrm{String}) \times \mathrm{Option}(\mathbb{Q}) \times (\mathrm{String} \times \mathbb{Q})^{*}$$ -/
structure Raw where
  type : String
  pick : Option String := none
  noul : Option Rat := none
  probs : List (String × Rat) := []
deriving Repr, DecidableEq

/-- Look up every key, in key order; `none` as soon as one key is missing.

$$\mathrm{lookupAll}(l, [\,]) = [\,], \quad \mathrm{lookupAll}(l, k :: ks) = \begin{cases} v :: vs & l(k) = v,\ \mathrm{lookupAll}(l, ks) = vs \\ \bot & \text{otherwise} \end{cases}$$ -/
def lookupAll (l : List (String × Rat)) : List String → Option (List Rat)
  | [] => some []
  | k :: ks =>
    match l.lookup k, lookupAll l ks with
    | some v, some vs => some (v :: vs)
    | _, _ => none

/-- Check a reply's probabilities against the keys: exactly as many entries as keys, every key present, every value
in [0, 1], sum 1 within `eps`; the result is the values in key order.

$$\mathrm{checkDist}(K, l) = d \iff |l| = |K| \land \mathrm{lookupAll}(l, K) = d \land \mathrm{distOk}(|K|, d)$$ -/
def checkDist (keys : List String) (l : List (String × Rat)) : Except String (List Rat) :=
  if l.length ≠ keys.length then .error "probabilities: the keys differ from the question's" else
  match lookupAll l keys with
  | none => .error "probabilities: a key of the question is missing"
  | some d =>
    if !(d.all unit) then .error "probabilities: a value outside [0, 1]"
    else if !sumOk d then .error "probabilities: the sum is not 1 within eps"
    else .ok d

/-- Validate a raw answer against its question (the `oracle.validate` op): a schema-mismatch reason, or the typed
answer.

$$\mathrm{validate}(s, r) = \begin{cases} \mathrm{noul}(p) & s = \mathrm{noul},\ r.\mathit{type} = \texttt{noul},\ r.\mathit{noul} = p,\ 0 \le p \le 1 \\ \mathrm{choice}(o, d) & s = \mathrm{choice}(O, z),\ r.\mathit{type} = \texttt{choice},\ r.\mathit{pick} = o \in O,\ \mathrm{checkDist}(O, r.\mathit{probs}) = d \\ \mathrm{score}(d) & s = \mathrm{score}(L),\ r.\mathit{type} = \texttt{score},\ \mathrm{checkDist}(\mathrm{keys}(s), r.\mathit{probs}) = d \\ \mathrm{error} & \text{otherwise, and whenever } \lnot\mathrm{wf}(s) \end{cases}$$ -/
def validate (s : Spec) (r : Raw) : Except String Answer :=
  if !s.wf then .error "the question is not well-formed" else
  match s with
  | .noul =>
    if r.type ≠ "noul" then .error s!"answer type {r.type}, expected noul" else
    match r.noul with
    | none => .error "noul: the probability is missing"
    | some p => if unit p then .ok (.noul p) else .error "noul: the probability is outside [0, 1]"
  | .choice os _ =>
    if r.type ≠ "choice" then .error s!"answer type {r.type}, expected choice" else
    match r.pick with
    | none => .error "choice: the pick is missing"
    | some pk =>
      if !os.contains pk then .error "choice: the pick is not an option" else
      match checkDist os r.probs with
      | .error e => .error e
      | .ok d => .ok (.choice pk d)
  | .score ls =>
    if r.type ≠ "score" then .error s!"answer type {r.type}, expected score" else
    match checkDist ((List.range ls.length).map toString) r.probs with
    | .error e => .error e
    | .ok d => .ok (.score d)

/-- The raw form of a typed answer (what a correct reply carries): the inverse direction of `validate`.

$$\mathrm{toRaw}(s, \mathrm{choice}(o, d)) = (\texttt{choice}, o, \bot, \mathrm{zip}(\mathrm{keys}(s), d)), \quad \mathrm{toRaw}(s, \mathrm{noul}(p)) = (\texttt{noul}, \bot, p, [\,]), \quad \mathrm{toRaw}(s, \mathrm{score}(d)) = (\texttt{score}, \bot, \bot, \mathrm{zip}(\mathrm{keys}(s), d))$$ -/
def toRaw (s : Spec) : Answer → Raw
  | .choice pk d => { type := "choice", pick := some pk, probs := s.keys.zip d }
  | .noul p => { type := "noul", noul := some p }
  | .score d => { type := "score", probs := s.keys.zip d }

/-! ### Validation is sound and complete -/

/-- A successful `lookupAll` returns one value per key.

$$\forall l, K, d:\ \mathrm{lookupAll}(l, K) = d \Rightarrow |d| = |K|$$ -/
theorem lookupAll_length (l : List (String × Rat)) :
    ∀ (ks : List String) (d : List Rat), lookupAll l ks = some d → d.length = ks.length
  | [], d, h => by simp [lookupAll] at h; subst h; rfl
  | k :: ks, d, h => by
    unfold lookupAll at h
    split at h
    · rename_i v vs _ hvs
      simp at h; subst h
      simp [lookupAll_length l ks vs hvs]
    · exact absurd h (by simp)

/-- With distinct keys, a pair of the list is what `lookup` finds.

$$\forall l, k, v:\ \mathrm{nodup}(\mathrm{map}(\mathrm{fst}, l)) \land (k, v) \in l \Rightarrow l(k) = v$$ -/
theorem lookup_of_mem :
    ∀ (l : List (String × Rat)) (k : String) (v : Rat), (l.map Prod.fst).Nodup → (k, v) ∈ l → l.lookup k = some v
  | [], _, _, _, h => by simp at h
  | (k', v') :: t, k, v, hn, h => by
    simp only [List.map_cons, List.nodup_cons] at hn
    simp only [List.lookup_cons]
    rcases List.mem_cons.mp h with he | ht
    · simp at he; obtain ⟨rfl, rfl⟩ := he; simp
    · have hk : k ≠ k' := by
        intro hkk; subst hkk
        exact hn.1 (List.mem_map.mpr ⟨(k, v), ht, rfl⟩)
      have : (k == k') = false := by simp [hk]
      rw [this]
      exact lookup_of_mem t k v hn.2 ht

/-- Looking up every key of `zip(K, d)` in a list that contains all its pairs (with distinct keys) gives `d` back.

$$\forall l, K, d:\ |K| = |d| \land \mathrm{zip}(K, d) \subseteq l \land \mathrm{nodup}(\mathrm{map}(\mathrm{fst}, l)) \Rightarrow \mathrm{lookupAll}(l, K) = d$$ -/
theorem lookupAll_of_sub (l : List (String × Rat)) (hn : (l.map Prod.fst).Nodup) :
    ∀ (ks : List String) (d : List Rat), ks.length = d.length → (∀ p ∈ ks.zip d, p ∈ l) → lookupAll l ks = some d
  | [], [], _, _ => rfl
  | [], _ :: _, h, _ => by simp at h
  | _ :: _, [], h, _ => by simp at h
  | k :: ks, v :: vs, h, hs => by
    simp only [List.length_cons, Nat.add_right_cancel_iff] at h
    have h1 : l.lookup k = some v := lookup_of_mem l k v hn (hs (k, v) (by simp))
    have h2 : lookupAll l ks = some vs :=
      lookupAll_of_sub l hn ks vs h fun p hp => hs p (by simp [hp])
    simp [lookupAll, h1, h2]

/-- With distinct keys and one value per key, looking the keys up in their own zip returns the values.

$$\forall K, d:\ \mathrm{nodup}(K) \land |K| = |d| \Rightarrow \mathrm{lookupAll}(\mathrm{zip}(K, d), K) = d$$ -/
theorem lookupAll_zip (ks : List String) (d : List Rat) (hn : ks.Nodup) (h : ks.length = d.length) :
    lookupAll (ks.zip d) ks = some d := by
  apply lookupAll_of_sub
  · rw [List.map_fst_zip (Nat.le_of_eq h)]; exact hn
  · exact h
  · intro p hp; exact hp

/-- What `checkDist` accepts is a distribution with one value per key.

$$\forall K, l, d:\ \mathrm{checkDist}(K, l) = d \Rightarrow \mathrm{distOk}(|K|, d)$$ -/
theorem checkDist_sound (keys : List String) (l : List (String × Rat)) (d : List Rat)
    (h : checkDist keys l = .ok d) : distOk keys.length d = true := by
  unfold checkDist at h
  split at h
  · exact absurd h (by simp)
  · split at h
    · exact absurd h (by simp)
    · rename_i d' hd'
      split at h
      · exact absurd h (by simp)
      · split at h
        · exact absurd h (by simp)
        · rename_i hu hs
          simp at h; subst h
          simp only [Bool.not_eq_true'] at hu hs
          simp only [Bool.not_eq_false] at hu hs
          simp [distOk, lookupAll_length l keys d' hd', hu, hs]

/-- `checkDist` accepts the zip of distinct keys with a distribution over them.

$$\forall K, d:\ \mathrm{nodup}(K) \land \mathrm{distOk}(|K|, d) \Rightarrow \mathrm{checkDist}(K, \mathrm{zip}(K, d)) = d$$ -/
theorem checkDist_complete (keys : List String) (d : List Rat) (hn : keys.Nodup) (h : distOk keys.length d = true) :
    checkDist keys (keys.zip d) = .ok d := by
  simp only [distOk, Bool.and_eq_true, beq_iff_eq] at h
  obtain ⟨⟨hl, hu⟩, hs⟩ := h
  have hz : (keys.zip d).length = keys.length := by simp [List.length_zip, hl]
  have hla := lookupAll_zip keys d hn hl.symm
  simp [checkDist, hz, hla, hu, hs]

/-- **Validation is sound.** Every accepted reply is a well-typed answer of a well-formed question.

$$\forall s, r, a:\ \mathrm{validate}(s, r) = a \Rightarrow \mathrm{wf}(s) \land \mathrm{wt}(s, a)$$ -/
theorem validate_sound (s : Spec) (r : Raw) (a : Answer) (h : validate s r = .ok a) :
    s.wf = true ∧ wt s a = true := by
  unfold validate at h
  split at h
  · exact absurd h (by simp)
  · rename_i hw
    simp only [Bool.not_eq_true', Bool.not_eq_false] at hw
    refine ⟨hw, ?_⟩
    split at h
    · split at h
      · exact absurd h (by simp)
      · split at h
        · exact absurd h (by simp)
        · split at h
          · simp at h; subst h; simp_all [wt]
          · exact absurd h (by simp)
    · rename_i os z
      split at h
      · exact absurd h (by simp)
      · split at h
        · exact absurd h (by simp)
        · rename_i pk _
          split at h
          · exact absurd h (by simp)
          · rename_i hc
            split at h
            · exact absurd h (by simp)
            · rename_i d hd
              simp at h; subst h
              simp only [Bool.not_eq_true', Bool.not_eq_false] at hc
              have hm : pk ∈ os := by simpa using hc
              have hs := checkDist_sound os r.probs d hd
              simp [wt, hm, hs]
    · rename_i ls
      split at h
      · exact absurd h (by simp)
      · split at h
        · exact absurd h (by simp)
        · rename_i d hd
          simp at h; subst h
          have := checkDist_sound _ r.probs d hd
          simp at this
          simp [wt, this]

/-- **Validation is complete.** The raw form of every well-typed answer of a well-formed question is accepted and
read back as that answer.

$$\forall s, a:\ \mathrm{wf}(s) \land \mathrm{wt}(s, a) \Rightarrow \mathrm{validate}(s, \mathrm{toRaw}(s, a)) = a$$ -/
theorem validate_complete (s : Spec) (a : Answer) (hw : s.wf = true) (ht : wt s a = true) :
    validate s (toRaw s a) = .ok a := by
  cases s with
  | choice os z =>
    cases a with
    | choice pk d =>
      simp only [wt, Bool.and_eq_true] at ht
      simp only [Spec.wf, Bool.and_eq_true, decide_eq_true_eq] at hw
      have hc := checkDist_complete os d hw.1.1.1 (by simpa using ht.2)
      have hz : z ∈ os := by simpa using hw.1.1.2
      have hp : pk ∈ os := by simpa using ht.1
      simp [validate, toRaw, Spec.keys, Spec.wf, hw, hz, hp, hc]
    | noul _ => simp [wt] at ht
    | score _ => simp [wt] at ht
  | noul =>
    cases a with
    | noul p =>
      simp only [wt] at ht
      simp [validate, toRaw, Spec.wf, ht]
    | choice _ _ => simp [wt] at ht
    | score _ => simp [wt] at ht
  | score ls =>
    cases a with
    | score d =>
      simp only [wt] at ht
      have hw' := hw
      simp only [Spec.wf, Bool.and_eq_true, decide_eq_true_eq] at hw'
      have hc := checkDist_complete ((List.range ls.length).map toString) d hw'.1.1 (by simpa using ht)
      simp [validate, toRaw, Spec.keys, hw, hc]
    | choice _ _ => simp [wt] at ht
    | noul _ => simp [wt] at ht

/-! ## Confidence (recomputed from the validated probabilities) -/

/-- The absolute value of a rational.

$$|q| = \begin{cases} -q & q < 0 \\ q & \text{otherwise} \end{cases}$$ -/
def absQ (q : Rat) : Rat := if q < 0 then -q else q

/-- The largest value of a list, `0` for the empty list (probabilities are never negative).

$$\mathrm{maxQ}([\,]) = 0, \quad \mathrm{maxQ}(x :: xs) = \max(x, \mathrm{maxQ}(xs))$$ -/
def maxQ : List Rat → Rat
  | [] => 0
  | x :: xs => let m := maxQ xs; if x ≤ m then m else x

/-- The first index holding the largest value (`|d|` when there is none, i.e. for the empty list).

$$\mathrm{argmax}(d) = \min\{\, i : d_i = \mathrm{maxQ}(d) \,\} \ (\text{or } |d| \text{ if no such } i)$$ -/
def argmax (d : List Rat) : Nat := d.findIdx (· == maxQ d)

/-- Σ over the list of `d_i · |i − c|` (indices from `i₀`): the probability-weighted distance from the level `c`.

$$\mathrm{spread}(d, c, i_0) = \textstyle\sum_{j < |d|} d_j \cdot |i_0 + j - c|$$ -/
def spread : List Rat → Rat → Nat → Rat
  | [], _, _ => 0
  | p :: ps, c, i => p * absQ ((i : Rat) - c) + spread ps c (i + 1)

/-- Choice confidence: (p_max − 1/n)/(1 − 1/n), 1 when all probability sits on one option, 0 when it is even
(Rat division by zero is 0, so `n ≤ 1` gives 0).

$$\mathrm{confChoice}(d) = \frac{\mathrm{maxQ}(d) - 1/n}{1 - 1/n}, \quad n = |d|$$ -/
def confChoice (d : List Rat) : Rat :=
  let n : Rat := d.length
  (maxQ d - 1 / n) / (1 - 1 / n)

/-- Score confidence: 1 minus the probability-weighted distance from the most likely level `m`, over the same
distance of an even spread measured from the middle level, floored at 0 (0 when that even-spread distance is 0).

$$\mathrm{confScore}(d) = \begin{cases} \max\!\left(0,\ 1 - \dfrac{\mathrm{spread}(d, m, 0)}{\mathrm{MAD}}\right) & \mathrm{MAD} > 0 \\ 0 & \text{otherwise} \end{cases}, \quad m = \mathrm{argmax}(d),\ \mathrm{MAD} = \frac{1}{n}\sum_{i < n}\left|i - \frac{n - 1}{2}\right|,\ n = |d|$$ -/
def confScore (d : List Rat) : Rat :=
  let n := d.length
  let mad := spread (List.replicate n 1) (((n : Rat) - 1) / 2) 0 / (n : Rat)
  if mad ≤ 0 then 0 else
  let c := 1 - spread d (argmax d : Rat) 0 / mad
  if c < 0 then 0 else c

/-- The gate value of an answer: the confidence of a Choice or Score, the margin |2p − 1| of a Noul.

$$\mathrm{gate}(\mathrm{choice}(o, d)) = \mathrm{confChoice}(d), \quad \mathrm{gate}(\mathrm{noul}(p)) = |2p - 1|, \quad \mathrm{gate}(\mathrm{score}(d)) = \mathrm{confScore}(d)$$ -/
def gate : Answer → Rat
  | .choice _ d => confChoice d
  | .noul p => absQ (2 * p - 1)
  | .score d => confScore d

-- the documentation's examples: Choice (0.88, 0.12, 0) gives 0.82 (the page rounds its inputs and shows 0.81);
-- Score (0, 0.57, 0.43) gives 1 - 0.43 / (2/3) = 0.355; a Noul of 0.95 has margin 0.9
#guard confChoice [88/100, 12/100, 0] == 41/50
#guard confScore [0, 57/100, 43/100] == 71/200
#guard confScore [0, 1/2, 1/2] == 1/4
#guard confScore [1/2, 0, 1/2] == 0
#guard gate (.noul (95/100)) == 9/10
#guard confChoice [1/4, 1/4, 1/4, 1/4] == 0
#guard argmax [1/10, 6/10, 3/10] == 1

/-! ## Outcomes, actions and the policy -/

/-- Why no answer came back: a timeout, an HTTP status, an unparsable body, a reply that fails validation, the
spend guard, no API key in the keychain, or a state that is not redacted (the client refuses to send it).

$$\mathrm{Failure} ::= \mathrm{timeout} \mid \mathrm{http}(c) \mid \mathrm{malformed} \mid \mathrm{schema}(e) \mid \mathrm{overBudget} \mid \mathrm{noKey} \mid \mathrm{unredacted}$$ -/
inductive Failure where
  | timeout
  | http (status : Nat)
  | malformed
  | schema (detail : String)
  | overBudget
  | noKey
  | unredacted
deriving Repr, DecidableEq, Inhabited

/-- What one call produced: a validated answer or a failure.

$$\mathrm{Outcome} ::= \mathrm{answer}(a) \mid \mathrm{failure}(f)$$ -/
inductive Outcome where
  | answer (a : Answer)
  | failure (f : Failure)
deriving Repr, DecidableEq

/-- The advice an oracle can give: a label only (an option, yes or no, a level index). It is printed for a person or
an agent, never executed.

$$\mathrm{Advice} ::= \mathrm{pick}(o) \mid \mathrm{yes} \mid \mathrm{no} \mid \mathrm{level}(i)$$ -/
inductive Advice where
  | pick (option : String)
  | yes
  | no
  | level (i : Nat)
deriving Repr, DecidableEq, Inhabited

/-- Why an outcome escalates to a person (or a reasoning model): a failure, no calibrated threshold yet, a gate
value below the threshold, or the no-match option.

$$\mathrm{Reason} ::= \mathrm{failure}(f) \mid \mathrm{uncalibrated} \mid \mathrm{below}(g, \tau) \mid \mathrm{noMatch}$$ -/
inductive Reason where
  | failure (f : Failure)
  | uncalibrated
  | below (gate threshold : Rat)
  | noMatch
deriving Repr, DecidableEq, Inhabited

/-- The whole action space of an oracle question: advise or escalate. There is no constructor for a land, push,
delete, cancel or kill, so no oracle outcome can become one.

$$\mathrm{Action} ::= \mathrm{advise}(v) \mid \mathrm{escalate}(r), \quad v \in \mathrm{Advice},\ r \in \mathrm{Reason}$$ -/
inductive Action where
  | advise (v : Advice)
  | escalate (r : Reason)
deriving Repr, DecidableEq, Inhabited

/-- Is the action an escalation?

$$\mathrm{isEsc}(\mathrm{escalate}(r)) = \top, \quad \mathrm{isEsc}(\mathrm{advise}(v)) = \bot$$ -/
def Action.isEscalate : Action → Bool
  | .escalate _ => true
  | .advise _ => false

/-- The advice an answer gives: the pick of a Choice, yes iff p ≥ 1/2 for a Noul, the most likely level of a Score.

$$\mathrm{adv}(\mathrm{choice}(o, d)) = \mathrm{pick}(o), \quad \mathrm{adv}(\mathrm{noul}(p)) = \begin{cases} \mathrm{yes} & p \ge \tfrac12 \\ \mathrm{no} & \text{otherwise} \end{cases}, \quad \mathrm{adv}(\mathrm{score}(d)) = \mathrm{level}(\mathrm{argmax}(d))$$ -/
def adviceOf : Answer → Advice
  | .choice pk _ => .pick pk
  | .noul p => if 1 / 2 ≤ p then .yes else .no
  | .score d => .level (argmax d)

/-- The answer picks the question's no-match option.

$$\mathrm{isNoMatch}(s, a) \iff s = \mathrm{choice}(O, z) \land a = \mathrm{choice}(z, d) \text{ for some } O, z, d$$ -/
def isNoMatch : Spec → Answer → Bool
  | .choice _ z, .choice pk _ => pk == z
  | _, _ => false

/-- **The policy** (the `oracle.decide` op): a failure escalates with it; an answer that is not well-typed escalates as
a schema failure; without a calibrated threshold everything escalates; a gate value below the threshold escalates;
the no-match option escalates; otherwise the answer's advice.

$$\mathrm{policy}(s, t, o) = \begin{cases} \mathrm{escalate}(\mathrm{failure}(f)) & o = \mathrm{failure}(f) \\ \mathrm{escalate}(\mathrm{failure}(\mathrm{schema})) & o = \mathrm{answer}(a),\ \lnot(\mathrm{wf}(s) \land \mathrm{wt}(s, a)) \\ \mathrm{escalate}(\mathrm{uncalibrated}) & o = \mathrm{answer}(a),\ \mathrm{wf}(s) \land \mathrm{wt}(s, a),\ t = \bot \\ \mathrm{escalate}(\mathrm{below}(\mathrm{gate}(a), \tau)) & \ldots,\ t = \tau,\ \mathrm{gate}(a) < \tau \\ \mathrm{escalate}(\mathrm{noMatch}) & \ldots,\ t = \tau,\ \mathrm{gate}(a) \ge \tau,\ \mathrm{isNoMatch}(s, a) \\ \mathrm{advise}(\mathrm{adv}(a)) & \ldots,\ t = \tau,\ \mathrm{gate}(a) \ge \tau,\ \lnot\mathrm{isNoMatch}(s, a) \end{cases}$$ -/
def policy (s : Spec) (t : Option Rat) : Outcome → Action
  | .failure f => .escalate (.failure f)
  | .answer a =>
    if !(s.wf && wt s a) then .escalate (.failure (.schema "the answer does not fit the question")) else
    match t with
    | none => .escalate .uncalibrated
    | some τ =>
      if gate a < τ then .escalate (.below (gate a) τ)
      else if isNoMatch s a then .escalate .noMatch
      else .advise (adviceOf a)

/-- **The policy is total**: every question, threshold and outcome gives exactly an advice or an escalation.

$$\forall s, t, o:\ (\exists v:\ \mathrm{policy}(s, t, o) = \mathrm{advise}(v)) \lor (\exists r:\ \mathrm{policy}(s, t, o) = \mathrm{escalate}(r))$$ -/
theorem policy_total (s : Spec) (t : Option Rat) (o : Outcome) :
    (∃ v, policy s t o = .advise v) ∨ (∃ r, policy s t o = .escalate r) := by
  cases h : policy s t o with
  | advise v => exact .inl ⟨v, rfl⟩
  | escalate r => exact .inr ⟨r, rfl⟩

/-- **Every failure escalates**, with the failure as the reason, whatever the question and threshold.

$$\forall s, t, f:\ \mathrm{policy}(s, t, \mathrm{failure}(f)) = \mathrm{escalate}(\mathrm{failure}(f))$$ -/
theorem failure_escalates (s : Spec) (t : Option Rat) (f : Failure) :
    policy s t (.failure f) = .escalate (.failure f) := rfl

/-- **Without a threshold every outcome escalates.**

$$\forall s, o:\ \exists r:\ \mathrm{policy}(s, \bot, o) = \mathrm{escalate}(r)$$ -/
theorem uncalibrated_escalates (s : Spec) (o : Outcome) : ∃ r, policy s none o = .escalate r := by
  cases o with
  | failure f => exact ⟨_, rfl⟩
  | answer a =>
    by_cases hw : (s.wf && wt s a) = true <;> simp [policy, hw]

/-- **Below the threshold escalates.** A confidence (or Noul margin) strictly below the threshold never advises.

$$\forall s, a, \tau:\ \mathrm{gate}(a) < \tau \Rightarrow \exists r:\ \mathrm{policy}(s, \tau, \mathrm{answer}(a)) = \mathrm{escalate}(r)$$ -/
theorem escalate_below (s : Spec) (a : Answer) (τ : Rat) (h : gate a < τ) :
    ∃ r, policy s (some τ) (.answer a) = .escalate r := by
  by_cases hw : (s.wf && wt s a) = true <;> simp [policy, hw, h]

/-- **What an advice certifies.** An advice comes only from a well-typed answer of a well-formed question, under a
threshold the gate value reaches, not the no-match option, and it is that answer's advice.

$$\forall s, t, o, v:\ \mathrm{policy}(s, t, o) = \mathrm{advise}(v) \Rightarrow \exists a, \tau:\ o = \mathrm{answer}(a) \land t = \tau \land \mathrm{wf}(s) \land \mathrm{wt}(s, a) \land \tau \le \mathrm{gate}(a) \land \lnot\mathrm{isNoMatch}(s, a) \land v = \mathrm{adv}(a)$$ -/
theorem advise_sound (s : Spec) (t : Option Rat) (o : Outcome) (v : Advice) (h : policy s t o = .advise v) :
    ∃ a τ, o = .answer a ∧ t = some τ ∧ s.wf = true ∧ wt s a = true ∧ τ ≤ gate a ∧ isNoMatch s a = false ∧
      v = adviceOf a := by
  cases o with
  | failure f => simp [policy] at h
  | answer a =>
    by_cases hw : (s.wf && wt s a) = true
    · simp only [Bool.and_eq_true] at hw
      cases t with
      | none => simp [policy, hw] at h
      | some τ =>
        by_cases hg : gate a < τ
        · simp [policy, hw, hg] at h
        · by_cases hn : isNoMatch s a = true
          · simp [policy, hw, hg, hn] at h
          · simp [policy, hw, hg, hn] at h
            exact ⟨a, τ, rfl, rfl, hw.1, hw.2, Rat.not_lt.mp hg, by simpa using hn, h.symm⟩
    · simp [policy, hw] at h

/-! ## The action space holds no irreversible effect -/

/-- Every effect a tool of this repo can have on the world: land, push, delete, cancel, kill, or the two harmless
ones, print a line and ask a person.

$$\mathrm{Effect} ::= \mathrm{land} \mid \mathrm{push} \mid \mathrm{delete} \mid \mathrm{cancel} \mid \mathrm{kill} \mid \mathrm{print} \mid \mathrm{ask}$$ -/
inductive Effect where
  | land
  | push
  | delete
  | cancel
  | kill
  | print
  | ask
deriving Repr, DecidableEq

/-- The irreversible effects: land, push, delete, cancel, kill.

$$\mathrm{irrev}(e) \iff e \in \{\mathrm{land}, \mathrm{push}, \mathrm{delete}, \mathrm{cancel}, \mathrm{kill}\}$$ -/
def Effect.irreversible : Effect → Bool
  | .land | .push | .delete | .cancel | .kill => true
  | .print | .ask => false

/-- The only effect an oracle action has: an advice is printed, an escalation asks a person.

$$\mathrm{eff}(\mathrm{advise}(v)) = \mathrm{print}, \quad \mathrm{eff}(\mathrm{escalate}(r)) = \mathrm{ask}$$ -/
def Action.effect : Action → Effect
  | .advise _ => .print
  | .escalate _ => .ask

/-- **No oracle action is irreversible**, by the type: every `Action` (whatever produced it) has a reversible effect.

$$\forall x \in \mathrm{Action}:\ \lnot\mathrm{irrev}(\mathrm{eff}(x))$$ -/
theorem action_reversible (x : Action) : x.effect.irreversible = false := by
  cases x <;> rfl

/-- **Oracle output is never a land, push, delete, cancel or kill**: for every question, threshold and outcome.

$$\forall s, t, o:\ \lnot\mathrm{irrev}(\mathrm{eff}(\mathrm{policy}(s, t, o)))$$ -/
theorem never_irreversible (s : Spec) (t : Option Rat) (o : Outcome) :
    (policy s t o).effect.irreversible = false := action_reversible _

end Fw.Oracle
