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
or rewrite), preset, flags, profile, git sha and the image the run executed in, and lists its artifacts as
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

/-! ## Targets -/

/-- The page a run measures: the original site (the unmodified snapshot) or the rewrite (`apps/site`).

$$\mathrm{Target} = \{\mathrm{original}, \mathrm{rewrite}\}$$
-/
inductive Target where
  | original
  | rewrite
deriving DecidableEq, Repr

/-- Wire name of a target (the values of the `target` input of chromium-counts.yml).

$$\operatorname{name}(\mathrm{original}) = \texttt{"original"},\quad \operatorname{name}(\mathrm{rewrite}) = \texttt{"rewrite"}$$
-/
def Target.name : Target → String
  | .original => "original"
  | .rewrite => "rewrite"

/-- A target from its wire name (`both`, which the workflow also accepts, is not one target).

$$\operatorname{ofName}(s) = \begin{cases} \mathrm{original} & s = \texttt{"original"} \\ \mathrm{rewrite} & s = \texttt{"rewrite"} \\ \bot & \text{otherwise} \end{cases}$$
-/
def Target.ofName : String → Option Target
  | "original" => some .original
  | "rewrite" => some .rewrite
  | _ => none

/-- Target names round-trip.

$$\forall t:\ \operatorname{ofName}(\operatorname{name}(t)) = \mathrm{some}\ t$$
-/
theorem Target.ofName_name (t : Target) : Target.ofName t.name = some t := by
  cases t <;> rfl

/-- A target is the target of its name.

$$\forall s, t:\ \operatorname{ofName}(s) = \mathrm{some}\ t \Rightarrow \operatorname{name}(t) = s$$
-/
theorem Target.name_ofName {s : String} {t : Target} (h : Target.ofName s = some t) : t.name = s := by
  unfold Target.ofName at h
  split at h <;> first | (cases h; rfl) | cases h

/-- Target names are injective.

$$\forall t, t':\ \operatorname{name}(t) = \operatorname{name}(t') \Rightarrow t = t'$$
-/
theorem Target.name_inj {t t' : Target} (h : t.name = t'.name) : t = t' := by
  cases t <;> cases t' <;> first | rfl | (exact absurd h (by decide))

#guard Target.ofName "both" == none

/-- The default preset name (with no flags and `defaultProfile` it is the default configuration).

$$\mathrm{defaultPreset} = \texttt{original}$$
-/
def defaultPreset : String := "original"

/-- The configuration fits the target: presets and flags exist only in the rewrite, so the original target takes the
default preset and no flag (chromium-counts.yml refuses `target=original` with a preset or flags).

$$\operatorname{fits}(t, p, F) \iff t \ne \texttt{original} \lor (p = \mathrm{defaultPreset} \land F = [\,])$$
-/
def targetFits (target preset : String) (fw : List (String × String)) : Bool :=
  target != "original" || (preset == defaultPreset && fw.isEmpty)

#guard targetFits "rewrite" "strip-demo" [("a", "b")] && targetFits "original" "original" []
#guard !targetFits "original" "strip-demo" [] && !targetFits "original" "original" [("a", "b")]

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

/-- A flag part: like `isId`, but letters after the first may also be upper case, because the
site's part ids are camelCase (`nav.hitTest`).

$$\operatorname{isPart}(s) \iff 1 \le |s| \le 64 \land s_0 \in [a\text{-}z0\text{-}9] \land \forall c \in s:\ c \in [a\text{-}zA\text{-}Z0\text{-}9\_.\text{-}]$$
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

/-- What one run measured and where its bytes are, as read from the wire: the engine and the target are names (strings
checked by `problems`), the flags are (part, variant) pairs.

$$\mathrm{Manifest} = (\mathit{engine}, \mathit{target}, \mathit{preset}, \mathit{fw}, \mathit{profile}, \mathit{gitSha}, \mathit{image}, \mathit{runId}, \mathit{entries}) \in \mathrm{String}^{3} \times (\mathrm{String} \times \mathrm{String})^{*} \times \mathrm{String}^{4} \times \mathrm{Entry}^{*}$$
-/
structure Manifest where
  engine : String
  target : String
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

