import Lean.Data.Json
import Fw.Gate.FlagDelta
import Fw.Gate.Compare

namespace Fw.Gate.Replaced
open Fw.Gate Fw.Gate.FlagDelta

def absent (it : DItem) : Bool :=
  it.cls == .count && it.key == "count" && !it.byRect && it.status == .differ && it.rewriteCount == some 0

def hits (e : ReplacedPart) (flags : List String) (part : String) (it : DItem) : Bool :=
  flags.contains e.flag && e.part == part && absent it

def excuseEntry (es : List ReplacedPart) (flags : List String) (part : String) (it : DItem) : Option ReplacedPart :=
  es.find? (hits · flags part it)

inductive Excuse where
  | delta (d : Delta)
  | replaced (e : ReplacedPart)

def Excuse.id : Excuse → String
  | .delta d => d.id
  | .replaced e => e.id

def Excuse.by : Excuse → String
  | .delta _ => "delta"
  | .replaced _ => "replaced"

def excuse (es : List ReplacedPart) (flags : List String) (part : String) (it : DItem) : Option Excuse :=
  match excuseItem flags part it with
  | some d => some (.delta d)
  | none => (excuseEntry es flags part it).map .replaced

def allExcused (es : List ReplacedPart) (flags : List String) (part : String) (fails : List DItem) : Bool :=
  !fails.isEmpty && fails.all fun it => (excuse es flags part it).isSome

def readingVerdict (es : List ReplacedPart) (flags : List String) (part : String) (v : Verdict) (fails : List DItem) :
    Verdict :=
  if v == .fail && allExcused es flags part fails then .pass else v

def excusedItems (es : List ReplacedPart) (flags : List String) (part : String) (v : Verdict) (fails : List DItem) :
    List (DItem × Excuse) :=
  if v == .fail && allExcused es flags part fails then
    fails.filterMap fun it => (excuse es flags part it).map fun x => (it, x)
  else []

