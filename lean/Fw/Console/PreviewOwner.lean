import Fw.Console.Preview

/-!
# Owner login, LAN gate and idle stop for the task previews (console-lan-owner)

Pure rules behind three I/O pieces of `apps/console-api`. The console reads an owner passphrase from the macOS
keychain and offers `POST /owner/login`; this module decides (1) whether a login attempt may be tried at all (a
rate limit per client address), (2) which requests a LAN device may make and which need an owner session, and
(3) which previews the just-in-time rule stops (idle for 15 minutes, or past the 60 minute TTL).

What is proved is the decision; what is not: the constant-time compare of the passphrase, the cookie, the keychain
read, the socket (its remote address) and the proxy are I/O. Same-UID access (reading the keychain, ptrace) is an
accepted limit, as in `Fw.Console.Preview`.
-/

namespace Fw.Console.Preview.Owner

/-! ## 1. Login admission -/

/-- Tries allowed per window.

$$\mathit{maxTries} = 5$$ -/
def maxTries : Nat := 5

/-- The window in which failures are counted (ms).

$$\mathit{window} = 600000 = 10\ \text{min}$$ -/
def window : Nat := 600000

/-- How long an address stays locked after `maxTries` failures (ms).

$$\mathit{lock} = 600000 = 10\ \text{min}$$ -/
def lockMs : Nat := 600000

/-- The record of one client address: the times of its recent failures and the end of its lock (`0` = never locked).

$$r = (F, u)$$ with failure times $F \subseteq \mathbb{N}$ and lock end $u \in \mathbb{N}$. -/
structure Rec where
  fails : List Nat := []
  lockUntil : Nat := 0
deriving Repr, DecidableEq

/-- A try may be made now: the address is not locked.

$$\operatorname{open}(r, t) \iff r.u \le t$$ -/
def Rec.isOpen (r : Rec) (now : Nat) : Bool := decide (r.lockUntil ≤ now)

/-- The record after a failed try at `now`: failures older than the window are dropped, this one is added, and the
`maxTries`-th failure inside the window locks the address (the failure list restarts).

