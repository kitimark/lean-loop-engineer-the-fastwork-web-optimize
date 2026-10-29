import Lean.Data.Json
import Fw.Preset.V2Proved
import Fw.Preset.Shipped
import Fw.Parts.HeroExitScrollOffset
import Fw.Parts.HeroExitWork
import Fw.Parts.PlatformGlintHold
/-!
Generates the `v2-proved` and `shipped` presets and their decision rows from the findings ledger and `part.json` files.
Run from `lean/`: `printf 'import Fw.Preset.Gen\n#eval Fw.Preset.Gen.run ["--check"]\n' | lake env lean --stdin` (drop `--check` to write).
-/
namespace Fw.Preset.Gen
open Lean Fw.Preset
open Fw.Gate.Trajectory (Stored Engine Walk Family Group Outcome Unjudged UnitRow outcome basisAt groupsOf widthsOf)

def threadedKey : Key := ("hero.exit",
  "hero-exit-threaded (v6, KD#2): JS --exit-opacity writer → per-consumer CSS scroll-driven animations, plus an IO \
    sentinel for pointer-events")

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
  let ksp : Key := ("hero",
    "hero:scene-pause: port the original paused-scene rule to the hero track (will-change auto and animations paused \
      while the scene is far off-screen), so WebKit stops keeping the hero layers composited at the end of the page")
  let khf : Key := ("platform.glint",
    "platform.glint:hold-freeze: each glint dash's two repeating <animate> (x1, x2 over 5 s) become a ring of five pieces \
      per attribute with fill=freeze, an <animate> ramp where the value moves and a <set> where it holds, so no non-<set> \
      animation is active in the hold segments (left [1,2,4], right [0,3,4])")
  let kel : Key := ("nav",
    "nav:earn-logical: the earn button's transition lists padding-inline-start and padding-inline-end in place of the \
      padding-inline shorthand, so WebKit starts a side-padding transition at every hero-pill flip")
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
   (⟨"engine.scroll", "unthrottle"⟩, [kut]),
   (⟨"hero", "scene-pause"⟩, [ksp]),
   (⟨"platform.glint", "hold-freeze"⟩, [khf]),
   (⟨"hero.exit", "threaded"⟩, [threadedKey]),
   (⟨"nav", "earn-logical"⟩, [kel])]

inductive Exclusion where
  | hand (reason : String)
  | resourceTrade

def Exclusion.text : Exclusion → String
  | .hand s => s
  | .resourceTrade => "the decided resource verdict (Fw.Engine.Resource.Flags.decided) is a trade on every engine \
      (#guard in Fw.Engine.Resource.Preset)"

def curated : List (Flag × Exclusion) :=
  [(⟨"hero.accent", "steps"⟩, .hand
    "ledger n = 15: a trade on Chromium and no win on WebKit (INFERRED); a follow-up makes the generator require an \
      engine-win field"),
   (⟨"morph.panel", "rest"⟩, .resourceTrade)]

def reasonOf (f : Flag) : Option String := (curated.find? (·.1 == f)).map (·.2.text)

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

theorem panel_rest_not_mem {reg : List Reg} {ledger : List Row} {st : List Stored} :
    (⟨"morph.panel", "rest"⟩ : Flag) ∉ preset reg links ledger st :=
  curated_not_mem (by simp [reasonOf, curated])

def parseFlag (s : String) : Except String Flag :=
  match s.splitOn ":" with
  | [p, v] => if p.isEmpty || v.isEmpty then .error s!"bad flag {s}" else .ok ⟨p, v⟩
  | _ => .error s!"bad flag {s}"

def parseKind : String → Except String Kind
  | "faithful" => .ok .faithful
  | "optimized" => .ok .optimized
  | "ablation" => .ok .ablation
  | "proposal" => .ok .proposal
  | "probe" => .ok .probe
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
  | .probe => "probe"

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
  let vc ← match ← optStr j "visClass" with
    | none => pure none
    | some s => some <$> parseVisClass s
  return { part := ← j.getObjValAs? String "part", candidate := ← j.getObjValAs? String "candidate",
           status := ← j.getObjValAs? String "status", flag := ← optStr j "flag", fResult := fr, visClass := vc }

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
    if kind == .probe && vc.isSome then throw s!"{f.key}: a probe is measurement only and carries no look class"
    return { flag := f, kind, requires := ← rel "requires" f.key, conflicts := ← rel "conflicts" f.key, visClass := vc }

def namedPresetText (name : String) (p : List Flag) : String :=
  (Json.mkObj [("name", .str name), ("extends", "original"),
    ("fw", Json.mkObj (p.map fun f => (f.part, .str f.variant)))]).compress ++ "\n"

def presetText (p : List Flag) : String := namedPresetText "v2-proved" p

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

def flagRows (ledger : List Row) (f : Flag) : List Row := ledger.filter (·.flag == some f.key)

inductive ClassIssue where
  | noRow
  | rowCount (n : Nat)
  | differs (row : Option VisClass) (part : VisClass)
deriving DecidableEq, Repr

def ClassIssue.text (f : Flag) : ClassIssue → String
  | .noRow => s!"{f.key}: no ledger row has this flag"
  | .rowCount n => s!"{f.key}: {n} ledger rows have this flag"
  | .differs row c =>
    s!"{f.key}: the ledger row has visClass {(row.map visClassWord).getD "none"}, part.json has {visClassWord c}"

def classIssue (ledger : List Row) (r : Reg) : Option ClassIssue :=
  match r.visClass with
  | none => none
  | some c =>
    match flagRows ledger r.flag with
    | [] => some .noRow
    | [x] => if x.visClass = some c then none else some (.differs x.visClass c)
    | rs => some (.rowCount rs.length)

def classDisagreements (reg : List Reg) (ledger : List Row) : List String :=
  reg.filterMap fun r => (classIssue ledger r).map (·.text r.flag)

def ClassAgrees (ledger : List Row) (r : Reg) : Prop :=
  ∀ c, r.visClass = some c → ∃ x, flagRows ledger r.flag = [x] ∧ x.visClass = some c

