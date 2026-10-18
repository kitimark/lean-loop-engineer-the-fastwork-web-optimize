/-!
# Stale services: a running service must not lag the files it was built from

A service reads input files once, when it is started (console-api) or built (the `fwcore` binary). If one of them
changed on `main` after that, the running process still holds the old code: the incident of task `console-stale`
(console-api started 04:12 kept running while `workflow-claim` landed at 04:48, so workflow runs stayed unbound in
the ready lane for hours).

Time is not used: `fw land` builds the merge commit before its checks and moves `main` to it 23-89 s later
(MEASURED, 12 lands), so a commit time predates the moment `main` moved. Instead each running piece of code records
the commit of `main` it was started or built from (its base), and an input is *changed* iff the first-parent range
`base..main` touches it (`git log --first-parent <base>..main -- <path>` is non-empty). The collector (`fw watch`)
only measures that Bool per input; this module is the rule.

What runs is judged, not what is on disk. console-api holds one long-lived `fwcore` child, spawned from the binary
that was on disk at that moment. So console-api is judged on its own inputs against its start commit AND on the
`fwcore` inputs against the build commit of its child; the binary on disk is a third thing, judged as service
`fwcore`. A rebuild on disk changes only the disk; the child is replaced only when console-api restarts (or the child
respawns). Design rule: when the code a process runs cannot be identified, that is an alert (`svc.unknown`), never
silence: `chooseBase` below picks the build commit of a binary or says it cannot.
-/

namespace Fw.Obs

/-- One input group of a service: a path (file or directory prefix) and whether the first-parent range
`base..main` touches it.

$$i = (\mathit{path}, \mathit{changed}) \in \mathrm{String} \times \mathbb B$$
-/
structure SvcInput where
  path    : String
  changed : Bool
deriving DecidableEq, Repr

/-- A service: its name, its input groups (each judged against the base commit of the code that runs it) and, when
that code cannot be identified, the reason.

$$s = (\mathit{name}, I, u) \in \mathrm{String} \times \mathcal I^* \times (\mathrm{String} \cup \{\bot\})$$
-/
structure Svc where
  name    : String
  inputs  : List SvcInput := []
  /-- Why the code this service runs cannot be identified (`none`: it can). Never silence: the alert `svc.unknown`. -/
  unknown : Option String := none
deriving DecidableEq, Repr

/-- The changed input paths of a service.

$$\operatorname{changed}(s) = [\,\mathit{path}(i) \mid i \leftarrow I,\ \mathit{changed}(i)\,],\quad s = (n, I, u)$$
-/
def Svc.changed (s : Svc) : List String :=
  (s.inputs.filter (fun i => i.changed)).map SvcInput.path

/-- A service is stale when some input changed on `main` since its base commit.

$$\operatorname{stale}(s) \iff \operatorname{changed}(s) \ne []$$
-/
def Svc.staleB (s : Svc) : Bool := !s.changed.isEmpty

/-- A path is reported exactly when one of the service's inputs has that path and is changed.

$$\forall s, x:\quad x \in \operatorname{changed}(s) \iff \exists i \in I.\ \mathit{path}(i) = x \wedge \mathit{changed}(i)$$
-/
theorem Svc.mem_changed (s : Svc) (x : String) :
    x ∈ s.changed ↔ ∃ i ∈ s.inputs, i.path = x ∧ i.changed = true := by
  simp only [Svc.changed, List.mem_map, List.mem_filter]
  constructor
  · rintro ⟨i, ⟨hi, hs⟩, rfl⟩; exact ⟨i, hi, rfl, hs⟩
  · rintro ⟨i, hi, rfl, hs⟩; exact ⟨i, ⟨hi, hs⟩, rfl⟩

/-- Stale iff some input is changed.

