/-!
# The artifact store: layout, run manifests and the `fw run` plan

Spec of what `fw run` stores and plans (PLAN §10.1). Pure; the JSON glue is `Fw.Wire.Store`.

**Layout** (under `.fw-console/store/`, gitignored with the console state):

```
objects/<d[0..2]>/<d[2..64]>      the bytes of one artifact; d = its sha256, lowercase hex
runs/<runKey>/manifest.json       one manifest per run: what was measured and where the bytes are
```

An object is **content-addressed**: its path is a function of the sha256 of its bytes
(`objectPath`, injective on 64-hex digests). A run manifest names the engine, preset, flags,
profile, git sha and the image the run executed in, and lists its artifacts as
`{name, digest, bytes}` sorted by name. The digest of the run's identity (the `runKey`) is the
sha256 of the canonical JSON of `keyPairs`; the hash is computed by the caller (L3 assumption: sha256
has no collisions on what we hash), while `keyPairs_inj` proves that distinct configurations
never share the *input* of the hash.

**Plan.** `plan` turns a request (preset, flags, engines, profile, git sha, image) into one job
per distinct engine in canonical order, each with the CI workflow it dispatches, its inputs and the
reason it cannot run yet (a workflow without an input for something the request needs). Nothing
measures on the developer's machine: a job is a `gh workflow run` on CI.
-/
namespace Fw.Store

/-! ## Engines -/

/-- The two engines of the study.

$$\mathrm{Engine} = \{\mathrm{chromium}, \mathrm{webkit}\}$$
-/
inductive Engine where
  | chromium
  | webkit
deriving DecidableEq, Repr

/-- Wire name of an engine.

$$\operatorname{name}(\mathrm{chromium}) = \texttt{"chromium"},\quad \operatorname{name}(\mathrm{webkit}) = \texttt{"webkit"}$$
-/
def Engine.name : Engine → String
  | .chromium => "chromium"
  | .webkit => "webkit"

/-- An engine from its wire name.

$$\operatorname{ofName}(s) = \begin{cases} \mathrm{chromium} & s = \texttt{"chromium"} \\ \mathrm{webkit} & s = \texttt{"webkit"} \\ \bot & \text{otherwise} \end{cases}$$
-/
def Engine.ofName : String → Option Engine
  | "chromium" => some .chromium
  | "webkit" => some .webkit
  | _ => none

/-- Names round-trip.

$$\forall e:\ \operatorname{ofName}(\operatorname{name}(e)) = e$$
-/
theorem Engine.ofName_name (e : Engine) : Engine.ofName e.name = some e := by
  cases e <;> rfl

/-- Names are injective.

$$\forall e, e':\ \operatorname{name}(e) = \operatorname{name}(e') \Rightarrow e = e'$$
-/
theorem Engine.name_inj {e e' : Engine} (h : e.name = e'.name) : e = e' := by
  cases e <;> cases e' <;> first | rfl | (exact absurd h (by decide))

/-- The engines in canonical order, restricted to those requested: no duplicates, chromium first.

$$\operatorname{canon}(E) = [\, e \in [\mathrm{chromium}, \mathrm{webkit}] \mid e \in E \,]$$
-/
def canonEngines (es : List Engine) : List Engine :=
  [Engine.chromium, Engine.webkit].filter (fun e => decide (e ∈ es))

/-- Canonical engines are exactly the requested ones.

$$\forall E, e:\ e \in \operatorname{canon}(E) \iff e \in E$$
-/
theorem mem_canonEngines (es : List Engine) (e : Engine) : e ∈ canonEngines es ↔ e ∈ es := by
  cases e <;> simp [canonEngines]

/-- Canonical engines have no duplicates.

$$\forall E:\ \operatorname{canon}(E)\ \text{has no repeated element}$$
-/
theorem canonEngines_nodup (es : List Engine) : (canonEngines es).Nodup := by
  unfold canonEngines
  exact List.Nodup.sublist (List.filter_sublist) (by decide)

/-! ## Digests and object paths -/

/-- A lowercase hexadecimal digit.

$$\mathrm{hex}(c) \iff c \in \{0..9\} \cup \{a..f\}$$
-/
def isHexChar (c : Char) : Bool := c.isDigit || (decide ('a' ≤ c) && decide (c ≤ 'f'))

