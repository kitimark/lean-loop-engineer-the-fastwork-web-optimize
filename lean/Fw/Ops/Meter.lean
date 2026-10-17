/-!
# Budget meter: per-agent alerts (PLAN §8.4 soft alerts, §8.5 waiting and lifetime)

Ports `docs/team/tools/agent-idle.py` to Lean (seconds instead of minutes): per agent its context
size, idle time and cache TTL give alerts

* `ctxBig`: the last-turn context is above the cap (200k by default, the `autoCompactWindow`);
* `idleExpiring`: idle for more than TTL − 60 s (its prompt cache is about to expire, MEASURED
  5-minute writes in the observability note §1);
* `coldWake`: the agent was woken (resumed or respawned) after an idle gap longer than its TTL,
  so it paid a full cache rewrite;

and the script's verdict (`resumeOk`, `resumeCheap`, `respawn`). Alerts are deduped: each
(agent, rule) pair alerts at most once per window (`once_per_window`), and every rule is monotone
in its inputs (`holds_mono`, `verdict_mono`).
-/
namespace Fw.Ops.Meter

/-- The alert rules.

$$\mathrm{Rule} = \{\mathrm{ctxBig},\ \mathrm{idleExpiring},\ \mathrm{coldWake}\}$$
-/
inductive Rule where
  | ctxBig | idleExpiring | coldWake
deriving DecidableEq, Repr

/-- All rules, in output order.

$$\mathrm{Rules} = [\mathrm{ctxBig}, \mathrm{idleExpiring}, \mathrm{coldWake}]$$
-/
def Rule.all : List Rule := [.ctxBig, .idleExpiring, .coldWake]

/-- The meter's parameters: the context cap, the lead time before TTL expiry, the dedupe window
and the context above which an expired agent should be respawned rather than resumed (all in
tokens or seconds).

$$\mathrm{Params} = (c_{max}, \lambda, \omega, c_{resp}), \qquad \text{defaults } c_{max} = 200000,\ \lambda = 60,\ \omega = 3600,\ c_{resp} = 30000$$
-/
structure Params where
  ctxMax     : Nat := 200000
  leadSec    : Nat := 60
  windowSec  : Nat := 3600
  respawnCtx : Nat := 30000
deriving Repr

/-- One agent observation: its last-turn context in tokens, seconds since its last transcript line,
its cache TTL in seconds, and the idle gap before its latest wake (0 when it was not woken).

$$o = (o.\mathit{agent},\ o.\mathit{ctx},\ o.\mathit{idle},\ o.\mathit{ttl},\ o.\mathit{gap}) \in \mathrm{String} \times \mathbb{N}^4$$
-/
structure Obs where
  agent      : String
  ctx        : Nat
  idleSec    : Nat
  ttlSec     : Nat
  wakeGapSec : Nat
deriving DecidableEq, Repr

/-- The cache TTL an agent's writes used (as in `agent-idle.py`): 1 h when its 1-hour cache
writes exceed its 5-minute ones, else 5 min.

$$\mathrm{ttl}(w_{5m}, w_{1h}) = \begin{cases} 3600 & w_{1h} > w_{5m} \\ 300 & \text{otherwise} \end{cases}$$
-/
def ttlOf (w5m w1h : Nat) : Nat := if w1h > w5m then 3600 else 300

/-- Whether a rule fires for an observation.

$$\mathrm{ctxBig}(o) \iff o.\mathit{ctx} > c_{max}, \qquad \mathrm{idleExpiring}(o) \iff o.\mathit{idle} + \lambda > o.\mathit{ttl}, \qquad \mathrm{coldWake}(o) \iff o.\mathit{gap} > o.\mathit{ttl}$$
-/
def holds (p : Params) (o : Obs) : Rule → Bool
  | .ctxBig => Decidable.decide (p.ctxMax < o.ctx)
  | .idleExpiring => Decidable.decide (o.ttlSec < o.idleSec + p.leadSec)
  | .coldWake => Decidable.decide (o.ttlSec < o.wakeGapSec)

/-- The pointwise order on observations of one agent: more context, more idle time, a longer wake
gap, a shorter TTL.

