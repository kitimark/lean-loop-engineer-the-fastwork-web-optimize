import Fw.Store.Layout
/-!
# `fw ci`: which part of a finished CI run enters the artifact store

Spec of `store.ciRun` (glue in `Fw.Wire.Store`, I/O in `apps/runner/src/ci.ts`). `fw ci` pulls a finished
`chromium-counts` run into the store, one store key per target. This module decides, from the run metadata
(`gh run view`) and the downloaded artifacts, whether the run is stored at all (accept, or refuse with every reason)
and, when it is, the key inputs (a `Req`) of each target and the shard artifacts filed under that key.

Two calls: before the download (`got = none`) only the run itself is checked, so a failed run downloads nothing;
after it (`got = some g`) the artifacts, the class directories and the shards' own facts are checked too, and the
key inputs are given. Proved: a refused run stores nothing (`ciRun_refused`), an accepted run succeeded with every
shard job (`ciRun_accepted_run`) and has every artifact (`ciRun_accepted_got`, `ciRun_accepted_req`), and two
artifacts with different targets are filed under different keys (`ciRun_key_ne`, `ciRun_keys_nodup`).
-/
namespace Fw.Store

/-! ## The run -/

/-- One job of a CI run, as `gh run view --json jobs` lists it (an unfinished job has the empty conclusion). -/
structure CiJob where
  name : String
  conclusion : String
deriving Repr, DecidableEq

/-- The metadata of a CI run (`gh run view --json workflowName,status,conclusion,headSha,jobs`). -/
structure CiRun where
  runId : String
  workflow : String
  status : String
  conclusion : String
  headSha : String
  jobs : List CiJob
deriving Repr

/-- The workflow whose runs `fw ci` stores. -/
def ciWorkflow : String := "chromium-counts"

/-- One measuring shard of a run: the target it measured and its repetition number (decimal digits, as written). -/
structure Shard where
  target : Target
  n : String
deriving Repr, DecidableEq

/-- The artifact a shard uploads. -/
def Shard.artifact (s : Shard) : String := "chromium-counts-" ++ s.target.name ++ "-r" ++ s.n

/-- The directory a shard's files get inside its store key. -/
def Shard.dir (s : Shard) : String := "r" ++ s.n

/-- A non-empty run of decimal digits. -/
def isDigits (s : String) : Bool := !s.isEmpty && s.toList.all Char.isDigit

/-- The shard a job measures, read from its name `counts (<target>, r<n>)` (the matrix job name of chromium-counts.yml);
`none` for every other job.

(the two prefixes `counts (original, r` and `counts (rewrite, r` exclude each other, so at most one `(t, n)` fits).
-/
def shardOfJob (name : String) : Option Shard :=
  [Target.original, Target.rewrite].findSome? fun t =>
    let pre := ("counts (" ++ t.name ++ ", r").toList
    let cs := name.toList
    if pre.isPrefixOf cs && cs.getLast? == some ')' then
      let n := String.ofList ((cs.drop pre.length).dropLast)
      if isDigits n then some ⟨t, n⟩ else none
    else none

#guard shardOfJob "counts (original, r1)" == some ⟨.original, "1"⟩
#guard shardOfJob "counts (rewrite, r12)" == some ⟨.rewrite, "12"⟩
#guard shardOfJob "counts (both, r1)" == none
#guard shardOfJob "counts (original, r)" == none
#guard shardOfJob "counts (original, r1x)" == none
#guard shardOfJob "counts (original, r1) " == none
#guard shardOfJob "plan" == none

/-- The shard jobs of a run, in job order, each with its shard. -/
def shardJobs (r : CiRun) : List (Shard × CiJob) :=
  r.jobs.filterMap fun j => (shardOfJob j.name).map fun s => (s, j)

/-- A text, or a fallback when it is empty. -/
def orElse (s d : String) : String := if s.isEmpty then d else s

