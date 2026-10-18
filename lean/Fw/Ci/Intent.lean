import Fw.Ci.Trigger
import Fw.Ci.Verdict
/-!
# Who asks for a CI run (task `ci-own-trigger`)

`Fw.Ci.Trigger` answers "could this push have changed the result of a workflow?". It does not answer "did anyone ask
for this run?", so one push that touched Lean or the site started 8–13 workflows (macOS lanes included), and agents
cancelled what they would not read (forensics in `research/notes/2026/10-18-ci-own-trigger.md`: 300 runs, 19 % read).

Here a push to `ci/**` starts a lane only when the head commit asks for it with a token `[ci:<lane>]` (the *intent*),
or when the lane is a default lane: `lean.yml` (ubuntu, never a macOS lane) is wanted on every push, whatever lanes it
names. A token for no lane, such as `[ci:none]`, asks for nothing more.

Round 3 (the threat model: the tip push of a `ci/**` branch always runs every lane its head commit requests, plus lean,
whenever the lane's inputs differ from `main`; a wait never reports pass for a requested lane that did not run; older
pushes may waste runner minutes):
* no workflow has a `paths` filter any more, so every push creates a run of every lane, and the guard decides
  (`decision`): a `ci/**` push runs a wanted lane iff its commit is the branch tip (`git ls-remote`), not on `main`, and
  some file that differs from `main` on the whole branch (merge-base to the commit, `Trigger.effective`) is an input of
  the lane (`tip_starts`, `tip_lean_always`, `tip_history_free`: a revert in an earlier push does not matter);
* no concurrency group is shared on `ci/**` and nothing is cancelled (`groupExpr`, `Fw.Ci.Cancel`); instead every
  heavy job re-checks the tip in its first step and stops as `stale` when a newer push moved it (`stale_never_works`);
* a `main` push keeps the old coarse `paths` rule, now in the guard (`main_keeps_paths_rule`); dispatches and
  schedules always run (`record_always_runs`).

Two places evaluate the intent: the guard job's `if:` (`ifExpr`, rendered here and written into every workflow by
`scripts/ci-paths.mjs`; GitHub skips the guard, so no runner starts, when the head commit does not want the lane:
`gate`, `gate_eq`), and the guard script (`.github/scripts/changed-inputs.mjs`), which computes `decision` in full. The
verdict of a finished run is `Fw.Ci.Verdict.verdict`, never the workflow conclusion alone.

Round 4: `fw ci push` refuses a push on which a named lane would be skipped, since its wait could never pass
(`pushOk`, `skipped_named_refused`); `--partial` lets it push when one named lane starts.

Golden: `packages/contracts/golden/ci/intent.jsonl` (the lanes with their `if:`, the re-check steps, the replay
cases, the gate vectors and the push vectors), written by `lake test -- --write-ci-trigger-golden`.
-/
namespace Fw.Ci.Intent
open Lean Fw.Ops.PathCheck Fw.Ci.Trigger
open Fw.Console.LandSpeed (selected selected_of_mem skip_sound ReadsWithin St)
open Fw.Ci.Verdict (Skip)

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

/-- Two words without the separator $c$: if each, followed by $c$, starts the same text, they are equal.
$$\forall a, b, t, t', c:\ c \notin a \land c \notin b \land a \mathbin{+\!\!+} c :: t = b \mathbin{+\!\!+} c :: t' \Rightarrow a = b$$ -/
theorem sep_inj (a b t t' : List Char) (c : Char) (ha : c ∉ a) (hb : c ∉ b) (h : a ++ c :: t = b ++ c :: t') :
    a = b := by
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
$$M = [\texttt{engine-premises.yml},\ \texttt{sim-speed.yml},\ \texttt{webkit-sim.yml},\ \texttt{wktr-fixtures.yml},\ \texttt{wktr.yml}]$$ -/
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


/-! ## The start decision (round 3: the tip decides on the branch's whole diff against `main`) -/

/-- Does the head commit want the lane? A default lane always; any other lane when the message names it.
$$\forall \ell, m:\ \operatorname{want}(\ell, m) \iff \ell.\mathit{dflt} \lor \operatorname{req}(\ell.n, m)$$ -/
def wanted (l : Lane) (m : String) : Bool := l.byDefault || requested l.name m

/-- The event of a run: a push to `refs/heads/ci/**`, a push to `main` (the only other branch the workflows list), or a
record (a dispatch or a schedule).
$$e \in \{\mathrm{ci},\ \mathrm{main},\ \mathrm{rec}\}$$ -/
inductive Ev where
  | ciPush
  | mainPush
  | record
  deriving DecidableEq, Repr

/-- A `ci/**` push, from GitHub's event name and ref.
$$\forall e, r:\ \operatorname{isCi}(e, r) \iff e = \texttt{push} \land \texttt{refs/heads/ci/} \sqsubseteq_{\mathrm{pre}} r$$ -/
def isCi (event ref : String) : Bool := event == "push" && ref.startsWith "refs/heads/ci/"

/-- The event of a run from GitHub's event name and ref: a `ci/**` push, else any other push (`main`), else a record.
$$\forall e, r:\ \operatorname{ev}(e, r) = \begin{cases} \mathrm{ci} & \operatorname{isCi}(e, r) \\ \mathrm{main} & \text{else if } e = \texttt{push} \\ \mathrm{rec} & \text{otherwise} \end{cases}$$ -/
def evOf (event ref : String) : Ev :=
  if isCi event ref then .ciPush else if event == "push" then .mainPush else .record

/-- The facts the guard reads for one run. `ev`: the event. `msg`: the head commit message. `tip`: the run's commit is
the branch's current tip (`git ls-remote`; a read error counts as the tip). `landed`: the commit is already on `main`.
`diff`: on a `ci/**` push the files changed from the merge-base with `main` to the commit (the whole branch, never
this push alone); on a `main` push the push's own diff. `differs`: the file's content at the commit is not `main`'s.
$$p = (e,\ m,\ \mathit{tip},\ \mathit{land},\ D,\ \delta)$$ (below its fields are written $p.e$, $p.m$, $p.\mathit{tip}$,
$p.\mathit{land}$, $p.D$, $p.\delta$) -/
structure Push where
  ev : Ev
  msg : String
  tip : Bool
  landed : Bool
  diff : List String
  differs : String → Bool

