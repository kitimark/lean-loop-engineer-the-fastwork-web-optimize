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

/-- Last segment of a path without its extension. -/
def stem (path : String) : String :=
  let name := (path.splitOn "/").getLast?.getD ""
  let e := ext path
  if e.isEmpty then name else String.ofList (name.toList.take (name.length - e.length))

/-- A character a build hash may hold (no `-`: a hash holding one is simply not recognised). -/
def hashChar (c : Char) : Bool := c.isAlphanum || c == '_'

/-- An 8-character token that looks random: digit and letter, or an inner capital with a lower case letter. -/
def randomLooking (t : List Char) : Bool :=
  (t.any Char.isDigit && t.any Char.isAlpha) ||
  (t.tail.any Char.isUpper && t.any Char.isLower)

/-- The stem ends in a separator (`-` or `.`) and 8 hash characters that look random. -/
def hashedStem (s : String) : Bool :=
  let cs := s.toList
  let n := cs.length
  8 < n &&
  ((cs.drop (n - 9)).head? == some '-' || (cs.drop (n - 9)).head? == some '.') &&
  (cs.drop (n - 8)).all hashChar &&
  randomLooking (cs.drop (n - 8))

/-- Path prefix of SvelteKit's content-addressed output. -/
def immutableDir : String := "/_app/immutable/"

/-- File kind: `.html` is always `html`; else `_app/immutable/**` or a hashed file name is `hashed`.

$$\operatorname{kind}(p) = \begin{cases}\mathrm{html} & \operatorname{ext}(p)=\texttt{.html}\\ \mathrm{hashed} & p \in \texttt{/\_app/immutable/**} \vee \operatorname{hashedStem}(\operatorname{stem}(p))\\ \mathrm{other} & \text{else}\end{cases}$$ -/
def kind (path : String) : Kind :=
  if ext path == ".html" then .html
  else if path.startsWith immutableDir || hashedStem (stem path) then .hashed
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

/-- **Only hashed files are reused without asking.**

$$\mathrm{reuse}(\operatorname{kind}(p)) \Rightarrow \operatorname{kind}(p) = \mathrm{hashed}$$ -/
theorem reuse_only_hashed (p : String) (h : reusesWithoutAsking (kind p) = true) : kind p = .hashed := by
  revert h; unfold reusesWithoutAsking; cases kind p <;> simp

/-- **Html is never immutable.**

$$\operatorname{ext}(p)=\texttt{.html} \Rightarrow \operatorname{cacheControl}(\operatorname{kind}(p)) = \texttt{no-cache}$$ -/
theorem html_no_cache (p : String) (h : ext p = ".html") : cacheControl (kind p) = "no-cache" := by
  simp [kind, h, cacheControl]

/-- **Every file that is not hashed revalidates.**

$$\operatorname{kind}(p) \ne \mathrm{hashed} \Rightarrow \operatorname{cacheControl}(\operatorname{kind}(p)) = \texttt{no-cache}$$ -/
theorem unhashed_revalidates (p : String) (h : kind p ≠ .hashed) : cacheControl (kind p) = "no-cache" := by
  revert h; cases kind p <;> simp [cacheControl]

/-- **No stale content, revalidating files.** If the ETag is injective on bytes, other bytes never match a stored ETag, so
the client refetches.

$$(\forall a, b.\ e(a)=e(b) \Rightarrow a=b) \wedge b_1 \ne b_2 \Rightarrow e(b_1) \ne e(b_2)$$ -/
theorem changed_bytes_new_etag {B : Type} (e : B → String) (inj : ∀ a b, e a = e b → a = b)
    (b₁ b₂ : B) (h : b₁ ≠ b₂) : e b₁ ≠ e b₂ := fun he => h (inj _ _ he)

/-- **No stale content, hashed files.** If a build gives one hashed URL only one byte string, two builds never serve
different bytes at that URL, so reuse without asking is safe.

$$\operatorname{kind}(u)=\mathrm{hashed} \wedge \mathrm{build}_1(u)=b_1 \wedge \mathrm{build}_2(u)=b_2 \Rightarrow b_1=b_2$$ -/
theorem hashed_url_pins_bytes {B : Type} (build₁ build₂ : String → Option B)
    (addr : ∀ u b₁ b₂, build₁ u = some b₁ → build₂ u = some b₂ → kind u = .hashed → b₁ = b₂)
    (u : String) (b₁ b₂ : B) (h₁ : build₁ u = some b₁) (h₂ : build₂ u = some b₂) (hk : kind u = .hashed) : b₁ = b₂ :=
  addr u b₁ b₂ h₁ h₂ hk

#guard kind "/index.html" == .html
#guard kind "/_app/immutable/chunks/x.js" == .hashed
#guard kind "/_app/immutable/assets/google-sans-latin-normal.BbZhqv4U.woff2" == .hashed
#guard kind "/assets/index-BxK3a9Qz.js" == .hashed
#guard kind "/assets/app.4f3a9c1d.css" == .hashed
#guard kind "/assets/index-Ab-3x_9Z.js" == .other
#guard kind "/assets/foo-homepage.js" == .other
#guard kind "/assets/foo-Homepage.js" == .other
#guard kind "/selling/fonts/playpen-sans-latin.woff2" == .other
#guard kind "/assets/index-BxK3a9Qz.html" == .html
#guard kind "/" == .other
#guard compressible "/a/B.JS" && !compressible "/a.png"

end Fw.Console.PreviewCache
