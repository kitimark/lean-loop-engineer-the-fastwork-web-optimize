import Fw.Plan.Trailer
import Fw.Console.Preview
import Fw.Gate.Search
/-!
# Builds tab: landed port/fix rows, flag and preset rows, what Preview opens, which searches a picker offers
Every list, target and search of the tab is decided here; `console.builds` and `console.buildsPicker` are the wire ops.
-/
namespace Fw.Console.Builds
open Fw.Console.Preview (Target)

/-- A commit of main's first-parent log. -/
structure LogCommit where
  sha : String
  time : Nat
  body : String
deriving Repr, DecidableEq

/-- A task of the work graph. -/
structure Known where
  id : String
  title : String
deriving Repr, DecidableEq

/-- A landed port or fix task: its land commit and the commit's time. -/
structure Row where
  task : String
  sha : String
  title : String
  landedAt : Nat
deriving Repr, DecidableEq

/-- The id starts with `port-` or `fix-`. -/
def isPortFix (id : String) : Bool := id.startsWith "port-" || id.startsWith "fix-"

/-- The prefix group of a task id. -/
def group (id : String) : String := if id.startsWith "port-" then "port" else "fix"

/-- The row a trailer `Task: t` on commit `c` makes: a known port or fix task, landed at `c`. -/
def rowOf (known : List Known) (c : LogCommit) (t : String) : Option Row :=
  match known.find? (·.id == t) with
  | some k => if isPortFix k.id then some { task := k.id, sha := c.sha, title := k.title, landedAt := c.time } else none
  | none => none

/-- Every landing the log shows, in log order. -/
def landings (known : List Known) (log : List LogCommit) : List Row :=
  log.flatMap fun c => (Fw.Plan.Trailer.trailers c.body).filterMap (rowOf known c)

/-- Newer land time first. -/
def newestFirst (a b : Row) : Bool := decide (b.landedAt ≤ a.landedAt)

/-- The rows whose task is not in `seen` and not an earlier row's task. -/
def dedupeAux (seen : List String) : List Row → List Row
  | [] => []
  | r :: rs => if seen.contains r.task then dedupeAux seen rs else r :: dedupeAux (r.task :: seen) rs

/-- The first row of each task. -/
def dedupe (rs : List Row) : List Row := dedupeAux [] rs

/-- The port list: one row per landed port or fix task, newest land first. -/
def portRows (known : List Known) (log : List LogCommit) : List Row :=
  dedupe ((landings known log).mergeSort newestFirst)

/-- What a port row's Preview opens: main at its land commit. -/
def portTarget (r : Row) : Target := .main r.sha

/-- What an optimize row's Preview opens: the current main. -/
def optTarget (mainSha : String) : Target := .main mainSha

theorem rowOf_port_fix (known : List Known) (c : LogCommit) (t : String) (r : Row) (h : rowOf known c t = some r) :
    isPortFix r.task = true := by
  unfold rowOf at h
  split at h
  · rename_i k hk
    split at h
    · rename_i hp
      cases h
      exact hp
    · cases h
  · cases h

theorem rowOf_land (known : List Known) (c : LogCommit) (t : String) (r : Row) (h : rowOf known c t = some r) :
    r.sha = c.sha ∧ r.landedAt = c.time := by
  unfold rowOf at h
  split at h
  · split at h
    · cases h; exact ⟨rfl, rfl⟩
    · cases h
  · cases h

theorem rowOf_known (known : List Known) (c : LogCommit) (t : String) (r : Row) (h : rowOf known c t = some r) :
    r.task = t := by
  unfold rowOf at h
  split at h
  · rename_i k hk
    split at h
    · cases h
      have := List.find?_some hk
      simpa using this
    · cases h
  · cases h

theorem mem_landings (known : List Known) (log : List LogCommit) (r : Row) :
    r ∈ landings known log ↔ ∃ c ∈ log, ∃ t ∈ Fw.Plan.Trailer.trailers c.body, rowOf known c t = some r := by
  simp [landings, List.mem_flatMap, List.mem_filterMap]