/-- A lowercase hex string of exactly `n` digits.

$$\operatorname{isHex}_n(s) \iff |s| = n \land \forall c \in s:\ \mathrm{hex}(c)$$
-/
def isHex (n : Nat) (s : String) : Bool := s.toList.length == n && s.toList.all isHexChar

/-- The characters of an object path: `objects/`, the first two digits, `/`, the other digits.

$$\operatorname{pathChars}(d) = \texttt{objects/} \mathbin{+\!\!+} d_{[0,2)} \mathbin{+\!\!+} \texttt{/} \mathbin{+\!\!+} d_{[2,\infty)}$$
-/
def pathChars (d : List Char) : List Char :=
  "objects/".toList ++ (d.take 2 ++ '/' :: d.drop 2)

/-- The path of an object, relative to the store root.

$$\operatorname{objectPath}(d) = \texttt{objects/} d_{[0,2)} \texttt{/} d_{[2,\infty)}$$
-/
def objectPath (d : String) : String := String.ofList (pathChars d.toList)

/-- **Content addressing is injective.** Two digests of at least two digits with the same path are
the same digest, so two different byte strings (different sha256) never share a file.

$$\forall d, d' \text{ with } |d|, |d'| \ge 2:\ \operatorname{objectPath}(d) = \operatorname{objectPath}(d') \Rightarrow d = d'$$
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

$$\operatorname{isId}(s) \iff 1 \le |s| \le 64 \land s_0 \in [a\text{-}z0\text{-}9] \land \forall c \in s:\ c \in [a\text{-}z0\text{-}9\_.\text{-}]$$
-/
def isId (s : String) : Bool :=
  let cs := s.toList
  decide (0 < cs.length) && decide (cs.length ≤ 64) &&
    (match cs with
     | c :: _ => c.isDigit || (decide ('a' ≤ c) && decide (c ≤ 'z'))
     | [] => false) &&
    cs.all (fun c => c.isDigit || (decide ('a' ≤ c) && decide (c ≤ 'z')) || c == '.' || c == '_' || c == '-')

/-- An artifact name inside a run: `/`-separated segments of `A-Za-z0-9._-`, none empty, `.` or `..`,
so a name can never leave the run's directory.

$$\operatorname{safeName}(n) \iff n \ne \varepsilon \land \forall s \in \operatorname{split}_{/}(n):\ s \ne \varepsilon \land s \notin \{\texttt{.}, \texttt{..}\} \land s \in [A\text{-}Za\text{-}z0\text{-}9\_.\text{-}]^{*}$$
-/
def safeName (n : String) : Bool :=
  !n.isEmpty && (n.splitOn "/").all fun s =>
    !s.isEmpty && s != "." && s != ".." &&
      s.toList.all (fun c => c.isAlphanum || c == '.' || c == '_' || c == '-')

/-- **A safe name has no `..` segment.**

$$\forall n:\ \operatorname{safeName}(n) \Rightarrow \forall s \in \operatorname{split}_{/}(n):\ s \ne \texttt{..}$$
-/
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

/-- One stored artifact of a run.

$$\mathrm{Entry} = \mathrm{Name} \times \mathrm{Digest} \times \mathbb{N}$$
-/
structure Entry where
  name : String
  digest : String
  bytes : Nat
deriving Repr, DecidableEq

/-- What one run measured and where its bytes are.

$$\mathrm{Manifest} = \mathrm{Engine} \times \mathrm{Preset} \times \mathrm{Flags} \times \mathrm{Profile} \times \mathrm{Sha} \times \mathrm{Image} \times \mathrm{RunId} \times \mathrm{Entry}^{*}$$
-/
structure Manifest where
  engine : String
  preset : String
  fw : List (String × String)
  profile : String
  gitSha : String
  image : String
  runId : String
  entries : List Entry
deriving Repr

/-- The flags are strictly increasing by part, so a part appears at most once and the list is canonical.

$$\operatorname{flagsOk}(F) \iff \forall i < j:\ F_i.\mathrm{part} < F_j.\mathrm{part}$$
-/
def flagsOk (fw : List (String × String)) : Bool :=
  decide (fw.Pairwise (fun a b => a.1 < b.1))

/-- The flag list is free of duplicate parts when strictly increasing.

$$\operatorname{flagsOk}(F) \Rightarrow \text{the parts of } F \text{ are pairwise distinct}$$
-/
theorem flagsOk_nodup {fw : List (String × String)} (h : flagsOk fw = true) :
    (fw.map (·.1)).Nodup := by
  have h' : fw.Pairwise (fun a b => a.1 < b.1) := by simpa [flagsOk] using h
  rw [List.nodup_iff_pairwise_ne] -- Pairwise (≠) on the mapped list
  rw [List.pairwise_map]
  exact h'.imp (fun {a b} hab => fun e => String.lt_irrefl _ (e ▸ hab))

/-- An image: a container digest `sha256:<64 hex>` or a CI runner label `runner:<id>`.

$$\operatorname{imageOk}(s) \iff \exists d:\ s = \texttt{sha256:} d \land \operatorname{isHex}_{64}(d)\ \lor\ \exists r:\ s = \texttt{runner:} r \land \operatorname{isId}(r)$$
-/
def imageOk (s : String) : Bool :=
  (s.startsWith "sha256:" && isHex 64 (s.drop 7).toString) ||
  (s.startsWith "runner:" && isId (s.drop 7).toString)

/-- Strictly increasing entry names (sorted, no duplicate name).

$$\operatorname{entriesSorted}(E) \iff \forall i < j:\ E_i.\mathrm{name} < E_j.\mathrm{name}$$
-/
def entriesSorted (es : List Entry) : Bool := decide (es.Pairwise (fun a b => a.name < b.name))

/-- Sorted entries have distinct names.

$$\operatorname{entriesSorted}(E) \Rightarrow \text{the names of } E \text{ are pairwise distinct}$$
-/
theorem entriesSorted_nodup {es : List Entry} (h : entriesSorted es = true) :
    (es.map (·.name)).Nodup := by
  have h' : es.Pairwise (fun a b => a.name < b.name) := by simpa [entriesSorted] using h
  rw [List.nodup_iff_pairwise_ne, List.pairwise_map]
  exact h'.imp (fun {a b} hab => fun e => String.lt_irrefl _ (e ▸ hab))

/-- Every problem of a manifest, as a message (empty = valid).

$$\operatorname{problems}(m) = [\,\text{each violated rule}\,]$$ over the rules: engine known, preset and profile ids, flags canonical with id parts and variants, 40-hex git sha, image, digits-only run id, entry names safe and strictly increasing, entry digests 64-hex.
-/
def Manifest.problems (m : Manifest) : List String :=
  (if (Engine.ofName m.engine).isSome then [] else ["engine: unknown"]) ++
  (if isId m.preset then [] else ["preset: not an id"]) ++
  (if isId m.profile then [] else ["profile: not an id"]) ++
  (if flagsOk m.fw then [] else ["fw: parts must be strictly increasing"]) ++
  (if m.fw.all (fun p => isId p.1 && isId p.2) then [] else ["fw: part and variant must be ids"]) ++
  (if isHex 40 m.gitSha then [] else ["gitSha: not 40 hex digits"]) ++
  (if imageOk m.image then [] else ["image: not sha256:<64 hex> or runner:<id>"]) ++
  (if !m.runId.isEmpty && m.runId.toList.all Char.isDigit then [] else ["runId: not digits"]) ++
  (if entriesSorted m.entries then [] else ["entries: names must be strictly increasing"]) ++
  (if m.entries.all (fun e => safeName e.name) then [] else ["entries: name escapes the run directory"]) ++
  (if m.entries.all (fun e => isHex 64 e.digest) then [] else ["entries: digest not 64 hex digits"])

/-- A manifest is valid when it has no problem.

$$\operatorname{valid}(m) \iff \operatorname{problems}(m) = [\,]$$
-/
def Manifest.valid (m : Manifest) : Bool := m.problems.isEmpty

/-- A valid manifest names a known engine.

$$\operatorname{valid}(m) \Rightarrow \exists e:\ \operatorname{ofName}(m.\mathrm{engine}) = e$$
-/
theorem Manifest.valid_engine {m : Manifest} (h : m.valid = true) :
    ∃ e, Engine.ofName m.engine = some e := by
  simp only [valid, problems, List.isEmpty_iff, List.append_eq_nil_iff] at h
  have h1 := h.1.1.1.1.1.1.1.1.1.1
  by_cases hs : (Engine.ofName m.engine).isSome
  · exact Option.isSome_iff_exists.mp hs
  · simp [hs] at h1

/-- A valid manifest has sorted, hence name-distinct, entries with 64-hex digests.

$$\operatorname{valid}(m) \Rightarrow \text{entry names pairwise distinct} \land \forall e \in m.\mathrm{entries}:\ \operatorname{isHex}_{64}(e.\mathrm{digest})$$
-/
theorem Manifest.valid_entries {m : Manifest} (h : m.valid = true) :
    (m.entries.map (·.name)).Nodup ∧ ∀ e ∈ m.entries, isHex 64 e.digest = true := by
  simp only [valid, problems, List.isEmpty_iff, List.append_eq_nil_iff] at h
  constructor
  · apply entriesSorted_nodup
    by_cases hs : entriesSorted m.entries = true
    · exact hs
    · have := h.1.1.2; simp [hs] at this
  · intro e he
    have h3 := h.2
    by_cases hs : (m.entries.all (fun e => isHex 64 e.digest)) = true
    · simp only [List.all_eq_true] at hs; exact hs e he
    · simp [hs] at h3

/-! ## The identity of a run -/

/-- What a run's identity depends on. `preset` and the flags select the site configuration, `profile`
the scroll script, `sha` the code, `image` the browser build and machine.

$$\mathrm{Req} = \mathrm{Engine} \times \mathrm{Preset} \times \mathrm{Flags} \times \mathrm{Profile} \times \mathrm{Sha} \times \mathrm{Image}$$
-/
structure Req where
  engine : Engine
  preset : String
  fw : List (String × String)
  profile : String
  sha : String
  image : String

/-- Flatten flags to key pairs: each part and each variant is its own pair.

$$\operatorname{flagPairs}([(a_1, v_1), \dots]) = [(\texttt{fw}, a_1), (\texttt{fwv}, v_1), \dots]$$
-/
def flagPairs (fw : List (String × String)) : List (String × String) :=
  fw.flatMap fun p => [("fw", p.1), ("fwv", p.2)]

/-- Flattening flags loses nothing.

$$\forall F, F':\ \operatorname{flagPairs}(F) = \operatorname{flagPairs}(F') \Rightarrow F = F'$$
-/
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

