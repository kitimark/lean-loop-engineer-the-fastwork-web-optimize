import Lean.Data.Json
import Fw.Device.EndFloor
/-! End-floor window: the frame-count-pinned window and the per-rep transient-or-steady reading of the WKTR tick probe. -/
namespace Fw.Device.EndFloorWindow
open Lean Fw.Device.EndWktr

def pinN : Nat := 48

def pinReps : Nat := 12

def minReps : Nat := 6

def stop (k : Nat) : Bool := pinN ≤ k

def readLoop : Nat → Nat → Nat
  | 0, k => k
  | fuel + 1, k => if stop k then k else readLoop fuel (k + 1)

theorem readLoop_exact (k : Nat) (h : k ≤ pinN) : readLoop (pinN - k) k = pinN := by
  have key : ∀ fuel k, k ≤ pinN → pinN - k = fuel → readLoop fuel k = pinN := by
    intro fuel
    induction fuel with
    | zero => intro k hk hf; simp only [readLoop]; omega
    | succ f ih =>
      intro k hk hf
      by_cases hs : stop k = true
      · simp only [readLoop, hs, ite_true]
        simp only [stop, decide_eq_true_eq] at hs
        omega
      · have hlt : k < pinN := by simp only [stop, Bool.not_eq_true, decide_eq_false_iff_not] at hs; omega
        simp only [readLoop, hs]
        exact ih (k + 1) (by omega) (by omega)
  exact key _ k h rfl

theorem window_reads_pinN : readLoop pinN 0 = pinN := by
  simpa using readLoop_exact 0 (Nat.zero_le _)

inductive Pin where
  | empty | pinned | fewer | unpinned
  deriving DecidableEq, Repr

def Pin.name : Pin → String
  | .empty => "empty" | .pinned => "pinned" | .fewer => "fewer reps" | .unpinned => "unpinned"

def pinOf (wins : List Nat) : Pin :=
  if wins = [] then .empty
  else if wins.all (· == pinN) then (if wins.length = pinReps then .pinned else .fewer)
  else .unpinned

theorem pinOf_empty : pinOf [] = .empty := by simp [pinOf]

theorem pinOf_pinned (wins : List Nat) (hall : wins.all (· == pinN) = true) (hl : wins.length = pinReps) : pinOf wins = .pinned := by
  have hne : wins ≠ [] := by
    intro h
    have : pinReps = 0 := by simpa [h] using hl.symm
    simp [pinReps] at this
  simp [pinOf, hne, hall, hl]

theorem pinOf_fewer (wins : List Nat) (hne : wins ≠ []) (hall : wins.all (· == pinN) = true) (hl : wins.length ≠ pinReps) :
    pinOf wins = .fewer := by
  simp [pinOf, hne, hall, hl]

theorem pinOf_unpinned (wins : List Nat) (hne : wins ≠ []) (hall : wins.all (· == pinN) = false) : pinOf wins = .unpinned := by
  simp [pinOf, hne, hall]

theorem sum_of_all_eq (wins : List Nat) (h : wins.all (· == pinN) = true) : wins.sum = pinN * wins.length := by
  induction wins with
  | nil => simp
  | cons a t ih =>
    simp only [List.all_cons, Bool.and_eq_true, beq_iff_eq] at h
    have := ih h.2
    simp only [List.sum_cons, List.length_cons, this, h.1]
    rw [Nat.mul_succ]
    omega

theorem pinned_frames (wins : List Nat) (h : pinOf wins = .pinned) : wins.sum = pinN * pinReps := by
  unfold pinOf at h
  by_cases h0 : wins = []
  · simp [h0] at h
  by_cases h1 : wins.all (· == pinN) = true
  · by_cases h2 : wins.length = pinReps
    · rw [sum_of_all_eq wins h1, h2]
    · simp [h0, h1, h2] at h
  · simp [h0, h1] at h

theorem pinned_equal (a b : List Nat) (ha : pinOf a = .pinned) (hb : pinOf b = .pinned) : a.sum = b.sum := by
  rw [pinned_frames a ha, pinned_frames b hb]

theorem legacy_windows_unpinned : pinOf [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3] = .unpinned ∧
    pinOf [15, 17, 17, 18, 17, 16, 16, 18, 15, 16, 17, 17] = .unpinned := by decide

structure Tick where
  r : Nat
  m : Nat
  q : Nat
  d : Nat
  deriving DecidableEq, Repr

inductive Fc where
  | tick | quiet | idle
  deriving DecidableEq, Repr

def Tick.cls (t : Tick) : Fc := if 0 < t.m then .tick else if 0 < t.q then .quiet else .idle

inductive Rc where
  | empty | steady | accelerated | transient | elsewhere | resumes
  deriving DecidableEq, Repr

