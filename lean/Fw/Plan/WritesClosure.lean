import Lean.Data.Json
import Fw.Console.Land
import Fw.Obs.Timing

namespace Fw.Plan.WritesClosure
open Fw.Ops.PathCheck Fw.Console.Land

inductive Kind | module | workflow | other
deriving DecidableEq, Repr

def Kind.name : Kind → String
  | .module => "module" | .workflow => "workflow" | .other => "other"

def lastSeg (w : String) : String := ((w.splitOn "/").getLast?).getD ""

def wild (s : String) : Bool := s == "*" || s == "**"

def leanFile (w : String) : Bool := (lastSeg w).endsWith ".lean" || wild (lastSeg w)

def ymlFile (w : String) : Bool :=
  (lastSeg w).endsWith ".yml" || (lastSeg w).endsWith ".yaml" || wild (lastSeg w)

def kindOf (w : String) : Kind :=
  if w.startsWith "lean/Fw/" && leanFile w then .module
  else if w.startsWith ".github/workflows/" && ymlFile w then .workflow
  else .other

def checkSh : String := "lean/scripts/check.sh"
def triggerLean : String := "lean/Fw/Ci/Trigger.lean"
def triggersGolden : String := "packages/contracts/golden/ci/triggers.jsonl"
def fwRoot : String := "lean/Fw.lean"

def triggerFix : List String := [triggerLean, triggersGolden]

def wfTables : List String :=
  triggerFix ++ ["lean/Fw/Ci/Intent.lean", "packages/contracts/golden/ci/intent.jsonl", "lean/Fw/Ci/Overflow.lean"]

def implied : Kind → List String
  | .module => [fwRoot]
  | .workflow => wfTables
  | .other => []

inductive Fresh | new | existing | «open»
deriving DecidableEq, Repr

def Fresh.name : Fresh → String
  | .new => "new" | .existing => "existing" | .open => "open"

def isGlob (w : String) : Bool := w.toList.contains '*'

def freshOf (tracked : List String) (w : String) : Fresh :=
  if tracked.any (inScope (parseScope [w])) then (if isGlob w then .open else .existing) else .new

def needs (tracked writes : List String) (f : Fresh) : List String :=
  ((writes.filter (freshOf tracked · == f)).flatMap (implied ∘ kindOf)).eraseDups

structure Gap where
  script : String
  path : String
deriving Repr, DecidableEq

def names (writes : List String) (p : String) : Bool := inScope (parseScope writes) p

def owned (writes : List String) (gaps : List Gap) : List Gap :=
  gaps.filter fun g => names writes g.path || names writes g.script

def readNeeds (writes : List String) (gaps : List Gap) : List String :=
  if (owned writes gaps).isEmpty then [] else triggerFix

def required (tracked writes : List String) (gaps : List Gap) : List String :=
  (needs tracked writes .new ++ readNeeds writes gaps).eraseDups

def mayNeed (tracked writes : List String) (gaps : List Gap) : List String :=
  (needs tracked writes .open).filter (!(required tracked writes gaps).contains ·)

structure Task where
  id : String
  owner : String
  stream : String
  writes : List String
  done : Bool
deriving Repr

def scopeOf (t : Task) : List String := landScope t.writes [t.id, t.owner] [] t.id t.stream

def missing (tracked : List String) (gaps : List Gap) (t : Task) : List String :=
  if t.done then [] else violations (scopeOf t) (required tracked t.writes gaps)

def missingOpen (tracked : List String) (gaps : List Gap) (t : Task) : List String :=
  if t.done then [] else violations (scopeOf t) (mayNeed tracked t.writes gaps)

def source (tracked writes : List String) (gaps : List Gap) (f : Fresh) (p : String) : String :=
  match (writes.filter (freshOf tracked · == f)).find? fun w => (implied (kindOf w)).contains p with
  | some w => w
  | none => if f == .new then ((owned writes gaps).head?.map fun g => "../" ++ g.path ++ " in " ++ g.script).getD ""
      else ""

structure Finding where
  task : String
  code : String
  severity : String
  detail : String
deriving Repr, DecidableEq

def findings (tracked : List String) (gaps : List Gap) (t : Task) : List Finding :=
  (missing tracked gaps t).map (fun p =>
      ⟨t.id, "writesClosure", "error", p ++ " for " ++ source tracked t.writes gaps .new p⟩) ++
    (missingOpen tracked gaps t).map (fun p =>
      ⟨t.id, "writesClosureOpen", "warn", p ++ " for " ++ source tracked t.writes gaps .open p⟩)

theorem kindOf_module_iff (w : String) :
    kindOf w = .module ↔ w.startsWith "lean/Fw/" = true ∧ leanFile w = true := by
  unfold kindOf; repeat' split
  all_goals simp_all

theorem kindOf_workflow_iff (w : String) :
    kindOf w = .workflow ↔ (w.startsWith "lean/Fw/" && leanFile w) = false ∧
      w.startsWith ".github/workflows/" = true ∧ ymlFile w = true := by
  unfold kindOf; repeat' split
  all_goals simp_all

theorem implied_eq_nil_iff (k : Kind) : implied k = [] ↔ k = .other := by
  cases k <;> simp [implied, wfTables, triggerFix]

theorem implied_module : implied .module = [fwRoot] := rfl

theorem implied_workflow : implied .workflow = wfTables := rfl

theorem freshOf_new_iff (tr : List String) (w : String) :
    freshOf tr w = .new ↔ ∀ f ∈ tr, inScope (parseScope [w]) f = false := by
  unfold freshOf; repeat' split
  all_goals simp_all

theorem freshOf_existing_iff (tr : List String) (w : String) :
    freshOf tr w = .existing ↔ (∃ f ∈ tr, inScope (parseScope [w]) f = true) ∧ isGlob w = false := by
  unfold freshOf; repeat' split
  all_goals simp_all

theorem freshOf_open_iff (tr : List String) (w : String) :
    freshOf tr w = .open ↔ (∃ f ∈ tr, inScope (parseScope [w]) f = true) ∧ isGlob w = true := by
  unfold freshOf; repeat' split
  all_goals simp_all

theorem mem_needs (tr ws : List String) (f : Fresh) (p : String) :
    p ∈ needs tr ws f ↔ ∃ w ∈ ws, freshOf tr w = f ∧ p ∈ implied (kindOf w) := by
  simp [needs, List.mem_eraseDups, and_assoc]

theorem mem_owned (ws : List String) (gs : List Gap) (g : Gap) :
    g ∈ owned ws gs ↔ g ∈ gs ∧ (names ws g.path = true ∨ names ws g.script = true) := by
  simp [owned]

theorem mem_readNeeds (ws : List String) (gs : List Gap) (p : String) :
    p ∈ readNeeds ws gs ↔ owned ws gs ≠ [] ∧ p ∈ triggerFix := by
  unfold readNeeds; split <;> simp_all [List.isEmpty_iff]

theorem mem_required (tr ws : List String) (gs : List Gap) (p : String) :
    p ∈ required tr ws gs ↔
      (∃ w ∈ ws, freshOf tr w = .new ∧ p ∈ implied (kindOf w)) ∨ (owned ws gs ≠ [] ∧ p ∈ triggerFix) := by
  simp only [required, List.mem_eraseDups, List.mem_append, mem_needs, mem_readNeeds]

theorem mem_required_no_gaps (tr ws : List String) (p : String) :
    p ∈ required tr ws [] ↔ ∃ w ∈ ws, freshOf tr w = .new ∧ p ∈ implied (kindOf w) := by
  rw [mem_required]; simp [owned]

