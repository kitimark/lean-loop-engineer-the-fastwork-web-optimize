import Fw.Port.Text

/-! Check 4 of the port completeness gate: the shape of every inline `<svg>` of the prerendered page. The skeleton of
an svg is its normalised `viewBox`, the number of descendant elements per tag, and for each `<path>` in document order
the byte length of its `d` and its command letters; never the path data itself. `scripts/port/digest.mjs` computes the
skeleton (checked against `packages/contracts/golden/port/svg.jsonl`), keys it by a SHA-256 of its canonical JSON, and
matches the keys of the two arms with `Fw.Port.Sections.unmatched`: each svg is decided on its own. The key stands for
the skeleton under the premise that SHA-256 has no collision on these inputs. -/

namespace Fw.Port.Svg

open Fw.Port.Sections

/-- A descendant element of an svg: its tag (lower case) and its `d` attribute (empty when absent).
$$k = (\tau, d)$$ -/
structure Kid where
  tag : String
  d : String
deriving Repr, DecidableEq

/-- An inline svg: its `viewBox` attribute (empty when absent) and its descendant elements in document order.
$$S = (v, K)$$ -/
structure Svg where
  viewBox : String
  kids : List Kid
deriving Repr, DecidableEq

/-- The tags counted one by one; every other tag counts in one last bucket.
$$U = [\texttt{circle}, \texttt{clippath}, \texttt{defs}, \texttt{ellipse}, \texttt{g}, \texttt{line}, \texttt{lineargradient}, \texttt{mask}, \texttt{path}, \texttt{polygon}, \texttt{polyline}, \texttt{radialgradient}, \texttt{rect}, \texttt{stop}, \texttt{text}, \texttt{use}]$$ -/
def tagU : List String :=
  ["circle", "clippath", "defs", "ellipse", "g", "line", "lineargradient", "mask", "path", "polygon", "polyline",
    "radialgradient", "rect", "stop", "text", "use"]

/-- Element counts: one per tag of $U$, then the count of tags outside $U$.
$$\operatorname{counts}(K) = [\,|[k \in K \mid k.\tau = u]| \mid u \in U\,] \mathbin{+\!\!+} [\,|[k \in K \mid k.\tau \notin U]|\,]$$ -/
def counts (K : List Kid) : List Nat :=
  tagU.map (fun u => (K.filter (·.tag == u)).length) ++ [(K.filter fun k => !tagU.contains k.tag).length]

/-- The SVG path command letters.
$$C = \{\texttt{M},\texttt{m},\texttt{Z},\texttt{z},\texttt{L},\texttt{l},\texttt{H},\texttt{h},\texttt{V},\texttt{v},\texttt{C},\texttt{c},\texttt{S},\texttt{s},\texttt{Q},\texttt{q},\texttt{T},\texttt{t},\texttt{A},\texttt{a}\}$$ -/
def cmdLetters : List Char := "MmZzLlHhVvCcSsQqTtAa".toList

/-- The command letters of a path's `d`, in order (an exponent `e` is not a command letter).
$$\operatorname{letters}(d) = [c \in d \mid c \in C]$$ -/
def letters (d : String) : String := String.ofList (d.toList.filter cmdLetters.contains)

#guard letters "M0 0L1e-5 2c1 2 3 4 5 6z" == "MLcz"
#guard letters "" == ""

/-- The skeleton of an svg.
$$\operatorname{skel}(v, K) = \bigl(\operatorname{norm}(v),\ \operatorname{counts}(K),\ [(\operatorname{bytes}(k.d), \operatorname{letters}(k.d)) \mid k \in K,\ k.\tau = \texttt{path}]\bigr)$$
where $\operatorname{bytes}$ is the UTF-8 byte length. -/
structure Skel where
  viewBox : String
  counts : List Nat
  paths : List (Nat × String)
deriving Repr, DecidableEq

/-- The paths of an svg.
$$P(K) = [k \in K \mid k.\tau = \texttt{path}]$$ -/
def pathsOf (K : List Kid) : List Kid := K.filter (·.tag == "path")