$$\forall F:\ \operatorname{flagsOk}(F) \Rightarrow \text{the parts of } F \text{ are pairwise distinct}$$
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

$$\forall E:\ \operatorname{entriesSorted}(E) \Rightarrow \text{the names of } E \text{ are pairwise distinct}$$
-/
theorem entriesSorted_nodup {es : List Entry} (h : entriesSorted es = true) :
    (es.map (·.name)).Nodup := by
  have h' : es.Pairwise (fun a b => a.name < b.name) := by simpa [entriesSorted] using h
  rw [List.nodup_iff_pairwise_ne, List.pairwise_map]
  exact h'.imp (fun {a b} hab => fun e => String.lt_irrefl _ (e ▸ hab))

/-- Every problem of a manifest, as a message (empty = valid).

$$\begin{aligned} \operatorname{problems}(m) ={} & [\texttt{engine: unknown} \mid \operatorname{ofName}(m.\mathit{engine}) = \bot] \mathbin{+\!\!+} [\texttt{target: not original or rewrite} \mid \operatorname{ofName}_{\mathrm{Target}}(m.\mathit{target}) = \bot] \\ & \mathbin{+\!\!+} [\texttt{target: original takes no preset or flags} \mid \neg\operatorname{fits}(m.\mathit{target}, m.\mathit{preset}, m.\mathit{fw})] \mathbin{+\!\!+} [\texttt{preset: not an id} \mid \neg\operatorname{isId}(m.\mathit{preset})] \mathbin{+\!\!+} [\texttt{profile: not an id} \mid \neg\operatorname{isId}(m.\mathit{profile})] \\ & \mathbin{+\!\!+} [\texttt{fw: parts must be strictly increasing} \mid \neg\operatorname{flagsOk}(m.\mathit{fw})] \mathbin{+\!\!+} [\texttt{fw: part and variant must be ids} \mid \exists (a, v) \in m.\mathit{fw}:\ \neg\operatorname{isPart}(a) \lor \neg\operatorname{isId}(v)] \\ & \mathbin{+\!\!+} [\texttt{gitSha: not 40 hex digits} \mid \neg\operatorname{isHex}_{40}(m.\mathit{gitSha})] \mathbin{+\!\!+} [\texttt{image: not sha256:<64 hex> or runner:<id>} \mid \neg\operatorname{imageOk}(m.\mathit{image})] \\ & \mathbin{+\!\!+} [\texttt{runId: not digits} \mid m.\mathit{runId} = \varepsilon \lor \exists c \in m.\mathit{runId}:\ c \notin \{\texttt{0}..\texttt{9}\}] \mathbin{+\!\!+} [\texttt{entries: names must be strictly increasing} \mid \neg\operatorname{entriesSorted}(m.\mathit{entries})] \\ & \mathbin{+\!\!+} [\texttt{entries: name escapes the run directory} \mid \exists e \in m.\mathit{entries}:\ \neg\operatorname{safeName}(e.\mathit{name})] \\ & \mathbin{+\!\!+} [\texttt{entries: digest not 64 hex digits} \mid \exists e \in m.\mathit{entries}:\ \neg\operatorname{isHex}_{64}(e.\mathit{digest})] \end{aligned}\qquad \text{where } [x \mid c] = \begin{cases} [x] & c \\ [\,] & \neg c \end{cases} \text{ (the messages come in this order)}$$
-/
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
  (if m.entries.all (fun e => isHex 64 e.digest) then [] else ["entries: digest not 64 hex digits"])

/-- A manifest is valid when it has no problem.

$$\operatorname{valid}(m) \iff \operatorname{problems}(m) = [\,]$$
-/
def Manifest.valid (m : Manifest) : Bool := m.problems.isEmpty

/-- A valid manifest names a known engine.

$$\forall m:\ \operatorname{valid}(m) \Rightarrow \exists e:\ \operatorname{ofName}(m.\mathrm{engine}) = \mathrm{some}\ e$$
-/
theorem Manifest.valid_engine {m : Manifest} (h : m.valid = true) :
    ∃ e, Engine.ofName m.engine = some e := by
  simp only [valid, problems, List.isEmpty_iff, List.append_eq_nil_iff] at h
  have h1 := h.1.1.1.1.1.1.1.1.1.1.1.1
  by_cases hs : (Engine.ofName m.engine).isSome
  · exact Option.isSome_iff_exists.mp hs
  · simp [hs] at h1

