import Fw.Console.Preview

/-!
# Owner login, LAN gate, preview origin and idle stop for the task previews (console-lan-owner)

Pure rules behind the I/O pieces of `apps/console-api`. The console reads an owner passphrase from the macOS
keychain and offers `POST /owner/login`; this module decides (1) whether a login attempt may be tried at all (a
rate limit per client address and one across all addresses), (2) which requests a LAN device may make and which need
the owner token, (3) which origin may act as the owner (the previews run on their own port, hence their own origin,
and never share the console's), and (4) which previews the just-in-time rule stops (idle for 15 minutes, or past the
60 minute TTL).

What is proved is the decision; what is not: the constant-time compare of the passphrase, the cookies, the keychain
read, the socket (its remote address), the browser's own `Origin` header and the proxy are I/O. Same-UID access
(reading the keychain, ptrace) is an accepted limit, as in `Fw.Console.Preview`.
-/

namespace Fw.Console.Preview.Owner

/-! ## 1. Login admission -/

/-- Tries allowed per window, per client address. -/
def maxTries : Nat := 5

/-- The window in which failures are counted (ms). -/
def window : Nat := 600000

/-- How long an address stays locked after `maxTries` failures (ms). -/
def lockMs : Nat := 600000

/-- Failed tries allowed per window across all client addresses together. -/
def globMax : Nat := 20

/-- The window of the global count (ms). -/
def globWindow : Nat := 600000

/-- How long every address is locked after `globMax` failures in the window (ms). -/
def globLock : Nat := 600000

/-- The record of one counter (one client address, or the global one): the times of its recent failures, in order and
with repeats, and the end of its lock (`0` = never locked). -/
structure Rec where
  fails : List Nat := []
  lockUntil : Nat := 0
deriving Repr, DecidableEq

/-- A try may be made now: the counter is not locked. -/
def Rec.isOpen (r : Rec) (now : Nat) : Bool := decide (r.lockUntil ≤ now)

/-- The record after a failed try at `now` under limit `m`, window `w` and lock time `l`: failures older than the window
are dropped, this one is added at the end, and the `m`-th failure inside the window locks the counter (the list restarts). -/
def Rec.failW (m w l : Nat) (r : Rec) (now : Nat) : Rec :=
  let fs := (r.fails.filter fun t => decide (now < t + w)) ++ [now]
  if m ≤ fs.length then { fails := [], lockUntil := now + l } else { fails := fs, lockUntil := 0 }

/-- The per-address failure: `m = maxTries`, `w = window`, `l = lock`. -/
def Rec.fail (r : Rec) (now : Nat) : Rec := r.failW maxTries window lockMs now

/-- What a login attempt gets. -/
inductive Verdict where
  | disabled | locked | wrong | ok
deriving Repr, DecidableEq

/-- Its wire name. -/
def Verdict.name : Verdict → String
  | .disabled => "disabled" | .locked => "locked" | .wrong => "wrong" | .ok => "ok"

/-- One login attempt at `now`, with the record `r` of the client's address and the global record `g`. `enabled`: the
console has an owner passphrase. `correct`: the (constant-time) comparison of the presented passphrase matched. An
attempt is refused before the answer is looked at when the address or the global counter is locked. A correct answer
clears the address's record; a wrong one is counted at the address and globally. -/
def attempt (r g : Rec) (now : Nat) (enabled correct : Bool) : Verdict × Rec × Rec :=
  if !enabled then (.disabled, r, g)
  else if !(r.isOpen now && g.isOpen now) then (.locked, r, g)
  else if correct then (.ok, {}, g) else (.wrong, r.fail now, g.failW globMax globWindow globLock now)

/-- **A login succeeds only with the right passphrase, on an enabled console, from an unlocked address, while the
global counter is not locked.** -/
theorem ok_only_if (r g : Rec) (now : Nat) (e c : Bool) (h : (attempt r g now e c).1 = .ok) :
    e = true ∧ c = true ∧ r.lockUntil ≤ now ∧ g.lockUntil ≤ now := by
  by_cases ho : r.lockUntil ≤ now <;> by_cases hg : g.lockUntil ≤ now <;>
    cases e <;> cases c <;> simp [attempt, Rec.isOpen, ho, hg] at h ⊢

/-- **A lock holds against the right passphrase too.** While `t < r.u` or `t < g.u` the attempt is refused whatever was
presented, and neither record changes (a refused try does not extend a lock). -/
theorem locked_refuses (r g : Rec) (now : Nat) (c : Bool) (h : now < r.lockUntil ∨ now < g.lockUntil) :
    attempt r g now true c = (.locked, r, g) := by
  rcases h with h | h <;> simp [attempt, Rec.isOpen] <;> omega

/-- A console without a passphrase refuses every login and counts nothing. -/
theorem disabled_refuses (r g : Rec) (now : Nat) (c : Bool) : attempt r g now false c = (.disabled, r, g) := rfl

