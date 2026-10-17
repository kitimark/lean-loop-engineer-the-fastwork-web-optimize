import Lean.Data.Json
/-!
# Device lease (one exclusive resource, FIFO queue, time-bounded holds)

A pure transition function `step : State → Cmd → State × Reply`. The TypeScript shell persists
`State` as JSON and forwards commands; it never decides who holds the device.
v1 lessons encoded: I-113 (re-queue lost its place) and I-091 (renew shortened a lease) as
theorems, I-041 (exclusivity broken) by the type of `State` plus the invariant `Inv`.
I-011/I-049 (starvation) is **not** proved: one release step is FIFO (`release_fifo`), but a holder
can renew forever, so starvation-freedom is false without a renew cap (gap G4 of the Lean-to-math
note).
-/
namespace Fw.Lease

/-- An owner (a client of the device) is named by a string.

$$\mathrm{Owner} = \text{strings}$$
-/
abbrev Owner := String

/-- A lease: who holds the device and until when (seconds since epoch).

$$\mathrm{Lease} = \mathrm{Owner} \times \mathbb{N}, \qquad l = (l.\mathit{owner},\ l.\mathit{expires})$$
-/
structure Lease where
  owner   : Owner
  expires : Nat          -- seconds since epoch
deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

/-- The lease state: at most one holder (by type) and a queue of waiting owners.

$$\mathrm{State} = \mathrm{Lease}_\bot \times \mathrm{Owner}^{*}, \qquad s = (h, Q) = (s.\mathit{holder},\ s.\mathit{queue}), \qquad s_0 = (\bot, [\,])$$
-/
structure State where
  holder : Option Lease := none   -- mutual exclusion by construction: at most one holder
  queue  : List Owner   := []
deriving Repr, Lean.ToJson, Lean.FromJson

/-- Commands sent to the lease; `now` is the current time and `ttl` a lease length, in seconds.

$$\mathrm{Cmd} = \mathrm{acquire}(o, \mathit{now}, \mathit{ttl}) \mid \mathrm{renew}(o, \mathit{now}, \mathit{ttl}) \mid \mathrm{release}(o, \mathit{now}, \mathit{ttl}) \mid \mathrm{tick}(\mathit{now}, \mathit{ttl})$$
-/
inductive Cmd where
  | acquire (o : Owner) (now ttl : Nat)
  | renew   (o : Owner) (now ttl : Nat)
  | release (o : Owner) (now ttl : Nat)   -- ttl: the next holder's lease length
  | tick    (now ttl : Nat)
deriving Repr, Lean.ToJson, Lean.FromJson

/-- Replies to commands.

$$\mathrm{Reply} = \mathrm{granted}(l) \mid \mathrm{queued}(\mathit{pos}) \mid \mathrm{renewed}(l) \mid \mathrm{released} \mid \mathrm{refused}(\mathit{why}) \mid \mathrm{ok}$$
-/
inductive Reply where
  | granted (l : Lease) | queued (pos : Nat) | renewed (l : Lease) | released | refused (why : String) | ok
deriving Repr, Lean.ToJson, Lean.FromJson

/-- Hand the device to the head of the queue for `ttl` seconds (FIFO, no barging); with nobody
waiting the device becomes free.

$$\operatorname{promote}(\mathit{now}, \mathit{ttl}, [\,]) = (\bot, [\,]), \qquad \operatorname{promote}(\mathit{now}, \mathit{ttl}, o :: q) = \big((o,\ \mathit{now} + \mathit{ttl}),\ q\big)$$
-/
def promote (now ttl : Nat) : List Owner → State
  | []      => { holder := none, queue := [] }
  | o :: q  => { holder := some ⟨o, now + ttl⟩, queue := q }

/-- The lease transition function: the new state and the reply for one command. With
$s = (h, Q)$, first match wins, $\operatorname{idx}_Q(o)$ the 0-based position of $o$ in $Q$ and
$Q \ominus o$ the removal of the first occurrence of $o$:

$$\mathrm{step}\big(s, \mathrm{acquire}(o, \mathit{now}, \mathit{ttl})\big) = \begin{cases} \big(((o, \mathit{now} + \mathit{ttl}), [\,]),\ \mathrm{granted}(o, \mathit{now} + \mathit{ttl})\big) & h = \bot,\ Q = [\,] \\ (s,\ \mathrm{refused}(\texttt{"not normalized"})) & h = \bot,\ Q \ne [\,] \\ (s,\ \mathrm{granted}(l)) & h = l,\ l.\mathit{owner} = o \\ (s,\ \mathrm{queued}(\operatorname{idx}_Q(o))) & h = l,\ l.\mathit{owner} \ne o,\ o \in Q \\ \big((l,\ Q \mathbin{+\!\!+} [o]),\ \mathrm{queued}(|Q|)\big) & h = l,\ l.\mathit{owner} \ne o,\ o \notin Q \end{cases}$$

$$\mathrm{step}\big(s, \mathrm{renew}(o, \mathit{now}, \mathit{ttl})\big) = \begin{cases} \big((l', Q),\ \mathrm{renewed}(l')\big),\ l' = (o,\ \max(l.\mathit{expires},\ \mathit{now} + \mathit{ttl})) & h = l,\ l.\mathit{owner} = o \\ (s,\ \mathrm{refused}(\texttt{"not the holder"})) & \text{otherwise} \end{cases}$$

$$\mathrm{step}\big(s, \mathrm{release}(o, \mathit{now}, \mathit{ttl})\big) = \begin{cases} (\operatorname{promote}(\mathit{now}, \mathit{ttl}, Q),\ \mathrm{released}) & h = l,\ l.\mathit{owner} = o \\ \big((l,\ Q \ominus o),\ \mathrm{ok}\big) & h = l,\ l.\mathit{owner} \ne o \\ (s,\ \mathrm{ok}) & h = \bot \end{cases}$$

$$\mathrm{step}\big(s, \mathrm{tick}(\mathit{now}, \mathit{ttl})\big) = \begin{cases} (\operatorname{promote}(\mathit{now}, \mathit{ttl}, Q),\ \mathrm{ok}) & h = l,\ l.\mathit{expires} \le \mathit{now} \\ (s,\ \mathrm{ok}) & \text{otherwise} \end{cases}$$