theorem classIssue_eq_none_iff {ledger : List Row} {r : Reg} : classIssue ledger r = none ↔ ClassAgrees ledger r := by
  unfold classIssue ClassAgrees
  cases hv : r.visClass with
  | none => simp
  | some c =>
    simp only [Option.some.injEq, forall_eq']
    match h : flagRows ledger r.flag with
    | [] => simp
    | [x] => by_cases hx : x.visClass = some c <;> simp [hx]
    | _ :: _ :: _ => simp

theorem classDisagreements_eq_nil_iff {reg : List Reg} {ledger : List Row} :
    classDisagreements reg ledger = [] ↔ ∀ r ∈ reg, ClassAgrees ledger r := by
  unfold classDisagreements
  simp only [List.filterMap_eq_nil_iff, Option.map_eq_none_iff]
  exact forall₂_congr fun _ _ => classIssue_eq_none_iff

theorem classIssue_of_noRow {ledger : List Row} {r : Reg} {c : VisClass} (hc : r.visClass = some c)
    (h : flagRows ledger r.flag = []) : classIssue ledger r = some .noRow := by
  simp [classIssue, hc, h]

theorem classIssue_of_rowCount {ledger : List Row} {r : Reg} {c : VisClass} {x y : Row} {rs : List Row}
    (hc : r.visClass = some c) (h : flagRows ledger r.flag = x :: y :: rs) :
    classIssue ledger r = some (.rowCount (rs.length + 2)) := by
  simp [classIssue, hc, h]

theorem classIssue_of_differs {ledger : List Row} {r : Reg} {c : VisClass} {x : Row}
    (hc : r.visClass = some c) (h : flagRows ledger r.flag = [x]) (hx : x.visClass ≠ some c) :
    classIssue ledger r = some (.differs x.visClass c) := by
  simp [classIssue, hc, h, hx]

theorem classIssue_of_unclassed {ledger : List Row} {r : Reg} (hc : r.visClass = none) : classIssue ledger r = none := by
  simp [classIssue, hc]

theorem mem_classDisagreements {reg : List Reg} {ledger : List Row} {r : Reg} {i : ClassIssue} (hr : r ∈ reg)
    (h : classIssue ledger r = some i) : i.text r.flag ∈ classDisagreements reg ledger :=
  List.mem_filterMap.2 ⟨r, hr, by simp [h]⟩

def lookCandidates (reg : List Reg) : List Flag :=
  ((reg.filter fun r => r.visClass == some .l).map (·.flag)).mergeSort fun a b => a.key ≤ b.key

theorem probe_not_mem_lookCandidates {reg : List Reg} {f : Flag} (hc : probesClean reg = true) (h : OnlyProbe reg f) :
    f ∉ lookCandidates reg := by
  intro hm
  unfold lookCandidates at hm
  obtain ⟨r, hr, rfl⟩ := List.mem_map.1 ((List.mem_mergeSort).1 hm)
  simp only [List.mem_filter, beq_iff_eq] at hr
  have hk := h r hr.1 rfl
  have hall := List.all_eq_true.1 hc r hr.1
  simp [hk, hr.2] at hall

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

def superJson : Option Super → Json
  | none => .null
  | some (.reader r) => Json.mkObj [("by", .str (toString r)), ("why", .str "reader")]
  | some (.retry r) => Json.mkObj [("by", .str (toString r)), ("why", .str "retry")]

def superWord : Option Super → String
  | none => ""
  | some (.reader r) => s!", superseded by {r} (reader)"
  | some (.retry r) => s!", superseded by {r} (retry)"

def storedJson (st : List Stored) (s : Stored) : Json :=
  Json.mkObj [("run", .str (toString s.run)), ("sha", .str s.sha), ("reader", .str s.reader), ("search", .str s.search),
    ("flags", toJson s.flags), ("engine", .str (engineWord s.engine)), ("path", .str (walkWord s.walk)),
    ("widths", toJson s.widths),
    ("groups", .arr (s.groups.map fun g => Json.mkObj [("node", .str g.node), ("prop", .str g.prop),
      ("content", toJson g.content), ("coverage", toJson g.coverage)]).toArray),
    ("outcome", .str (outcomeWord (outcome s))), ("superseded", superJson (supersede st s))]

def parseRunId (t : String) : Except String Nat :=
  if !t.isEmpty && t.all Char.isDigit then .ok (t.foldl (fun n c => 10 * n + (c.toNat - '0'.toNat)) 0)
  else .error s!"run id {t.quote} is not a decimal number"

theorem parseRunId_ok {t : String} {n : Nat} (h : parseRunId t = .ok n) : !t.isEmpty && t.all Char.isDigit := by
  unfold parseRunId at h
  split at h
  · assumption
  · cases h

theorem parseRunId_error {t : String} (h : (!t.isEmpty && t.all Char.isDigit) = false) :
    parseRunId t = .error s!"run id {t.quote} is not a decimal number" := by
  unfold parseRunId
  simp only [h, Bool.false_eq_true, ↓reduceIte]

def parseStored (j : Json) : Except String Stored := do
  let gs ← (← j.getObjVal? "groups").getArr?
  let groups ← gs.toList.mapM fun g => do
    return ⟨← g.getObjValAs? String "node", ← g.getObjValAs? String "prop", ← g.getObjValAs? (List Nat) "content",
      ← g.getObjValAs? (List Nat) "coverage"⟩
  return { run := ← parseRunId (← j.getObjValAs? String "run"), sha := ← j.getObjValAs? String "sha",
           reader := (← optStr j "reader").getD "",
           search := ← j.getObjValAs? String "search", flags := ← j.getObjValAs? (List String) "flags",
           engine := ← parseEngine (← j.getObjValAs? String "engine"),
           walk := ← parseWalk (← j.getObjValAs? String "path"), widths := ← j.getObjValAs? (List Nat) "widths",
           groups }

def parseStoredText (t : String) : Except String (List Stored) :=
  ((t.splitOn "\n").filter (!·.isEmpty)).mapM fun l => do parseStored (← Json.parse l)

def storedText (st : List Stored) : String :=
  let key (s : Stored) := engineWord s.engine ++ " " ++ walkWord s.walk
  String.join ((st.mergeSort fun a b => a.run < b.run || (a.run == b.run && key a ≤ key b)).map fun s => (storedJson st s).compress ++ "\n")

def trajJson (st : List Stored) (f : Flag) : Json :=
  let cell (fam : Family) (w : Walk) : Json :=
    Json.mkObj [("family", .str (familyWord fam)), ("path", .str (walkWord w)), ("cell", .str (tcellWord (tcell st f fam w))),
      ("runs", .arr ((runsFor st f fam w).map fun s => Json.mkObj [("run", .str (toString s.run)),
        ("engine", .str (engineWord s.engine)), ("alone", .bool (s.flags == [f.key])),
        ("outcome", .str (outcomeWord (outcome s))), ("superseded", superJson (supersede st s)),
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

def q6Answer : Option String := some Fw.Parts.HeroExitScrollOffset.q6Text

def acceptedLook (f : Flag) : Bool := lookDecisions.any fun d => d.flag == f && d.decision == .accepted

def lookMet (reg : List Reg) (f : Flag) : Bool := exactLook reg f || acceptedLook f

theorem lookMet_of_exact {reg : List Reg} {f : Flag} (h : exactLook reg f = true) : lookMet reg f = true := by
  simp [lookMet, h]

theorem lookMet_of_accepted {reg : List Reg} {f : Flag} (h : acceptedLook f = true) : lookMet reg f = true := by
  simp [lookMet, h]

theorem lookMet_false {reg : List Reg} {f : Flag} (hx : exactLook reg f = false) (ha : acceptedLook f = false) :
    lookMet reg f = false := by
  simp [lookMet, hx, ha]

def lookAccepted (f : Flag) : Bool :=
  lookDecisions.any fun d => d.flag == f && d.decision == .accepted && d.review == .done

theorem lookAccepted_iff {f : Flag} :
    lookAccepted f = true ↔ ∃ d ∈ lookDecisions, d.flag = f ∧ d.decision = .accepted ∧ d.review = .done := by
  simp [lookAccepted, and_assoc]

def shippedNow (reg : List Reg) (ledger : List Row) (st : List Stored) : List Flag :=
  Shipped.shipped lookAccepted reg links ledger st

/-- **Every `shipped` member outside `v2-proved` has an accepted, reviewed user look decision in `lookDecisions`**. -/
theorem shipped_extra_decided {reg : List Reg} {ledger : List Row} {st : List Stored} {f : Flag}
    (h : f ∈ shippedNow reg ledger st) (hn : f ∉ preset reg links ledger st) :
    ∃ d ∈ lookDecisions, d.flag = f ∧ d.decision = .accepted ∧ d.review = .done :=
  lookAccepted_iff.1 (Shipped.shipped_extra_accepted h hn)

theorem shipped_look_decided {reg : List Reg} {ledger : List Row} {st : List Stored} {f : Flag}
    (h : f ∈ shippedNow reg ledger st) (hl : isLook reg f = true) :
    ∃ d ∈ lookDecisions, d.flag = f ∧ d.decision = .accepted ∧ d.review = .done :=
  lookAccepted_iff.1 (Shipped.shipped_look_accepted h hl)

#guard lookAccepted ⟨"nav", "earn-logical"⟩ && lookAccepted ⟨"hero.exit", "threaded"⟩
#guard !lookAccepted ⟨"nav", "earn-no-transition"⟩ && !lookAccepted ⟨"hero.accent", "draw-nolayout"⟩
#guard !lookAccepted ⟨"nav", "faithful"⟩

def reqMet (reg : List Reg) (ledger : List Row) (st : List Stored) (f : Flag) : EntryReq → Bool
  | .proofs => why links ledger f == .proved
  | .gate fam => walks.all fun w => tcell st f fam w == .pass
  | .look => lookMet reg f
  | .q6 => q6Answer.isSome

def blockers (reg : List Reg) (ledger : List Row) (st : List Stored) (f : Flag) : List EntryReq :=
  entryReqs.filter fun r => !reqMet reg ledger st f r

inductive Entry | enter | notYet (blockers : List EntryReq)
deriving DecidableEq, Repr

def entry (reg : List Reg) (ledger : List Row) (st : List Stored) (f : Flag) : Entry :=
  if (blockers reg ledger st f).isEmpty then .enter else .notYet (blockers reg ledger st f)

theorem entry_enter_iff {reg : List Reg} {ledger : List Row} {st : List Stored} {f : Flag} :
    entry reg ledger st f = .enter ↔ ∀ r ∈ entryReqs, reqMet reg ledger st f r = true := by
  have e : (blockers reg ledger st f).isEmpty = true ↔ ∀ r ∈ entryReqs, reqMet reg ledger st f r = true := by
    simp [blockers, List.filter_eq_nil_iff]
  unfold entry
  by_cases h : (blockers reg ledger st f).isEmpty = true
  · simp only [h, ↓reduceIte, true_iff]
    exact e.1 h
  · simp only [h, Bool.false_eq_true, ↓reduceIte, reduceCtorEq, false_iff]
    exact fun h' => h (e.2 h')

theorem entry_notYet_of_unmet {reg : List Reg} {ledger : List Row} {st : List Stored} {f : Flag} {r : EntryReq}
    (hr : r ∈ entryReqs) (hu : reqMet reg ledger st f r = false) :
    entry reg ledger st f = .notYet (blockers reg ledger st f) ∧ r ∈ blockers reg ledger st f := by
  have hb : r ∈ blockers reg ledger st f := List.mem_filter.2 ⟨hr, by simp [hu]⟩
  have hne : (blockers reg ledger st f).isEmpty = false := by
    cases e : blockers reg ledger st f with
    | nil => simp [e] at hb
    | cons _ _ => rfl
  exact ⟨by simp [entry, hne], hb⟩

theorem ok_of_enter {reg : List Reg} {ledger : List Row} {st : List Stored} {f : Flag}
    (he : entry reg ledger st f = .enter) (ho : isOpt reg f = true) (hl : isLook reg f = false) :
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

theorem enter_of_ok_exact {reg : List Reg} {ledger : List Row} {st : List Stored} {f : Flag}
    (hk : ok reg links ledger st f = true) (hx : exactLook reg f = true) : entry reg ledger st f = .enter := by
  simp only [ok, Bool.and_eq_true, beq_iff_eq] at hk
  have hg := trajWhy_pass_iff.1 hk.1.2
  refine entry_enter_iff.2 fun r hr => ?_
  cases r with
  | proofs => simp [reqMet, hk.1.1.2]
  | gate fam =>
    simp only [reqMet, List.all_eq_true, beq_iff_eq]
    exact hg fam (by cases fam <;> simp [families])
  | look => exact lookMet_of_exact hx
  | q6 => rfl

theorem entry_enter_iff_ok_of_exact {reg : List Reg} {ledger : List Row} {st : List Stored} {f : Flag}
    (hx : exactLook reg f = true) (ho : isOpt reg f = true) :
    entry reg ledger st f = .enter ↔ ok reg links ledger st f = true :=
  ⟨fun he => ok_of_enter he ho (not_isLook_of_exactLook hx), fun hk => enter_of_ok_exact hk hx⟩

def heroExitThreaded : Flag := ⟨"hero.exit", "threaded"⟩

def holdFreeze : Flag := ⟨"platform.glint", "hold-freeze"⟩

theorem q6_met {reg : List Reg} {ledger : List Row} {st : List Stored} {f : Flag} : reqMet reg ledger st f .q6 = true := rfl

theorem threaded_look_met {reg : List Reg} {ledger : List Row} {st : List Stored} : reqMet reg ledger st heroExitThreaded .look = true :=
  lookMet_of_accepted (by decide)

theorem threaded_link : linkOf links heroExitThreaded = some [threadedKey] := by
  rfl

theorem rowWhy_ne_proved {ledger : List Row} {k : Key} : rowWhy ledger k ≠ some .proved := by
  unfold rowWhy
  split
  · split
    · simp
    · split <;> simp
  · simp

theorem threaded_proofs_iff {reg : List Reg} {ledger : List Row} {st : List Stored} :
    reqMet reg ledger st heroExitThreaded .proofs = true ↔
      falsifiedBy ledger heroExitThreaded = false ∧ rowWhy ledger threadedKey = none := by
  simp only [reqMet, why, threaded_link, List.findSome?, beq_iff_eq]
  have hn := @rowWhy_ne_proved ledger threadedKey
  cases falsifiedBy ledger heroExitThreaded <;> cases h : rowWhy ledger threadedKey <;> simp_all

theorem threaded_proofs_blocked {reg : List Reg} {ledger : List Row} {st : List Stored} {r : Row}
    (hr : rowsOf ledger threadedKey = [r]) (hs : r.status ≠ "proved") :
    reqMet reg ledger st heroExitThreaded .proofs = false ∧
      (falsifiedBy ledger heroExitThreaded = false → why links ledger heroExitThreaded = .notProved threadedKey r.status) := by
  have hw : rowWhy ledger threadedKey = some (.notProved threadedKey r.status) := by
    simp [rowWhy, hr, hs]
  refine ⟨?_, fun hf => by simp [why, hf, threaded_link, hw]⟩
  cases h : reqMet reg ledger st heroExitThreaded .proofs
  · rfl
  · simp [(threaded_proofs_iff.1 h).2] at hw

theorem threaded_proofs_of_promoted {reg : List Reg} {ledger : List Row} {st : List Stored} {r : Row}
    (hr : rowsOf ledger threadedKey = [r]) (hs : r.status = "proved") (hm : r.fResult ≠ some .modelBug)
    (hf : falsifiedBy ledger heroExitThreaded = false) : reqMet reg ledger st heroExitThreaded .proofs = true :=
  threaded_proofs_iff.2 ⟨hf, by simp [rowWhy, hr, hs, hm]⟩

theorem threaded_not_yet {reg : List Reg} {ledger : List Row} {st : List Stored} {r : Row}
    (hr : rowsOf ledger threadedKey = [r]) (hs : r.status ≠ "proved") :
    entry reg ledger st heroExitThreaded = .notYet (blockers reg ledger st heroExitThreaded) ∧
      .proofs ∈ blockers reg ledger st heroExitThreaded ∧ .look ∉ blockers reg ledger st heroExitThreaded ∧
      .q6 ∉ blockers reg ledger st heroExitThreaded :=
  let h := entry_notYet_of_unmet (by simp [entryReqs]) (threaded_proofs_blocked (st := st) hr hs).1
  ⟨h.1, h.2, fun h => by simp [blockers, threaded_look_met] at h, fun h => by simp [blockers, q6_met] at h⟩

theorem gate_blocked_of_own_fail {reg : List Reg} {ledger : List Row} {st : List Stored} {f : Flag} {fam : Family} {w : Walk}
    {s : Stored} (hw : w ∈ walks) (hs : s ∈ runsFor st f fam w) (ho : s.flags = [f.key])
    (hf : outcome s = .fail) (hr : ∀ n ∈ (later st s).getLast?, n.reader = s.reader) :
    reqMet reg ledger st f (.gate fam) = false ∧ .gate fam ∈ blockers reg ledger st f := by
  have hu : reqMet reg ledger st f (.gate fam) = false := by
    simp only [reqMet, List.all_eq_false, beq_iff_eq]
    exact ⟨w, hw, by simp [fail_not_hidden hs ho hf hr]⟩
  have hr : EntryReq.gate fam ∈ entryReqs := by cases fam <;> simp [entryReqs]
  exact ⟨hu, (entry_notYet_of_unmet hr hu).2⟩

def threadedEvidence (ledger : List Row) (st : List Stored) : EntryReq → String
  | .proofs =>
    let w := why links ledger heroExitThreaded
    let status := match w with
      | .proved => "proved"
      | .notProved _ s => s
      | w => (whyJson w).compress
    let r2 := if w == .proved then "closed by Fw.Parts.HeroExitWork.cr_lane_style_saving (R2 inherited fan-out \
        units), Fw.Parts.HeroExitWork.wk_style_saving with Fw.Parts.HeroExitWork.wk_trade_r2E (WebKit inherited \
        fan-out per element) and Fw.Parts.HeroExitWork.wk_edge_layout with Fw.Parts.HeroExitWork.edgeFrames_le_starts \
        (WebKit edge-frame cost)"
      else "open until the row is proved"
    "linked to ledger row hero-exit-threaded (v6, KD#2), status " ++ status ++ "; met only when that row is proved \
      (Fw.Preset.Gen.threaded_proofs_iff): Fw.Parts.HeroExitOpt.consumer_eq_s holds under the hypothesis RG11, \
      Fw.Parts.HeroExitOpt.cr_real_tradeE and Fw.Parts.HeroExitOpt.wk_tradeE give a trade, and the row's missingWhy \
      items are " ++ r2
  | .gate fam =>
    let cell (w : Walk) : String :=
      let runs := (runsFor st heroExitThreaded fam w).map fun s =>
        "run " ++ toString s.run ++ " " ++ engineWord s.engine ++ " " ++ outcomeWord (outcome s) ++
          superWord (supersede st s)
      walkWord w ++ " " ++ tcellWord (tcell st heroExitThreaded fam w) ++
        (if runs.isEmpty then " (no stored run)" else " (" ++ ", ".intercalate runs ++ ")")
    "trajectory " ++ "; ".intercalate (walks.map cell) ++ "; the 25/40/40 new hero units of run 40156078840 sit on \
      nodes that paint no box, at equal offsets (Fw.Parts.HeroExitScrollOffset.measured_hidden); PathPix runs \
      39924527942 and 39929556147 grade every valid P cell L (research/notes/2026/10-2x-hero-exit-threaded-pix.md)"
  | .look => "accepted 2026-10-24 on the real iPhone (results/phone/2026-10-24-hero-exit-threaded/summary.md)"
  | .q6 => q6Answer.getD "open: no answer recorded"

def threadedRowNames : List Name :=
  [``Fw.Parts.HeroExitWork.cr_lane_style_saving, ``Fw.Parts.HeroExitWork.wk_edge_layout,
    ``Fw.Parts.HeroExitWork.edgeFrames_le_starts, ``Fw.Parts.HeroExitOpt.consumer_eq_s,
    ``Fw.Parts.HeroExitOpt.cr_real_tradeE, ``Fw.Parts.HeroExitOpt.wk_tradeE,
    ``Fw.Parts.HeroExitWork.wk_style_saving, ``Fw.Parts.HeroExitWork.wk_trade_r2E]

def theoremTokens (t : String) : List String :=
  (t.splitToList fun c => c == ' ' || c == '(' || c == ')' || c == ',' || c == ';' || c == ':' || c == '\n').filter
    fun w => "Fw.".isPrefixOf w || w.contains '_'

def rowLinks (ledger : Json) (flag : String) : List String :=
  let rows := ((ledger.getObjVal? "findings").toOption.bind (·.getArr?.toOption)).getD #[]
  match rows.toList.find? (fun r => (r.getObjValAs? String "flag").toOption == some flag) with
  | none => []
  | some r => ["leanFor", "leanAgainst"].flatMap fun k => (r.getObjValAs? (List String) k).toOption.getD []

def linkGaps (ledger : Json) (f : Flag) (names : List Name) : List String :=
  (names.map toString).filter fun n => !(rowLinks ledger f.key).contains n

def threadedLinkGaps (ledger : Json) : List String := linkGaps ledger heroExitThreaded threadedRowNames

def holdRowNames : List Name :=
  [``Fw.Parts.PlatformGlintHold.hold_premise, ``Fw.Parts.PlatformGlintHold.hold_eq_faithful,
    ``Fw.Parts.PlatformGlintHold.ticking_hold, ``Fw.Parts.PlatformGlintHold.ticking_ramp,
    ``Fw.Parts.PlatformGlintHold.ticking_le, ``Fw.Parts.PlatformGlintHold.hold_resume_eq,
    ``Fw.Parts.PlatformGlintPause.resume_seek_forward]

def holdLinkGaps (ledger : Json) : List String := linkGaps ledger holdFreeze holdRowNames

#guard (theoremTokens "a (Fw.X.y_z), b_c: d") == ["Fw.X.y_z", "b_c"]
#guard threadedLinkGaps (Json.mkObj [("findings", .arr #[Json.mkObj [("flag", .str heroExitThreaded.key),
  ("leanFor", .arr ((threadedRowNames.drop 1).map (.str ·.toString)).toArray),
  ("leanAgainst", .arr #[.str (threadedRowNames.head!.toString)])]])]) == []
#guard threadedLinkGaps (Json.mkObj [("findings", .arr #[Json.mkObj [("flag", .str heroExitThreaded.key),
  ("leanFor", .arr ((threadedRowNames.drop 1).map (.str ·.toString)).toArray)]])]) ==
  (threadedRowNames.take 1).map toString
