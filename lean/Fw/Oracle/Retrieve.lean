import Fw.Oracle.Expand
import Fw.Oracle.ExpandPaired
import Fw.Oracle.Send
namespace Fw.Oracle.Retrieve
open Fw.Oracle Fw.Oracle.Expand

structure RetrieveCfg where
  maxReads : Nat := 8
  readBytes : Nat := 32768
  rounds : Nat := 2
  sendsPerRow : Nat := 2
  excerptBytes : Nat := 8192
  maxPick : Nat := 4
deriving Repr, DecidableEq

def rcfg : RetrieveCfg := {}

def inScope (fs : List (String × Option String)) : Bool :=
  fs.any fun (v, w) => v == "kept" || v == "overCap" || (v == "vocab" && !(w.getD "").startsWith "c-")

#guard inScope [("notAllowed", none), ("overCap", none)]
#guard inScope [("vocab", some "blocker")]
#guard !inScope [("vocab", some "c-quota"), ("notAllowed", none), ("noText", none)]
#guard !inScope []

def tree (id : String) (files : List (String × Option String)) : List (String × String) :=
  (kept safe id files).filter fun (p, _) => (hit id p).isNone

theorem tree_allowed {id p x : String} {files : List (String × Option String)} (h : (p, x) ∈ tree id files) :
    allowed safe p = true ∧ (p, some x) ∈ files ∧ (∀ w ∈ vocab id, ¬ ∃ u v, lower x = u ++ lower w ++ v) ∧
      hit id p = none := by
  obtain ⟨hk, hp⟩ := List.mem_filter.mp h
  exact ⟨kept_allowed hk, kept_whole hk, kept_vocabFree rfl hk, by simpa using hp⟩

theorem tree_refuses {id p : String} {files : List (String × Option String)} (h : allowed safe p = false) (x : String) :
    (p, x) ∉ tree id files := fun hm => by simp [(tree_allowed hm).1] at h

theorem tree_ledger (id x : String) (files : List (String × Option String)) :
    ("docs/team/incidents/ledger.json", x) ∉ tree id files := tree_refuses allowed_ledger x

theorem tree_graph (id x : String) (files : List (String × Option String)) :
    ("docs/team/work-graph.json", x) ∉ tree id files := tree_refuses allowed_graph x

theorem tree_research (id x : String) (files : List (String × Option String)) :
    ("research/notes/2026/10-2x-jev-file-context.md", x) ∉ tree id files := tree_refuses allowed_research x

theorem tree_docs (id x : String) (files : List (String × Option String)) :
    ("docs/team/tools/land.md", x) ∉ tree id files := tree_refuses (by decide) x

theorem tree_oracle (id x : String) (files : List (String × Option String)) :
    ("lean/Fw/Oracle/Labels.lean", x) ∉ tree id files := tree_refuses allowed_labels x

#guard tree "inc-x" [("scripts/a.mjs", some "ok"), ("scripts/c-quota.mjs", some "ok"), ("scripts/b.mjs", some "a blocker"),
  ("docs/x.md", some "ok"), ("apps/inc-x.ts", some "ok")] == [("scripts/a.mjs", "ok")]

structure Call where
  tool : String
  path : String
  glob : String := ""
  bytes : Nat
deriving Repr, DecidableEq

def readTools : List String := ["Read", "Grep", "Glob"]

def segs (s : String) : List String := s.splitOn "/"

def globOk (g : String) : Bool := !g.startsWith "/" && !(segs g).contains ".."

def dirOf (paths : List String) (d : String) : Bool := paths.any fun q => (d ++ "/").toList.isPrefixOf q.toList

def inTree (paths : List String) (c : Call) : Bool :=
  readTools.contains c.tool && globOk c.glob &&
    if c.tool == "Read" then paths.contains c.path else c.path == "" || paths.contains c.path || dirOf paths c.path