$$\operatorname{keyPairs}(r) = [(\texttt{v}, 1), (\texttt{engine}, \cdot), (\texttt{preset}, \cdot), (\texttt{profile}, \cdot), (\texttt{sha}, \cdot), (\texttt{image}, \cdot)] \mathbin{+\!\!+} \operatorname{flagPairs}(r.\mathrm{fw})$$
-/
def keyPairs (r : Req) : List (String × String) :=
  [("v", "1"), ("engine", r.engine.name), ("preset", r.preset), ("profile", r.profile),
   ("sha", r.sha), ("image", r.image)] ++ flagPairs r.fw

/-- **Distinct configurations never share the input of the key hash.**

$$\forall r, r':\ \operatorname{keyPairs}(r) = \operatorname{keyPairs}(r') \Rightarrow r = r'$$
-/
theorem keyPairs_inj {r r' : Req} (h : keyPairs r = keyPairs r') : r = r' := by
  simp only [keyPairs, List.cons_append, List.nil_append, List.cons.injEq, Prod.mk.injEq] at h
  obtain ⟨_, ⟨_, he⟩, ⟨_, hp⟩, ⟨_, hr⟩, ⟨_, hs⟩, ⟨_, hi⟩, hf⟩ := h
  have hf := flagPairs_inj hf
  cases r; cases r'
  simp only at *
  rw [Engine.name_inj he, hp, hr, hs, hi, hf]

