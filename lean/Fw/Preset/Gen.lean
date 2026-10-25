import Lean.Data.Json
import Fw.Preset.V2Proved
/-!
Generates the `v2-proved` preset and decision rows from the findings ledger and `part.json` files.
Run from `lean/`: `printf 'import Fw.Preset.Gen\n#eval Fw.Preset.Gen.run ["--check"]\n' | lake env lean --stdin` (drop `--check` to write).
-/
namespace Fw.Preset.Gen
open Lean Fw.Preset
open Fw.Gate.Trajectory (Stored Engine Walk Family Group Outcome Unjudged UnitRow outcome basisAt groupsOf widthsOf)

def linkTable : List (Flag × List Key) :=
  let k1 : Key := ("engine.scroll", "batched (all reads, then all returned writes, one pass per frame)")
  let k3 : Key := ("nav.hitTest", "hit-skip (skip the probe while morph > 0.2)")
  let k4 : Key := ("nav.hitTest", "elements-skip (elementsFromPoint with an allow-list, no pointer-events write)")
  let k7 : Key := ("hero.countdown (+ morph.countdown)",
    "strip (cd-strip, KD#12): 10 will-change faces per digit -> one 12-entry strip")
  let k8h : Key := ("hero.countdown / morph.countdown",
    "hidden-skip: skip face writes while the clock is not visible; the spring keeps integrating")
  let k9 : Key := ("morph.tween",
    "g0.0b: the rAF tween replaced by one WAAPI animation on a registered --morph with cubic-bezier(1/3,1,2/3,1)")
  let k12 : Key := ("morph.mount", "warm-up: mount the panel at a still moment near the end (v14, D1 always-built card)")
  let k13 : Key := ("morph.countdown",
    "strip (10 will-change faces per digit -> one 12-entry strip), reused from hero.countdown (KD#12, cd-strip)")
  let k25h : Key := ("engine.scene",
    "hidden pause of compositor marquees (morph.columns at m <= 0.08, scene off-screen), HiddenPause.lean")
  let k25m : Key := ("engine.scene",
    "morph.countdown hidden: keep the spring integrating, skip the 16 face writes per digit (HiddenPause skipWrites)")
  let k21 : Key := ("pain.notes",
    "arm the 3 s rotation interval only while visible (armed = inView and not narrow and not covered)")
  let k16 : Key := ("people.card",
    "MQ-gated shrink (KD#3): skip the --future-shrink write and the rAF re-request in the c860 band")
  let kut : Key := ("engine.scroll",
    "engine.scroll:unthrottle: ship the throttle-lift element (one absolute 1 px opacity-0 element with a root scroll-driven \
      animation of a registered custom property, inside @supports and (pointer: coarse)) so Mobile Safari stops holding \
      visible-rect updates to 100 ms while the toolbar collapses")
  let k6i : Key := ("hero.exit",
    "hero.exit:scoped with inline reader writes (task exit-scoped-inline): the writer sets --exit-opacity and \
      --exit-scatter inline on each of the 16 readers in the frame it writes the stage")
  [(⟨"engine.scroll", "batched"⟩, [k1]),
   (⟨"nav.hitTest", "elements-skip"⟩, [k4]),
   (⟨"nav.hitTest", "hit-skip"⟩, [k3]),
   (⟨"hero.countdown", "strip"⟩, [k7]),
   (⟨"morph.countdown", "strip"⟩, [k7, k13]),
   (⟨"morph.countdown", "hidden-pause"⟩, [k8h, k25m]),
   (⟨"morph.columns", "hidden-pause"⟩, [k25h]),
   (⟨"engine.scene", "hidden-pause"⟩, [k25h]),
   (⟨"morph.mount", "shift"⟩, [k12]),
   (⟨"morph.tween", "waapi"⟩, [k9]),
   (⟨"pain.notes", "visible"⟩, [k21]),
   (⟨"people.card", "mq"⟩, [k16]),
   (⟨"hero.exit", "scoped"⟩, [k6i]),
   (⟨"engine.scroll", "unthrottle"⟩, [kut])]

def curated : List (Flag × String) :=
  [(⟨"hero.accent", "steps"⟩,
    "ledger n = 15: a trade on Chromium and no win on WebKit (INFERRED); a follow-up makes the generator require an \
      engine-win field")]

def reasonOf (f : Flag) : Option String := (curated.find? (·.1 == f)).map (·.2)

def links : List (Flag × List Key) := linkTable.filter fun l => (reasonOf l.1).isNone

theorem linkOf_links (f : Flag) :
    linkOf links f = if (reasonOf f).isNone then linkOf linkTable f else none := by
  unfold links linkOf
  generalize linkTable = l
  induction l with
  | nil => split <;> rfl
  | cons a t ih =>
    rw [List.filter_cons]
    by_cases h : a.1 = f
    · subst h
      by_cases hr : (reasonOf a.1).isNone = true
      · simp only [hr, ite_true, List.find?_cons, beq_self_eq_true, Option.map_some]
      · simp only [hr, ih, Bool.false_eq_true, ite_false]
    · have hb : (a.1 == f) = false := by simpa using h
      by_cases hr : (reasonOf a.1).isNone = true
      · simp only [hr, ite_true, List.find?_cons, hb, ih]
      · simp only [hr, ih, Bool.false_eq_true, ite_false, List.find?_cons, hb]

theorem linkOf_links_of_none {f : Flag} (h : reasonOf f = none) : linkOf links f = linkOf linkTable f := by
  simp [linkOf_links, h]

theorem curated_not_mem {reg : List Reg} {ledger : List Row} {st : List Stored} {f : Flag} (h : reasonOf f ≠ none) :
    f ∉ preset reg links ledger st :=
  unlinked_not_mem (by simp [linkOf_links, h])

def parseFlag (s : String) : Except String Flag :=
  match s.splitOn ":" with
  | [p, v] => if p.isEmpty || v.isEmpty then .error s!"bad flag {s}" else .ok ⟨p, v⟩
  | _ => .error s!"bad flag {s}"

def parseKind : String → Except String Kind
  | "faithful" => .ok .faithful
  | "optimized" => .ok .optimized
  | "ablation" => .ok .ablation
  | "proposal" => .ok .proposal
  | s => .error s!"unknown kind {s}"

def parseVisClass : String → Except String VisClass
  | "E" => .ok .e
  | "E-s" => .ok .eS
  | "Q" => .ok .q
  | "L" => .ok .l
  | s => .error s!"unknown visClass {s}"

def visClassWord : VisClass → String
  | .e => "E"
  | .eS => "E-s"
  | .q => "Q"
  | .l => "L"

def kindWord : Kind → String
  | .faithful => "faithful"
  | .optimized => "optimized"
  | .ablation => "ablation"
  | .proposal => "proposal"

def parseFRes : String → Except String FRes
  | "pass" => .ok .pass
  | "unusable" => .ok .unusable
  | "model-bug" => .ok .modelBug
  | s => .error s!"unknown fResult {s}"

def fresWord : FRes → String
  | .pass => "pass"
  | .unusable => "unusable"
  | .modelBug => "model-bug"

def optStr (j : Json) (n : String) : Except String (Option String) :=
  match j.getObjVal? n with
  | .error _ => .ok none
  | .ok .null => .ok none
  | .ok (.str s) => .ok (some s)
  | .ok _ => .error s!"field {n} is not a string"

