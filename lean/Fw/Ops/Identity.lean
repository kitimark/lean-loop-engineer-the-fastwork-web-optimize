import Fw.Console
/-!
# Hook identity (SPK-c decision 1; PLAN §8.3 capability hook, R27)

Who a hook record comes from, from its two identity fields `agent_id` and `agent_type`
(`research/notes/2026/10-17-spk-drafts/spk-c.md`, identity table, MEASURED on Claude Code 2.1.302):

| `agent_id` | `agent_type` | identity |
|---|---|---|
| absent | anything | the lead (main session) |
| non-empty | non-empty | the agent of that type (a role, or a teammate's **name**) |
| present | absent or `""` | unknown: a forked internal agent; never the lead |
| `""` | anything | unknown (fail closed) |

The lead is the record with **no** `agent_id`, never "empty `agent_type`". The capability
actor of an identity: the lead acts as `lead`, an agent whose type contains `review` (ASCII
case-insensitive) as `reviewer`, any other agent as `owner`, and an unknown identity gets no
capability at all. `cap.mjs` (the hook) and console-api's `actorFor` follow this module and are
checked against its golden vectors (`packages/contracts/golden/ops/ops.actor.jsonl`).

Proved: a record with an `agent_id` is never the lead (`who_lead_iff`, `capActor_lead_iff`), the
forked-agent shapes are unknown and get no capability (`who_forked`, `capActor_none_iff`), and a
capability actor is only ever `lead`, `reviewer` or `owner` (`capActor_range`).

Open (SPK-c decision 2): a teammate's `agent_type` is its name, not its role; mapping it to a role
needs the console roster (name to role), which does not exist yet. Until then a teammate acts as
`owner`, or as `reviewer` when its name contains `review`.
-/
namespace Fw.Ops.Identity
open Fw.Console

/-- The identity of a hook record: the lead, an agent of a given type, or unknown.

$$\mathrm{Who} = \{\mathrm{lead}\} \cup \{\mathrm{agent}(t) \mid t \in \mathrm{String}\} \cup \{\mathrm{unknown}\}$$

The three kinds of sender a hook record can have.
-/
inductive Who where
  | lead
  | agent (type : String)
  | unknown
deriving DecidableEq, Repr

/-- The identity rule: no `agent_id` is the lead; a non-empty `agent_id` with a non-empty
`agent_type` is that agent; every other shape is unknown.

$$\operatorname{who}(i, t) = \begin{cases} \mathrm{lead} & i = \bot \\ \mathrm{agent}(r) & i = s \ne \texttt{""} \wedge t = r \ne \texttt{""} \\ \mathrm{unknown} & \text{otherwise} \end{cases} \qquad (i, t \in \mathrm{String} \cup \{\bot\})$$

A record is the lead exactly when it has no agent id, and an agent only when both fields are non-empty.
-/
def who : Option String → Option String → Who
  | none, _ => .lead
  | some s, some r => if s = "" ∨ r = "" then .unknown else .agent r
  | some _, none => .unknown

/-- Whether `p` occurs as a contiguous block inside a character list.

$$\operatorname{infixOf}(p, w) = \mathrm{true} \iff \exists\, u, v.\ w = u \cdot p \cdot v$$

Plain substring search on character lists.
-/
def infixOf (p : List Char) : List Char → Bool
  | [] => p.isEmpty
  | c :: cs => p.isPrefixOf (c :: cs) || infixOf p cs

/-- A reviewing role: its type contains `review`, ignoring ASCII case.

$$\operatorname{isReviewRole}(t) = \operatorname{infixOf}(\texttt{review}, \operatorname{lower}(t))$$

where $\operatorname{lower}$ lowercases ASCII letters only (as JavaScript's `/review/i` does).
An agent type counts as a reviewer when it contains the word review in any ASCII case.
-/
def isReviewRole (t : String) : Bool := infixOf "review".toList t.toLower.toList

/-- The capability actor of an identity; an unknown identity gets none.

$$\operatorname{actorOf}(\mathrm{lead}) = \mathrm{lead}, \quad \operatorname{actorOf}(\mathrm{agent}(t)) = \begin{cases} \mathrm{reviewer} & \operatorname{isReviewRole}(t) \\ \mathrm{owner} & \text{otherwise} \end{cases}, \quad \operatorname{actorOf}(\mathrm{unknown}) = \bot$$

The lead acts as lead, agents as reviewer or owner, and unknown senders cannot act.
-/
def actorOf : Who → Option Actor
  | .lead => some .lead
  | .agent t => some (if isReviewRole t then .reviewer else .owner)
  | .unknown => none

/-- The actor a capability for the record $(i, t)$ is minted for ($\bot$: refuse to mint).

$$\operatorname{capActor}(i, t) = \operatorname{actorOf}(\operatorname{who}(i, t))$$

The identity rule followed by the actor table.
-/
def capActor (i t : Option String) : Option Actor := actorOf (who i t)

/-- The lead is exactly the record without an `agent_id`.

$$\forall\, i, t \in \mathrm{String} \cup \{\bot\}.\quad \operatorname{who}(i, t) = \mathrm{lead} \iff i = \bot$$

No record that carries an agent id, whatever its agent type, is ever treated as the lead.
-/
theorem who_lead_iff (i t : Option String) : who i t = .lead ↔ i = none := by
  cases i with
  | none => simp [who]
  | some s =>
    cases t with
    | none => simp [who]
    | some r => by_cases h : s = "" ∨ r = "" <;> simp [who, h]

/-- A record with an `agent_id` is never the lead.

$$\forall\, s \in \mathrm{String},\ t \in \mathrm{String} \cup \{\bot\}.\quad \operatorname{who}(s, t) \ne \mathrm{lead}$$

Carrying an agent id, even an empty one, rules out the lead.
-/
theorem who_some_ne_lead (s : String) (t : Option String) : who (some s) t ≠ .lead := by
  simp [who_lead_iff]

/-- The agent identity is exactly a non-empty `agent_id` with a non-empty `agent_type`.

$$\forall\, i, t \in \mathrm{String} \cup \{\bot\},\ r \in \mathrm{String}.\quad \operatorname{who}(i, t) = \mathrm{agent}(r) \iff \exists\, s \in \mathrm{String}.\ i = s \wedge s \ne \texttt{""} \wedge t = r \wedge r \ne \texttt{""}$$

A record names an agent only when both identity fields are present and non-empty, and then it names its own type.
-/
theorem who_agent_iff (i t : Option String) (r : String) :
    who i t = .agent r ↔ ∃ s, i = some s ∧ s ≠ "" ∧ t = some r ∧ r ≠ "" := by
  cases i with
  | none => simp [who]
  | some s =>
    cases t with
    | none => simp [who]
    | some r' =>
      by_cases h : s = "" ∨ r' = ""
      · simp only [who, h, ite_true]
        constructor
        · intro h'; cases h'
        · rintro ⟨s', hs, hs', ht, hr⟩
          cases hs; cases ht
          rcases h with h | h <;> contradiction
      · simp only [who, h, ite_false]
        simp only [not_or] at h
        constructor
        · intro h'; cases h'; exact ⟨s, rfl, h.1, rfl, h.2⟩
        · rintro ⟨s', hs, -, ht, -⟩; cases hs; cases ht; rfl

/-- The unknown identity is exactly an `agent_id` that is empty, or that comes with a missing or
empty `agent_type`.

$$\forall\, i, t \in \mathrm{String} \cup \{\bot\}.\quad \operatorname{who}(i, t) = \mathrm{unknown} \iff \exists\, s \in \mathrm{String}.\ i = s \wedge (s = \texttt{""} \vee t = \bot \vee t = \texttt{""})$$

Everything that is neither the lead nor a well-formed agent is unknown, and nothing else is.
-/
theorem who_unknown_iff (i t : Option String) :
    who i t = .unknown ↔ ∃ s, i = some s ∧ (s = "" ∨ t = none ∨ t = some "") := by
  cases i with
  | none => simp [who]
  | some s =>
    cases t with
    | none => simp [who]
    | some r => by_cases h : s = "" ∨ r = "" <;> simp_all [who]

/-- The forked internal agent (an `agent_id` with an empty or missing `agent_type`) is unknown.

$$\forall\, s \in \mathrm{String}.\quad \operatorname{who}(s, \texttt{""}) = \mathrm{unknown} \ \wedge\ \operatorname{who}(s, \bot) = \mathrm{unknown}$$

Claude Code's own side agents, which send an id but an empty type, are never attributed to anyone.
-/
theorem who_forked (s : String) : who (some s) (some "") = .unknown ∧ who (some s) none = .unknown := by
  simp [who]

/-- The rule is total and single-valued: every record has exactly one identity, one of the three kinds.

$$\forall\, i, t \in \mathrm{String} \cup \{\bot\}.\ \exists\, w \in \mathrm{Who}.\quad \operatorname{who}(i, t) = w \ \wedge\ \bigl(w = \mathrm{lead} \vee \exists\, r \in \mathrm{String}.\ w = \mathrm{agent}(r) \vee w = \mathrm{unknown}\bigr) \ \wedge\ \forall\, w' \in \mathrm{Who}.\ \operatorname{who}(i, t) = w' \implies w' = w$$

Each pair of identity fields gets one and only one identity.
-/
theorem who_total (i t : Option String) :
    ∃ w, who i t = w ∧ (w = .lead ∨ (∃ r, w = .agent r) ∨ w = .unknown) ∧ ∀ w', who i t = w' → w' = w := by
  refine ⟨who i t, rfl, ?_, fun w h => h.symm⟩
  cases who i t with
  | lead => exact .inl rfl
  | agent r => exact .inr (.inl ⟨r, rfl⟩)
  | unknown => exact .inr (.inr rfl)

/-- A capability is minted as the lead exactly for records without an `agent_id`.

$$\forall\, i, t \in \mathrm{String} \cup \{\bot\}.\quad \operatorname{capActor}(i, t) = \mathrm{lead} \iff i = \bot$$

No agent, named, forked or malformed, can ever obtain a lead capability.
-/
theorem capActor_lead_iff (i t : Option String) : capActor i t = some .lead ↔ i = none := by
  rw [← who_lead_iff i t]
  unfold capActor
  cases who i t with
  | lead => simp [actorOf]
  | agent r => by_cases h : isReviewRole r <;> simp [actorOf, h]
  | unknown => simp [actorOf]

/-- No capability is minted exactly for the unknown identity.

$$\forall\, i, t \in \mathrm{String} \cup \{\bot\}.\quad \operatorname{capActor}(i, t) = \bot \iff \operatorname{who}(i, t) = \mathrm{unknown}$$

The hook refuses to mint precisely when the record's sender is unknown.
-/
theorem capActor_none_iff (i t : Option String) : capActor i t = none ↔ who i t = .unknown := by
  unfold capActor
  cases who i t with
  | lead => simp [actorOf]
  | agent r => simp [actorOf]
  | unknown => simp [actorOf]

/-- A capability actor is only ever the lead, a reviewer or an owner.

$$\forall\, i, t \in \mathrm{String} \cup \{\bot\},\ a \in \mathrm{Actor}.\quad \operatorname{capActor}(i, t) = a \implies a \in \{\mathrm{lead}, \mathrm{reviewer}, \mathrm{owner}\}$$

A capability never claims to be the user, a script, git or a hook.
-/
theorem capActor_range (i t : Option String) (a : Actor) (h : capActor i t = some a) :
    a = .lead ∨ a = .reviewer ∨ a = .owner := by
  unfold capActor at h
  cases hw : who i t with
  | lead => rw [hw] at h; simp [actorOf] at h; exact .inl h.symm
  | agent r =>
    rw [hw] at h
    by_cases hr : isReviewRole r <;> simp [actorOf, hr] at h <;> simp [← h]
  | unknown => rw [hw] at h; simp [actorOf] at h

/-! ## Examples (the golden edge cases) -/

#guard who none none == .lead
#guard who none (some "lean-prover") == .lead
#guard who (some "a0123456789abcdef") (some "lean-prover") == .agent "lean-prover"
#guard who (some "a0123456789abcdef") (some "") == .unknown
#guard who (some "a0123456789abcdef") none == .unknown
#guard who (some "") (some "lean-prover") == .unknown
#guard who (some "a0123456789abcdef") (some "main") == .agent "main"
#guard capActor none none == some .lead
#guard capActor (some "a1") (some "main") == some .owner
#guard capActor (some "a1") (some "reviewer") == some .reviewer
#guard capActor (some "a1") (some "code-REVIEWER") == some .reviewer
#guard capActor (some "a1") (some "lean-prover") == some .owner
#guard capActor (some "a1") (some "") == none
#guard capActor (some "a1") none == none
#guard isReviewRole "math-reviewer" && !isReviewRole "revie" && !isReviewRole ""

end Fw.Ops.Identity
