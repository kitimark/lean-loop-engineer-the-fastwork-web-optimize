/-!
# Spawn guard (PLAN §8.1, §8.2, §8.3 `PreToolUse` matcher `Agent`)

A pure decision `decide : Input → Decision` for one `Agent` tool call: the alive agents (with
their roles and kinds), the roles table, the caps, the recent spawns and the request. The hook
(`spawn-guard.mjs`) only moves JSON; every rule is here.

The kind a call produces follows PLAN §8.1 (CONFIRMED there): `isolation: "worktree"` on the call
makes a worktree subagent; a *named* call from the lead (depth 0) without isolation becomes a
teammate in the main checkout, even if the role file asks for a worktree (the trap of I-272);
anything else is a plain subagent (teammates cannot nest).

Proved: an accepted spawn never exceeds a cap (`accepted_within`, `accepted_rate`), never reuses
a name (`accepted_names_nodup`), the worktree trap is denied (`trap_worktree_role_as_teammate`),
a teammate role asked with worktree isolation is denied (`teammate_with_isolation_denied`), and
an `ask` model (fable) is never plainly allowed (`ask_never_allow`, `ask_needs_approval`).
-/
namespace Fw.Ops.SpawnGuard

/-- What a spawn runs as: an in-process teammate, a plain subagent, or a named worktree subagent.

$$\mathrm{Kind} = \{\mathrm{teammate},\ \mathrm{subagent},\ \mathrm{worktree}\}$$
-/
inductive Kind where
  | teammate | subagent | worktree
deriving DecidableEq, Repr

/-- A role of the roster (PLAN §8.2): its name, what it runs as, and whether it writes files.

$$\mathrm{Role} = \mathrm{String} \times \mathrm{Kind} \times \mathbb{B}, \qquad \rho = (\rho.\mathit{name},\ \rho.\mathit{runsAs},\ \rho.\mathit{edits})$$
-/
structure Role where
  name   : String
  runsAs : Kind
  edits  : Bool
deriving DecidableEq, Repr

/-- An alive agent: its name, role, kind and the agent that spawned it.

$$\mathrm{Agent} = \mathrm{String} \times \mathrm{String} \times \mathrm{Kind} \times \mathrm{String}, \qquad a = (a.\mathit{name},\ a.\mathit{role},\ a.\mathit{kind},\ a.\mathit{spawner})$$
-/
structure Agent where
  name    : String
  role    : String
  kind    : Kind
  spawner : String
deriving DecidableEq, Repr

/-- The caps (PLAN §8.2, §8.3): at most 5 teammates, 8 worktree subagents, 10 subagents in all
(worktree ones included), per-role caps (3 lean-provers), at most 10 spawns per 600 s per
spawner, the `ask` model patterns, and whether an unnamed read-only subagent is allowed.

$$\mathrm{Caps} = (T, W, S, R, n, \Delta, M, u), \qquad \text{defaults } T = 5,\ W = 8,\ S = 10,\ R = [(\texttt{lean-prover}, 3)],\ n = 10,\ \Delta = 600,\ M = [\texttt{fable}],\ u = \mathrm{false}$$
-/
structure Caps where
  teammates       : Nat := 5
  worktrees       : Nat := 8
  subagents       : Nat := 10
  perRole         : List (String × Nat) := [("lean-prover", 3)]
  spawnsPerWindow : Nat := 10
  windowSec       : Nat := 600
  askModels       : List String := ["fable"]
  unnamedReadOnly : Bool := false
deriving Repr