/-- The refusals that depend on the run alone: another workflow, a run not completed or not successful, a run
without shard jobs.
-/
def runRefusals (r : CiRun) : List String :=
  (if r.workflow = ciWorkflow then [] else [s!"run {r.runId} is workflow {r.workflow}, not chromium-counts"]) ++
  (if r.status = "completed" then
    (if r.conclusion = "success" then [] else [s!"run {r.runId} concluded {orElse r.conclusion "unknown"}, not success"])
   else [s!"run {r.runId} is {r.status}, not completed"]) ++
  (if (shardJobs r).isEmpty then [s!"run {r.runId} has no counts shard jobs"] else [])

/-! ## The downloaded artifacts -/

/-- What `fw ci` read from one downloaded shard artifact: its name, the profile id and the query (`counts.json`,
`profile.id`, `meta.search`, absent query = empty), the target it says it measured (`meta.target`, may be absent)
and the image (`image-id.txt`).
-/
structure ShardFacts where
  name : String
  profile : String
  image : String
  search : String
  target : Option String
deriving Repr

/-- The download: the shard artifacts read (with their facts) and the directories under `chromium-classes`. -/
structure Got where
  artifacts : List ShardFacts
  classes : List String
deriving Repr

/-- The facts of a shard's artifact, if it was downloaded (the first artifact of that name). -/
def factOf (g : Got) (s : Shard) : Option ShardFacts := g.artifacts.find? (·.name == s.artifact)

/-- The refusals of the shard jobs, in job order: a job that did not succeed, and (after the download) an artifact
that is missing.
-/
def jobRefusals (r : CiRun) (got : Option Got) : List String :=
  (shardJobs r).flatMap fun p =>
    (if p.2.conclusion = "success" then [] else [s!"shard {p.1.artifact}: job {orElse p.2.conclusion "unfinished"}"]) ++
    (match got with
     | some g => if (factOf g p.1).isSome then [] else [s!"missing shard artifact {p.1.artifact}"]
     | none => [])

/-- The targets a run measured, in canonical order (one store key each). -/
def ciTargets (r : CiRun) : List Target :=
  [Target.original, Target.rewrite].filter fun t => (shardJobs r).any fun p => decide (p.1.target = t)

/-- The shards of one target, duplicates removed, sorted by artifact name. -/
def shardsOf (r : CiRun) (t : Target) : List Shard :=
  (((shardJobs r).map (·.1)).filter (fun s => decide (s.target = t))).eraseDups.mergeSort
    fun a b => !decide (b.artifact < a.artifact)

/-- The facts of the downloaded shards of one target, in shard order. -/
def factsOf (r : CiRun) (g : Got) (t : Target) : List ShardFacts := (shardsOf r t).filterMap (factOf g)

/-- A shard agrees with the first shard of its target: same profile, query and image, and it measured that target
(an absent `meta.target` counts as that target).
-/
def agrees (t : Target) (f0 f : ShardFacts) : Bool :=
  f.profile == f0.profile && f.search == f0.search && f.image == f0.image && f.target.getD t.name == t.name

/-- The refusals of the download, per target in canonical order: a missing class directory, then shards that
disagree.
-/
def gotRefusals (r : CiRun) (g : Got) : List String :=
  (ciTargets r).flatMap (fun t => if g.classes.contains t.name then [] else [s!"missing chromium-classes/{t.name}"]) ++
  (ciTargets r).flatMap fun t =>
    match factsOf r g t with
    | [] => []
    | f0 :: fs => if (f0 :: fs).all (agrees t f0) then [] else [s!"{t.name} shards disagree on profile, query, target or image"]

/-- Every refusal of a run: the run, its shard jobs, and (after the download, `got = some g`) the
download.
-/
def ciRefusals (r : CiRun) (got : Option Got) : List String :=
  runRefusals r ++ jobRefusals r got ++ (match got with | some g => gotRefusals r g | none => [])

/-! ## The key inputs -/

