import Std.Data.String.ToNat
/-!
# The artifact store: layout, run manifests and the `fw run` plan

Spec of what `fw run` stores and plans (PLAN §10.1). Pure; the JSON glue is `Fw.Wire.Store`.

**Layout** (under `.fw-console/store/`, gitignored with the console state):

```
objects/<d[0..2]>/<d[2..64]>      the bytes of one artifact; d = its sha256, lowercase hex
runs/<runKey>/manifest.json       one manifest per run: what was measured and where the bytes are
```

An object is **content-addressed**: its path is a function of the sha256 of its bytes
(`objectPath`, injective on 64-hex digests). A run manifest names the engine, the target (original site
or rewrite), preset, flags, profile, git sha, the image the run executed in and its run count, and lists its artifacts as
`{name, digest, bytes}` sorted by name. The digest of the run's identity (the `runKey`) is the
sha256 of the canonical JSON of `keyPairs`; the hash is computed by the caller (L3 assumption: sha256
has no collisions on what we hash), while `keyPairs_inj` proves that distinct configurations
never share the *input* of the hash.

**Plan.** `plan` turns a request (target, preset, flags, engines, profile, git sha, image) into one job
per distinct engine in canonical order, each with the CI workflow it dispatches, its inputs and the
reason it cannot run yet (a workflow without an input for something the request needs). Nothing
measures on the developer's machine: a job is a `gh workflow run` on CI.
-/
namespace Fw.Store

/-! ## Engines -/

/-- The two engines of the study. -/
inductive Engine where
  | chromium
  | webkit
deriving DecidableEq, Repr

/-- Wire name of an engine. -/
def Engine.name : Engine → String
  | .chromium => "chromium"
  | .webkit => "webkit"

/-- An engine from its wire name. -/
def Engine.ofName : String → Option Engine
  | "chromium" => some .chromium
  | "webkit" => some .webkit
  | _ => none

/-- Names round-trip. -/
theorem Engine.ofName_name (e : Engine) : Engine.ofName e.name = some e := by
  cases e <;> rfl

/-- Names are injective. -/
theorem Engine.name_inj {e e' : Engine} (h : e.name = e'.name) : e = e' := by
  cases e <;> cases e' <;> first | rfl | (exact absurd h (by decide))

/-- The engines in canonical order, restricted to those requested: no duplicates, chromium first. -/
def canonEngines (es : List Engine) : List Engine :=
  [Engine.chromium, Engine.webkit].filter (fun e => decide (e ∈ es))

/-- Canonical engines are exactly the requested ones. -/
theorem mem_canonEngines (es : List Engine) (e : Engine) : e ∈ canonEngines es ↔ e ∈ es := by
  cases e <;> simp [canonEngines]

/-- Canonical engines have no duplicates. -/
theorem canonEngines_nodup (es : List Engine) : (canonEngines es).Nodup := by
  unfold canonEngines
  exact List.Nodup.sublist (List.filter_sublist) (by decide)

/-! ## Targets -/

/-- The page a run measures: the original site (the unmodified snapshot) or the rewrite (`apps/site`). -/
inductive Target where
  | original
  | rewrite
deriving DecidableEq, Repr

/-- Wire name of a target (the values of the `target` input of chromium-counts.yml). -/
def Target.name : Target → String
  | .original => "original"
  | .rewrite => "rewrite"

/-- A target from its wire name (`both`, which the workflow also accepts, is not one target). -/
def Target.ofName : String → Option Target
  | "original" => some .original
  | "rewrite" => some .rewrite
  | _ => none

/-- Target names round-trip. -/
theorem Target.ofName_name (t : Target) : Target.ofName t.name = some t := by
  cases t <;> rfl

/-- A target is the target of its name. -/
theorem Target.name_ofName {s : String} {t : Target} (h : Target.ofName s = some t) : t.name = s := by
  unfold Target.ofName at h
  split at h <;> first | (cases h; rfl) | cases h

/-- Target names are injective. -/
theorem Target.name_inj {t t' : Target} (h : t.name = t'.name) : t = t' := by
  cases t <;> cases t' <;> first | rfl | (exact absurd h (by decide))

#guard Target.ofName "both" == none

/-- The default preset name (with no flags and `defaultProfile` it is the default configuration). -/
def defaultPreset : String := "original"

/-- The configuration fits the target: presets and flags exist only in the rewrite, so the original target takes the
default preset and no flag (chromium-counts.yml refuses `target=original` with a preset or flags).
-/
def targetFits (target preset : String) (fw : List (String × String)) : Bool :=
  target != "original" || (preset == defaultPreset && fw.isEmpty)

#guard targetFits "rewrite" "strip-demo" [("a", "b")] && targetFits "original" "original" []
#guard !targetFits "original" "strip-demo" [] && !targetFits "original" "original" [("a", "b")]

/-! ## Digests and object paths -/

/-- A lowercase hexadecimal digit. -/
def isHexChar (c : Char) : Bool := c.isDigit || (decide ('a' ≤ c) && decide (c ≤ 'f'))

/-- A lowercase hex string of exactly `n` digits. -/
def isHex (n : Nat) (s : String) : Bool := s.toList.length == n && s.toList.all isHexChar

/-- The characters of an object path: `objects/`, the first two digits, `/`, the other digits. -/
def pathChars (d : List Char) : List Char :=
  "objects/".toList ++ (d.take 2 ++ '/' :: d.drop 2)

/-- The path of an object, relative to the store root. -/
def objectPath (d : String) : String := String.ofList (pathChars d.toList)