theorem trigger_required_iff (tr ws : List String) (gs : List Gap) :
    triggerLean ∈ required tr ws gs ↔
      (∃ w ∈ ws, freshOf tr w = .new ∧ kindOf w = .workflow) ∨ owned ws gs ≠ [] := by
  rw [mem_required]
  constructor
  · rintro (⟨w, hw, hn, hp⟩ | ⟨h, _⟩)
    · refine .inl ⟨w, hw, hn, ?_⟩
      cases hk : kindOf w <;> simp_all [implied, fwRoot, triggerLean]
    · exact .inr h
  · rintro (⟨w, hw, hn, hk⟩ | h)
    · exact .inl ⟨w, hw, hn, by simp [hk, implied, wfTables, triggerFix]⟩
    · exact .inr ⟨h, by simp [triggerFix]⟩

theorem trigger_only_by_read (tr ws : List String) (gs : List Gap)
    (hw : ∀ w ∈ ws, freshOf tr w = .new → kindOf w ≠ .workflow) :
    triggerLean ∈ required tr ws gs ↔ ∃ g ∈ gs, names ws g.path = true ∨ names ws g.script = true := by
  rw [trigger_required_iff]
  constructor
  · rintro (⟨w, h1, h2, h3⟩ | h)
    · exact absurd h3 (hw w h1 h2)
    · obtain ⟨g, hg⟩ := List.exists_mem_of_ne_nil _ h
      exact ⟨g, ((mem_owned ws gs g).mp hg).1, ((mem_owned ws gs g).mp hg).2⟩
  · rintro ⟨g, hg, hn⟩
    exact .inr (List.ne_nil_of_mem ((mem_owned ws gs g).mpr ⟨hg, hn⟩))

theorem required_eq_nil_iff (tr ws : List String) (gs : List Gap) :
    required tr ws gs = [] ↔ (∀ w ∈ ws, freshOf tr w = .new → kindOf w = .other) ∧ owned ws gs = [] := by
  constructor
  · intro h
    refine ⟨fun w hw hn => ?_, ?_⟩
    · rw [← implied_eq_nil_iff]
      refine List.eq_nil_iff_forall_not_mem.mpr fun p hp => ?_
      have := (mem_required tr ws gs p).mpr (.inl ⟨w, hw, hn, hp⟩)
      simp [h] at this
    · refine Classical.byContradiction fun ho => ?_
      have := (mem_required tr ws gs triggerLean).mpr (.inr ⟨ho, by simp [triggerFix]⟩)
      simp [h] at this
  · rintro ⟨h, ho⟩
    refine List.eq_nil_iff_forall_not_mem.mpr fun p hp => ?_
    rcases (mem_required tr ws gs p).mp hp with ⟨w, hw, hn, hp⟩ | ⟨hne, _⟩
    · simp [(implied_eq_nil_iff _).mpr (h w hw hn)] at hp
    · exact hne ho

theorem required_of_new (tr ws : List String) (gs : List Gap) (w : String) (hw : w ∈ ws)
    (hn : freshOf tr w = .new) : ∀ p ∈ implied (kindOf w), p ∈ required tr ws gs :=
  fun p hp => (mem_required tr ws gs p).mpr (.inl ⟨w, hw, hn, hp⟩)

theorem required_module (tr ws : List String) (gs : List Gap) (w : String) (hw : w ∈ ws)
    (hn : freshOf tr w = .new) (hk : kindOf w = .module) : fwRoot ∈ required tr ws gs := by
  have := required_of_new tr ws gs w hw hn; rw [hk] at this; exact this _ (by simp [implied])

theorem required_workflow (tr ws : List String) (gs : List Gap) (w : String) (hw : w ∈ ws)
    (hn : freshOf tr w = .new) (hk : kindOf w = .workflow) : ∀ p ∈ wfTables, p ∈ required tr ws gs := by
  have := required_of_new tr ws gs w hw hn; rw [hk] at this; exact this

theorem required_of_gap (tr ws : List String) (gs : List Gap) (g : Gap) (hg : g ∈ gs)
    (hn : names ws g.path = true ∨ names ws g.script = true) : ∀ p ∈ triggerFix, p ∈ required tr ws gs :=
  fun p hp => (mem_required tr ws gs p).mpr
    (.inr ⟨List.ne_nil_of_mem ((mem_owned ws gs g).mpr ⟨hg, hn⟩), hp⟩)

theorem mem_mayNeed (tr ws : List String) (gs : List Gap) (p : String) :
    p ∈ mayNeed tr ws gs ↔ (∃ w ∈ ws, freshOf tr w = .open ∧ p ∈ implied (kindOf w)) ∧ p ∉ required tr ws gs := by
  simp [mayNeed, mem_needs]

theorem mem_missing_iff (tr : List String) (gs : List Gap) (t : Task) (hd : t.done = false) (p : String) :
    p ∈ missing tr gs t ↔ p ∈ required tr t.writes gs ∧ inScope (parseScope (scopeOf t)) p = false := by
  simp [missing, hd, mem_violations]

theorem mem_missingOpen_iff (tr : List String) (gs : List Gap) (t : Task) (hd : t.done = false) (p : String) :
    p ∈ missingOpen tr gs t ↔ p ∈ mayNeed tr t.writes gs ∧ inScope (parseScope (scopeOf t)) p = false := by
  simp [missingOpen, hd, mem_violations]

theorem missing_nil_iff_land_ok (tr : List String) (gs : List Gap) (t : Task) (hd : t.done = false)
    (hw : t.writes ≠ []) :
    missing tr gs t = [] ↔
      landVerdict t.writes [t.id, t.owner] [] (required tr t.writes gs) t.id t.stream = .ok := by
  cases hv : violations (scopeOf t) (required tr t.writes gs) <;>
    simp_all [landVerdict, missing, scopeOf, List.isEmpty_iff]

theorem missing_refused (tr : List String) (gs : List Gap) (t : Task) (hd : t.done = false) (p : String)
    (h : p ∈ missing tr gs t) : p ∈ violations (scopeOf t) [p] := by
  rw [mem_violations]; exact ⟨by simp, ((mem_missing_iff tr gs t hd p).mp h).2⟩

theorem one_call (tr : List String) (gs : List Gap) (t : Task) (hd : t.done = false) :
    violations (scopeOf t) (required tr t.writes gs ++ mayNeed tr t.writes gs) =
      missing tr gs t ++ missingOpen tr gs t := by
  simp [violations, missing, missingOpen, hd, List.filter_append]

theorem done_silent (tr : List String) (gs : List Gap) (t : Task) (hd : t.done = true) :
    findings tr gs t = [] := by
  simp [findings, missing, missingOpen, hd]

theorem error_iff (tr : List String) (gs : List Gap) (t : Task) :
    (∃ f ∈ findings tr gs t, f.severity = "error") ↔ missing tr gs t ≠ [] := by
  constructor
  · rintro ⟨f, hf, hs⟩
    simp only [findings, List.mem_append, List.mem_map] at hf
    rcases hf with ⟨p, hp, rfl⟩ | ⟨p, _, rfl⟩
    · exact List.ne_nil_of_mem hp
    · simp at hs
  · intro h
    obtain ⟨p, hp⟩ := List.exists_mem_of_ne_nil _ h
    exact ⟨_, List.mem_append_left _ (List.mem_map_of_mem hp), rfl⟩

def jsSpace (c : Char) : Bool :=
  ['\t', '\n', '\x0b', '\x0c', '\r', ' ', '\u00a0', '\u1680', '\u2028', '\u2029', '\u202f', '\u205f', '\u3000', '\uFEFF'].contains c ||
    ('\u2000' ≤ c && c ≤ '\u200a')

def readStop (c : Char) : Bool := jsSpace c || ['\'', '"', '`', ';', ')', '|', '&', '<', '>'].contains c

def literalRead (s : List Char) : Option String :=
  if s.isEmpty || s.any (fun c => "$*?{}".contains c) then none else some (String.ofList s)

theorem readStop_dot : readStop '.' = false := by decide

