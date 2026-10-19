/-! Port completeness gate (port plan section L7): the sections the checks compare, the exclusion lists, and the
multiset difference every check decides its units with.

The snapshot carries no `data-fw` attribute, so a section is named by a pair of root selectors, one per arm, read from
the breakpoint gate's `anchors.json` (the first role of each part). A part whose roots name the same nodes as another
part's is left out (`dropped`, with the reason), so that each row owns its own nodes. `scripts/port/digest.mjs` reads
this table from `packages/contracts/golden/port/sections.json` (`lean/scripts/PortGolden.lean`);
`apps/site/test/port-sections.test.mjs` checks that the table and `dropped` cover `anchors.json`, that no node of the
snapshot page or of the prerendered page is matched by two section rows, and that the rows matching no node there are
exactly `unrooted`. Node matching runs in the site test (the selector matcher is a TS stand-in); the theorems here
decide the selector strings only. -/

namespace Fw.Port.Sections

/-- The five checks of the gate. -/
inductive Check | text | attrs | assets | svg | fonts
deriving Repr, DecidableEq, Inhabited

/-- Wire name of a check. Is the constructor name. -/
def Check.name : Check → String
  | .text => "text" | .attrs => "attrs" | .assets => "assets" | .svg => "svg" | .fonts => "fonts"

/-- One section: a part id, the root selector in the snapshot and the root selector in the prerendered rewrite. -/
structure Root where
  part : String
  orig : String
  rewrite : String
deriving Repr, DecidableEq

/-- One row per part id of `anchors.json` that is not in `dropped`, in its order: the part's first role. -/
def table : List Root := [
  ⟨"engine.scroll", "html", "html[data-fw=\"engine-scroll\"]"⟩,
  ⟨"hero.countdown", ".hero-track .countdown", "[data-fw=\"hero-countdown\"]"⟩,
  ⟨"morph.countdown", ".start-selling-morph-center .waitlist-closing-countdown", "[data-fw=\"morph-countdown\"]"⟩,
  ⟨"morph.columns", ".start-selling-morph-backdrop", "[data-fw=\"morph-panel\"] > [data-fw-role=\"backdrop\"]"⟩,
  ⟨"morph.tween", "html", "html[data-fw-morph-tween]"⟩,
  ⟨"morph.panel", ".start-selling-top-nav .start-selling-morph-panel", "[data-fw=\"morph-panel\"]"⟩,
  ⟨"nav", "header.start-selling-top-nav", "[data-fw=\"nav\"]"⟩,
  ⟨"nav.langMenu", ".start-selling-language-switch-wrap", "[data-fw=\"nav-lang\"]"⟩,
  ⟨"commission", "section.commission", "[data-fw=\"commission\"]"⟩,
  ⟨"commission.typing", ".fee-visual-scale", "[data-fw=\"commission-typing\"]"⟩,
  ⟨"overlays.drawer", ".why-bring", "[data-fw=\"overlay-drawer\"]"⟩,
  ⟨"overlays.signup", "dialog[data-modal-name=\"waitlist-signup\"]", "dialog[data-fw=\"overlay-signup\"]"⟩,
  ⟨"hero", ".hero-track", "[data-fw=\"hero-exit\"]"⟩,
  ⟨"hero.orbit", ".hero-track .hero > .orbit", "[data-fw=\"hero-orbit\"]"⟩,
  ⟨"hero.deck", ".hero-track .hero > .mobile-deck", "[data-fw=\"hero-deck\"]"⟩,
  ⟨"hero.accent", ".hero-track h1 em.script-accent", "[data-fw=\"hero-accent\"]"⟩,
  ⟨"hero.cue", ".hero-track .hero > button.scroll-cue", "[data-fw=\"hero-cue\"]"⟩,
  ⟨"people.card", "section#people", "[data-fw=\"people\"]"⟩,
  ⟨"people.o", ".start-selling-future-people-o", "[data-fw=\"people-o\"]"⟩,
  ⟨"people.carousel", ".start-selling-future-community-pill", "[data-fw=\"people-pill\"]"⟩,
  ⟨"people.deck", "#profile-showcase", "[data-fw=\"people-deck\"]"⟩,
  ⟨"pain", "section.pain", "[data-fw=\"pain\"]"⟩,
  ⟨"pain.notes", ".pain-sticky > .pain-canvas", "[data-fw=\"pain-notes\"]"⟩,
  ⟨"platform", "section#platform", "[data-fw=\"platform\"]"⟩,
  ⟨"platform.stageBg", ".start-selling-platform-stage", "[data-fw-row] > div:first-child"⟩,
  ⟨"platform.sweep", ".start-selling-platform-row-title-doc,.start-selling-platform-row-title-earn,.start-selling-platform-row-title-secure,.start-selling-platform-row-title-organized", "[data-fw-sweep]"⟩,
  ⟨"platform.glint", ".start-selling-platform-secure-network-dash", "[data-fw-dash]"⟩,
  ⟨"platform.entries", ".start-selling-platform-profile,.start-selling-platform-visual.is-search,.start-selling-platform-secure,.start-selling-platform-invoice", "[data-fw-visual]"⟩,
  ⟨"platform.marquee", ".start-selling-platform-profile-reviews-track", "[data-marquee]"⟩]