/-- A failure list never reaches the limit: it locks first. -/
theorem failW_len_lt (m w l : Nat) (hm : 0 < m) (r : Rec) (now : Nat) : (r.failW m w l now).fails.length < m := by
  unfold Rec.failW
  dsimp only
  split
  · simpa using hm
  · rename_i h; simp at h ⊢; omega

/-- The per-address list never reaches the limit. -/
theorem fail_len_lt (r : Rec) (now : Nat) : (r.fail now).fails.length < maxTries :=
  failW_len_lt maxTries window lockMs (by decide) r now

/-- **The `maxTries`-th failure inside the window locks the address for the full lock time.** -/
theorem lock_after_max (r : Rec) (now : Nat)
    (h : maxTries ≤ (r.fails.filter fun t => decide (now < t + window)).length + 1) :
    (r.fail now).lockUntil = now + lockMs := by
  unfold Rec.fail Rec.failW
  simp [h]

/-- The invariant of a window that starts at `t_0` under limit `m` and window `w`: either unlocked with fewer than `m`
failures, all inside the window, or locked until after the window ends. -/
def InvP (m w t0 : Nat) (r : Rec) : Prop :=
  (r.lockUntil = 0 ∧ r.fails.length < m ∧ ∀ f ∈ r.fails, t0 ≤ f) ∨ t0 + w ≤ r.lockUntil

/-- The tries already used up in the window. -/
def usedP (m w t0 : Nat) (r : Rec) : Nat := if t0 + w ≤ r.lockUntil then m else r.fails.length

/-- The invariant keeps the used tries within the limit. -/
theorem usedP_le (m w t0 : Nat) (r : Rec) (h : InvP m w t0 r) : usedP m w t0 r ≤ m := by
  unfold usedP
  split
  · exact Nat.le_refl _
  · rcases h with ⟨_, h2, _⟩ | h
    · omega
    · contradiction

