import Lean.Data.Json
/-!
# Profile wire format of the Chromium arm: `kind`, `css`, `dropFlags`, the user agent and the lane's system fonts
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

inductive Mode where
  | counts
  | load
  deriving DecidableEq, Repr

def Mode.name : Mode → String
  | .counts => "counts"
  | .load => "load"

def Mode.kind : Mode → Kind
  | .counts => .counts
  | .load => .probe

def runnable (k : Kind) (m : Mode) : Bool := decide (k = m.kind)

theorem counts_refuses_probe : runnable .probe .counts = false := by decide
theorem counts_runs_counts : runnable .counts .counts = true := by decide
theorem load_runs_probe : runnable .probe .load = true := by decide
theorem load_refuses_counts : runnable .counts .load = false := by decide

def resolve (inProfiles inProbes : Bool) : Option Kind :=
  match inProfiles, inProbes with
  | true, false => some .counts
  | false, true => some .probe
  | _, _ => none

def readOk (inProfiles inProbes : Bool) (declared : Kind) : Bool := resolve inProfiles inProbes == some declared

theorem readOk_probe_in_probes : readOk false true .probe = true := by decide
theorem readOk_counts_in_profiles : readOk true false .counts = true := by decide
theorem readOk_refuses_probe_in_profiles : readOk true false .probe = false := by decide
theorem readOk_refuses_counts_in_probes : readOk false true .counts = false := by decide
theorem readOk_refuses_both (k : Kind) : readOk true true k = false := by cases k <;> decide
theorem readOk_refuses_neither (k : Kind) : readOk false false k = false := by cases k <;> decide

theorem readOk_iff (a b : Bool) (k : Kind) : readOk a b k = true ↔
    (a = true ∧ b = false ∧ k = .counts) ∨ (a = false ∧ b = true ∧ k = .probe) := by
  cases a <;> cases b <;> cases k <;> decide

def cftPlatform : String → String → Option String
  | "linux", "x64" => some "linux64"
  | "linux", "arm64" => some "linux-arm64"
  | "darwin", "arm64" => some "mac-arm64"
  | "darwin", "x64" => some "mac-x64"
  | "win32", "x64" => some "win64"
  | _, _ => none

def cftPlatforms : List String := ["linux64", "linux-arm64", "mac-arm64", "mac-x64", "win64"]

def cftExe (plat : String) : String :=
  if plat.startsWith "mac-" then s!"chrome-{plat}/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"
  else if plat = "win64" then s!"chrome-{plat}/chrome.exe"
  else s!"chrome-{plat}/chrome"

def cftUrl (version plat : String) : String :=
  s!"https://storage.googleapis.com/chrome-for-testing-public/{version}/{plat}/chrome-{plat}.zip"

theorem cftPlatform_linux_x64 : cftPlatform "linux" "x64" = some "linux64" := rfl
theorem cftPlatform_linux_arm64 : cftPlatform "linux" "arm64" = some "linux-arm64" := rfl
theorem cftPlatform_darwin_arm64 : cftPlatform "darwin" "arm64" = some "mac-arm64" := rfl
theorem cftPlatform_darwin_x64 : cftPlatform "darwin" "x64" = some "mac-x64" := rfl
theorem cftPlatform_win32_x64 : cftPlatform "win32" "x64" = some "win64" := rfl
theorem cftPlatform_win32_arm64 : cftPlatform "win32" "arm64" = none := rfl

theorem cftPlatforms_nodup : cftPlatforms.Nodup := by decide

theorem cftPlatform_listed (os arch p : String) (h : cftPlatform os arch = some p) : p ∈ cftPlatforms := by
  unfold cftPlatform at h
  split at h <;> simp_all [cftPlatforms]

theorem cftExe_in_archive : ∀ p ∈ cftPlatforms, (cftExe p).startsWith s!"chrome-{p}/" = true := by decide +kernel

def fontPkg : String := "fonts-liberation"

def fontVersion : String := "1:1.07.4-11"

def fontDir : String := "/usr/share/fonts/truetype/liberation"

def fontFamilies : List String := ["Liberation Mono", "Liberation Sans", "Liberation Serif"]

def fontsConfLines : List String :=
  ["<?xml version=\"1.0\"?>", "<!DOCTYPE fontconfig SYSTEM \"fonts.dtd\">", "<fontconfig>", s!"  <dir>{fontDir}</dir>",
   "  <cachedir>/tmp/fontconfig-cache</cachedir>", "</fontconfig>"]

