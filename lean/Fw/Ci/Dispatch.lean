import Lean.Data.Json
/-!
# Which run did my dispatch start? (task `fw-run-dispatch-pick`)

`fw run --trajectory` dispatches `trajectory-probe.yml` and must read the id of the run that dispatch created. It took
"the newest run on the ref" and twice got another run: a skipped push run (39505172794), or the same run for two parallel
dispatches (39508414669 and 39508421419).

Identity instead of recency: the dispatch carries a nonce (`-f nonce=<n>`), the workflow's `run-name` echoes it
(`trajectory-probe dispatch nonce=<n>`), and the run list (`gh run list --event workflow_dispatch --json
databaseId,displayTitle,event`) is searched for exactly that title. The pick is `found` only for exactly one such run;
no run yet is `absent` (the caller polls again, at the poll interval of the CI rules), two is `ambiguous`, never a guess.

Golden: `packages/contracts/golden/ci/dispatch.jsonl`, written by `lake test -- --write-ci-trigger-golden`; the TS twin
(`apps/runner/src/run-pick.ts`) is replayed against it.
-/
namespace Fw.Ci.Dispatch
open Lean

/-- The workflows whose `run-name` echoes the nonce of a dispatch (`<workflow> dispatch nonce=<n>`) and whose
`workflow_dispatch` declares the input `nonce`: the four `fw run` dispatches. A wait with a nonce for any other workflow
can never match a run. -/
def dispatchWorkflows : List String := ["trajectory-probe", "breakpoint-gate", "chromium-counts", "webkit-sim"]

/-- The run title of a dispatch of workflow `wf` with this nonce (`run-name` of the workflow). -/
def titleFor (wf n : String) : String := wf ++ " dispatch nonce=" ++ n

/-- The `run-name:` expression a dispatch workflow's yml must carry so that its run gets the title `titleFor wf n`: on a
`workflow_dispatch` the title with the input `nonce` in place of the `{0}`, else the default title. The check
`scripts/ci-paths.mjs` (`runNameProblems`) compares the yml line with this text (golden `workflows` line, `runNames`). -/
def runNameFor (wf : String) : String :=
  "${{ github.event_name == 'workflow_dispatch' && format('" ++ titleFor wf "{0}" ++ "', inputs.nonce || 'none') || '' }}"

/-- The run title of a trajectory-probe dispatch. -/
def title (n : String) : String := titleFor "trajectory-probe" n

/-- A nonce is 8 to 32 characters of `a-z0-9`, so it cannot be mistaken for another title and needs no escaping. -/
def validNonce (n : String) : Bool :=
  decide (8 ≤ n.length ∧ n.length ≤ 32) && n.toList.all fun c => c.isLower || c.isDigit

/-- One row of the run list. -/
structure Row where
  id : Nat
  event : String
  title : String
deriving Repr, DecidableEq

/-- The pick. -/
inductive Pick where
  | found (id : Nat)
  | absent
  | ambiguous (ids : List Nat)
  | badNonce
deriving Repr, DecidableEq

/-- The row belongs to the dispatch with this nonce: a `workflow_dispatch` run with exactly its title. -/
def isMine (n : String) (r : Row) : Bool := r.event == "workflow_dispatch" && r.title == title n

/-- The run of a dispatch: the only row that is the dispatch's. -/
def pick (n : String) (rows : List Row) : Pick :=
  if !validNonce n then .badNonce
  else
    match (rows.filter (isMine n)).map (·.id) with
    | [] => .absent
    | [i] => .found i
    | is => .ambiguous is

/-- A title determines its nonce. -/
theorem titleFor_inj (wf a b : String) (h : titleFor wf a = titleFor wf b) : a = b := by
  unfold titleFor at h
  have := congrArg String.toList h
  simp only [String.toList_append, List.append_assoc] at this
  exact String.toList_inj.mp (List.append_cancel_left (List.append_cancel_left this))

/-- A trajectory-probe title determines its nonce. -/
theorem title_inj (a b : String) (h : title a = title b) : a = b := titleFor_inj "trajectory-probe" a b h

/-- Branch bad nonce: nothing is picked. -/
theorem pick_bad (n : String) (rows : List Row) (h : validNonce n = false) : pick n rows = .badNonce := by
  simp [pick, h]

/-- Branch none of the rows is the dispatch's: absent. -/
theorem pick_absent (n : String) (rows : List Row) (hn : validNonce n = true) (h : ∀ r ∈ rows, isMine n r = false) :
    pick n rows = .absent := by
  have : rows.filter (isMine n) = [] := List.filter_eq_nil_iff.mpr fun r hr => by simp [h r hr]
  simp [pick, hn, this]

/-- Branch exactly one row is the dispatch's: found, with that row's id. -/
theorem pick_found (n : String) (rows : List Row) (r : Row) (hn : validNonce n = true)
    (h : rows.filter (isMine n) = [r]) : pick n rows = .found r.id := by
  simp [pick, hn, h]

/-- Branch two or more rows are the dispatch's: ambiguous, listing them all. -/
theorem pick_ambiguous (n : String) (rows : List Row) (a b : Row) (rest : List Row) (hn : validNonce n = true)
    (h : rows.filter (isMine n) = a :: b :: rest) :
    pick n rows = .ambiguous (a.id :: b.id :: rest.map (·.id)) := by
  simp [pick, hn, h]

/-- **Soundness.** A found id belongs to a row of the list that is a `workflow_dispatch` run with the dispatch's title. -/
theorem found_sound (n : String) (rows : List Row) (i : Nat) (h : pick n rows = .found i) :
    ∃ r ∈ rows, r.id = i ∧ r.event = "workflow_dispatch" ∧ r.title = title n := by
  unfold pick at h
  split at h
  · simp at h
  rename_i hn
  split at h
  · simp at h
  · rename_i j hj
    simp only [Pick.found.injEq] at h
    subst h
    have : (rows.filter (isMine n)).map (·.id) = [j] := hj
    obtain ⟨r, hr, hid⟩ := List.mem_map.mp (by rw [this]; simp : j ∈ (rows.filter (isMine n)).map (·.id))
    have hm := List.mem_filter.mp hr
    refine ⟨r, hm.1, hid, ?_⟩
    simpa [isMine] using hm.2
  · simp at h

/-- **Another nonce never matches.** A row with the title of a different valid dispatch is not mine. -/
theorem other_nonce_not_mine (a b : String) (r : Row) (hne : a ≠ b) (h : r.title = title b) : isMine a r = false := by
  simp only [isMine, Bool.and_eq_false_iff, beq_eq_false_iff_ne, ne_eq]
  right
  intro ht
  exact hne (title_inj a b (ht.symm.trans h))

/-- **A push run never matches.** A row of any other event is not mine, whatever its title. -/
theorem push_not_mine (n : String) (r : Row) (h : r.event ≠ "workflow_dispatch") : isMine n r = false := by
  simp [isMine, h]