/-- The parameters of a page query `?k=v&k=v` (a leading `?` dropped, empty segments skipped, the value after the
first `=`, empty when there is none). No percent-decoding: chromium-counts.yml writes the query raw.
-/
def queryParams (search : String) : List (String × String) :=
  let q := match search.toList with
    | '?' :: cs => String.ofList cs
    | _ => search
  (q.splitOn "&").filterMap fun kv =>
    match kv.splitOn "=" with
    | k :: v => if kv.isEmpty then none else some (k, "=".intercalate v)
    | [] => none

/-- The value of the first parameter named `k`. -/
def queryGet (ps : List (String × String)) (k : String) : Option String := (ps.find? (·.1 == k)).map (·.2)

/-- A flag `part:variant`; anything else becomes `(ε, s)`, which the manifest check refuses. -/
def flagOf (s : String) : String × String :=
  match s.splitOn ":" with
  | [a, b] => (a, b)
  | _ => ("", s)

/-- The preset and flags of a rewrite query: `preset` (default `original`) and the comma list `fw`, its empty items
dropped, sorted by part (stable).

(a present but empty value is kept: `?preset=` gives the preset `ε`; the sort is stable, by the lexicographic order of the parts).
-/
def searchConfig (search : String) : String × List (String × String) :=
  let ps := queryParams search
  ((queryGet ps "preset").getD defaultPreset,
   ((((queryGet ps "fw").getD "").splitOn ",").filter (fun x => !x.isEmpty) |>.map flagOf).mergeSort
     fun a b => !decide (b.1 < a.1))

#guard searchConfig "" == ("original", [])
#guard searchConfig "?preset=strip-demo" == ("strip-demo", [])
#guard searchConfig "?fw=hero.countdown:strip" == ("original", [("hero.countdown", "strip")])
#guard searchConfig "?preset=p&fw=b:y,a:x" == ("p", [("a", "x"), ("b", "y")])
#guard searchConfig "preset=p&&fw=a:x," == ("p", [("a", "x")])
#guard searchConfig "?preset=&fw=hero" == ("", [("", "hero")])

def ciReq (r : CiRun) (t : Target) (f : ShardFacts) : Req :=
  let c : String × List (String × String) := match t with
    | .rewrite => searchConfig f.search
    | .original => (defaultPreset, [])
  { engine := .chromium, target := t, preset := c.1, fw := c.2, profile := f.profile, sha := r.headSha, image := f.image,
    runs := (shardsOf r t).length }

/-- One store key of an accepted run: its target, the shards filed under it, and its key inputs (only after the
download).
-/
structure CiTarget where
  target : Target
  shards : List Shard
  req : Option Req

/-- The store key of target `t`: its shards, and the key inputs from the first downloaded shard's facts. -/
def ciTarget (r : CiRun) (got : Option Got) (t : Target) : CiTarget :=
  { target := t, shards := shardsOf r t, req := got.bind fun g => (factsOf r g t).head?.map (ciReq r t) }

/-- The answer of `store.ciRun`: every refusal (none = accepted) and the store keys. -/
structure CiResult where
  refusals : List String
  targets : List CiTarget

/-- **`store.ciRun`.** A run is accepted when it has no refusal; then it files one store key per target it measured,
otherwise none.
-/
def ciRun (r : CiRun) (got : Option Got) : CiResult :=
  let rs := ciRefusals r got
  { refusals := rs, targets := if rs.isEmpty then (ciTargets r).map (ciTarget r got) else [] }

/-! ## Properties -/

/-- **A refused run stores nothing:** when there is a refusal, no store key is filed. -/
theorem ciRun_refused {r : CiRun} {got : Option Got} (h : (ciRun r got).refusals ≠ []) :
    (ciRun r got).targets = [] := by
  simp only [ciRun] at *
  simp [List.isEmpty_iff, h]

/-- The store keys of an accepted run are its targets in canonical order. -/
theorem ciRun_accepted_targets {r : CiRun} {got : Option Got} (h : (ciRun r got).refusals = []) :
    (ciRun r got).targets = (ciTargets r).map (ciTarget r got) := by
  simp only [ciRun] at *
  simp [h]