theorem dedupeAux_sublist (seen : List String) : ∀ rs : List Row, (dedupeAux seen rs).Sublist rs
  | [] => by simp [dedupeAux]
  | r :: rs => by
    unfold dedupeAux
    split
    · exact (dedupeAux_sublist seen rs).cons r
    · exact (dedupeAux_sublist (r.task :: seen) rs).cons_cons r

theorem dedupeAux_fresh (seen : List String) : ∀ rs : List Row, ∀ r ∈ dedupeAux seen rs, r.task ∉ seen
  | [], r, h => by simp [dedupeAux] at h
  | x :: rs, r, h => by
    unfold dedupeAux at h
    split at h
    · exact dedupeAux_fresh seen rs r h
    · rename_i hc
      rcases List.mem_cons.1 h with rfl | h'
      · simpa using hc
      · intro hs
        exact dedupeAux_fresh (x.task :: seen) rs r h' (List.mem_cons_of_mem _ hs)

theorem dedupeAux_nodup (seen : List String) : ∀ rs : List Row, ((dedupeAux seen rs).map (·.task)).Nodup
  | [] => by simp [dedupeAux]
  | x :: rs => by
    unfold dedupeAux
    split
    · exact dedupeAux_nodup seen rs
    · rename_i hc
      rw [List.map_cons, List.nodup_cons]
      refine ⟨?_, dedupeAux_nodup (x.task :: seen) rs⟩
      intro hm
      obtain ⟨r, hr, hrt⟩ := List.mem_map.1 hm
      exact dedupeAux_fresh (x.task :: seen) rs r hr (by rw [hrt]; exact List.mem_cons_self)

theorem dedupeAux_cover (seen : List String) : ∀ rs : List Row, ∀ r ∈ rs,
    r.task ∈ seen ∨ ∃ r' ∈ dedupeAux seen rs, r'.task = r.task
  | [], r, h => by simp at h
  | x :: rs, r, h => by
    unfold dedupeAux
    split
    · rename_i hc
      rcases List.mem_cons.1 h with rfl | h'
      · exact Or.inl (by simpa using hc)
      · exact dedupeAux_cover seen rs r h'
    · rcases List.mem_cons.1 h with rfl | h'
      · exact Or.inr ⟨r, List.mem_cons_self, rfl⟩
      · rcases dedupeAux_cover (x.task :: seen) rs r h' with h1 | ⟨r', hr', ht⟩
        · rcases List.mem_cons.1 h1 with h2 | h2
          · exact Or.inr ⟨x, List.mem_cons_self, h2.symm⟩
          · exact Or.inl h2
        · exact Or.inr ⟨r', List.mem_cons_of_mem _ hr', ht⟩

theorem portRows_port_fix (known : List Known) (log : List LogCommit) (r : Row) (h : r ∈ portRows known log) :
    isPortFix r.task = true := by
  unfold portRows dedupe at h
  have h1 := (dedupeAux_sublist [] _).subset h
  have h2 := (List.mergeSort_perm (landings known log) newestFirst).mem_iff.1 h1
  obtain ⟨c, _, t, _, hr⟩ := (mem_landings known log r).1 h2
  exact rowOf_port_fix known c t r hr

theorem portRows_land_commit (known : List Known) (log : List LogCommit) (r : Row) (h : r ∈ portRows known log) :
    ∃ c ∈ log, r.sha = c.sha ∧ r.landedAt = c.time := by
  unfold portRows dedupe at h
  have h1 := (dedupeAux_sublist [] _).subset h
  have h2 := (List.mergeSort_perm (landings known log) newestFirst).mem_iff.1 h1
  obtain ⟨c, hc, t, _, hr⟩ := (mem_landings known log r).1 h2
  exact ⟨c, hc, rowOf_land known c t r hr⟩

theorem portRows_nodup (known : List Known) (log : List LogCommit) :
    ((portRows known log).map (·.task)).Nodup := dedupeAux_nodup [] _

