import Lean.Data.Json
import Fw.Parts.HiddenPause
import Fw.Parts.MorphMountDormant
/-!
# morph.columns, variant `idle-none`: no track animation while the scene rule pauses the panel
Proof note: research/notes/2026/10-20-morph-idle-none.md.
-/
namespace Fw.Parts.MorphIdleNone

open Fw.Engine Fw.Parts.HiddenPause

structure St where
  clock : Rat
  present : Bool
deriving Repr, DecidableEq

def varStep (s : St) (fr : Rat × Rat) : St :=
  if scenePaused fr.2 then ⟨s.clock, false⟩ else ⟨s.clock + fr.1, true⟩

def varRun (ℓ0 : Rat) (frs : List (Rat × Rat)) : St := frs.foldl varStep ⟨ℓ0, true⟩

def restartClock (ℓ0 : Rat) (frs : List (Rat × Rat)) : Rat :=
  frs.foldl (fun ℓ fr => if scenePaused fr.2 then 0 else ℓ + fr.1) ℓ0

theorem foldl_varStep_clock (frs : List (Rat × Rat)) :
    ∀ s : St, (frs.foldl varStep s).clock = frs.foldl clockStep s.clock := by
  induction frs with
  | nil => intro s; rfl
  | cons fr frs ih =>
    intro s
    simp only [List.foldl_cons]
    rw [ih]
    congr 1
    unfold varStep clockStep
    split <;> rfl

theorem varRun_clock (ℓ0 : Rat) (frs : List (Rat × Rat)) : (varRun ℓ0 frs).clock = origClock ℓ0 frs :=
  foldl_varStep_clock frs ⟨ℓ0, true⟩

theorem varRun_present (ℓ0 : Rat) (frs : List (Rat × Rat)) (fr : Rat × Rat) :
    (varRun ℓ0 (frs ++ [fr])).present = !scenePaused fr.2 := by
  unfold varRun
  rw [List.foldl_append]
  simp only [List.foldl_cons, List.foldl_nil, varStep]
  split <;> simp_all

theorem restart_shifts : restartClock 0 [(16, 1), (16, 0), (16, 1)] ≠ origClock 0 [(16, 1), (16, 0), (16, 1)] := by
  decide +kernel

#guard (varRun 0 [(16, 1), (16, 0), (16, 1)]).clock == 32
#guard !(varRun 0 [(16, 1), (16, 0)]).present && (varRun 0 [(16, 1), (16, 0), (16, 1)]).present

def shownO (ℓ0 : Rat) (frs : List (Rat × Rat)) : Option Rat := some (origClock ℓ0 frs)

def shownV (ℓ0 : Rat) (frs : List (Rat × Rat)) : Option Rat :=
  if (varRun ℓ0 frs).present then some (varRun ℓ0 frs).clock else none

theorem shownV_eq (ℓ0 : Rat) (hist : List (Rat × Rat)) (fr : Rat × Rat) (h : scenePaused fr.2 = false) :
    shownV ℓ0 (hist ++ [fr]) = shownO ℓ0 (hist ++ [fr]) := by
  unfold shownV shownO
  rw [varRun_present, varRun_clock, h]
  rfl

theorem idleNone_visSame {Env T : Type} (vp : Env → Rect) (ℓ0 : Env → Rat) (hist : Env → T → List (Rat × Rat))
    (cur : Env → T → Rat × Rat) (tm : Env → T → Tmpl (Option Rat))
    (hU : ∀ env t, UnderPanel (cur env t).2 (tm env t)) :
    VisSame E vp (fun env t => inst (tm env t) (shownO (ℓ0 env) (hist env t ++ [cur env t])))
      (fun env t => inst (tm env t) (shownV (ℓ0 env) (hist env t ++ [cur env t]))) :=
  panel_visSame vp (fun env t => (cur env t).2) tm _ _ hU fun env t h =>
    (shownV_eq (ℓ0 env) (hist env t) (cur env t) (by
      cases hs : scenePaused (cur env t).2
      · rfl
      · rw [scenePaused_imp_hiddenPause _ hs] at h; exact absurd h (by decide)))

open Fw.Parts.MorphMountDormant

theorem place_direct_adds (direct : Nat → Bool) (ls : List Layer) (c : Chunk) (hd : direct c.space = true)
    (hn : ls.any (·.space == c.space) = false) : (place direct ls c).length = ls.length + 1 := by
  simp [place, hd, hn]

theorem layers_idle_eq (direct : Nat → Bool) (pre tracks post : List Chunk)
    (h : Absorbed (layerize direct pre) tracks) :
    layerize direct (pre ++ tracks ++ post) = layerize direct (pre ++ post) :=
  layerize_absorbed direct pre tracks post h

def backdrop : Chunk := ⟨0, ⟨0, 0, 422, 52⟩⟩

def tracksOn : List Chunk := [⟨1, ⟨0, 0, 135, 1348⟩⟩, ⟨2, ⟨140, 0, 136, 1340⟩⟩, ⟨3, ⟨280, 0, 135, 1612⟩⟩]

def tracksOff : List Chunk := tracksOn.map fun c => { c with space := 0 }

def above : List Chunk := [⟨0, ⟨0, 0, 136, 52⟩⟩, ⟨0, ⟨140, 0, 135, 52⟩⟩]

theorem tracks_layers_drop :
    (layerize (fun s => decide (1 ≤ s)) ([backdrop] ++ tracksOn ++ above)).length = 5 ∧
    (layerize (fun s => decide (1 ≤ s)) ([backdrop] ++ tracksOff ++ above)).length = 1 := by
  decide +kernel

def frameSeqs : List (List (Int × Int)) :=
  [[(16, 0), (16, 0), (16, 5)],
   [(16, 500), (16, 1), (16, 0), (16, 2), (16, 1000)],
   [(16, 2), (16, 1), (16, 1), (16, 80), (16, 1)],
   [(16, 1000), (16, 1000)],
   [(16, 0), (16, 0)]]

def morphs : List Int := [0, 1, 2, 80, 81, 500, 1000]

def toFr (f : Int × Int) : Rat × Rat := ((f.1 : Rat), (f.2 : Rat) / 1000)

def line (fn : String) (inp : List (String × Lean.Json)) (out : Lean.Json) : String :=
  (Lean.Json.mkObj [("fn", .str fn), ("in", Lean.Json.mkObj inp), ("out", out)]).compress

def stJson (s : St) : Lean.Json :=
  Lean.Json.mkObj [("present", .bool s.present), ("clock", .num (.fromInt s.clock.floor))]

def lines : List String :=
  morphs.map (fun mm => line "removed" [("mm", .num (.fromInt mm))] (.bool (scenePaused ((mm : Rat) / 1000)))) ++
  frameSeqs.map fun fs =>
    line "run" [("frames", .arr (fs.map fun f => .arr #[.num (.fromInt f.1), .num (.fromInt f.2)]).toArray)]
      (.arr ((List.range fs.length).map fun i => stJson (varRun 0 ((fs.take (i + 1)).map toFr))).toArray)

def goldenText : String := String.join (lines.map (· ++ "\n"))

def gen (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText then
      IO.eprintln s!"morph-idle-none golden: {path} is up to date ({lines.length} lines)"
      return 0
    IO.eprintln s!"morph-idle-none golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print goldenText
    return 0

end Fw.Parts.MorphIdleNone