/-- **An accepted run succeeded:** it is a chromium-counts run, completed with success, with at least one shard job,
and every shard job succeeded (whether or not the artifacts were checked yet).
-/
theorem ciRun_accepted_run {r : CiRun} {got : Option Got} (h : (ciRun r got).refusals = []) :
    r.workflow = ciWorkflow ∧ r.status = "completed" ∧ r.conclusion = "success" ∧ shardJobs r ≠ [] ∧
      ∀ p ∈ shardJobs r, p.2.conclusion = "success" := by
  simp only [ciRun, ciRefusals, runRefusals, jobRefusals, List.append_eq_nil_iff] at h
  obtain ⟨⟨⟨⟨hw, hs⟩, hn⟩, hj⟩, _⟩ := h
  refine ⟨?_, ?_, ?_, ?_, ?_⟩
  · by_cases c : r.workflow = ciWorkflow
    · exact c
    · simp [c] at hw
  · by_cases c : r.status = "completed"
    · exact c
    · simp [c] at hs
  · by_cases c : r.status = "completed"
    · by_cases d : r.conclusion = "success"
      · exact d
      · simp [c, d] at hs
    · simp [c] at hs
  · intro e
    simp [e] at hn
  · intro p hp
    rw [List.flatMap_eq_nil_iff] at hj
    have := hj p hp
    rw [List.append_eq_nil_iff] at this
    by_cases c : p.2.conclusion = "success"
    · exact c
    · simp [c] at this

/-- A shard of a target is one of the run's shard jobs, and measured that target. -/
theorem mem_shardsOf {r : CiRun} {t : Target} {s : Shard} (h : s ∈ shardsOf r t) :
    (∃ j, (s, j) ∈ shardJobs r) ∧ s.target = t := by
  simp only [shardsOf, List.mem_mergeSort, List.mem_eraseDups, List.mem_filter, List.mem_map,
    decide_eq_true_eq] at h
  obtain ⟨⟨p, hp, rfl⟩, ht⟩ := h
  exact ⟨⟨p.2, hp⟩, ht⟩

/-- Every shard job's shard is listed under its target. -/
theorem shardsOf_of_job {r : CiRun} {s : Shard} {j : CiJob} (h : (s, j) ∈ shardJobs r) :
    s ∈ shardsOf r s.target := by
  simp only [shardsOf, List.mem_mergeSort, List.mem_eraseDups, List.mem_filter, List.mem_map,
    decide_eq_true_eq]
  exact ⟨⟨(s, j), h, rfl⟩, trivial⟩

/-- **An accepted download is complete:** every store key's class directory and every shard artifact filed under it
were downloaded.
-/
theorem ciRun_accepted_got {r : CiRun} {g : Got} (h : (ciRun r (some g)).refusals = []) :
    ∀ c ∈ (ciRun r (some g)).targets, c.target.name ∈ g.classes ∧
      ∀ s ∈ c.shards, ∃ f ∈ g.artifacts, f.name = s.artifact := by
  rw [ciRun_accepted_targets h]
  simp only [ciRun, ciRefusals, gotRefusals, jobRefusals, List.append_eq_nil_iff, List.flatMap_eq_nil_iff] at h
  obtain ⟨⟨_, hj⟩, hc, _⟩ := h
  intro c hcm
  simp only [List.mem_map] at hcm
  obtain ⟨t, ht, rfl⟩ := hcm
  refine ⟨?_, ?_⟩
  · have := hc t ht
    show t.name ∈ g.classes
    by_cases e : t.name ∈ g.classes
    · exact e
    · simp [e] at this
  · intro s hs
    obtain ⟨⟨j, hsj⟩, _⟩ := mem_shardsOf hs
    have h2 := (hj (s, j) hsj).2
    by_cases e : (factOf g s).isSome = true
    · obtain ⟨f, hf⟩ := Option.isSome_iff_exists.mp e
      have hm := List.mem_of_find?_eq_some hf
      have hn := List.find?_some hf
      exact ⟨f, hm, by simpa using hn⟩
    · simp [e] at h2

