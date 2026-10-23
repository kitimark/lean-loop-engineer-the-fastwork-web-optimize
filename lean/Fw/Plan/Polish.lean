/-!
# `plan.polishPlan` and `plan.polishCuts`: which files the comment and prose passes may edit, and which prose cuts apply
Skip-class paths are never in a stage's scope (`skip_never_edited`); a cut applies only when unique, prose and `cutSafe`.
-/
namespace Fw.Plan.Polish

inductive Cls where
  | code | shell | prose | skip
deriving Repr, DecidableEq

def Cls.name : Cls → String
  | .code => "code" | .shell => "shell" | .prose => "prose" | .skip => "skip"

def segs (p : String) : List String := p.splitOn "/"

def baseName (p : String) : String := (segs p).getLast?.getD ""

def extOf (p : String) : String :=
  match (baseName p).splitOn "." with
  | [] | [_] => ""
  | xs => xs.getLast?.getD ""

def skipRoots : List String :=
  ["snapshot/", "packages/contracts/golden/", "lean/golden/", "lean/.lake/", ".cache/", ".local/", ".claude/worktrees/"]

def skipSegs : List String := ["fixtures", "golden", "node_modules", "props-lint-cases", ".lake", ".."]

def lockNames : List String := ["pnpm-lock.yaml", "package-lock.json", "lake-manifest.json"]

def shellExts : List String := ["sh", "bash"]

def codeExts : List String := ["ts", "tsx", "mts", "cts", "js", "jsx", "mjs", "cjs", "lean", "yml", "yaml"]

def proseJson : List String := ["docs/team/incidents/ledger.json", "docs/team/work-graph.json"]

def protectedDirs : List String := [".claude/"]

def protectedFiles : List String := ["CLAUDE.md"]

def protectedPath (p : String) : Bool := protectedFiles.contains p || protectedDirs.any fun r => p.startsWith r

def polishable (p : String) : Bool := !protectedPath p

/-- A character a worktree directory name may hold. -/
def nameChar (c : Char) : Bool := c.isAlphanum || c == '_' || c == '-' || c == '.'

/-- The worktree name of an absolute directory `/<...>/.claude/worktrees/<name>`, none for a relative, `~` or placeholder path or a
name with other characters. `fw polish plan` prints it as `worktree-name <name>`, one word that a copy of the absolute path cannot damage. -/
def wtName (dir : String) : Option String :=
  if dir.startsWith "/" then
    match (segs dir).reverse with
    | n :: "worktrees" :: ".claude" :: _ => if n != "" && n != "." && n != ".." && n.all nameChar then some n else none
    | _ => none
  else none

def genName (p : String) : Bool := ((baseName p).splitOn ".gen.").length > 1

def skipped (gen : List String) (p : String) : Bool :=
  gen.contains p || !polishable p || skipRoots.any (fun r => p.startsWith r) || (segs p).any skipSegs.contains || genName p ||
    lockNames.contains (baseName p) || p.startsWith "/" || p.isEmpty

def stamped (head : String) : Bool := ["-- GENERATED", "// GENERATED", "# GENERATED"].any fun m => head.startsWith m

/-- `outputs`: what the generators report they write (`ci-paths`); `heads`: (path, first line) of the diff's files. -/
def genOf (outputs : List String) (heads : List (String × String)) : List String :=
  outputs ++ (heads.filter fun h => stamped h.2).map (·.1)

def classify (gen : List String) (p : String) : Cls :=
  if skipped gen p then .skip
  else if shellExts.contains (extOf p) then .shell
  else if codeExts.contains (extOf p) then .code
  else if extOf p == "md" || proseJson.contains p then .prose
  else .skip

/-- The line-comment token of a code or shell path. -/
def mark (p : String) : Option String :=
  let e := extOf p
  if shellExts.contains e || e == "yml" || e == "yaml" then some "#"
  else if e == "lean" then some "--"
  else if codeExts.contains e then some "//"
  else none

inductive Stage where
  | comments | prose
deriving Repr, DecidableEq

def Stage.name : Stage → String
  | .comments => "comments" | .prose => "prose"

def Stage.admits : Stage → Cls → Bool
  | .comments, .code | .comments, .shell | .prose, .prose => true
  | _, _ => false

def scope (gen : List String) (st : Stage) (ps : List String) : List String :=
  (ps.filter fun p => st.admits (classify gen p)).eraseDups

def stages (gen : List String) (ps : List String) : List Stage :=
  [Stage.comments, Stage.prose].filter fun st => !(scope gen st ps).isEmpty

/-- After the passes: an edited path is kept iff some stage admits it and it is in the branch diff. -/
def keeps (gen diff : List String) (p : String) : Bool :=
  diff.contains p && [Stage.comments, Stage.prose].any fun st => st.admits (classify gen p)

/-- The paths of `ps` that were clean at plan time. -/
def undirty (dirtyBefore ps : List String) : List String := ps.filter fun p => !dirtyBefore.contains p

