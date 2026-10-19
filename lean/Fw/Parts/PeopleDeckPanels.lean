/-!
# people.deck panels: which feed panel shows, and what it lists

Restated (not copied) from `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`, read independently of the TS part:

* 6456 and 10719-10721: the feed has four tabs $\{\text{posts}, \text{services}, \text{reviews}, \text{about}\}$; the panel is the
  posts panel for `posts`, the services grid for `services`, the reviews panel for `reviews` and the about panel for every
  other value (the fallback branch);
* 6486-6496 (`QD`, `$D`): the review filters are `all` (the profile's review total) followed by one filter per service whose
  review count is above 0; `all` lists every review, a service filter only the reviews of that service;
* 6500-6503 (`tO`) and 10478-10479, 10498: the faces are the authors with a not yet seen avatar, the first three are drawn,
  and the "+n" chip shows $\max(0, \mathit{total} - \min(\mathit{faces}, 3))$ when positive;
* 6475-6477 (`XD`): the verdict word of a score, thresholds $4.5$, $4$, $3.5$, $2.5$;
* 10268, 10287: the summary draws five stars, star $i$ is filled iff $i < \operatorname{round}(\mathit{score})$;
* 10460: the show-more toggle flips an expanded flag;
* 6676-6678, 6752-6754, 6788-6790, 6816-6818: the about panel always shows work experience and skills, and shows
  education, certificates, languages and awards only when their list is not empty.

Section order of the about panel follows the template (6551): experience, education, skills, certificates, languages, awards.
-/
namespace Fw.Parts.PeopleDeckPanels

/-! ## Tabs -/

/-- The four feed tabs (JS 6456). $$T = \{\text{posts}, \text{services}, \text{reviews}, \text{about}\}$$ -/
inductive Tab where
  | posts | services | reviews | about
  deriving DecidableEq, Repr

/-- The tab of an id string; any other string falls to about (JS 10720). $$\operatorname{tab}(s)$$ -/
def tabOf (s : String) : Tab :=
  if s = "posts" then .posts else if s = "services" then .services else if s = "reviews" then .reviews else .about

/-- The wire id of a tab. $$\operatorname{id}(t)$$ -/
def Tab.id : Tab → String
  | .posts => "posts"
  | .services => "services"
  | .reviews => "reviews"
  | .about => "about"

/-- The four tab ids, in order (JS 6456). $$\mathrm{ids} = [\text{posts}, \text{services}, \text{reviews}, \text{about}]$$ -/
def tabIds : List String := ["posts", "services", "reviews", "about"]

/-- Each of the four tabs round-trips through its id, so exactly one panel shows per tab.
$$\forall t \in T,\ \operatorname{tab}(\operatorname{id}(t)) = t$$ -/
theorem tabOf_id (t : Tab) : tabOf t.id = t := by
  cases t <;> decide

/-- A string that is none of the four ids shows the about panel.
$$s \notin \mathrm{ids} \Rightarrow \operatorname{tab}(s) = \text{about}$$ -/
theorem tabOf_other (s : String) (h : s ∉ tabIds) : tabOf s = .about := by
  unfold tabOf
  simp only [tabIds, List.mem_cons, List.not_mem_nil, or_false, not_or] at h
  simp [h.1, h.2.1, h.2.2.1]

/-! ## Review filters -/

/-- A service as the filters see it: id and review count. -/
structure Svc where
  id : String
  reviewCount : Nat
  deriving DecidableEq, Repr

/-- The filter ids: `all`, then each service with at least one review (JS 6486-6493).
$$[\text{all}] \mathbin{+\!\!+} [\,s.\mathrm{id} \mid s \in S,\ s.\mathrm{reviewCount} > 0\,]$$ -/
def filterIds (ss : List Svc) : List String :=
  "all" :: (ss.filter (fun s => 0 < s.reviewCount)).map Svc.id

/-- The filter ids number one plus the services with reviews, and `all` is first.
$$|\mathrm{filterIds}(S)| = 1 + |\{s \in S : s.\mathrm{reviewCount} > 0\}|$$ -/
theorem filterIds_length (ss : List Svc) : (filterIds ss).length = 1 + (ss.filter (fun s => 0 < s.reviewCount)).length := by
  unfold filterIds
  simp [Nat.add_comm]

/-- The filter `all` is always the first button. $$\mathrm{filterIds}(S)_0 = \text{all}$$ -/
theorem filterIds_head (ss : List Svc) : (filterIds ss).head? = some "all" := by
  simp [filterIds]

/-- The reviews a filter lists, given each review's service id (JS 6494-6496).
$$\operatorname{shown}(f, R) = R \text{ if } f = \text{all, else } [r \in R : r = f]$$ -/
def shown (f : String) (rs : List String) : List String :=
  if f = "all" then rs else rs.filter (fun r => r = f)

/-- The filter `all` lists every review. $$\operatorname{shown}(\text{all}, R) = R$$ -/
theorem shown_all (rs : List String) : shown "all" rs = rs := by
  simp [shown]

/-- A filter never lists more reviews than there are. $$|\operatorname{shown}(f, R)| \le |R|$$ -/
theorem shown_length_le (f : String) (rs : List String) : (shown f rs).length ≤ rs.length := by
  unfold shown
  split
  · exact Nat.le_refl _
  · exact List.length_filter_le _ _

/-- Every listed review belongs to the chosen service (or the filter is `all`).
$$f \ne \text{all},\ r \in \operatorname{shown}(f, R) \Rightarrow r = f$$ -/
theorem shown_mem (f : String) (rs : List String) (hf : f ≠ "all") (r : String) (h : r ∈ shown f rs) : r = f := by
  unfold shown at h
  simp only [hf, ite_false, List.mem_filter, decide_eq_true_eq] at h
  exact h.2

/-! ## Faces -/

/-- The authors with a not yet seen avatar, first occurrence kept (JS 6500-6503).
$$\operatorname{dedup}(L)$$ -/
def dedup (l : List String) : List String := l.eraseDups

/-- The avatars drawn: the first three distinct ones (JS 10498). $$\operatorname{faces}(L) = \operatorname{take}_3(\operatorname{dedup}(L))$$ -/
def faces (l : List String) : List String := (dedup l).take 3

/-- At most three faces are drawn. $$|\operatorname{faces}(L)| \le 3$$ -/
theorem faces_length_le (l : List String) : (faces l).length ≤ 3 := by
  unfold faces
  simp only [List.length_take]
  exact Nat.min_le_left _ _

/-- The "+n" chip count (JS 10479). $$\operatorname{more}(\mathit{total}, L) = \mathit{total} - \min(|\operatorname{dedup}(L)|, 3)$$ truncated at 0 -/
def more (total : Nat) (l : List String) : Nat := total - min (dedup l).length 3

/-- The chip shows exactly when the total exceeds the faces drawn by the distinct authors.
$$\operatorname{more}(\mathit{total}, L) > 0 \iff \min(|\operatorname{dedup}(L)|, 3) < \mathit{total}$$ -/
theorem more_pos_iff (total : Nat) (l : List String) : 0 < more total l ↔ min (dedup l).length 3 < total := by
  unfold more
  omega

/-! ## Score -/

/-- The verdict words (JS 6475-6477). -/
inductive Verdict where
  | excellent | veryGood | good | fair | poor
  deriving DecidableEq, Repr

/-- The verdict of a score. $$\operatorname{verdict}(x)$$ is excellent for $x \ge 4.5$, very good for $x \ge 4$, good for
$x \ge 3.5$, fair for $x \ge 2.5$, else poor. -/
def verdict (x : Rat) : Verdict :=
  if 9 / 2 ≤ x then .excellent else if 4 ≤ x then .veryGood else if 7 / 2 ≤ x then .good else if 5 / 2 ≤ x then .fair else .poor

/-- Rank of a verdict, higher is better. -/
def Verdict.rank : Verdict → Nat
  | .excellent => 4 | .veryGood => 3 | .good => 2 | .fair => 1 | .poor => 0

/-- The wire name of a verdict. -/
def Verdict.name : Verdict → String
  | .excellent => "excellent" | .veryGood => "veryGood" | .good => "good" | .fair => "fair" | .poor => "poor"

/-- A higher score never gets a lower verdict. $$x \le y \Rightarrow \operatorname{rank}(\operatorname{verdict}(x)) \le \operatorname{rank}(\operatorname{verdict}(y))$$ -/
theorem verdict_mono (x y : Rat) (h : x ≤ y) : (verdict x).rank ≤ (verdict y).rank := by
  unfold verdict
  grind [Verdict.rank]

/-- JS `Math.round`. $$\operatorname{rnd}(x) = \lfloor x + \tfrac12 \rfloor$$ -/
def rnd (x : Rat) : Int := (x + 1 / 2).floor

/-- Whether star $i$ (0-based) of the five is filled (JS 10287). $$\mathrm{filled}(x, i) \iff i < \operatorname{rnd}(x)$$ -/
def filled (x : Rat) (i : Nat) : Bool := decide ((i : Int) < rnd x)

/-- Filled stars are a prefix: if a star is filled, so is every earlier one.
$$\mathrm{filled}(x, j) \wedge i \le j \Rightarrow \mathrm{filled}(x, i)$$ -/
theorem filled_prefix (x : Rat) (i j : Nat) (hij : i ≤ j) (h : filled x j = true) : filled x i = true := by
  simp only [filled, decide_eq_true_eq] at *
  omega

/-- A score of 4.5 or more fills all five stars on the 5-point scale: $x \ge \tfrac92 \wedge x \le 5 \Rightarrow
\forall i < 5,\ \mathrm{filled}(x, i)$ is false only past $\operatorname{rnd}(x) = 5$; checked at the endpoints. -/
theorem filled_five : filled 5 4 = true ∧ filled (9 / 2) 4 = true ∧ filled (9 / 2 - 1 / 100) 4 = false := by
  decide +kernel

/-! ## Monogram -/

/-- The monogram of a name when no logo exists (JS 6478-6485 `ZD`): the first letter, upper-cased, of the first two
whitespace-separated words that start with a letter or digit. ASCII letters and digits only (an accepted limit: every name
in the data is ASCII, a TS test checks it). $$\operatorname{initials}(n)$$ -/
def initials (name : String) : String :=
  let ws : List (List Char) := (name.split Char.isWhitespace).toList.map (fun w => w.copy.toList)
  let ks : List (List Char) := ws.filter (fun w => match w with | c :: _ => c.isAlphanum | [] => false)
  String.ofList ((ks.take 2).map (fun w => match w with | c :: _ => c.toUpper | [] => ' '))

/-- A monogram has at most two letters. $$|\operatorname{initials}(n)| \le 2$$ -/
theorem initials_length_le (n : String) : (initials n).length ≤ 2 := by
  unfold initials
  simp only [String.length_ofList, List.length_map, List.length_take]
  exact Nat.min_le_left _ _

/-! ## Toggle -/

/-- The show-more toggle (JS 10460). $$\operatorname{flip}(b) = \lnot b$$ -/
def flip (b : Bool) : Bool := !b

/-- Two toggles restore the clamp. $$\operatorname{flip}(\operatorname{flip}(b)) = b$$ -/
theorem flip_flip (b : Bool) : flip (flip b) = b := by
  cases b <;> rfl

/-! ## About sections -/

/-- Section lengths of an about block: education, certificates, languages, awards (the optional ones). -/
structure AboutLens where
  education : Nat
  certificates : Nat
  languages : Nat
  awards : Nat
  deriving DecidableEq, Repr

/-- The section ids shown, in template order (JS 6551, 6676-6678, 6752-6754, 6788-6790, 6816-6818).
$$\mathrm{sections}(a)$$ -/
def sections (a : AboutLens) : List String :=
  ["experience"] ++ (if 0 < a.education then ["education"] else []) ++ ["skills"] ++
    (if 0 < a.certificates then ["certificates"] else []) ++ (if 0 < a.languages then ["languages"] else []) ++
    (if 0 < a.awards then ["awards"] else [])

/-- Experience comes first and skills are always present. $$\text{experience} \in \mathrm{sections}(a) \wedge \text{skills} \in
\mathrm{sections}(a)$$ -/
theorem sections_core (a : AboutLens) : "experience" ∈ sections a ∧ "skills" ∈ sections a := by
  simp [sections]

/-- An empty optional list shows no section. $$a.\mathrm{awards} = 0 \Rightarrow \text{awards} \notin \mathrm{sections}(a)$$ -/
theorem sections_awards_empty (a : AboutLens) (h : a.awards = 0) : "awards" ∉ sections a := by
  unfold sections
  simp [h]

end Fw.Parts.PeopleDeckPanels