/-! ## The plan of `fw run` -/

/-- A run request as the user typed it, before validation.

$$\mathrm{Request} = \mathrm{Preset} \times \mathrm{Flags} \times \mathrm{Engines} \times \mathrm{Profile} \times \mathbb{N} \times \mathrm{Sha} \times (\mathrm{Engine} \rightharpoonup \mathrm{Image})$$
-/
structure Request where
  preset : String
  fw : List (String × String)
  engines : List String
  profile : String
  runs : Nat
  sha : String
  images : List (String × String)

/-- The default configuration: the original site (preset `original`, no flags) on the default profile.

$$\mathrm{default} = (\texttt{original}, [\,], \texttt{swipe-v1})$$
-/
def defaultPreset : String := "original"

/-- The default scroll profile.

$$\mathrm{defaultProfile} = \texttt{swipe-v1}$$
-/
def defaultProfile : String := "swipe-v1"

/-- The image an engine's workflow runs on unless the request pins another (a container digest).

$$\operatorname{defaultImage}(\mathrm{chromium}) = \texttt{runner:ubuntu-24.04-arm},\quad \operatorname{defaultImage}(\mathrm{webkit}) = \texttt{runner:xcode-27}$$
-/
def defaultImage : Engine → String
  | .chromium => "runner:ubuntu-24.04-arm"
  | .webkit => "runner:xcode-27"