/-- A valid manifest names a known target, and its configuration fits that target.

$$\forall m:\ \operatorname{valid}(m) \Rightarrow (\exists t:\ \operatorname{ofName}_{\mathrm{Target}}(m.\mathrm{target}) = \mathrm{some}\ t) \land \operatorname{fits}(m.\mathrm{target}, m.\mathrm{preset}, m.\mathrm{fw})$$
-/
theorem Manifest.valid_target {m : Manifest} (h : m.valid = true) :
    (∃ t, Target.ofName m.target = some t) ∧ targetFits m.target m.preset m.fw = true := by
  simp only [valid, problems, List.isEmpty_iff, List.append_eq_nil_iff] at h
  have h1 := h.1.1.1.1.1.1.1.1.1.1.1.2
  have h2 := h.1.1.1.1.1.1.1.1.1.1.2
  constructor
  · by_cases hs : (Target.ofName m.target).isSome
    · exact Option.isSome_iff_exists.mp hs
    · simp [hs] at h1
  · by_cases hs : targetFits m.target m.preset m.fw = true
    · exact hs
    · simp [hs] at h2

/-- A valid manifest has sorted, hence name-distinct, entries with 64-hex digests.

$$\forall m:\ \operatorname{valid}(m) \Rightarrow \text{entry names pairwise distinct} \land \forall e \in m.\mathrm{entries}:\ \operatorname{isHex}_{64}(e.\mathrm{digest})$$
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

/-- What a run's identity depends on. `target` selects the page (original or rewrite), `preset` and the flags the
site configuration, `profile` the scroll script, `sha` the code, `image` the browser build and machine.

$$\mathrm{Req} = \mathrm{Engine} \times \mathrm{Target} \times \mathrm{Preset} \times \mathrm{Flags} \times \mathrm{Profile} \times \mathrm{Sha} \times \mathrm{Image}$$
-/
structure Req where
  engine : Engine
  target : Target
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

$$\forall a, b:\ \operatorname{flagPairs}(a) = \operatorname{flagPairs}(b) \Rightarrow a = b$$
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

Version 2 added the target (version 1 keys had none, so an original and a rewrite run shared one key).

$$\operatorname{keyPairs}(r) = [(\texttt{v}, \texttt{2}), (\texttt{engine}, \operatorname{name}(r.\mathrm{engine})), (\texttt{target}, \operatorname{name}(r.\mathrm{target})), (\texttt{preset}, r.\mathrm{preset}), (\texttt{profile}, r.\mathrm{profile}), (\texttt{sha}, r.\mathrm{sha}), (\texttt{image}, r.\mathrm{image})] \mathbin{+\!\!+} \operatorname{flagPairs}(r.\mathrm{fw})$$
-/
def keyPairs (r : Req) : List (String × String) :=
  [("v", "2"), ("engine", r.engine.name), ("target", r.target.name), ("preset", r.preset), ("profile", r.profile),
   ("sha", r.sha), ("image", r.image)] ++ flagPairs r.fw

/-- **Distinct configurations never share the input of the key hash.**

$$\forall r, r':\ \operatorname{keyPairs}(r) = \operatorname{keyPairs}(r') \Rightarrow r = r'$$
-/
theorem keyPairs_inj {r r' : Req} (h : keyPairs r = keyPairs r') : r = r' := by
  simp only [keyPairs, List.cons_append, List.nil_append, List.cons.injEq, Prod.mk.injEq] at h
  obtain ⟨_, ⟨_, he⟩, ⟨_, ht⟩, ⟨_, hp⟩, ⟨_, hr⟩, ⟨_, hs⟩, ⟨_, hi⟩, hf⟩ := h
  have hf := flagPairs_inj hf
  cases r; cases r'
  simp only at *
  rw [Engine.name_inj he, Target.name_inj ht, hp, hr, hs, hi, hf]