/-- The skeleton of an svg (see `Skel`).
$$\operatorname{skel}(S) = \bigl(\operatorname{norm}(S.v),\ \operatorname{counts}(S.K),\ [(\operatorname{bytes}(k.d), \operatorname{letters}(k.d)) \mid k \in P(S.K)]\bigr)$$ -/
def skel (s : Svg) : Skel :=
  ⟨Fw.Port.Text.norm s.viewBox, counts s.kids, (pathsOf s.kids).map fun k => (k.d.utf8ByteSize, letters k.d)⟩

#guard (skel ⟨" 0 0  24 24", [⟨"g", ""⟩, ⟨"path", "M0 0h1"⟩, ⟨"circle", ""⟩]⟩).paths == [(6, "Mh")]
#guard (skel ⟨"0 0 24 24", [⟨"foo", ""⟩]⟩).counts.getLast? == some 1

/-- Equal skeletons give the same element counts and the same command sequence of every path, in order.
$$\forall a, b:\ \operatorname{skel}(a) = \operatorname{skel}(b) \Rightarrow \operatorname{counts}(a.K) = \operatorname{counts}(b.K) \land [\operatorname{letters}(k.d) \mid k \in P(a.K)] = [\operatorname{letters}(k.d) \mid k \in P(b.K)]$$ -/
theorem skel_eq_counts_letters (a b : Svg) (h : skel a = skel b) :
    counts a.kids = counts b.kids ∧
      (pathsOf a.kids).map (fun k => letters k.d) = (pathsOf b.kids).map (fun k => letters k.d) := by
  simp only [skel, Skel.mk.injEq] at h
  obtain ⟨_, hc, hp⟩ := h
  refine ⟨hc, ?_⟩
  have := congrArg (List.map Prod.snd) hp
  simpa [List.map_map, Function.comp_def] using this

/-- Equal skeletons give equal normalised view boxes and the same `d` byte length of every path, in order.
$$\forall a, b:\ \operatorname{skel}(a) = \operatorname{skel}(b) \Rightarrow \operatorname{norm}(a.v) = \operatorname{norm}(b.v) \land [\operatorname{bytes}(k.d) \mid k \in P(a.K)] = [\operatorname{bytes}(k.d) \mid k \in P(b.K)]$$ -/
theorem skel_eq_viewBox_bytes (a b : Svg) (h : skel a = skel b) :
    Fw.Port.Text.norm a.viewBox = Fw.Port.Text.norm b.viewBox ∧
      (pathsOf a.kids).map (fun k => k.d.utf8ByteSize) = (pathsOf b.kids).map (fun k => k.d.utf8ByteSize) := by
  simp only [skel, Skel.mk.injEq] at h
  obtain ⟨hv, _, hp⟩ := h
  refine ⟨hv, ?_⟩
  have := congrArg (List.map Prod.fst) hp
  simpa [List.map_map, Function.comp_def] using this

/-- An svg's path count is part of its counts, so equal skeletons have equally many paths.
$$\forall a, b:\ \operatorname{skel}(a) = \operatorname{skel}(b) \Rightarrow |P(a.K)| = |P(b.K)|$$ -/
theorem skel_eq_path_count (a b : Svg) (h : skel a = skel b) : (pathsOf a.kids).length = (pathsOf b.kids).length := by
  have := congrArg List.length (skel_eq_counts_letters a b h).2
  simpa using this

/-! ## The per-svg decision -/

/-- The verdict of the svg check over the skeleton keys of the two arms: the original's svgs that the rewrite does
not match and the rewrite's svgs that the original does not match, each without the excluded keys.
$$\operatorname{missing}(E, o, r) = [k \in \operatorname{unmatched}(o, r) \mid \lnot\operatorname{exclKey}(E, \mathrm{svg}, k)]$$
$$\operatorname{extra}(E, o, r) = [k \in \operatorname{unmatched}(r, o) \mid \lnot\operatorname{exclKey}(E, \mathrm{svg}, k)]$$ -/
structure Verdict where
  missing : List String
  extra : List String
deriving Repr, DecidableEq

/-- The check of one page (see `Verdict`).
$$\operatorname{check}(E, o, r) = (\operatorname{missing}(E, o, r), \operatorname{extra}(E, o, r))$$ -/
def check (E : List Excl) (o r : List String) : Verdict :=
  ⟨(unmatched o r).filter (!exclKey E .svg ·), (unmatched r o).filter (!exclKey E .svg ·)⟩

