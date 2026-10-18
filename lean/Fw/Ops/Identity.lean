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

$$\operatorname{isReviewRole}(t) = \operatorname{infixOf}(\texttt{review}, \operatorname{lower}(t)),\quad \text{where } \operatorname{lower} \text{ lowercases ASCII letters only (as JavaScript's } \texttt{/review/i} \text{ does)}$$

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

/-!
## The capability decision and the open door (cap-diagnose; PLAN §8.3, R27)

`cap.mjs` (the `PreToolUse(Bash)` hook) first splits a Bash command into the tokens of its first simple
command (shell quoting; an unquoted `;`, `&`, `|` or newline ends it). Everything after that split is a
decision and is made here: mint a capability for `pnpm fw <argv>`, or mint nothing **for exactly one named
reason**, so `pnpm fw` can print the reason instead of a bare 403 (`capDecide_mint_iff`,
`capDecide_noMint_iff`). The console-api door without a capability (`POST /api/commands`) is decided here
too (`openDoor`): an actor that needs a capability (`lead`, `owner`, `reviewer`; exactly the range of
`capActor`, `isAgentActor_iff`) is refused there unless the caller shows the console secret.

Consumers, checked against `packages/contracts/golden/ops/ops.cap.jsonl` and `ops.door.jsonl`: `cap.mjs`
`decideCap`, console-api `cap/cap.ts` `openDoor`.
-/

/-- Why no capability is minted; exactly one reason per refusal.

$$\mathrm{Reason} = \{\mathrm{notFwPrefix},\ \mathrm{unknownActor}\}$$

`notFwPrefix`: the command does not start with `pnpm fw` (a leading `cd`, or `pnpm -s fw`). `unknownActor`:
the sender is a forked agent without an `agent_type`, or has an empty id. A trailing filter pipe or a redirect
is not a reason: the tokenizer drops it (`capDecide_pipe_invariant`).
-/
inductive Reason where
  | notFwPrefix
  | unknownActor
deriving DecidableEq, Repr

/-- The wire name of a reason.

$$\operatorname{name}(r) = \text{the constructor name of } r \text{ as a string, e.g. } \operatorname{name}(\mathrm{notFwPrefix}) = \texttt{"notFwPrefix"}$$

The string the hook records and `pnpm fw` prints.
-/
def Reason.name : Reason → String
  | .notFwPrefix => "notFwPrefix" | .unknownActor => "unknownActor"

/-- The outcome of the capability hook: mint for an actor and an argv, or mint nothing for one reason.

$$\mathrm{CapDecision} = \{\mathrm{mint}(a, \vec{x}) \mid a \in \mathrm{Actor},\ \vec{x} \in \mathrm{String}^*\} \cup \{\mathrm{noMint}(r) \mid r \in \mathrm{Reason}\}$$

The two kinds of answer of `capDecide`.
-/
inductive CapDecision where
  | mint (actor : Actor) (argv : List String)
  | noMint (reason : Reason)
deriving DecidableEq, Repr

/-- A lexed token of a Bash input: a word, a redirect (operator and target, e.g. `2>&1`, `>f`, `>>f`), or a
top-level control operator (`|`, `;`, `&&`, newline) that ends the first simple command.

$$\mathrm{Tok} = \{\mathrm{word}(s) \mid s \in \mathrm{String}\} \cup \{\mathrm{redir},\ \mathrm{stop}\}$$

The lexer (quotes, operators) is I/O glue in `cap.mjs`; its output is classified into these three kinds.
-/
inductive Tok where
  | word (s : String)
  | redir
  | stop
deriving DecidableEq, Repr

/-- The words of the first simple command: redirects are dropped, a stop ends the command.

$$\operatorname{cmdWords}(\mathrm{word}(s)\cdot ts) = s \cdot \operatorname{cmdWords}(ts),\quad \operatorname{cmdWords}(\mathrm{redir}\cdot ts) = \operatorname{cmdWords}(ts),\quad \operatorname{cmdWords}(\mathrm{stop}\cdot ts) = \operatorname{cmdWords}([]) = []$$

This is the argv that `fw` sees and the hook hashes.
-/
def cmdWords : List Tok → List String
  | [] => []
  | .stop :: _ => []
  | .word s :: ts => s :: cmdWords ts
  | .redir :: ts => cmdWords ts

/-- Words of a stop-free prefix followed by anything split off.

$$\forall ts, u.\quad (\forall t \in ts.\ t \ne \mathrm{stop}) \implies \operatorname{cmdWords}(ts \cdot u) = \operatorname{cmdWords}(ts) \cdot \operatorname{cmdWords}(u)$$

Words concatenate over a prefix that has no control operator.
-/
theorem cmdWords_append (ts u : List Tok) (h : ∀ t ∈ ts, t ≠ .stop) :
    cmdWords (ts ++ u) = cmdWords ts ++ cmdWords u := by
  induction ts with
  | nil => simp [cmdWords]
  | cons t ts ih =>
    have ht : t ≠ .stop := h t (List.mem_cons_self ..)
    have ih' := ih (fun x hx => h x (List.mem_cons_of_mem _ hx))
    cases t with
    | word s => simp [cmdWords, ih']
    | redir => simp [cmdWords, ih']
    | stop => exact absurd rfl ht

/-- Redirects followed by a stop contribute no words.

$$\forall rs, rest.\quad (\forall r \in rs.\ r = \mathrm{redir}) \implies \operatorname{cmdWords}(rs \cdot \mathrm{stop} \cdot rest) = []$$

A tail of redirects and a pipe adds nothing to the argv.
-/
theorem cmdWords_redirs_stop (rs rest : List Tok) (h : ∀ r ∈ rs, r = .redir) :
    cmdWords (rs ++ .stop :: rest) = [] := by
  induction rs with
  | nil => simp [cmdWords]
  | cons r rs ih =>
    have hr : r = .redir := h r (List.mem_cons_self ..)
    subst hr
    simpa [cmdWords] using ih (fun x hx => h x (List.mem_cons_of_mem _ hx))

/-- The capability decision for a record's identity and the words of its first simple command.

$$\operatorname{capDecide}(i, t, \vec{w}) = \begin{cases} \mathrm{noMint}(\mathrm{notFwPrefix}) & \nexists \vec{x}.\ \vec{w} = \texttt{pnpm}\cdot\texttt{fw}\cdot\vec{x} \\ \mathrm{noMint}(\mathrm{unknownActor}) & \vec{w} = \texttt{pnpm}\cdot\texttt{fw}\cdot\vec{x} \wedge \operatorname{capActor}(i, t) = \bot \\ \mathrm{mint}(a, \vec{x}) & \vec{w} = \texttt{pnpm}\cdot\texttt{fw}\cdot\vec{x} \wedge \operatorname{capActor}(i, t) = a \end{cases}$$

The checks run in the order prefix, identity.
-/
def capDecide (i t : Option String) : List String → CapDecision
  | "pnpm" :: "fw" :: argv =>
    match capActor i t with
    | some a => .mint a argv
    | none => .noMint .unknownActor
  | _ => .noMint .notFwPrefix

/-- `capDecide` on a `pnpm fw` command unfolds to the identity check.

$$\forall i, t, \vec{x}.\quad \operatorname{capDecide}(i, t, \texttt{pnpm}\cdot\texttt{fw}\cdot\vec{x}) = \begin{cases} \mathrm{mint}(a, \vec{x}) & \operatorname{capActor}(i, t) = a \\ \mathrm{noMint}(\mathrm{unknownActor}) & \operatorname{capActor}(i, t) = \bot \end{cases}$$

The defining equation, stated for use in the iff theorems.
-/
theorem capDecide_fw (i t : Option String) (argv : List String) :
    capDecide i t ("pnpm" :: "fw" :: argv) =
      match capActor i t with
      | some a => .mint a argv
      | none => .noMint .unknownActor := rfl

/-- Any command that does not start with `pnpm fw` is refused as `notFwPrefix`.

$$\forall i, t, \vec{w}.\quad (\nexists \vec{x}.\ \vec{w} = \texttt{pnpm}\cdot\texttt{fw}\cdot\vec{x}) \implies \operatorname{capDecide}(i, t, \vec{w}) = \mathrm{noMint}(\mathrm{notFwPrefix})$$

The prefix check comes first, whatever the sender is.
-/
theorem capDecide_other (i t : Option String) (w : List String) (h : ∀ x, w ≠ "pnpm" :: "fw" :: x) :
    capDecide i t w = .noMint .notFwPrefix := by
  unfold capDecide
  split
  · rename_i x; exact absurd rfl (h x)
  · rfl

/-- A capability is minted exactly for a `pnpm fw` command from a known sender.

$$\forall i, t, \vec{w}, a, \vec{x}.\quad \operatorname{capDecide}(i, t, \vec{w}) = \mathrm{mint}(a, \vec{x}) \iff \vec{w} = \texttt{pnpm}\cdot\texttt{fw}\cdot\vec{x} \wedge \operatorname{capActor}(i, t) = a$$

The minted argv is exactly what follows `pnpm fw`, and the minted actor is the one of `capActor`.
-/
theorem capDecide_mint_iff (i t : Option String) (w : List String) (a : Actor) (x : List String) :
    capDecide i t w = .mint a x ↔ w = "pnpm" :: "fw" :: x ∧ capActor i t = some a := by
  by_cases hw : ∃ y, w = "pnpm" :: "fw" :: y
  · obtain ⟨y, rfl⟩ := hw
    rw [capDecide_fw]
    cases hc : capActor i t with
    | none => simp
    | some b =>
      simp only [CapDecision.mint.injEq, List.cons.injEq, true_and, Option.some.injEq]
      constructor
      · rintro ⟨rfl, rfl⟩; exact ⟨rfl, rfl⟩
      · rintro ⟨rfl, rfl⟩; exact ⟨rfl, rfl⟩
  · rw [capDecide_other i t w (fun y h => hw ⟨y, h⟩)]
    simp only [reduceCtorEq, false_iff, not_and]
    intro h; exact absurd ⟨x, h⟩ hw

/-- No capability is minted for exactly one reason, decided by the two checks in order.

$$\operatorname{capDecide}(i, t, \vec{w}) = \mathrm{noMint}(r) \iff \begin{cases} \nexists \vec{x}.\ \vec{w} = \texttt{pnpm}\cdot\texttt{fw}\cdot\vec{x} & r = \mathrm{notFwPrefix} \\ \exists \vec{x}.\ \vec{w} = \texttt{pnpm}\cdot\texttt{fw}\cdot\vec{x} \wedge \operatorname{capActor}(i, t) = \bot & r = \mathrm{unknownActor} \end{cases}$$

The two reasons are mutually exclusive: each refusal carries the one reason whose condition holds.
-/
theorem capDecide_noMint_iff (i t : Option String) (w : List String) (r : Reason) :
    capDecide i t w = .noMint r ↔
      (r = .notFwPrefix ∧ ∀ x, w ≠ "pnpm" :: "fw" :: x) ∨
      (r = .unknownActor ∧ ∃ x, w = "pnpm" :: "fw" :: x ∧ capActor i t = none) := by
  by_cases hw : ∃ y, w = "pnpm" :: "fw" :: y
  · obtain ⟨y, rfl⟩ := hw
    rw [capDecide_fw]
    cases hc : capActor i t <;> cases r <;> simp
  · rw [capDecide_other i t w (fun y h => hw ⟨y, h⟩)]
    have : ∀ x, w ≠ "pnpm" :: "fw" :: x := fun y h => hw ⟨y, h⟩
    cases r <;> simp [this]

/-- A trailing filter pipe or redirect does not change the decision.

$$\forall i, t, ts, rs, rest.\quad (\forall t' \in ts.\ t' \ne \mathrm{stop}) \wedge (\forall r \in rs.\ r = \mathrm{redir}) \implies \operatorname{capDecide}(i, t, \operatorname{cmdWords}(ts \cdot rs \cdot \mathrm{stop} \cdot rest)) = \operatorname{capDecide}(i, t, \operatorname{cmdWords}(ts))$$

So `pnpm fw x 2>&1 | tail -5` mints exactly what `pnpm fw x` mints.
-/
theorem capDecide_pipe_invariant (i t : Option String) (ts rs rest : List Tok)
    (hts : ∀ x ∈ ts, x ≠ .stop) (hrs : ∀ r ∈ rs, r = .redir) :
    capDecide i t (cmdWords (ts ++ (rs ++ .stop :: rest))) = capDecide i t (cmdWords ts) := by
  rw [cmdWords_append ts _ hts, cmdWords_redirs_stop rs rest hrs, List.append_nil]

/-- The refusal reason is unique: a command cannot be refused for two reasons.

$$\forall i, t, \vec{w}, r, r'.\quad \operatorname{capDecide}(i, t, \vec{w}) = \mathrm{noMint}(r) \wedge \operatorname{capDecide}(i, t, \vec{w}) = \mathrm{noMint}(r') \implies r = r'$$

`capDecide` is a function, so one command and one sender give one answer.
-/
theorem capDecide_noMint_unique (i t : Option String) (w : List String) (r r' : Reason)
    (h : capDecide i t w = .noMint r) (h' : capDecide i t w = .noMint r') : r = r' := by
  rw [h] at h'; exact CapDecision.noMint.inj h'

/-- A minted capability is for the lead, a reviewer or an owner, and only a record without `agent_id` gets the lead.

$$\forall i, t, \vec{w}, a, \vec{x}.\quad \operatorname{capDecide}(i, t, \vec{w}) = \mathrm{mint}(a, \vec{x}) \implies a \in \{\mathrm{lead}, \mathrm{reviewer}, \mathrm{owner}\} \wedge (a = \mathrm{lead} \iff i = \bot)$$

The hook never mints a capability for the user, a script, git or a hook, and never lets an agent be the lead.
-/
theorem capDecide_mint_actor (i t : Option String) (w : List String) (a : Actor) (x : List String)
    (h : capDecide i t w = .mint a x) :
    (a = .lead ∨ a = .reviewer ∨ a = .owner) ∧ (a = .lead ↔ i = none) := by
  obtain ⟨-, hc⟩ := (capDecide_mint_iff i t w a x).1 h
  exact ⟨capActor_range i t a hc, by rw [← capActor_lead_iff, hc]; simp⟩

/-! ## The door without capability -/

/-- An actor that only a capability may speak as.

$$\operatorname{isAgentActor}(a) = \mathrm{true} \iff a \in \{\mathrm{lead}, \mathrm{owner}, \mathrm{reviewer}\}$$

The agent-facing actors; `user`, `script`, `git` and `hook` are not.
-/
def isAgentActor : Actor → Bool
  | .lead | .owner | .reviewer => true
  | _ => false

/-- The door without capability (`POST /api/commands`): a body that claims an agent actor needs the console secret.

$$\operatorname{openDoor}(a, s) = \mathrm{true} \iff \neg\operatorname{isAgentActor}(a) \vee s = \mathrm{true}$$

The web UI (`user`) and the internal script, git and hook actors pass; `lead`, `owner` and `reviewer` pass only with the secret.
-/
def openDoor (a : Actor) (secret : Bool) : Bool := !isAgentActor a || secret

/-- The agent actors are exactly the actors a capability can be minted for.

$$\forall a \in \mathrm{Actor}.\quad \operatorname{isAgentActor}(a) = \mathrm{true} \iff \exists i, t.\ \operatorname{capActor}(i, t) = a$$

So the open door refuses precisely the actors that the capability door is the only legitimate source of.
-/
theorem isAgentActor_iff (a : Actor) : isAgentActor a = true ↔ ∃ i t, capActor i t = some a := by
  constructor
  · intro h
    cases a <;> simp [isAgentActor] at h
    · exact ⟨none, none, rfl⟩
    · exact ⟨some "a1", some "lean-prover", by decide +kernel⟩
    · exact ⟨some "a1", some "reviewer", by decide +kernel⟩
  · rintro ⟨i, t, h⟩
    rcases capActor_range i t a h with rfl | rfl | rfl <;> rfl

/-- Without the secret, the open door refuses exactly the agent actors.

$$\forall a \in \mathrm{Actor}.\quad \operatorname{openDoor}(a, \mathrm{false}) = \mathrm{false} \iff a \in \{\mathrm{lead}, \mathrm{owner}, \mathrm{reviewer}\}$$

A self-declared actor in a request body cannot make a command look like an agent's.
-/
theorem openDoor_no_secret (a : Actor) : openDoor a false = false ↔ isAgentActor a = true := by
  simp [openDoor]

/-- With the secret, the open door accepts every actor.

$$\forall a \in \mathrm{Actor}.\quad \operatorname{openDoor}(a, \mathrm{true}) = \mathrm{true}$$

The console's own tools (the plan sync of `fw land`) read the secret and speak as the lead.
-/
theorem openDoor_secret (a : Actor) : openDoor a true = true := by
  simp [openDoor]

/-! ## Examples (the golden edge cases) -/

#guard capDecide none none ["pnpm", "fw", "status"] == .mint .lead ["status"]
#guard capDecide (some "a1") (some "lean-prover") ["pnpm", "fw", "land", "b"] == .mint .owner ["land", "b"]
#guard capDecide (some "a1") (some "") ["pnpm", "fw", "status"] == .noMint .unknownActor
#guard capDecide none none ["cd", "x"] == .noMint .notFwPrefix
#guard capDecide none none ["pnpm", "-s", "fw", "land"] == .noMint .notFwPrefix
#guard cmdWords [.word "pnpm", .word "fw", .word "land", .word "b", .redir, .stop, .word "tail"] == ["pnpm", "fw", "land", "b"]
#guard openDoor .user false && !openDoor .lead false && openDoor .lead true


end Fw.Ops.Identity
