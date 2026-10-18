/-!
# Result-cache soundness (task `gate-speed-ci`; reused by `land-speed`)

A CI check or install is a function of its **declared inputs**: the list `decl` of input names the
step reads (a pinned version, the runner image, a dependency list, a file hash). A cache stores the
result under a **key** computed from the declared inputs only. This module proves, for any such
check, that

* equal keys give equal results (`key_sound`), so a cache hit is the fresh result (`cache_sound`);
* a change to any declared input changes the key (`key_complete`), so no stale entry is ever hit;
* the key ignores everything that is not declared (`key_congr`), so a hit is not lost for nothing.

Nothing here knows about GitHub, apt or Playwright; `actions/cache` is one instance (its key string is
the serialised declared inputs, `hashFiles` is one more hash).

**Premises, stated and not hidden.**

* `CollisionFree hash`: the hash of two different declared-input vectors differs. For SHA-256 this is
  a computational assumption, not a theorem; the module takes it as an explicit hypothesis of the
  theorems that need it (`key_complete`, `key_sound`, `cache_sound`).
* `DependsOnlyOn decl run`: the check reads nothing but the declared inputs. This is the contract of
  the workflow author (an undeclared input, such as the date or the network, breaks it) and is the
  one thing a Lean proof cannot check; the golden file `golden/ops/cache.jsonl` lists the declared
  inputs of every cache in the repository and a test checks each appears in the cache key.
* A partial-key fallback (`restore-keys`) is NOT modelled: it looks up a key that covers fewer inputs
  than `decl`, which `key_complete` cannot cover. Do not use it for a result cache. (Lake's artifact
  cache, the last section, may use it: there an entry is a set of artifacts that Lake re-checks one by
  one against their traces (a premise about Lake, not proved here), so a fallback entry can only cost
  rebuilds, which `rebuild_in_cone` bounds.)
-/
namespace Fw.Ops.Cache

/-- The values of all named inputs of the world a step runs in (a version string, an image tag, ...).

$$\mathrm{Env} = \mathrm{Name} \to \mathrm{Value}$$
-/
abbrev Env := String → String

/-- The declared-input vector: the declared names with their values in `e`, in declaration order.

$$\operatorname{declared}(D, e) = \big( (n, e(n)) \big)_{n \in D}$$
-/
def declared (decl : List String) (e : Env) : List (String × String) :=
  decl.map fun n => (n, e n)

/-- The cache key: a hash of the declared-input vector.

$$\operatorname{key}_h(D, e) = h\big(\operatorname{declared}(D, e)\big)$$
-/
def key {K : Type} (h : List (String × String) → K) (decl : List String) (e : Env) : K :=
  h (declared decl e)

/-- The hash separates different declared-input vectors (the explicit collision-freeness premise).

$$\operatorname{CollisionFree}(h) \iff \forall a, b.\; h(a) = h(b) \Rightarrow a = b$$
-/
def CollisionFree {K : Type} (h : List (String × String) → K) : Prop :=
  ∀ a b, h a = h b → a = b

/-- The check reads only its declared inputs: two worlds that agree on every declared name give the
same result.

$$\operatorname{DependsOnlyOn}(D, f) \iff \forall e, e'.\; (\forall n \in D.\; e(n) = e'(n)) \Rightarrow f(e) = f(e')$$
-/
def DependsOnlyOn {R : Type} (decl : List String) (run : Env → R) : Prop :=
  ∀ e e' : Env, (∀ n ∈ decl, e n = e' n) → run e = run e'

/-- Two worlds have the same declared-input vector exactly when they agree on every declared name.