/-- **Different targets give different keys:** an original run and a rewrite run never share a key, whatever else they
have in common.

$$\forall r, r':\ r.\mathrm{target} \ne r'.\mathrm{target} \Rightarrow \operatorname{keyPairs}(r) \ne \operatorname{keyPairs}(r')$$
-/
theorem keyPairs_target_ne {r r' : Req} (h : r.target ≠ r'.target) : keyPairs r ≠ keyPairs r' :=
  fun hk => h (congrArg Req.target (keyPairs_inj hk))

/-- The run identity a manifest records, when its engine and target are known names.

$$\operatorname{req}(m) = \begin{cases} \mathrm{some}\ (e, t, m.\mathrm{preset}, m.\mathrm{fw}, m.\mathrm{profile}, m.\mathrm{gitSha}, m.\mathrm{image}) & \operatorname{ofName}(m.\mathrm{engine}) = \mathrm{some}\ e \land \operatorname{ofName}_{\mathrm{Target}}(m.\mathrm{target}) = \mathrm{some}\ t \\ \bot & \text{otherwise} \end{cases}$$
-/
def Manifest.req (m : Manifest) : Option Req :=
  match Engine.ofName m.engine, Target.ofName m.target with
  | some e, some t => some { engine := e, target := t, preset := m.preset, fw := m.fw, profile := m.profile,
                             sha := m.gitSha, image := m.image }
  | _, _ => none

/-- **A valid manifest has a key**, and its key records the manifest's target name.

$$\forall m:\ \operatorname{valid}(m) \Rightarrow \exists r:\ \operatorname{req}(m) = \mathrm{some}\ r \land (\texttt{target}, m.\mathrm{target}) \in \operatorname{keyPairs}(r)$$
-/
theorem Manifest.valid_req {m : Manifest} (h : m.valid = true) :
    ∃ r, m.req = some r ∧ ("target", m.target) ∈ keyPairs r := by
  obtain ⟨e, he⟩ := Manifest.valid_engine h
  obtain ⟨⟨t, ht⟩, _⟩ := Manifest.valid_target h
  refine ⟨{ engine := e, target := t, preset := m.preset, fw := m.fw, profile := m.profile, sha := m.gitSha,
            image := m.image }, by simp [Manifest.req, he, ht], ?_⟩
  simp [keyPairs, Target.name_ofName ht]

/-! ## The plan of `fw run` -/

/-- A run request as the user typed it, before validation: engine names may be unknown or repeated, and the image
pins are an association list from engine name to image (first match wins, unknown names allowed until `reqProblems`).

The target is a name too (checked by `reqProblems`).

$$\mathrm{Request} = (\mathit{target}, \mathit{preset}, \mathit{fw}, \mathit{engines}, \mathit{profile}, \mathit{runs}, \mathit{sha}, \mathit{images}) \in \mathrm{String} \times \mathrm{String} \times (\mathrm{String} \times \mathrm{String})^{*} \times \mathrm{String}^{*} \times \mathrm{String} \times \mathbb{N} \times \mathrm{String} \times (\mathrm{String} \times \mathrm{String})^{*}$$
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

/-- The `workflow_dispatch` inputs a workflow declares (as of its file in `.github/workflows/`; chromium-counts.yml
gained `target`, `preset`, `fw` and `image_run` with the rewrite lane).

$$\operatorname{inputs}(\mathrm{chromium}) = [\texttt{profile}, \texttt{runs}, \texttt{target}, \texttt{preset}, \texttt{fw}, \texttt{image\_run}],\quad \operatorname{inputs}(\mathrm{webkit}) = [\texttt{vms}, \texttt{sessions}, \texttt{fresh\_boot}]$$
-/
def workflowInputs : Engine → List String
  | .chromium => ["profile", "runs", "target", "preset", "fw", "image_run"]
  | .webkit => ["vms", "sessions", "fresh_boot"]

/-- The `fw` dispatch input: the flags as `part:variant`, joined by commas (empty for no flag).

$$\operatorname{fwInput}([(a_1, v_1), \dots, (a_k, v_k)]) = a_1\texttt{:}v_1\texttt{,}\dots\texttt{,}a_k\texttt{:}v_k,\qquad \operatorname{fwInput}([\,]) = \varepsilon$$
-/
def fwInput (fw : List (String × String)) : String :=
  ",".intercalate (fw.map fun p => p.1 ++ ":" ++ p.2)

#guard fwInput [] == ""
#guard fwInput [("hero.countdown", "strip"), ("nav.hitTest", "hit-skip")] == "hero.countdown:strip,nav.hitTest:hit-skip"

/-- The request fields that differ from a fixed workflow's built-in configuration (the original site, the default
profile, preset and flags), so the workflow must accept them as inputs.

