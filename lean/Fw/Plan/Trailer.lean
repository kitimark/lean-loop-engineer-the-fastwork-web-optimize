/-!
# `Task: <id>` trailers on main: which commit marks which task done (`plan.trailers`)

The git reconciler reads the first-parent history of `main` (newest first, as `git log` prints it)
and asks this rule which `task.done` facts it holds (task `lean-console-gaps`; before, a TS stand-in in
`apps/console-api/src/reconcile/git.ts` and `reconciler.ts`).

* A **trailer line** is a line of a commit message of the form `Task:`, then spaces or tabs, then an
  id of ASCII letters, digits, `.`, `_` or `-`, then only spaces or tabs to the end of the line.
  Lines end at `\n`, `\r`, U+2028 or U+2029 (the line ends of a JavaScript `/^…$/m` match).
* Every trailer gets a **verdict**, walking the commits oldest first: `unknown` (no task has that id),
  `alreadyDone` (the plan has it done), `duplicate` (an older commit already marked it), else `done`.
* The facts are the `done` verdicts: the task and the sha of the **oldest** first-parent commit that
  names it (`mem_facts_iff`), only for known undone tasks, each task at most once (`facts_nodup`).
-/
namespace Fw.Plan.Trailer

/-- A blank: space or tab.

$$\operatorname{blank}(c) \iff c \in \{\texttt{' '}, \texttt{'\textbackslash t'}\}$$

The characters allowed around a trailer id.
-/
def isBlank (c : Char) : Bool := c == ' ' || c == '\t'

/-- An id character: an ASCII letter or digit, `.`, `_` or `-`.

$$\operatorname{idChar}(c) \iff c \in \{\texttt{A}..\texttt{Z}, \texttt{a}..\texttt{z}, \texttt{0}..\texttt{9}, \texttt{.}, \texttt{\_}, \texttt{-}\}$$

The characters a task id is made of.
-/
def isIdChar (c : Char) : Bool := c.isAlphanum || c == '.' || c == '_' || c == '-'

/-- A line end: `\n`, `\r`, U+2028 or U+2029.

$$\operatorname{eol}(c) \iff c \in \{\mathrm{U{+}000A}, \mathrm{U{+}000D}, \mathrm{U{+}2028}, \mathrm{U{+}2029}\}$$

The characters that end a line in a JavaScript multiline match.
-/
def isEol (c : Char) : Bool := c == '\n' || c == '\r' || c == '\u2028' || c == '\u2029'

/-- The id a line names, if it is a trailer line: the line is `Task:` $\cdot\, b_1 \cdot x \cdot b_2$
with $b_1, b_2$ blank runs and $x$ a non-empty id.

$$\operatorname{trailer}(w) = \begin{cases} x & w = \texttt{Task:} \cdot b_1 \cdot x \cdot b_2,\ b_1, b_2 \in \{\texttt{' '}, \texttt{'\textbackslash t'}\}^{*},\ x \in \{c : \operatorname{isIdChar}(c)\}^{+} \\ \bot & \text{otherwise} \end{cases}$$

A line is a trailer when it says `Task:` and one id, with only spaces or tabs around it.
-/
def trailerOf (w : List Char) : Option String :=
  match w with
  | 'T' :: 'a' :: 's' :: 'k' :: ':' :: rest =>
    let r := rest.dropWhile isBlank
    let x := r.takeWhile isIdChar
    if !x.isEmpty && (r.dropWhile isIdChar).all isBlank then some (String.ofList x) else none
  | _ => none

/-- The trailer ids of a commit message, in line order.

$$\operatorname{trailers}(B) = [\, \operatorname{trailer}(w) \mid w \in \operatorname{lines}(B),\ \operatorname{trailer}(w) \ne \bot \,],\quad \text{where } \operatorname{lines}(B) \text{ splits } B \text{ at every line end } (\operatorname{eol})$$

Every `Task:` line of a message, in order.
-/
def trailers (body : String) : List String :=
  (body.toList.splitOnP isEol).filterMap trailerOf

/-- A commit of the first-parent history: its sha and its message.

$$c = (\mathit{sha}, \mathit{body})$$

What the reconciler reads from `git log --first-parent`.
-/
structure Commit where
  sha  : String
  body : String
deriving Repr, DecidableEq

/-- What a trailer does.

$$\mathrm{Verdict} = \{\mathrm{done}, \mathrm{unknown}, \mathrm{alreadyDone}, \mathrm{duplicate}\}$$

A trailer marks a task done, or is ignored with a reason.
-/
inductive Verdict where
  | done | unknown | alreadyDone | duplicate
deriving Repr, DecidableEq

/-- The wire name of a verdict.

$$\operatorname{name}(v) = \text{the constructor name of } v, \text{ e.g. } \operatorname{name}(\mathrm{alreadyDone}) = \texttt{"alreadyDone"}$$

How a verdict is spelled in JSON.
-/
def Verdict.name : Verdict → String
  | .done => "done" | .unknown => "unknown" | .alreadyDone => "alreadyDone" | .duplicate => "duplicate"

/-- The (task, sha) pairs of a newest-first history, oldest commit first (inside one commit, in
line order).

