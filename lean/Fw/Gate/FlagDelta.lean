import Lean.Data.Json
import Fw.Wire.Gate
import Fw.Gate.Settle
import Fw.Parts.MorphPanelOpt
import Fw.Parts.MorphColumnsScale
namespace Fw.Gate.FlagDelta
open Fw.Gate

inductive Look where
  | e
  | q
  | l
  deriving DecidableEq, Repr

structure Delta where
  id : String
  flag : String
  part : String
  role : String
  property : String
  orig : String
  rewrite : String
  look : Look
  reason : String
  premise : Lean.Name

def deltas : List Delta :=
  [ { id := "panel-rest-section-filter", flag := "morph.panel:rest", part := "platform", role := "section",
      property := "filter", orig := "blur(0px)", rewrite := "none", look := .e,
      reason := "at rest the variant draws no filter where the original draws blur(0px); invisible under RG10, which panel-rest-n11 measured on the rewrite DOM",
      premise := ``Fw.Parts.MorphPanelOpt.rest_visSame_E },
    { id := "panel-rest-scene-filter", flag := "morph.panel:rest", part := "engine.scene", role := "scene",
      property := "filter", orig := "blur(0px)", rewrite := "none", look := .e,
      reason := "at rest the variant draws no filter where the original draws blur(0px); invisible under RG10, which panel-rest-n11 measured on the rewrite DOM",
      premise := ``Fw.Parts.MorphPanelOpt.rest_visSame_E },
    { id := "final-scale-col-flex-basis", flag := "morph.columns:final-scale", part := "morph.columns", role := "col",
      property := "flex-basis", orig := "0px", rewrite := "auto", look := .l,
      reason := "the columns keep the final-width layout (flex: none) and a horizontal scale draws the base edges; a look change",
      premise := ``Fw.Parts.MorphColumnsScale.layout_const },
    { id := "final-scale-col-flex-grow", flag := "morph.columns:final-scale", part := "morph.columns", role := "col",
      property := "flex-grow", orig := "1", rewrite := "0", look := .l,
      reason := "the columns keep the final-width layout (flex: none) and a horizontal scale draws the base edges; a look change",
      premise := ``Fw.Parts.MorphColumnsScale.layout_const },
    { id := "final-scale-col-flex-shrink", flag := "morph.columns:final-scale", part := "morph.columns", role := "col",
      property := "flex-shrink", orig := "1", rewrite := "0", look := .l,
      reason := "the columns keep the final-width layout (flex: none) and a horizontal scale draws the base edges; a look change",
      premise := ``Fw.Parts.MorphColumnsScale.layout_const } ]

structure DItem where
  cls : Cls
  role : String
  key : String
  status : Status
  byRect : Bool := false
  orig : Option String
  rewrite : Option String
  deriving DecidableEq, Repr

def Delta.matches (d : Delta) (flags : List String) (part : String) (it : DItem) : Bool :=
  flags.contains d.flag && d.part == part && it.cls == .style && !it.byRect && it.status == .differ &&
    d.role == it.role && d.property == it.key && it.orig == some d.orig && it.rewrite == some d.rewrite

def excuseItem (flags : List String) (part : String) (it : DItem) : Option Delta :=
  deltas.find? (·.matches flags part it)

def allExcused (flags : List String) (part : String) (fails : List DItem) : Bool :=
  !fails.isEmpty && fails.all fun it => (excuseItem flags part it).isSome

def readingVerdict (flags : List String) (part : String) (v : Verdict) (fails : List DItem) : Verdict :=
  if v == .fail && allExcused flags part fails then .pass else v

def excusedItems (flags : List String) (part : String) (v : Verdict) (fails : List DItem) : List (DItem × String) :=
  if v == .fail && allExcused flags part fails then
    fails.filterMap fun it => (excuseItem flags part it).map fun d => (it, d.id)
  else []