/-- The image of a job: the request's pin for that engine, else the default.

$$\operatorname{imageOf}(q, e) = \begin{cases} i & (e.\mathrm{name}, i) \in q.\mathrm{images} \text{ (first)} \\ \operatorname{defaultImage}(e) & \text{otherwise} \end{cases}$$
-/
def imageOf (q : Request) (e : Engine) : String :=
  ((q.images.find? (fun p => p.1 == e.name)).map (·.2)).getD (defaultImage e)

/-- The CI workflow file that measures an engine.

$$\operatorname{workflow}(\mathrm{chromium}) = \texttt{chromium-counts.yml},\quad \operatorname{workflow}(\mathrm{webkit}) = \texttt{webkit-sim.yml}$$
-/
def workflowOf : Engine → String
  | .chromium => "chromium-counts.yml"
  | .webkit => "webkit-sim.yml"

/-- The `workflow_dispatch` inputs a workflow declares (as of its file in `.github/workflows/`).

$$\operatorname{inputs}(\mathrm{chromium}) = \{\texttt{profile}, \texttt{runs}\},\quad \operatorname{inputs}(\mathrm{webkit}) = \{\texttt{vms}, \texttt{sessions}, \texttt{fresh\_boot}\}$$
-/
def workflowInputs : Engine → List String
  | .chromium => ["profile", "runs"]
  | .webkit => ["vms", "sessions", "fresh_boot"]

/-- The request fields that differ from the workflow's built-in configuration, so the workflow must
accept them as inputs.

$$\operatorname{needs}(q) = [\texttt{profile} \mid q.\mathrm{profile} \ne \mathrm{defaultProfile}] \mathbin{+\!\!+} [\texttt{preset} \mid q.\mathrm{preset} \ne \texttt{original}] \mathbin{+\!\!+} [\texttt{fw} \mid q.\mathrm{fw} \ne [\,]]$$
-/
def needs (q : Request) : List String :=
  (if q.profile == defaultProfile then [] else ["profile"]) ++
  (if q.preset == defaultPreset then [] else ["preset"]) ++
  (if q.fw.isEmpty then [] else ["fw"])

/-- The dispatch inputs: the engine's own, from the request. Chromium takes the profile and the run
count; WebKit takes none of the request (its experiment is fixed).

$$\operatorname{dispatch}(\mathrm{chromium}, q) = [(\texttt{profile}, q.\mathrm{profile}), (\texttt{runs}, q.\mathrm{runs})],\quad \operatorname{dispatch}(\mathrm{webkit}, q) = [\,]$$
-/
def dispatchInputs (e : Engine) (q : Request) : List (String × String) :=
  match e with
  | .chromium => [("profile", q.profile), ("runs", toString q.runs)]
  | .webkit => []

/-- Why a job cannot run: the first needed field its workflow has no input for.

$$\operatorname{blocked}(e, q) = \begin{cases} \bot & \forall x \in \operatorname{needs}(q):\ x \in \operatorname{inputs}(e) \\ \text{the first } x \text{ not in } \operatorname{inputs}(e) & \text{otherwise} \end{cases}$$
-/
def blocked (e : Engine) (q : Request) : Option String :=
  (needs q).find? (fun x => !(workflowInputs e).contains x)