theorem absent_iff (it : DItem) :
    absent it = true ↔ it.cls = .count ∧ it.key = "count" ∧ it.byRect = false ∧ it.status = .differ ∧
      it.rewriteCount = some 0 := by
  simp only [absent, Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true']
  constructor
  · rintro ⟨⟨⟨⟨a, b⟩, c⟩, d⟩, e⟩; exact ⟨a, b, c, d, e⟩
  · rintro ⟨a, b, c, d, e⟩; exact ⟨⟨⟨⟨a, b⟩, c⟩, d⟩, e⟩

theorem countStatus_absent (a : Nat) : countStatus a 0 = .differ ↔ 0 < a := by
  unfold countStatus
  by_cases h : a = 0 <;> simp [h] <;> omega

theorem matches_iff (e : ReplacedPart) (flags : List String) (part : String) (it : DItem) :
    hits e flags part it = true ↔ e.flag ∈ flags ∧ e.part = part ∧ absent it = true := by
  simp only [hits, Bool.and_eq_true, beq_iff_eq, List.contains_iff_mem]
  exact and_assoc

theorem excuseEntry_spec {es : List ReplacedPart} {flags : List String} {part : String} {it : DItem}
    {e : ReplacedPart} (h : excuseEntry es flags part it = some e) :
    e ∈ es ∧ e.flag ∈ flags ∧ e.part = part ∧ absent it = true := by
  have h' : es.find? (hits · flags part it) = some e := h
  have hp := List.find?_some h'
  exact ⟨List.mem_of_find?_eq_some h', (matches_iff e flags part it).1 hp⟩

theorem entry_same_part {es : List ReplacedPart} {flags : List String} {part : String} {it : DItem}
    {e : ReplacedPart} (h : excuseEntry es flags part it = some e) : e.part = part :=
  (excuseEntry_spec h).2.2.1

theorem entry_flag_on {es : List ReplacedPart} {flags : List String} {part : String} {it : DItem}
    {e : ReplacedPart} (h : excuseEntry es flags part it = some e) : e.flag ∈ flags :=
  (excuseEntry_spec h).2.1

theorem entry_absent {es : List ReplacedPart} {flags : List String} {part : String} {it : DItem}
    {e : ReplacedPart} (h : excuseEntry es flags part it = some e) :
    it.cls = .count ∧ it.status = .differ ∧ it.rewriteCount = some 0 := by
  obtain ⟨a, _, _, d, e⟩ := (absent_iff it).1 (excuseEntry_spec h).2.2.2
  exact ⟨a, d, e⟩

theorem excuseEntry_none {es : List ReplacedPart} {flags : List String} {part : String} {it : DItem}
    (h : ∀ e ∈ es, ¬ (e.flag ∈ flags ∧ e.part = part ∧ absent it = true)) : excuseEntry es flags part it = none := by
  cases hx : excuseEntry es flags part it with
  | none => rfl
  | some e => exact absurd (excuseEntry_spec hx).2 (h e (excuseEntry_spec hx).1)

theorem other_part_none {es : List ReplacedPart} {flags : List String} {part : String} (it : DItem)
    (h : ∀ e ∈ es, e.part ≠ part) : excuseEntry es flags part it = none :=
  excuseEntry_none fun e he hx => h e he hx.2.1

theorem present_none (es : List ReplacedPart) (flags : List String) (part : String) {it : DItem}
    (hp : it.rewriteCount ≠ some 0) : excuseEntry es flags part it = none :=
  excuseEntry_none fun _ _ hx => hp ((absent_iff it).1 hx.2.2).2.2.2.2

theorem not_count_none (es : List ReplacedPart) (flags : List String) (part : String) {it : DItem}
    (hc : it.cls ≠ .count) : excuseEntry es flags part it = none :=
  excuseEntry_none fun _ _ hx => hc ((absent_iff it).1 hx.2.2).1

theorem delta_not_count {flags : List String} {part : String} {it : DItem} (hc : it.cls = .count) :
    excuseItem flags part it = none := by
  cases h : excuseItem flags part it with
  | none => rfl
  | some d => rw [(deltas_enumerated h).2.2.1] at hc; cases hc

theorem excuse_not_count (es : List ReplacedPart) (flags : List String) (part : String) {it : DItem}
    (hc : it.cls ≠ .count) : excuse es flags part it = (excuseItem flags part it).map .delta := by
  unfold excuse
  cases excuseItem flags part it with
  | some d => rfl
  | none => simp [not_count_none es flags part hc]

theorem excuse_style (es : List ReplacedPart) (flags : List String) (part : String) {it : DItem}
    (hc : it.cls = .style) : excuse es flags part it = (excuseItem flags part it).map .delta :=
  excuse_not_count es flags part (by rw [hc]; decide)

theorem excuse_count (es : List ReplacedPart) (flags : List String) (part : String) {it : DItem}
    (hc : it.cls = .count) : excuse es flags part it = (excuseEntry es flags part it).map .replaced := by
  simp [excuse, delta_not_count hc]

theorem excuse_nil (flags : List String) (part : String) (it : DItem) :
    excuse [] flags part it = (excuseItem flags part it).map .delta := by
  unfold excuse
  cases excuseItem flags part it <;> rfl

theorem allExcused_nil (flags : List String) (part : String) (fails : List DItem) :
    allExcused [] flags part fails = FlagDelta.allExcused flags part fails := by
  simp [allExcused, FlagDelta.allExcused, excuse_nil]

theorem readingVerdict_nil (flags : List String) (part : String) (v : Verdict) (fails : List DItem) :
    readingVerdict [] flags part v fails = FlagDelta.readingVerdict flags part v fails := by
  simp [readingVerdict, FlagDelta.readingVerdict, allExcused_nil]

theorem excusedItems_nil (flags : List String) (part : String) (v : Verdict) (fails : List DItem) :
    (excusedItems [] flags part v fails).map (fun p => (p.1, p.2.id)) = FlagDelta.excusedItems flags part v fails := by
  unfold excusedItems FlagDelta.excusedItems
  rw [allExcused_nil]
  split
  · rw [List.map_filterMap]
    congr 1
    funext it
    rw [excuse_nil]
    cases excuseItem flags part it <;> rfl
  · rfl

theorem readingVerdict_changes (es : List ReplacedPart) (flags : List String) (part : String) (v : Verdict)
    (fails : List DItem) (h : readingVerdict es flags part v fails ≠ v) :
    v = .fail ∧ readingVerdict es flags part v fails = .pass := by
  by_cases hc : (v == .fail && allExcused es flags part fails) = true
  · simp only [Bool.and_eq_true, beq_iff_eq] at hc
    exact ⟨hc.1, by simp [readingVerdict, hc]⟩
  · simp [readingVerdict, hc] at h

theorem unexcused_fails {es : List ReplacedPart} {flags : List String} {part : String} {fails : List DItem}
    {it : DItem} (hi : it ∈ fails) (hn : excuse es flags part it = none) :
    readingVerdict es flags part .fail fails = .fail := by
  have : allExcused es flags part fails = false := by
    simp only [allExcused, Bool.and_eq_false_iff, Bool.not_eq_false', List.isEmpty_iff, List.all_eq_false]
    exact .inr ⟨it, hi, by simp [hn]⟩
  simp [readingVerdict, this]

theorem present_anchor_fails (es : List ReplacedPart) (flags : List String) (part : String) {fails : List DItem}
    {it : DItem} (hi : it ∈ fails) (hc : it.cls = .count) (hp : it.rewriteCount ≠ some 0) :
    readingVerdict es flags part .fail fails = .fail :=
  unexcused_fails hi (by rw [excuse_count es flags part hc, present_none es flags part hp]; rfl)

theorem other_part_fails {es : List ReplacedPart} (flags : List String) {part : String} {fails : List DItem}
    {it : DItem} (hi : it ∈ fails) (hc : it.cls = .count) (h : ∀ e ∈ es, e.part ≠ part) :
    readingVerdict es flags part .fail fails = .fail :=
  unexcused_fails hi (by rw [excuse_count es flags part hc, other_part_none it h]; rfl)

theorem pass_items {es : List ReplacedPart} {flags : List String} {part : String} {fails : List DItem}
    (hp : readingVerdict es flags part .fail fails = .pass) {it : DItem} (hi : it ∈ fails) :
    (∃ d, excuseItem flags part it = some d) ∨
      ∃ e ∈ es, e.flag ∈ flags ∧ e.part = part ∧ it.cls = .count ∧ it.rewriteCount = some 0 := by
  cases hx : excuse es flags part it with
  | none => rw [unexcused_fails hi hx] at hp; cases hp
  | some x =>
    unfold excuse at hx
    cases hd : excuseItem flags part it with
    | some d => exact .inl ⟨d, rfl⟩
    | none =>
      rw [hd] at hx
      cases he : excuseEntry es flags part it with
      | none => rw [he] at hx; cases hx
      | some e =>
        obtain ⟨m, f, p, _⟩ := excuseEntry_spec he
        obtain ⟨c, _, r⟩ := entry_absent he
        exact .inr ⟨e, m, f, p, c, r⟩

theorem absent_pass {es : List ReplacedPart} {flags : List String} {part : String} {fails : List DItem}
    {e : ReplacedPart} (he : e ∈ es) (hf : e.flag ∈ flags) (hp : e.part = part) (hne : fails ≠ [])
    (ha : ∀ it ∈ fails, absent it = true) : readingVerdict es flags part .fail fails = .pass := by
  have hall : ∀ it ∈ fails, (excuse es flags part it).isSome = true := fun it hi => by
    have hc : it.cls = .count := ((absent_iff it).1 (ha it hi)).1
    rw [excuse_count es flags part hc]
    cases hx : excuseEntry es flags part it with
    | some _ => rfl
    | none =>
      have hfind : (es.find? (hits · flags part it)).isSome = true :=
        List.find?_isSome.2 ⟨e, he, (matches_iff e flags part it).2 ⟨hf, hp, ha it hi⟩⟩
      rw [show excuseEntry es flags part it = es.find? (hits · flags part it) from rfl] at hx
      rw [hx] at hfind; cases hfind
  have : allExcused es flags part fails = true := by
    simp only [allExcused, Bool.and_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff_exists_mem]
    exact ⟨List.exists_mem_of_ne_nil fails hne, List.all_eq_true.2 hall⟩
  simp [readingVerdict, this]

def fixtureMounted (v : String) : Bool := v != "on"

theorem fixture_unmounted_iff (v : String) : fixtureMounted v = false ↔ v = "on" := by
  simp [fixtureMounted]

def fixtureParts : List ReplacedPart :=
  [ { id := "fixture-stage-mount", flag := "fixture.stage:on", part := "morph.mount",
      reason := "test fixture: the fixture flag unmounts the mount target", premise := ``fixture_unmounted_iff },
    { id := "fixture-stage-tween", flag := "fixture.stage:on", part := "morph.tween",
      reason := "test fixture: the fixture flag unmounts the tween scroller", premise := ``fixture_unmounted_iff } ]

def countItem (role : String) (o r : Nat) : DItem :=
  { cls := .count, role, key := "count", status := countStatus o r, orig := none, rewrite := none, rewriteCount := some r }

def stageOn : List String := ["fixture.stage:on"]

def mountGone : DItem := countItem "target" 1 0

def tweenGone : DItem := countItem "scroller" 1 0

#guard absent mountGone
#guard !absent (countItem "target" 1 2)
#guard !absent (countItem "target" 0 0)
#guard !absent { mountGone with rewriteCount := none }
#guard !absent { mountGone with cls := .box }
#guard readingVerdict fixtureParts stageOn "morph.mount" .fail [mountGone] == .pass
#guard readingVerdict fixtureParts stageOn "morph.tween" .fail [tweenGone] == .pass
#guard readingVerdict fixtureParts [] "morph.mount" .fail [mountGone] == .fail
#guard readingVerdict [] stageOn "morph.mount" .fail [mountGone] == .fail
#guard readingVerdict fixtureParts stageOn "platform" .fail [mountGone] == .fail
#guard readingVerdict fixtureParts stageOn "morph.mount" .fail [countItem "target" 1 2] == .fail
#guard readingVerdict fixtureParts stageOn "morph.mount" .fail [mountGone, FlagDelta.styleItem "target" "opacity" "1" "0"] == .fail
#guard readingVerdict fixtureParts stageOn "morph.mount" .fail [] == .fail
#guard readingVerdict fixtureParts stageOn "morph.mount" .nc [mountGone] == .nc
#guard (excusedItems fixtureParts stageOn "morph.mount" .fail [mountGone]).map (·.2.id) == ["fixture-stage-mount"]
#guard readingVerdict fixtureParts (stageOn ++ ["morph.panel:rest"]) "platform" .fail [sectionFilter] == .pass

open Lean (Json toJson)

def entryJson (kind : String) (r : ReplacedPart) : String :=
  (Json.mkObj [("kind", .str kind), ("id", .str r.id), ("flag", .str r.flag), ("part", .str r.part),
    ("reason", .str r.reason), ("premise", .str r.premise.toString)]).compress

def itemJson (it : DItem) : Json :=
  Json.mkObj [("cls", .str (Fw.Wire.Gate.clsName it.cls)), ("role", .str it.role), ("key", .str it.key),
    ("status", .str (Fw.Wire.Gate.statusName it.status)), ("byRect", .bool it.byRect), ("a", optJson it.orig),
    ("b", optJson it.rewrite), ("rewriteCount", match it.rewriteCount with | some n => toJson n | none => .null)]

def excuseJson (p : DItem × Excuse) : Json :=
  Json.mkObj [("id", .str p.2.id), ("by", .str p.2.by)]

def readingLine (fixture : Bool) (flags : List String) (part : String) (v : Verdict) (fails : List DItem) : String :=
  let es := if fixture then fixtureParts else []
  (Json.mkObj [("kind", "reading"), ("entries", .str (if fixture then "fixture" else "none")), ("flags", toJson flags),
    ("part", .str part), ("v", .str (Fw.Wire.Gate.verdictName v)), ("fails", Json.arr (fails.map itemJson).toArray),
    ("out", .str (Fw.Wire.Gate.verdictName (readingVerdict es flags part v fails))),
    ("excused", Json.arr ((excusedItems es flags part v fails).map excuseJson).toArray)]).compress

def readingCases : List (Bool × List String × String × Verdict × List DItem) :=
  [ (true, stageOn, "morph.mount", .fail, [mountGone]),
    (true, stageOn, "morph.tween", .fail, [tweenGone]),
    (true, stageOn, "morph.mount", .fail, [mountGone, mountGone]),
    (true, [], "morph.mount", .fail, [mountGone]),
    (true, ["other.flag:on"], "morph.mount", .fail, [mountGone]),
    (false, stageOn, "morph.mount", .fail, [mountGone]),
    (true, stageOn, "platform", .fail, [mountGone]),
    (true, stageOn, "morph.tween", .fail, [mountGone, countItem "scroller" 1 1]),
    (true, stageOn, "morph.mount", .fail, [countItem "target" 1 2]),
    (true, stageOn, "morph.mount", .fail, [countItem "target" 2 1]),
    (true, stageOn, "morph.mount", .fail, [countItem "target" 0 0]),
    (true, stageOn, "morph.mount", .fail, [{ mountGone with rewriteCount := none }]),
    (true, stageOn, "morph.mount", .fail, [{ mountGone with key := "width" }]),
    (true, stageOn, "morph.mount", .fail, [{ mountGone with byRect := true }]),
    (true, stageOn, "morph.mount", .fail, [{ mountGone with cls := .box }]),
    (true, stageOn, "morph.mount", .fail, [{ mountGone with cls := .style }]),
    (true, stageOn, "morph.mount", .fail, [mountGone, FlagDelta.styleItem "target" "opacity" "1" "0"]),
    (true, stageOn, "morph.mount", .fail, []),
    (true, stageOn, "morph.mount", .nc, [mountGone]),
    (true, stageOn, "morph.mount", .pass, []),
    (true, stageOn, "morph.mount", .unreachable .wholeWidth, []),
    (true, stageOn ++ ["morph.panel:rest"], "platform", .fail, [sectionFilter]),
    (true, stageOn ++ ["morph.panel:rest"], "platform", .fail, [sectionFilter, countItem "section" 1 0]),
    (false, ["morph.panel:rest"], "platform", .fail, [sectionFilter]),
    (false, ["morph.panel:rest"], "platform", .fail, [sectionFilter, FlagDelta.styleItem "section" "opacity" "1" "0.5"]),
    (true, stageOn, "platform", .fail, [sectionFilter]) ]

def goldenLines (_ : Unit := ()) : List String :=
  fixtureParts.map (entryJson "fixture") ++ readingCases.map fun (x, f, p, v, fs) => readingLine x f p v fs

def goldenText (_ : Unit := ()) : String := String.intercalate "" ((goldenLines ()).map (· ++ "\n"))

def run (args : List String) : IO UInt32 := do
  match Fw.Gate.Settle.argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"replaced golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"replaced golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print (goldenText ())
    return 0

end Fw.Gate.Replaced
