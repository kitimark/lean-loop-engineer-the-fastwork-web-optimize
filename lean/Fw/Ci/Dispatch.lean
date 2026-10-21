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

/-- The title a dispatch with this nonce gets (`run-name` of the workflow). -/
def titlePrefix : String := "trajectory-probe dispatch nonce="

/-- The run title of a dispatch. -/
def title (n : String) : String := titlePrefix ++ n

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
theorem title_inj (a b : String) (h : title a = title b) : a = b := by
  unfold title at h
  have := congrArg String.toList h
  simp only [String.toList_append] at this
  exact String.toList_inj.mp (List.append_cancel_left this)

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
  | dispatch (nonce : String)
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
  | .dispatch n, r => validNonce n && isMine n ⟨r.id, r.event, r.title⟩

/-- The ids of the runs the wait means, in list order. -/
def select (w : Want) (rows : List Run) : List Nat := (rows.filter (wanted w)).map (·.id)

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
theorem dispatch_never_push (n : String) (r : Run) (h : r.event ≠ "workflow_dispatch") : wanted (.dispatch n) r = false := by
  simp [wanted, isMine, h]

/-- Branch dispatch: a run of another nonce is not selected. -/
theorem dispatch_other_nonce (a b : String) (r : Run) (hne : a ≠ b) (h : r.title = title b) : wanted (.dispatch a) r = false := by
  have := other_nonce_not_mine a b ⟨r.id, r.event, r.title⟩ hne h
  simp [wanted, this]

/-- Branch dispatch: an invalid nonce selects nothing. -/
theorem dispatch_bad_nonce (n : String) (rows : List Run) (h : validNonce n = false) : select (.dispatch n) rows = [] := by
  simp [select, wanted, h]

/-- Branch dispatch: a run with the dispatch's title is selected, on any head sha. -/
theorem dispatch_selects (n : String) (r : Run) (hn : validNonce n = true) (he : r.event = "workflow_dispatch") (ht : r.title = title n) :
    wanted (.dispatch n) r = true := by
  simp [wanted, isMine, hn, he, ht]

/-- **Soundness.** A selected id belongs to a row of the list that `wanted` accepts. -/
theorem select_sound (w : Want) (rows : List Run) (i : Nat) (h : i ∈ select w rows) :
    ∃ r ∈ rows, r.id = i ∧ wanted w r = true := by
  obtain ⟨r, hr, hid⟩ := List.mem_map.mp h
  exact ⟨r, (List.mem_filter.mp hr).1, hid, (List.mem_filter.mp hr).2⟩

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
  ("dispatch: the push is newer, the dispatch is picked", .dispatch "abc12345", [sr 9 "push" "ci: measure" "abcdef1234567", sr 8 "workflow_dispatch" (title "abc12345") "abcdef1234567"]),
  ("dispatch: two dispatches, each its own (first)", .dispatch "aaaa1111", [sr 22 "workflow_dispatch" (title "bbbb2222") "abcdef1234567", sr 21 "workflow_dispatch" (title "aaaa1111") "abcdef1234567"]),
  ("dispatch: two dispatches, each its own (second)", .dispatch "bbbb2222", [sr 22 "workflow_dispatch" (title "bbbb2222") "abcdef1234567", sr 21 "workflow_dispatch" (title "aaaa1111") "abcdef1234567"]),
  ("dispatch: a push run with the dispatch's title text", .dispatch "abc12345", [sr 9 "push" (title "abc12345") "abcdef1234567"]),
  ("dispatch: a bad nonce", .dispatch "abc", [sr 9 "workflow_dispatch" (title "abc") "abcdef1234567"]),
  ("dispatch: no run yet", .dispatch "abc12345", [])]

/-- The JSON of a want. -/
def wantJson : Want → Json
  | .push s => Json.mkObj [("kind", "push"), ("sha", .str s)]
  | .dispatch n => Json.mkObj [("kind", "dispatch"), ("nonce", .str n)]

/-- One golden line of `select`. -/
def selectLine (c : String × Want × List Run) : Json :=
  Json.mkObj [("kind", "select"), ("name", .str c.1), ("want", wantJson c.2.1),
    ("rows", .arr (c.2.2.map fun r => Json.mkObj [("id", .num r.id), ("event", .str r.event), ("title", .str r.title), ("sha", .str r.sha)]).toArray),
    ("ids", .arr ((select c.2.1 c.2.2).map fun (i : Nat) => (Json.num i : Json)).toArray)]

/-- One golden line. -/
def caseLine (c : String × String × List Row) : Json :=
  Json.mkObj [("kind", "pick"), ("name", .str c.1), ("nonce", .str c.2.1), ("rows", .arr (c.2.2.map rowJson).toArray),
    ("title", .str (title c.2.1)), ("valid", .bool (validNonce c.2.1)), ("result", pickJson (pick c.2.1 c.2.2))]

/-- The text of the golden file. -/
def goldenText (_ : Unit := ()) : String := String.join (cases.map fun c => (caseLine c).compress ++ "\n") ++
  String.join (selectCases.map fun c => (selectLine c).compress ++ "\n")

/-- Compare (or write) the golden file; returns the number of stale files. -/
def runGolden (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / ".." / "packages" / "contracts" / "golden" / "ci" / "dispatch.jsonl"
  if write then
    IO.FS.createDirAll (root / ".." / "packages" / "contracts" / "golden" / "ci")
    IO.FS.writeFile p goldenText
    IO.println s!"ci dispatch golden: written {cases.length + selectCases.length} cases"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != goldenText then
    IO.println s!"ci dispatch golden: {p} is stale (regenerate: cd lean && lake test -- --write-ci-trigger-golden)"
    return 1
  IO.println s!"ci dispatch golden: {cases.length + selectCases.length} cases ok"
  return 0

end Fw.Ci.Dispatch
