import Fw.Gate.Scope

/-!
# Merging sharded gate runs (`.github/scripts/merge-gate.mjs`)

The pure part of `.github/scripts/merge-gate.mjs`@2ccc158: the per-shard run files of one engine are checked and
merged into the one run file the summary reads. `mergeGate` models the script as it is today (probe shards, all
sweeps in one sweeps file); `mergeGateById` is the proposed form in which whole sweeps may sit in any file and are
merged by id like the probes. Both reproduce the unsharded run (`mergeGate_eq_unsharded`,
`mergeGateById_eq_unsharded`), and sharding keeps every part's verdict (`sharded_verdict_eq`). The unit of a shard
is a whole sweep: splitting one sweep into two can change a verdict (`split_sweep_changes_verdict`).

The header check compares `JSON.stringify` strings, so a header is modelled as a value with decidable equality; the
schema test is the predicate `hdrOk`. A run narrowed by `--parts` replaces the wanted ids by its Lean scope before
the checks (`merge-gate.mjs:39-45`), so the wanted id lists are parameters here.
-/

namespace Fw.Gate
open Fw.Site.Breakpoints

/-! ## Merging records by id -/

/-- A filter-map that maps every element to itself is the identity.

Used to read the merged list back as the unsharded one. -/
theorem filterMap_eq_self {α : Type} (f : α → Option α) :
    ∀ (l : List α), (∀ x ∈ l, f x = some x) → l.filterMap f = l
  | [], _ => rfl
  | a :: l, h => by
    rw [List.filterMap_cons, h a (by simp)]
    simp only
    rw [filterMap_eq_self f l (fun x hx => h x (by simp [hx]))]

/-- Distinct images mean distinct members.

With distinct ids, a record is determined by its id. -/
theorem nodupMap_inj {α β : Type} (f : α → β) : ∀ (l : List α), (l.map f).Nodup →
    ∀ x ∈ l, ∀ y ∈ l, f x = f y → x = y
  | [], _, x, hx, _, _, _ => by simp at hx
  | a :: l, hnd, x, hx, y, hy, he => by
    rw [List.map_cons, List.nodup_cons] at hnd
    obtain ⟨ha, hl⟩ := hnd
    simp only [List.mem_cons] at hx hy
    rcases hx with rfl | hx <;> rcases hy with rfl | hy
    · rfl
    · exact absurd (List.mem_map.mpr ⟨y, hy, he.symm⟩) ha
    · exact absurd (List.mem_map.mpr ⟨x, hx, he⟩) ha
    · exact nodupMap_inj f l hl x hx y hy he

/-- Merge records by id (`merge-gate.mjs:46-56`, `:68`): the records' ids must be distinct (a repeat fails), every
wanted id must be present (none missing) and every present id wanted (none extra); the result lists, for each wanted
id in order, the record with that id.

The probe half of the merge script (`byId`, `missing`, `extra`, `wantIds.map(byId.get)`). -/
def mergeById {α : Type} (idOf : α → String) (want : List String) (recs : List α) : Option (List α) :=
  if (recs.map idOf).Nodup ∧ (∀ i ∈ want, i ∈ recs.map idOf) ∧ (∀ i ∈ recs.map idOf, i ∈ want) then
    some (want.filterMap fun i => recs.find? fun r => idOf r == i)
  else none

#guard mergeById id ["a", "b", "c"] ["c", "a", "b"] = some ["a", "b", "c"]
#guard mergeById id ["a", "b"] ["a", "b", "a"] = none
#guard mergeById id ["a", "b"] ["a"] = none
#guard mergeById id ["a"] ["a", "b"] = none
#guard mergeById id [] [] = some []

/-- **The merge reproduces the unsharded records.** If the unsharded run wrote records `R` with distinct ids and the
shards together hold the records of `R` in any order (each once, none extra), merging them against the ids of `R`
gives back `R`, in order.

