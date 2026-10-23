import Lean.Data.Json
/-!
# Profile wire format of the Chromium arm: `kind`, `css`, `dropFlags` and the user agent
Twin: `packages/measure-chromium/src/profile.mjs`, checked against `packages/contracts/golden/measure/profile.jsonl`.
-/
namespace Fw.Measure.Profile
open Lean

inductive Kind where
  | counts
  | probe
  deriving DecidableEq, Repr

def Kind.name : Kind → String
  | .counts => "counts"
  | .probe => "probe"

def Kind.dir : Kind → String
  | .counts => "profiles"
  | .probe => "probes"

def parseKind : Option String → Option Kind
  | none => some .counts
  | some "counts" => some .counts
  | some "probe" => some .probe
  | some _ => none

structure Wire where
  kind : Kind
  mobile : Bool
  css : Option String
  dropFlags : List String
  variants : Nat
  deriving Repr

def pinned : List String :=
  ["--remote-debugging-port=", "--user-data-dir=", "--enable-begin-frame-control", "--run-all-compositor-stages-before-draw"]

def pre (d a : String) : Bool := d.toList.isPrefixOf a.toList

def dropOk (d : String) : Bool :=
  d.length > 2 && pre "--" d && pinned.all (fun p => !pre d p && !pre p d)

def keep (args drops : List String) : List String :=
  args.filter (fun a => !drops.any (fun d => pre d a))

inductive Problem where
  | badKind
  | dropInCounts
  | variantsInCounts
  | badDrop (d : String)
  | emptyCss
  deriving DecidableEq, Repr

def Problem.name : Problem → String
  | .badKind => "badKind"
  | .dropInCounts => "dropInCounts"
  | .variantsInCounts => "variantsInCounts"
  | .badDrop _ => "badDrop"
  | .emptyCss => "emptyCss"

def problem (w : Wire) : Option Problem :=
  if w.kind = .counts ∧ w.dropFlags ≠ [] then some .dropInCounts
  else if w.kind = .counts ∧ w.variants ≠ 0 then some .variantsInCounts
  else match w.dropFlags.find? (fun d => !dropOk d) with
    | some d => some (.badDrop d)
    | none => if w.css = some "" then some .emptyCss else none

def userAgent (mobile : Bool) : String :=
  if mobile then "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Mobile Safari/537.36"
  else "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36"

theorem pre_iff (d a : String) : pre d a = true ↔ d.toList <+: a.toList := by
  simp [pre, List.isPrefixOf_iff_prefix]

theorem parseKind_none : parseKind none = some .counts := rfl
theorem parseKind_counts : parseKind (some "counts") = some .counts := rfl
theorem parseKind_probe : parseKind (some "probe") = some .probe := rfl
theorem parseKind_other (s : String) (h1 : s ≠ "counts") (h2 : s ≠ "probe") : parseKind (some s) = none := by
  unfold parseKind; split <;> simp_all

theorem keep_sublist (args drops : List String) : (keep args drops).Sublist args := List.filter_sublist

theorem keep_nil (args : List String) : keep args [] = args := by simp [keep]

theorem mem_keep (args drops : List String) (a : String) :
    a ∈ keep args drops ↔ a ∈ args ∧ ∀ d ∈ drops, pre d a = false := by
  simp [keep]