/-- **One failed try inside the window keeps the invariant and uses up at least one more try.** For an open counter
and a time `t` with `t_0 ≤ t < t_0 + w` (and `0 < w ≤ l`). -/
theorem fail_step (m w l t0 t : Nat) (r : Rec) (hw : 0 < w) (hwl : w ≤ l) (hi : InvP m w t0 r)
    (hopen : r.isOpen t = true) (ht : t0 ≤ t ∧ t < t0 + w) :
    InvP m w t0 (r.failW m w l t) ∧ usedP m w t0 r + 1 ≤ usedP m w t0 (r.failW m w l t) := by
  rcases hi with ⟨h0, hlen, hf⟩ | h
  · have hfilt : (r.fails.filter fun u => decide (t < u + w)) = r.fails := by
      rw [List.filter_eq_self]
      intro a ha
      have := hf a ha
      simp; omega
    have hu : usedP m w t0 r = r.fails.length := by simp [usedP, h0]; omega
    by_cases hmx : m ≤ r.fails.length + 1
    · have hr : r.failW m w l t = { fails := [], lockUntil := t + l } := by
        unfold Rec.failW; simp [hfilt, hmx]
      rw [hr]
      refine ⟨Or.inr (by show t0 + w ≤ t + l; omega), ?_⟩
      have hq : t0 + w ≤ t + l := by omega
      have hu' : usedP m w t0 { fails := [], lockUntil := t + l } = m := by simp [usedP, hq]
      rw [hu, hu']
      omega
    · have hr : r.failW m w l t = { fails := r.fails ++ [t], lockUntil := 0 } := by
        unfold Rec.failW; simp [hfilt, hmx]
      rw [hr]
      have hq : ¬ t0 + w ≤ 0 := by omega
      refine ⟨Or.inl ⟨rfl, ?_, ?_⟩, ?_⟩
      · simp; omega
      · intro f hf'
        simp at hf'
        rcases hf' with h | h
        · exact hf f h
        · omega
      · have hu' : usedP m w t0 { fails := r.fails ++ [t], lockUntil := 0 } = r.fails.length + 1 := by
          simp [usedP, hq]
        rw [hu, hu']
        omega
  · exfalso
    simp [Rec.isOpen] at hopen
    omega

/-- The attempts of one client address that never knows the passphrase, at the (ascending) times `ts`: how many of them
were let through to a passphrase check, and the final record. -/
def runWrong : Rec → List Nat → Nat × Rec
  | r, [] => (0, r)
  | r, t :: ts =>
    if r.isOpen t then
      let p := runWrong (r.fail t) ts
      (p.1 + 1, p.2)
    else runWrong r ts

/-- The induction behind `no_unbounded_tries`: tries let through plus tries used up never exceed `maxTries`. Here
`n(r, ts) := runWrong(r, ts).1`. -/
theorem runWrong_le (t0 : Nat) : ∀ (ts : List Nat) (r : Rec), InvP maxTries window t0 r →
    (∀ t ∈ ts, t0 ≤ t ∧ t < t0 + window) → (runWrong r ts).1 + usedP maxTries window t0 r ≤ maxTries := by
  intro ts
  induction ts with
  | nil =>
    intro r hi _
    have := usedP_le _ _ _ _ hi
    simpa [runWrong] using this
  | cons t ts ih =>
    intro r hi hts
    have ht := hts t (by simp)
    have hts' : ∀ u ∈ ts, t0 ≤ u ∧ u < t0 + window := fun u hu => hts u (by simp [hu])
    by_cases hopen : r.isOpen t = true
    · have hrun : runWrong r (t :: ts) = ((runWrong (r.fail t) ts).1 + 1, (runWrong (r.fail t) ts).2) := by
        simp [runWrong, hopen]
      rw [hrun]
      obtain ⟨hin, hus⟩ : InvP maxTries window t0 (r.fail t) ∧ usedP maxTries window t0 r + 1 ≤ usedP maxTries window t0 (r.fail t) :=
        fail_step maxTries window lockMs t0 t r (by decide) (by decide) hi hopen ht
      have := ih (r.fail t) hin hts'
      dsimp only
      omega
    · have hno : r.isOpen t = false := by simpa using hopen
      have : runWrong r (t :: ts) = runWrong r ts := by simp [runWrong, hno]
      rw [this]
      exact ih r hi hts'

/-- **No unbounded tries from one address.** A client that never knows the passphrase and tries as often as it likes
during any span shorter than the window (10 min) is let through to at most `maxTries` (5) passphrase checks; the rest
meet the lock. Here `∅` is the record `([], 0)`. -/
theorem no_unbounded_tries (t0 : Nat) (ts : List Nat) (h : ∀ t ∈ ts, t0 ≤ t ∧ t < t0 + window) :
    (runWrong {} ts).1 ≤ maxTries := by
  have hi : InvP maxTries window t0 ({} : Rec) := Or.inl ⟨rfl, by simp [maxTries], by simp⟩
  have := runWrong_le t0 ts {} hi h
  omega

/-- **What one attempt does to the global counter.** With a wrong passphrase on an enabled console: a `wrong` verdict
means the global counter was open and was charged one failure; any other verdict leaves it unchanged. -/
theorem attempt_global_step (r g : Rec) (now : Nat) :
    ((attempt r g now true false).1 = .wrong →
      g.isOpen now = true ∧ (attempt r g now true false).2.2 = g.failW globMax globWindow globLock now) ∧
    ((attempt r g now true false).1 ≠ .wrong → (attempt r g now true false).2.2 = g) := by
  by_cases ho : r.isOpen now = true <;> by_cases hg : g.isOpen now = true <;> simp [attempt, ho, hg]

/-- A record table with one address changed. -/
def upd (rs : Nat → Rec) (a : Nat) (r : Rec) : Nat → Rec := fun b => if b = a then r else rs b

/-- The attempts of any number of clients, each `(address, time)` (ascending times), none of which knows the
passphrase: how many were let through to a passphrase check (verdict `wrong`), and the final global record. The records
of the addresses are an arbitrary function from address to record, updated as `attempt` says.

In the second line, `(v, r', g') = attempt(ρ(a), g, t, true, false)` and
`(n, g'') = runSys(g', ρ[a ↦ r'], as)`. -/
def runSys : Rec → (Nat → Rec) → List (Nat × Nat) → Nat × Rec
  | g, _, [] => (0, g)
  | g, rs, (a, t) :: ts =>
    let x := attempt (rs a) g t true false
    let p := runSys x.2.2 (upd rs a x.2.1) ts
    (if x.1 = .wrong then p.1 + 1 else p.1, p.2)

/-- The induction behind `global_bound`: checks let through plus global tries used up never exceed `globMax`.

Here `n = runSys(g,ρ,as).1`, and the invariant
and `φ` are taken at `m = globMax`, `w = globWindow`. -/
theorem runSys_le (t0 : Nat) : ∀ (ts : List (Nat × Nat)) (g : Rec) (rs : Nat → Rec), InvP globMax globWindow t0 g →
    (∀ p ∈ ts, t0 ≤ p.2 ∧ p.2 < t0 + globWindow) → (runSys g rs ts).1 + usedP globMax globWindow t0 g ≤ globMax := by
  intro ts
  induction ts with
  | nil =>
    intro g rs hi _
    have := usedP_le _ _ _ _ hi
    simpa [runSys] using this
  | cons p ts ih =>
    intro g rs hi hts
    obtain ⟨a, t⟩ := p
    have ht := hts (a, t) (by simp)
    have hts' : ∀ q ∈ ts, t0 ≤ q.2 ∧ q.2 < t0 + globWindow := fun q hq => hts q (by simp [hq])
    obtain ⟨hw, hn⟩ := attempt_global_step (rs a) g t
    by_cases hv : (attempt (rs a) g t true false).1 = .wrong
    · obtain ⟨hopen, hg'⟩ := hw hv
      obtain ⟨hin, hus⟩ := fail_step globMax globWindow globLock t0 t g (by decide) (by decide) hi hopen ht
      have := ih (attempt (rs a) g t true false).2.2 (upd rs a (attempt (rs a) g t true false).2.1)
        (by rw [hg']; exact hin) hts'
      rw [hg'] at this
      simp only [runSys, hv, ite_true]
      rw [hg']
      omega
    · have hg' := hn hv
      have := ih (attempt (rs a) g t true false).2.2 (upd rs a (attempt (rs a) g t true false).2.1)
        (by rw [hg']; exact hi) hts'
      rw [hg'] at this
      simp only [runSys, hv, ite_false]
      rw [hg']
      exact this

/-- **A global bound on guesses.** Whatever the number of client addresses, however they are spread, and whatever the
per-address records are to begin with, all clients together who never know the passphrase are let through to at most
`globMax` (20) passphrase checks during any span shorter than the global window (10 min); every later try meets the
global lock. Here `∅` is the record `([],0)` and `n = runSys(∅,ρ,as).1`. -/
theorem global_bound (t0 : Nat) (ts : List (Nat × Nat)) (rs : Nat → Rec)
    (h : ∀ p ∈ ts, t0 ≤ p.2 ∧ p.2 < t0 + globWindow) : (runSys {} rs ts).1 ≤ globMax := by
  have hi : InvP globMax globWindow t0 ({} : Rec) := Or.inl ⟨rfl, by simp [globMax], by simp⟩
  have := runSys_le t0 ts {} rs hi h
  omega

/-- LAN mode starts only with an owner passphrase of at least this many characters. -/
def minPass : Nat := 12

/-- Whether LAN mode starts: it was asked for, a private address was found, and the keychain passphrase is long enough.
The result names why not, without any detail of the passphrase. -/
def lanStart (want hasAddr hasPass : Bool) (len : Nat) : String :=
  if !want then "off" else if !hasAddr then "noAddress" else if !hasPass then "noPassphrase"
  else if len < minPass then "shortPassphrase" else "start"

/-- **LAN mode needs a long passphrase.** -/
theorem lan_start_requires_long (want hasAddr hasPass : Bool) (len : Nat)
    (h : lanStart want hasAddr hasPass len = "start") :
    want = true ∧ hasAddr = true ∧ hasPass = true ∧ minPass ≤ len := by
  unfold lanStart at h
  cases want <;> cases hasAddr <;> cases hasPass <;> simp at h ⊢
  all_goals (first | omega | (simp [minPass] at *; omega))

/-! ## 2. Which requests a LAN device may make (console port) -/

/-- The class of a request path on the console port: the login page (`/owner/login`, GET and POST), a preview path
(`/preview/…`, which the console port never serves: previews have their own port), the data and action paths (`/api/…`,
`/owner…`, which carry the owner's data), or the shell (every other path: the built console web, static files that hold no
data and make no request by themselves). -/
inductive Cls where
  | login | preview | other | shell
deriving Repr, DecidableEq

/-- Its wire name. -/
def Cls.name : Cls → String
  | .login => "login" | .preview => "preview" | .other => "other" | .shell => "shell"

/-- The class of a path (exact match for the login page: any other spelling under `/owner` is `other`, hence gated). -/
def classify (path : String) : Cls :=
  if path == "/owner/login" then .login
  else if path.startsWith "/preview/" then .preview
  else if path == "/api" || path.startsWith "/api/" || path == "/owner" || path.startsWith "/owner/" then .other
  else .shell

/-- **The login page is exactly one path.** -/
theorem classify_login_iff (p : String) : classify p = .login ↔ p = "/owner/login" := by
  constructor
  · intro hc
    refine Classical.byContradiction fun hne => ?_
    have hb : (p == "/owner/login") = false := by simpa using hne
    unfold classify at hc
    simp only [hb, Bool.false_eq_true, ↓reduceIte] at hc
    split at hc <;> (try split at hc) <;> simp at hc
  · intro h
    subst h
    simp [classify]

/-- Whether the console port serves a request. `lan`: it arrived from a non-loopback address (or an unknown one).
`bearer`: it carries a valid owner token in its `Authorization` header (never a cookie). `hostOk`: its Host header names
this console. A LAN request with another Host is refused; the login page and the shell are open to LAN (a browser
cannot attach a header to a page load; the shell holds no data); the console never serves a preview path (previews live
on their own port, hence their own origin); every data or action path on LAN needs the bearer token, and on loopback keeps
today's rules. -/
def allow (lan bearer hostOk : Bool) (c : Cls) : Bool :=
  (!lan || hostOk) && (match c with | .login => true | .shell => true | .preview => false | .other => !lan || bearer)

/-- **A LAN request without the owner token reaches the login page and the shell and nothing else.** What Lean proves is
the implication (not an equivalence: with a foreign Host nothing is served, see `lan_wrong_host`). -/
theorem lan_requires_owner (bearer hostOk : Bool) (c : Cls) (h : allow true bearer hostOk c = true) :
    c = .login ∨ c = .shell ∨ bearer = true := by
  cases c <;> simp_all [allow]

/-- With the right Host the LAN rule is exact. -/
theorem lan_allow_iff (bearer : Bool) (c : Cls) :
    allow true bearer true c = true ↔ c = .login ∨ c = .shell ∨ (c = .other ∧ bearer = true) := by
  cases c <;> simp [allow]

/-- The same, from the path: with no token, an allowed LAN request is the login page or a shell path. -/
theorem lan_path_requires_owner (hostOk : Bool) (p : String) (h : allow true false hostOk (classify p) = true) :
    classify p = .login ∨ classify p = .shell := by
  rcases lan_requires_owner false hostOk _ h with h1 | h1 | h1
  · exact Or.inl h1
  · exact Or.inr h1
  · contradiction

/-- **No data path is a shell path**: a path under `/api/` or `/owner/` is never the open shell. -/
theorem data_paths_not_shell (p : String) (h : p.startsWith "/api/" = true ∨ p.startsWith "/owner/" = true) :
    classify p ≠ .shell := by
  unfold classify
  intro hc
  split at hc
  · simp at hc
  split at hc
  · simp at hc
  split at hc
  · simp at hc
  rename_i h1 h2 h3
  rcases h with h | h <;> simp_all

/-- **The console port never serves a preview path**, from loopback or from the LAN, with or without a token. -/
theorem console_never_serves_preview (lan bearer hostOk : Bool) : allow lan bearer hostOk .preview = false := by
  simp [allow]

/-- **Loopback keeps today's rules** for everything but preview paths. -/
theorem loopback_unchanged (bearer hostOk : Bool) (c : Cls) (hc : c ≠ .preview) :
    allow false bearer hostOk c = true := by
  cases c <;> simp_all [allow]

/-- **The owner's phone can reach the login page** (right Host, any token state). -/
theorem login_reachable (lan bearer : Bool) : allow lan bearer true .login = true := by
  simp [allow]

/-- A LAN request whose Host is not this console is refused whatever it carries (DNS rebinding). -/
theorem lan_wrong_host (bearer : Bool) (c : Cls) : allow true bearer false c = false := by
  cases c <;> simp [allow]

/-! ## 2b. The preview port: its own origin, its own cookie -/

/-- Whether the preview port serves a request. `previewCookie`: the request carries a live preview-access cookie (a
cookie of its own, it is never an owner proof, see `cookie_never_owner`). `hostOk`: its Host names the preview
port. Everything on the preview port needs the preview cookie, from loopback as from the LAN. -/
def allowPreview (lan previewCookie hostOk : Bool) : Bool := (!lan || hostOk) && previewCookie

/-- **A preview is never served without a preview-access cookie.** -/
theorem preview_requires_cookie (lan previewCookie hostOk : Bool) (h : allowPreview lan previewCookie hostOk = true) :
    previewCookie = true := by
  simp_all [allowPreview]

/-- A LAN request to the preview port with a foreign Host is refused whatever it carries. -/
theorem preview_wrong_host (previewCookie : Bool) : allowPreview true previewCookie false = false := by
  simp [allowPreview]

/-! ## 2b'. Inspect grants: a loopback-only, one-time, preview-only way in for agents -/

/-- How long a grant link can be redeemed (ms). -/
def grantTokenTtl : Nat := 600000

/-- How long the cookie a redeemed grant sets is valid (ms). -/
def grantCookieTtl : Nat := 3600000

/-- Whether a grant may be issued: only for a request from the loopback address. -/
def issueAllowed (lan : Bool) : Bool := !lan

/-- **A grant is never issued to a LAN request.** -/
theorem issue_requires_loopback (lan : Bool) (h : issueAllowed lan = true) : lan = false := by
  cases lan <;> simp_all [issueAllowed]

/-- A loopback request may issue. -/
theorem issue_from_loopback : issueAllowed false = true := rfl

/-- The outcome of presenting a grant token. -/
inductive Redeem where
  | ok | lan | unknown | used | expired
deriving Repr, DecidableEq

/-- Its wire name. -/
def Redeem.name : Redeem → String
  | .ok => "ok" | .lan => "lan" | .unknown => "unknown" | .used => "used" | .expired => "expired"

/-- A token is redeemed once, within its time, by a loopback request that names a token this console issued. -/
def redeem (lan known used : Bool) (issuedAt now : Nat) : Redeem :=
  if lan then .lan
  else if !known then .unknown
  else if used then .used
  else if issuedAt + grantTokenTtl ≤ now then .expired
  else .ok

/-- **Redeeming works exactly for a loopback request, a known token, not used before, inside its ten minutes.** -/
theorem redeem_ok_iff (lan known used : Bool) (a now : Nat) :
    redeem lan known used a now = .ok ↔ lan = false ∧ known = true ∧ used = false ∧ now < a + grantTokenTtl := by
  unfold redeem
  cases lan <;> cases known <;> cases used <;> simp [Nat.not_le]

/-- A LAN request never redeems. -/
theorem redeem_lan (known used : Bool) (a now : Nat) : redeem true known used a now = .lan := by
  simp [redeem]

/-- A token this console did not issue never redeems. -/
theorem redeem_unknown (used : Bool) (a now : Nat) : redeem false false used a now = .unknown := by
  simp [redeem]

/-- **Single use**: a token already redeemed never redeems again. -/
theorem redeem_used (a now : Nat) : redeem false true true a now = .used := by
  simp [redeem]

/-- **Expiry**: an unused known token redeems no more after ten minutes. -/
theorem redeem_expired (a now : Nat) (h : a + grantTokenTtl ≤ now) : redeem false true false a now = .expired := by
  simp [redeem, h]

/-- Whether the preview port serves a request on the strength of a grant cookie. `known`: the cookie names a grant this
console opened; `started`: when. Only a preview path is served, never `/api`, `/owner`, the login page or a shell path:
a root-absolute request is no preview path here (each preview arm has its own origin, see `Fw.Console.Preview.Arm`). -/
def allowGrant (lan hostOk known : Bool) (started now : Nat) (c : Cls) : Bool :=
  (!lan || hostOk) && known && decide (now < started + grantCookieTtl) &&
    (match c with | .preview => true | .shell => false | .login => false | .other => false)

/-- **A grant cookie is a known one.** -/
theorem grant_requires_known (lan hostOk known : Bool) (s now : Nat) (c : Cls)
    (h : allowGrant lan hostOk known s now c = true) : known = true := by
  cases known <;> simp_all [allowGrant]

/-- **A grant cookie expires after sixty minutes.** -/
theorem grant_expires (lan hostOk known : Bool) (s now : Nat) (c : Cls)
    (h : s + grantCookieTtl ≤ now) : allowGrant lan hostOk known s now c = false := by
  simp [allowGrant, Nat.not_lt.mpr h]

/-- A grant never opens `/api` or `/owner`. -/
theorem grant_never_other (lan hostOk known : Bool) (s now : Nat) :
    allowGrant lan hostOk known s now .other = false := by
  simp [allowGrant]

/-- A grant never opens the login page. -/
theorem grant_never_login (lan hostOk known : Bool) (s now : Nat) :
    allowGrant lan hostOk known s now .login = false := by
  simp [allowGrant]

/-- A grant never opens a shell path (`/_app/x.js`): no Referer reading remains. -/
theorem grant_never_shell (lan hostOk known : Bool) (s now : Nat) :
    allowGrant lan hostOk known s now .shell = false := by
  simp [allowGrant]

/-- A LAN request with a foreign Host is refused whatever it carries. -/
theorem grant_wrong_host (known : Bool) (s now : Nat) (c : Cls) :
    allowGrant true false known s now c = false := by
  simp [allowGrant]

/-- A live grant opens a preview path. -/
theorem grant_opens_preview (lan : Bool) (s now : Nat) (h : now < s + grantCookieTtl) :
    allowGrant lan true true s now .preview = true := by
  simp [allowGrant, h]

/-- Whether the preview port serves a request: a preview-access cookie of an owner session, or a live grant. -/
def servePreview (lan session hostOk known : Bool) (started now : Nat) (c : Cls) : Bool :=
  allowPreview lan session hostOk || allowGrant lan hostOk known started now c

/-- **Without a session cookie, the preview port serves only what a grant opens**: only a preview path, never `/api`,
`/owner`, the login page or a shell path. -/
theorem serve_grant_only_preview (lan hostOk known : Bool) (s now : Nat) (c : Cls)
    (h : servePreview lan false hostOk known s now c = true) : c = .preview := by
  cases c <;> simp_all [servePreview, allowPreview, allowGrant]

/-- With no grant and no session cookie nothing is served. -/
theorem serve_needs_credential (lan hostOk : Bool) (s now : Nat) (c : Cls) :
    servePreview lan false hostOk false s now c = false := by
  simp [servePreview, allowPreview, allowGrant]

/-! ## 2c. Origins: the preview never shares the console's -/

/-- A web origin (scheme `http`): host and port. -/
structure Origin where
  host : String
  port : Nat
deriving Repr, DecidableEq

/-- The origin of the console on a host and its console port. -/
def consoleOrigin (host : String) (p : Nat) : Origin := ⟨host, p⟩

/-- The origin of the previews on a host and the preview port (the port the preview listener actually got, which is
not always the console port plus one). -/
def previewOrigin (host : String) (q : Nat) : Origin := ⟨host, q⟩

/-- **Previews never share the console origin.** When the two ports differ, so do the origins, whatever the host. A page
served by the preview port therefore runs in another origin than the console web. -/
theorem preview_origin_ne_console (host : String) (p q : Nat) (hq : q ≠ p) : previewOrigin host q ≠ consoleOrigin host p := by
  intro h
  exact hq (congrArg Origin.port h)

/-- What a request presents as proof. `bearer`: a valid owner token in the `Authorization` header (the only credential
that can be an owner proof). `preview`: a valid preview-access cookie (the only cookie there is; it opens the preview port
and nothing else). -/
structure Cred where
  bearer : Bool
  preview : Bool

/-- The trusted (console) origins for one request, computed from the origin of its Host header (when that names this
console), the configured extra web origins, and the preview port. No origin of the preview port is ever trusted, and
nothing is trusted while the preview port is unknown. -/
def trustedOrigins (previewPort : Option Nat) (own : Option Origin) (extra : List Origin) : List Origin :=
  match previewPort with
  | none => []
  | some q => (own.toList ++ extra).filter fun o => o.port != q

/-- **Nothing is trusted while the preview port is unset.** -/
theorem trusted_unset (own : Option Origin) (extra : List Origin) : trustedOrigins none own extra = [] := rfl

/-- **No trusted origin is on the preview port.** -/
theorem trusted_not_preview (q : Nat) (own : Option Origin) (extra : List Origin) (o : Origin)
    (h : o ∈ trustedOrigins (some q) own extra) : o.port ≠ q := by
  simp [trustedOrigins] at h
  rcases h with h | h <;> exact h.2

/-- Every trusted origin was offered (the Host's own origin or a configured one). -/
theorem trusted_offered (q : Option Nat) (own : Option Origin) (extra : List Origin) (o : Origin)
    (h : o ∈ trustedOrigins q own extra) : o ∈ own.toList ++ extra := by
  cases q with
  | none => simp [trustedOrigins] at h
  | some q =>
    simp [trustedOrigins] at h ⊢
    rcases h with h | h
    · exact Or.inl h.1
    · exact Or.inr h.1

/-- The name of the preview-access cookie (the only cookie the console sets). -/
def previewCookieName : String := "fw_preview"

/-- An `Origin` header is acceptable among the trusted origins. A request with no `Origin` header is acceptable only
when `strict` is false (command-line tools send none; a browser always sends one on a POST). -/
def originOk (strict : Bool) (trusted : List Origin) : Option Origin → Bool
  | none => !strict
  | some o => decide (o ∈ trusted)

/-- An owner action on the console (start or stop a preview, log out): it needs the bearer token and an `Origin` header
that is a trusted (console) origin. The preview-access cookie plays no part. -/
def ownerAction (trusted : List Origin) (c : Cred) (origin : Option Origin) : Bool :=
  c.bearer && originOk true trusted origin

/-- A request that may change state without being an owner action (every non-GET route, e.g. `/api/commands`, which
command-line tools call): an `Origin` header, when there is one, must be a trusted origin. -/
def commandOk (trusted : List Origin) (origin : Option Origin) : Bool := originOk false trusted origin

/-- A login (`POST /owner/login`): no token yet, but the `Origin` header must be there and be a trusted origin, so a
page on another origin (a preview) cannot post to the login. -/
def loginOk (trusted : List Origin) (origin : Option Origin) : Bool := originOk true trusted origin

/-- **An owner action requires the console origin.** If it is allowed, the request had an `Origin` header and it is one
of the trusted origins. -/
theorem owner_action_requires_console_origin (trusted : List Origin) (c : Cred) (origin : Option Origin)
    (h : ownerAction trusted c origin = true) : ∃ o' ∈ trusted, origin = some o' := by
  cases origin with
  | none => simp [ownerAction, originOk] at h
  | some o => simp [ownerAction, originOk] at h; exact ⟨o, h.2, rfl⟩

/-- **Owner rights require the bearer token.** If an owner action is allowed, the request presented a valid bearer token.
The only cookie in the credential (`preview`) is not consulted. -/
theorem owner_requires_bearer (trusted : List Origin) (c : Cred) (origin : Option Origin)
    (h : ownerAction trusted c origin = true) : c.bearer = true := by
  simp_all [ownerAction]

/-- **No cookie input can yield owner rights.** The verdict is the same for either value of the preview-access cookie, so
no cookie can change it. -/
theorem owner_independent_of_cookie (trusted : List Origin) (b k k' : Bool) (origin : Option Origin) :
    ownerAction trusted ⟨b, k⟩ origin = ownerAction trusted ⟨b, k'⟩ origin := rfl

/-- **A cookie alone is never the owner.** Without the bearer token nothing is allowed, whatever the cookie and the
`Origin`. -/
theorem cookie_never_owner (trusted : List Origin) (preview : Bool) (origin : Option Origin) :
    ownerAction trusted ⟨false, preview⟩ origin = false := by
  simp [ownerAction]

/-- A request from a preview page is refused for every owner action, command and login, whenever the preview origin is
not trusted. -/
theorem preview_origin_refused (trusted : List Origin) (c : Cred) (host : String) (q : Nat)
    (hn : previewOrigin host q ∉ trusted) :
    ownerAction trusted c (some (previewOrigin host q)) = false ∧ commandOk trusted (some (previewOrigin host q)) = false ∧
      loginOk trusted (some (previewOrigin host q)) = false := by
  simp [ownerAction, commandOk, loginOk, originOk, hn]

/-- **With the computed trusted list, every origin on the preview port is refused**, for any host and any credential:
the hypothesis of `preview_origin_refused` is established here, not assumed. -/
theorem computed_trusted_refuses_preview (q : Nat) (own : Option Origin) (extra : List Origin) (c : Cred) (host : String) :
    ownerAction (trustedOrigins (some q) own extra) c (some (previewOrigin host q)) = false ∧
      commandOk (trustedOrigins (some q) own extra) (some (previewOrigin host q)) = false ∧
      loginOk (trustedOrigins (some q) own extra) (some (previewOrigin host q)) = false := by
  apply preview_origin_refused
  intro hm
  exact trusted_not_preview q own extra _ hm rfl

/-- **While the preview port is unset, every owner action and every login that carries an Origin header is refused.** -/
theorem unset_refuses (own : Option Origin) (extra : List Origin) (c : Cred) (o : Origin) :
    ownerAction (trustedOrigins none own extra) c (some o) = false ∧ loginOk (trustedOrigins none own extra) (some o) = false := by
  simp [ownerAction, loginOk, originOk, trustedOrigins]

/-- The console's own origin is accepted when the bearer token is there and the origin is trusted. -/
theorem console_origin_accepted (trusted : List Origin) (preview : Bool) (o : Origin)
    (hc : o ∈ trusted) :
    ownerAction trusted ⟨true, preview⟩ (some o) = true := by
  simp [ownerAction, originOk, hc]

/-! ## 3. Just-in-time previews: idle stop and TTL -/

/-- A preview idle for this long is stopped (ms). -/
def idleLimit : Nat := 900000

/-- A live preview with the time of its last proxied request (ms); the time it started serving until one comes. -/
structure Live where
  pv : Pv
  seen : Nat

/-- It stays: inside the TTL and not idle. -/
def Live.alive (l : Live) (now : Nat) : Bool := decide (now < l.pv.deadline) && decide (now < l.seen + idleLimit)

/-- The previews that stay at `now`. -/
def sweep (s : List Live) (now : Nat) : List Live := s.filter (·.alive now)

/-- The previews that are stopped at `now`. -/
def reaped (s : List Live) (now : Nat) : List Live := s.filter fun l => !l.alive now

/-- Why a preview was stopped: the TTL, else idleness. -/
def why (l : Live) (now : Nat) : String := if l.pv.deadline ≤ now then "ttl" else "idle"

/-- **TTL stops.** A preview at or past its 60 minute deadline is reaped and does not stay, however recently it was used. -/
theorem ttl_stops (s : List Live) (now : Nat) (l : Live) (hl : l ∈ s) (h : l.pv.started + ttl ≤ now) :
    l ∈ reaped s now ∧ l ∉ sweep s now := by
  have hn : l.alive now = false := by
    have : ¬ now < l.pv.deadline := by simp [Pv.deadline]; omega
    simp [Live.alive, this]
  refine ⟨List.mem_filter.mpr ⟨hl, by simp [hn]⟩, fun hm => ?_⟩
  have := (List.mem_filter.mp hm).2
  simp [hn] at this

/-- **Idle stops.** A preview with no proxied request for 15 minutes is reaped and does not stay. -/
theorem idle_stops (s : List Live) (now : Nat) (l : Live) (hl : l ∈ s) (h : l.seen + idleLimit ≤ now) :
    l ∈ reaped s now ∧ l ∉ sweep s now := by
  have hn : l.alive now = false := by
    have : ¬ now < l.seen + idleLimit := by omega
    simp [Live.alive, this]
  refine ⟨List.mem_filter.mpr ⟨hl, by simp [hn]⟩, fun hm => ?_⟩
  have := (List.mem_filter.mp hm).2
  simp [hn] at this

/-- **What stays is young and busy.** -/
theorem sweep_young (s : List Live) (now : Nat) (l : Live) (h : l ∈ sweep s now) :
    now < l.pv.started + ttl ∧ now < l.seen + idleLimit := by
  have := (List.mem_filter.mp h).2
  simp [Live.alive, Pv.deadline] at this
  exact ⟨of_decide_eq_true this.1, this.2⟩

/-- **Nothing is lost.** The stayers and the stopped ones are the table, in some order. -/
theorem sweep_partition (s : List Live) (now : Nat) : (sweep s now ++ reaped s now).Perm s := by
  unfold sweep reaped
  have := List.filter_append_perm (fun l : Live => l.alive now) s
  simpa using this

/-- **A request keeps a preview alive.** A preview used at `t` (so `seen = t`) and inside its TTL stays until 15 minutes
after `t`. -/
theorem touch_keeps (l : Live) (t t' : Nat) (hs : l.seen = t) (h1 : t' < t + idleLimit) (h2 : t' < l.pv.started + ttl) :
    l.alive t' = true := by
  simp only [Live.alive, Pv.deadline, Bool.and_eq_true, decide_eq_true_eq]
  exact ⟨decide_eq_true h2, by omega⟩

/-- **Why is exact.** The reason is `ttl` exactly when the deadline passed. -/
theorem why_ttl_iff (l : Live) (now : Nat) : why l now = "ttl" ↔ l.pv.started + ttl ≤ now := by
  unfold why Pv.deadline
  split <;> simp_all

end Fw.Console.Preview.Owner