Edge: `acquire` never checks expiry; a re-entrant `acquire` does not extend the lease; a lease
expiring exactly at `now` counts as expired.
-/
def step : State → Cmd → State × Reply
  | s, .acquire o now ttl =>
    match s.holder with
    | none   => if s.queue = [] then ({ holder := some ⟨o, now + ttl⟩, queue := [] }, .granted ⟨o, now + ttl⟩)
                else (s, .refused "not normalized")
    | some l =>
      if l.owner = o then (s, .granted l)                              -- re-entrant
      else if o ∈ s.queue then (s, .queued (s.queue.idxOf o))          -- keeps its place (I-113)
      else ({ s with queue := s.queue ++ [o] }, .queued s.queue.length)
  | s, .renew o now ttl =>
    match s.holder with
    | some l => if l.owner = o then
                  let l' : Lease := ⟨o, max l.expires (now + ttl)⟩      -- never shortens (I-091)
                  ({ s with holder := some l' }, .renewed l')
                else (s, .refused "not the holder")
    | none   => (s, .refused "not the holder")
  | s, .release o now ttl =>
    match s.holder with
    | some l => if l.owner = o then (promote now ttl s.queue, .released)
                else ({ s with queue := s.queue.erase o }, .ok)         -- a waiter leaves
    | none   => (s, .ok)
  | s, .tick now ttl =>
    match s.holder with
    | some l => if l.expires ≤ now then (promote now ttl s.queue, .ok) else (s, .ok)
    | none   => (s, .ok)

-- Fresh acquire; a waiter queues; re-entrant acquire does not extend; tick at exact expiry promotes.
#guard
  let s1 := (step {} (.acquire "a" 0 10)).1
  let s2 := (step s1 (.acquire "b" 1 10)).1
  s1.holder == some ⟨"a", 10⟩ && s2.queue == ["b"]
  && (step s1 (.acquire "a" 5 100)).1.holder == some ⟨"a", 10⟩
  && (step s2 (.tick 10 7)).1.holder == some ⟨"b", 17⟩ && (step s2 (.tick 9 7)).1.holder == some ⟨"a", 10⟩
-- Renew never shortens; a stranger's release changes nothing; a waiter's release leaves the queue.
#guard
  let s2 := (step (step {} (.acquire "a" 0 10)).1 (.acquire "b" 1 10)).1
  (step s2 (.renew "a" 2 3)).1.holder == some ⟨"a", 10⟩
  && (step s2 (.renew "a" 2 30)).1.holder == some ⟨"a", 32⟩
  && (step s2 (.release "zed" 5 10)).1.queue == ["b"]
  && (step s2 (.release "b" 5 10)).1.queue == []
  && (step s2 (.release "a" 5 20)).1.holder == some ⟨"b", 25⟩
-- G4: renewing forever starves the waiter.
#guard
  let s := (step (step {} (.acquire "a" 0 10)).1 (.acquire "b" 1 10)).1
  let s := (step (step (step (step s (.renew "a" 9 10)).1 (.tick 15 10)).1 (.renew "a" 18 10)).1 (.tick 25 10)).1
  s.holder == some ⟨"a", 28⟩ && s.queue == ["b"]

/-- The lease invariant: nobody waits for a free device, nobody is queued twice, and the holder is
not also waiting. It holds initially (`inv_init`) and is kept by every step (`step_inv`); the
corollary for every reachable state is not stated as a theorem here (gap G3).

$$\operatorname{Inv}(h, Q) \iff \big(h = \bot \Rightarrow Q = [\,]\big) \ \land\ \big(Q \text{ has no repeated owner}\big) \ \land\ \big(\forall l:\ h = l \Rightarrow l.\mathit{owner} \notin Q\big)$$
-/
structure Inv (s : State) : Prop where
  idle_empty : s.holder = none → s.queue = []
  nodup      : s.queue.Nodup
  not_both   : ∀ l, s.holder = some l → l.owner ∉ s.queue

/-- The empty state satisfies the invariant.

$$\operatorname{Inv}(s_0), \qquad s_0 = (\bot, [\,])$$
-/
theorem inv_init : Inv {} := ⟨fun _ => rfl, List.nodup_nil, by simp⟩

/-- Promoting from a duplicate-free queue gives a state that satisfies the invariant.

$$\forall \mathit{now}, \mathit{ttl} \in \mathbb{N},\ \forall Q \in \mathrm{Owner}^{*}:\quad Q \text{ has no repeated owner} \;\Rightarrow\; \operatorname{Inv}\big(\operatorname{promote}(\mathit{now}, \mathit{ttl}, Q)\big)$$
-/
theorem promote_inv {now ttl : Nat} {q : List Owner} (h : q.Nodup) : Inv (promote now ttl q) := by
  cases q with
  | nil => exact ⟨fun _ => rfl, List.nodup_nil, by simp [promote]⟩
  | cons o q =>
    rw [List.nodup_cons] at h
    refine ⟨by simp [promote], h.2, ?_⟩
    intro l hl
    simp [promote] at hl
    subst hl
    exact h.1

/-- Every command keeps the invariant (one step).

$$\forall s \in \mathrm{State},\ \forall c \in \mathrm{Cmd}:\quad \operatorname{Inv}(s) \;\Rightarrow\; \operatorname{Inv}\big(\mathrm{step}(s, c)_1\big)$$
-/
theorem step_inv {s : State} (c : Cmd) (h : Inv s) : Inv (step s c).1 := by
  cases c with
  | acquire o now ttl =>
    simp only [step]
    split
    · split
      · exact ⟨fun _ => rfl, List.nodup_nil, by simp⟩
      · exact h
    · rename_i l hl
      split
      · exact h
      · split
        · exact h
        · rename_i hne hnq
          refine ⟨by simp [hl], ?_, ?_⟩
          · rw [List.nodup_append]
            refine ⟨h.nodup, by simp, ?_⟩
            intro a ha b hb
            simp only [List.mem_singleton] at hb
            subst hb
            intro e; subst e; exact hnq ha
          · intro l' hl'
            simp only [hl, Option.some.injEq] at hl'
            subst hl'
            have := h.not_both l hl
            simp only [List.mem_append, List.mem_singleton, not_or]
            exact ⟨this, hne⟩
  | renew o now ttl =>
    simp only [step]
    split
    · split
      · rename_i l hl _
        refine ⟨by simp, h.nodup, ?_⟩
        intro l' hl'
        simp only [Option.some.injEq] at hl'
        subst hl'
        have := h.not_both l hl
        simp_all
      · exact h
    · exact h
  | release o now ttl =>
    simp only [step]
    split
    · split
      · exact promote_inv h.nodup
      · rename_i l hl _
        refine ⟨by simp [hl], h.nodup.erase o, ?_⟩
        intro l' hl'
        simp only [hl, Option.some.injEq] at hl'
        subst hl'
        exact fun hm => h.not_both l hl (List.mem_of_mem_erase hm)
    · exact h
  | tick now ttl =>
    simp only [step]
    split
    · split
      · exact promote_inv h.nodup
      · exact h
    · exact h

/-- I-113: a waiter that asks again keeps its place (the state does not change).

$$s.\mathit{holder} = l \ \land\ l.\mathit{owner} \ne o \ \land\ o \in s.\mathit{queue} \;\Rightarrow\; \mathrm{step}\big(s, \mathrm{acquire}(o, \mathit{now}, \mathit{ttl})\big)_1 = s$$
-/
theorem requeue_keeps_place (s : State) (l : Lease) (o : Owner) (now ttl : Nat)
    (hl : s.holder = some l) (hne : l.owner ≠ o) (hq : o ∈ s.queue) :
    (step s (.acquire o now ttl)).1 = s := by
  simp [step, hl, hne, hq]

/-- I-091: the holder's renew never moves its expiry earlier.

$$s.\mathit{holder} = l \;\Rightarrow\; \exists l':\ \mathrm{step}\big(s, \mathrm{renew}(l.\mathit{owner}, \mathit{now}, \mathit{ttl})\big)_1.\mathit{holder} = l' \ \land\ l.\mathit{expires} \le l'.\mathit{expires}$$
-/
theorem renew_never_shortens (s : State) (l : Lease) (now ttl : Nat) (hl : s.holder = some l) :
    ∃ l', (step s (.renew l.owner now ttl)).1.holder = some l' ∧ l.expires ≤ l'.expires := by
  refine ⟨⟨l.owner, max l.expires (now + ttl)⟩, by simp [step, hl], by simp; omega⟩

/-- FIFO for one release step: when the holder releases, the head of the queue gets the device for
`ttl` seconds and every other waiter moves up exactly one place (this is not a starvation-freedom
theorem: a holder may renew forever, gap G4).

$$s.\mathit{holder} = l \ \land\ s.\mathit{queue} = o :: q \;\Rightarrow\; \mathrm{step}\big(s, \mathrm{release}(l.\mathit{owner}, \mathit{now}, \mathit{ttl})\big)_1 = \big((o,\ \mathit{now} + \mathit{ttl}),\ q\big)$$
-/
theorem release_fifo (s : State) (l : Lease) (o : Owner) (q : List Owner) (now ttl : Nat)
    (hl : s.holder = some l) (hq : s.queue = o :: q) :
    (step s (.release l.owner now ttl)).1 = { holder := some ⟨o, now + ttl⟩, queue := q } := by
  simp [step, hl, hq, promote]

end Fw.Lease
