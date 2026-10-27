import Lean.Data.Json
namespace Fw.Parts.MorphStyle

/-- A per-frame style or attribute write of the morph tween that can reach a consumer. -/
inductive Write where
  | navMorph
  | navAttr
  | platFade
  deriving DecidableEq, Repr

/-- The nav is in the base look, or `.is-flip` is on the root (morph.geom:on). -/
inductive Mode where
  | base
  | flip
  deriving DecidableEq, Repr

def Write.name : Write → String
  | .navMorph => "nav.--morph"
  | .navAttr => "nav.data-fw-morph"
  | .platFade => "platform.--morph-fade"

def Mode.name : Mode → String
  | .base => "base"
  | .flip => "flip"

/-- Readers of each write, per mode, as source files under `apps/site/src/parts` (a CSS file reads the property with
`var()`, a `.tsx` file observes or reads the attribute). In flip mode the nav rule `.is-flip [data-fw='nav'] { --morph: 1
!important }` (morph.geom/geom.css) wins over the inline value, and the `platform` tracks of morph.geom/tracks.ts animate
`opacity` and `filter`, the only two properties that read `--morph-fade`; the attribute keeps its observers. -/
def consumers : Write → Mode → List String
  | .navMorph, .base =>
    ["morph.columns/morph.module.css", "morph.panel/morph.module.css", "nav/box.module.css", "nav/nav.module.css"]
  | .navMorph, .flip => []
  | .navAttr, _ => ["morph.geom/index.tsx", "nav.hitTest/index.tsx", "nav/index.tsx"]
  | .platFade, .base => ["platform/platform.module.css"]
  | .platFade, .flip => []

/-- Writes with no reader in flip mode: the ones the tween may skip there. -/
def skippable (w : Write) : Bool := (consumers w .flip).isEmpty

theorem skippable_navMorph : skippable .navMorph = true := rfl
theorem skippable_platFade : skippable .platFade = true := rfl
theorem not_skippable_navAttr : skippable .navAttr = false := rfl

/-- Frames that write: skipped exactly while the flip is on and the morph is above 0 (the geom driver leaves at `m ≤ 0`). -/
def writes (flip : Bool) (m : Rat) : Bool := !(flip && decide (0 < m))

/-- What the stored (inline) value is after one frame at `m`, from the previous stored value `s`. -/
def stored (flip : Bool) (m s : Rat) : Rat := if writes flip m then m else s

/-- The value a reader of a skippable write sees: in flip mode the override (`one` for the nav property, the track `fade m`
for the platform) and in base mode the stored value. -/
def seen (mode : Mode) (override : Rat) (st : Rat) : Rat :=
  match mode with
  | .base => st
  | .flip => override

def modeOf (flip : Bool) : Mode := if flip then .flip else .base

/-- Same look: with the skip, every reader sees what it saw with a write at every frame, at every `m` and from any previous
stored value. -/
theorem seen_same (flip : Bool) (m s override : Rat) :
    seen (modeOf flip) override (stored flip m s) = seen (modeOf flip) override m := by
  by_cases h : writes flip m = true
  · simp [stored, h]
  · cases flip with
    | false => simp [writes] at h
    | true => simp [modeOf, seen]

/-- The base look is untouched: with the flip off every frame writes. -/
theorem base_writes (m : Rat) : writes false m = true := by simp [writes]

/-- The leaving frame writes (`m = 0`), so the base rules read the true end value when the class goes. -/
theorem leave_writes (flip : Bool) : writes flip 0 = true := by simp [writes]

/-- A frame that is skipped has the flip on and `m > 0`. -/
theorem skip_iff (flip : Bool) (m : Rat) : writes flip m = false ↔ flip = true ∧ 0 < m := by
  cases flip <;> simp [writes]

/-- Readers of the attribute stay in flip mode, so it is never skipped. -/
theorem navAttr_read_in_flip : (consumers .navAttr .flip).length = 3 := rfl


/-- The flush inside `leave` runs with the flip class already gone, so it reads the stored value: it is exactly the end
value when the write at `m = 0` came first (the timed settle syncs before it), whatever was stored before. -/
theorem leave_flush (s : Rat) : seen .base 0 (stored true 0 s) = 0 := by
  simp [seen, stored, writes]

/-- Without that write the flush reads the stale value: the nav then transitions from it to the end value. -/
theorem leave_flush_stale (s : Rat) (h : s ≠ 0) : seen .base 0 s ≠ 0 := by
  simpa [seen] using h

/-- Frames of a push saved by the skip. -/
def saved (fs : List (Bool × Rat)) : Nat := (fs.filter fun f => !writes f.1 f.2).length

theorem saved_le (fs : List (Bool × Rat)) : saved fs ≤ fs.length := List.length_filter_le _ _

theorem saved_base (ms : List Rat) : saved (ms.map fun m => (false, m)) = 0 := by
  induction ms with
  | nil => rfl
  | cons m ms ih => simp [saved, writes] at ih ⊢

end Fw.Parts.MorphStyle