/-- **A job that is not blocked can express everything the request needs.**

$$\operatorname{blocked}(e, q) = \bot \Rightarrow \forall x \in \operatorname{needs}(q):\ x \in \operatorname{inputs}(e)$$
-/
theorem blocked_none_sound {e : Engine} {q : Request} (h : blocked e q = none) :
    ∀ x ∈ needs q, x ∈ workflowInputs e := by
  intro x hx
  have := (List.find?_eq_none.mp h) x hx
  simpa using this

/-- One job of a plan.

$$\mathrm{Job} = \mathrm{Engine} \times \mathrm{Workflow} \times \mathrm{Inputs} \times \mathrm{Key} \times \mathrm{Blocked}?$$
-/
structure Job where
  engine : Engine
  workflow : String
  inputs : List (String × String)
  key : List (String × String)
  blocked : Option String

/-- Request-level problems (empty = the request is well formed).

$$\operatorname{reqProblems}(q) = [\,\text{each violated rule}\,]$$ over: engines non-empty and known, preset and profile ids, flags ids and strictly increasing after sorting by part, `2 ≤ runs ≤ 10`, 40-hex git sha, images.
-/
def reqProblems (q : Request) : List String :=
  (if q.engines.isEmpty then ["engines: none given"] else []) ++
  (if q.engines.all (fun n => (Engine.ofName n).isSome) then [] else ["engines: unknown name"]) ++
  (if isId q.preset then [] else ["preset: not an id"]) ++
  (if isId q.profile then [] else ["profile: not an id"]) ++
  (if q.fw.all (fun p => isId p.1 && isId p.2) then [] else ["fw: part and variant must be ids"]) ++
  (if flagsOk q.fw then [] else ["fw: a part appears twice"]) ++
  (if 2 ≤ q.runs && q.runs ≤ 10 then [] else ["runs: must be 2 to 10"]) ++
  (if isHex 40 q.sha then [] else ["sha: not 40 hex digits"]) ++
  (if q.images.all (fun p => (Engine.ofName p.1).isSome && imageOk p.2) then [] else ["images: unknown engine or bad image"])

/-- The jobs of a well-formed request: one per distinct requested engine, in canonical order.

$$\operatorname{jobs}(q) = [\,\operatorname{job}(e, q) \mid e \in \operatorname{canon}(\operatorname{engines}(q))\,]$$
-/
def jobsOf (q : Request) : List Job :=
  let es := canonEngines (q.engines.filterMap Engine.ofName)
  es.map fun e =>
    { engine := e, workflow := workflowOf e, inputs := dispatchInputs e q, blocked := blocked e q,
      key := keyPairs { engine := e, preset := q.preset, fw := q.fw, profile := q.profile, sha := q.sha, image := imageOf q e } }

/-- The plan: the jobs when the request is well formed, no job otherwise.

$$\operatorname{plan}(q) = \begin{cases} \operatorname{jobs}(q) & \operatorname{reqProblems}(q) = [\,] \\ [\,] & \text{otherwise} \end{cases}$$
-/
def plan (q : Request) : List Job := if (reqProblems q).isEmpty then jobsOf q else []

/-- **A refused request plans nothing.**

$$\operatorname{reqProblems}(q) \ne [\,] \Rightarrow \operatorname{plan}(q) = [\,]$$
-/
theorem plan_nil_of_problems {q : Request} (h : reqProblems q ≠ []) : plan q = [] := by
  simp [plan, h]

/-- **One job per distinct engine.** The engines of a plan are exactly the requested ones, in
canonical order, with no repeat.

$$\operatorname{reqProblems}(q) = [\,] \Rightarrow \operatorname{engines}(\operatorname{plan}(q)) = \operatorname{canon}(\operatorname{engines}(q))\ \land\ \text{no repeat}$$
-/
theorem plan_engines {q : Request} (h : reqProblems q = []) :
    (plan q).map (·.engine) = canonEngines (q.engines.filterMap Engine.ofName) ∧
    ((plan q).map (·.engine)).Nodup := by
  have hp : plan q = jobsOf q := by simp [plan, h]
  have he : (jobsOf q).map (·.engine) = canonEngines (q.engines.filterMap Engine.ofName) := by
    simp [jobsOf, Function.comp_def]
  rw [hp, he]
  exact ⟨rfl, canonEngines_nodup _⟩