/-- **The guard's decision**: `none` runs the lane's jobs, `some k` skips them for reason $k$. A record runs. A `main`
push runs iff its diff passes the lane's coarse `paths` globs (the rule GitHub applied before round 3). A `ci/**` push
skips, in this order, when the head commit does not want the lane, when the commit is not the branch tip, when it is
already on `main`, and when no file that differs from `main` is an input of the lane; otherwise it runs. Below
$\mathrm{run}$ is `none` and a kind $k$ is `some k`.
$$\forall S, \ell, p:\ \operatorname{dec}(S, \ell, p) = \begin{cases} \mathrm{run} & p.e = \mathrm{rec} \\ \mathrm{run} & p.e = \mathrm{main} \land \operatorname{sel}(\operatorname{push}(\ell.w), p.D) \\ \mathrm{unchanged} & p.e = \mathrm{main} \land \lnot\operatorname{sel}(\operatorname{push}(\ell.w), p.D) \\ \mathrm{unwanted} & p.e = \mathrm{ci} \land \lnot\operatorname{want}(\ell, p.m) \\ \mathrm{stale} & p.e = \mathrm{ci} \land \operatorname{want}(\ell, p.m) \land \lnot p.\mathit{tip} \\ \mathrm{landed} & p.e = \mathrm{ci} \land \operatorname{want}(\ell, p.m) \land p.\mathit{tip} \land p.\mathit{land} \\ \mathrm{unchanged} & p.e = \mathrm{ci} \land \operatorname{want}(\ell, p.m) \land p.\mathit{tip} \land \lnot p.\mathit{land} \land \lnot\operatorname{starts}(\ell.w, S, \operatorname{eff}(p.D, p.\delta)) \\ \mathrm{run} & \text{otherwise} \end{cases}$$ -/
def decision (S : String → List String) (l : Lane) (p : Push) : Option Skip :=
  match p.ev with
  | .record => none
  | .mainPush => if selected (pushPaths l.wf) p.diff then none else some .unchanged
  | .ciPush =>
    if !wanted l p.msg then some .unwanted
    else if !p.tip then some .stale
    else if p.landed then some .landed
    else if !l.wf.starts S (effective p.diff p.differs) then some .unchanged
    else none

/-- The guard starts the lane's jobs iff it decides to run.
$$\forall S, \ell, p:\ \operatorname{start}(S, \ell, p) \iff \operatorname{dec}(S, \ell, p) = \mathrm{none}$$ -/
def start (S : String → List String) (l : Lane) (p : Push) : Bool := decision S l p == none

/-- **A record always runs.** A dispatch or a schedule starts every lane.
$$\forall S, \ell, p:\ p.e = \mathrm{rec} \Rightarrow \operatorname{start}(S, \ell, p)$$ -/
theorem record_always_runs (S : String → List String) (l : Lane) (p : Push) (h : p.ev = .record) :
    start S l p = true := by
  simp [start, decision, h]

