import Lean.Data.Json
import Fw.Ops.Wire
/-!
# Context-budget lint (task context-slop)

A verdict per agent-read text file: `ok`, `overBudget m` (measure `m` is over the budget of the file's kind) or
`slop s` (the first mechanical slop marker). `scripts/context-lint.mjs` only reads the files and sends their path,
byte size and lines; every rule is here. The rules and their evidence: research/notes/2026/10-18-context-slop.md.

Proved: every file gets exactly one verdict class (`verdict_cases`), and a file that is no larger in any measure
never gets a worse budget verdict (`overBudget_mono`, `rank_mono`).
-/
namespace Fw.Lint.Context

/-- The kinds of agent-read text the lint knows.

$$\mathrm{FileKind} = \{\mathrm{claudeMd},\ \mathrm{agent},\ \mathrm{skill},\ \mathrm{handoff},\ \mathrm{teamDoc},\ \mathrm{other}\}$$
-/
inductive FileKind where
  | claudeMd | agent | skill | handoff | teamDoc | other
deriving DecidableEq, Repr

/-- The kind of a repo-relative path, by its `/`-separated segments: `CLAUDE.md`; `.claude/agents/f` with `f` ending
in `.md`; `.claude/skills/d/SKILL.md`; `docs/team/handoffs/f` with `f` ending in `.md`; `docs/team/tools/f` with `f`
ending in `.md`, or `docs/team/token-policy.md`; anything else is `other`.

$$\mathrm{kind}(p) = \begin{cases} \mathrm{claudeMd} & p = \texttt{CLAUDE.md} \\ \mathrm{agent} & p = \texttt{.claude/agents/}f,\ f \text{ has no } \texttt{/},\ f \text{ ends in } \texttt{.md} \\ \mathrm{skill} & p = \texttt{.claude/skills/}d\texttt{/SKILL.md},\ d \text{ has no } \texttt{/} \\ \mathrm{handoff} & p = \texttt{docs/team/handoffs/}f,\ f \text{ has no } \texttt{/},\ f \text{ ends in } \texttt{.md} \\ \mathrm{teamDoc} & p = \texttt{docs/team/tools/}f,\ f \text{ has no } \texttt{/},\ f \text{ ends in } \texttt{.md},\ \text{or } p = \texttt{docs/team/token-policy.md} \\ \mathrm{other} & \text{otherwise} \end{cases}$$
-/
def kindOf (path : String) : FileKind :=
  match path.splitOn "/" with
  | ["CLAUDE.md"] => .claudeMd
  | [".claude", "agents", f] => if f.endsWith ".md" then .agent else .other
  | [".claude", "skills", _, "SKILL.md"] => .skill
  | ["docs", "team", "handoffs", f] => if f.endsWith ".md" then .handoff else .other
  | ["docs", "team", "tools", f] => if f.endsWith ".md" then .teamDoc else .other
  | ["docs", "team", "token-policy.md"] => .teamDoc
  | _ => .other

/-- A budget: optional caps on the byte size, the line count and the byte size of the frontmatter `description`
(`none` = no cap).

$$\mathrm{Budget} = (\mathrm{Option}\ \mathbb{N})^3, \qquad \beta = (\beta.\mathit{bytes},\ \beta.\mathit{lines},\ \beta.\mathit{desc})$$
-/
structure Budget where
  bytes : Option Nat
  lines : Option Nat
  desc  : Option Nat
deriving DecidableEq, Repr

/-- The budget of each kind. `CLAUDE.md` and the agent bodies load on every spawn, a skill description on every
session (its body on use), a handoff is capped at 30 lines (CLAUDE.md), and a team doc is read on most tasks.

$$\beta(\mathrm{claudeMd}) = (5000, \bot, \bot),\ \beta(\mathrm{agent}) = (2000, \bot, 300),\ \beta(\mathrm{skill}) = (4000, \bot, 300),\ \beta(\mathrm{handoff}) = (\bot, 30, \bot),\ \beta(\mathrm{teamDoc}) = (6000, \bot, \bot),\ \beta(\mathrm{other}) = (\bot, \bot, \bot)$$
-/
def budget : FileKind → Budget
  | .claudeMd => ⟨some 5000, none, none⟩
  | .agent => ⟨some 2000, none, some 300⟩
  | .skill => ⟨some 4000, none, some 300⟩
  | .handoff => ⟨none, some 30, none⟩
  | .teamDoc => ⟨some 6000, none, none⟩
  | .other => ⟨none, none, none⟩

/-- The mechanical slop markers: a commit SHA in an agent or skill body (A7: bodies hold rules that outlive SHAs), a
date in an always-loaded file (dated narration), a heading named after a task (history in a doc meant for use), and an
AI-writing tell (an em dash, an inflated word or a filler phrase; D1, D2, D5, D11).

$$\mathrm{Slop} = \{\mathrm{sha},\ \mathrm{datedNote},\ \mathrm{historyHeading},\ \mathrm{aiTell}\}$$
-/
inductive Slop where
  | sha | datedNote | historyHeading | aiTell
deriving DecidableEq, Repr

/-- Every marker, in the order a line is checked.

$$S = [\mathrm{sha},\ \mathrm{datedNote},\ \mathrm{historyHeading},\ \mathrm{aiTell}]$$
-/
def allSlops : List Slop := [.sha, .datedNote, .historyHeading, .aiTell]

/-- The kinds a marker applies to: `sha` to agents and skills; `datedNote` to `CLAUDE.md`, agents and skills;
`historyHeading` to every kind but handoffs and `other`; `aiTell` to every kind but `other`.

$$\mathrm{applies}(s, k) \iff \begin{cases} k \in \{\mathrm{agent}, \mathrm{skill}\} & s = \mathrm{sha} \\ k \in \{\mathrm{claudeMd}, \mathrm{agent}, \mathrm{skill}\} & s = \mathrm{datedNote} \\ k \notin \{\mathrm{handoff}, \mathrm{other}\} & s = \mathrm{historyHeading} \\ k \ne \mathrm{other} & s = \mathrm{aiTell} \end{cases}$$
-/
def appliesTo : Slop → FileKind → Bool
  | .sha, k => k == .agent || k == .skill
  | .datedNote, k => k == .claudeMd || k == .agent || k == .skill
  | .historyHeading, k => k != .handoff && k != .other
  | .aiTell, k => k != .other

/-! ## Line scanners (on `List Char`) -/

/-- `p` occurs in `l` as a contiguous run.

$$\mathrm{infix}(p, l) \iff \exists u, v:\ l = u \mathbin{+\!\!+} p \mathbin{+\!\!+} v$$
-/
def infixB (p : List Char) : List Char → Bool
  | [] => p.isEmpty
  | l@(_ :: t) => p.isPrefixOf l || infixB p t

/-- The maximal runs of ASCII letters and digits in a line (the words), in order.

$$\mathrm{words}(l) = \text{the maximal nonempty runs of } [\texttt{0-9A-Za-z}] \text{ in } l, \text{ left to right}$$
-/
def words (l : List Char) : List (List Char) :=
  let (acc, cur) := l.foldl (fun (acc, cur) c =>
    if c.isAlphanum then (acc, cur ++ [c]) else if cur.isEmpty then (acc, cur) else (acc ++ [cur], [])) ([], [])
  if cur.isEmpty then acc else acc ++ [cur]

/-- A commit SHA: 7 to 40 lowercase hex digits with at least one digit and at least one letter (so a plain number
or an English word is not one).

$$\mathrm{isSha}(w) \iff 7 \le |w| \le 40 \land w \in [\texttt{0-9a-f}]^* \land \exists c \in w:\ c \in [\texttt{0-9}] \land \exists c \in w:\ c \in [\texttt{a-f}]$$
-/
def isSha (w : List Char) : Bool :=
  7 ≤ w.length && w.length ≤ 40 && w.all (fun c => c.isDigit || ('a' ≤ c && c ≤ 'f')) && w.any Char.isDigit
    && w.any (fun c => 'a' ≤ c && c ≤ 'f')

/-- A date `dddd-dd-dd` starts here.

$$\mathrm{dateAt}(l) \iff l = d_1 d_2 d_3 d_4 \texttt{-} d_5 d_6 \texttt{-} d_7 d_8 \mathbin{+\!\!+} v,\ d_i \in [\texttt{0-9}]$$
-/
def dateAt : List Char → Bool
  | a :: b :: c :: d :: '-' :: e :: f :: '-' :: g :: h :: _ => [a, b, c, d, e, f, g, h].all Char.isDigit
  | _ => false

/-- A date `dddd-dd-dd` occurs somewhere in the line.

$$\mathrm{hasDate}(l) \iff \exists u, v:\ l = u \mathbin{+\!\!+} v \land \mathrm{dateAt}(v)$$
-/
def hasDate : List Char → Bool
  | [] => false
  | l@(_ :: t) => dateAt l || hasDate t

/-- A task id: nonempty, only lowercase ASCII letters, digits and `-`, with at least one `-`.

$$\mathrm{isTaskId}(w) \iff w \in [\texttt{a-z0-9-}]^+ \land \texttt{-} \in w$$
-/
def isTaskId (w : List Char) : Bool :=
  !w.isEmpty && w.contains '-' && w.all (fun c => ('a' ≤ c && c ≤ 'z') || c.isDigit || c == '-')

/-- The text after the last `(` of a line, when the line has one.

$$\mathrm{afterParen}(l) = \begin{cases} v & l = u \mathbin{+\!\!+} [\texttt{(}] \mathbin{+\!\!+} v,\ \texttt{(} \notin v \\ \bot & \texttt{(} \notin l \end{cases}$$
-/
def afterParen (l : List Char) : Option (List Char) :=
  match l.reverse.span (· != '(') with
  | (rv, _ :: _) => some rv.reverse
  | (_, []) => none

/-- A markdown heading named after task history: after leading blanks it starts with `#`, and it holds `(task ` or
ends (before trailing blanks) with `(<task id>)`.

$$\mathrm{historyHeading}(l) \iff t_0 = \texttt{\#} \land \big(\mathrm{infix}(\texttt{(task }, t) \lor (t' = u \mathbin{+\!\!+} \texttt{)} \land \mathrm{afterParen}(u) = w \land \mathrm{isTaskId}(w))\big)$$
where $t$ is $l$ without leading spaces and tabs and $t'$ is $t$ without trailing spaces and tabs.
-/
def historyHeading (l : List Char) : Bool :=
  let blank (c : Char) : Bool := c == ' ' || c == '\t'
  let t := l.dropWhile blank
  let t' := (t.reverse.dropWhile blank).reverse
  t.head? == some '#' &&
    (infixB "(task ".toList t ||
      (t'.getLast? == some ')' && match afterParen t'.dropLast with
        | some w => isTaskId w
        | none => false))

/-- The inflated words of D2 and D5 (matched as whole lowercase words).

$$W = \{\texttt{delve}, \texttt{delves}, \texttt{delving}, \texttt{pivotal}, \texttt{crucial}, \texttt{showcase}, \texttt{showcases}, \texttt{showcasing}, \texttt{tapestry}, \texttt{testament}, \texttt{vibrant}, \texttt{seamless}, \texttt{seamlessly}, \texttt{leverage}, \texttt{leverages}, \texttt{leveraging}, \texttt{utilize}, \texttt{utilizes}, \texttt{utilizing}, \texttt{facilitate}, \texttt{facilitates}\}$$
-/
def aiWords : List String :=
  ["delve", "delves", "delving", "pivotal", "crucial", "showcase", "showcases", "showcasing", "tapestry", "testament",
   "vibrant", "seamless", "seamlessly", "leverage", "leverages", "leveraging", "utilize", "utilizes", "utilizing",
   "facilitate", "facilitates"]

/-- The filler phrases of D1 (matched in the lowercased line).

$$F = \{\texttt{in order to},\ \texttt{it is important to note}\}$$
-/
def fillers : List String := ["in order to", "it is important to note"]

/-- An AI-writing tell: an em dash (U+2014), a word of $W$, or a phrase of $F$, case-insensitive (ASCII).

$$\mathrm{aiTell}(l) \iff \texttt{—} \in l \lor \exists w \in \mathrm{words}(\mathrm{lower}(l)):\ w \in W \lor \exists f \in F:\ \mathrm{infix}(f, \mathrm{lower}(l))$$
-/
def aiTell (l : List Char) : Bool :=
  let low := l.map Char.toLower
  l.contains '—' || (words low).any (fun w => aiWords.contains (String.ofList w))
    || fillers.any (fun f => infixB f.toList low)

/-- Whether marker `s` fires on a line.

$$\mathrm{fires}(\mathrm{sha}, l) \iff \exists w \in \mathrm{words}(l):\ \mathrm{isSha}(w),\quad \mathrm{fires}(\mathrm{datedNote}, l) \iff \mathrm{hasDate}(l),\quad \mathrm{fires}(\mathrm{historyHeading}, l) \iff \mathrm{historyHeading}(l),\quad \mathrm{fires}(\mathrm{aiTell}, l) \iff \mathrm{aiTell}(l)$$
-/
def fires : Slop → List Char → Bool
  | .sha, l => (words l).any isSha
  | .datedNote, l => hasDate l
  | .historyHeading, l => historyHeading l
  | .aiTell, l => aiTell l

/-- The markers on one line of a file of kind `k`, in the order of $S$.

$$\mathrm{lineSlops}(k, l) = [\, s \in S \mid \mathrm{applies}(s, k) \land \mathrm{fires}(s, l) \,]$$
-/
def lineSlops (k : FileKind) (l : String) : List Slop :=
  allSlops.filter fun s => appliesTo s k && fires s l.toList

/-- Every hit `(marker, 1-based line number)` of a file, by line, then in the order of $S$.

$$\mathrm{hits}(k, [l_1, \dots, l_n]) = \mathrm{lineSlops}(k, l_1) \times \{1\} \mathbin{+\!\!+} \cdots \mathbin{+\!\!+} \mathrm{lineSlops}(k, l_n) \times \{n\}$$
-/
def hitsOf (k : FileKind) (lines : List String) : List (Slop × Nat) :=
  lines.zipIdx.flatMap fun (l, i) => (lineSlops k l).map (·, i + 1)

/-- The UTF-8 byte size of the frontmatter `description`: when the first line is `---`, the first line before the
next `---` that starts with `description:`, without that prefix and its leading spaces; 0 when there is none.

$$\mathrm{desc}(L) = \begin{cases} \|v\|_{\mathrm{utf8}} & L = \texttt{---} :: R,\ \text{the first } r \in \mathrm{takeWhile}(\ne \texttt{---}, R) \text{ with prefix } \texttt{description:} \text{ is } \texttt{description:}\,\sqcup^*\,v \\ 0 & \text{otherwise} \end{cases}$$
-/
def descOf (lines : List String) : Nat :=
  match lines with
  | "---" :: rest =>
    match (rest.takeWhile (· != "---")).find? (·.startsWith "description:") with
    | some l => (((l.toList.drop 12).dropWhile (· == ' ')).map Char.utf8Size).sum
    | none => 0
  | _ => 0

/-! ## The verdict -/

/-- The facts the verdict reads: the kind, the byte size, the line count, the description size and the hits.

$$\mathrm{Facts} = \mathrm{FileKind} \times \mathbb{N}^3 \times (\mathrm{Slop} \times \mathbb{N})^*, \qquad f = (f.\mathit{kind}, f.\mathit{bytes}, f.\mathit{lines}, f.\mathit{desc}, f.\mathit{hits})$$
-/
structure Facts where
  kind  : FileKind
  bytes : Nat
  lines : Nat
  desc  : Nat
  hits  : List (Slop × Nat)
deriving DecidableEq, Repr

/-- The facts of a file from its path, byte size and lines.

$$\mathrm{facts}(p, b, L) = (\mathrm{kind}(p),\ b,\ |L|,\ \mathrm{desc}(L),\ \mathrm{hits}(\mathrm{kind}(p), L))$$
-/
def factsOf (path : String) (bytes : Nat) (lines : List String) : Facts :=
  ⟨kindOf path, bytes, lines.length, descOf lines, hitsOf (kindOf path) lines⟩

/-- The measure that broke a budget.

$$\mathrm{Measure} = \{\mathrm{bytes},\ \mathrm{lines},\ \mathrm{desc}\}$$
-/
inductive Measure where
  | bytes | lines | desc
deriving DecidableEq, Repr

/-- A value is over an optional cap: strictly greater than it (no cap: never over).

$$\mathrm{over}(\bot, v) = \mathrm{false}, \qquad \mathrm{over}(c, v) \iff v > c$$
-/
def over : Option Nat → Nat → Bool
  | some c, v => c < v
  | none, _ => false

/-- The first measure over the kind's budget, checked in the order bytes, lines, description.

$$\mathrm{fail}(k, b, l, d) = \begin{cases} \mathrm{bytes} & \mathrm{over}(\beta(k).\mathit{bytes}, b) \\ \mathrm{lines} & \lnot\mathrm{over}(\beta(k).\mathit{bytes}, b) \land \mathrm{over}(\beta(k).\mathit{lines}, l) \\ \mathrm{desc} & \lnot\mathrm{over}(\beta(k).\mathit{bytes}, b) \land \lnot\mathrm{over}(\beta(k).\mathit{lines}, l) \land \mathrm{over}(\beta(k).\mathit{desc}, d) \\ \bot & \text{otherwise} \end{cases}$$
-/
def budgetFail (k : FileKind) (b l d : Nat) : Option Measure :=
  if over (budget k).bytes b then some .bytes
  else if over (budget k).lines l then some .lines
  else if over (budget k).desc d then some .desc
  else none

/-- A verdict.

$$\mathrm{Verdict} = \mathrm{ok} \mid \mathrm{overBudget}(m),\ m \in \mathrm{Measure} \mid \mathrm{slop}(s),\ s \in \mathrm{Slop}$$
-/
inductive Verdict where
  | ok | overBudget (m : Measure) | slop (s : Slop)
deriving DecidableEq, Repr

/-- The verdict: over budget first; else the marker of the first hit; else ok.

$$\mathrm{verdict}(f) = \begin{cases} \mathrm{overBudget}(m) & \mathrm{fail}(f.\mathit{kind}, f.\mathit{bytes}, f.\mathit{lines}, f.\mathit{desc}) = m \\ \mathrm{slop}(s) & \mathrm{fail}(\dots) = \bot \land f.\mathit{hits} = (s, n) :: r \\ \mathrm{ok} & \mathrm{fail}(\dots) = \bot \land f.\mathit{hits} = [] \end{cases}$$
-/
def verdict (f : Facts) : Verdict :=
  match budgetFail f.kind f.bytes f.lines f.desc with
  | some m => .overBudget m
  | none =>
    match f.hits with
    | (s, _) :: _ => .slop s
    | [] => .ok

/-- How bad a verdict is for the budget order: ok, then slop, then over budget.

$$\mathrm{rank}(\mathrm{ok}) = 0,\quad \mathrm{rank}(\mathrm{slop}(s)) = 1,\quad \mathrm{rank}(\mathrm{overBudget}(m)) = 2$$
-/
def rank : Verdict → Nat
  | .ok => 0
  | .slop _ => 1
  | .overBudget _ => 2

/-! ## Proofs -/

/-- Every file gets exactly one verdict class, and the class is the one the definition names: over budget with the
failing measure, slop with the first hit's marker, or ok with no failing measure and no hit.

$$\forall f:\ \big(\exists m:\ \mathrm{verdict}(f) = \mathrm{overBudget}(m) \land \mathrm{fail}(f) = m\big) \lor \big(\exists s, n, r:\ \mathrm{verdict}(f) = \mathrm{slop}(s) \land \mathrm{fail}(f) = \bot \land f.\mathit{hits} = (s, n) :: r\big) \lor \big(\mathrm{verdict}(f) = \mathrm{ok} \land \mathrm{fail}(f) = \bot \land f.\mathit{hits} = []\big)$$
where $\mathrm{fail}(f) = \mathrm{fail}(f.\mathit{kind}, f.\mathit{bytes}, f.\mathit{lines}, f.\mathit{desc})$.
-/
theorem verdict_cases (f : Facts) :
    (∃ m, verdict f = .overBudget m ∧ budgetFail f.kind f.bytes f.lines f.desc = some m) ∨
    (∃ s n r, verdict f = .slop s ∧ budgetFail f.kind f.bytes f.lines f.desc = none ∧ f.hits = (s, n) :: r) ∨
    (verdict f = .ok ∧ budgetFail f.kind f.bytes f.lines f.desc = none ∧ f.hits = []) := by
  unfold verdict
  cases hb : budgetFail f.kind f.bytes f.lines f.desc with
  | some m => exact Or.inl ⟨m, rfl, rfl⟩
  | none =>
    cases hh : f.hits with
    | nil => exact Or.inr (Or.inr ⟨rfl, rfl, rfl⟩)
    | cons x r => exact Or.inr (Or.inl ⟨x.1, x.2, r, rfl, rfl, rfl⟩)

/-- Being over a cap is monotone in the value.

$$\forall c, v', v:\ v' \le v \land \mathrm{over}(c, v') \Rightarrow \mathrm{over}(c, v)$$
-/
theorem over_mono (c : Option Nat) {v' v : Nat} (h : v' ≤ v) (ho : over c v' = true) : over c v = true := by
  cases c with
  | none => simp [over] at ho
  | some c => simp [over] at ho ⊢; omega

/-- Over budget is monotone in size: if a file is over its kind's budget, a file of the same kind that is at least as
large in bytes, lines and description is over it too.

$$\forall k, b', l', d', b, l, d:\ b' \le b \land l' \le l \land d' \le d \land \mathrm{fail}(k, b', l', d') \ne \bot \Rightarrow \mathrm{fail}(k, b, l, d) \ne \bot$$
-/
theorem overBudget_mono (k : FileKind) {b' l' d' b l d : Nat} (hb : b' ≤ b) (hl : l' ≤ l) (hd : d' ≤ d)
    (h : (budgetFail k b' l' d').isSome = true) : (budgetFail k b l d).isSome = true := by
  unfold budgetFail at h ⊢
  by_cases h1 : over (budget k).bytes b' = true
  · simp [over_mono _ hb h1]
  · by_cases h2 : over (budget k).lines l' = true
    · simp only [over_mono _ hl h2]; split <;> rfl
    · by_cases h3 : over (budget k).desc d' = true
      · simp only [over_mono _ hd h3]; split <;> (try split) <;> rfl
      · simp [h1, h2, h3] at h

/-- A smaller file never gets a worse budget verdict: for two files with the same kind and the same hits, if the first
is no larger in bytes, lines and description, its verdict ranks no worse.

$$\forall f', f:\ f'.\mathit{kind} = f.\mathit{kind} \land f'.\mathit{hits} = f.\mathit{hits} \land f'.\mathit{bytes} \le f.\mathit{bytes} \land f'.\mathit{lines} \le f.\mathit{lines} \land f'.\mathit{desc} \le f.\mathit{desc} \Rightarrow \mathrm{rank}(\mathrm{verdict}(f')) \le \mathrm{rank}(\mathrm{verdict}(f))$$
-/
theorem rank_mono (f' f : Facts) (hk : f'.kind = f.kind) (hh : f'.hits = f.hits) (hb : f'.bytes ≤ f.bytes)
    (hl : f'.lines ≤ f.lines) (hd : f'.desc ≤ f.desc) : rank (verdict f') ≤ rank (verdict f) := by
  have hm := overBudget_mono f.kind hb hl hd
  unfold verdict
  rw [hk, hh]
  cases h' : budgetFail f.kind f'.bytes f'.lines f'.desc with
  | some m =>
    have := hm (by simp [h'])
    cases h : budgetFail f.kind f.bytes f.lines f.desc with
    | none => simp [h] at this
    | some _ => simp [rank]
  | none =>
    cases h : budgetFail f.kind f.bytes f.lines f.desc with
    | some _ => cases f.hits <;> simp [rank]
    | none => exact Nat.le_refl _

/-- The verdict of a file depends only on its facts: two files with equal facts get equal verdicts (no hidden input).

$$\forall p, b, L, p', b', L':\ \mathrm{facts}(p, b, L) = \mathrm{facts}(p', b', L') \Rightarrow \mathrm{verdict}(\mathrm{facts}(p, b, L)) = \mathrm{verdict}(\mathrm{facts}(p', b', L'))$$
-/
theorem verdict_of_facts (p p' : String) (b b' : Nat) (L L' : List String) (h : factsOf p b L = factsOf p' b' L') :
    verdict (factsOf p b L) = verdict (factsOf p' b' L') := by rw [h]

/-! ## Examples -/

#guard kindOf "CLAUDE.md" == .claudeMd
#guard kindOf ".claude/agents/lean-prover.md" == .agent
#guard kindOf ".claude/skills/no-slop/SKILL.md" == .skill
#guard kindOf "docs/team/handoffs/context-slop.md" == .handoff
#guard kindOf "docs/team/tools/land.md" == .teamDoc
#guard kindOf "docs/team/token-policy.md" == .teamDoc
#guard kindOf "docs/team/handoffs/old/x.md" == .other
#guard kindOf "lean/Fw/Lint/Context.lean" == .other
#guard kindOf "" == .other
#guard isSha "5b3d632".toList && !isSha "1234567".toList && !isSha "deadbeef".toList && !isSha "5b3d63".toList
#guard hasDate "(user decision 2026-10-17)".toList && !hasDate "2026-10".toList
#guard historyHeading "## Shadow review (task land-dry)".toList
#guard historyHeading "### Output (obs-next-glue)  ".toList
#guard !historyHeading "## Output (JSON)".toList && !historyHeading "text (obs-next-glue)".toList
#guard aiTell "A pivotal step".toList && aiTell "in Order To build".toList && aiTell "a — b".toList
#guard !aiTell "use the order to sort".toList
#guard descOf ["---", "name: x", "description: abc", "---", "description: zzzzzz"] == 3
#guard descOf ["name: x", "description: abc"] == 0
#guard verdict (factsOf "docs/team/handoffs/a.md" 10 ((List.range 31).map toString)) == .overBudget .lines
#guard verdict (factsOf "docs/team/handoffs/a.md" 10 ((List.range 30).map toString)) == .ok
#guard verdict (factsOf ".claude/agents/a.md" 100 ["---", "name: a", "---", "Pinned at 5b3d632."]) == .slop .sha
#guard verdict (factsOf "CLAUDE.md" 100 ["Rule (user decision 2026-10-17)."]) == .slop .datedNote
#guard verdict (factsOf "CLAUDE.md" 5001 ["Rule (user decision 2026-10-17)."]) == .overBudget .bytes
#guard verdict (factsOf "research/notes/x.md" 99999 ["delve 5b3d632 2026-10-17"]) == .ok
#guard verdict (factsOf "docs/team/handoffs/a.md" 10 ["at 5b3d632 on 2026-10-17"]) == .ok
#guard verdict (factsOf ".claude/skills/a/SKILL.md" 10 ["---", "description: " ++ "".pushn 'x' 301, "---"]) ==
  .overBudget .desc

end Fw.Lint.Context

/-! ## Wire: `lint.context` -/
namespace Fw.Wire.Lint
open Lean Fw.Lint.Context Fw.Wire.Ops

/-- Kind wire names. -/
def kindName : FileKind → String
  | .claudeMd => "claudeMd" | .agent => "agent" | .skill => "skill" | .handoff => "handoff" | .teamDoc => "teamDoc"
  | .other => "other"

/-- Marker wire names. -/
def slopName : Slop → String
  | .sha => "sha" | .datedNote => "datedNote" | .historyHeading => "historyHeading" | .aiTell => "aiTell"

/-- Measure wire names. -/
def measureName : Measure → String
  | .bytes => "bytes" | .lines => "lines" | .desc => "desc"

/-- The value and cap of a measure for some facts. -/
def measured (f : Facts) : Measure → Nat × Option Nat
  | .bytes => (f.bytes, (budget f.kind).bytes)
  | .lines => (f.lines, (budget f.kind).lines)
  | .desc => (f.desc, (budget f.kind).desc)

/-- The reply row of one file. -/
def row (path : String) (f : Facts) : Json :=
  let base : List (String × Json) := [("path", .str path), ("kind", .str (kindName f.kind)),
    ("bytes", toJson f.bytes), ("lines", toJson f.lines), ("hits", toJson f.hits.length)]
  Json.mkObj <| base ++ match verdict f with
    | .ok => [("verdict", .str "ok")]
    | .overBudget m =>
      let (v, c) := measured f m
      [("verdict", .str "overBudget"), ("measure", .str (measureName m)), ("value", toJson v),
        ("budget", match c with | some c => toJson c | none => .null)]
    | .slop s =>
      [("verdict", .str "slop"), ("slop", .str (slopName s)), ("line", toJson ((f.hits.head?.map (·.2)).getD 0))]

/-- `lint.context`: `files` [{path, bytes, lines [string]}] → `files` [{path, kind, bytes, lines, hits, verdict,
measure/value/budget (overBudget) or slop/line (slop)}], `counts` {ok, overBudget, slop}. -/
def opContext (req : Json) : Except String Reply := do
  let files ← (← arr req "files").toList.mapM fun j => do
    let p ← str j "path"
    let b ← nat j "bytes"
    let ls ← (← arr j "lines").toList.mapM (asStr "lines")
    pure (p, factsOf p b ls)
  let vs := files.map fun (_, f) => verdict f
  let count (r : Nat) : Json := toJson (vs.filter (rank · == r)).length
  pure [("files", .arr (files.toArray.map fun (p, f) => row p f)),
    ("counts", Json.mkObj [("ok", count 0), ("slop", count 1), ("overBudget", count 2)])]

/-- The ops of this module. -/
def ops : List String := ["lint.context"]

/-- Dispatch (`none` when the op is not one of these). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "lint.context" => some (opContext req)
  | _ => none

#guard ops.all fun o => (handle o (Json.mkObj [("files", .arr #[])])).isSome

end Fw.Wire.Lint