theorem readStop_slash : readStop '/' = false := by decide

def readsFrom : Bool → List Char → List (Option String)
  | true, '.' :: '.' :: '/' :: r => literalRead (r.takeWhile (!readStop ·)) :: readsFrom false (r.dropWhile (!readStop ·))
  | _, '/' :: '.' :: '.' :: '/' :: r => none :: readsFrom false (r.dropWhile (!readStop ·))
  | _, c :: r => readsFrom (readStop c) r
  | _, [] => []
termination_by _ s => s.length
decreasing_by
  all_goals simp_wf
  all_goals first
    | omega
    | (have := (List.dropWhile_suffix (p := fun c => !readStop c) (l := r)).length_le; omega)

def readsOf (s : List Char) : List (Option String) := readsFrom true s

def dotdotSeg : List Char := ['/', '.', '.', '/']

theorem readsFrom_seg (b : Bool) (r : List Char) :
    readsFrom b ('/' :: '.' :: '.' :: '/' :: r) = none :: readsFrom false (r.dropWhile (!readStop ·)) := by
  cases b <;> rw [readsFrom]

theorem readsFrom_start (r : List Char) :
    readsFrom true ('.' :: '.' :: '/' :: r) =
      literalRead (r.takeWhile (!readStop ·)) :: readsFrom false (r.dropWhile (!readStop ·)) := by
  rw [readsFrom]

theorem readsFrom_cons (b : Bool) (c : Char) (r : List Char) (h1 : ¬(b = true ∧ ['.', '.', '/'] <+: c :: r))
    (h2 : ¬dotdotSeg <+: c :: r) : readsFrom b (c :: r) = readsFrom (readStop c) r := by
  rw [readsFrom.eq_def]
  split
  next _ _ _ he => exact absurd ⟨rfl, _, he.symm⟩ h1
  next _ _ _ _ he => exact absurd ⟨_, he.symm⟩ h2
  next _ _ _ _ _ _ _ he => obtain ⟨rfl, rfl⟩ := List.cons.inj he; rfl
  next _ _ _ he => simp at he

theorem dropWhile_word (t : List Char) (h : ∀ c ∈ t, readStop c = false) : t.dropWhile (!readStop ·) = [] := by
  induction t with
  | nil => rfl
  | cons c r ih => simp [h c List.mem_cons_self, ih fun d hd => h d (List.mem_cons_of_mem c hd)]

theorem readsFrom_word (w : List Char) (hw : ∀ c ∈ w, readStop c = false) :
    readsFrom false w = if dotdotSeg <:+: w then [none] else [] := by
  induction w using List.rec with
  | nil => simp [readsFrom, dotdotSeg]
  | cons c r ih =>
    have hr : ∀ c ∈ r, readStop c = false := fun d hd => hw d (List.mem_cons_of_mem c hd)
    by_cases hs : dotdotSeg <+: c :: r
    · obtain ⟨t, ht⟩ := hs
      simp only [dotdotSeg, List.cons_append, List.nil_append] at ht
      obtain ⟨rfl, rfl⟩ := List.cons.inj ht
      rw [readsFrom_seg, dropWhile_word t fun d hd => hw d (by simp [hd]), readsFrom]
      simp [show dotdotSeg <:+: '/' :: '.' :: '.' :: '/' :: t from ⟨[], t, rfl⟩]
    · simp only [List.infix_cons_iff, hs, false_or]
      rw [← ih hr, readsFrom_cons false c r (by simp) hs, hw c List.mem_cons_self]

theorem readsFrom_true_eq (w : List Char) (h : w.head? ≠ some '.') : readsFrom true w = readsFrom false w := by
  cases w with
  | nil => rw [readsFrom, readsFrom]
  | cons c r =>
    by_cases hs : dotdotSeg <+: c :: r
    · obtain ⟨t, ht⟩ := hs
      simp only [dotdotSeg, List.cons_append, List.nil_append] at ht
      rw [← ht, readsFrom_seg, readsFrom_seg]
    · have hc : ¬['.', '.', '/'] <+: c :: r := fun ⟨_, ht⟩ => h (by simp [← ht])
      rw [readsFrom_cons true c r (by simp [hc]) hs, readsFrom_cons false c r (by simp) hs]

theorem readsOf_mid_dotdot (x y : List Char) (hx : ∀ c ∈ x, readStop c = false) (hy : ∀ c ∈ y, readStop c = false)
    (h : x.head? ≠ some '.') : readsOf (x ++ dotdotSeg ++ y) = [none] := by
  have hd : (x ++ dotdotSeg ++ y).head? ≠ some '.' := by cases x <;> simp_all [dotdotSeg]
  have hw : ∀ c ∈ x ++ dotdotSeg ++ y, readStop c = false := by
    intro c hc
    simp only [List.mem_append] at hc
    rcases hc with (hc | hc) | hc
    · exact hx c hc
    · simp only [dotdotSeg, List.mem_cons, List.not_mem_nil, or_false] at hc
      rcases hc with rfl | rfl | rfl | rfl <;> simp only [readStop_dot, readStop_slash]
    · exact hy c hc
  rw [readsOf, readsFrom_true_eq _ hd, readsFrom_word _ hw]
  simp

def normRead (p : String) : String := "/".intercalate (Fw.Ops.PathCheck.segs p)

def readPath (p : String) : Option String :=
  if (Fw.Ops.PathCheck.segs p).contains ".." then none else some (normRead p)

theorem readPath_dotdot (p : String) (h : ".." ∈ Fw.Ops.PathCheck.segs p) : readPath p = none := by
  simp [readPath, h]

theorem readPath_plain (p : String) (h : ".." ∉ Fw.Ops.PathCheck.segs p) : readPath p = some (normRead p) := by
  simp [readPath, h]

def ghGlob : List Char → List Char → Bool
  | '*' :: '*' :: '/' :: g, s =>
      ghGlob g s || (List.range s.length).any fun i => s[i]? == some '/' && ghGlob g (s.drop (i + 1))
  | '*' :: '*' :: g, s => (List.range (s.length + 1)).any fun i => ghGlob g (s.drop i)
  | '*' :: g, s => (List.range (s.length + 1)).any fun i => !(s.take i).contains '/' && ghGlob g (s.drop i)
  | [], s => s.isEmpty
  | _ :: _, [] => false
  | c :: g, d :: s => c == d && ghGlob g s

def ghMatches (globs : List String) (p : String) : Bool :=
  globs.foldl (fun hit g => if g.startsWith "!" then hit && !ghGlob (g.toList.drop 1) p.toList
    else hit || ghGlob g.toList p.toList) false

def rowGlobChar (c : Char) : Bool := c.isAlphanum || ['.', '_', '-', '/', '*'].contains c

def globBody : List Char → List Char
  | '!' :: r => r
  | r => r

def rowGlob (g : String) : Bool := !(globBody g.toList).isEmpty && (globBody g.toList).all rowGlobChar

theorem rowGlob_iff (g : String) :
    rowGlob g = true ↔ globBody g.toList ≠ [] ∧ ∀ c ∈ globBody g.toList, rowGlobChar c = true := by
  simp [rowGlob]

theorem rowGlob_empty_refused (g : String) (h : globBody g.toList = []) : rowGlob g = false := by
  simp [rowGlob, h]

theorem rowGlob_char_refused (g : String) (c : Char) (hc : c ∈ globBody g.toList) (hr : rowGlobChar c = false) :
    rowGlob g = false := by
  cases hg : rowGlob g
  · rfl
  · exact absurd ((rowGlob_iff g).mp hg |>.2 c hc) (by simp [hr])

theorem mem_globBody (l : List Char) (c : Char) (h : c ∈ l) : c = '!' ∨ c ∈ globBody l := by
  match l, h with
  | '!' :: r, h => simpa [globBody] using h
  | [], h => simp at h
  | a :: r, h => by_cases ha : a = '!' <;> simp_all [globBody]