/-- **Content addressing is injective.** Two digests of at least two digits with the same path are
the same digest, so two different byte strings (different sha256) never share a file.
-/
theorem objectPath_inj {d d' : String} (h2 : 2 ≤ d.toList.length) (h2' : 2 ≤ d'.toList.length)
    (h : objectPath d = objectPath d') : d = d' := by
  have hl := congrArg String.toList h
  simp only [objectPath, String.toList_ofList, pathChars] at hl
  have hl := List.append_cancel_left hl
  have hlen : (d.toList.take 2).length = (d'.toList.take 2).length := by
    simp; omega
  obtain ⟨h1, h3⟩ := List.append_inj hl hlen
  have h3 := (List.cons.inj h3).2
  have : d.toList = d'.toList := by
    rw [← List.take_append_drop 2 d.toList, ← List.take_append_drop 2 d'.toList, h1, h3]
  exact String.toList_inj.mp this

#guard objectPath "ab0123" == "objects/ab/0123"
#guard isHex 4 "09af"
#guard !isHex 4 "09aF"
#guard !isHex 4 "09a"

/-! ## Names and manifests -/

/-- A short identifier: 1 to 64 characters from `a-z 0-9 . _ -`, starting with a letter or digit.
Colons, commas, slashes and spaces are excluded, which is what keeps flag lists unambiguous.
-/
def isId (s : String) : Bool :=
  let cs := s.toList
  decide (0 < cs.length) && decide (cs.length ≤ 64) &&
    (match cs with
     | c :: _ => c.isDigit || (decide ('a' ≤ c) && decide (c ≤ 'z'))
     | [] => false) &&
    cs.all (fun c => c.isDigit || (decide ('a' ≤ c) && decide (c ≤ 'z')) || c == '.' || c == '_' || c == '-')

/-- A flag part: like `isId`, but letters after the first may also be upper case, because the
site's part ids are camelCase (`nav.hitTest`).
-/
def isPart (s : String) : Bool :=
  let cs := s.toList
  decide (0 < cs.length) && decide (cs.length ≤ 64) &&
    (match cs with
     | c :: _ => c.isDigit || (decide ('a' ≤ c) && decide (c ≤ 'z'))
     | [] => false) &&
    cs.all (fun c => c.isAlphanum || c == '.' || c == '_' || c == '-')

#guard isPart "nav.hitTest" && isPart "hero.countdown" && !isId "nav.hitTest"
#guard !isPart "Nav" && !isPart "" && !isPart "a:b" && !isPart "a,b" && !isPart "a/b"

/-- An artifact name inside a run: `/`-separated segments of `A-Za-z0-9._-`, none empty, `.` or `..`,
so a name can never leave the run's directory.
-/
def safeName (n : String) : Bool :=
  !n.isEmpty && (n.splitOn "/").all fun s =>
    !s.isEmpty && s != "." && s != ".." &&
      s.toList.all (fun c => c.isAlphanum || c == '.' || c == '_' || c == '-')

/-- **A safe name has no `..` segment.** -/
theorem safeName_no_dotdot {n : String} (h : safeName n = true) :
    ∀ s ∈ n.splitOn "/", s ≠ ".." := by
  intro s hs
  simp only [safeName, Bool.and_eq_true, List.all_eq_true] at h
  have := (h.2 s hs)
  simp only [bne_iff_ne, ne_eq] at this
  exact this.1.2

#guard safeName "counts/run-1.json"
#guard !safeName "../x"
#guard !safeName "a//b"
#guard !safeName "/abs"
#guard !safeName "a/./b"

/-- One stored artifact of a run. -/
structure Entry where
  name : String
  digest : String
  bytes : Nat
deriving Repr, DecidableEq

/-- What one run measured and where its bytes are, as read from the wire: the engine and the target are names (strings
checked by `problems`), the flags are (part, variant) pairs.
-/
structure Manifest where
  engine : String
  target : String
  preset : String
  fw : List (String × String)
  profile : String
  gitSha : String
  image : String
  runs : Nat
  runId : String
  entries : List Entry
deriving Repr

/-- The flags are strictly increasing by part, so a part appears at most once and the list is canonical. -/
def flagsOk (fw : List (String × String)) : Bool :=
  decide (fw.Pairwise (fun a b => a.1 < b.1))

/-- The flag list is free of duplicate parts when strictly increasing. -/
theorem flagsOk_nodup {fw : List (String × String)} (h : flagsOk fw = true) :
    (fw.map (·.1)).Nodup := by
  have h' : fw.Pairwise (fun a b => a.1 < b.1) := by simpa [flagsOk] using h
  rw [List.nodup_iff_pairwise_ne] -- Pairwise (≠) on the mapped list
  rw [List.pairwise_map]
  exact h'.imp (fun {a b} hab => fun e => String.lt_irrefl _ (e ▸ hab))

/-- An image: a container digest `sha256:<64 hex>` or a CI runner label `runner:<id>`. -/
def imageOk (s : String) : Bool :=
  (s.startsWith "sha256:" && isHex 64 (s.drop 7).toString) ||
  (s.startsWith "runner:" && isId (s.drop 7).toString)

/-- Strictly increasing entry names (sorted, no duplicate name). -/
def entriesSorted (es : List Entry) : Bool := decide (es.Pairwise (fun a b => a.name < b.name))

/-- Sorted entries have distinct names. -/
theorem entriesSorted_nodup {es : List Entry} (h : entriesSorted es = true) :
    (es.map (·.name)).Nodup := by
  have h' : es.Pairwise (fun a b => a.name < b.name) := by simpa [entriesSorted] using h
  rw [List.nodup_iff_pairwise_ne, List.pairwise_map]
  exact h'.imp (fun {a b} hab => fun e => String.lt_irrefl _ (e ▸ hab))

/-- Every problem of a manifest, as a message (empty = valid). -/
def Manifest.problems (m : Manifest) : List String :=
  (if (Engine.ofName m.engine).isSome then [] else ["engine: unknown"]) ++
  (if (Target.ofName m.target).isSome then [] else ["target: not original or rewrite"]) ++
  (if targetFits m.target m.preset m.fw then [] else ["target: original takes no preset or flags"]) ++
  (if isId m.preset then [] else ["preset: not an id"]) ++
  (if isId m.profile then [] else ["profile: not an id"]) ++
  (if flagsOk m.fw then [] else ["fw: parts must be strictly increasing"]) ++
  (if m.fw.all (fun p => isPart p.1 && isId p.2) then [] else ["fw: part and variant must be ids"]) ++
  (if isHex 40 m.gitSha then [] else ["gitSha: not 40 hex digits"]) ++
  (if imageOk m.image then [] else ["image: not sha256:<64 hex> or runner:<id>"]) ++
  (if !m.runId.isEmpty && m.runId.toList.all Char.isDigit then [] else ["runId: not digits"]) ++
  (if entriesSorted m.entries then [] else ["entries: names must be strictly increasing"]) ++
  (if m.entries.all (fun e => safeName e.name) then [] else ["entries: name escapes the run directory"]) ++
  (if m.entries.all (fun e => isHex 64 e.digest) then [] else ["entries: digest not 64 hex digits"]) ++
  (if 1 ≤ m.runs then [] else ["runs: not a positive count"])

/-- A manifest is valid when it has no problem. -/
def Manifest.valid (m : Manifest) : Bool := m.problems.isEmpty

/-- A valid manifest names a known engine. -/
theorem Manifest.valid_engine {m : Manifest} (h : m.valid = true) :
    ∃ e, Engine.ofName m.engine = some e := by
  simp only [valid, problems, List.isEmpty_iff, List.append_eq_nil_iff] at h
  have h1 := h.1.1.1.1.1.1.1.1.1.1.1.1.1
  by_cases hs : (Engine.ofName m.engine).isSome
  · exact Option.isSome_iff_exists.mp hs
  · simp [hs] at h1

/-- A valid manifest names a known target, and its configuration fits that target. -/
theorem Manifest.valid_target {m : Manifest} (h : m.valid = true) :
    (∃ t, Target.ofName m.target = some t) ∧ targetFits m.target m.preset m.fw = true := by
  simp only [valid, problems, List.isEmpty_iff, List.append_eq_nil_iff] at h
  have h1 := h.1.1.1.1.1.1.1.1.1.1.1.1.2
  have h2 := h.1.1.1.1.1.1.1.1.1.1.1.2
  constructor
  · by_cases hs : (Target.ofName m.target).isSome
    · exact Option.isSome_iff_exists.mp hs
    · simp [hs] at h1
  · by_cases hs : targetFits m.target m.preset m.fw = true
    · exact hs
    · simp [hs] at h2

/-- A valid manifest has sorted, hence name-distinct, entries with 64-hex digests. -/
theorem Manifest.valid_entries {m : Manifest} (h : m.valid = true) :
    (m.entries.map (·.name)).Nodup ∧ ∀ e ∈ m.entries, isHex 64 e.digest = true := by
  simp only [valid, problems, List.isEmpty_iff, List.append_eq_nil_iff] at h
  constructor
  · apply entriesSorted_nodup
    by_cases hs : entriesSorted m.entries = true
    · exact hs
    · have := h.1.1.1.2; simp [hs] at this
  · intro e he
    have h3 := h.1.2
    by_cases hs : (m.entries.all (fun e => isHex 64 e.digest)) = true
    · simp only [List.all_eq_true] at hs; exact hs e he
    · simp [hs] at h3

/-! ## The identity of a run -/

/-- What a run's identity depends on. `target` selects the page (original or rewrite), `preset` and the flags the
site configuration, `profile` the scroll script, `sha` the code, `image` the browser build and machine, `runs` the
independent repetitions (Chromium shards, WebKit VMs).
-/
structure Req where
  engine : Engine
  target : Target
  preset : String
  fw : List (String × String)
  profile : String
  sha : String
  image : String
  runs : Nat

/-- Flatten flags to key pairs: each part and each variant is its own pair. -/
def flagPairs (fw : List (String × String)) : List (String × String) :=
  fw.flatMap fun p => [("fw", p.1), ("fwv", p.2)]

/-- Flattening flags loses nothing. -/
theorem flagPairs_inj : ∀ {a b : List (String × String)}, flagPairs a = flagPairs b → a = b
  | [], [], _ => rfl
  | [], _ :: _, h => by simp [flagPairs] at h
  | _ :: _, [], h => by simp [flagPairs] at h
  | (p, v) :: a, (p', v') :: b, h => by
    simp only [flagPairs, List.flatMap_cons, List.cons_append, List.nil_append, List.cons.injEq,
      Prod.mk.injEq] at h
    obtain ⟨⟨_, h1⟩, ⟨_, h2⟩, h3⟩ := h
    have := flagPairs_inj (a := a) (b := b) h3
    rw [h1, h2, this]

/-- The pairs whose canonical JSON the caller hashes to get the run key.

Version 2 added the target (version 1 keys had none, so an original and a rewrite run shared one key). Version 3 added
the run count (version 2 keys had none, so a 1-VM and a 3-VM WebKit run shared one key).
-/
def keyPairs (r : Req) : List (String × String) :=
  [("v", "3"), ("engine", r.engine.name), ("target", r.target.name), ("preset", r.preset), ("profile", r.profile),
   ("sha", r.sha), ("image", r.image), ("runs", toString r.runs)] ++ flagPairs r.fw

/-- **Distinct configurations never share the input of the key hash.** -/
theorem keyPairs_inj {r r' : Req} (h : keyPairs r = keyPairs r') : r = r' := by
  simp only [keyPairs, List.cons_append, List.nil_append, List.cons.injEq, Prod.mk.injEq] at h
  obtain ⟨_, ⟨_, he⟩, ⟨_, ht⟩, ⟨_, hp⟩, ⟨_, hr⟩, ⟨_, hs⟩, ⟨_, hi⟩, ⟨_, hn⟩, hf⟩ := h
  have hf := flagPairs_inj hf
  have hn : r.runs = r'.runs := Nat.repr_injective hn
  cases r; cases r'
  simp only at *
  rw [Engine.name_inj he, Target.name_inj ht, hp, hr, hs, hi, hn, hf]

/-- **Different targets give different keys:** an original run and a rewrite run never share a key, whatever else they
have in common.
-/
theorem keyPairs_target_ne {r r' : Req} (h : r.target ≠ r'.target) : keyPairs r ≠ keyPairs r' :=
  fun hk => h (congrArg Req.target (keyPairs_inj hk))

/-- **Different run counts give different keys:** a 2-VM and a 3-VM run never share a key, whatever else they have in
common.
-/
theorem keyPairs_runs_ne {r r' : Req} (h : r.runs ≠ r'.runs) : keyPairs r ≠ keyPairs r' :=
  fun hk => h (congrArg Req.runs (keyPairs_inj hk))

/-- **No version 3 key is a version 2 key:** a run stored before the run count entered the key (every WebKit run then
measured 1 VM) is never a cache hit for a request planned now.
-/
theorem keyPairs_ne_v2 (r : Req) (rest : List (String × String)) : keyPairs r ≠ ("v", "2") :: rest := by
  simp [keyPairs]

/-- The run identity a manifest records, when its engine and target are known names. -/
def Manifest.req (m : Manifest) : Option Req :=
  match Engine.ofName m.engine, Target.ofName m.target with
  | some e, some t => some { engine := e, target := t, preset := m.preset, fw := m.fw, profile := m.profile,
                             sha := m.gitSha, image := m.image, runs := m.runs }
  | _, _ => none

/-- **A valid manifest has a key**, and its key records the manifest's target name. -/
theorem Manifest.valid_req {m : Manifest} (h : m.valid = true) :
    ∃ r, m.req = some r ∧ ("target", m.target) ∈ keyPairs r := by
  obtain ⟨e, he⟩ := Manifest.valid_engine h
  obtain ⟨⟨t, ht⟩, _⟩ := Manifest.valid_target h
  refine ⟨{ engine := e, target := t, preset := m.preset, fw := m.fw, profile := m.profile, sha := m.gitSha,
            image := m.image, runs := m.runs }, by simp [Manifest.req, he, ht], ?_⟩
  simp [keyPairs, Target.name_ofName ht]

/-! ## The plan of `fw run` -/

/-- A run request as the user typed it, before validation: engine names may be unknown or repeated, and the image
pins are an association list from engine name to image (first match wins, unknown names allowed until `reqProblems`).

The target is a name too (checked by `reqProblems`).
-/
structure Request where
  target : String
  preset : String
  fw : List (String × String)
  engines : List String
  profile : String
  runs : Nat
  sha : String
  images : List (String × String)

/-- The default scroll profile. -/
def defaultProfile : String := "swipe-v1"

/-- The image an engine's workflow runs on unless the request pins another (a container digest). -/
def defaultImage : Engine → String
  | .chromium => "runner:ubuntu-24.04-arm"
  | .webkit => "runner:xcode-27"

/-- The image of a job: the request's pin for that engine, else the default. -/
def imageOf (q : Request) (e : Engine) : String :=
  ((q.images.find? (fun p => p.1 == e.name)).map (·.2)).getD (defaultImage e)

/-- The measurement lanes a dispatch can start: the two count workflows (one per engine), the breakpoint gate and the
trajectory probe. -/
inductive Lane where
  | chromiumCounts
  | webkitSim
  | breakpointGate
  | trajectory
  deriving DecidableEq

/-- The lanes, in the order of the check script. -/
def Lane.all : List Lane := [.chromiumCounts, .webkitSim, .breakpointGate, .trajectory]

/-- The workflow file of a lane in `.github/workflows/`. -/
def Lane.file : Lane → String
  | .chromiumCounts => "chromium-counts.yml"
  | .webkitSim => "webkit-sim.yml"
  | .breakpointGate => "breakpoint-gate.yml"
  | .trajectory => "trajectory-probe.yml"

/-- The `workflow_dispatch` inputs a lane's workflow declares, in file order. This is the one canonical table: the check
`scripts/LaneInputs.lean --check` (a stage of `lean/scripts/check.sh`) parses the three files and fails when a list differs.
-/
def Lane.inputs : Lane → List String
  | .chromiumCounts => ["profile", "runs", "target", "preset", "fw", "only", "image_run", "nonce"]
  | .webkitSim => ["vms", "sessions", "fresh_boot", "experiment", "arms", "reps", "lag", "cost", "target", "preset", "fw", "fault", "nonce"]
  | .breakpointGate => ["engines", "runs", "free", "times", "fw", "preset", "parts", "nonce"]
  | .trajectory => ["engines", "fw", "preset", "widths", "diagnostic", "nonce"]

/-- The lane that measures an engine's counts. -/
def Lane.ofEngine : Engine → Lane
  | .chromium => .chromiumCounts
  | .webkit => .webkitSim

/-- The CI workflow file that measures an engine. -/
def workflowOf (e : Engine) : String := (Lane.ofEngine e).file

/-- The `workflow_dispatch` inputs the workflow of an engine declares (`Lane.inputs`). -/
def workflowInputs (e : Engine) : List String := (Lane.ofEngine e).inputs

#guard workflowOf .webkit == "webkit-sim.yml"
#guard workflowOf .chromium == "chromium-counts.yml"

/-- The `fw` dispatch input: the flags as `part:variant`, joined by commas (empty for no flag). -/
def fwInput (fw : List (String × String)) : String :=
  ",".intercalate (fw.map fun p => p.1 ++ ":" ++ p.2)

#guard fwInput [] == ""
#guard fwInput [("hero.countdown", "strip"), ("nav.hitTest", "hit-skip")] == "hero.countdown:strip,nav.hitTest:hit-skip"

/-- The request fields that differ from a fixed workflow's built-in configuration (the original site, the default
profile, preset and flags), so the workflow must accept them as inputs.
-/
def needs (q : Request) : List String :=
  (if q.target == Target.original.name then [] else ["target"]) ++
  (if q.profile == defaultProfile then [] else ["profile"]) ++
  (if q.preset == defaultPreset then [] else ["preset"]) ++
  (if q.fw.isEmpty then [] else ["fw"])

/-- The dispatch inputs: the engine's own, from the request. Chromium takes the profile, the run count (in decimal),
the target (always sent, so the workflow never falls back to its default `both`), the preset and the flags
(`image_run` keeps its default); WebKit takes the run count as its VM count `vms` (in decimal), the target, the preset
and the flags (webkit-sim has no profile input, so a profile other than the default is blocked; `sessions` keeps its
default of one per VM).
-/
def dispatchInputs (e : Engine) (q : Request) : List (String × String) :=
  match e with
  | .chromium => [("profile", q.profile), ("runs", toString q.runs), ("target", q.target), ("preset", q.preset),
                  ("fw", fwInput q.fw)]
  | .webkit => [("vms", toString q.runs), ("target", q.target), ("preset", q.preset), ("fw", fwInput q.fw)]

/-- **Chromium is told the target:** its dispatch inputs carry the request's target, never the workflow default. -/
theorem dispatch_target (q : Request) : ("target", q.target) ∈ dispatchInputs .chromium q := by
  simp [dispatchInputs]

/-- **WebKit is told the run count:** its dispatch inputs carry the request's run count as `vms`, never the workflow
default of 1.
-/
theorem dispatch_vms (q : Request) : ("vms", toString q.runs) ∈ dispatchInputs .webkit q := by
  simp [dispatchInputs]

/-- Why a job cannot run: the first needed field its workflow has no input for. -/
def blocked (e : Engine) (q : Request) : Option String :=
  (needs q).find? (fun x => !(workflowInputs e).contains x)

/-- **A job that is not blocked can express everything the request needs.** -/
theorem blocked_none_sound {e : Engine} {q : Request} (h : blocked e q = none) :
    ∀ x ∈ needs q, x ∈ workflowInputs e := by
  intro x hx
  have := (List.find?_eq_none.mp h) x hx
  simpa using this

/-- **The Chromium workflow can express every request:** a chromium job is never blocked. -/
theorem blocked_chromium (q : Request) : blocked .chromium q = none := by
  unfold blocked needs
  apply List.find?_eq_none.mpr
  intro x hx
  simp only [List.mem_append] at hx
  rcases hx with ((hx | hx) | hx) | hx <;> split at hx <;> simp_all [workflowInputs, Lane.ofEngine, Lane.inputs]

/-- **A chromium job sends what the request needs:** every needed field is a key of its dispatch inputs. -/
theorem needs_dispatched (q : Request) (x : String) (hx : x ∈ needs q) :
    ∃ v, (x, v) ∈ dispatchInputs .chromium q := by
  unfold needs at hx
  simp only [List.mem_append] at hx
  rcases hx with ((hx | hx) | hx) | hx <;> split at hx <;> simp_all [dispatchInputs]

/-- **A job is blocked exactly when some needed input is missing from its lane's table.** One statement for both count
lanes (`blocked e q = none` iff every needed input is declared by the workflow).
-/
theorem blocked_eq_none_iff (e : Engine) (q : Request) :
    blocked e q = none ↔ ∀ x ∈ needs q, x ∈ workflowInputs e := by
  constructor
  · exact blocked_none_sound
  · intro h
    apply List.find?_eq_none.mpr
    intro x hx
    simpa using h x hx

/-- **The other branch:** a job names a reason only when it is a needed input the workflow lacks. -/
theorem blocked_some_sound (e : Engine) (q : Request) (r : String) :
    blocked e q = some r → r ∈ needs q ∧ r ∉ workflowInputs e := by
  intro h
  have h1 := List.find?_some h
  have hm := List.mem_of_find?_eq_some h
  simp at h1
  exact ⟨hm, h1⟩

/-- **WebKit is blocked only by the profile:** webkit-sim declares `target`, `preset` and `fw` but no `profile`, so a job
is blocked iff the request's profile is not the default.
-/
theorem blocked_webkit_iff (q : Request) : blocked .webkit q = none ↔ q.profile = defaultProfile := by
  rw [blocked_eq_none_iff]
  unfold needs
  constructor
  · intro h
    by_cases hp : q.profile = defaultProfile
    · exact hp
    · have := h "profile" (by simp [hp])
      simp [workflowInputs, Lane.ofEngine, Lane.inputs] at this
  · intro h x hx
    simp only [List.mem_append] at hx
    rcases hx with ((hx | hx) | hx) | hx <;> split at hx <;> simp_all [workflowInputs, Lane.ofEngine, Lane.inputs]

/-- **A webkit job sends what the request needs, apart from the profile:** every needed field except `profile` is a key
of its dispatch inputs.
-/
theorem needs_dispatched_webkit (q : Request) (x : String) (hx : x ∈ needs q) (hp : x ≠ "profile") :
    ∃ v, (x, v) ∈ dispatchInputs .webkit q := by
  unfold needs at hx
  simp only [List.mem_append] at hx
  rcases hx with ((hx | hx) | hx) | hx <;> split at hx <;> simp_all [dispatchInputs]

/-- **Every dispatch input is declared:** a key of `dispatchInputs e q` is an input of the engine's workflow, so
`gh workflow run -f` is never given a name the workflow lacks.
-/
theorem dispatch_keys_declared (e : Engine) (q : Request) : ∀ p ∈ dispatchInputs e q, p.1 ∈ workflowInputs e := by
  intro p hp
  cases e <;> simp [dispatchInputs, workflowInputs, Lane.ofEngine, Lane.inputs] at hp ⊢ <;> rcases hp with rfl | rfl | rfl | rfl | rfl <;> simp

/-- The most VMs one webkit-sim run takes: its `vms` input is 1 to 3 (`Fw.Measure.SimPlan.problems`), so a WebKit
request runs 2 or 3 times.
-/
def webkitMaxVms : Nat := 3

/-- One job of a plan. -/
structure Job where
  engine : Engine
  workflow : String
  inputs : List (String × String)
  key : List (String × String)
  blocked : Option String

/-- Request-level problems (empty = the request is well formed).

`flagsOk` checks the
flags in the order given (the wire layer sorts them by part first, so there a failure means a repeated part).
-/
def reqProblems (q : Request) : List String :=
  (if q.engines.isEmpty then ["engines: none given"] else []) ++
  (if q.engines.all (fun n => (Engine.ofName n).isSome) then [] else ["engines: unknown name"]) ++
  (if (Target.ofName q.target).isSome then [] else ["target: not original or rewrite"]) ++
  (if targetFits q.target q.preset q.fw then [] else ["target: original takes no preset or flags"]) ++
  (if isId q.preset then [] else ["preset: not an id"]) ++
  (if isId q.profile then [] else ["profile: not an id"]) ++
  (if q.fw.all (fun p => isPart p.1 && isId p.2) then [] else ["fw: part and variant must be ids"]) ++
  (if flagsOk q.fw then [] else ["fw: a part appears twice"]) ++
  (if 2 ≤ q.runs && q.runs ≤ 10 then [] else ["runs: must be 2 to 10"]) ++
  (if isHex 40 q.sha then [] else ["sha: not 40 hex digits"]) ++
  (if q.images.all (fun p => (Engine.ofName p.1).isSome && imageOk p.2) then [] else ["images: unknown engine or bad image"]) ++
  (if q.engines.contains Engine.webkit.name && webkitMaxVms < q.runs then ["runs: webkit-sim takes at most 3 VMs"] else [])

/-- The jobs of a request for one target: one per distinct requested engine, in canonical order. -/
def jobsFor (q : Request) (t : Target) : List Job :=
  let es := canonEngines (q.engines.filterMap Engine.ofName)
  es.map fun e =>
    { engine := e, workflow := workflowOf e, inputs := dispatchInputs e q, blocked := blocked e q,
      key := keyPairs { engine := e, target := t, preset := q.preset, fw := q.fw, profile := q.profile, sha := q.sha,
                        image := imageOf q e, runs := q.runs } }

/-- The jobs of a request: those for its target, none when the target is not a known name. -/
def jobsOf (q : Request) : List Job :=
  match Target.ofName q.target with
  | some t => jobsFor q t
  | none => []

/-- The plan: the jobs when the request is well formed, no job otherwise. -/
def plan (q : Request) : List Job := if (reqProblems q).isEmpty then jobsOf q else []

/-- **A refused request plans nothing.** -/
theorem plan_nil_of_problems {q : Request} (h : reqProblems q ≠ []) : plan q = [] := by
  simp [plan, h]

/-- **An accepted request names a known target that fits its configuration.** -/
theorem reqProblems_nil_target {q : Request} (h : reqProblems q = []) :
    (∃ t, Target.ofName q.target = some t) ∧ targetFits q.target q.preset q.fw = true := by
  simp only [reqProblems, List.append_eq_nil_iff] at h
  have h1 := h.1.1.1.1.1.1.1.1.1.2
  have h2 := h.1.1.1.1.1.1.1.1.2
  constructor
  · by_cases hs : (Target.ofName q.target).isSome
    · exact Option.isSome_iff_exists.mp hs
    · simp [hs] at h1
  · by_cases hs : targetFits q.target q.preset q.fw = true
    · exact hs
    · simp [hs] at h2

/-- The plan of an accepted request is the job list for its target. -/
theorem plan_eq_jobsFor {q : Request} {t : Target} (h : reqProblems q = []) (ht : Target.ofName q.target = some t) :
    plan q = jobsFor q t := by
  simp [plan, h, jobsOf, ht]

/-- **One job per distinct engine.** The engines of a plan are exactly the requested ones, in
canonical order, with no repeat.
-/
theorem plan_engines {q : Request} (h : reqProblems q = []) :
    (plan q).map (·.engine) = canonEngines (q.engines.filterMap Engine.ofName) ∧
    ((plan q).map (·.engine)).Nodup := by
  obtain ⟨⟨t, ht⟩, _⟩ := reqProblems_nil_target h
  have he : (jobsFor q t).map (·.engine) = canonEngines (q.engines.filterMap Engine.ofName) := by
    simp [jobsFor, Function.comp_def]
  rw [plan_eq_jobsFor h ht, he]
  exact ⟨rfl, canonEngines_nodup _⟩

/-- **A well-formed plan has canonical flags.** When the request is accepted, its flags are strictly
increasing by part, so two orderings of the same flags give the same key after sorting.
-/
theorem reqProblems_nil_flags {q : Request} (h : reqProblems q = []) : flagsOk q.fw = true := by
  simp only [reqProblems, List.append_eq_nil_iff] at h
  by_cases hs : flagsOk q.fw = true
  · exact hs
  · have := h.1.1.1.1.2; simp [hs] at this

/-- **A job's key carries its engine and the request's flags.** Two jobs of one plan have different
keys (they differ in the engine pair).
-/
theorem plan_key_inj {q : Request} (h : reqProblems q = []) {j j' : Job} (hj : j ∈ plan q)
    (hj' : j' ∈ plan q) (hk : j.key = j'.key) : j = j' := by
  obtain ⟨⟨t, ht⟩, _⟩ := reqProblems_nil_target h
  rw [plan_eq_jobsFor h ht] at hj hj'
  simp only [jobsFor, List.mem_map] at hj hj'
  obtain ⟨e, _, rfl⟩ := hj
  obtain ⟨e', _, rfl⟩ := hj'
  have := keyPairs_inj hk
  have he : e = e' := by cases this; rfl
  subst he; rfl

/-- **Every job's key records the request's target.** -/
theorem plan_key_target {q : Request} (h : reqProblems q = []) {j : Job} (hj : j ∈ plan q) :
    ("target", q.target) ∈ j.key := by
  obtain ⟨⟨t, ht⟩, _⟩ := reqProblems_nil_target h
  rw [plan_eq_jobsFor h ht] at hj
  simp only [jobsFor, List.mem_map] at hj
  obtain ⟨e, _, rfl⟩ := hj
  simp [keyPairs, Target.name_ofName ht]

/-- **An original run and a rewrite run never share a key.** Two accepted requests with different targets give jobs
with different keys, whatever else (engine, preset, flags, profile, sha, image) they have in common.
-/
theorem plan_key_target_ne {q q' : Request} (h : reqProblems q = []) (h' : reqProblems q' = [])
    (ht : q.target ≠ q'.target) {j j' : Job} (hj : j ∈ plan q) (hj' : j' ∈ plan q') : j.key ≠ j'.key := by
  obtain ⟨⟨t, hq⟩, _⟩ := reqProblems_nil_target h
  obtain ⟨⟨t', hq'⟩, _⟩ := reqProblems_nil_target h'
  rw [plan_eq_jobsFor h hq] at hj
  rw [plan_eq_jobsFor h' hq'] at hj'
  simp only [jobsFor, List.mem_map] at hj hj'
  obtain ⟨e, _, rfl⟩ := hj
  obtain ⟨e', _, rfl⟩ := hj'
  apply keyPairs_target_ne
  intro htt
  apply ht
  rw [← Target.name_ofName hq, ← Target.name_ofName hq']
  exact congrArg Target.name htt

/-- **Every job's key is the key of a run identity with the request's run count.** -/
theorem plan_key_runs {q : Request} {j : Job} (hj : j ∈ plan q) : ∃ r : Req, r.runs = q.runs ∧ j.key = keyPairs r := by
  unfold plan at hj
  split at hj
  · unfold jobsOf at hj
    split at hj
    · simp only [jobsFor, List.mem_map] at hj
      obtain ⟨e, _, rfl⟩ := hj
      exact ⟨_, rfl, rfl⟩
    · simp at hj
  · simp at hj

/-- **A 2-run and a 3-run request never share a key.** Two requests with different run counts give jobs with different
keys, whatever else they have in common, so a cached run is a hit only for its own VM or shard count.
-/
theorem plan_key_runs_ne {q q' : Request} (hr : q.runs ≠ q'.runs) {j j' : Job} (hj : j ∈ plan q)
    (hj' : j' ∈ plan q') : j.key ≠ j'.key := by
  obtain ⟨r, hr1, hk⟩ := plan_key_runs hj
  obtain ⟨r', hr2, hk'⟩ := plan_key_runs hj'
  rw [hk, hk']
  exact keyPairs_runs_ne (by rw [hr1, hr2]; exact hr)

/-- **An accepted WebKit request fits webkit-sim:** its run count, sent as `vms`, is 2 to `webkitMaxVms`. -/
theorem reqProblems_nil_webkit_runs {q : Request} (h : reqProblems q = []) (hw : Engine.webkit.name ∈ q.engines) :
    2 ≤ q.runs ∧ q.runs ≤ webkitMaxVms := by
  simp only [reqProblems, List.append_eq_nil_iff] at h
  have h1 := h.1.1.1.2
  have h2 := h.2
  constructor
  · by_cases hs : (2 ≤ q.runs && q.runs ≤ 10) = true
    · simp at hs; exact hs.1
    · simp [hs] at h1
  · by_cases hs : webkitMaxVms < q.runs
    · simp [hs, hw] at h2
    · omega

/-! ## The breakpoint gate lane

`breakpoint-gate.yml` compares the original snapshot with the rewrite; it takes no target and no profile. Its dispatch
inputs here are the engines, the rewrite's preset and flags (`parts`, `runs`, `free` and `times` keep their workflow
defaults).
-/

/-- The `engines` values of `breakpoint-gate.yml`. -/
def gateEngines : List String := ["both", "chromium", "playwright-webkit"]

/-- A gate request: the engines option, the rewrite arm's preset (empty = none) and flags. -/
structure GateRequest where
  engines : String
  preset : String
  fw : List (String × String)

/-- The gate request that equals the workflow defaults. -/
def GateRequest.default : GateRequest := { engines := "both", preset := "", fw := [] }

/-- Request-level problems of a gate request (empty = well formed). The workflow takes preset and fw exclusively. -/
def gateProblems (g : GateRequest) : List String :=
  (if g.engines ∈ gateEngines then [] else ["engines: not both, chromium or playwright-webkit"]) ++
  (if g.preset.isEmpty || isId g.preset then [] else ["preset: not an id"]) ++
  (if g.fw.all (fun p => isPart p.1 && isId p.2) then [] else ["fw: part and variant must be ids"]) ++
  (if flagsOk g.fw then [] else ["fw: a part appears twice"]) ++
  (if g.preset.isEmpty || g.fw.isEmpty then [] else ["preset: exclusive with fw"])

/-- The gate request fields that differ from the workflow defaults, so the workflow must accept them as inputs. -/
def gateNeeds (g : GateRequest) : List String :=
  (if g.engines == "both" then [] else ["engines"]) ++
  (if g.preset.isEmpty then [] else ["preset"]) ++
  (if g.fw.isEmpty then [] else ["fw"])

/-- The dispatch inputs of the gate: always the three, so the workflow never falls back silently. -/
def gateDispatchInputs (g : GateRequest) : List (String × String) :=
  [("engines", g.engines), ("preset", g.preset), ("fw", fwInput g.fw)]

/-- Why the gate cannot run: the first needed field its workflow has no input for. -/
def gateBlocked (g : GateRequest) : Option String :=
  (gateNeeds g).find? (fun x => !(Lane.breakpointGate.inputs).contains x)

/-- **The gate is blocked exactly when some needed input is missing from its table.** -/
theorem gateBlocked_eq_none_iff (g : GateRequest) :
    gateBlocked g = none ↔ ∀ x ∈ gateNeeds g, x ∈ Lane.breakpointGate.inputs := by
  constructor
  · intro h x hx
    have := (List.find?_eq_none.mp h) x hx
    simpa using this
  · intro h
    apply List.find?_eq_none.mpr
    intro x hx
    simpa using h x hx

/-- **The gate workflow can express every gate request:** it is never blocked. -/
theorem gateBlocked_none (g : GateRequest) : gateBlocked g = none := by
  rw [gateBlocked_eq_none_iff]
  intro x hx
  unfold gateNeeds at hx
  simp only [List.mem_append] at hx
  rcases hx with (hx | hx) | hx <;> split at hx <;> simp_all [Lane.inputs]

/-- **The gate sends what the request needs:** every needed field is a key of its dispatch inputs. -/
theorem gate_needs_dispatched (g : GateRequest) (x : String) (hx : x ∈ gateNeeds g) :
    ∃ v, (x, v) ∈ gateDispatchInputs g := by
  unfold gateNeeds at hx
  simp only [List.mem_append] at hx
  rcases hx with (hx | hx) | hx <;> split at hx <;> simp_all [gateDispatchInputs]

/-- **Every gate dispatch input is declared by the workflow.** -/
theorem gate_keys_declared (g : GateRequest) : ∀ p ∈ gateDispatchInputs g, p.1 ∈ Lane.breakpointGate.inputs := by
  intro p hp
  simp [gateDispatchInputs] at hp
  rcases hp with rfl | rfl | rfl <;> simp [Lane.inputs]

#guard gateProblems GateRequest.default == []
#guard gateProblems { GateRequest.default with engines := "webkit" } == ["engines: not both, chromium or playwright-webkit"]
#guard gateProblems { GateRequest.default with preset := "v2-proved", fw := [("a", "b")] } == ["preset: exclusive with fw"]
#guard gateDispatchInputs GateRequest.default == [("engines", "both"), ("preset", ""), ("fw", "")]
#guard gateDispatchInputs { engines := "chromium", preset := "", fw := [("morph.tween", "waapi")] }
  == [("engines", "chromium"), ("preset", ""), ("fw", "morph.tween:waapi")]
#guard gateBlocked { engines := "chromium", preset := "v2-proved", fw := [] } == none

/-! ## The trajectory probe lane

`trajectory-probe.yml` takes the gate's three inputs (the engines, the rewrite's preset and flags) and the list of
widths; the other inputs have no default to change. It also declares `nonce`, the identity of a dispatch (set by `fw run`,
`Fw.Ci.Dispatch`), which no request carries. The request is a gate request and a widths string (empty = all
four; the allowlist is `Fw.Gate.Trajectory.pickWidths`, checked in `Fw.Wire.Store`).
-/

/-- The dispatch inputs of the probe: the gate's three and the widths, always all four. -/
def trajectoryDispatchInputs (g : GateRequest) (widths : String) : List (String × String) :=
  gateDispatchInputs g ++ [("widths", widths)]

/-- Why the probe cannot run: the first needed field its workflow has no input for. -/
def trajectoryBlocked (g : GateRequest) : Option String :=
  (gateNeeds g).find? (fun x => !(Lane.trajectory.inputs).contains x)

/-- **The probe workflow can express every request:** it is never blocked. -/
theorem trajectoryBlocked_none (g : GateRequest) : trajectoryBlocked g = none := by
  apply List.find?_eq_none.mpr
  intro x hx
  unfold gateNeeds at hx
  simp only [List.mem_append] at hx
  rcases hx with (hx | hx) | hx <;> split at hx <;> simp_all [Lane.inputs]

/-- **Every probe dispatch input is declared by the workflow.** -/
theorem trajectory_keys_declared (g : GateRequest) (w : String) :
    ∀ p ∈ trajectoryDispatchInputs g w, p.1 ∈ Lane.trajectory.inputs := by
  intro p hp
  simp [trajectoryDispatchInputs, gateDispatchInputs] at hp
  rcases hp with rfl | rfl | rfl | rfl <;> simp [Lane.inputs]

#guard trajectoryDispatchInputs GateRequest.default "" == [("engines", "both"), ("preset", ""), ("fw", ""), ("widths", "")]
#guard trajectoryDispatchInputs { engines := "chromium", preset := "", fw := [("morph.tween", "waapi")] } "390,641"
  == [("engines", "chromium"), ("preset", ""), ("fw", "morph.tween:waapi"), ("widths", "390,641")]
#guard trajectoryBlocked { engines := "chromium", preset := "v2-proved", fw := [] } == none

/-- The manifest path of a run, relative to the store root, from the hex digest of its key. -/
def manifestPath (d : String) : String := "runs/" ++ d ++ "/manifest.json"

#guard manifestPath "ab" == "runs/ab/manifest.json"

/-- A cache verdict of a job: the digest of its key is in the store (`hit`), is not (`miss`), or was
not computed (`unknown`).
-/
def cacheOf (d : Option String) (present : List String) : String :=
  match d with
  | none => "unknown"
  | some x => if x ∈ present then "hit" else "miss"

#guard canonEngines [.webkit, .chromium, .webkit] == [.chromium, .webkit]

/-- A well-formed request for the guards (the `#guard` below checks `reqProblems(exReq) = []`).

In the field order (target, preset, fw, engines, profile, runs, sha, images).
-/
def exReq : Request :=
  { target := "original", preset := "original", fw := [], engines := ["webkit", "chromium", "webkit"],
    profile := "swipe-v1", runs := 3, sha := "0123456789abcdef0123456789abcdef01234567", images := [] }

/-- `exReq` on the rewrite with a preset and one flag (accepted too). -/
def exRw : Request := { exReq with target := "rewrite", preset := "strip-demo", fw := [("hero.countdown", "strip")] }

#guard reqProblems exReq == []
#guard reqProblems exRw == []
#guard reqProblems { exReq with target := "both" } == ["target: not original or rewrite"]
#guard reqProblems { exReq with fw := [("hero.countdown", "strip")] } == ["target: original takes no preset or flags"]
#guard (reqProblems { exReq with preset := "Orig", fw := [("a", "b"), ("a", "c")], engines := [], runs := 1, sha := "xyz", images := [("tablet", "x")] }).length == 7
#guard imageOf exReq .webkit == "runner:xcode-27"
#guard imageOf { exReq with images := [("webkit", "sha256:0000000000000000000000000000000000000000000000000000000000000000")] } .webkit
  == "sha256:0000000000000000000000000000000000000000000000000000000000000000"
#guard (plan exReq).map (·.engine) == [.chromium, .webkit]
#guard (plan exRw).map (·.blocked) == [none, none]
#guard ((plan exReq).map (·.key)).all (·.contains ("target", "original"))
#guard ((plan { exReq with target := "rewrite" }).map (·.key)).all (·.contains ("target", "rewrite"))
#guard (plan exReq).map (·.key) != (plan { exReq with target := "rewrite" }).map (·.key)
#guard blocked .webkit { exRw with target := "original" } == none
#guard blocked .webkit { exReq with profile := "swipe-wheel-v1" } == some "profile"
#guard blocked .chromium { exReq with profile := "swipe-wheel-v1" } == none
#guard blocked .chromium exRw == none
#guard blocked .webkit exRw == none
#guard dispatchInputs .chromium exRw
  == [("profile", "swipe-v1"), ("runs", "3"), ("target", "rewrite"), ("preset", "strip-demo"), ("fw", "hero.countdown:strip")]
#guard dispatchInputs .webkit exRw == [("vms", "3"), ("target", "rewrite"), ("preset", "strip-demo"), ("fw", "hero.countdown:strip")]
#guard dispatchInputs .webkit exReq == [("vms", "3"), ("target", "original"), ("preset", "original"), ("fw", "")]
#guard dispatchInputs .webkit { exReq with runs := 2 } |>.contains ("vms", "2")
#guard (dispatchInputs .webkit exRw).all (fun p => Lane.webkitSim.inputs.contains p.1)
#guard (plan exReq).map (·.key) != (plan { exReq with runs := 2 }).map (·.key)
#guard ((plan exReq).map (·.key)).all (·.contains ("runs", "3"))
#guard reqProblems { exReq with runs := 4 } == ["runs: webkit-sim takes at most 3 VMs"]
#guard reqProblems { exReq with runs := 4, engines := ["chromium"] } == []
#guard reqProblems { exReq with runs := 3 } == []
#guard cacheOf (some "a") ["a"] == "hit"
#guard cacheOf (some "b") ["a"] == "miss"
#guard cacheOf none ["a"] == "unknown"

end Fw.Store
