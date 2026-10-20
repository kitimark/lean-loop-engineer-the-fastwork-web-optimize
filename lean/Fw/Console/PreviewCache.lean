/-!
# Cache policy of the task previews (preview-speed)

Which `Cache-Control` a preview file gets, and why a rebuilt file is never served stale.
-/

namespace Fw.Console.PreviewCache

/-- The three kinds of preview file. -/
inductive Kind | hashed | html | other
  deriving DecidableEq, Repr

/-- Lower-cased extension of a path's last segment, with the dot ("" when none). -/
def ext (path : String) : String :=
  let name := (path.splitOn "/").getLast?.getD ""
  match name.splitOn "." with
  | [] | [_] => ""
  | parts => "." ++ (parts.getLast?.getD "").toLower

/-- A lower-case hex digit (the alphabet of `sha256` hex). -/
def isHex (c : Char) : Bool := c.isDigit || ('a' ≤ c && c ≤ 'f')

/-- The root-level stylesheet `mui.<sha8>.css` that `apps/site/scripts/build.mjs` names after its own bytes. -/
def isMuiName (path : String) : Bool :=
  let cs := path.toList
  cs.length == 17 && cs.take 5 == "/mui.".toList && ((cs.drop 5).take 8).all isHex && cs.drop 13 == ".css".toList

/-- Path prefix of SvelteKit's content-addressed output. -/
def immutableDir : String := "/_app/immutable/"

/-- File kind, decided by identity: `.html` is `html`; else `hashed` iff under `_app/immutable/`, or listed in the
rewrite build's `.vite/manifest.json` (`names`), or a `mui.<sha8>.css`; else `other`. -/
def kind (names : List String) (path : String) : Kind :=
  if ext path == ".html" then .html
  else if path.startsWith immutableDir || names.contains path || isMuiName path then .hashed
  else .other

/-- The `Cache-Control` of a kind. -/
def cacheControl : Kind → String
  | .hashed => "public, max-age=31536000, immutable"
  | .html | .other => "no-cache"

/-- Text types the servers compress. -/
def compressible (path : String) : Bool :=
  [".html", ".css", ".js", ".mjs", ".json", ".svg", ".txt"].contains (ext path)

/-- A client may reuse a stored copy without asking: only an immutable one. -/
def reusesWithoutAsking (k : Kind) : Bool := k == .hashed

/-- **Only hashed files are reused without asking.** -/
theorem reuse_only_hashed (N : List String) (p : String) (h : reusesWithoutAsking (kind N p) = true) : kind N p = .hashed := by
  revert h; unfold reusesWithoutAsking; cases kind N p <;> simp

/-- **Html is never immutable.** -/
theorem html_no_cache (N : List String) (p : String) (h : ext p = ".html") : cacheControl (kind N p) = "no-cache" := by
  simp [kind, h, cacheControl]

/-- **Every file that is not hashed revalidates.** -/
theorem unhashed_revalidates (N : List String) (p : String) (h : kind N p ≠ .hashed) :
    cacheControl (kind N p) = "no-cache" := by
  revert h; cases kind N p <;> simp [cacheControl]

/-- **Identity, forward: the `_app/immutable/` arm.** -/
theorem immutable_dir_hashed (N : List String) (p : String) (h : p.startsWith immutableDir = true) (hx : (ext p == ".html") = false) :
    kind N p = .hashed := by
  simp [kind, hx, h]

/-- **Identity, forward: the manifest arm.** -/
theorem manifest_name_hashed (N : List String) (p : String) (h : N.contains p = true) (hx : (ext p == ".html") = false) :
    kind N p = .hashed := by
  simp only [kind, hx, h, Bool.or_true, Bool.true_or, Bool.false_eq_true, ite_false, ite_true]

/-- **Identity, forward: the `mui.<sha8>.css` arm.** -/
theorem mui_name_hashed (N : List String) (p : String) (h : isMuiName p = true) (hx : (ext p == ".html") = false) :
    kind N p = .hashed := by
  simp [kind, hx, h]

/-- **Identity, backward: nothing else is hashed.** A hashed file is under `_app/immutable/`, listed in the manifest, or a
`mui.<sha8>.css`; no name shape alone ever makes a file immutable. -/
theorem hashed_is_identified (N : List String) (p : String) (h : kind N p = .hashed) :
    p.startsWith immutableDir = true ∨ N.contains p = true ∨ isMuiName p = true := by
  unfold kind at h
  split at h
  · cases h
  · split at h
    · rename_i hc; simpa [Bool.or_eq_true, or_assoc] using hc
    · cases h

/-- **No stale content, revalidating files.** The ETag is a collision-free hash of the bytes (INFERRED modelling assumption:
sha256 collisions are ignored), so other bytes never match a stored ETag and the client refetches. -/
theorem changed_bytes_new_etag {B : Type} (e : B → String) (inj : ∀ a b, e a = e b → a = b)
    (b₁ b₂ : B) (h : b₁ ≠ b₂) : e b₁ ≠ e b₂ := fun he => h (inj _ _ he)

