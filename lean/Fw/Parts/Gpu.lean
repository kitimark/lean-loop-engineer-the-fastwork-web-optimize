namespace Fw.Parts.Gpu

/-- The engines on which a variant's mechanism reaches the compositor or GPU. -/
inductive Engines where
  | both | webkit | chromium
deriving Repr, DecidableEq

/-- The label shown on the pill. -/
def Engines.label : Engines → String
  | .both => "both engines"
  | .webkit => "WebKit only"
  | .chromium => "Chromium only"

/-- A GPU variant: its mechanism, the engines it holds on, and the ledger row `n` that backs it (index in
`research/findings/ledger.json`, 2026-10-24). -/
structure Entry where
  part : String
  variant : String
  engines : Engines
  mechanism : String
  n : Nat
deriving Repr, DecidableEq

/-- Entries are variants whose mechanism hands an animated property to the compositor, or fixes the size or count of
composited layers. Left out on purpose: `engine.scroll:unthrottle` (it lifts a scroll throttle, no layer or property
moves), `morph.tween:waapi*` (the registered `--morph` stays on main, n9), `morph.columns:hidden-pause` and
`engine.scene:hidden-pause` (they save a compositor tick only, n14, n25), `nav:earn-no-transition`, `hero.accent:*`
(`steps` falls back to main in WebKit, `draw-*` change layout or paint), and `pain:dark-static` (no animated layer). -/
def entries : List Entry := [
  ⟨"hero.exit", "threaded", .both, "scroll-driven CSS animations of opacity and transform replace a per-frame main-thread write of --exit-opacity; Chromium composites them (blur stays on main), WebKit threads them by default (ThreadedScrollDrivenAnimationsEnabled, UnifiedWebPreferences.yaml:8518-8531@862f17d)", 5⟩,
  ⟨"platform", "fade-threaded", .webkit, "the section fade is one opacity and blur Web Animation per push instead of a per-frame custom property write; WebKit threads it (Core Animation), Chromium keeps the blur on main (compositor_animations.cc:405-417@f842f52)", 77⟩,
  ⟨"morph.panel", "threaded", .both, "the panel opacity and scale and its blur run as Web Animations per push; WebKit hands all three to Core Animation (filter, opacity, transform), Chromium composites opacity and scale and keeps the blur on main; the nav still writes --morph each frame", 85⟩,
  ⟨"morph.panel", "const-bounds", .webkit, "the blur-backed panel layer keeps a constant box, so a morph frame never discards its backing store (RemoteLayerBackingStore.mm:145-151@862f17d); Chromium not shown", 78⟩,
  ⟨"hero.countdown", "strip", .both, "one 12-entry strip per digit replaces 10 will-change faces: 80 composited layers become 8 (compositing_reason_finder.cc:76-137@f842f52)", 6⟩,
  ⟨"morph.countdown", "strip", .both, "one 12-entry strip per digit replaces 10 will-change faces: 80 composited layers become 8", 18⟩,
  ⟨"hero", "scene-pause", .both, "will-change auto and paused animations off-screen release about 85 composited hero layers (RenderLayerCompositor.cpp:3842-3867@862f17d); measured win on WebKit, a trade on Chromium", 73⟩,
  ⟨"morph.columns", "idle-none", .both, "no idle animation on the column tracks, so 5 track layers become 1: Chromium layer-frames 28107 to 24667, WebKit backing 101 to 85 MB", 87⟩,
  ⟨"pain", "dark-scroll", .both, "the dark flip is a scroll-driven animation of two solid pseudo-element layers (animation reason, no backing store) instead of a repaint; paint area falls 4 percent on Chromium and 28 to 34 percent on WebKit", 80⟩,
  ⟨"people.o", "preview-translate", .both, "a kept scroll frame sets translate on the card's own layer instead of left and top: 0 layout passes against 1", 86⟩,
  ⟨"people.carousel", "crop", .both, "the avatar exit runs opacity and transform on the leaver and translate on the followers instead of width, flex-basis, margin-right and border-width: six time-based effects, all composited on both engines (Chromium cr_crop_zero, WebKit wk_crop_all_comp; compositor_animations.cc:78-83@f842f52, KeyframeEffect.cpp:2724-2744@862f17d); look-change class", 32⟩,
  ⟨"nav", "clip-box", .webkit, "the nav is the constant union box while it morphs and the pill is a clip-path inset, so the nav layers are not resized per frame (Fw.Engine.WebKitSimple simpleContainer_backing); clip-path itself still restyles on main", 82⟩,
  ⟨"nav", "bar-fixed", .webkit, "includes clip-box; the bar is a constant-width composited layer (will-change: transform) and the logo and actions move by 2D translate; the Conservative memory-pressure policy drops that layer", 83⟩,
  ⟨"nav", "logo-3d", .webkit, "includes bar-fixed; translate3d gives the logo its own layer under the Normal policy, so its move costs 0 layout (RenderLayerCompositor.cpp:3898-3899@862f17d); 2D translate keeps 1", 84⟩]

/-- The GPU mechanism text of a variant, `none` when it is not a GPU optimization. -/
def mechanism (part variant : String) : Option String :=
  (entries.find? fun e => e.part == part && e.variant == variant).map (·.mechanism)

/-- The engine label of a GPU variant, `none` when it is not one. -/
def engines (part variant : String) : Option String :=
  (entries.find? fun e => e.part == part && e.variant == variant).map (·.engines.label)

#guard (entries.map fun e => (e.part, e.variant)).eraseDups.length == entries.length

theorem mechanism_entry : ∀ e ∈ entries, mechanism e.part e.variant ≠ none := by decide

theorem mechanism_none_of_not_mem (p v : String) (h : (p, v) ∉ entries.map fun e => (e.part, e.variant)) : mechanism p v = none := by
  unfold mechanism
  cases hf : entries.find? (fun e => e.part == p && e.variant == v) with
  | none => rfl
  | some e =>
    exfalso; apply h
    have hm := List.mem_of_find?_eq_some hf
    have hp := List.find?_some hf
    simp only [Bool.and_eq_true, beq_iff_eq] at hp
    exact List.mem_map.2 ⟨e, hm, by rw [hp.1, hp.2]⟩

theorem engines_entry : ∀ e ∈ entries, engines e.part e.variant ≠ none := by decide

theorem fade_threaded_webkit : engines "platform" "fade-threaded" = some "WebKit only" := by decide

theorem hero_exit_both : engines "hero.exit" "threaded" = some "both engines" := by decide

theorem unthrottle_not_gpu : mechanism "engine.scroll" "unthrottle" = none := by decide

theorem waapi_not_gpu : mechanism "morph.tween" "waapi" = none ∧ mechanism "morph.tween" "waapi-scoped" = none := by decide

end Fw.Parts.Gpu