def Rc.name : Rc → String
  | .empty => "empty" | .steady => "steady" | .accelerated => "accelerated" | .transient => "transient" | .elsewhere => "elsewhere"
  | .resumes => "resumes"

def settlesFrom : Bool → List Tick → Bool
  | _, [] => true
  | s, t :: ts => match t.cls with
    | .tick => !s && settlesFrom s ts
    | .quiet => settlesFrom true ts
    | .idle => settlesFrom s ts

def hasCls (c : Fc) (ts : List Tick) : Bool := ts.any (·.cls == c)

def laterRecalc (ts : List Tick) : Bool := ts.any fun t => t.cls != .tick && 0 < t.r

def pick (any settles qr hq ht : Bool) : Rc :=
  if any = false then .empty
  else if settles = false then .resumes
  else if qr = true then .elsewhere
  else if hq = false then .steady
  else if ht = false then .accelerated
  else .transient

def repClass (ts : List Tick) : Rc :=
  pick (hasCls .tick ts || hasCls .quiet ts) (settlesFrom false ts) (laterRecalc ts) (hasCls .quiet ts) (hasCls .tick ts)

def startupLen (ts : List Tick) : Nat := (ts.takeWhile fun t => t.cls == .tick).length

theorem pick_empty : ∀ a s q hq ht, pick a s q hq ht = .empty ↔ a = false := by decide

theorem pick_resumes : ∀ a s q hq ht, pick a s q hq ht = .resumes ↔ (a = true ∧ s = false) := by decide

theorem pick_elsewhere : ∀ a s q hq ht, pick a s q hq ht = .elsewhere ↔ (a = true ∧ s = true ∧ q = true) := by decide

theorem pick_steady : ∀ a s q hq ht, pick a s q hq ht = .steady ↔ (a = true ∧ s = true ∧ q = false ∧ hq = false) := by decide

theorem pick_accelerated : ∀ a s q hq ht, pick a s q hq ht = .accelerated ↔
    (a = true ∧ s = true ∧ q = false ∧ hq = true ∧ ht = false) := by decide

theorem pick_transient : ∀ a s q hq ht, pick a s q hq ht = .transient ↔
    (a = true ∧ s = true ∧ q = false ∧ hq = true ∧ ht = true) := by decide

theorem repClass_empty (ts : List Tick) : repClass ts = .empty ↔ (hasCls .tick ts || hasCls .quiet ts) = false :=
  pick_empty _ _ _ _ _

theorem repClass_resumes (ts : List Tick) : repClass ts = .resumes ↔
    ((hasCls .tick ts || hasCls .quiet ts) = true ∧ settlesFrom false ts = false) := pick_resumes _ _ _ _ _

theorem repClass_elsewhere (ts : List Tick) : repClass ts = .elsewhere ↔
    ((hasCls .tick ts || hasCls .quiet ts) = true ∧ settlesFrom false ts = true ∧ laterRecalc ts = true) :=
  pick_elsewhere _ _ _ _ _

theorem repClass_steady (ts : List Tick) : repClass ts = .steady ↔
    ((hasCls .tick ts || hasCls .quiet ts) = true ∧ settlesFrom false ts = true ∧ laterRecalc ts = false ∧
      hasCls .quiet ts = false) := pick_steady _ _ _ _ _

theorem repClass_accelerated (ts : List Tick) : repClass ts = .accelerated ↔
    ((hasCls .tick ts || hasCls .quiet ts) = true ∧ settlesFrom false ts = true ∧ laterRecalc ts = false ∧
      hasCls .quiet ts = true ∧ hasCls .tick ts = false) := pick_accelerated _ _ _ _ _

theorem repClass_transient (ts : List Tick) : repClass ts = .transient ↔
    ((hasCls .tick ts || hasCls .quiet ts) = true ∧ settlesFrom false ts = true ∧ laterRecalc ts = false ∧
      hasCls .quiet ts = true ∧ hasCls .tick ts = true) := pick_transient _ _ _ _ _

theorem laterRecalc_false (ts : List Tick) (h : laterRecalc ts = false) : ∀ t ∈ ts, t.cls ≠ .tick → t.r = 0 := by
  intro t ht hq
  have h2 := List.any_eq_false.mp h t ht
  have h3 : (t.cls != Fc.tick) = true := bne_iff_ne.mpr hq
  have h4 : ¬ (0 < t.r) := by
    intro hr
    apply h2
    simp [h3, hr]
  omega

theorem transient_later_free (ts : List Tick) (h : repClass ts = .transient) : ∀ t ∈ ts, t.cls ≠ .tick → t.r = 0 :=
  laterRecalc_false ts ((repClass_transient ts).mp h).2.2.1