theorem matches_spec (d : Delta) (flags : List String) (part : String) (it : DItem) :
    d.matches flags part it = true ↔ d.flag ∈ flags ∧ d.part = part ∧ it.cls = .style ∧ it.byRect = false ∧
      it.status = .differ ∧ d.role = it.role ∧ d.property = it.key ∧ it.orig = some d.orig ∧ it.rewrite = some d.rewrite := by
  simp only [Delta.matches, Bool.and_eq_true, beq_iff_eq, List.contains_iff_mem, Bool.not_eq_true']
  constructor
  · rintro ⟨⟨⟨⟨⟨⟨⟨⟨a, b⟩, c⟩, e⟩, f⟩, g⟩, h⟩, i⟩, j⟩; exact ⟨a, b, c, e, f, g, h, i, j⟩
  · rintro ⟨a, b, c, e, f, g, h, i, j⟩; exact ⟨⟨⟨⟨⟨⟨⟨⟨a, b⟩, c⟩, e⟩, f⟩, g⟩, h⟩, i⟩, j⟩

theorem excuseItem_spec {flags : List String} {part : String} {it : DItem} {d : Delta} (h : excuseItem flags part it = some d) :
    d ∈ deltas ∧ d.matches flags part it = true := by
  have h' : deltas.find? (·.matches flags part it) = some d := h
  have hp := List.find?_some h'
  exact ⟨List.mem_of_find?_eq_some h', hp⟩

theorem excused_only_flag_on {flags : List String} {part : String} {it : DItem} {d : Delta}
    (h : excuseItem flags part it = some d) : d.flag ∈ flags :=
  ((matches_spec d flags part it).1 (excuseItem_spec h).2).1

theorem deltas_enumerated {flags : List String} {part : String} {it : DItem} {d : Delta}
    (h : excuseItem flags part it = some d) :
    d ∈ deltas ∧ d.part = part ∧ it.cls = .style ∧ it.status = .differ ∧ it.role = d.role ∧ it.key = d.property ∧
      it.orig = some d.orig ∧ it.rewrite = some d.rewrite := by
  obtain ⟨hm, hx⟩ := excuseItem_spec h
  obtain ⟨_, b, c, _, f, g, k, i, j⟩ := (matches_spec d flags part it).1 hx
  exact ⟨hm, b, c, f, g.symm, k.symm, i, j⟩

theorem unlisted_item_fails {flags : List String} {part : String} {fails : List DItem} {it : DItem}
    (hi : it ∈ fails) (hn : excuseItem flags part it = none) : readingVerdict flags part .fail fails = .fail := by
  have : allExcused flags part fails = false := by
    simp only [allExcused, Bool.and_eq_false_iff, Bool.not_eq_false', List.isEmpty_iff, List.all_eq_false]
    exact .inr ⟨it, hi, by simp [hn]⟩
  simp [readingVerdict, this]

theorem flags_off_unchanged {flags : List String} (hoff : ∀ d ∈ deltas, d.flag ∉ flags) (part : String) (v : Verdict)
    (fails : List DItem) : readingVerdict flags part v fails = v := by
  have hn : ∀ it, excuseItem flags part it = none := fun it => by
    cases h : excuseItem flags part it with
    | none => rfl
    | some d => exact absurd (excused_only_flag_on h) (hoff d (excuseItem_spec h).1)
  cases hf : fails with
  | nil => simp [readingVerdict, allExcused]
  | cons it _ =>
    by_cases hv : v = .fail
    · subst hv; rw [← hf]; exact unlisted_item_fails (by rw [hf]; exact List.mem_cons_self) (hn it)
    · simp [readingVerdict, hv]

theorem no_flags_unchanged (part : String) (v : Verdict) (fails : List DItem) : readingVerdict [] part v fails = v :=
  flags_off_unchanged (fun _ _ h => by cases h) part v fails

theorem readingVerdict_changes (flags : List String) (part : String) (v : Verdict) (fails : List DItem)
    (h : readingVerdict flags part v fails ≠ v) : v = .fail ∧ readingVerdict flags part v fails = .pass := by
  by_cases hc : (v == .fail && allExcused flags part fails) = true
  · simp only [Bool.and_eq_true, beq_iff_eq] at hc
    exact ⟨hc.1, by simp [readingVerdict, hc]⟩
  · simp [readingVerdict, hc] at h

theorem excused_all_printed {flags : List String} {part : String} {fails : List DItem} {it : DItem}
    (hp : readingVerdict flags part .fail fails = .pass) (hi : it ∈ fails) :
    ∃ d, excuseItem flags part it = some d ∧ (it, d.id) ∈ excusedItems flags part .fail fails := by
  have ha : allExcused flags part fails = true := by
    unfold readingVerdict at hp; split at hp
    · simp_all
    · cases hp
  have hs := (List.all_eq_true.1 (by simp only [allExcused, Bool.and_eq_true] at ha; exact ha.2)) it hi
  obtain ⟨d, hd⟩ := Option.isSome_iff_exists.1 hs
  refine ⟨d, hd, ?_⟩
  simp only [excusedItems, ha, beq_self_eq_true, Bool.and_self, ite_true, List.mem_filterMap]
  exact ⟨it, hi, by simp [hd]⟩

def relabel (flags : List String) (part : String) (it : DItem) : Status :=
  if (excuseItem flags part it).isSome then .equal else it.status

theorem excused_differ {flags : List String} {part : String} {it : DItem} (h : (excuseItem flags part it).isSome = true) :
    it.status = .differ := by
  obtain ⟨d, hd⟩ := Option.isSome_iff_exists.1 h
  exact (deltas_enumerated hd).2.2.2.1

theorem readingVerdict_relabel (flags : List String) (part : String) (L : List DItem) :
    cellVerdict (L.map (relabel flags part)) =
      readingVerdict flags part (cellVerdict (L.map (·.status))) (L.filter fun it => failsS it.status) := by
  have fs : ∀ s : Status, failsS s = true ↔ s ≠ .na ∧ s ≠ .equal := by
    intro s; cases s <;> simp [failsS]
  by_cases hF : ∃ it ∈ L, failsS it.status = true
  · obtain ⟨w, hw, hwf⟩ := hF
    have hfail : cellVerdict (L.map (·.status)) = .fail :=
      (cellVerdict_fail_iff _).2 ⟨w.status, List.mem_map_of_mem hw, (fs _).1 hwf⟩
    rw [hfail]
    by_cases hA : allExcused flags part (L.filter fun it => failsS it.status) = true
    · have hr : readingVerdict flags part .fail (L.filter fun it => failsS it.status) = .pass := by
        simp [readingVerdict, hA]
      rw [hr, cellVerdict_pass_iff]
      have hall := List.all_eq_true.1 (by simp only [allExcused, Bool.and_eq_true] at hA; exact hA.2)
      refine ⟨⟨relabel flags part w, List.mem_map_of_mem hw, ?_⟩, ?_⟩
      · have := hall w (List.mem_filter.2 ⟨hw, hwf⟩); simp [relabel, this]
      · intro s hs
        obtain ⟨it, hit, rfl⟩ := List.mem_map.1 hs
        by_cases he : (excuseItem flags part it).isSome = true
        · exact .inr (by simp [relabel, he])
        · have hnf : failsS it.status = false := by
            cases h : failsS it.status
            · rfl
            · exact absurd (hall it (List.mem_filter.2 ⟨hit, h⟩)) he
          simp only [relabel, he]
          cases hs' : it.status <;> simp_all [failsS]
    · have hr : readingVerdict flags part .fail (L.filter fun it => failsS it.status) = .fail := by
        simp [readingVerdict, hA]
      rw [hr, cellVerdict_fail_iff]
      have hne : (L.filter fun it => failsS it.status).isEmpty = false := by
        cases h : (L.filter fun it => failsS it.status).isEmpty
        · rfl
        · exact absurd (List.isEmpty_iff.1 h ▸ List.mem_filter.2 ⟨hw, hwf⟩) (List.not_mem_nil)
      have : ¬ (L.filter fun it => failsS it.status).all (fun it => (excuseItem flags part it).isSome) = true := by
        intro h; exact hA (by simp only [allExcused, hne, h]; rfl)
      obtain ⟨u, huL, huf, hun⟩ : ∃ u, u ∈ L ∧ failsS u.status = true ∧ excuseItem flags part u = none := by
        simpa [List.all_eq_true] using this
      exact ⟨relabel flags part u, List.mem_map_of_mem huL, by simpa [relabel, hun] using (fs _).1 huf⟩
  · have hnot : ∀ it ∈ L, failsS it.status = false := fun it hi => by
      cases h : failsS it.status
      · rfl
      · exact absurd ⟨it, hi, h⟩ hF
    have hfil : (L.filter fun it => failsS it.status) = [] := List.filter_eq_nil_iff.2 (by simp_all)
    rw [hfil]
    simp only [readingVerdict, allExcused, List.isEmpty_nil, Bool.not_true, Bool.false_and, Bool.and_false]
    simp only [Bool.false_eq_true, ite_false]
    congr 1
    apply List.map_congr_left
    intro it hi
    have he : (excuseItem flags part it).isSome = false := by
      cases h : (excuseItem flags part it).isSome
      · rfl
      · have hd := excused_differ h; have := hnot it hi; simp [hd, failsS] at this
    simp [relabel, he]

def flagOk (f : String) : Bool :=
  match f.splitOn ":" with
  | [p, v] => !p.isEmpty && !v.isEmpty && (p ++ v).all fun c => c.isAlphanum || c == '.' || c == '-' || c == '_'
  | _ => false

def flagsOfSearch (s : String) : Option (List String) :=
  let body := if s.startsWith "?" then (s.drop 1).toString else s
  if body.isEmpty then some [] else
  let step (acc : List String) (seg : String) : Option (List String) :=
    match seg.splitOn "=" with
    | name :: rest =>
      if name.any (· == '%') then none
      else if name != "fw" then some acc
      else match rest with
        | [value] =>
          let fs := (value.splitOn ",").filter (· != "")
          if fs.all flagOk then some (acc ++ fs) else none
        | _ => none
    | [] => some acc
  ((body.splitOn "&").foldlM step []).map List.eraseDups

#guard flagsOfSearch "" == some []
#guard flagsOfSearch "?fw=morph.panel:rest" == some ["morph.panel:rest"]
#guard flagsOfSearch "?fw=morph.columns:final-scale,morph.panel:rest&x=1" == some ["morph.columns:final-scale", "morph.panel:rest"]
#guard flagsOfSearch "?fw=a:b&fw=c:d&fw=a:b" == some ["a:b", "c:d"]
#guard flagsOfSearch "?fw=a:b%2Cc:d" == none
#guard flagsOfSearch "?f%77=a:b" == none
#guard flagsOfSearch "?fw" == none
#guard flagsOfSearch "?fw=a" == none
#guard flagsOfSearch "?other=1" == some []

def styleItem (role key a b : String) : DItem :=
  { cls := .style, role, key, status := .differ, orig := some a, rewrite := some b }

def sectionFilter : DItem := styleItem "section" "filter" "blur(0px)" "none"

def sceneFilter : DItem := styleItem "scene" "filter" "blur(0px)" "none"

def flexItems : List DItem :=
  [styleItem "col" "flex-basis" "0px" "auto", styleItem "col" "flex-grow" "1" "0", styleItem "col" "flex-shrink" "1" "0"]

def restOn : List String := ["morph.panel:rest"]

def scaleOn : List String := ["morph.columns:final-scale"]

#guard readingVerdict restOn "platform" .fail [sectionFilter] == .pass
#guard readingVerdict restOn "engine.scene" .fail [sceneFilter] == .pass
#guard readingVerdict [] "platform" .fail [sectionFilter] == .fail
#guard readingVerdict scaleOn "platform" .fail [sectionFilter] == .fail
#guard readingVerdict restOn "engine.scene" .fail [sectionFilter] == .fail
#guard readingVerdict restOn "platform" .fail [sectionFilter, styleItem "section" "opacity" "1" "0.5"] == .fail
#guard readingVerdict restOn "platform" .fail [styleItem "section" "filter" "blur(1px)" "none"] == .fail
#guard readingVerdict restOn "platform" .fail [{ sectionFilter with byRect := true }] == .fail
#guard readingVerdict restOn "platform" .fail [{ sectionFilter with cls := .box }] == .fail
#guard readingVerdict restOn "platform" .fail [] == .fail
#guard readingVerdict restOn "platform" .nc [sectionFilter] == .nc
#guard readingVerdict restOn "platform" .pass [] == .pass
#guard readingVerdict scaleOn "morph.columns" .fail (flexItems ++ flexItems) == .pass
#guard readingVerdict scaleOn "morph.columns" .fail (flexItems ++ [styleItem "col" "width" "60px" "62px"]) == .fail
#guard readingVerdict (restOn ++ scaleOn) "morph.columns" .fail flexItems == .pass
#guard (excusedItems restOn "platform" .fail [sectionFilter]).map (·.2) == ["panel-rest-section-filter"]
#guard excusedItems restOn "platform" .fail [sectionFilter, styleItem "section" "opacity" "1" "0.5"] == []

open Lean (Json toJson)

def lookName : Look → String
  | .e => "E" | .q => "Q" | .l => "L"

def optJson : Option String → Json
  | some s => .str s
  | none => .null

def itemJson (it : DItem) : Json :=
  Json.mkObj [("cls", .str (Fw.Wire.Gate.clsName it.cls)), ("role", .str it.role), ("key", .str it.key),
    ("status", .str (Fw.Wire.Gate.statusName it.status)), ("byRect", .bool it.byRect), ("a", optJson it.orig),
    ("b", optJson it.rewrite)]

def deltaLine (d : Delta) : String :=
  (Json.mkObj [("kind", "delta"), ("id", .str d.id), ("flag", .str d.flag), ("part", .str d.part), ("role", .str d.role),
    ("property", .str d.property), ("orig", .str d.orig), ("rewrite", .str d.rewrite), ("look", .str (lookName d.look)),
    ("reason", .str d.reason), ("premise", .str d.premise.toString)]).compress

def searchLine (s : String) : String :=
  (Json.mkObj [("kind", "search"), ("search", .str s),
    ("flags", match flagsOfSearch s with | some fs => toJson fs | none => .null)]).compress

def readingLine (flags : List String) (part : String) (v : Verdict) (fails : List DItem) : String :=
  (Json.mkObj [("kind", "reading"), ("flags", toJson flags), ("part", .str part),
    ("v", .str (Fw.Wire.Gate.verdictName v)), ("fails", Json.arr (fails.map itemJson).toArray),
    ("out", .str (Fw.Wire.Gate.verdictName (readingVerdict flags part v fails))),
    ("excused", toJson ((excusedItems flags part v fails).map (·.2)))]).compress

def searchCases : List String :=
  ["", "?fw=morph.panel:rest", "?fw=morph.columns:final-scale", "?fw=morph.columns:final-scale,morph.panel:rest&x=1",
   "?fw=a:b&fw=c:d&fw=a:b", "?fw=a:b%2Cc:d", "?f%77=a:b", "?fw", "?fw=a", "?fw=a:b:c", "?other=1", "fw=a:b", "?fw=,a:b,"]

def readingCases : List (List String × String × Verdict × List DItem) :=
  [ (restOn, "platform", .fail, [sectionFilter]),
    (restOn, "engine.scene", .fail, [sceneFilter]),
    (restOn, "engine.scene", .fail, [sceneFilter, sceneFilter]),
    ([], "platform", .fail, [sectionFilter]),
    (scaleOn, "platform", .fail, [sectionFilter]),
    (restOn, "engine.scene", .fail, [sectionFilter]),
    (restOn, "nav", .fail, [sectionFilter]),
    (restOn, "platform", .fail, [sectionFilter, styleItem "section" "opacity" "1" "0.5"]),
    (restOn, "platform", .fail, [styleItem "section" "filter" "blur(1px)" "none"]),
    (restOn, "platform", .fail, [styleItem "section" "filter" "blur(0px)" "blur(0px)"]),
    (restOn, "platform", .fail, [{ sectionFilter with byRect := true }]),
    (restOn, "platform", .fail, [{ sectionFilter with cls := .box }]),
    (restOn, "platform", .fail, [{ sectionFilter with status := .missing }]),
    (restOn, "platform", .fail, [{ sectionFilter with rewrite := none }]),
    (restOn, "platform", .fail, []),
    (restOn, "platform", .nc, [sectionFilter]),
    (restOn, "platform", .pass, []),
    (restOn, "platform", .unreachable .wholeWidth, []),
    (scaleOn, "morph.columns", .fail, flexItems),
    (scaleOn, "morph.columns", .fail, flexItems ++ flexItems ++ flexItems),
    (scaleOn, "morph.columns", .fail, flexItems ++ [styleItem "col" "width" "60px" "62px"]),
    (scaleOn, "morph.columns", .fail, [styleItem "col" "flex-grow" "1" "1"]),
    (restOn, "morph.columns", .fail, flexItems),
    (restOn ++ scaleOn, "morph.columns", .fail, flexItems),
    (restOn ++ scaleOn, "platform", .fail, [sectionFilter]) ]

def goldenLines (_ : Unit := ()) : List String :=
  deltas.map deltaLine ++ searchCases.map searchLine ++
    readingCases.map fun (f, p, v, fs) => readingLine f p v fs

def goldenText (_ : Unit := ()) : String := String.intercalate "" ((goldenLines ()).map (· ++ "\n"))

def run (args : List String) : IO UInt32 := do
  match Fw.Gate.Settle.argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"flag-delta golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"flag-delta golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print (goldenText ())
    return 0

end Fw.Gate.FlagDelta