$$\operatorname{declared}(D, e) = \operatorname{declared}(D, e') \iff \forall n \in D.\; e(n) = e'(n)$$
-/
theorem declared_eq_iff (decl : List String) (e e' : Env) :
    declared decl e = declared decl e' ↔ ∀ n ∈ decl, e n = e' n := by
  induction decl with
  | nil => simp [declared]
  | cons a l ih =>
    simp only [declared, List.map_cons, List.cons.injEq, Prod.mk.injEq, true_and, List.mem_cons,
      forall_eq_or_imp] at *
    rw [ih]

/-- The key ignores undeclared inputs: worlds that agree on every declared name get the same key
(for any hash, no premise).

$$(\forall n \in D.\; e(n) = e'(n)) \Rightarrow \operatorname{key}_h(D, e) = \operatorname{key}_h(D, e')$$
-/
theorem key_congr {K : Type} (h : List (String × String) → K) (decl : List String) (e e' : Env)
    (hagree : ∀ n ∈ decl, e n = e' n) : key h decl e = key h decl e' := by
  unfold key
  rw [(declared_eq_iff decl e e').2 hagree]

/-- **Key completeness.** If any declared input changes, the key changes, provided the hash is
collision-free.

$$\operatorname{CollisionFree}(h) \wedge \big(\exists n \in D.\; e(n) \ne e'(n)\big) \Rightarrow \operatorname{key}_h(D, e) \ne \operatorname{key}_h(D, e')$$
-/
theorem key_complete {K : Type} (h : List (String × String) → K) (hcf : CollisionFree h)
    (decl : List String) (e e' : Env) (hdiff : ∃ n ∈ decl, e n ≠ e' n) :
    key h decl e ≠ key h decl e' := by
  intro heq
  have hd := hcf _ _ heq
  obtain ⟨n, hn, hne⟩ := hdiff
  exact hne ((declared_eq_iff decl e e').1 hd n hn)

/-- The key is equal exactly when every declared input is equal (completeness and congruence in one).

$$\operatorname{CollisionFree}(h) \Rightarrow \big(\operatorname{key}_h(D, e) = \operatorname{key}_h(D, e') \iff \forall n \in D.\; e(n) = e'(n)\big)$$
-/
theorem key_eq_iff {K : Type} (h : List (String × String) → K) (hcf : CollisionFree h)
    (decl : List String) (e e' : Env) :
    key h decl e = key h decl e' ↔ ∀ n ∈ decl, e n = e' n :=
  ⟨fun heq => (declared_eq_iff decl e e').1 (hcf _ _ heq), key_congr h decl e e'⟩

/-- **Equal keys give equal results.** For a check that reads only its declared inputs, two worlds
with the same key produce the same result.

$$\operatorname{CollisionFree}(h) \wedge \operatorname{DependsOnlyOn}(D, f) \wedge \operatorname{key}_h(D, e) = \operatorname{key}_h(D, e') \Rightarrow f(e) = f(e')$$
-/
theorem key_sound {K R : Type} (h : List (String × String) → K) (hcf : CollisionFree h)
    (decl : List String) (run : Env → R) (hdep : DependsOnlyOn decl run) (e e' : Env)
    (hkey : key h decl e = key h decl e') : run e = run e' :=
  hdep e e' ((key_eq_iff h hcf decl e e').1 hkey)

/-! ## The cache itself -/

/-- A result cache: stored `(key, result)` pairs, newest first.

$$\mathrm{Cache}(K, R) = (K \times R)^{*}$$
-/
abbrev Cache (K R : Type) := List (K × R)

/-- Look a key up (the newest entry wins).

$$\operatorname{lookup}(c, k) = r \text{ for the first } (k, r) \in c, \text{ else none}$$
-/
def lookup {K R : Type} [DecidableEq K] (c : Cache K R) (k : K) : Option R :=
  match c.find? (fun p => decide (p.1 = k)) with
  | some p => some p.2
  | none => none

/-- Every stored entry was produced by a fresh run in some world whose key it carries.

$$\operatorname{Valid}(c) \iff \forall (k, r) \in c.\; \exists e.\; \operatorname{key}_h(D, e) = k \wedge f(e) = r$$
-/
def Valid {K R : Type} (h : List (String × String) → K) (decl : List String) (run : Env → R)
    (c : Cache K R) : Prop :=
  ∀ p ∈ c, ∃ e, key h decl e = p.1 ∧ run e = p.2

/-- Get the result for the world `e`: a hit returns the stored result, a miss runs the check and
stores it under its key.

$$\operatorname{getOrRun}(c, e) = \begin{cases} (r, c) & \operatorname{lookup}(c, \operatorname{key}(e)) = r \\ (f(e), (\operatorname{key}(e), f(e)) :: c) & \text{miss} \end{cases}$$
-/
def getOrRun {K R : Type} [DecidableEq K] (h : List (String × String) → K) (decl : List String)
    (run : Env → R) (c : Cache K R) (e : Env) : R × Cache K R :=
  match lookup c (key h decl e) with
  | some r => (r, c)
  | none => (run e, (key h decl e, run e) :: c)

/-- A hit comes from a stored entry with that key.

$$\operatorname{lookup}(c, k) = r \Rightarrow \exists (k', r') \in c.\; k' = k \wedge r' = r$$
-/
theorem lookup_mem {K R : Type} [DecidableEq K] (c : Cache K R) (k : K) (r : R)
    (hl : lookup c k = some r) : ∃ p ∈ c, p.1 = k ∧ p.2 = r := by
  unfold lookup at hl
  split at hl
  · rename_i p hp
    have := List.find?_some hp
    have hmem := List.mem_of_find?_eq_some hp
    simp at hl this
    exact ⟨p, hmem, by simpa using this, hl⟩
  · simp at hl

/-- **Cache soundness, one step.** Starting from a valid cache, a get-or-run returns exactly the
fresh result, hit or miss, and the cache stays valid.

$$\operatorname{CollisionFree}(h) \wedge \operatorname{DependsOnlyOn}(D, f) \wedge \operatorname{Valid}(c) \Rightarrow \operatorname{getOrRun}(c, e).1 = f(e) \wedge \operatorname{Valid}(\operatorname{getOrRun}(c, e).2)$$
-/
theorem cache_sound {K R : Type} [DecidableEq K] (h : List (String × String) → K)
    (hcf : CollisionFree h) (decl : List String) (run : Env → R) (hdep : DependsOnlyOn decl run)
    (c : Cache K R) (hv : Valid h decl run c) (e : Env) :
    (getOrRun h decl run c e).1 = run e ∧ Valid h decl run (getOrRun h decl run c e).2 := by
  unfold getOrRun
  cases hl : lookup c (key h decl e) with
  | some r =>
    obtain ⟨p, hp, hk, hr⟩ := lookup_mem c _ r hl
    obtain ⟨e', hk', hr'⟩ := hv p hp
    refine ⟨?_, hv⟩
    show r = run e
    rw [← hr, ← hr', eq_comm]
    exact key_sound h hcf decl run hdep e e' (by rw [hk', hk])
  | none =>
    refine ⟨rfl, ?_⟩
    intro p hp
    rcases List.mem_cons.1 hp with rfl | hp
    · exact ⟨e, rfl, rfl⟩
    · exact hv p hp

/-- Run a whole sequence of worlds through one cache (a workflow run after run).

$$\operatorname{runAll}(c, [\,]) = ([\,], c), \quad \operatorname{runAll}(c, e :: es) = (r :: rs, c'') \text{ with } (r, c') = \operatorname{getOrRun}(c, e),\ (rs, c'') = \operatorname{runAll}(c', es)$$
-/
def runAll {K R : Type} [DecidableEq K] (h : List (String × String) → K) (decl : List String)
    (run : Env → R) : Cache K R → List Env → List R × Cache K R
  | c, [] => ([], c)
  | c, e :: es =>
    let s := getOrRun h decl run c e
    let t := runAll h decl run s.2 es
    (s.1 :: t.1, t.2)

/-- **Cache soundness, any history.** From an empty (or valid) cache, a cache shared by any sequence
of runs returns exactly what fresh runs would.

$$\operatorname{CollisionFree}(h) \wedge \operatorname{DependsOnlyOn}(D, f) \wedge \operatorname{Valid}(c) \Rightarrow \operatorname{runAll}(c, es).1 = \operatorname{map}\, f\, es$$
-/
theorem cache_sound_all {K R : Type} [DecidableEq K] (h : List (String × String) → K)
    (hcf : CollisionFree h) (decl : List String) (run : Env → R) (hdep : DependsOnlyOn decl run) :
    ∀ (es : List Env) (c : Cache K R), Valid h decl run c →
      (runAll h decl run c es).1 = es.map run := by
  intro es
  induction es with
  | nil => intro c _; rfl
  | cons e es ih =>
    intro c hv
    obtain ⟨h1, h2⟩ := cache_sound h hcf decl run hdep c hv e
    simp only [runAll, List.map_cons]
    rw [h1, ih _ h2]

/-- The empty cache is valid.

$$\operatorname{Valid}([\,])$$
-/
theorem valid_empty {K R : Type} (h : List (String × String) → K) (decl : List String)
    (run : Env → R) : Valid h decl run ([] : Cache K R) := by
  intro p hp; simp at hp

/-- **A key that leaves out a read input is unsound.** If two worlds agree on every name of the key
but the check gives different results, they share a key and a hit would return a wrong result.
(Why a partial key such as a `restore-keys` prefix is refused.)

$$\big(\forall n \in D_k.\; e(n) = e'(n)\big) \wedge f(e) \ne f(e') \Rightarrow \operatorname{key}_h(D_k, e) = \operatorname{key}_h(D_k, e') \wedge f(e) \ne f(e')$$
-/
theorem partial_key_unsound {K R : Type} (h : List (String × String) → K) (dkey : List String)
    (run : Env → R) (e e' : Env) (hagree : ∀ n ∈ dkey, e n = e' n) (hne : run e ≠ run e') :
    key h dkey e = key h dkey e' ∧ run e ≠ run e' :=
  ⟨key_congr h dkey e e' hagree, hne⟩

/-! ## Lake's artifact cache: one writer, narrow readers (task `site-build-cache`)

The cache above stores one result per key. Lake's artifact cache (`.lake-cache`, `actions/cache` in
`.github/actions/setup-lean`) is different: an entry is a *set* of module artifacts, each named by the
module's input hash, and a job that restores it rebuilds exactly the modules of its own import cone whose
artifact is missing. Premise (Lake's behaviour, not proved here): Lake re-checks every trace, so a stale or
partial entry is never unsound, only slow;
the question here is which modules a job rebuilds.

Before this task every job that ran `setup-lean` could save the shared key, and GitHub keeps the first save.
A site job whose cone was two modules could win and store an entry without the gate modules; later jobs
that needed those modules restored it and rebuilt 38 of them (2 s -> 50 s,
research/notes/2026/10-18-slow-site-build.md). The fix: only one job (the `lean` job of `lean.yml`, which builds
every target) saves; every other job only restores (`Fw.Ops.LakeCache.jobs`). `cache_complete` says that the
writer's entry holds every module any reader needs when every reader's targets are in the writer's cone;
`rebuild_mono` and `rebuild_in_cone` say a job never rebuilds more than its own cone.

The model: `deps m` lists the modules (or Lake targets) `m` imports; `hash m` names `m`'s artifact for one
source tree (one exact cache key; a fallback entry from another tree has other hashes, and the rebuild bounds
still hold).
-/

/-- Module `m` is in the import cone of the roots `ts`: a root, or imported by a module of the cone.

$$\forall \mathit{deps}, T:\ \operatorname{cl}_{\mathit{deps}}(T) = \text{the least } X \text{ with } T \subseteq X \text{ and } \forall m \in X,\ \forall d \in \mathit{deps}(m):\ d \in X$$ -/
inductive InCone (deps : String → List String) (ts : List String) : String → Prop
  | root {m : String} : m ∈ ts → InCone deps ts m
  | dep {m d : String} : InCone deps ts m → d ∈ deps m → InCone deps ts d

/-- **The cone is transitive.** If every root of `ts'` is in the cone of `ts`, the whole cone of `ts'` is.

$$\forall \mathit{deps}, T, T':\ (\forall t \in T':\ t \in \operatorname{cl}(T)) \Rightarrow \forall m:\ (m \in \operatorname{cl}(T') \Rightarrow m \in \operatorname{cl}(T))$$ -/
theorem inCone_trans (deps : String → List String) (ts ts' : List String)
    (hroots : ∀ t ∈ ts', InCone deps ts t) {m : String} (h : InCone deps ts' m) : InCone deps ts m := by
  induction h with
  | root hm => exact hroots _ hm
  | dep _ hd ih => exact InCone.dep ih hd

/-- **More roots, larger cone.**

$$\forall \mathit{deps}, T, T':\ T' \subseteq T \Rightarrow \forall m:\ (m \in \operatorname{cl}(T') \Rightarrow m \in \operatorname{cl}(T))$$ -/
theorem inCone_mono (deps : String → List String) (ts ts' : List String) (hsub : ∀ t ∈ ts', t ∈ ts)
    {m : String} (h : InCone deps ts' m) : InCone deps ts m :=
  inCone_trans deps ts ts' (fun t ht => InCone.root (hsub t ht)) h

/-- A restored Lake entry: the set of artifact hashes it holds.

$$\mathrm{Entry}(H) = H \to \mathrm{Prop}$$ -/
abbrev Entry (H : Type) := H → Prop

/-- Module `m` is rebuilt by a job with targets `ts` that restored the entry `C`: it is in the job's cone and its
artifact is not in `C`.

$$\forall \mathit{deps}, h, C, T, m:\ m \in \operatorname{rb}(T, C) \iff m \in \operatorname{cl}(T) \land h(m) \notin C$$ -/
def Rebuilds {H : Type} (deps : String → List String) (hash : String → H) (C : Entry H) (ts : List String)
    (m : String) : Prop :=
  InCone deps ts m ∧ ¬ C (hash m)

/-- The entry after a job builds its targets on top of the restored entry `C`: `C` plus the artifact of every
module of its cone (what the job saves, if it saves).

$$\forall \mathit{deps}, h, C, T:\ \operatorname{after}(T, C) = C \cup \{\, h(m) \mid m \in \operatorname{cl}(T) \,\}$$ -/
def afterBuild {H : Type} (deps : String → List String) (hash : String → H) (C : Entry H) (ts : List String) :
    Entry H :=
  fun x => C x ∨ ∃ m, InCone deps ts m ∧ hash m = x

/-- **A job never rebuilds outside its own cone.**

$$\forall \mathit{deps}, h, C, T, m:\ m \in \operatorname{rb}(T, C) \Rightarrow m \in \operatorname{cl}(T)$$ -/
theorem rebuild_in_cone {H : Type} (deps : String → List String) (hash : String → H) (C : Entry H)
    (ts : List String) (m : String) (h : Rebuilds deps hash C ts m) : InCone deps ts m := h.1

/-- **Rebuilds are monotone in the cone.** A job whose cone lies inside another job's cone rebuilds no module the
other would not rebuild from the same entry.

$$\forall \mathit{deps}, h, C, T, T':\ \operatorname{cl}(T') \subseteq \operatorname{cl}(T) \Rightarrow \forall m:\ (m \in \operatorname{rb}(T', C) \Rightarrow m \in \operatorname{rb}(T, C))$$ -/
theorem rebuild_mono {H : Type} (deps : String → List String) (hash : String → H) (C : Entry H)
    (ts ts' : List String) (hcl : ∀ m, InCone deps ts' m → InCone deps ts m) (m : String)
    (h : Rebuilds deps hash C ts' m) : Rebuilds deps hash C ts m :=
  ⟨hcl m h.1, h.2⟩

/-- **A larger entry never rebuilds more.**

$$\forall \mathit{deps}, h, C, C', T:\ C \subseteq C' \Rightarrow \forall m:\ (m \in \operatorname{rb}(T, C') \Rightarrow m \in \operatorname{rb}(T, C))$$ -/
theorem rebuild_antitone {H : Type} (deps : String → List String) (hash : String → H) (C C' : Entry H)
    (ts : List String) (hsub : ∀ x, C x → C' x) (m : String) (h : Rebuilds deps hash C' ts m) :
    Rebuilds deps hash C ts m :=
  ⟨h.1, fun hc => h.2 (hsub _ hc)⟩

/-- **Cache completeness.** If every target of a restoring job is in the writer's cone, the entry the writer saves
(whatever entry it restored) holds every module the restoring job needs on the same source tree: the job
rebuilds nothing.

$$\forall \mathit{deps}, h, C, T_w, T_j:\ (\forall t \in T_j:\ t \in \operatorname{cl}(T_w)) \Rightarrow \forall m:\ m \notin \operatorname{rb}(T_j, \operatorname{after}(T_w, C))$$ -/
theorem cache_complete {H : Type} (deps : String → List String) (hash : String → H) (C : Entry H)
    (tw tj : List String) (hcov : ∀ t ∈ tj, InCone deps tw t) (m : String) :
    ¬ Rebuilds deps hash (afterBuild deps hash C tw) tj m :=
  fun h => h.2 (Or.inr ⟨m, inCone_trans deps tw tj hcov h.1, rfl⟩)

/-- **Why the first-save race was slow.** If a narrow job saves the entry, a job whose cone holds a module that was
not in the restored entry and whose artifact the saver did not build rebuilds it.

$$\forall \mathit{deps}, h, C, T_s, T_j, m:\ m \in \operatorname{cl}(T_j) \land h(m) \notin C \land (\forall m' \in \operatorname{cl}(T_s):\ h(m') \ne h(m)) \Rightarrow m \in \operatorname{rb}(T_j, \operatorname{after}(T_s, C))$$ -/
theorem narrow_saver_rebuilds {H : Type} (deps : String → List String) (hash : String → H) (C : Entry H)
    (ts tj : List String) (m : String) (hj : InCone deps tj m) (hc : ¬ C (hash m))
    (hout : ∀ m', InCone deps ts m' → hash m' ≠ hash m) :
    Rebuilds deps hash (afterBuild deps hash C ts) tj m := by
  refine ⟨hj, ?_⟩
  rintro (h | ⟨m', hm', he⟩)
  · exact hc h
  · exact hout m' hm' he

end Fw.Ops.Cache