def fontsConf : String := String.intercalate "\n" fontsConfLines ++ "\n"

def fontsOk (found : List String) : Bool := fontFamilies.all (fun f => found.contains f)

theorem fontsOk_nil : fontsOk [] = false := by decide
theorem fontsOk_families : fontsOk fontFamilies = true := by decide

theorem fontsOk_iff (found : List String) : fontsOk found = true ↔ ∀ f ∈ fontFamilies, f ∈ found := by
  simp [fontsOk, List.all_eq_true]

theorem fontsOk_missing (found : List String) (f : String) (hf : f ∈ fontFamilies) (hn : f ∉ found) : fontsOk found = false := by
  cases h : fontsOk found
  · rfl
  · exact absurd ((fontsOk_iff found).1 h f hf) hn

theorem fontsOk_mono (found extra : List String) (h : fontsOk found = true) : fontsOk (found ++ extra) = true :=
  (fontsOk_iff _).2 fun f hf => List.mem_append_left _ ((fontsOk_iff found).1 h f hf)

theorem fontsConf_dir : s!"  <dir>{fontDir}</dir>" ∈ fontsConfLines := by simp [fontsConfLines]

theorem fontsConf_one_dir : (fontsConfLines.filter (fun l => l.startsWith "  <dir>")).length = 1 := by decide +kernel

theorem fontDir_system : fontDir.startsWith "/usr/share/fonts/" = true := by decide +kernel

theorem fontDir_not_snapshot : fontDir.startsWith "/snapshot" = false := by decide +kernel

structure FontSet where
  name : String
  pkgs : List String

def fontSets : List FontSet :=
  [⟨"none", []⟩, ⟨"liberation", ["fonts-liberation"]⟩, ⟨"liberation+dejavu", ["fonts-liberation", "fonts-dejavu-core"]⟩,
   ⟨"liberation+tlwg", ["fonts-liberation", "fonts-thai-tlwg"]⟩, ⟨"liberation+noto", ["fonts-liberation", "fonts-noto-core"]⟩,
   ⟨"liberation+noto+emoji", ["fonts-liberation", "fonts-noto-core", "fonts-noto-color-emoji"]⟩]

theorem fontSets_names_nodup : (fontSets.map (·.name)).Nodup := by decide

structure SetScore where
  name : String
  idx : Nat
  dist : Nat
  notdef : Nat
  pkgs : Nat

def absDiff (a b : Nat) : Nat := if a ≤ b then b - a else a - b

def fontDist (refDoc gotDoc : Nat) (pairs : List (Nat × Nat)) : Nat :=
  absDiff refDoc gotDoc + (pairs.map fun p => absDiff p.1 p.2).sum

theorem absDiff_eq_zero (a b : Nat) : absDiff a b = 0 ↔ a = b := by
  unfold absDiff
  split <;> omega

theorem fontDist_zero_iff (refDoc gotDoc : Nat) (pairs : List (Nat × Nat)) :
    fontDist refDoc gotDoc pairs = 0 ↔ refDoc = gotDoc ∧ ∀ p ∈ pairs, p.1 = p.2 := by
  unfold fontDist
  induction pairs with
  | nil => simp [absDiff_eq_zero]
  | cons q t ih =>
    have h1 := absDiff_eq_zero q.1 q.2
    have h2 := absDiff_eq_zero refDoc gotDoc
    simp only [List.map_cons, List.sum_cons, List.mem_cons, forall_eq_or_imp] at ih ⊢
    constructor
    · intro h
      have hq : absDiff q.1 q.2 = 0 := by omega
      have hrest : absDiff refDoc gotDoc + (t.map fun p => absDiff p.1 p.2).sum = 0 := by omega
      obtain ⟨a, b⟩ := ih.1 hrest
      exact ⟨a, h1.1 hq, b⟩
    · rintro ⟨a, b, c⟩
      have := ih.2 ⟨a, c⟩
      have := h1.2 b
      omega

def fontBefore (a b : SetScore) : Bool :=
  a.dist < b.dist || (a.dist == b.dist && (a.notdef < b.notdef || (a.notdef == b.notdef && (a.pkgs < b.pkgs || (a.pkgs == b.pkgs && a.idx < b.idx)))))