theorem rowGlob_meta_refused (g : String) (c : Char) (hc : c ∈ g.toList) (hm : c = '?' ∨ c = '+' ∨ c = '[') :
    rowGlob g = false := by
  rcases mem_globBody _ c hc with rfl | hb
  · rcases hm with h | h | h <;> exact absurd h (by decide)
  · exact rowGlob_char_refused g c hb (by rcases hm with rfl | rfl | rfl <;> decide)

structure Read where
  script : String
  path : Option String
deriving Repr, DecidableEq

def scriptReads (scripts : List (String × String)) : List Read :=
  scripts.flatMap fun (s, text) => (readsOf text.toList).map fun p => ⟨s, p.bind readPath⟩

def unmatched (globs : List String) : Read → Bool
  | ⟨_, none⟩ => true
  | ⟨_, some p⟩ => !ghMatches globs p

def inputGaps (scripts : List (String × String)) (globs : List String) : List Read :=
  (scriptReads scripts).filter (unmatched globs)

def gapsOf (scripts : List (String × String)) (globs : List String) : List Gap :=
  (inputGaps scripts globs).filterMap fun r => r.path.map (Gap.mk r.script)

theorem ghMatches_nil (p : String) : ghMatches [] p = false := rfl

theorem mem_inputGaps (ss : List (String × String)) (gs : List String) (r : Read) :
    r ∈ inputGaps ss gs ↔ r ∈ scriptReads ss ∧ unmatched gs r = true := by
  simp [inputGaps]

theorem nonliteral_gap (ss : List (String × String)) (gs : List String) (s : String)
    (h : ⟨s, none⟩ ∈ scriptReads ss) : ⟨s, none⟩ ∈ inputGaps ss gs :=
  (mem_inputGaps ss gs _).mpr ⟨h, rfl⟩

theorem unmatched_gap (ss : List (String × String)) (gs : List String) (s p : String)
    (h : ⟨s, some p⟩ ∈ scriptReads ss) (hm : ghMatches gs p = false) : ⟨s, some p⟩ ∈ inputGaps ss gs :=
  (mem_inputGaps ss gs _).mpr ⟨h, by simp [unmatched, hm]⟩

theorem matched_no_gap (ss : List (String × String)) (gs : List String) (s p : String)
    (hm : ghMatches gs p = true) : ⟨s, some p⟩ ∉ inputGaps ss gs := by
  rw [mem_inputGaps]; simp [unmatched, hm]

theorem mem_gapsOf (ss : List (String × String)) (gs : List String) (g : Gap) :
    g ∈ gapsOf ss gs ↔ ⟨g.script, some g.path⟩ ∈ scriptReads ss ∧ ghMatches gs g.path = false := by
  simp only [gapsOf, List.mem_filterMap, Option.map_eq_some_iff, mem_inputGaps]
  constructor
  · rintro ⟨⟨s, p⟩, ⟨hr, hu⟩, q, rfl, rfl⟩
    simpa [unmatched] using And.intro hr hu
  · rintro ⟨hr, hm⟩
    exact ⟨_, ⟨hr, by simp [unmatched, hm]⟩, g.path, rfl, rfl⟩

theorem dotdot_gap (ss : List (String × String)) (gs : List String) (s text p : String) (hs : (s, text) ∈ ss)
    (hp : some p ∈ readsOf text.toList) (hd : ".." ∈ Fw.Ops.PathCheck.segs p) : ⟨s, none⟩ ∈ inputGaps ss gs :=
  nonliteral_gap ss gs s (List.mem_flatMap.mpr ⟨(s, text), hs, List.mem_map.mpr ⟨some p, hp, by simp [readPath_dotdot p hd]⟩⟩)

theorem required_of_unmatched_read (tr ws : List String) (ss : List (String × String)) (gs : List String)
    (s p : String) (hr : ⟨s, some p⟩ ∈ scriptReads ss) (hm : ghMatches gs p = false)
    (hn : names ws p = true ∨ names ws s = true) : ∀ q ∈ triggerFix, q ∈ required tr ws (gapsOf ss gs) :=
  required_of_gap tr ws _ ⟨s, p⟩ ((mem_gapsOf ss gs ⟨s, p⟩).mpr ⟨hr, hm⟩) hn

theorem trigger_only_by_unmatched_read (tr ws : List String) (ss : List (String × String)) (gs : List String)
    (hw : ∀ w ∈ ws, freshOf tr w = .new → kindOf w ≠ .workflow) :
    triggerLean ∈ required tr ws (gapsOf ss gs) ↔
      ∃ s p, ⟨s, some p⟩ ∈ scriptReads ss ∧ ghMatches gs p = false ∧ (names ws p = true ∨ names ws s = true) := by
  rw [trigger_only_by_read tr ws _ hw]
  constructor
  · rintro ⟨g, hg, hn⟩
    exact ⟨g.script, g.path, ((mem_gapsOf ss gs g).mp hg).1, ((mem_gapsOf ss gs g).mp hg).2, hn⟩
  · rintro ⟨s, p, hr, hm, hn⟩
    exact ⟨⟨s, p⟩, (mem_gapsOf ss gs ⟨s, p⟩).mpr ⟨hr, hm⟩, hn⟩

#guard readsOf ". ../scripts/span.sh\nx ../a/$b ../ .../c;../d".toList ==
  [some "scripts/span.sh", none, none, some "d"]
#guard readsOf "x/../y".toList == [none] && readsOf "a../b .../c ../..".toList == [some ".."]
#guard readsOf "$R/../x \"/../y\" ../a/../b x/../../c".toList == [none, none, some "a/../b", none]
#guard scriptReads [("s", "cat x/../y")] == [⟨"s", none⟩]
#guard ghMatches ["lean/**"] "lean/a/b.lean" && !ghMatches ["lean/**"] "lean"
#guard !ghMatches ["lean/Fw"] "lean/Fw/X.lean" && ghMatches ["a/**/c.json"] "a/c.json"
#guard ghMatches ["**", "!x/**", "x/y"] "x/y" && !ghMatches ["x/y", "!x/**"] "x/y"
#guard normRead "a//b/./c.json" == "a/b/c.json"
#guard normRead "a/../b" == "a/../b" && readPath "a/../b" == none && readPath "lean/.." == none
#guard readPath "a//./b..c/...x" == some "a/b..c/...x"
#guard inputGaps [("s", "../lean/../x ../../e")] ["**"] == [⟨"s", none⟩, ⟨"s", none⟩]
#guard jsSpace '\u00a0' && jsSpace '\u2005' && jsSpace '\uFEFF' && !jsSpace '\u200b' && !jsSpace 'a'
#guard rowGlob "lean/**" && rowGlob "!lean/Fw/A_b-c.lean" && !rowGlob "" && !rowGlob "!" && !rowGlob "!!a"
#guard !rowGlob "lean/?.lean" && !rowGlob "a+" && !rowGlob "lean/[ab].lean" && !rowGlob "@fwcore"
#guard inputGaps [("s", "../a ../b ../$c")] ["a"] == [⟨"s", some "b"⟩, ⟨"s", none⟩]
#guard gapsOf [("s", "../a ../b ../$c")] ["a"] == [⟨"s", "b"⟩]

def isError (f : Finding) : Bool := f.code == "writesClosure" && f.severity == "error"

def newErrors (before after : List Finding) : List Finding :=
  after.filter fun f => isError f && decide (f ∉ before)

theorem mem_newErrors (b a : List Finding) (f : Finding) :
    f ∈ newErrors b a ↔ f ∈ a ∧ isError f = true ∧ f ∉ b := by
  simp [newErrors]