$$\operatorname{needs}(q) = [\texttt{target} \mid q.\mathrm{target} \ne \texttt{original}] \mathbin{+\!\!+} [\texttt{profile} \mid q.\mathrm{profile} \ne \mathrm{defaultProfile}] \mathbin{+\!\!+} [\texttt{preset} \mid q.\mathrm{preset} \ne \texttt{original}] \mathbin{+\!\!+} [\texttt{fw} \mid q.\mathrm{fw} \ne [\,]]$$
-/
def needs (q : Request) : List String :=
  (if q.target == Target.original.name then [] else ["target"]) ++
  (if q.profile == defaultProfile then [] else ["profile"]) ++
  (if q.preset == defaultPreset then [] else ["preset"]) ++
  (if q.fw.isEmpty then [] else ["fw"])

/-- The dispatch inputs: the engine's own, from the request. Chromium takes the profile, the run count (in decimal),
the target (always sent, so the workflow never falls back to its default `both`), the preset and the flags
(`image_run` keeps its default); WebKit takes none of the request (its experiment is fixed).

$$\operatorname{dispatch}(\mathrm{chromium}, q) = [(\texttt{profile}, q.\mathrm{profile}), (\texttt{runs}, \operatorname{dec}(q.\mathrm{runs})), (\texttt{target}, q.\mathrm{target}), (\texttt{preset}, q.\mathrm{preset}), (\texttt{fw}, \operatorname{fwInput}(q.\mathrm{fw}))],\quad \operatorname{dispatch}(\mathrm{webkit}, q) = [\,]$$
-/
def dispatchInputs (e : Engine) (q : Request) : List (String × String) :=
  match e with
  | .chromium => [("profile", q.profile), ("runs", toString q.runs), ("target", q.target), ("preset", q.preset),
                  ("fw", fwInput q.fw)]
  | .webkit => []

/-- **Chromium is told the target:** its dispatch inputs carry the request's target, never the workflow default.

$$\forall q:\ (\texttt{target}, q.\mathrm{target}) \in \operatorname{dispatch}(\mathrm{chromium}, q)$$
-/
theorem dispatch_target (q : Request) : ("target", q.target) ∈ dispatchInputs .chromium q := by
  simp [dispatchInputs]

/-- Why a job cannot run: the first needed field its workflow has no input for.

$$\operatorname{blocked}(e, q) = \begin{cases} \bot & \forall x \in \operatorname{needs}(q):\ x \in \operatorname{inputs}(e) \\ \text{the first } x \text{ not in } \operatorname{inputs}(e) & \text{otherwise} \end{cases}$$
-/
def blocked (e : Engine) (q : Request) : Option String :=
  (needs q).find? (fun x => !(workflowInputs e).contains x)

/-- **A job that is not blocked can express everything the request needs.**

$$\forall e, q:\ \operatorname{blocked}(e, q) = \bot \Rightarrow \forall x \in \operatorname{needs}(q):\ x \in \operatorname{inputs}(e)$$
-/
theorem blocked_none_sound {e : Engine} {q : Request} (h : blocked e q = none) :
    ∀ x ∈ needs q, x ∈ workflowInputs e := by
  intro x hx
  have := (List.find?_eq_none.mp h) x hx
  simpa using this

/-- **The Chromium workflow can express every request:** a chromium job is never blocked.