$$\forall s:\quad \operatorname{stale}(s) \iff \exists i \in I.\ \mathit{changed}(i)$$
-/
theorem Svc.stale_iff (s : Svc) :
    s.staleB = true ↔ ∃ i ∈ s.inputs, i.changed = true := by
  unfold Svc.staleB
  constructor
  · intro h
    cases hc : s.changed with
    | nil => simp [hc] at h
    | cons x _ =>
      obtain ⟨i, hi, _, hs⟩ := (Svc.mem_changed s x).1 (by rw [hc]; exact List.mem_cons_self)
      exact ⟨i, hi, hs⟩
  · rintro ⟨i, hi, hs⟩
    have hm := (Svc.mem_changed s i.path).2 ⟨i, hi, rfl, hs⟩
    cases hc : s.changed with
    | nil => rw [hc] at hm; simp at hm
    | cons _ _ => rfl

/-- The code of a service cannot be identified.

$$\operatorname{unknown}(s) \iff u \ne \bot,\quad s = (n, I, u)$$
-/
def Svc.unknownB (s : Svc) : Bool := s.unknown.isSome

/-! ### The history model

`main` is a first-parent history, oldest first; each commit is the list of paths it touches. A base commit is a
position `b` in it (the number of commits it contains). Every statement below is about this model: whether the
range after the base touches a path. -/

/-- The path is touched by the range after position `b`.

$$\operatorname{touched}(H, b, x) \iff \exists c \in H[b..].\ x \in c$$
-/
def touched (hist : List (List String)) (b : Nat) (x : String) : Bool :=
  (hist.drop b).any (fun c => decide (x ∈ c))

/-- The input groups `X` judged against base position `b` of the history `H`.

$$\operatorname{inputs}(H, b, X) = [(x, \operatorname{touched}(H, b, x)) \mid x \leftarrow X]$$
-/
def judgeInputs (hist : List (List String)) (b : Nat) (paths : List String) : List SvcInput :=
  paths.map (fun x => ⟨x, touched hist b x⟩)

/-- The service whose inputs are judged against base position `b` of the history `H`.

$$\operatorname{judge}(H, b, n, X) = (n, \operatorname{inputs}(H, b, X), \bot)$$
-/
def Svc.judge (hist : List (List String)) (b : Nat) (name : String) (paths : List String) : Svc :=
  { name, inputs := judgeInputs hist b paths }

/-- At the head of `main` the range is empty: nothing is touched.

$$\forall H, x:\quad \neg\operatorname{touched}(H, |H|, x)$$
-/
theorem touched_length (hist : List (List String)) (x : String) : touched hist hist.length x = false := by
  simp [touched]

/-- A commit on `main` at or after the base that touches a path marks it: a landing after the start is stale.

