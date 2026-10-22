/-!
# Steps after the measurement step of the macOS jobs (task `macos-teardown-trim`)
The allowlist per job, the lint decision `checkJob` and the theorem that a result upload runs on success.
-/
namespace Fw.Ci.Steps

/-- The status of a job when a step is reached. -/
inductive Status where
  | success
  | failure
  | cancelled
  deriving DecidableEq, Repr

/-- Every status. -/
def Status.all : List Status := [.success, .failure, .cancelled]

/-- The status function a step is guarded with (always together with `steps.stale.outcome == 'skipped'`). -/
inductive Cond where
  | notCancelled
  | always
  | failure
  deriving DecidableEq, Repr

/-- Whether a step guarded with `c` runs at job status `s` (GitHub's `!cancelled()`, `always()`, `failure()`). -/
def Cond.runs : Cond → Status → Bool
  | .notCancelled, s => s != .cancelled
  | .always, _ => true
  | .failure, s => s == .failure

/-- The `if:` text of a guarded step, written into the workflow. -/
def Cond.text : Cond → String
  | .notCancelled => "${{ (!cancelled()) && steps.stale.outcome == 'skipped' }}"
  | .always => "${{ (always()) && steps.stale.outcome == 'skipped' }}"
  | .failure => "${{ failure() && steps.stale.outcome == 'skipped' }}"

/-- What a step after the measurement step is for. -/
inductive Kind where
  | collect
  | hostState
  | teardown
  | upload
  | telemetry
  deriving DecidableEq, Repr

/-- The label of every upload step. -/
def uploadLabel : String := "actions/upload-artifact"

/-- An allowed step: its label, kind and guard. -/
structure Post where
  label : String
  kind : Kind
  cond : Cond
  deriving DecidableEq, Repr

/-- A macOS job: its measurement step and the steps allowed after it, in order. -/
structure Row where
  file : String
  job : String
  measure : String
  post : List Post
  deriving DecidableEq, Repr

/-- A job with a step that shuts down or deletes a Simulator of a VM that is discarded. -/
def Row.hasTeardown (r : Row) : Bool := r.post.any (·.kind == .teardown)

/-- The upload of a result, guarded to run whenever the job was not cancelled. -/
def up (c : Cond) : Post := ⟨uploadLabel, .upload, c⟩

/-- The telemetry finish step. -/
def tel : Post := ⟨"./.github/actions/telemetry", .telemetry, .always⟩

/-- The allowlist: the macOS jobs. -/
def rows : List Row := [
  ⟨"webkit-sim.yml", "sim", "Determinism sessions",
    [⟨"Keep logs", .collect, .notCancelled⟩, ⟨"Host state on failure", .hostState, .failure⟩, up .notCancelled, tel]⟩,
  ⟨"toolbar-throttle.yml", "sim", "Touch probe (three arms, rotated per round)",
    [⟨"Keep logs", .collect, .notCancelled⟩, ⟨"Host state on failure", .hostState, .failure⟩, up .notCancelled, tel]⟩,
  ⟨"path-pix.yml", "sim", "Path-pix capture (all arms, all offsets)",
    [⟨"Keep logs", .collect, .notCancelled⟩, ⟨"Host state on failure", .hostState, .failure⟩, up .notCancelled, tel]⟩,
  ⟨"wktr.yml", "wktr", "WKTR, fresh process per pass, per variant",
    [⟨"Delete the Simulator device", .teardown, .always⟩, up .always]⟩,
  ⟨"wktr-fixtures.yml", "fixtures", "WKTR fixtures, fresh process per pass and cell",
    [⟨"Delete the Simulator devices", .teardown, .always⟩, up .always]⟩,
  ⟨"engine-premises.yml", "webkit", "WKTR premise run, fresh process per pass",
    [⟨"Delete the Simulator device", .teardown, .always⟩, up .always]⟩,
  ⟨"gate-gaps.yml", "collect-macos", "Collect (Playwright WebKit, WKWebView, Simulator; no judging here)",
    [⟨"Shut down and delete the Simulator devices", .teardown, .always⟩, up .always]⟩]

/-- The `file/job` ids of the jobs whose Simulator teardown is still there (follow-up trims). -/
def flagged : List String := (rows.filter (·.hasTeardown)).map fun r => r.file ++ "/" ++ r.job

/-- A step as the lint reads it from the workflow: label, `if:` text and `timeout-minutes` text. -/
structure Obs where
  label : String
  ifText : Option String
  timeout : Option String
  deriving DecidableEq, Repr

/-- The step the allowlist asks for. -/
def Post.expected (p : Post) : Obs := ⟨p.label, some p.cond.text, none⟩

/-- Step label: its name, else its action without the ref. -/
def labelOf (name uses : Option String) : String :=
  match name, uses with
  | some n, _ => n
  | none, some u => (u.splitOn "@").headD u
  | none, none => ""

/-- Problems of the observed steps against the allowed ones, walked in step. -/
def go : List Post → List Obs → List String
  | [], [] => []
  | p :: ps, [] => ("missing:" ++ p.label) :: go ps []
  | [], o :: os => ("unlisted:" ++ o.label) :: go [] os
  | p :: ps, o :: os =>
    if o.label = p.label then
      (if o.ifText = some p.cond.text then [] else ["cond:" ++ o.label])
        ++ (if o.timeout = none then [] else ["timeout:" ++ o.label]) ++ go ps os
    else if os.any (·.label = p.label) then ("unlisted:" ++ o.label) :: go (p :: ps) os
    else ("missing:" ++ p.label) :: go ps (o :: os)
termination_by ps os => ps.length + os.length

/-- The steps after the measurement step, if it occurs exactly once. -/
def tailAfter (m : String) : List Obs → Option (List Obs)
  | [] => none
  | o :: os => if o.label = m then (if os.any (·.label = m) then none else some os) else tailAfter m os

/-- Problems of a job's steps against its row. -/
def checkJob (r : Row) (steps : List Obs) : List String :=
  match tailAfter r.measure steps with
  | none => ["measure:" ++ r.measure]
  | some t => go r.post t

/-- The jobs the allowlist names for a workflow file. -/
def listed (file : String) : List String := (rows.filter (·.file = file)).map (·.job)

/-- Problems of the macOS jobs found in a workflow against the rows of its file. -/
def coverage (file : String) (found : List String) : List String :=
  (found.filter (fun j => !(listed file).contains j)).map ("uncovered:" ++ ·)
    ++ ((listed file).filter (fun j => !found.contains j)).map ("stale-row:" ++ ·)

/-! ## The allowlist -/

/-- Every row has an upload that runs on success. -/
theorem upload_runs_on_success : ∀ r ∈ rows, ∃ p ∈ r.post, p.kind = .upload ∧ p.cond.runs .success = true := by
  decide

/-- Every row has an upload that runs on failure. -/
theorem upload_runs_on_failure : ∀ r ∈ rows, ∃ p ∈ r.post, p.kind = .upload ∧ p.cond.runs .failure = true := by
  decide

/-- Every upload is the upload action. -/
theorem upload_label : ∀ r ∈ rows, ∀ p ∈ r.post, p.kind = .upload → p.label = uploadLabel := by
  decide

/-- Whenever an upload runs, the step that copies its files runs. -/
theorem collect_runs_with_upload : ∀ r ∈ rows, ∀ c ∈ r.post, ∀ u ∈ r.post, c.kind = .collect → u.kind = .upload →
    ∀ s ∈ Status.all, u.cond.runs s = true → c.cond.runs s = true := by
  decide

/-- Only telemetry follows the upload. -/
theorem only_telemetry_after_upload : ∀ r ∈ rows,
    ∀ p ∈ (r.post.dropWhile (·.kind != .upload)).drop 1, p.kind = .telemetry := by
  decide

/-- Host state is collected on failure only: it costs nothing on success. -/
theorem host_state_failure_only : ∀ r ∈ rows, ∀ p ∈ r.post, p.kind = .hostState →
    p.cond = .failure ∧ p.cond.runs .success = false := by
  decide

/-- The trimmed workflow keeps no Simulator teardown. -/
theorem webkit_sim_no_teardown : ∀ r ∈ rows, r.file = "webkit-sim.yml" → r.hasTeardown = false := by
  decide

/-- A job is flagged exactly when it still has a teardown step. -/
theorem flagged_iff : ∀ r ∈ rows, (r.file ++ "/" ++ r.job ∈ flagged ↔ r.hasTeardown = true) := by
  decide

/-! ## The lint decision -/

/-- No problems means the observed steps are the allowed steps: label, guard text and no timeout. -/
theorem go_nil : ∀ (n : Nat) (ps : List Post) (os : List Obs), ps.length + os.length ≤ n →
    go ps os = [] → os = ps.map Post.expected := by
  intro n
  induction n with
  | zero =>
    intro ps os h _
    have hp : ps = [] := List.length_eq_zero_iff.1 (by omega)
    have ho : os = [] := List.length_eq_zero_iff.1 (by omega)
    subst hp; subst ho; rfl
  | succ n ih =>
    intro ps os hn h
    match ps, os, hn, h with
    | [], [], _, _ => rfl
    | p :: ps, [], _, h => simp [go] at h
    | [], o :: os, _, h => simp [go] at h
    | p :: ps, o :: os, hn, h =>
      rw [go] at h
      by_cases hl : o.label = p.label
      · by_cases hc : o.ifText = some p.cond.text
        · by_cases ht : o.timeout = none
          · simp only [hl, hc, ht, ↓reduceIte, List.nil_append] at h
            have := ih ps os (by simp at hn; omega) h
            obtain ⟨l, i, t⟩ := o
            simp_all [Post.expected]
          · simp [hl, ht] at h
        · simp [hl, hc] at h
      · by_cases hm : os.any (·.label = p.label) = true
        · simp [hl, hm] at h
        · simp [hl, hm] at h

/-- A step with the allowed label and another guard is reported. -/
theorem go_cond (p : Post) (ps : List Post) (o : Obs) (os : List Obs) (hl : o.label = p.label)
    (hc : o.ifText ≠ some p.cond.text) : ("cond:" ++ o.label) ∈ go (p :: ps) (o :: os) := by
  rw [go]; simp [hl, hc] at *

/-- A step with the allowed label and a timeout is reported. -/
theorem go_timeout (p : Post) (ps : List Post) (o : Obs) (os : List Obs) (hl : o.label = p.label)
    (ht : o.timeout ≠ none) : ("timeout:" ++ o.label) ∈ go (p :: ps) (o :: os) := by
  rw [go]; simp [hl, ht] at *

/-- An allowed step that never comes is reported. -/
theorem go_missing (p : Post) (ps : List Post) : ("missing:" ++ p.label) ∈ go (p :: ps) [] := by
  simp [go]

/-- A step after the last allowed one is reported. -/
theorem go_unlisted (o : Obs) (os : List Obs) : ("unlisted:" ++ o.label) ∈ go [] (o :: os) := by
  simp [go]

/-- A step that is not the allowed one, with the allowed one later, is reported. -/
theorem go_extra (p : Post) (ps : List Post) (o : Obs) (os : List Obs) (hl : o.label ≠ p.label)
    (hm : os.any (·.label = p.label) = true) : ("unlisted:" ++ o.label) ∈ go (p :: ps) (o :: os) := by
  rw [go]; simp [hl, hm]

/-- An allowed step that is not among the rest of the steps is reported. -/
theorem go_absent (p : Post) (ps : List Post) (o : Obs) (os : List Obs) (hl : o.label ≠ p.label)
    (hm : os.any (·.label = p.label) = false) : ("missing:" ++ p.label) ∈ go (p :: ps) (o :: os) := by
  rw [go]; simp [hl, hm]

/-- A measurement step that does not occur exactly once is reported. -/
theorem checkJob_measure (r : Row) (steps : List Obs) (h : tailAfter r.measure steps = none) :
    checkJob r steps = ["measure:" ++ r.measure] := by
  simp [checkJob, h]

/-- The allowed steps themselves have no problems. -/
theorem go_expected : ∀ ps : List Post, go ps (ps.map Post.expected) = [] := by
  intro ps
  induction ps with
  | nil => simp [go]
  | cons p ps ih =>
    simp only [List.map_cons]
    rw [go]
    simp [Post.expected, ih]

/-- A step after the measurement step is a step of the job. -/
theorem tailAfter_subset (m : String) : ∀ (steps t : List Obs), tailAfter m steps = some t → ∀ x ∈ t, x ∈ steps := by
  intro steps
  induction steps with
  | nil => intro t h; simp [tailAfter] at h
  | cons o os ih =>
    intro t h x hx
    simp only [tailAfter] at h
    by_cases hl : o.label = m
    · by_cases ha : os.any (·.label = m) = true
      · simp [hl, ha] at h
      · simp only [hl, ha, ↓reduceIte] at h
        cases h
        exact List.mem_cons_of_mem _ hx
    · simp only [hl, ↓reduceIte] at h
      exact List.mem_cons_of_mem _ (ih t h x hx)

/-- **A job with no problems uploads its result on success.** The allowed steps follow the measurement step, and the
allowed upload is guarded to run when the job succeeded. -/
theorem upload_survives (r : Row) (hr : r ∈ rows) (steps : List Obs) (h : checkJob r steps = []) :
    ∃ o ∈ steps, ∃ c : Cond, o.label = uploadLabel ∧ o.ifText = some c.text ∧ o.timeout = none ∧
      c.runs .success = true := by
  unfold checkJob at h
  cases ht : tailAfter r.measure steps with
  | none => rw [ht] at h; simp at h
  | some t =>
    rw [ht] at h
    have h1 := go_nil _ r.post t (Nat.le_refl _) h
    obtain ⟨p, hp, hk, hrun⟩ := upload_runs_on_success r hr
    refine ⟨p.expected, tailAfter_subset _ steps t ht _ (h1 ▸ List.mem_map_of_mem hp), p.cond, ?_, rfl, rfl, hrun⟩
    exact upload_label r hr p hp hk

/-- No problems means the macOS jobs found in the workflow are the jobs the allowlist names for it. -/
theorem coverage_nil (file : String) (found : List String) (h : coverage file found = []) :
    ∀ j, j ∈ found ↔ j ∈ listed file := by
  unfold coverage at h
  have h' := List.append_eq_nil_iff.1 h
  simp only [List.map_eq_nil_iff, List.filter_eq_nil_iff, Bool.not_eq_true', List.contains_eq_any_beq] at h'
  intro j
  constructor
  · intro hj
    have := h'.1 j hj
    simpa using this
  · intro hj
    have := h'.2 j hj
    simpa using this

/-- A job found in the workflow with no row is reported. -/
theorem coverage_uncovered (file j : String) (found : List String) (hf : j ∈ found) (hl : j ∉ listed file) :
    ("uncovered:" ++ j) ∈ coverage file found := by
  unfold coverage
  simp only [List.mem_append, List.mem_map, List.mem_filter]
  exact Or.inl ⟨j, ⟨hf, by simpa using hl⟩, rfl⟩

/-- A row whose job is not found in the workflow is reported. -/
theorem coverage_stale (file j : String) (found : List String) (hl : j ∈ listed file) (hf : j ∉ found) :
    ("stale-row:" ++ j) ∈ coverage file found := by
  unfold coverage
  simp only [List.mem_append, List.mem_map, List.mem_filter]
  exact Or.inr ⟨j, ⟨hl, by simpa using hf⟩, rfl⟩

end Fw.Ci.Steps
