/-!
# Observed tool calls: the obs key and the per-(agent type, tool) summary (`ops.obs`)

Replaces console-api's TS stand-ins in `apps/console-api/src/spool/drain.ts` (task `lean-console-gaps`):

* **Key join.** An observation's idempotency key is `agent|event|id`, where `agent` is the
  `agent_id` (or `main` when there is none), and `id` is the `tool_use_id`, or the record's
  timestamp when the event carries no tool use (hook-only events). A hook record and a transcript
  record of the same tool call therefore get the same key, whatever their timestamps
  (`obsKey_tool_ts`).
* **Summary.** Tool calls (`PostToolUse`, `PostToolUseFailure`) grouped by (agent type, tool), with
  `main` and `?` for a missing agent type or tool name: the number of calls, of errors
  (`is_error = true`) and the summed `duration_ms` (missing = 0). Groups appear in the order of
  their first call. Proved: the groups are exactly the groups of the tool calls
  (`mem_groups`), each group appears once (`groups_nodup`), and every row holds the counts of its
  group (`summarize_row`).
-/
namespace Fw.Ops.Obs

/-! ## Key join -/

/-- The idempotency key of an observation: agent id (or `main`), event and tool-use id (or the
timestamp), joined by `|`.

$$\operatorname{obsKey}(i, e, u, t) = a \mathbin{+\!\!+} \texttt{"|"} \mathbin{+\!\!+} e \mathbin{+\!\!+} \texttt{"|"} \mathbin{+\!\!+} x, \quad a = \begin{cases} s & i = s \\ \texttt{"main"} & i = \bot \end{cases}, \quad x = \begin{cases} v & u = v \\ \operatorname{dec}(t) & u = \bot \end{cases} \qquad (i, u \in \mathrm{String} \cup \{\bot\},\ e \in \mathrm{String},\ t \in \mathbb{N})$$

where $\operatorname{dec}(t)$ is the decimal numeral of $t$; an empty string $s$ or $v$ is kept as it is (only $\bot$ is replaced).
The key names who did what, and which tool call or moment it was.
-/
def obsKey (agentId : Option String) (event : String) (toolUseId : Option String) (ts : Nat) : String :=
  agentId.getD "main" ++ "|" ++ event ++ "|" ++ toolUseId.getD (toString ts)

/-- With a tool-use id the key does not depend on the timestamp, so the hook record and the
transcript record of one tool call share a key.

$$\forall i \in \mathrm{String} \cup \{\bot\},\ e, v \in \mathrm{String},\ t_1, t_2 \in \mathbb{N}:\quad \operatorname{obsKey}(i, e, v, t_1) = \operatorname{obsKey}(i, e, v, t_2)$$

Two records of the same tool call get the same key at any times.
-/
theorem obsKey_tool_ts (i : Option String) (e v : String) (t₁ t₂ : Nat) :
    obsKey i e (some v) t₁ = obsKey i e (some v) t₂ := rfl

/-- Without a tool-use id the timestamp is the last part of the key.

$$\forall i \in \mathrm{String} \cup \{\bot\},\ e \in \mathrm{String},\ t \in \mathbb{N}:\quad \operatorname{obsKey}(i, e, \bot, t) = \operatorname{obsKey}(i, e, \operatorname{dec}(t), 0)$$

A hook-only event is keyed by its timestamp, exactly as if the timestamp were its tool-use id.
-/
theorem obsKey_no_tool (i : Option String) (e : String) (t : Nat) :
    obsKey i e none t = obsKey i e (some (toString t)) 0 := rfl

#guard obsKey none "Stop" none 42 == "main|Stop|42"
#guard obsKey (some "a1") "PostToolUse" (some "toolu_1") 7 == "a1|PostToolUse|toolu_1"
#guard obsKey (some "") "X" (some "") 7 == "|X|"

/-! ## Summary -/

/-- One observed line, as far as the summary reads it.

$$\ell = (\mathit{event}, \mathit{agentType}_\bot, \mathit{toolName}_\bot, \mathit{isError}_\bot, \mathit{durationMs}_\bot)$$

The fields of an `obs.jsonl` line that the tool-call summary uses.
-/
structure Line where
  event      : String
  agentType  : Option String := none
  toolName   : Option String := none
  isError    : Option Bool := none
  durationMs : Option Nat := none
deriving Repr, DecidableEq

/-- A line is a tool call when its event is `PostToolUse` or `PostToolUseFailure`.