$$\forall H, b, j, c, x:\quad b \le j \wedge H[j] = c \wedge x \in c \Rightarrow \operatorname{touched}(H, b, x)$$
-/
theorem touched_of_mem (hist : List (List String)) (b j : Nat) (hj : b ≤ j) (c : List String)
    (hc : hist[j]? = some c) (x : String) (hx : x ∈ c) : touched hist b x = true := by
  simp only [touched, List.any_eq_true, decide_eq_true_eq]
  refine ⟨c, ?_, hx⟩
  rw [List.mem_iff_getElem?]
  exact ⟨j - b, by rw [List.getElem?_drop]; simpa [Nat.add_sub_cancel' hj] using hc⟩

/-- Landing more commits never clears a touched path: the range only grows.

$$\forall H, E, b, x:\quad \operatorname{touched}(H, b, x) \Rightarrow \operatorname{touched}(H \mathbin{+\!\!+} E, b, x)$$
-/
theorem touched_append (hist ext : List (List String)) (b : Nat) (x : String)
    (h : touched hist b x = true) : touched (hist ++ ext) b x = true := by
  simp only [touched, List.any_eq_true, decide_eq_true_eq, List.drop_append] at h ⊢
  obtain ⟨c, hc, hx⟩ := h
  exact ⟨c, List.mem_append.2 (.inl hc), hx⟩

/-- A judged service is judged at the head of `main`: restarting (console-api) or rebuilding (`fwcore`) records the
current head as the new base, the range is empty, no input is changed.

$$\forall H, n, X:\quad \neg\operatorname{stale}(\operatorname{judge}(H, |H|, n, X))$$
-/
theorem Svc.judge_head_not_stale (hist : List (List String)) (name : String) (paths : List String) :
    (Svc.judge hist hist.length name paths).staleB = false := by
  cases hb : (Svc.judge hist hist.length name paths).staleB with
  | false => rfl
  | true =>
    obtain ⟨i, hi, hc⟩ := (Svc.stale_iff _).1 hb
    simp only [Svc.judge, judgeInputs, List.mem_map] at hi
    obtain ⟨x, _, rfl⟩ := hi
    simp [touched] at hc

/-- A judged service is stale once a later commit touches one of its inputs, whatever else lands afterwards.

$$\forall H, E, b, n, X:\quad \operatorname{stale}(\operatorname{judge}(H, b, n, X)) \Rightarrow \operatorname{stale}(\operatorname{judge}(H \mathbin{+\!\!+} E, b, n, X))$$
-/
theorem Svc.judge_stale_append (hist ext : List (List String)) (b : Nat) (name : String) (paths : List String)
    (h : (Svc.judge hist b name paths).staleB = true) : (Svc.judge (hist ++ ext) b name paths).staleB = true := by
  obtain ⟨i, hi, hc⟩ := (Svc.stale_iff _).1 h
  simp only [Svc.judge, judgeInputs, List.mem_map] at hi
  obtain ⟨x, hx, rfl⟩ := hi
  exact (Svc.stale_iff _).2 ⟨⟨x, touched (hist ++ ext) b x⟩, by
    simp only [Svc.judge, judgeInputs, List.mem_map]; exact ⟨x, hx, rfl⟩,
    touched_append hist ext b x hc⟩

/-! ### The stack: what console-api runs, what is on disk

Three base positions in the history `H`:

* `apiBase`: the commit console-api was started from (it read `apps/console-api`, `packages/contracts` then);
* `coreBase`: the build commit of the `fwcore` child console-api holds (spawned from the disk binary at that moment);
* `diskBase`: the build commit of the `fwcore` binary on disk now.

console-api is judged on its own inputs against `apiBase` and on the `fwcore` inputs against `coreBase`; the disk
binary is the service `fwcore`, judged against `diskBase`. -/

/-- The three base positions.

$$\Theta = (a, k, d) \in \mathbb N^3$$
-/
structure Stack where
  apiBase  : Nat
  coreBase : Nat
  diskBase : Nat

/-- console-api: its own inputs `A` against its start commit, the `fwcore` inputs `K` against the commit its child was
built from.

$$\operatorname{api}(H, \Theta) = (\texttt{console-api},\ \operatorname{inputs}(H, a, A) \mathbin{+\!\!+} \operatorname{inputs}(H, k, K),\ \bot)$$
-/
def Stack.api (hist : List (List String)) (apiOwn coreIn : List String) (t : Stack) : Svc :=
  { name := "console-api", inputs := judgeInputs hist t.apiBase apiOwn ++ judgeInputs hist t.coreBase coreIn }

/-- The `fwcore` binary on disk: the `fwcore` inputs `K` against its build commit.

$$\operatorname{disk}(H, \Theta) = \operatorname{judge}(H, d, \texttt{fwcore}, K)$$
-/
def Stack.disk (hist : List (List String)) (coreIn : List String) (t : Stack) : Svc :=
  Svc.judge hist t.diskBase "fwcore" coreIn

/-- Restarting console-api: it is started from the head of `main` and spawns its `fwcore` child from the binary on
disk, so the child is as old as the disk.

$$\operatorname{restartApi}(H, (a, k, d)) = (|H|, d, d)$$
-/
def Stack.restartApi (hist : List (List String)) (t : Stack) : Stack :=
  { t with apiBase := hist.length, coreBase := t.diskBase }

/-- A child respawn (crash) takes the binary on disk and leaves console-api's own base.

$$\operatorname{respawn}(a, k, d) = (a, d, d)$$
-/
def Stack.respawn (t : Stack) : Stack := { t with coreBase := t.diskBase }

/-- `lake build` at the head of `main` replaces the file on disk only; the child holds the old code.

$$\operatorname{rebuild}(H, (a, k, d)) = (a, k, |H|)$$
-/
def Stack.rebuild (hist : List (List String)) (t : Stack) : Stack := { t with diskBase := hist.length }

/-- A rebuild without a console-api restart leaves console-api's core inputs stale: if a commit at or after the
child's build commit touched a `fwcore` input, console-api is still stale after the rebuild. (The old model said a
rebuild cleared everything: the false negative of round 3.)