$$\forall q:\quad \operatorname{blocked}(\mathrm{chromium}, q) = \bot$$
-/
theorem blocked_chromium (q : Request) : blocked .chromium q = none := by
  unfold blocked needs
  apply List.find?_eq_none.mpr
  intro x hx
  simp only [List.mem_append] at hx
  rcases hx with ((hx | hx) | hx) | hx <;> split at hx <;> simp_all [workflowInputs]

/-- **A chromium job sends what the request needs:** every needed field is a key of its dispatch inputs.

$$\forall q, x:\quad x \in \operatorname{needs}(q) \Rightarrow \exists v:\ (x, v) \in \operatorname{dispatch}(\mathrm{chromium}, q)$$
-/
theorem needs_dispatched (q : Request) (x : String) (hx : x ∈ needs q) :
    ∃ v, (x, v) ∈ dispatchInputs .chromium q := by
  unfold needs at hx
  simp only [List.mem_append] at hx
  rcases hx with ((hx | hx) | hx) | hx <;> split at hx <;> simp_all [dispatchInputs]

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

$$\begin{aligned} \operatorname{reqProblems}(q) ={} & [\texttt{engines: none given} \mid q.\mathit{engines} = [\,]] \mathbin{+\!\!+} [\texttt{engines: unknown name} \mid \exists n \in q.\mathit{engines}:\ \operatorname{ofName}(n) = \bot] \\ & \mathbin{+\!\!+} [\texttt{target: not original or rewrite} \mid \operatorname{ofName}_{\mathrm{Target}}(q.\mathit{target}) = \bot] \mathbin{+\!\!+} [\texttt{target: original takes no preset or flags} \mid \neg\operatorname{fits}(q.\mathit{target}, q.\mathit{preset}, q.\mathit{fw})] \\ & \mathbin{+\!\!+} [\texttt{preset: not an id} \mid \neg\operatorname{isId}(q.\mathit{preset})] \mathbin{+\!\!+} [\texttt{profile: not an id} \mid \neg\operatorname{isId}(q.\mathit{profile})] \\ & \mathbin{+\!\!+} [\texttt{fw: part and variant must be ids} \mid \exists (a, v) \in q.\mathit{fw}:\ \neg\operatorname{isPart}(a) \lor \neg\operatorname{isId}(v)] \mathbin{+\!\!+} [\texttt{fw: a part appears twice} \mid \neg\operatorname{flagsOk}(q.\mathit{fw})] \\ & \mathbin{+\!\!+} [\texttt{runs: must be 2 to 10} \mid \neg(2 \le q.\mathit{runs} \le 10)] \mathbin{+\!\!+} [\texttt{sha: not 40 hex digits} \mid \neg\operatorname{isHex}_{40}(q.\mathit{sha})] \\ & \mathbin{+\!\!+} [\texttt{images: unknown engine or bad image} \mid \exists (n, i) \in q.\mathit{images}:\ \operatorname{ofName}(n) = \bot \lor \neg\operatorname{imageOk}(i)] \end{aligned}$$

where $[x \mid c]$ is $[x]$ when $c$ holds and $[\,]$ otherwise; the messages come in this order. `flagsOk` checks the
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
  (if q.images.all (fun p => (Engine.ofName p.1).isSome && imageOk p.2) then [] else ["images: unknown engine or bad image"])

/-- The jobs of a request for one target: one per distinct requested engine, in canonical order.

$$\operatorname{jobsFor}(q, t) = [\,(e, \operatorname{workflow}(e), \operatorname{dispatch}(e, q), \operatorname{keyPairs}((e, t, q.\mathit{preset}, q.\mathit{fw}, q.\mathit{profile}, q.\mathit{sha}, \operatorname{imageOf}(q, e))), \operatorname{blocked}(e, q)) \mid e \in \operatorname{canon}(E_q)\,],\quad \text{where } E_q = [\,\operatorname{ofName}(n) \mid n \in q.\mathit{engines},\ \operatorname{ofName}(n) \ne \bot\,] \text{ (unknown names dropped); the tuple is (engine, workflow, inputs, key, blocked) and the inner tuple is a } \texttt{Req}$$
-/
def jobsFor (q : Request) (t : Target) : List Job :=
  let es := canonEngines (q.engines.filterMap Engine.ofName)
  es.map fun e =>
    { engine := e, workflow := workflowOf e, inputs := dispatchInputs e q, blocked := blocked e q,
      key := keyPairs { engine := e, target := t, preset := q.preset, fw := q.fw, profile := q.profile, sha := q.sha,
                        image := imageOf q e } }