theorem transient_settles (ts : List Tick) (h : repClass ts = .transient) : settlesFrom false ts = true :=
  ((repClass_transient ts).mp h).2.1

theorem elsewhere_recalc (ts : List Tick) (h : repClass ts = .elsewhere) : laterRecalc ts = true :=
  ((repClass_elsewhere ts).mp h).2.2

theorem steady_no_quiet (ts : List Tick) (h : repClass ts = .steady) : hasCls .quiet ts = false :=
  ((repClass_steady ts).mp h).2.2.2


structure Rep where
  ts : List Tick
  deriving DecidableEq, Repr

inductive Av where
  | unread | alike (c : Rc) | mixed
  deriving DecidableEq, Repr

def Av.name : Av → String
  | .unread => "unread" | .alike c => c.name | .mixed => "mixed"

def armVerdict (reps : List (List Tick)) : Av :=
  if reps.length < minReps then .unread
  else match reps.map repClass with
    | [] => .unread
    | c :: cs => if cs.all (· == c) then .alike c else .mixed

theorem armVerdict_unread (reps : List (List Tick)) (h : reps.length < minReps) : armVerdict reps = .unread := by
  simp [armVerdict, h]

theorem armVerdict_alike (reps : List (List Tick)) (c : Rc) (cs : List Rc) (h0 : ¬ reps.length < minReps)
    (hm : reps.map repClass = c :: cs) (h : cs.all (· == c) = true) : armVerdict reps = .alike c := by
  simp [armVerdict, h0, hm, h]

theorem armVerdict_mixed (reps : List (List Tick)) (c : Rc) (cs : List Rc) (h0 : ¬ reps.length < minReps)
    (hm : reps.map repClass = c :: cs) (h : cs.all (· == c) = false) : armVerdict reps = .mixed := by
  simp [armVerdict, h0, hm, h]

def classRate (c : Fc) (reps : List (List Tick)) : Nat :=
  rpf100 ((reps.flatten.filter fun t => t.cls == c).map (·.r))

theorem rpf100_zero (xs : List Nat) (h : ∀ x ∈ xs, x = 0) : rpf100 xs = 0 := by
  have : xs.sum = 0 := by
    induction xs with
    | nil => rfl
    | cons a t ih =>
      simp only [List.sum_cons]
      rw [h a (by simp), ih (fun x hx => h x (by simp [hx]))]
  simp [rpf100, this]

theorem alike_transient_later_rate (reps : List (List Tick)) (k : Fc) (hk : k ≠ .tick) (h : armVerdict reps = .alike .transient) :
    classRate k reps = 0 := by
  unfold armVerdict at h
  by_cases h0 : reps.length < minReps
  · simp [h0] at h
  have hq : ∀ ts ∈ reps, repClass ts = .transient := by
    revert h
    cases hm : reps.map repClass with
    | nil => simp [h0]
    | cons c cs =>
      intro h
      simp only [h0, ite_false] at h
      by_cases hc : cs.all (· == c) = true
      · simp only [hc, ite_true, Av.alike.injEq] at h
        subst h
        intro ts hts
        have hmem : repClass ts ∈ reps.map repClass := List.mem_map_of_mem hts
        rw [hm] at hmem
        simp only [List.mem_cons] at hmem
        rcases hmem with h1 | h1
        · exact h1
        · simpa [List.all_eq_true] using (List.all_eq_true.mp hc) _ h1
      · simp [hc] at h
  apply rpf100_zero
  intro x hx
  simp only [List.mem_map, List.mem_filter, List.mem_flatten, beq_iff_eq] at hx
  obtain ⟨t, ⟨⟨ts, hts, htt⟩, hcl⟩, hr⟩ := hx
  rw [← hr]
  exact transient_later_free ts (hq ts hts) t htt (by rw [hcl]; exact hk)

def repsOf (rs : List (List Tick)) : Nat := rs.length

private def tk (r m q d : Nat) : Tick := ⟨r, m, q, d⟩

private def tickJ (t : Tick) : Json := Json.arr #[toJson t.r, toJson t.m, toJson t.q, toJson t.d]

private def repJ (ts : List Tick) : Json := Json.arr (ts.map tickJ).toArray

private def repsJ (rs : List (List Tick)) : Json := Json.arr (rs.map repJ).toArray

private def listJ (xs : List Nat) : Json := Json.arr (xs.map fun x => toJson x).toArray

private def winCases : List (String × List Nat) :=
  [("pinned", List.replicate pinReps pinN), ("empty", []), ("fewer reps", List.replicate (pinReps - 1) pinN),
   ("legacy three", List.replicate pinReps 3), ("legacy long", [15, 17, 17, 18, 17, 16, 16, 18, 15, 16, 17, 17]),
   ("one short rep", pinN :: List.replicate (pinReps - 1) (pinN - 1)), ("one long rep", (pinN + 1) :: List.replicate (pinReps - 1) pinN)]