/-- **An accepted download has the key inputs of every store key.** -/
theorem ciRun_accepted_req {r : CiRun} {g : Got} (h : (ciRun r (some g)).refusals = []) :
    ∀ c ∈ (ciRun r (some g)).targets, c.req.isSome := by
  have hg := ciRun_accepted_got h
  rw [ciRun_accepted_targets h] at hg ⊢
  intro c hcm
  have hgc := (hg c hcm).2
  simp only [List.mem_map] at hcm
  obtain ⟨t, ht, rfl⟩ := hcm
  simp only [ciTargets, List.mem_filter, List.any_eq_true, decide_eq_true_eq] at ht
  obtain ⟨_, p, hp, hpt⟩ := ht
  have hs : p.1 ∈ shardsOf r t := hpt ▸ shardsOf_of_job (s := p.1) (j := p.2) hp
  obtain ⟨f, hf, hfn⟩ := hgc p.1 hs
  have hfo : (factOf g p.1).isSome := by
    simp only [factOf, List.find?_isSome]
    exact ⟨f, hf, by simp [hfn]⟩
  obtain ⟨f', hf'⟩ := Option.isSome_iff_exists.mp hfo
  have hne : factsOf r g t ≠ [] := by
    intro e
    have : f' ∈ factsOf r g t := List.mem_filterMap.mpr ⟨p.1, hs, hf'⟩
    simp [e] at this
  simp only [ciTarget, Option.bind_some]
  cases hfs : factsOf r g t with
  | nil => exact absurd hfs hne
  | cons _ _ => simp

/-- The targets of a run are pairwise distinct. -/
theorem ciTargets_nodup (r : CiRun) : (ciTargets r).Nodup :=
  List.Nodup.sublist List.filter_sublist (by decide)

/-- **One store key per target:** the store keys of a run have pairwise distinct targets. -/
theorem ciRun_targets_nodup (r : CiRun) (got : Option Got) : ((ciRun r got).targets.map (·.target)).Nodup := by
  simp only [ciRun]
  split
  · rw [List.map_map]
    have : (CiTarget.target ∘ ciTarget r got) = id := by funext t; rfl
    rw [this, List.map_id]
    exact ciTargets_nodup r
  · exact List.nodup_nil

/-- Every shard filed under a store key measured that key's target. -/
theorem ciRun_shard_target {r : CiRun} {got : Option Got} {c : CiTarget} {s : Shard}
    (hc : c ∈ (ciRun r got).targets) (hs : s ∈ c.shards) : s.target = c.target := by
  simp only [ciRun] at hc
  split at hc
  · simp only [List.mem_map] at hc
    obtain ⟨t, _, rfl⟩ := hc
    exact (mem_shardsOf hs).2
  · simp at hc

/-- The key inputs of a store key name that key's target. -/
theorem ciRun_req_target {r : CiRun} {got : Option Got} {c : CiTarget} {q : Req}
    (hc : c ∈ (ciRun r got).targets) (hq : c.req = some q) : q.target = c.target := by
  simp only [ciRun] at hc
  split at hc
  · simp only [List.mem_map] at hc
    obtain ⟨t, _, rfl⟩ := hc
    simp only [ciTarget, Option.bind_eq_some_iff, Option.map_eq_some_iff] at hq
    obtain ⟨_, _, _, _, rfl⟩ := hq
    rfl
  · simp at hc