#guard threadedLinkGaps .null == threadedRowNames.map toString
#guard holdLinkGaps .null == holdRowNames.map toString

def entryWord : Entry → String
  | .enter => "enter"
  | .notYet _ => "not yet"

def reqWord : Shipped.Req → String
  | .kind => "kind"
  | .proofs => "proofs"
  | .gate fam => "gate " ++ familyWord fam
  | .look => "look"

def reqsJson (rs : List Shipped.Req) : Json := .arr (rs.map (.str ∘ reqWord)).toArray

def route (reg : List Reg) (ledger : List Row) (st : List Stored) (f : Flag) : Json :=
  if ok reg links ledger st f then "v2-proved"
  else if Shipped.lookOk lookAccepted reg links ledger st f then "look-accepted" else .null

def presetsJson (reg : List Reg) (ledger : List Row) (st : List Stored) (f : Flag) : Json :=
  Json.mkObj [
    ("v2-proved", Json.mkObj [("member", .bool ((preset reg links ledger st).contains f)),
      ("blockers", reqsJson (Shipped.blockersV2 reg links ledger st f))]),
    ("shipped", Json.mkObj [("member", .bool ((shippedNow reg ledger st).contains f)),
      ("route", route reg ledger st f),
      ("blockers", reqsJson (Shipped.blockersShipped lookAccepted reg links ledger st f))])]