$$\operatorname{pairs}(C) = [\, (x, c.\mathit{sha}) \mid c \in \operatorname{rev}(C),\ x \in \operatorname{trailers}(c.\mathit{body}) \,]$$

Every trailer with its commit, from the oldest commit to the newest.
-/
def pairs (cs : List Commit) : List (String × String) :=
  cs.reverse.flatMap fun c => (trailers c.body).map fun x => (x, c.sha)

/-- The verdict of one trailer for task $x$, given the plan's tasks $P$ (id, done) and the tasks
already marked by older trailers $S$ (the first row of $P$ with id $x$ counts).

$$\operatorname{verdict}(P, S, x) = \begin{cases} \mathrm{unknown} & \operatorname{lookup}(x, P) = \bot \\ \mathrm{alreadyDone} & \operatorname{lookup}(x, P) = \mathrm{true} \\ \mathrm{duplicate} & \operatorname{lookup}(x, P) = \mathrm{false} \land x \in S \\ \mathrm{done} & \operatorname{lookup}(x, P) = \mathrm{false} \land x \notin S \end{cases}$$

A trailer counts only for a known, undone task that no older trailer has marked.
-/
def verdict (tasks : List (String × Bool)) (seen : List String) (x : String) : Verdict :=
  match tasks.lookup x with
  | none => .unknown
  | some true => .alreadyDone
  | some false => if x ∈ seen then .duplicate else .done

/-- The verdicts of a list of (task, sha) pairs, walking it in order and remembering the tasks
marked so far.