/-- A path dirty at plan time is in no stage scope, is not kept and is not restored; the plan is computed from `undirty`. -/
theorem dirty_never_scoped (gen dirtyBefore ps ed : List String) (p : String) (h : p ∈ dirtyBefore) :
    (∀ st, p ∉ scope gen st (undirty dirtyBefore ps)) ∧ p ∉ (undirty dirtyBefore ed).filter (keeps gen (undirty dirtyBefore ps))
      ∧ p ∉ (undirty dirtyBefore ed).filter (fun q => !keeps gen (undirty dirtyBefore ps) q) := by
  have hn : ∀ l, p ∉ undirty dirtyBefore l := by
    intro l hp
    simp [undirty, List.mem_filter] at hp
    exact hp.2 h
  refine ⟨fun st hp => ?_, fun hp => hn _ (List.mem_filter.1 hp).1, fun hp => hn _ (List.mem_filter.1 hp).1⟩
  simp only [scope, List.mem_eraseDups, List.mem_filter] at hp
  exact hn _ hp.1

theorem skipped_skip (gen : List String) (p : String) (h : skipped gen p = true) : classify gen p = .skip := by
  simp [classify, h]

theorem protected_skip (gen : List String) (p : String) (h : protectedPath p = true) : classify gen p = .skip :=
  skipped_skip gen p (by simp [skipped, polishable, h])

theorem claude_dir_protected (s : String) : protectedPath (".claude/" ++ s) = true := by
  simp [protectedPath, protectedDirs]

theorem claude_md_protected : protectedPath "CLAUDE.md" = true := by simp [protectedPath, protectedFiles]

theorem polishable_iff (p : String) : polishable p = true ↔ protectedPath p = false := by simp [polishable]

theorem wtName_relative (dir : String) (h : dir.startsWith "/" = false) : wtName dir = none := by simp [wtName, h]

theorem wtName_safe (dir n : String) (h : wtName dir = some n) : (n != "" && n.all nameChar) = true := by
  unfold wtName at h
  split at h
  · split at h
    · split at h
      · simp_all
      · cases h
    · cases h
  · cases h

example : wtName "~/source/x/.claude/worktrees/wf_b291cc70-2f8-1" = none := wtName_relative _ (by simp)

theorem wtName_not_dots (dir n : String) (h : wtName dir = some n) : (n != "." && n != "..") = true := by
  unfold wtName at h
  split at h
  · split at h
    · split at h
      · simp_all
      · cases h
    · cases h
  · cases h

theorem gen_skip (gen : List String) (p : String) (h : p ∈ gen) : classify gen p = .skip :=
  skipped_skip gen p (by simp [skipped, h])

theorem stamped_skip (outs : List String) (heads : List (String × String)) (p h : String) (hm : (p, h) ∈ heads)
    (hs : stamped h = true) : classify (genOf outs heads) p = .skip :=
  gen_skip _ p (List.mem_append_right _ (List.mem_map.2 ⟨(p, h), List.mem_filter.2 ⟨hm, hs⟩, rfl⟩))

theorem snapshot_skip (gen : List String) (p : String) (h : p.startsWith "snapshot/" = true) :
    classify gen p = .skip :=
  skipped_skip gen p (by simp [skipped, skipRoots, h])

theorem admits_not_skip (st : Stage) : st.admits .skip = false := by cases st <;> rfl

theorem skip_never_edited (gen : List String) (st : Stage) (ps : List String) (p : String)
    (h : p ∈ scope gen st ps) : classify gen p ≠ .skip := by
  intro hs
  simp only [scope, List.mem_eraseDups, List.mem_filter] at h
  rw [hs, admits_not_skip] at h
  exact Bool.false_ne_true h.2

theorem gen_never_edited (gen : List String) (st : Stage) (ps : List String) (p : String) (h : p ∈ gen) :
    p ∉ scope gen st ps := fun hm => skip_never_edited gen st ps p hm (gen_skip gen p h)

theorem kept_not_skip (gen diff : List String) (p : String) (h : keeps gen diff p = true) :
    classify gen p ≠ .skip := by
  intro hs
  simp [keeps, hs, Stage.admits] at h

theorem kept_in_diff (gen diff : List String) (p : String) (h : keeps gen diff p = true) : p ∈ diff := by
  simp only [keeps, Bool.and_eq_true, List.contains_iff_mem] at h
  exact h.1

theorem protected_never_scoped (gen : List String) (st : Stage) (ps : List String) (p : String)
    (h : protectedPath p = true) : p ∉ scope gen st ps := fun hm => skip_never_edited gen st ps p hm (protected_skip gen p h)

theorem protected_not_kept (gen diff : List String) (p : String) (h : protectedPath p = true) :
    keeps gen diff p = false := by
  cases hk : keeps gen diff p
  · rfl
  · exact absurd (protected_skip gen p h) (kept_not_skip gen diff p hk)

theorem shell_mark (gen : List String) (p : String) (h : classify gen p = .shell) : mark p = some "#" := by
  simp only [classify] at h
  split at h
  · cases h
  split at h
  · rename_i hs
    have hm : extOf p ∈ shellExts := by simpa using hs
    simp [mark, hm]
  split at h
  · cases h
  split at h <;> cases h

theorem shell_not_lean (gen : List String) (p : String) (h : classify gen p = .shell) : mark p ≠ some "--" := by
  rw [shell_mark gen p h]; decide