def entryJson (reg : List Reg) (ledger : List Row) (st : List Stored) (f : Flag) : Json :=
  let head := [("decision", Json.str (entryWord (entry reg ledger st f))),
    ("blockers", .arr ((blockers reg ledger st f).map (.str ·.word)).toArray),
    ("presets", presetsJson reg ledger st f)]
  if f != heroExitThreaded then Json.mkObj head else
  Json.mkObj (head ++ [("requirements", .arr (entryReqs.map fun r => Json.mkObj [("req", .str r.word),
      ("met", .bool (reqMet reg ledger st f r)), ("evidence", .str (threadedEvidence ledger st r))]).toArray)])

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
    ("userDecision", decisionOf f), ("entry", entryJson reg ledger st f)]

def probeFlags (reg : List Reg) : List Flag :=
  ((reg.filter fun r => r.kind == .probe).map (·.flag)).mergeSort fun a b => a.key ≤ b.key

def probesText (reg : List Reg) (p : List Flag) : String :=
  String.join ((probeFlags reg).map fun f =>
    (Json.mkObj [("flag", .str f.key), ("kind", "probe"), ("member", .bool (p.contains f)),
      ("lookCandidate", .bool ((lookCandidates reg).contains f))]).compress ++ "\n")

def decisionsText (reg : List Reg) (ledger : List Row) (st : List Stored) : String :=
  String.join ((decided reg).map fun f => (decision reg ledger st f).compress ++ "\n")

def shippedDecided (reg : List Reg) : List Flag :=
  decided reg ++ (lookCandidates reg).filter fun f => !(decided reg).contains f

def shippedDecision (reg : List Reg) (ledger : List Row) (st : List Stored) (f : Flag) : Json :=
  let s := shippedNow reg ledger st
  let kind : Json := match reg.find? (·.flag == f) with
    | some r => .str (kindWord r.kind)
    | none => .null
  let vc : Json := match (reg.find? (·.flag == f)).bind (·.visClass) with
    | some c => .str (visClassWord c)
    | none => .null
  let shadow : Json := if !s.contains f && Shipped.okShipped lookAccepted reg links ledger st f then
      match s.find? (·.part == f.part) with
      | some g => .str g.key
      | none => .null
    else .null
  Json.mkObj [("flag", .str f.key), ("kind", kind), ("visClass", vc), ("member", .bool (s.contains f)),
    ("route", route reg ledger st f), ("shadowedBy", shadow),
    ("blockers", reqsJson (Shipped.blockersShipped lookAccepted reg links ledger st f)),
    ("lookRoute", reqsJson (Shipped.blockersLook lookAccepted reg links ledger st f)),
    ("trajectory", .str (twhyWord (trajWhy st f))), ("userDecision", decisionOf f)]