$$\forall H, \Theta, j, c, x:\quad k \le j \wedge H[j] = c \wedge x \in c \wedge x \in K \Rightarrow \operatorname{stale}(\operatorname{api}(H, \operatorname{rebuild}(H, \Theta)))$$
-/
theorem rebuild_without_restart_api_stale (hist : List (List String)) (apiOwn coreIn : List String) (t : Stack)
    (j : Nat) (hj : t.coreBase ≤ j) (c : List String) (hc : hist[j]? = some c) (x : String) (hx : x ∈ c)
    (hk : x ∈ coreIn) :
    ((t.rebuild hist).api hist apiOwn coreIn).staleB = true := by
  refine (Svc.stale_iff _).2 ⟨⟨x, touched hist t.coreBase x⟩, ?_, touched_of_mem hist t.coreBase j hj c hc x hx⟩
  simp only [Stack.api, Stack.rebuild, List.mem_append, judgeInputs, List.mem_map]
  exact .inr ⟨x, hk, rfl⟩

/-- The rebuild itself is fine: the binary on disk is not stale afterwards, and console-api's verdict is unchanged.

$$\forall H, \Theta:\quad \neg\operatorname{stale}(\operatorname{disk}(H, \operatorname{rebuild}(H, \Theta))) \wedge \operatorname{api}(H, \operatorname{rebuild}(H, \Theta)) = \operatorname{api}(H, \Theta)$$
-/
theorem rebuild_clears_disk (hist : List (List String)) (apiOwn coreIn : List String) (t : Stack) :
    ((t.rebuild hist).disk hist coreIn).staleB = false ∧
      (t.rebuild hist).api hist apiOwn coreIn = t.api hist apiOwn coreIn :=
  ⟨Svc.judge_head_not_stale hist "fwcore" coreIn, rfl⟩

/-- Restarting console-api after a rebuild clears everything: both input groups are judged at the head.

$$\forall H, \Theta:\quad \neg\operatorname{stale}(\operatorname{api}(H, \operatorname{restartApi}(H, \operatorname{rebuild}(H, \Theta)))) \wedge \neg\operatorname{stale}(\operatorname{disk}(H, \operatorname{restartApi}(H, \operatorname{rebuild}(H, \Theta))))$$
-/
theorem restartApi_after_rebuild_clears (hist : List (List String)) (apiOwn coreIn : List String) (t : Stack) :
    (((t.rebuild hist).restartApi hist).api hist apiOwn coreIn).staleB = false ∧
      (((t.rebuild hist).restartApi hist).disk hist coreIn).staleB = false := by
  refine ⟨?_, Svc.judge_head_not_stale hist "fwcore" coreIn⟩
  cases hb : (((t.rebuild hist).restartApi hist).api hist apiOwn coreIn).staleB with
  | false => rfl
  | true =>
    obtain ⟨i, hi, hc⟩ := (Svc.stale_iff _).1 hb
    simp only [Stack.api, Stack.rebuild, Stack.restartApi, List.mem_append, judgeInputs, List.mem_map] at hi
    rcases hi with ⟨x, _, rfl⟩ | ⟨x, _, rfl⟩ <;> simp [touched] at hc

/-- Restarting console-api without a rebuild leaves the core inputs stale: the new child comes from the stale binary on
disk, while console-api's own inputs are fresh.