theorem scope_mem (gen : List String) (st : Stage) (ps : List String) (p : String) :
    p ∈ scope gen st ps ↔ p ∈ ps ∧ st.admits (classify gen p) = true := by
  simp [scope]

theorem mem_stages (gen ps : List String) (st : Stage) :
    st ∈ stages gen ps ↔ ∃ p ∈ ps, st.admits (classify gen p) = true := by
  have hst : st ∈ [Stage.comments, Stage.prose] := by cases st <;> simp
  rw [stages, List.mem_filter]
  simp only [hst, true_and]
  constructor
  · intro h
    cases hs : scope gen st ps with
    | nil => simp [hs] at h
    | cons q qs => exact ⟨q, ((scope_mem gen st ps q).1 (hs ▸ List.mem_cons_self))⟩
  · rintro ⟨p, hp, ha⟩
    have hm : p ∈ scope gen st ps := (scope_mem gen st ps p).2 ⟨hp, ha⟩
    cases hs : scope gen st ps with
    | nil => simp [hs] at hm
    | cons => rfl

theorem comments_runs_iff (gen ps : List String) :
    Stage.comments ∈ stages gen ps ↔ ∃ p ∈ ps, classify gen p = .code ∨ classify gen p = .shell := by
  rw [mem_stages]
  constructor
  · rintro ⟨p, hp, ha⟩
    refine ⟨p, hp, ?_⟩
    revert ha; cases classify gen p <;> simp [Stage.admits]
  · rintro ⟨p, hp, hc⟩
    exact ⟨p, hp, by rcases hc with hc | hc <;> rw [hc] <;> rfl⟩

theorem prose_runs_iff (gen ps : List String) :
    Stage.prose ∈ stages gen ps ↔ ∃ p ∈ ps, classify gen p = .prose := by
  rw [mem_stages]
  constructor
  · rintro ⟨p, hp, ha⟩
    refine ⟨p, hp, ?_⟩
    revert ha; cases classify gen p <;> simp [Stage.admits]
  · rintro ⟨p, hp, hc⟩
    exact ⟨p, hp, by rw [hc]; rfl⟩

theorem stages_nil (gen : List String) : stages gen [] = [] := by
  simp [stages, scope]

/-! ## Cuts -/

def statusWords : List String := ["CONFIRMED", "INFERRED", "MEASURED"]

/-- Polarity words: a cut that drops one flips or loses a claim. -/
def polarWords : List String :=
  ["not", "Not", "no", "No", "never", "Never", "without", "Without", "unless", "Unless"]

def wordChar (c : Char) : Bool := c.isAlphanum || "._/:-#+~".contains c

def trimTail (w : String) : String :=
  String.ofList ((w.toList.reverse.dropWhile fun c => ".:,-#".contains c).reverse)

def digits (s : String) : Bool := !s.isEmpty && s.all Char.isDigit

def isFileLine (w : String) : Bool :=
  match (w.splitOn ":").reverse with
  | ln :: pre@(_ :: _) =>
    let p := ":".intercalate pre.reverse
    (match ln.splitOn "-" with | [a] => digits a | [a, b] => digits a && digits b | _ => false) &&
      (p.contains '/' || p.contains '.') && p.any Char.isAlpha
  | _ => false

def isCommit (w : String) : Bool :=
  7 ≤ w.length && w.length ≤ 40 && w.toList.all (fun c => "0123456789abcdef".toList.contains c) &&
    w.any Char.isDigit && w.any Char.isAlpha

/-- Numbers (digit runs), `path:line`, commit ids and status words of a text; run ids are digit runs. -/
def facts (s : String) : List String :=
  ((s.splitToList (!·.isDigit)).filter (!·.isEmpty) ++
    ((s.splitToList (!wordChar ·)).map trimTail).filter fun w =>
      isFileLine w || isCommit w || statusWords.contains w || polarWords.contains w).eraseDups

def missing (old new : String) : List String :=
  let fn := facts new
  (facts old).filter (!fn.contains ·)

def cutSafe (old new : String) : Bool := (missing old new).isEmpty

theorem cutSafe_iff (old new : String) : cutSafe old new = true ↔ ∀ f ∈ facts old, f ∈ facts new := by
  simp [cutSafe, missing, List.filter_eq_nil_iff]

theorem cutSafe_refl (s : String) : cutSafe s s = true := by
  rw [cutSafe_iff]; exact fun _ h => h

/-- Space before a closing mark, after an opening one, or two parentheticals in a row. -/
def badPairs : List String := [" ;", " ,", " .", " )", " :", "( ", ") ("]

def countAux (p : List Char) : List Char → Nat → Nat
  | [], n => n
  | c :: cs, n => countAux p cs (if p.isPrefixOf (c :: cs) then n + 1 else n)

def occ (pat s : String) : Nat := if pat.isEmpty then 0 else countAux pat.toList s.toList 0

def punctOk (old new : String) : Bool := badPairs.all fun b => occ b new ≤ occ b old

def jsonSafe (path old new : String) : Bool :=
  extOf path != "json" || ![old, new].any fun t => t.contains '"' || t.contains '\\' || t.contains '\n'

structure Cut where
  path : String
  old : String
  new : String
deriving Repr