/-- **A well-formed plan has canonical flags.** When the request is accepted, its flags are strictly
increasing by part, so two orderings of the same flags give the same key after sorting.

$$\operatorname{reqProblems}(q) = [\,] \Rightarrow \operatorname{flagsOk}(q.\mathrm{fw})$$
-/
theorem reqProblems_nil_flags {q : Request} (h : reqProblems q = []) : flagsOk q.fw = true := by
  simp only [reqProblems, List.append_eq_nil_iff] at h
  by_cases hs : flagsOk q.fw = true
  · exact hs
  · have := h.1.1.1.2; simp [hs] at this

/-- **A job's key carries its engine and the request's flags.** Two jobs of one plan have different
keys (they differ in the engine pair).

$$\operatorname{reqProblems}(q) = [\,] \Rightarrow \forall j, j' \in \operatorname{plan}(q):\ j.\mathrm{key} = j'.\mathrm{key} \Rightarrow j = j'$$
-/
theorem plan_key_inj {q : Request} (h : reqProblems q = []) {j j' : Job} (hj : j ∈ plan q)
    (hj' : j' ∈ plan q) (hk : j.key = j'.key) : j = j' := by
  have hp : plan q = jobsOf q := by simp [plan, h]
  rw [hp] at hj hj'
  simp only [jobsOf, List.mem_map] at hj hj'
  obtain ⟨e, _, rfl⟩ := hj
  obtain ⟨e', _, rfl⟩ := hj'
  have := keyPairs_inj hk
  have he : e = e' := by cases this; rfl
  subst he; rfl

/-- The manifest path of a run, relative to the store root, from the hex digest of its key.

$$\operatorname{manifestPath}(d) = \texttt{runs/} d \texttt{/manifest.json}$$
-/
def manifestPath (d : String) : String := "runs/" ++ d ++ "/manifest.json"

#guard manifestPath "ab" == "runs/ab/manifest.json"

/-- A cache verdict of a job: the digest of its key is in the store (`hit`), is not (`miss`), or was
not computed (`unknown`).

$$\operatorname{cache}(d, P) = \begin{cases} \mathrm{unknown} & d = \bot \\ \mathrm{hit} & d \in P \\ \mathrm{miss} & \text{otherwise} \end{cases}$$
-/
def cacheOf (d : Option String) (present : List String) : String :=
  match d with
  | none => "unknown"
  | some x => if x ∈ present then "hit" else "miss"

#guard canonEngines [.webkit, .chromium, .webkit] == [.chromium, .webkit]

/-- A well-formed request for the guards: $$\mathrm{reqProblems}(\mathrm{exReq}) = [\,]$$ -/
def exReq : Request :=
  { preset := "original", fw := [], engines := ["webkit", "chromium", "webkit"], profile := "swipe-v1", runs := 3,
    sha := "0123456789abcdef0123456789abcdef01234567", images := [] }

#guard reqProblems exReq == []
#guard (reqProblems { exReq with preset := "Orig", fw := [("a", "b"), ("a", "c")], engines := [], runs := 1, sha := "xyz", images := [("tablet", "x")] }).length == 6
#guard imageOf exReq .webkit == "runner:xcode-27"
#guard imageOf { exReq with images := [("webkit", "sha256:0000000000000000000000000000000000000000000000000000000000000000")] } .webkit
  == "sha256:0000000000000000000000000000000000000000000000000000000000000000"
#guard (plan exReq).map (·.engine) == [.chromium, .webkit]
#guard blocked .webkit { exReq with fw := [("hero.countdown", "strip")] } == some "fw"
#guard blocked .chromium { exReq with profile := "swipe-wheel-v1" } == none
#guard cacheOf (some "a") ["a"] == "hit"
#guard cacheOf (some "b") ["a"] == "miss"
#guard cacheOf none ["a"] == "unknown"

end Fw.Store