def shippedDecisionsText (reg : List Reg) (ledger : List Row) (st : List Stored) : String :=
  String.join ((shippedDecided reg).map fun f => (shippedDecision reg ledger st f).compress ++ "\n")

def unclassified (reg : List Reg) (f : Flag) : Bool :=
  reg.any (·.flag == f) && reg.all fun r => r.flag != f || r.visClass.isNone

def lookExceptions : List Flag := [⟨"engine.scroll", "unthrottle"⟩]

def agreeScope (reg : List Reg) (f : Flag) : Bool :=
  (exactLook reg f || unclassified reg f) && !lookExceptions.contains f

def entryGaps (reg : List Reg) (ledger : List Row) (st : List Stored) : List Flag :=
  (decided reg).filter fun f => agreeScope reg f && ((entry reg ledger st f == .enter) != ok reg links ledger st f)

def staleLookExceptions (reg : List Reg) : List Flag := lookExceptions.filter fun f => !unclassified reg f

theorem entry_enter_iff_ok_of_noGaps {reg : List Reg} {ledger : List Row} {st : List Stored} {f : Flag}
    (hg : entryGaps reg ledger st = []) (hd : f ∈ decided reg) (hs : agreeScope reg f = true) :
    entry reg ledger st f = .enter ↔ ok reg links ledger st f = true := by
  have h := List.filter_eq_nil_iff.1 hg f hd
  simp only [hs, Bool.true_and, bne_iff_ne, ne_eq, Classical.not_not] at h
  cases he : entry reg ledger st f <;> cases ho : ok reg links ledger st f <;> simp_all

def ledgerPath : System.FilePath := ".." / "research" / "findings" / "ledger.json"
def partsDir : System.FilePath := ".." / "apps" / "site" / "src" / "parts"
def goldenPreset : System.FilePath := ".." / "packages" / "contracts" / "golden" / "preset" / "v2-proved.json"
def goldenDecisions : System.FilePath :=
  ".." / "packages" / "contracts" / "golden" / "preset" / "v2-proved.decisions.jsonl"
def goldenLook : System.FilePath :=
  ".." / "packages" / "contracts" / "golden" / "preset" / "look-change.candidates.jsonl"
def goldenProbes : System.FilePath :=
  ".." / "packages" / "contracts" / "golden" / "preset" / "probes.jsonl"
def sitePreset : System.FilePath := ".." / "apps" / "site" / "src" / "registry" / "presets" / "v2-proved.json"
def goldenShipped : System.FilePath := ".." / "packages" / "contracts" / "golden" / "preset" / "shipped.json"
def goldenShippedDecisions : System.FilePath :=
  ".." / "packages" / "contracts" / "golden" / "preset" / "shipped.decisions.jsonl"
def siteShipped : System.FilePath := ".." / "apps" / "site" / "src" / "registry" / "presets" / "shipped.json"
def readerFiles : List String :=
  ["packages/contracts/src/flag-key.mjs", "packages/gate-breakpoints/src/engines.mjs",
   "packages/gate-breakpoints/src/page.mjs", "packages/gate-breakpoints/src/serve.mjs",
   "packages/gate-breakpoints/src/spec.mjs", "packages/gate-breakpoints/src/trajectory/cli.mjs",
   "packages/gate-breakpoints/src/trajectory/consumer.mjs", "packages/gate-breakpoints/src/trajectory/debug.mjs",
   "packages/gate-breakpoints/src/trajectory/kit.mjs", "packages/gate-breakpoints/src/trajectory/plan.mjs",
   "packages/gate-breakpoints/src/trajectory/reduce.mjs", "packages/gate-breakpoints/src/trajectory/registry.mjs",
   "packages/gate-breakpoints/src/trajectory/run.mjs"]

def readerFilesText : String := (toJson readerFiles).compress ++ "\n"

def goldenReaderFiles : System.FilePath :=
  ".." / "packages" / "contracts" / "golden" / "preset" / "reader-files.json"
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

def run (args : List String) : IO Unit := do
  let ledger ← IO.ofExcept ((parseLedger (← readJson ledgerPath)).mapError fun e => s!"{ledgerPath}: {e}")
  let reg ← readRegistry
  let st ← readStored
  let p ← IO.ofExcept (generate reg links ledger st)
  let sp ← IO.ofExcept (Shipped.generate lookAccepted reg links ledger st)
  unless (threadedLinkGaps (← readJson ledgerPath)).isEmpty do
    throw (IO.userError
      s!"threadedEvidence cites theorems outside the ledger row's links: {threadedLinkGaps (← readJson ledgerPath)}")
  unless (holdLinkGaps (← readJson ledgerPath)).isEmpty do
    throw (IO.userError s!"the hold-freeze ledger row does not link: {holdLinkGaps (← readJson ledgerPath)}")
  let bad := ledgerDisagreements (← readJson ledgerPath) lookDecisions
  unless bad.isEmpty do throw (IO.userError s!"the ledger text disagrees with Gen.lookDecisions: {bad}")
  unless (classDisagreements reg ledger).isEmpty do
    throw (IO.userError s!"the ledger visClass disagrees with part.json: {classDisagreements reg ledger}")
  unless (entryGaps reg ledger st).isEmpty do
    throw (IO.userError s!"Gen.entry and V2Proved.ok disagree: {(entryGaps reg ledger st).map (·.key)}")
  unless (staleLookExceptions reg).isEmpty do
    throw (IO.userError s!"lookExceptions name flags that are not unclassified: {(staleLookExceptions reg).map (·.key)}")
  unless (staleDecisions reg).isEmpty do
    throw (IO.userError s!"look decisions name no look-change candidate and no refused registered flag: {(staleDecisions reg).map (·.key)}")
  unless (refusedMembers lookDecisions p).isEmpty do
    throw (IO.userError s!"refused flags in v2-proved: {(refusedMembers lookDecisions p).map (·.key)}")
  let unread := (st.filter (·.reader.isEmpty)).map (·.run)
  unless unread.isEmpty do
    throw (IO.userError s!"{storedPath}: runs {unread} have no reader identity; fill it with Fw.Preset.Gen.record")
  let outs := [(goldenPreset, presetText p), (sitePreset, presetText p),
    (goldenDecisions, decisionsText reg ledger st), (goldenLook, lookText reg p),
    (goldenProbes, probesText reg p), (storedPath, storedText st), (goldenReaderFiles, readerFilesText),
    (goldenShipped, namedPresetText "shipped" sp), (siteShipped, namedPresetText "shipped" sp),
    (goldenShippedDecisions, shippedDecisionsText reg ledger st)]
  if args.contains "--check" then
    let mut stale : List String := []
    for (path, text) in outs do
      let cur ← try IO.FS.readFile path catch _ => pure ""
      if cur != text then stale := stale ++ [path.toString]
    unless stale.isEmpty do
      throw (IO.userError s!"v2-proved: stale {stale}; regenerate with Fw.Preset.Gen.run []")
    IO.println s!"v2-proved: up to date, {p.length} flags: {p.map (·.key)}; shipped: {sp.map (·.key)}"
  else
    for (path, text) in outs do
      IO.FS.createDirAll (path.parent.getD ".")
      IO.FS.writeFile path text
    IO.println s!"v2-proved: written, {p.length} flags: {p.map (·.key)}; shipped: {sp.map (·.key)}"

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