def rel (root p : String) : Option String :=
  let r := if p == root then some "" else if (root ++ "/").isPrefixOf p then some (p.drop (root.length + 1)).copy
    else if p.startsWith "/" then none else some p
  r.bind fun s =>
    let s := if s.startsWith "./" then (s.drop 2).copy else s
    let s := if s.endsWith "/" then (s.dropEnd 1).copy else s
    if s == "." then some "" else if (segs s).any (fun x => x == ".." || x == ".") then none else some s

#guard rel "/t" "/t/scripts/a.mjs" == some "scripts/a.mjs"
#guard rel "/t" "/t" == some "" && rel "/t" "." == some "" && rel "/t" "./apps/" == some "apps"
#guard rel "/t" "/etc/passwd" == none && rel "/t" "/t/../x" == none && rel "/t" "/tx/a" == none
#guard rel "/t" "apps/../../x" == none

def callAt (root : String) (c : Call) : Option Call := (rel root c.path).map fun p => { c with path := p }

inductive Verdict where
  | ok
  | outside
  | overReads
  | overBytes
deriving Repr, DecidableEq

def traceBytes (cs : List Call) : Nat := (cs.map (·.bytes)).sum

def traceVerdict (rc : RetrieveCfg) (paths : List String) (cs : List Call) : Verdict :=
  if !cs.all (inTree paths) then .outside
  else if rc.maxReads < cs.length then .overReads
  else if rc.readBytes < traceBytes cs then .overBytes
  else .ok

theorem traceVerdict_ok {rc : RetrieveCfg} {paths : List String} {cs : List Call} :
    traceVerdict rc paths cs = .ok ↔
      (∀ c ∈ cs, inTree paths c = true) ∧ cs.length ≤ rc.maxReads ∧ traceBytes cs ≤ rc.readBytes := by
  unfold traceVerdict
  by_cases ha : cs.all (inTree paths) = true
  · have hl := List.all_eq_true.mp ha
    by_cases hr : rc.maxReads < cs.length
    · simp only [ha, hr, Bool.not_true, Bool.false_eq_true, ↓reduceIte, reduceCtorEq, false_iff, not_and]
      intro _ h
      omega
    · by_cases hb : rc.readBytes < traceBytes cs
      · simp [ha, hr, hb]
      · simp only [ha, hr, hb, Bool.not_true, Bool.false_eq_true, ↓reduceIte, true_iff]
        exact ⟨hl, Nat.le_of_not_lt hr, Nat.le_of_not_lt hb⟩
  · simp only [ha, Bool.not_false, ↓reduceIte, reduceCtorEq, false_iff, not_and]
    intro h
    exact absurd (List.all_eq_true.mpr h) ha

def traceAt (rc : RetrieveCfg) (root : String) (paths : List String) (raw : List Call) : Verdict :=
  match raw.mapM (callAt root) with
  | none => .outside
  | some cs => traceVerdict rc paths cs

theorem traceVerdict_outside {rc : RetrieveCfg} {paths : List String} {cs : List Call} {c : Call} (hc : c ∈ cs)
    (h : inTree paths c = false) : traceVerdict rc paths cs = .outside := by
  have : cs.all (inTree paths) = false := by
    cases hh : cs.all (inTree paths)
    · rfl
    · simp [List.all_eq_true.mp hh c hc] at h
  simp [traceVerdict, this]

theorem traceVerdict_overReads {rc : RetrieveCfg} {paths : List String} {cs : List Call}
    (hin : ∀ c ∈ cs, inTree paths c = true) (h : rc.maxReads < cs.length) : traceVerdict rc paths cs = .overReads := by
  simp [traceVerdict, List.all_eq_true.mpr hin, h]

theorem traceVerdict_overBytes {rc : RetrieveCfg} {paths : List String} {cs : List Call}
    (hin : ∀ c ∈ cs, inTree paths c = true) (hr : cs.length ≤ rc.maxReads) (h : rc.readBytes < traceBytes cs) :
    traceVerdict rc paths cs = .overBytes := by
  simp [traceVerdict, List.all_eq_true.mpr hin, Nat.not_lt.mpr hr, h]