$$\operatorname{isCall}(\ell) \iff \ell.\mathit{event} \in \{\texttt{"PostToolUse"}, \texttt{"PostToolUseFailure"}\}$$

Only finished tool calls count; every other hook event is ignored by the summary.
-/
def isCall (l : Line) : Bool := l.event == "PostToolUse" || l.event == "PostToolUseFailure"

/-- The group of a line: its agent type (`main` when missing) and its tool name (`?` when missing).

$$\operatorname{group}(\ell) = (\ell.\mathit{agentType} \text{ or } \texttt{"main"},\ \ell.\mathit{toolName} \text{ or } \texttt{"?"})$$

Lines are grouped by who called which tool.
-/
def group (l : Line) : String × String := (l.agentType.getD "main", l.toolName.getD "?")

/-- One summary row: a group and its counts.

$$r = (\mathit{agentType}, \mathit{toolName}, \mathit{calls}, \mathit{errors}, \mathit{totalMs})$$

The totals of one (agent type, tool) group.
-/
structure Row where
  agentType : String
  toolName  : String
  calls     : Nat
  errors    : Nat
  totalMs   : Nat
deriving Repr, DecidableEq

/-- The list without repeats, keeping first occurrences, skipping the elements of `seen`.

$$\operatorname{uniqAux}(S, [\,]) = [\,], \qquad \operatorname{uniqAux}(S, a :: w) = \begin{cases} \operatorname{uniqAux}(S, w) & a \in S \\ a :: \operatorname{uniqAux}(\{a\} \cup S, w) & a \notin S \end{cases}$$

Walk the list and keep each element the first time it is met.
-/
def uniqAux {α : Type} [DecidableEq α] : List α → List α → List α
  | _, [] => []
  | seen, a :: as => if a ∈ seen then uniqAux seen as else a :: uniqAux (a :: seen) as

/-- The list without repeats, in first-occurrence order.

$$\operatorname{uniq}(w) = \operatorname{uniqAux}(\emptyset, w)$$

Each element once, in the order it first appears.
-/
def uniq {α : Type} [DecidableEq α] (l : List α) : List α := uniqAux [] l

/-- The groups of the tool calls, in the order of their first call.

$$\operatorname{groups}(L) = \operatorname{uniq}([\operatorname{group}(\ell) \mid \ell \in L,\ \operatorname{isCall}(\ell)])$$

Every (agent type, tool) pair that made at least one call, once each.
-/
def groups (ls : List Line) : List (String × String) := uniq ((ls.filter isCall).map group)

/-- The row of group $k$: its tool calls, their errors and their summed duration.

$$\operatorname{row}(L, k) = (k_1, k_2, |C|, |[\ell \in C \mid \ell.\mathit{isError} = \mathrm{true}]|, \textstyle\sum_{\ell \in C} (\ell.\mathit{durationMs} \text{ or } 0)), \quad C = [\ell \in L \mid \operatorname{isCall}(\ell) \land \operatorname{group}(\ell) = k]$$

The counts of one group, read straight off the lines.
-/
def rowFor (ls : List Line) (k : String × String) : Row :=
  let c := ls.filter fun l => isCall l && group l == k
  ⟨k.1, k.2, c.length, (c.filter (·.isError == some true)).length, (c.map (·.durationMs.getD 0)).sum⟩

/-- The tool-call summary: one row per group, in the order of the group's first call.

$$\operatorname{summarize}(L) = [\operatorname{row}(L, k) \mid k \in \operatorname{groups}(L)]$$

Count calls, errors and time per (agent type, tool).
-/
def summarize (ls : List Line) : List Row := (groups ls).map (rowFor ls)

/-! ## Proofs -/

/-- Membership in `uniqAux`: an element of the list not already seen.

$$\forall S, w, x:\quad x \in \operatorname{uniqAux}(S, w) \iff x \in w \land x \notin S$$