def storedOf (run : Nat) (sha reader : String) (e : Engine) (presetKeys : Option (List String)) (j : Json) :
    Except String (List Stored) := do
  if ← j.getObjValAs? Bool "refused" then throw s!"run {run} {engineWord e} was refused"
  let search ← j.getObjValAs? String "search"
  let flags ← flagsOfSearch search presetKeys
  let us ← (← (← j.getObjVal? "units").getArr?).toList.mapM parseUnit
  return [Walk.hero, .morph].filterMap fun w =>
    if us.any (·.walk == walkWord w) then
      some { run, sha, reader, search, flags, engine := e, walk := w, widths := widthsOf (walkWord w) us,
             groups := groupsOf (walkWord w) us }
    else none

def sameRow (n s : Stored) : Bool := n.run == s.run && n.engine == s.engine && n.walk == s.walk

def merge (old new : List Stored) : List Stored :=
  old.filter (fun s => !new.any (sameRow · s)) ++ new

theorem merge_new_mem {old new : List Stored} {n : Stored} (h : n ∈ new) : n ∈ merge old new :=
  List.mem_append_right _ h

theorem merge_keeps {old new : List Stored} {s : Stored} (hs : s ∈ old) :
    s ∈ merge old new ∨ ∃ n ∈ new, sameRow n s = true := by
  by_cases h : new.any (sameRow · s) = true
  · exact Or.inr (List.any_eq_true.1 h)
  · exact Or.inl (List.mem_append_left _ (List.mem_filter.2 ⟨hs, by simpa using h⟩))

theorem sameRow_self (n : Stored) : sameRow n n = true := by
  simp [sameRow]

theorem merge_idem (old new : List Stored) : merge (merge old new) new = merge old new := by
  have hn : new.filter (fun s => !new.any (sameRow · s)) = [] :=
    List.filter_eq_nil_iff.2 fun n hn => by simpa using ⟨n, hn, sameRow_self n⟩
  simp only [merge, List.filter_append, hn, List.append_nil, List.filter_filter, Bool.and_self]

def readerOf (sha : String) : IO String := do
  let ls ← IO.Process.output { cmd := "git", args := #["ls-tree", "--full-tree", sha, "--"] ++ readerFiles.toArray }
  unless ls.exitCode == 0 do throw (IO.userError s!"git ls-tree {sha}: {ls.stderr}")
  if ls.stdout.isEmpty then throw (IO.userError s!"commit {sha} holds none of the reader files")
  IO.FS.withTempFile fun h path => do
    h.putStr ls.stdout
    h.flush
    let o ← IO.Process.output { cmd := "git", args := #["hash-object", path.toString] }
    unless o.exitCode == 0 do throw (IO.userError s!"git hash-object: {o.stderr}")
    pure (String.ofList (o.stdout.toList.takeWhile Char.isAlphanum))

def fillReaders (st : List Stored) : IO (List Stored) := do
  let mut known : List (String × String) := []
  let mut out : Array Stored := #[]
  for s in st do
    if s.reader.isEmpty then
      match known.lookup s.sha with
      | some r => out := out.push { s with reader := r }
      | none =>
        let r ← readerOf s.sha
        known := known ++ [(s.sha, r)]
        out := out.push { s with reader := r }
    else out := out.push s
  pure out.toList

def record (args : List String) : IO Unit := do
  let (run, sha, pf, dirs) ← match args with
    | r :: s :: p :: d :: ds => pure (r, s, p, d :: ds)
    | _ => throw (IO.userError "usage: record [run, sha, presetFile or -, artifactDir...]")
  let runId ← IO.ofExcept (parseRunId run)
  unless sha.length == 40 && sha.all fun c => c.isDigit || ('a' ≤ c && c ≤ 'f') do
    throw (IO.userError s!"bad sha {sha}")
  let keys ← if pf == "-" then pure none else some <$> IO.ofExcept (presetKeys (← readJson pf))
  let reader ← readerOf sha
  let mut new : List Stored := []
  for d in dirs do
    let dir : System.FilePath := d
    let e ← IO.ofExcept (engineOfArtifact (dir.fileName.getD ""))
    let j ← readJson (dir / unitsName e)
    new := new ++ (← IO.ofExcept ((storedOf runId sha reader e keys j).mapError fun m => s!"{dir}: {m}"))
  let st := merge (← fillReaders (← readStored)) new
  IO.FS.writeFile storedPath (storedText st)
  for s in st do
    if new.any (sameKey s ·) then
      IO.println s!"record: run {s.run} {engineWord s.engine} {walkWord s.walk}: {outcomeWord (outcome s)}{superWord (supersede st s)}"

#guard (parseRunId "40671695274").toOption == some 40671695274
#guard (parseRunId "0").toOption == some 0
#guard (parseRunId "").toOption.isNone
#guard (parseRunId "run-1").toOption.isNone
#guard (parseRunId "12a").toOption.isNone
#guard (parseRunId "-1").toOption.isNone
#guard (parseRunId "1_000").toOption.isNone
#guard readerFiles == readerFiles.mergeSort (· ≤ ·)

#guard (parseFlag "nav.hitTest:hit-skip").toOption == some ⟨"nav.hitTest", "hit-skip"⟩
#guard (parseFlag "nav.hitTest").toOption.isNone
#guard (parseFlag "a:b:c").toOption.isNone
#guard (parseFlag ":b").toOption.isNone
#guard (parseKind "optimized").toOption == some .optimized
#guard (parseKind "Optimized").toOption.isNone
#guard (parseKind "probe").toOption == some .probe
#guard (parsePart (Json.mkObj [("id", "m"), ("variants", Json.mkObj [("off", Json.mkObj [("kind", "probe")])])])).toOption.map
  (fun rs => rs.map (·.kind)) == some [.probe]
#guard (parsePart (Json.mkObj [("id", "m"), ("variants", Json.mkObj [("off", Json.mkObj [("kind", "probe"), ("visClass", "L")])])])).toOption.isNone
#guard probesText [⟨⟨"m", "off"⟩, .probe, [], [], none⟩, ⟨⟨"m", "faithful"⟩, .faithful, [], [], none⟩] []
  == "{\"flag\":\"m:off\",\"kind\":\"probe\",\"lookCandidate\":false,\"member\":false}\n"
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
#guard (reasonOf ⟨"morph.panel", "rest"⟩).isSome
#guard (reasonOf ⟨"morph.countdown", "hidden-pause"⟩).isNone
#guard (reasonOf ⟨"hero.countdown", "hidden-pause"⟩).isNone
#guard links.map (·.1.key) == ["engine.scroll:batched", "nav.hitTest:elements-skip", "nav.hitTest:hit-skip",
  "hero.countdown:strip", "morph.countdown:strip", "morph.countdown:hidden-pause", "morph.columns:hidden-pause", "engine.scene:hidden-pause", "morph.mount:shift",
  "morph.tween:waapi", "pain.notes:visible", "people.card:mq", "hero.exit:scoped", "engine.scroll:unthrottle",
  "hero:scene-pause", "platform.glint:hold-freeze", "hero.exit:threaded", "nav:earn-logical"]
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

private def holdReg (c : VisClass) : Reg :=
  { flag := holdFreeze, kind := .optimized, requires := [], conflicts := [], visClass := some c }

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
private def classReg (v : String) (c : Option VisClass) : Reg :=
  { flag := ⟨"p", v⟩, kind := .proposal, requires := [], conflicts := [], visClass := c }
private def classRow (v : String) (c : Option VisClass) : Row :=
  { part := "p", candidate := v, status := "proved", flag := some s!"p:{v}", fResult := none, visClass := c }
#guard classDisagreements [classReg "a" (some .l)] [classRow "a" (some .l)] == []
#guard classDisagreements [classReg "a" none] [] == []
#guard classDisagreements [classReg "a" (some .e)] [classRow "b" (some .e)] == ["p:a: no ledger row has this flag"]
#guard classDisagreements [classReg "a" (some .l)] [classRow "a" (some .e)] ==
  ["p:a: the ledger row has visClass E, part.json has L"]
#guard classDisagreements [classReg "a" (some .eS)] [classRow "a" none] ==
  ["p:a: the ledger row has visClass none, part.json has E-s"]
#guard classDisagreements [classReg "a" (some .q)] [classRow "a" (some .q), classRow "a" (some .q)] ==
  ["p:a: 2 ledger rows have this flag"]
#guard classDisagreements [classReg "a" (some .l), classReg "b" (some .e), classReg "c" none]
  [classRow "a" (some .l), classRow "b" (some .eS), classRow "c" (some .q)] ==
  ["p:b: the ledger row has visClass E-s, part.json has E"]
#guard (parseRow (Json.mkObj [("part", "a"), ("candidate", "c"), ("status", "proved"), ("visClass", "E-s")])).toOption.map
  (·.visClass) == some (some .eS)
#guard (parseRow (Json.mkObj [("part", "a"), ("candidate", "c"), ("status", "proved")])).toOption.map (·.visClass) ==
  some none
#guard (parseRow (Json.mkObj [("part", "a"), ("candidate", "c"), ("status", "proved"), ("visClass", "e")])).toOption.isNone

private def stEx : Stored :=
  ⟨7, "s", "r", "?fw=a:x", ["a:x"], .macWebkit, .morph, [390, 641], [⟨"nav", "opacity", [390], [641]⟩]⟩
private def stBad : Stored :=
  { stEx with engine := .chromium, widths := Fw.Gate.Trajectory.allowedWidths,
              groups := [⟨"nav", "opacity", [390, 641], []⟩] }
private def unitJ (w : Nat) (p v r : String) : Json :=
  Json.mkObj [("width", w), ("path", .str p), ("node", "nav"), ("prop", "opacity"), ("verdict", .str v), ("rel", .str r)]
private def unitsJ (refused : Bool) (search : String) : Json :=
  Json.mkObj [("refused", .bool refused), ("search", .str search), ("units", .arr #[unitJ 390 "morph" "pass" "new",
    unitJ 641 "morph" "fail:coverage" "new", unitJ 641 "morph" "pass" "ok", unitJ 390 "hero" "pass" "ok"])]