structure HookSt where
  calls : Nat := 0
  bytes : Nat := 0
deriving Repr, DecidableEq

inductive Hook where
  | allow
  | deny (why : String)
deriving Repr, DecidableEq

def hook (rc : RetrieveCfg) (paths : List String) (st : HookSt) (c : Call) : Hook :=
  if !inTree paths c then .deny "outside"
  else if rc.maxReads ≤ st.calls then .deny "overReads"
  else if rc.readBytes < st.bytes + c.bytes then .deny "overBytes"
  else .allow

def step (st : HookSt) (c : Call) : HookSt := { calls := st.calls + 1, bytes := st.bytes + c.bytes }

def hookRun (rc : RetrieveCfg) (paths : List String) : HookSt → List Call → List Call
  | _, [] => []
  | st, c :: cs => if hook rc paths st c = .allow then c :: hookRun rc paths (step st c) cs else hookRun rc paths st cs

theorem hook_allow {rc : RetrieveCfg} {paths : List String} {st : HookSt} {c : Call} (h : hook rc paths st c = .allow) :
    inTree paths c = true ∧ st.calls < rc.maxReads ∧ st.bytes + c.bytes ≤ rc.readBytes := by
  unfold hook at h
  by_cases hi : inTree paths c = true
  · by_cases hr : rc.maxReads ≤ st.calls
    · simp [hi, hr] at h
    · by_cases hb : rc.readBytes < st.bytes + c.bytes
      · simp [hi, hr, hb] at h
      · exact ⟨hi, Nat.lt_of_not_le hr, Nat.le_of_not_lt hb⟩
  · simp [hi] at h

theorem hookRun_bound {rc : RetrieveCfg} {paths : List String} : ∀ (st : HookSt) (cs : List Call),
    st.calls ≤ rc.maxReads → st.bytes ≤ rc.readBytes →
    (∀ c ∈ hookRun rc paths st cs, inTree paths c = true) ∧
      st.calls + (hookRun rc paths st cs).length ≤ rc.maxReads ∧
      st.bytes + traceBytes (hookRun rc paths st cs) ≤ rc.readBytes
  | st, [], hc, hb => by simp [hookRun, traceBytes, hc, hb]
  | st, c :: cs, hc, hb => by
    unfold hookRun
    split
    · rename_i ha
      obtain ⟨hi, hr, hy⟩ := hook_allow ha
      obtain ⟨h1, h2, h3⟩ := hookRun_bound (rc := rc) (paths := paths) (step st c) cs
        (by simp only [step]; omega) (by simp only [step]; omega)
      have e1 : (step st c).calls = st.calls + 1 := rfl
      have e2 : (step st c).bytes = st.bytes + c.bytes := rfl
      rw [e1] at h2
      rw [e2] at h3
      refine ⟨fun x hx => ?_, ?_, ?_⟩
      · rcases List.mem_cons.mp hx with rfl | hx
        · exact hi
        · exact h1 x hx
      · simp only [List.length_cons]; omega
      · simp only [traceBytes, List.map_cons, List.sum_cons] at h3 ⊢; omega
    · exact hookRun_bound st cs hc hb

theorem traceVerdict_hookRun (rc : RetrieveCfg) (paths : List String) (cs : List Call) :
    traceVerdict rc paths (hookRun rc paths {} cs) = .ok := by
  obtain ⟨h1, h2, h3⟩ := hookRun_bound (rc := rc) (paths := paths) {} cs (Nat.zero_le _) (Nat.zero_le _)
  exact traceVerdict_ok.mpr ⟨h1, by simpa using h2, by simpa using h3⟩