def fontStep (s : SetScore) : Option SetScore → SetScore
  | none => s
  | some q => if fontBefore s q then s else q

def fontPick : List SetScore → Option SetScore
  | [] => none
  | s :: t => some (fontStep s (fontPick t))

theorem fontPick_nil : fontPick [] = none := rfl

theorem fontBefore_irrefl (a : SetScore) : fontBefore a a = false := by
  simp [fontBefore]

theorem fontBefore_trans (a b c : SetScore) (h1 : fontBefore a b = true) (h2 : fontBefore b c = true) : fontBefore a c = true := by
  simp only [fontBefore, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at *
  omega

theorem fontPick_mem : ∀ (l : List SetScore) (p : SetScore), fontPick l = some p → p ∈ l
  | [], p, h => by simp [fontPick] at h
  | s :: t, p, h => by
    simp only [fontPick, Option.some.injEq] at h
    subst h
    cases hq : fontPick t with
    | none => simp [fontStep]
    | some q =>
      have hm := fontPick_mem t q hq
      by_cases hb : fontBefore s q = true
      · simp [fontStep, hb]
      · simp [fontStep, hb, hm]

theorem fontPick_isSome (l : List SetScore) : (fontPick l).isSome = true ↔ l ≠ [] := by
  cases l <;> simp [fontPick]

theorem fontPick_min : ∀ (l : List SetScore) (p : SetScore), fontPick l = some p → ∀ s ∈ l, fontBefore s p = false
  | [], p, h => by simp [fontPick] at h
  | s :: t, p, h => by
    simp only [fontPick, Option.some.injEq] at h
    subst h
    intro x hx
    cases hq : fontPick t with
    | none =>
      have ht : t = [] := by
        cases t with
        | nil => rfl
        | cons a b => have := (fontPick_isSome (a :: b)).2 (by simp); rw [hq] at this; simp at this
      subst ht
      simp at hx; subst hx; simp [fontStep, fontBefore_irrefl]
    | some q =>
      have ih := fontPick_min t q hq
      by_cases hb : fontBefore s q = true
      · have hs : fontStep s (some q) = s := by simp [fontStep, hb]
        rw [hs]
        rcases List.mem_cons.1 hx with rfl | hx
        · exact fontBefore_irrefl _
        · cases hxs : fontBefore x s
          · rfl
          · have := fontBefore_trans x s q hxs hb
            rw [ih x hx] at this
            exact absurd this (by decide)
      · have hs : fontStep s (some q) = q := by simp [fontStep, hb]
        rw [hs]
        rcases List.mem_cons.1 hx with rfl | hx
        · simpa using hb
        · exact ih x hx

def notdefCount (installed : Nat → Bool) : List (Nat × Nat) → Nat
  | [] => 0
  | p :: t => (if installed p.1 then 0 else p.2) + notdefCount installed t

theorem notdefCount_nil (i : Nat → Bool) : notdefCount i [] = 0 := rfl

theorem notdefCount_mono (i j : Nat → Bool) (h : ∀ c, i c = true → j c = true) :
    ∀ l, notdefCount j l ≤ notdefCount i l
  | [] => Nat.le_refl _
  | p :: t => by
    have ih := notdefCount_mono i j h t
    simp only [notdefCount]
    by_cases hi : i p.1 = true
    · simp [hi, h _ hi]; omega
    · by_cases hj : j p.1 = true <;> simp [hi, hj] <;> omega

theorem notdefCount_all (l : List (Nat × Nat)) : notdefCount (fun _ => true) l = 0 := by
  induction l with
  | nil => rfl
  | cons p t ih => simp [notdefCount, ih]

theorem notdefCount_none (l : List (Nat × Nat)) : notdefCount (fun _ => false) l = (l.map (·.2)).sum := by
  induction l with
  | nil => rfl
  | cons p t ih => simp [notdefCount, ih]

def notdefIn (covered : List Nat) (l : List (Nat × Nat)) : Nat := notdefCount (fun c => covered.contains c) l

structure Swipe where
  startY : Nat
  minY : Nat
  dy : Nat
  holdFrames : Nat
  gapFrames : Nat

def Swipe.moves (s : Swipe) : Nat := (s.startY - s.minY) / s.dy

def Swipe.stroke (s : Swipe) : Nat := s.moves + s.holdFrames + s.gapFrames + 2

def Swipe.reach (s : Swipe) : Nat := s.moves * s.dy

def Swipe.strokes (s : Swipe) (scroll : Nat) : Nat := (scroll + s.reach - 1) / s.reach

def Swipe.budget (s : Swipe) (scroll : Nat) : Nat := (4 * s.strokes scroll + 1) * s.stroke

def swipeTouchV1 : Swipe := ⟨880, 100, 10, 0, 2⟩

def fontPageMaxScroll : Nat := 6278 - 932

theorem swipe_strokes_cover (s : Swipe) (scroll : Nat) (h : 0 < s.reach) : scroll ≤ s.strokes scroll * s.reach := by
  unfold Swipe.strokes
  have h1 := Nat.div_add_mod (scroll + s.reach - 1) s.reach
  have h2 := Nat.mod_lt (scroll + s.reach - 1) h
  rw [Nat.mul_comm] at h1
  omega

theorem swipe_budget_ideal (s : Swipe) (scroll : Nat) : s.strokes scroll * s.stroke ≤ s.budget scroll := by
  unfold Swipe.budget
  exact Nat.mul_le_mul_right _ (by omega)

theorem swipe_budget_mono (s : Swipe) (a b : Nat) (h : a ≤ b) : s.budget a ≤ s.budget b := by
  unfold Swipe.budget Swipe.strokes
  exact Nat.mul_le_mul_right _ (by have := Nat.div_le_div_right (c := s.reach) (show a + s.reach - 1 ≤ b + s.reach - 1 by omega); omega)

theorem swipe_budget_quarter (s : Swipe) (scroll p n : Nat) (hreach : 0 < s.reach) (hr : s.reach ≤ 4 * p) (hn : (n - 1) * p < scroll) :
    n * s.stroke ≤ s.budget scroll := by
  have hc := swipe_strokes_cover s scroll hreach
  have h3 : (n - 1) * p < (4 * s.strokes scroll) * p := by
    calc (n - 1) * p < scroll := hn
      _ ≤ s.strokes scroll * s.reach := hc
      _ ≤ s.strokes scroll * (4 * p) := Nat.mul_le_mul_left _ hr
      _ = (4 * s.strokes scroll) * p := by rw [← Nat.mul_assoc, Nat.mul_comm (s.strokes scroll) 4]
  have h4 := Nat.lt_of_mul_lt_mul_right h3
  unfold Swipe.budget
  exact Nat.mul_le_mul_right _ (by omega)

def Swipe.band (s : Swipe) : Nat := s.dy

def Swipe.idleFrames (s : Swipe) : Nat := 2 * s.stroke

def Swipe.ended (s : Swipe) (limit y idle : Nat) : Bool :=
  decide (limit ≤ y) || (decide (limit ≤ y + s.band) && decide (s.idleFrames ≤ idle))

theorem swipe_ended_limit (s : Swipe) (limit y idle : Nat) (h : limit ≤ y) : s.ended limit y idle = true := by
  simp [Swipe.ended, h]

theorem swipe_ended_stall (s : Swipe) (limit y idle : Nat) (hb : limit ≤ y + s.band) (hi : s.idleFrames ≤ idle) :
    s.ended limit y idle = true := by
  simp [Swipe.ended, hb, hi]

theorem swipe_not_ended_far (s : Swipe) (limit y idle : Nat) (h : y + s.band < limit) : s.ended limit y idle = false := by
  have h1 : ¬ limit ≤ y := by omega
  have h2 : ¬ limit ≤ y + s.band := by omega
  simp [Swipe.ended, h1, h2]

theorem swipe_not_ended_moving (s : Swipe) (limit y idle : Nat) (h : y < limit) (hi : idle < s.idleFrames) :
    s.ended limit y idle = false := by
  have h1 : ¬ limit ≤ y := by omega
  have h2 : ¬ s.idleFrames ≤ idle := by omega
  simp [Swipe.ended, h1, h2]

theorem swipe_budget_idle (s : Swipe) (scroll : Nat) (hreach : 0 < s.reach) (hs : 0 < scroll) : s.idleFrames ≤ s.budget scroll := by
  have hc := swipe_strokes_cover s scroll hreach
  have h1 : 0 < s.strokes scroll := by
    rcases Nat.eq_zero_or_pos (s.strokes scroll) with h | h
    · rw [h] at hc; omega
    · exact h
  unfold Swipe.idleFrames Swipe.budget
  have : 2 ≤ 4 * s.strokes scroll + 1 := by omega
  calc 2 * s.stroke ≤ (4 * s.strokes scroll + 1) * s.stroke := Nat.mul_le_mul_right _ this

theorem swipeTouchV1_shape : swipeTouchV1.moves = 78 ∧ swipeTouchV1.stroke = 82 ∧ swipeTouchV1.reach = 780 := by decide

theorem swipeTouchV1_budget : swipeTouchV1.budget fontPageMaxScroll = 2378 := by decide

theorem swipeTouchV1_end : swipeTouchV1.band = 10 ∧ swipeTouchV1.idleFrames = 164 ∧ swipeTouchV1.ended 5346 5342 164 = true ∧
    swipeTouchV1.ended 5346 5342 163 = false := by decide

private def distCases : List (Nat × Nat × List (Nat × Nat)) :=
  [(6000, 6000, []), (6000, 5300, []), (4600, 5300, [(100, 120), (80, 80)]), (5300, 5300, [(10, 10), (20, 20)]), (0, 0, [(5, 0)])]

private def pickCases : List (List SetScore) :=
  [[], [⟨"a", 0, 5, 0, 0⟩], [⟨"a", 0, 5, 1, 1⟩, ⟨"b", 1, 5, 0, 2⟩], [⟨"a", 0, 7, 0, 0⟩, ⟨"b", 1, 3, 9, 3⟩],
   [⟨"a", 0, 3, 2, 2⟩, ⟨"b", 1, 3, 2, 1⟩, ⟨"c", 2, 3, 2, 1⟩], [⟨"a", 0, 3, 2, 2⟩, ⟨"b", 1, 3, 2, 2⟩]]

private def notdefCases : List (List Nat × List (Nat × Nat)) :=
  [([], []), ([], [(9733, 1), (65, 4)]), ([65], [(9733, 1), (65, 4)]), ([65, 9733], [(9733, 1), (65, 4)]), ([3585], [(3585, 7), (9733, 1)])]

def scoreJson (s : SetScore) : Json :=
  Json.mkObj [("name", s.name), ("idx", s.idx), ("dist", s.dist), ("notdef", s.notdef), ("pkgs", s.pkgs)]

private def fontsCases : List (List String) :=
  [[], fontFamilies, ["Liberation Sans"], ["Liberation Mono", "Liberation Sans", "Liberation Sans Narrow", "Liberation Serif"],
   ["DejaVu Sans", "Liberation Mono", "Liberation Sans", "Liberation Serif"], ["Liberation Mono", "Liberation Serif"]]

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

private def cftCases : List (String × String) :=
  [("linux", "x64"), ("linux", "arm64"), ("darwin", "arm64"), ("darwin", "x64"), ("win32", "x64"), ("win32", "arm64"), ("freebsd", "x64"), ("linux", "ia32")]

private def swipeCases : List (Swipe × Nat) :=
  [(swipeTouchV1, 0), (swipeTouchV1, 1), (swipeTouchV1, 780), (swipeTouchV1, 781), (swipeTouchV1, 4626), (swipeTouchV1, fontPageMaxScroll),
   (⟨880, 100, 10, 2, 3⟩, 5346), (⟨500, 100, 25, 0, 0⟩, 3000)]

private def endCases : List (Swipe × Nat × Nat × Nat) :=
  [(swipeTouchV1, 5346, 5346, 0), (swipeTouchV1, 5346, 5400, 0), (swipeTouchV1, 5346, 5345, 0), (swipeTouchV1, 5346, 5342, 164),
   (swipeTouchV1, 5346, 5342, 163), (swipeTouchV1, 5346, 5335, 164), (swipeTouchV1, 5346, 5336, 164), (swipeTouchV1, 5346, 5335, 9999),
   (swipeTouchV1, 5346, 0, 0), (swipeTouchV1, 0, 0, 0),
   (⟨10, 0, 10, 0, 0⟩, 5346, 5342, 6), (⟨10, 0, 10, 0, 0⟩, 5346, 5342, 5), (⟨10, 0, 10, 0, 0⟩, 5346, 5330, 99), (⟨10, 0, 10, 0, 0⟩, 5346, 5346, 0)]

private def swipeJson (s : Swipe) : Json :=
  Json.mkObj [("startY", s.startY), ("minY", s.minY), ("dyPerFrame", s.dy), ("holdFrames", s.holdFrames), ("gapFrames", s.gapFrames)]

private def kindCases : List (Option String) := [none, some "counts", some "probe", some "Probe", some ""]

def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("pinned", toJson pinned), ("ua", Json.mkObj [("mobile", userAgent true), ("desktop", userAgent false)]),
     ("dirs", Json.mkObj [("counts", Kind.counts.dir), ("probe", Kind.probe.dir)])]).compress] ++
  [(Json.mkObj [("kind", "fonts"), ("pkg", fontPkg), ("version", fontVersion), ("dir", fontDir), ("families", toJson fontFamilies),
     ("conf", fontsConf)]).compress] ++
  [(Json.mkObj [("kind", "fontSets"), ("sets", Json.arr (fontSets.map fun f => Json.mkObj [("name", f.name), ("pkgs", toJson f.pkgs)]).toArray)]).compress] ++
  (distCases.map fun (r, g, ps) => (Json.mkObj [("kind", "fontDist"), ("ref", r), ("got", g), ("pairs", toJson (ps.map fun p => [p.1, p.2])),
     ("dist", fontDist r g ps)]).compress) ++
  (pickCases.map fun l => (Json.mkObj [("kind", "fontPick"), ("scores", Json.arr (l.map scoreJson).toArray),
     ("pick", match fontPick l with | some s => Json.str s.name | none => Json.null)]).compress) ++
  (notdefCases.map fun (cov, l) => (Json.mkObj [("kind", "notdef"), ("covered", toJson cov), ("cps", toJson (l.map fun p => [p.1, p.2])),
     ("count", notdefIn cov l)]).compress) ++
  (fontsCases.map fun found => (Json.mkObj [("kind", "fontsOk"), ("found", toJson found), ("ok", toJson (fontsOk found))]).compress) ++
  [(Json.mkObj [("kind", "touchPage"), ("maxScroll", fontPageMaxScroll), ("input", swipeJson swipeTouchV1), ("maxFrames", swipeTouchV1.budget fontPageMaxScroll)]).compress] ++
  (swipeCases.map fun (w, sc) => (Json.mkObj [("kind", "touchBudget"), ("input", swipeJson w), ("scroll", sc), ("moves", w.moves), ("stroke", w.stroke),
     ("reach", w.reach), ("strokes", w.strokes sc), ("budget", w.budget sc)]).compress) ++
  (endCases.map fun (w, limit, y, idle) => (Json.mkObj [("kind", "touchEnd"), ("input", swipeJson w), ("limit", limit), ("y", y), ("idle", idle),
     ("band", w.band), ("idleFrames", w.idleFrames), ("ended", toJson (w.ended limit y idle))]).compress) ++
  (kindCases.map fun k => (Json.mkObj [("kind", "parseKind"), ("in", match k with | some s => Json.str s | none => Json.null),
     ("out", match parseKind k with | some x => Json.str x.name | none => Json.null)]).compress) ++
  (dropCases.map fun (d : String) => (Json.mkObj [("kind", "dropOk"), ("drop", Json.str d), ("ok", toJson (dropOk d))]).compress) ++
  (keepCases.map fun (a, ds) => (Json.mkObj [("kind", "keep"), ("args", toJson a), ("drops", toJson ds), ("out", toJson (keep a ds))]).compress) ++
  ([Kind.counts, .probe].flatMap fun k => [Mode.counts, .load].map fun m => (Json.mkObj [("kind", "runnable"), ("profile", k.name), ("mode", m.name),
     ("ok", toJson (runnable k m))]).compress) ++
  ([false, true].flatMap fun a => [false, true].flatMap fun b => [Kind.counts, .probe].map fun k => (Json.mkObj [("kind", "readOk"),
     ("inProfiles", toJson a), ("inProbes", toJson b), ("declared", k.name), ("ok", toJson (readOk a b k))]).compress) ++
  (cftCases.map fun (os, arch) => (Json.mkObj [("kind", "cft"), ("os", os), ("arch", arch),
     ("platform", match cftPlatform os arch with | some p => Json.str p | none => Json.null),
     ("exe", match cftPlatform os arch with | some p => Json.str (cftExe p) | none => Json.null),
     ("url", match cftPlatform os arch with | some p => Json.str (cftUrl "156.0.8078.47" p) | none => Json.null)]).compress) ++
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