def parseRow (j : Json) : Except String Row := do
  let fr ← match ← optStr j "fResult" with
    | none => pure none
    | some s => some <$> parseFRes s
  return { part := ← j.getObjValAs? String "part", candidate := ← j.getObjValAs? String "candidate",
           status := ← j.getObjValAs? String "status", flag := ← optStr j "flag", fResult := fr }

def parseLedger (j : Json) : Except String (List Row) := do
  let a ← (← j.getObjVal? "findings").getArr?
  a.toList.mapM parseRow

def parseFlags (j : Json) : Except String (List Flag) := do
  (← j.getArr?).toList.mapM fun x => do parseFlag (← x.getStr?)

def parsePart (j : Json) : Except String (List Reg) := do
  let id ← j.getObjValAs? String "id"
  let vs ← (← j.getObjVal? "variants").getObj?
  let rel (field key : String) : Except String (List Flag) :=
    match j.getObjVal? field >>= (·.getObjVal? key) with
    | .ok x => parseFlags x
    | .error _ => .ok []
  vs.toList.mapM fun (v, d) => do
    let f : Flag := ⟨id, v⟩
    let kind ← parseKind (← d.getObjValAs? String "kind")
    let vc ← match ← optStr d "visClass" with
      | none => pure none
      | some w => some <$> parseVisClass w
    if kind == .optimized && vc == some .l then throw s!"{f.key}: an optimized variant cannot be a look change (L)"
    return { flag := f, kind, requires := ← rel "requires" f.key, conflicts := ← rel "conflicts" f.key, visClass := vc }

def presetText (p : List Flag) : String :=
  (Json.mkObj [("name", "v2-proved"), ("extends", "original"),
    ("fw", Json.mkObj (p.map fun f => (f.part, .str f.variant)))]).compress ++ "\n"

def whyJson : Why → Json
  | .proved => Json.mkObj [("verdict", "proved")]
  | .noLink => Json.mkObj [("verdict", "no-link")]
  | .falsifiedFlag => Json.mkObj [("verdict", "falsified-flag")]
  | .rowCount k n => Json.mkObj [("verdict", "row-count"), ("part", .str k.1), ("candidate", .str k.2), ("count", n)]
  | .notProved k s => Json.mkObj [("verdict", "not-proved"), ("part", .str k.1), ("candidate", .str k.2),
      ("status", .str s)]
  | .falsified k => Json.mkObj [("verdict", "falsified"), ("part", .str k.1), ("candidate", .str k.2)]

def rowJson (r : Row) : Json :=
  Json.mkObj [("status", .str r.status), ("fResult", match r.fResult with | some x => .str (fresWord x) | none => .null)]

def verdictJson (ledger : List Row) (f : Flag) : Json :=
  match reasonOf f with
  | some r => Json.mkObj [("verdict", "excluded"), ("reason", .str r)]
  | none => whyJson (why links ledger f)

def decided (reg : List Reg) : List Flag :=
  linkTable.map (·.1) ++
    ((reg.filter fun r => r.kind == .optimized && (linkOf linkTable r.flag).isNone).map (·.flag)).mergeSort
      (fun a b => a.key ≤ b.key)

inductive LookVerdict | kept | rejected | accepted
deriving DecidableEq, Repr

def LookVerdict.word : LookVerdict → String
  | .kept => "kept" | .rejected => "rejected" | .accepted => "accepted"

inductive LookReview | pending | done
deriving DecidableEq, Repr

def LookReview.word : LookReview → String
  | .pending => "pending" | .done => "done"

inductive Ready | ready | pending
deriving DecidableEq, Repr

def Ready.word : Ready → String
  | .ready => "ready" | .pending => "pending"

structure EngineMat where
  state : Ready
  run : Option String := none
  artifact : Option String := none
  expires : Option String := none
  task : Option String := none
deriving DecidableEq, Repr

structure ReviewMaterial where
  chromium : EngineMat
  webkit : EngineMat
deriving DecidableEq, Repr

structure LookDecision where
  flag : Flag
  date : String
  decision : LookVerdict
  review : LookReview
  material : Option ReviewMaterial := none
deriving DecidableEq, Repr

def lookDecisions : List LookDecision :=
  [{ flag := ⟨"nav", "earn-no-transition"⟩, date := "2026-10-21", decision := .kept, review := .pending,
     material := some
       { chromium := { state := .ready, run := some "39473950464", artifact := some "frames-chromium",
                       expires := some "2026-11-19" }
         webkit := { state := .ready, run := some "39530106935", artifact := some "frames-apple-390, frames-apple-1280",
                     expires := some "2026-11-20" } } },
   { flag := ⟨"nav", "earn-logical"⟩, date := "2026-10-25", decision := .accepted, review := .done,
     material := some
       { chromium := { state := .ready, run := some "40100783726, 40102193302",
                       artifact := some "transitions-apple-390, transitions-apple-1280", expires := some "2026-11-23",
                       task := some "earn-logical-proof" }
         webkit := { state := .ready, run := some "40100783726, 40102193302",
                     artifact := some "transitions-apple-390, transitions-apple-1280", expires := some "2026-11-23",
                     task := some "earn-logical-proof" } } },
   { flag := ⟨"hero.accent", "draw-nolayout-full"⟩, date := "2026-10-25", decision := .rejected, review := .done,
     material := some
       { chromium := { state := .pending }
         webkit := { state := .ready, run := some "40030735082, 40035116432",
                     artifact := some "webkit-sim-r1, webkit-sim-r2, webkit-sim-r3", expires := some "2026-11-22",
                     task := some "accent-nolayout-measure" } } },
   { flag := ⟨"hero.exit", "threaded"⟩, date := "2026-10-24", decision := .accepted, review := .done },
   { flag := ⟨"hero.accent", "draw-nolayout"⟩, date := "2026-10-24", decision := .rejected, review := .done }]

def EngineMat.json (m : EngineMat) : Json :=
  Json.mkObj ([("state", .str m.state.word)] ++
    (m.run.map (fun x => [("run", Json.str x)])).getD [] ++
    (m.artifact.map (fun x => [("artifact", Json.str x)])).getD [] ++
    (m.expires.map (fun x => [("expires", Json.str x)])).getD [] ++
    (m.task.map (fun x => [("task", Json.str x)])).getD [])

def LookDecision.json (d : LookDecision) : Json :=
  Json.mkObj [("date", .str d.date), ("decision", .str d.decision.word), ("review", .str d.review.word),
    ("material", match d.material with
      | some m => Json.mkObj [("chromium", m.chromium.json), ("webkit", m.webkit.json)]
      | none => .null)]

