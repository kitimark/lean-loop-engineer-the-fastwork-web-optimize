import Fw.Port.Sections

/-! Check 1 of the port completeness gate: the text of a section. The leaves are the section's text nodes in document
order; each is normalised (ASCII whitespace runs collapsed to one space, then trimmed) and empty leaves are dropped. The
digest is an injective encoding of the leaf list, so two sections have equal digests exactly when their normalised
leaves are equal (`digest_eq_iff`). The site side hashes this encoding with SHA-256 and stores only the hash. -/

namespace Fw.Port.Text

open Fw.Port.Sections

/-- HTML's ASCII whitespace: space, tab, line feed, form feed, carriage return. -/
def isWs (c : Char) : Bool := c == ' ' || c == '\t' || c == '\n' || c == '\x0c' || c == '\r'

/-- One leaf normalised: every whitespace character becomes a space, the text is split at spaces, empty pieces are
dropped and the rest joined with one space. Other characters (U+00A0 included) are kept. -/
def norm (s : String) : String :=
  " ".intercalate (((String.ofList (s.toList.map fun c => if isWs c then ' ' else c)).splitOn " ").filter (· != ""))

#guard norm "  a \n\t b  " == "a b"
#guard norm "   " == ""
#guard norm "" == ""
#guard norm "a\u00A0b" == "a\u00A0b"

/-- The leaves of a section: each text node normalised, the empty ones dropped, order kept. -/
def leaves (ts : List String) : List String := (ts.map norm).filter (· != "")

#guard leaves [" a ", "\n", "b  c"] == ["a", "b c"]
#guard leaves [] == []

/-- The encoding of a leaf list: each leaf as its length followed by its character codes. -/
def enc : List String → List Nat
  | [] => []
  | s :: ss => s.length :: (s.toList.map Char.toNat ++ enc ss)

#guard enc ["ab", ""] == [2, 97, 98, 0]

/-- Character codes determine the characters. -/
theorem codes_inj : ∀ x y : List Char, x.map Char.toNat = y.map Char.toNat → x = y
  | [], [], _ => rfl
  | [], _ :: _, h => by simp at h
  | _ :: _, [], h => by simp at h
  | a :: x, b :: y, h => by
    simp only [List.map_cons, List.cons.injEq] at h
    rw [Char.toNat_inj.mp h.1, codes_inj x y h.2]

/-- The encoding is injective. -/
theorem enc_inj : ∀ a b : List String, enc a = enc b → a = b
  | [], [], _ => rfl
  | [], _ :: _, h => by simp [enc] at h
  | _ :: _, [], h => by simp [enc] at h
  | s :: ss, t :: ts, h => by
    simp only [enc, List.cons.injEq] at h
    obtain ⟨hl, h2⟩ := h
    have hlen : (s.toList.map Char.toNat).length = (t.toList.map Char.toNat).length := by
      simp [String.length_toList, hl]
    obtain ⟨hst, hrest⟩ := List.append_inj h2 hlen
    have hs : s = t := by
      apply String.ext
      exact codes_inj _ _ hst
    rw [hs, enc_inj ss ts hrest]

/-- The digest of a section's text nodes: the encoding of its leaves. -/
def digest (ts : List String) : List Nat := enc (leaves ts)

/-- Equal digests mean equal normalised leaves, and conversely. -/
theorem digest_eq_iff (a b : List String) : digest a = digest b ↔ leaves a = leaves b :=
  ⟨enc_inj _ _, fun h => by simp [digest, h]⟩

/-- Text exclusions of one section on both arms: `key = "*"` drops the whole section's text, any other key drops the
leaves equal to it. -/
def drop (E : List Excl) (s : String) (L : List String) : List String :=
  if exclIn E .text s "*" then [] else L.filter fun l => !exclIn E .text s l

/-- The text verdict of one section: equal digests after the section's exclusions. -/
def pass (E : List Excl) (s : String) (a b : List String) : Bool :=
  enc (drop E s (leaves a)) == enc (drop E s (leaves b))

/-- A section passes exactly when its leaves, after its exclusions, are equal. -/
theorem pass_iff (E : List Excl) (s : String) (a b : List String) :
    pass E s a b = true ↔ drop E s (leaves a) = drop E s (leaves b) := by
  simp only [pass, beq_iff_eq]
  exact ⟨enc_inj _ _, fun h => by rw [h]⟩

/-- A section whose whole text is excluded passes. -/
theorem pass_of_all (E : List Excl) (s : String) (a b : List String) (h : exclIn E .text s "*" = true) :
    pass E s a b = true := by
  simp [pass, drop, h]

/-- Text exclusions, one entry per section and leaf, each with its reason. -/
def exclusions : List Excl := [
  ⟨.text, "hero.countdown", "*", "countdown digits are the time left until launch, read from the clock at render time"⟩,
  ⟨.text, "morph.countdown", "*", "countdown digits are the time left until launch, read from the clock at render time"⟩]

/-- The text exclusions are well formed and all belong to the text check. -/
theorem exclusions_wf : wf exclusions = true ∧ ∀ e ∈ exclusions, e.check = .text := by decide

#guard pass exclusions "hero" ["Hello  world"] ["Hello", "world"] == false
#guard pass exclusions "hero" [" Hello world "] ["Hello world"]
#guard pass exclusions "hero.countdown" ["01"] ["02"]

end Fw.Port.Text