theorem portRows_sorted (known : List Known) (log : List LogCommit) :
    (portRows known log).Pairwise fun a b => b.landedAt ≤ a.landedAt := by
  unfold portRows dedupe
  have hs : ((landings known log).mergeSort newestFirst).Pairwise fun a b => newestFirst a b = true :=
    List.pairwise_mergeSort
      (fun a b c hab hbc => by simp only [newestFirst, decide_eq_true_eq] at *; omega)
      (fun a b => by simp [newestFirst]; omega) _
  exact (hs.imp (fun {a b} h => by simpa [newestFirst] using h)).sublist (dedupeAux_sublist [] _)

theorem portRows_complete (known : List Known) (log : List LogCommit) (c : LogCommit) (hc : c ∈ log)
    (t : String) (ht : t ∈ Fw.Plan.Trailer.trailers c.body) (r : Row) (hr : rowOf known c t = some r) :
    ∃ r' ∈ portRows known log, r'.task = r.task := by
  unfold portRows dedupe
  have hm : r ∈ (landings known log).mergeSort newestFirst :=
    (List.mergeSort_perm (landings known log) newestFirst).mem_iff.2 ((mem_landings known log r).2 ⟨c, hc, t, ht, hr⟩)
  rcases dedupeAux_cover [] _ r hm with h | h
  · simp at h
  · exact h

theorem portTarget_land (r : Row) : portTarget r = .main r.sha := rfl

theorem optTarget_main (m : String) : optTarget m = .main m := rfl

/-! ## Optimize rows -/

/-- A registered flag variant (`part.json`): `requires` are the `part:variant` keys it is requested with. -/
structure Flag where
  part : String
  variant : String
  kind : String
  requires : List String
deriving Repr, DecidableEq

/-- A preset: its name and the variant it sets per part. -/
structure Preset where
  name : String
  fw : List (String × String)
deriving Repr, DecidableEq

/-- The `part:variant` key. -/
def Flag.key (f : Flag) : String := f.part ++ ":" ++ f.variant

/-- The prerendered search of a flag variant, written like `enumerateSearches` in `apps/site/src/entry-server.tsx`. -/
def flagSearch (f : Flag) : String := "?fw=" ++ ",".intercalate (f.key :: f.requires)

/-- The prerendered search of a preset. -/
def presetSearch (name : String) : String := "?preset=" ++ name

/-- The searches a build prerenders: default, each preset, each single variant. -/
def enumerate (presets : List Preset) (flags : List Flag) : List String :=
  "" :: (presets.map (fun p => presetSearch p.name) ++ flags.map flagSearch)

/-- What the tab says about a row. -/
inductive Status where
  | v2Proved
  | c3Out
  | baseline
  | notInV2
  | presetV2
  | presetOther
deriving DecidableEq, Repr

/-- The wire name of a status. -/
def Status.name : Status → String
  | .v2Proved => "v2-proved"
  | .c3Out => "out of v2-proved (C3)"
  | .baseline => "baseline"
  | .notInV2 => "not in v2-proved"
  | .presetV2 => "the v2-proved preset"
  | .presetOther => "preset"

/-- Flags the C3 decision (wave-2 gate) took out of v2-proved. -/
def c3Out : List String := ["hero.countdown:strip"]

/-- The note shown with a C3 row. -/
def c3Note : String := "C3 decision: out of v2-proved after the wave-2 gate; the generated preset follows in c3-preset-update"

/-- The note of a status. -/
def Status.note : Status → Option String
  | .c3Out => some c3Note
  | _ => none

/-- The variant is set by the generated `v2-proved` preset. -/
def inV2 (presets : List Preset) (f : Flag) : Bool :=
  presets.any fun p => p.name == "v2-proved" && p.fw.any fun kv => kv.1 == f.part && kv.2 == f.variant

/-- A C3 flag is out whatever the generated preset still says; else the baseline; else the preset decides. -/
def flagStatus (presets : List Preset) (f : Flag) : Status :=
  if c3Out.contains f.key then .c3Out
  else if f.kind == "faithful" then .baseline
  else if inV2 presets f then .v2Proved else .notInV2

