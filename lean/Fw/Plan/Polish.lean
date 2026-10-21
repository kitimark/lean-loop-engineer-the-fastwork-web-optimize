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

def genName (p : String) : Bool := ((baseName p).splitOn ".gen.").length > 1

/-- `gen`: the paths a generator writes or compares (`fw polish` collects them). -/
def skipped (gen : List String) (p : String) : Bool :=
  gen.contains p || skipRoots.any (fun r => p.startsWith r) || (segs p).any skipSegs.contains || genName p ||
    lockNames.contains (baseName p) || p.startsWith "/" || p.isEmpty

/-- A generator's stamp on the first line of a file it writes. -/
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

theorem skipped_skip (gen : List String) (p : String) (h : skipped gen p = true) : classify gen p = .skip := by
  simp [classify, h]

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

end Fw.Plan.Polish