$$\operatorname{judge}(P, S, [\,]) = [\,], \qquad \operatorname{judge}(P, S, (x, s) :: L) = (x, s, v) :: \operatorname{judge}(P, S', L), \quad v = \operatorname{verdict}(P, S, x),\ S' = \begin{cases} \{x\} \cup S & v = \mathrm{done} \\ S & \text{otherwise} \end{cases}$$

Each trailer is judged after all older ones.
-/
def judge (tasks : List (String × Bool)) : List String → List (String × String) → List (String × String × Verdict)
  | _, [] => []
  | seen, (x, s) :: ps =>
    let v := verdict tasks seen x
    (x, s, v) :: judge tasks (if v = .done then x :: seen else seen) ps

/-- Every trailer of a newest-first history with its verdict, oldest first.

$$\operatorname{verdicts}(P, C) = \operatorname{judge}(P, \emptyset, \operatorname{pairs}(C))$$

The verdict of each `Task:` line on main.
-/
def verdicts (tasks : List (String × Bool)) (cs : List Commit) : List (String × String × Verdict) :=
  judge tasks [] (pairs cs)

/-- The `task.done` facts: the trailers judged `done`, as (task, evidence sha), oldest first.

$$\operatorname{facts}(P, C) = [\, (x, s) \mid (x, s, \mathrm{done}) \in \operatorname{verdicts}(P, C) \,]$$

The tasks that main's history marks done, each with the commit that did it.
-/
def facts (tasks : List (String × Bool)) (cs : List Commit) : List (String × String) :=
  (verdicts tasks cs).filterMap fun (x, s, v) => if v = .done then some (x, s) else none

/-- The sha of the first pair for task $x$ (the oldest commit that names it).

$$\operatorname{first}(L, x) = \begin{cases} s & (x, s) \text{ is the first pair of } L \text{ with task } x \\ \bot & \text{no pair of } L \text{ has task } x \end{cases}$$

Where a task is first named.
-/
def firstSha (ps : List (String × String)) (x : String) : Option String :=
  (ps.find? (·.1 == x)).map (·.2)

/-! ## Proofs -/

/-- The `done` verdicts of `judge`: exactly the first pair of each known undone task not in $S$.

$$\forall P, S, L, x, s:\quad (x, s, \mathrm{done}) \in \operatorname{judge}(P, S, L) \iff \operatorname{lookup}(x, P) = \mathrm{false} \land x \notin S \land \operatorname{first}(L, x) = s$$

The walk marks a task at its first pair, and only if it is known, undone and not yet marked.
-/
theorem mem_judge_done (tasks : List (String × Bool)) (seen : List String)
    (ps : List (String × String)) (x s : String) :
    (x, s, Verdict.done) ∈ judge tasks seen ps ↔
      tasks.lookup x = some false ∧ x ∉ seen ∧ firstSha ps x = some s := by
  induction ps generalizing seen with
  | nil => simp [judge, firstSha]
  | cons p ps ih =>
    obtain ⟨y, t⟩ := p
    simp only [judge, List.mem_cons, Prod.mk.injEq, ih, firstSha, List.find?_cons]
    by_cases hxy : y = x
    · subst hxy
      simp only [beq_self_eq_true, Option.map_some, Option.some.injEq, true_and]
      unfold verdict
      cases hl : tasks.lookup y with
      | none => simp
      | some b =>
        cases b
        · by_cases hs : y ∈ seen
          · simp [hs]
          · simp [hs, eq_comm]
        · simp
    · have hb : (y == x) = false := by simpa using hxy
      simp only [hb, firstSha] at *
      have hne : ¬ (x = y) := fun h => hxy h.symm
      simp only [hne, false_and, false_or]
      constructor
      · rintro ⟨h1, h2, h3⟩
        refine ⟨h1, fun h => h2 ?_, h3⟩
        split <;> simp_all
      · rintro ⟨h1, h2, h3⟩
        refine ⟨h1, ?_, h3⟩
        split
        · simp [h2, hne]
        · exact h2

/-- **The facts are the oldest trailer of each known undone task.**

$$\forall P, C, x, s:\quad (x, s) \in \operatorname{facts}(P, C) \iff \operatorname{lookup}(x, P) = \mathrm{false} \land \operatorname{first}(\operatorname{pairs}(C), x) = s$$

A task is marked done by main exactly when the plan knows it, has it undone, and some commit names it; the evidence is the oldest such commit.
-/
theorem mem_facts_iff (tasks : List (String × Bool)) (cs : List Commit) (x s : String) :
    (x, s) ∈ facts tasks cs ↔ tasks.lookup x = some false ∧ firstSha (pairs cs) x = some s := by
  have h := mem_judge_done tasks [] (pairs cs) x s
  simp only [List.not_mem_nil, not_false_eq_true, true_and] at h
  rw [← h]
  simp only [facts, verdicts, List.mem_filterMap]
  constructor
  · rintro ⟨⟨y, t, v⟩, hm, he⟩
    by_cases hv : v = .done
    · subst hv; simp only [↓reduceIte, Option.some.injEq, Prod.mk.injEq] at he
      obtain ⟨rfl, rfl⟩ := he; exact hm
    · simp [hv] at he
  · intro hm
    exact ⟨(x, s, .done), hm, by simp⟩

/-- Done verdicts never repeat a task of $S$ nor each other.

$$\forall P, S, L:\quad [\, x \mid (x, s, \mathrm{done}) \in \operatorname{judge}(P, S, L) \,] \text{ has pairwise distinct elements, none in } S$$

The walk marks each task at most once.
-/
theorem judge_done_nodup (tasks : List (String × Bool)) (seen : List String) (ps : List (String × String)) :
    (((judge tasks seen ps).filterMap fun (x, s, v) => if v = .done then some (x, s) else none).map
      Prod.fst).Nodup ∧
    ∀ q ∈ (judge tasks seen ps).filterMap (fun (x, s, v) => if v = .done then some (x, s) else none),
      q.1 ∉ seen := by
  induction ps generalizing seen with
  | nil => simp [judge]
  | cons p ps ih =>
    obtain ⟨y, t⟩ := p
    simp only [judge]
    by_cases hv : verdict tasks seen y = .done
    · obtain ⟨ih1, ih2⟩ := ih (y :: seen)
      have hys : y ∉ seen := by
        unfold verdict at hv
        split at hv
        · cases hv
        · cases hv
        · split at hv
          · cases hv
          · assumption
      simp only [hv, ↓reduceIte, List.filterMap_cons, List.map_cons]
      refine ⟨List.nodup_cons.mpr ⟨?_, ih1⟩, ?_⟩
      · intro hm
        obtain ⟨q, hq, hq1⟩ := List.mem_map.mp hm
        exact ih2 q hq (by rw [hq1]; exact List.mem_cons_self ..)
      · intro q hq
        rcases List.mem_cons.mp hq with rfl | hq
        · exact hys
        · exact fun h => ih2 q hq (List.mem_cons_of_mem _ h)
    · obtain ⟨ih1, ih2⟩ := ih seen
      simp only [hv, ↓reduceIte, List.filterMap_cons]
      exact ⟨ih1, ih2⟩

/-- **Each task is marked done at most once.**

$$\forall P, C:\quad [\, x \mid (x, s) \in \operatorname{facts}(P, C) \,] \text{ has pairwise distinct elements}$$

No task gets two `task.done` facts from main's trailers.
-/
theorem facts_nodup (tasks : List (String × Bool)) (cs : List Commit) :
    ((facts tasks cs).map Prod.fst).Nodup :=
  (judge_done_nodup tasks [] (pairs cs)).1

/-! ## Examples -/

#guard trailers "fix\n\nTask: lean-plan\n" == ["lean-plan"]
#guard trailers "Task:\tx.y_z-1 \t\r\nTask: a b\nTask:\nTask: ok" == ["x.y_z-1", "ok"]
#guard trailers " Task: x\ntask: y\nTask: é" == []
#guard trailers "a\u2028Task: z" == ["z"]
#guard facts [("a", false), ("b", true)]
    [⟨"s3", "Task: a\nTask: c"⟩, ⟨"s2", "Task: b"⟩, ⟨"s1", "Task: a"⟩] == [("a", "s1")]
#guard verdicts [("a", false), ("b", true)]
    [⟨"s3", "Task: a\nTask: c"⟩, ⟨"s2", "Task: b"⟩, ⟨"s1", "Task: a"⟩] ==
  [("a", "s1", .done), ("b", "s2", .alreadyDone), ("a", "s3", .duplicate), ("c", "s3", .unknown)]
#guard facts [] [] == []

end Fw.Plan.Trailer