$$\forall H, \Theta, j, c, x:\quad d \le j \wedge H[j] = c \wedge x \in c \wedge x \in K \Rightarrow \operatorname{stale}(\operatorname{api}(H, \operatorname{restartApi}(H, \Theta))) \wedge \operatorname{stale}(\operatorname{disk}(H, \operatorname{restartApi}(H, \Theta))) \wedge \neg\operatorname{stale}(\operatorname{judge}(H, |H|, \texttt{console-api}, A))$$
-/
theorem restartApi_without_rebuild_stale (hist : List (List String)) (apiOwn coreIn : List String) (t : Stack)
    (j : Nat) (hj : t.diskBase ≤ j) (c : List String) (hc : hist[j]? = some c) (x : String) (hx : x ∈ c)
    (hk : x ∈ coreIn) :
    ((t.restartApi hist).api hist apiOwn coreIn).staleB = true ∧
      ((t.restartApi hist).disk hist coreIn).staleB = true ∧
      (Svc.judge hist (t.restartApi hist).apiBase "console-api" apiOwn).staleB = false := by
  have ht := touched_of_mem hist t.diskBase j hj c hc x hx
  refine ⟨(Svc.stale_iff _).2 ⟨⟨x, touched hist t.diskBase x⟩, ?_, ht⟩,
    (Svc.stale_iff _).2 ⟨⟨x, touched hist t.diskBase x⟩, ?_, ht⟩, Svc.judge_head_not_stale hist "console-api" apiOwn⟩
  · simp only [Stack.api, Stack.restartApi, List.mem_append, judgeInputs, List.mem_map]
    exact .inr ⟨x, hk, rfl⟩
  · simp only [Stack.disk, Stack.restartApi, Svc.judge, judgeInputs, List.mem_map]
    exact ⟨x, hk, rfl⟩

/-- A child respawn picks up the disk: it clears console-api's core inputs exactly when the disk is current.

$$\operatorname{respawn}(\Theta) = (a, d, d)$$
-/
theorem respawn_coreBase (t : Stack) : t.respawn.coreBase = t.diskBase := rfl

/-! ### Which commit was a binary built from

The build script records the commit (`sha`) in a file written after the build succeeded, so the record is at least as
new as the binary. A plain `lake build` leaves the old record behind, older than the binary: such a record says
nothing. Then the build commit is read from the reflog of `main`: the newest ref move at or before the binary's time
(a build starts at a head of `main`; a land moves `main` 23-89 s after it). If that is ambiguous (no move at or before
the binary, or two moves in the same second), the commit is unknown. All times are seconds. -/

/-- The build commit of a binary: a commit, or unknown with the reason.

$$B = \mathrm{String} \uplus \mathrm{String}\quad(\text{commit} \mid \text{why unknown})$$
-/
inductive Base where
  | at (sha : String)
  | unknown (why : String)
deriving DecidableEq, Repr

/-- The base from the reflog of `main` (entries `(sha, time)`, newest first): the newest move at or before the binary
time `t_b`; unknown when there is none or two moves share its second.

$$\operatorname{fromLog}(t_b, L) = \begin{cases} \operatorname{at}(s) & L_{\le t_b} = (s, t) :: R,\ \forall (s', t') \in R.\ t' \ne t \\ \operatorname{unknown} & \text{otherwise}\end{cases}$$
-/
def fromLog (bin : Nat) (log : List (String × Nat)) : Base :=
  match log.filter (fun e => decide (e.2 ≤ bin)) with
  | [] => .unknown "no move of main at or before the binary"
  | (s, t) :: rest =>
    if rest.any (fun e => e.2 == t) then .unknown "two moves of main in the same second as the binary's base" else .at s

/-- The base commit of a binary with mtime `t_b`, given its build record `(sha, t_r)` (if any) and the reflog.

