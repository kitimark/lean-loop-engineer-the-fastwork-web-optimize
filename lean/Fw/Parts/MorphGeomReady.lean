import Fw.Parts.MorphGeomVerify
namespace Fw.Parts.MorphGeom

structure CellObs where
  cols : Nat
  imgs : Nat
  loaded : Nat
  running : Nat

def sideLoaded (o : CellObs) : Bool := o.loaded == o.imgs

def sideSettled (o : CellObs) : Bool := o.running == 0

def cellReady (want : Nat) (base flag : CellObs) : Bool :=
  flag.cols == want && flag.imgs == base.imgs && sideLoaded base && sideLoaded flag && sideSettled base && sideSettled flag

theorem ready_no_columns_waits (want : Nat) (base flag : CellObs) (h : flag.cols ≠ want) :
    cellReady want base flag = false := by simp [cellReady, h]

theorem ready_missing_images_waits (want : Nat) (base flag : CellObs) (h : flag.imgs ≠ base.imgs) :
    cellReady want base flag = false := by simp [cellReady, h]

theorem ready_unloaded_waits (want : Nat) (base flag : CellObs) (h : sideLoaded flag = false) :
    cellReady want base flag = false := by simp [cellReady, h]

theorem ready_base_unloaded_waits (want : Nat) (base flag : CellObs) (h : sideLoaded base = false) :
    cellReady want base flag = false := by simp [cellReady, h]

theorem ready_flag_moving_waits (want : Nat) (base flag : CellObs) (h : sideSettled flag = false) :
    cellReady want base flag = false := by simp [cellReady, h]

theorem ready_base_moving_waits (want : Nat) (base flag : CellObs) (h : sideSettled base = false) :
    cellReady want base flag = false := by simp [cellReady, h]

theorem ready_mounted_reads (want : Nat) (base flag : CellObs) (hc : flag.cols = want) (hi : flag.imgs = base.imgs)
    (hb : base.loaded = base.imgs) (hf : flag.loaded = flag.imgs) (hbr : base.running = 0) (hfr : flag.running = 0) :
    cellReady want base flag = true := by
  simp [cellReady, sideLoaded, sideSettled, hc, hi, hb, hf, hbr, hfr]

inductive WaitStep where
  | poll
  | read
  | late
  deriving DecidableEq

def WaitStep.name : WaitStep → String
  | .poll => "poll"
  | .read => "read"
  | .late => "late"

def waitStep (elapsed limit : Nat) (ready : Bool) : WaitStep :=
  if ready then .read else if limit ≤ elapsed then .late else .poll

theorem wait_ready_reads (elapsed limit : Nat) : waitStep elapsed limit true = .read := by simp [waitStep]

theorem wait_bounded (elapsed limit : Nat) (ready : Bool) (h : limit ≤ elapsed) : waitStep elapsed limit ready ≠ .poll := by
  cases ready <;> simp [waitStep, h]

theorem wait_polls_early (elapsed limit : Nat) (h : elapsed < limit) : waitStep elapsed limit false = .poll := by
  have : ¬ limit ≤ elapsed := by omega
  simp [waitStep, this]

def waitVerdict (st : WaitStep) (defects : Nat) : Option Bool :=
  if st = .poll then none else some (defects == 0)

theorem late_same_as_read (defects : Nat) : waitVerdict .late defects = waitVerdict .read defects := by
  simp [waitVerdict]

theorem late_defect_fails (defects : Nat) (h : 0 < defects) : waitVerdict .late defects = some false := by
  have : defects ≠ 0 := by omega
  simp [waitVerdict, this]

inductive Attempt where
  | fault
  | reading (ok : Bool)

def Attempt.name : Attempt → String
  | .fault => "fault"
  | .reading true => "pass"
  | .reading false => "fail"

inductive Outcome where
  | pass
  | fail
  | exhausted
  deriving DecidableEq

def Outcome.name : Outcome → String
  | .pass => "pass"
  | .fail => "fail"
  | .exhausted => "exhausted"

def Outcome.ok : Outcome → Bool
  | .pass => true
  | _ => false

def firstReading : List Attempt → Option Bool
  | [] => none
  | .fault :: rest => firstReading rest
  | .reading ok :: _ => some ok

def cellOutcome (max : Nat) (as : List Attempt) : Outcome :=
  match firstReading (as.take max) with
  | some true => .pass
  | some false => .fail
  | none => .exhausted

theorem outcome_all_faults_exhausted (max : Nat) (as : List Attempt) (h : ∀ a ∈ as, a = .fault) :
    cellOutcome max as = .exhausted := by
  have hf : ∀ l : List Attempt, (∀ a ∈ l, a = .fault) → firstReading l = none := by
    intro l
    induction l with
    | nil => intro _; rfl
    | cons a t ih =>
      intro hl
      have ha : a = .fault := hl a (by simp)
      subst ha
      simp [firstReading, ih (fun x hx => hl x (by simp [hx]))]
  have := hf (as.take max) (fun a ha => h a (List.mem_of_mem_take ha))
  simp [cellOutcome, this]

theorem firstReading_prefix (pre rest : List Attempt) (ok : Bool) (h : ∀ a ∈ pre, a = .fault) :
    firstReading (pre ++ .reading ok :: rest) = some ok := by
  induction pre with
  | nil => rfl
  | cons a t ih =>
    have ha : a = .fault := h a (by simp)
    subst ha
    simp [firstReading, ih (fun x hx => h x (by simp [hx]))]

