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

/-- One golden line. -/
def caseLine (c : String × String × List Row) : Json :=
  Json.mkObj [("kind", "pick"), ("name", .str c.1), ("nonce", .str c.2.1), ("rows", .arr (c.2.2.map rowJson).toArray),
    ("title", .str (title c.2.1)), ("valid", .bool (validNonce c.2.1)), ("result", pickJson (pick c.2.1 c.2.2))]

/-- The text of the golden file. -/
def goldenText (_ : Unit := ()) : String := String.join (cases.map fun c => (caseLine c).compress ++ "\n")

/-- Compare (or write) the golden file; returns the number of stale files. -/
def runGolden (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / ".." / "packages" / "contracts" / "golden" / "ci" / "dispatch.jsonl"
  if write then
    IO.FS.createDirAll (root / ".." / "packages" / "contracts" / "golden" / "ci")
    IO.FS.writeFile p goldenText
    IO.println s!"ci dispatch golden: written {cases.length} cases"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != goldenText then
    IO.println s!"ci dispatch golden: {p} is stale (regenerate: cd lean && lake test -- --write-ci-trigger-golden)"
    return 1
  IO.println s!"ci dispatch golden: {cases.length} cases ok"
  return 0

end Fw.Ci.Dispatch