`uniqAux` keeps exactly the unseen elements.
-/
theorem mem_uniqAux {α : Type} [DecidableEq α] (seen l : List α) (x : α) :
    x ∈ uniqAux seen l ↔ x ∈ l ∧ x ∉ seen := by
  induction l generalizing seen with
  | nil => simp [uniqAux]
  | cons a as ih =>
    by_cases h : a ∈ seen
    · simp only [uniqAux, h, ↓reduceIte, ih, List.mem_cons]
      constructor
      · rintro ⟨h1, h2⟩; exact ⟨Or.inr h1, h2⟩
      · rintro ⟨h1 | h1, h2⟩
        · subst h1; exact absurd h h2
        · exact ⟨h1, h2⟩
    · simp only [uniqAux, h, ↓reduceIte, List.mem_cons, ih]
      constructor
      · rintro (h1 | ⟨h1, h2⟩)
        · subst h1; exact ⟨Or.inl rfl, h⟩
        · exact ⟨Or.inr h1, fun h3 => h2 (Or.inr h3)⟩
      · rintro ⟨h1 | h1, h2⟩
        · exact Or.inl h1
        · by_cases hx : x = a
          · exact Or.inl hx
          · exact Or.inr ⟨h1, fun h3 => h3.elim hx h2⟩

/-- `uniqAux` has no repeats.

$$\forall S, w:\quad \operatorname{uniqAux}(S, w) \text{ has pairwise distinct elements}$$

Each kept element is kept once.
-/
theorem uniqAux_nodup {α : Type} [DecidableEq α] (seen l : List α) : (uniqAux seen l).Nodup := by
  induction l generalizing seen with
  | nil => exact List.nodup_nil
  | cons a as ih =>
    by_cases h : a ∈ seen
    · simp only [uniqAux, h, ↓reduceIte]; exact ih seen
    · simp only [uniqAux, h, ↓reduceIte]
      refine List.nodup_cons.mpr ⟨?_, ih _⟩
      intro hm
      exact ((mem_uniqAux _ _ _).mp hm).2 (List.mem_cons_self ..)

/-- The groups are exactly the groups of the tool calls.

$$\forall L, k:\quad k \in \operatorname{groups}(L) \iff \exists \ell \in L:\ \operatorname{isCall}(\ell) \land \operatorname{group}(\ell) = k$$

A group has a row exactly when some tool call falls in it.
-/
theorem mem_groups (ls : List Line) (k : String × String) :
    k ∈ groups ls ↔ ∃ l ∈ ls, isCall l = true ∧ group l = k := by
  simp [groups, uniq, mem_uniqAux, and_assoc]

/-- Each group appears once.

$$\forall L:\quad \operatorname{groups}(L) \text{ has pairwise distinct elements}$$

No (agent type, tool) pair gets two rows.
-/
theorem groups_nodup (ls : List Line) : (groups ls).Nodup := uniqAux_nodup _ _

/-- Every summary row holds the counts of its own group.

$$\forall L, r:\quad r \in \operatorname{summarize}(L) \implies (r.\mathit{agentType}, r.\mathit{toolName}) \in \operatorname{groups}(L) \land r = \operatorname{row}(L, (r.\mathit{agentType}, r.\mathit{toolName}))$$

A row's calls, errors and time are the counts over the tool calls of that group.
-/
theorem summarize_row (ls : List Line) (r : Row) (h : r ∈ summarize ls) :
    (r.agentType, r.toolName) ∈ groups ls ∧ r = rowFor ls (r.agentType, r.toolName) := by
  simp only [summarize, List.mem_map] at h
  obtain ⟨k, hk, rfl⟩ := h
  exact ⟨hk, rfl⟩

/-- Lines that are not tool calls change nothing.

$$\forall L, \ell:\quad \lnot\operatorname{isCall}(\ell) \implies \operatorname{summarize}(\ell :: L) = \operatorname{summarize}(L)$$

Non-tool events (starts, stops, prompts) never show up in the summary.
-/
theorem summarize_skip (ls : List Line) (l : Line) (h : isCall l = false) :
    summarize (l :: ls) = summarize ls := by
  simp [summarize, groups, rowFor, h]

/-! ## Examples -/

#guard summarize [] == []
#guard summarize [⟨"SubagentStart", some "b", none, none, none⟩] == []
#guard summarize [⟨"PostToolUse", some "b", some "Bash", none, some 100⟩,
    ⟨"PostToolUseFailure", some "b", some "Bash", some true, some 50⟩,
    ⟨"PostToolUse", none, none, some false, none⟩] ==
  [⟨"b", "Bash", 2, 1, 150⟩, ⟨"main", "?", 1, 0, 0⟩]
#guard groups [⟨"PostToolUse", some "x", some "T", none, none⟩, ⟨"PostToolUse", some "y", some "T", none, none⟩,
    ⟨"PostToolUse", some "x", some "T", none, none⟩] == [("x", "T"), ("y", "T")]

end Fw.Ops.Obs