theorem new_error_refused (b a : List Finding) (f : Finding) (ha : f ∈ a) (he : isError f = true) (hb : f ∉ b) :
    f ∈ newErrors b a := (mem_newErrors b a f).mpr ⟨ha, he, hb⟩

theorem old_error_passes (b a : List Finding) (f : Finding) (hb : f ∈ b) : f ∉ newErrors b a := by
  rw [mem_newErrors]; exact fun h => h.2.2 hb

theorem warning_passes (b a : List Finding) (f : Finding) (hc : f.code = "writesClosureOpen") :
    f ∉ newErrors b a := by
  rw [mem_newErrors]; simp [isError, hc]

theorem newErrors_self (a : List Finding) : newErrors a a = [] := by
  simp [newErrors, List.filter_eq_nil_iff]
  exact fun _ h _ => h

def fontPre : List String :=
  ["packages/measure-chromium/**", "lean/Fw/Measure/Profile.lean", "packages/contracts/golden/measure/**",
    "research/notes/2026/10-2x-counts-font-fidelity.md", "docs/team/handoffs/counts-font-fidelity.md"]

def fontTables : List String :=
  ["apps/runner/src/land.ts", "lean/Fw/Ci/Intent.lean", "lean/Fw/Ci/Overflow.lean", "lean/Fw/Ci/Pool/Caps.lean",
    "lean/Fw/Ci/Trigger.lean", "scripts/ci-paths.test.mjs", "packages/contracts/golden/ci/**",
    "lean/Fw/Ops/LakeJobsGen.lean"]

def fontPost : List String := fontPre ++ [".github/workflows/font-fidelity.yml"] ++ fontTables

def fontTracked : List String :=
  ["lean/Fw/Measure/Profile.lean", "packages/contracts/golden/measure/profile.jsonl", "lean/Fw/Ci/Intent.lean",
    "lean/Fw/Ci/Overflow.lean", "lean/Fw/Ci/Pool/Caps.lean", "lean/Fw/Ci/Trigger.lean",
    "packages/contracts/golden/ci/triggers.jsonl", "lean/Fw/Ops/LakeJobsGen.lean", "lean/Fw/Faithful/Measured.lean"]

def footPre : List String :=
  ["apps/site/scripts/part-footprint.mjs", "apps/site/scripts/part-footprint*.test.mjs",
    "lean/Fw/Parts/FootprintData.lean", "lean/Fw/Parts/FootprintRows.lean",
    "packages/contracts/golden/parts/footprint*.json", "docs/team/handoffs/footprint-classname-operands.md"]

def footR323 : List String :=
  footPre ++ ["apps/site/package.json", "lean/Fw/Parts/ClassPos.lean", "lean/Fw.lean", "lean/scripts/ClassPosGolden.lean",
    "packages/contracts/golden/parts/footprint*.jsonl"]

def footLater : List String :=
  ["lean/scripts/check.sh", "lean/Fw/Ci/Trigger.lean", "packages/contracts/golden/ci/triggers.jsonl"]

def footTracked : List String :=
  ["lean/Fw/Parts/FootprintData.lean", "lean/Fw/Parts/FootprintRows.lean",
    "packages/contracts/golden/parts/footprint.gen.json", "lean/scripts/check.sh", "lean/Fw/Ci/Trigger.lean",
    "packages/contracts/golden/ci/triggers.jsonl", "lean/Fw.lean"]

def morphPre : List String :=
  ["lean/Fw/Measure/WkCost.lean", "lean/scripts/*WkCost*.lean", "packages/contracts/golden/measure/wkcost*.jsonl",
    "packages/measure-webkit/src/lag/morphcost.mjs", "packages/measure-webkit/src/lag/cli.mjs",
    "packages/measure-webkit/test/lag-morphcost.test.mjs", "results/morph-idle-none/**",
    "docs/team/handoffs/morph-cost-sums-golden.md"]

def morphAdded : List String :=
  ["lean/Fw/Ci/Trigger.lean", "packages/contracts/golden/ci/triggers.jsonl", "lean/scripts/check.sh",
    "lean/scripts/WkCostSums.lean"]

def morphTracked : List String :=
  ["lean/Fw/Measure/WkCost.lean", "lean/scripts/WkCostGolden.lean", "packages/contracts/golden/measure/wkcost.jsonl",
    "lean/Fw/Ci/Trigger.lean", "packages/contracts/golden/ci/triggers.jsonl", "lean/scripts/check.sh"]

def probePre : List String :=
  ["lean/Fw/Gate/Trajectory.lean", "lean/scripts/TrajectoryGolden.lean",
    "packages/contracts/golden/gate/trajectory*.jsonl", "packages/gate-breakpoints/src/trajectory/reduce.mjs",
    "packages/gate-breakpoints/src/trajectory/run.mjs", "packages/gate-breakpoints/test/trajectory*.test.mjs",
    "docs/team/handoffs/hero-probe-original.md"]

def probeTracked : List String :=
  ["lean/Fw/Gate/Trajectory.lean", "lean/scripts/TrajectoryGolden.lean", "packages/contracts/golden/gate/trajectory.jsonl"]

def pixPre : List String :=
  ["research/notes/2026/10-2x-hero-exit-threaded-pix.md", "results/hero-exit-threaded-pix/**",
    "docs/team/handoffs/hero-exit-threaded-pix.md"]

def pixAdded : List String :=
  [".github/workflows/path-pix.yml", "lean/Fw/Gate/PathPix.lean", "packages/contracts/golden/gate/path-pix.jsonl",
    "packages/measure-webkit/src/pathpix*.mjs", "packages/measure-webkit/test/pathpix*.test.mjs",
    "packages/measure-chromium/src/pathpix*.mjs", "packages/measure-chromium/test/pathpix*.test.mjs"]

def pixTracked : List String :=
  [".github/workflows/path-pix.yml", "lean/Fw/Gate/PathPix.lean", "packages/contracts/golden/gate/path-pix.jsonl"]

def selfWrites : List String :=
  ["lean/Fw/Plan/WritesClosure.lean", "lean/Fw.lean", "lean/scripts/WritesClosureGolden.lean", "lean/scripts/check.sh",
    "lean/Fw/Ci/Trigger.lean", "packages/contracts/golden/ci/triggers.jsonl",
    "packages/contracts/golden/plan/writes-closure.jsonl", "apps/runner/src/plan*.ts", "apps/runner/test/plan*.test.ts",
    "docs/team/handoffs/graph-writes-closure.md"]

def selfTracked : List String :=
  ["lean/Fw.lean", "lean/scripts/check.sh", "lean/Fw/Ci/Trigger.lean", "packages/contracts/golden/ci/triggers.jsonl",
    "apps/runner/src/plan.ts", "apps/runner/test/plan.test.ts"]

def mk (id owner stream : String) (writes : List String) : Task := ⟨id, owner, stream, writes, false⟩

structure Case where
  name : String
  graph : String
  tree : String
  task : Task
  tracked : List String
  scripts : List (String × String)
  globs : List String
  added : List String

def Case.gaps (c : Case) : List Gap := gapsOf c.scripts c.globs

def classposGap : Gap := ⟨checkSh, "packages/contracts/golden/parts/footprint.classpos.jsonl"⟩

def sumsGap : Gap := ⟨checkSh, "packages/contracts/golden/measure/wkcost-sums.jsonl"⟩

def otherGap : Gap := ⟨checkSh, "packages/x/y.jsonl"⟩

def leanRow : List String :=
  ["lean/**", "scripts/span.sh", "packages/contracts/golden/parts/footprint.gen.json",
    "packages/contracts/golden/measure/wkcost.jsonl"]

def readText (golden : String) : String := ". ../scripts/span.sh\njob golden --check ../" ++ golden ++ "\n"

def classposScripts : List (String × String) := [(checkSh, readText classposGap.path)]

def sumsScripts : List (String × String) := [(checkSh, readText sumsGap.path)]