def ledgerDisagreements (ledger : Json) (ds : List LookDecision) : List String :=
  let rows := ((ledger.getObjVal? "findings").toOption.bind (·.getArr?.toOption)).getD #[]
  ds.flatMap fun d =>
    match rows.toList.find? (fun r => (r.getObjValAs? String "flag").toOption == some d.flag.key) with
    | none => [s!"{d.flag.key}: no ledger row"]
    | some r =>
      match r.getObjVal? "userDecision" with
      | .error _ => [s!"{d.flag.key}: the ledger row has no userDecision"]
      | .ok u =>
        let text := (u.getObjValAs? String "decision").toOption.getD ""
        let rev := (u.getObjValAs? String "review").toOption.getD ""
        let has (hay needle : String) : Bool := 1 < (hay.splitOn needle).length
        (if (u.getObjValAs? String "date").toOption == some d.date then [] else [s!"{d.flag.key}: date differs"]) ++
        (if d.decision.word.isPrefixOf text then [] else [s!"{d.flag.key}: decision text does not start with {d.decision.word}"]) ++
        (if has text "deferred" == (d.review == .pending) then [] else [s!"{d.flag.key}: deferred does not match the review state"]) ++
        (match d.material with
          | none => []
          | some m =>
            [m.chromium.run, m.chromium.artifact, m.chromium.expires].filterMap fun o =>
              o.bind fun x => if has rev x then none else some s!"{d.flag.key}: review text lacks {x}")

def lookCandidates (reg : List Reg) : List Flag :=
  ((reg.filter fun r => r.visClass == some .l).map (·.flag)).mergeSort fun a b => a.key ≤ b.key

theorem isLook_of_mem_lookCandidates {reg : List Reg} {f : Flag} (h : f ∈ lookCandidates reg) : isLook reg f = true := by
  unfold lookCandidates at h
  obtain ⟨r, hr, rfl⟩ := List.mem_map.1 ((List.mem_mergeSort).1 h)
  simp only [List.mem_filter] at hr
  simp only [isLook, List.any_eq_true, Bool.and_eq_true, beq_iff_eq]
  exact ⟨r, hr.1, rfl, by simpa using hr.2⟩

theorem lookCandidates_not_mem {reg : List Reg} {ledger : List Row} {st : List Stored} {f : Flag}
    (h : f ∈ lookCandidates reg) : f ∉ preset reg links ledger st :=
  look_not_mem (isLook_of_mem_lookCandidates h)

def decisionKept (reg : List Reg) (d : LookDecision) : Bool :=
  (lookCandidates reg).contains d.flag || (d.decision != .kept && reg.any (·.flag == d.flag))

theorem decisionKept_of_candidate {reg : List Reg} {d : LookDecision} (h : d.flag ∈ lookCandidates reg) :
    decisionKept reg d = true := by
  simp [decisionKept, h]

theorem decisionKept_of_settled {reg : List Reg} {d : LookDecision} (hd : d.decision ≠ .kept)
    (hr : ∃ r ∈ reg, r.flag = d.flag) : decisionKept reg d = true := by
  obtain ⟨r, hm, he⟩ := hr
  have hk : (d.decision != .kept) = true := by simpa using hd
  simp only [decisionKept, hk, Bool.or_eq_true, Bool.and_eq_true, true_and, List.any_eq_true, beq_iff_eq]
  exact .inr ⟨r, hm, he⟩

theorem decisionKept_of_rejected {reg : List Reg} {d : LookDecision} (hd : d.decision = .rejected)
    (hr : ∃ r ∈ reg, r.flag = d.flag) : decisionKept reg d = true :=
  decisionKept_of_settled (by simp [hd]) hr

theorem decisionKept_of_accepted {reg : List Reg} {d : LookDecision} (hd : d.decision = .accepted)
    (hr : ∃ r ∈ reg, r.flag = d.flag) : decisionKept reg d = true :=
  decisionKept_of_settled (by simp [hd]) hr

theorem settled_of_decisionKept {reg : List Reg} {d : LookDecision} (h : decisionKept reg d = true)
    (hc : d.flag ∉ lookCandidates reg) : d.decision = .rejected ∨ d.decision = .accepted := by
  simp only [decisionKept, Bool.or_eq_true, Bool.and_eq_true, List.contains_iff_mem] at h
  have hk := (h.resolve_left hc).1
  cases e : d.decision <;> simp_all

theorem not_decisionKept_of_unregistered {reg : List Reg} {d : LookDecision} (h : ∀ r ∈ reg, r.flag ≠ d.flag) :
    decisionKept reg d = false := by
  have hc : d.flag ∉ lookCandidates reg := fun hm => by
    unfold lookCandidates at hm
    obtain ⟨r, hr, he⟩ := List.mem_map.1 ((List.mem_mergeSort).1 hm)
    exact h r (List.mem_filter.1 hr).1 he
  simp only [decisionKept, Bool.or_eq_false_iff, Bool.and_eq_false_iff, List.any_eq_false, beq_iff_eq]
  exact ⟨by simpa using hc, .inr h⟩

def staleIn (reg : List Reg) (ds : List LookDecision) : List Flag :=
  (ds.filter fun d => !decisionKept reg d).map (·.flag)

def staleDecisions (reg : List Reg) : List Flag := staleIn reg lookDecisions

def refusedMembers (ds : List LookDecision) (p : List Flag) : List Flag :=
  ((ds.filter (·.decision == .rejected)).map (·.flag)).filter p.contains

def decisionOf (f : Flag) : Json :=
  match lookDecisions.find? (·.flag == f) with
  | some d => d.json
  | none => .null

def lookJson (reg : List Reg) (p : List Flag) (f : Flag) : Json :=
  let kind : Json := match reg.find? (·.flag == f) with
    | some r => .str (kindWord r.kind)
    | none => .null
  Json.mkObj [("flag", .str f.key), ("kind", kind), ("visClass", .str (visClassWord .l)),
    ("member", .bool (p.contains f)), ("userDecision", decisionOf f)]

def lookText (reg : List Reg) (p : List Flag) : String :=
  String.join ((lookCandidates reg).map fun f => (lookJson reg p f).compress ++ "\n")

def engineWord : Engine → String
  | .chromium => "chromium"
  | .linuxWebkit => "linux-webkit"
  | .macWebkit => "mac-webkit"

def parseEngine : String → Except String Engine
  | "chromium" => .ok .chromium
  | "linux-webkit" => .ok .linuxWebkit
  | "mac-webkit" => .ok .macWebkit
  | s => .error s!"unknown engine {s}"

def walkWord : Walk → String
  | .hero => "hero"
  | .morph => "morph"

def parseWalk : String → Except String Walk
  | "hero" => .ok .hero
  | "morph" => .ok .morph
  | s => .error s!"unknown path {s}"

def familyWord : Family → String
  | .chromium => "chromium"
  | .webkit => "webkit"

def outcomeWord : Outcome → String
  | .pass => "pass"
  | .fail => "fail"
  | .unjudged .coverage => "no verdict: coverage"
  | .unjudged .widths => "no verdict: widths"

def tcellWord : TCell → String
  | .pass => "pass"
  | .fail => "fail"
  | .pending => "pending"

def twhyWord : TWhy → String
  | .pass => "pass"
  | .pending => "pending: trajectory"
  | .falsified => "falsified: trajectory"

def storedJson (s : Stored) : Json :=
  Json.mkObj [("run", .str s.run), ("sha", .str s.sha), ("search", .str s.search), ("flags", toJson s.flags),
    ("engine", .str (engineWord s.engine)), ("path", .str (walkWord s.walk)), ("widths", toJson s.widths),
    ("groups", .arr (s.groups.map fun g => Json.mkObj [("node", .str g.node), ("prop", .str g.prop),
      ("content", toJson g.content), ("coverage", toJson g.coverage)]).toArray)]