$$F' = \{f \in F : t < f + \mathit{window}\} \cup \{t\};\quad
r' = \begin{cases} (\emptyset,\ t + \mathit{lock}) & |F'| \ge \mathit{maxTries}\\ (F',\ 0) & \text{otherwise}\end{cases}$$ -/
def Rec.fail (r : Rec) (now : Nat) : Rec :=
  let fs := (r.fails.filter fun t => decide (now < t + window)) ++ [now]
  if maxTries ≤ fs.length then { fails := [], lockUntil := now + lockMs } else { fails := fs, lockUntil := 0 }

/-- What a login attempt gets. -/
inductive Verdict where
  | disabled | locked | wrong | ok
deriving Repr, DecidableEq

/-- Its wire name. -/
def Verdict.name : Verdict → String
  | .disabled => "disabled" | .locked => "locked" | .wrong => "wrong" | .ok => "ok"

/-- One login attempt at `now`. `enabled`: the console has an owner passphrase. `correct`: the (constant-time)
comparison of the presented passphrase matched. A locked address is refused before the answer is looked at; a
correct answer clears the address's record.

$$\operatorname{attempt}(r, t, e, c) = \begin{cases}
(\mathrm{disabled}, r) & \neg e\\
(\mathrm{locked}, r) & e \wedge t < r.u\\
(\mathrm{ok}, (\emptyset, 0)) & e \wedge r.u \le t \wedge c\\
(\mathrm{wrong}, r.\mathrm{fail}(t)) & e \wedge r.u \le t \wedge \neg c\end{cases}$$ -/
def attempt (r : Rec) (now : Nat) (enabled correct : Bool) : Verdict × Rec :=
  if !enabled then (.disabled, r)
  else if !r.isOpen now then (.locked, r)
  else if correct then (.ok, {}) else (.wrong, r.fail now)

/-- **A login succeeds only with the right passphrase, on an enabled console, from an unlocked address.**

$$\operatorname{attempt}(r,t,e,c).1 = \mathrm{ok} \Rightarrow e \wedge c \wedge r.u \le t$$ -/
theorem ok_only_if (r : Rec) (now : Nat) (e c : Bool) (h : (attempt r now e c).1 = .ok) :
    e = true ∧ c = true ∧ r.lockUntil ≤ now := by
  by_cases ho : r.lockUntil ≤ now
  · cases e <;> cases c <;> simp [attempt, Rec.isOpen, ho] at h ⊢ <;> omega
  · cases e <;> cases c <;> simp [attempt, Rec.isOpen, ho] at h

/-- **A lock holds against the right passphrase too.** While $t < r.u$ the attempt is refused whatever was
presented, and the record does not change (a refused try does not extend the lock).

$$t < r.u \wedge e \Rightarrow \operatorname{attempt}(r,t,e,c) = (\mathrm{locked}, r)$$ -/
theorem locked_refuses (r : Rec) (now : Nat) (c : Bool) (h : now < r.lockUntil) :
    attempt r now true c = (.locked, r) := by
  simp [attempt, Rec.isOpen]; omega

/-- A console without a passphrase refuses every login and counts nothing.

$$\operatorname{attempt}(r,t,\mathrm{false},c) = (\mathrm{disabled}, r)$$ -/
theorem disabled_refuses (r : Rec) (now : Nat) (c : Bool) : attempt r now false c = (.disabled, r) := rfl

/-- A failure list never reaches the limit: it locks first.

$$|(r.\mathrm{fail}(t)).F| < \mathit{maxTries}$$ -/
theorem fail_len_lt (r : Rec) (now : Nat) : (r.fail now).fails.length < maxTries := by
  unfold Rec.fail
  dsimp only
  split
  · simp [maxTries]
  · rename_i h; simp at h ⊢; omega

/-- **The `maxTries`-th failure inside the window locks the address for the full lock time.**

$$\mathit{maxTries} \le |\{f \in F : t < f + \mathit{window}\}| + 1 \Rightarrow (r.\mathrm{fail}(t)).u = t + \mathit{lock}$$ -/
theorem lock_after_max (r : Rec) (now : Nat)
    (h : maxTries ≤ (r.fails.filter fun t => decide (now < t + window)).length + 1) :
    (r.fail now).lockUntil = now + lockMs := by
  unfold Rec.fail
  simp [h]

/-- The attempts of one client that never knows the passphrase, at the (ascending) times `ts`: how many of them were
let through to a passphrase check, and the final record.

$$\operatorname{runWrong}(r, [\,]) = (0, r),\quad
\operatorname{runWrong}(r, t{::}ts) = \begin{cases}(1 + n,\ r'') & r.u \le t\\ \operatorname{runWrong}(r, ts) & \text{else}\end{cases}$$ -/
def runWrong : Rec → List Nat → Nat × Rec
  | r, [] => (0, r)
  | r, t :: ts =>
    if r.isOpen t then
      let p := runWrong (r.fail t) ts
      (p.1 + 1, p.2)
    else runWrong r ts

/-- The invariant of a window that starts at `t₀`: either unlocked with fewer than `maxTries` failures, all inside
the window, or locked until after the window ends.

$$\mathrm{Inv}_{t_0}(r) \iff \big(r.u = 0 \wedge |F| < \mathit{maxTries} \wedge \forall f \in F: t_0 \le f\big) \vee t_0 + \mathit{window} \le r.u$$ -/
def Inv (t0 : Nat) (r : Rec) : Prop :=
  (r.lockUntil = 0 ∧ r.fails.length < maxTries ∧ ∀ f ∈ r.fails, t0 ≤ f) ∨ t0 + window ≤ r.lockUntil

/-- The tries already used up in the window.

$$\varphi_{t_0}(r) = \begin{cases}\mathit{maxTries} & t_0 + \mathit{window} \le r.u\\ |F| & \text{else}\end{cases}$$ -/
def used (t0 : Nat) (r : Rec) : Nat := if t0 + window ≤ r.lockUntil then maxTries else r.fails.length

/-- The induction behind `no_unbounded_tries`: tries let through plus tries used up never exceed `maxTries`.

$$\mathrm{Inv}_{t_0}(r) \wedge (\forall t \in ts: t_0 \le t < t_0 + \mathit{window}) \Rightarrow n(r, ts) + \varphi_{t_0}(r) \le \mathit{maxTries}$$ -/
theorem runWrong_le (t0 : Nat) : ∀ (ts : List Nat) (r : Rec), Inv t0 r →
    (∀ t ∈ ts, t0 ≤ t ∧ t < t0 + window) → (runWrong r ts).1 + used t0 r ≤ maxTries := by
  intro ts
  induction ts with
  | nil =>
    intro r hi _
    simp only [runWrong, used]
    split
    · omega
    · rcases hi with ⟨_, h2, _⟩ | h
      · omega
      · contradiction
  | cons t ts ih =>
    intro r hi hts
    have ht := hts t (by simp)
    have hts' : ∀ u ∈ ts, t0 ≤ u ∧ u < t0 + window := fun u hu => hts u (by simp [hu])
    have hw : window = 600000 := rfl
    have hl : lockMs = 600000 := rfl
    have hm : maxTries = 5 := rfl
    by_cases hlock : t0 + window ≤ r.lockUntil
    · have hno : r.isOpen t = false := by simp [Rec.isOpen]; omega
      simp only [runWrong, hno]
      simpa using ih r hi hts'
    · rcases hi with ⟨h0, hlen, hf⟩ | h
      · have hopen : r.isOpen t = true := by simp [Rec.isOpen, h0]
        have hfilt : (r.fails.filter fun u => decide (t < u + window)) = r.fails := by
          rw [List.filter_eq_self]
          intro a ha
          have := hf a ha
          simp; omega
        have hu : used t0 r = r.fails.length := by simp [used, hlock]
        have hrun : runWrong r (t :: ts) = ((runWrong (r.fail t) ts).1 + 1, (runWrong (r.fail t) ts).2) := by
          simp [runWrong, hopen]
        rw [hrun]
        dsimp only
        by_cases hmx : maxTries ≤ r.fails.length + 1
        · have hr : r.fail t = { fails := [], lockUntil := t + lockMs } := by
            unfold Rec.fail; simp [hfilt, hmx]
          have hin : Inv t0 (r.fail t) := by
            rw [hr]; right; show t0 + window ≤ t + lockMs; omega
          have := ih (r.fail t) hin hts'
          rw [hr] at this ⊢
          have hu' : used t0 { fails := [], lockUntil := t + lockMs } = maxTries := by
            have hq : t0 + window ≤ t + lockMs := by omega
            simp [used, hq]
          rw [hu'] at this
          omega
        · have hr : r.fail t = { fails := r.fails ++ [t], lockUntil := 0 } := by
            unfold Rec.fail; simp [hfilt, hmx]
          have hin : Inv t0 (r.fail t) := by
            rw [hr]; left
            refine ⟨rfl, ?_, ?_⟩
            · simp; omega
            · intro f hf'
              simp at hf'
              rcases hf' with h | h
              · exact hf f h
              · omega
          have := ih (r.fail t) hin hts'
          rw [hr] at this ⊢
          have hu' : used t0 { fails := r.fails ++ [t], lockUntil := 0 } = r.fails.length + 1 := by
            have hq : ¬ t0 + window ≤ 0 := by omega
            simp [used, hq]
          rw [hu'] at this
          omega
      · exact absurd h hlock

/-- **No unbounded tries.** A client that never knows the passphrase and tries as often as it likes during any span
shorter than the window (10 min) is let through to at most `maxTries` (5) passphrase checks; the rest meet the lock.

$$\forall ts:\ (\forall t \in ts:\ t_0 \le t < t_0 + \mathit{window}) \Rightarrow n(\varnothing, ts) \le \mathit{maxTries}$$ -/
theorem no_unbounded_tries (t0 : Nat) (ts : List Nat) (h : ∀ t ∈ ts, t0 ≤ t ∧ t < t0 + window) :
    (runWrong {} ts).1 ≤ maxTries := by
  have hi : Inv t0 ({} : Rec) := Or.inl ⟨rfl, by simp [maxTries], by simp⟩
  have := runWrong_le t0 ts {} hi h
  omega

/-! ## 2. Which requests a LAN device may make -/

/-- The class of a request path: the login page (`/owner/login`, GET and POST), a preview (`/preview/…`), or the rest
(the console web, `/api/…`, `/owner` with the tty link).

$$\operatorname{cls}(p) = \begin{cases}\mathrm{login} & p = \texttt{/owner/login}\\ \mathrm{preview} & p \text{ starts with } \texttt{/preview/}\\ \mathrm{other} & \text{else}\end{cases}$$ -/
inductive Cls where
  | login | preview | other
deriving Repr, DecidableEq

/-- Its wire name. -/
def Cls.name : Cls → String
  | .login => "login" | .preview => "preview" | .other => "other"

/-- The class of a path (exact match for the login page: any other spelling is `other`, hence gated). -/
def classify (path : String) : Cls :=
  if path == "/owner/login" then .login else if path.startsWith "/preview/" then .preview else .other

/-- **The login page is exactly one path.**

$$\operatorname{cls}(p) = \mathrm{login} \iff p = \texttt{/owner/login}$$ -/
theorem classify_login_iff (p : String) : classify p = .login ↔ p = "/owner/login" := by
  unfold classify
  by_cases h : p = "/owner/login"
  · simp [h]
  · have : (p == "/owner/login") = false := by simpa using h
    simp [this, h]
    split <;> simp

/-- Whether a request is served. `lan`: it arrived from a non-loopback address (or an unknown one). `session`: it
carries a valid owner session. `hostOk`: its Host header names this console. A LAN request with another Host is
refused; the login page is open to LAN; a preview needs a session wherever it comes from; everything else on LAN needs
a session and on loopback keeps today's rules.

$$\operatorname{allow}(\ell, s, h, c) = \neg(\ell \wedge \neg h) \wedge \begin{cases}\mathrm{true} & c = \mathrm{login}\\ s & c = \mathrm{preview}\\ \neg\ell \vee s & c = \mathrm{other}\end{cases}$$ -/
def allow (lan session hostOk : Bool) (c : Cls) : Bool :=
  (!lan || hostOk) && (match c with | .login => true | .preview => session | .other => !lan || session)

/-- **A LAN request without an owner session reaches the login page and nothing else.**

$$\ell \wedge \operatorname{allow}(\ell, s, h, c) \Rightarrow c = \mathrm{login} \vee s$$ -/
theorem lan_requires_owner (session hostOk : Bool) (c : Cls) (h : allow true session hostOk c = true) :
    c = .login ∨ session = true := by
  cases c <;> simp_all [allow]

/-- The same, from the path.

$$\ell \wedge \neg s \wedge \operatorname{allow}(\ell, s, h, \operatorname{cls}(p)) \Rightarrow p = \texttt{/owner/login}$$ -/
theorem lan_path_requires_owner (hostOk : Bool) (p : String) (h : allow true false hostOk (classify p) = true) :
    p = "/owner/login" := by
  rcases lan_requires_owner false hostOk _ h with h1 | h1
  · exact (classify_login_iff p).1 h1
  · contradiction

/-- **A preview is never served without an owner session**, from loopback or from the LAN.

$$\operatorname{allow}(\ell, s, h, \mathrm{preview}) \Rightarrow s$$ -/
theorem preview_requires_owner (lan session hostOk : Bool) (h : allow lan session hostOk .preview = true) :
    session = true := by
  simp_all [allow]

/-- **Loopback keeps today's rules** for everything but previews.

$$\neg\ell \wedge c \ne \mathrm{preview} \Rightarrow \operatorname{allow}(\ell, s, h, c)$$ -/
theorem loopback_unchanged (session hostOk : Bool) (c : Cls) (hc : c ≠ .preview) :
    allow false session hostOk c = true := by
  cases c <;> simp_all [allow]

/-- **The owner's phone can reach the login page** (right Host, any session state).

$$\operatorname{allow}(\ell, s, \mathrm{true}, \mathrm{login})$$ -/
theorem login_reachable (lan session : Bool) : allow lan session true .login = true := by
  simp [allow]

/-- A LAN request whose Host is not this console is refused whatever it carries (DNS rebinding).

$$\operatorname{allow}(\mathrm{true}, s, \mathrm{false}, c) = \mathrm{false}$$ -/
theorem lan_wrong_host (session : Bool) (c : Cls) : allow true session false c = false := by
  cases c <;> simp [allow]

/-! ## 3. Just-in-time previews: idle stop and TTL -/

/-- A preview idle for this long is stopped (ms).

$$\mathit{idle} = 900000 = 15\ \text{min}$$ -/
def idleLimit : Nat := 900000

/-- A live preview with the time of its last proxied request (ms); the time it started serving until one comes.

$$l = (p, \mathit{seen})$$ -/
structure Live where
  pv : Pv
  seen : Nat

/-- It stays: inside the TTL and not idle.

$$\operatorname{alive}(l, t) \iff t < l.p.t_0 + \mathit{ttl} \ \wedge\ t < l.\mathit{seen} + \mathit{idle}$$ -/
def Live.alive (l : Live) (now : Nat) : Bool := decide (now < l.pv.deadline) && decide (now < l.seen + idleLimit)

/-- The previews that stay at `now`.

$$\operatorname{sweep}(L, t) = [\,l \in L : \operatorname{alive}(l, t)\,]$$ -/
def sweep (s : List Live) (now : Nat) : List Live := s.filter (·.alive now)

/-- The previews that are stopped at `now`.

$$\operatorname{reaped}(L, t) = [\,l \in L : \neg\operatorname{alive}(l, t)\,]$$ -/
def reaped (s : List Live) (now : Nat) : List Live := s.filter fun l => !l.alive now

/-- Why a preview was stopped: the TTL, else idleness.

$$\operatorname{why}(l, t) = \begin{cases}\mathrm{ttl} & l.p.t_0 + \mathit{ttl} \le t\\ \mathrm{idle} & \text{else}\end{cases}$$ -/
def why (l : Live) (now : Nat) : String := if l.pv.deadline ≤ now then "ttl" else "idle"

/-- **TTL stops.** A preview at or past its 60 minute deadline is reaped and does not stay, however recently it was used.

$$l.p.t_0 + \mathit{ttl} \le t \Rightarrow l \in \operatorname{reaped}(L, t) \wedge l \notin \operatorname{sweep}(L, t)$$ -/
theorem ttl_stops (s : List Live) (now : Nat) (l : Live) (hl : l ∈ s) (h : l.pv.started + ttl ≤ now) :
    l ∈ reaped s now ∧ l ∉ sweep s now := by
  have hn : l.alive now = false := by
    have : ¬ now < l.pv.deadline := by simp [Pv.deadline]; omega
    simp [Live.alive, this]
  refine ⟨List.mem_filter.mpr ⟨hl, by simp [hn]⟩, fun hm => ?_⟩
  have := (List.mem_filter.mp hm).2
  simp [hn] at this

/-- **Idle stops.** A preview with no proxied request for 15 minutes is reaped and does not stay.

$$l.\mathit{seen} + \mathit{idle} \le t \Rightarrow l \in \operatorname{reaped}(L, t) \wedge l \notin \operatorname{sweep}(L, t)$$ -/
theorem idle_stops (s : List Live) (now : Nat) (l : Live) (hl : l ∈ s) (h : l.seen + idleLimit ≤ now) :
    l ∈ reaped s now ∧ l ∉ sweep s now := by
  have hn : l.alive now = false := by
    have : ¬ now < l.seen + idleLimit := by omega
    simp [Live.alive, this]
  refine ⟨List.mem_filter.mpr ⟨hl, by simp [hn]⟩, fun hm => ?_⟩
  have := (List.mem_filter.mp hm).2
  simp [hn] at this

/-- **What stays is young and busy.**

$$l \in \operatorname{sweep}(L, t) \Rightarrow t < l.p.t_0 + \mathit{ttl} \wedge t < l.\mathit{seen} + \mathit{idle}$$ -/
theorem sweep_young (s : List Live) (now : Nat) (l : Live) (h : l ∈ sweep s now) :
    now < l.pv.started + ttl ∧ now < l.seen + idleLimit := by
  have := (List.mem_filter.mp h).2
  simp [Live.alive, Pv.deadline] at this
  exact ⟨of_decide_eq_true this.1, this.2⟩

/-- **Nothing is lost.** The stayers and the stopped ones are the table, in some order.

$$\operatorname{sweep}(L, t) \mathbin{+\!\!+} \operatorname{reaped}(L, t) \sim L$$ -/
theorem sweep_partition (s : List Live) (now : Nat) : (sweep s now ++ reaped s now).Perm s := by
  unfold sweep reaped
  have := List.filter_append_perm (fun l : Live => l.alive now) s
  simpa using this

/-- **A request keeps a preview alive.** A preview used at `t` (so `seen = t`) and inside its TTL stays until 15 minutes
after `t`.

$$l.\mathit{seen} = t \wedge t' < t + \mathit{idle} \wedge t' < l.p.t_0 + \mathit{ttl} \Rightarrow \operatorname{alive}(l, t')$$ -/
theorem touch_keeps (l : Live) (t t' : Nat) (hs : l.seen = t) (h1 : t' < t + idleLimit) (h2 : t' < l.pv.started + ttl) :
    l.alive t' = true := by
  simp only [Live.alive, Pv.deadline, Bool.and_eq_true, decide_eq_true_eq]
  exact ⟨decide_eq_true h2, by omega⟩

/-- **Why is exact.** The reason is `ttl` exactly when the deadline passed.

$$\operatorname{why}(l, t) = \mathrm{ttl} \iff l.p.t_0 + \mathit{ttl} \le t$$ -/
theorem why_ttl_iff (l : Live) (now : Nat) : why l now = "ttl" ↔ l.pv.started + ttl ≤ now := by
  unfold why Pv.deadline
  split <;> simp_all

end Fw.Console.Preview.Owner