def otherScripts : List (String × String) := [(checkSh, readText otherGap.path)]

def mainScripts : List (String × String) := [(checkSh, readText "packages/contracts/golden/parts/footprint.gen.json")]

#guard gapsOf mainScripts leanRow == [] && leanRow.all rowGlob
#guard gapsOf classposScripts leanRow == [classposGap]
#guard gapsOf sumsScripts leanRow == [sumsGap]
#guard gapsOf otherScripts leanRow == [otherGap]
#guard gapsOf classposScripts (leanRow ++ [classposGap.path]) == []

def cases : List Case := [
  ⟨"r322 before: counts-font-fidelity", "31bf66d51^", "31bf66d51^",
    mk "counts-font-fidelity" "measure-engineer" "measure" fontPre, fontTracked, mainScripts, leanRow,
    [".github/workflows/font-fidelity.yml"] ++ fontTables⟩,
  ⟨"r322 workflow named, tables not", "31bf66d51^", "31bf66d51^",
    mk "counts-font-fidelity" "measure-engineer" "measure" (fontPre ++ [".github/workflows/font-fidelity.yml"]),
    fontTracked, mainScripts, leanRow, fontTables⟩,
  ⟨"r322 after", "31bf66d51", "31bf66d51", mk "counts-font-fidelity" "measure-engineer" "measure" fontPost,
    fontTracked, mainScripts, leanRow, []⟩,
  ⟨"r323 before: footprint-classname-operands", "132cfa8e1^", "132cfa8e1^",
    mk "footprint-classname-operands" "part-builder" "parts" footPre, footTracked, mainScripts, leanRow,
    footR323.drop footPre.length ++ footLater⟩,
  ⟨"r323 after", "132cfa8e1", "132cfa8e1", mk "footprint-classname-operands" "part-builder" "parts" footR323,
    footTracked, mainScripts, leanRow, footLater⟩,
  ⟨"r325 before", "6d61219e9^", "f4743ef8a",
    mk "footprint-classname-operands" "part-builder" "parts" (footR323 ++ [checkSh]), footTracked, classposScripts, leanRow,
    triggerFix⟩,
  ⟨"r325 after", "6d61219e9", "f4743ef8a",
    mk "footprint-classname-operands" "part-builder" "parts" (footR323 ++ footLater), footTracked, classposScripts, leanRow, []⟩,
  ⟨"r328 before: morph-cost-sums-golden", "890278714^", "890278714^",
    mk "morph-cost-sums-golden" "measure-engineer" "measure" morphPre, morphTracked, mainScripts, leanRow, morphAdded⟩,
  ⟨"r328 build branch", "890278714^", "5599b944d",
    mk "morph-cost-sums-golden" "measure-engineer" "measure" morphPre, morphTracked, sumsScripts, leanRow, morphAdded⟩,
  ⟨"r328 after", "890278714", "5599b944d",
    mk "morph-cost-sums-golden" "measure-engineer" "measure" (morphPre ++ morphAdded), morphTracked, sumsScripts, leanRow, []⟩,
  ⟨"r330 before: counts-font-fidelity", "b3f6f21bd^", "b3f6f21bd^",
    mk "counts-font-fidelity" "measure-engineer" "measure" fontPost, fontTracked, mainScripts, leanRow,
    ["lean/Fw/Faithful/Measured.lean", "results/faithful/**", "packages/measure-chromium/test/faithful.test.mjs"]⟩,
  ⟨"r331 before: hero-probe-original", "1baf5a8a5^", "1baf5a8a5^",
    mk "hero-probe-original" "measure-engineer" "gate" probePre, probeTracked, mainScripts, leanRow, ["docs/team/tools/trajectory-probe.md"]⟩,
  ⟨"r334 before: hero-exit-threaded-pix", "f3248e954^", "f3248e954^",
    mk "hero-exit-threaded-pix" "measure-engineer" "measure" pixPre, [], mainScripts, leanRow, pixAdded⟩,
  ⟨"r334 after", "f3248e954", "f3248e954",
    mk "hero-exit-threaded-pix" "measure-engineer" "measure" (pixPre ++ pixAdded), pixTracked, mainScripts, leanRow, []⟩,
  ⟨"graph-writes-closure", "f3248e954", "f3248e954",
    mk "graph-writes-closure" "lean-prover" "tooling" selfWrites, selfTracked, mainScripts, leanRow, []⟩,
  ⟨"a new module alone", "-", "-", mk "x" "o" "tooling" ["lean/Fw/X/New.lean"], [], [], [], [fwRoot]⟩,
  ⟨"a new workflow alone", "-", "-", mk "x" "o" "tooling" [".github/workflows/new.yml"], [], [], [], wfTables⟩,
  ⟨"a gap in a script the row writes", "-", "-", mk "x" "o" "tooling" [checkSh], [], otherScripts, leanRow, triggerFix⟩,
  ⟨"a gap of another row", "-", "-", mk "x" "o" "tooling" ["apps/runner/src/x.ts"], [], otherScripts, leanRow, []⟩,
  ⟨"no artefact", "-", "-", mk "x" "o" "tooling" ["apps/runner/src/x.ts", "docs/team/tools/x.md"], [], [], [], []⟩,
  ⟨"a done row", "-", "-", { mk "x" "o" "tooling" [".github/workflows/new.yml"] with done := true }, [], [], [], []⟩]

def named (c : Case) : List (String × String) :=
  (findings c.tracked c.gaps c.task).map fun f => (f.code, (f.detail.splitOn " for ").headD "")

def err (p : String) : String × String := ("writesClosure", p)
def warn (p : String) : String × String := ("writesClosureOpen", p)

#guard (cases.map named) == [
  [],
  [err triggerLean, err "lean/Fw/Ci/Intent.lean", err "lean/Fw/Ci/Overflow.lean"],
  [],
  [],
  [],
  [err triggerLean],
  [],
  [],
  [err triggerLean],
  [],
  [],
  [],
  [],
  [],
  [],
  [],
  [err triggerLean, err "lean/Fw/Ci/Intent.lean", err "lean/Fw/Ci/Overflow.lean"],
  [err triggerLean],
  [],
  [],
  []]

#guard cases.all fun c => (named c).all fun (code, p) => code != "writesClosure" || c.added.contains p

def admitted (c : Case) (p : String) : Bool := inScope (parseScope (scopeOf c.task)) p

def covers (c : Case) (table : List String) : Bool :=
  (c.added.filter table.contains).all fun p => admitted c p || (named c).contains (err p)

def newOf (c : Case) (k : Kind) : Bool :=
  c.task.writes.any fun w => freshOf c.tracked w == .new && kindOf w == k

#guard cases.all fun c => c.task.done || !newOf c .workflow || covers c wfTables
#guard cases.all fun c => c.task.done || !newOf c .module || covers c [fwRoot]
#guard cases.all fun c => c.task.done || (owned c.task.writes c.gaps).isEmpty || covers c triggerFix
#guard cases.all fun c => newOf c .workflow || !(named c).contains (err triggerLean) || !(owned c.task.writes c.gaps).isEmpty

#guard kindOf "packages/contracts/golden/parts/footprint*.jsonl" == .other
#guard kindOf "lean/scripts/*WkCost*.lean" == .other
#guard kindOf "lean/scripts/check.sh" == .other
#guard kindOf "lean/Fw/Plan/WritesClosure.lean" == .module
#guard kindOf "lean/Fw/**" == .module
#guard kindOf ".github/workflows/font-fidelity.yml" == .workflow
#guard kindOf "docs/team/tools/trajectory-probe.md" == .other
#guard freshOf ["lean/scripts/WkCostGolden.lean"] "lean/scripts/*WkCost*.lean" == .open
#guard freshOf ["lean/scripts/WkCostGolden.lean"] "lean/scripts/WkCostSums.lean" == .new
#guard freshOf ["lean/Fw/Ci/Trigger.lean"] "lean/Fw/Ci/Trigger.lean" == .existing
#guard freshOf [] "packages/contracts/golden/parts/footprint*.jsonl" == .new
#guard owned ["packages/contracts/golden/parts/footprint*.jsonl"] [classposGap] == [classposGap]
#guard owned [checkSh] [otherGap] == [otherGap]
#guard owned ["packages/contracts/golden/parts/footprint*.json"] [classposGap] == []
#guard required [] ["packages/contracts/golden/measure/new.jsonl"] [] == []