def parseStored (j : Json) : Except String Stored := do
  let gs ← (← j.getObjVal? "groups").getArr?
  let groups ← gs.toList.mapM fun g => do
    return ⟨← g.getObjValAs? String "node", ← g.getObjValAs? String "prop", ← g.getObjValAs? (List Nat) "content",
      ← g.getObjValAs? (List Nat) "coverage"⟩
  return { run := ← j.getObjValAs? String "run", sha := ← j.getObjValAs? String "sha",
           search := ← j.getObjValAs? String "search", flags := ← j.getObjValAs? (List String) "flags",
           engine := ← parseEngine (← j.getObjValAs? String "engine"),
           walk := ← parseWalk (← j.getObjValAs? String "path"), widths := ← j.getObjValAs? (List Nat) "widths",
           groups }

def parseStoredText (t : String) : Except String (List Stored) :=
  ((t.splitOn "\n").filter (!·.isEmpty)).mapM fun l => do parseStored (← Json.parse l)

def storedText (st : List Stored) : String :=
  let key (s : Stored) := s.run ++ " " ++ engineWord s.engine ++ " " ++ walkWord s.walk
  String.join ((st.mergeSort fun a b => key a ≤ key b).map fun s => (storedJson s).compress ++ "\n")

def trajJson (st : List Stored) (f : Flag) : Json :=
  let cell (fam : Family) (w : Walk) : Json :=
    Json.mkObj [("family", .str (familyWord fam)), ("path", .str (walkWord w)), ("cell", .str (tcellWord (tcell st f fam w))),
      ("runs", .arr ((runsFor st f fam w).map fun s => Json.mkObj [("run", .str s.run),
        ("engine", .str (engineWord s.engine)), ("alone", .bool (s.flags == [f.key])),
        ("outcome", .str (outcomeWord (outcome s))),
        ("sameByProof", toJson (s.widths.filter fun w => basisAt s.flags w == .sameByProof))]).toArray)]
  Json.mkObj [("verdict", .str (twhyWord (trajWhy st f))),
    ("cells", .arr (families.flatMap fun fam => walks.map (cell fam)).toArray)]

inductive EntryReq | proofs | gate (fam : Family) | look | q6
deriving DecidableEq, Repr

def EntryReq.word : EntryReq → String
  | .proofs => "proofs"
  | .gate fam => "gate " ++ familyWord fam
  | .look => "look"
  | .q6 => "q6 same scroll offset"

def entryReqs : List EntryReq := [.proofs, .gate .chromium, .gate .webkit, .look, .q6]

def q6Answer : Option String := none

def acceptedLook (f : Flag) : Bool := lookDecisions.any fun d => d.flag == f && d.decision == .accepted

def reqMet (ledger : List Row) (st : List Stored) (f : Flag) : EntryReq → Bool
  | .proofs => why links ledger f == .proved
  | .gate fam => walks.all fun w => tcell st f fam w == .pass
  | .look => acceptedLook f
  | .q6 => q6Answer.isSome

def blockers (ledger : List Row) (st : List Stored) (f : Flag) : List EntryReq :=
  entryReqs.filter fun r => !reqMet ledger st f r

inductive Entry | enter | notYet (blockers : List EntryReq)
deriving DecidableEq, Repr

def entry (ledger : List Row) (st : List Stored) (f : Flag) : Entry :=
  if (blockers ledger st f).isEmpty then .enter else .notYet (blockers ledger st f)

theorem entry_enter_iff {ledger : List Row} {st : List Stored} {f : Flag} :
    entry ledger st f = .enter ↔ ∀ r ∈ entryReqs, reqMet ledger st f r = true := by
  have e : (blockers ledger st f).isEmpty = true ↔ ∀ r ∈ entryReqs, reqMet ledger st f r = true := by
    simp [blockers, List.filter_eq_nil_iff]
  unfold entry
  by_cases h : (blockers ledger st f).isEmpty = true
  · simp only [h, ↓reduceIte, true_iff]
    exact e.1 h
  · simp only [h, Bool.false_eq_true, ↓reduceIte, reduceCtorEq, false_iff]
    exact fun h' => h (e.2 h')

theorem entry_notYet_of_unmet {ledger : List Row} {st : List Stored} {f : Flag} {r : EntryReq}
    (hr : r ∈ entryReqs) (hu : reqMet ledger st f r = false) :
    entry ledger st f = .notYet (blockers ledger st f) ∧ r ∈ blockers ledger st f := by
  have hb : r ∈ blockers ledger st f := List.mem_filter.2 ⟨hr, by simp [hu]⟩
  have hne : (blockers ledger st f).isEmpty = false := by
    cases e : blockers ledger st f with
    | nil => simp [e] at hb
    | cons _ _ => rfl
  exact ⟨by simp [entry, hne], hb⟩

theorem ok_of_enter {reg : List Reg} {ledger : List Row} {st : List Stored} {f : Flag}
    (he : entry ledger st f = .enter) (ho : isOpt reg f = true) (hl : isLook reg f = false) :
    ok reg links ledger st f = true := by
  have h := entry_enter_iff.1 he
  have hp : why links ledger f = .proved := by simpa [reqMet] using h .proofs (by simp [entryReqs])
  have hg : ∀ fam ∈ families, ∀ w ∈ walks, tcell st f fam w = .pass := by
    intro fam hf w hw
    have hfam : fam = .chromium ∨ fam = .webkit := by simpa [families] using hf
    have hm := h (.gate fam) (by rcases hfam with rfl | rfl <;> simp [entryReqs])
    simp only [reqMet, List.all_eq_true, beq_iff_eq] at hm
    exact hm w hw
  simp [ok, ho, hl, hp, trajWhy_pass_iff.2 hg]

def heroExitThreaded : Flag := ⟨"hero.exit", "threaded"⟩

theorem q6_open {ledger : List Row} {st : List Stored} {f : Flag} :
    entry ledger st f = .notYet (blockers ledger st f) ∧ .q6 ∈ blockers ledger st f :=
  entry_notYet_of_unmet (by simp [entryReqs]) rfl

theorem threaded_look_met {ledger : List Row} {st : List Stored} : reqMet ledger st heroExitThreaded .look = true := by
  simp only [reqMet]
  decide

theorem threaded_unlinked : linkOf links heroExitThreaded = none := by
  decide

theorem threaded_proofs_unmet {ledger : List Row} {st : List Stored} :
    reqMet ledger st heroExitThreaded .proofs = false := by
  simp only [reqMet, why, threaded_unlinked, beq_eq_false_iff_ne, ne_eq]
  split <;> simp

theorem threaded_not_yet {ledger : List Row} {st : List Stored} :
    entry ledger st heroExitThreaded = .notYet (blockers ledger st heroExitThreaded) ∧
      .q6 ∈ blockers ledger st heroExitThreaded ∧ .proofs ∈ blockers ledger st heroExitThreaded ∧
      .look ∉ blockers ledger st heroExitThreaded :=
  ⟨q6_open.1, q6_open.2, (entry_notYet_of_unmet (by simp [entryReqs]) threaded_proofs_unmet).2,
    fun h => by simp [blockers, threaded_look_met] at h⟩