/-- The page passes when no svg is missing and none is extra.
$$\operatorname{pass}(E, o, r) \iff \operatorname{missing}(E, o, r) = [\,] \land \operatorname{extra}(E, o, r) = [\,]$$ -/
def pass (E : List Excl) (o r : List String) : Bool := (check E o r).missing.isEmpty && (check E o r).extra.isEmpty

/-- An original svg is missing exactly when it is unmatched and not excluded.
$$\forall E, o, r, k:\ k \in \operatorname{missing}(E, o, r) \iff k \in \operatorname{unmatched}(o, r) \land \lnot\operatorname{exclKey}(E, \mathrm{svg}, k)$$ -/
theorem mem_missing (E : List Excl) (o r : List String) (k : String) :
    k ∈ (check E o r).missing ↔ k ∈ unmatched o r ∧ exclKey E .svg k = false := by
  simp [check]

/-- A rewrite svg is extra exactly when it is unmatched and not excluded.
$$\forall E, o, r, k:\ k \in \operatorname{extra}(E, o, r) \iff k \in \operatorname{unmatched}(r, o) \land \lnot\operatorname{exclKey}(E, \mathrm{svg}, k)$$ -/
theorem mem_extra (E : List Excl) (o r : List String) (k : String) :
    k ∈ (check E o r).extra ↔ k ∈ unmatched r o ∧ exclKey E .svg k = false := by
  simp [check]

/-- The page passes exactly when every unmatched key of either arm is excluded.
$$\forall E, o, r:\ \operatorname{pass}(E, o, r) \iff (\forall k \in \operatorname{unmatched}(o, r),\ \operatorname{exclKey}(E, \mathrm{svg}, k)) \land (\forall k \in \operatorname{unmatched}(r, o),\ \operatorname{exclKey}(E, \mathrm{svg}, k))$$ -/
theorem pass_iff (E : List Excl) (o r : List String) :
    pass E o r = true ↔ (∀ k ∈ unmatched o r, exclKey E .svg k = true) ∧
      (∀ k ∈ unmatched r o, exclKey E .svg k = true) := by
  simp [pass, check, List.filter_eq_nil_iff]

/-- With no exclusions the page passes exactly when the two arms hold the same multiset of skeleton keys.
$$\forall o, r:\ \operatorname{pass}([\,], o, r) \iff \forall k,\ \operatorname{count}(k, o) = \operatorname{count}(k, r)$$ -/
theorem pass_nil_iff (o r : List String) : pass [] o r = true ↔ ∀ k, o.count k = r.count k := by
  have h1 := unmatched_nil_iff o r
  have h2 := unmatched_nil_iff r o
  have ht : ∀ l : List String, l.filter (fun _ => true) = l := fun l => List.filter_eq_self.mpr (by simp)
  simp only [pass, check, exclKey, List.any_nil, Bool.not_false, List.isEmpty_iff, Bool.and_eq_true, ht]
  rw [h1, h2]
  constructor
  · rintro ⟨a, b⟩ k; exact Nat.le_antisymm (a k) (b k)
  · intro h; exact ⟨fun k => Nat.le_of_eq (h k), fun k => Nat.le_of_eq (h k).symm⟩

/-- Svg exclusions (none yet): each entry names a skeleton key, the section that owns the svg, and why.
$$E_{\mathrm{svg}} = [\,]$$ -/
def exclusions : List Excl := []

/-- The svg exclusions are well formed and all belong to the svg check.
$$\operatorname{wf}(E_{\mathrm{svg}}) \land \forall e \in E_{\mathrm{svg}},\ e.c = \mathrm{svg}$$ -/
theorem exclusions_wf : wf exclusions = true ∧ ∀ e ∈ exclusions, e.check = .svg := by decide

#guard check [] ["a", "a", "b"] ["a", "c"] == ⟨["a", "b"], ["c"]⟩
#guard check [⟨.svg, "nav", "b", "r"⟩] ["a", "b"] ["a"] == ⟨[], []⟩
#guard pass [] ["a", "b"] ["b", "a"]

end Fw.Port.Svg