/-- The jobs of a request: those for its target, none when the target is not a known name.

$$\operatorname{jobs}(q) = \begin{cases} \operatorname{jobsFor}(q, t) & \operatorname{ofName}_{\mathrm{Target}}(q.\mathit{target}) = \mathrm{some}\ t \\ [\,] & \operatorname{ofName}_{\mathrm{Target}}(q.\mathit{target}) = \bot \end{cases}$$
-/
def jobsOf (q : Request) : List Job :=
  match Target.ofName q.target with
  | some t => jobsFor q t
  | none => []

/-- The plan: the jobs when the request is well formed, no job otherwise.

$$\operatorname{plan}(q) = \begin{cases} \operatorname{jobs}(q) & \operatorname{reqProblems}(q) = [\,] \\ [\,] & \text{otherwise} \end{cases}$$
-/
def plan (q : Request) : List Job := if (reqProblems q).isEmpty then jobsOf q else []

/-- **A refused request plans nothing.**

$$\forall q:\ \operatorname{reqProblems}(q) \ne [\,] \Rightarrow \operatorname{plan}(q) = [\,]$$
-/
theorem plan_nil_of_problems {q : Request} (h : reqProblems q ≠ []) : plan q = [] := by
  simp [plan, h]

/-- **An accepted request names a known target that fits its configuration.**

$$\forall q:\ \operatorname{reqProblems}(q) = [\,] \Rightarrow (\exists t:\ \operatorname{ofName}_{\mathrm{Target}}(q.\mathrm{target}) = \mathrm{some}\ t) \land \operatorname{fits}(q.\mathrm{target}, q.\mathrm{preset}, q.\mathrm{fw})$$
-/
theorem reqProblems_nil_target {q : Request} (h : reqProblems q = []) :
    (∃ t, Target.ofName q.target = some t) ∧ targetFits q.target q.preset q.fw = true := by
  simp only [reqProblems, List.append_eq_nil_iff] at h
  have h1 := h.1.1.1.1.1.1.1.1.2
  have h2 := h.1.1.1.1.1.1.1.2
  constructor
  · by_cases hs : (Target.ofName q.target).isSome
    · exact Option.isSome_iff_exists.mp hs
    · simp [hs] at h1
  · by_cases hs : targetFits q.target q.preset q.fw = true
    · exact hs
    · simp [hs] at h2

/-- The plan of an accepted request is the job list for its target.

$$\forall q, t:\ \operatorname{reqProblems}(q) = [\,] \land \operatorname{ofName}_{\mathrm{Target}}(q.\mathrm{target}) = \mathrm{some}\ t \Rightarrow \operatorname{plan}(q) = \operatorname{jobsFor}(q, t)$$
-/
theorem plan_eq_jobsFor {q : Request} {t : Target} (h : reqProblems q = []) (ht : Target.ofName q.target = some t) :
    plan q = jobsFor q t := by
  simp [plan, h, jobsOf, ht]

/-- **One job per distinct engine.** The engines of a plan are exactly the requested ones, in
canonical order, with no repeat.

$$\forall q:\ \operatorname{reqProblems}(q) = [\,] \Rightarrow \operatorname{engines}(\operatorname{plan}(q)) = \operatorname{canon}(E_q)\ \land\ \operatorname{engines}(\operatorname{plan}(q))\ \text{has no repeated element},\quad \text{where } E_q = [\,\operatorname{ofName}(n) \mid n \in q.\mathit{engines},\ \operatorname{ofName}(n) \ne \bot\,],\ \operatorname{engines}(P) = [\,j.\mathrm{engine} \mid j \in P\,]$$
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

$$\forall q:\ \operatorname{reqProblems}(q) = [\,] \Rightarrow \operatorname{flagsOk}(q.\mathrm{fw})$$
-/
theorem reqProblems_nil_flags {q : Request} (h : reqProblems q = []) : flagsOk q.fw = true := by
  simp only [reqProblems, List.append_eq_nil_iff] at h
  by_cases hs : flagsOk q.fw = true
  · exact hs
  · have := h.1.1.1.2; simp [hs] at this