/-- **Two artifacts with different targets get different keys:** shards of different targets are filed under store keys
whose key pairs (the input of the key hash) differ.
-/
theorem ciRun_key_ne {r : CiRun} {got : Option Got} {c c' : CiTarget} {s s' : Shard} {q q' : Req}
    (hc : c ∈ (ciRun r got).targets) (hc' : c' ∈ (ciRun r got).targets) (hs : s ∈ c.shards) (hs' : s' ∈ c'.shards)
    (ht : s.target ≠ s'.target) (hq : c.req = some q) (hq' : c'.req = some q') : keyPairs q ≠ keyPairs q' := by
  apply keyPairs_target_ne
  rw [ciRun_req_target hc hq, ciRun_req_target hc' hq', ← ciRun_shard_target hc hs, ← ciRun_shard_target hc' hs']
  exact ht

/-- **The key pairs of a run's store keys are pairwise distinct.** -/
theorem ciRun_keys_nodup (r : CiRun) (got : Option Got) :
    (((ciRun r got).targets.filterMap (·.req)).map keyPairs).Nodup := by
  have hn := ciRun_targets_nodup r got
  have hmem : ∀ c ∈ (ciRun r got).targets, ∀ q, c.req = some q → q.target = c.target :=
    fun c hc q hq => ciRun_req_target hc hq
  generalize (ciRun r got).targets = cs at hn hmem
  unfold List.Nodup at *
  rw [List.pairwise_map] at hn ⊢
  rw [List.pairwise_filterMap]
  refine List.Pairwise.imp_of_mem ?_ hn
  intro a b ha hb hab q hq q' hq'
  apply keyPairs_target_ne
  rw [hmem a ha q hq, hmem b hb q' hq']
  exact hab

/-! ## Examples -/

/-- A sha used by the examples. -/
private def exSha : String := "0123456789abcdef0123456789abcdef01234567"

/-- A complete `both` run with two shards per target. -/
private def exRun : CiRun :=
  { runId := "42", workflow := "chromium-counts", status := "completed", conclusion := "success", headSha := exSha,
    jobs := [⟨"plan", "success"⟩, ⟨"counts (original, r2)", "success"⟩, ⟨"counts (original, r1)", "success"⟩,
             ⟨"counts (rewrite, r1)", "success"⟩, ⟨"counts (rewrite, r2)", "success"⟩, ⟨"classify", "success"⟩] }

/-- The facts of a downloaded shard. -/
private def exFact (name search : String) : ShardFacts :=
  { name := name, profile := "swipe-v1", image := "runner:ubuntu-24.04-arm", search := search, target := none }

/-- The download of `exRun`. -/
private def exGot : Got :=
  { artifacts := ["chromium-counts-original-r1", "chromium-counts-original-r2"].map (exFact · "") ++
      ["chromium-counts-rewrite-r1", "chromium-counts-rewrite-r2"].map (exFact · "?preset=strip-demo"),
    classes := ["original", "rewrite"] }

#guard (ciRun exRun none).refusals == []
#guard (ciRun exRun none).targets.map (fun c => (c.target, c.shards.map Shard.artifact, c.req.isSome)) ==
  [(.original, ["chromium-counts-original-r1", "chromium-counts-original-r2"], false),
   (.rewrite, ["chromium-counts-rewrite-r1", "chromium-counts-rewrite-r2"], false)]
#guard (ciRun exRun (some exGot)).refusals == []
#guard (ciRun exRun (some exGot)).targets.map (fun c => c.req.map fun q => (q.preset, q.profile, q.sha == exSha)) ==
  [some ("original", "swipe-v1", true), some ("strip-demo", "swipe-v1", true)]
#guard (ciRun { exRun with conclusion := "failure" } none).refusals == ["run 42 concluded failure, not success"]
#guard (ciRun { exRun with conclusion := "failure" } none).targets.isEmpty
#guard (ciRun { exRun with status := "in_progress", conclusion := "" } none).refusals == ["run 42 is in_progress, not completed"]
#guard (ciRun { exRun with workflow := "webkit-sim" } none).refusals == ["run 42 is workflow webkit-sim, not chromium-counts"]
#guard (ciRun { exRun with jobs := [⟨"plan", "success"⟩] } none).refusals == ["run 42 has no counts shard jobs"]
#guard (ciRun { exRun with jobs := [⟨"counts (original, r1)", ""⟩] } none).refusals ==
  ["shard chromium-counts-original-r1: job unfinished"]
#guard (ciRun exRun (some { exGot with artifacts := exGot.artifacts.take 3 })).refusals ==
  ["missing shard artifact chromium-counts-rewrite-r2"]
#guard (ciRun exRun (some { exGot with classes := ["original"] })).refusals == ["missing chromium-classes/rewrite"]
#guard (ciRun exRun (some { exGot with artifacts := exGot.artifacts.set 1 (exFact "chromium-counts-original-r2" "?x") })).refusals ==
  ["original shards disagree on profile, query, target or image"]
#guard (ciRun exRun (some { exGot with artifacts := exGot.artifacts.set 0 { exFact "chromium-counts-original-r1" "" with target := some "rewrite" } })).refusals ==
  ["original shards disagree on profile, query, target or image"]

/-! ## The download of a run that `fw run` files

`gh run download <id>` without a pattern fetches every artifact of the run, the build outputs included (`chromium-image`
209 MB, `fwcore` 158 MB, `site-dist` 27 MB; MEASURED 2026-10-25, runs 40153927556, 40153920231, 40156382719: 400 MB, 92 s,
423 s, 122 s). The WebKit run 40153925235 had 210 MB and died at the 40 s bound. Nothing reads those outputs from the store
(they are rebuilt from the commit), so the download fetches only the files the store keeps, one `Piece` per artifact,
each with a timeout sized from its own byte bound. -/

/-- The sizes of the download rule, in one record (one start-time constant, not seven: `Fw.Lint.InitCost` counts them).
`maxHoldMs` is the longest a charged gh call may hold the budget lock, `Fw.Obs.Timing.defaultCallTimeoutMs` (the runner
test checks the two equal). `baseMs` is the time a piece gets before any byte moves (the listing and the redirect),
`msPerKb` the time per kilobyte (2 ms is 0.5 MB/s, half the slowest rate measured, 0.95 MB/s on run 40153920231), `cost`
the requests one piece is charged (the listing and the redirect to blob storage). The `*Kb` fields bound the bytes of
a chromium-counts shard (largest seen 1844 KB), of `chromium-classes` and `telemetry-*` (seen 40 and 36 KB) and of a
webkit-sim VM (largest seen 11856 KB). -/
structure DlRule where
  maxHoldMs : Nat
  baseMs : Nat
  msPerKb : Nat
  cost : Nat
  countsKb : Nat
  smallKb : Nat
  simKb : Nat

/-- The download rule. -/
def dlRule : DlRule :=
  { maxHoldMs := 40000, baseMs := 15000, msPerKb := 2, cost := 2, countsKb := 2000, smallKb := 100, simKb := 12500 }

/-- One download call: a `gh run download --pattern` glob, the bound on its bytes, its timeout and its charge. -/
structure Piece where
  pattern : String
  kb : Nat
  timeoutMs : Nat
  cost : Nat
deriving Repr, DecidableEq

/-- A piece of at most `kb` kilobytes. -/
def piece (pattern : String) (kb : Nat) : Piece :=
  { pattern, kb, timeoutMs := dlRule.baseMs + dlRule.msPerKb * kb, cost := dlRule.cost }

/-- The repetition numbers `1` .. `n`, as digits. -/
def reps (n : Nat) : List String := (List.range n).map fun i => toString (i + 1)

/-- What `fw run` downloads for a run of `n` repetitions (chromium: of `target`; webkit: `n` VMs): the shard artifacts, then
the class directories (chromium only) and the telemetry. Build outputs are not in the list. -/
def downloadPieces (e : Engine) (t : Target) (n : Nat) : List Piece :=
  match e with
  | .chromium => (reps n).map (fun r => piece ("chromium-counts-" ++ t.name ++ "-r" ++ r) dlRule.countsKb) ++
      [piece "chromium-classes" dlRule.smallKb, piece "telemetry-*" dlRule.smallKb]
  | .webkit => (reps n).map (fun r => piece ("webkit-sim-r" ++ r) dlRule.simKb) ++ [piece "telemetry-*" dlRule.smallKb]

/-- Charge of the one retry of a piece that timed out: its full charge when no response of the first attempt was seen, one
request (the listing again) when `served` responses arrived, since the first attempt's charge already covers the redirect. -/
def retryCost (c served : Nat) : Nat := if served = 0 then c else 1

/-- **Every piece fits the lock hold bound**, so a download never keeps the budget lock longer than a listing does. -/
theorem piece_fits_hold (e : Engine) (t : Target) (n : Nat) :
    ∀ p ∈ downloadPieces e t n, p.timeoutMs ≤ dlRule.maxHoldMs := by
  intro p hp
  cases e <;> simp only [downloadPieces, List.mem_append, List.mem_map, List.mem_cons, List.not_mem_nil, or_false] at hp <;>
    rcases hp with ⟨r, _, rfl⟩ | rfl | rfl <;>
    simp [piece, dlRule]
theorem piece_fits_hold_webkit_tight : (piece "x" dlRule.simKb).timeoutMs = dlRule.maxHoldMs := by decide

/-- **A timeout is sized from the bytes:** a piece takes `dlRule.baseMs` plus `dlRule.msPerKb` per kilobyte. -/
theorem piece_timeout (pattern : String) (kb : Nat) : (piece pattern kb).timeoutMs = dlRule.baseMs + dlRule.msPerKb * kb := rfl

/-- **The shard artifacts are all downloaded:** the artifact of each shard `⟨t, r<k>⟩` of a run of `n` repetitions
(`Shard.artifact`) is the pattern of a piece. -/
theorem shard_downloaded (t : Target) (n : Nat) (i : Nat) (hi : i < n) :
    (Shard.artifact ⟨t, toString (i + 1)⟩) ∈ (downloadPieces .chromium t n).map (·.pattern) := by
  simp only [downloadPieces, List.map_append, List.map_map, List.mem_append]
  left
  simp only [reps, List.map_map, List.mem_map, List.mem_range, Function.comp]
  exact ⟨i, hi, rfl⟩

/-- **No build output is downloaded:** the three big artifacts of a run are not a piece. -/
theorem build_outputs_skipped (e : Engine) (t : Target) (n : Nat) :
    ∀ p ∈ downloadPieces e t n, p.pattern ≠ "chromium-image" ∧ p.pattern ≠ "fwcore" ∧ p.pattern ≠ "site-dist" := by
  intro p hp
  cases e <;> simp only [downloadPieces, List.mem_append, List.mem_map, List.mem_cons, List.not_mem_nil, or_false] at hp <;>
    rcases hp with ⟨r, _, rfl⟩ | rfl | rfl <;> simp only [piece] <;>
    refine ⟨?_, ?_, ?_⟩ <;> intro h <;> first | (have := congrArg (fun s => s.toList.take 10) h; simp [String.toList_append] at this) | (revert h; decide)

/-- **A retry is never charged more than the call:** one request after a response was seen, the full charge before. -/
theorem retryCost_le (c served : Nat) (h : 1 ≤ c) : retryCost c served ≤ c := by
  unfold retryCost; split <;> omega

theorem retryCost_served (c served : Nat) (h : 0 < served) : retryCost c served = 1 := by
  simp [retryCost, Nat.pos_iff_ne_zero.mp h]

theorem retryCost_unserved (c : Nat) : retryCost c 0 = c := by simp [retryCost]

#guard (downloadPieces .webkit .rewrite 3).map (·.pattern) == ["webkit-sim-r1", "webkit-sim-r2", "webkit-sim-r3", "telemetry-*"]
#guard (downloadPieces .webkit .rewrite 3).map (·.timeoutMs) == [40000, 40000, 40000, 15200]
#guard (downloadPieces .chromium .original 2).map (·.pattern) ==
  ["chromium-counts-original-r1", "chromium-counts-original-r2", "chromium-classes", "telemetry-*"]
#guard (downloadPieces .chromium .rewrite 1).map (·.timeoutMs) == [19000, 15200, 15200]
#guard 11856 ≤ dlRule.simKb && 1844 ≤ dlRule.countsKb
#guard retryCost 2 0 == 2 && retryCost 2 1 == 1

end Fw.Store