/-- A root is page level when its original selector is the document element: such a part owns no section and its
nodes count for the page. -/
def Root.pageLevel (r : Root) : Bool := r.orig == "html"

/-- The section rows: the table without its page-level rows. -/
def sections : List Root := table.filter (!·.pageLevel)

/-- The name of the page-level section. -/
def page : String := "page"

/-- The owner of a node, given for each of its ancestors (innermost first, the node itself included) the part ids
whose root selector matches that ancestor, in table order: the first id at the innermost ancestor that matches any
root, else the page. -/
def owner : List (List String) → String
  | [] => page
  | [] :: rest => owner rest
  | (i :: _) :: _ => i

/-- A node whose ancestors match no root belongs to the page. -/
theorem owner_page (A : List (List String)) (h : ∀ m ∈ A, m = []) : owner A = page := by
  induction A with
  | nil => rfl
  | cons m rest ih =>
    have hm : m = [] := h m (by simp)
    subst hm
    exact ih (fun x hx => h x (by simp [hx]))

/-- The owner is the first id of the innermost matching ancestor. -/
theorem owner_innermost (B A : List (List String)) (i : String) (m' : List String) (h : ∀ m ∈ B, m = []) :
    owner (B ++ (i :: m') :: A) = i := by
  induction B with
  | nil => rfl
  | cons b rest ih =>
    have hb : b = [] := h b (by simp)
    subst hb
    exact ih (fun x hx => h x (by simp [hx]))

#guard owner [[], ["nav", "hero"], ["hero"]] == "nav"
#guard owner [[], []] == "page"
#guard owner [] == "page"

/-- The parts of `anchors.json` that own no section, each with the reason: two parts whose roots name the same node
cannot both own it, so one of them is left out. -/
def dropped : List (String × String) := [
  ("nav.hitTest", "same root pair as nav: the nav header in both arms"),
  ("morph.mount", "a runtime mount that owns no markup: its original root .start-selling-platform is the section#platform node of platform, its rewrite root an empty hidden div"),
  ("hero.exit", "same root pair as hero: the hero track in both arms"),
  ("engine.scene", "a runtime scene over the platform section: its original root is the section#platform node of platform, its rewrite root is platform's")]

/-- The part ids of the table and of `dropped` are distinct, the table has 29 rows, exactly two are page level
(`engine.scroll`, `morph.tween`), and every dropped part has a reason. -/
theorem table_shape :
    table.length = 29 ∧ (table.map (·.part) ++ dropped.map (·.1)).Nodup ∧
      (table.filter (·.pageLevel)).map (·.part) = ["engine.scroll", "morph.tween"] ∧
      ∀ d ∈ dropped, d.2 ≠ "" := by decide +kernel

/-- No two section rows share an original root selector, and none share a rewrite root selector. Distinct strings do
not yet mean distinct nodes (two selectors can name one element); the site test decides that on both built pages. -/
theorem roots_distinct :
    (sections.map (·.orig)).Nodup ∧ (sections.map (·.rewrite)).Nodup := by decide +kernel

/-- The section rows whose roots match no node of the prerendered page, on either arm: their markup mounts at run
time, so they own no node of the prerendered page, and their ownership is undecided until check 5 (runtime states). -/
def unrooted : List String := ["morph.countdown", "morph.columns", "morph.panel", "overlays.drawer"]

/-- Every unrooted part is a section row. -/
theorem unrooted_sections : ∀ i ∈ unrooted, ∃ r ∈ sections, r.part = i := by decide +kernel

/-! ## Units and the multiset difference -/

/-- The units of `o` that `r` does not match, each occurrence on its own: walk `o`, and an element found in `r`
consumes one copy of it there. -/
def unmatched {α : Type} [BEq α] : List α → List α → List α
  | [], _ => []
  | a :: o, r => if r.contains a then unmatched o (r.erase a) else a :: unmatched o r

#guard unmatched [1, 1, 2, 3] [1, 3, 4] == [1, 2]
#guard unmatched ([] : List Nat) [1] == []
#guard unmatched [5] ([] : List Nat) == [5]

/-- The unmatched units are the multiset difference: each value occurs as often as its surplus in `o` over `r`
(truncated subtraction). -/
theorem count_unmatched {α : Type} [BEq α] [LawfulBEq α] (o r : List α) (x : α) :
    (unmatched o r).count x = o.count x - r.count x := by
  induction o generalizing r with
  | nil => simp [unmatched]
  | cons a o ih =>
    by_cases ha : r.contains a = true
    · have hmem : a ∈ r := by simpa using ha
      simp only [unmatched, ha, ite_true, ih, List.count_cons, List.count_erase]
      by_cases hx : a = x
      · subst hx
        have : 0 < r.count a := List.count_pos_iff.mpr hmem
        simp
        omega
      · simp [beq_iff_eq, hx]
    · have hnot : a ∉ r := by simpa using ha
      simp only [unmatched, ha, Bool.false_eq_true, ite_false, List.count_cons, ih]
      by_cases hx : a = x
      · subst hx
        have : r.count a = 0 := List.count_eq_zero.mpr hnot
        simp [this]
      · simp [beq_iff_eq, hx]

/-- Nothing is unmatched exactly when `r` holds every value at least as often as `o`. -/
theorem unmatched_nil_iff {α : Type} [BEq α] [LawfulBEq α] (o r : List α) :
    unmatched o r = [] ↔ ∀ x, o.count x ≤ r.count x := by
  constructor
  · intro h x
    have := count_unmatched o r x
    rw [h] at this
    simp at this
    omega
  · intro h
    cases hu : unmatched o r with
    | nil => rfl
    | cons y ys =>
      have hc := count_unmatched o r y
      rw [hu] at hc
      have : 0 < (y :: ys).count y := List.count_pos_iff.mpr (by simp)
      have := h y
      omega

/-! ## Exclusions -/

/-- One exclusion: the check, the section it belongs to (the page for a page-wide check), the unit key (a URL, a skeleton hash, a leaf, an attribute
name) and why the unit is not compared. -/
structure Excl where
  check : Check
  sec : String
  key : String
  reason : String
deriving Repr, DecidableEq

/-- A unit of a page-wide check (assets, svg) is excluded when an entry of that check names its key (such entries
name the page as their section, see `wf`). -/
def exclKey (E : List Excl) (c : Check) (k : String) : Bool := E.any fun e => e.check == c && e.key == k

/-- A unit of a sectioned check (text, attrs) is excluded when an entry of that check and section names its key. -/
def exclIn (E : List Excl) (c : Check) (s k : String) : Bool :=
  E.any fun e => e.check == c && e.sec == s && e.key == k

/-- `exclKey` unfolded. -/
theorem exclKey_iff (E : List Excl) (c : Check) (k : String) :
    exclKey E c k = true ↔ ∃ e ∈ E, e.check = c ∧ e.key = k := by
  simp [exclKey]

/-- `exclIn` unfolded. -/
theorem exclIn_iff (E : List Excl) (c : Check) (s k : String) :
    exclIn E c s k = true ↔ ∃ e ∈ E, e.check = c ∧ e.sec = s ∧ e.key = k := by
  simp [exclIn, and_assoc]

/-- The section an entry may name: the page for a page-wide check (assets, svg), a section row for a sectioned check
(text, attrs). -/
def Excl.secOk (e : Excl) : Bool :=
  match e.check with
  | .assets | .svg | .fonts => e.sec == page
  | .text | .attrs => sections.any (·.part == e.sec)

#guard Excl.secOk ⟨.svg, "page", "k", "r"⟩
#guard !Excl.secOk ⟨.assets, "nav", "k", "r"⟩
#guard Excl.secOk ⟨.text, "hero.countdown", "*", "r"⟩
#guard !Excl.secOk ⟨.text, "page", "*", "r"⟩
#guard !Excl.secOk ⟨.attrs, "engine.scene", "k", "r"⟩

/-- A list is well formed when every entry has a reason and a section its check allows, and no two entries share
check, section and key; for the page-wide checks the section is the page, so their keys are distinct per check. -/
def wf (E : List Excl) : Bool :=
  E.all (fun e => e.reason != "" && e.secOk) && (E.map fun e => (e.check.name, e.sec, e.key)).Nodup

#guard wf [⟨.text, "nav", "k", "r"⟩, ⟨.text, "hero", "k", "r"⟩]
#guard !wf [⟨.text, "nav", "k", ""⟩]
#guard !wf [⟨.text, "nav", "k", "r"⟩, ⟨.text, "nav", "k", "s"⟩]
#guard !wf [⟨.svg, "nav", "k", "r"⟩]
#guard !wf [⟨.svg, "page", "k", "r"⟩, ⟨.svg, "page", "k", "s"⟩]

end Fw.Port.Sections