/-- **A `main` push keeps the old rule:** it starts the lane iff its diff passes the lane's coarse `paths` globs
(`Trigger.pushPaths`, the list GitHub's `paths` filter used before round 3).
$$\forall S, \ell, p:\ p.e = \mathrm{main} \Rightarrow \bigl(\operatorname{start}(S, \ell, p) \iff \operatorname{sel}(\operatorname{push}(\ell.w), p.D)\bigr)$$ -/
theorem main_keeps_paths_rule (S : String → List String) (l : Lane) (p : Push) (h : p.ev = .mainPush) :
    start S l p = true ↔ selected (pushPaths l.wf) p.diff = true := by
  cases hs : selected (pushPaths l.wf) p.diff <;> simp [start, decision, h, hs]

/-- **The decision on a `ci/**` push, unfolded.**
$$\forall S, \ell, p:\ p.e = \mathrm{ci} \Rightarrow \Bigl(\operatorname{start}(S, \ell, p) \iff \operatorname{want}(\ell, p.m) \land p.\mathit{tip} \land \lnot p.\mathit{land} \land \exists x \in p.D:\ p.\delta(x) \land \mathrm{in}(\mathrm{parse}(\operatorname{expand}(S, \ell.w.G)), x)\Bigr)$$ -/
theorem start_ci_iff (S : String → List String) (l : Lane) (p : Push) (hci : p.ev = .ciPush) :
    start S l p = true ↔ wanted l p.msg = true ∧ p.tip = true ∧ p.landed = false ∧
      ∃ x ∈ p.diff, p.differs x = true ∧ inScope (parseScope (expand S l.wf.inputs)) x = true := by
  rw [← starts_iff]
  cases hw : wanted l p.msg <;> cases ht : p.tip <;> cases hl : p.landed <;>
    cases hs : l.wf.starts S (effective p.diff p.differs) <;> simp [start, decision, hci, hw, ht, hl, hs]

/-- **The tip starts every requested lane that is due.** On a `ci/**` push, if the head commit names the lane, the
commit is the branch tip and not on `main`, and some file that differs from `main` on the branch is an input of the
lane, the lane starts, whatever earlier pushes did.
$$\forall S, \ell, p:\ p.e = \mathrm{ci} \land \operatorname{req}(\ell.n, p.m) \land p.\mathit{tip} \land \lnot p.\mathit{land} \land \operatorname{starts}(\ell.w, S, \operatorname{eff}(p.D, p.\delta)) \Rightarrow \operatorname{start}(S, \ell, p)$$ -/
theorem tip_starts (S : String → List String) (l : Lane) (p : Push) (hci : p.ev = .ciPush)
    (hr : requested l.name p.msg = true) (ht : p.tip = true) (hl : p.landed = false)
    (hs : l.wf.starts S (effective p.diff p.differs) = true) : start S l p = true := by
  have hw : wanted l p.msg = true := by simp [wanted, hr]
  simp [start, decision, hci, hw, ht, hl, hs]

/-- **The tip always checks the Lean proofs when they are due.** On a `ci/**` push, a default lane (`lean`) starts
whenever the commit is the branch tip, not on `main`, and some file that differs from `main` on the branch is one of
its inputs, whatever lanes the head commit names (none, `[ci:none]`, or others).
$$\forall S, \ell, p:\ p.e = \mathrm{ci} \land \ell.\mathit{dflt} \land p.\mathit{tip} \land \lnot p.\mathit{land} \land \operatorname{starts}(\ell.w, S, \operatorname{eff}(p.D, p.\delta)) \Rightarrow \operatorname{start}(S, \ell, p)$$ -/
theorem tip_lean_always (S : String → List String) (l : Lane) (p : Push) (hci : p.ev = .ciPush)
    (hd : l.byDefault = true) (ht : p.tip = true) (hl : p.landed = false)
    (hs : l.wf.starts S (effective p.diff p.differs) = true) : start S l p = true := by
  have hw : wanted l p.msg = true := by simp [wanted, hd]
  simp [start, decision, hci, hw, ht, hl, hs]

/-- **The tip's decision has no history.** Two `ci/**` pushes with the same message, tip and landed flags, and the
same files that differ from `main` on the branch, get the same decision for every lane: what earlier pushes changed,
reverted or ran does not matter (the reviewer's revert sequence: push A changes X and Y, push B reverts X; B still
starts lean because Y differs from `main`).
$$\forall S, \ell, p, q:\ p.e = q.e = \mathrm{ci} \land p.m = q.m \land p.\mathit{tip} = q.\mathit{tip} \land p.\mathit{land} = q.\mathit{land} \land \operatorname{eff}(p.D, p.\delta) = \operatorname{eff}(q.D, q.\delta) \Rightarrow \operatorname{dec}(S, \ell, p) = \operatorname{dec}(S, \ell, q)$$ -/
theorem tip_history_free (S : String → List String) (l : Lane) (p q : Push) (hp : p.ev = .ciPush)
    (hq : q.ev = .ciPush) (hm : p.msg = q.msg) (ht : p.tip = q.tip) (hl : p.landed = q.landed)
    (he : effective p.diff p.differs = effective q.diff q.differs) : decision S l p = decision S l q := by
  simp only [decision, hp, hq, hm, ht, hl, he]

/-- **A commit that is not the tip starts no job.** On a `ci/**` push, if a newer push moved the branch tip before the
guard read it, the guard skips the lane as stale (when the head commit wants it; otherwise as unwanted).
$$\forall S, \ell, p:\ p.e = \mathrm{ci} \land \lnot p.\mathit{tip} \Rightarrow \lnot\operatorname{start}(S, \ell, p)$$ -/
theorem stale_guard_never_starts (S : String → List String) (l : Lane) (p : Push) (hci : p.ev = .ciPush)
    (ht : p.tip = false) : start S l p = false := by
  cases hw : wanted l p.msg <;> simp [start, decision, hci, hw, ht]

/-- **No unrequested start.** On a `ci/**` push a lane starts only if the head commit names it or the lane is a
default lane.
$$\forall S, \ell, p:\ p.e = \mathrm{ci} \land \operatorname{start}(S, \ell, p) \Rightarrow \operatorname{req}(\ell.n, p.m) \lor \ell.\mathit{dflt}$$ -/
theorem no_unrequested_start (S : String → List String) (l : Lane) (p : Push) (hci : p.ev = .ciPush)
    (h : start S l p = true) : requested l.name p.msg = true ∨ l.byDefault = true := by
  have hw := ((start_ci_iff S l p hci).mp h).1
  simp only [wanted, Bool.or_eq_true] at hw
  exact hw.symm

/-- **A landed commit starts no job** on a `ci/**` push.
$$\forall S, \ell, p:\ p.e = \mathrm{ci} \land p.\mathit{land} \Rightarrow \lnot\operatorname{start}(S, \ell, p)$$ -/
theorem landed_never_runs_heavy (S : String → List String) (l : Lane) (p : Push) (hci : p.ev = .ciPush)
    (h : p.landed = true) : start S l p = false := by
  cases hw : wanted l p.msg <;> cases ht : p.tip <;> simp [start, decision, hci, hw, ht, h]

/-- **The default starts no macOS lane.** On a `ci/**` push whose head commit carries no intent, no lane of the
table that starts holds a macOS job.
$$\forall S, p, \ell \in L:\ p.e = \mathrm{ci} \land \lnot\operatorname{intent}(p.m) \land \operatorname{start}(S, \ell, p) \Rightarrow \ell.\mathit{dflt} \land \lnot \ell.\mathit{mac}$$ -/
theorem default_no_macos (S : String → List String) (p : Push) (l : Lane) (hl : l ∈ lanes) (hci : p.ev = .ciPush)
    (hi : intent p.msg = false) (h : start S l p = true) : l.byDefault = true ∧ l.macos = false := by
  rcases no_unrequested_start S l p hci h with h1 | hd
  · rw [intent_of_requested _ _ h1] at hi; exact Bool.noConfusion hi
  · exact ⟨hd, default_lane_not_macos l hl hd⟩

/-- **A run whose lane inputs equal `main`'s answers like `main`.** If the lane's result depends only on its expanded
inputs and no effective file of the branch is one of them, the result on the commit equals the result on `main`'s
content (a skip `unchanged` loses nothing).
$$\forall S, \ell, X, \mathit{run}, \sigma, \sigma':\ \mathrm{RW}(\mathit{run}, \operatorname{expand}(S, \ell.w.G)) \land \lnot\operatorname{starts}(\ell.w, S, X) \land (\forall q \notin X:\ \sigma(q) = \sigma'(q)) \Rightarrow \mathit{run}(\sigma) = \mathit{run}(\sigma')$$ -/
theorem unchanged_replays {R} (S : String → List String) (l : Lane) (eff : List String) (run : St → R)
    (hrw : ReadsWithin run (expand S l.wf.inputs)) (hs : l.wf.starts S eff = false) (σ σ' : St)
    (hd : ∀ q, q ∉ eff → σ q = σ' q) : run σ = run σ' :=
  skipped_replays S l.wf eff run hrw hs σ σ' hd

/-! ## The guard job's `if:` -/

/-- The `if:` of the guard job, as a Boolean: true unless a `ci/**` push's head commit does not want the lane. A
default lane always passes; any other lane only when the message names it.
$$\forall \ell, c, m:\ \operatorname{gate}(\ell, c, m) \iff \lnot c \lor \ell.\mathit{dflt} \lor \operatorname{req}(\ell.n, m)$$ -/
def gate (l : Lane) (ci : Bool) (m : String) : Bool := !ci || l.byDefault || requested l.name m

/-- **The `if:` is exactly "not a ci push, or wanted".**
$$\forall \ell, c, m:\ \operatorname{gate}(\ell, c, m) = \lnot c \lor \operatorname{want}(\ell, m)$$ -/
theorem gate_eq (l : Lane) (ci : Bool) (m : String) : gate l ci m = (!ci || wanted l m) := by
  simp [gate, wanted, Bool.or_assoc]

/-- **The `if:` never drops a start.** Since round 3 no workflow has a `paths` filter, so every push creates a run of
every lane; the guard then runs whenever the guard script would start the lane.
$$\forall S, \ell, p:\ \operatorname{start}(S, \ell, p) \Rightarrow \operatorname{gate}(\ell, p.e = \mathrm{ci}, p.m)$$ -/
theorem start_gate (S : String → List String) (l : Lane) (p : Push) (h : start S l p = true) :
    gate l (p.ev == .ciPush) p.msg = true := by
  rw [gate_eq]
  cases hci : p.ev
  · simpa using ((start_ci_iff S l p hci).mp h).1
  · rfl
  · rfl

/-- A `contains` call on the head commit message, as GitHub expression text.
$$\forall s:\ \operatorname{has}(s) = \texttt{contains(github.event.head\_commit.message, '}s\texttt{')}$$ -/
def containsExpr (s : String) : String := "contains(github.event.head_commit.message, '" ++ s ++ "')"

/-- The "not a ci push" part of the `if:`.
$$\mathrm{rec} = \texttt{github.event\_name != 'push' || !startsWith(github.ref, 'refs/heads/ci/')}$$ -/
def recordExpr : String := "github.event_name != 'push' || !startsWith(github.ref, 'refs/heads/ci/')"

/-- The guard job's `if:` text: `gate` written as a GitHub expression. A default lane has no `if:` at all (the empty
text: a job without `if:` always runs, and actionlint rejects a constant condition).
$$\forall \ell:\ \operatorname{ifExpr}(\ell) = \begin{cases} \texttt{""} & \ell.\mathit{dflt} \\ \texttt{\$\{\{ } \mathrm{rec} \texttt{ || } \operatorname{has}(\operatorname{tok}(\ell.n)) \texttt{ \}\}} & \lnot\ell.\mathit{dflt} \end{cases}$$ -/
def ifExpr (l : Lane) : String :=
  if l.byDefault then ""
  else "${{ " ++ recordExpr ++ " || " ++ containsExpr (String.ofList (tok l.name)) ++ " }}"

#guard ifExpr (laneOf ⟨"wktr.yml", [], []⟩) ==
  "${{ github.event_name != 'push' || !startsWith(github.ref, 'refs/heads/ci/') || contains(github.event.head_commit.message, '[ci:wktr]') }}"
#guard ifExpr (laneOf ⟨"lean.yml", [], []⟩) == ""

/-! ## The heavy job's tip re-check (round 3)

Every heavy job starts with two steps (written by `scripts/ci-paths.mjs`): `tip re-check` (id `tip`, only on a `ci/**`
push) reads the branch tip with `git ls-remote` and writes `tip=false` when another commit is the tip (a read error
writes `tip=true`: fail open); `stale: ...` (id `stale`) runs only on `tip=false` and exits 1. GitHub's step rules
(github/docs@dae83f7, `content/actions/reference/workflows-and-actions/expressions.md`: a step without a status check
function gets `success()`, which is false once an earlier step failed; `contexts.md`: `steps.<id>.outcome` is one of
`success`, `failure`, `cancelled`, `skipped`) then stop every later step: a plain step sees the failure, and every step
whose `if:` holds a status function carries the conjunct `steps.stale.outcome == 'skipped'` (CONFIRMED from the docs;
MEASURED in the research note). The verdict of such a job is `not-run` (`Fw.Ci.Verdict.stale_never_pass`). -/

/-- Does the `stale:` step run? Only on a `ci/**` push whose job read another commit as the tip (`some false`; `none`:
the re-check step did not write an answer).
$$\forall e, t:\ \operatorname{staleRuns}(e, t) \iff e = \mathrm{ci} \land t = \mathrm{some}(\bot)$$ -/
def staleRuns (ev : Ev) (tipAtJob : Option Bool) : Bool := ev == .ciPush && tipAtJob == some false

/-- A later step's kind: `plain` (its `if:`, if any, has no status function, so GitHub adds `success()`) or `status`
(its `if:` holds `always()`, `failure()`, `cancelled()` or `success()`).
$$c \in \{\mathrm{plain},\ \mathrm{status}\}$$ -/
inductive StepKind where
  | plain
  | status
  deriving DecidableEq, Repr

/-- Does a later step of a heavy job run? `okBefore`: no step before it (other than `stale:`) failed; `cond`: its own
`if:` without the stale conjunct. A plain step needs `okBefore`, its condition and no failed `stale:` step; a status step
needs its condition and the conjunct (`stale:` skipped).
$$\forall e, t, c, o, \phi:\ \operatorname{runs}(e, t, c, o, \phi) = \begin{cases} o \land \phi \land \lnot\operatorname{staleRuns}(e, t) & c = \mathrm{plain} \\ \phi \land \lnot\operatorname{staleRuns}(e, t) & c = \mathrm{status} \end{cases}$$ -/
def stepRuns (ev : Ev) (tipAtJob : Option Bool) (c : StepKind) (okBefore cond : Bool) : Bool :=
  match c with
  | .plain => okBefore && cond && !staleRuns ev tipAtJob
  | .status => cond && !staleRuns ev tipAtJob

/-- **A stale run never works.** On a `ci/**` push, once a heavy job's re-check reads another commit as the branch
tip, no later step of the job runs, whatever its kind and condition.
$$\forall c, o, \phi:\ \operatorname{runs}(\mathrm{ci}, \mathrm{some}(\bot), c, o, \phi) = \bot$$ -/
theorem stale_never_works (c : StepKind) (okBefore cond : Bool) :
    stepRuns .ciPush (some false) c okBefore cond = false := by
  cases c <;> simp [stepRuns, staleRuns]

/-- **The re-check changes nothing at the tip or off `ci/**`.** When the `stale:` step does not run, every later step
runs exactly as it did before round 3.
$$\forall e, t, o, \phi:\ \lnot\operatorname{staleRuns}(e, t) \Rightarrow \operatorname{runs}(e, t, \mathrm{plain}, o, \phi) = (o \land \phi) \land \operatorname{runs}(e, t, \mathrm{status}, o, \phi) = \phi$$ -/
theorem tip_job_unchanged (ev : Ev) (t : Option Bool) (okBefore cond : Bool) (h : staleRuns ev t = false) :
    stepRuns ev t .plain okBefore cond = (okBefore && cond) ∧ stepRuns ev t .status okBefore cond = cond := by
  simp [stepRuns, h]

#guard stepRuns .ciPush (some true) .plain true true && stepRuns .mainPush (some false) .status false true
#guard !stepRuns .ciPush (some false) .status true true && stepRuns .ciPush none .plain true true

/-- The re-check step's name and `if:` (only on a `ci/**` push).
$$\mathrm{tipName} = \texttt{tip re-check},\quad \mathrm{tipIf} = \texttt{github.event\_name == 'push' \&\& startsWith(github.ref, 'refs/heads/ci/')}$$ -/
def tipName : String := "tip re-check"

@[inherit_doc tipName]
def tipIf : String := "github.event_name == 'push' && startsWith(github.ref, 'refs/heads/ci/')"

/-- The stale step's name (it starts with `Fw.Ci.Verdict.staleStep`, which the wait reads) and its `if:`.
$$\mathrm{staleName} = \mathrm{staleStep} \mathbin{+\!\!+} \texttt{ a newer push is the branch tip},\quad \mathrm{staleIf} = \texttt{steps.tip.outputs.tip == 'false'}$$ -/
def staleName : String := Fw.Ci.Verdict.staleStep ++ " a newer push is the branch tip"

@[inherit_doc staleName]
def staleIf : String := "steps.tip.outputs.tip == 'false'"

/-- The conjunct every status-function step of a heavy job carries.
$$\mathrm{conj} = \texttt{steps.stale.outcome == 'skipped'}$$ -/
def workConj : String := "steps.stale.outcome == 'skipped'"

/-! ## Concurrency (round 3: none on `ci/**`) -/

/-- The concurrency group of a heavy job `j` of lane $\ell$ (`j` is filled in by `scripts/ci-paths.mjs`): on a `main`
push one group per lane, ref, job and matrix leg (main runs queue, as before); on a `ci/**` push, a dispatch or a
schedule the run's own id, so no two runs share a group and nothing is cancelled or replaced while pending
(`Fw.Ci.Cancel.ci_never_cancelled`). No job sets `cancel-in-progress`.
$$\forall \ell, j:\ \operatorname{grp}(\ell, j) = \texttt{ci-lane:} \mathbin{+\!\!+} \ell.n \mathbin{+\!\!+} \texttt{:\$\{\{ github.event\_name == 'push' \&\& !startsWith(github.ref, 'refs/heads/ci/') \&\& github.ref || github.run\_id \}\}:} \mathbin{+\!\!+} j \mathbin{+\!\!+} \texttt{:\$\{\{ strategy.job-index \}\}}$$ -/
def groupExpr (l : Lane) (job : String) : String :=
  "ci-lane:" ++ l.name ++ String.singleton ':' ++
    ("${{ github.event_name == 'push' && !startsWith(github.ref, 'refs/heads/ci/') && github.ref || github.run_id }}:" ++
      job ++ ":${{ strategy.job-index }}")

/-- **Two lanes never share a group.** For valid lane names, equal groups (same job) mean the same lane.
$$\forall \ell, \ell', j:\ \operatorname{valid}(\ell.n) \land \operatorname{valid}(\ell'.n) \land \operatorname{grp}(\ell, j) = \operatorname{grp}(\ell', j) \Rightarrow \ell.n = \ell'.n$$ -/
theorem group_lane_inj (l l' : Lane) (job : String) (hl : validName l.name = true) (hl' : validName l'.name = true)
    (h : groupExpr l job = groupExpr l' job) : l.name = l'.name := by
  have nc : ∀ (n : String), validName n = true → ':' ∉ n.toList := by
    intro n hn hm
    simp only [validName, Bool.and_eq_true, List.all_eq_true] at hn
    exact absurd (hn.2 _ hm) (by decide)
  have h2 := congrArg String.toList h
  simp only [groupExpr, String.toList_append, String.toList_singleton, List.append_assoc, List.singleton_append,
    List.append_cancel_left_eq] at h2
  exact String.toList_inj.mp (sep_inj _ _ _ _ ':' (nc _ hl) (nc _ hl') h2)

/-! ## The push preview (round 4: `fw ci push` refuses a partial request) -/

/-- One lane of the push preview: whether the agent named it in `--lanes` (a default lane it did not name: `false`)
and whether its guard would start it on this push, the pushed commit being the tip (`start`).
$$p = (\mathit{named},\ \mathit{run})$$ -/
structure Planned where
  named : Bool
  run : Bool
  deriving DecidableEq, Repr

/-- **Whether `fw ci push` pushes.** Every named lane would start; or, with `--partial` ($\pi$), at least one named lane
would. A request that names no lane (`none`) satisfies the first disjunct, so it always pushes.
$$\forall \pi, P:\ \operatorname{pushOk}(\pi, P) \iff (\forall p \in P:\ p.\mathit{named} \Rightarrow p.\mathit{run}) \lor \bigl(\pi \land \exists p \in P:\ p.\mathit{named} \land p.\mathit{run}\bigr)$$ -/
def pushOk (part : Bool) (ps : List Planned) : Bool :=
  ps.all (fun p => !p.named || p.run) || (part && ps.any fun p => p.named && p.run)

/-- **Without `--partial`, a push starts every named lane.** If the push goes ahead, every lane the agent named would
start, so no named lane is skipped as unchanged or landed and the wait is not doomed to *not run*.
$$\forall P:\ \operatorname{pushOk}(\bot, P) \Rightarrow \forall p \in P:\ p.\mathit{named} \Rightarrow p.\mathit{run}$$ -/
theorem push_full_starts (ps : List Planned) (h : pushOk false ps = true) :
    ∀ p ∈ ps, p.named = true → p.run = true := by
  intro p hp hn
  simp only [pushOk, Bool.false_and, Bool.or_false, List.all_eq_true] at h
  have := h p hp
  simp [hn] at this
  exact this

/-- **A named lane that would be skipped refuses the push** (without `--partial`).
$$\forall P, p:\ p \in P \land p.\mathit{named} \land \lnot p.\mathit{run} \Rightarrow \lnot\operatorname{pushOk}(\bot, P)$$ -/
theorem skipped_named_refused (ps : List Planned) (p : Planned) (hp : p ∈ ps) (hn : p.named = true)
    (hr : p.run = false) : pushOk false ps = false := by
  cases h : pushOk false ps
  · rfl
  · have := push_full_starts ps h p hp hn
    rw [hr] at this
    exact absurd this (by decide)

/-- **With `--partial`, a push starts at least one named lane** unless no lane is named.
$$\forall P:\ \operatorname{pushOk}(\top, P) \land (\exists p \in P:\ p.\mathit{named}) \Rightarrow \exists p \in P:\ p.\mathit{named} \land p.\mathit{run}$$ -/
theorem partial_starts_one (ps : List Planned) (h : pushOk true ps = true) (hn : ∃ p ∈ ps, p.named = true) :
    ∃ p ∈ ps, p.named = true ∧ p.run = true := by
  simp only [pushOk, Bool.true_and, Bool.or_eq_true, List.all_eq_true, List.any_eq_true, Bool.and_eq_true] at h
  rcases h with h | h
  · obtain ⟨p, hp, hpn⟩ := hn
    have := h p hp
    simp [hpn] at this
    exact ⟨p, hp, hpn, this⟩
  · exact h

#guard pushOk false [⟨true, true⟩, ⟨false, false⟩]
#guard !pushOk false [⟨true, true⟩, ⟨true, false⟩]
#guard pushOk true [⟨true, true⟩, ⟨true, false⟩]
#guard !pushOk true [⟨true, false⟩, ⟨false, true⟩]
#guard pushOk false [⟨false, false⟩]
#guard pushOk false []

/-- Every preview of at most 3 lanes: each list over $O = [(\bot,\bot), (\bot,\top), (\top,\bot), (\top,\top)]$ of
length 0 to 3 exactly once, by length, then by prefix, then by the last element's place in $O$ (85 lists).
$$\mathrm{plans} = P_0 \mathbin{+\!\!+} P_1 \mathbin{+\!\!+} P_2 \mathbin{+\!\!+} P_3, \quad P_0 = [[\,]],\ P_{k+1} = [\, xs \mathbin{+\!\!+} [o] : xs \in P_k,\ o \in O \,]$$ -/
def plans : List (List Planned) :=
  let one : List Planned := [⟨false, false⟩, ⟨false, true⟩, ⟨true, false⟩, ⟨true, true⟩]
  let ext (ps : List (List Planned)) := ps.flatMap fun xs => one.map fun p => xs ++ [p]
  let l1 := ext [[]]
  let l2 := ext l1
  [[]] ++ l1 ++ l2 ++ ext l2

#guard plans.length == 85

/-- The push vectors: for each $\pi$ and each plan, the value of `pushOk` (`ci-push.mjs` checks its own rule on them).
$$\mathrm{pushVec} = [\, (\pi, P, \operatorname{pushOk}(\pi, P)) : \pi \in [\bot, \top],\ P \in \mathrm{plans} \,]$$ -/
def pushVectors : List (Bool × List Planned × Bool) :=
  [false, true].flatMap fun part => plans.map fun ps => (part, ps, pushOk part ps)

/-! ## Replay cases and golden (`packages/contracts/golden/ci/intent.jsonl`) -/

/-- The decision of every lane under the sample cones (`Trigger.sampleCone`), as (file, tag) with tag `run` or the skip
tag (written $\operatorname{tag}$, with $\operatorname{tag}(\mathrm{none}) = \texttt{run}$); a path in `merged` already has
`main`'s content.
$$\forall e, m, D, M, t, \mathit{land}:\ \operatorname{decI}(e, m, D, M, t, \mathit{land}) = [\, (\ell.w.\mathit{file},\ \operatorname{tag}(\operatorname{dec}(S_{\mathrm{sample}}, \ell, (e, m, t, \mathit{land}, D, \lambda x.\ x \notin M)))) : \ell \in L \,]$$ -/
def decideIntent (ev : Ev) (msg : String) (diff merged : List String) (tip landed : Bool) : List (String × String) :=
  lanes.map fun l => (l.wf.file,
    match decision (setMap sampleCone) l ⟨ev, msg, tip, landed, diff, (fun x => !merged.contains x)⟩ with
    | none => "run"
    | some k => k.tag)

/-- The files of the lanes a run starts (`decideIntent` with tag `run`).
$$\forall e, m, D, M, t, \mathit{land}:\ \operatorname{runI}(e, m, D, M, t, \mathit{land}) = [\, f : (f, \texttt{run}) \in \operatorname{decI}(e, m, D, M, t, \mathit{land}) \,]$$ -/
def runIntent (ev : Ev) (msg : String) (diff merged : List String) (tip landed : Bool) : List String :=
  ((decideIntent ev msg diff merged tip landed).filter (·.2 == "run")).map (·.1)

/-- The files of the lanes whose guard job's `if:` passes.
$$\forall c, m:\ \operatorname{gated}(c, m) = [\, \ell.w.\mathit{file} : \ell \in L,\ \operatorname{gate}(\ell, c, m) \,]$$ -/
def gatedBy (ci : Bool) (msg : String) : List String := (lanes.filter fun l => gate l ci msg).map (·.wf.file)

-- no intent: only lean, even though the module is in the fwcore cone of 8 workflows
#guard runIntent .ciPush "fix x" ["lean/Fw/Wire.lean"] [] true false == ["lean.yml"]
#guard runIntent .ciPush "fix x\n\n[ci:wktr]" ["lean/Fw/Wire.lean"] [] true false == ["lean.yml", "wktr.yml"]
#guard runIntent .ciPush "[ci:none]" ["lean/Fw/Wire.lean"] [] true false == ["lean.yml"]
#guard runIntent .ciPush "[ci:wktr]" ["docs/x.md"] [] true false == []
-- the reviewer's revert sequence: A changes X and Y; B reverts X, so the branch differs from main in Y only
#guard runIntent .ciPush "a" ["lean/Fw/Wire.lean", "lean/Fw/Ops/Wire.lean"] [] true false == ["lean.yml"]
#guard (decideIntent .ciPush "a" ["lean/Fw/Wire.lean", "lean/Fw/Ops/Wire.lean"] [] false false).lookup "lean.yml" ==
  some "stale"
#guard runIntent .ciPush "b" ["lean/Fw/Ops/Wire.lean"] [] true false == ["lean.yml"]
#guard (decideIntent .ciPush "b2" [] [] true false).lookup "lean.yml" == some "unchanged"
-- a docs-only tip on a branch whose Lean differs from main: lean runs
#guard runIntent .ciPush "docs" ["docs/x.md", "lean/Fw/Wire.lean"] [] true false == ["lean.yml"]
#guard (decideIntent .ciPush "[ci:lean]" ["lean/Fw/Wire.lean"] [] true true).lookup "lean.yml" == some "landed"
#guard (decideIntent .ciPush "x" ["lean/Fw/Wire.lean"] [] true false).lookup "wktr.yml" == some "unwanted"
#guard runIntent .record "" [] [] true false == lanes.map (·.wf.file)
#guard runIntent .mainPush "" ["docs/x.md"] [] true false == []
#guard (runIntent .mainPush "" ["lean/Fw/Wire.lean"] [] true false).contains "lean.yml"
#guard gatedBy true "x" == ["lean.yml"]
#guard evOf "push" "refs/heads/ci/x" == .ciPush && evOf "push" "refs/heads/main" == .mainPush &&
  evOf "workflow_dispatch" "refs/heads/ci/x" == .record

/-- The event's name in the golden. $$\mathrm{ci} \mapsto \texttt{ci},\ \mathrm{main} \mapsto \texttt{main},\ \mathrm{rec} \mapsto \texttt{record}$$ -/
def Ev.tag : Ev → String
  | .ciPush => "ci"
  | .mainPush => "main"
  | .record => "record"

/-- A replay case: name, event, head message, branch diff, paths that equal `main`, tip, landed.
$$\mathrm{cases} = [\, (n, e, m, D, M, t, \mathit{land}) \,]$$ -/
def cases : List (String × Ev × String × List String × List String × Bool × Bool) := [
  ("no intent, a fwcore module: only the default lane", .ciPush, "fix x", ["lean/Fw/Wire.lean"], [], true, false),
  ("no intent, a wktr file: nothing (wktr is not a default lane)", .ciPush, "fix x",
    ["packages/measure-wktr/src/a.mjs"], [], true, false),
  ("intent for one macOS lane: it and lean (lean inputs differ)", .ciPush, "fix x\n\n[ci:wktr]",
    ["lean/Fw/Wire.lean", "packages/measure-wktr/src/a.mjs"], [], true, false),
  ("a longer name is not the shorter lane", .ciPush, "[ci:wktr-fixtures]", ["lean/Fw/Wire.lean"], [], true, false),
  ("two lanes, upper case", .ciPush, "[CI:Lean] [ci:breakpoint-gate]", ["lean/Fw/Wire.lean"], [], true, false),
  ("intent for nothing: lean still checks its inputs", .ciPush, "handoff [ci:none]", ["lean/Fw/Wire.lean"], [], true,
    false),
  ("intent for nothing, no lean input differs: nothing", .ciPush, "handoff [ci:none]", ["docs/x.md"], [], true, false),
  ("requested lane whose inputs equal main: skipped unchanged", .ciPush, "[ci:wktr]", ["docs/x.md"], [], true, false),
  ("a merge of main with intent: the merged file equals main", .ciPush, "[ci:lean]", ["lean/Fw/Wire.lean"],
    ["lean/Fw/Wire.lean"], true, false),
  ("revert sequence, push A (changes X and Y) at the tip", .ciPush, "A",
    ["lean/Fw/Wire.lean", "lean/Fw/Ops/Wire.lean"], [], true, false),
  ("revert sequence, push A after B moved the tip: stale", .ciPush, "A",
    ["lean/Fw/Wire.lean", "lean/Fw/Ops/Wire.lean"], [], false, false),
  ("revert sequence, push B (reverts X): Y still differs, lean runs", .ciPush, "B", ["lean/Fw/Ops/Wire.lean"], [],
    true, false),
  ("revert sequence, push B with main's X merged: lean runs", .ciPush, "B",
    ["lean/Fw/Wire.lean", "lean/Fw/Ops/Wire.lean"], ["lean/Fw/Wire.lean"], true, false),
  ("revert sequence, push C reverts Y too: nothing differs, lean unchanged", .ciPush, "C", [], [], true, false),
  ("a docs-only tip on a branch whose Lean differs: lean runs", .ciPush, "docs", ["docs/x.md", "lean/Fw/Wire.lean"],
    [], true, false),
  ("a requested lane on a stale commit: stale", .ciPush, "[ci:wktr]", ["packages/measure-wktr/src/a.mjs"], [], false,
    false),
  ("landed", .ciPush, "[ci:lean]", ["lean/Fw/Wire.lean"], [], true, true),
  ("a main push of a Lean file: the coarse paths rule", .mainPush, "", ["lean/Fw/Wire.lean"], [], true, false),
  ("a main push of docs only: nothing", .mainPush, "", ["docs/x.md"], [], true, false),
  ("a record (dispatch, schedule) runs every lane", .record, "", [], [], true, false)]

/-- The event and ref pairs of the gate vectors: a `ci/**` push, a main push, a dispatch and a schedule.
$$E = [(\texttt{push}, \texttt{refs/heads/ci/x}),\ (\texttt{push}, \texttt{refs/heads/main}),\ (\texttt{workflow\_dispatch}, \texttt{refs/heads/ci/x}),\ (\texttt{schedule}, \texttt{refs/heads/main})]$$ -/
def gateEnvs : List (String × String) :=
  [("push", "refs/heads/ci/x"), ("push", "refs/heads/main"), ("workflow_dispatch", "refs/heads/ci/x"),
    ("schedule", "refs/heads/main")]

/-- The messages of the gate vectors: no token, `[ci:none]`, near misses, and every lane's token (also upper case).
$$\mathrm{msgs} = [\texttt{fix x},\ \texttt{[ci:none]},\ \texttt{[ci: lean]},\ \texttt{[ci:wktr-fixtures]}] \mathbin{+\!\!+} [\operatorname{tok}(\ell.n),\ \operatorname{upper}(\operatorname{tok}(\ell.n)) : \ell \in L]$$ -/
def gateMsgs : List String :=
  ["fix x", "[ci:none]", "[ci: lean]", "[ci:wktr-fixtures]"] ++
    lanes.flatMap fun l => [String.ofList (tok l.name), (String.ofList (tok l.name)).toUpper]

/-- The gate vectors of one lane: for every event, ref and message, the value of `gate`. A test evaluates the
workflow's own `if:` text on each and compares.
$$\forall \ell:\ \operatorname{vec}(\ell) = [\, (e, r, m, \operatorname{gate}(\ell, \operatorname{isCi}(e, r), m)) : (e, r) \in E,\ m \in \mathrm{msgs} \,]$$ -/
def gateVectors (l : Lane) : List (String × String × String × Bool) :=
  gateEnvs.flatMap fun (e, r) => gateMsgs.map fun m => (e, r, m, gate l (isCi e r) m)

/-- The lanes line: every lane with its name, token, macOS flag, default flag, the guard `if:` text and the
concurrency group of its heavy jobs (`<job>` stands for the job id); also the guard's decision step names
(`Fw.Ci.Verdict.decisionStep`), the skip tags, and the re-check steps every heavy job starts with.
$$\operatorname{lanesLine} = \{\texttt{kind}: \texttt{lanes},\ \texttt{prefix}: \mathrm{pre},\ \texttt{decision}: \{\texttt{run}, \texttt{skip}\},\ \texttt{skips}: [\operatorname{tag}(k) : k \in K],\ \texttt{recheck}: \{\mathrm{tipName}, \mathrm{tipIf}, \mathrm{staleName}, \mathrm{staleIf}, \mathrm{conj}\},\ \texttt{lanes}: [\,\{\texttt{file}, \texttt{name}, \texttt{token}, \texttt{macos}, \texttt{byDefault}, \texttt{if}, \texttt{group}\} : \ell \in L\,]\}$$ -/
def lanesLine : Json :=
  Json.mkObj [("kind", "lanes"), ("prefix", .str (String.ofList tokPrefix)),
    ("decision", Json.mkObj [("run", .str (Fw.Ci.Verdict.decisionStep true)),
      ("skip", .str (Fw.Ci.Verdict.decisionStep false))]),
    ("skips", strs (Fw.Ci.Verdict.Skip.all.map (·.tag))),
    ("recheck", Json.mkObj [("tipName", .str tipName), ("tipIf", .str tipIf), ("staleName", .str staleName),
      ("staleIf", .str staleIf), ("conj", .str workConj)]),
    ("lanes", .arr (lanes.map fun l => Json.mkObj [("file", .str l.wf.file), ("name", .str l.name),
      ("token", .str (String.ofList (tok l.name))), ("macos", .bool l.macos), ("byDefault", .bool l.byDefault),
      ("if", .str (ifExpr l)), ("group", .str (groupExpr l "<job>"))]).toArray)]

/-- One gate line: a lane's gate vectors.
$$\forall \ell:\ \operatorname{gateLine}(\ell) = \{\texttt{kind}: \texttt{gate},\ \texttt{file}: \ell.w.\mathit{file},\ \texttt{rows}: \operatorname{vec}(\ell)\}$$ -/
def gateLine (l : Lane) : Json :=
  Json.mkObj [("kind", "gate"), ("file", .str l.wf.file),
    ("rows", .arr ((gateVectors l).map fun (e, r, m, g) => Json.arr #[.str e, .str r, .str m, .bool g]).toArray)]

/-- One replay line with every lane's decision tag, the started and the gated lanes.
$$\operatorname{caseLine}(n, e, m, D, M, t, \mathit{land}) = \{\dots,\ \texttt{decisions}: \operatorname{decI}(e, m, D, M, t, \mathit{land}),\ \texttt{started}: \operatorname{runI}(e, m, D, M, t, \mathit{land}),\ \texttt{gated}: \operatorname{gated}(e = \mathrm{ci}, m)\}$$ -/
def caseLine (k : String × Ev × String × List String × List String × Bool × Bool) : Json :=
  let (n, ev, msg, diff, merged, tip, landed) := k
  Json.mkObj [("kind", "case"), ("name", .str n), ("event", .str ev.tag), ("msg", .str msg), ("diff", strs diff),
    ("merged", strs merged), ("tip", .bool tip), ("landed", .bool landed),
    ("cones", Json.mkObj [("Main", strs (sampleCone "Main")), ("BreakgenMain", strs (sampleCone "BreakgenMain"))]),
    ("decisions", Json.mkObj ((decideIntent ev msg diff merged tip landed).map fun (f, t) => (f, Json.str t))),
    ("started", strs (runIntent ev msg diff merged tip landed)), ("gated", strs (gatedBy (ev == .ciPush) msg))]

/-- The push line: the push vectors, each row `[part, [[named, run]], ok]`.
$$\operatorname{pushLine} = \{\texttt{kind}: \texttt{push},\ \texttt{rows}: \mathrm{pushVec}\}$$ -/
def pushLine : Json :=
  Json.mkObj [("kind", "push"), ("rows", .arr (pushVectors.map fun (part, ps, ok) =>
    Json.arr #[.bool part, .arr (ps.map fun p => Json.arr #[.bool p.named, .bool p.run]).toArray, .bool ok]).toArray)]

/-- The golden text. $$\text{one JSON object per line: the lanes, the cases, one gate line per lane, then the push line}$$ -/
def goldenText : String :=
  String.join (((lanesLine :: cases.map caseLine) ++ lanes.map gateLine ++ [pushLine]).map fun j => j.compress ++ "\n")

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