/-- The status of a preset row. -/
def presetStatus (p : Preset) : Status := if p.name == "v2-proved" then .presetV2 else .presetOther

/-- A slot character: lowercase letter or digit, else `-`. -/
def slotChar (c : Char) : Char :=
  if ('a' ≤ c.toLower && c.toLower ≤ 'z') || ('0' ≤ c.toLower && c.toLower ≤ '9') then c.toLower else '-'

/-- The preview slot of an optimize row (one live preview per slot). -/
def slot (kind name : String) : String := "opt-" ++ kind ++ "-" ++ String.map slotChar name

/-- One optimize row. -/
structure Opt where
  kind : String
  name : String
  search : String
  status : Status
  slot : String
deriving Repr, DecidableEq

/-- The optimize list: one row per preset, then one per flag variant. -/
def optRows (presets : List Preset) (flags : List Flag) : List Opt :=
  presets.map (fun p => { kind := "preset", name := p.name, search := presetSearch p.name, status := presetStatus p,
                          slot := slot "preset" p.name }) ++
  flags.map (fun f => { kind := "flag", name := f.key, search := flagSearch f, status := flagStatus presets f,
                        slot := slot "flag" f.key })

theorem optRows_length (presets : List Preset) (flags : List Flag) :
    (optRows presets flags).length = presets.length + flags.length := by
  simp [optRows]

theorem optRows_prerendered (presets : List Preset) (flags : List Flag) (o : Opt) (h : o ∈ optRows presets flags) :
    o.search ∈ enumerate presets flags := by
  simp only [optRows, List.mem_append, List.mem_map] at h
  simp only [enumerate, List.mem_cons, List.mem_append, List.mem_map]
  rcases h with ⟨p, hp, rfl⟩ | ⟨f, hf, rfl⟩
  · exact Or.inr (Or.inl ⟨p, hp, rfl⟩)
  · exact Or.inr (Or.inr ⟨f, hf, rfl⟩)

theorem flagStatus_c3 (presets : List Preset) (f : Flag) (h : c3Out.contains f.key = true) :
    flagStatus presets f = .c3Out := by unfold flagStatus; rw [h]; simp

theorem flagStatus_baseline (presets : List Preset) (f : Flag) (h : c3Out.contains f.key = false) (hk : f.kind = "faithful") :
    flagStatus presets f = .baseline := by unfold flagStatus; rw [h]; simp [hk]

theorem flagStatus_proved (presets : List Preset) (f : Flag) (h : c3Out.contains f.key = false) (hk : (f.kind == "faithful") = false)
    (hv : inV2 presets f = true) : flagStatus presets f = .v2Proved := by unfold flagStatus; rw [h, hk, hv]; simp

theorem flagStatus_not_proved (presets : List Preset) (f : Flag) (h : c3Out.contains f.key = false) (hk : (f.kind == "faithful") = false)
    (hv : inV2 presets f = false) : flagStatus presets f = .notInV2 := by unfold flagStatus; rw [h, hk, hv]; simp

theorem c3_never_proved (presets : List Preset) (f : Flag) (h : c3Out.contains f.key = true) :
    flagStatus presets f ≠ .v2Proved := by rw [flagStatus_c3 presets f h]; decide

theorem c3_note (presets : List Preset) (f : Flag) (h : c3Out.contains f.key = true) :
    (flagStatus presets f).note = some c3Note := by rw [flagStatus_c3 presets f h]; rfl

theorem slotChar_alphabet (c : Char) : ('a' ≤ slotChar c ∧ slotChar c ≤ 'z') ∨ ('0' ≤ slotChar c ∧ slotChar c ≤ '9') ∨ slotChar c = '-' := by
  unfold slotChar
  split
  · rename_i h
    simp only [Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq] at h
    rcases h with h | h
    · exact Or.inl h
    · exact Or.inr (Or.inl h)
  · exact Or.inr (Or.inr rfl)