/-- One `Agent` call: the name (`""` when unnamed), the role (`subagent_type`), whether the call
carries `isolation: "worktree"`, the model (`""` = the role's), the spawner and the spawner's depth
(0 = the lead).

$$\mathrm{Req} = (\mathit{name}, \mathit{role}, \mathit{iso}, \mathit{model}, \mathit{spawner}, d) \in \mathrm{String}^2 \times \mathbb{B} \times \mathrm{String}^2 \times \mathbb{N}$$
-/
structure Req where
  name      : String
  role      : String
  isolation : Bool
  model     : String
  spawner   : String
  depth     : Nat
deriving DecidableEq, Repr

/-- The guard's input: alive agents, roles table, caps, earlier accepted spawns `(spawner, time s)`,
the current time in seconds and the request.

$$\mathrm{Input} = (A, P, C, H, \mathit{now}, q)$$
-/
structure Input where
  alive  : List Agent
  roles  : List Role
  caps   : Caps
  recent : List (String × Nat)
  now    : Nat
  req    : Req

/-- Why a spawn is denied.

$$\mathrm{Reason} = \mathrm{unnamed} \mid \mathrm{nameInUse} \mid \mathrm{unknownRole} \mid \mathrm{kindMismatch}(k_{want}, k_{got}) \mid \mathrm{nestedEditor} \mid \mathrm{rateLimited} \mid \mathrm{capTeammates} \mid \mathrm{capWorktrees} \mid \mathrm{capSubagents} \mid \mathrm{capRole}(r)$$
-/
inductive Reason where
  | unnamed | nameInUse | unknownRole | kindMismatch (want got : Kind) | nestedEditor | rateLimited
  | capTeammates | capWorktrees | capSubagents | capRole (role : String)
deriving DecidableEq, Repr

/-- The guard's answer.

$$\mathrm{Decision} = \mathrm{allow} \mid \mathrm{needsApproval} \mid \mathrm{deny}(r),\ r \in \mathrm{Reason}$$
-/
inductive Decision where
  | allow | needsApproval | deny (r : Reason)
deriving DecidableEq, Repr

/-- A decision lets the spawn go ahead (directly, or after your approval).

$$\mathrm{accepted}(\mathrm{allow}) = \mathrm{accepted}(\mathrm{needsApproval}) = \mathrm{true}, \qquad \mathrm{accepted}(\mathrm{deny}(r)) = \mathrm{false}$$
-/
def Decision.accepted : Decision → Bool
  | .allow | .needsApproval => true
  | .deny _ => false

/-- The kind a call produces (PLAN §8.1): worktree isolation on the call gives a worktree subagent;
otherwise a named call from the lead gives a teammate; otherwise a plain subagent.

$$\kappa(q) = \begin{cases} \mathrm{worktree} & q.\mathit{iso} \\ \mathrm{teammate} & \lnot q.\mathit{iso},\ q.d = 0,\ q.\mathit{name} \ne \texttt{""} \\ \mathrm{subagent} & \text{otherwise} \end{cases}$$
-/
def effKind (q : Req) : Kind :=
  if q.isolation then .worktree else if q.depth = 0 ∧ q.name ≠ "" then .teammate else .subagent

/-- The agent a spawn would add.

$$\nu(q) = (q.\mathit{name},\ q.\mathit{role},\ \kappa(q),\ q.\mathit{spawner})$$
-/
def newAgent (q : Req) : Agent := ⟨q.name, q.role, effKind q, q.spawner⟩

/-- Number of agents of kind `k` (list entries, repeats counted).

$$\#_k(A) = \big|[\, a \in A \mid a.\mathit{kind} = k \,]\big|$$
-/
def countKind (k : Kind) (as : List Agent) : Nat := (as.filter (·.kind == k)).length

/-- Number of subagents of any kind (plain or worktree), i.e. all non-teammates (list entries,
repeats counted).

$$\#_{sub}(A) = \big|[\, a \in A \mid a.\mathit{kind} \ne \mathrm{teammate} \,]\big|$$
-/
def countSub (as : List Agent) : Nat := (as.filter (·.kind != .teammate)).length

/-- Number of agents with role `r` (list entries, repeats counted).

$$\#^{r}(A) = \big|[\, a \in A \mid a.\mathit{role} = r \,]\big|$$
-/
def countRole (r : String) (as : List Agent) : Nat := (as.filter (·.role == r)).length

/-- A set of agents respects the caps: teammates, worktree subagents, all subagents and every
per-role cap.

$$\mathrm{Within}(C, A) \iff \#_{\mathrm{teammate}}(A) \le T \land \#_{\mathrm{worktree}}(A) \le W \land \#_{sub}(A) \le S \land \forall (r, c) \in R:\ \#^{r}(A) \le c$$
-/
def Within (c : Caps) (as : List Agent) : Prop :=
  countKind .teammate as ≤ c.teammates ∧ countKind .worktree as ≤ c.worktrees ∧
  countSub as ≤ c.subagents ∧ ∀ p ∈ c.perRole, countRole p.1 as ≤ p.2

/-- The first per-role cap the agents exceed, if any.

$$\mathrm{overRole}(R, A) = \text{the first } r \text{ with } (r, c) \in R,\ \#^{r}(A) > c, \text{ else } \bot$$
-/
def overRole (rs : List (String × Nat)) (as : List Agent) : Option String :=
  (rs.find? fun p => Decidable.decide (countRole p.1 as > p.2)).map (·.1)

/-- Earlier spawns by the same spawner inside the window ending now (list entries, so equal entries
each count).

$$\mathrm{recent}(i) = \big|[\, (s, t) \in H \mid s = q.\mathit{spawner} \land \mathit{now} < t + \Delta \,]\big|$$
-/
def recentCount (i : Input) : Nat :=
  (i.recent.filter fun p => p.1 == i.req.spawner && Decidable.decide (i.now < p.2 + i.caps.windowSec)).length

/-- Lower-case substring test: `p` occurs in `s`, ignoring ASCII case.

$$\mathrm{hasInfix}(p, s) \iff \exists u, v:\ \mathrm{lower}(s) = u \cdot \mathrm{lower}(p) \cdot v$$
-/
def hasInfix (p s : String) : Bool :=
  let pl := p.toLower.toList
  let sl := s.toLower.toList
  (List.range (sl.length + 1)).any fun k => (sl.drop k).take pl.length == pl

/-- The request's model is an `ask` model: some non-empty pattern of `M` occurs in it.

$$\mathrm{ask}(C, q) \iff \exists m \in M:\ m \ne \texttt{""} \land \mathrm{hasInfix}(m, q.\mathit{model})$$
-/
def isAsk (c : Caps) (q : Req) : Bool := c.askModels.any fun m => m != "" && hasInfix m q.model

/-- The cap checks on the agents after the spawn, in order: teammates, worktree subagents, all
subagents, per-role caps.

$$\mathrm{capFail}(C, A') = \begin{cases} \mathrm{capTeammates} & \#_{\mathrm{teammate}}(A') > T \\ \mathrm{capWorktrees} & \#_{\mathrm{teammate}}(A') \le T \land \#_{\mathrm{worktree}}(A') > W \\ \mathrm{capSubagents} & \#_{\mathrm{teammate}}(A') \le T \land \#_{\mathrm{worktree}}(A') \le W \land \#_{sub}(A') > S \\ \mathrm{capRole}(r) & \#_{\mathrm{teammate}}(A') \le T \land \#_{\mathrm{worktree}}(A') \le W \land \#_{sub}(A') \le S \land \mathrm{overRole}(R, A') = r \\ \bot & \#_{\mathrm{teammate}}(A') \le T \land \#_{\mathrm{worktree}}(A') \le W \land \#_{sub}(A') \le S \land \mathrm{overRole}(R, A') = \bot \end{cases}$$
-/
def capFail (c : Caps) (after : List Agent) : Option Reason :=
  if countKind .teammate after > c.teammates then some .capTeammates
  else if countKind .worktree after > c.worktrees then some .capWorktrees
  else if countSub after > c.subagents then some .capSubagents
  else (overRole c.perRole after).map .capRole

/-- The checks once the role $\rho$ is known, in order: kind, nesting, rate, caps.

$$\mathrm{roleCheck}(i, \rho) = \begin{cases} \mathrm{kindMismatch}(\rho.\mathit{runsAs}, \kappa(q)) & \kappa(q) \ne \rho.\mathit{runsAs} \\ \mathrm{nestedEditor} & \kappa(q) = \rho.\mathit{runsAs} \land q.d \ge 1 \land \rho.\mathit{edits} \\ \mathrm{rateLimited} & \kappa(q) = \rho.\mathit{runsAs} \land \lnot(q.d \ge 1 \land \rho.\mathit{edits}) \land \mathrm{recent}(i) \ge n \\ \mathrm{capFail}(C, \nu(q) :: A) & \kappa(q) = \rho.\mathit{runsAs} \land \lnot(q.d \ge 1 \land \rho.\mathit{edits}) \land \mathrm{recent}(i) < n \end{cases}$$
-/
def roleCheck (i : Input) (r : Role) : Option Reason :=
  if effKind i.req ≠ r.runsAs then some (.kindMismatch r.runsAs (effKind i.req))
  else if i.req.depth ≥ 1 ∧ r.edits = true then some .nestedEditor
  else if recentCount i ≥ i.caps.spawnsPerWindow then some .rateLimited
  else capFail i.caps (newAgent i.req :: i.alive)

/-- The role a request names: the first row of the roles table with that name.

$$\mathrm{role}(i) = \text{the first } \rho \in P \text{ with } \rho.\mathit{name} = q.\mathit{role}, \text{ else } \bot$$
-/
def roleOf (i : Input) : Option Role := i.roles.find? (·.name == i.req.role)

/-- An unnamed call is excused: the caps allow unnamed read-only subagents and the role is one.

$$\mathrm{excused}(i) \iff u \land \exists \rho:\ \mathrm{role}(i) = \rho \land \rho.\mathit{runsAs} = \mathrm{subagent} \land \lnot \rho.\mathit{edits}$$
-/
def excused (i : Input) : Bool :=
  i.caps.unnamedReadOnly && match roleOf i with
    | some r => r.runsAs == .subagent && !r.edits
    | none => false

/-- The name is taken: some alive agent has the requested (non-empty) name.

$$\mathrm{taken}(i) \iff q.\mathit{name} \ne \texttt{""} \land \exists a \in A:\ a.\mathit{name} = q.\mathit{name}$$
-/
def taken (i : Input) : Bool := i.req.name != "" && i.alive.any (·.name == i.req.name)

/-- The first failing check, in order: name, name in use, role, then `roleCheck`.

$$\mathrm{check}(i) = \begin{cases} \mathrm{unnamed} & U \\ \mathrm{nameInUse} & \lnot U \land \mathrm{taken}(i) \\ \mathrm{unknownRole} & \lnot U \land \lnot\mathrm{taken}(i) \land \mathrm{role}(i) = \bot \\ \mathrm{roleCheck}(i, \rho) & \lnot U \land \lnot\mathrm{taken}(i) \land \mathrm{role}(i) = \rho \end{cases}, \qquad U \iff q.\mathit{name} = \texttt{""} \land \lnot\mathrm{excused}(i)$$
-/
def check (i : Input) : Option Reason :=
  if i.req.name = "" ∧ excused i = false then some .unnamed
  else if taken i then some .nameInUse
  else match roleOf i with
    | none => some .unknownRole
    | some r => roleCheck i r

/-- The guard: deny with the first failing check; otherwise an `ask` model needs your approval;
otherwise allow.

$$\mathrm{decide}(i) = \begin{cases} \mathrm{deny}(r) & \mathrm{check}(i) = r \\ \mathrm{needsApproval} & \mathrm{check}(i) = \bot \land \mathrm{ask}(C, q) \\ \mathrm{allow} & \mathrm{check}(i) = \bot \land \lnot \mathrm{ask}(C, q) \end{cases}$$
-/
def decide (i : Input) : Decision :=
  match check i with
  | some r => .deny r
  | none => if isAsk i.caps i.req then .needsApproval else .allow

/-! ## Proofs -/

/-- A decision is accepted exactly when the checks all pass.

$$\forall i:\quad \mathrm{accepted}(\mathrm{decide}(i)) \iff \mathrm{check}(i) = \bot$$
-/
theorem accepted_iff (i : Input) : (decide i).accepted = true ↔ check i = none := by
  unfold decide
  cases h : check i with
  | some r => simp [Decision.accepted]
  | none => by_cases ha : isAsk i.caps i.req <;> simp [ha, Decision.accepted]

/-- `overRole` finds nothing exactly when every per-role cap holds.

$$\forall R, A:\quad \mathrm{overRole}(R, A) = \bot \iff \forall (r, c) \in R:\ \#^{r}(A) \le c$$
-/
theorem overRole_none {rs : List (String × Nat)} {as : List Agent} :
    overRole rs as = none ↔ ∀ p ∈ rs, countRole p.1 as ≤ p.2 := by
  simp [overRole, List.find?_eq_none]

/-- No cap fails exactly when the agents are within the caps.

$$\forall C, A':\quad \mathrm{capFail}(C, A') = \bot \iff \mathrm{Within}(C, A')$$
-/
theorem capFail_none (c : Caps) (as : List Agent) : capFail c as = none ↔ Within c as := by
  unfold capFail Within
  rw [← overRole_none]
  split
  · simp only [reduceCtorEq, false_iff]; omega
  split
  · simp only [reduceCtorEq, false_iff]; omega
  split
  · simp only [reduceCtorEq, false_iff]; omega
  · cases overRole c.perRole as <;> simp <;> omega

/-- Passing all checks means: a name (or an excused unnamed call), a free name, a known role
$\rho$ of the right kind, no nested editor, room in the rate window, and the caps hold after the
spawn.

$$\forall i:\quad \mathrm{check}(i) = \bot \iff \big(q.\mathit{name} = \texttt{""} \Rightarrow \mathrm{excused}(i)\big) \land \lnot\mathrm{taken}(i) \land \exists \rho:\ \mathrm{role}(i) = \rho \land \kappa(q) = \rho.\mathit{runsAs} \land \lnot(q.d \ge 1 \land \rho.\mathit{edits}) \land \mathrm{recent}(i) < n \land \mathrm{Within}(C, \nu(q) :: A)$$
-/
theorem check_none (i : Input) : check i = none ↔
    (i.req.name = "" → excused i = true) ∧ taken i = false ∧
    ∃ r, roleOf i = some r ∧ effKind i.req = r.runsAs ∧ ¬(i.req.depth ≥ 1 ∧ r.edits = true) ∧
      recentCount i < i.caps.spawnsPerWindow ∧ Within i.caps (newAgent i.req :: i.alive) := by
  unfold check
  by_cases h1 : i.req.name = "" ∧ excused i = false
  · rw [ite_eq_left h1]
    simp only [reduceCtorEq, false_iff, not_and]
    intro h
    have := h h1.1
    rw [h1.2] at this
    cases this
  · rw [ite_eq_right h1]
    have h1' : i.req.name = "" → excused i = true := by
      intro hn; cases he : excused i
      · exact absurd ⟨hn, he⟩ h1
      · rfl
    by_cases h2 : taken i = true
    · simp [h2]
    · rw [ite_eq_right h2]
      have h2' : taken i = false := by simpa using h2
      cases hr : roleOf i with
      | none => simp
      | some r =>
        simp only [roleCheck, Option.some.injEq, exists_eq_left', h2', true_and]
        rw [← capFail_none]
        by_cases k : effKind i.req = r.runsAs
        · rw [ite_eq_right (fun h => h k)]
          by_cases n : i.req.depth ≥ 1 ∧ r.edits = true
          · rw [ite_eq_left n]; simp [n]
          · rw [ite_eq_right n]
            by_cases t : recentCount i ≥ i.caps.spawnsPerWindow
            · rw [ite_eq_left t]; simp only [reduceCtorEq, false_iff, not_and]; intro _ _ _ h; omega
            · rw [ite_eq_right t]
              constructor
              · intro h; exact ⟨h1', k, n, by omega, h⟩
              · intro h; exact h.2.2.2.2
        · rw [ite_eq_left k]; simp [k]

/-- An accepted spawn never exceeds a cap: after adding the new agent, all caps hold (no
assumption on the current agents is needed, because each cap is checked on the set after the
spawn).

$$\forall i:\quad \mathrm{accepted}(\mathrm{decide}(i)) \Rightarrow \mathrm{Within}\big(C,\ \nu(q) :: A\big)$$
-/
theorem accepted_within (i : Input) (h : (decide i).accepted = true) :
    Within i.caps (newAgent i.req :: i.alive) := by
  obtain ⟨_, _, _, _, _, _, _, hw⟩ := (check_none i).mp ((accepted_iff i).mp h)
  exact hw

/-- An accepted spawn respects the rate cap: the spawner made fewer than $n$ spawns in the
window, so with this one it makes at most $n$.

$$\forall i:\quad \mathrm{accepted}(\mathrm{decide}(i)) \Rightarrow \mathrm{recent}(i) + 1 \le n$$
-/
theorem accepted_rate (i : Input) (h : (decide i).accepted = true) :
    recentCount i + 1 ≤ i.caps.spawnsPerWindow := by
  obtain ⟨_, _, _, _, _, _, hr, _⟩ := (check_none i).mp ((accepted_iff i).mp h)
  omega

/-- An accepted named spawn keeps names unique: if the alive names have no repeats, neither do
they after the spawn.

$$\forall i:\quad \mathrm{accepted}(\mathrm{decide}(i)) \land q.\mathit{name} \ne \texttt{""} \land \mathrm{names}(A) \text{ has no repeats} \Rightarrow \mathrm{names}(\nu(q) :: A) \text{ has no repeats}$$
-/
theorem accepted_names_nodup (i : Input) (h : (decide i).accepted = true) (hn : i.req.name ≠ "")
    (hd : (i.alive.map (·.name)).Nodup) : ((newAgent i.req :: i.alive).map (·.name)).Nodup := by
  obtain ⟨_, ht, _⟩ := (check_none i).mp ((accepted_iff i).mp h)
  simp only [List.map_cons, List.nodup_cons, newAgent]
  refine ⟨?_, hd⟩
  intro hm
  simp only [List.mem_map] at hm
  obtain ⟨a, ha, he⟩ := hm
  have : i.alive.any (·.name == i.req.name) = true := List.any_eq_true.mpr ⟨a, ha, by simp [he]⟩
  simp [taken, hn, this] at ht

/-- A named spawn never reuses the name of an alive agent.

$$\forall i, a \in A:\quad q.\mathit{name} \ne \texttt{""} \land a.\mathit{name} = q.\mathit{name} \Rightarrow \mathrm{decide}(i) = \mathrm{deny}(\mathrm{nameInUse})$$
-/
theorem name_in_use_denied (i : Input) (hn : i.req.name ≠ "") (a : Agent) (ha : a ∈ i.alive)
    (he : a.name = i.req.name) : decide i = .deny .nameInUse := by
  have hany : i.alive.any (·.name == i.req.name) = true := List.any_eq_true.mpr ⟨a, ha, by simp [he]⟩
  simp [decide, check, taken, hn, hany]

/-- The worktree trap (PLAN §8.1, I-272): a call for a role that runs as a worktree subagent,
without `isolation` on the call, would not run in a worktree (from the lead it becomes a teammate
in the main checkout); the guard never accepts it.

$$\forall i, \rho:\quad \mathrm{role}(i) = \rho \land \rho.\mathit{runsAs} = \mathrm{worktree} \land \lnot q.\mathit{iso} \Rightarrow \lnot\,\mathrm{accepted}(\mathrm{decide}(i))$$
-/
theorem trap_worktree_role_as_teammate (i : Input) (ρ : Role) (hr : roleOf i = some ρ)
    (hw : ρ.runsAs = .worktree) (hiso : i.req.isolation = false) : (decide i).accepted = false := by
  have hk : effKind i.req ≠ .worktree := by
    unfold effKind; simp only [hiso, Bool.false_eq_true, ↓reduceIte]; split <;> simp
  cases h : (decide i).accepted
  · rfl
  · obtain ⟨_, _, r', hr', hk', _⟩ := (check_none i).mp ((accepted_iff i).mp h)
    rw [hr] at hr'; cases hr'
    exact absurd (hk'.trans hw) hk

/-- The trap's exact verdict: a named call from the lead with a free name, for a worktree role,
without `isolation`, is denied as a kind mismatch (wanted worktree, would get teammate).

$$\forall i, \rho:\quad q.\mathit{name} \ne \texttt{""} \land \lnot\mathrm{taken}(i) \land q.d = 0 \land \lnot q.\mathit{iso} \land \mathrm{role}(i) = \rho \land \rho.\mathit{runsAs} = \mathrm{worktree} \Rightarrow \mathrm{decide}(i) = \mathrm{deny}\big(\mathrm{kindMismatch}(\mathrm{worktree}, \mathrm{teammate})\big)$$
-/
theorem trap_exact (i : Input) (ρ : Role) (hr : roleOf i = some ρ) (hw : ρ.runsAs = .worktree)
    (hiso : i.req.isolation = false) (hn : i.req.name ≠ "") (hd : i.req.depth = 0)
    (hfree : taken i = false) : decide i = .deny (.kindMismatch .worktree .teammate) := by
  have hk : effKind i.req = .teammate := by simp [effKind, hiso, hd, hn]
  simp [decide, check, hr, hw, hk, hn, hfree, roleCheck]

/-- A teammate spawn that asks for worktree isolation is never accepted: the call would run as a
worktree subagent, not as the teammate its role names.

$$\forall i, \rho:\quad \mathrm{role}(i) = \rho \land \rho.\mathit{runsAs} = \mathrm{teammate} \land q.\mathit{iso} \Rightarrow \lnot\,\mathrm{accepted}(\mathrm{decide}(i))$$
-/
theorem teammate_with_isolation_denied (i : Input) (ρ : Role) (hr : roleOf i = some ρ)
    (ht : ρ.runsAs = .teammate) (hiso : i.req.isolation = true) : (decide i).accepted = false := by
  have hk : effKind i.req = .worktree := by simp [effKind, hiso]
  cases h : (decide i).accepted
  · rfl
  · obtain ⟨_, _, r', hr', hk', _⟩ := (check_none i).mp ((accepted_iff i).mp h)
    rw [hr] at hr'; cases hr'
    rw [hk, ht] at hk'; cases hk'

/-- An `ask` model (fable) is never plainly allowed.

$$\forall i:\quad \mathrm{ask}(C, q) \Rightarrow \mathrm{decide}(i) \ne \mathrm{allow}$$
-/
theorem ask_never_allow (i : Input) (h : isAsk i.caps i.req = true) : decide i ≠ .allow := by
  unfold decide
  cases check i <;> simp [h]

/-- An `ask` model that passes every check maps to "needs approval"; any other passing request is
allowed.

$$\forall i:\quad \mathrm{check}(i) = \bot \Rightarrow \big(\mathrm{decide}(i) = \mathrm{needsApproval} \iff \mathrm{ask}(C, q)\big) \land \big(\mathrm{decide}(i) = \mathrm{allow} \iff \lnot\mathrm{ask}(C, q)\big)$$
-/
theorem ask_needs_approval (i : Input) (h : check i = none) :
    (decide i = .needsApproval ↔ isAsk i.caps i.req = true) ∧
    (decide i = .allow ↔ isAsk i.caps i.req = false) := by
  unfold decide
  rw [h]
  cases isAsk i.caps i.req <;> simp

/-- Depth-2 spawns are read-only helpers: an accepted spawn from a non-lead spawner is for a role
that does not edit.

$$\forall i, \rho:\quad \mathrm{role}(i) = \rho \land \mathrm{accepted}(\mathrm{decide}(i)) \land q.d \ge 1 \Rightarrow \lnot \rho.\mathit{edits}$$
-/
theorem accepted_nested_read_only (i : Input) (ρ : Role) (hr : roleOf i = some ρ)
    (h : (decide i).accepted = true) (hd : i.req.depth ≥ 1) : ρ.edits = false := by
  obtain ⟨_, _, r', hr', _, hne, _⟩ := (check_none i).mp ((accepted_iff i).mp h)
  rw [hr] at hr'; cases hr'
  cases he : ρ.edits
  · rfl
  · exact absurd ⟨hd, he⟩ hne

/-- The kind the named role is meant to run as (`none` for a role not in the table); the spawn
hook logs it next to the kind the call produces, $\kappa(i.\mathit{req})$, so a mismatch explains itself.

$$\operatorname{wantKind}(i) = \begin{cases} \mathrm{some}(\rho.\mathit{runsAs}) & \mathrm{role}(i) = \mathrm{some}(\rho) \\ \bot & \mathrm{role}(i) = \bot \end{cases}$$
-/
def wantKind (i : Input) : Option Kind := (roleOf i).map (·.runsAs)

/-- A `kindMismatch` denial carries the wanted kind of the role and the kind the call produces.

$$\forall i, w, g:\quad \operatorname{check}(i) = \mathrm{some}(\mathrm{kindMismatch}(w, g)) \implies \operatorname{wantKind}(i) = \mathrm{some}(w) \land g = \kappa(i.\mathit{req}) \land w \ne g$$

A mismatch reason always names the role's kind and the call's kind, and they differ.
-/
theorem kindMismatch_fields (i : Input) (w g : Kind) (h : check i = some (.kindMismatch w g)) :
    wantKind i = some w ∧ g = effKind i.req ∧ w ≠ g := by
  unfold check at h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h
  rename_i r hr
  unfold roleCheck at h
  split at h
  · rename_i hne
    simp only [Option.some.injEq, Reason.kindMismatch.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    exact ⟨by simp [wantKind, hr], rfl, fun he => hne he.symm⟩
  split at h
  · cases h
  split at h
  · cases h
  unfold capFail at h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h
  cases ho : overRole i.caps.perRole (newAgent i.req :: i.alive) <;> simp [ho] at h

/-! ## Examples -/

/-- The roster rows the examples use.

$$P_0 = [(\texttt{lean-prover}, \mathrm{worktree}, \top), (\texttt{researcher}, \mathrm{teammate}, \top), (\texttt{reviewer}, \mathrm{subagent}, \bot)]$$
-/
def exRoles : List Role :=
  [⟨"lean-prover", .worktree, true⟩, ⟨"researcher", .teammate, true⟩, ⟨"reviewer", .subagent, false⟩]

/-- An example input with the default caps at time 1000 s.

$$\mathrm{ex}(A, H, q) = (A, P_0, C_{default}, H, 1000, q)$$
-/
def exInput (alive : List Agent) (recent : List (String × Nat)) (q : Req) : Input :=
  ⟨alive, exRoles, {}, recent, 1000, q⟩

#guard decide (exInput [] [] ⟨"lean-ops", "lean-prover", true, "", "lead", 0⟩) == .allow
#guard decide (exInput [] [] ⟨"lean-ops", "lean-prover", false, "", "lead", 0⟩) ==
  .deny (.kindMismatch .worktree .teammate)
#guard decide (exInput [] [] ⟨"r1", "researcher", true, "", "lead", 0⟩) ==
  .deny (.kindMismatch .teammate .worktree)
#guard decide (exInput [] [] ⟨"r1", "researcher", false, "", "lead", 0⟩) == .allow
#guard decide (exInput [] [] ⟨"lean-x", "lean-prover", true, "claude-fable-5-1", "lead", 0⟩) == .needsApproval
#guard decide (exInput [] [] ⟨"lean-x", "lean-prover", true, "Claude-FABLE", "lead", 0⟩) == .needsApproval
#guard decide (exInput [] [] ⟨"lean-x", "lean-prover", true, "claude-opus-5-5", "lead", 0⟩) == .allow
#guard decide (exInput [] [] ⟨"", "lean-prover", true, "", "lead", 0⟩) == .deny .unnamed
#guard decide (exInput [] [] ⟨"", "reviewer", false, "", "lead", 0⟩) == .deny .unnamed
#guard decide { exInput [] [] ⟨"", "reviewer", false, "", "lead", 0⟩ with caps := { unnamedReadOnly := true } } ==
  .allow
#guard decide (exInput [⟨"a", "reviewer", .subagent, "lead"⟩] [] ⟨"a", "lean-prover", true, "", "lead", 0⟩) ==
  .deny .nameInUse
#guard decide (exInput [] [] ⟨"x", "nobody", true, "", "lead", 0⟩) == .deny .unknownRole
#guard wantKind (exInput [] [] ⟨"x", "nobody", true, "", "lead", 0⟩) == none
#guard wantKind (exInput [] [] ⟨"x", "researcher", true, "", "lead", 0⟩) == some .teammate
#guard decide (exInput [] [] ⟨"x", "lean-prover", true, "", "eng-webkit", 1⟩) == .deny .nestedEditor
#guard decide (exInput [] [] ⟨"x", "reviewer", false, "", "eng-webkit", 1⟩) == .allow
-- the 4th lean-prover hits the per-role cap
#guard decide (exInput ((List.range 3).map fun k => ⟨s!"l{k}", "lean-prover", .worktree, "lead"⟩) []
  ⟨"l9", "lean-prover", true, "", "lead", 0⟩) == .deny (.capRole "lean-prover")
-- the 6th teammate is denied
#guard decide (exInput ((List.range 5).map fun k => ⟨s!"t{k}", "researcher", .teammate, "lead"⟩) []
  ⟨"t9", "researcher", false, "", "lead", 0⟩) == .deny .capTeammates
-- the 11th spawn in 10 minutes is denied; spawns 600 s old no longer count
#guard decide (exInput [] ((List.range 10).map fun _ => ("lead", 500)) ⟨"x", "lean-prover", true, "", "lead", 0⟩) ==
  .deny .rateLimited
#guard decide (exInput [] ((List.range 10).map fun _ => ("lead", 400)) ⟨"x", "lean-prover", true, "", "lead", 0⟩) ==
  .allow

end Fw.Ops.SpawnGuard