/-- A failing run of the flag alone on one path of a family leaves that family's gate unmet and a blocker. -/
theorem gate_blocked_of_own_fail {ledger : List Row} {st : List Stored} {f : Flag} {fam : Family} {w : Walk}
    {s : Stored} (hw : w ∈ walks) (hs : s ∈ runsFor st f fam w) (ho : s.flags = [f.key])
    (hf : outcome s = .fail) :
    reqMet ledger st f (.gate fam) = false ∧ .gate fam ∈ blockers ledger st f := by
  have hu : reqMet ledger st f (.gate fam) = false := by
    simp only [reqMet, List.all_eq_false, beq_iff_eq]
    exact ⟨w, hw, by simp [tcell_own_fail hs ho hf]⟩
  have hr : EntryReq.gate fam ∈ entryReqs := by cases fam <;> simp [entryReqs]
  exact ⟨hu, (entry_notYet_of_unmet hr hu).2⟩

def threadedEvidence (st : List Stored) : EntryReq → String
  | .proofs => "Fw.Parts.HeroExitOpt.consumer_eq_s (E-s under the hypothesis RG11), cr_real_tradeE and wk_tradeE (a \
      trade); ledger row hero-exit-threaded (v6, KD#2) is partly-proved and Gen.linkTable has no link"
  | .gate fam =>
    let cell (w : Walk) : String :=
      let runs := (runsFor st heroExitThreaded fam w).map fun s =>
        "run " ++ s.run ++ " " ++ engineWord s.engine ++ " " ++ outcomeWord (outcome s)
      walkWord w ++ " " ++ tcellWord (tcell st heroExitThreaded fam w) ++
        (if runs.isEmpty then " (no stored run)" else " (" ++ ", ".intercalate runs ++ ")")
    "trajectory " ++ "; ".intercalate (walks.map cell) ++ "; PathPix runs 39924527942 and 39929556147 grade every \
      valid P cell L (research/notes/2026/10-2x-hero-exit-threaded-pix.md)"
  | .look => "accepted 2026-10-24 on the real iPhone (results/phone/2026-10-24-hero-exit-threaded/summary.md)"
  | .q6 => q6Answer.getD "open: no answer recorded; Fw.Engine.Visual.PathPremises.c3o and c3v (each arm shows its own \
      value at its own frame time) are hypotheses, and Fw.Parts.HeroExitOpt does not model which scroll offset the \
      compositor shows"

def entryWord : Entry → String
  | .enter => "enter"
  | .notYet _ => "not yet"

def entryJson (ledger : List Row) (st : List Stored) (f : Flag) : Json :=
  if f != heroExitThreaded then .null else
  Json.mkObj [("decision", .str (entryWord (entry ledger st f))),
    ("blockers", .arr ((blockers ledger st f).map (.str ·.word)).toArray),
    ("requirements", .arr (entryReqs.map fun r => Json.mkObj [("req", .str r.word),
      ("met", .bool (reqMet ledger st f r)), ("evidence", .str (threadedEvidence st r))]).toArray)]

def decision (reg : List Reg) (ledger : List Row) (st : List Stored) (f : Flag) : Json :=
  let p := preset reg links ledger st
  let fs := links.map (·.1)
  let shadow : Json := if ok reg links ledger st f && !p.contains f then
      match firstOk (ok reg links ledger st) fs f.part with
      | some g => .str g.key
      | none => .null
    else .null
  let rows := ((linkOf linkTable f).getD []).map fun k =>
    Json.mkObj [("part", .str k.1), ("candidate", .str k.2), ("found", .arr ((rowsOf ledger k).map rowJson).toArray)]
  Json.mkObj [("flag", .str f.key), ("registered", .bool (isOpt reg f)), ("why", verdictJson ledger f),
    ("trajectory", trajJson st f), ("member", .bool (p.contains f)), ("shadowedBy", shadow),
    ("rows", .arr rows.toArray), ("flagRows", .arr ((ledger.filter (·.flag == some f.key)).map rowJson).toArray),
    ("userDecision", decisionOf f), ("entry", entryJson ledger st f)]

def decisionsText (reg : List Reg) (ledger : List Row) (st : List Stored) : String :=
  String.join ((decided reg).map fun f => (decision reg ledger st f).compress ++ "\n")

def ledgerPath : System.FilePath := ".." / "research" / "findings" / "ledger.json"
def partsDir : System.FilePath := ".." / "apps" / "site" / "src" / "parts"
def goldenPreset : System.FilePath := ".." / "packages" / "contracts" / "golden" / "preset" / "v2-proved.json"
def goldenDecisions : System.FilePath :=
  ".." / "packages" / "contracts" / "golden" / "preset" / "v2-proved.decisions.jsonl"
def goldenLook : System.FilePath :=
  ".." / "packages" / "contracts" / "golden" / "preset" / "look-change.candidates.jsonl"
def sitePreset : System.FilePath := ".." / "apps" / "site" / "src" / "registry" / "presets" / "v2-proved.json"
def storedPath : System.FilePath :=
  ".." / "packages" / "contracts" / "golden" / "preset" / "v2-proved.trajectory.jsonl"

def readStored : IO (List Stored) := do
  IO.ofExcept ((parseStoredText (← IO.FS.readFile storedPath)).mapError fun e => s!"{storedPath}: {e}")

def readJson (p : System.FilePath) : IO Json := do
  IO.ofExcept ((Json.parse (← IO.FS.readFile p)).mapError fun e => s!"{p}: {e}")

def readRegistry : IO (List Reg) := do
  let ds := (← partsDir.readDir).qsort (·.fileName < ·.fileName)
  let mut out : List Reg := []
  for d in ds do
    let pj := d.path / "part.json"
    if ← pj.pathExists then
      out := out ++ (← IO.ofExcept ((parsePart (← readJson pj)).mapError fun e => s!"{pj}: {e}"))
  return out

/-- Write the four preset files, or with `--check` throw when any differs from the Lean output. -/
def run (args : List String) : IO Unit := do
  let ledger ← IO.ofExcept ((parseLedger (← readJson ledgerPath)).mapError fun e => s!"{ledgerPath}: {e}")
  let reg ← readRegistry
  let st ← readStored
  let p ← IO.ofExcept (generate reg links ledger st)
  let bad := ledgerDisagreements (← readJson ledgerPath) lookDecisions
  unless bad.isEmpty do throw (IO.userError s!"the ledger text disagrees with Gen.lookDecisions: {bad}")
  unless (staleDecisions reg).isEmpty do
    throw (IO.userError s!"look decisions name no look-change candidate and no refused registered flag: {(staleDecisions reg).map (·.key)}")
  unless (refusedMembers lookDecisions p).isEmpty do
    throw (IO.userError s!"refused flags in v2-proved: {(refusedMembers lookDecisions p).map (·.key)}")
  let outs := [(goldenPreset, presetText p), (sitePreset, presetText p),
    (goldenDecisions, decisionsText reg ledger st), (goldenLook, lookText reg p)]
  if args.contains "--check" then
    let mut stale : List String := []
    for (path, text) in outs do
      let cur ← try IO.FS.readFile path catch _ => pure ""
      if cur != text then stale := stale ++ [path.toString]
    unless stale.isEmpty do
      throw (IO.userError s!"v2-proved: stale {stale}; regenerate with Fw.Preset.Gen.run []")
    IO.println s!"v2-proved: up to date, {p.length} flags: {p.map (·.key)}"
  else
    for (path, text) in outs do
      IO.FS.createDirAll (path.parent.getD ".")
      IO.FS.writeFile path text
    IO.println s!"v2-proved: written, {p.length} flags: {p.map (·.key)}"

