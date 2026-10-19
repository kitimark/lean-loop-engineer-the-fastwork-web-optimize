import Fw.Port.Sections

/-! Check 3 of the port completeness gate: every asset the original page references is served by the rewrite, under
the URL `apps/site/assets.manifest.json` gives it, or is excluded with a reason. An asset is a URL with an extension of
`exts` (images, fonts, media, the web manifest; code is not an asset) that names a file of its arm. The reference sets
are read at run time by `scripts/port/digest.mjs` (the snapshot page and its scripts and styles; the prerendered
`dist/aot` page and its bundles); this module decides each URL on its own (`verdict`) and is checked against
`packages/contracts/golden/port/assets.jsonl`. -/

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

/-- Asset exclusions: original URLs the rewrite does not serve by decision, each with its owning section and reason.
$$E_{\mathrm{assets}} = [\,]$$ -/
def exclusions : List Excl := []

/-- The asset exclusions are well formed and all belong to the asset check.
$$\operatorname{wf}(E_{\mathrm{assets}}) \land \forall e \in E_{\mathrm{assets}},\ e.c = \mathrm{assets}$$ -/
theorem exclusions_wf : wf exclusions = true ∧ ∀ e ∈ exclusions, e.check = .assets := by decide

#guard missing [⟨"/fonts/a.woff2", "snapshot/site/_app/immutable/assets/a.woff2"⟩] ["/fonts/a.woff2"] []
  ["/_app/immutable/assets/a.woff2", "/selling/o.svg", "/selling/o.svg"] == ["/selling/o.svg"]
#guard verdict [] [] [⟨.assets, "people.o", "/selling/o.svg", "r"⟩] "/selling/o.svg" == .excluded

end Fw.Site.Assets