inductive CutV where
  | apply | notProse | notFound | notUnique | dropsFacts (ms : List String) | breaksPunct | breaksJson
deriving Repr, DecidableEq

def CutV.name : CutV → String
  | .apply => "apply" | .notProse => "notProse" | .notFound => "notFound" | .notUnique => "notUnique"
  | .dropsFacts _ => "dropsFacts" | .breaksPunct => "breaksPunct" | .breaksJson => "breaksJson"

/-- One cut against the current text of its file. -/
def judge (gen : List String) (doc : String) (c : Cut) : CutV :=
  if classify gen c.path != .prose then .notProse
  else if occ c.old doc = 0 then .notFound
  else if occ c.old doc ≥ 2 then .notUnique
  else if !cutSafe c.old c.new then .dropsFacts (missing c.old c.new)
  else if !punctOk c.old c.new then .breaksPunct
  else if !jsonSafe c.path c.old c.new then .breaksJson
  else .apply

theorem judge_apply_iff (gen : List String) (doc : String) (c : Cut) :
    judge gen doc c = .apply ↔ classify gen c.path = .prose ∧ occ c.old doc = 1 ∧ cutSafe c.old c.new = true ∧
      punctOk c.old c.new = true ∧ jsonSafe c.path c.old c.new = true := by
  unfold judge
  by_cases h1 : classify gen c.path = .prose <;> simp only [h1, bne_self_eq_false, Bool.false_eq_true, ↓reduceIte,
    true_and, false_and, reduceCtorEq, bne_iff_ne, ne_eq, not_false_eq_true, Bool.not_eq_true']
  by_cases h2 : occ c.old doc = 0
  · simp [h2]
  by_cases h3 : occ c.old doc ≥ 2
  · simp only [h2, h3, ↓reduceIte, reduceCtorEq, false_iff]; omega
  have h4 : occ c.old doc = 1 := by omega
  simp only [h4, true_and]
  cases cutSafe c.old c.new <;> cases punctOk c.old c.new <;> cases jsonSafe c.path c.old c.new <;> simp

theorem judge_apply_unique (gen : List String) (doc : String) (c : Cut) (h : judge gen doc c = .apply) :
    occ c.old doc = 1 := ((judge_apply_iff gen doc c).1 h).2.1

theorem judge_apply_safe (gen : List String) (doc : String) (c : Cut) (h : judge gen doc c = .apply) :
    ∀ f ∈ facts c.old, f ∈ facts c.new := (cutSafe_iff _ _).1 ((judge_apply_iff gen doc c).1 h).2.2.1

theorem judge_apply_prose (gen : List String) (doc : String) (c : Cut) (h : judge gen doc c = .apply) :
    classify gen c.path = .prose := ((judge_apply_iff gen doc c).1 h).1

theorem judge_skip (gen : List String) (doc : String) (c : Cut) (h : classify gen c.path = .skip) :
    judge gen doc c = .notProse := by simp [judge, h]

theorem judge_notFound (gen : List String) (doc : String) (c : Cut) (hp : classify gen c.path = .prose)
    (h : occ c.old doc = 0) : judge gen doc c = .notFound := by simp [judge, hp, h]

theorem judge_notUnique (gen : List String) (doc : String) (c : Cut) (hp : classify gen c.path = .prose)
    (h : occ c.old doc ≥ 2) : judge gen doc c = .notUnique := by
  have : occ c.old doc ≠ 0 := by omega
  simp [judge, hp, h, this]

theorem judge_dropsFacts (gen : List String) (doc : String) (c : Cut) (hp : classify gen c.path = .prose)
    (h1 : occ c.old doc = 1) (h : cutSafe c.old c.new = false) :
    judge gen doc c = .dropsFacts (missing c.old c.new) := by simp [judge, hp, h1, h]

theorem judge_breaksPunct (gen : List String) (doc : String) (c : Cut) (hp : classify gen c.path = .prose)
    (h1 : occ c.old doc = 1) (hs : cutSafe c.old c.new = true) (h : punctOk c.old c.new = false) :
    judge gen doc c = .breaksPunct := by simp [judge, hp, h1, hs, h]

theorem judge_breaksJson (gen : List String) (doc : String) (c : Cut) (hp : classify gen c.path = .prose)
    (h1 : occ c.old doc = 1) (hs : cutSafe c.old c.new = true) (hq : punctOk c.old c.new = true)
    (h : jsonSafe c.path c.old c.new = false) : judge gen doc c = .breaksJson := by
  simp [judge, hp, h1, hs, hq, h]

/-- Judge the cuts in order, each against the text the earlier applied cuts left. -/
def applyAll (gen : List String) (doc : String) (cs : List Cut) : String × List CutV :=
  cs.foldl (fun (d, vs) c =>
    let v := judge gen d c
    (if v = .apply then d.replace c.old c.new else d, vs ++ [v])) (doc, [])

/-! ## Hunks: an edit stays only near the branch's own changed lines -/

/-- Lines `start .. start + len - 1` of one side of a `git diff -U0` hunk; `len = 0` is a point after line `start`. -/
structure Span where
  start : Nat
  len : Nat
deriving Repr, DecidableEq

/-- The last line of a span; a point span ends where it starts. -/
def Span.hi (s : Span) : Nat := s.start + max s.len 1 - 1

/-- Lines of margin around a branch hunk inside which an edit is kept. -/
def margin : Nat := 3

/-- `hs`: the branch's hunks of one file (merge-base to head); `e`: one edit hunk against head. -/
def admitted (hs : List Span) (e : Span) : Bool :=
  hs.any fun h => decide (h.start - margin ≤ e.start ∧ e.hi ≤ h.hi + margin)

theorem Span.start_le_hi (s : Span) : s.start ≤ s.hi := by
  unfold Span.hi; omega

theorem admitted_iff (hs : List Span) (e : Span) :
    admitted hs e = true ↔ ∃ h ∈ hs, h.start - margin ≤ e.start ∧ e.hi ≤ h.hi + margin := by
  simp [admitted]

theorem admitted_nil (e : Span) : admitted [] e = false := rfl

theorem admitted_hunk (hs : List Span) (h : Span) (hm : h ∈ hs) : admitted hs h = true :=
  (admitted_iff hs h).2 ⟨h, hm, by have := h.start_le_hi; omega, by have := h.start_le_hi; omega⟩

theorem admitted_inside (hs : List Span) (h e : Span) (hm : h ∈ hs) (a : h.start ≤ e.start) (b : e.hi ≤ h.hi) :
    admitted hs e = true :=
  (admitted_iff hs e).2 ⟨h, hm, by have := e.start_le_hi; omega, by have := e.start_le_hi; omega⟩

theorem restored_far_above (hs : List Span) (e : Span) (far : ∀ h ∈ hs, h.hi + margin < e.start) :
    admitted hs e = false := by
  cases hb : admitted hs e
  · rfl
  · obtain ⟨h, hm, _, h2⟩ := (admitted_iff hs e).1 hb
    have := far h hm; have := e.start_le_hi; omega

theorem restored_far_below (hs : List Span) (e : Span) (far : ∀ h ∈ hs, e.hi + margin < h.start) :
    admitted hs e = false := by
  cases hb : admitted hs e
  · rfl
  · obtain ⟨h, hm, h1, _⟩ := (admitted_iff hs e).1 hb
    have := far h hm; have := e.start_le_hi; omega

/-- The lines `comment-sicko` may edit for a hunk: the hunk plus the margin, first line 1. -/
def Span.reach (s : Span) : Nat × Nat := (max 1 (s.start - margin), s.hi + margin)

theorem reach_admits (h : Span) : admitted [h] ⟨h.reach.1, 1⟩ = true :=
  admitted_iff _ _ |>.2 ⟨h, List.mem_singleton.2 rfl, by simp [Span.reach, Span.hi, margin]; omega,
    by simp [Span.reach, Span.hi, margin]; omega⟩

/-! ## Paths: an admitted path is repo-relative and never leaves the worktree -/

/-- Walk the segments with the depth below the root; `..` at depth 0 leaves the root. -/
def depthOk : List String → Nat → Bool
  | [], _ => true
  | s :: r, d =>
    if s == ".." then (match d with | 0 => false | d + 1 => depthOk r d)
    else if s == "." || s.isEmpty then depthOk r d
    else depthOk r (d + 1)

def relOk (p : String) : Bool := !p.isEmpty && !p.startsWith "/" && depthOk (segs p) 0

theorem relOk_empty (p : String) (h : p.isEmpty = true) : relOk p = false := by simp [relOk, h]

theorem relOk_abs (p : String) (h : p.startsWith "/" = true) : relOk p = false := by simp [relOk, h]

theorem relOk_up (p : String) (r : List String) (h : segs p = ".." :: r) : relOk p = false := by
  simp [relOk, h, depthOk]

theorem depthOk_plain (l : List String) (hl : ∀ s ∈ l, s ≠ "..") (d : Nat) : depthOk l d = true := by
  induction l generalizing d with
  | nil => rfl
  | cons s r ih =>
    have hs : (s == "..") = false := by simpa using hl s List.mem_cons_self
    have hr := ih (fun x hx => hl x (List.mem_cons_of_mem _ hx))
    simp only [depthOk, hs, Bool.false_eq_true, ↓reduceIte]
    split <;> simp [hr]

theorem relOk_plain (p : String) (hne : p.isEmpty = false) (hab : p.startsWith "/" = false)
    (h : ∀ s ∈ segs p, s ≠ "..") : relOk p = true := by
  simp [relOk, hne, hab, depthOk_plain _ h]

/-- An edit hunk of `p` is kept iff `p` is a relative path inside the worktree and the hunk lies inside a branch hunk plus the margin. -/
def editKept (hs : List Span) (p : String) (e : Span) : Bool := relOk p && admitted hs e

theorem editKept_rel (hs : List Span) (p : String) (e : Span) (h : editKept hs p e = true) : relOk p = true := by
  simp only [editKept, Bool.and_eq_true] at h; exact h.1

theorem editKept_near (hs : List Span) (p : String) (e : Span) (h : editKept hs p e = true) :
    ∃ x ∈ hs, x.start - margin ≤ e.start ∧ e.hi ≤ x.hi + margin := by
  simp only [editKept, Bool.and_eq_true] at h; exact (admitted_iff hs e).1 h.2

/-! ## The main checkout stays untouched -/

/-- The dirty paths of the main checkout that the polish plan names. -/
def blocked (dirty planned : List String) : List String := (dirty.filter planned.contains).eraseDups

theorem blocked_mem (d ps : List String) (p : String) : p ∈ blocked d ps ↔ p ∈ d ∧ p ∈ ps := by
  simp [blocked]

theorem blocked_empty_of_clean (ps : List String) : blocked [] ps = [] := rfl

theorem blocked_ne_nil (d ps : List String) (p : String) (hd : p ∈ d) (hp : p ∈ ps) : blocked d ps ≠ [] := by
  intro h
  have := (blocked_mem d ps p).2 ⟨hd, hp⟩
  rw [h] at this; simp at this

/-! ## The polish stage ends clean -/

/-- What the worktree holds after the commit step: tracked paths that differ from HEAD (index or tree) and untracked paths. -/
structure St where
  dirty : List String
  untracked : List String
deriving Repr, DecidableEq

/-- Paths to restore from HEAD and untracked paths to delete. -/
structure Act where
  restore : List String
  remove : List String
deriving Repr, DecidableEq

def Act.run (a : Act) (s : St) : St :=
  ⟨s.dirty.filter fun p => !a.restore.contains p, s.untracked.filter fun p => !a.remove.contains p⟩

/-- Restore the dirty paths that were clean at plan time (`dirtyBefore`; a path the builder had dirty keeps its edits);
delete the untracked paths that were not there before the polish stage. -/
def settle (before dirtyBefore : List String) (s : St) : Act :=
  ⟨s.dirty.filter fun p => !dirtyBefore.contains p, s.untracked.filter fun p => !before.contains p⟩

/-- With a clean worktree at plan time no dirty path survives the settle. -/
theorem settle_clean (before : List String) (s : St) : ((settle before [] s).run s).dirty = [] := by
  simp [settle, Act.run, List.filter_eq_nil_iff]

/-- A path still dirty after the settle was dirty at plan time. -/
theorem settle_dirty_before (before dirtyBefore : List String) (s : St) (p : String)
    (h : p ∈ ((settle before dirtyBefore s).run s).dirty) : p ∈ dirtyBefore := by
  simp [settle, Act.run] at h
  rcases h with ⟨h1, h2⟩
  rcases h2 with h2 | h2
  · exact absurd h1 h2
  · exact h2

/-- Builder work is never wiped: a path dirty at plan time keeps its edits. -/
theorem settle_keeps_dirty_before (before dirtyBefore : List String) (s : St) (p : String)
    (hs : p ∈ s.dirty) (hb : p ∈ dirtyBefore) : p ∈ ((settle before dirtyBefore s).run s).dirty := by
  simp [settle, Act.run]; exact ⟨hs, Or.inr hb⟩

/-- Only paths that were clean at plan time and are dirty now are restored. -/
theorem settle_restores_clean_only (before dirtyBefore : List String) (s : St) (p : String)
    (h : p ∈ (settle before dirtyBefore s).restore) : p ∈ s.dirty ∧ p ∉ dirtyBefore := by
  simp [settle] at h; exact ⟨h.1, h.2⟩

theorem settle_untracked_before (before dirtyBefore : List String) (s : St) (p : String)
    (h : p ∈ ((settle before dirtyBefore s).run s).untracked) : p ∈ before := by
  simp [settle, Act.run] at h
  rcases h with ⟨h1, h2⟩
  rcases h2 with h2 | h2
  · exact absurd h1 h2
  · exact h2

theorem settle_keeps_before (before dirtyBefore : List String) (s : St) (p : String) (hs : p ∈ s.untracked) (hb : p ∈ before) :
    p ∈ ((settle before dirtyBefore s).run s).untracked := by
  simp [settle, Act.run]; exact ⟨hs, Or.inr hb⟩

theorem settle_removes_created (before dirtyBefore : List String) (s : St) (p : String) (h : p ∈ (settle before dirtyBefore s).remove) :
    p ∈ s.untracked ∧ p ∉ before := by
  simp [settle] at h; exact ⟨h.1, h.2⟩

theorem settle_committed (before dirtyBefore : List String) (s : St) (hd : ∀ p ∈ s.dirty, p ∈ dirtyBefore)
    (hu : ∀ p ∈ s.untracked, p ∈ before) : settle before dirtyBefore s = ⟨[], []⟩ := by
  simp [settle]
  exact ⟨hd, hu⟩

theorem settle_idempotent (before dirtyBefore : List String) (s : St) :
    settle before dirtyBefore ((settle before dirtyBefore s).run s) = ⟨[], []⟩ :=
  settle_committed before dirtyBefore _ (settle_dirty_before before dirtyBefore s) (settle_untracked_before before dirtyBefore s)

/-! ## The kept hunks of one file: HEAD with exactly the kept hunks applied -/

/-- One `-U0` hunk of the polish edits against HEAD: `target` HEAD lines come before it (the old start, minus one unless
the hunk only inserts), it replaces `oldLen` HEAD lines with `new`, and `keep` says whether the hunk stays. -/
structure WHunk where
  target : Nat
  oldLen : Nat
  new : List String
  keep : Bool
deriving Repr, DecidableEq

/-- The text of the file as lines: walk the hunks in ascending order over the HEAD lines `rest` (`done` already consumed);
a kept hunk emits its new lines, a restored hunk emits the HEAD lines it covers. No hunk is ever reverse-applied alone, so
a restored hunk cannot land at a shifted line. -/
def walk : List String → Nat → List WHunk → List String
  | rest, _, [] => rest
  | rest, done, h :: hs =>
    let skip := h.target - done
    rest.take skip ++ (if h.keep then h.new else (rest.drop skip).take h.oldLen)
      ++ walk ((rest.drop skip).drop h.oldLen) (done + skip + h.oldLen) hs

theorem walk_nil (rest : List String) (done : Nat) : walk rest done [] = rest := rfl

/-- With every hunk restored the walk gives back HEAD. -/
theorem walk_restored (hs : List WHunk) (hk : ∀ h ∈ hs, h.keep = false) :
    ∀ (rest : List String) (done : Nat), walk rest done hs = rest := by
  induction hs with
  | nil => intro rest done; rfl
  | cons h hs ih =>
    intro rest done
    have h0 : h.keep = false := hk h (by simp)
    have := ih (fun x hx => hk x (by simp [hx])) ((rest.drop (h.target - done)).drop h.oldLen)
      (done + (h.target - done) + h.oldLen)
    simp only [walk, h0, Bool.false_eq_true, ↓reduceIte, this]
    rw [List.append_assoc, List.take_append_drop, List.take_append_drop]

/-- A kept hunk emits its new lines between the HEAD lines before it and the walk of the rest. -/
theorem walk_keep (rest : List String) (done : Nat) (h : WHunk) (hs : List WHunk) (hk : h.keep = true) :
    walk rest done (h :: hs) = rest.take (h.target - done) ++ h.new
      ++ walk ((rest.drop (h.target - done)).drop h.oldLen) (done + (h.target - done) + h.oldLen) hs := by
  simp [walk, hk]

/-- A restored hunk emits the HEAD lines it covers, unchanged. -/
theorem walk_restore (rest : List String) (done : Nat) (h : WHunk) (hs : List WHunk) (hk : h.keep = false) :
    walk rest done (h :: hs) = rest.take (h.target - done) ++ (rest.drop (h.target - done)).take h.oldLen
      ++ walk ((rest.drop (h.target - done)).drop h.oldLen) (done + (h.target - done) + h.oldLen) hs := by
  simp [walk, hk]

/-- A restored hunk in ascending order is as if it were not there: the result is HEAD with only the kept hunks applied. -/
theorem walk_skip_restored (rest : List String) (done : Nat) (h h2 : WHunk) (hs : List WHunk) (hk : h.keep = false)
    (o1 : done ≤ h.target) (o2 : h.target + h.oldLen ≤ h2.target) :
    walk rest done (h :: h2 :: hs) = walk rest done (h2 :: hs) := by
  simp only [walk, hk, Bool.false_eq_true, ↓reduceIte]
  have e : h2.target - done = (h.target - done) + h.oldLen + (h2.target - (done + (h.target - done) + h.oldLen)) := by omega
  have e1 : done + (h.target - done) + h.oldLen + (h2.target - (done + (h.target - done) + h.oldLen)) = h2.target := by omega
  generalize h.target - done = a at *
  generalize h.oldLen = n at *
  generalize h2.target - (done + a + n) = b at *
  rw [e]
  simp only [List.drop_drop, List.take_add, List.append_assoc, e1]
  have e2 : h2.target = done + (a + n + b) := by omega
  rw [e2]

/-! ## Goldens: the three 10-22 over-cuts -/

def supWire : Cut := ⟨"docs/team/handoffs/sup-wire.md",
  "`Fw.Wire.Sup.Golden.gen` (cases take the token as a parameter, so fwcore builds no start-time constant); `--check`",
  "`Fw.Wire.Sup.Golden.gen` ; `--check`"⟩

def waiter : Cut := ⟨"research/notes/2026/10-2x-preview-502-flake.md",
  "waiter's, not the run's. Not investigated.)", "waiter's.)"⟩

def jevCounts : Cut := ⟨"docs/team/handoffs/jev-datasets.md",
  "Round 2 (branch merged with main at b2d4dff0; ledger commit ecdc0787; counts.json 2026-10-22T00:57:38+07:00). Counts (rows / labelled / held out):",
  "Counts (counts.json) (rows / labelled / held out):"⟩

#guard (judge [] supWire.old supWire).name = "dropsFacts"
#guard (judge [] waiter.old waiter).name = "dropsFacts"
#guard (missing jevCounts.old jevCounts.new).take 3 = ["2", "4", "0"]
#guard ["b2d4dff0", "ecdc0787"].all (missing jevCounts.old jevCounts.new).contains
#guard (judge [] jevCounts.old jevCounts).name = "dropsFacts"

#guard facts "see lean/Fw/X.lean:12-30, run 39125771186 at 0eeff67b (MEASURED)." =
  ["12", "30", "39125771186", "0", "67", "lean/Fw/X.lean:12-30", "0eeff67b", "MEASURED"]
#guard cutSafe "MEASURED: 82 of 111 frames, see a.md:4." "82 of 111 frames (MEASURED, a.md:4)"
#guard !cutSafe "INFERRED from 3 runs" "from 3 runs"
#guard !isCommit "defaced" && !isCommit "1234567" && isCommit "02cd5f37"
#guard occ "ab" "abab" = 2 && occ "aa" "aaa" = 2 && occ "" "x" = 0

#guard classify [] "lean/scripts/check.sh" = .shell && mark "lean/scripts/check.sh" = some "#"
#guard classify [".github/workflows/device-replay.yml"] ".github/workflows/device-replay.yml" = .skip
#guard classify [] ".github/workflows/device-replay.yml" = .code
#guard classify (genOf [] [("lean/Fw/Ops/LakeJobsGen.lean", "-- GENERATED by node scripts/ci-paths.mjs --write")])
  "lean/Fw/Ops/LakeJobsGen.lean" = .skip
#guard !stamped "-- generated constants have no entry"
#guard classify [] "snapshot/www.fastwork.co/index.html" = .skip
#guard classify [] "packages/contracts/golden/plan/polish.jsonl" = .skip
#guard classify [] "apps/site/src/breakpoints.gen.json" = .skip
#guard classify [] "apps/runner/test/fixtures/gh-status/a.ts" = .skip
#guard classify [] "pnpm-lock.yaml" = .skip
#guard classify [] "apps/runner/src/fw.ts" = .code && mark "lean/Fw/Plan/Polish.lean" = some "--"
#guard classify [] "docs/team/handoffs/x.md" = .prose && classify [] "docs/team/work-graph.json" = .prose
#guard classify [] "apps/site/public/logo.svg" = .skip && classify [] "scripts/hooks/pre-commit" = .skip
#guard stages [] ["a.md", "b.ts"] = [.comments, .prose] && stages [] ["x.sh"] = [.comments]
#guard stages [] ["snapshot/a.md", "lean/golden/x.json"] = []
#guard keeps [] ["a.ts"] "a.ts" && !keeps [] ["a.ts"] "b.ts" && !keeps ["a.ts"] ["a.ts"] "a.ts"
#guard judge [] "x" ⟨"docs/team/work-graph.json", "x", "\"y"⟩ = .breaksJson
#guard judge [] "x a x" ⟨"a.md", "x", ""⟩ = .notUnique && judge [] "a" ⟨"a.md", "b", ""⟩ = .notFound
#guard judge [] "a" ⟨"a.ts", "a", ""⟩ = .notProse
#guard applyAll [] "one two three" [⟨"a.md", "two ", ""⟩, ⟨"a.md", "two", "2"⟩] = ("one three", [.apply, .notFound])

#guard !admitted [⟨60, 2⟩] ⟨62, 59⟩
#guard admitted [⟨10, 2⟩] ⟨12, 1⟩ && admitted [⟨10, 2⟩] ⟨14, 1⟩ && !admitted [⟨10, 2⟩] ⟨15, 1⟩
#guard !admitted [⟨10, 2⟩] ⟨60, 2⟩ && !admitted [] ⟨1, 1⟩ && admitted [⟨10, 2⟩] ⟨7, 1⟩ && !admitted [⟨10, 2⟩] ⟨6, 1⟩
#guard (Span.mk 10 0).hi = 10 && (Span.mk 10 3).hi = 12 && (Span.mk 1 2).reach = (1, 5)
#guard relOk "lean/a.lean" && relOk "a/../b" && !relOk "../a" && !relOk "/etc/x" && !relOk "a/../../b" && !relOk ""
#guard blocked ["a", "b", "a"] ["a", "c"] = ["a"] && blocked [] ["a"] = []

#guard (settle ["keep.txt"] [] ⟨["a.ts", "b.ts"], ["keep.txt", "a.ts-e", "x.orig"]⟩) = ⟨["a.ts", "b.ts"], ["a.ts-e", "x.orig"]⟩
#guard (settle ["k"] [] ⟨[], ["k"]⟩) = ⟨[], []⟩ && ((settle ["k"] [] ⟨["a"], ["k", "z"]⟩).run ⟨["a"], ["k", "z"]⟩) = ⟨[], ["k"]⟩
#guard (settle [] ["mine.ts"] ⟨["a.ts", "mine.ts"], []⟩) = ⟨["a.ts"], []⟩

-- the Trajectory case: a kept deletion above, a 3-line deletion below that is restored (HEAD lines a..j)
private def head10 : List String := ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]
#guard walk head10 0 [⟨1, 1, [], true⟩, ⟨6, 3, [], false⟩] = ["a", "c", "d", "e", "f", "g", "h", "i", "j"]
#guard walk head10 0 [⟨1, 1, ["B"], true⟩, ⟨6, 3, [], true⟩] = ["a", "B", "c", "d", "e", "f", "j"]
#guard walk head10 0 [⟨3, 0, ["x"], true⟩] = ["a", "b", "c", "x", "d", "e", "f", "g", "h", "i", "j"]
#guard walk head10 0 [⟨1, 1, ["B"], false⟩, ⟨8, 2, ["Y"], true⟩] = ["a", "b", "c", "d", "e", "f", "g", "h", "Y"]

end Fw.Plan.Polish
