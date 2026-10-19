import Fw.Site.Assets
import Fw.Port.Text

/-! Check 2 of the port completeness gate: the attribute multiset of a section. Only the attributes of `names` count
(links, sources, alternative text, language, head meta). URL-valued attributes of the original are first renamed to the
rewrite's URLs with the asset manifest's map (`Fw.Site.Assets.rename`; in a `srcset`, each candidate's URL). Each
(name, value) pair is a unit decided on its own by the multiset difference `Fw.Port.Sections.unmatched`. Specified
here; the site side follows in the next round. -/

namespace Fw.Port.Attrs

open Fw.Port.Sections Fw.Site.Assets

/-- The attributes the check compares. -/
def names : List String := ["href", "src", "srcset", "alt", "lang", "hreflang", "rel", "property", "name", "content"]

/-- A `srcset` with each candidate's URL renamed: the value split at commas, each piece normalised (`Fw.Port.Text.norm`),
empty pieces dropped, the first word of each piece renamed and the other words kept, the pieces joined with `", "`
(an empty value gives the empty string). -/
def renameSrcset (F : List File) (v : String) : String :=
  ", ".intercalate <| ((v.splitOn ",").map Fw.Port.Text.norm |>.filter (· != "")).map fun c =>
    match c.splitOn " " with
    | [] => c
    | u :: rest => " ".intercalate (rename F u :: rest)

#guard renameSrcset [⟨"/x/a.avif", "snapshot/site/s/a.avif"⟩] "/s/a.avif 240w,  /s/b.avif 480w" == "/x/a.avif 240w, /s/b.avif 480w"

/-- An original attribute value in rewrite terms: `href` and `src` renamed, `srcset` renamed per candidate, any other
value kept. -/
def renameVal (F : List File) (n v : String) : String :=
  if n == "href" || n == "src" then rename F v else if n == "srcset" then renameSrcset F v else v

/-- The compared pairs of one arm in section `s`: attributes named in `N` and not excluded for `s`. -/
def pick (E : List Excl) (s : String) (A : List (String × String)) : List (String × String) :=
  A.filter fun (n, _) => names.contains n && !exclIn E .attrs s n

/-- The verdict of one section: the original's pairs (renamed) the rewrite lacks, and the rewrite's pairs the
original lacks. -/
structure Verdict where
  missing : List (String × String)
  extra : List (String × String)
deriving Repr, DecidableEq

/-- The original's compared pairs in rewrite terms. -/
def origPairs (F : List File) (E : List Excl) (s : String) (O : List (String × String)) : List (String × String) :=
  (pick E s O).map fun (n, v) => (n, renameVal F n v)

/-- The check of one section (see `Verdict`). -/
def check (F : List File) (E : List Excl) (s : String) (O R : List (String × String)) : Verdict :=
  ⟨unmatched (origPairs F E s O) (pick E s R), unmatched (pick E s R) (origPairs F E s O)⟩

/-- A section passes when nothing is missing or extra. -/
def pass (F : List File) (E : List Excl) (s : String) (O R : List (String × String)) : Bool :=
  (check F E s O R).missing.isEmpty && (check F E s O R).extra.isEmpty

/-- A section passes exactly when both arms hold every compared pair equally often. -/
theorem pass_iff (F : List File) (E : List Excl) (s : String) (O R : List (String × String)) :
    pass F E s O R = true ↔ ∀ p, (origPairs F E s O).count p = (pick E s R).count p := by
  have h1 := unmatched_nil_iff (origPairs F E s O) (pick E s R)
  have h2 := unmatched_nil_iff (pick E s R) (origPairs F E s O)
  simp only [pass, check, List.isEmpty_iff, Bool.and_eq_true]
  rw [h1, h2]
  constructor
  · rintro ⟨a, b⟩ p; exact Nat.le_antisymm (a p) (b p)
  · intro h; exact ⟨fun p => Nat.le_of_eq (h p), fun p => Nat.le_of_eq (h p).symm⟩

/-- A missing pair is a surplus of the original, an extra pair a surplus of the rewrite. -/
theorem mem_iff (F : List File) (E : List Excl) (s : String) (O R : List (String × String)) (p : String × String) :
    (p ∈ (check F E s O R).missing ↔ (pick E s R).count p < (origPairs F E s O).count p) ∧
      (p ∈ (check F E s O R).extra ↔ (origPairs F E s O).count p < (pick E s R).count p) := by
  simp only [check]
  constructor
  · rw [← List.count_pos_iff, count_unmatched]; omega
  · rw [← List.count_pos_iff, count_unmatched]; omega

/-- Attribute exclusions (none yet): each entry names a section and an attribute name, with its reason. -/
def exclusions : List Excl := []

/-- The attribute exclusions are well formed and all belong to the attribute check. -/
theorem exclusions_wf : wf exclusions = true ∧ ∀ e ∈ exclusions, e.check = .attrs := by decide

#guard pass [⟨"/fonts/a.woff2", "snapshot/site/f/a.woff2"⟩] [] "nav" [("href", "/f/a.woff2"), ("class", "x")]
  [("href", "/fonts/a.woff2")]
#guard (check [] [] "nav" [("alt", "Fastwork")] [("alt", "")]) == ⟨[("alt", "Fastwork")], [("alt", "")]⟩
#guard pass [] [⟨.attrs, "nav", "alt", "r"⟩] "nav" [("alt", "Fastwork")] []

end Fw.Port.Attrs