$$\operatorname{base}(t_b, r, L) = \begin{cases} \operatorname{at}(s) & r = (s, t_r),\ t_b \le t_r \\ \operatorname{fromLog}(t_b, L) & \text{otherwise}\end{cases}$$
-/
def chooseBase (bin : Nat) (rec : Option (String × Nat)) (log : List (String × Nat)) : Base :=
  match rec with
  | some (s, tr) => if bin ≤ tr then .at s else fromLog bin log
  | none => fromLog bin log

/-- A record not older than the binary is the base.

$$\forall s, t_r, L:\quad t_b \le t_r \Rightarrow \operatorname{base}(t_b, (s, t_r), L) = \operatorname{at}(s)$$
-/
theorem chooseBase_fresh (bin : Nat) (s : String) (tr : Nat) (log : List (String × Nat)) (h : bin ≤ tr) :
    chooseBase bin (some (s, tr)) log = .at s := by
  simp [chooseBase, h]

/-- A record older than the binary (binary mtime greater) is ignored: the answer is the reflog's.

$$\forall s, t_r, L:\quad t_r < t_b \Rightarrow \operatorname{base}(t_b, (s, t_r), L) = \operatorname{base}(t_b, \bot, L)$$
-/
theorem chooseBase_stale_record (bin : Nat) (s : String) (tr : Nat) (log : List (String × Nat)) (h : tr < bin) :
    chooseBase bin (some (s, tr)) log = chooseBase bin none log := by
  simp [chooseBase, Nat.not_le.2 h]

/-- No record and no move of `main` at or before the binary: unknown, never a guess.

$$\forall L:\quad (\forall (s, t) \in L.\ t_b < t) \Rightarrow \operatorname{base}(t_b, \bot, L) = \operatorname{unknown}$$
-/
theorem chooseBase_no_move (bin : Nat) (log : List (String × Nat)) (h : ∀ e ∈ log, bin < e.2) :
    ∃ why, chooseBase bin none log = .unknown why := by
  have hf : log.filter (fun e => decide (e.2 ≤ bin)) = [] := by
    apply List.filter_eq_nil_iff.2
    intro e he
    simpa using h e he
  exact ⟨"no move of main at or before the binary", by simp [chooseBase, fromLog, hf]⟩

/-- A commit named by the reflog was a head of `main` at or before the binary.

$$\forall s:\quad \operatorname{fromLog}(t_b, L) = \operatorname{at}(s) \Rightarrow \exists t \le t_b.\ (s, t) \in L$$
-/
theorem fromLog_mem (bin : Nat) (log : List (String × Nat)) (s : String) (h : fromLog bin log = .at s) :
    ∃ t, t ≤ bin ∧ (s, t) ∈ log := by
  unfold fromLog at h
  split at h
  · cases h
  · rename_i hs s' t rest hc
    split at h
    · cases h
    · cases h
      have hm : (s, t) ∈ log.filter (fun e => decide (e.2 ≤ bin)) := by rw [hc]; exact List.mem_cons_self
      rw [List.mem_filter] at hm
      exact ⟨t, by simpa using hm.2, hm.1⟩

-- A land builds in the pre-lock window: the binary is built at 1000 from head `old` (moved at 100); `main` moves to
-- `new` at 1030. A plain `lake build` leaves no record: the base is `old`, and `new`'s changes are then seen.
#guard chooseBase 1000 none [("new", 1030), ("old", 100)] == .at "old"
-- the same binary with a record from an older script build: the record is older than the binary, so ignored
#guard chooseBase 1000 (some ("ancient", 50)) [("new", 1030), ("old", 100)] == .at "old"
#guard chooseBase 1000 (some ("old", 1001)) [("new", 1030), ("old", 100)] == .at "old"
-- nothing identifies the build: unknown
#guard chooseBase 1000 none [("new", 1030)] == .unknown "no move of main at or before the binary"
#guard chooseBase 1000 none [] == .unknown "no move of main at or before the binary"
#guard chooseBase 1000 none [("b", 100), ("a", 100)] == .unknown "two moves of main in the same second as the binary's base"
-- a record exactly as new as the binary (same second) counts
#guard chooseBase 1000 (some ("rec", 1000)) [] == .at "rec"

end Fw.Obs