def engineOfArtifact : String → Except String Engine
  | "trajectory-chromium" => .ok .chromium
  | "trajectory-playwright-webkit" => .ok .linuxWebkit
  | "trajectory-apple" => .ok .macWebkit
  | s => .error s!"unknown trajectory artifact {s}"

def unitsName : Engine → String
  | .chromium => "units-chromium.json"
  | _ => "units-playwright-webkit.json"

def flagsOfSearch (search : String) (presetKeys : Option (List String)) : Except String (List String) := do
  let ks ← if search.startsWith "?fw=" then
      ((search.drop 4).toString.splitOn ",").mapM fun k => do pure (← parseFlag k).key
    else if search.startsWith "?preset=" && !(search.drop 8).toString.contains '&' then
      match presetKeys with
      | some ks => pure ks
      | none => throw s!"search {search} needs the preset file of the run's commit"
    else throw s!"search {search} is neither ?fw= nor ?preset="
  if ks.isEmpty then throw s!"search {search} names no flag" else pure ks

def presetKeys (j : Json) : Except String (List String) := do
  unless (← j.getObjValAs? String "extends") == "original" do throw "preset does not extend original"
  let fw ← (← j.getObjVal? "fw").getObj?
  let ks ← fw.toList.mapM fun ((p, v) : String × Json) => do pure (p ++ ":" ++ (← v.getStr?))
  pure (ks.mergeSort (· ≤ ·))

def parseUnit (j : Json) : Except String UnitRow := do
  return { width := ← j.getObjValAs? Nat "width", walk := ← j.getObjValAs? String "path",
           node := ← j.getObjValAs? String "node", prop := ← j.getObjValAs? String "prop",
           coverage := (← j.getObjValAs? String "verdict") == "fail:coverage",
           isNew := (← j.getObjValAs? String "rel") == "new" }

def storedOf (run sha : String) (e : Engine) (presetKeys : Option (List String)) (j : Json) :
    Except String (List Stored) := do
  if ← j.getObjValAs? Bool "refused" then throw s!"run {run} {engineWord e} was refused"
  let search ← j.getObjValAs? String "search"
  let flags ← flagsOfSearch search presetKeys
  let us ← (← (← j.getObjVal? "units").getArr?).toList.mapM parseUnit
  return [Walk.hero, .morph].filterMap fun w =>
    if us.any (·.walk == walkWord w) then
      some { run, sha, search, flags, engine := e, walk := w, widths := widthsOf (walkWord w) us,
             groups := groupsOf (walkWord w) us }
    else none

def merge (old new : List Stored) : List Stored :=
  old.filter (fun s => !new.any fun n => n.run == s.run && n.engine == s.engine && n.walk == s.walk) ++ new

def record (args : List String) : IO Unit := do
  let (run, sha, pf, dirs) ← match args with
    | r :: s :: p :: d :: ds => pure (r, s, p, d :: ds)
    | _ => throw (IO.userError "usage: record [run, sha, presetFile or -, artifactDir...]")
  unless !run.isEmpty && run.all Char.isDigit do throw (IO.userError s!"bad run id {run}")
  unless sha.length == 40 && sha.all fun c => c.isDigit || ('a' ≤ c && c ≤ 'f') do
    throw (IO.userError s!"bad sha {sha}")
  let keys ← if pf == "-" then pure none else some <$> IO.ofExcept (presetKeys (← readJson pf))
  let mut new : List Stored := []
  for d in dirs do
    let dir : System.FilePath := d
    let e ← IO.ofExcept (engineOfArtifact (dir.fileName.getD ""))
    let j ← readJson (dir / unitsName e)
    new := new ++ (← IO.ofExcept ((storedOf run sha e keys j).mapError fun m => s!"{dir}: {m}"))
  IO.FS.writeFile storedPath (storedText (merge (← readStored) new))
  for s in new do
    IO.println s!"record: run {s.run} {engineWord s.engine} {walkWord s.walk}: {outcomeWord (outcome s)}"

#guard (parseFlag "nav.hitTest:hit-skip").toOption == some ⟨"nav.hitTest", "hit-skip"⟩
#guard (parseFlag "nav.hitTest").toOption.isNone
#guard (parseFlag "a:b:c").toOption.isNone
#guard (parseFlag ":b").toOption.isNone
#guard (parseKind "optimized").toOption == some .optimized
#guard (parseKind "Optimized").toOption.isNone
#guard (parseFRes "model-bug").toOption == some .modelBug
#guard (parseFRes "falsified").toOption.isNone
#guard (parseRow (Json.mkObj [("part", "a"), ("candidate", "c"), ("status", "proved")])).toOption.map (·.fResult)
  == some none
#guard (parseRow (Json.mkObj [("part", "a"), ("candidate", "c"), ("status", "proved"), ("fResult", "model-bug"),
  ("flag", "a:x")])).toOption.map (fun r => (r.flag, r.fResult)) == some (some "a:x", some .modelBug)
#guard (parseRow (Json.mkObj [("part", "a"), ("candidate", "c"), ("status", "proved"), ("fResult", "bug")])).toOption.isNone
#guard (parseRow (Json.mkObj [("part", "a"), ("status", "proved")])).toOption.isNone
#guard ((parsePart (Json.mkObj [("id", "m"), ("variants", Json.mkObj [("faithful", Json.mkObj [("kind", "faithful")]),
    ("s", Json.mkObj [("kind", "optimized")])]), ("requires", Json.mkObj [("m:s", Json.arr #["h:s"])]),
    ("conflicts", Json.mkObj [])])).toOption.map fun rs => rs.map fun r => (r.flag.key, r.requires.map (·.key)))
  == some [("m:faithful", []), ("m:s", ["h:s"])]
#guard presetText [⟨"b", "x"⟩, ⟨"a", "y"⟩] == "{\"extends\":\"original\",\"fw\":{\"a\":\"y\",\"b\":\"x\"},\"name\":\"v2-proved\"}\n"
#guard (reasonOf ⟨"hero.countdown", "strip"⟩).isNone
#guard (reasonOf ⟨"morph.countdown", "strip"⟩).isNone
#guard (reasonOf ⟨"hero.accent", "steps"⟩).isSome
#guard (reasonOf ⟨"morph.countdown", "hidden-pause"⟩).isNone
#guard (reasonOf ⟨"hero.countdown", "hidden-pause"⟩).isNone
#guard links.map (·.1.key) == ["engine.scroll:batched", "nav.hitTest:elements-skip", "nav.hitTest:hit-skip",
  "hero.countdown:strip", "morph.countdown:strip", "morph.countdown:hidden-pause", "morph.columns:hidden-pause", "engine.scene:hidden-pause", "morph.mount:shift",
  "morph.tween:waapi", "pain.notes:visible", "people.card:mq", "hero.exit:scoped", "engine.scroll:unthrottle"]