#guard hook rcfg ["a.mjs"] {} { tool := "Read", path := "a.mjs", bytes := 10 } == .allow
#guard hook rcfg ["a.mjs"] {} { tool := "Read", path := "b.mjs", bytes := 10 } == .deny "outside"
#guard hook rcfg ["a.mjs"] {} { tool := "Bash", path := "a.mjs", bytes := 0 } == .deny "outside"
#guard hook rcfg ["d/a.mjs"] {} { tool := "Glob", path := "d", glob := "../**", bytes := 0 } == .deny "outside"
#guard hook rcfg ["d/a.mjs"] {} { tool := "Grep", path := "d", glob := "*.mjs", bytes := 0 } == .allow
#guard hook rcfg ["a.mjs"] { calls := 8 } { tool := "Read", path := "a.mjs", bytes := 1 } == .deny "overReads"
#guard hook rcfg ["a.mjs"] { calls := 1, bytes := 32000 } { tool := "Read", path := "a.mjs", bytes := 769 } == .deny "overBytes"

structure Range where
  path : String
  first : Nat
  last : Nat
deriving Repr, DecidableEq

def runs : List Nat → List (Nat × Nat)
  | [] => []
  | n :: ns => match runs ns with
    | (a, b) :: rs => if n + 1 = a then (n, b) :: rs else (n, n) :: (a, b) :: rs
    | [] => [(n, n)]

def sortNat (l : List Nat) : List Nat := (l.mergeSort fun a b => decide (a ≤ b)).eraseDups

def readRanges (reads : List (String × List Nat)) : List Range :=
  (dedup (reads.map (·.1))).flatMap fun p =>
    (runs (sortNat ((reads.filter (·.1 == p)).flatMap (·.2)))).map fun (a, b) => ⟨p, a, b⟩

#guard runs [1, 2, 3, 7, 8, 10] == [(1, 3), (7, 8), (10, 10)]
#guard readRanges [("a", [5, 6]), ("b", [1]), ("a", [1, 2, 3, 4, 9])] == [⟨"a", 1, 6⟩, ⟨"a", 9, 9⟩, ⟨"b", 1, 1⟩]

def covers (r e : Range) : Bool := r.path == e.path && decide (r.first ≤ e.first) && decide (e.last ≤ r.last)

def evidenceValid (rs : List Range) (e : Range) : Bool := decide (1 ≤ e.first) && decide (e.first ≤ e.last) && rs.any (covers · e)

def validEvidence (rs : List Range) (es : List Range) : List Range := es.filter (evidenceValid rs)