/-! ## Picker -/

/-- A preset search: `?preset=` and a valid preset name. -/
def isPresetKey (s : String) : Bool := s.startsWith "?preset=" && Fw.Gate.Search.validPreset (String.ofList (s.toList.drop 8))

/-- A flag search: `?fw=` and a valid flag set. -/
def isFwKey (s : String) : Bool := s.startsWith "?fw=" && Fw.Gate.Search.validFw (String.ofList (s.toList.drop 4))

/-- The picker offers the default, a preset search or a flag search. -/
def offered (s : String) : Bool := s.isEmpty || isPresetKey s || isFwKey s

/-- The searches a build's picker lists, from its prerendered keys: default, presets, flags, each in key order. -/
def picker (keys : List String) : List String :=
  keys.filter (·.isEmpty) ++ keys.filter isPresetKey ++ keys.filter isFwKey

/-- The search the compare view loads for a requested one: itself when offered, else the default. -/
def choose (keys : List String) (cur : String) : String := if (picker keys).contains cur then cur else ""

theorem picker_prerendered (keys : List String) (s : String) (h : s ∈ picker keys) : s ∈ keys := by
  simp only [picker, List.mem_append, List.mem_filter] at h
  rcases h with (h | h) | h
  · exact h.1
  · exact h.1
  · exact h.1

theorem picker_offered (keys : List String) (s : String) (h : s ∈ picker keys) : offered s = true := by
  simp only [picker, List.mem_append, List.mem_filter] at h
  simp only [offered, Bool.or_eq_true]
  rcases h with (h | h) | h
  · exact Or.inl (Or.inl h.2)
  · exact Or.inl (Or.inr h.2)
  · exact Or.inr h.2

theorem picker_complete (keys : List String) (s : String) (hk : s ∈ keys) (ho : offered s = true) : s ∈ picker keys := by
  simp only [picker, List.mem_append, List.mem_filter]
  simp only [offered, Bool.or_eq_true] at ho
  rcases ho with (h | h) | h
  · exact Or.inl (Or.inl ⟨hk, h⟩)
  · exact Or.inl (Or.inr ⟨hk, h⟩)
  · exact Or.inr ⟨hk, h⟩

theorem picker_default_first (keys : List String) (h : "" ∈ keys) : (picker keys).head? = some "" := by
  have hne : keys.filter (·.isEmpty) ≠ [] := by
    intro he
    have := List.filter_eq_nil_iff.1 he "" h
    simp at this
  obtain ⟨a, l, hal⟩ := List.exists_cons_of_ne_nil hne
  have ha : a ∈ keys.filter (·.isEmpty) := by rw [hal]; exact List.mem_cons_self
  have hae : a.isEmpty = true := (List.mem_filter.1 ha).2
  have : a = "" := String.isEmpty_iff.1 hae
  simp [picker, hal, this]

theorem choose_offered (keys : List String) (cur : String) (h : (picker keys).contains cur = true) : choose keys cur = cur := by
  unfold choose; simp only [h]; simp

theorem choose_unknown (keys : List String) (cur : String) (h : (picker keys).contains cur = false) : choose keys cur = "" := by
  unfold choose; simp only [h]; simp

theorem preset_key_chars (s : String) (h : isPresetKey s = true) : ∀ c ∈ s.toList.drop 8, Fw.Gate.Search.presetChar c = true := by
  simp only [isPresetKey, Bool.and_eq_true, Fw.Gate.Search.validPreset, Bool.not_eq_true', List.all_eq_true] at h
  simpa using h.2.2

theorem fw_key_chars (s : String) (h : isFwKey s = true) : ∀ c ∈ s.toList.drop 4, Fw.Gate.Search.fwChar c = true := by
  simp only [isFwKey, Bool.and_eq_true, Fw.Gate.Search.validFw, Bool.not_eq_true', List.all_eq_true] at h
  simpa using h.2.2

end Fw.Console.Builds