#guard ((verdictJson [] ⟨"hero.accent", "steps"⟩).getObjValAs? String "verdict").toOption == some "excluded"
#guard ((verdictJson [] ⟨"hero.countdown", "strip"⟩).getObjValAs? String "verdict").toOption == some "row-count"
#guard ((verdictJson [] ⟨"morph.countdown", "hidden-pause"⟩).getObjValAs? String "verdict").toOption == some "row-count"
#guard presetText [] == "{\"extends\":\"original\",\"fw\":{},\"name\":\"v2-proved\"}\n"
#guard (parseVisClass "L").toOption == some .l
#guard (parseVisClass "E-s").toOption == some .eS
#guard (parseVisClass "l").toOption.isNone
#guard ((parsePart (Json.mkObj [("id", "m"), ("variants", Json.mkObj [("s", Json.mkObj [("kind", "proposal"),
    ("visClass", "L")])])])).toOption.map fun rs => rs.map (·.visClass)) == some [some .l]
#guard ((parsePart (Json.mkObj [("id", "m"), ("variants", Json.mkObj [("s", Json.mkObj [("kind", "optimized")])])])).toOption.map
    fun rs => rs.map (·.visClass)) == some [none]
#guard (parsePart (Json.mkObj [("id", "m"), ("variants", Json.mkObj [("s", Json.mkObj [("kind", "optimized"),
    ("visClass", "L")])])])).toOption.isNone
#guard (parsePart (Json.mkObj [("id", "m"), ("variants", Json.mkObj [("s", Json.mkObj [("kind", "proposal"),
    ("visClass", "X")])])])).toOption.isNone
#guard lookCandidates [{ flag := ⟨"n", "b"⟩, kind := .proposal, requires := [], conflicts := [], visClass := some .l },
    { flag := ⟨"n", "a"⟩, kind := .proposal, requires := [], conflicts := [], visClass := some .l },
    { flag := ⟨"n", "c"⟩, kind := .optimized, requires := [], conflicts := [], visClass := some .q }] ==
  [⟨"n", "a"⟩, ⟨"n", "b"⟩]
private def earnReg : Reg :=
  { flag := ⟨"nav", "earn-no-transition"⟩, kind := .proposal, requires := [], conflicts := [], visClass := some .l }

private def earnLogicalReg : Reg :=
  { flag := ⟨"nav", "earn-logical"⟩, kind := .proposal, requires := [], conflicts := [], visClass := some .l }

private def accentFullReg : Reg :=
  { flag := ⟨"hero.accent", "draw-nolayout-full"⟩, kind := .optimized, requires := [], conflicts := [], visClass := none }

private def threadedReg : Reg :=
  { flag := ⟨"hero.exit", "threaded"⟩, kind := .optimized, requires := [], conflicts := [], visClass := none }

private def accentReg : Reg :=
  { flag := ⟨"hero.accent", "draw-nolayout"⟩, kind := .optimized, requires := [], conflicts := [], visClass := none }

#guard staleDecisions [] == [⟨"nav", "earn-no-transition"⟩, ⟨"nav", "earn-logical"⟩, ⟨"hero.accent", "draw-nolayout-full"⟩,
  ⟨"hero.exit", "threaded"⟩, ⟨"hero.accent", "draw-nolayout"⟩]
#guard staleDecisions [earnReg, earnLogicalReg] == [⟨"hero.accent", "draw-nolayout-full"⟩, ⟨"hero.exit", "threaded"⟩,
  ⟨"hero.accent", "draw-nolayout"⟩]
#guard staleDecisions [earnReg, earnLogicalReg, accentFullReg, accentReg] == [⟨"hero.exit", "threaded"⟩]
#guard staleDecisions [earnReg, earnLogicalReg, accentFullReg, threadedReg, accentReg] == []
#guard staleIn [{ earnReg with visClass := none }] (lookDecisions.take 1) == [⟨"nav", "earn-no-transition"⟩]
#guard staleIn [accentFullReg] ((lookDecisions.drop 2).take 1) == []
#guard staleIn [accentFullReg] (((lookDecisions.drop 2).take 1).map fun d => { d with decision := .kept }) ==
  [⟨"hero.accent", "draw-nolayout-full"⟩]
#guard staleIn [threadedReg] ((lookDecisions.drop 3).take 1) == []
#guard staleIn [threadedReg] (((lookDecisions.drop 3).take 1).map fun d => { d with decision := .kept }) ==
  [⟨"hero.exit", "threaded"⟩]
#guard refusedMembers lookDecisions [] == []
#guard refusedMembers lookDecisions [⟨"hero.accent", "draw-nolayout-full"⟩, ⟨"nav", "earn-logical"⟩] ==
  [⟨"hero.accent", "draw-nolayout-full"⟩]
#guard refusedMembers lookDecisions [⟨"nav", "earn-logical"⟩, ⟨"nav", "earn-no-transition"⟩] == []
#guard decisionOf ⟨"x", "y"⟩ == .null
#guard ((decisionOf ⟨"hero.accent", "draw-nolayout-full"⟩).getObjValAs? String "decision").toOption == some "rejected"
#guard lookText [earnReg] [] ==
  "{\"flag\":\"nav:earn-no-transition\",\"kind\":\"proposal\",\"member\":false,\"userDecision\":{\"date\":\"2026-10-21\",\"decision\":\"kept\",\"material\":{\"chromium\":{\"artifact\":\"frames-chromium\",\"expires\":\"2026-11-19\",\"run\":\"39473950464\",\"state\":\"ready\"},\"webkit\":{\"artifact\":\"frames-apple-390, frames-apple-1280\",\"expires\":\"2026-11-20\",\"run\":\"39530106935\",\"state\":\"ready\"}},\"review\":\"pending\"},\"visClass\":\"L\"}\n"
#guard (ledgerDisagreements (Json.mkObj [("findings", .arr #[Json.mkObj [("flag", .str "nav:earn-no-transition"),
  ("userDecision", Json.mkObj [("date", .str "2026-10-21"), ("decision", .str "kept 2026-10-21; visual review deferred"),
    ("review", .str "CI run 39473950464 artifact frames-chromium (expires 2026-11-19)")])]])]) (lookDecisions.take 1)).isEmpty
#guard (ledgerDisagreements (Json.mkObj [("findings", .arr #[Json.mkObj [("flag", .str "nav:earn-no-transition"),
  ("userDecision", Json.mkObj [("date", .str "2026-10-21"), ("decision", .str "accepted"),
    ("review", .str "x")])]])]) (lookDecisions.take 1)).length == 5
#guard (ledgerDisagreements (Json.mkObj [("findings", .arr #[])]) lookDecisions).length == 5
#guard (ledgerDisagreements (Json.mkObj [("findings", .arr #[Json.mkObj [("flag", .str "nav:earn-logical"),
  ("userDecision", Json.mkObj [("date", .str "2026-10-25"), ("decision", .str "accepted 2026-10-25"),
    ("review", .str "runs 40100783726, 40102193302 artifacts transitions-apple-390, transitions-apple-1280 (expire 2026-11-23)")])]])])
    ((lookDecisions.drop 1).take 1)).isEmpty
#guard (ledgerDisagreements (Json.mkObj [("findings", .arr #[Json.mkObj [("flag", .str "hero.accent:draw-nolayout-full"),
  ("userDecision", Json.mkObj [("date", .str "2026-10-25"), ("decision", .str "rejected 2026-10-25: refused in chat"),
    ("review", .str "runs 40030735082, 40035116432")])]])]) ((lookDecisions.drop 2).take 1)).isEmpty
