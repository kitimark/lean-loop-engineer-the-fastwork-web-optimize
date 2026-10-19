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

/-- An owner (a client of the device) is named by a string. -/
abbrev Owner := String

/-- A lease: who holds the device and until when (seconds since epoch). -/
structure Lease where
  owner   : Owner
  expires : Nat          -- seconds since epoch
deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

/-- The lease state: at most one holder (by type) and a queue of waiting owners. -/
structure State where
  holder : Option Lease := none   -- mutual exclusion by construction: at most one holder
  queue  : List Owner   := []
deriving Repr, Lean.ToJson, Lean.FromJson

/-- Commands sent to the lease; `now` is the current time and `ttl` a lease length, in seconds. -/
inductive Cmd where
  | acquire (o : Owner) (now ttl : Nat)
  | renew   (o : Owner) (now ttl : Nat)
  | release (o : Owner) (now ttl : Nat)   -- ttl: the next holder's lease length
  | tick    (now ttl : Nat)
deriving Repr, Lean.ToJson, Lean.FromJson

/-- Replies to commands. -/
inductive Reply where
  | granted (l : Lease) | queued (pos : Nat) | renewed (l : Lease) | released | refused (why : String) | ok
deriving Repr, Lean.ToJson, Lean.FromJson

/-- Hand the device to the head of the queue for `ttl` seconds (FIFO, no barging); with nobody
waiting the device becomes free.
-/
def promote (now ttl : Nat) : List Owner → State
  | []      => { holder := none, queue := [] }
  | o :: q  => { holder := some ⟨o, now + ttl⟩, queue := q }

/-- The lease transition function: the new state and the reply for one command. With
`s = (h, Q)`, first match wins, `idx_Q(o)` the 0-based position of `o` in `Q` and
`Q ⊖ o` the removal of the first occurrence of `o`.

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
-/
structure Inv (s : State) : Prop where
  idle_empty : s.holder = none → s.queue = []
  nodup      : s.queue.Nodup
  not_both   : ∀ l, s.holder = some l → l.owner ∉ s.queue

/-- The empty state satisfies the invariant. -/
theorem inv_init : Inv {} := ⟨fun _ => rfl, List.nodup_nil, by simp⟩

/-- Promoting from a duplicate-free queue gives a state that satisfies the invariant. -/
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

/-- Every command keeps the invariant (one step). -/
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

/-- I-113: a waiter that asks again keeps its place (the state does not change). -/
theorem requeue_keeps_place (s : State) (l : Lease) (o : Owner) (now ttl : Nat)
    (hl : s.holder = some l) (hne : l.owner ≠ o) (hq : o ∈ s.queue) :
    (step s (.acquire o now ttl)).1 = s := by
  simp [step, hl, hne, hq]

/-- I-091: the holder's renew never moves its expiry earlier. -/
theorem renew_never_shortens (s : State) (l : Lease) (now ttl : Nat) (hl : s.holder = some l) :
    ∃ l', (step s (.renew l.owner now ttl)).1.holder = some l' ∧ l.expires ≤ l'.expires := by
  refine ⟨⟨l.owner, max l.expires (now + ttl)⟩, by simp [step, hl], by simp; omega⟩

/-- FIFO for one release step: when the holder releases, the head of the queue gets the device for
`ttl` seconds and every other waiter moves up exactly one place (this is not a starvation-freedom
theorem: a holder may renew forever, gap G4).
-/
theorem release_fifo (s : State) (l : Lease) (o : Owner) (q : List Owner) (now ttl : Nat)
    (hl : s.holder = some l) (hq : s.queue = o :: q) :
    (step s (.release l.owner now ttl)).1 = { holder := some ⟨o, now + ttl⟩, queue := q } := by
  simp [step, hl, hq, promote]

end Fw.Lease