$$o \preceq o' \iff o.\mathit{agent} = o'.\mathit{agent} \land o.\mathit{ctx} \le o'.\mathit{ctx} \land o.\mathit{idle} \le o'.\mathit{idle} \land o.\mathit{gap} \le o'.\mathit{gap} \land o'.\mathit{ttl} \le o.\mathit{ttl}$$
-/
def Obs.le (o o' : Obs) : Prop :=
  o.agent = o'.agent ∧ o.ctx ≤ o'.ctx ∧ o.idleSec ≤ o'.idleSec ∧ o.wakeGapSec ≤ o'.wakeGapSec ∧
    o'.ttlSec ≤ o.ttlSec

/-- Monotone alerts: a rule that fires keeps firing when context, idle time or wake gap grow or
the TTL shrinks.

$$\forall p, o, o', r:\quad o \preceq o' \land r(o) \Rightarrow r(o')$$
-/
theorem holds_mono (p : Params) {o o' : Obs} (h : o.le o') (r : Rule) (hr : holds p o r = true) :
    holds p o' r = true := by
  obtain ⟨_, hc, hi, hg, ht⟩ := h
  cases r <;> simp [holds] at hr ⊢ <;> omega

/-- The verdict of `agent-idle.py`: resume within the TTL, resume cheaply a small expired agent,
respawn a large expired one.

$$\mathrm{Verdict} = \mathrm{resumeOk} \mid \mathrm{resumeCheap} \mid \mathrm{respawn}$$
-/
inductive Verdict where
  | resumeOk | resumeCheap | respawn
deriving DecidableEq, Repr

/-- The rank of a verdict (worse is higher).

$$\mathrm{rank}(\mathrm{resumeOk}) = 0,\quad \mathrm{rank}(\mathrm{resumeCheap}) = 1,\quad \mathrm{rank}(\mathrm{respawn}) = 2$$
-/
def Verdict.rank : Verdict → Nat
  | .resumeOk => 0 | .resumeCheap => 1 | .respawn => 2

/-- The verdict for an observation.

$$\mathrm{verdict}(o) = \begin{cases} \mathrm{respawn} & o.\mathit{idle} > o.\mathit{ttl} \land o.\mathit{ctx} > c_{resp} \\ \mathrm{resumeOk} & o.\mathit{idle} \le o.\mathit{ttl} \\ \mathrm{resumeCheap} & \text{otherwise} \end{cases}$$
-/
def verdict (p : Params) (o : Obs) : Verdict :=
  if o.ttlSec < o.idleSec ∧ p.respawnCtx < o.ctx then .respawn
  else if o.idleSec ≤ o.ttlSec then .resumeOk
  else .resumeCheap

/-- The verdict only gets worse as context or idle time grow or the TTL shrinks.

$$\forall p, o, o':\quad o \preceq o' \Rightarrow \mathrm{rank}(\mathrm{verdict}(o)) \le \mathrm{rank}(\mathrm{verdict}(o'))$$
-/
theorem verdict_mono (p : Params) {o o' : Obs} (h : o.le o') :
    (verdict p o).rank ≤ (verdict p o').rank := by
  obtain ⟨_, hc, hi, _, ht⟩ := h
  unfold verdict
  by_cases a : o.ttlSec < o.idleSec ∧ p.respawnCtx < o.ctx
  · have a' : o'.ttlSec < o'.idleSec ∧ p.respawnCtx < o'.ctx := ⟨by omega, by omega⟩
    simp [a, a', Verdict.rank]
  · by_cases b : o.idleSec ≤ o.ttlSec
    · simp only [a, b, ↓reduceIte, Verdict.rank]; omega
    · have b' : ¬ o'.idleSec ≤ o'.ttlSec := by omega
      simp only [a, b, b', ↓reduceIte]
      split <;> simp [Verdict.rank]

/-! ## Dedupe: once per (agent, rule, window) -/

/-- An alert key: (agent, rule).

$$\mathrm{Key} = \mathrm{String} \times \mathrm{Rule}$$
-/
abbrev Key := String × Rule

/-- An emitted alert: (agent, rule, window index).

$$\mathrm{Alert} = \mathrm{String} \times \mathrm{Rule} \times \mathbb{N}$$
-/
abbrev Alert := String × Rule × Nat

/-- The dedupe state: the current window index and the keys already alerted in it.

$$\sigma = (\sigma.w,\ \sigma.F), \qquad \sigma_0 = (0, [\,])$$
-/
structure State where
  window : Nat := 0
  fired  : List Key := []
deriving DecidableEq, Repr

/-- The keys whose rule fires, in observation order.

$$\mathrm{cand}(p, O) = [\,(o.\mathit{agent}, r) : o \in O,\ r \in \mathrm{Rules},\ r(o)\,]$$
-/
def candidates (p : Params) (obs : List Obs) : List Key :=
  obs.flatMap fun o => (Rule.all.filter (holds p o)).map ((o.agent, ·))

/-- The candidates not yet seen, each once, in order.

$$\mathrm{fresh}(S, [\,]) = [\,], \qquad \mathrm{fresh}(S, c :: C) = \begin{cases} \mathrm{fresh}(S, C) & c \in S \\ c :: \mathrm{fresh}(c :: S, C) & c \notin S \end{cases}$$
-/
def fresh : List Key → List Key → List Key
  | _, [] => []
  | seen, c :: cs => if c ∈ seen then fresh seen cs else c :: fresh (c :: seen) cs

/-- One meter tick at time `now` (seconds): the window is $\lfloor \mathit{now} / \omega \rfloor$; a
new window forgets the fired keys; the fresh candidates are emitted and remembered.

$$\mathrm{step}(\sigma, \mathit{now}, O) = \big((w,\ N \mathbin{+\!\!+} F_0),\ [(a, r, w) : (a, r) \in N]\big), \quad w = \lfloor \mathit{now}/\omega \rfloor,\ F_0 = \begin{cases} \sigma.F & w = \sigma.w \\ [\,] & w \ne \sigma.w \end{cases},\ N = \mathrm{fresh}(F_0, \mathrm{cand}(p, O))$$
-/
def step (p : Params) (s : State) (now : Nat) (obs : List Obs) : State × List Alert :=
  let w := now / p.windowSec
  let f0 := if w = s.window then s.fired else []
  let new := fresh f0 (candidates p obs)
  (⟨w, new ++ f0⟩, new.map fun k => (k.1, k.2, w))

/-- Run the meter over a trace of ticks, collecting all alerts.

$$\mathrm{run}(\sigma, [\,]) = (\sigma, [\,]), \qquad \mathrm{run}(\sigma, (t, O) :: T) = (\sigma'',\ A \mathbin{+\!\!+} A'') \text{ where } (\sigma', A) = \mathrm{step}(\sigma, t, O),\ (\sigma'', A'') = \mathrm{run}(\sigma', T)$$
-/
def run (p : Params) : State → List (Nat × List Obs) → State × List Alert
  | s, [] => (s, [])
  | s, (now, obs) :: rest =>
    let r1 := step p s now obs
    let r2 := run p r1.1 rest
    (r2.1, r1.2 ++ r2.2)

/-- Membership in `fresh`: a candidate not seen before.

$$\forall S, C, x:\quad x \in \mathrm{fresh}(S, C) \iff x \in C \land x \notin S$$
-/
theorem mem_fresh (seen cs : List Key) (x : Key) : x ∈ fresh seen cs ↔ x ∈ cs ∧ x ∉ seen := by
  induction cs generalizing seen with
  | nil => simp [fresh]
  | cons c cs ih =>
    simp only [fresh]
    split
    · rename_i hc
      rw [ih]
      constructor
      · intro ⟨h1, h2⟩; exact ⟨List.mem_cons_of_mem _ h1, h2⟩
      · intro ⟨h1, h2⟩
        rcases List.mem_cons.mp h1 with e | e
        · exact absurd (e ▸ hc) h2
        · exact ⟨e, h2⟩
    · rename_i hc
      rw [List.mem_cons, ih, List.mem_cons, List.mem_cons]
      constructor
      · rintro (e | ⟨h1, h2⟩)
        · exact ⟨.inl e, e ▸ hc⟩
        · exact ⟨.inr h1, fun m => h2 (.inr m)⟩
      · rintro ⟨e | h1, h2⟩
        · exact .inl e
        · by_cases e : x = c
          · exact .inl e
          · exact .inr ⟨h1, fun m => m.elim e h2⟩

/-- `fresh` has no repeats.

$$\forall S, C:\quad \mathrm{fresh}(S, C) \text{ has no repeats}$$
-/
theorem fresh_nodup (seen cs : List Key) : (fresh seen cs).Nodup := by
  induction cs generalizing seen with
  | nil => simp [fresh]
  | cons c cs ih =>
    simp only [fresh]
    split
    · exact ih seen
    · refine List.nodup_cons.mpr ⟨?_, ih _⟩
      intro m
      exact ((mem_fresh _ _ _).mp m).2 List.mem_cons_self

/-- A tick is complete: a firing rule whose key was not yet alerted in this window is alerted now.

$$\forall o \in O, r:\quad r(o) \land (o.\mathit{agent}, r) \notin F_0 \Rightarrow (o.\mathit{agent}, r, w) \in \mathrm{step}(\sigma, \mathit{now}, O).2$$
-/
theorem step_complete (p : Params) (s : State) (now : Nat) (obs : List Obs) (o : Obs) (ho : o ∈ obs)
    (r : Rule) (hr : holds p o r = true)
    (hn : (o.agent, r) ∉ (if now / p.windowSec = s.window then s.fired else [])) :
    (o.agent, r, now / p.windowSec) ∈ (step p s now obs).2 := by
  simp only [step, List.mem_map]
  refine ⟨(o.agent, r), (mem_fresh _ _ _).mpr ⟨?_, hn⟩, rfl⟩
  simp only [candidates, List.mem_flatMap, List.mem_map, List.mem_filter]
  exact ⟨o, ho, r, ⟨by cases r <;> simp [Rule.all], hr⟩, rfl⟩

/-- A tick is sound: every alert is a firing rule of an observed agent.

$$\forall (a, r, w) \in \mathrm{step}(\sigma, \mathit{now}, O).2:\quad \exists o \in O:\ o.\mathit{agent} = a \land r(o)$$
-/
theorem step_sound (p : Params) (s : State) (now : Nat) (obs : List Obs) (a : Alert)
    (h : a ∈ (step p s now obs).2) : ∃ o ∈ obs, o.agent = a.1 ∧ holds p o a.2.1 = true := by
  simp only [step, List.mem_map] at h
  obtain ⟨k, hk, rfl⟩ := h
  have := ((mem_fresh _ _ _).mp hk).1
  simp only [candidates, List.mem_flatMap, List.mem_map, List.mem_filter] at this
  obtain ⟨o, ho, r, ⟨_, hr⟩, rfl⟩ := this
  exact ⟨o, ho, rfl, hr⟩

/-- The run invariant: with non-decreasing tick times not before the state's window, the alerts
have no repeats, and each is in a later window than the state's, or in the same window with a key
not yet fired.

$$\mathrm{times}(T) \text{ non-decreasing} \land \forall (t, O) \in T:\ \sigma.w \le \lfloor t/\omega \rfloor \Rightarrow \mathrm{run}(\sigma, T).2 \text{ has no repeats} \land \forall (a, r, w) \in \mathrm{run}(\sigma, T).2:\ w > \sigma.w \lor \big(w = \sigma.w \land (a, r) \notin \sigma.F\big)$$
-/
theorem run_inv (p : Params) (s : State) (tr : List (Nat × List Obs))
    (hmono : (tr.map (·.1)).Pairwise (· ≤ ·)) (hge : ∀ x ∈ tr, s.window ≤ x.1 / p.windowSec) :
    (run p s tr).2.Nodup ∧ ∀ e ∈ (run p s tr).2,
      s.window < e.2.2 ∨ (e.2.2 = s.window ∧ (e.1, e.2.1) ∉ s.fired) := by
  induction tr generalizing s with
  | nil => simp [run]
  | cons x rest ih =>
    obtain ⟨now, obs⟩ := x
    simp only [List.map_cons, List.pairwise_cons, List.mem_map] at hmono
    have hw : s.window ≤ now / p.windowSec := hge _ List.mem_cons_self
    -- the state after the first tick
    let w := now / p.windowSec
    let f0 := if w = s.window then s.fired else []
    let new := fresh f0 (candidates p obs)
    have hs1 : (step p s now obs).1 = ⟨w, new ++ f0⟩ := rfl
    have ho1 : (step p s now obs).2 = new.map fun k => (k.1, k.2, w) := rfl
    have hge' : ∀ y ∈ rest, (step p s now obs).1.window ≤ y.1 / p.windowSec := by
      intro y hy
      rw [hs1]
      exact Nat.div_le_div_right (hmono.1 y.1 ⟨y, hy, rfl⟩)
    obtain ⟨ihn, ihf⟩ := ih _ hmono.2 hge'
    simp only [run]
    rw [ho1]
    rw [hs1] at ihf
    refine ⟨?_, ?_⟩
    · refine List.nodup_append.mpr ⟨?_, ihn, ?_⟩
      · refine List.Pairwise.map _ ?_ (fresh_nodup f0 (candidates p obs))
        intro a b hab e
        simp only [Prod.mk.injEq] at e
        exact hab (Prod.ext e.1 e.2.1)
      · intro a ha b hb e
        subst e
        simp only [List.mem_map] at ha
        obtain ⟨k, hk, rfl⟩ := ha
        rcases ihf _ hb with h | ⟨_, h⟩
        · exact Nat.lt_irrefl _ h
        · exact h (List.mem_append_left _ hk)
    · intro e he
      rcases List.mem_append.mp he with he | he
      · simp only [List.mem_map] at he
        obtain ⟨k, hk, rfl⟩ := he
        by_cases hws : w = s.window
        · refine .inr ⟨hws, ?_⟩
          have := ((mem_fresh _ _ _).mp hk).2
          simp only [f0, hws, ↓reduceIte] at this
          exact this
        · exact .inl (Nat.lt_of_le_of_ne hw (Ne.symm hws))
      · rcases ihf e he with h | ⟨h1, h2⟩
        · exact .inl (Nat.lt_of_le_of_lt hw h)
        · by_cases hws : w = s.window
          · refine .inr ⟨h1.trans hws, fun m => h2 (List.mem_append_right _ ?_)⟩
            simp only [f0, hws, ↓reduceIte]
            exact m
          · exact .inl (h1 ▸ Nat.lt_of_le_of_ne hw (Ne.symm hws))

/-- Once per window: over any trace with non-decreasing times, starting from the empty state,
no (agent, rule, window) alert is emitted twice.

$$\forall T:\quad \mathrm{times}(T) \text{ non-decreasing} \Rightarrow \mathrm{run}(\sigma_0, T).2 \text{ has no repeats}$$
-/
theorem once_per_window (p : Params) (tr : List (Nat × List Obs))
    (hmono : (tr.map (·.1)).Pairwise (· ≤ ·)) : (run p {} tr).2.Nodup :=
  (run_inv p {} tr hmono fun _ _ => Nat.zero_le _).1

/-! ## Examples -/

/-- An example observation.

$$\mathrm{ex}(a, c, i, t, g) = (a, c, i, t, g)$$
-/
def exObs (a : String) (ctx idle ttl gap : Nat) : Obs := ⟨a, ctx, idle, ttl, gap⟩

#guard ttlOf 10 20 == 3600 && ttlOf 20 20 == 300
#guard holds {} (exObs "a" 200001 0 300 0) .ctxBig && !holds {} (exObs "a" 200000 0 300 0) .ctxBig
#guard holds {} (exObs "a" 0 241 300 0) .idleExpiring && !holds {} (exObs "a" 0 240 300 0) .idleExpiring
#guard holds {} (exObs "a" 0 0 300 301) .coldWake && !holds {} (exObs "a" 0 0 300 300) .coldWake
#guard verdict {} (exObs "a" 50000 301 300 0) == .respawn
#guard verdict {} (exObs "a" 20000 301 300 0) == .resumeCheap
#guard verdict {} (exObs "a" 50000 300 300 0) == .resumeOk
-- the same idle agent seen twice in one hour alerts once; in the next hour again
#guard (run {} {} [(100, [exObs "a" 0 250 300 0]), (200, [exObs "a" 0 350 300 0]),
    (3700, [exObs "a" 0 3850 300 0])]).2 ==
  [("a", .idleExpiring, 0), ("a", .idleExpiring, 1)]
-- duplicate observations in one tick alert once
#guard (step {} {} 0 [exObs "a" 300000 0 300 0, exObs "a" 300000 0 300 0]).2 == [("a", .ctxBig, 0)]

end Fw.Ops.Meter