Here `Q ∼ R` says `Q` is a permutation of `R`. -/
theorem mergeById_eq_unsharded {α : Type} (idOf : α → String) (R recs : List α)
    (hnd : (R.map idOf).Nodup) (hp : recs.Perm R) :
    mergeById idOf (R.map idOf) recs = some R := by
  have hc : (recs.map idOf).Perm (R.map idOf) := hp.map idOf
  have hcond : (recs.map idOf).Nodup ∧ (∀ i ∈ R.map idOf, i ∈ recs.map idOf) ∧
      (∀ i ∈ recs.map idOf, i ∈ R.map idOf) :=
    ⟨hc.nodup_iff.mpr hnd, fun _ hi => hc.mem_iff.mpr hi, fun _ hi => hc.mem_iff.mp hi⟩
  unfold mergeById
  split
  case isFalse hn => exact absurd hcond hn
  rw [Option.some.injEq, List.filterMap_map]
  have key : ∀ x ∈ R, (recs.find? fun r => idOf r == idOf x) = some x := by
    intro x hx
    have hx' : x ∈ recs := hp.mem_iff.mpr hx
    cases hf : recs.find? (fun r => idOf r == idOf x) with
    | none =>
      rw [List.find?_eq_none] at hf
      exact absurd (by simp) (hf x hx')
    | some y =>
      have hy : y ∈ recs := List.mem_of_find?_eq_some hf
      have hid : idOf y = idOf x := by simpa using List.find?_some hf
      exact congrArg some (nodupMap_inj idOf R hnd y (hp.mem_iff.mp hy) x hx hid)
  exact filterMap_eq_self _ R key

/-! ## The merge script -/

/-- One run file (`fw.gate-breakpoints.run/1`): a header, the probe records and the sweep records.

What `run.mjs` writes and `merge-gate.mjs` reads. -/
structure RunFile (H α β : Type) where
  /-- the header (compared as a whole) -/
  header : H
  /-- probe records -/
  probes : List α
  /-- sweep records -/
  sweeps : List β

/-- Every file's header passes the schema test and equals the first file's (`merge-gate.mjs:34-38`).

The header check of the merge script. -/
def headersOk {H α β : Type} [DecidableEq H] (hdrOk : H → Bool) (f0 : RunFile H α β)
    (fs : List (RunFile H α β)) : Bool :=
  fs.all fun f => hdrOk f.header && f.header == f0.header

/-- **The merge script today** (`merge-gate.mjs`@2ccc158): no shard file is a usage error; all files (shards, then
the sweeps file if given) must pass `headersOk`; no shard may hold sweeps; the shards' probes are merged by id
against `wantIds`; the sweeps file, if given, must hold no probes and exactly the sweeps `wantSweeps` in order. The
output is the first file's header, the merged probes and the sweeps file's sweeps (`[]` without one).

The whole decision of the merge step; reading and writing the files is glue. -/
def mergeGate {H α β : Type} [DecidableEq H] (hdrOk : H → Bool) (pid : α → String) (sid : β → String)
    (wantIds wantSweeps : List String) (shards : List (RunFile H α β)) (sweepFile : Option (RunFile H α β)) :
    Option (RunFile H α β) :=
  match shards with
  | [] => none
  | f0 :: _ =>
    if headersOk hdrOk f0 (shards ++ sweepFile.toList) && shards.all (·.sweeps.isEmpty) then
      match mergeById pid wantIds (shards.flatMap (·.probes)) with
      | none => none
      | some ps =>
        match sweepFile with
        | none => some ⟨f0.header, ps, []⟩
        | some g =>
          if g.probes.isEmpty && g.sweeps.map sid == wantSweeps then some ⟨f0.header, ps, g.sweeps⟩ else none
    else none

#guard (mergeGate (H := Nat) (fun _ => true) id id ["a", "b"] ["s"]
  [⟨0, ["b"], []⟩, ⟨0, ["a"], []⟩] (some ⟨0, [], ["s"]⟩)).map (fun f => (f.probes, f.sweeps)) = some (["a", "b"], ["s"])
#guard (mergeGate (H := Nat) (fun _ => true) id id ["a", "b"] ["s"] [⟨0, ["b"], []⟩, ⟨1, ["a"], []⟩] none).isNone
#guard (mergeGate (H := Nat) (fun _ => true) id id ["a"] ["s"] [⟨0, ["a"], ["s"]⟩] none).isNone
#guard (mergeGate (H := Nat) (fun _ => true) id id ["a"] ["s"] [⟨0, ["a"], []⟩] (some ⟨0, [], ["t"]⟩)).isNone
#guard (mergeGate (H := Nat) (α := String) (β := String) (fun _ => true) id id [] [] [] (some ⟨0, [], []⟩)).isNone