/-- **A found id is the only match.** Every row that is the dispatch's has the found id. -/
theorem found_unique (n : String) (rows : List Row) (i : Nat) (h : pick n rows = .found i) :
    ∀ r ∈ rows, isMine n r = true → r.id = i := by
  intro r hr hm
  unfold pick at h
  split at h
  · simp at h
  split at h
  · simp at h
  · rename_i j hj
    simp only [Pick.found.injEq] at h
    subst h
    have hmem : r ∈ rows.filter (isMine n) := List.mem_filter.mpr ⟨hr, hm⟩
    have h2 : (rows.filter (isMine n)).map (·.id) = [j] := hj
    have : r.id ∈ (rows.filter (isMine n)).map (·.id) := List.mem_map_of_mem hmem
    rw [h2] at this
    simpa using this
  · simp at h

/-! ## Which run does a wait mean? (task `ci-push-probe-inputs`, round 2)

`fw ci wait --branch B --workflow W` took the newest run of W on the commit and swapped a push run and a dispatch run of
the same commit. The wait names what it waits for: a push of a commit (`--sha`), or a dispatch (`--nonce`). The row is
selected by that identity, never by recency. A push run has event `push` and a head sha the wanted sha is a prefix of;
a dispatch run is `isMine` (event `workflow_dispatch`, the nonce's title), whatever its head sha. -/

/-- What a wait is for. -/
inductive Want where
  | push (sha : String)
  | dispatch (workflow nonce : String)
deriving Repr, DecidableEq

/-- A run list row with its head sha. -/
structure Run where
  id : Nat
  event : String
  title : String
  sha : String
deriving Repr, DecidableEq

/-- A sha to prefix-match is 7 to 40 characters of `0-9a-f`. -/
def validSha (s : String) : Bool :=
  decide (7 ≤ s.length ∧ s.length ≤ 40) && s.toList.all fun c => c.isDigit || ('a' ≤ c && c ≤ 'f')

/-- The run is the one the wait means. -/
def wanted : Want → Run → Bool
  | .push s, r => validSha s && r.event == "push" && s.isPrefixOf r.sha
  | .dispatch w n, r => dispatchWorkflows.contains w && validNonce n && r.event == "workflow_dispatch" && r.title == titleFor w n

/-- The ids of the runs the wait means, in list order. -/
def select (w : Want) (rows : List Run) : List Nat := (rows.filter (wanted w)).map (·.id)

/-- The one run a wait means, or why there is none. -/
inductive One where
  | found (id : Nat)
  | absent
  | ambiguous (ids : List Nat)
deriving Repr, DecidableEq

/-- Choose one run from the selected ones. No run is `absent`. A push wait takes the greatest id (a commit may have several push
runs: a rerun keeps its id, a new push run is newer). A dispatch wait takes its only run; several runs of one nonce are `ambiguous`
(an error, never the newest, as `pick` says for the same case). -/
def selectOne (w : Want) (rows : List Run) : One :=
  match w, select w rows with
  | _, [] => .absent
  | .push _, a :: t => .found (t.foldl max a)
  | .dispatch _ _, [i] => .found i
  | .dispatch _ _, is => .ambiguous is

/-- Branch no wanted run: absent, for either want. -/
theorem selectOne_absent (w : Want) (rows : List Run) (h : select w rows = []) : selectOne w rows = .absent := by
  cases w <;> simp [selectOne, h]

/-- Branch push with a run: the greatest selected id is found; a push wait is never ambiguous. -/
theorem selectOne_push (s : String) (rows : List Run) (a : Nat) (t : List Nat) (h : select (.push s) rows = a :: t) :
    selectOne (.push s) rows = .found (t.foldl max a) := by
  simp [selectOne, h]

/-- Branch dispatch with one run: found. -/
theorem selectOne_dispatch_found (w n : String) (rows : List Run) (i : Nat) (h : select (.dispatch w n) rows = [i]) :
    selectOne (.dispatch w n) rows = .found i := by
  simp [selectOne, h]

/-- Branch dispatch with two or more runs: ambiguous, listing all of them. -/
theorem selectOne_dispatch_ambiguous (w n : String) (rows : List Run) (a b : Nat) (rest : List Nat)
    (h : select (.dispatch w n) rows = a :: b :: rest) : selectOne (.dispatch w n) rows = .ambiguous (a :: b :: rest) := by
  simp [selectOne, h]

/-- The fold of `max` from `m` is `m` or an element. -/
theorem foldl_max_mem (l : List Nat) (m : Nat) : l.foldl max m ∈ m :: l := by
  induction l generalizing m with
  | nil => simp
  | cons x xs ih =>
    have h := ih (max m x)
    simp only [List.foldl, List.mem_cons] at h ⊢
    rcases h with h | h
    · rcases Nat.le_total m x with hle | hle
      · rw [Nat.max_eq_right hle] at h ⊢
        exact Or.inr (Or.inl h)
      · rw [Nat.max_eq_left hle] at h ⊢
        exact Or.inl h
    · exact Or.inr (Or.inr h)

/-- Branch push: a found id is one of the selected ids (the greatest). -/
theorem selectOne_push_mem (s : String) (rows : List Run) (i : Nat) (h : selectOne (.push s) rows = .found i) :
    i ∈ select (.push s) rows := by
  cases hs : select (.push s) rows with
  | nil => simp [selectOne, hs] at h
  | cons a t =>
    simp only [selectOne, hs, One.found.injEq] at h
    subst h
    exact foldl_max_mem t a

/-- Branch push: a dispatch run is never selected, whatever its sha and title. -/
theorem push_never_dispatch (s : String) (r : Run) (h : r.event ≠ "push") : wanted (.push s) r = false := by
  simp [wanted, h]

/-- Branch push: a push run of another commit (the wanted sha is not a prefix of its head sha) is not selected. -/
theorem push_other_sha (s : String) (r : Run) (h : s.isPrefixOf r.sha = false) : wanted (.push s) r = false := by
  simp [wanted, h]

/-- Branch push: a push run of the commit is selected. -/
theorem push_selects (s : String) (r : Run) (hs : validSha s = true) (he : r.event = "push") (hp : s.isPrefixOf r.sha = true) :
    wanted (.push s) r = true := by
  simp [wanted, hs, he, hp]

/-- Branch dispatch: a push run is never selected, whatever its title. -/
theorem dispatch_never_push (w n : String) (r : Run) (h : r.event ≠ "workflow_dispatch") : wanted (.dispatch w n) r = false := by
  simp [wanted, h]

/-- Branch dispatch: a run of another nonce is not selected. -/
theorem dispatch_other_nonce (w a b : String) (r : Run) (hne : a ≠ b) (h : r.title = titleFor w b) : wanted (.dispatch w a) r = false := by
  simp only [wanted, Bool.and_eq_false_iff, beq_eq_false_iff_ne, ne_eq]
  right
  intro ht
  exact hne (titleFor_inj w a b (ht.symm.trans h))

/-- Branch dispatch: an invalid nonce selects nothing. -/
theorem dispatch_bad_nonce (w n : String) (rows : List Run) (h : validNonce n = false) : select (.dispatch w n) rows = [] := by
  simp [select, wanted, h]

/-- Branch dispatch: a workflow outside `dispatchWorkflows` selects nothing (no run-name carries a nonce there). -/
theorem dispatch_unknown_workflow (w n : String) (rows : List Run) (h : dispatchWorkflows.contains w = false) : select (.dispatch w n) rows = [] := by
  have h' : w ∉ dispatchWorkflows := by simpa using h
  simp [select, wanted, h']

/-- Branch dispatch: a run with the dispatch's title is selected, on any head sha. -/
theorem dispatch_selects (w n : String) (r : Run) (hw : dispatchWorkflows.contains w = true) (hn : validNonce n = true)
    (he : r.event = "workflow_dispatch") (ht : r.title = titleFor w n) : wanted (.dispatch w n) r = true := by
  have hw' : w ∈ dispatchWorkflows := by simpa using hw
  simp [wanted, hw', hn, he, ht]

/-- Branch dispatch: the head sha plays no part (the TS caller must not filter by it either). -/
theorem dispatch_any_sha (w n s : String) (r : Run) : wanted (.dispatch w n) { r with sha := s } = wanted (.dispatch w n) r := by
  simp [wanted]

/-- A push wait whose commit has only `workflow_dispatch` runs: nothing is selected, and a hint says so. -/
def dispatchOnly : Want → List Run → Bool
  | .push s, rows => validSha s && (select (.push s) rows).isEmpty && rows.any fun r => r.event == "workflow_dispatch" && s.isPrefixOf r.sha
  | .dispatch _ _, _ => false

/-- Hint branch: a dispatch wait never gets the hint. -/
theorem dispatchOnly_dispatch (w n : String) (rows : List Run) : dispatchOnly (.dispatch w n) rows = false := rfl

/-- Hint branch: a selected push run silences the hint. -/
theorem dispatchOnly_selected (s : String) (rows : List Run) (h : select (.push s) rows ≠ []) : dispatchOnly (.push s) rows = false := by
  cases hs : select (.push s) rows with
  | nil => exact absurd hs h
  | cons a t => simp [dispatchOnly, hs]

/-- Hint branch: no push run is selected and a dispatch run of the commit exists: the hint. -/
theorem dispatchOnly_fires (s : String) (rows : List Run) (r : Run) (hs : validSha s = true) (hsel : select (.push s) rows = [])
    (hr : r ∈ rows) (he : r.event = "workflow_dispatch") (hp : s.isPrefixOf r.sha = true) : dispatchOnly (.push s) rows = true := by
  simp only [dispatchOnly, hs, hsel, List.isEmpty_nil, Bool.and_true, Bool.true_and, List.any_eq_true]
  exact ⟨r, hr, by simp [he, hp]⟩

/-- **Soundness.** A selected id belongs to a row of the list that `wanted` accepts. -/
theorem select_sound (w : Want) (rows : List Run) (i : Nat) (h : i ∈ select w rows) :
    ∃ r ∈ rows, r.id = i ∧ wanted w r = true := by
  obtain ⟨r, hr, hid⟩ := List.mem_map.mp h
  exact ⟨r, (List.mem_filter.mp hr).1, hid, (List.mem_filter.mp hr).2⟩

/-! ## One row per run (task `ci-run-dedup`)
`gh run list` reads page by page, so one run can appear twice in one list; the poller keeps one row per id. -/

/-- A run list row with GitHub's time of the run's last change (`updatedAt`, epoch milliseconds). -/
structure Listed where
  run : Run
  updatedAt : Nat
deriving Repr, DecidableEq

/-- The ids of the rows, in list order. -/
def ids (rows : List Listed) : List Nat := rows.map (·.run.id)

/-- The runs of the rows, in list order. -/
def runs (rows : List Listed) : List Run := rows.map (·.run)

/-- Add a row: a new id goes last; a known id keeps its place and takes the row with the newer `updatedAt` (a tie keeps the
row already there). -/
def keepNewest (acc : List Listed) (r : Listed) : List Listed :=
  if acc.any (·.run.id == r.run.id) then
    acc.map fun s => if s.run.id == r.run.id && s.updatedAt < r.updatedAt then r else s
  else acc ++ [r]

/-- One row per id, the newest `updatedAt` of that id, at the place of the id's first row. -/
def dedupById (rows : List Listed) : List Listed := rows.foldl keepNewest []

/-- The ids listed more than once, each once, in the order of `dedupById`. -/
def dupIds (rows : List Listed) : List Nat := (ids (dedupById rows)).filter fun i => 2 ≤ (ids rows).count i

/-- Copies of one id are one run: the same event, title and head sha (only status and `updatedAt` change). -/
def OneRunPerId (rows : List Listed) : Prop := ∀ r ∈ rows, ∀ s ∈ rows, r.run.id = s.run.id → r.run = s.run

#guard ids (dedupById [⟨⟨1, "push", "a", "s"⟩, 5⟩, ⟨⟨2, "push", "b", "s"⟩, 5⟩, ⟨⟨1, "push", "a", "s"⟩, 7⟩]) = [1, 2]
#guard (dedupById [⟨⟨1, "push", "a", "s"⟩, 5⟩, ⟨⟨1, "push", "a", "s"⟩, 7⟩]).map (·.updatedAt) = [7]
#guard (dedupById [⟨⟨1, "push", "a", "s"⟩, 7⟩, ⟨⟨1, "push", "a", "s"⟩, 5⟩]).map (·.updatedAt) = [7]
#guard dupIds [⟨⟨1, "push", "a", "s"⟩, 5⟩, ⟨⟨2, "push", "b", "s"⟩, 5⟩, ⟨⟨1, "push", "a", "s"⟩, 7⟩] = [1]
#guard dupIds [⟨⟨1, "push", "a", "s"⟩, 5⟩, ⟨⟨2, "push", "b", "s"⟩, 5⟩] = []

/-- Adding a row keeps the id list, or appends the row's id when it is new. -/
theorem ids_keepNewest (acc : List Listed) (r : Listed) :
    ids (keepNewest acc r) = if r.run.id ∈ ids acc then ids acc else ids acc ++ [r.run.id] := by
  have hany : acc.any (·.run.id == r.run.id) = true ↔ r.run.id ∈ ids acc := by
    simp only [List.any_eq_true, beq_iff_eq, ids, List.mem_map]
  unfold keepNewest
  by_cases h : r.run.id ∈ ids acc
  · simp only [hany.mpr h, h, ↓reduceIte]
    simp only [ids, List.map_map]
    apply List.map_congr_left
    intro s _
    simp only [Function.comp]
    split
    · rename_i hc
      simp only [Bool.and_eq_true, beq_iff_eq] at hc
      exact hc.1.symm
    · rfl
  · have hf : acc.any (·.run.id == r.run.id) = false := Bool.eq_false_iff.mpr fun hh => h (hany.mp hh)
    simp only [hf, h, Bool.false_eq_true, ↓reduceIte]
    simp [ids]

/-- Adding a row keeps the ids free of duplicates. -/
theorem nodup_keepNewest (acc : List Listed) (r : Listed) (h : (ids acc).Nodup) : (ids (keepNewest acc r)).Nodup := by
  rw [ids_keepNewest]
  split
  · exact h
  · rename_i hn
    refine List.nodup_append.mpr ⟨h, by simp, ?_⟩
    intro a ha b hb hab
    simp at hb
    exact hn (hb ▸ hab ▸ ha)

/-- Adding rows keeps the ids free of duplicates. -/
theorem nodup_foldl (acc rows : List Listed) (h : (ids acc).Nodup) : (ids (rows.foldl keepNewest acc)).Nodup := by
  induction rows generalizing acc with
  | nil => exact h
  | cons r rs ih => exact ih _ (nodup_keepNewest acc r h)

/-- **No duplicate ids.** `dedupById` lists each id once. -/
theorem dedupById_nodup (rows : List Listed) : (ids (dedupById rows)).Nodup :=
  nodup_foldl [] rows List.nodup_nil

/-- A row after adding is the added row or a row from before. -/
theorem mem_keepNewest (acc : List Listed) (r s : Listed) (h : s ∈ keepNewest acc r) : s ∈ acc ∨ s = r := by
  unfold keepNewest at h
  split at h
  · obtain ⟨x, hx, hxs⟩ := List.mem_map.mp h
    split at hxs
    · exact Or.inr hxs.symm
    · exact Or.inl (hxs ▸ hx)
  · rcases List.mem_append.mp h with h | h
    · exact Or.inl h
    · exact Or.inr (by simpa using h)

/-- A row after adding rows is one of them or a row from before. -/
theorem mem_foldl (acc rows : List Listed) (s : Listed) (h : s ∈ rows.foldl keepNewest acc) : s ∈ acc ∨ s ∈ rows := by
  induction rows generalizing acc with
  | nil => exact Or.inl h
  | cons r rs ih =>
    rcases ih _ h with h | h
    · rcases mem_keepNewest acc r s h with h | h
      · exact Or.inl h
      · exact Or.inr (h ▸ List.mem_cons_self)
    · exact Or.inr (List.mem_cons_of_mem r h)

/-- **Soundness.** Every kept row is a row of the list. -/
theorem mem_dedupById (rows : List Listed) (s : Listed) (h : s ∈ dedupById rows) : s ∈ rows := by
  rcases mem_foldl [] rows s h with h | h
  · simp at h
  · exact h

/-- A row of the same id and at least the same `updatedAt` is in the list. -/
def Covered (x : Listed) (l : List Listed) : Prop := ∃ y ∈ l, y.run.id = x.run.id ∧ x.updatedAt ≤ y.updatedAt

/-- Adding a row covers the added row and every row from before. -/
theorem covered_keepNewest (acc : List Listed) (r x : Listed) (h : x ∈ acc ∨ x = r) : Covered x (keepNewest acc r) := by
  unfold keepNewest Covered
  split
  · rename_i hany
    rcases h with hx | hx
    · let f := fun s : Listed => if s.run.id == r.run.id && s.updatedAt < r.updatedAt then r else s
      refine ⟨f x, List.mem_map_of_mem hx, ?_⟩
      simp only [f]
      split
      · rename_i hc
        simp only [Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at hc
        exact ⟨hc.1.symm, Nat.le_of_lt hc.2⟩
      · exact ⟨rfl, Nat.le_refl _⟩
    · subst hx
      obtain ⟨s, hs, hsid⟩ := List.any_eq_true.mp hany
      simp only [beq_iff_eq] at hsid
      let f := fun t : Listed => if t.run.id == x.run.id && t.updatedAt < x.updatedAt then x else t
      refine ⟨f s, List.mem_map_of_mem hs, ?_⟩
      simp only [f]
      split
      · exact ⟨rfl, Nat.le_refl _⟩
      · rename_i hc
        simp only [hsid, beq_self_eq_true, Bool.true_and, decide_eq_true_eq] at hc
        exact ⟨hsid, Nat.le_of_not_lt hc⟩
  · rcases h with hx | hx
    · exact ⟨x, List.mem_append_left _ hx, rfl, Nat.le_refl _⟩
    · exact ⟨r, List.mem_append_right _ (List.mem_singleton_self r), hx ▸ rfl, hx ▸ Nat.le_refl _⟩

/-- Covering is transitive. -/
theorem covered_trans (x : Listed) (acc l : List Listed) (h : Covered x acc) (step : ∀ y ∈ acc, Covered y l) : Covered x l := by
  obtain ⟨y, hy, hid, hle⟩ := h
  obtain ⟨z, hz, hid', hle'⟩ := step y hy
  exact ⟨z, hz, hid'.trans hid, Nat.le_trans hle hle'⟩

/-- Adding rows covers each of them and every row from before. -/
theorem covered_foldl (acc rows : List Listed) (x : Listed) (h : x ∈ acc ∨ x ∈ rows) : Covered x (rows.foldl keepNewest acc) := by
  induction rows generalizing acc x with
  | nil =>
    rcases h with h | h
    · exact ⟨x, h, rfl, Nat.le_refl _⟩
    · simp at h
  | cons r rs ih =>
    have step : ∀ y ∈ keepNewest acc r, Covered y (rs.foldl keepNewest (keepNewest acc r)) := fun y hy => ih _ y (Or.inl hy)
    rcases h with h | h
    · exact covered_trans x _ _ (covered_keepNewest acc r x (Or.inl h)) step
    · rcases List.mem_cons.mp h with h | h
      · exact covered_trans x _ _ (covered_keepNewest acc r x (Or.inr h)) step
      · exact ih _ x (Or.inr h)

/-- **Newest wins.** Each row's id is kept, by a row whose `updatedAt` is at least the row's. -/
theorem dedupById_newest (rows : List Listed) (r : Listed) (h : r ∈ rows) :
    ∃ s ∈ dedupById rows, s.run.id = r.run.id ∧ r.updatedAt ≤ s.updatedAt :=
  covered_foldl [] rows r (Or.inr h)

/-- Adding rows of new ids appends them. -/
theorem foldl_fresh (acc rows : List Listed) (h : (ids (acc ++ rows)).Nodup) : rows.foldl keepNewest acc = acc ++ rows := by
  induction rows generalizing acc with
  | nil => simp
  | cons r rs ih =>
    have hn : r.run.id ∉ ids acc := by
      intro hm
      have := (List.nodup_append.mp (by simpa [ids] using h)).2.2 _ hm r.run.id (by simp)
      exact this rfl
    have hk : keepNewest acc r = acc ++ [r] := by
      have : acc.any (·.run.id == r.run.id) = false := by
        simp only [List.any_eq_false, beq_iff_eq]
        intro s hs he
        exact hn (he ▸ List.mem_map_of_mem hs)
      simp [keepNewest, this]
    simp only [List.foldl_cons, hk]
    rw [ih _ (by simpa using h)]
    simp

/-- **No copies, no change.** A list whose ids are free of duplicates is kept as it is. -/
theorem dedupById_of_nodup (rows : List Listed) (h : (ids rows).Nodup) : dedupById rows = rows := by
  unfold dedupById
  simpa using foldl_fresh [] rows (by simpa using h)

/-- An id is listed in `dupIds` exactly when it is listed at least twice. -/
theorem mem_dupIds (rows : List Listed) (i : Nat) : i ∈ dupIds rows ↔ 2 ≤ (ids rows).count i := by
  unfold dupIds
  simp only [List.mem_filter, decide_eq_true_eq]
  refine ⟨fun h => h.2, fun h => ⟨?_, h⟩⟩
  have hm : i ∈ ids rows := List.count_pos_iff.mp (by omega)
  obtain ⟨r, hr, rfl⟩ := List.mem_map.mp hm
  obtain ⟨s, hs, hid, _⟩ := dedupById_newest rows r hr
  exact hid ▸ List.mem_map_of_mem hs

/-- The selected ids of kept rows are free of duplicates. -/
theorem select_dedupById_nodup (w : Want) (rows : List Listed) : (select w (runs (dedupById rows))).Nodup := by
  apply List.Nodup.sublist _ (dedupById_nodup rows)
  unfold select runs ids
  have := (List.filter_sublist (p := wanted w) (l := (dedupById rows).map (·.run))).map (·.id)
  simpa [List.map_map, Function.comp_def] using this

/-- An id is selected from the kept rows exactly when a wanted row of the list has it. -/
theorem mem_select_dedupById (w : Want) (rows : List Listed) (h1 : OneRunPerId rows) (i : Nat) :
    i ∈ select w (runs (dedupById rows)) ↔ ∃ r ∈ rows, wanted w r.run = true ∧ r.run.id = i := by
  unfold select runs
  simp only [List.mem_map, List.mem_filter]
  constructor
  · rintro ⟨_, ⟨⟨s, hs, rfl⟩, hw⟩, rfl⟩
    exact ⟨s, mem_dedupById rows s hs, hw, rfl⟩
  · rintro ⟨r, hr, hw, rfl⟩
    obtain ⟨s, hs, hid, _⟩ := dedupById_newest rows r hr
    have heq : s.run = r.run := h1 s (mem_dedupById rows s hs) r hr hid
    exact ⟨s.run, ⟨⟨s, hs, rfl⟩, heq ▸ hw⟩, heq ▸ rfl⟩

/-- A list free of duplicates, not empty, all of whose elements are `i`, is `[i]`. -/
theorem eq_singleton (l : List Nat) (i : Nat) (hn : l.Nodup) (hall : ∀ j ∈ l, j = i) (hne : l ≠ []) : l = [i] := by
  match l, hn with
  | [], _ => exact absurd rfl hne
  | [a], _ => rw [hall a (by simp)]
  | a :: b :: _, hn =>
    have ha := hall a (by simp)
    have hb := hall b (by simp)
    have := (List.nodup_cons.mp hn).1
    exact absurd (by simp [ha, hb]) this

/-- **Found on kept rows.** When every wanted row has id `i` and one exists, `selectOne` on the kept rows is `found i`, for
either want (so `[a, a]` is `found a.id`). -/
theorem selectOne_dedupById_found (w : Want) (rows : List Listed) (i : Nat) (h1 : OneRunPerId rows)
    (hall : ∀ r ∈ rows, wanted w r.run = true → r.run.id = i) (hex : ∃ r ∈ rows, wanted w r.run = true) :
    selectOne w (runs (dedupById rows)) = .found i := by
  have hs : select w (runs (dedupById rows)) = [i] := by
    apply eq_singleton _ i (select_dedupById_nodup w rows)
    · intro j hj
      obtain ⟨r, hr, hw, rfl⟩ := (mem_select_dedupById w rows h1 j).mp hj
      exact hall r hr hw
    · obtain ⟨r, hr, hw⟩ := hex
      have : r.run.id ∈ select w (runs (dedupById rows)) := (mem_select_dedupById w rows h1 _).mpr ⟨r, hr, hw, rfl⟩
      exact List.ne_nil_of_mem this
  cases w with
  | push s => simpa using selectOne_push s _ i [] hs
  | dispatch wf n => exact selectOne_dispatch_found wf n _ i hs

/-- **One run listed twice.** A wanted row and its copy are `found` with the row's id (incident nonce 912416a6895d9222). -/
theorem selectOne_dedupById_twice (w : Want) (a : Listed) (h : wanted w a.run = true) :
    selectOne w (runs (dedupById [a, a])) = .found a.run.id := by
  apply selectOne_dedupById_found w [a, a] a.run.id
  · intro r hr s hs _
    simp only [List.mem_cons, List.not_mem_nil, or_false, or_self] at hr hs
    rw [hr, hs]
  · intro r hr _
    simp only [List.mem_cons, List.not_mem_nil, or_false, or_self] at hr
    rw [hr]
  · exact ⟨a, by simp, h⟩

/-- An ambiguous dispatch result is the selected ids, two or more. -/
theorem selectOne_dispatch_ambiguous_select (w n : String) (rows : List Run) (l : List Nat)
    (h : selectOne (.dispatch w n) rows = .ambiguous l) : select (.dispatch w n) rows = l ∧ 2 ≤ l.length := by
  cases hs : select (.dispatch w n) rows with
  | nil => simp [selectOne, hs] at h
  | cons a t =>
    cases t with
    | nil => simp [selectOne, hs] at h
    | cons b rest =>
      rw [selectOne_dispatch_ambiguous w n rows a b rest hs] at h
      simp only [One.ambiguous.injEq] at h
      subst h
      simp

/-- **Ambiguous on id sets.** An ambiguous result on kept rows lists two or more ids, each once, and its id set is exactly
the ids of the wanted rows of the list: it depends on which rows are listed, not on their order or copies. -/
theorem selectOne_dedupById_ambiguous (w n : String) (rows : List Listed) (l : List Nat) (h1 : OneRunPerId rows)
    (h : selectOne (.dispatch w n) (runs (dedupById rows)) = .ambiguous l) :
    l.Nodup ∧ 2 ≤ l.length ∧ ∀ i, i ∈ l ↔ ∃ r ∈ rows, wanted (.dispatch w n) r.run = true ∧ r.run.id = i := by
  obtain ⟨hs, hlen⟩ := selectOne_dispatch_ambiguous_select w n _ l h
  subst hs
  exact ⟨select_dedupById_nodup _ rows, hlen, mem_select_dedupById _ rows h1⟩

/-- **Order and copies play no part.** Two lists with the same rows (any order, any copies): when one is ambiguous on kept
rows, so is the other, with the same id set. -/
theorem selectOne_dedupById_ambiguous_same (w n : String) (rows rows' : List Listed) (l : List Nat) (h1 : OneRunPerId rows)
    (h1' : OneRunPerId rows') (hsame : ∀ r, r ∈ rows ↔ r ∈ rows')
    (h : selectOne (.dispatch w n) (runs (dedupById rows)) = .ambiguous l) :
    ∃ l', selectOne (.dispatch w n) (runs (dedupById rows')) = .ambiguous l' ∧ ∀ i, i ∈ l ↔ i ∈ l' := by
  obtain ⟨hnd, hlen, hmem⟩ := selectOne_dedupById_ambiguous w n rows l h1 h
  have hiff : ∀ i, i ∈ l ↔ i ∈ select (.dispatch w n) (runs (dedupById rows')) := by
    intro i
    rw [hmem, mem_select_dedupById _ rows' h1']
    exact ⟨fun ⟨r, hr, hw, hi⟩ => ⟨r, (hsame r).mp hr, hw, hi⟩, fun ⟨r, hr, hw, hi⟩ => ⟨r, (hsame r).mpr hr, hw, hi⟩⟩
  refine ⟨select (.dispatch w n) (runs (dedupById rows')), ?_, hiff⟩
  match l, hnd, hlen with
  | a :: b :: _, hnd, _ =>
    have hab : a ≠ b := fun e => (List.nodup_cons.mp hnd).1 (e ▸ List.mem_cons_self)
    have ha := (hiff a).mp (by simp)
    have hb := (hiff b).mp (by simp)
    cases hl : select (.dispatch w n) (runs (dedupById rows')) with
    | nil => rw [hl] at ha; simp at ha
    | cons x t =>
      cases t with
      | nil =>
        rw [hl] at ha hb
        simp at ha hb
        exact absurd (ha.trans hb.symm) hab
      | cons y rest => exact selectOne_dispatch_ambiguous w n _ x y rest hl

/-! ## Golden -/

/-- The rows of a case. -/
def rowJson (r : Row) : Json := Json.mkObj [("id", .num r.id), ("event", .str r.event), ("title", .str r.title)]

/-- The JSON of a pick. -/
def pickJson : Pick → Json
  | .found i => Json.mkObj [("kind", "found"), ("id", .num i)]
  | .absent => Json.mkObj [("kind", "absent")]
  | .ambiguous ids => Json.mkObj [("kind", "ambiguous"), ("ids", .arr (ids.map fun (i : Nat) => (Json.num i : Json)).toArray)]
  | .badNonce => Json.mkObj [("kind", "badNonce")]

/-- A dispatch row. -/
def d (i : Nat) (n : String) : Row := ⟨i, "workflow_dispatch", title n⟩

/-- Cases: (name, nonce, rows). -/
def cases : List (String × String × List Row) := [
  ("one dispatch", "abc12345", [d 11 "abc12345"]),
  ("empty list", "abc12345", []),
  ("two parallel dispatches, each picks its own (first)", "aaaa1111", [d 22 "bbbb2222", d 21 "aaaa1111"]),
  ("two parallel dispatches, each picks its own (second)", "bbbb2222", [d 22 "bbbb2222", d 21 "aaaa1111"]),
  ("a skipped push run is newest", "abc12345", [⟨30, "push", "ci: measure [ci:trajectory-probe]"⟩, d 29 "abc12345"]),
  ("a push run with the same title text", "abc12345", [⟨30, "push", title "abc12345"⟩]),
  ("a dispatch of another nonce only", "abc12345", [d 40 "zzzz9999"]),
  ("a prefix of another nonce", "abc12345", [d 41 "abc123456"]),
  ("a suffix of another nonce", "abc12345", [d 42 "xabc12345"]),
  ("the same nonce twice", "abc12345", [d 50 "abc12345", d 49 "abc12345"]),
  ("the same nonce three times", "abc12345", [d 52 "abc12345", d 51 "abc12345", d 50 "abc12345"]),
  ("a manual dispatch without nonce", "abc12345", [⟨60, "workflow_dispatch", "trajectory-probe dispatch nonce=none"⟩]),
  ("a schedule run", "abc12345", [⟨61, "schedule", title "abc12345"⟩]),
  ("nonce too short", "abc", [d 70 "abc"]),
  ("nonce too long", "abcdefghijabcdefghijabcdefghijabc", [d 71 "abcdefghijabcdefghijabcdefghijabc"]),
  ("nonce with an upper case letter", "ABC12345", [d 72 "ABC12345"]),
  ("nonce with a space", "abc 1234", [d 73 "abc 1234"]),
  ("empty nonce", "", [d 74 ""])]

/-- A run of the select cases. -/
def sr (i : Nat) (e t sha : String) : Run := ⟨i, e, t, sha⟩

/-- Cases of `select`: (name, want, rows); the rows are listed newest first. -/
def selectCases : List (String × Want × List Run) := [
  ("push: the dispatch is newer, the push run is picked", .push "abcdef1234", [sr 9 "workflow_dispatch" (title "abc12345") "abcdef1234567", sr 8 "push" "ci: measure" "abcdef1234567"]),
  ("push: the push run is newer", .push "abcdef1234", [sr 9 "push" "ci: measure" "abcdef1234567", sr 8 "workflow_dispatch" (title "abc12345") "abcdef1234567"]),
  ("push: another commit's push run", .push "abcdef1234", [sr 9 "push" "ci: x" "1234567abcdef"]),
  ("push: a short sha is refused", .push "abcdef", [sr 9 "push" "ci: x" "abcdef1234567"]),
  ("push: an upper case sha is refused", .push "ABCDEF1234", [sr 9 "push" "ci: x" "ABCDEF1234567"]),
  ("push: a schedule run", .push "abcdef1234", [sr 9 "schedule" "x" "abcdef1234567"]),
  ("dispatch: the push is newer, the dispatch is picked", .dispatch "trajectory-probe" "abc12345", [sr 9 "push" "ci: measure" "abcdef1234567", sr 8 "workflow_dispatch" (title "abc12345") "abcdef1234567"]),
  ("dispatch: two dispatches, each its own (first)", .dispatch "trajectory-probe" "aaaa1111", [sr 22 "workflow_dispatch" (title "bbbb2222") "abcdef1234567", sr 21 "workflow_dispatch" (title "aaaa1111") "abcdef1234567"]),
  ("dispatch: two dispatches, each its own (second)", .dispatch "trajectory-probe" "bbbb2222", [sr 22 "workflow_dispatch" (title "bbbb2222") "abcdef1234567", sr 21 "workflow_dispatch" (title "aaaa1111") "abcdef1234567"]),
  ("dispatch: a push run with the dispatch's title text", .dispatch "trajectory-probe" "abc12345", [sr 9 "push" (title "abc12345") "abcdef1234567"]),
  ("dispatch: a bad nonce", .dispatch "trajectory-probe" "abc", [sr 9 "workflow_dispatch" (title "abc") "abcdef1234567"]),
  ("dispatch: no run yet", .dispatch "trajectory-probe" "abc12345", []),
  ("dispatch: on another head sha (the sha plays no part)", .dispatch "trajectory-probe" "abc12345", [sr 9 "workflow_dispatch" (title "abc12345") "1234567abcdef"]),
  ("dispatch: breakpoint-gate has its own title", .dispatch "breakpoint-gate" "abc12345", [sr 9 "workflow_dispatch" (titleFor "breakpoint-gate" "abc12345") "abcdef1234567", sr 8 "workflow_dispatch" (title "abc12345") "abcdef1234567"]),
  ("dispatch: chromium-counts", .dispatch "chromium-counts" "abc12345", [sr 9 "workflow_dispatch" (titleFor "chromium-counts" "abc12345") "abcdef1234567"]),
  ("dispatch: webkit-sim", .dispatch "webkit-sim" "abc12345", [sr 9 "workflow_dispatch" (titleFor "webkit-sim" "abc12345") "abcdef1234567"]),
  ("dispatch: a workflow with no nonce selects nothing", .dispatch "wktr" "abc12345", [sr 9 "workflow_dispatch" (titleFor "wktr" "abc12345") "abcdef1234567"])]

/-- Cases of `dispatchOnly`: (name, want, rows). -/
def hintCases : List (String × Want × List Run) := [
  ("hint: only a dispatch run of the commit", .push "abcdef1234", [sr 9 "workflow_dispatch" (title "abc12345") "abcdef1234567"]),
  ("hint: a push run exists, no hint", .push "abcdef1234", [sr 9 "workflow_dispatch" (title "abc12345") "abcdef1234567", sr 8 "push" "ci: x" "abcdef1234567"]),
  ("hint: a dispatch of another commit", .push "abcdef1234", [sr 9 "workflow_dispatch" (title "abc12345") "1234567abcdef"]),
  ("hint: no runs", .push "abcdef1234", []),
  ("hint: a dispatch wait", .dispatch "trajectory-probe" "abc12345", [sr 9 "workflow_dispatch" (title "abc12345") "abcdef1234567"]),
  ("hint: a short sha", .push "abcdef", [sr 9 "workflow_dispatch" (title "abc12345") "abcdef1234567"])]

/-- The JSON of a want. -/
def wantJson : Want → Json
  | .push s => Json.mkObj [("kind", "push"), ("sha", .str s)]
  | .dispatch w n => Json.mkObj [("kind", "dispatch"), ("workflow", .str w), ("nonce", .str n)]

/-- One golden line of `select`. -/
def selectLine (c : String × Want × List Run) : Json :=
  Json.mkObj [("kind", "select"), ("name", .str c.1), ("want", wantJson c.2.1),
    ("rows", .arr (c.2.2.map fun r => Json.mkObj [("id", .num r.id), ("event", .str r.event), ("title", .str r.title), ("sha", .str r.sha)]).toArray),
    ("ids", .arr ((select c.2.1 c.2.2).map fun (i : Nat) => (Json.num i : Json)).toArray)]

/-- One golden line of `dispatchOnly`. -/
def hintLine (c : String × Want × List Run) : Json :=
  Json.mkObj [("kind", "hint"), ("name", .str c.1), ("want", wantJson c.2.1),
    ("rows", .arr (c.2.2.map fun r => Json.mkObj [("id", .num r.id), ("event", .str r.event), ("title", .str r.title), ("sha", .str r.sha)]).toArray),
    ("hint", .bool (dispatchOnly c.2.1 c.2.2))]

/-- The golden line of `dispatchWorkflows`: the names and, in the same order, the `run-name:` text each yml must carry. -/
def workflowsLine : Json := Json.mkObj [("kind", "workflows"), ("list", .arr (dispatchWorkflows.map Json.str).toArray),
  ("runNames", .arr (dispatchWorkflows.map (Json.str ∘ runNameFor)).toArray)]

/-- Cases of `selectOne`: (name, want, rows). -/
def oneCases : List (String × Want × List Run) := [
  ("one: a dispatch with one run", .dispatch "trajectory-probe" "abc12345", [sr 9 "workflow_dispatch" (title "abc12345") "abcdef1234567"]),
  ("one: a dispatch with no run", .dispatch "trajectory-probe" "abc12345", []),
  ("one: a dispatch with two runs of one nonce is ambiguous", .dispatch "trajectory-probe" "abc12345", [sr 9 "workflow_dispatch" (title "abc12345") "abcdef1234567", sr 8 "workflow_dispatch" (title "abc12345") "1234567abcdef"]),
  ("one: a dispatch with three runs of one nonce", .dispatch "webkit-sim" "abc12345", [sr 7 "workflow_dispatch" (titleFor "webkit-sim" "abc12345") "a", sr 9 "workflow_dispatch" (titleFor "webkit-sim" "abc12345") "b", sr 8 "workflow_dispatch" (titleFor "webkit-sim" "abc12345") "c"]),
  ("one: a dispatch beside a run of another nonce", .dispatch "trajectory-probe" "aaaa1111", [sr 9 "workflow_dispatch" (title "bbbb2222") "x", sr 8 "workflow_dispatch" (title "aaaa1111") "x"]),
  ("one: a dispatch with a bad nonce", .dispatch "trajectory-probe" "abc", [sr 9 "workflow_dispatch" (title "abc") "x"]),
  ("one: a push with one run", .push "abcdef1234", [sr 9 "push" "ci: m" "abcdef1234567"]),
  ("one: a push with two push runs takes the greatest id", .push "abcdef1234", [sr 8 "push" "ci: m" "abcdef1234567", sr 9 "push" "ci: m" "abcdef1234567"]),
  ("one: a push with two push runs, newest first", .push "abcdef1234", [sr 9 "push" "ci: m" "abcdef1234567", sr 8 "push" "ci: m" "abcdef1234567"]),
  ("one: a push beside a dispatch", .push "abcdef1234", [sr 9 "workflow_dispatch" (title "abc12345") "abcdef1234567", sr 8 "push" "ci: m" "abcdef1234567"]),
  ("one: a push with no run", .push "abcdef1234", [sr 9 "push" "ci: x" "1234567abcdef"])]

/-- The JSON of a `One`. -/
def oneJson : One → Json
  | .found i => Json.mkObj [("kind", "found"), ("id", .num i)]
  | .absent => Json.mkObj [("kind", "absent")]
  | .ambiguous ids => Json.mkObj [("kind", "ambiguous"), ("ids", .arr (ids.map fun (i : Nat) => (Json.num i : Json)).toArray)]

/-- A listed run of the dedup cases. -/
def lr (i : Nat) (e t sha : String) (at_ : Nat) : Listed := ⟨⟨i, e, t, sha⟩, at_⟩

/-- Cases of `dedupById` then `selectOne`: (name, want, rows). -/
def dedupCases : List (String × Want × List Listed) := [
  ("dedup: one dispatch listed twice is found", .dispatch "trajectory-probe" "abc12345",
    [lr 9 "workflow_dispatch" (title "abc12345") "abcdef1234567" 1000, lr 9 "workflow_dispatch" (title "abc12345") "abcdef1234567" 1000]),
  ("dedup: the later copy is newer and kept", .dispatch "webkit-sim" "abc12345",
    [lr 9 "workflow_dispatch" (titleFor "webkit-sim" "abc12345") "a" 1000, lr 8 "push" "ci: m" "a" 900, lr 9 "workflow_dispatch" (titleFor "webkit-sim" "abc12345") "a" 2000]),
  ("dedup: the first copy is newer and kept", .dispatch "webkit-sim" "abc12345",
    [lr 9 "workflow_dispatch" (titleFor "webkit-sim" "abc12345") "a" 2000, lr 9 "workflow_dispatch" (titleFor "webkit-sim" "abc12345") "a" 1000]),
  ("dedup: three copies", .dispatch "trajectory-probe" "abc12345",
    [lr 9 "workflow_dispatch" (title "abc12345") "a" 1000, lr 9 "workflow_dispatch" (title "abc12345") "a" 3000, lr 9 "workflow_dispatch" (title "abc12345") "a" 2000]),
  ("dedup: two runs of one nonce, one listed twice, stay ambiguous", .dispatch "trajectory-probe" "abc12345",
    [lr 9 "workflow_dispatch" (title "abc12345") "a" 1000, lr 8 "workflow_dispatch" (title "abc12345") "a" 1000, lr 9 "workflow_dispatch" (title "abc12345") "a" 1000]),
  ("dedup: no copies, the list is unchanged", .dispatch "trajectory-probe" "aaaa1111",
    [lr 22 "workflow_dispatch" (title "bbbb2222") "a" 1000, lr 21 "workflow_dispatch" (title "aaaa1111") "a" 1000]),
  ("dedup: a push run listed twice", .push "abcdef1234",
    [lr 9 "push" "ci: m" "abcdef1234567" 1000, lr 8 "push" "ci: m" "abcdef1234567" 500, lr 9 "push" "ci: m" "abcdef1234567" 1000]),
  ("dedup: a copy without updatedAt (0) loses", .push "abcdef1234",
    [lr 9 "push" "ci: m" "abcdef1234567" 0, lr 9 "push" "ci: m" "abcdef1234567" 1000]),
  ("dedup: an empty list", .dispatch "trajectory-probe" "abc12345", [])]

#guard selectOne (.dispatch "trajectory-probe" "abc12345")
  (runs (dedupById [lr 9 "workflow_dispatch" (title "abc12345") "x" 1, lr 9 "workflow_dispatch" (title "abc12345") "x" 1])) = .found 9

/-- The JSON of a listed run. -/
def listedJson (r : Listed) : Json :=
  Json.mkObj [("id", .num r.run.id), ("event", .str r.run.event), ("title", .str r.run.title), ("sha", .str r.run.sha), ("updatedAt", .num r.updatedAt)]

/-- One golden line of `dedupById`, `dupIds` and `selectOne` on the kept rows. -/
def dedupLine (c : String × Want × List Listed) : Json :=
  Json.mkObj [("kind", "dedup"), ("name", .str c.1), ("want", wantJson c.2.1), ("rows", .arr (c.2.2.map listedJson).toArray),
    ("kept", .arr ((dedupById c.2.2).map listedJson).toArray), ("dups", .arr ((dupIds c.2.2).map fun (i : Nat) => (Json.num i : Json)).toArray),
    ("result", oneJson (selectOne c.2.1 (runs (dedupById c.2.2))))]

/-- One golden line of `selectOne`. -/
def oneLine (c : String × Want × List Run) : Json :=
  Json.mkObj [("kind", "one"), ("name", .str c.1), ("want", wantJson c.2.1),
    ("rows", .arr (c.2.2.map fun r => Json.mkObj [("id", .num r.id), ("event", .str r.event), ("title", .str r.title), ("sha", .str r.sha)]).toArray),
    ("result", oneJson (selectOne c.2.1 c.2.2))]

/-- One golden line. -/
def caseLine (c : String × String × List Row) : Json :=
  Json.mkObj [("kind", "pick"), ("name", .str c.1), ("nonce", .str c.2.1), ("rows", .arr (c.2.2.map rowJson).toArray),
    ("title", .str (title c.2.1)), ("valid", .bool (validNonce c.2.1)), ("result", pickJson (pick c.2.1 c.2.2))]

/-- The text of the golden file. -/
def goldenText (_ : Unit := ()) : String := String.join (cases.map fun c => (caseLine c).compress ++ "\n") ++
  String.join (selectCases.map fun c => (selectLine c).compress ++ "\n") ++
  String.join (hintCases.map fun c => (hintLine c).compress ++ "\n") ++ String.join (oneCases.map fun c => (oneLine c).compress ++ "\n") ++
  String.join (dedupCases.map fun c => (dedupLine c).compress ++ "\n") ++ workflowsLine.compress ++ "\n"

/-- Compare (or write) the golden file; returns the number of stale files. -/
def runGolden (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / ".." / "packages" / "contracts" / "golden" / "ci" / "dispatch.jsonl"
  if write then
    IO.FS.createDirAll (root / ".." / "packages" / "contracts" / "golden" / "ci")
    IO.FS.writeFile p goldenText
    IO.println s!"ci dispatch golden: written {cases.length + selectCases.length + hintCases.length + oneCases.length + dedupCases.length + 1} cases"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != goldenText then
    IO.println s!"ci dispatch golden: {p} is stale (regenerate: cd lean && lake test -- --write-ci-trigger-golden)"
    return 1
  IO.println s!"ci dispatch golden: {cases.length + selectCases.length + hintCases.length + oneCases.length + dedupCases.length + 1} cases ok"
  return 0

end Fw.Ci.Dispatch