private def transientRep : List Tick :=
  [tk 2 3 0 0, tk 1 2 1 0, tk 0 0 3 0, tk 0 0 3 0, tk 0 0 3 0, tk 0 0 0 3, tk 0 0 0 3, tk 0 0 0 3, tk 0 0 0 3, tk 0 0 0 3, tk 0 0 0 3, tk 0 0 0 3]

private def repCases : List (String × List Tick) :=
  [("transient", transientRep),
   ("steady", (List.range pinN).map fun i => if i < 8 then tk 1 4 0 0 else tk 0 0 0 4),
   ("accelerated", (List.range pinN).map fun i => if i < 8 then tk 0 0 4 0 else tk 0 0 0 4),
   ("elsewhere", (List.range pinN).map fun i => if i < 2 then tk 2 3 1 0 else tk 1 0 4 0),
   ("resumes", [tk 1 2 0 0, tk 0 0 2 0, tk 1 1 1 0, tk 0 0 0 2]),
   ("empty", List.replicate pinN (tk 0 0 0 4)),
   ("quiet frame with a recalc", [tk 1 2 0 0, tk 1 0 2 0, tk 0 0 0 2]),
   ("idle frame with a recalc", [tk 1 2 0 0, tk 0 0 2 0, tk 3 0 0 2]),
   ("tick after idle after quiet", [tk 0 1 0 0, tk 0 0 2 0, tk 0 0 0 2, tk 1 1 0 1]),
   ("pending then quiet", [tk 1 4 0 0, tk 0 0 4 0]),
   ("one tick frame", [tk 1 1 0 0])]

private def armCases : List (String × List (List Tick)) :=
  [("all transient", List.replicate pinReps transientRep), ("one rep short of minimum", List.replicate (minReps - 1) transientRep),
   ("minimum reps", List.replicate minReps transientRep),
   ("one differs", transientRep :: List.replicate (pinReps - 1) (List.replicate pinN (tk 1 0 4 0))),
   ("all elsewhere", List.replicate pinReps (List.replicate pinN (tk 1 0 4 0))),
   ("all steady", List.replicate pinReps (List.replicate pinN (tk 1 4 0 0))),
   ("no reps", [])]

private def overallCases : List (String × List Av) :=
  [("three alike", [.alike .transient, .alike .transient, .alike .transient]),
   ("one unread", [.alike .transient, .unread, .alike .transient]), ("two unread", [.alike .transient, .unread, .unread]),
   ("one differs", [.alike .transient, .alike .elsewhere, .alike .transient]), ("mixed job", [.alike .transient, .mixed, .alike .transient])]

def overall (vs : List Av) : String := overallNames ((vs.filter fun v => v != .unread).map Av.name)

theorem overall_inconclusive (vs : List Av) (h : (vs.filter fun v => v != .unread).length < minValid) : overall vs = "inconclusive" := by
  simpa [overall] using overallNames_inconclusive _ (by simpa using h)

def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("pinN", pinN), ("pinReps", pinReps), ("minReps", minReps)]).compress] ++
  (winCases.map fun (n, w) =>
    (Json.mkObj [("kind", "pin"), ("name", n), ("wins", listJ w), ("pin", Json.str (pinOf w).name)]).compress) ++
  (repCases.map fun (n, ts) =>
    (Json.mkObj [("kind", "rep"), ("name", n), ("ticks", repJ ts), ("class", Json.str (repClass ts).name),
      ("startup", startupLen ts)]).compress) ++
  (armCases.map fun (n, rs) =>
    (Json.mkObj [("kind", "arm"), ("name", n), ("reps", repsJ rs), ("verdict", Json.str (armVerdict rs).name),
      ("tickRate", classRate .tick rs), ("quietRate", classRate .quiet rs), ("idleRate", classRate .idle rs)]).compress) ++
  (overallCases.map fun (n, vs) =>
    (Json.mkObj [("kind", "overall"), ("name", n), ("verdicts", Json.arr (vs.map fun v => Json.str v.name).toArray),
      ("overall", Json.str (overall vs))]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "device" / "end-floor-window.jsonl"

def checkRepo : IO Unit := do
  let cur ← IO.FS.readBinFile goldenPath
  if cur.data != (goldenText ()).toUTF8.data then throw (IO.userError s!"device-end-floor-window golden differs: {goldenPath}")
  IO.println s!"device-end-floor-window golden: up to date ({(goldenLines ()).length} lines)"

def writeRepo : IO Unit := IO.FS.writeFile goldenPath (goldenText ())

end Fw.Device.EndFloorWindow
