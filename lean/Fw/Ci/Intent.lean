import Fw.Ci.Trigger
/-!
# Who asks for a CI run (task `ci-own-trigger`)

`Fw.Ci.Trigger` answers "could this push have changed the result of a workflow?". It does not answer "did anyone ask
for this run?", so one push that touched Lean or the site started 8–13 workflows (macOS lanes included), and agents
cancelled what they would not read (forensics in `research/notes/2026/10-18-ci-own-trigger.md`: 300 runs, 19 % read).

Here a push to `ci/**` starts a lane only when the head commit asks for it with a token `[ci:<lane>]` (the *intent*).
A push with no token at all starts only the default lanes (`lean.yml`, never a macOS lane); a token for no lane, such
as `[ci:none]`, starts nothing. A requested lane still starts only when the push changed one of its inputs
(`Trigger.starts_iff`), when no newer push on the branch changed them (*superseded*), and when the commit is not
already on `main` (*landed*). Main pushes, dispatches and schedules always run (a run there is a record).

Two places evaluate it:
* the guard job's `if:` (`ifExpr`, rendered here and written into every workflow by `scripts/ci-paths.mjs`): GitHub
  skips the guard, so no runner starts, when the head commit does not want the lane (`gate`, `gate_eq`);
* the guard script (`.github/scripts/changed-inputs.mjs`), which decides `start` in full.

Golden: `packages/contracts/golden/ci/intent.jsonl` (the lanes with their `if:` and the replay cases), written by
`lake test -- --write-ci-trigger-golden`.
-/
namespace Fw.Ci.Intent
open Lean Fw.Ops.PathCheck Fw.Ci.Trigger
open Fw.Console.LandSpeed (selected selected_of_mem skip_sound ReadsWithin St)

/-! ## The intent token -/