theorem pinned_kept (args drops : List String) (a p : String) (hd : ∀ d ∈ drops, dropOk d = true)
    (ha : a ∈ args) (hp : p ∈ pinned) (hpa : pre p a = true) : a ∈ keep args drops := by
  refine (mem_keep args drops a).2 ⟨ha, fun d hm => ?_⟩
  have hok := hd d hm
  simp only [dropOk, Bool.and_eq_true, List.all_eq_true, Bool.not_eq_true'] at hok
  have ⟨hdp, hpd⟩ := hok.2 p hp
  cases h : pre d a with
  | false => rfl
  | true =>
    rw [pre_iff] at h hpa
    rcases List.prefix_or_prefix_of_prefix h hpa with h' | h'
    · rw [← pre_iff] at h'; simp_all
    · rw [← pre_iff] at h'; simp_all

theorem problem_dropInCounts (w : Wire) (hk : w.kind = .counts) (hd : w.dropFlags ≠ []) :
    problem w = some .dropInCounts := by
  simp [problem, hk, hd]

theorem problem_variantsInCounts (w : Wire) (hk : w.kind = .counts) (hd : w.dropFlags = []) (hv : w.variants ≠ 0) :
    problem w = some .variantsInCounts := by
  simp [problem, hk, hd, hv]

theorem problem_badDrop (w : Wire) (d : String) (hk : w.kind = .probe) (hf : w.dropFlags.find? (fun d => !dropOk d) = some d) :
    problem w = some (.badDrop d) := by
  simp [problem, hk, hf]

theorem find_none_iff (ds : List String) : ds.find? (fun d => !dropOk d) = none ↔ ∀ d ∈ ds, dropOk d = true := by
  rw [List.find?_eq_none]; simp

private theorem problem_rest (w : Wire) (h1 : ¬(w.kind = .counts ∧ w.dropFlags ≠ [])) (h2 : ¬(w.kind = .counts ∧ w.variants ≠ 0)) :
    problem w = match w.dropFlags.find? (fun d => !dropOk d) with
      | some d => some (.badDrop d)
      | none => if w.css = some "" then some .emptyCss else none := by
  unfold problem; simp only [h1, h2, ↓reduceIte]

theorem problem_emptyCss (w : Wire) (hc : w.css = some "") (hk : w.kind = .probe ∨ (w.dropFlags = [] ∧ w.variants = 0))
    (hd : ∀ d ∈ w.dropFlags, dropOk d = true) : problem w = some .emptyCss := by
  have h1 : ¬(w.kind = .counts ∧ w.dropFlags ≠ []) := by
    rcases hk with hk | ⟨hd0, _⟩
    · rw [hk]; exact fun h => nomatch h.1
    · exact fun h => h.2 hd0
  have h2 : ¬(w.kind = .counts ∧ w.variants ≠ 0) := by
    rcases hk with hk | ⟨_, hv⟩
    · rw [hk]; exact fun h => nomatch h.1
    · exact fun h => h.2 hv
  rw [problem_rest w h1 h2, (find_none_iff _).2 hd]; simp only [hc, ↓reduceIte]

theorem problem_eq_none (w : Wire) : problem w = none ↔
    (w.kind = .counts → w.dropFlags = [] ∧ w.variants = 0) ∧ (∀ d ∈ w.dropFlags, dropOk d = true) ∧ w.css ≠ some "" := by
  constructor
  · intro h
    have hk : w.kind = .counts → w.dropFlags = [] ∧ w.variants = 0 := fun hk => by
      have hd : w.dropFlags = [] := Classical.byContradiction fun hd => by rw [problem_dropInCounts w hk hd] at h; cases h
      refine ⟨hd, Classical.byContradiction fun hv => ?_⟩
      rw [problem_variantsInCounts w hk hd hv] at h; cases h
    have h1 : ¬(w.kind = .counts ∧ w.dropFlags ≠ []) := fun h' => h'.2 (hk h'.1).1
    have h2 : ¬(w.kind = .counts ∧ w.variants ≠ 0) := fun h' => h'.2 (hk h'.1).2
    rw [problem_rest w h1 h2] at h
    cases hf : w.dropFlags.find? (fun d => !dropOk d) with
    | some d => rw [hf] at h; cases h
    | none =>
      rw [hf] at h
      refine ⟨hk, (find_none_iff _).1 hf, fun hc => ?_⟩
      simp only [hc, ↓reduceIte] at h; cases h
  · intro ⟨hk, hall, hc⟩
    have h1 : ¬(w.kind = .counts ∧ w.dropFlags ≠ []) := fun h' => h'.2 (hk h'.1).1
    have h2 : ¬(w.kind = .counts ∧ w.variants ≠ 0) := fun h' => h'.2 (hk h'.1).2
    rw [problem_rest w h1 h2, (find_none_iff _).2 hall]; simp only [hc, ↓reduceIte]

theorem userAgent_mobile : userAgent true = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Mobile Safari/537.36" := rfl
theorem userAgent_desktop : userAgent false = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36" := rfl

private def keepCases : List (List String × List String) :=
  let a := ["--remote-debugging-port=9222", "--no-sandbox", "--disable-gpu", "--user-data-dir=/tmp/p", "--enable-begin-frame-control",
    "--run-all-compositor-stages-before-draw", "--font-render-hinting=none", "--lang=en-US", "about:blank"]
  [(a, []), (a, ["--disable-gpu"]), (a, ["--font-render-hinting", "--lang"]), (a, ["--no"]), (a, ["--x"]), ([], ["--lang"])]

private def dropCases : List String :=
  ["--disable-gpu", "--lang", "--", "-x", "--x", "--remote", "--user-data-dir=/x", "--enable-begin-frame-control", "--run-all", "--enable"]

private def wireJson (w : Wire) : Json :=
  Json.mkObj [("kind", w.kind.name), ("mobile", w.mobile), ("css", match w.css with | some c => Json.str c | none => Json.null),
    ("dropFlags", toJson w.dropFlags), ("variants", w.variants)]

private def wireCases : List Wire :=
  [⟨.counts, true, none, [], 0⟩, ⟨.counts, false, some "*{text-wrap:wrap!important}", [], 0⟩, ⟨.counts, false, none, ["--lang"], 0⟩,
   ⟨.counts, false, none, [], 3⟩, ⟨.probe, false, none, ["--lang", "--disable-gpu"], 4⟩, ⟨.probe, false, none, ["--remote"], 0⟩,
   ⟨.probe, false, some "", [], 2⟩, ⟨.counts, true, some "", [], 0⟩, ⟨.probe, true, some "h2{color:red}", [], 0⟩]

private def kindCases : List (Option String) := [none, some "counts", some "probe", some "Probe", some ""]

def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("pinned", toJson pinned), ("ua", Json.mkObj [("mobile", userAgent true), ("desktop", userAgent false)]),
     ("dirs", Json.mkObj [("counts", Kind.counts.dir), ("probe", Kind.probe.dir)])]).compress] ++
  (kindCases.map fun k => (Json.mkObj [("kind", "parseKind"), ("in", match k with | some s => Json.str s | none => Json.null),
     ("out", match parseKind k with | some x => Json.str x.name | none => Json.null)]).compress) ++
  (dropCases.map fun (d : String) => (Json.mkObj [("kind", "dropOk"), ("drop", Json.str d), ("ok", toJson (dropOk d))]).compress) ++
  (keepCases.map fun (a, ds) => (Json.mkObj [("kind", "keep"), ("args", toJson a), ("drops", toJson ds), ("out", toJson (keep a ds))]).compress) ++
  (wireCases.map fun w => (Json.mkObj [("kind", "wire"), ("wire", wireJson w),
     ("problem", match problem w with | some p => Json.str p.name | none => Json.null), ("dir", w.kind.dir), ("ua", userAgent w.mobile)]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"profile golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"profile golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

#guard keep ["--lang=en-US", "--remote-debugging-port=9222"] ["--lang"] == ["--remote-debugging-port=9222"]
#guard dropOk "--remote" == false
#guard dropOk "--user-data-dir=/x" == false
#guard dropOk "--disable-gpu" == true

end Fw.Measure.Profile