theorem validEvidence_read {rs es : List Range} {e : Range} (he : e ∈ validEvidence rs es) {n : Nat}
    (h1 : e.first ≤ n) (h2 : n ≤ e.last) : ∃ r ∈ rs, r.path = e.path ∧ r.first ≤ n ∧ n ≤ r.last := by
  obtain ⟨_, hv⟩ := List.mem_filter.mp he
  simp only [evidenceValid, Bool.and_eq_true, decide_eq_true_eq, List.any_eq_true] at hv
  obtain ⟨⟨_, _⟩, r, hr, hc⟩ := hv
  simp only [covers, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at hc
  exact ⟨r, hr, hc.1.1, by omega, by omega⟩

#guard validEvidence [⟨"a", 1, 6⟩] [⟨"a", 2, 4⟩, ⟨"a", 5, 7⟩, ⟨"b", 1, 1⟩, ⟨"a", 0, 1⟩, ⟨"a", 4, 3⟩] == [⟨"a", 2, 4⟩]

def candidates (rc : RetrieveCfg) (ps : List String) : List String :=
  ((dedup ps).mergeSort fun a b => decide (a ≤ b)).take rc.maxPick

def slot (i : Nat) : String := "f" ++ toString (i + 1)

def slots (rc : RetrieveCfg) : List String := (List.range rc.maxPick).map slot ++ ["none"]

def slotted (cs : List String) : List (String × String) := (List.range cs.length).zip cs |>.map fun (i, p) => (slot i, p)

def pickText (cs : List String) : String := "\n".intercalate ((slotted cs).map fun (s, p) => s ++ ": " ++ p)

theorem filePick_slots : filePick.spec.keys = slots rcfg := by decide

def pick1Row (rc : RetrieveCfg) (row : List (String × String)) (ps : List String) : List (String × String) :=
  row ++ [("candidates", pickText (candidates rc ps))]

def best : List (Option String × Rat) → Option String × Rat
  | [] => (none, 0)
  | [x] => x
  | x :: y :: ys => let b := best (y :: ys); if b.2 ≤ x.2 then x else b

def pick (cs : List String) (probs : List (String × Rat)) : Option String :=
  (best ((slotted cs).map (fun (s, p) => (some p, (probs.lookup s).getD 0)) ++ [(none, (probs.lookup "none").getD 0)])).1

theorem best_mem : ∀ (l : List (Option String × Rat)), l ≠ [] → best l ∈ l
  | [], h => absurd rfl h
  | [x], _ => by simp [best]
  | x :: y :: ys, _ => by
    have ih := best_mem (y :: ys) (by simp)
    show (if (best (y :: ys)).2 ≤ x.2 then x else best (y :: ys)) ∈ x :: y :: ys
    split
    · exact List.mem_cons_self
    · exact List.mem_cons_of_mem _ ih

theorem slotted_snd {cs : List String} {s p : String} (h : (s, p) ∈ slotted cs) : p ∈ cs := by
  unfold slotted at h
  obtain ⟨⟨i, q⟩, hm, he⟩ := List.mem_map.mp h
  simp only [Prod.mk.injEq] at he
  obtain ⟨_, rfl⟩ := he
  exact List.of_mem_zip hm |>.2

theorem pick_mem {cs : List String} {probs : List (String × Rat)} {p : String} (h : pick cs probs = some p) : p ∈ cs := by
  unfold pick at h
  have hm := best_mem ((slotted cs).map (fun (s, p) => (some p, (probs.lookup s).getD 0)) ++
    [(none, (probs.lookup "none").getD 0)]) (by simp)
  generalize best _ = b at h hm
  obtain ⟨b1, b2⟩ := b
  simp only at h
  subst h
  rcases List.mem_append.mp hm with hm | hm
  · obtain ⟨⟨s, q⟩, hq, he⟩ := List.mem_map.mp hm
    simp only [Prod.mk.injEq, Option.some.injEq] at he
    obtain ⟨rfl, _⟩ := he
    exact slotted_snd hq
  · simp at hm

#guard pick ["b.mjs", "a.mjs"] [("f1", 1 / 2), ("f2", 1 / 2), ("none", 0)] == some "b.mjs"
#guard pick ["a.mjs"] [("f1", 1 / 10), ("f3", 8 / 10), ("none", 1 / 10)] == some "a.mjs"
#guard pick ["a.mjs"] [("f1", 1 / 10), ("none", 9 / 10)] == none
#guard pick [] [("f1", 1)] == none
#guard candidates rcfg ["s/b", "s/a", "s/b", "s/c", "s/e", "s/d"] == ["s/a", "s/b", "s/c", "s/d"]

def takeFit (cap : Nat) : List String → List String → List String
  | acc, [] => acc
  | acc, l :: ls => if escBytes ("\n".intercalate (acc ++ [l])) ≤ cap then takeFit cap (acc ++ [l]) ls else acc

def excerpt (cap : Nat) (t : String) : String := "\n".intercalate (takeFit cap [] (t.splitOn "\n"))

theorem takeFit_le (cap : Nat) : ∀ (acc ls : List String), escBytes ("\n".intercalate acc) ≤ cap →
    escBytes ("\n".intercalate (takeFit cap acc ls)) ≤ cap
  | _, [], h => h
  | acc, l :: ls, h => by
    unfold takeFit
    split
    · exact takeFit_le cap _ ls (by assumption)
    · exact h

theorem excerpt_le (cap : Nat) (t : String) : escBytes (excerpt cap t) ≤ cap :=
  takeFit_le cap [] _ (by simp [escBytes])

#guard excerpt 8 "abc\ndef\nghi" == "abc\ndef"
#guard excerpt 2 "abc\nd" == ""

def pickRow (rc : RetrieveCfg) (row : List (String × String)) : Option (String × String) → List (String × String)
  | none => row
  | some (p, t) => withFiles row [(p, excerpt rc.excerptBytes t)]

theorem pick_none_noop (rc : RetrieveCfg) (row : List (String × String)) (names : List String) :
    bodyText incidentClass (redactState names (rowState d1 (pickRow rc row none))) =
      bodyText incidentClass (redactState names (rowState d1 row)) := rfl

def pickSends (cs : List String) (picked : Option String) : Nat :=
  if cs = [] then 0 else if picked.isNone then 1 else 2

theorem pickSends_le (cs : List String) (picked : Option String) : pickSends cs picked ≤ rcfg.sendsPerRow := by
  unfold pickSends rcfg
  split
  · exact Nat.zero_le _
  · split <;> decide

theorem rounds_cover : rcfg.rounds = rcfg.sendsPerRow := rfl

def rangeLabel (r : Range) : String := r.path ++ ":" ++ toString r.first ++ "-" ++ toString r.last

def lineSlice (t : String) (r : Range) : String := "\n".intercalate (((t.splitOn "\n").drop (r.first - 1)).take (r.last + 1 - r.first))

def hybridRow (row : List (String × String)) (rs : List (String × String)) : List (String × String) := withFiles row (fit row [] rs)

theorem hybrid_noreads (row : List (String × String)) : hybridRow row [] = row := rfl

theorem hybrid_uncut (row : List (String × String)) (rs : List (String × String)) (h : sizeWith row [] ≤ stateCap) :
    stateBytes (rowState d1 (hybridRow row rs)) ≤ stateCap ∧
      capState stateCap (rowState d1 (hybridRow row rs)) = rowState d1 (hybridRow row rs) := by
  have he : stateEsc (rowState d1 (hybridRow row rs)) ≤ stateCap := by
    rcases fit_fits (row := row) (fs := rs) (.inl rfl) with h0 | h0
    · simp only [hybridRow, h0]; exact h
    · exact h0
  have hb := Nat.le_trans (stateBytes_le_esc _) he
  exact ⟨hb, capState_of_le _ _ hb⟩

theorem hybrid_kept {row rs : List (String × String)} {x : String × String} (h : x ∈ fit row [] rs) : x ∈ rs := by
  rcases fit_mem h with h | h
  · simp at h
  · exact h

#guard lineSlice "a\nb\nc\nd" ⟨"p", 2, 3⟩ == "b\nc"
#guard hybridRow [("title", "t")] [("a.mjs:1-1", "x"), ("b.mjs:1-1", xs 40000)] == [("title", "t"), ("files", "file: a.mjs:1-1\nx")]

structure Item where
  id : String
  sends : Nat
  tokens : Nat
deriving Repr, DecidableEq

def runSends (r : List Item) : Nat := (r.map (·.sends)).sum

def runTokens (r : List Item) : Nat := (r.map (·.tokens)).sum

def fits (bud : Budget) (rb : RunBudget) (r : List Item) : Bool :=
  decide (runSends r ≤ bud.runCap) && decide (runTokens r ≤ rb.maxInputTokens)

def close (r : List Item) : List (List Item) := if r = [] then [] else [r]

def plan (bud : Budget) (rb : RunBudget) : Nat → List Item → List Item → List (List Item) × List Item
  | _, cur, [] => (close cur, [])
  | left, cur, it :: rest =>
    if left < it.sends then (close cur, it :: rest)
    else if fits bud rb (cur ++ [it]) then plan bud rb (left - it.sends) (cur ++ [it]) rest
    else if fits bud rb [it] then
      let r := plan bud rb (left - it.sends) [it] rest
      (close cur ++ r.1, r.2)
    else (close cur, it :: rest)

def sendPlan (bud : Budget) (rb : RunBudget) (logged : Nat) (items : List Item) : List (List Item) × List Item :=
  plan bud rb (bud.dailyCap - logged) [] items

theorem runSends_append (a b : List Item) : runSends (a ++ b) = runSends a + runSends b := by simp [runSends]

theorem plan_ok (bud : Budget) (rb : RunBudget) : ∀ (left : Nat) (cur items : List Item), fits bud rb cur = true →
    (∀ r ∈ (plan bud rb left cur items).1, fits bud rb r = true) ∧
      ((plan bud rb left cur items).1.map runSends).sum ≤ runSends cur + left
  | left, cur, [], hc => by
    unfold plan close
    split <;> simp_all
  | left, cur, it :: rest, hc => by
    have hcl : (∀ r ∈ close cur, fits bud rb r = true) ∧ ((close cur).map runSends).sum ≤ runSends cur := by
      unfold close; split <;> simp_all
    unfold plan
    split
    · exact ⟨hcl.1, Nat.le_trans hcl.2 (Nat.le_add_right _ _)⟩
    · split
      · rename_i hl hf
        obtain ⟨h1, h2⟩ := plan_ok bud rb (left - it.sends) (cur ++ [it]) rest hf
        refine ⟨h1, ?_⟩
        rw [runSends_append] at h2
        simp only [runSends, List.map_cons, List.map_nil, List.sum_cons, List.sum_nil] at h2 ⊢
        omega
      · split
        · rename_i hl _ hf
          obtain ⟨h1, h2⟩ := plan_ok bud rb (left - it.sends) [it] rest hf
          refine ⟨fun r hr => ?_, ?_⟩
          · rcases List.mem_append.mp hr with hr | hr
            · exact hcl.1 r hr
            · exact h1 r hr
          · simp only [List.map_append, List.sum_append]
            simp only [runSends, List.map_cons, List.map_nil, List.sum_cons, List.sum_nil] at h2
            have := hcl.2
            omega
        · exact ⟨hcl.1, Nat.le_trans hcl.2 (Nat.le_add_right _ _)⟩

theorem sendPlan_runs (bud : Budget) (rb : RunBudget) (logged : Nat) (items : List Item) :
    ∀ r ∈ (sendPlan bud rb logged items).1, runSends r ≤ bud.runCap ∧ runTokens r ≤ rb.maxInputTokens := by
  intro r hr
  have := (plan_ok bud rb _ [] items (by simp [fits, runSends, runTokens])).1 r hr
  simpa [fits] using this

theorem sendPlan_day (bud : Budget) (rb : RunBudget) (logged : Nat) (items : List Item) :
    ((sendPlan bud rb logged items).1.map runSends).sum ≤ bud.dailyCap - logged := by
  have := (plan_ok bud rb (bud.dailyCap - logged) [] items (by simp [fits, runSends, runTokens])).2
  unfold sendPlan
  simpa [runSends] using this

#guard (sendPlan defaultBudget defaultRunBudget 49 ((List.range 5).map fun i => ⟨toString i, 2, 150000⟩)).1.map (·.length) == [2, 2, 1]
#guard (sendPlan defaultBudget defaultRunBudget 196 ((List.range 5).map fun i => ⟨toString i, 2, 10⟩)) ==
  ([[⟨"0", 2, 10⟩, ⟨"1", 2, 10⟩]], [⟨"2", 2, 10⟩, ⟨"3", 2, 10⟩, ⟨"4", 2, 10⟩])
#guard (sendPlan defaultBudget defaultRunBudget 0 [⟨"a", 1, 500000⟩, ⟨"b", 1, 1⟩]) == ([], [⟨"a", 1, 500000⟩, ⟨"b", 1, 1⟩])

structure ArmCmp where
  arm : String
  vsC : List Pair
  vsX : List Pair
deriving Repr, DecidableEq

inductive Why where
  | netLowC (arm : String) (net : Int)
  | netLowX (arm : String) (net : Int)
  | gainOnDropped (arm id : String)
  | untraced (arm id : String)
deriving Repr, DecidableEq

def reasons (a : ArmCmp) (dropped traced : List String) : List Why :=
  (if net a.vsC < minNet then [Why.netLowC a.arm (net a.vsC)] else []) ++
    (if net a.vsX < 0 then [Why.netLowX a.arm (net a.vsX)] else []) ++
    ((gains a.vsC).filter dropped.contains).map (Why.gainOnDropped a.arm) ++
    ((gains a.vsC).filter fun i => !traced.contains i).map (Why.untraced a.arm)

def adopt (a : ArmCmp) (dropped traced : List String) : Bool := (reasons a dropped traced).isEmpty

theorem adopt_iff (a : ArmCmp) (dropped traced : List String) :
    adopt a dropped traced = true ↔ minNet ≤ net a.vsC ∧ 0 ≤ net a.vsX ∧
      ∀ i ∈ gains a.vsC, i ∉ dropped ∧ i ∈ traced := by
  simp only [adopt, reasons, List.isEmpty_iff, List.append_eq_nil_iff, List.map_eq_nil_iff, List.filter_eq_nil_iff,
    List.contains_iff_mem, Bool.not_eq_true']
  constructor
  · rintro ⟨⟨⟨hc, hx⟩, hd⟩, ht⟩
    refine ⟨?_, ?_, fun i hi => ⟨fun hm => hd i hi (by simpa using hm), by simpa using ht i hi⟩⟩
    · by_cases hl : net a.vsC < minNet
      · simp [hl] at hc
      · exact Int.not_lt.mp hl
    · by_cases hl : net a.vsX < 0
      · simp [hl] at hx
      · exact Int.not_lt.mp hl
  · rintro ⟨hc, hx, hg⟩
    exact ⟨⟨⟨by simp [Int.not_lt.mpr hc], by simp [Int.not_lt.mpr hx]⟩,
      fun i hi hm => (hg i hi).1 (by simpa using hm)⟩, fun i hi => by simpa using (hg i hi).2⟩

theorem reject_netLowC {a : ArmCmp} {dropped traced : List String} (h : net a.vsC < minNet) :
    adopt a dropped traced = false := by
  cases hb : adopt a dropped traced
  · rfl
  · exact absurd ((adopt_iff _ _ _).mp hb).1 (Int.not_le.mpr h)

theorem reject_netLowX {a : ArmCmp} {dropped traced : List String} (h : net a.vsX < 0) :
    adopt a dropped traced = false := by
  cases hb : adopt a dropped traced
  · rfl
  · exact absurd ((adopt_iff _ _ _).mp hb).2.1 (Int.not_le.mpr h)

theorem reject_dropped {a : ArmCmp} {dropped traced : List String} {i : String} (hi : i ∈ gains a.vsC)
    (hd : i ∈ dropped) : adopt a dropped traced = false := by
  cases hb : adopt a dropped traced
  · rfl
  · exact absurd hd (((adopt_iff _ _ _).mp hb).2.2 i hi).1

theorem reject_untraced {a : ArmCmp} {dropped traced : List String} {i : String} (hi : i ∈ gains a.vsC)
    (ht : i ∉ traced) : adopt a dropped traced = false := by
  cases hb : adopt a dropped traced
  · rfl
  · exact absurd (((adopt_iff _ _ _).mp hb).2.2 i hi).2 ht

#guard adopt ⟨"t", ["a", "b", "c", "d"].map (⟨·, false, true⟩), []⟩ [] ["a", "b", "c", "d"]
#guard !adopt ⟨"t", ["a", "b", "c", "d"].map (⟨·, false, true⟩), [⟨"a", true, false⟩]⟩ [] ["a", "b", "c", "d"]
#guard reasons ⟨"t", [⟨"a", false, true⟩], []⟩ ["a"] [] ==
  [.netLowC "t" 1, .gainOnDropped "t" "a", .untraced "t" "a"]

end Fw.Oracle.Retrieve
