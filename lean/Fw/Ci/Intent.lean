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

Round 5: the default lane (lean) never skips as `unchanged` on a `ci/**` push; it runs on every tip that is not on
`main` (`lean_never_unchanged`, `tip_lean_always`), so the lean row's inputs are no safety input there. A branch wait
reads `waitLanes` and passes only with a pass of lean and of every requested lane on that commit
(`wait_needs_default_pass`, `wait_needs_requested_pass`).

Golden: `packages/contracts/golden/ci/intent.jsonl` (the lanes with their `if:`, the re-check steps, the replay
cases, the gate vectors and the push vectors) and `packages/contracts/golden/ci/pushlane.jsonl` (the push lane
verdicts), written by `lake test -- --write-ci-trigger-golden`.
-/
namespace Fw.Ci.Intent
open Lean Fw.Ops.PathCheck Fw.Ci.Trigger
open Fw.Console.LandSpeed (selected selected_of_mem skip_sound ReadsWithin St)
open Fw.Ci.Verdict (Skip)

/-! ## The intent token -/

/-- The token prefix. -/
def tokPrefix : List Char := ['[', 'c', 'i', ':']

/-- The token that asks for lane `n`. -/
def tok (n : String) : List Char := tokPrefix ++ n.toList ++ [']']

/-- The message with ASCII `A`–`Z` lowered (Lean `Char.toLower`; GitHub's `contains` ignores case too). -/
def lower (m : String) : List Char := m.toList.map Char.toLower

/-- Does the message carry any intent (some `[ci:`)? -/
def intent (m : String) : Bool := decide (tokPrefix <:+: lower m)

/-- Does the message ask for lane `n`? -/
def requested (n m : String) : Bool := decide (tok n <:+: lower m)

/-- A character allowed in a lane name: a lower-case ASCII letter, a digit or `-`. -/
def nameChar (c : Char) : Bool := c.isLower || c.isDigit || c == '-'

/-- A lane name: non-empty, every character a name character. -/
def validName (n : String) : Bool := !n.isEmpty && n.toList.all nameChar

#guard requested "lean" "fix x\n\n[ci:lean] [ci:wktr]"
#guard requested "lean" "[CI:Lean]"
#guard !requested "wktr" "[ci:wktr-fixtures]"
#guard !requested "lean" "[ci: lean]"
#guard intent "[ci:none]" && !requested "lean" "[ci:none]"
#guard !intent "merge main into ci/x"

/-- A requested lane means the message carries intent. -/
theorem intent_of_requested (n m : String) (h : requested n m = true) : intent m = true := by
  simp only [requested, intent, decide_eq_true_eq] at h ⊢
  exact List.IsInfix.trans (List.IsPrefix.isInfix (by simp [tok, List.append_assoc])) h

/-- Two names without brackets: if the first, followed by `]`, starts the second followed by `]`, they are equal. -/
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

/-- Two words without the separator `c`: if each, followed by `c`, starts the same text, they are equal. -/
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

/-- **Token non-confusion.** For valid lane names, the token of `a` occurs inside the token of `b` only when
`a = b`; so a message asking for `wktr-fixtures` does not ask for `wktr`. -/
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
job, and whether it starts without any intent. -/
structure Lane where
  wf : Wf
  name : String
  macos : Bool
  byDefault : Bool

/-- The workflows whose push run holds a macOS job (`gate-gaps` runs macOS only on a dispatch with `macos=true`;
`trajectory-probe` runs its macOS leg on a push only when the head commit carries `[frames:` or the commit line has a `debug=` key;
`smoothness` runs its two WebKit legs only when the head commit carries `[webkit-cadence]`). -/
def macosFiles : List String :=
  ["engine-premises.yml", "font-fidelity.yml", "path-pix.yml", "sim-speed.yml", "smoothness.yml", "toolbar-throttle.yml", "trajectory-probe.yml", "webkit-sim.yml", "wktr-fixtures.yml", "wktr.yml"]

def defaultFiles : List String := ["lean.yml"]

/-- The lane name of a workflow file: the file name without `.yml`. -/
def stem (f : String) : String := (f.dropEnd 4).toString

/-- The lane of a workflow. -/
def laneOf (w : Wf) : Lane := ⟨w, stem w.file, macosFiles.contains w.file, defaultFiles.contains w.file⟩

/-- Every lane, in table order. -/
def lanes (_ : Unit := ()) : List Lane := table.map laneOf

#guard lanes.all (validName ·.name)
#guard (lanes.map (·.name)).eraseDups.length == lanes.length
#guard (lanes.filter (·.byDefault)).map (·.name) == ["lean"]
#guard (macosFiles ++ defaultFiles).all fun f => (table.map (·.file)).contains f

/-- **No default lane is a macOS lane.** -/
theorem default_lane_not_macos (l : Lane) (hl : l ∈ lanes) (hd : l.byDefault = true) : l.macos = false := by
  simp only [lanes, List.mem_map] at hl
  obtain ⟨w, -, rfl⟩ := hl
  simp only [laneOf, defaultFiles, List.contains_cons, List.contains_nil, Bool.or_false, beq_iff_eq] at hd ⊢
  rw [hd]; decide

/-- **The default lane is lean.** A lane of a workflow is a default lane iff the workflow is `lean.yml`. -/
theorem default_iff_lean (w : Wf) : (laneOf w).byDefault = true ↔ w.file = "lean.yml" := by
  simp [laneOf, defaultFiles]


/-! ## The start decision (round 3: the tip decides on the branch's whole diff against `main`) -/

/-- Does the head commit want the lane? A default lane always; any other lane when the message names it. -/
def wanted (l : Lane) (m : String) : Bool := l.byDefault || requested l.name m

/-- The event of a run: a push to `refs/heads/ci/**`, a push to `main` (the only other branch the workflows list), or a
record (a dispatch or a schedule). -/
inductive Ev where
  | ciPush
  | mainPush
  | record
  deriving DecidableEq, Repr

/-- A `ci/**` push, from GitHub's event name and ref. -/
def isCi (event ref : String) : Bool := event == "push" && ref.startsWith "refs/heads/ci/"

/-- The event of a run from GitHub's event name and ref: a `ci/**` push, else any other push (`main`), else a record. -/
def evOf (event ref : String) : Ev :=
  if isCi event ref then .ciPush else if event == "push" then .mainPush else .record

/-- The facts the guard reads for one run. `ev`: the event. `msg`: the head commit message. `tip`: the run's commit is
the branch's current tip (`git ls-remote`; a read error counts as the tip). `landed`: the commit is already on `main`.
`diff`: on a `ci/**` push the files changed from the merge-base with `main` to the commit (the whole branch, never
this push alone); on a `main` push the push's own diff. `differs`: the file's content at the commit is not `main`'s.
(below its fields are written `p.e`, `p.m`, `p.tip`,
`p.land`, `p.D`, `p.δ`) -/
structure Push where
  ev : Ev
  msg : String
  tip : Bool
  landed : Bool
  diff : List String
  differs : String → Bool

/-- **The guard's decision**: `none` runs the lane's jobs, `some k` skips them for reason `k`. A record runs. A `main`
push runs iff its diff passes the lane's coarse `paths` globs (the rule GitHub applied before round 3). A `ci/**` push
skips, in this order, when the head commit does not want the lane, when the commit is not the branch tip, when it is
already on `main`, and, for a lane that is not a default lane, when no file that differs from `main` is an input of
the lane; otherwise it runs (round 5: the default lane, lean, never skips as unchanged on a `ci/**` push). Below
`run` is `none` and a kind `k` is `some k`. -/
def decision (S : String → List String) (l : Lane) (p : Push) : Option Skip :=
  match p.ev with
  | .record => none
  | .mainPush => if selected (pushPaths l.wf) p.diff then none else some .unchanged
  | .ciPush =>
    if !wanted l p.msg then some .unwanted
    else if !p.tip then some .stale
    else if p.landed then some .landed
    else if !l.byDefault && !l.wf.starts S (effective p.diff p.differs) then some .unchanged
    else none

/-- The guard starts the lane's jobs iff it decides to run. -/
def start (S : String → List String) (l : Lane) (p : Push) : Bool := decision S l p == none

/-- **A record always runs.** A dispatch or a schedule starts every lane. -/
theorem record_always_runs (S : String → List String) (l : Lane) (p : Push) (h : p.ev = .record) :
    start S l p = true := by
  simp [start, decision, h]

/-- **A `main` push keeps the old rule:** it starts the lane iff its diff passes the lane's coarse `paths` globs
(`Trigger.pushPaths`, the list GitHub's `paths` filter used before round 3). -/
theorem main_keeps_paths_rule (S : String → List String) (l : Lane) (p : Push) (h : p.ev = .mainPush) :
    start S l p = true ↔ selected (pushPaths l.wf) p.diff = true := by
  cases hs : selected (pushPaths l.wf) p.diff <;> simp [start, decision, h, hs]

/-- **The decision on a `ci/**` push, unfolded.** -/
theorem start_ci_iff (S : String → List String) (l : Lane) (p : Push) (hci : p.ev = .ciPush) :
    start S l p = true ↔ wanted l p.msg = true ∧ p.tip = true ∧ p.landed = false ∧ (l.byDefault = true ∨
      ∃ x ∈ p.diff, p.differs x = true ∧ inScope (parseScope (expand S l.wf.inputs)) x = true) := by
  rw [← starts_iff]
  cases hw : wanted l p.msg <;> cases ht : p.tip <;> cases hl : p.landed <;> cases hd : l.byDefault <;>
    cases hs : l.wf.starts S (effective p.diff p.differs) <;> simp [start, decision, hci, hw, ht, hl, hd, hs]

/-- **The tip starts every requested lane that is due.** On a `ci/**` push, if the head commit names the lane, the
commit is the branch tip and not on `main`, and some file that differs from `main` on the branch is an input of the
lane, the lane starts, whatever earlier pushes did. -/
theorem tip_starts (S : String → List String) (l : Lane) (p : Push) (hci : p.ev = .ciPush)
    (hr : requested l.name p.msg = true) (ht : p.tip = true) (hl : p.landed = false)
    (hs : l.wf.starts S (effective p.diff p.differs) = true) : start S l p = true := by
  have hw : wanted l p.msg = true := by simp [wanted, hr]
  simp [start, decision, hci, hw, ht, hl, hs]

/-- **The tip always checks the Lean proofs** (round 5). On a `ci/**` push, a default lane (`lean`) starts whenever
the commit is the branch tip and not on `main`, whatever files differ from `main` and whatever lanes the head commit
names (none, `[ci:none]`, or others). -/
theorem tip_lean_always (S : String → List String) (l : Lane) (p : Push) (hci : p.ev = .ciPush)
    (hd : l.byDefault = true) (ht : p.tip = true) (hl : p.landed = false) : start S l p = true := by
  have hw : wanted l p.msg = true := by simp [wanted, hd]
  simp [start, decision, hci, hw, ht, hl, hd]

/-- **Lean never skips as unchanged on a `ci/**` push** (round 5). The guard of a default lane never decides
`unchanged` on a `ci/**` push, so the lean row's inputs never make lean skip there; it skips only as stale or landed. -/
theorem lean_never_unchanged (S : String → List String) (l : Lane) (p : Push) (hci : p.ev = .ciPush)
    (hd : l.byDefault = true) : decision S l p ≠ some .unchanged := by
  have hw : wanted l p.msg = true := by simp [wanted, hd]
  cases ht : p.tip <;> cases hl : p.landed <;> simp [decision, hci, hw, ht, hl, hd]

/-- **The tip's decision has no history.** Two `ci/**` pushes with the same message, tip and landed flags, and the
same files that differ from `main` on the branch, get the same decision for every lane: what earlier pushes changed,
reverted or ran does not matter (the reviewer's revert sequence: push A changes X and Y, push B reverts X; B still
starts lean because Y differs from `main`). -/
theorem tip_history_free (S : String → List String) (l : Lane) (p q : Push) (hp : p.ev = .ciPush)
    (hq : q.ev = .ciPush) (hm : p.msg = q.msg) (ht : p.tip = q.tip) (hl : p.landed = q.landed)
    (he : effective p.diff p.differs = effective q.diff q.differs) : decision S l p = decision S l q := by
  simp only [decision, hp, hq, hm, ht, hl, he]

/-- **A commit that is not the tip starts no job.** On a `ci/**` push, if a newer push moved the branch tip before the
guard read it, the guard skips the lane as stale (when the head commit wants it; otherwise as unwanted). -/
theorem stale_guard_never_starts (S : String → List String) (l : Lane) (p : Push) (hci : p.ev = .ciPush)
    (ht : p.tip = false) : start S l p = false := by
  cases hw : wanted l p.msg <;> simp [start, decision, hci, hw, ht]

/-- **No unrequested start.** On a `ci/**` push a lane starts only if the head commit names it or the lane is a
default lane. -/
theorem no_unrequested_start (S : String → List String) (l : Lane) (p : Push) (hci : p.ev = .ciPush)
    (h : start S l p = true) : requested l.name p.msg = true ∨ l.byDefault = true := by
  have hw := ((start_ci_iff S l p hci).mp h).1
  simp only [wanted, Bool.or_eq_true] at hw
  exact hw.symm

/-- **A landed commit starts no job** on a `ci/**` push. -/
theorem landed_never_runs_heavy (S : String → List String) (l : Lane) (p : Push) (hci : p.ev = .ciPush)
    (h : p.landed = true) : start S l p = false := by
  cases hw : wanted l p.msg <;> cases ht : p.tip <;> simp [start, decision, hci, hw, ht, h]

/-- **The default starts no macOS lane.** On a `ci/**` push whose head commit carries no intent, no lane of the
table that starts holds a macOS job. -/
theorem default_no_macos (S : String → List String) (p : Push) (l : Lane) (hl : l ∈ lanes) (hci : p.ev = .ciPush)
    (hi : intent p.msg = false) (h : start S l p = true) : l.byDefault = true ∧ l.macos = false := by
  rcases no_unrequested_start S l p hci h with h1 | hd
  · rw [intent_of_requested _ _ h1] at hi; exact Bool.noConfusion hi
  · exact ⟨hd, default_lane_not_macos l hl hd⟩

/-- **A run whose lane inputs equal `main`'s answers like `main`.** If the lane's result depends only on its expanded
inputs and no effective file of the branch is one of them, the result on the commit equals the result on `main`'s
content (a skip `unchanged` loses nothing). -/
theorem unchanged_replays {R} (S : String → List String) (l : Lane) (eff : List String) (run : St → R)
    (hrw : ReadsWithin run (expand S l.wf.inputs)) (hs : l.wf.starts S eff = false) (σ σ' : St)
    (hd : ∀ q, q ∉ eff → σ q = σ' q) : run σ = run σ' :=
  skipped_replays S l.wf eff run hrw hs σ σ' hd

/-! ## The guard job's `if:` -/

/-- The `if:` of the guard job, as a Boolean: true unless a `ci/**` push's head commit does not want the lane. A
default lane always passes; any other lane only when the message names it. -/
def gate (l : Lane) (ci : Bool) (m : String) : Bool := !ci || l.byDefault || requested l.name m

/-- **The `if:` is exactly "not a ci push, or wanted".** -/
theorem gate_eq (l : Lane) (ci : Bool) (m : String) : gate l ci m = (!ci || wanted l m) := by
  simp [gate, wanted, Bool.or_assoc]

/-- **The `if:` never drops a start.** Since round 3 no workflow has a `paths` filter, so every push creates a run of
every lane; the guard then runs whenever the guard script would start the lane. -/
theorem start_gate (S : String → List String) (l : Lane) (p : Push) (h : start S l p = true) :
    gate l (p.ev == .ciPush) p.msg = true := by
  rw [gate_eq]
  cases hci : p.ev
  · simpa using ((start_ci_iff S l p hci).mp h).1
  · rfl
  · rfl

/-- A `contains` call on the head commit message, as GitHub expression text. -/
def containsExpr (s : String) : String := "contains(github.event.head_commit.message, '" ++ s ++ "')"

/-- The "not a ci push" part of the `if:`. -/
def recordExpr : String := "github.event_name != 'push' || !startsWith(github.ref, 'refs/heads/ci/')"

/-- The guard job's `if:` text: `gate` written as a GitHub expression. A default lane has no `if:` at all (the empty
text: a job without `if:` always runs, and actionlint rejects a constant condition). -/
def ifExpr (l : Lane) : String :=
  if l.byDefault then ""
  else "${{ " ++ recordExpr ++ " || " ++ containsExpr (String.ofList (tok l.name)) ++ " }}"

#guard ifExpr (laneOf ⟨"wktr.yml", [], [], []⟩) ==
  "${{ github.event_name != 'push' || !startsWith(github.ref, 'refs/heads/ci/') || contains(github.event.head_commit.message, '[ci:wktr]') }}"
#guard ifExpr (laneOf ⟨"lean.yml", [], [], []⟩) == ""

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
the re-check step did not write an answer). -/
def staleRuns (ev : Ev) (tipAtJob : Option Bool) : Bool := ev == .ciPush && tipAtJob == some false

/-- A later step's kind: `plain` (its `if:`, if any, has no status function, so GitHub adds `success()`) or `status`
(its `if:` holds `always()`, `failure()`, `cancelled()` or `success()`). -/
inductive StepKind where
  | plain
  | status
  deriving DecidableEq, Repr

/-- Does a later step of a heavy job run? `okBefore`: no step before it (other than `stale:`) failed; `cond`: its own
`if:` without the stale conjunct. A plain step needs `okBefore`, its condition and no failed `stale:` step; a status step
needs its condition and the conjunct (`stale:` skipped). -/
def stepRuns (ev : Ev) (tipAtJob : Option Bool) (c : StepKind) (okBefore cond : Bool) : Bool :=
  match c with
  | .plain => okBefore && cond && !staleRuns ev tipAtJob
  | .status => cond && !staleRuns ev tipAtJob

/-- **A stale run never works.** On a `ci/**` push, once a heavy job's re-check reads another commit as the branch
tip, no later step of the job runs, whatever its kind and condition. -/
theorem stale_never_works (c : StepKind) (okBefore cond : Bool) :
    stepRuns .ciPush (some false) c okBefore cond = false := by
  cases c <;> simp [stepRuns, staleRuns]

/-- **The re-check changes nothing at the tip or off `ci/**`.** When the `stale:` step does not run, every later step
runs exactly as it did before round 3. -/
theorem tip_job_unchanged (ev : Ev) (t : Option Bool) (okBefore cond : Bool) (h : staleRuns ev t = false) :
    stepRuns ev t .plain okBefore cond = (okBefore && cond) ∧ stepRuns ev t .status okBefore cond = cond := by
  simp [stepRuns, h]

#guard stepRuns .ciPush (some true) .plain true true && stepRuns .mainPush (some false) .status false true
#guard !stepRuns .ciPush (some false) .status true true && stepRuns .ciPush none .plain true true

/-- The re-check step's name and `if:` (only on a `ci/**` push). -/
def tipName : String := "tip re-check"

@[inherit_doc tipName]
def tipIf : String := "github.event_name == 'push' && startsWith(github.ref, 'refs/heads/ci/')"

/-- The stale step's name (it starts with `Fw.Ci.Verdict.staleStep`, which the wait reads) and its `if:`. -/
def staleName : String := Fw.Ci.Verdict.staleStep ++ " a newer push is the branch tip"

@[inherit_doc staleName]
def staleIf : String := "steps.tip.outputs.tip == 'false'"

/-- The conjunct every status-function step of a heavy job carries. -/
def workConj : String := "steps.stale.outcome == 'skipped'"

/-! ## Concurrency (round 3: none on `ci/**`) -/

/-- The concurrency group of a heavy job `j` of lane `ℓ` (`j` is filled in by `scripts/ci-paths.mjs`): on a `main`
push one group per lane, ref, job and matrix leg (main runs queue, as before); on a `ci/**` push, a dispatch or a
schedule the run's own id, so no two runs share a group and nothing is cancelled or replaced while pending
(`Fw.Ci.Cancel.ci_never_cancelled`). No job sets `cancel-in-progress`. -/
def groupExpr (l : Lane) (job : String) : String :=
  "ci-lane:" ++ l.name ++ String.singleton ':' ++
    ("${{ github.event_name == 'push' && !startsWith(github.ref, 'refs/heads/ci/') && github.ref || github.run_id }}:" ++
      job ++ ":${{ strategy.job-index }}")

/-- **Two lanes never share a group.** For valid lane names, equal groups (same job) mean the same lane. -/
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

/-! ## The lanes of a branch wait (round 5) -/

/-- The lanes a branch wait reads for a head commit message: every lane the message wants (the requested lanes and
the default lane), in table order. -/
def waitLanes (m : String) : List Lane := lanes.filter fun l => wanted l m

/-- **A branch wait needs a pass of the default lane** (round 5). For any known head commit message and any facts per
lane (the newest run of the lane for that commit), if the wait over `waitLanes` passes, every default lane (lean) has
a passing run: a skip, `unchanged` included, never stands in for it. -/
theorem wait_needs_default_pass (m : String) (run : Lane → Fw.Ci.Verdict.LaneRun)
    (h : Fw.Ci.Verdict.waitVerdict (some ((waitLanes m).map run)) = .pass) :
    ∀ l ∈ lanes, l.byDefault = true → (run l).v = some .pass := by
  intro l hl hd
  have hm : l ∈ waitLanes m := List.mem_filter.mpr ⟨hl, by simp [wanted, hd]⟩
  have hp := ((Fw.Ci.Verdict.combine_requested_pass_iff _).mp h).1 (run l) (List.mem_map_of_mem hm)
  exact (Fw.Ci.Verdict.laneOk_iff _).mp hp

/-- **A branch wait needs a pass of every requested lane.** If the wait over `waitLanes` passes, every lane the
message names has a passing run. -/
theorem wait_needs_requested_pass (m : String) (run : Lane → Fw.Ci.Verdict.LaneRun)
    (h : Fw.Ci.Verdict.waitVerdict (some ((waitLanes m).map run)) = .pass) :
    ∀ l ∈ lanes, requested l.name m = true → (run l).v = some .pass := by
  intro l hl hr
  have hm : l ∈ waitLanes m := List.mem_filter.mpr ⟨hl, by simp [wanted, hr]⟩
  have hp := ((Fw.Ci.Verdict.combine_requested_pass_iff _).mp h).1 (run l) (List.mem_map_of_mem hm)
  exact (Fw.Ci.Verdict.laneOk_iff _).mp hp

#guard (waitLanes "fix").map (·.name) == ["lean"]
#guard (waitLanes "x [ci:wktr]").map (·.name) == ["lean", "wktr"]

/-! ## The push preview (round 4: `fw ci push` refuses a partial request) -/

/-- One lane of the push preview: whether the agent named it in `--lanes` (a default lane it did not name: `false`)
and whether its guard would start it on this push, the pushed commit being the tip (`start`). -/
structure Planned where
  named : Bool
  run : Bool
  deriving DecidableEq, Repr

/-- **Whether `fw ci push` pushes.** Every named lane would start; or, with `--partial` (`π`), at least one named lane
would. A request that names no lane (`none`) satisfies the first disjunct, so it always pushes. -/
def pushOk (part : Bool) (ps : List Planned) : Bool :=
  ps.all (fun p => !p.named || p.run) || (part && ps.any fun p => p.named && p.run)

/-- **Without `--partial`, a push starts every named lane.** If the push goes ahead, every lane the agent named would
start, so no named lane is skipped as unchanged or landed and the wait is not doomed to *not run*. -/
theorem push_full_starts (ps : List Planned) (h : pushOk false ps = true) :
    ∀ p ∈ ps, p.named = true → p.run = true := by
  intro p hp hn
  simp only [pushOk, Bool.false_and, Bool.or_false, List.all_eq_true] at h
  have := h p hp
  simp [hn] at this
  exact this

/-- **A named lane that would be skipped refuses the push** (without `--partial`). -/
theorem skipped_named_refused (ps : List Planned) (p : Planned) (hp : p ∈ ps) (hn : p.named = true)
    (hr : p.run = false) : pushOk false ps = false := by
  cases h : pushOk false ps
  · rfl
  · have := push_full_starts ps h p hp hn
    rw [hr] at this
    exact absurd this (by decide)

/-- **With `--partial`, a push starts at least one named lane** unless no lane is named. -/
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

/-- Every preview of at most 3 lanes: each list over `O = [(⊥,⊥), (⊥,⊤), (⊤,⊥), (⊤,⊤)]` of
length 0 to 3 exactly once, by length, then by prefix, then by the last element's place in `O` (85 lists). -/
def plans : List (List Planned) :=
  let one : List Planned := [⟨false, false⟩, ⟨false, true⟩, ⟨true, false⟩, ⟨true, true⟩]
  let ext (ps : List (List Planned)) := ps.flatMap fun xs => one.map fun p => xs ++ [p]
  let l1 := ext [[]]
  let l2 := ext l1
  [[]] ++ l1 ++ l2 ++ ext l2

#guard plans.length == 85

/-- The push vectors: for each `π` and each plan, the value of `pushOk` (`ci-push.mjs` checks its own rule on them). -/
def pushVectors : List (Bool × List Planned × Bool) :=
  [false, true].flatMap fun part => plans.map fun ps => (part, ps, pushOk part ps)

def seederFiles : List String := seeders.map Prod.fst

#guard seederFiles == ["lean.yml", "premise-tests.yml"]

def startedNames (S : String → List String) (msg : String) (diff : List String) (differs : String → Bool)
    (landed : Bool) : List String :=
  (lanes.filter fun l => start S l ⟨.ciPush, msg, true, landed, diff, differs⟩).map (·.name)

def measuringNames (S : String → List String) (msg : String) (diff : List String) (differs : String → Bool)
    (landed : Bool) : List String :=
  ((lanes.filter fun l => start S l ⟨.ciPush, msg, true, landed, diff, differs⟩).filter
    fun l => !seederFiles.contains l.wf.file).map (·.name)

def lanesTrailer (m : String) : List String :=
  ((m.toLower.splitOn "[lanes:").drop 1).flatMap fun seg =>
    match seg.splitOn "]" with
    | body :: _ :: _ => ((body.split fun c => c == ',' || c == ' ' || c == '\t' || c == '\n').toList.map String.Slice.toString).filter (· != "")
    | _ => []

def requiredLanes (msgs : List String) : List String := (msgs.flatMap lanesTrailer).eraseDups

def missingLanes (started required : List String) : List String := required.filter fun n => !started.contains n

def sameTree (diff : List String) (differs : String → Bool) : Bool := (effective diff differs).isEmpty

inductive Reason where
  | ok
  | sameTree
  | missing
  | noMeasuring
  deriving DecidableEq, Repr

def Reason.tag : Reason → String
  | .ok => "ok"
  | .sameTree => "same-tree"
  | .missing => "missing"
  | .noMeasuring => "no-measuring"

def tipOf (msgs : List String) : String := msgs.headD ""

def reasonOf (same : Bool) (miss req meas : List String) : Reason :=
  if same then .sameTree
  else if !miss.isEmpty then .missing
  else if meas.isEmpty then .noMeasuring
  else .ok

theorem reasonOf_ne_ok (same : Bool) (miss req meas : List String) :
    reasonOf same miss req meas ≠ .ok ↔ same = true ∨ miss ≠ [] ∨ meas = [] := by
  unfold reasonOf
  by_cases a : same = true <;> by_cases b : miss = [] <;> by_cases c : req = [] <;> by_cases d : meas = [] <;>
    simp [a, b, c, d]

/-- The pre-push verdict over the commit messages of `origin/main..tip`, tip first. -/
def reason (S : String → List String) (msgs : List String) (diff : List String) (differs : String → Bool)
    (landed : Bool) : Reason :=
  reasonOf (sameTree diff differs) (missingLanes (startedNames S (tipOf msgs) diff differs landed) (requiredLanes msgs))
    (requiredLanes msgs) (measuringNames S (tipOf msgs) diff differs landed)

def refuseNoLane (S : String → List String) (msgs : List String) (diff : List String) (differs : String → Bool)
    (landed : Bool) : Bool := reason S msgs diff differs landed != .ok

def hookCovers (ref : String) : Bool := isCi "push" ref

theorem refuse_iff (S : String → List String) (msgs : List String) (diff : List String) (differs : String → Bool)
    (landed : Bool) :
    refuseNoLane S msgs diff differs landed = true ↔
      sameTree diff differs = true ∨
      missingLanes (startedNames S (tipOf msgs) diff differs landed) (requiredLanes msgs) ≠ [] ∨
      measuringNames S (tipOf msgs) diff differs landed = [] := by
  unfold refuseNoLane reason
  rw [bne_iff_ne]
  exact reasonOf_ne_ok _ _ _ _

theorem refuse_same_tree (S : String → List String) (msgs : List String) (diff : List String)
    (differs : String → Bool) (landed : Bool) (h : sameTree diff differs = true) :
    refuseNoLane S msgs diff differs landed = true :=
  (refuse_iff ..).mpr (Or.inl h)

theorem refuse_missing (S : String → List String) (msgs : List String) (diff : List String)
    (differs : String → Bool) (landed : Bool)
    (h : missingLanes (startedNames S (tipOf msgs) diff differs landed) (requiredLanes msgs) ≠ []) :
    refuseNoLane S msgs diff differs landed = true :=
  (refuse_iff ..).mpr (Or.inr (Or.inl h))

theorem refuse_no_measuring (S : String → List String) (msgs : List String) (diff : List String)
    (differs : String → Bool) (landed : Bool) 
    (hm : measuringNames S (tipOf msgs) diff differs landed = []) :
    refuseNoLane S msgs diff differs landed = true :=
  (refuse_iff ..).mpr (Or.inr (Or.inr hm))

theorem accept_iff (S : String → List String) (msgs : List String) (diff : List String) (differs : String → Bool)
    (landed : Bool) :
    refuseNoLane S msgs diff differs landed = false ↔
      sameTree diff differs = false ∧
      missingLanes (startedNames S (tipOf msgs) diff differs landed) (requiredLanes msgs) = [] ∧
      measuringNames S (tipOf msgs) diff differs landed ≠ [] := by
  rw [← Bool.not_eq_true, refuse_iff]
  simp [not_or]

theorem token_lane_runs (S : String → List String) (l : Lane) (hl : l ∈ lanes) (msg : String) (diff : List String)
    (differs : String → Bool) (hr : requested l.name msg = true)
    (hs : l.wf.starts S (effective diff differs) = true) :
    l.name ∈ startedNames S msg diff differs false := by
  have := tip_starts S l ⟨.ciPush, msg, true, false, diff, differs⟩ rfl hr rfl rfl hs
  exact List.mem_map.mpr ⟨l, List.mem_filter.mpr ⟨hl, this⟩, rfl⟩

theorem started_requested (S : String → List String) (msg : String) (diff : List String) (differs : String → Bool)
    (landed : Bool) (n : String) (h : n ∈ startedNames S msg diff differs landed) :
    requested n msg = true ∨ n = "lean" := by
  obtain ⟨l, hm, rfl⟩ := List.mem_map.mp h
  have hs := (List.mem_filter.mp hm).2
  rcases no_unrequested_start S l _ rfl hs with hr | hd
  · exact Or.inl hr
  · right
    have hl := (List.mem_filter.mp hm).1
    simp only [lanes, List.mem_map] at hl
    obtain ⟨w, -, rfl⟩ := hl
    have := (default_iff_lean w).mp hd
    show stem w.file = "lean"
    rw [this]
    decide +kernel

theorem missing_token_refused (S : String → List String) (msgs : List String) (diff : List String)
    (differs : String → Bool) (landed : Bool) (n : String) (hreq : n ∈ requiredLanes msgs)
    (hnl : n ≠ "lean") (hnt : requested n (tipOf msgs) = false) :
    refuseNoLane S msgs diff differs landed = true := by
  apply refuse_missing
  intro hnil
  have hs : n ∉ startedNames S (tipOf msgs) diff differs landed := fun hm => by
    rcases started_requested S _ diff differs landed n hm with h | h
    · simp [hnt] at h
    · exact hnl h
  have hc : (startedNames S (tipOf msgs) diff differs landed).contains n = false := by
    cases hh : (startedNames S (tipOf msgs) diff differs landed).contains n
    · rfl
    · exact absurd (List.mem_of_elem_eq_true hh) hs
  have : n ∈ missingLanes (startedNames S (tipOf msgs) diff differs landed) (requiredLanes msgs) :=
    List.mem_filter.mpr ⟨hreq, by rw [hc]; rfl⟩
  rw [hnil] at this
  exact absurd this (by simp)

theorem same_tree_no_measuring (S : String → List String) (msg : String) (diff : List String)
    (differs : String → Bool) (landed : Bool) (h : sameTree diff differs = true) :
    measuringNames S msg diff differs landed = [] := by
  simp only [measuringNames, List.map_eq_nil_iff, List.filter_eq_nil_iff, List.mem_filter, Bool.not_eq_true',
    and_imp]
  intro l hl hs
  have hs' := (start_ci_iff S l ⟨.ciPush, msg, true, landed, diff, differs⟩ rfl).mp hs
  rcases hs'.2.2.2 with hd | ⟨x, hx, hdx, -⟩
  · simp only [lanes, List.mem_map] at hl
    obtain ⟨w, -, rfl⟩ := hl
    have hf : (laneOf w).wf.file = "lean.yml" := (default_iff_lean w).mp hd
    simp [hf, seederFiles, seeders]
  · have hx' : x ∈ effective diff differs := List.mem_filter.mpr ⟨hx, hdx⟩
    simp only [sameTree, List.isEmpty_iff] at h
    rw [h] at hx'
    exact absurd hx' (by simp)

/-! ## The land intent (task `land-push-lane`) -/

def branchChar (c : Char) : Char := if c.isAlphanum || c == '.' || c == '_' || c == '-' then c else '_'

def sha7 (sha : String) : String := String.ofList (sha.toList.take 7)

/-- The branch `fw land` pushes for a task and its merge commit (TS `landBranch` in `land-remote.ts`). -/
def landBranch (task merge : String) (again : Bool) : String :=
  "ci/land-" ++ String.ofList (task.toList.map branchChar) ++ "-" ++ sha7 merge ++ (if again then "-again" else "")

structure Legs where
  gh : List String
  all : List String

/-- The message of the land's marker commit (TS `markerMessage` in `land-remote.ts`). -/
def markerMessage (task merge : String) (legs : Option Legs) : String :=
  let base := "land " ++ task ++ " " ++ sha7 merge
  match legs with
  | none => "[ci:land] " ++ base
  | some l =>
    if l.gh.isEmpty then base
    else if l.gh.length == l.all.length then "[ci:land] " ++ base
    else "[ci:land] " ++ base ++ " [legs:" ++ ",".intercalate l.gh ++ "]"

#guard landBranch "phone-feel-kit" "ff48bd93a0" false == "ci/land-phone-feel-kit-ff48bd9"
#guard landBranch "a/b é" "12" true == "ci/land-a_b__-12-again"
#guard markerMessage "t" "abcdef0123" (some ⟨[], ["x"]⟩) == "land t abcdef0"
#guard markerMessage "t" "abcdef0123" (some ⟨["x"], ["x", "y"]⟩) == "[ci:land] land t abcdef0 [legs:x]"

/-- The record `fw land` writes for the marker commit it is about to push; `pid` is the land process. -/
structure LandIntent where
  task : String
  merge : String
  again : Bool
  marker : String
  pid : Nat
  legs : Option Legs

/-- What the hook reads from git and the process table for the pushed commit. -/
structure PushFacts where
  sha : String
  parents : List String
  tree : String
  mergeTree : String
  msg : String
  ancestors : List Nat

inductive LandCheck where
  | ok
  | branch
  | marker
  | parent
  | tree
  | message
  | lanes
  | process
  deriving DecidableEq, Repr

def LandCheck.tag : LandCheck → String
  | .ok => "ok"
  | .branch => "branch"
  | .marker => "marker"
  | .parent => "parent"
  | .tree => "tree"
  | .message => "message"
  | .lanes => "lanes"
  | .process => "process"

def onlyLand (msg : String) : Bool := lanes.all fun l => !requested l.name msg || l.name == "land"

/-- The first identity check a land push fails, or `ok`: the ref is the intent's land branch, the pushed commit is
the marker, its only parent is the merge, its tree is the merge's, its message is the marker message and names no lane
but `land`, and the land process is an ancestor of the hook. -/
def landCheck (i : LandIntent) (ref : String) (f : PushFacts) : LandCheck :=
  if ref != "refs/heads/" ++ landBranch i.task i.merge i.again then .branch
  else if f.sha != i.marker then .marker
  else if f.parents != [i.merge] then .parent
  else if f.tree != f.mergeTree then .tree
  else if f.msg != markerMessage i.task i.merge i.legs then .message
  else if !onlyLand f.msg then .lanes
  else if !f.ancestors.contains i.pid then .process
  else .ok

def landAdmits (ref : String) (li : Option LandIntent) (f : PushFacts) : Bool :=
  match li with
  | some i => landCheck i ref f == .ok
  | none => false

/-- The pre-push hook's lane verdict on one ref: refused iff the hook covers it, no verified land intent admits it,
and `refuseNoLane` refuses it. -/
def pushRefused (ref : String) (li : Option LandIntent) (f : PushFacts) (S : String → List String)
    (msgs : List String) (diff : List String) (differs : String → Bool) (landed : Bool) : Bool :=
  hookCovers ref && !landAdmits ref li f && refuseNoLane S msgs diff differs landed

theorem pushRefused_only_ci (ref : String) (li : Option LandIntent) (f : PushFacts) (S : String → List String)
    (msgs : List String) (diff : List String) (differs : String → Bool) (landed : Bool) (h : hookCovers ref = false) :
    pushRefused ref li f S msgs diff differs landed = false := by
  simp [pushRefused, h]

theorem main_never_refused (li : Option LandIntent) (f : PushFacts) (S : String → List String) (msgs : List String)
    (diff : List String) (differs : String → Bool) (landed : Bool) :
    pushRefused "refs/heads/main" li f S msgs diff differs landed = false :=
  pushRefused_only_ci _ li f S msgs diff differs landed (by decide +kernel)

theorem no_intent_unchanged (ref : String) (f : PushFacts) (S : String → List String) (msgs : List String)
    (diff : List String) (differs : String → Bool) (landed : Bool) :
    pushRefused ref none f S msgs diff differs landed = (hookCovers ref && refuseNoLane S msgs diff differs landed) := by
  simp [pushRefused, landAdmits]

/-- **A plain `ci/*` push without a measuring lane is still refused**, whatever its branch name says. -/
theorem plain_no_measuring_refused (ref : String) (f : PushFacts) (S : String → List String) (msgs : List String)
    (diff : List String) (differs : String → Bool) (landed : Bool) (hc : hookCovers ref = true)
    (hm : measuringNames S (tipOf msgs) diff differs landed = []) :
    pushRefused ref none f S msgs diff differs landed = true := by
  rw [no_intent_unchanged, hc, refuse_no_measuring S msgs diff differs landed hm]; rfl

theorem landCheck_ok_iff (i : LandIntent) (ref : String) (f : PushFacts) :
    landCheck i ref f = .ok ↔ ref = "refs/heads/" ++ landBranch i.task i.merge i.again ∧ f.sha = i.marker ∧
      f.parents = [i.merge] ∧ f.tree = f.mergeTree ∧ f.msg = markerMessage i.task i.merge i.legs ∧
      onlyLand f.msg = true ∧ i.pid ∈ f.ancestors := by
  unfold landCheck
  by_cases a : ref = "refs/heads/" ++ landBranch i.task i.merge i.again <;>
  by_cases b : f.sha = i.marker <;> by_cases c : f.parents = [i.merge] <;> by_cases d : f.tree = f.mergeTree <;>
  by_cases e : f.msg = markerMessage i.task i.merge i.legs <;> cases onlyLand f.msg <;>
  by_cases h : i.pid ∈ f.ancestors <;> simp [a, b, c, d, e, h]

/-- **A land push is admitted exactly by a verified intent.** On a ref the hook covers that the lane rule refuses,
the push goes iff an intent is given and passes every identity check. -/
theorem admitted_iff (ref : String) (li : Option LandIntent) (f : PushFacts) (S : String → List String)
    (msgs : List String) (diff : List String) (differs : String → Bool) (landed : Bool) (hc : hookCovers ref = true)
    (hr : refuseNoLane S msgs diff differs landed = true) :
    pushRefused ref li f S msgs diff differs landed = false ↔ ∃ i, li = some i ∧ landCheck i ref f = .ok := by
  cases li with
  | none => simp [pushRefused, landAdmits, hc, hr]
  | some i => cases h : landCheck i ref f <;> simp [pushRefused, landAdmits, hc, hr, h]

theorem land_admitted (ref : String) (i : LandIntent) (f : PushFacts) (S : String → List String) (msgs : List String)
    (diff : List String) (differs : String → Bool) (landed : Bool) (h : landCheck i ref f = .ok) :
    pushRefused ref (some i) f S msgs diff differs landed = false := by
  simp [pushRefused, landAdmits, h]

theorem other_branch_refused (i : LandIntent) (ref : String) (f : PushFacts)
    (h : ref ≠ "refs/heads/" ++ landBranch i.task i.merge i.again) : landCheck i ref f ≠ .ok :=
  fun k => h ((landCheck_ok_iff i ref f).mp k).1

theorem other_commit_refused (i : LandIntent) (ref : String) (f : PushFacts) (h : f.sha ≠ i.marker) :
    landCheck i ref f ≠ .ok :=
  fun k => h ((landCheck_ok_iff i ref f).mp k).2.1

theorem other_parent_refused (i : LandIntent) (ref : String) (f : PushFacts) (h : f.parents ≠ [i.merge]) :
    landCheck i ref f ≠ .ok :=
  fun k => h ((landCheck_ok_iff i ref f).mp k).2.2.1

theorem other_tree_refused (i : LandIntent) (ref : String) (f : PushFacts) (h : f.tree ≠ f.mergeTree) :
    landCheck i ref f ≠ .ok :=
  fun k => h ((landCheck_ok_iff i ref f).mp k).2.2.2.1

theorem other_message_refused (i : LandIntent) (ref : String) (f : PushFacts)
    (h : f.msg ≠ markerMessage i.task i.merge i.legs) : landCheck i ref f ≠ .ok :=
  fun k => h ((landCheck_ok_iff i ref f).mp k).2.2.2.2.1

theorem other_lane_refused (i : LandIntent) (ref : String) (f : PushFacts) (h : onlyLand f.msg = false) :
    landCheck i ref f ≠ .ok :=
  fun k => by simp [((landCheck_ok_iff i ref f).mp k).2.2.2.2.2.1] at h

theorem foreign_process_refused (i : LandIntent) (ref : String) (f : PushFacts) (h : i.pid ∉ f.ancestors) :
    landCheck i ref f ≠ .ok :=
  fun k => h ((landCheck_ok_iff i ref f).mp k).2.2.2.2.2.2

/-- **An admitted land push runs only the land lane and lean.** -/
theorem land_runs_only_land (i : LandIntent) (ref : String) (f : PushFacts) (h : landCheck i ref f = .ok)
    (S : String → List String) (diff : List String) (differs : String → Bool) (landed : Bool) (n : String)
    (hn : n ∈ startedNames S f.msg diff differs landed) : n = "land" ∨ n = "lean" := by
  have ho := ((landCheck_ok_iff i ref f).mp h).2.2.2.2.2.1
  obtain ⟨l, hm, rfl⟩ := List.mem_map.mp hn
  rcases started_requested S f.msg diff differs landed l.name hn with hr | hl
  · left
    have hl := (List.mem_filter.mp hm).1
    have := List.all_eq_true.mp ho l hl
    simpa [hr] using this
  · exact Or.inr hl

/-! ## Replay cases and golden (`packages/contracts/golden/ci/intent.jsonl`) -/

/-- The decision of every lane under the sample cones (`Trigger.sampleCone`), as (file, tag) with tag `run` or the skip
tag (written `tag`, with `tag(none) = run`); a path in `merged` already has
`main`'s content. -/
def decideIntent (ev : Ev) (msg : String) (diff merged : List String) (tip landed : Bool) : List (String × String) :=
  lanes.map fun l => (l.wf.file,
    match decision (setMap sampleCone) l ⟨ev, msg, tip, landed, diff, (fun x => !merged.contains x)⟩ with
    | none => "run"
    | some k => k.tag)

/-- The files of the lanes a run starts (`decideIntent` with tag `run`). -/
def runIntent (ev : Ev) (msg : String) (diff merged : List String) (tip landed : Bool) : List String :=
  ((decideIntent ev msg diff merged tip landed).filter (·.2 == "run")).map (·.1)

/-- The files of the lanes whose guard job's `if:` passes. -/
def gatedBy (ci : Bool) (msg : String) : List String := (lanes.filter fun l => gate l ci msg).map (·.wf.file)

-- no intent: only lean, even though the module is in the fwcore cone of 8 workflows
#guard runIntent .ciPush "fix x" ["lean/Fw/Wire.lean"] [] true false == ["lean.yml"]
#guard runIntent .ciPush "fix x\n\n[ci:wktr]" ["lean/Fw/Wire.lean"] [] true false == ["lean.yml", "wktr.yml"]
#guard runIntent .ciPush "[ci:none]" ["lean/Fw/Wire.lean"] [] true false == ["lean.yml"]
#guard runIntent .ciPush "[ci:wktr]" ["docs/x.md"] [] true false == ["lean.yml"]
-- the reviewer's revert sequence: A changes X and Y; B reverts X, so the branch differs from main in Y only
#guard runIntent .ciPush "a" ["lean/Fw/Wire.lean", "lean/Fw/Ops/Wire.lean"] [] true false == ["lean.yml"]
#guard (decideIntent .ciPush "a" ["lean/Fw/Wire.lean", "lean/Fw/Ops/Wire.lean"] [] false false).lookup "lean.yml" ==
  some "stale"
#guard runIntent .ciPush "b" ["lean/Fw/Ops/Wire.lean"] [] true false == ["lean.yml"]
-- round 5: nothing differs from main and lean still runs (`lean_never_unchanged`); a requested lane skips
#guard (decideIntent .ciPush "b2" [] [] true false).lookup "lean.yml" == some "run"
#guard (decideIntent .ciPush "[ci:wktr]" ["docs/x.md"] [] true false).lookup "wktr.yml" == some "unchanged"
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

/-- The event's name in the golden. -/
def Ev.tag : Ev → String
  | .ciPush => "ci"
  | .mainPush => "main"
  | .record => "record"

/-- The 20 replay cases, in this order: name, event, head message, branch diff, paths that equal `main`, tip, landed.
Here `W = lean/Fw/Wire.lean`, `O = lean/Fw/Ops/Wire.lean`, `K = packages/measure-wktr/src/a.mjs`,
`X = docs/x.md`, `m_3` is `fix x`, two line feeds, then `[ci:wktr]`, and `""` is
the empty message. -/
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
  ("intent for nothing, no lean input differs: lean still runs", .ciPush, "handoff [ci:none]", ["docs/x.md"], [],
    true, false),
  ("requested lane whose inputs equal main: skipped unchanged, lean runs", .ciPush, "[ci:wktr]", ["docs/x.md"], [],
    true, false),
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
  ("revert sequence, push C reverts Y too: nothing differs, lean still runs", .ciPush, "C", [], [], true, false),
  ("a docs-only tip on a branch whose Lean differs: lean runs", .ciPush, "docs", ["docs/x.md", "lean/Fw/Wire.lean"],
    [], true, false),
  ("a requested lane on a stale commit: stale", .ciPush, "[ci:wktr]", ["packages/measure-wktr/src/a.mjs"], [], false,
    false),
  ("landed", .ciPush, "[ci:lean]", ["lean/Fw/Wire.lean"], [], true, true),
  ("a main push of a Lean file: the coarse paths rule", .mainPush, "", ["lean/Fw/Wire.lean"], [], true, false),
  ("a main push of docs only: nothing", .mainPush, "", ["docs/x.md"], [], true, false),
  ("a record (dispatch, schedule) runs every lane", .record, "", [], [], true, false)]

/-- The event and ref pairs of the gate vectors: a `ci/**` push, a main push, a dispatch and a schedule. -/
def gateEnvs : List (String × String) :=
  [("push", "refs/heads/ci/x"), ("push", "refs/heads/main"), ("workflow_dispatch", "refs/heads/ci/x"),
    ("schedule", "refs/heads/main")]

/-- The messages of the gate vectors: no token, `[ci:none]`, near misses, and every lane's token (also upper case). -/
def gateMsgs (_ : Unit := ()) : List String :=
  ["fix x", "[ci:none]", "[ci: lean]", "[ci:wktr-fixtures]"] ++
    lanes.flatMap fun l => [String.ofList (tok l.name), (String.ofList (tok l.name)).toUpper]

/-- The gate vectors of one lane: for every event, ref and message, the value of `gate`. A test evaluates the
workflow's own `if:` text on each and compares. -/
def gateVectors (l : Lane) : List (String × String × String × Bool) :=
  gateEnvs.flatMap fun (e, r) => gateMsgs.map fun m => (e, r, m, gate l (isCi e r) m)

/-- The lanes line: every lane with its name, token, macOS flag, default flag, the guard `if:` text and the
concurrency group of its heavy jobs (`<job>` stands for the job id); also the guard's decision step names
(`Fw.Ci.Verdict.decisionStep`), the skip tags, and the re-check steps every heavy job starts with.
Here `step` is the decision step name of `Fw.Ci.Verdict.decisionStep`, `K` the skip kinds in their
listed order, and `L` the lanes in their listed order. -/
def lanesLine (_ : Unit := ()) : Json :=
  Json.mkObj [("kind", "lanes"), ("prefix", .str (String.ofList tokPrefix)),
    ("decision", Json.mkObj [("run", .str (Fw.Ci.Verdict.decisionStep true)),
      ("skip", .str (Fw.Ci.Verdict.decisionStep false))]),
    ("skips", strs (Fw.Ci.Verdict.Skip.all.map (·.tag))),
    ("recheck", Json.mkObj [("tipName", .str tipName), ("tipIf", .str tipIf), ("staleName", .str staleName),
      ("staleIf", .str staleIf), ("conj", .str workConj)]),
    ("lanes", .arr (lanes.map fun l => Json.mkObj [("file", .str l.wf.file), ("name", .str l.name),
      ("token", .str (String.ofList (tok l.name))), ("macos", .bool l.macos), ("byDefault", .bool l.byDefault),
      ("if", .str (ifExpr l)), ("group", .str (groupExpr l "<job>"))]).toArray)]

/-- One gate line: a lane's gate vectors. -/
def gateLine (l : Lane) : Json :=
  Json.mkObj [("kind", "gate"), ("file", .str l.wf.file),
    ("rows", .arr ((gateVectors l).map fun (e, r, m, g) => Json.arr #[.str e, .str r, .str m, .bool g]).toArray)]

/-- One replay line with every lane's decision tag, the started and the gated lanes.
Here `cone` is `Fw.Ci.Trigger.sampleCone` and the decisions object keeps the order of
`decI`. -/
def caseLine (k : String × Ev × String × List String × List String × Bool × Bool) : Json :=
  let (n, ev, msg, diff, merged, tip, landed) := k
  Json.mkObj [("kind", "case"), ("name", .str n), ("event", .str ev.tag), ("msg", .str msg), ("diff", strs diff),
    ("merged", strs merged), ("tip", .bool tip), ("landed", .bool landed),
    ("cones", Json.mkObj [("Main", strs (sampleCone "Main")), ("BreakgenMain", strs (sampleCone "BreakgenMain"))]),
    ("decisions", Json.mkObj ((decideIntent ev msg diff merged tip landed).map fun (f, t) => (f, Json.str t))),
    ("started", strs (runIntent ev msg diff merged tip landed)), ("gated", strs (gatedBy (ev == .ciPush) msg))]

/-- The push line: the push vectors, each row `[part, [[named, run]], ok]`. -/
def pushLine : Json :=
  Json.mkObj [("kind", "push"), ("rows", .arr (pushVectors.map fun (part, ps, ok) =>
    Json.arr #[.bool part, .arr (ps.map fun p => Json.arr #[.bool p.named, .bool p.run]).toArray, .bool ok]).toArray)]

#guard lanesTrailer "x [lanes: wktr, Breakpoint-Gate]\n[lanes:lean]" == ["wktr", "breakpoint-gate", "lean"]
#guard lanesTrailer "[lanes: wktr" == [] && lanesTrailer "no trailer" == []
#guard requiredLanes ["a [lanes: wktr]", "[lanes: wktr lean]"] == ["wktr", "lean"]

def pushLaneCases : List (String × List String × List String × List String × Bool) := [
  ("empty commit with a token: the tree equals main", ["[ci:wktr] ci: request"], [], [], false),
  ("a diff that main already has", ["[ci:wktr]"], ["packages/measure-wktr/src/a.mjs"],
    ["packages/measure-wktr/src/a.mjs"], false),
  ("no token, a fwcore file: lean only", ["fix x"], ["lean/Fw/Wire.lean"], [], false),
  ("token and its input differs", ["x [ci:wktr]"], ["packages/measure-wktr/src/a.mjs"], [], false),
  ("token but no input differs", ["[ci:wktr]"], ["docs/x.md"], [], false),
  ("task requires wktr, the tip lacks the token", ["fix x", "[lanes: wktr]"], ["packages/measure-wktr/src/a.mjs"],
    [], false),
  ("task requires wktr, the tip names it", ["[ci:wktr]", "[lanes: wktr]"], ["packages/measure-wktr/src/a.mjs"], [],
    false),
  ("task requires wktr and lean, both start", ["[ci:wktr]", "[lanes: wktr, lean]"],
    ["packages/measure-wktr/src/a.mjs", "lean/Fw/Wire.lean"], [], false),
  ("task requires only lean: the seeder is no measuring lane", ["fix x", "[lanes: lean]"], ["lean/Fw/Wire.lean"], [], false),
  ("task requires an unknown lane", ["[ci:wktr]", "[lanes: nope]"], ["packages/measure-wktr/src/a.mjs"], [], false),
  ("upper case token and trailer", ["[CI:WKTR]", "[LANES: WKTR]"], ["packages/measure-wktr/src/a.mjs"], [], false),
  ("a longer name is not the shorter lane", ["[ci:wktr-fixtures]", "[lanes: wktr]"],
    ["packages/measure-wktr/src/a.mjs"], [], false),
  ("none token, docs only", ["handoff [ci:none]"], ["docs/x.md"], [], false),
  ("landed commit with a token", ["[ci:wktr]"], ["packages/measure-wktr/src/a.mjs"], [], true),
  ("the trailer is in an older commit, the tip has the token", ["[ci:wktr] more", "work", "[lanes: wktr]"],
    ["packages/measure-wktr/src/a.mjs"], [], false)]

def pushLaneLine (k : String × List String × List String × List String × Bool) : Json :=
  let (n, msgs, diff, merged, landed) := k
  let S := setMap sampleCone
  let differs : String → Bool := fun x => !merged.contains x
  Json.mkObj [("kind", "pushLane"), ("name", .str n), ("msgs", strs msgs), ("diff", strs diff), ("merged", strs merged),
    ("landed", .bool landed),
    ("cones", Json.mkObj [("Main", strs (sampleCone "Main")), ("BreakgenMain", strs (sampleCone "BreakgenMain"))]),
    ("runs", strs (startedNames S (tipOf msgs) diff differs landed)),
    ("measuring", strs (measuringNames S (tipOf msgs) diff differs landed)),
    ("required", strs (requiredLanes msgs)),
    ("missing", strs (missingLanes (startedNames S (tipOf msgs) diff differs landed) (requiredLanes msgs))),
    ("reason", .str (reason S msgs diff differs landed).tag), ("refuse", .bool (refuseNoLane S msgs diff differs landed))]

def landMerge : String := "ff48bd93a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5"
def landMarker : String := "75592390a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"

def landIntentOf (task : String) (again : Bool) (legs : Option Legs) : LandIntent :=
  ⟨task, landMerge, again, landMarker, 4242, legs⟩

def factsOf (i : LandIntent) : PushFacts :=
  ⟨i.marker, [i.merge], "t0", "t0", markerMessage i.task i.merge i.legs, [4300, 4242, 1]⟩

def refOf (i : LandIntent) : String := "refs/heads/" ++ landBranch i.task i.merge i.again

def landCases : List (String × Option LandIntent × String × PushFacts) :=
  let cc := landIntentOf "phone-feel-kit" false (some ⟨[], ["check-sh", "suites-a"]⟩)
  let ag := landIntentOf "phone-feel-kit" true (some ⟨["check-sh", "suites-a"], ["check-sh", "suites-a"]⟩)
  let inj := landIntentOf "x [ci:wktr]" false (some ⟨[], ["check-sh"]⟩)
  let f := factsOf cc
  [("the land's all-CircleCI push", some cc, refOf cc, f),
   ("the land's GitHub fallback push", some ag, refOf ag, factsOf ag),
   ("a hand-made ci/land push without an intent", none, refOf cc, f),
   ("another branch", some cc, "refs/heads/ci/land-x", f),
   ("the intent of the fallback on the first branch", some ag, refOf cc, factsOf ag),
   ("another commit", some cc, refOf cc, { f with sha := landMerge }),
   ("a second parent", some cc, refOf cc, { f with parents := [landMerge, landMarker] }),
   ("another tree", some cc, refOf cc, { f with tree := "t1" }),
   ("a message with a lane token", some cc, refOf cc, { f with msg := f.msg ++ " [ci:wktr]" }),
   ("a task name with a lane token", some inj, refOf inj, factsOf inj),
   ("a push from another process", some cc, refOf cc, { f with ancestors := [4300, 1] })]

def legsJson : Option Legs → Json
  | none => .null
  | some l => Json.mkObj [("gh", strs l.gh), ("all", strs l.all)]

def landCaseLine (k : String × Option LandIntent × String × PushFacts) : Json :=
  let (n, li, ref, f) := k
  let intent := match li with
    | none => Json.null
    | some i => Json.mkObj [("task", .str i.task), ("merge", .str i.merge), ("again", .bool i.again),
        ("marker", .str i.marker), ("pid", toJson i.pid), ("legs", legsJson i.legs)]
  Json.mkObj [("kind", "landCheck"), ("name", .str n), ("intent", intent), ("ref", .str ref),
    ("facts", Json.mkObj [("sha", .str f.sha), ("parents", strs f.parents), ("tree", .str f.tree),
      ("mergeTree", .str f.mergeTree), ("msg", .str f.msg), ("ancestors", toJson f.ancestors)]),
    ("branch", match li with | some i => .str (landBranch i.task i.merge i.again) | none => .null),
    ("marker", match li with | some i => .str (markerMessage i.task i.merge i.legs) | none => .null),
    ("check", match li with | some i => .str (landCheck i ref f).tag | none => .null),
    ("admit", .bool (landAdmits ref li f))]

#guard (landCases.map fun (_, li, ref, f) => (li.map fun i => (landCheck i ref f).tag).getD "none") ==
  ["ok", "ok", "none", "branch", "branch", "marker", "parent", "tree", "message", "lanes", "process"]
#guard landCases.map (fun (_, li, ref, f) => landAdmits ref li f) ==
  [true, true, false, false, false, false, false, false, false, false, false]
#guard onlyLand "[ci:land] land t abcdef0" && onlyLand "land t abcdef0" && !onlyLand "land t [ci:wktr]"

def landBranchCases : List (String × String × Bool) :=
  [("phone-feel-kit", landMerge, false), ("a/b é", "12", true), ("", landMerge, false), ("v1.2_x", landMerge, true)]

def markerCases : List (String × String × Option Legs) :=
  [("t", landMerge, none), ("t", landMerge, some ⟨[], ["a", "b"]⟩), ("t", landMerge, some ⟨["a", "b"], ["a", "b"]⟩),
   ("t", landMerge, some ⟨["a"], ["a", "b"]⟩), ("t", "12", some ⟨["a", "b"], ["a", "b", "c"]⟩)]

def landVectorLines (_ : Unit := ()) : List Json :=
  landBranchCases.map (fun (t, m, a) => Json.mkObj [("kind", "landBranch"), ("task", .str t), ("merge", .str m),
    ("again", .bool a), ("branch", .str (landBranch t m a))]) ++
  markerCases.map (fun (t, m, l) => Json.mkObj [("kind", "marker"), ("task", .str t), ("merge", .str m),
    ("legs", legsJson l), ("msg", .str (markerMessage t m l))]) ++
  landCases.map landCaseLine

def pushLaneText (_ : Unit := ()) : String :=
  String.join ((Json.mkObj [("kind", "head"), ("seeders", strs seederFiles)] :: pushLaneCases.map pushLaneLine ++
    landVectorLines).map fun j => j.compress ++ "\n")

#guard (pushLaneCases.map fun (_, m, d, e, l) =>
  (reason (setMap sampleCone) m d (fun x => !e.contains x) l).tag) ==
  ["same-tree", "same-tree", "no-measuring", "ok", "no-measuring", "missing", "ok", "ok", "no-measuring", "missing", "ok",
    "missing", "no-measuring", "no-measuring", "ok"]

/-- The golden text. -/
def goldenText (_ : Unit := ()) : String :=
  String.join (((lanesLine :: cases.map caseLine) ++ lanes.map gateLine ++ [pushLine]).map fun j => j.compress ++ "\n")

/-- Compare (or write) the golden file; returns the number of stale files. -/
def runGolden (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / ".." / "packages" / "contracts" / "golden" / "ci" / "intent.jsonl"
  if write then
    IO.FS.createDirAll (root / ".." / "packages" / "contracts" / "golden" / "ci")
    IO.FS.writeFile p goldenText
    IO.FS.writeFile (root / ".." / "packages" / "contracts" / "golden" / "ci" / "pushlane.jsonl") pushLaneText
    IO.println s!"ci intent golden: written {cases.length} cases"
    return 0
  let q := root / ".." / "packages" / "contracts" / "golden" / "ci" / "pushlane.jsonl"
  let cur ← try IO.FS.readFile p catch _ => pure ""
  let curQ ← try IO.FS.readFile q catch _ => pure ""
  if cur != goldenText || curQ != pushLaneText then
    IO.println s!"ci intent golden: {p} is stale (regenerate: cd lean && lake test -- --write-ci-trigger-golden)"
    return 1
  IO.println s!"ci intent golden: {cases.length} cases ok"
  return 0

end Fw.Ci.Intent