#guard (ledgerDisagreements (Json.mkObj [("findings", .arr #[Json.mkObj [("flag", .str "hero.accent:draw-nolayout-full"),
  ("userDecision", Json.mkObj [("date", .str "2026-10-24"), ("decision", .str "rejected; review deferred"),
    ("review", .str "")])]])]) ((lookDecisions.drop 2).take 1)).length == 2
#guard ((lookJson [] [] ⟨"x", "y"⟩).getObjVal? "userDecision").toOption == some .null

private def stEx : Stored :=
  ⟨"7", "s", "?fw=a:x", ["a:x"], .macWebkit, .morph, [390, 641], [⟨"nav", "opacity", [390], [641]⟩]⟩
private def stBad : Stored :=
  { stEx with engine := .chromium, widths := Fw.Gate.Trajectory.allowedWidths,
              groups := [⟨"nav", "opacity", [390, 641], []⟩] }
private def unitJ (w : Nat) (p v r : String) : Json :=
  Json.mkObj [("width", w), ("path", .str p), ("node", "nav"), ("prop", "opacity"), ("verdict", .str v), ("rel", .str r)]
private def unitsJ (refused : Bool) (search : String) : Json :=
  Json.mkObj [("refused", .bool refused), ("search", .str search), ("units", .arr #[unitJ 390 "morph" "pass" "new",
    unitJ 641 "morph" "fail:coverage" "new", unitJ 641 "morph" "pass" "ok", unitJ 390 "hero" "pass" "ok"])]

#guard (parseStoredText (storedText [stEx, { stEx with run := "6" }])).toOption == some [{ stEx with run := "6" }, stEx]
#guard (parseStoredText "{\"run\":\"1\"}\n").toOption.isNone
#guard (parseEngine "apple").toOption.isNone
#guard (parseWalk "exit").toOption.isNone
#guard (engineOfArtifact "trajectory-apple").toOption == some .macWebkit
#guard (engineOfArtifact "telemetry-site").toOption.isNone
#guard (flagsOfSearch "?fw=a:x,b:y" none).toOption == some ["a:x", "b:y"]
#guard (flagsOfSearch "?fw=a" none).toOption.isNone
#guard (flagsOfSearch "" none).toOption.isNone
#guard (flagsOfSearch "?preset=v2-proved" none).toOption.isNone
#guard (flagsOfSearch "?preset=v2-proved" (some ["a:x"])).toOption == some ["a:x"]
#guard (flagsOfSearch "?preset=v2-proved" (some [])).toOption.isNone
#guard (flagsOfSearch "?preset=v2-proved&fw=b:y" (some ["a:x"])).toOption.isNone
#guard (presetKeys (Json.mkObj [("extends", "original"), ("fw", Json.mkObj [("b", "y"), ("a", "x")])])).toOption ==
  some ["a:x", "b:y"]
#guard (presetKeys (Json.mkObj [("extends", "v2-proved"), ("fw", Json.mkObj [])])).toOption.isNone
#guard (storedOf "7" "s" .chromium none (unitsJ true "?fw=a:x")).toOption.isNone
#guard ((storedOf "7" "s" .chromium none (unitsJ false "?fw=a:x")).toOption.map fun l => l.map fun s =>
  (walkWord s.walk, s.widths, s.groups)) ==
  some [("hero", [390], []), ("morph", [390, 641], [⟨"nav", "opacity", [390], [641]⟩])]
#guard (merge [stEx, { stEx with walk := .hero }] [{ stEx with groups := [] }]).map (·.groups.length) == [1, 0]
#guard ((trajJson [stEx] ⟨"a", "x"⟩).getObjValAs? String "verdict").toOption == some "pending: trajectory"
#guard ((trajJson [stBad] ⟨"a", "x"⟩).getObjValAs? String "verdict").toOption == some "falsified: trajectory"

private def stPass (e : Engine) (w : Walk) : Stored :=
  ⟨"9", "s", "?fw=hero.exit:threaded", ["hero.exit:threaded"], e, w, Fw.Gate.Trajectory.allowedWidths, []⟩

private def stFail (e : Engine) : Stored :=
  ⟨"9", "s", "?fw=hero.exit:threaded", ["hero.exit:threaded"], e, .hero, Fw.Gate.Trajectory.allowedWidths,
    [{ node := "hero.deck.card", prop := "opacity", content := [640, 641, 1280], coverage := [] }]⟩

#guard outcome (stFail .chromium) == .fail
#guard entry [] [] heroExitThreaded == .notYet [.proofs, .gate .chromium, .gate .webkit, .q6]
#guard outcome (stPass .chromium .hero) == .pass
#guard blockers [] ([Engine.chromium, .macWebkit].flatMap fun e => walks.map (stPass e)) heroExitThreaded == [.proofs, .q6]
#guard blockers [] [stPass .chromium .hero, stPass .chromium .morph] heroExitThreaded == [.proofs, .gate .webkit, .q6]
#guard blockers [] [] ⟨"nav", "earn-logical"⟩ == [.proofs, .gate .chromium, .gate .webkit, .q6]
#guard blockers [] [] ⟨"hero.accent", "draw-nolayout"⟩ == [.proofs, .gate .chromium, .gate .webkit, .look, .q6]
#guard entryJson [] [] ⟨"hero.accent", "draw-nolayout"⟩ == .null
#guard ((entryJson [] [] heroExitThreaded).getObjValAs? String "decision").toOption == some "not yet"
#guard ((entryJson [] [] heroExitThreaded).getObjValAs? (List String) "blockers").toOption ==
  some ["proofs", "gate chromium", "gate webkit", "q6 same scroll offset"]
#guard threadedEvidence [] (.gate .webkit) |>.startsWith "trajectory hero pending (no stored run); morph pending (no stored run)"
#guard threadedEvidence [stPass .macWebkit .hero] (.gate .webkit) |>.startsWith
  "trajectory hero pass (run 9 mac-webkit pass); morph pending"
#guard threadedEvidence [stFail .linuxWebkit, stFail .macWebkit] (.gate .webkit) |>.startsWith
  "trajectory hero fail (run 9 linux-webkit fail, run 9 mac-webkit fail); morph pending"
#guard blockers [] (stFail .chromium :: [Engine.chromium, .macWebkit].flatMap fun e => walks.map (stPass e))
  heroExitThreaded == [.proofs, .gate .chromium, .q6]
#guard refusedMembers lookDecisions [⟨"hero.accent", "draw-nolayout"⟩, ⟨"hero.exit", "threaded"⟩] ==
  [⟨"hero.accent", "draw-nolayout"⟩]
#guard (ledgerDisagreements (Json.mkObj [("findings", .arr #[Json.mkObj [("flag", .str "hero.exit:threaded"),
  ("userDecision", Json.mkObj [("date", .str "2026-10-24"), ("decision", .str "accepted 2026-10-24: same look"),
    ("review", .str "results/phone/2026-10-24-hero-exit-threaded/summary.md")])]])]) ((lookDecisions.drop 3).take 1)).isEmpty
#guard (ledgerDisagreements (Json.mkObj [("findings", .arr #[Json.mkObj [("flag", .str "hero.exit:threaded"),
  ("userDecision", Json.mkObj [("date", .str "2026-10-24"), ("decision", .str "kept; review deferred"),
    ("review", .str "")])]])]) ((lookDecisions.drop 3).take 1)).length == 2

end Fw.Preset.Gen