/-- **Today's merge reproduces the unsharded run.** Let the unsharded run be `(h, P, K)` with `ok(h)` and
distinct probe ids. If there is at least one shard, every shard has header `h` and no sweeps, the shards' probes
together are a permutation of `P`, and the sweeps file is `(h, [], K)`, then merging against the ids of `P` and of
`K` gives `(h, P, K)`.

Probe sharding with one sweeps file loses and adds nothing. -/
theorem mergeGate_eq_unsharded {H α β : Type} [DecidableEq H] (hdrOk : H → Bool) (pid : α → String)
    (sid : β → String) (h : H) (P : List α) (K : List β) (shards : List (RunFile H α β))
    (hok : hdrOk h = true) (hnd : (P.map pid).Nodup) (hne : shards ≠ [])
    (hsh : ∀ f ∈ shards, f.header = h ∧ f.sweeps = []) (hp : (shards.flatMap (·.probes)).Perm P) :
    mergeGate hdrOk pid sid (P.map pid) (K.map sid) shards (some ⟨h, [], K⟩) = some ⟨h, P, K⟩ := by
  cases shards with
  | nil => exact absurd rfl hne
  | cons f0 rest =>
    have h0 : f0.header = h := (hsh f0 (by simp)).1
    have hhd : headersOk hdrOk f0 (f0 :: rest ++ [⟨h, [], K⟩]) = true := by
      simp only [headersOk, List.all_eq_true, Bool.and_eq_true, beq_iff_eq]
      intro f hf
      rw [List.mem_append, List.mem_singleton] at hf
      rcases hf with hf | rfl
      · rw [(hsh f hf).1, h0]; exact ⟨hok, rfl⟩
      · exact ⟨hok, h0.symm⟩
    have hsw : ((f0 :: rest).all fun f => f.sweeps.isEmpty) = true := by
      simp only [List.all_eq_true, List.isEmpty_iff]
      exact fun f hf => (hsh f hf).2
    simp only [mergeGate, Option.toList_some, hhd, hsw, Bool.and_self, ite_true,
      mergeById_eq_unsharded pid P _ hnd hp, List.isEmpty_nil, beq_self_eq_true, h0]

/-! ## The proposed merge: whole sweeps in any file -/

/-- **Proposed merge with sweeps sharded too:** no file is a usage error; all files must pass `headersOk`; the
probes of all files are merged by id against `wantIds` and the sweeps of all files by id against `wantSweeps`. A
sweep record is a whole sweep: a file holds a sweep with all its stops or not at all.

The merge step the CI-structure note proposes (sweeps on several jobs). -/
def mergeGateById {H α β : Type} [DecidableEq H] (hdrOk : H → Bool) (pid : α → String) (sid : β → String)
    (wantIds wantSweeps : List String) (files : List (RunFile H α β)) : Option (RunFile H α β) :=
  match files with
  | [] => none
  | f0 :: _ =>
    if headersOk hdrOk f0 files then
      match mergeById pid wantIds (files.flatMap (·.probes)), mergeById sid wantSweeps (files.flatMap (·.sweeps)) with
      | some ps, some ks => some ⟨f0.header, ps, ks⟩
      | _, _ => none
    else none

#guard (mergeGateById (H := Nat) (fun _ => true) id id ["a", "b"] ["s", "t"]
  [⟨0, ["b"], ["t"]⟩, ⟨0, ["a"], ["s"]⟩]).map (fun f => (f.probes, f.sweeps)) = some (["a", "b"], ["s", "t"])
#guard (mergeGateById (H := Nat) (fun _ => true) id id ["a"] ["s"] [⟨0, ["a"], ["s"]⟩, ⟨0, [], ["s"]⟩]).isNone
#guard (mergeGateById (H := Nat) (fun _ => true) id id ["a"] ["s", "t"] [⟨0, ["a"], ["s"]⟩]).isNone
#guard (mergeGateById (H := Nat) (α := String) (β := String) (fun _ => true) id id [] [] []).isNone

/-- **The proposed merge reproduces the unsharded run.** Let the unsharded run be `(h, P, K)` with `ok(h)`,
distinct probe ids and distinct sweep ids. If there is at least one file, every file has header `h`, and the files'
probes together are a permutation of `P` and their sweeps a permutation of `K`, then merging gives `(h, P, K)`.

