import Fw.Port.Sections

/-! Check 3 of the port completeness gate: every asset the original page references is served by the rewrite, under
the URL `apps/site/assets.manifest.json` gives it, inlined into its code, or is excluded with a reason. An asset is a
URL with an extension of `exts` (images, fonts, media, the web manifest; code is not an asset) that names a file of its
arm. The reference sets are read at run time by `scripts/port/digest.mjs` (the snapshot page and its scripts and
styles, minus `crawlSkip`; the prerendered `dist/aot` page and its bundles). The rewrite's served names are its asset
URLs plus one name `inline:` ++ i per `data:` URI found in its HTML, scripts and styles, where i is the URI's identity:
`bytes:` and the SHA-256 of the decoded bytes for a base64 payload, `svgtext:` and the SHA-256 of the percent-decoded
text for an `image/svg+xml,` payload. Vite 8.3.4 inlines every imported asset under 4096 bytes this way
(`DEFAULT_ASSETS_INLINE_LIMIT`, `shouldInline`, `svgToDataURL` in
`node_modules/.pnpm/vite@8.3.4*/node_modules/vite/dist/node/chunks/node.js:803,32711-32739`). An original asset has the
identity `bytes:` and the SHA-256 of its bytes, and an svg also `svgtext:` and the SHA-256 of `inlineNorm` of its text.
This module decides each URL on its own (`verdict`) and is checked against `packages/contracts/golden/port/assets.jsonl`.
The rename map is first one row per original asset that shares an identity with a rewrite asset (`renameRows`: the
bundler's hashed copies and inlined copies), then the manifest rows. -/

namespace Fw.Site.Assets

open Fw.Port.Sections

/-- File extensions that make a URL an asset (lower case, without the dot).
$$X = \{\texttt{avif}, \texttt{gif}, \texttt{ico}, \texttt{jpeg}, \texttt{jpg}, \texttt{mp3}, \texttt{mp4}, \texttt{otf}, \texttt{png}, \texttt{svg}, \texttt{ttf}, \texttt{webm}, \texttt{webmanifest}, \texttt{webp}, \texttt{woff}, \texttt{woff2}\}$$ -/
def exts : List String :=
  ["avif", "gif", "ico", "jpeg", "jpg", "mp3", "mp4", "otf", "png", "svg", "ttf", "webm", "webmanifest", "webp", "woff",
    "woff2"]

/-- The extension of a URL path: the text after its last dot when that dot follows the last slash, in lower case;
empty otherwise.
$$\operatorname{ext}(u) = \begin{cases} \operatorname{lower}(t) & u = p \mathbin{+\!\!+} \texttt{.} \mathbin{+\!\!+} t,\ \texttt{.}, \texttt{/} \notin t \\ \texttt{""} & \text{otherwise} \end{cases}$$ -/
def ext (u : String) : String :=
  let last := (u.splitOn "/").getLast?.getD ""
  match last.splitOn "." with
  | [_] => ""
  | ps => (ps.getLast?.getD "").toLower

#guard ext "/selling/a.b/c.SVG" == "svg"
#guard ext "/selling/a.b/c" == ""
#guard ext "" == ""

/-- A URL is an asset when its extension is in $X$.
$$\operatorname{asset}(u) \iff \operatorname{ext}(u) \in X$$ -/
def isAsset (u : String) : Bool := exts.contains (ext u)

#guard isAsset "/fonts/a.woff2"
#guard !isAsset "/_app/immutable/nodes/2.DyWL8TcE.js"
#guard !isAsset "/selling/"

/-- One row of the asset manifest: the URL the rewrite serves and the snapshot file it copies.
$$f = (u_{\mathrm{rw}}, \mathit{src})$$ -/
structure File where
  url : String
  src : String
deriving Repr, DecidableEq

/-- The snapshot's own directory prefix. $$\texttt{snapshot/site/}$$ -/
def snapRoot : String := "snapshot/site/"

/-- The URL under which the original page serves a snapshot file: the path below `snapshot/site/` with a leading slash;
`none` for a file outside it.
$$\operatorname{origUrl}(\mathit{src}) = \begin{cases} \texttt{/} \mathbin{+\!\!+} p & \mathit{src} = \texttt{snapshot/site/} \mathbin{+\!\!+} p \\ \bot & \text{otherwise} \end{cases}$$ -/
def origUrl (src : String) : Option String :=
  if src.startsWith snapRoot then some ("/" ++ (src.drop snapRoot.length).toString) else none

#guard origUrl "snapshot/site/_app/immutable/assets/x.woff2" == some "/_app/immutable/assets/x.woff2"
#guard origUrl "apps/site/x.png" == none

/-- The rename map: the original URL of the first manifest row whose snapshot file has it, mapped to that row's
rewrite URL; any other URL is its own name.
$$\operatorname{rename}(F, u) = \begin{cases} f.u_{\mathrm{rw}} & f \text{ the first } f \in F \text{ with } \operatorname{origUrl}(f.\mathit{src}) = u \\ u & \text{no such } f \end{cases}$$ -/
def rename (F : List File) (u : String) : String :=
  match F.find? (fun f => origUrl f.src == some u) with
  | some f => f.url
  | none => u

#guard rename [⟨"/fonts/a.woff2", "snapshot/site/_app/immutable/assets/a.woff2"⟩] "/_app/immutable/assets/a.woff2" == "/fonts/a.woff2"
#guard rename [] "/selling/x.png" == "/selling/x.png"

/-! ## Inlined assets -/

/-- The ECMAScript white space and line terminator code points: the set `String.prototype.trim` strips and the regular
expression class `\s` matches (the `Zs` category, tab, vertical tab, form feed, U+FEFF, and the four line terminators).
$$W = \{\texttt{U+0009}, \dots, \texttt{U+000D}, \texttt{U+0020}, \texttt{U+00A0}, \texttt{U+1680}, \texttt{U+2000}, \dots, \texttt{U+200A}, \texttt{U+2028}, \texttt{U+2029}, \texttt{U+202F}, \texttt{U+205F}, \texttt{U+3000}, \texttt{U+FEFF}\}$$ -/
def jsWs : List Nat :=
  [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007,
    0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF]

/-- A character is ECMAScript white space when its code point is in $W$. $$\operatorname{ws}(c) \iff c \in W$$ -/
def isJsWs (c : Char) : Bool := jsWs.contains c.toNat

/-- Trim: the characters without their leading and trailing characters of $W$.
$$\operatorname{trim}(s) = s_{a..b} \text{ for the least } a \text{ and greatest } b \text{ with } s_a, s_{b-1} \notin W \text{ (empty when every } s_i \in W)$$ -/
def trimJs (l : List Char) : List Char := ((l.dropWhile isJsWs).reverse.dropWhile isJsWs).reverse

/-- Tag collapse: left to right and without overlap, every `>` followed by a nonempty run of $W$ and then `<` becomes
`><`. The state `some w` holds the run read since the last `>` (reversed); `none` is outside such a run.
$$\operatorname{collapse}(s) = \operatorname{collapseTags}(\bot, s) = s \text{ with each match of } \texttt{>}\,W^{+}\,\texttt{<} \text{ replaced by } \texttt{><}$$ -/
def collapseTags : Option (List Char) → List Char → List Char
  | none, [] => []
  | none, c :: r => if c == '>' then '>' :: collapseTags (some []) r else c :: collapseTags none r
  | some w, [] => w.reverse
  | some w, c :: r =>
    if isJsWs c then collapseTags (some (c :: w)) r
    else if c == '<' then '<' :: collapseTags none r
    else w.reverse ++ if c == '>' then '>' :: collapseTags (some []) r else c :: collapseTags none r

/-- Run squash: every maximal run of characters of $W$ becomes one space; `b` says the last character read was in $W$
(so `true` at the start drops a leading run).
$$\operatorname{squash}(s) = \operatorname{squash}(\mathrm{false}, s) = s \text{ with each maximal run } W^{+} \text{ replaced by } \texttt{" "}$$ -/
def squash : Bool → List Char → List Char
  | _, [] => []
  | b, c :: r => if isJsWs c then (if b then squash true r else ' ' :: squash true r) else c :: squash false r

/-- The text Vite 8.3.4 inlines for an svg under its size limit, read back from the `data:` URI (percent escapes
decoded): trim, collapse whitespace between tags, double quotes to single quotes, each whitespace run to one space
(`svgToDataURL`, `node.js:32736-32739` of the installed Vite). Svgs that hold `<text`, `<foreignObject` or nested quotes
are inlined as base64 of their bytes instead, which the `bytes:` identity covers.
$$\operatorname{inlineNorm}(s) = \operatorname{squash}(\operatorname{quote}(\operatorname{collapse}(\operatorname{trim}(s)))),\qquad \operatorname{quote}(s) = s \text{ with every } \texttt{"} \text{ replaced by } \texttt{'}$$ -/
def inlineNorm (s : String) : String :=
  String.ofList (squash false ((collapseTags none (trimJs s.toList)).map fun c => if c == '"' then '\'' else c))

#guard inlineNorm "  <svg a=\"1\">\n  <g/>\t</svg>\n" == "<svg a='1'><g/></svg>"
#guard inlineNorm "<p>a  \n b</p> > <" == "<p>a b</p> ><"
#guard inlineNorm " <svg> \n<g/>　x y</svg>﻿" == "<svg><g/> x y</svg>"
#guard inlineNorm "> >  <" == "> ><"
#guard inlineNorm "" == ""
#guard inlineNorm " \n " == ""

/-- The served name of an inlined asset of identity $i$. $$\operatorname{inl}(i) = \texttt{inline:} \mathbin{+\!\!+} i$$ -/
def inlineName (i : String) : String := "inline:" ++ i

/-- The first rewrite asset $(n, i)$ (served name, identity) of $W$ whose identity is one of `ids`.
$$\operatorname{hit}(W, I) = \text{the first } w \in W \text{ with } w.2 \in I,\ \bot \text{ if none}$$ -/
def firstHit (W : List (String × String)) (ids : List String) : Option (String × String) :=
  W.find? fun w => ids.contains w.2

/-- The rename map: for each original asset $(\mathit{src}, I)$ of $O$ (its snapshot file and its identities) whose
identities a rewrite asset shares, one row from the first such rewrite asset's served name to the file, in the order
of $O$; then the manifest rows $M$.
$$\operatorname{rows}(O, W, M) = [(\operatorname{hit}(W, I).1, \mathit{src}) \mid (\mathit{src}, I) \in O,\ \operatorname{hit}(W, I) \ne \bot] \mathbin{+\!\!+} M$$ -/
def renameRows (O : List (String × List String)) (W : List (String × String)) (M : List File) : List File :=
  O.filterMap (fun o => (firstHit W o.2).map fun w => ⟨w.1, o.1⟩) ++ M

#guard renameRows [("snapshot/site/a.svg", ["bytes:1", "svgtext:2"]), ("snapshot/site/b.png", ["bytes:3"])]
  [("/x/a.svg", "bytes:9"), ("inline:svgtext:2", "svgtext:2"), ("/x/a2.svg", "svgtext:2")] [⟨"/m.png", "snapshot/site/b.png"⟩] ==
  [⟨"inline:svgtext:2", "snapshot/site/a.svg"⟩, ⟨"/m.png", "snapshot/site/b.png"⟩]
#guard renameRows [] [] [] == []

/-- What the check says about one original asset URL.
$$v \in \{\mathrm{present}, \mathrm{excluded}, \mathrm{missing}\}$$ -/
inductive Verdict | present | excluded | missing
deriving Repr, DecidableEq

/-- Wire name of a verdict. $$\operatorname{name}(v)$$ is the constructor name. -/
def Verdict.name : Verdict → String
  | .present => "present" | .excluded => "excluded" | .missing => "missing"

/-- The verdict of one original asset URL $u$, given the manifest $F$, the rewrite's asset URLs $R$ and the exclusions
$E$: present when its renamed URL is in $R$, else excluded when an asset exclusion names $u$, else missing.
$$\operatorname{verdict}(F, R, E, u) = \begin{cases} \mathrm{present} & \operatorname{rename}(F, u) \in R \\ \mathrm{excluded} & \operatorname{rename}(F, u) \notin R \land \operatorname{exclKey}(E, \mathrm{assets}, u) \\ \mathrm{missing} & \operatorname{rename}(F, u) \notin R \land \lnot\operatorname{exclKey}(E, \mathrm{assets}, u) \end{cases}$$ -/
def verdict (F : List File) (R : List String) (E : List Excl) (u : String) : Verdict :=
  if R.contains (rename F u) then .present else if exclKey E .assets u then .excluded else .missing

/-- Present exactly when the renamed URL is served.
$$\forall F, R, E, u:\ \operatorname{verdict}(F, R, E, u) = \mathrm{present} \iff \operatorname{rename}(F, u) \in R$$ -/
theorem verdict_present (F : List File) (R : List String) (E : List Excl) (u : String) :
    verdict F R E u = .present ↔ rename F u ∈ R := by
  unfold verdict
  by_cases h : R.contains (rename F u) = true
  · simp only [h, ite_true, true_iff]; simpa using h
  · simp only [h, Bool.false_eq_true, ite_false]
    have : rename F u ∉ R := by simpa using h
    constructor
    · intro hv; split at hv <;> cases hv
    · intro hm; exact absurd hm this

/-- Under the rename rows, an original URL renames to the served name of the first rewrite asset that shares an
identity with it, when every original asset of that URL carries the same identities.
$$\forall O, W, M, \mathit{src}, I, u, w:\ (\mathit{src}, I) \in O \land \operatorname{origUrl}(\mathit{src}) = u \land (\forall p \in O,\ \operatorname{origUrl}(p.1) = u \Rightarrow p.2 = I) \land \operatorname{hit}(W, I) = w \Rightarrow \operatorname{rename}(\operatorname{rows}(O, W, M), u) = w.1$$ -/
theorem rename_renameRows (O : List (String × List String)) (W : List (String × String)) (M : List File)
    (src : String) (I : List String) (u : String) (w : String × String) (hm : (src, I) ∈ O)
    (hu : origUrl src = some u) (hI : ∀ p ∈ O, origUrl p.1 = some u → p.2 = I) (hw : firstHit W I = some w) :
    rename (renameRows O W M) u = w.1 := by
  induction O with
  | nil => simp at hm
  | cons p O ih =>
    by_cases hp : origUrl p.1 = some u
    · have h2 : p.2 = I := hI p (by simp) hp
      simp [rename, renameRows, h2, hw, hp]
    · have hm' : (src, I) ∈ O := by
        rcases List.mem_cons.mp hm with h | h
        · subst h; exact absurd hu hp
        · exact h
      have ih' := ih hm' (fun q hq => hI q (by simp [hq]))
      unfold rename renameRows at ih' ⊢
      cases hf : firstHit W p.2 with
      | none => simpa [List.filterMap_cons, hf] using ih'
      | some v => simpa [List.filterMap_cons, hf, hp] using ih'

/-- An original asset that shares an identity with a served rewrite asset is present.
$$\forall O, W, M, R, E, \mathit{src}, I, u, w:\ (\mathit{src}, I) \in O \land \operatorname{origUrl}(\mathit{src}) = u \land (\forall p \in O,\ \operatorname{origUrl}(p.1) = u \Rightarrow p.2 = I) \land \operatorname{hit}(W, I) = w \land w.1 \in R \Rightarrow \operatorname{verdict}(\operatorname{rows}(O, W, M), R, E, u) = \mathrm{present}$$ -/
theorem present_of_hit (O : List (String × List String)) (W : List (String × String)) (M : List File)
    (R : List String) (E : List Excl) (src : String) (I : List String) (u : String) (w : String × String)
    (hm : (src, I) ∈ O) (hu : origUrl src = some u) (hI : ∀ p ∈ O, origUrl p.1 = some u → p.2 = I)
    (hw : firstHit W I = some w) (hR : w.1 ∈ R) : verdict (renameRows O W M) R E u = .present := by
  rw [verdict_present, rename_renameRows O W M src I u w hm hu hI hw]
  exact hR

/-- Excluded exactly when the renamed URL is not served and an asset exclusion names the URL.
$$\forall F, R, E, u:\ \operatorname{verdict}(F, R, E, u) = \mathrm{excluded} \iff \operatorname{rename}(F, u) \notin R \land \exists e \in E:\ e.c = \mathrm{assets} \land e.k = u$$ -/
theorem verdict_excluded (F : List File) (R : List String) (E : List Excl) (u : String) :
    verdict F R E u = .excluded ↔ rename F u ∉ R ∧ ∃ e ∈ E, e.check = .assets ∧ e.key = u := by
  rw [← exclKey_iff]
  unfold verdict
  by_cases h : R.contains (rename F u) = true
  · have : rename F u ∈ R := by simpa using h
    simp [this]
  · have : rename F u ∉ R := by simpa using h
    by_cases hx : exclKey E .assets u = true
    · simp [hx, this]
    · simp [hx, this]

/-- Missing exactly when the renamed URL is not served and no asset exclusion names the URL.
$$\forall F, R, E, u:\ \operatorname{verdict}(F, R, E, u) = \mathrm{missing} \iff \operatorname{rename}(F, u) \notin R \land \lnot\exists e \in E:\ e.c = \mathrm{assets} \land e.k = u$$ -/
theorem verdict_missing (F : List File) (R : List String) (E : List Excl) (u : String) :
    verdict F R E u = .missing ↔ rename F u ∉ R ∧ ¬ ∃ e ∈ E, e.check = .assets ∧ e.key = u := by
  rw [← exclKey_iff]
  unfold verdict
  by_cases h : R.contains (rename F u) = true
  · have : rename F u ∈ R := by simpa using h
    simp [this]
  · have : rename F u ∉ R := by simpa using h
    by_cases hx : exclKey E .assets u = true
    · simp [hx, this]
    · simp [hx, this]

/-- The original URLs that are missing, each once, in first-seen order.
$$\operatorname{missing}(F, R, E, O) = [u \in \operatorname{dedup}(O) \mid \operatorname{verdict}(F, R, E, u) = \mathrm{missing}]$$ -/
def missing (F : List File) (R : List String) (E : List Excl) (O : List String) : List String :=
  O.eraseDups.filter (verdict F R E · == .missing)

/-- The check passes when no original asset is missing.
$$\operatorname{pass}(F, R, E, O) \iff \operatorname{missing}(F, R, E, O) = [\,]$$ -/
def pass (F : List File) (R : List String) (E : List Excl) (O : List String) : Bool := (missing F R E O).isEmpty

/-- The check passes exactly when every original asset URL is served under its renamed URL or excluded:
$O \subseteq R \lor \text{excluded}$, URL by URL.
$$\forall F, R, E, O:\ \operatorname{pass}(F, R, E, O) \iff \forall u \in O,\ \operatorname{rename}(F, u) \in R \lor \exists e \in E:\ e.c = \mathrm{assets} \land e.k = u$$ -/
theorem pass_iff (F : List File) (R : List String) (E : List Excl) (O : List String) :
    pass F R E O = true ↔ ∀ u ∈ O, rename F u ∈ R ∨ ∃ e ∈ E, e.check = .assets ∧ e.key = u := by
  simp only [pass, missing, List.isEmpty_iff, List.filter_eq_nil_iff, List.mem_eraseDups, beq_iff_eq]
  apply forall_congr'; intro u; apply imp_congr_right; intro _
  rw [verdict_missing]
  constructor
  · intro h
    by_cases hr : rename F u ∈ R
    · exact .inl hr
    · exact .inr (Classical.byContradiction fun hn => h ⟨hr, hn⟩)
  · rintro (hr | he) ⟨hr', hn⟩
    · exact hr' hr
    · exact hn he

/-- Asset exclusions: original URLs the rewrite does not serve by decision, each with the page as its section and a
reason. The bold Fastwork face is declared by an `@font-face` of the snapshot stylesheet, but no rule applies it: the
custom property `--font-fastwork` that names it is defined once and never read, so browsers never fetch the file.
$$E_{\mathrm{assets}} = [(\mathrm{assets}, \texttt{page}, \texttt{/fonts/fastwork-Bold.ttf}, \rho)]$$ -/
def exclusions : List Excl := [
  ⟨.assets, page, "/fonts/fastwork-Bold.ttf",
    "@font-face declared; --font-fastwork defined but never referenced; no rule applies the face"⟩]

/-- URL prefixes the crawl of the original page does not follow, each with its reason: the snapshot mirrors the
third-party scripts the live page loads, and their files are not the page's own assets.
$$K = [(\texttt{/\_\_vendor/}, \rho)]$$ -/
def crawlSkip : List (String × String) := [
  ("/__vendor/", "mirrored third-party scripts (Amplitude, Hotjar, Cloudflare Insights, Google Tag Manager), not the page's own assets")]

/-- Every crawl skip has a reason and the prefixes are distinct.
$$(\forall k \in K,\ k.2 \ne \texttt{""}) \land \operatorname{nodup}([k.1 \mid k \in K])$$ -/
theorem crawlSkip_wf : (∀ k ∈ crawlSkip, k.2 ≠ "") ∧ (crawlSkip.map (·.1)).Nodup := by decide +kernel

/-- The asset exclusions are well formed and all belong to the asset check.
$$\operatorname{wf}(E_{\mathrm{assets}}) \land \forall e \in E_{\mathrm{assets}},\ e.c = \mathrm{assets}$$ -/
theorem exclusions_wf : wf exclusions = true ∧ ∀ e ∈ exclusions, e.check = .assets := by decide

#guard missing [⟨"/fonts/a.woff2", "snapshot/site/_app/immutable/assets/a.woff2"⟩] ["/fonts/a.woff2"] []
  ["/_app/immutable/assets/a.woff2", "/selling/o.svg", "/selling/o.svg"] == ["/selling/o.svg"]
#guard verdict [] [] [⟨.assets, "people.o", "/selling/o.svg", "r"⟩] "/selling/o.svg" == .excluded

end Fw.Site.Assets