/-- The token prefix. $$\mathrm{pre} = \texttt{[ci:}$$ -/
def tokPrefix : List Char := ['[', 'c', 'i', ':']

/-- The token that asks for lane $n$.
$$\forall n:\ \operatorname{tok}(n) = \texttt{[ci:} \mathbin{+\!\!+} n \mathbin{+\!\!+} \texttt{]}$$ -/
def tok (n : String) : List Char := tokPrefix ++ n.toList ++ [']']

/-- The message with ASCII `A`–`Z` lowered (Lean `Char.toLower`; GitHub's `contains` ignores case too).
$$\forall m:\ \operatorname{low}(m) = [\, \operatorname{lower}(c) : c \in m \,]$$ -/
def lower (m : String) : List Char := m.toList.map Char.toLower

/-- Does the message carry any intent (some `[ci:`)?
$$\forall m:\ \operatorname{intent}(m) \iff \mathrm{pre} \sqsubseteq_{\mathrm{inf}} \operatorname{low}(m)$$ -/
def intent (m : String) : Bool := decide (tokPrefix <:+: lower m)

/-- Does the message ask for lane $n$?
$$\forall n, m:\ \operatorname{req}(n, m) \iff \operatorname{tok}(n) \sqsubseteq_{\mathrm{inf}} \operatorname{low}(m)$$ -/
def requested (n m : String) : Bool := decide (tok n <:+: lower m)

/-- A character allowed in a lane name: a lower-case ASCII letter, a digit or `-`.
$$\forall c:\ \operatorname{nc}(c) \iff c \in \{\texttt{a}..\texttt{z}\} \cup \{\texttt{0}..\texttt{9}\} \cup \{\texttt{-}\}$$ -/
def nameChar (c : Char) : Bool := c.isLower || c.isDigit || c == '-'

/-- A lane name: non-empty, every character a name character.
$$\forall n:\ \operatorname{valid}(n) \iff n \ne \varepsilon \land \forall c \in n:\ \operatorname{nc}(c)$$ -/
def validName (n : String) : Bool := !n.isEmpty && n.toList.all nameChar

#guard requested "lean" "fix x\n\n[ci:lean] [ci:wktr]"
#guard requested "lean" "[CI:Lean]"
#guard !requested "wktr" "[ci:wktr-fixtures]"
#guard !requested "lean" "[ci: lean]"
#guard intent "[ci:none]" && !requested "lean" "[ci:none]"
#guard !intent "merge main into ci/x"

/-- A requested lane means the message carries intent.
$$\forall n, m:\ \operatorname{req}(n, m) \Rightarrow \operatorname{intent}(m)$$ -/
theorem intent_of_requested (n m : String) (h : requested n m = true) : intent m = true := by
  simp only [requested, intent, decide_eq_true_eq] at h ⊢
  exact List.IsInfix.trans (List.IsPrefix.isInfix (by simp [tok, List.append_assoc])) h

/-- Two names without brackets: if the first, followed by `]`, starts the second followed by `]`, they are equal.
$$\forall a, b, t:\ \texttt{]} \notin a \land \texttt{]} \notin b \land a \mathbin{+\!\!+} \texttt{]} \mathbin{+\!\!+} t = b \mathbin{+\!\!+} \texttt{]} \Rightarrow a = b$$ -/
theorem close_inj (a b t : List Char) (ha : ']' ∉ a) (hb : ']' ∉ b) (h : a ++ ']' :: t = b ++ [']']) : a = b := by
  induction a generalizing b with
  | nil =>
    cases b with
    | nil => rfl
    | cons y b' =>
      simp only [List.nil_append, List.cons_append, List.cons.injEq] at h
      exact absurd (h.1 ▸ List.mem_cons_self) hb
  | cons x a' ih =>
    cases b with
    | nil =>
      simp only [List.cons_append, List.nil_append, List.cons.injEq] at h
      exact absurd (h.1 ▸ List.mem_cons_self) ha
    | cons y b' =>
      simp only [List.cons_append, List.cons.injEq] at h
      rw [h.1, ih b' (fun hm => ha (List.mem_cons_of_mem _ hm)) (fun hm => hb (List.mem_cons_of_mem _ hm)) h.2]

/-- **Token non-confusion.** For valid lane names, the token of $a$ occurs inside the token of $b$ only when
$a = b$; so a message asking for `wktr-fixtures` does not ask for `wktr`.
$$\forall a, b:\ \operatorname{valid}(a) \land \operatorname{valid}(b) \land \operatorname{tok}(a) \sqsubseteq_{\mathrm{inf}} \operatorname{tok}(b) \Rightarrow a = b$$ -/
theorem tok_infix_inj (a b : String) (ha : validName a = true) (hb : validName b = true)
    (h : tok a <:+: tok b) : a = b := by
  have nc : ∀ (n : String), validName n = true → '[' ∉ n.toList ∧ ']' ∉ n.toList := by
    intro n hn
    simp only [validName, Bool.and_eq_true, List.all_eq_true] at hn
    exact ⟨fun hm => absurd (hn.2 _ hm) (by decide), fun hm => absurd (hn.2 _ hm) (by decide)⟩
  obtain ⟨ao, ac⟩ := nc a ha
  obtain ⟨bo, bc⟩ := nc b hb
  obtain ⟨s, t, hst⟩ := h
  cases s with
  | nil =>
    simp only [tok, tokPrefix, List.nil_append, List.append_assoc, List.cons_append, List.cons.injEq] at hst
    obtain ⟨-, -, -, -, hab⟩ := hst
    exact String.toList_inj.mp (close_inj _ _ t ac bc (by simpa using hab))
  | cons c s' =>
    simp only [tok, tokPrefix, List.cons_append, List.append_assoc, List.cons.injEq] at hst
    obtain ⟨-, hrest⟩ := hst
    have hm : '[' ∈ 'c' :: 'i' :: ':' :: ([] ++ (b.toList ++ [']'])) := by
      rw [← hrest]; simp
    simp [bo] at hm

/-! ## Lanes -/

/-- A lane: a workflow of the trigger table, the name an intent token uses, whether a push run of it holds a macOS
job, and whether it starts without any intent.
$$\ell = (w,\ n,\ \mathit{mac},\ \mathit{dflt})$$ -/
structure Lane where
  wf : Wf
  name : String
  macos : Bool
  byDefault : Bool

/-- The workflows whose push run holds a macOS job (`gate-gaps` runs macOS only on a dispatch with `macos=true`).
$$M = [\texttt{engine-premises},\ \texttt{sim-speed},\ \texttt{webkit-sim},\ \texttt{wktr-fixtures},\ \texttt{wktr}]$$ -/
def macosFiles : List String :=
  ["engine-premises.yml", "sim-speed.yml", "webkit-sim.yml", "wktr-fixtures.yml", "wktr.yml"]

/-- The default lanes, which start on a push with no intent: only the Lean proofs, on ubuntu.
$$D = [\texttt{lean.yml}]$$ -/
def defaultFiles : List String := ["lean.yml"]

/-- The lane name of a workflow file: the file name without `.yml`.
$$\forall f:\ \operatorname{stem}(f) = f \text{ without its last 4 characters (empty when } |f| \le 4)$$ -/
def stem (f : String) : String := (f.dropEnd 4).toString

/-- The lane of a workflow. $$\forall w:\ \operatorname{lane}(w) = (w,\ \operatorname{stem}(w.\mathit{file}),\ w.\mathit{file} \in M,\ w.\mathit{file} \in D)$$ -/
def laneOf (w : Wf) : Lane := ⟨w, stem w.file, macosFiles.contains w.file, defaultFiles.contains w.file⟩

/-- Every lane, in table order. $$L = [\, \operatorname{lane}(w) : w \in W \,]$$ -/
def lanes : List Lane := table.map laneOf

#guard lanes.all (validName ·.name)
#guard (lanes.map (·.name)).eraseDups.length == lanes.length
#guard (lanes.filter (·.byDefault)).map (·.name) == ["lean"]
#guard (macosFiles ++ defaultFiles).all fun f => (table.map (·.file)).contains f

/-- **No default lane is a macOS lane.**
$$\forall \ell \in L:\ \ell.\mathit{dflt} \Rightarrow \lnot \ell.\mathit{mac}$$ -/
theorem default_lane_not_macos (l : Lane) (hl : l ∈ lanes) (hd : l.byDefault = true) : l.macos = false := by
  simp only [lanes, List.mem_map] at hl
  obtain ⟨w, -, rfl⟩ := hl
  simp only [laneOf, defaultFiles, List.contains_cons, List.contains_nil, Bool.or_false, beq_iff_eq] at hd ⊢
  rw [hd]; decide

/-! ## The start decision -/

/-- Does the head commit want the lane? With intent: exactly the lanes it names; without: the default lanes.
$$\forall \ell, m:\ \operatorname{want}(\ell, m) = \begin{cases} \operatorname{req}(\ell.n, m) & \operatorname{intent}(m) \\ \ell.\mathit{dflt} & \lnot\operatorname{intent}(m) \end{cases}$$ -/
def wanted (l : Lane) (m : String) : Bool := if intent m then requested l.name m else l.byDefault

/-- The facts the guard reads for one run. `ci`: a push to `refs/heads/ci/**`. `msg`: the head commit message.
`diff`, `differs`: the push's diff and "the new content is not `main`'s" (as in `Trigger.effective`). `newer`: the
files changed between this commit and the branch's current tip (empty when it is the tip). `landed`: the commit is
already on `main`.
$$p = (\mathit{ci},\ m,\ D,\ \delta,\ N,\ \mathit{land})$$ (below its fields are written $p.\mathit{ci}$, $p.m$, $p.D$, $p.\delta$, $p.N$, $p.\mathit{land}$) -/
structure Push where
  ci : Bool
  msg : String
  diff : List String
  differs : String → Bool
  newer : List String
  landed : Bool

/-- A newer push on the branch changed one of the lane's inputs, so this run's result is stale.
$$\forall S, \ell, N:\ \operatorname{sup}(S, \ell, N) \iff \operatorname{starts}(\ell.w, S, N)$$ -/
def superseded (S : String → List String) (l : Lane) (newer : List String) : Bool := l.wf.starts S newer

/-- **The start decision.** A record (not a `ci/**` push) always runs. A `ci/**` push starts the lane iff the head
commit wants it, the push changed one of its inputs, no newer push changed them, and the commit has not landed.
$$\forall S, \ell, p:\ \operatorname{start}(S, \ell, p) \iff \lnot p.\mathit{ci} \lor \bigl(\operatorname{want}(\ell, p.m) \land \operatorname{starts}(\ell.w, S, \operatorname{eff}(p.D, p.\delta)) \land \lnot\operatorname{sup}(S, \ell, p.N) \land \lnot p.\mathit{land}\bigr)$$ -/
def start (S : String → List String) (l : Lane) (p : Push) : Bool :=
  !p.ci || (wanted l p.msg && l.wf.starts S (effective p.diff p.differs) && !superseded S l p.newer && !p.landed)

/-- **A record always runs.** A main push, a dispatch or a schedule starts every lane (its paths and branches filter
aside).
$$\forall S, \ell, p:\ \lnot p.\mathit{ci} \Rightarrow \operatorname{start}(S, \ell, p)$$ -/
theorem record_always_runs (S : String → List String) (l : Lane) (p : Push) (h : p.ci = false) :
    start S l p = true := by
  simp [start, h]

/-- **The decision on a `ci/**` push, unfolded** (the old `Trigger.starts_iff`, now under intent).
$$\forall S, \ell, p:\ p.\mathit{ci} \Rightarrow \Bigl(\operatorname{start}(S, \ell, p) \iff \operatorname{want}(\ell, p.m) \land \bigl(\exists x \in p.D:\ p.\delta(x) \land \mathrm{in}(\mathrm{parse}(\operatorname{expand}(S, \ell.w.G)), x)\bigr) \land \lnot\operatorname{sup}(S, \ell, p.N) \land \lnot p.\mathit{land}\Bigr)$$ -/
theorem start_ci_iff (S : String → List String) (l : Lane) (p : Push) (hci : p.ci = true) :
    start S l p = true ↔ wanted l p.msg = true ∧
      (∃ x ∈ p.diff, p.differs x = true ∧ inScope (parseScope (expand S l.wf.inputs)) x = true) ∧
      superseded S l p.newer = false ∧ p.landed = false := by
  rw [← starts_iff]
  simp only [start, hci, Bool.not_true, Bool.false_or, Bool.and_eq_true, Bool.not_eq_true']
  constructor
  · rintro ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩; exact ⟨h1, h2, h3, h4⟩
  · rintro ⟨h1, h2, h3, h4⟩; exact ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩

/-- **No unrequested start.** On a `ci/**` push a lane starts only if the head commit names it, or the commit has no
intent at all and the lane is a default lane.
$$\forall S, \ell, p:\ p.\mathit{ci} \land \operatorname{start}(S, \ell, p) \Rightarrow \bigl(\operatorname{intent}(p.m) \land \operatorname{req}(\ell.n, p.m)\bigr) \lor \bigl(\lnot\operatorname{intent}(p.m) \land \ell.\mathit{dflt}\bigr)$$ -/
theorem no_unrequested_start (S : String → List String) (l : Lane) (p : Push) (hci : p.ci = true)
    (h : start S l p = true) :
    (intent p.msg = true ∧ requested l.name p.msg = true) ∨ (intent p.msg = false ∧ l.byDefault = true) := by
  have hw := ((start_ci_iff S l p hci).mp h).1
  unfold wanted at hw
  cases hi : intent p.msg
  · rw [hi] at hw; exact Or.inr ⟨rfl, hw⟩
  · rw [hi] at hw; exact Or.inl ⟨rfl, hw⟩

/-- **No requested lane is lost.** If the head commit names the lane, the push changed one of its inputs, no newer
push changed them and the commit has not landed, the lane starts.
$$\forall S, \ell, p:\ \operatorname{req}(\ell.n, p.m) \land \operatorname{starts}(\ell.w, S, \operatorname{eff}(p.D, p.\delta)) \land \lnot\operatorname{sup}(S, \ell, p.N) \land \lnot p.\mathit{land} \Rightarrow \operatorname{start}(S, \ell, p)$$ -/
theorem requested_and_changed_starts (S : String → List String) (l : Lane) (p : Push)
    (hr : requested l.name p.msg = true) (hs : l.wf.starts S (effective p.diff p.differs) = true)
    (hn : superseded S l p.newer = false) (hl : p.landed = false) : start S l p = true := by
  have hw : wanted l p.msg = true := by simp [wanted, intent_of_requested _ _ hr, hr]
  simp [start, hw, hs, hn, hl]

/-- **The default starts no macOS lane.** On a `ci/**` push whose head commit carries no intent, no lane of the
table that starts holds a macOS job.
$$\forall S, p, \ell \in L:\ p.\mathit{ci} \land \lnot\operatorname{intent}(p.m) \land \operatorname{start}(S, \ell, p) \Rightarrow \ell.\mathit{dflt} \land \lnot \ell.\mathit{mac}$$ -/
theorem default_no_macos (S : String → List String) (p : Push) (l : Lane) (hl : l ∈ lanes) (hci : p.ci = true)
    (hi : intent p.msg = false) (h : start S l p = true) : l.byDefault = true ∧ l.macos = false := by
  rcases no_unrequested_start S l p hci h with ⟨h1, -⟩ | ⟨-, hd⟩
  · rw [hi] at h1; exact Bool.noConfusion h1
  · exact ⟨hd, default_lane_not_macos l hl hd⟩

/-- **A superseded run starts no job.** If a newer push on the branch changed one of the lane's inputs, the guard
does not start the lane's jobs.
$$\forall S, \ell, p:\ p.\mathit{ci} \land \operatorname{sup}(S, \ell, p.N) \Rightarrow \lnot\operatorname{start}(S, \ell, p)$$ -/
theorem superseded_never_runs_heavy (S : String → List String) (l : Lane) (p : Push) (hci : p.ci = true)
    (h : superseded S l p.newer = true) : start S l p = false := by
  simp [start, hci, h]

/-- **A landed commit starts no job.**
$$\forall S, \ell, p:\ p.\mathit{ci} \land p.\mathit{land} \Rightarrow \lnot\operatorname{start}(S, \ell, p)$$ -/
theorem landed_never_runs_heavy (S : String → List String) (l : Lane) (p : Push) (hci : p.ci = true)
    (h : p.landed = true) : start S l p = false := by
  simp [start, hci, h]

/-- **A run that is not superseded still answers for the tip.** If the lane's result depends only on its expanded
inputs and the newer pushes changed none of them, the result on this commit equals the result on the tip.
$$\forall S, \ell, N, \sigma, \sigma':\ \mathrm{RW}(\mathit{run}, \operatorname{expand}(S, \ell.w.G)) \land \lnot\operatorname{sup}(S, \ell, p.N) \land (\forall q \notin N:\ \sigma(q) = \sigma'(q)) \Rightarrow \mathit{run}(\sigma) = \mathit{run}(\sigma')$$ -/
theorem unsuperseded_replays {R} (S : String → List String) (l : Lane) (newer : List String) (run : St → R)
    (hrw : ReadsWithin run (expand S l.wf.inputs)) (hs : superseded S l newer = false) (σ σ' : St)
    (hd : ∀ q, q ∉ newer → σ q = σ' q) : run σ = run σ' :=
  skipped_replays S l.wf newer run hrw hs σ σ' hd

/-! ## The guard job's `if:` -/

/-- The `if:` of the guard job, as a Boolean: true unless a `ci/**` push's head commit does not want the lane. A
default lane passes when the message has no `[ci:` or names it; any other lane only when the message names it.
$$\forall \ell, c, m:\ \operatorname{gate}(\ell, c, m) = \lnot c \lor \begin{cases} \lnot\operatorname{intent}(m) \lor \operatorname{req}(\ell.n, m) & \ell.\mathit{dflt} \\ \operatorname{req}(\ell.n, m) & \lnot \ell.\mathit{dflt} \end{cases}$$ -/
def gate (l : Lane) (ci : Bool) (m : String) : Bool :=
  !ci || (if l.byDefault then !intent m || requested l.name m else requested l.name m)

/-- **The `if:` is exactly "not a ci push, or wanted".**
$$\forall \ell, c, m:\ \operatorname{gate}(\ell, c, m) = \lnot c \lor \operatorname{want}(\ell, m)$$ -/
theorem gate_eq (l : Lane) (ci : Bool) (m : String) : gate l ci m = (!ci || wanted l m) := by
  unfold gate wanted
  cases hi : intent m <;> cases hr : requested l.name m <;> cases l.byDefault <;> simp_all
  have := intent_of_requested _ _ hr
  simp_all

/-- **The `if:` never drops a start, and skips only what the guard would not start.**
$$\forall S, \ell, p:\ \operatorname{start}(S, \ell, p) \Rightarrow \operatorname{gate}(\ell, p.\mathit{ci}, p.m)$$ -/
theorem start_gate (S : String → List String) (l : Lane) (p : Push) (h : start S l p = true) :
    gate l p.ci p.msg = true := by
  rw [gate_eq]
  cases hci : p.ci
  · rfl
  · simpa using ((start_ci_iff S l p hci).mp h).1

/-- **End to end: no started lane is lost on GitHub's side.** If the cones stay inside the coarse globs and the guard
would start the lane on a `ci/**` push, then GitHub's static `paths` filter passes the push (so the run is created)
and the guard job's `if:` passes (so the guard runs).
$$\forall c, \ell, p:\ \operatorname{within}(c) \land p.\mathit{ci} \land \operatorname{start}(\operatorname{setMap}(c), \ell, p) \Rightarrow \operatorname{sel}(\operatorname{push}(\ell.w), p.D) \land \operatorname{gate}(\ell, \top, p.m)$$ -/
theorem no_lane_lost (c : String → List String) (hc : ConeWithin c) (l : Lane) (p : Push) (hci : p.ci = true)
    (h : start (setMap c) l p = true) : selected (pushPaths l.wf) p.diff = true ∧ gate l true p.msg = true := by
  have hs := ((start_ci_iff _ l p hci).mp h)
  refine ⟨push_filter_passes c hc l.wf p.diff p.differs ((starts_iff _ _ _ _).mpr hs.2.1), ?_⟩
  have := start_gate _ l p h
  rwa [hci] at this

/-- A `contains` call on the head commit message, as GitHub expression text.
$$\forall s:\ \operatorname{has}(s) = \texttt{contains(github.event.head\_commit.message, '}s\texttt{')}$$ -/
def containsExpr (s : String) : String := "contains(github.event.head_commit.message, '" ++ s ++ "')"

/-- The "not a ci push" part of the `if:`.
$$\mathrm{rec} = \texttt{github.event\_name != 'push' || !startsWith(github.ref, 'refs/heads/ci/')}$$ -/
def recordExpr : String := "github.event_name != 'push' || !startsWith(github.ref, 'refs/heads/ci/')"

/-- The guard job's `if:` text: `gate` written as a GitHub expression, one disjunct per disjunct of `gate`.
$$\forall \ell:\ \operatorname{ifExpr}(\ell) = \mathrm{rec} \mathbin{\|} \begin{cases} \texttt{!}\operatorname{has}(\texttt{[ci:}) \mathbin{\|} \operatorname{has}(\operatorname{tok}(\ell.n)) & \ell.\mathit{dflt} \\ \operatorname{has}(\operatorname{tok}(\ell.n)) & \lnot\ell.\mathit{dflt} \end{cases}$$ -/
def ifExpr (l : Lane) : String :=
  "${{ " ++ recordExpr ++ (if l.byDefault then " || !" ++ containsExpr (String.ofList tokPrefix) else "") ++
    " || " ++ containsExpr (String.ofList (tok l.name)) ++ " }}"

#guard ifExpr (laneOf ⟨"wktr.yml", [], []⟩) ==
  "${{ github.event_name != 'push' || !startsWith(github.ref, 'refs/heads/ci/') || contains(github.event.head_commit.message, '[ci:wktr]') }}"

/-! ## Replay cases and golden (`packages/contracts/golden/ci/intent.jsonl`) -/

/-- The files of the lanes a run starts, under the sample cones (`Trigger.sampleCone`); a path in `merged` already has
`main`'s content.
$$\forall c, m, D, M, N, \mathit{land}:\ \operatorname{runI} = [\, \ell.w.\mathit{file} : \ell \in L,\ \operatorname{start}(S_{\mathrm{sample}}, \ell, (c, m, D, \lambda x.\ x \notin M, N, \mathit{land})) \,]$$ -/
def runIntent (ci : Bool) (msg : String) (diff merged newer : List String) (landed : Bool) : List String :=
  (lanes.filter fun l => start (setMap sampleCone) l ⟨ci, msg, diff, (fun x => !merged.contains x), newer, landed⟩).map
    (·.wf.file)

/-- The files of the lanes whose guard job's `if:` passes.
$$\forall c, m:\ \operatorname{gated}(c, m) = [\, \ell.w.\mathit{file} : \ell \in L,\ \operatorname{gate}(\ell, c, m) \,]$$ -/
def gatedBy (ci : Bool) (msg : String) : List String := (lanes.filter fun l => gate l ci msg).map (·.wf.file)

-- no intent: only lean, even though the module is in the fwcore cone of 8 workflows
#guard runIntent true "fix x" ["lean/Fw/Wire.lean"] [] [] false == ["lean.yml"]
#guard runIntent true "fix x\n\n[ci:wktr]" ["lean/Fw/Wire.lean"] [] [] false == ["wktr.yml"]
#guard runIntent true "[ci:wktr]" ["docs/x.md"] [] [] false == []
#guard runIntent true "[ci:lean]" ["lean/Fw/Wire.lean"] [] ["lean/Fw/Wire.lean"] false == []
#guard runIntent true "[ci:lean]" ["lean/Fw/Wire.lean"] [] ["docs/x.md"] false == ["lean.yml"]
#guard runIntent false "" [] [] [] false == lanes.map (·.wf.file)
#guard gatedBy true "x" == ["lean.yml"]

/-- A replay case: name, ci push?, head message, diff, paths that equal `main`, newer files, landed.
$$\mathrm{cases} = [\, (n, c, m, D, M, N, \mathit{land}) \,]$$ -/
def cases : List (String × Bool × String × List String × List String × List String × Bool) := [
  ("no intent, a fwcore module: only the default lane", true, "fix x", ["lean/Fw/Wire.lean"], [], [], false),
  ("no intent, a wktr file: nothing (wktr is not a default lane)", true, "fix x", ["packages/measure-wktr/src/a.mjs"],
    [], [], false),
  ("intent for one macOS lane", true, "fix x\n\n[ci:wktr]", ["lean/Fw/Wire.lean"], [], [], false),
  ("a longer name is not the shorter lane", true, "[ci:wktr-fixtures]", ["lean/Fw/Wire.lean"], [], [], false),
  ("two lanes, upper case", true, "[CI:Lean] [ci:breakpoint-gate]", ["lean/Fw/Wire.lean"], [], [], false),
  ("intent for nothing", true, "handoff [ci:none]", ["lean/Fw/Wire.lean"], [], [], false),
  ("requested lane whose inputs did not change", true, "[ci:wktr]", ["docs/x.md"], [], [], false),
  ("a merge of main with intent", true, "[ci:lean]", ["lean/Fw/Wire.lean"], ["lean/Fw/Wire.lean"], [], false),
  ("superseded: a newer push changed the lane's inputs", true, "[ci:lean]", ["lean/Fw/Wire.lean"], [],
    ["lean/Fw/Wire.lean"], false),
  ("a newer docs-only push does not supersede", true, "[ci:lean]", ["lean/Fw/Wire.lean"], [], ["docs/x.md"], false),
  ("landed", true, "[ci:lean]", ["lean/Fw/Wire.lean"], [], [], true),
  ("a record (main push, dispatch) runs every lane", false, "", [], [], [], false)]

/-- The lanes line: every lane with its name, token, macOS flag, default flag and the guard `if:` text.
$$\operatorname{lanesLine} = \{\texttt{kind}: \texttt{lanes},\ \texttt{prefix}: \mathrm{pre},\ \texttt{lanes}: [\,\{\texttt{file}, \texttt{name}, \texttt{token}, \texttt{macos}, \texttt{byDefault}, \texttt{if}\} : \ell \in L\,]\}$$ -/
def lanesLine : Json :=
  Json.mkObj [("kind", "lanes"), ("prefix", .str (String.ofList tokPrefix)),
    ("lanes", .arr (lanes.map fun l => Json.mkObj [("file", .str l.wf.file), ("name", .str l.name),
      ("token", .str (String.ofList (tok l.name))), ("macos", .bool l.macos), ("byDefault", .bool l.byDefault),
      ("if", .str (ifExpr l))]).toArray)]

/-- One replay line with the started and the gated lanes.
$$\operatorname{caseLine}(n, c, m, D, M, N, \mathit{land}) = \{\dots,\ \texttt{started}: \operatorname{runI}(c, m, D, M, N, \mathit{land}),\ \texttt{gated}: \operatorname{gated}(c, m)\}$$ -/
def caseLine (k : String × Bool × String × List String × List String × List String × Bool) : Json :=
  let (n, ci, msg, diff, merged, newer, landed) := k
  Json.mkObj [("kind", "case"), ("name", .str n), ("ci", .bool ci), ("msg", .str msg), ("diff", strs diff),
    ("merged", strs merged), ("newer", strs newer), ("landed", .bool landed),
    ("cones", Json.mkObj [("Main", strs (sampleCone "Main")), ("BreakgenMain", strs (sampleCone "BreakgenMain"))]),
    ("started", strs (runIntent ci msg diff merged newer landed)), ("gated", strs (gatedBy ci msg))]

/-- The golden text. $$\text{one JSON object per line: the lanes, then the cases}$$ -/
def goldenText : String := String.join ((lanesLine :: cases.map caseLine).map fun j => j.compress ++ "\n")

/-- Compare (or write) the golden file; returns the number of stale files.
$$\operatorname{runGolden}(\mathit{write}) = 0\ \text{if the file equals goldenText (or was written), else } 1$$ -/
def runGolden (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / ".." / "packages" / "contracts" / "golden" / "ci" / "intent.jsonl"
  if write then
    IO.FS.createDirAll (root / ".." / "packages" / "contracts" / "golden" / "ci")
    IO.FS.writeFile p goldenText
    IO.println s!"ci intent golden: written {cases.length} cases"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != goldenText then
    IO.println s!"ci intent golden: {p} is stale (regenerate: cd lean && lake test -- --write-ci-trigger-golden)"
    return 1
  IO.println s!"ci intent golden: {cases.length} cases ok"
  return 0

end Fw.Ci.Intent