#guard (parseStoredText (storedText [stEx, { stEx with run := 6 }])).toOption == some [{ stEx with run := 6 }, stEx]
#guard (parseStoredText (storedText [stEx, { stEx with run := 10 }])).toOption.map (·.map (·.run)) == some [7, 10]
#guard (parseStoredText "{\"run\":\"1\"}\n").toOption.isNone
#guard (parseStoredText ((storedText [stEx]).replace "\"7\"" "\"x7\"")).toOption.isNone
#guard (parseStoredText ((storedText [stEx]).replace ",\"reader\":\"r\"" "")).toOption.map (·.map (·.reader)) ==
  some [""]
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
#guard (storedOf 7 "s" "r" .chromium none (unitsJ true "?fw=a:x")).toOption.isNone
#guard ((storedOf 7 "s" "r" .chromium none (unitsJ false "?fw=a:x")).toOption.map fun l => l.map fun s =>
  (walkWord s.walk, s.widths, s.groups)) ==
  some [("hero", [390], []), ("morph", [390, 641], [⟨"nav", "opacity", [390], [641]⟩])]
#guard (merge [stEx, { stEx with walk := .hero }] [{ stEx with groups := [] }]).map (·.groups.length) == [1, 0]
#guard (merge [stEx] [{ stEx with run := 9, groups := [] }]).map (·.run) == [7, 9]
#guard (merge [stEx] [{ stEx with run := 5, groups := [] }]).map (·.run) == [7, 5]
#guard (merge [stEx] [{ stEx with run := 9, flags := ["b:y"], groups := [] }]).map (·.run) == [7, 9]
#guard (merge [stEx] [{ stEx with run := 9, engine := .chromium, groups := [] }]).map (·.run) == [7, 9]
#guard merge (merge [stEx] [{ stEx with run := 9, groups := [] }]) [{ stEx with run := 9, groups := [] }] ==
  merge [stEx] [{ stEx with run := 9, groups := [] }]
#guard superWord (supersede [stEx, { stEx with run := 9, groups := [] }] stEx) == ", superseded by 9 (retry)"
#guard superWord (supersede [stEx, { stEx with run := 9, reader := "q", groups := [] }] stEx) ==
  ", superseded by 9 (reader)"
#guard superWord (supersede [stEx, { stEx with run := 9, groups := [] }] { stEx with run := 9, groups := [] }) == ""
#guard ((trajJson [stEx] ⟨"a", "x"⟩).getObjValAs? String "verdict").toOption == some "pending: trajectory"
#guard ((trajJson [stBad] ⟨"a", "x"⟩).getObjValAs? String "verdict").toOption == some "falsified: trajectory"

private def stPass (e : Engine) (w : Walk) : Stored :=
  ⟨9, "s", "r", "?fw=hero.exit:threaded", ["hero.exit:threaded"], e, w, Fw.Gate.Trajectory.allowedWidths, []⟩

private def stFail (e : Engine) : Stored :=
  ⟨9, "s", "r", "?fw=hero.exit:threaded", ["hero.exit:threaded"], e, .hero, Fw.Gate.Trajectory.allowedWidths,
    [{ node := "hero.deck.card", prop := "opacity", content := [640, 641, 1280], coverage := [] }]⟩

#guard outcome (stFail .chromium) == .fail
#guard entry [] [] [] heroExitThreaded == .notYet [.proofs, .gate .chromium, .gate .webkit]
#guard outcome (stPass .chromium .hero) == .pass
#guard blockers [] [] ([Engine.chromium, .macWebkit].flatMap fun e => walks.map (stPass e)) heroExitThreaded == [.proofs]
#guard blockers [] [] [stPass .chromium .hero, stPass .chromium .morph] heroExitThreaded == [.proofs, .gate .webkit]
#guard blockers [] [] [] ⟨"nav", "earn-logical"⟩ == [.proofs, .gate .chromium, .gate .webkit]
#guard blockers [] [] [] ⟨"hero.accent", "draw-nolayout"⟩ == [.proofs, .gate .chromium, .gate .webkit, .look]
#guard entryJson [] [] [] ⟨"hero.accent", "draw-nolayout"⟩ == Json.mkObj [("decision", "not yet"),
  ("blockers", Json.arr #["proofs", "gate chromium", "gate webkit", "look"]),
  ("presets", Json.mkObj [
    ("v2-proved", Json.mkObj [("member", false), ("blockers", Json.arr #["kind", "proofs", "gate chromium", "gate webkit"])]),
    ("shipped", Json.mkObj [("member", false), ("route", .null),
      ("blockers", Json.arr #["kind", "proofs", "gate chromium", "gate webkit", "look"])])])]
#guard Shipped.blockersShipped lookAccepted [earnLogicalReg] links [] [] earnLogicalReg.flag ==
  [.proofs, .gate .chromium, .gate .webkit]
#guard Shipped.blockersV2 [earnLogicalReg] links [] [] earnLogicalReg.flag ==
  [.kind, .proofs, .gate .chromium, .gate .webkit, .look]
#guard Shipped.blockersShipped lookAccepted [{ earnLogicalReg with kind := .ablation }] links [] [] earnLogicalReg.flag ==
  [.kind, .proofs, .gate .chromium, .gate .webkit]
#guard Shipped.blockersShipped lookAccepted [] links [] (walks.flatMap fun w => [Engine.chromium, .macWebkit].map
  fun e => { stPass e w with search := "?fw=nav:earn-logical", flags := ["nav:earn-logical"] }) earnLogicalReg.flag ==
  [.kind, .proofs]
#guard route [] [] [] earnLogicalReg.flag == .null
#guard reqWord (.gate .webkit) == "gate webkit" && reqWord .kind == "kind" && reqWord .look == "look"
#guard shippedNow [] [] [] == []
#guard blockers [holdReg .e] [] [] holdFreeze == [.proofs, .gate .chromium, .gate .webkit]
#guard blockers [holdReg .eS] [] [] holdFreeze == [.proofs, .gate .chromium, .gate .webkit]
#guard blockers [holdReg .q] [] [] holdFreeze == [.proofs, .gate .chromium, .gate .webkit, .look]
#guard blockers [holdReg .l] [] [] holdFreeze == [.proofs, .gate .chromium, .gate .webkit, .look]
#guard blockers [holdReg .e, { holdReg .e with visClass := none }] [] [] holdFreeze ==
  [.proofs, .gate .chromium, .gate .webkit, .look]
#guard lookMet [] heroExitThreaded && !lookMet [] holdFreeze
#guard entryGaps [holdReg .e] [] [] == []
#guard entryGaps [{ holdReg .e with kind := .proposal }] [] [] == []
#guard ((entryJson [] [] [] heroExitThreaded).getObjValAs? String "decision").toOption == some "not yet"
#guard ((entryJson [] [] [] heroExitThreaded).getObjValAs? (List String) "blockers").toOption ==
  some ["proofs", "gate chromium", "gate webkit"]
#guard threadedEvidence [] [] (.gate .webkit) |>.startsWith "trajectory hero pending (no stored run); morph pending (no stored run)"
#guard threadedEvidence [] [stPass .macWebkit .hero] (.gate .webkit) |>.startsWith
  "trajectory hero pass (run 9 mac-webkit pass); morph pending"
#guard threadedEvidence [] [stFail .linuxWebkit, stFail .macWebkit] (.gate .webkit) |>.startsWith
  "trajectory hero fail (run 9 linux-webkit fail, run 9 mac-webkit fail); morph pending"
#guard blockers [] [] (stFail .chromium :: [Engine.chromium, .macWebkit].flatMap fun e => walks.map (stPass e))
  heroExitThreaded == [.proofs, .gate .chromium]
#guard refusedMembers lookDecisions [⟨"hero.accent", "draw-nolayout"⟩, ⟨"hero.exit", "threaded"⟩] ==
  [⟨"hero.accent", "draw-nolayout"⟩]
#guard (ledgerDisagreements (Json.mkObj [("findings", .arr #[Json.mkObj [("flag", .str "hero.exit:threaded"),
  ("userDecision", Json.mkObj [("date", .str "2026-10-24"), ("decision", .str "accepted 2026-10-24: same look"),
    ("review", .str "results/phone/2026-10-24-hero-exit-threaded/summary.md")])]])]) ((lookDecisions.drop 3).take 1)).isEmpty
#guard (ledgerDisagreements (Json.mkObj [("findings", .arr #[Json.mkObj [("flag", .str "hero.exit:threaded"),
  ("userDecision", Json.mkObj [("date", .str "2026-10-24"), ("decision", .str "kept; review deferred"),
    ("review", .str "")])]])]) ((lookDecisions.drop 3).take 1)).length == 2