open Lean (Json)

def strs (xs : List String) : Json := .arr (xs.toArray.map Json.str)

def gapJson (g : Gap) : Json := Json.mkObj [("script", g.script), ("path", g.path)]

def readJson (r : Read) : Json := Json.mkObj [("script", r.script), ("path", (r.path.map Json.str).getD .null)]

def scriptsJson (ss : List (String × String)) : Json :=
  .arr (ss.toArray.map fun (s, text) => Json.mkObj [("script", s), ("text", text)])

def findingJson (f : Finding) : Json :=
  Json.mkObj [("task", f.task), ("code", f.code), ("severity", f.severity), ("detail", f.detail)]

def findingsJson (fs : List Finding) : Json := .arr (fs.toArray.map findingJson)

def pathRow (tracked : List String) (w : String) : Json :=
  Json.mkObj [("type", "path"), ("write", w), ("tracked", strs tracked), ("kind", (kindOf w).name),
    ("fresh", (freshOf tracked w).name), ("implied", strs (implied (kindOf w)))]

def caseRow (c : Case) : Json :=
  let t := c.task
  Json.mkObj [("type", "case"), ("name", c.name), ("graph", c.graph), ("tree", c.tree), ("id", t.id),
    ("owner", t.owner), ("stream", t.stream), ("done", t.done), ("writes", strs t.writes), ("tracked", strs c.tracked),
    ("scripts", scriptsJson c.scripts), ("globs", strs c.globs),
    ("gaps", .arr (c.gaps.toArray.map gapJson)), ("owned", .arr ((owned t.writes c.gaps).toArray.map gapJson)),
    ("required", strs (required c.tracked t.writes c.gaps)), ("mayNeed", strs (mayNeed c.tracked t.writes c.gaps)),
    ("violations", strs (missing c.tracked c.gaps t ++ missingOpen c.tracked c.gaps t)),
    ("findings", findingsJson (findings c.tracked c.gaps t)), ("added", strs c.added)]

def globVectors : List (List String × String) := [
  (["lean/**"], "lean/a/b.lean"), (["lean/**"], "lean"), (["lean/Fw"], "lean/Fw/X.lean"), (["lean/Fw"], "lean/Fw"),
  (["a/**/c.json"], "a/c.json"), (["a/**/c.json"], "a/b/d/c.json"), (["a/**/c.json"], "a/b/c.jsonx"),
  (["a/*.json"], "a/b/c.json"), (["a/*.json"], "a/.json"), (["**/c"], "c"), (["**/c"], "x/y/c"), (["a**"], "ab/c"),
  (["**", "!x/**", "x/y"], "x/y"), (["x/y", "!x/**"], "x/y"), (["x/**", "!x/y"], "x/z"), ([], "a"),
  (["packages/contracts/golden/**"], "packages/contracts/golden/ci/triggers.jsonl"), (["scripts/*.sh"], "scripts/a/b.sh"),
  (["lean/*.lean"], "lean/Fw.lean"), (["lean/*.lean"], "lean/Fw/A.lean")]

def globRow (gs : List String) (p : String) : Json :=
  Json.mkObj [("type", "glob"), ("globs", strs gs), ("path", p), ("match", ghMatches gs p)]

def rowGlobVectors : List String :=
  leanRow ++ ["lean/Fw/A_b-c.lean", "!lean/a.lean", "", "!", "!!a", "lean/?.lean", "a+", "lean/[ab].lean", "lean/[!a]",
    "a b", "a{b,c}", "@fwcore", "lean/\u00e9.lean", "lean/a\\b"]

def rowGlobRow (g : String) : Json := Json.mkObj [("type", "rowGlob"), ("glob", g), ("ok", rowGlob g)]

def prefixes (s : String) : List String := (List.range s.length).map fun i => String.ofList (s.toList.take (i + 1))

def agreeGlobs : List String :=
  (["**", "***", "**/", "***/", "*", "**/*"] ++
    ["lean/**/*.lean", "a/***/b", "**/b*.json", "a**/b", "*/**/", "x/*.json"].flatMap prefixes).eraseDups

def agreePaths : List String :=
  ["", "a", "b", "ab", "a/b", "a/x/b", "a/x/y/b", "a/b/c", "ab/b", "a//b", "a/", "/a", ".x", "*", "a*b", "lean",
    "lean/", "lean/a.lean", "lean/Fw/A.lean", "lean/Fw/A/B.lean", "lean/a.leanx", "lean/.lean", "leanx/a.lean",
    "x/lean/a.lean", "b.json", "x/b1.json", "x/y/bc.json", "x/c.json", "x/.json", "a/../b", "lean/../x", "lean/**"]

def agreeLists : List (List String) := agreeGlobs.map ([·]) ++ agreeGlobs.map fun g => ["**", "!" ++ g]

#guard agreeLists.all (·.all rowGlob)

def agreeRow (gs : List String) : Json :=
  Json.mkObj [("type", "agree"), ("globs", strs gs), ("hits", strs (agreePaths.filter (ghMatches gs)))]

def timeWindow : Nat := 30

def syncSample (durMs load : Nat) : Fw.Obs.Timing.Sample :=
  { tool := "fw", step := "plan sync", durMs, host := .«local», load }

def calm (durMs load : Nat) : Bool :=
  !Fw.Obs.Timing.contended { loadMax := Fw.Obs.Timing.calmLoad } (syncSample durMs load)

theorem calm_iff (d l : Nat) : calm d l = true ↔ l ≤ Fw.Obs.Timing.calmLoad := by
  simp only [calm, Fw.Obs.Timing.contended, syncSample]
  by_cases h : Fw.Obs.Timing.calmLoad < l <;> simp [h] <;> omega

def calmDurs (xs : List (Nat × Nat)) : List Nat := (xs.filter fun (d, l) => calm d l).map (·.1)

theorem mem_calmDurs (xs : List (Nat × Nat)) (d : Nat) :
    d ∈ calmDurs xs ↔ ∃ l, (d, l) ∈ xs ∧ l ≤ Fw.Obs.Timing.calmLoad := by
  simp [calmDurs, calm_iff]