/-- The manifest property of a build: every name the manifest lists carries bytes whose hash is the listed content hash.
`M` maps a name to its content hash; the build maps a path to bytes. -/
def ManifestFaithful {B H : Type} (hash : B → H) (M : List (String × H)) (build : String → Option B) : Prop :=
  ∀ p x h, M.lookup p = some h → build p = some x → hash x = h

/-- The naming property of the other two arms: a build serves a path under `_app/immutable/` or a `mui.<sha8>.css` only with
bytes whose name function gives that very path (the path embeds the bytes' hash). -/
def NameAddressed {B : Type} (nm : B → String) (build : String → Option B) : Prop :=
  ∀ p x, (p.startsWith immutableDir = true ∨ isMuiName p = true) → build p = some x → nm x = p

/-- A name listed in `names` of a manifest list is a key of it. -/
theorem contains_names {H : Type} (M : List (String × H)) (p : String) (h : (M.map Prod.fst).contains p = true) :
    ∃ c, M.lookup p = some c := by
  induction M with
  | nil => simp at h
  | cons e rest ih =>
    obtain ⟨k, v⟩ := e
    by_cases hk : p = k
    · subst hk; exact ⟨v, by simp [List.lookup]⟩
    · have hne : (p == k) = false := beq_false_of_ne hk
      have h' : (rest.map Prod.fst).contains p = true := by
        simp only [List.map_cons, List.contains_cons, Bool.or_eq_true] at h
        rcases h with h | h
        · exact absurd (beq_iff_eq.mp h) hk
        · exact h
      obtain ⟨c, hc⟩ := ih h'
      exact ⟨c, by simp [List.lookup, hne, hc]⟩

/-- **No stale content, hashed files (over the classifier).** For a manifest `M` (name `→` content hash), two builds that
both satisfy the manifest property and the naming property, a collision-free content hash and name function (INFERRED
modelling assumption), a path classified hashed by `kind_(names(M))` carries the same bytes
in both builds, so reuse without asking can never show old bytes after a rebuild. -/
theorem hashed_serves_same_bytes {B H : Type} (hash : B → H) (nm : B → String)
    (hinj : ∀ a b, hash a = hash b → a = b) (ninj : ∀ a b, nm a = nm b → a = b)
    (M : List (String × H)) (b₁ b₂ : String → Option B)
    (f₁ : ManifestFaithful hash M b₁) (f₂ : ManifestFaithful hash M b₂)
    (n₁ : NameAddressed nm b₁) (n₂ : NameAddressed nm b₂)
    (p : String) (x y : B) (hk : kind (M.map Prod.fst) p = .hashed) (h₁ : b₁ p = some x) (h₂ : b₂ p = some y) : x = y := by
  rcases hashed_is_identified _ p hk with hd | hm | hu
  · exact ninj _ _ ((n₁ p x (.inl hd) h₁).trans (n₂ p y (.inl hd) h₂).symm)
  · obtain ⟨c, hc⟩ := contains_names M p hm
    exact hinj _ _ ((f₁ p x c hc h₁).trans (f₂ p y c hc h₂).symm)
  · exact ninj _ _ ((n₁ p x (.inr hu) h₁).trans (n₂ p y (.inr hu) h₂).symm)

/-- **No stale content, the rest (over the classifier).** Every path not classified hashed gets `no-cache`, so a client
revalidates it by ETag. -/
theorem unclassified_no_cache (N : List String) (p : String) (h : kind N p ≠ .hashed) :
    cacheControl (kind N p) = "no-cache" := unhashed_revalidates N p h

#guard kind [] "/index.html" == .html
#guard kind [] "/_app/immutable/chunks/x.js" == .hashed
#guard kind [] "/_app/immutable/assets/google-sans-latin-normal.BbZhqv4U.woff2" == .hashed
#guard kind ["/assets/index-BxK3a9Qz.js"] "/assets/index-BxK3a9Qz.js" == .hashed
#guard kind [] "/assets/index-BxK3a9Qz.js" == .other
#guard kind [] "/mui.b3bea9d9.css" == .hashed
#guard kind [] "/mui.B3bea9d9.css" == .other
#guard kind [] "/x/mui.b3bea9d9.css" == .other
#guard kind ["/assets/index-BxK3a9Qz.html"] "/assets/index-BxK3a9Qz.html" == .html
#guard kind [] "/fonts/Roboto-SemiBold.woff2" == .other
#guard kind [] "/img/og-1200x630.png" == .other
#guard kind [] "/icons/icon-darkMode.svg" == .other
#guard kind [] "/selling/fonts/playpen-sans-latin.woff2" == .other
#guard kind [] "/" == .other
#guard compressible "/a/B.JS" && !compressible "/a.png"

end Fw.Console.PreviewCache