private def threadedRow (status : String) : Row :=
  ⟨threadedKey.1, threadedKey.2, status, some "hero.exit:threaded", none, none⟩

#guard 1 < ((threadedEvidence [threadedRow "proved"] [] .proofs).splitOn "closed by").length &&
  (theoremTokens (threadedEvidence [threadedRow "proved"] [] .proofs)).all fun w =>
    w ∈ (``Fw.Preset.Gen.threaded_proofs_iff :: threadedRowNames).map toString
#guard threadedRowNames.all fun n =>
  (theoremTokens (threadedEvidence [threadedRow "proved"] [] .proofs)).contains n.toString

#guard why links [threadedRow "partly-proved"] heroExitThreaded == .notProved threadedKey "partly-proved"
#guard blockers [] [threadedRow "partly-proved"] (stFail .chromium :: [Engine.chromium, .macWebkit].flatMap fun e =>
  walks.map (stPass e)) heroExitThreaded == [.proofs, .gate .chromium]
#guard blockers [] [threadedRow "proved"] ([Engine.chromium, .macWebkit].flatMap fun e => walks.map (stPass e))
  heroExitThreaded == []
#guard entry [] [threadedRow "proved", threadedRow "proved"] [] heroExitThreaded ==
  .notYet [.proofs, .gate .chromium, .gate .webkit]
#guard threadedEvidence [threadedRow "partly-proved"] [] .proofs |>.startsWith
  "linked to ledger row hero-exit-threaded (v6, KD#2), status partly-proved;"
#guard threadedEvidence [threadedRow "partly-proved"] [] .proofs |>.endsWith "items are open until the row is proved"
#guard threadedEvidence [threadedRow "proved"] [] .proofs |>.endsWith "edgeFrames_le_starts (WebKit edge-frame cost)"
#guard threadedEvidence [] [] .q6 == Fw.Parts.HeroExitScrollOffset.q6Text

private def holdRow (status : String) : Row :=
  let k := ((linkOf links holdFreeze).getD []).headD ("", "")
  ⟨k.1, k.2, status, some holdFreeze.key, none, some .e⟩

private def holdSt (e : Engine) (w : Walk) : Stored :=
  ⟨9, "s", "r", "?fw=platform.glint:hold-freeze", [holdFreeze.key], e, w, Fw.Gate.Trajectory.allowedWidths, []⟩

private def holdAll : List Stored := [Engine.chromium, .macWebkit].flatMap fun e => walks.map (holdSt e)

#guard entry [holdReg .e] [holdRow "proved"] holdAll holdFreeze == .enter
#guard ok [holdReg .e] links [holdRow "proved"] holdAll holdFreeze
#guard entry [holdReg .e] [holdRow "partly-proved"] holdAll holdFreeze == .notYet [.proofs]
#guard entry [holdReg .q] [holdRow "proved"] holdAll holdFreeze == .notYet [.look]
#guard entryGaps [holdReg .e] [holdRow "proved"] holdAll == []
#guard entryGaps [{ holdReg .e with kind := .proposal }] [holdRow "proved"] holdAll == [holdFreeze]
#guard entryGaps [{ holdReg .e with visClass := none }] [holdRow "proved"] holdAll == [holdFreeze]
#guard entryGaps [holdReg .q] [holdRow "proved"] holdAll == []
#guard agreeScope [holdReg .e] holdFreeze && agreeScope [{ holdReg .e with visClass := none }] holdFreeze
#guard !agreeScope [holdReg .q] holdFreeze && !agreeScope [holdReg .l] holdFreeze && !agreeScope [] holdFreeze

private def earnRow (status : String) : Row :=
  let k := ((linkOf links ⟨"nav", "earn-logical"⟩).getD []).headD ("", "")
  ⟨k.1, k.2, status, some "nav:earn-logical", none, some .l⟩

private def earnSt (e : Engine) (w : Walk) : Stored :=
  ⟨9, "s", "r", "?fw=nav:earn-logical", ["nav:earn-logical"], e, w, Fw.Gate.Trajectory.allowedWidths, []⟩

private def earnAll : List Stored := [Engine.chromium, .macWebkit].flatMap fun e => walks.map (earnSt e)

#guard (linkOf links ⟨"nav", "earn-logical"⟩).isSome
#guard why links [earnRow "proved"] ⟨"nav", "earn-logical"⟩ == .proved
#guard entry [earnLogicalReg] [earnRow "proved"] earnAll ⟨"nav", "earn-logical"⟩ == .enter
#guard entry [earnLogicalReg] [earnRow "proved"] [] ⟨"nav", "earn-logical"⟩ == .notYet [.gate .chromium, .gate .webkit]
#guard entry [earnLogicalReg] [earnRow "partly-proved"] earnAll ⟨"nav", "earn-logical"⟩ == .notYet [.proofs]
#guard !ok [earnLogicalReg] links [earnRow "proved"] earnAll ⟨"nav", "earn-logical"⟩
#guard !(preset [earnLogicalReg] links [earnRow "proved"] earnAll).contains ⟨"nav", "earn-logical"⟩
#guard !agreeScope [earnLogicalReg] ⟨"nav", "earn-logical"⟩
#guard entryGaps [earnLogicalReg] [earnRow "proved"] earnAll == []

private def unthrottleReg (c : Option VisClass) : Reg :=
  { flag := ⟨"engine.scroll", "unthrottle"⟩, kind := .optimized, requires := [], conflicts := [], visClass := c }

#guard !agreeScope [unthrottleReg none] ⟨"engine.scroll", "unthrottle"⟩
#guard unclassified [unthrottleReg none] ⟨"engine.scroll", "unthrottle"⟩ && !unclassified [] ⟨"engine.scroll", "unthrottle"⟩
#guard staleLookExceptions [unthrottleReg none] == []
#guard staleLookExceptions [unthrottleReg (some .e)] == lookExceptions
#guard staleLookExceptions [unthrottleReg none, unthrottleReg (some .q)] == lookExceptions

end Fw.Preset.Gen