theorem take_past_prefix (pre rest : List Attempt) (x : Attempt) (max : Nat) (h : pre.length < max) :
    (pre ++ x :: rest).take max = pre ++ x :: rest.take (max - pre.length - 1) := by
  induction pre generalizing max with
  | nil =>
    cases max with
    | zero => simp at h
    | succ k => simp
  | cons a t ih =>
    cases max with
    | zero => simp at h
    | succ k =>
      have h' : t.length < k := by simp at h; omega
      simp [ih k h']

theorem retry_defect_stays_fail (max : Nat) (pre rest : List Attempt) (h : ∀ a ∈ pre, a = .fault)
    (hl : pre.length < max) : cellOutcome max (pre ++ .reading false :: rest) = .fail := by
  rw [cellOutcome, take_past_prefix pre rest (.reading false) max hl, firstReading_prefix pre _ false h]

theorem outcome_pass_has_reading (max : Nat) (as : List Attempt) (h : (cellOutcome max as).ok = true) :
    Attempt.reading true ∈ as := by
  have key : ∀ l : List Attempt, firstReading l = some true → Attempt.reading true ∈ l := by
    intro l
    induction l with
    | nil => simp [firstReading]
    | cons a t ih =>
      cases a with
      | fault => intro hh; simp [firstReading] at hh; exact List.mem_cons_of_mem _ (ih hh)
      | reading ok => intro hh; simp [firstReading] at hh; simp [hh]
  unfold cellOutcome at h
  split at h
  · rename_i hr; exact List.mem_of_mem_take (key _ hr)
  · rename_i hr; simp [Outcome.ok] at h
  · rename_i hr; simp [Outcome.ok] at h

inductive Next where
  | done
  | again
  | stop
  deriving DecidableEq

def Next.name : Next → String
  | .done => "done"
  | .again => "again"
  | .stop => "stop"

def retryNext (n max : Nat) : Attempt → Next
  | .reading _ => .done
  | .fault => if n < max then .again else .stop

theorem retry_reading_done (n max : Nat) (ok : Bool) : retryNext n max (.reading ok) = .done := rfl

theorem retry_fault_again (n max : Nat) (h : n < max) : retryNext n max .fault = .again := by simp [retryNext, h]

theorem retry_fault_stops (n max : Nat) (h : max ≤ n) : retryNext n max .fault = .stop := by
  have : ¬ n < max := by omega
  simp [retryNext, this]

inductive ErrKind where
  | stall
  | defect
  deriving DecidableEq

def ErrKind.name : ErrKind → String
  | .stall => "stall"
  | .defect => "defect"

def errKind (errName : String) : ErrKind :=
  if errName = "LimitError" ∨ errName = "TimeoutError" then .stall else .defect

def ErrKind.attempt : ErrKind → Attempt
  | .stall => .fault
  | .defect => .reading false

theorem err_limit_is_stall : errKind "LimitError" = .stall := by simp [errKind]

theorem err_timeout_is_stall : errKind "TimeoutError" = .stall := by simp [errKind]

theorem err_other_is_defect (errName : String) (h1 : errName ≠ "LimitError") (h2 : errName ≠ "TimeoutError") :
    errKind errName = .defect := by simp [errKind, h1, h2]

theorem err_stall_is_fault : ErrKind.attempt .stall = .fault := rfl

theorem err_defect_not_retried (n max : Nat) : retryNext n max (ErrKind.attempt .defect) = .done := rfl

theorem err_defect_first_fails (max : Nat) (rest : List Attempt) (h : 0 < max) :
    cellOutcome max (ErrKind.attempt .defect :: rest) = .fail := by
  have := retry_defect_stays_fail max [] rest (by simp) (by simpa using h)
  simpa [ErrKind.attempt] using this

def cellsPass (os : List Outcome) : Bool := os.all Outcome.ok

def cellsKept (os : List Outcome) : Bool := os.all fun o => o != .exhausted

theorem cells_pass_exhausted_fails (os : List Outcome) (h : Outcome.exhausted ∈ os) : cellsPass os = false := by
  cases hp : cellsPass os with
  | false => rfl
  | true =>
    have := List.all_eq_true.mp hp _ h
    simp [Outcome.ok] at this

theorem cells_pass_fail_fails (os : List Outcome) (h : Outcome.fail ∈ os) : cellsPass os = false := by
  cases hp : cellsPass os with
  | false => rfl
  | true =>
    have := List.all_eq_true.mp hp _ h
    simp [Outcome.ok] at this

theorem cells_kept_exhausted_fails (os : List Outcome) (h : Outcome.exhausted ∈ os) : cellsKept os = false := by
  cases hp : cellsKept os with
  | false => rfl
  | true =>
    have := List.all_eq_true.mp hp _ h
    simp at this

theorem cells_kept_reports_fail (os : List Outcome) (h : ∀ o ∈ os, o ≠ .exhausted) : cellsKept os = true := by
  exact List.all_eq_true.mpr fun o ho => by simpa using h o ho

def readyLimitMs : Nat := 20000
def readyPollMs : Nat := 250
def shotLimitMs : Nat := 120000
def callLimitMs : Nat := 60000
def closeLimitMs : Nat := 15000
def maxAttempts : Nat := 2

theorem limits_ordered : readyPollMs < readyLimitMs ∧ closeLimitMs < callLimitMs ∧ callLimitMs < shotLimitMs ∧ 1 < maxAttempts := by
  decide

end Fw.Parts.MorphGeom