theorem contended_not_in_calmDurs (xs : List (Nat × Nat)) (d l : Nat) (h : Fw.Obs.Timing.calmLoad < l)
    (hx : ∀ l', (d, l') ∈ xs → l' = l) : d ∉ calmDurs xs := by
  rw [mem_calmDurs]
  rintro ⟨l', hm, hl⟩
  rw [hx l' hm] at hl
  omega

def timeRow (label : String) (xs : List Nat) : String :=
  s!"| {label} | {xs.length} | {Fw.Obs.Timing.p50 xs} ms | {Fw.Obs.Timing.p90 xs} ms | {Fw.Obs.Timing.maxL xs} ms |\n"

def timeTable (before after : List (Nat × Nat)) : String :=
  let b := Fw.Obs.Timing.lastN timeWindow (calmDurs before)
  let a := calmDurs after
  let d : Int := (Fw.Obs.Timing.p50 a : Int) - Fw.Obs.Timing.p50 b
  let calmN := (calmDurs before).length + a.length
  s!"Calm runs only: load floor at most {Fw.Obs.Timing.calmLoad} (Fw.Obs.Timing.calmLoad); {calmN} of " ++
    s!"{before.length + after.length} samples are calm.\n\n" ++
    "| Window | n | p50 | p90 | max |\n|---|---|---|---|---|\n" ++
    timeRow s!"last {b.length} calm runs before the closure check" b ++ timeRow "every calm run with it" a ++
    s!"\nINFERRED: the closure check adds about {d} ms to a calm sync (p50 with it minus p50 before).\n"

#guard timeTable [(300, 0), (100, 4), (200, 2), (900, 5)] [(650, 1), (600, 3), (4000, 12)] ==
  "Calm runs only: load floor at most 4 (Fw.Obs.Timing.calmLoad); 5 of 7 samples are calm.\n\n" ++
  "| Window | n | p50 | p90 | max |\n|---|---|---|---|---|\n| last 3 calm runs before the closure check | 3 | 200 ms | 300 ms | 300 ms |\n" ++
  "| every calm run with it | 2 | 600 ms | 650 ms | 650 ms |\n\nINFERRED: the closure check adds about 400 ms to a calm sync (p50 with it minus p50 before).\n"

def timeVectors : List (List (Nat × Nat) × List (Nat × Nat)) :=
  [([], []), ([(300, 0), (100, 4), (200, 2), (900, 5)], [(650, 1), (600, 3), (4000, 12)]),
    ((List.range 40).map fun i => (100 + i, i % 7), [(811, 4), (642, 5), (700, 0), (600, 140)]), ([(500, 9), (400, 8)], [(450, 4)])]

def timeTableRow (b a : List (Nat × Nat)) : Json :=
  Json.mkObj [("type", "timeTable"), ("before", Lean.toJson b), ("after", Lean.toJson a), ("text", timeTable b a)]

def timeParamsRow : Json :=
  Json.mkObj [("type", "timeParams"), ("calmLoad", Fw.Obs.Timing.calmLoad), ("window", timeWindow)]

def gapVectors : List (List (String × String) × List String) := [
  ([("lean/scripts/check.sh", "job a x --check ../packages/a.jsonl ../packages/b.jsonl ../lean/Fw/X.lean ../$V\n"),
    ("lean/scripts/other.sh", "node ../packages/c.json\n")], ["lean/**", "packages/a.jsonl"]),
  ([("lean/scripts/check.sh", ". ../scripts/span.sh\nsh -c 'sh ../scripts/fwcore-build.sh && x' ../a/$b ../\n")],
    ["scripts/span.sh", "scripts/*.sh"]),
  ([("lean/scripts/n.sh", "x ../a//b/./c.json .../d.json ../../e ../f*.json ../g{1}\n")], ["a/b/**", "!a/b/c.json"]),
  ([("lean/scripts/w.sh", "x ../a.json\u00a0../b.json\u2003../c.json\x0b../d.json;../e.json|../f.json\n")], ["a.json", "c.json"]),
  ([("lean/scripts/b.sh", "cat x/../y a../b.json .../c.json \"$R/../z\" /../d ../ok.json ../e/../f\n")], ["**"]),
  (classposScripts, leanRow), (sumsScripts, leanRow), (mainScripts, leanRow)]

def gapRow (ss : List (String × String)) (gs : List String) : Json :=
  Json.mkObj [("type", "gaps"), ("scripts", scriptsJson ss), ("globs", strs gs),
    ("reads", .arr ((scriptReads ss).toArray.map readJson)), ("inputGaps", .arr ((inputGaps ss gs).toArray.map readJson)),
    ("gaps", .arr ((gapsOf ss gs).toArray.map gapJson))]

def errAt (task p : String) : Finding := ⟨task, "writesClosure", "error", p ++ " for x"⟩

def warnAt (task p : String) : Finding := ⟨task, "writesClosureOpen", "warn", p ++ " for x"⟩

def syncVectors : List (List Finding × List Finding) := [
  ([], []), ([], [errAt "a" triggerLean]), ([errAt "a" triggerLean], [errAt "a" triggerLean]),
  ([], [warnAt "a" triggerLean]), ([errAt "a" triggerLean], [errAt "a" triggerLean, errAt "b" triggerLean]),
  ([errAt "a" triggerLean], [errAt "a" fwRoot]), ([errAt "a" triggerLean, warnAt "b" fwRoot], []),
  ([], [⟨"a", "evNotOnMain", "error", "x"⟩])]

#guard syncVectors.map (fun (b, a) => (newErrors b a).length) == [0, 1, 0, 0, 1, 1, 0, 0]

def syncRow (b a : List Finding) : Json :=
  Json.mkObj [("type", "sync"), ("before", findingsJson b), ("after", findingsJson a), ("refused", findingsJson (newErrors b a))]

def pathVectors : List (List String × String) := [
  ([], "packages/contracts/golden/plan/writes-closure.jsonl"), ([], "packages/contracts/golden/**"),
  ([], "packages/contracts/golden/ci/triggers.jsonl"), ([], "lean/scripts/X.lean"), ([], "lean/scripts/check.sh"),
  ([], "lean/Fw/A/B.lean"), ([], "lean/Fw/**"), ([], "lean/Fw/A/*"), ([], "lean/Fw/A/b.md"), ([], "lean/FwTestMain.lean"),
  ([], ".github/workflows/a.yml"), ([], ".github/workflows/a.yaml"), ([], ".github/workflows/*"),
  ([], ".github/workflows/a.md"), ([], ".github/scripts/a.mjs"), ([], "!lean/Fw/A.lean"), ([], "docs/team/tools/x.md"),
  (["lean/scripts/WkCostGolden.lean"], "lean/scripts/*WkCost*.lean"),
  (["lean/scripts/WkCostGolden.lean"], "lean/scripts/WkCostSums.lean"),
  (["lean/Fw/Ci/Trigger.lean"], "lean/Fw/Ci/Trigger.lean"), (["lean/Fw/Ci/Trigger.lean"], "lean/Fw/Ci"),
  (["lean/Fw/Ci/Trigger.lean"], "lean/Fw/**"), (["lean/Fw/Ci/Trigger.lean"], "lean/Fw/Ci/T*.lean"),
  (["a/b/c.json"], "a/**/c.json"), (["a/b/c.json"], "a/*/d.json")]

def goldenText (_ : Unit) : String :=
  String.join ((pathVectors.map fun (tr, w) => (pathRow tr w).compress ++ "\n") ++
    (cases.map fun c => (caseRow c).compress ++ "\n") ++ (globVectors.map fun (gs, p) => (globRow gs p).compress ++ "\n") ++
    (rowGlobVectors.map fun g => (rowGlobRow g).compress ++ "\n") ++
    [(Json.mkObj [("type", "agreePaths"), ("paths", strs agreePaths)]).compress ++ "\n"] ++
    (agreeLists.map fun gs => (agreeRow gs).compress ++ "\n") ++
    (timeVectors.map fun (b, a) => (timeTableRow b a).compress ++ "\n") ++
    [timeParamsRow.compress ++ "\n"] ++
    (gapVectors.map fun (ss, gs) => (gapRow ss gs).compress ++ "\n") ++
    syncVectors.map fun (b, a) => (syncRow b a).compress ++ "\n")

def goldenPath : String := "../packages/contracts/golden/plan/writes-closure.jsonl"

def run (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    let cur ← try IO.FS.readFile goldenPath catch _ => pure ""
    if cur != goldenText () then
      IO.println s!"writes-closure golden: {goldenPath} is stale (regenerate: cd lean && lake env lean --run scripts/WritesClosureGolden.lean)"
      return 1
    IO.println s!"writes-closure golden: {cases.length} cases, up to date"
    return 0
  IO.FS.writeFile goldenPath (goldenText ())
  IO.println s!"writes-closure golden: {cases.length} cases written"
  return 0

end Fw.Plan.WritesClosure