/-- **A job's key carries its engine and the request's flags.** Two jobs of one plan have different
keys (they differ in the engine pair).

$$\forall q:\ \operatorname{reqProblems}(q) = [\,] \Rightarrow \forall j, j' \in \operatorname{plan}(q):\ j.\mathrm{key} = j'.\mathrm{key} \Rightarrow j = j'$$
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

/-- **Every job's key records the request's target.**

$$\forall q:\ \operatorname{reqProblems}(q) = [\,] \Rightarrow \forall j \in \operatorname{plan}(q):\ (\texttt{target}, q.\mathrm{target}) \in j.\mathrm{key}$$
-/
theorem plan_key_target {q : Request} (h : reqProblems q = []) {j : Job} (hj : j ∈ plan q) :
    ("target", q.target) ∈ j.key := by
  obtain ⟨⟨t, ht⟩, _⟩ := reqProblems_nil_target h
  rw [plan_eq_jobsFor h ht] at hj
  simp only [jobsFor, List.mem_map] at hj
  obtain ⟨e, _, rfl⟩ := hj
  simp [keyPairs, Target.name_ofName ht]

/-- **An original run and a rewrite run never share a key.** Two accepted requests with different targets give jobs
with different keys, whatever else (engine, preset, flags, profile, sha, image) they have in common.

$$\forall q, q':\ \operatorname{reqProblems}(q) = [\,] \land \operatorname{reqProblems}(q') = [\,] \land q.\mathrm{target} \ne q'.\mathrm{target} \Rightarrow \forall j \in \operatorname{plan}(q),\ j' \in \operatorname{plan}(q'):\ j.\mathrm{key} \ne j'.\mathrm{key}$$
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

/-- A well-formed request for the guards (the `#guard` below checks $\operatorname{reqProblems}(\mathrm{exReq}) = [\,]$).

$$\mathrm{exReq} = (\texttt{original}, \texttt{original}, [\,], [\texttt{webkit}, \texttt{chromium}, \texttt{webkit}], \texttt{swipe-v1}, 3, \texttt{0123456789abcdef0123456789abcdef01234567}, [\,])$$

in the field order (target, preset, fw, engines, profile, runs, sha, images).
-/
def exReq : Request :=
  { target := "original", preset := "original", fw := [], engines := ["webkit", "chromium", "webkit"],
    profile := "swipe-v1", runs := 3, sha := "0123456789abcdef0123456789abcdef01234567", images := [] }

/-- `exReq` on the rewrite with a preset and one flag (accepted too).

$$\mathrm{exRw} = \mathrm{exReq}[\mathit{target} := \texttt{rewrite}, \mathit{preset} := \texttt{strip-demo}, \mathit{fw} := [(\texttt{hero.countdown}, \texttt{strip})]]$$
-/
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
#guard (plan exRw).map (·.blocked) == [none, some "target"]
#guard ((plan exReq).map (·.key)).all (·.contains ("target", "original"))
#guard ((plan { exReq with target := "rewrite" }).map (·.key)).all (·.contains ("target", "rewrite"))
#guard (plan exReq).map (·.key) != (plan { exReq with target := "rewrite" }).map (·.key)
#guard blocked .webkit { exRw with target := "original" } == some "preset"
#guard blocked .webkit { exReq with profile := "swipe-wheel-v1" } == some "profile"
#guard blocked .chromium { exReq with profile := "swipe-wheel-v1" } == none
#guard blocked .chromium exRw == none
#guard blocked .webkit exRw == some "target"
#guard dispatchInputs .chromium exRw
  == [("profile", "swipe-v1"), ("runs", "3"), ("target", "rewrite"), ("preset", "strip-demo"), ("fw", "hero.countdown:strip")]
#guard dispatchInputs .webkit exRw == []
#guard cacheOf (some "a") ["a"] == "hit"
#guard cacheOf (some "b") ["a"] == "miss"
#guard cacheOf none ["a"] == "unknown"

end Fw.Store
