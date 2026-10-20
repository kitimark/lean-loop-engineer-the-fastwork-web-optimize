/-!
# Where the time of a `fw ci wait` goes (task `ci-wait-lag`)

A wait that decided on a finish of its own passes through marks, all epoch milliseconds: GitHub marks the run done
(`upd`), the poller's list shows it (`tick`), the waiter reads the file (`read`), its jobs view ends (`viewEnd`),
fwcore decides (`done`), the cleanup ends (`ret`), the ingest of the CI spans runs from `i0` to `i1`, and the process
ends (`end`). `parts` cuts that path into seven pieces, each gap belongs to exactly one piece, and the pieces add up to
the whole (`parts_sum`). `fw timings --lag` (`apps/runner/src/timing-ci.ts`) only records the marks and replays the golden
`packages/contracts/golden/ci-budget/lag.jsonl` that this module generates.
-/
namespace Fw.Ci.Lag

/-- The marks of one wait, epoch milliseconds. -/
structure Marks where
  upd : Int
  tick : Int
  read : Int
  viewEnd : Int
  done : Int
  ret : Int
  i0 : Int
  i1 : Int
  stop : Int
  deriving Repr

/-- The pieces of the lag of one wait. `ingest` is the span ingest inside the exit, taken out of `exit`. -/
structure Parts where
  list : Int
  pickup : Int
  view : Int
  verdict : Int
  cleanup : Int
  ingest : Int
  exit : Int
  total : Int
  deriving Repr, DecidableEq

/-- The partition of the path from `upd` to the end into seven pieces and the total. -/
def parts (m : Marks) : Parts where
  list := m.tick - m.upd
  pickup := m.read - m.tick
  view := m.viewEnd - m.read
  verdict := m.done - m.viewEnd
  cleanup := m.ret - m.done
  ingest := m.i1 - m.i0
  exit := m.stop - m.ret - (m.i1 - m.i0)
  total := m.stop - m.upd

/-- **The seven pieces add up to the total**, for any marks, in order or not. -/
theorem parts_sum (m : Marks) :
    let p := parts m
    p.list + p.pickup + p.view + p.verdict + p.cleanup + p.ingest + p.exit = p.total := by
  simp only [parts]; omega

/-- The gap between the previous tick and the deciding tick. -/
def gap (tick prev : Int) : Int := tick - prev

/-- How long the list still showed the run unfinished after GitHub marked it done (never negative). -/
def stale (prev upd : Int) : Int := max 0 (prev - upd)

/-- **Staleness is never negative.** -/
theorem stale_nonneg (prev upd : Int) : 0 ≤ stale prev upd := by
  unfold stale; omega

/-- **No staleness when the previous tick came before the finish.** -/
theorem stale_zero_of_before (prev upd : Int) (h : prev ≤ upd) : stale prev upd = 0 := by
  simp [stale]; omega

#guard parts ⟨1000, 3000, 3100, 5000, 5010, 5020, 5030, 5230, 5300⟩ ==
  ⟨2000, 100, 1900, 10, 10, 200, 80, 4300⟩
#guard stale 900 1000 == 0
#guard stale 1500 1000 == 500

/-- Which kind of wait a span is. Only `done` waits count toward the lag: their lag is the wait's own. -/
inductive Kind | done | late | grace
  deriving Repr, DecidableEq

/-- The kind of a wait that decided on a finish. A required lane without a finished run: `grace`. Otherwise a tick
older than the wait's registration (`reg`): `late`. Otherwise `done`. -/
def kind (lanesMissing : Bool) (tick? : Option Int) (reg : Int) : Kind :=
  if lanesMissing then .grace
  else match tick? with
    | some t => if t < reg then .late else .done
    | none => .done

/-- **A lane without a finished run is a grace wait**, whatever the tick. -/
theorem kind_grace (t : Option Int) (reg : Int) : kind true t reg = .grace := by simp [kind]

/-- **A tick before the registration is a late wait** (all lanes there). -/
theorem kind_late (t reg : Int) (h : t < reg) : kind false (some t) reg = .late := by simp [kind, h]

/-- **A tick at or after the registration is a done wait** (all lanes there). -/
theorem kind_done (t reg : Int) (h : reg ≤ t) : kind false (some t) reg = .done := by
  simp [kind]; omega

/-- **With no tick seen the wait is done** (all lanes there). -/
theorem kind_done_none (reg : Int) : kind false none reg = .done := by simp [kind]

/-- The critical run of a wait: the index of the finish times `upds` with the latest one, the first on a tie. -/
def crit : List Int -> Option Nat
  | [] => none
  | x :: xs =>
    match crit xs with
    | none => some 0
    | some j => if xs.getD j 0 <= x then some 0 else some (j + 1)

/-- The critical run of a nonempty list exists. -/
theorem crit_some : (l : List Int) -> l ≠ [] -> ∃ i, crit l = some i := by
  intro l hl
  cases l with
  | nil => exact absurd rfl hl
  | cons x xs =>
    unfold crit
    cases crit xs with
    | none => exact ⟨0, rfl⟩
    | some j =>
      by_cases h : xs.getD j 0 <= x
      · exact ⟨0, by simp only [h, ↓reduceIte]⟩
      · exact ⟨j + 1, by simp only [h, ↓reduceIte]⟩

/-- **The critical run is a valid index and no run finished later.** -/
theorem crit_spec : (l : List Int) -> (i : Nat) -> crit l = some i ->
    ∃ h : i < l.length, ∀ j (hj : j < l.length), l[j] <= l[i] := by
  intro l
  induction l with
  | nil => intro i h; simp [crit] at h
  | cons x xs ih =>
    intro i h
    unfold crit at h
    cases hc : crit xs with
    | none =>
      rw [hc] at h
      have hi : i = 0 := by simpa using h.symm
      subst hi
      have hnil : xs = [] := by
        cases xs with
        | nil => rfl
        | cons y ys => obtain ⟨m, hm⟩ := crit_some (y :: ys) (by simp); rw [hc] at hm; cases hm
      subst hnil
      refine ⟨by simp, ?_⟩
      intro j hj; simp at hj; subst hj; simp
    | some k =>
      rw [hc] at h
      dsimp only at h
      obtain ⟨hk, hmax⟩ := ih k hc
      have hget : xs.getD k 0 = xs[k] := by simp [hk]
      by_cases hle : xs[k] <= x
      · have hle' : xs.getD k 0 <= x := by rw [hget]; exact hle
        have hi : i = 0 := by simp only [hle', ↓reduceIte] at h; injection h with h; omega
        subst hi
        refine ⟨by simp, ?_⟩
        intro j hj; cases j with
        | zero => simp
        | succ j => have := hmax j (by simpa using hj); simp; omega
      · have hle' : ¬ xs.getD k 0 <= x := by rw [hget]; exact hle
        have hi : i = k + 1 := by simp only [hle', ↓reduceIte] at h; injection h with h; omega
        subst hi
        refine ⟨by simp; omega, ?_⟩
        intro j hj; cases j with
        | zero => simp; omega
        | succ j => simp; exact hmax j (by simpa using hj)

#guard kind true none 5 == .grace
#guard kind false (some 4) 5 == .late
#guard kind false (some 5) 5 == .done
#guard kind false none 5 == .done
#guard crit [] == none
#guard crit [3, 9, 9, 2] == some 1
#guard crit [9, 9] == some 0

end Fw.Ci.Lag