Whole sweeps can go to any job; the distinct sweep ids are `sweeps_ids_nodup`. -/
theorem mergeGateById_eq_unsharded {H α β : Type} [DecidableEq H] (hdrOk : H → Bool) (pid : α → String)
    (sid : β → String) (h : H) (P : List α) (K : List β) (files : List (RunFile H α β))
    (hok : hdrOk h = true) (hnd : (P.map pid).Nodup) (hknd : (K.map sid).Nodup) (hne : files ≠ [])
    (hh : ∀ f ∈ files, f.header = h) (hp : (files.flatMap (·.probes)).Perm P)
    (hk : (files.flatMap (·.sweeps)).Perm K) :
    mergeGateById hdrOk pid sid (P.map pid) (K.map sid) files = some ⟨h, P, K⟩ := by
  cases files with
  | nil => exact absurd rfl hne
  | cons f0 rest =>
    have h0 : f0.header = h := hh f0 (by simp)
    have hhd : headersOk hdrOk f0 (f0 :: rest) = true := by
      simp only [headersOk, List.all_eq_true, Bool.and_eq_true, beq_iff_eq]
      intro f hf
      rw [hh f hf, h0]; exact ⟨hok, rfl⟩
    simp only [mergeGateById, hhd, ite_true, mergeById_eq_unsharded pid P _ hnd hp,
      mergeById_eq_unsharded sid K _ hknd hk, h0]

/-- The four sweeps of the full gate have distinct ids, the premise of `mergeGateById_eq_unsharded` for sweeps.

No two sweeps can be confused in a by-id merge. -/
theorem sweeps_ids_nodup : (sweeps.map (·.id)).Nodup := by
  decide +kernel

/-! ## Verdicts of a sharded run -/

/-- **Sharding keeps the verdict.** Split a run's loads `S` and whole sweeps `K` over jobs as `(S_j)_j` and
`(K_j)_j`. If the loads of all jobs together are a permutation of `S` and their sweeps a permutation of `K`, every
part's verdict over the jobs equals its verdict over the unsharded run.

Order does not matter to the rollup (`rollup_perm`); each sweep keeps its own stop order. -/
theorem sharded_verdict_eq {κ : Type} [DecidableEq κ] (reach : Env → Option Reason) (key : Env → κ)
    (hv : List κ → Verdict) (S : List Probe) (K : List Sweep) (Ss : List (List Probe)) (Ks : List (List Sweep))
    (hS : Ss.flatten.Perm S) (hK : Ks.flatten.Perm K) :
    scopedVerdict reach key hv Ss.flatten Ks.flatten = scopedVerdict reach key hv S K := by
  unfold scopedVerdict
  apply rollup_perm
  exact (hS.map _).append (hK.flatMap_right _)

/-- The key of the split counterexample: is the width at most 600?

One media-query bit. -/
def splitKey (e : Env) : Bool := decide (e.width.LeNat 600)

/-- The hypothesis of the split counterexample: a part that fails once its key returns to an earlier state (a stale
state after a round trip), i.e. when the collapsed history has at least 3 entries.

A round-trip bug only a whole sweep can show. -/
def roundTripHv (h : List Bool) : Verdict := if h.length ≥ 3 then .fail else .pass

/-- **Splitting one sweep can change a verdict.** The sweep `700 → 600 → 700` fails under
`(κ_600, hv_3)` (its last stop's history is `(⊥, ⊤, ⊥)`), but cut into `700 → 600` and
`700`, run as two sweeps, it passes (no history has 3 entries). So a shard must hold whole sweeps.

Here `(n_0, ...)` is a sweep of `deskStop` widths; the stops of the two pieces, concatenated, are the original
sweep's stops. -/
theorem split_sweep_changes_verdict (reach : Env → Option Reason) :
    scopedVerdict reach splitKey roundTripHv [] [⟨"w", "", [700, 600, 700].map deskStop⟩] = .fail ∧
    scopedVerdict reach splitKey roundTripHv []
      [⟨"w1", "", [700, 600].map deskStop⟩, ⟨"w2", "", [700].map deskStop⟩] = .pass := by
  unfold scopedVerdict
  simp only [List.map_nil, List.nil_append]
  constructor <;> decide +kernel

end Fw.Gate
