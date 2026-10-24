import Fw.Wire
import Fw.Console.PreviewTable
import Fw.Ops.LeanFirstSearch
namespace Fw.Wire.Ops.Golden
open Lean

def lit (s : String) : Json := (Json.parse s).toOption.getD (Json.mkObj [("unparsable", .str s)])

def searchRegistry : Json := lit "{\"parts\":[{\"id\":\"hero.countdown\",\"variants\":[\"faithful\",\"strip\",\"hidden-pause\",\"one-chain\"],\"impls\":[\"mui\",\"plain\"]},{\"id\":\"hero.exit\",\"variants\":[\"faithful\",\"scoped\"],\"impls\":[\"plain\"]},{\"id\":\"morph.countdown\",\"variants\":[\"faithful\",\"strip\",\"hidden-pause\"],\"impls\":[\"mui\",\"plain\"],\"requires\":{\"morph.countdown:strip\":[\"hero.countdown:strip\"]}},{\"id\":\"morph.mount\",\"variants\":[\"faithful\",\"shift\",\"shift-dormant\"],\"impls\":[\"mui\",\"plain\"]},{\"id\":\"morph.tween\",\"variants\":[\"faithful\",\"waapi\",\"waapi-scoped\"],\"impls\":[\"mui\",\"plain\"]},{\"id\":\"pain.notes\",\"variants\":[\"faithful\",\"visible\",\"visible-idem\"],\"impls\":[\"plain\"]},{\"id\":\"engine.scroll\",\"variants\":[\"faithful\",\"batched\"],\"impls\":[\"mui\",\"plain\"]},{\"id\":\"nav.hitTest\",\"variants\":[\"faithful\",\"hit-skip\",\"elements-skip\"],\"impls\":[\"mui\",\"plain\"],\"requires\":{},\"conflicts\":{\"nav.hitTest:hit-skip\":[\"engine.scroll:batched\"]}}],\"presets\":[{\"name\":\"original\",\"fw\":{}},{\"name\":\"strip-demo\",\"extends\":\"original\",\"fw\":{\"hero.countdown\":\"strip\"}},{\"name\":\"v2-proved\",\"extends\":\"original\",\"fw\":{\"engine.scroll\":\"batched\",\"morph.mount\":\"shift\",\"morph.tween\":\"waapi\",\"pain.notes\":\"visible\"}},{\"name\":\"loop-a\",\"extends\":\"loop-b\",\"fw\":{}},{\"name\":\"loop-b\",\"extends\":\"loop-a\",\"fw\":{}},{\"name\":\"plain-impl\",\"fw\":{\"hero.countdown\":\"one-chain@plain\"}},{\"name\":\"bad-impl\",\"fw\":{\"hero.exit\":\"scoped@mui\"}}]}"

def srch (s : String) : Json := Json.mkObj [("registry", searchRegistry), ("search", .str s)]

def openS (s extra : String) : Json :=
  let base := Json.mkObj [("mode", "search"), ("main", "m9"), ("search", .str s), ("registry", searchRegistry)]
  match lit extra with
  | .obj kvs => kvs.toList.foldl (fun j kv => j.setObjVal! kv.1 kv.2) base
  | _ => base

def roles : String :=
  "[{\"name\":\"lean-prover\",\"runsAs\":\"worktree\",\"edits\":true},{\"name\":\"researcher\",\"runsAs\":\"teammate\",\"edits\":true},{\"name\":\"reviewer\",\"runsAs\":\"subagent\",\"edits\":false},{\"name\":\"Explore\",\"runsAs\":\"subagent\",\"edits\":false}]"

def cmpReg : Json := lit "{\"parts\":[{\"id\":\"morph.tween\",\"slot\":\"morph\",\"impls\":[\"plain\"],\"variants\":[{\"name\":\"faithful\",\"kind\":\"faithful\"},{\"name\":\"waapi\",\"kind\":\"optimized\"},{\"name\":\"waapi-scoped\",\"kind\":\"optimized\"}]},{\"id\":\"hero.countdown\",\"slot\":\"hero\",\"impls\":[\"mui\",\"plain\"],\"variants\":[{\"name\":\"faithful\",\"kind\":\"faithful\"},{\"name\":\"strip\",\"kind\":\"optimized\"},{\"name\":\"one-chain\",\"kind\":\"optimized\",\"limit\":\"look change: the second chain is dropped\"}]},{\"id\":\"morph.countdown\",\"slot\":\"morph\",\"impls\":[\"plain\"],\"variants\":[{\"name\":\"faithful\",\"kind\":\"faithful\"},{\"name\":\"strip\",\"kind\":\"optimized\"}],\"requires\":{\"morph.countdown:strip\":[\"hero.countdown:strip\"]}},{\"id\":\"nav.hitTest\",\"slot\":\"nav\",\"impls\":[\"plain\"],\"variants\":[{\"name\":\"faithful\",\"kind\":\"faithful\"},{\"name\":\"hit-skip\",\"kind\":\"optimized\"}],\"conflicts\":{\"nav.hitTest:hit-skip\":[\"engine.scroll:batched\"]}},{\"id\":\"engine.scroll\",\"slot\":\"engine\",\"impls\":[\"plain\"],\"variants\":[{\"name\":\"faithful\",\"kind\":\"faithful\"},{\"name\":\"batched\",\"kind\":\"optimized\"}]},{\"id\":\"pain.notes\",\"slot\":\"pain\",\"impls\":[\"plain\"],\"variants\":[{\"name\":\"faithful\",\"kind\":\"faithful\"},{\"name\":\"visible\",\"kind\":\"optimized\"}]}],\"presets\":[{\"name\":\"original\",\"fw\":{}},{\"name\":\"strip-demo\",\"extends\":\"original\",\"fw\":{\"hero.countdown\":\"strip\"}},{\"name\":\"v2-proved\",\"extends\":\"original\",\"fw\":{\"engine.scroll\":\"batched\",\"pain.notes\":\"visible\"}},{\"name\":\"bad\",\"extends\":\"original\",\"fw\":{\"morph.tween\":\"waapi\"}},{\"name\":\"loop\",\"extends\":\"loop\",\"fw\":{}}]}"

def cmpLedger : String :=
  "[{\"part\":\"engine.scroll\",\"candidate\":\"engine.scroll `batched`\",\"status\":\"measured\",\"flags\":[\"engine.scroll:batched\"],\"flag\":\"engine.scroll:batched\"},{\"part\":\"pain.notes\",\"candidate\":\"pain.notes `visible`\",\"status\":\"measured\",\"flags\":[\"pain.notes:visible\"],\"flag\":\"pain.notes:visible\"},{\"part\":\"morph.tween\",\"candidate\":\"morph.tween `waapi`\",\"status\":\"refuted\",\"flags\":[\"morph.tween:waapi\"],\"flag\":\"morph.tween:waapi\"},{\"part\":\"hero.countdown\",\"candidate\":\"hero.countdown `strip`\",\"status\":\"measured\",\"flags\":[\"hero.countdown:strip\"]},{\"part\":\"hero.countdown\",\"candidate\":\"hero.countdown `one-chain`\",\"status\":\"measured\",\"flags\":[\"hero.countdown:one-chain\"]},{\"part\":\"nav.hitTest\",\"candidate\":\"nav.hitTest, another idea\",\"status\":\"open\",\"flags\":[]}]"

def cmpLedgerFixed : String :=
  "[{\"part\":\"engine.scroll\",\"candidate\":\"engine.scroll `batched`\",\"status\":\"measured\",\"flags\":[\"engine.scroll:batched\"],\"flag\":\"engine.scroll:batched\"},{\"part\":\"pain.notes\",\"candidate\":\"pain.notes `visible`\",\"status\":\"measured\",\"flags\":[\"pain.notes:visible\"],\"flag\":\"pain.notes:visible\"},{\"part\":\"morph.tween\",\"candidate\":\"morph.tween `waapi`\",\"status\":\"refuted\",\"flags\":[\"morph.tween:waapi\"],\"flag\":\"morph.tween:waapi\",\"id\":\"tw.falsified\",\"supersededBy\":\"tw.fixed\"},{\"part\":\"hero.countdown\",\"candidate\":\"hero.countdown `strip`\",\"status\":\"measured\",\"flags\":[\"hero.countdown:strip\"]},{\"part\":\"hero.countdown\",\"candidate\":\"hero.countdown `one-chain`\",\"status\":\"measured\",\"flags\":[\"hero.countdown:one-chain\"]},{\"part\":\"nav.hitTest\",\"candidate\":\"nav.hitTest, another idea\",\"status\":\"open\",\"flags\":[]},{\"part\":\"morph.tween\",\"candidate\":\"the fixed driver\",\"status\":\"proved\",\"flags\":[\"morph.tween:waapi\"],\"id\":\"tw.fixed\"}]"

def cmpReg2 : Json := lit "{\"parts\":[{\"id\":\"morph.columns\",\"slot\":\"morph\",\"impls\":[\"mui\",\"plain\"],\"variants\":[{\"name\":\"faithful\",\"kind\":\"faithful\"},{\"name\":\"hidden-pause\",\"kind\":\"optimized\"}]},{\"id\":\"morph.countdown\",\"slot\":\"morph\",\"impls\":[\"mui\",\"plain\"],\"variants\":[{\"name\":\"faithful\",\"kind\":\"faithful\"},{\"name\":\"hidden-pause\",\"kind\":\"optimized\"}]},{\"id\":\"engine.scroll\",\"slot\":\"engine\",\"impls\":[\"mui\",\"plain\"],\"variants\":[{\"name\":\"faithful\",\"kind\":\"faithful\"},{\"name\":\"batched\",\"kind\":\"optimized\"}]},{\"id\":\"pain.notes\",\"slot\":\"pain\",\"impls\":[\"mui\",\"plain\"],\"variants\":[{\"name\":\"faithful\",\"kind\":\"faithful\"},{\"name\":\"visible\",\"kind\":\"optimized\"}]}],\"presets\":[{\"name\":\"original\",\"fw\":{}},{\"name\":\"mui-impl\",\"extends\":\"original\",\"fw\":{\"engine.scroll\":\"batched@mui\"}},{\"name\":\"plain-impl\",\"extends\":\"original\",\"fw\":{\"engine.scroll\":\"batched@plain\"}}]}"

def cmpLedger2 : String :=
  "[{\"part\":\"morph.columns\",\"candidate\":\"columns as a still picture while the menu is closed (g0.0h keep-phase = hidden-pause of the marquee)\",\"status\":\"partly-proved\",\"flags\":[\"morph.columns:hidden-pause\"]},{\"part\":\"engine.scene\",\"candidate\":\"hidden pause of compositor marquees (morph.columns at m <= 0.08, scene off-screen), HiddenPause.lean\",\"status\":\"proved\",\"flags\":[\"morph.columns:hidden-pause\"]},{\"part\":\"engine.scene\",\"candidate\":\"morph.countdown hidden: keep the spring integrating, skip the 16 face writes per digit (HiddenPause skipWrites)\",\"status\":\"proved\",\"flags\":[\"morph.countdown:hidden-pause\"]},{\"part\":\"engine.scroll\",\"candidate\":\"engine.scroll `batched`\",\"status\":\"proved\",\"flags\":[\"engine.scroll:batched\"]},{\"part\":\"pain.notes\",\"candidate\":\"pain.notes `visible`\",\"status\":\"proved\",\"flags\":[\"pain.notes:visible\"]},{\"part\":\"pain.notes\",\"candidate\":\"pain.notes `visible`, second measurement\",\"status\":\"measured\",\"flags\":[\"pain.notes:visible\"]}]"

def cmp2 (picks : String) : Json :=
  lit s!"\{\"registry\":{cmpReg2.compress},\"picks\":{picks},\"ledger\":{cmpLedger2}}"

def cmp (picks : String) (ledger : String := cmpLedger) : Json :=
  lit s!"\{\"registry\":{cmpReg.compress},\"picks\":{picks},\"ledger\":{ledger}}"

def cmpReal : Json := lit r#"{"registry":{"parts":[{"id":"commission","slot":"commission","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"band-gate","kind":"optimized","limit":"style-only saving: skips the two custom-property writes while mq.c1000 matches and the follower still moves; writes the current pair when the follower settles, on the first frame that reads the band off and on a band change without a frame; the follower, the classes and the frame requests are unchanged"}]},{"id":"commission.typing","slot":"commission","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""}]},{"id":"engine.scene","slot":"engine","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"hidden-pause","kind":"optimized","limit":""}]},{"id":"engine.scroll","slot":"engine","impls":["mui","plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"batched","kind":"optimized","limit":""},{"name":"unthrottle","kind":"optimized","limit":"changes nothing on Chromium or without animation-timeline; costs one restyled element per scroll frame"},{"name":"throttle-lift","kind":"ablation","limit":""}]},{"id":"hero","slot":"hero","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"scene-pause","kind":"optimized","limit":"same look as the original (visSame_original, class E); differs from the faithful arm, which lacks the original's pause rule: while paused every hero CSS animation stops and resumes on return at the original's time, not the faithful arm's: cue scrollFloat (2.2 s loop), accent idle0-2 (0.6 s loops), accent strokeIn and strokeOut (0.9 s), cue copyIn at <= 600 px (0.7 s after 0.2 s), and until the splash ends (data-splash=done, data-done, 1.82 s) the copy and cue copyFromRing (0.7 s after 1.14 s) and the card ringAppear and cardFromRing; the countdown has no CSS animation (only its faces lose will-change). No-claim zones: a paused box is hidden within kMax during the splash (proved, Fw.Parts.HeroScenePause.hero_paused_hidden) and after the splash within kCopy (170 px at 932x430, INFERRED), not beyond; copy column assumed inside the stage; svh assumed = vh; hero.countdown:strip not covered"}]},{"id":"hero.accent","slot":"hero","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"steps","kind":"optimized","limit":""},{"name":"draw-one","kind":"optimized","limit":"the two copies at opacity 0 in the draw window get no stroke animation (Lean drawOne_visSame, drawOne_still_iff); saves 2 of 3 animated paths per draw frame (animatedCount_values), the visible copy still lays out per frame"},{"name":"draw-nolayout","kind":"optimized","limit":"look change: the draw is a clip-path wipe of the visible copy instead of a stroke trace: look-change, for the user's visual review; no layout in the draw-out frames (arm_drawOut_nolayout); the draw-in keeps the original's width transition, which lays out (arm_drawIn_layout_only_width)"},{"name":"draw-nolayout-full","kind":"optimized","limit":"look change: draw-nolayout plus no width transition on the host, so the headline text jumps to the new width at the start of the draw-in instead of gliding over 0.9 s; the width is set once (wkLayoutFrames_values: 1 layout frame per cycle, faithful 2 per frame), the other draw frames need no layout in WebKit or Chromium (full_inRest_nolayout): look-change, for the user's visual review"}]},{"id":"hero.countdown","slot":"hero","impls":["mui","plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"strip","kind":"optimized","limit":""},{"name":"hidden-pause","kind":"optimized","limit":"under reduced motion hero.exit writes 1, so the gate never closes and the variant saves nothing there (Lean hidden_iff_exit)"},{"name":"one-chain","kind":"optimized","limit":"saves rAF callbacks only in frames where 2 or more digits roll, or 1 digit rolls while another part shares the loop (Lean oneChain_raf, page_lt_shared); equal otherwise (oneChain_raf_eq, page_eq_still)"}]},{"id":"hero.cue","slot":"hero","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""}]},{"id":"hero.deck","slot":"hero","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""}]},{"id":"hero.exit","slot":"hero","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"scoped","kind":"optimized","limit":"the win is in UpdateLayoutTree.elementCount, a quarantined counter; WebKit is source-only (Lean wk_units)"},{"name":"threaded","kind":"optimized","limit":"the CSS animations replace the callback only for a settled entrance in a browser with animation-timeline and unreduced motion; before Safari 26.4 they run on the main thread; countdown hidden-pause reads the stage's inline --exit-opacity, which this variant clears"}]},{"id":"hero.orbit","slot":"hero","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""}]},{"id":"morph.columns","slot":"morph","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"hidden-pause","kind":"optimized","limit":""},{"name":"idle-none","kind":"optimized","limit":""}]},{"id":"morph.countdown","slot":"morph","impls":["mui","plain"],"requires":{"morph.countdown:strip":["hero.countdown:strip"]},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"strip","kind":"optimized","limit":""},{"name":"hidden-pause","kind":"optimized","limit":""}]},{"id":"morph.mount","slot":"morph","impls":["mui","plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"shift","kind":"optimized","limit":""},{"name":"shift-dormant","kind":"optimized","limit":""},{"name":"band","kind":"optimized","limit":"band premises: pan checked on the replay profiles, IO lag INFERRED; inBand models only the 150% bottom edge of BAND_ROOT_MARGIN; the 1000% top edge is assumed never crossed while armed (page below the platform shorter than 10 viewports, INFERRED, unchecked); the merged touch listener is passive while the platform is out of the band"}]},{"id":"morph.panel","slot":"morph","impls":["mui","plain"],"requires":{},"conflicts":{"morph.panel:threaded":["morph.tween:waapi","morph.tween:waapi-scoped"]},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"const-bounds","kind":"optimized","limit":"while the nav morphs (is-morphing) the panel box keeps the nav's final size and each child is inset onto the nav box; the nav and the column tracks still change size every frame (colW_mono, pitch_scaled_ne), the children are still laid out per frame, and the panel layer's blur outset still varies while the fade runs (INFERRED)"},{"name":"threaded","kind":"optimized","limit":"const-bounds plus one opacity and scale effect and one blur effect per push; the nav still writes --morph on every frame, so RecalculateStyles stays (recalc_same); CA's blur is not the software blur (pixels at most Q on WebKit); Chromium keeps the blur effect on the main thread"}]},{"id":"morph.tween","slot":"morph","impls":["mui","plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"waapi","kind":"optimized","limit":""},{"name":"waapi-scoped","kind":"optimized","limit":""},{"name":"scroll-lock","kind":"proposal","limit":"look change (L) during a trackpad gesture in flight: the pinned page no longer jitters and the overlay scrollbar hides while the morph runs; costs 2 root style passes per morph where it engages (hover input and overlay scrollbar); reads the scrollbar kind once per activation; on (hover: none) it is not installed and on classic scrollbars it never writes the root"},{"name":"band","kind":"optimized","limit":"band premises: pan checked on the replay profiles, IO lag INFERRED; inBand models only the 150% bottom edge of BAND_ROOT_MARGIN; the 1000% top edge is assumed never crossed while armed (page below the platform shorter than 10 viewports, INFERRED, unchecked); the merged touch listener is passive while the platform is out of the band"}]},{"id":"nav","slot":"nav","impls":["plain"],"requires":{},"conflicts":{"nav:clip-box":["morph.panel:const-bounds"],"nav:bar-fixed":["morph.panel:const-bounds"],"nav:logo-3d":["morph.panel:const-bounds"]},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"earn-no-transition","kind":"proposal","limit":"look change (L) while the nav morphs: the earn button follows --morph without its 0.68 s lag; VisSame only at settled frames"},{"name":"clip-box","kind":"proposal","limit":"the nav is the union box while it morphs and the pill is a clip-path inset; the panel and bar are placed on the pill box by the same insets, so layout of both still changes per frame; raster area is a trade (area_trade) unless the nav is a simple container; the width transition lists are the original's; the union width comes from min-width, the declared width equals the rest width at morph 0 (decl_eq_rest_zero) and differs by under 0.42 px for 0 < m <= cut (decl_close_rest); at rest, Q at the curved clip edge. Mid-morph look change (L, user look review): the local Simulator lane shows about 1.01M changed px at m0.5 against a later-load floor of 0 and a pill edge ring of 8,617 px (results/gpu-safari/nav-*.json); the CI morph trajectory is red on both engines (runs 39887328839, 39887331854, 39887335005); the rest-state gate and the open/close nav-clip cell pass (rest gate) and grade E (cell) and cannot see it (Fw.Parts.Footprint rest_blind, cell_blind)."},{"name":"bar-fixed","kind":"proposal","limit":"includes clip-box (a part has one variant, so the arms are cumulative); the bar is a composited layer (will-change: transform), which the Conservative policy drops (bar_normal_only). Mid-morph look change (L, user look review): the local Simulator lane shows about 1.01M changed px at m0.5 against a later-load floor of 0 and a pill edge ring of 8,617 px (results/gpu-safari/nav-*.json); the CI morph trajectory is red on both engines (runs 39887328839, 39887331854, 39887335005); the rest-state gate and the open/close nav-clip cell pass (rest gate) and grade E (cell) and cannot see it (Fw.Parts.Footprint rest_blind, cell_blind)."},{"name":"logo-3d","kind":"proposal","limit":"includes bar-fixed; the logo is moved by translate3d, composited under the Normal policy only; at 430 wide CA resamples the 3x raster at scale 0.75 (Q, look review if the pixel diff exceeds tolerance). Mid-morph look change (L, user look review): the local Simulator lane shows about 1.01M changed px at m0.5 against a later-load floor of 0 and a pill edge ring of 8,617 px (results/gpu-safari/nav-*.json); the CI morph trajectory is red on both engines (runs 39887328839, 39887331854, 39887335005); the rest-state gate and the open/close nav-clip cell pass (rest gate) and grade E (cell) and cannot see it (Fw.Parts.Footprint rest_blind, cell_blind)."}]},{"id":"nav.hitTest","slot":"nav","impls":["mui","plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"hit-skip","kind":"optimized","limit":""},{"name":"elements-skip","kind":"optimized","limit":""}]},{"id":"nav.langMenu","slot":"nav","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""}]},{"id":"overlays.drawer","slot":"overlays","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""}]},{"id":"overlays.signup","slot":"overlays","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""}]},{"id":"pain","slot":"pain","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"dark-scroll","kind":"optimized","limit":"adds two solid-colour layers (pseudo-elements) with no backing store (Lean solid_layers_le, layer_backing_zero); at most 860 px, in engines with the root scroll timeline and animation-range (elsewhere faithful); the pixel equality holds when the card reveal translation has finished at the flip offset and the original's class is current (premises: Cont INFERRED, Reveal MEASURED for the offset and INFERRED for its timing; where Reveal fails the arms differ for at most 48 px of scroll, Lean drift_window); the flip runs in the UI process (INFERRED), so its frame can differ by one from the main-thread class; WebKit promotes the stage content above the animated layer (overlap, RenderLayerCompositor.cpp:1332-1335@862f17d, 12 MB more backing while the Pain stage is in view, Lean promoted_cost, hold_backing) and restyles the layer every scrolling frame (scroll_comp_ride)"},{"name":"dark-static","kind":"proposal","limit":"look change: at most 860 px the two pseudo-element layers are #131922 from the start and people.card never writes is-pain-dark, so the white Pain top that the original shows before the flip is dark; the premise Hidden (white state never in view) fails at 390 and 640 (MEASURED, trajectory probe run 39852164349: Pain top 370 and 843 px below the flip offset 873, 891.5 needed (Lean hidden_fails_390, hidden_fails_640)); no animated layer, so no overlap promotion and no extra backing (Lean static_eq_base)"}]},{"id":"pain.notes","slot":"pain","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"visible","kind":"optimized","limit":""},{"name":"visible-idem","kind":"optimized","limit":"a covered frame after a note move still commits once, as in the original; skipping on empty extras alone is not E (Lean naive_not_E)"}]},{"id":"people.card","slot":"people","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"mq","kind":"optimized","limit":"Lean premise P1 (the c860 band is fixed per load) is not enforced: outside P1, a resize across c860 shows a multi-frame visible lerp of scale and radius from the stale frozen value (INFERRED)"}]},{"id":"people.carousel","slot":"people","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"crop","kind":"proposal","limit":"look change (L, user look review): the leaver keeps its 32 px box and fades and scales under the followers, so its collapse and border-width shrink are gone (the differing region is the 32 px leaver slot); followers move by the compositor translate, within one device pixel of the layout position (LayoutUnit rounding not modelled). No clip-path is animated: a clip-path effect ticks on main in WebKit (wkThread) and paints in Chromium, so the crop is the container's existing overflow clip. Six compositor effects against one (a trade on the comp stage) and five animated layers (about 0.18 MB at dpr 3) for 220 ms of every 1.02 s."}]},{"id":"people.deck","slot":"people","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""}]},{"id":"people.o","slot":"people","impls":["plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"preview-translate","kind":"optimized","limit":"desktop only (the card exists above 860 px); a kept scroll frame sets translate by the integer scroll delta and writes no left/top, a flip, resize or layout shift rewrites them; the card needs its own layer for the layout win (WebKit table: transform on a non-composited layer still lays out)"}]},{"id":"platform","slot":"platform","impls":["mui","plain"],"requires":{},"conflicts":{"platform:fade-threaded":["morph.tween:waapi","morph.tween:waapi-scoped"]},"variants":[{"name":"faithful","kind":"faithful","limit":""},{"name":"mq","kind":"optimized","limit":"phone band only: skips the --platform-shrink write while mq.c860 matches and writes the current value when the band is left; the saving may sit outside the felt end-of-page window (INFERRED)"},{"name":"fade-threaded","kind":"optimized","limit":"one opacity and blur effect per push replaces the per-frame --morph-fade write; equal values under the WAAPI premises, but CA's blur is not the software blur (pixels at best Q on WebKit); the section's blur layer is tiled above 1280 px; Chromium keeps the blur on the main thread"}]},{"id":"platform.entries","slot":"platform","impls":["mui","plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""}]},{"id":"platform.glint","slot":"platform","impls":["mui","plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""}]},{"id":"platform.marquee","slot":"platform","impls":["mui","plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""}]},{"id":"platform.stageBg","slot":"platform","impls":["mui","plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""}]},{"id":"platform.sweep","slot":"platform","impls":["mui","plain"],"requires":{},"conflicts":{},"variants":[{"name":"faithful","kind":"faithful","limit":""}]}],"presets":[{"name":"original","fw":{}},{"name":"strip-demo","extends":"original","fw":{"hero.countdown":"strip"}},{"name":"v2-proved","extends":"original","fw":{}}]},"picks":[],"ledger":[{"part":"engine.scroll","candidate":"batched (all reads, then all returned writes, one pass per frame)","status":"proved","flags":["engine.scroll:batched"]},{"part":"engine.scroll","candidate":"observers (KD#1): replace per-frame rect reads with IntersectionObserver/ResizeObserver","status":"not-tried","flags":[]},{"part":"nav.hitTest","candidate":"hit-skip (skip the probe while morph > 0.2)","status":"proved","flags":["nav.hitTest:hit-skip"]},{"part":"nav.hitTest","candidate":"elements-skip (elementsFromPoint with an allow-list, no pointer-events write)","status":"proved","flags":["nav.hitTest:elements-skip"]},{"part":"nav.hitTest","candidate":"write-on-change (toggle is-on-dark only when it changes)","status":"proved","flags":[]},{"part":"hero.exit","candidate":"hero-exit-threaded (v6, KD#2): JS --exit-opacity writer → per-consumer CSS scroll-driven animations, plus an IO sentinel for pointer-events","status":"partly-proved","flags":["hero.exit:threaded"]},{"part":"hero.countdown (+ morph.countdown)","candidate":"strip (cd-strip, KD#12): 10 will-change faces per digit -> one 12-entry strip","status":"proved","flags":["hero.countdown:strip","morph.countdown:strip"]},{"part":"hero.countdown","candidate":"cd-roll-ca: spring roll replaced by a WAAPI transform animation with sampled keyframes","status":"partly-proved","flags":[]},{"part":"hero.countdown","candidate":"clock-aligned timer (KD#19): setInterval(1000) replaced by a timeout chain aimed at T0 + k*1000","status":"proved","flags":[]},{"part":"hero.countdown / morph.countdown","candidate":"hidden-skip: skip face writes while the clock is not visible; the spring keeps integrating","status":"proved","flags":["hero.countdown:hidden-pause","morph.countdown:hidden-pause"]},{"part":"morph.tween","candidate":"g0.0b: the rAF tween replaced by one WAAPI animation on a registered --morph with cubic-bezier(1/3,1,2/3,1)","status":"proved","flags":["morph.tween:waapi"]},{"part":"morph.tween","candidate":"CM / compositor-morph (PR-030): transforms on a scroll timeline, rounded box from 4 corner clippers","status":"not-proved","flags":[]},{"part":"morph.panel (platform panel)","candidate":"blur(0) -> filter:none at rest (MorphPanelOpt rest variant)","status":"proved","flags":[]},{"part":"morph.panel (end-of-page glass)","candidate":"constant glass (g0.0k): the animated backdrop blur replaced by a constant 20 px one","status":"not-proved","flags":[]},{"part":"morph.panel (end-of-page bar)","candidate":"g0.0f: the bar's colour from two flat GPU layers plus a clip shape (Safari only)","status":"not-tried","flags":[]},{"part":"morph.panel (platform panel)","candidate":"own layer during the blur fade (MorphPanelOpt sub-claim 2; v1 g0.1b)","status":"proved","flags":[]},{"part":"morph.mount","candidate":"warm-up: mount the panel at a still moment near the end (v14, D1 always-built card)","status":"proved","flags":["morph.mount:shift"]},{"part":"morph.countdown","candidate":"own clock layer: the clock wrapper in the menu centre composited while the menu is open (KD#12 menuClock.ownLayer; v1 panel-clock-layer and g0.0i)","status":"not-proved","flags":[]},{"part":"morph.countdown","candidate":"strip (10 will-change faces per digit -> one 12-entry strip), reused from hero.countdown (KD#12, cd-strip)","status":"proved","flags":["morph.countdown:strip"]},{"part":"morph.columns","candidate":"columns as a still picture while the menu is closed (g0.0h keep-phase = hidden-pause of the marquee)","status":"partly-proved","flags":["morph.columns:hidden-pause"]},{"part":"morph.columns","candidate":"dprSized images (KD#16: five 1282x1282 PNGs in ~138 px columns resized to drawn size x 1.2)","status":"not-proved","flags":[]},{"part":"hero.accent","candidate":"accent-wipe (v1): stroke-dashoffset draw -> counter-translated clip wipe","status":"not-proved","flags":[]},{"part":"hero.accent","candidate":"boil variant `steps`: chain of zero-duration fill-forwards opacity steps (v2 Lean variant)","status":"proved","flags":["hero.accent:steps"]},{"part":"hero.accent","candidate":"boil-ca (v1): step-end -> keyword linear with 0.01 % jumps, so the timing is CA-acceptable","status":"not-proved","flags":[]},{"part":"people.card","candidate":"MQ-gated shrink (KD#3): skip the --future-shrink write and the rAF re-request in the c860 band","status":"proved","flags":["people.card:mq"]},{"part":"people.card","candidate":"PR-041 instant reveal: skip the blur/opacity fade after a fast flick","status":"not-proved","flags":[]},{"part":"people.card","candidate":"blur tail cut 1.6 s -> 0.9 s via a 17-stop linear() resample, then snap to none (KD#15, large-area-blur)","status":"not-proved","flags":[]},{"part":"people.card","candidate":"g0.0m pre-painted card: visibility visible and will-change opacity at opacity 0 on touch screens","status":"partly-proved","flags":[]},{"part":"people.o","candidate":"FLIP (people-gpu, PR-031): set the final grid size once, slide the parts with WAAPI translate","status":"not-proved","flags":[]},{"part":"people.carousel","candidate":"keep the 5 slots mounted and update src in place (st5)","status":"not-proved","flags":[]},{"part":"people.carousel","candidate":"rest at opacity 0.999 and scale(1) so no presence flip happens (st6, KD#8)","status":"not-proved","flags":[]},{"part":"people.carousel","candidate":"st6 slide geometry: width/flex-basis/margin shrink of the leaver -> clip-path ellipse crop + translate; followers translate (layout-animations)","status":"not-proved","flags":[]},{"part":"people.carousel","candidate":"people.carousel:crop: avatars-exit animates width, flex-basis, margin-right and border-width (layout every frame in both engines); the crop variant animates opacity and transform on the leaver and the compositor translate on the followers","status":"look-change","flag":"people.carousel:crop","flags":["people.carousel:crop"],"id":"people.carousel.crop"},{"part":"people.deck","candidate":"cqiFormula sizing (g0.0j): aspect-ratio + height:auto -> container-type:inline-size + height:calc(100cqi*764/353)","status":"partly-proved","flags":[]},{"part":"pain.notes","candidate":"arm the 3 s rotation interval only while visible (armed = inView and not narrow and not covered)","status":"proved","flags":["pain.notes:visible"]},{"part":"pain.notes","candidate":"solid-colour composited layer for the is-pain-dark background flip (n10-d)","status":"not-tried","flags":[]},{"part":"commission.typing","candidate":"commission-forced-layout: cached matchMedia, line count via ResizeObserver, compact-band snap, write-on-change","status":"partly-proved","flags":[]},{"part":"commission.typing","candidate":"no container-type above per-frame text (platform.containers off)","status":"not-tried","flags":[]},{"part":"commission.typing","candidate":"typing-chunks: 2 characters per step (bubble, agents query), count-up written every 48 ms","status":"proved","flags":[]},{"part":"platform.sweep","candidate":"sweep-exact G3: background-position sweep -> ::after band moved by translateX under -webkit-mask-clip:text (illusion-sweep: darken-blend variant)","status":"partly-proved","flags":[]},{"part":"platform.glint","candidate":"glint-ca G1: SMIL x1/x2 on a linearGradient -> clip-path:path() span with a gradient strip moved by transform","status":"not-proved","flags":[]},{"part":"engine.scene","candidate":"covered pause (hero under the 0.999-opacity People card, KD#18 hero-covered-pause)","status":"not-proved","flags":[]},{"part":"engine.scene","candidate":"hidden pause of compositor marquees (morph.columns at m <= 0.08, scene off-screen), HiddenPause.lean","status":"proved","flags":["morph.columns:hidden-pause","engine.scene:hidden-pause"]},{"part":"engine.scene","candidate":"hysteresis and idle pre-warm for the scene/deferral gate (KD#10)","status":"partly-proved","flags":[]},{"part":"engine.scene","candidate":"morph.countdown hidden: keep the spring integrating, skip the 16 face writes per digit (HiddenPause skipWrites)","status":"proved","flags":["morph.countdown:hidden-pause"]},{"part":"engine.scene","candidate":"pause per element instead of the section-wide :where(*) animation-play-state rule (KD#10)","status":"partly-proved","flags":[]},{"part":"premise","candidate":"premise cv.auto-margin: a node under a content-visibility-skipped subtree reports unresolved auto margins","status":"refuted","flags":[],"id":"premise.cv.auto-margin"},{"part":"premise","candidate":"premise anim.list: getAnimations lists every running CSS animation and transition and no rAF lerp","status":"intermittent","flags":[],"id":"premise.anim.list"},{"part":"gate.page-root","candidate":"page-root gate anchor scrollWidth <= innerWidth, modelled with innerWidth fixed at the requested viewport (Fw.Gate.PageRoot, faithful-checks-rerun round 1)","status":"refuted","flags":[],"id":"gate.pageRoot.fixedInnerWidth"},{"part":"hero.exit","candidate":"hero.exit:scoped (exit-scoped-var): register --exit-opacity and --exit-scatter with inherits: false and re-inherit them only on the 7 classes between the stage and the 16 readers","status":"partly-proved","flags":["hero.exit:scoped"],"id":"hero.exit.scoped","supersededBy":"hero.exit.scoped.inline"},{"part":"hero.countdown","candidate":"hero.countdown:one-chain (countdown-one-chain): run every rolling digit's rAF chain from one subscriber of the shared loop instead of one rAF callback per digit; faces, setInterval(1000) and transform writes unchanged","status":"partly-proved","flags":["hero.countdown:one-chain"],"id":"hero.countdown.oneChain"},{"part":"morph.tween","candidate":"morph.tween:waapi-scoped (tween-platform-scope): the WAAPI tween with a non-inherited --platform-morph, so the platform subtree leaves every tween frame","status":"partly-proved","flags":["morph.tween:waapi-scoped"],"id":"morph.tween.waapiScoped"},{"part":"morph.mount","candidate":"morph.mount:shift-dormant (morph-layers): keep shift's early mount but keep the panel's timed state asleep (marquee tracks animation-name: none, no countdown driver) until the original trigger","status":"partly-proved","flags":["morph.mount:shift-dormant"],"id":"morph.mount.shiftDormant"},{"part":"morph.mount","candidate":"morph.mount idle-none (morph-layers, rejected): animation-name: none on the paused end scene to drop its layers","status":"not-tried","flags":[],"id":"morph.mount.idleNone"},{"part":"pain.notes","candidate":"pain.notes:visible-idem (notes-scroll-idem): skip the covered-frame commit that writes nothing","status":"proved","flags":["pain.notes:visible-idem"],"id":"pain.notes.visibleIdem"},{"part":"nav.morph","candidate":"contain the fixed nav's relayout with a containment boundary (nav-oof-root-finding)","status":"refuted","flags":[],"id":"nav.oofRoot.containment"},{"part":"premise","candidate":"premise cv.used-margin-fresh: getComputedStyle reads the used auto margin of a node in a content-visibility-skipped subtree fresh at stop 0 (commission-margin-recur)","status":"refuted","flags":[],"id":"premise.cv.used-margin-fresh"},{"part":"premise","candidate":"premise cv.margin-typed-om: computedStyleMap margin reads give the computed value, not the used one (cmr-margin-typed-om)","status":"proved","flags":[],"id":"premise.cv.margin-typed-om"},{"part":"gate.margin","candidate":"margin rule: when both arms are non-fixed (auto or percent), decide the margin cell by its rect cell (cmr-margin-rect-rule)","status":"proved","flags":[],"id":"gate.margin.rectRule"},{"part":"premise","candidate":"premise: Playwright's context screen survives a live resize (gate-green-baseline)","status":"refuted","flags":[],"id":"premise.webkit.screen-kept"},{"part":"load.bundle","candidate":"named import of the breakpoint conditions so the bundler drops matrix, edgePairs and backingTheorems (breakpoints-named-import)","status":"partly-proved","flags":[],"id":"load.breakpoints.namedImport"},{"part":"tooling.land","candidate":"land: build fwcore once in a prep job and share it with the land legs instead of one parallel build per leg (land-fwcore-once, reverted)","status":"refuted","flags":[],"id":"tooling.land.fwcoreOnce"},{"part":"tooling.land","candidate":"land: split the lane into parallel legs (land-lane-speed)","status":"proved","flags":[],"id":"tooling.land.legs"},{"part":"tooling.fwcore","candidate":"fwcore: build its tables lazily instead of at startup (fwcore-startup)","status":"proved","flags":[],"id":"tooling.fwcore.lazyTables"},{"part":"tooling.ci","candidate":"run some CI jobs on CircleCI's free tier (circleci-pilot)","status":"partly-proved","flags":[],"id":"tooling.ci.circleciPilot"},{"part":"morph.tween","candidate":"morph.tween:waapi falsified on real devices: the nav classes stay stale for the whole morph, so the logo stays static and then jumps","status":"refuted","flag":"morph.tween:waapi","flags":["morph.tween:waapi"],"id":"morph.tween.waapi.falsified"},{"part":"morph.tween","candidate":"morph.tween:waapi-scoped falsified on real devices: it shares the waapi driver, so the nav classes stay stale for the whole morph","status":"refuted","flag":"morph.tween:waapi-scoped","flags":["morph.tween:waapi-scoped"],"id":"morph.tween.waapiScoped.falsified"},{"part":"hero.exit","candidate":"hero.exit:scoped falsified on WebKit: the hero readers keep a stale cached style while --exit-opacity changes","status":"refuted","flag":"hero.exit:scoped","flags":["hero.exit:scoped"],"id":"hero.exit.scoped.falsified","supersededBy":"hero.exit.scoped.inline"},{"part":"nav","candidate":"nav:earn-no-transition: the earn button's max-width, padding-inline and opacity transitions are off while the nav morphs, so they follow --morph instead of retargeting every frame","status":"look-change","flag":"nav:earn-no-transition","flags":["nav:earn-no-transition"],"id":"nav.earn.noTransition"},{"part":"morph.panel","candidate":"C1 final-size: lay the panel, backdrop and columns out once at the final panel size, centred in the nav and clipped by its overflow: hidden (panel-final-size)","status":"refuted","flags":[],"id":"morph.panel.finalSize.visual"},{"part":"hero.exit","candidate":"hero.exit:scoped with inline reader writes (task exit-scoped-inline): the writer sets --exit-opacity and --exit-scatter inline on each of the 16 readers in the frame it writes the stage","status":"proved","flags":["hero.exit:scoped"],"id":"hero.exit.scoped.inline"},{"part":"morph.tween","candidate":"morph.tween:waapi keeps the original's nav width tail after a close: the driver writes the base --morph from 100 ms before the 0.001 marker to the end of a close","status":"partly-proved","flag":"morph.tween:waapi","flags":["morph.tween:waapi"],"id":"morph.tween.waapi.navWidthTail"},{"part":"morph.tween","candidate":"morph.tween:scroll-lock (C4): hold the root at overflow: hidden while the morph is active, only where the primary input hovers and the scrollbar is an overlay one, instead of relying on the scrollTo pin alone","status":"look-change","flag":"morph.tween:scroll-lock","flags":["morph.tween:scroll-lock"],"id":"morph.tween.scrollLock"},{"part":"hero","candidate":"hero:scene-pause: port the original paused-scene rule to the hero track (will-change auto and animations paused while the scene is far off-screen), so WebKit stops keeping the hero layers composited at the end of the page","status":"partly-proved","flag":"hero:scene-pause","flags":["hero:scene-pause"],"id":"hero.scenePause"},{"part":"engine.scroll","candidate":"engine.scroll:throttle-lift (diagnostic, never in a preset): remove the cause of Safari's 100 ms scroll-event throttle at the hero exit to test whether the throttle produces the still runs felt as lag","status":"partly-proved","flag":"engine.scroll:throttle-lift","flags":["engine.scroll:throttle-lift"],"id":"engine.scroll.throttleLift"},{"part":"platform","candidate":"platform:mq: skip the --platform-shrink write while the phone-band media query matches (the card look does not read it there); write the current value at once when the page leaves the band","status":"partly-proved","flag":"platform:mq","flags":["platform:mq"],"id":"platform.mq"},{"part":"hero.accent","candidate":"hero.accent:draw-one: in the draw window run the stroke-dashoffset animation on the visible copy (frame0) only; the two copies at opacity 0 (accent.module.css:79-86) get no animation","status":"proved","flag":"hero.accent:draw-one","flags":["hero.accent:draw-one"],"id":"accent.draw-one"},{"part":"platform","candidate":"platform:fade-threaded: run the section fade of a morph push as one opacity and blur Web Animation per push (Core Animation on WebKit) instead of writing --morph-fade every frame","status":"partly-proved","flag":"platform:fade-threaded","flags":["platform:fade-threaded"],"id":"platform.fade-threaded"},{"part":"morph.panel","candidate":"morph.panel:const-bounds: while the nav morphs, keep the panel layer at the nav's final box and inset every child onto the nav box, so the blur-backed panel layer is not resized on any morph frame","status":"partly-proved","flag":"morph.panel:const-bounds","flags":["morph.panel:const-bounds"],"id":"morph.panel-const-bounds"},{"part":"commission","candidate":"commission:band-gate: in the c1000 band skip the two custom-property writes (--commission-enter-shrink, --commission-shrink) every follower frame, since the CSS pins scale 1 and radius 0 there; write the current pair on the first frame that reads the band off","status":"partly-proved","flag":"commission:band-gate","flags":["commission:band-gate"],"id":"commission.band-gate"},{"part":"pain","candidate":"pain:dark-scroll: at most 860 px, replace the is-pain-dark class flip (section restyle and background repaint) with two empty solid layers whose opacity runs on the root scroll timeline with steps(1, jump-start), range start 256 px before the flip written once per layout; people.card stops toggling the class where the engine runs it (continues n=21)","status":"partly-proved","flag":"pain:dark-scroll","flags":["pain:dark-scroll"],"id":"pain.dark-scroll"},{"part":"morph.mount","candidate":"morph.mount:band + morph.tween:band: one window touch listener for both morph parts, non-passive only while the platform section is in the band or a morph runs, passive elsewhere, so a pan far from the end of the page does not wait for the web main thread","status":"partly-proved","flag":"morph.mount:band","flags":["morph.mount:band","morph.tween:band"],"id":"morph.touch-band"},{"part":"nav","candidate":"nav:clip-box: while the nav morphs the box is the union of its boxes at constant size and the pill is a clip-path inset, so the morph writes no width, height, top or border-radius on the nav; the bar and the panel are still placed by the insets, so they lay out per frame","status":"partly-proved","flag":"nav:clip-box","flags":["nav:clip-box"],"id":"nav.clip-box"},{"part":"nav","candidate":"nav:bar-fixed (includes clip-box): the bar keeps its union width and moves by translate, the logo and actions by closed-form translations, so the morph writes no layout property on the bar","status":"partly-proved","flag":"nav:bar-fixed","flags":["nav:bar-fixed"],"id":"nav.bar-fixed"},{"part":"nav","candidate":"nav:logo-3d (includes bar-fixed): the logo moves by translate3d and scale in one transform so it composites instead of repainting","status":"partly-proved","flag":"nav:logo-3d","flags":["nav:logo-3d"],"id":"nav.logo-3d"},{"part":"morph.panel","candidate":"morph.panel:threaded: run the panel's opacity, blur and scale of a morph push as two Web Animation effects (opacity with scale, and blur alone) instead of three style writes per frame","status":"partly-proved","flag":"morph.panel:threaded","flags":["morph.panel:threaded"],"id":"morph.panel-threaded"},{"part":"people.o","candidate":"people.o:preview-translate: move the fixed seller preview card with the translate property by the integer scroll delta instead of writing top in every scroll frame (desktop, above 860 px)","status":"partly-proved","flag":"people.o:preview-translate","flags":["people.o:preview-translate"],"id":"people.o-preview-translate"},{"part":"morph.columns","candidate":"morph.columns:idle-none: remove the marquee track animations (animation-name none) while the scene rule pauses the panel, and seek them back to their kept time on return","status":"partly-proved","flag":"morph.columns:idle-none","flags":["morph.columns:idle-none"],"id":"morph.columns-idle-none"},{"part":"hero.accent","candidate":"hero.accent:draw-nolayout: the draw reveals the visible copy with a clip-path inset() wipe (kept 0.9 s, same easing) and the stroke stays whole, instead of animating stroke-dashoffset on three stacked copies","status":"look-change","flag":"hero.accent:draw-nolayout","flags":["hero.accent:draw-nolayout"],"id":"accent.draw-nolayout"},{"part":"hero.accent","candidate":"hero.accent:draw-nolayout-full: draw-nolayout plus no width transition on the host (transition: none on .drawingIn), so the word box takes its new width in one frame at the start of the draw-in and every other draw frame changes only clip-path","status":"look-change","flag":"hero.accent:draw-nolayout-full","flags":["hero.accent:draw-nolayout-full"],"id":"accent.drawin-width-nolayout"},{"part":"premise","candidate":"premise: a Playwright WebKit trusted wheel carries a momentum phase (morph-wheel-momentum)","status":"refuted","flags":[],"id":"premise.webkit.wheel-momentum"},{"part":"morph.tween","candidate":"morph-wheel-momentum: overlap a moving drawn scroll with the open morph on the CI macOS Playwright WebKit wheel lane (pull drive)","status":"refuted","flags":[],"id":"morph.wheel.lock-no-moving-scroll"},{"part":"hero.accent","candidate":"hero.accent same-look: trace the stroke by animating stroke-dasharray instead of stroke-dashoffset","status":"refuted","flags":[],"id":"accent.same.dasharray"},{"part":"hero.accent","candidate":"hero.accent same-look: rewrite each path d per frame to the drawn part of the stroke","status":"refuted","flags":[],"id":"accent.same.path-d"},{"part":"hero.accent","candidate":"hero.accent same-look: pre-rendered sprite of the draw, stepped background-position (or mask-position)","status":"partly-proved","flags":[],"id":"accent.same.sprite"},{"part":"hero.accent","candidate":"hero.accent same-look: draw the stroke in a CSS Paint API worklet driven by a registered custom property","status":"refuted","flags":[],"id":"accent.same.paint-api"},{"part":"hero.accent","candidate":"hero.accent same-look: show the final stroke clipped to the region the pen has swept so far","status":"refuted","flags":[],"id":"accent.same.clip-final"},{"part":"hero.accent","candidate":"hero.accent same-look: draw the stroke per frame on a fixed-size canvas 2D (setLineDash, lineDashOffset) in requestAnimationFrame","status":"partly-proved","flags":[],"id":"accent.same.canvas"},{"part":"hero.accent","candidate":"hero.accent same-look: keep the accent at its final width from the draw-in start and translate the first and last words by +-(wf - w(t))/2 with the same 0.9 s easing","status":"partly-proved","flags":[],"id":"accent.same.glide"},{"part":"engine.scroll","candidate":"engine.scroll:unthrottle: ship the throttle-lift element (one fixed 1 px opacity-0 element with a root scroll-driven animation of a registered custom property, inside @supports) so Mobile Safari stops holding visible-rect updates to 100 ms while the toolbar collapses","status":"partly-proved","flag":"engine.scroll:unthrottle","flags":["engine.scroll:unthrottle"],"id":"engine.scroll.unthrottle"}]}"#

def registryHas (part variant : String) : Bool :=
  match cmpReal.getObjVal? "registry" >>= (·.getObjVal? "parts") >>= (·.getArr?) with
  | .ok ps => ps.any fun p =>
      (p.getObjValAs? String "id").toOption == some part &&
      (match p.getObjVal? "variants" >>= (·.getArr?) with
       | .ok vs => vs.any fun v => (v.getObjValAs? String "name").toOption == some variant
       | .error _ => false)
  | .error _ => false

#guard Fw.Parts.Gpu.entries.all fun e => registryHas e.part e.variant

def spawn (alive extra call : String) : Json :=
  lit s!"\{\"alive\":{alive},\"roles\":{roles},\"now\":1000{extra},\"req\":{call}}"

def aliveN (p role kind : String) (n : Nat) : String :=
  "[" ++ ",".intercalate ((List.range n).map fun k =>
    s!"\{\"name\":\"{p}{k}\",\"role\":\"{role}\",\"kind\":\"{kind}\"}") ++ "]"

def wait' (cmd : String) (caps : String) : Json :=
  Json.mkObj [("cmd", .str cmd), ("caps", lit caps)]

def wait (cmd : String) : Json := Json.mkObj [("cmd", .str cmd)]

def cases (_ : Unit := ()) : List (String × List (String × Json)) := [
  ("ops.spawn", [
    ("named worktree subagent with isolation: allow", spawn "[]" "" "{\"name\":\"lean-ops\",\"role\":\"lean-prover\",\"isolation\":\"worktree\",\"spawner\":\"lead\",\"depth\":0}"),
    ("worktree role without isolation becomes a teammate: deny (I-272 trap)", spawn "[]" "" "{\"name\":\"lean-ops\",\"role\":\"lean-prover\",\"spawner\":\"lead\",\"depth\":0}"),
    ("teammate role with worktree isolation: allow (shadow-log false positive)", spawn "[]" "" "{\"name\":\"res-1\",\"role\":\"researcher\",\"isolation\":\"worktree\"}"),
    ("teammate role, named, no isolation: allow", spawn "[]" "" "{\"name\":\"res-1\",\"role\":\"researcher\",\"isolation\":null}"),
    ("fable per call: needs approval", spawn "[]" "" "{\"name\":\"lean-x\",\"role\":\"lean-prover\",\"isolation\":\"worktree\",\"model\":\"claude-fable-5-1\"}"),
    ("fable but over a cap: deny wins", spawn (aliveN "l" "lean-prover" "worktree" 3) "" "{\"name\":\"lean-x\",\"role\":\"lean-prover\",\"isolation\":\"worktree\",\"model\":\"fable\"}"),
    ("unnamed call: deny", spawn "[]" "" "{\"role\":\"Explore\"}"),
    ("unnamed read-only subagent with unnamedReadOnly: allow", spawn "[]" ",\"caps\":{\"unnamedReadOnly\":true}" "{\"role\":\"Explore\"}"),
    ("name in use: deny", spawn "[{\"name\":\"lean-ops\",\"role\":\"lean-prover\",\"kind\":\"worktree\"}]" "" "{\"name\":\"lean-ops\",\"role\":\"lean-prover\",\"isolation\":\"worktree\"}"),
    ("unknown role: deny", spawn "[]" "" "{\"name\":\"x\",\"role\":\"general-purpose\",\"isolation\":\"worktree\"}"),
    ("editing role from a depth-1 spawner: deny", spawn "[]" "" "{\"name\":\"x\",\"role\":\"lean-prover\",\"isolation\":\"worktree\",\"spawner\":\"eng-webkit\",\"depth\":1}"),
    ("read-only helper from a depth-1 spawner: allow", spawn "[]" "" "{\"name\":\"loc-1\",\"role\":\"reviewer\",\"spawner\":\"eng-webkit\",\"depth\":1}"),
    ("6th teammate: deny", spawn (aliveN "t" "researcher" "teammate" 5) "" "{\"name\":\"t9\",\"role\":\"researcher\"}"),
    ("9th worktree subagent: deny", spawn (aliveN "w" "part-builder" "worktree" 8) "" "{\"name\":\"w9\",\"role\":\"lean-prover\",\"isolation\":\"worktree\"}"),
    ("11th subagent in all: deny", spawn (aliveN "s" "reviewer" "subagent" 10) "" "{\"name\":\"s99\",\"role\":\"reviewer\",\"spawner\":\"eng-webkit\",\"depth\":1}"),
    ("4th lean-prover: deny capRole", spawn (aliveN "l" "lean-prover" "worktree" 3) "" "{\"name\":\"l9\",\"role\":\"lean-prover\",\"isolation\":true}"),
    ("11th spawn in 10 min by one spawner: deny", spawn "[]" ",\"recent\":[{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500}]" "{\"name\":\"x\",\"role\":\"lean-prover\",\"isolation\":\"worktree\"}"),
    ("spawns older than the window do not count: allow", spawn "[]" ",\"recent\":[{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400}]" "{\"name\":\"x\",\"role\":\"lean-prover\",\"isolation\":\"worktree\"}"),
    ("custom caps", spawn (aliveN "t" "researcher" "teammate" 2) ",\"caps\":{\"teammates\":2,\"perRole\":{},\"askModels\":[]}" "{\"name\":\"t9\",\"role\":\"researcher\"}"),
    ("bad kind is refused", spawn "[{\"name\":\"a\",\"role\":\"r\",\"kind\":\"robot\"}]" "" "{\"name\":\"x\",\"role\":\"reviewer\"}"),
    ("bad isolation is refused", spawn "[]" "" "{\"name\":\"x\",\"role\":\"lean-prover\",\"isolation\":\"container\"}")]),
  ("ops.pathCheck", [
    ("lean-prover scope: math.lock excluded, docs outside", lit "{\"scope\":[\"lean/**\",\"!lean/math.lock.json\"],\"paths\":[\"lean/Fw/Ops/Usage.lean\",\"lean/math.lock.json\",\"docs/plan/PLAN.md\"]}"),
    ("all inside", lit "{\"scope\":[\"lean/**\"],\"paths\":[\"lean/Fw.lean\",\"lean/golden/ops-x.txt\"]}"),
    ("dot-dot and empty paths are never in scope; ./ and // normalise", lit "{\"scope\":[\"lean/**\"],\"paths\":[\"lean/../docs/x.md\",\"\",\"./lean//Fw.lean\"]}"),
    ("star inside a segment; directory prefix", lit "{\"scope\":[\"packages/measure-*\",\"apps/console-*/**\"],\"paths\":[\"packages/measure-webkit/src/a.ts\",\"packages/model/x.ts\",\"apps/console-web/src/App.tsx\",\"apps/site/x\"]}"),
    ("part slug is a whole segment", lit "{\"scope\":[\"apps/site/src/parts/hero/**\"],\"paths\":[\"apps/site/src/parts/hero/a.tsx\",\"apps/site/src/parts/heroX/a.tsx\"]}"),
    ("trailing slash is a directory prefix", lit "{\"scope\":[\"research/notes/\",\"refs/**\"],\"paths\":[\"research/notes/2026/a.md\",\"research/decisions/b.md\",\"refs/x\"]}"),
    ("double star in the middle", lit "{\"scope\":[\"docs/**/*.md\"],\"paths\":[\"docs/a.md\",\"docs/x/y/b.md\",\"docs/x/c.html\"]}"),
    ("empty scope: everything is a violation", lit "{\"scope\":[],\"paths\":[\"a\"]}"),
    ("no paths", lit "{\"scope\":[\"lean/**\"],\"paths\":[]}")]),
  ("ops.usage", [
    ("partial lines of one message joined per field; non-usage lines skipped", lit "{\"lines\":[{\"type\":\"assistant\",\"message\":{\"id\":\"msg_1\",\"usage\":{\"input_tokens\":3,\"cache_read_input_tokens\":1000,\"output_tokens\":1}}},{\"type\":\"user\",\"message\":{\"role\":\"user\"}},{\"type\":\"assistant\",\"message\":{\"id\":\"msg_1\",\"usage\":{\"input_tokens\":3,\"cache_read_input_tokens\":1000,\"cache_creation_input_tokens\":200,\"cache_creation\":{\"ephemeral_5m_input_tokens\":200,\"ephemeral_1h_input_tokens\":0},\"output_tokens\":57}}}]}"),
    ("same lines reversed give the same table", lit "{\"lines\":[{\"type\":\"assistant\",\"message\":{\"id\":\"msg_1\",\"usage\":{\"input_tokens\":3,\"cache_read_input_tokens\":1000,\"cache_creation_input_tokens\":200,\"cache_creation\":{\"ephemeral_5m_input_tokens\":200,\"ephemeral_1h_input_tokens\":0},\"output_tokens\":57}}},{\"type\":\"user\",\"message\":{\"role\":\"user\"}},{\"type\":\"assistant\",\"message\":{\"id\":\"msg_1\",\"usage\":{\"input_tokens\":3,\"cache_read_input_tokens\":1000,\"output_tokens\":1}}}]}"),
    ("table plus new records: sorted by id, totals summed", lit "{\"table\":[{\"id\":\"b\",\"input\":1,\"output\":10}],\"records\":[{\"id\":\"a\",\"cache1h\":5},{\"id\":\"b\",\"output\":12},{\"id\":\"b\",\"output\":11}]}"),
    ("duplicates change nothing", lit "{\"records\":[{\"id\":\"a\",\"input\":2},{\"id\":\"a\",\"input\":2}]}"),
    ("empty", lit "{}"),
    ("a non-integer count is refused", lit "{\"records\":[{\"id\":\"a\",\"input\":1.5}]}")]),
  ("ops.meter", [
    ("each rule at its threshold", lit "{\"now\":100,\"agents\":[{\"agent\":\"big\",\"ctx\":200001,\"idleSec\":0,\"ttlSec\":300},{\"agent\":\"edge\",\"ctx\":200000,\"idleSec\":240,\"ttlSec\":300},{\"agent\":\"idle\",\"ctx\":1000,\"idleSec\":241,\"ttlSec\":300},{\"agent\":\"cold\",\"ctx\":50000,\"idleSec\":0,\"ttlSec\":300,\"wakeGapSec\":301}]}"),
    ("already fired in this window: no repeat", lit "{\"now\":200,\"state\":{\"window\":0,\"fired\":[{\"agent\":\"idle\",\"rule\":\"idleExpiring\"}]},\"agents\":[{\"agent\":\"idle\",\"ctx\":1000,\"idleSec\":341,\"ttlSec\":300}]}"),
    ("next window: fires again", lit "{\"now\":3700,\"state\":{\"window\":0,\"fired\":[{\"agent\":\"idle\",\"rule\":\"idleExpiring\"}]},\"agents\":[{\"agent\":\"idle\",\"ctx\":1000,\"idleSec\":3841,\"ttlSec\":300}]}"),
    ("ttl from cache writes; verdicts", lit "{\"now\":0,\"agents\":[{\"agent\":\"h1\",\"ctx\":50000,\"idleSec\":400,\"w5m\":10,\"w1h\":90},{\"agent\":\"m5\",\"ctx\":50000,\"idleSec\":400,\"w5m\":90,\"w1h\":10},{\"agent\":\"small\",\"ctx\":20000,\"idleSec\":400,\"ttlSec\":300}]}"),
    ("custom params", lit "{\"now\":0,\"params\":{\"ctxMax\":100,\"leadSec\":0,\"windowSec\":60,\"respawnCtx\":10},\"agents\":[{\"agent\":\"a\",\"ctx\":101,\"idleSec\":300,\"ttlSec\":300}]}"),
    ("duplicate agents in one tick alert once", lit "{\"now\":0,\"agents\":[{\"agent\":\"a\",\"ctx\":300000,\"idleSec\":0,\"ttlSec\":300},{\"agent\":\"a\",\"ctx\":300000,\"idleSec\":0,\"ttlSec\":300}]}"),
    ("unknown rule in state is refused", lit "{\"now\":0,\"state\":{\"fired\":[{\"agent\":\"a\",\"rule\":\"loud\"}]},\"agents\":[]}")]),
  ("ops.hook", [
    ("PostToolUse from a subagent (tool input and response dropped)", lit "{\"payloads\":[{\"session_id\":\"s1\",\"transcript_path\":\"/x\",\"cwd\":\"/y\",\"hook_event_name\":\"PostToolUse\",\"agent_id\":\"a1\",\"agent_type\":\"lean-prover\",\"tool_name\":\"Bash\",\"tool_use_id\":\"toolu_1\",\"tool_input\":{\"command\":\"ls\"},\"tool_response\":{\"stdout\":\"x\"},\"duration_ms\":412,\"prompt_id\":\"p1\"}]}"),
    ("main thread has no agent_id; failure fields", lit "{\"payloads\":[{\"session_id\":\"s1\",\"hook_event_name\":\"PostToolUseFailure\",\"tool_name\":\"Edit\",\"tool_use_id\":\"toolu_2\",\"error\":\"denied\",\"is_interrupt\":false,\"duration_ms\":3}]}"),
    ("TeammateIdle and SubagentStart", lit "{\"payloads\":[{\"session_id\":\"s1\",\"hook_event_name\":\"TeammateIdle\",\"agent_id\":\"a2\",\"teammate_name\":\"eng-webkit\",\"team_name\":\"t\"},{\"session_id\":\"s1\",\"hook_event_name\":\"SubagentStart\",\"agent_id\":\"a3\",\"agent_type\":\"reviewer\"}]}"),
    ("bad payloads are reported by index, the rest decoded", lit "{\"payloads\":[{\"hook_event_name\":\"PostToolUse\"},{\"session_id\":\"s1\",\"hook_event_name\":\"PostToolUse\",\"duration_ms\":1.5},\"x\",{\"session_id\":\"s1\",\"hook_event_name\":\"Stop\"}]}"),
    ("missing payloads is refused", lit "{}"),
    ("identity: forked internal agent (empty agent_type) is unknown, never the lead", lit "{\"payloads\":[{\"session_id\":\"s1\",\"hook_event_name\":\"SubagentStop\",\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"\"},{\"session_id\":\"s1\",\"hook_event_name\":\"Stop\"}]}")]),
  ("ops.actor", [
    ("lead: no agent_id, no agent_type", lit "{}"),
    ("lead: null agent_id", lit "{\"agent_id\":null,\"agent_type\":null}"),
    ("lead: no agent_id, agent_type set (main session started with an agent)", lit "{\"agent_type\":\"lean-prover\"}"),
    ("lead: the caps.jsonl lead record", lit "{\"agent_id\":null,\"agent_type\":\"main\"}"),
    ("subagent role: owner", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"lean-prover\"}"),
    ("reviewer role", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"reviewer\"}"),
    ("review in the type, any ASCII case", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"Math-REVIEWER\"}"),
    ("near miss: revie is an owner", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"revie-w\"}"),
    ("agent typed main is an owner, never the lead", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"main\"}"),
    ("teammate: agent_type is its name (role unresolved, SPK-c open)", lit "{\"agent_id\":\"aeng-webkit-0123456789abcdef\",\"agent_type\":\"eng-webkit\"}"),
    ("forked internal agent: empty agent_type is unknown", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"\"}"),
    ("agent_id without agent_type is unknown", lit "{\"agent_id\":\"a0123456789abcdef\"}"),
    ("agent_id with null agent_type is unknown", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":null}"),
    ("empty agent_id is unknown", lit "{\"agent_id\":\"\",\"agent_type\":\"lean-prover\"}"),
    ("non-string agent_id is refused", lit "{\"agent_id\":7,\"agent_type\":\"lean-prover\"}"),
    ("non-string agent_type is refused", lit "{\"agent_id\":\"a1\",\"agent_type\":true}")]),
  ("ops.cap", [
    ("lead mints for pnpm fw status", lit "{\"tokens\":[\"pnpm\",\"fw\",\"status\"]}"),
    ("lead: agent_type ignored", lit "{\"agent_id\":null,\"agent_type\":\"main\",\"tokens\":[\"pnpm\",\"fw\",\"land\",\"b\",\"--task\",\"t\"]}"),
    ("agent mints as owner", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"lean-prover\",\"tokens\":[\"pnpm\",\"fw\",\"land\",\"b\"]}"),
    ("reviewer role mints as reviewer", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"Math-REVIEWER\",\"tokens\":[\"pnpm\",\"fw\",\"card\",\"review\"]}"),
    ("bare pnpm fw mints an empty argv", lit "{\"tokens\":[\"pnpm\",\"fw\"]}"),
    ("leading cd: notFwPrefix", lit "{\"tokens\":[\"cd\",\"apps/runner\"]}"),
    ("pnpm -s fw: notFwPrefix", lit "{\"tokens\":[\"pnpm\",\"-s\",\"fw\",\"land\",\"--dry\",\"b\"]}"),
    ("pnpm --filter x fw: notFwPrefix", lit "{\"tokens\":[\"pnpm\",\"--filter\",\"x\",\"fw\",\"status\"]}"),
    ("empty command: notFwPrefix", lit "{\"tokens\":[]}"),
    ("pnpm alone: notFwPrefix", lit "{\"tokens\":[\"pnpm\"]}"),
    ("a different program: notFwPrefix", lit "{\"tokens\":[\"echo\",\"pnpm\",\"fw\"]}"),
    ("2>&1 then a filter pipe mints for the bare command", lit "{\"tokens\":[\"pnpm\",\"fw\",\"land\",\"b\",{\"redir\":\"2>&1\"},{\"stop\":\"|\"},\"tail\",\"-5\"]}"),
    ("redirect to a file is dropped", lit "{\"tokens\":[\"pnpm\",\"fw\",\"status\",{\"redir\":\">out.txt\"}]}"),
    ("append redirect and 2>/dev/null are dropped", lit "{\"tokens\":[\"pnpm\",\"fw\",\"status\",{\"redir\":\">>log\"},{\"redir\":\"2>/dev/null\"}]}"),
    ("input redirect is dropped", lit "{\"tokens\":[\"pnpm\",\"fw\",\"send\",{\"redir\":\"<in\"}]}"),
    ("redirect between words is dropped", lit "{\"tokens\":[\"pnpm\",\"fw\",{\"redir\":\"2>&1\"},\"land\",\"b\"]}"),
    ("a pipe ends the command (grep filter)", lit "{\"tokens\":[\"pnpm\",\"fw\",\"land\",\"b\",{\"stop\":\"|\"},\"grep\",\"VERDICT\"]}"),
    ("&& ends the command", lit "{\"tokens\":[\"pnpm\",\"fw\",\"status\",{\"stop\":\"&&\"},\"echo\",\"done\"]}"),
    ("a lone number is an argument, not a redirect", lit "{\"tokens\":[\"pnpm\",\"fw\",\"land\",\"b\",\"2\"]}"),
    ("a pipe before pnpm fw: notFwPrefix", lit "{\"tokens\":[\"echo\",{\"stop\":\"|\"},\"pnpm\",\"fw\",\"status\"]}"),
    ("unknown actor stays refused through a pipe", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"\",\"tokens\":[\"pnpm\",\"fw\",\"land\",{\"redir\":\"2>&1\"},{\"stop\":\"|\"},\"tail\"]}"),
    ("forked agent: unknownActor", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"\",\"tokens\":[\"pnpm\",\"fw\",\"status\"]}"),
    ("agent_id without agent_type: unknownActor", lit "{\"agent_id\":\"a0123456789abcdef\",\"tokens\":[\"pnpm\",\"fw\",\"status\"]}"),
    ("empty agent_id: unknownActor", lit "{\"agent_id\":\"\",\"agent_type\":\"lean-prover\",\"tokens\":[\"pnpm\",\"fw\",\"status\"]}"),
    ("prefix wins over unknown actor", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"\",\"tokens\":[\"cd\",\"x\"]}"),
    ("non-string token is refused", lit "{\"tokens\":[\"pnpm\",7]}"),
    ("non-string agent_id is refused", lit "{\"agent_id\":7,\"tokens\":[\"pnpm\",\"fw\"]}")]),
  ("ops.door", [
    ("user (the web UI) passes without the secret", lit "{\"actor\":\"user\"}"),
    ("script, git and hook pass without the secret", lit "{\"actor\":\"script\"}"),
    ("git passes", lit "{\"actor\":\"git\"}"),
    ("hook passes", lit "{\"actor\":\"hook\"}"),
    ("lead is refused without the secret", lit "{\"actor\":\"lead\"}"),
    ("owner is refused without the secret", lit "{\"actor\":\"owner\"}"),
    ("reviewer is refused without the secret", lit "{\"actor\":\"reviewer\",\"secret\":false}"),
    ("lead passes with the secret", lit "{\"actor\":\"lead\",\"secret\":true}"),
    ("owner passes with the secret", lit "{\"actor\":\"owner\",\"secret\":true}"),
    ("unknown actor name is refused", lit "{\"actor\":\"root\"}"),
    ("missing actor is refused", lit "{}")]),
  ("ops.obs", [
    ("keys: tool_use_id joins; without it the timestamp; no agent_id is main", lit "{\"records\":[{\"agent_id\":\"a1\",\"hook_event_name\":\"PostToolUse\",\"tool_use_id\":\"toolu_1\",\"ts\":5},{\"agent_id\":null,\"hook_event_name\":\"Stop\",\"tool_use_id\":null,\"ts\":7},{\"hook_event_name\":\"Notification\",\"ts\":9}]}"),
    ("keys: an empty agent_id stays empty (only null or missing is main)", lit "{\"records\":[{\"agent_id\":\"\",\"hook_event_name\":\"X\",\"tool_use_id\":\"\",\"ts\":7}]}"),
    ("summary: calls, errors and summed duration per (agent type, tool), first-seen order", lit "{\"lines\":[{\"key\":\"k1\",\"hook_event_name\":\"PostToolUse\",\"agent_type\":\"b\",\"tool_name\":\"Bash\",\"is_error\":false,\"duration_ms\":100,\"ts\":1},{\"hook_event_name\":\"Stop\",\"agent_type\":\"b\"},{\"hook_event_name\":\"PostToolUse\"},{\"hook_event_name\":\"PostToolUseFailure\",\"agent_type\":\"b\",\"tool_name\":\"Bash\",\"is_error\":true,\"duration_ms\":50}]}"),
    ("summary: null fields count as main, ?, no error and 0 ms", lit "{\"lines\":[{\"hook_event_name\":\"PostToolUse\",\"agent_type\":null,\"tool_name\":null,\"is_error\":null,\"duration_ms\":null}]}"),
    ("empty request: no keys, no rows", lit "{}"),
    ("record without ts is refused", lit "{\"records\":[{\"hook_event_name\":\"Stop\"}]}"),
    ("fractional duration is refused", lit "{\"lines\":[{\"hook_event_name\":\"PostToolUse\",\"duration_ms\":1.5}]}"),
    ("admission (task-state-truth): only decision fields reject; soft fields become null with a note; unknown fields are named; every rejection, note and unknown field is an issue",
      lit "{\"raw\":[\"{\\\"agent_id\\\":\\\"a1\\\",\\\"agent_type\\\":\\\"\\\",\\\"hook_event_name\\\":\\\"SubagentStop\\\",\\\"tool_name\\\":null,\\\"tool_use_id\\\":null,\\\"duration_ms\\\":null,\\\"is_error\\\":null,\\\"verb\\\":null,\\\"ts\\\":5,\\\"background_tasks\\\":20}\",\"{\\\"agent_id\\\":\\\"a1\\\",\\\"agent_type\\\":7,\\\"hook_event_name\\\":\\\"PostToolUse\\\",\\\"tool_name\\\":\\\"Bash\\\",\\\"tool_use_id\\\":\\\"t1\\\",\\\"duration_ms\\\":-1,\\\"is_error\\\":false,\\\"ts\\\":6,\\\"future\\\":1}\",\"{\\\"agent_id\\\":\\\"\\\",\\\"hook_event_name\\\":\\\"Stop\\\",\\\"ts\\\":7}\",\"not json\"]}"),
    ("life (task-state-truth): start and stop by id only (a name is never a life key), any other event is a heartbeat of the id, a named spawn guard spawns and labels its obs key",
      lit "{\"life\":[{\"event\":\"SubagentStart\",\"agent_id\":\"a1\",\"key\":\"k1\",\"ts\":1},{\"event\":\"SubagentStop\",\"agent_id\":\"a1\",\"key\":\"k2\",\"ts\":2},{\"event\":\"SubagentStop\",\"agent_id\":\"a2\",\"key\":\"k3\",\"ts\":3},{\"event\":\"PostToolUse\",\"agent_id\":\"a1\",\"key\":\"k4\",\"ts\":1200000,\"epoch\":2},{\"event\":\"SpawnGuard\",\"agent_id\":\"lead\",\"agent_name\":\"fix-nav\",\"key\":\"k5\",\"ts\":9},{\"event\":\"Stop\",\"key\":\"k6\",\"ts\":9}]}"),
    ("life (alert-rules-fix): a heartbeat counts only while no stop was sent (epoch 0); after a stop (epoch > 0) only a start revives",
      lit "{\"life\":[{\"event\":\"PostToolUse\",\"agent_id\":\"a1\",\"key\":\"k1\",\"ts\":1200000,\"epoch\":0},{\"event\":\"PostToolUse\",\"agent_id\":\"a1\",\"key\":\"k2\",\"ts\":1200002,\"epoch\":1200000},{\"event\":\"SubagentStart\",\"agent_id\":\"a1\",\"key\":\"k3\",\"ts\":1300000,\"epoch\":1200000}]}"),
    ("life (alert-rules-fix, resume): stop, then a newer start, then a tool call heartbeats again; an older start resets nothing; the epochs are the drain's state after each record",
      lit "{\"life\":[{\"event\":\"SubagentStop\",\"agent_id\":\"a1\",\"key\":\"k1\",\"ts\":1200000,\"epoch\":0},{\"event\":\"SubagentStart\",\"agent_id\":\"a1\",\"key\":\"k2\",\"ts\":1100000,\"epoch\":1200000},{\"event\":\"SubagentStart\",\"agent_id\":\"a1\",\"key\":\"k3\",\"ts\":1300000,\"epoch\":1200000},{\"event\":\"PostToolUse\",\"agent_id\":\"a1\",\"key\":\"k4\",\"ts\":2200000,\"epoch\":0},{\"event\":\"PostToolUse\",\"agent_id\":\"a1\",\"key\":\"k5\",\"ts\":2200001,\"epoch\":1200000}]}"),
    ("resume (alert-rules-fix): a StructuredOutput call 2 ms after the stop is not a resume (spool of a workflow subagent, 2026-10-19)",
      lit "{\"resume\":[{\"hooks\":[{\"event\":\"SubagentStart\",\"ts\":0},{\"event\":\"PostToolUse\",\"ts\":1445654},{\"event\":\"SubagentStop\",\"ts\":1454982},{\"event\":\"PostToolUse\",\"ts\":1454984}]}]}"),
    ("resume (alert-rules-fix): the same shape, 86 s agent",
      lit "{\"resume\":[{\"hooks\":[{\"event\":\"SubagentStart\",\"ts\":0},{\"event\":\"PostToolUse\",\"ts\":72892},{\"event\":\"SubagentStop\",\"ts\":86059},{\"event\":\"PostToolUse\",\"ts\":86062}]}]}"),
    ("resume (alert-rules-fix): the same shape, 57 s agent",
      lit "{\"resume\":[{\"hooks\":[{\"event\":\"SubagentStart\",\"ts\":0},{\"event\":\"PostToolUse\",\"ts\":50570},{\"event\":\"SubagentStop\",\"ts\":56823},{\"event\":\"PostToolUse\",\"ts\":56829}]}]}"),
    ("resume (alert-rules-fix): a SubagentHandback call after a second stop is not a resume",
      lit "{\"resume\":[{\"hooks\":[{\"event\":\"SubagentStart\",\"ts\":0},{\"event\":\"PostToolUse\",\"ts\":3049},{\"event\":\"PostToolUse\",\"ts\":5748},{\"event\":\"SubagentStop\",\"ts\":12670},{\"event\":\"SubagentStop\",\"ts\":18446},{\"event\":\"PostToolUse\",\"ts\":18450}]}]}"),
    ("resume (alert-rules-fix): a SubagentStart after the stop resumes",
      lit "{\"resume\":[{\"hooks\":[{\"event\":\"SubagentStart\",\"ts\":0},{\"event\":\"PostToolUse\",\"ts\":3941},{\"event\":\"PostToolUse\",\"ts\":9378545},{\"event\":\"PostToolUse\",\"ts\":9382232},{\"event\":\"SubagentStop\",\"ts\":9382453},{\"event\":\"SubagentStart\",\"ts\":20229172},{\"event\":\"PostToolUse\",\"ts\":20238537}]}]}"),
    ("resume (alert-rules-fix): a start at the stop time is not after it",
      lit "{\"resume\":[{\"hooks\":[{\"event\":\"SubagentStart\",\"ts\":0},{\"event\":\"SubagentStop\",\"ts\":10},{\"event\":\"SubagentStart\",\"ts\":10}]}]}"),
    ("resume (alert-rules-fix): records out of order, the newest stop wins and a start between two stops is old",
      lit "{\"resume\":[{\"hooks\":[{\"event\":\"SubagentStop\",\"ts\":10},{\"event\":\"SubagentStart\",\"ts\":5},{\"event\":\"SubagentStop\",\"ts\":20}]}]}"),
    ("resume (alert-rules-fix): no stop, no stop time",
      lit "{\"resume\":[{\"hooks\":[{\"event\":\"SubagentStart\",\"ts\":0},{\"event\":\"PostToolUse\",\"ts\":3}]}]}"),
    ("resume (alert-rules-fix): an empty spool",
      lit "{\"resume\":[{\"hooks\":[]}]}"),
    ("labels (task-state-truth): a usable name labels the id; an empty name does not",
      lit "{\"labels\":[{\"id\":\"a1\",\"name\":\"fix-nav\"},{\"id\":\"a2\",\"name\":\"\"}]}"),
    ("spool alert (task-state-truth): issues with counts, none while a spool alert is open",
      lit "{\"fieldAlert\":{\"now\":5,\"open\":[],\"issues\":[{\"issue\":\"rejected:json\",\"count\":2},{\"issue\":\"lifeOf:error\",\"count\":1}]}}"),
    ("spool alert (task-state-truth): an open spool alert holds the next one",
      lit "{\"fieldAlert\":{\"now\":6,\"open\":[\"alert-spool-5\"],\"issues\":[{\"issue\":\"rejected:json\",\"count\":1}]}}"),
    ("spool alert (alert-rules-fix): only caught fwcore throws get the throw title, not the emit.mjs one",
      lit "{\"fieldAlert\":{\"now\":7,\"open\":[],\"issues\":[{\"issue\":\"sweep:lifeOf\",\"count\":3}]}}"),
    ("spool alert (alert-rules-fix): a throw and a rejected line together keep the spool title",
      lit "{\"fieldAlert\":{\"now\":8,\"open\":[],\"issues\":[{\"issue\":\"sweep:drain\",\"count\":1},{\"issue\":\"rejected:json\",\"count\":1}]}}"),
    ("spool alert (alert-steps-plain): an unknown field alone gets the plain unknown-field title, for the lead",
      lit "{\"fieldAlert\":{\"now\":9,\"open\":[],\"issues\":[{\"issue\":\"session_pid:unknown\",\"count\":1}]}}"),
    ("resolve (alert-steps-plain): the stale step posted before details existed closes, its field is known now",
      lit "{\"resolve\":{\"now\":1792500000000,\"window\":{\"lines\":0,\"issues\":[]},\"steps\":[{\"id\":\"alert-spool-1792389046068\",\"title\":\"Spool lines need a look: session_pid:unknown x1; fix emit.mjs or Fw.Ops.Obs.specs, then press Done\",\"body\":\"\",\"audience\":\"lead\"}]}}"),
    ("resolve (alert-steps-plain): a field the spec still does not know stays open",
      lit "{\"resolve\":{\"now\":5000,\"window\":{\"lines\":4,\"issues\":[]},\"steps\":[{\"id\":\"alert-spool-1\",\"title\":\"x\",\"body\":\"Details: no_such_field:unknown x1\",\"audience\":\"lead\"}]}}"),
    ("resolve (alert-steps-plain): a key still failing in the window keeps the step open",
      lit "{\"resolve\":{\"now\":5000,\"window\":{\"lines\":4,\"issues\":[\"rejected:json\"]},\"steps\":[{\"id\":\"alert-spool-1\",\"title\":\"x\",\"body\":\"Details: rejected:json x2\",\"audience\":\"lead\"}]}}"),
    ("resolve (alert-steps-plain): a quiet window with no line closes no rejection",
      lit "{\"resolve\":{\"now\":5000,\"window\":{\"lines\":0,\"issues\":[]},\"steps\":[{\"id\":\"alert-spool-1\",\"title\":\"x\",\"body\":\"Details: rejected:json x2\",\"audience\":\"lead\"}]}}"),
    ("resolve (alert-steps-plain): a clean window after a line closes the rejection step with a note",
      lit "{\"resolve\":{\"now\":5000,\"window\":{\"lines\":3,\"issues\":[]},\"steps\":[{\"id\":\"alert-spool-1\",\"title\":\"x\",\"body\":\"Details: rejected:json x2\",\"audience\":\"lead\"}]}}"),
    ("resolve (alert-steps-plain): a step for the user is never closed by the script",
      lit "{\"resolve\":{\"now\":5000,\"window\":{\"lines\":3,\"issues\":[]},\"steps\":[{\"id\":\"alert-spool-1\",\"title\":\"x\",\"body\":\"Details: rejected:json x2\",\"audience\":\"user\"}]}}"),
    ("resolve (alert-steps-plain): a cut details line names no key, so it never closes",
      lit "{\"resolve\":{\"now\":5000,\"window\":{\"lines\":3,\"issues\":[]},\"steps\":[{\"id\":\"alert-spool-1\",\"title\":\"x\",\"body\":\"Details: rejected:json x2, a:unknown x1…\",\"audience\":\"lead\"}]}}")]),
  ("ops.wait", [
    ("fw watch with a trailing &: deny bgLong fwWatch", wait "pnpm fw watch --until-alert &"),
    ("fw watch in the foreground: allow", wait "pnpm fw watch --until-alert"),
    ("fw watch behind && and &: the whole list is backgrounded: deny", wait "cd x && node apps/runner/fw.mjs watch &"),
    ("test run sent to the background with a log: allow (not long-running)", wait "pnpm test > log.txt 2>&1 &"),
    ("2>&1 and &> are redirects, not background: allow", wait "pnpm vitest run 2>&1 | tail -5; cmd &> out.log"),
    ("& inside quotes is text: allow", wait "echo 'pnpm fw watch &' \"a & b\""),
    ("until loop with &: deny bgLong loop", wait "until grep -q done out.txt; do sleep 5; done &"),
    ("until loop in the foreground with no bound: deny unboundedLoop", wait "until grep -q done out.txt; do sleep 5; done"),
    ("while loop in the foreground with no bound: deny unboundedLoop", wait "while true; do sleep 60; done"),
    ("until loop with a counter test: allow", wait "i=0; until [ $i -gt 5 ]; do sleep 5; i=$((i+1)); done"),
    ("until loop with a clock deadline: allow", wait "until [ $SECONDS -ge 60 ]; do sleep 2; done"),
    ("timeout before until runs a command named until, no loop is parsed: allow", wait "timeout 60 until grep -q x f; do sleep 1; done"),
    ("loop inside timeout N bash -c: bounded by timeout: allow", wait "timeout 600 bash -c 'until gh run view 1 --exit-status; do sleep 30; done'"),
    ("for loop backgrounded around fw watch: deny bgLong fwWatch", wait "for f in a b; do pnpm fw watch; done &"),
    ("long sleep with &: deny bgLong longSleep", wait "sleep 600 &"),
    ("sleep with a minute suffix behind &&: deny", wait "sleep 2m && echo hi &"),
    ("short sleep with &: allow", wait "sleep 5 &"),
    ("sleep over the cap set by caps: deny", wait' "sleep 10 &" "{\"maxSleepSec\":5}"),
    ("dev server with &: deny bgLong server", wait "pnpm dev &"),
    ("node server script with &: deny bgLong server", wait "node apps/console-api/server.mjs & sleep 1; curl localhost"),
    ("tail -f with &: deny bgLong tail", wait "tail -f x.log &"),
    ("only the unit before & counts: a later foreground fw watch is allowed", wait "echo hi & pnpm fw watch"),
    ("newline continues an and-or list: the backgrounded list is long: deny", wait "a &&\n pnpm dev &"),
    ("comment is ignored: allow", wait "echo hi # pnpm fw watch &"),
    ("empty command: allow", wait ""),
    ("while-read loop over a file redirect: bounded by its input: allow", wait "while IFS= read -r line; do echo \"$line\"; done < list.txt"),
    ("while-read loop fed by a finite pipe: allow", wait "git ls-files | while read -r f; do wc -l \"$f\"; done | sort"),
    ("while-read loop over a here-string: allow", wait "while read -r a b; do echo $a; done <<< \"$pairs\""),
    ("here-document body is data, not commands: allow", wait "cat > f.py <<'EOF'\nwhile True:\n    pass\nEOF\npython3 f.py"),
    ("<<- here-document with a tab-indented delimiter: allow", wait "cat <<-EOF > x.sh\n\twhile true; do sleep 1; done\n\tEOF\necho ok"),
    ("nested read loops, both over finite input: allow", wait "find . -type f | while read f; do while read l; do echo $l; done < \"$f\"; done"),
    ("while-read loop on the tool's stdin: deny unboundedLoop", wait "while read l; do echo $l; done"),
    ("while-read loop fed by tail -f: deny unboundedLoop", wait "tail -f x.log | while read l; do echo $l; done"),
    ("while-read loop over a process substitution: deny unboundedLoop", wait "while read l; do echo $l; done < <(tail -f x.log)"),
    ("read with its own redirect re-reads line 1 forever: deny unboundedLoop", wait "while read l < f; do echo $l; done"),
    ("loop after do is still seen: deny unboundedLoop", wait "for f in a b; do while true; do sleep 1; done; done"),
    ("loop after a closed here-document is code again: deny unboundedLoop", wait "cat <<EOF > f\nx\nEOF\nwhile true; do sleep 1; done"),
    ("CI poll with no counter: deny unboundedLoop", wait "until [ \"$(gh run view 1 --json status -q .status)\" = completed ]; do sleep 150; done"),
    ("finite read loop with &: still a backgrounded loop: deny bgLong loop", wait "ls | while read f; do echo $f; done &"),
    ("read condition extended by || true never fails: deny unboundedLoop", wait "while read l || true; do sleep 1; done < f"),
    ("read condition extended by || : never fails: deny unboundedLoop", wait "while read l || :; do sleep 1; done < f"),
    ("read condition followed by another command before do: deny unboundedLoop", wait "while read l; [ 1 ]; do sleep 1; done < f"),
    ("read loop over a process substitution of an allowlisted producer: allow", wait "while read -r f; do echo $f; done < <(git diff --name-only main)"),
    ("read loop over a process substitution of ping: deny unboundedLoop", wait "while read l; do echo $l; done < <(ping x)"),
    ("producer outside the allowlist (ping): deny unboundedLoop", wait "ping x | while read l; do echo $l; done"),
    ("tail -fn is a follow: deny unboundedLoop", wait "tail -fn 10 log | while read l; do echo $l; done"),
    ("tail --follow=name is a follow: deny unboundedLoop", wait "tail --follow=name log | while read l; do echo $l; done"),
    ("cat of a device: deny unboundedLoop", wait "cat /dev/urandom | while read l; do echo $l; done"),
    ("cat - reads stdin: deny unboundedLoop", wait "cat - | while read l; do echo $l; done"),
    ("cat -u: deny unboundedLoop", wait "cat -u f | while read l; do echo $l; done"),
    ("log stream never ends: deny unboundedLoop", wait "log stream | while read l; do echo $l; done"),
    ("sleep infinity: deny unboundedLoop", wait "sleep infinity | while read l; do echo $l; done"),
    ("a filter after an endless producer: deny unboundedLoop", wait "tail -f log | grep x | while read l; do echo $l; done"),
    ("an allowlisted filter after a finite producer: allow", wait "git ls-files | grep lean | while read -r f; do wc -l \"$f\"; done"),
    ("a done redirect overrides the pipe: deny unboundedLoop", wait "ls | while read l; do echo $l; done < /dev/zero"),
    ("double-quoted <<EOF is text, the loop after it is code: deny unboundedLoop", wait "echo \"<<EOF\"\nuntil false; do sleep 5; done"),
    ("single-quoted <<EOF is text, the loop after it is code: deny unboundedLoop", wait "echo '<<EOF'\nuntil false; do sleep 5; done"),
    ("server smoke test with & and kill: deny bgLong server", wait "node server.mjs & pid=$!; sleep 1; curl -s localhost:3000; kill $pid"),
    ("r3: arithmetic in the body does not bound an endless read loop: deny", wait "tail -f log | while read l; do echo $((n+1)); done"),
    ("r3: date in the body does not bound a read loop over yes: deny", wait "yes | while read l; do echo; date; done"),
    ("r3: date in the body does not bound while true: deny", wait "while true; do date; sleep 1; done"),
    ("r3: date in the body does not bound a CI poll: deny", wait "until gh run view 1 --exit-status; do date; sleep 120; done"),
    ("r3: the word deadline is not a bound: deny", wait "until false; do sleep 1; echo deadline; done"),
    ("r3: $SECONDS not compared to a limit is not a bound: deny", wait "while [ \"$SECONDS\" ]; do sleep 1; done"),
    ("r3: a constant comparison is not a bound: deny", wait "while [ 1 -lt 2 ]; do sleep 1; done"),
    ("r3: a break in the body is not a bound: deny", wait "i=0; while :; do [ $i -lt 5 ] || break; i=$((i+1)); done"),
    ("r3: a counter test cannot clear a read of an endless input: deny", wait "i=0; tail -f log | while read l && [ $i -lt 9 ]; do i=$((i+1)); done"),
    ("r3: while with test || true never fails: deny", wait "i=0; while [ $i -lt 9 ] || true; do sleep 1; done"),
    ("r3: counter and an until-loop test in the condition: allow", wait "i=0; until gh run view 1 --exit-status || [ $i -ge 10 ]; do sleep 30; i=$((i+1)); done"),
    ("r3: file test and counter joined by &&: allow", wait "i=0; while [ ! -s \"$F\" ] && [ $i -lt 55 ]; do sleep 10; i=$((i+1)); done"),
    ("r3: arithmetic counter test: allow", wait "i=0; while (( i < 10 )); do i=$((i+1)); done"),
    ("r3: sed and awk filters after a finite producer: allow", wait "git log --oneline | sed 's/a/b/' | awk '{print $1}' | while read h; do echo $h; done"),
    ("r3: awk with a loop is not a finite filter: deny", wait "git log | awk '{while(1)print}' | while read h; do echo $h; done"),
    ("r3: xargs running echo over a finite input: allow", wait "ls | xargs -n 1 echo | while read l; do echo $l; done"),
    ("r3: gh pr list as a producer: allow", wait "gh pr list --json number -q '.[].number' | while read n; do gh pr view $n; done"),
    ("r3: read -d $'\\0' over find -print0: allow", wait "find . -name '*.json' -print0 | while IFS= read -r -d $'\\0' f; do echo \"$f\"; done"),
    ("r3: a repo node script is a finite producer: allow", wait "node scripts/list.mjs | while read l; do echo $l; done"),
    ("r3: pnpm is not a known finite producer: deny", wait "pnpm -s fw list | while read l; do echo $l; done"),
    ("r3: //dev/zero is a device: deny", wait "while read l; do echo $l; done < //dev/zero"),
    ("r3: ./../../dev/zero is a device: deny", wait "cat ./../../dev/zero | while read l; do echo $l; done"),
    ("r3: here-string running yes: deny", wait "while read l; do echo $l; done <<< \"$(yes)\""),
    ("r3: here-string running a finite producer: allow", wait "while read -r f; do echo $f; done <<< \"$(git diff --name-only)\""),
    ("r3: git reflog piped into a read loop: allow", wait "git reflog show main | head -12 | while read h rest; do echo $h; done"),
    ("r4: gh poll by command substitution compared with a number: deny", wait "until [ \"$(gh run list -b ci/x --json status -q length)\" -ge 1 ]; do sleep 120; done"),
    ("r4: ls count by command substitution: deny", wait "until [ \"$(ls out/*.json 2>/dev/null | wc -l)\" -gt 0 ]; do sleep 30; done"),
    ("r4: pgrep count by command substitution: deny", wait "while [ \"$(pgrep -c node)\" -gt 0 ]; do sleep 5; done"),
    ("r4: backquote substitution: deny", wait "while [ `echo 0` -lt 1 ]; do sleep 1; done"),
    ("r4: $$ is not a counter: deny", wait "while [ $$ -gt 0 ]; do sleep 1; done"),
    ("r4: $# is not a counter: deny", wait "while [ $# -ge 0 ]; do sleep 1; done"),
    ("r4: $RANDOM is not a counter: deny", wait "while [ $RANDOM -ge 0 ]; do sleep 1; done"),
    ("r4: ${x:-0} default expansion: deny", wait "while [ \"${x:-0}\" -lt 1 ]; do sleep 1; done"),
    ("r4: $((0)) arithmetic expansion: deny", wait "while [ $((0)) -lt 1 ]; do sleep 1; done"),
    ("r4: limit held in a variable ($end) is not a literal: deny", wait "end=$((SECONDS+60)); until [ $SECONDS -ge $end ]; do sleep 2; done"),
    ("r4: while with SECONDS growing away from the exit: deny", wait "while [ $SECONDS -ge 0 ]; do sleep 1; done"),
    ("r4: until with SECONDS growing away from the exit: deny", wait "until [ $SECONDS -lt 0 ]; do sleep 1; done"),
    ("r4: (( SECONDS >= 0 )) in a while: deny", wait "while (( SECONDS >= 0 )); do sleep 1; done"),
    ("r4: negated test is outside the grammar: deny", wait "while ! [ $SECONDS -lt 60 ]; do sleep 1; done"),
    ("r4: comma in (( )): deny", wait "i=0; while (( i < 10 , 1 )); do sleep 1; done"),
    ("r4: ternary in (( )): deny", wait "i=0; while (( i < 10 ? 1 : 1 )); do sleep 1; done"),
    ("r4: hex literal in (( )): deny", wait "while (( 0x0 < 1 )); do sleep 1; done"),
    ("r4: octal literal in (( )): deny", wait "while (( 010 < i )); do sleep 1; done"),
    ("r4: RANDOM in (( )): deny", wait "while (( RANDOM >= 0 )); do sleep 1; done"),
    ("r4: string order < in [[ ]]: deny", wait "i=0; while [[ $i < 10 ]]; do i=$((i+1)); done"),
    ("r4: read -n 0 reads nothing and never hits EOF: deny", wait "while read -n 0 x; do :; done < f.txt"),
    ("r4: read -t 0 only polls: deny", wait "while read -t 0; do :; done < f.txt"),
    ("r4: backslash-newline joins a keyword: deny", wait "whi\\\nle true; do sleep 1; done"),
    ("r4: while with SECONDS below a literal: allow", wait "while [ $SECONDS -lt 600 ]; do sleep 5; done"),
    ("r4: until with quoted SECONDS at a literal or a poll: allow", wait "until [ \"$SECONDS\" -ge 600 ] || gh run view 1 --exit-status; do sleep 30; done"),
    ("r4: until (( SECONDS > N )): allow", wait "until (( SECONDS > 600 )); do sleep 5; done"),
    ("r4: [[ ${i} -le 3 ]]: allow", wait "i=0; while [[ ${i} -le 3 ]]; do i=$((i+1)); done"),
    ("r4: producer with 2>/dev/null: allow", wait "ls -t a*.jsonl 2>/dev/null | head -3 | while read f; do echo $f; done"),
    ("r4: git worktree list piped into a read loop: allow", wait "git worktree list --porcelain | awk '/^worktree /{print $2}' | while read p; do echo $p; done"),
    ("r5: EPOCHSECONDS may be unset in zsh, never a bound: deny", wait "until [ $EPOCHSECONDS -ge 1760800000 ]; do sleep 1; done"),
    ("r5: a 23-digit literal is not a number: deny", wait "i=0; while [ $i -lt 12345678901234567890123 ]; do i=$((i+1)); done"),
    ("r5: $_ is reset by every command: deny", wait "while [ $_ -lt 10 ]; do sleep 1; done"),
    ("r6: BASH_MONOSECONDS in [ ] (unset in zsh and bash < 5.3): deny", wait "until [ $BASH_MONOSECONDS -ge 1 ]; do sleep 0.2; done"),
    ("r6: BASH_MONOSECONDS in (( )): deny", wait "until (( BASH_MONOSECONDS >= 1 )); do sleep 0.2; done"),
    ("r6: PIPESTATUS is reset by the shell: deny", wait "until [ $PIPESTATUS -ge 3 ]; do PIPESTATUS=$((PIPESTATUS+1)); done"),
    ("r6: GROUPS is fixed by the shell: deny", wait "until [ $GROUPS -ge 999999 ]; do GROUPS=$((GROUPS+1)); done"),
    ("r6: BASH_LINENO is set by the shell: deny", wait "until [ $BASH_LINENO -ge 3 ]; do BASH_LINENO=$((BASH_LINENO+1)); done"),
    ("r6: BASH_ARGV is set by the shell: deny", wait "until [ $BASH_ARGV -ge 3 ]; do BASH_ARGV=$((BASH_ARGV+1)); done"),
    ("r6: zsh status is reset by every command: deny", wait "while [ $status -lt 3 ]; do sleep 0.1; done"),
    ("r6: zsh status even when assigned first: deny", wait "status=0; while [ $status -lt 3 ]; do sleep 0.1; done"),
    ("r6: zsh TTYIDLE: deny", wait "while [ $TTYIDLE -lt 3 ]; do sleep 0.1; done"),
    ("r6: SECONDS against an epoch literal: deny", wait "while [ $SECONDS -lt 1792312012 ]; do sleep 1; done"),
    ("r6: an uppercase counter, even assigned: deny", wait "N=0; while [ $N -lt 5 ]; do N=$((N+1)); done"),
    ("r6: a counter never set by the command: deny", wait "while [ $i -lt 5 ]; do i=$((i+1)); done"),
    ("r6: a counter set only after && (may not run): deny", wait "true && i=0; until [ $i -ge 5 ]; do i=$((i+1)); done"),
    ("r6: lowercase counter set to a literal first: allow", wait "i=0; while [ $i -lt 5 ]; do echo $i; i=$((i+1)); done"),
    ("r6: SECONDS at the one-day cap: allow", wait "while [ $SECONDS -lt 86400 ]; do sleep 5; done"),
    ("missing cmd is refused", lit "{}")]),
  ("ops.watchDiff", [
    ("first check opens every alert, one line per key (first detail)", lit "{\"now\":[{\"code\":\"proc.long\",\"subject\":\"node#7\",\"detail\":\"31m\"},{\"code\":\"proc.long\",\"subject\":\"node#7\",\"detail\":\"32m\"},{\"code\":\"ci.slow\",\"subject\":\"run-1\"}]}"),
    ("open alerts stay quiet, a gone one closes, a new one opens", lit "{\"prev\":[{\"code\":\"proc.long\",\"subject\":\"node#7\"},{\"code\":\"ci.slow\",\"subject\":\"run-1\"}],\"now\":[{\"code\":\"ci.slow\",\"subject\":\"run-1\",\"detail\":\"x\"},{\"code\":\"agent.gone\",\"subject\":\"a1\",\"detail\":\"y\"}]}"),
    ("same code, other subject is another key", lit "{\"prev\":[{\"code\":\"proc.long\",\"subject\":\"node#7\"}],\"now\":[{\"code\":\"proc.long\",\"subject\":\"node#8\",\"detail\":\"\"}]}"),
    ("no alerts closes all, a repeated open key closes once", lit "{\"prev\":[{\"code\":\"a\",\"subject\":\"1\"},{\"code\":\"a\",\"subject\":\"1\"}],\"now\":[]}"),
    ("missing now is refused", lit "{\"prev\":[]}")]),
  ("ops.watchKeep", [
    ("same pid and start: live and kept", lit "{\"entries\":[{\"pid\":7,\"start\":1792300000}],\"rows\":[{\"pid\":7,\"start\":1792300000,\"args\":\"caffeinate -i\"}]}"),
    ("reused pid (other start): dropped, not kept", lit "{\"entries\":[{\"pid\":7,\"start\":1792300000}],\"rows\":[{\"pid\":7,\"start\":1792300001,\"args\":\"python\"}]}"),
    ("gone process: dropped", lit "{\"entries\":[{\"pid\":7,\"start\":1792300000},{\"pid\":8,\"start\":5}],\"rows\":[{\"pid\":8,\"start\":5,\"args\":\"x\"}]}"),
    ("the lead Monitor stream is kept without a declaration; other intervals are not", lit "{\"rows\":[{\"pid\":9,\"start\":1,\"args\":\"node apps/runner/src/fw.ts watch --interval 300 --stream\"},{\"pid\":10,\"start\":1,\"args\":\"node apps/runner/src/fw.ts watch --interval 60 --stream\"}]}"),
    ("a non-integer start is refused", lit "{\"entries\":[{\"pid\":7,\"start\":1.5}]}")])]

def lintFile (path : String) (bytes : Nat) (lines : List String) : Json :=
  Json.mkObj [("path", .str path), ("bytes", toJson bytes), ("lines", .arr (lines.toArray.map .str))]

def lintFiles (fs : List Json) : Json := Json.mkObj [("files", .arr fs.toArray)]

def numbered (n : Nat) : List String := (List.range n).map fun k => s!"line {k}"

def lintCases : List (String × Json) := [
  ("handoff: 30 lines is ok, 31 is over the line budget",
    lintFiles [lintFile "docs/team/handoffs/a.md" 300 (numbered 30), lintFile "docs/team/handoffs/b.md" 310 (numbered 31)]),
  ("CLAUDE.md: over 5600 bytes is over budget even with slop; at 5600 a dated note is slop",
    lintFiles [lintFile "CLAUDE.md" 5601 ["Rule (user decision 2026-10-17)."],
      lintFile "CLAUDE.md" 5600 ["Rule (user decision 2026-10-17)."]]),
  ("agent: a SHA in the body is slop; the description budget is 300 bytes",
    lintFiles [lintFile ".claude/agents/a.md" 200 ["---", "name: a", "description: short", "---", "Read src at 5b3d632."],
      lintFile ".claude/agents/b.md" 400 ["---", "name: b", "description: " ++ "".pushn 'x' 301, "---", "Body."]]),
  ("team doc: a heading named after a task is slop; a plain heading is ok",
    lintFiles [lintFile "docs/team/tools/land.md" 100 ["# land", "## Output (task land-dry)"],
      lintFile "docs/team/tools/x.md" 100 ["# x", "## Output (JSON)"]]),
  ("skill: an AI tell (em dash, inflated word, filler) is slop, the first hit's line is reported",
    lintFiles [lintFile ".claude/skills/s/SKILL.md" 100 ["---", "description: d", "---", "Plain line.", "We leverage — it."]]),
  ("handoffs and other files get no SHA or date check; other files have no budget",
    lintFiles [lintFile "docs/team/handoffs/c.md" 50 ["state: 5b3d632 on 2026-10-17"],
      lintFile "research/notes/n.md" 999999 ["delve"]]),
  ("no files: zero counts", lintFiles []),
  ("files missing: refused", Json.mkObj []),
  ("a file without lines: refused",
    Json.mkObj [("files", .arr #[Json.mkObj [("path", .str "CLAUDE.md"), ("bytes", toJson 1)]])])]

def extra (_ : Unit := ()) : List (String × String × List (String × Json)) := [
  ("lint", "lint.context", lintCases),
  ("plan", "plan.trailers", [
    ("oldest trailer marks done; later ones are duplicates; done and unknown ids are reported", lit "{\"commits\":[{\"sha\":\"s3\",\"body\":\"merge x\\n\\nTask: a\\nTask: c\"},{\"sha\":\"s2\",\"body\":\"Task: b\"},{\"sha\":\"s1\",\"body\":\"subject\\n\\nTask: a\"}],\"tasks\":[{\"id\":\"a\",\"state\":\"claimed\"},{\"id\":\"b\",\"state\":\"done\"}]}"),
    ("trailer syntax: line start, blanks around the id, id chars only, CRLF ok", lit "{\"commits\":[{\"sha\":\"s1\",\"body\":\"Task:  t-1.x_2 \\r\\nTask: t 2\\n task: t3\\nTask:\\nxTask: t4\\nTask:t5\"}],\"tasks\":[{\"id\":\"t-1.x_2\",\"state\":\"open\"},{\"id\":\"t5\",\"state\":\"open\"}]}"),
    ("two trailers of one task in one commit: the first is done, the second a duplicate", lit "{\"commits\":[{\"sha\":\"s1\",\"body\":\"Task: a\\nTask: a\"}],\"tasks\":[{\"id\":\"a\",\"state\":\"open\"}]}"),
    ("no commits", lit "{\"commits\":[],\"tasks\":[{\"id\":\"a\",\"state\":\"open\"}]}"),
    ("missing tasks is refused", lit "{\"commits\":[]}")]),
  ("console", "console.landReadiness", [
    ("new card needs everything (device too)", lit "{\"card\":{\"id\":\"c\",\"needsDevice\":true},\"sha\":\"h\"}"),
    ("ready at head", lit "{\"card\":{\"id\":\"c\",\"owner\":\"o\",\"needsDevice\":false,\"approved\":true,\"head\":\"h\",\"screenAt\":\"h\",\"reviewAt\":\"h\"},\"sha\":\"h\"}"),
    ("ready, but the request names an older sha", lit "{\"card\":{\"id\":\"c\",\"needsDevice\":false,\"approved\":true,\"head\":\"h\",\"screenAt\":\"h\",\"reviewAt\":\"h\"},\"sha\":\"g\"}"),
    ("review at an old head; device missing", lit "{\"card\":{\"id\":\"c\",\"needsDevice\":true,\"approved\":true,\"head\":\"h\",\"screenAt\":\"h\",\"reviewAt\":\"g\",\"deviceAt\":null},\"sha\":\"h\"}"),
    ("landed card", lit "{\"card\":{\"id\":\"c\",\"needsDevice\":false,\"approved\":true,\"head\":\"h\",\"screenAt\":\"h\",\"reviewAt\":\"h\",\"landed\":true},\"sha\":\"h\"}"),
    ("missing needsDevice is refused", lit "{\"card\":{\"id\":\"c\"},\"sha\":\"h\"}")]),
  ("console", "console.alert", [
    ("permission prompt of an agent: names agent, kind and tool", lit "{\"event\":{\"hook_event_name\":\"Notification\",\"agent_id\":\"a1\",\"agent_type\":\"builder\",\"tool_name\":\"Bash\",\"notification_type\":\"permission_prompt\",\"ts\":10}}"),
    ("needs input", lit "{\"event\":{\"hook_event_name\":\"Notification\",\"agent_id\":\"a1\",\"agent_type\":\"builder\",\"notification_type\":\"agent_needs_input\",\"ts\":10}}"),
    ("the lead's own Notification is no alert", lit "{\"event\":{\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"tool_name\":\"Bash\",\"ts\":10}}"),
    ("no agent_id: attributed to the single agent with a tool in flight", lit "{\"event\":{\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"tool_name\":\"Bash\",\"ts\":10},\"flights\":[{\"agent_id\":\"a1\",\"agent_type\":\"builder\",\"tool_name\":\"Bash\"},{\"tool_name\":\"Agent\"}]}"),
    ("no agent_id, two agents in flight: not attributable", lit "{\"event\":{\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"ts\":10},\"flights\":[{\"agent_id\":\"a1\"},{\"agent_id\":\"a2\"}]}"),
    ("no agent_id, the lead has a tool of its own in flight: its prompt", lit "{\"event\":{\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"ts\":10},\"flights\":[{\"agent_id\":\"a1\"},{\"tool_name\":\"Bash\"}]}"),
    ("an agent with an open alert gets no second one", lit "{\"event\":{\"hook_event_name\":\"Notification\",\"agent_id\":\"a1\",\"agent_type\":\"builder\",\"ts\":12},\"open\":[\"alert-a1-10\"]}"),
    ("idle prompt is no alert", lit "{\"event\":{\"hook_event_name\":\"Notification\",\"agent_id\":\"a1\",\"notification_type\":\"idle_prompt\",\"ts\":10}}"),
    ("StopFailure of the lead session is the owner's (alert-steps-plain)", lit "{\"event\":{\"hook_event_name\":\"StopFailure\",\"ts\":4}}"),
    ("needs input is the owner's (alert-steps-plain)", lit "{\"event\":{\"hook_event_name\":\"Notification\",\"agent_id\":\"a1\",\"agent_type\":\"builder\",\"notification_type\":\"agent_needs_input\",\"ts\":10}}"),
    ("StopFailure of an agent", lit "{\"event\":{\"hook_event_name\":\"StopFailure\",\"agent_id\":\"a1\",\"agent_type\":\"builder\",\"ts\":4}}"),
    ("the agent's next tool result closes its earlier alerts only", lit "{\"event\":{\"hook_event_name\":\"PostToolUse\",\"agent_id\":\"a1\",\"tool_name\":\"Bash\",\"ts\":11},\"open\":[\"alert-a1-10\",\"alert-a2-10\",\"alert-a1-11\",\"alert-0123456789ab\"]}"),
    ("the lead's next tool result closes the lead's alert", lit "{\"event\":{\"hook_event_name\":\"PostToolUse\",\"ts\":11},\"open\":[\"alert-main-10\"]}"),
    ("SubagentStop closes", lit "{\"event\":{\"hook_event_name\":\"SubagentStop\",\"agent_id\":\"a1\",\"ts\":12},\"open\":[\"alert-a1-10\"]}"),
    ("missing ts is refused", lit "{\"event\":{\"hook_event_name\":\"Stop\"}}")]),
  ("console", "console.landScope", [
    ("writes, own handoff, generated and registration files land", lit "{\"writes\":[\"apps/runner/src/land.ts\",\"apps/runner/test/land*.ts\"],\"names\":[\"pa-land\"],\"paths\":[\"apps/runner/src/land.ts\",\"apps/runner/test/land-x.ts\",\"docs/team/handoffs/pa-land.md\",\"packages/contracts/golden/ops/a.jsonl\",\"lean/Fw.lean\"]}"),
    ("a file outside every glob is refused", lit "{\"writes\":[\"apps/runner/src/land.ts\"],\"names\":[\"pa-land\"],\"paths\":[\"apps/runner/src/land.ts\",\"apps/site/x.tsx\",\"docs/team/handoffs/other.md\"]}"),
    ("no writes and no allow: refused with the reason", lit "{\"writes\":[],\"names\":[\"t\"],\"paths\":[\"a.md\"]}"),
    ("--allow admits its glob only", lit "{\"writes\":[],\"allow\":[\"notes/**\"],\"paths\":[\"notes/a.md\",\"x.md\"]}"),
    ("protected paths are refused even under **", lit "{\"writes\":[\"**\"],\"paths\":[\".git/config\",\".fw-console/events.jsonl\",\".claude/settings.json\",\"lean/.lake/x\",\"a.md\"]}"),
    ("names with a slash or star make no handoff glob", lit "{\"writes\":[\"a/**\"],\"names\":[\"../x\",\"b/*\"],\"paths\":[\"docs/team/handoffs/../x.md\",\"docs/team/handoffs/b/c.md\"]}"),
    ("missing paths is refused", lit "{\"writes\":[]}"),
    ("a port task lands its registration files (registry, App, shells, Gate/Scope, Parts/Golden, anchors, its Lean part)", lit "{\"writes\":[\"apps/site/src/parts/platform/**\"],\"names\":[\"port-platform\"],\"task\":\"port-platform\",\"stream\":\"parts\",\"paths\":[\"apps/site/src/registry/index.ts\",\"apps/site/src/App.tsx\",\"apps/site/scripts/gen-shells.mjs\",\"lean/Fw/Gate/Scope.lean\",\"lean/Fw/Parts/Golden.lean\",\"lean/Fw/Parts/PlatformSweep.lean\",\"packages/gate-breakpoints/src/anchors.json\",\"packages/gate-breakpoints/src/scope.gen.json\",\"apps/site/src/parts/platform/x.tsx\"]}"),
    ("a port task does not land another part's Lean module", lit "{\"writes\":[\"apps/site/src/parts/platform/**\"],\"task\":\"port-platform\",\"stream\":\"parts\",\"paths\":[\"lean/Fw/Parts/HeroExit.lean\"]}"),
    ("the same registration files are refused for a task of no known kind", lit "{\"writes\":[\"apps/site/src/parts/platform/**\"],\"task\":\"land-hardening\",\"stream\":\"console\",\"paths\":[\"apps/site/src/App.tsx\"]}"),
    ("a measurement task lands its package and baselines", lit "{\"writes\":[\"research/notes/x.md\"],\"task\":\"zone-baselines-webkit\",\"stream\":\"measure\",\"paths\":[\"packages/measure-webkit/src/a.ts\",\"packages/measure-webkit/test/a.test.ts\",\"results/baselines/webkit/a.json\"]}"),
    ("baselines are refused for a task outside the measure stream", lit "{\"writes\":[\"research/notes/x.md\"],\"task\":\"t\",\"stream\":\"console\",\"paths\":[\"results/baselines/a.json\"]}"),
    ("a proof task lands its Lean part files and engine golden", lit "{\"writes\":[\"lean/Fw/Parts/HiddenPause.lean\"],\"task\":\"proof-hidden-pause\",\"stream\":\"lean\",\"paths\":[\"lean/Fw/Parts/HiddenPause.lean\",\"lean/Fw/Parts/HiddenPauseOpt.lean\",\"packages/contracts/golden/engine/hidden-pause.jsonl\"]}"),
    ("protected paths stay refused for a port task even with --allow **", lit "{\"writes\":[\"a/**\"],\"allow\":[\"**\"],\"task\":\"port-x\",\"stream\":\"parts\",\"paths\":[\".git/config\",\"lean/.lake/x\",\".claude/settings.json\",\".fw-console/events.jsonl\"]}")]),
  ("console", "console.landLock", [
    ("no lock file: free", lit "{\"held\":false}"),
    ("a live pid holds it: busy", lit "{\"held\":true,\"alive\":true}"),
    ("a dead pid holds it: stale, reported", lit "{\"held\":true,\"alive\":false}"),
    ("missing held is refused", lit "{}")]),
  ("console", "console.landGuard", [
    ("no lock: any commit is allowed", lit "{\"held\":false}"),
    ("lock held by a live land: another commit is refused", lit "{\"held\":true,\"alive\":true,\"here\":true,\"own\":false}"),
    ("the land's own commit goes through", lit "{\"held\":true,\"alive\":true,\"here\":true,\"own\":true}"),
    ("a commit in another checkout is allowed", lit "{\"held\":true,\"alive\":true,\"here\":false,\"own\":false}"),
    ("dead pid: stale, refused and reported", lit "{\"held\":true,\"alive\":false,\"here\":true,\"own\":false}"),
    ("missing held is refused", lit "{}")]),
  ("console", "console.landCommit", [
    ("locked, merge open, head unchanged: commit", lit "{\"locked\":true,\"mergeHead\":\"b1\",\"head\":\"m0\",\"pre\":\"m0\"}"),
    ("no lock", lit "{\"locked\":false,\"mergeHead\":\"b1\",\"head\":\"m0\",\"pre\":\"m0\"}"),
    ("MERGE_HEAD gone: refuse, do not reset", lit "{\"locked\":true,\"mergeHead\":null,\"head\":\"m0\",\"pre\":\"m0\"}"),
    ("HEAD moved by another commit: refuse", lit "{\"locked\":true,\"mergeHead\":\"b1\",\"head\":\"x9\",\"pre\":\"m0\"}"),
    ("missing pre is refused", lit "{\"locked\":true,\"head\":\"m0\"}")]),
  ("console", "console.landPick", [
    ("the given branch has commits: keep it", lit "{\"givenAhead\":true,\"others\":[{\"name\":\"ci/t\",\"ahead\":true,\"contains\":true}]}"),
    ("nothing to land and no candidate", lit "{\"givenAhead\":false,\"others\":[]}"),
    ("the agent's ci branch is the one candidate", lit "{\"givenAhead\":false,\"others\":[{\"name\":\"ci/t\",\"ahead\":true,\"contains\":true},{\"name\":\"w\",\"ahead\":false,\"contains\":true}]}"),
    ("a candidate that does not contain the given branch is no candidate", lit "{\"givenAhead\":false,\"others\":[{\"name\":\"ci/t\",\"ahead\":true,\"contains\":false}]}"),
    ("two different candidates: ambiguous, refuse", lit "{\"givenAhead\":false,\"others\":[{\"name\":\"ci/t\",\"ahead\":true,\"contains\":true},{\"name\":\"w\",\"ahead\":true,\"contains\":true}]}"),
    ("missing givenAhead is refused", lit "{\"others\":[]}")]),
  ("console", "console.landPool", [
    ("idle machine: all cores", lit "{\"cores\":8,\"load\":0}"),
    ("light load: the free cores", lit "{\"cores\":8,\"load\":3}"),
    ("load at half the cores: half", lit "{\"cores\":8,\"load\":5}"),
    ("saturated: the fair-share floor, not one", lit "{\"cores\":8,\"load\":20}"),
    ("odd core count", lit "{\"cores\":10,\"load\":23}"),
    ("one core: one", lit "{\"cores\":1,\"load\":9}"),
    ("zero cores: still one", lit "{\"cores\":0,\"load\":0}"),
    ("missing load is refused", lit "{\"cores\":8}")]),
  ("console", "console.landRetry", [
    ("passed: no re-run", lit "{\"passed\":true,\"loadFailure\":false}"),
    ("passed with a timeout word in the log: no re-run", lit "{\"passed\":true,\"loadFailure\":true}"),
    ("failed by the code: final", lit "{\"passed\":false,\"loadFailure\":false}"),
    ("timed out under load: re-run alone", lit "{\"passed\":false,\"loadFailure\":true}"),
    ("missing loadFailure is refused", lit "{\"passed\":false}")]),
  ("console", "console.previewTarget", [
    ("landed on main: main", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"ci\",\"sha\":\"7ba0436\",\"onMain\":true,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}],\"children\":[]}"),
    ("integrated only: the newest integration ref that contains it", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"ci\",\"sha\":\"4d26f44\",\"onMain\":false,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}],\"children\":[]}"),
    ("an older ref when the newest does not contain it", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"ci\",\"sha\":\"4d26f44\",\"onMain\":false,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":false},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}],\"children\":[]}"),
    ("the head is exactly an integration tip: that ref, not a newer one", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"ci\",\"sha\":\"26e5f53\",\"onMain\":false,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}],\"children\":[]}"),
    ("a documentation-only handoff commit does not hide the commit the gate ran", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"handoff\",\"sha\":\"ad919a4\",\"onMain\":false,\"noCode\":true,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":false},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":false}]},{\"src\":\"ci\",\"sha\":\"26e5f53\",\"onMain\":false,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}],\"children\":[]}"),
    ("a head with no code that nothing holds: the newest integration ref", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"named\",\"sha\":\"ef1774f\",\"onMain\":false,\"noCode\":true,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":false},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":false}]}],\"children\":[]}"),
    ("a head with code that nothing holds: its own head", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"named\",\"sha\":\"0f5cdb7\",\"onMain\":false,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":false},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":false}]}],\"children\":[]}"),
    ("no integration ref at all and no code: its own head", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"named\",\"sha\":\"0f5cdb7\",\"onMain\":false,\"noCode\":true,\"cands\":[]}],\"children\":[]}"),
    ("no head and no sub-task: no preview", lit "{\"main\":\"25d9402\",\"facts\":[],\"children\":[]}"),
    ("an umbrella whose sub-tasks are all on main: main", lit "{\"main\":\"25d9402\",\"facts\":[],\"children\":[{\"facts\":[{\"src\":\"ci\",\"sha\":\"a1\",\"onMain\":true,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}]},{\"facts\":[{\"src\":\"ci\",\"sha\":\"a2\",\"onMain\":true,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}]}]}"),
    ("an umbrella with one sub-task only integrated: the first ref that holds all", lit "{\"main\":\"25d9402\",\"facts\":[],\"children\":[{\"facts\":[{\"src\":\"ci\",\"sha\":\"a1\",\"onMain\":true,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}]},{\"facts\":[{\"src\":\"ci\",\"sha\":\"a2\",\"onMain\":false,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":false}]}]}]}"),
    ("an umbrella whose sub-tasks share no ref: no preview", lit "{\"main\":\"25d9402\",\"facts\":[],\"children\":[{\"facts\":[{\"src\":\"ci\",\"sha\":\"a1\",\"onMain\":false,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":false}]}]},{\"facts\":[{\"src\":\"ci\",\"sha\":\"a2\",\"onMain\":false,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":false},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}]}]}"),
    ("a head that is a direct commit on main's first-parent line is its own land commit", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"ci\",\"sha\":\"d1d1d1d\",\"onMain\":true,\"noCode\":false,\"fpLine\":true,\"path\":[],\"cands\":[]}],\"children\":[]}"),
    ("a landed head previews the first line commit whose second parent holds it", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"ci\",\"sha\":\"a1a1a1a\",\"onMain\":true,\"noCode\":false,\"fpLine\":false,\"path\":[{\"sha\":\"b2b2b2b\",\"p2Has\":false},{\"sha\":\"c3c3c3c\",\"p2Has\":true},{\"sha\":\"e5e5e5e\",\"p2Has\":true}],\"cands\":[]}],\"children\":[]}"),
    ("a merge whose second parent does not hold the task's work is never the head", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"merge\",\"sha\":\"f6f6f6f\",\"onMain\":true,\"noCode\":false,\"fpLine\":true,\"ownWork\":false,\"path\":[],\"cands\":[]},{\"src\":\"originCi\",\"sha\":\"5b50ad0\",\"onMain\":true,\"noCode\":false,\"fpLine\":false,\"path\":[{\"sha\":\"6e968ba\",\"p2Has\":true}],\"cands\":[]},{\"src\":\"handoffCommit\",\"sha\":\"72971b8\",\"onMain\":true,\"noCode\":false,\"behind\":true,\"fpLine\":false,\"path\":[{\"sha\":\"6e968ba\",\"p2Has\":true}],\"cands\":[]}],\"children\":[]}"),
    ("missing main is refused", lit "{\"facts\":[]}")] ++ Fw.Console.PreviewTable.goldenCases),
  ("console", "console.previewAdmit", [
    ("the user starts the first preview: the two lowest ports", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"live\":[]}"),
    ("a test range: the base moves both ports, the production range is not touched", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"portBase\":47300,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47300,\"op\":47301,\"started\":0}]}"),
    ("a base whose backend ports would leave the port space is refused noPorts", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"portBase\":64600,\"live\":[]}"),
    ("the highest base that fits is admitted", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"portBase\":64496,\"live\":[]}"),
    ("the second preview takes the next two", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a freed port pair is reused", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"live\":[{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("a third preview is refused", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("the same task twice is refused", lit "{\"preview\":\"n\",\"task\":\"port-nav\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("the same id twice is refused", lit "{\"preview\":\"a\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("low disk is refused", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":100,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"live\":[]}"),
    ("no target is refused", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":false,\"secret\":false,\"cookie\":true,\"origin\":true,\"live\":[]}"),
    ("the console secret is refused even with cookie and origin", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":true,\"cookie\":true,\"origin\":true,\"live\":[]}"),
    ("no owner cookie is refused", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":false,\"origin\":true,\"live\":[]}"),
    ("no same-origin Origin is refused", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":false,\"live\":[]}"),
    ("neither cookie nor origin is refused", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":false,\"origin\":false,\"live\":[]}"),
    ("a missing proof field is refused", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"live\":[]}"),
    ("missing now is refused", lit "{\"secret\":false,\"cookie\":true,\"origin\":true,\"preview\":\"n\",\"task\":\"t\",\"diskMb\":9000,\"hasTarget\":true,\"live\":[]}")]),
  ("console", "console.previewTick", [
    ("nothing live", lit "{\"now\":10,\"live\":[]}"),
    ("both inside the TTL", lit "{\"now\":3000000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("the older one is past its deadline", lit "{\"now\":3600000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("both past", lit "{\"now\":3700000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}")]),
  ("console", "console.previewStop", [
    ("the user stops a recorded preview", lit "{\"secret\":false,\"cookie\":true,\"origin\":true,\"preview\":\"a\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("an id that is not in the table kills nothing", lit "{\"secret\":false,\"cookie\":true,\"origin\":true,\"preview\":\"zzz\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("a request without the owner cookie is refused", lit "{\"secret\":false,\"cookie\":false,\"origin\":true,\"preview\":\"a\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}")]),
  ("console", "console.previewFail", [
    ("a failed build leaves the table", lit "{\"preview\":\"a\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("an id that is not in the table changes nothing", lit "{\"preview\":\"zzz\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("missing live is fine: empty table", lit "{\"preview\":\"a\"}")]),
  ("console", "console.previewLink", [
    ("a terminal: the link goes to the tty, the only allowed sink", lit "{\"hasTty\":true}"),
    ("no terminal: no link is printed", lit "{\"hasTty\":false}"),
    ("a first reissue is allowed", lit "{\"hasTty\":true,\"now\":5000}"),
    ("a reissue 59.999 s after the last link is refused", lit "{\"hasTty\":true,\"now\":70000,\"last\":10001}"),
    ("a reissue a minute after the last link is allowed", lit "{\"hasTty\":true,\"now\":70000,\"last\":10000}")]),
  ("console", "console.previewReap", [
    ("everything recorded is killed", lit "{\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("empty table", lit "{\"live\":[]}")]),
  ("console", "console.ownerLogin", [
    ("a fresh address with the right passphrase gets in", lit "{\"enabled\":true,\"correct\":true,\"now\":1000}"),
    ("a wrong passphrase is recorded at the address and globally", lit "{\"enabled\":true,\"correct\":false,\"now\":1000}"),
    ("the fifth failure inside the window locks the address for 10 minutes", lit "{\"enabled\":true,\"correct\":false,\"now\":5000,\"fails\":[1000,2000,3000,4000]}"),
    ("failures older than the window are forgotten", lit "{\"enabled\":true,\"correct\":false,\"now\":700000,\"fails\":[1000,2000,3000,4000]}"),
    ("a locked address is refused even with the right passphrase", lit "{\"enabled\":true,\"correct\":true,\"now\":5001,\"lockUntil\":605000}"),
    ("the lock ends at its end time", lit "{\"enabled\":true,\"correct\":true,\"now\":605000,\"lockUntil\":605000}"),
    ("a console without a passphrase refuses the login", lit "{\"enabled\":false,\"correct\":true,\"now\":1000}"),
    ("a missing correct field is refused", lit "{\"enabled\":true,\"now\":1000}"),
    ("the twentieth global failure locks every address, a fresh one included", lit "{\"enabled\":true,\"correct\":false,\"now\":20000,\"gFails\":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19]}"),
    ("a global lock refuses a fresh address with the right passphrase", lit "{\"enabled\":true,\"correct\":true,\"now\":20001,\"gLockUntil\":620000}"),
    ("a global lock that ended lets a correct passphrase in", lit "{\"enabled\":true,\"correct\":true,\"now\":620000,\"gLockUntil\":620000}"),
    ("a wrong passphrase adds to the global failures", lit "{\"enabled\":true,\"correct\":false,\"now\":3000,\"gFails\":[1000,2000]}"),
    ("global failures older than the window are forgotten", lit "{\"enabled\":true,\"correct\":false,\"now\":700000,\"gFails\":[1000,2000,3000]}")]),
  ("console", "console.previewCache", [
    ("a manifest name is immutable", lit "{\"path\":\"/assets/index-BxK3a9Qz.js\",\"manifest\":[\"/assets/index-BxK3a9Qz.js\"]}"),
    ("the same name outside the manifest revalidates", lit "{\"path\":\"/assets/index-BxK3a9Qz.js\"}"),
    ("a manifest css name is immutable", lit "{\"path\":\"/assets/entry-client-CQgE-Jzo.css\",\"manifest\":[\"/assets/entry-client-BrkKyAS_.js\",\"/assets/entry-client-CQgE-Jzo.css\"]}"),
    ("hashed font under _app/immutable: immutable, not compressed", lit "{\"path\":\"/_app/immutable/assets/google-sans-latin-normal.BbZhqv4U.woff2\"}"),
    ("anything under _app/immutable is immutable", lit "{\"path\":\"/_app/immutable/chunks/x.js\"}"),
    ("mui.<sha8>.css is immutable", lit "{\"path\":\"/mui.b3bea9d9.css\"}"),
    ("a mui css name with a capital is not", lit "{\"path\":\"/mui.B3bea9d9.css\"}"),
    ("a mui css name below a directory is not", lit "{\"path\":\"/x/mui.b3bea9d9.css\"}"),
    ("html revalidates", lit "{\"path\":\"/index.html\"}"),
    ("a manifest html name still revalidates", lit "{\"path\":\"/assets/index-BxK3a9Qz.html\",\"manifest\":[\"/assets/index-BxK3a9Qz.html\"]}"),
    ("a root path revalidates", lit "{\"path\":\"/\"}"),
    ("an unhashed font revalidates", lit "{\"path\":\"/selling/fonts/playpen-sans-latin.woff2\"}"),
    ("Roboto-SemiBold looks hashed but is not listed: other", lit "{\"path\":\"/fonts/Roboto-SemiBold.woff2\"}"),
    ("og-1200x630 looks hashed but is not listed: other", lit "{\"path\":\"/img/og-1200x630.png\"}"),
    ("icon-darkMode looks hashed but is not listed: other", lit "{\"path\":\"/icons/icon-darkMode.svg\"}"),
    ("a hash-looking name beside a manifest that lacks it: other", lit "{\"path\":\"/assets/app.4f3a9c1d.css\",\"manifest\":[\"/assets/x.js\"]}"),
    ("svg is compressed, png is not", lit "{\"path\":\"/selling/a.svg\"}"),
    ("png revalidates, not compressed", lit "{\"path\":\"/selling/a.png\"}"),
    ("a manifest that is not an array of strings is refused", lit "{\"path\":\"/a.js\",\"manifest\":[1]}"),
    ("missing path is refused", lit "{}")]),
  ("console", "console.builds", [
    ("landed port and fix tasks, newest first; one row per task at its newest land commit; unknown and non-port tasks left out", lit "{\"main\":\"m9\",\"log\":[{\"sha\":\"c5\",\"time\":500,\"body\":\"land hero\\n\\nTask: port-hero\\n\"},{\"sha\":\"c4\",\"time\":400,\"body\":\"graph: x\\n\\nTask: proof-lean\\n\"},{\"sha\":\"c3\",\"time\":300,\"body\":\"land nav fix\\n\\nTask: fix-nav\\n\"},{\"sha\":\"c2\",\"time\":350,\"body\":\"re-land hero\\n\\nTask: port-hero\\n\"},{\"sha\":\"c1\",\"time\":100,\"body\":\"land ghost\\n\\nTask: port-ghost\\n\"}],\"known\":[{\"id\":\"port-hero\",\"title\":\"Hero port\"},{\"id\":\"fix-nav\",\"title\":\"Nav fix\"},{\"id\":\"proof-lean\",\"title\":\"A proof\"},{\"id\":\"port-later\",\"title\":\"Not landed yet\"}],\"flags\":[],\"presets\":[]}"),
    ("no landings: no port rows", lit "{\"main\":\"m9\",\"log\":[],\"known\":[{\"id\":\"port-hero\",\"title\":\"Hero port\"},{\"id\":\"fix-nav\",\"title\":\"Nav fix\"},{\"id\":\"proof-lean\",\"title\":\"A proof\"},{\"id\":\"port-later\",\"title\":\"Not landed yet\"}],\"flags\":[],\"presets\":[]}"),
    ("a commit with two trailers gives two rows", lit "{\"main\":\"m9\",\"log\":[{\"sha\":\"d1\",\"time\":10,\"body\":\"both\\n\\nTask: port-hero\\nTask: fix-nav\\n\"}],\"known\":[{\"id\":\"port-hero\",\"title\":\"Hero port\"},{\"id\":\"fix-nav\",\"title\":\"Nav fix\"},{\"id\":\"proof-lean\",\"title\":\"A proof\"},{\"id\":\"port-later\",\"title\":\"Not landed yet\"}],\"flags\":[],\"presets\":[]}"),
    ("flag and preset rows: status from the v2-proved preset, C3 flag out, faithful baseline, requires in the search, target is main", lit "{\"main\":\"m9\",\"log\":[],\"known\":[],\"flags\":[{\"part\":\"hero.countdown\",\"variant\":\"faithful\",\"kind\":\"faithful\"},{\"part\":\"hero.countdown\",\"variant\":\"strip\",\"kind\":\"optimized\"},{\"part\":\"engine.scroll\",\"variant\":\"batched\",\"kind\":\"optimized\"},{\"part\":\"nav.hitTest\",\"variant\":\"elements-skip\",\"kind\":\"optimized\"},{\"part\":\"morph.countdown\",\"variant\":\"strip\",\"kind\":\"optimized\",\"requires\":[\"hero.countdown:strip\"]}],\"presets\":[{\"name\":\"original\",\"fw\":{}},{\"name\":\"v2-proved\",\"fw\":{\"engine.scroll\":\"batched\",\"hero.countdown\":\"strip\"}}]}"),
    ("no v2-proved preset: nothing is proved, C3 stays out", lit "{\"main\":\"m9\",\"log\":[],\"known\":[],\"flags\":[{\"part\":\"hero.countdown\",\"variant\":\"faithful\",\"kind\":\"faithful\"},{\"part\":\"hero.countdown\",\"variant\":\"strip\",\"kind\":\"optimized\"},{\"part\":\"engine.scroll\",\"variant\":\"batched\",\"kind\":\"optimized\"},{\"part\":\"nav.hitTest\",\"variant\":\"elements-skip\",\"kind\":\"optimized\"},{\"part\":\"morph.countdown\",\"variant\":\"strip\",\"kind\":\"optimized\",\"requires\":[\"hero.countdown:strip\"]}],\"presets\":[{\"name\":\"original\",\"fw\":{}}]}"),
    ("evidence only: a task without a trailer gets a row at its evidence land commit with its own land slot", lit "{\"main\":\"m9\",\"log\":[{\"sha\":\"e3\",\"time\":300,\"body\":\"land nav\\n\\nTask: fix-nav\\n\"},{\"sha\":\"e2\",\"time\":200,\"body\":\"merge old hero work\"},{\"sha\":\"e1\",\"time\":100,\"body\":\"root\"}],\"known\":[{\"id\":\"port-hero\",\"title\":\"Hero port\"},{\"id\":\"fix-nav\",\"title\":\"Nav fix\"},{\"id\":\"proof-lean\",\"title\":\"A proof\"},{\"id\":\"port-later\",\"title\":\"Not landed yet\"}],\"evidence\":[{\"task\":\"port-hero\",\"sha\":\"e2\"}],\"flags\":[],\"presets\":[]}"),
    ("a trailer landing wins over an evidence fact of the same task", lit "{\"main\":\"m9\",\"log\":[{\"sha\":\"t3\",\"time\":300,\"body\":\"land hero\\n\\nTask: port-hero\\n\"},{\"sha\":\"t2\",\"time\":200,\"body\":\"merge old hero work\"}],\"known\":[{\"id\":\"port-hero\",\"title\":\"Hero port\"},{\"id\":\"fix-nav\",\"title\":\"Nav fix\"},{\"id\":\"proof-lean\",\"title\":\"A proof\"},{\"id\":\"port-later\",\"title\":\"Not landed yet\"}],\"evidence\":[{\"task\":\"port-hero\",\"sha\":\"t2\"}],\"flags\":[],\"presets\":[]}"),
    ("evidence whose land commit is not in the log, and evidence of a non-port task, give no row", lit "{\"main\":\"m9\",\"log\":[{\"sha\":\"n2\",\"time\":200,\"body\":\"merge\"}],\"known\":[{\"id\":\"port-hero\",\"title\":\"Hero port\"},{\"id\":\"fix-nav\",\"title\":\"Nav fix\"},{\"id\":\"proof-lean\",\"title\":\"A proof\"},{\"id\":\"port-later\",\"title\":\"Not landed yet\"}],\"evidence\":[{\"task\":\"port-hero\",\"sha\":\"zz\"},{\"task\":\"proof-lean\",\"sha\":\"n2\"},{\"task\":\"port-ghost\",\"sha\":\"n2\"}],\"flags\":[],\"presets\":[]}"),
    ("a preset that extends another: the glue passes the resolved fw, so an inherited variant is v2-proved", lit "{\"main\":\"m9\",\"log\":[],\"known\":[],\"evidence\":[],\"flags\":[{\"part\":\"engine.scroll\",\"variant\":\"batched\",\"kind\":\"optimized\"},{\"part\":\"nav.hitTest\",\"variant\":\"elements-skip\",\"kind\":\"optimized\"}],\"presets\":[{\"name\":\"original\",\"fw\":{\"engine.scroll\":\"batched\"}},{\"name\":\"v2-proved\",\"fw\":{\"engine.scroll\":\"batched\",\"nav.hitTest\":\"elements-skip\"}}]}"),
    ("a malformed flag is refused", lit "{\"main\":\"m9\",\"log\":[],\"known\":[],\"flags\":[{\"part\":\"a\"}],\"presets\":[]}"),
    ("missing main is refused", lit "{\"log\":[],\"known\":[],\"flags\":[],\"presets\":[]}")]),
  ("console", "console.buildsSearch", [
    ("the long search: v2-proved, then five flags; accepted, canonical form unchanged", srch "?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped"),
    ("v2-proved alone", srch "?preset=v2-proved"),
    ("the empty search is the default page", srch ""),
    ("a lone question mark is the default page", srch "?"),
    ("no leading question mark is read the same", srch "preset=v2-proved"),
    ("a preset that extends another", srch "?preset=strip-demo"),
    ("the fw entries of several fw parameters are joined in order", srch "?fw=hero.exit:scoped&fw=pain.notes:visible"),
    ("the preset comes first in the canonical form, whatever the order given", srch "?fw=hero.exit:scoped&preset=v2-proved"),
    ("a later fw entry overrides the preset", srch "?preset=v2-proved&fw=morph.mount:shift-dormant"),
    ("empty fw entries and unknown parameters are dropped", srch "?utm=1&fw=,hero.exit:scoped,&fw="),
    ("an impl the part has", srch "?fw=hero.countdown:strip@plain"),
    ("an impl from a preset", srch "?preset=plain-impl"),
    ("an unknown part", srch "?fw=hero.nothing:strip"),
    ("an unknown variant", srch "?fw=hero.exit:nope"),
    ("an unknown impl", srch "?fw=hero.exit:scoped@mui"),
    ("an unknown impl in a preset", srch "?preset=bad-impl"),
    ("two presets", srch "?preset=original&preset=v2-proved"),
    ("an unknown preset", srch "?preset=nope"),
    ("an empty preset name", srch "?preset="),
    ("a preset cycle", srch "?preset=loop-a"),
    ("a requires violation", srch "?fw=morph.countdown:strip"),
    ("the requirement chosen too: accepted", srch "?fw=hero.countdown:strip,morph.countdown:strip"),
    ("a conflicts violation", srch "?fw=nav.hitTest:hit-skip,engine.scroll:batched"),
    ("a conflicts violation across a preset and an fw entry", srch "?preset=v2-proved&fw=nav.hitTest:hit-skip"),
    ("an entry without a variant", srch "?fw=hero.exit"),
    ("an entry with two colons", srch "?fw=hero.exit:scoped:x"),
    ("several errors are all reported, in the site's order", srch "?preset=original&preset=nope&fw=a:b,hero.exit:nope,zzz"),
    ("a percent escape is refused", srch "?fw=hero.exit:scoped%20x"),
    ("angle brackets are refused", srch "?fw=<script>"),
    ("a space is refused", srch "?fw=hero.exit:scoped hero.countdown:strip"),
    ("a second question mark is refused", srch "??fw=hero.exit:scoped"),
    ("a fragment is refused", srch "?fw=hero.exit:scoped#x"),
    ("a search over 2000 characters is refused", srch ("?fw=" ++ "".pushn 'a' 2001)),
    ("a missing registry is refused", Json.mkObj [("search", "?preset=original")])]),
  ("console", "console.buildsOpen", [
    ("a row reuses a serving preview of its commit and opens the rewrite arm", lit "{\"mode\":\"row\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"search\":\"?preset=v2-proved\",\"previews\":[{\"id\":\"p1\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"serving\":true}],\"port\":47001}"),
    ("a row reuses a serving preview of another slot at the same commit", lit "{\"mode\":\"row\",\"slot\":\"opt-flag-x\",\"sha\":\"m9\",\"search\":\"?fw=a:b\",\"previews\":[{\"id\":\"p2\",\"slot\":\"land-port-hero\",\"sha\":\"m9\",\"serving\":true}],\"port\":47001}"),
    ("the compare arm", lit "{\"mode\":\"row\",\"arm\":\"compare\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"search\":\"?preset=v2-proved\",\"previews\":[{\"id\":\"p1\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"serving\":true}],\"port\":47001}"),
    ("a port row opens at the default page", lit "{\"mode\":\"row\",\"slot\":\"land-port-hero\",\"sha\":\"c5\",\"search\":\"\",\"previews\":[{\"id\":\"p3\",\"slot\":\"land-port-hero\",\"sha\":\"c5\",\"serving\":true}],\"port\":47001}"),
    ("a building preview of the commit: wait for it, start nothing", lit "{\"mode\":\"row\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"search\":\"?preset=v2-proved\",\"previews\":[{\"id\":\"p4\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"serving\":false}],\"port\":47001}"),
    ("a serving preview wins over a building one of the same commit", lit "{\"mode\":\"row\",\"slot\":\"s\",\"sha\":\"m9\",\"search\":\"\",\"previews\":[{\"id\":\"b\",\"slot\":\"s\",\"sha\":\"m9\",\"serving\":false},{\"id\":\"a\",\"slot\":\"t\",\"sha\":\"m9\",\"serving\":true}],\"port\":47001}"),
    ("the slot holds a preview of an older commit: rebuild", lit "{\"mode\":\"row\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"search\":\"?preset=v2-proved\",\"previews\":[{\"id\":\"p5\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m1\",\"serving\":true}],\"port\":47001}"),
    ("a preview of another commit in another slot: start", lit "{\"mode\":\"row\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"search\":\"?preset=v2-proved\",\"previews\":[{\"id\":\"p6\",\"slot\":\"land-port-hero\",\"sha\":\"m1\",\"serving\":true}],\"port\":47001}"),
    ("no preview at all: start", lit "{\"mode\":\"row\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"search\":\"?preset=v2-proved\",\"previews\":[]}"),
    ("LAN on with an address: the link uses it", lit "{\"mode\":\"row\",\"slot\":\"s\",\"sha\":\"m9\",\"search\":\"?preset=v2-proved\",\"previews\":[{\"id\":\"p1\",\"slot\":\"s\",\"sha\":\"m9\",\"serving\":true}],\"lan\":true,\"lanAddr\":\"192.0.2.10\",\"port\":47001}"),
    ("LAN on but no address known: loopback", lit "{\"mode\":\"row\",\"slot\":\"s\",\"sha\":\"m9\",\"search\":\"\",\"previews\":[{\"id\":\"p1\",\"slot\":\"s\",\"sha\":\"m9\",\"serving\":true}],\"lan\":true,\"port\":47001}"),
    ("LAN off: loopback even when an address is given", lit "{\"mode\":\"row\",\"slot\":\"s\",\"sha\":\"m9\",\"search\":\"\",\"previews\":[{\"id\":\"p1\",\"slot\":\"s\",\"sha\":\"m9\",\"serving\":true}],\"lan\":false,\"lanAddr\":\"192.0.2.10\",\"port\":47001}"),
    ("a valid pasted search reuses the main build", openS "?preset=v2-proved&fw=hero.exit:scoped" "{\"previews\":[{\"id\":\"p1\",\"slot\":\"opt-preset-original\",\"sha\":\"m9\",\"serving\":true}],\"port\":47001}"),
    ("a pasted search is opened in canonical form", openS "?fw=hero.exit:scoped&preset=v2-proved" "{\"previews\":[{\"id\":\"p1\",\"slot\":\"x\",\"sha\":\"m9\",\"serving\":true}],\"port\":47001}"),
    ("a pasted search with no main preview starts the main slot", openS "?preset=v2-proved" "{\"previews\":[{\"id\":\"p1\",\"slot\":\"x\",\"sha\":\"m1\",\"serving\":true}]}"),
    ("the main slot holds an older main: rebuild", openS "?preset=v2-proved" "{\"previews\":[{\"id\":\"p7\",\"slot\":\"open-main\",\"sha\":\"m1\",\"serving\":true}]}"),
    ("a refused search opens nothing even when a preview serves", openS "?preset=original&preset=v2-proved" "{\"previews\":[{\"id\":\"p1\",\"slot\":\"x\",\"sha\":\"m9\",\"serving\":true}],\"port\":47001}"),
    ("a bad charset opens nothing", openS "?fw=hero.exit:scoped%20x" "{\"previews\":[]}"),
    ("an unknown arm is refused", lit "{\"mode\":\"row\",\"arm\":\"x\",\"slot\":\"s\",\"sha\":\"m9\",\"previews\":[]}"),
    ("an unknown mode is refused", lit "{\"mode\":\"x\",\"previews\":[]}")]),
  ("console", "console.compose", [
    ("no picks: every part at its default, the empty search is the default page", cmp "[]"),
    ("a measured pick opens its flag", cmp "[{\"part\":\"hero.countdown\",\"variant\":\"strip\"}]"),
    ("picks in any order give one canonical search, in page order", cmp "[{\"part\":\"pain.notes\",\"variant\":\"visible\"},{\"part\":\"hero.countdown\",\"variant\":\"strip\"}]"),
    ("a pick of the default variant adds nothing", cmp "[{\"part\":\"hero.countdown\",\"variant\":\"faithful\"}]"),
    ("a look-change variant is allowed and classed look-change in the table", cmp "[{\"part\":\"hero.countdown\",\"variant\":\"one-chain\"}]"),
    ("a refuted variant is refused with its reason, no link", cmp "[{\"part\":\"morph.tween\",\"variant\":\"waapi\"}]"),
    ("an unrated variant (no ledger row) is allowed", cmp "[{\"part\":\"morph.tween\",\"variant\":\"waapi-scoped\"}]"),
    ("a requires violation is refused", cmp "[{\"part\":\"morph.countdown\",\"variant\":\"strip\"}]"),
    ("the requirement chosen too: allowed", cmp "[{\"part\":\"morph.countdown\",\"variant\":\"strip\"},{\"part\":\"hero.countdown\",\"variant\":\"strip\"}]"),
    ("a conflicts violation is refused", cmp "[{\"part\":\"nav.hitTest\",\"variant\":\"hit-skip\"},{\"part\":\"engine.scroll\",\"variant\":\"batched\"}]"),
    ("an unknown part is refused", cmp "[{\"part\":\"hero.nothing\",\"variant\":\"strip\"}]"),
    ("an unknown variant is refused", cmp "[{\"part\":\"hero.countdown\",\"variant\":\"nope\"}]"),
    ("two proved variants of coupled parts: allowed, with the coupling notes", cmp "[{\"part\":\"pain.notes\",\"variant\":\"visible\"},{\"part\":\"engine.scroll\",\"variant\":\"batched\"},{\"part\":\"morph.tween\",\"variant\":\"waapi-scoped\"}]"),
    ("the last pick of a part wins", cmp "[{\"part\":\"hero.countdown\",\"variant\":\"one-chain\"},{\"part\":\"hero.countdown\",\"variant\":\"strip\"}]"),
    ("no ledger rows: every non-default variant is unrated", cmp "[]" "[]"),
    ("a malformed ledger row is refused", cmp "[]" "[{\"part\":\"a\"}]"),
    ("a refuted row superseded by a proved row no longer refutes: the superseding row is about the same flag, its class applies, the pick is allowed", cmp "[{\"part\":\"morph.tween\",\"variant\":\"waapi\"}]" cmpLedgerFixed),
    ("a supersededBy that names no ledger row id is refused", cmp "[]" "[{\"part\":\"morph.tween\",\"candidate\":\"morph.tween `waapi`\",\"status\":\"refuted\",\"flags\":[\"morph.tween:waapi\"],\"flag\":\"morph.tween:waapi\",\"id\":\"tw.falsified\",\"supersededBy\":\"tw.nothing\"}]"),
    ("a supersededBy naming its own row is refused", cmp "[{\"part\":\"morph.tween\",\"variant\":\"waapi\"}]" "[{\"part\":\"morph.tween\",\"candidate\":\"morph.tween `waapi`\",\"status\":\"refuted\",\"flags\":[\"morph.tween:waapi\"],\"flag\":\"morph.tween:waapi\",\"id\":\"tw.falsified\",\"supersededBy\":\"tw.falsified\"}]"),
    ("two rows that supersede each other (a 2-cycle) are refused", cmp "[{\"part\":\"morph.tween\",\"variant\":\"waapi\"}]" "[{\"part\":\"morph.tween\",\"candidate\":\"morph.tween `waapi`\",\"status\":\"refuted\",\"flags\":[\"morph.tween:waapi\"],\"flag\":\"morph.tween:waapi\",\"id\":\"tw.falsified\",\"supersededBy\":\"tw.fixed\"},{\"part\":\"morph.tween\",\"candidate\":\"the fixed driver\",\"status\":\"proved\",\"flags\":[\"morph.tween:waapi\"],\"id\":\"tw.fixed\",\"supersededBy\":\"tw.falsified\"}]"),
    ("a chain of two supersededBy reaching a live row is allowed: the live row's class applies", cmp "[{\"part\":\"morph.tween\",\"variant\":\"waapi\"}]" "[{\"part\":\"morph.tween\",\"candidate\":\"morph.tween `waapi`\",\"status\":\"refuted\",\"flags\":[\"morph.tween:waapi\"],\"flag\":\"morph.tween:waapi\",\"id\":\"tw.falsified\",\"supersededBy\":\"tw.fixed\"},{\"part\":\"morph.tween\",\"candidate\":\"the fixed driver\",\"status\":\"proved\",\"flags\":[\"morph.tween:waapi\"],\"id\":\"tw.fixed\",\"supersededBy\":\"tw.fixed2\"},{\"part\":\"morph.tween\",\"candidate\":\"the second fix\",\"status\":\"proved\",\"flags\":[\"morph.tween:waapi\"],\"id\":\"tw.fixed2\"}]"),
    ("two ledger rows with the same id are refused", cmp "[]" "[{\"part\":\"morph.tween\",\"candidate\":\"morph.tween `waapi`\",\"status\":\"refuted\",\"flags\":[\"morph.tween:waapi\"],\"id\":\"tw.fixed\"},{\"part\":\"morph.tween\",\"candidate\":\"the fixed driver\",\"status\":\"proved\",\"flags\":[\"morph.tween:waapi\"],\"id\":\"tw.fixed\"}]"),
    ("a supersededBy that is not a string is refused", cmp "[]" "[{\"part\":\"morph.tween\",\"candidate\":\"morph.tween `waapi`\",\"status\":\"refuted\",\"flags\":[\"morph.tween:waapi\"],\"supersededBy\":1}]"),
    ("a variant whose rows are all proved is ledger-proved; a mix of proved and measured is measured", cmp2 "[]"),
    ("rows attach to morph.columns:hidden-pause and morph.countdown:hidden-pause by their flags; presets with a non-default impl are refused", cmp2 "[{\"part\":\"morph.columns\",\"variant\":\"hidden-pause\"}]"),
    ("a ledger row without a flags field is refused", cmp "[]" "[{\"part\":\"morph.tween\",\"candidate\":\"morph.tween `waapi`\",\"status\":\"refuted\"}]"),
    ("a flag naming no registered part or variant is refused, one error per flag", cmp "[]" "[{\"part\":\"morph.tween\",\"candidate\":\"morph.tween `waapi`\",\"status\":\"refuted\",\"flags\":[\"morph.tween:nope\",\"hero.nothing:strip\"]}]"),
    ("a flag field missing from the row's flags is refused", cmp "[]" "[{\"part\":\"morph.tween\",\"candidate\":\"morph.tween `waapi`\",\"status\":\"refuted\",\"flags\":[\"morph.tween:waapi-scoped\"],\"flag\":\"morph.tween:waapi\"}]"),
    ("flags that are not an array of strings are refused", cmp "[]" "[{\"part\":\"morph.tween\",\"candidate\":\"morph.tween `waapi`\",\"status\":\"refuted\",\"flags\":\"morph.tween:waapi\"}]"),
    ("a row superseded by a row about another flag is refused", cmp "[{\"part\":\"morph.tween\",\"variant\":\"waapi\"}]" "[{\"part\":\"morph.tween\",\"candidate\":\"morph.tween `waapi`\",\"status\":\"refuted\",\"flags\":[\"morph.tween:waapi\"],\"flag\":\"morph.tween:waapi\",\"id\":\"tw.falsified\",\"supersededBy\":\"tw.fixed\"},{\"part\":\"morph.tween\",\"candidate\":\"the fixed driver\",\"status\":\"proved\",\"flags\":[\"morph.tween:waapi-scoped\"],\"id\":\"tw.fixed\"}]"),
    ("a superseding row that keeps the superseded row's flags and adds one is allowed: it joins both variants", cmp "[{\"part\":\"morph.tween\",\"variant\":\"waapi\"}]" "[{\"part\":\"morph.tween\",\"candidate\":\"morph.tween `waapi`\",\"status\":\"refuted\",\"flags\":[\"morph.tween:waapi\"],\"flag\":\"morph.tween:waapi\",\"id\":\"tw.falsified\",\"supersededBy\":\"tw.fixed\"},{\"part\":\"morph.tween\",\"candidate\":\"the fixed driver\",\"status\":\"proved\",\"flags\":[\"morph.tween:waapi\",\"morph.tween:waapi-scoped\"],\"id\":\"tw.fixed\"}]"),
    ("the real registry and ledger: every variant gets the rows the text rules gave", cmpReal),
    ("a missing registry is refused", lit "{\"picks\":[],\"ledger\":[]}")]),
  ("console", "console.buildsPicker", [
    ("keys of a build: default first, then presets, then flags, each in key order", lit "{\"keys\":[\"?fw=hero.countdown:strip\",\"?preset=v2-proved\",\"\",\"?fw=a:b,c:d\",\"?preset=original\"],\"current\":\"?fw=a:b,c:d\"}"),
    ("an unknown current search falls back to the default", lit "{\"keys\":[\"\",\"?preset=original\"],\"current\":\"?fw=zzz\"}"),
    ("a current search that is not prerendered is not offered even when well formed", lit "{\"keys\":[\"\",\"?preset=original\"],\"current\":\"?preset=v2-proved\"}"),
    ("a key outside the alphabets is never offered", lit "{\"keys\":[\"\",\"?fw=a\\\"b\",\"?preset=<x>\",\"?other=1\",\"?fw=\",\"?preset=\"],\"current\":\"?preset=<x>\"}"),
    ("no current search: the default", lit "{\"keys\":[\"\",\"?preset=original\"]}"),
    ("a build without the default key: the current search that is offered stays", lit "{\"keys\":[\"?preset=original\"],\"current\":\"?preset=original\"}"),
    ("missing keys: an empty picker", lit "{\"current\":\"\"}")]),
  ("console", "console.ownerGate", [
    ("LAN, no session: the login page", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/owner/login\"}"),
    ("LAN, no token: the shell (the built console web) is served", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/\"}"),
    ("LAN, no token: a static asset is shell", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/assets/index.js\"}"),
    ("LAN, no token: the owner link route is refused", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/owner\"}"),
    ("LAN, no token: logout is refused", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/owner/logout\"}"),
    ("LAN, no token, foreign Host: the shell is refused", lit "{\"lan\":true,\"session\":false,\"hostOk\":false,\"path\":\"/\"}"),
    ("LAN, no session: the API is refused", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/api/board\"}"),
    ("LAN, no session: a preview path is refused", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/preview/a/r/\"}"),
    ("LAN, no session: another spelling of the login path is refused", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/owner/login/\"}"),
    ("LAN with a session: the console web", lit "{\"lan\":true,\"session\":true,\"hostOk\":true,\"path\":\"/\"}"),
    ("LAN with a session: the console port never serves a preview path", lit "{\"lan\":true,\"session\":true,\"hostOk\":true,\"path\":\"/preview/a/r/\"}"),
    ("LAN with a session but a foreign Host is refused", lit "{\"lan\":true,\"session\":true,\"hostOk\":false,\"path\":\"/\"}"),
    ("loopback keeps today's rules: no session needed", lit "{\"lan\":false,\"session\":false,\"hostOk\":false,\"path\":\"/api/board\"}"),
    ("loopback: the console port never serves a preview path", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"path\":\"/preview/a/o/\"}"),
    ("preview port, no preview cookie: refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/preview/a/r/\",\"port\":\"preview\"}"),
    ("preview port, preview cookie: served", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"path\":\"/preview/a/r/\",\"port\":\"preview\"}"),
    ("preview port, LAN, preview cookie, foreign Host: refused", lit "{\"lan\":true,\"session\":true,\"hostOk\":false,\"path\":\"/preview/a/r/\",\"port\":\"preview\"}"),
    ("preview port, LAN, preview cookie, right Host: served", lit "{\"lan\":true,\"session\":true,\"hostOk\":true,\"path\":\"/preview/a/r/\",\"port\":\"preview\"}"),
    ("preview port, live grant cookie: a preview path is served", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/preview/a/o/\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, live grant cookie, LAN host: a preview path is served", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/preview/a/o/\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, grant cookie, LAN, foreign Host: refused", lit "{\"lan\":true,\"session\":false,\"hostOk\":false,\"path\":\"/preview/a/o/\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, grant cookie 60 minutes old: refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/preview/a/o/\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":3601000}"),
    ("preview port, grant cookie just inside 60 minutes: served", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/preview/a/o/\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":3600999}"),
    ("preview port, grant cookie unknown to the console: refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/preview/a/o/\",\"port\":\"preview\",\"grant\":false,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, grant: /api is refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/api/tasks\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, grant: /owner is refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/owner/logout\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, grant: the login page is refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/owner/login\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, grant: a root-absolute script path is no preview path (no Referer reading), refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/_app/immutable/entry/start.js\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, grant: a root-absolute path without a preview Referer is refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/_app/immutable/entry/start.js\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, grant: the shell root is refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, session cookie still serves, reported as the session", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"path\":\"/preview/a/o/\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":0,\"now\":99999999}"),
    ("an unknown port is refused", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"path\":\"/\",\"port\":\"x\"}")]),
  ("console", "console.previewArm", [
    ("task arm, session cookie: its root-absolute module path goes to its backend unchanged", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"port\":47100,\"path\":\"/_app/immutable/entry/start.js\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("original arm of the same preview", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"port\":47101,\"path\":\"/_app/immutable/entry/start.js\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("second preview, task arm: another backend, never the first preview", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"port\":47102,\"path\":\"/selling/x.png?v=1\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("second preview, original arm", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"port\":47103,\"path\":\"/\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("a port no arm listens on is refused by route", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"port\":47104,\"path\":\"/\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("no cookie and no grant: not allowed", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"port\":47100,\"path\":\"/\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("grant cookie, inside 60 minutes: allowed by grant", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"port\":47100,\"path\":\"/_app/x.js\",\"grant\":true,\"grantStarted\":1000,\"now\":2000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("grant cookie 60 minutes old: not allowed", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"port\":47100,\"path\":\"/\",\"grant\":true,\"grantStarted\":1000,\"now\":3601000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("LAN, session cookie, foreign Host: not allowed", lit "{\"lan\":true,\"session\":true,\"hostOk\":false,\"port\":47100,\"path\":\"/\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("LAN, session cookie, right Host: allowed", lit "{\"lan\":true,\"session\":true,\"hostOk\":true,\"port\":47101,\"path\":\"/index.html\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("an api path on an arm origin is just that arm's file path", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"port\":47100,\"path\":\"/api/board\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}")]),
  ("console", "console.loginReturn", [
    ("an HTML request to a live arm keeps its exact path and query", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("the original arm of the preview", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47101,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("an API request stays refused", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":false,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a port no live preview owns is sent to the login without a return", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47999,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("the console port is never a return target", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47000,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a protocol-relative path is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"//evil.example/x\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a path that is not a path is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"javascript:alert(1)\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("an encoded CRLF is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/%0d%0aSet-Cookie:x=1\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a backslash is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/\\\\evil.example\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a fragment is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/x#y\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a path over 2000 characters is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a host with userinfo is refused", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"evil@192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a host with a path is refused", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"evil.example/x\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a short nonce is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"abc\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a live preview path on the preview port is kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47001,\"path\":\"/preview/a/compare\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a stopped preview path on the preview port is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47001,\"path\":\"/preview/zz/compare\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("the preview port without a preview path is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47001,\"path\":\"/__grant?t=x\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("the loopback name works", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"127.0.0.1\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a held link that is still live is the destination, on the login host", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"192.0.2.9\",\"now\":1000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}],\"held\":{\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"issuedAt\":500}}"),
    ("a stopped preview goes to the Builds tab", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"192.0.2.9\",\"now\":1000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[],\"held\":{\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"issuedAt\":500}}"),
    ("nothing held goes home", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"192.0.2.9\",\"now\":1000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("an expired reference goes home", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"192.0.2.9\",\"now\":700000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}],\"held\":{\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"issuedAt\":500}}"),
    ("a bad host goes home", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"evil@192.0.2.9\",\"now\":1000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}],\"held\":{\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"issuedAt\":500}}"),
    ("a held path outside the allowlist goes home", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"192.0.2.9\",\"now\":1000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}],\"held\":{\"port\":47100,\"path\":\"//evil.example\",\"issuedAt\":500}}"),
    ("a stopped preview-port link goes to the Builds tab", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"192.0.2.9\",\"now\":1000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[],\"held\":{\"port\":47001,\"path\":\"/preview/a/compare\",\"issuedAt\":500}}"),
    ("a live preview-port link is the destination", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"192.0.2.9\",\"now\":1000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}],\"held\":{\"port\":47001,\"path\":\"/preview/a/compare\",\"issuedAt\":500}}"),
    ("a well-formed foreign host is refused", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"evil.example\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("HEAD is not sent to the login", lit "{\"kind\":\"redirect\",\"method\":\"HEAD\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a full store logs in plain", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":256,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("one below the cap still keeps the link", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":255,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a well-formed foreign host lands home", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"evil.example\",\"now\":1000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}],\"held\":{\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"issuedAt\":500}}")]),
  ("console", "console.previewGrant", [
    ("issue from loopback is allowed", lit "{\"kind\":\"issue\",\"lan\":false}"),
    ("issue from a LAN address is refused", lit "{\"kind\":\"issue\",\"lan\":true}"),
    ("redeem: loopback, known, unused, inside ten minutes", lit "{\"kind\":\"redeem\",\"lan\":false,\"known\":true,\"used\":false,\"issuedAt\":1000,\"now\":2000}"),
    ("redeem: the last millisecond of the ten minutes", lit "{\"kind\":\"redeem\",\"lan\":false,\"known\":true,\"used\":false,\"issuedAt\":1000,\"now\":600999}"),
    ("redeem: ten minutes are over", lit "{\"kind\":\"redeem\",\"lan\":false,\"known\":true,\"used\":false,\"issuedAt\":1000,\"now\":601000}"),
    ("redeem: a second use is refused", lit "{\"kind\":\"redeem\",\"lan\":false,\"known\":true,\"used\":true,\"issuedAt\":1000,\"now\":2000}"),
    ("redeem: a token this console never issued", lit "{\"kind\":\"redeem\",\"lan\":false,\"known\":false,\"used\":false,\"issuedAt\":0,\"now\":2000}"),
    ("redeem: from a LAN address is refused even with a good token", lit "{\"kind\":\"redeem\",\"lan\":true,\"known\":true,\"used\":false,\"issuedAt\":1000,\"now\":2000}"),
    ("an unknown kind is refused", lit "{\"kind\":\"x\",\"lan\":false}")]),
  ("console", "console.ownerAction", [
    ("owner action: bearer token and the console origin (own Host)", lit "{\"kind\":\"owner\",\"bearer\":true,\"origin\":{\"host\":\"192.0.2.7\",\"port\":47000},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("owner action from a preview page (the preview origin) is refused", lit "{\"kind\":\"owner\",\"bearer\":true,\"origin\":{\"host\":\"192.0.2.7\",\"port\":47001},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("the preview port is not the console port plus one: its origin is still refused", lit "{\"kind\":\"owner\",\"bearer\":true,\"origin\":{\"host\":\"192.0.2.7\",\"port\":51234},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":51234}"),
    ("an extra origin on the preview port is dropped from the trusted list", lit "{\"kind\":\"owner\",\"bearer\":true,\"origin\":{\"host\":\"localhost\",\"port\":47001},\"host\":{\"host\":\"127.0.0.1\",\"port\":47000},\"extra\":[{\"host\":\"localhost\",\"port\":47001},{\"host\":\"localhost\",\"port\":5173}],\"previewPort\":47001}"),
    ("an extra web origin (the dev server) is trusted", lit "{\"kind\":\"owner\",\"bearer\":true,\"origin\":{\"host\":\"localhost\",\"port\":5173},\"host\":{\"host\":\"127.0.0.1\",\"port\":47000},\"extra\":[{\"host\":\"localhost\",\"port\":5173}],\"previewPort\":47001}"),
    ("the preview port unset: nothing is trusted, the owner action is refused", lit "{\"kind\":\"owner\",\"bearer\":true,\"origin\":{\"host\":\"192.0.2.7\",\"port\":47000},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[]}"),
    ("owner action without an Origin header is refused", lit "{\"kind\":\"owner\",\"bearer\":true,\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("owner action with a null Origin is refused", lit "{\"kind\":\"owner\",\"bearer\":true,\"origin\":null,\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("owner action without the bearer token is refused", lit "{\"kind\":\"owner\",\"bearer\":false,\"origin\":{\"host\":\"192.0.2.7\",\"port\":47000},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("a command from the console origin", lit "{\"kind\":\"command\",\"bearer\":false,\"origin\":{\"host\":\"192.0.2.7\",\"port\":47000},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("a command from a preview page is refused", lit "{\"kind\":\"command\",\"bearer\":true,\"origin\":{\"host\":\"192.0.2.7\",\"port\":47001},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("a command with no Origin (command-line tool) is accepted", lit "{\"kind\":\"command\",\"bearer\":false,\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("a login from the console origin", lit "{\"kind\":\"login\",\"bearer\":false,\"origin\":{\"host\":\"192.0.2.7\",\"port\":47000},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("a login from a preview page is refused", lit "{\"kind\":\"login\",\"bearer\":false,\"origin\":{\"host\":\"192.0.2.7\",\"port\":47001},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("a login without an Origin is refused", lit "{\"kind\":\"login\",\"bearer\":false,\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("an unknown kind is refused", lit "{\"kind\":\"x\",\"bearer\":true,\"extra\":[]}")]),
  ("console", "console.lanStart", [
    ("not asked for", lit "{\"want\":false,\"hasAddr\":true,\"hasPass\":true,\"passLen\":20}"),
    ("no private address", lit "{\"want\":true,\"hasAddr\":false,\"hasPass\":true,\"passLen\":20}"),
    ("no passphrase in the keychain", lit "{\"want\":true,\"hasAddr\":true,\"hasPass\":false,\"passLen\":0}"),
    ("eleven characters is too short", lit "{\"want\":true,\"hasAddr\":true,\"hasPass\":true,\"passLen\":11}"),
    ("twelve characters starts", lit "{\"want\":true,\"hasAddr\":true,\"hasPass\":true,\"passLen\":12}")]),
  ("console", "console.daemon", [
    ("start with nothing recorded is allowed", lit "{\"kind\":\"start\"}"),
    ("start with a recorded pid that does not answer is allowed (stale file)", lit "{\"kind\":\"start\",\"recorded\":4242}"),
    ("start while the recorded pid answers is refused", lit "{\"kind\":\"start\",\"recorded\":4242,\"answered\":4242}"),
    ("start when another pid answers on the recorded port is allowed", lit "{\"kind\":\"start\",\"recorded\":4242,\"answered\":9999}"),
    ("pid 1 is never a console", lit "{\"kind\":\"start\",\"recorded\":1,\"answered\":1}"),
    ("start is refused when the recorded pid is alive but did not answer", lit "{\"kind\":\"start\",\"recorded\":4242,\"alive\":true}"),
    ("a recorded pid that is not alive does not block start", lit "{\"kind\":\"start\",\"recorded\":4242,\"alive\":false}"),
    ("pid 1 alive and silent blocks nothing", lit "{\"kind\":\"start\",\"recorded\":1,\"alive\":true}"),
    ("a different pid answered while the recorded one is alive: allowed", lit "{\"kind\":\"start\",\"recorded\":4242,\"answered\":9999,\"alive\":true}"),
    ("stop signals the verified pid", lit "{\"kind\":\"stop\",\"recorded\":4242,\"answered\":4242}"),
    ("stop signals nothing when nothing answers", lit "{\"kind\":\"stop\",\"recorded\":4242,\"answered\":null}"),
    ("stop signals nothing on a pid mismatch", lit "{\"kind\":\"stop\",\"recorded\":4242,\"answered\":9999}"),
    ("stop signals nothing when nothing is recorded", lit "{\"kind\":\"stop\",\"answered\":4242}"),
    ("restart of a verified console stops then starts", lit "{\"kind\":\"restart\",\"recorded\":4242,\"answered\":4242}"),
    ("restart with no verified console only starts", lit "{\"kind\":\"restart\",\"recorded\":4242}"),
    ("a log below the default limit is kept", lit "{\"kind\":\"rotate\",\"size\":5242879}"),
    ("a log at the default limit is rotated", lit "{\"kind\":\"rotate\",\"size\":5242880}"),
    ("a log of exactly 50 MiB draws no warning", lit "{\"kind\":\"rotate\",\"size\":52428800}"),
    ("a log above 50 MiB draws the warning", lit "{\"kind\":\"rotate\",\"size\":52428801}"),
    ("a custom limit", lit "{\"kind\":\"rotate\",\"size\":100,\"limit\":100}"),
    ("an unknown kind is refused", lit "{\"kind\":\"x\"}")]),
  ("console", "console.previewSweep", [
    ("nothing live", lit "{\"now\":10,\"live\":[]}"),
    ("a fresh and a busy preview stay", lit "{\"now\":1000000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0,\"seen\":500000},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":900000}]}"),
    ("15 minutes without a request stops it (idle)", lit "{\"now\":1400000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0,\"seen\":500000}]}"),
    ("14 min 59.999 s without a request stays", lit "{\"now\":1399999,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0,\"seen\":500000}]}"),
    ("the TTL stops a preview that is in use", lit "{\"now\":3600000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0,\"seen\":3599000}]}"),
    ("a preview never used since it started is idle after 15 minutes", lit "{\"now\":900000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}")]),
  ("console", "console.actor", [
    ("all sources", lit "{}"),
    ("the alert source writes as script", lit "{\"source\":\"alert\"}"),
    ("unknown source is refused", lit "{\"source\":\"lead\"}")])]

open Fw.Ops.LeanFirst in
def leanFirstReq (F : Facts) : Json := lfFactsJson F

def withField (k : String) (v : Json) : Json → Json
  | .obj kvs => .obj (kvs.insert k v)
  | j => j

open Fw.Ops.LeanFirst in
def faultName (f : Fault) : String := ((reprStr f).splitOn ".").getLastD ""

open Fw.Ops.LeanFirst in
def leanFirstCases (_ : Unit := ()) : List (String × Json) :=
  let at_ := s!"at the deployed stage {stage.name}"
  [(s!"all rules met {at_}", leanFirstReq base)] ++
  Fault.all.map (fun f => (s!"fault {faultName f} {at_}", leanFirstReq (factsOf [f]))) ++
  [(s!"two reason faults (stub implementation, no kill): both reasons, the verdict names the first {at_}",
     leanFirstReq (factsOf [.stub, .noKill])),
   (s!"stub: the property's own implementation is unreached though a lemma of the land is reached {at_}",
     leanFirstReq (factsOf [.stub])),
   (s!"directory glob apps/runner/** over decision code with no property: no-props {at_}",
     leanFirstReq (factsOf [.dirGlob])),
   (s!"globs only under docs/ and research/ with no property: not decision code {at_}",
     leanFirstReq (factsOf [.docsGlob])),
   (s!"a candidate theorem without reachFromWire: missing reach {at_}", leanFirstReq (factsOf [.reachUnknown])),
   (s!"exempt.tsv and killOf read at branch commit b, not main m: missing exempt-main {at_}",
     leanFirstReq (factsOf [.exemptBranch])),
   (s!"exempt.tsv and killOf never read (no exemptAt): missing exempt-main {at_}",
     withField "exemptAt" .null (leanFirstReq base)),
   (s!"request stage field ratchet is ignored: same reply as all rules met {at_}",
     withField "stage" (.str "ratchet") (leanFirstReq base)),
   (s!"request stage field ratchet is ignored on a stub {at_}",
     withField "stage" (.str "ratchet") (leanFirstReq (factsOf [.stub]))),
   (s!"unknown stage name is ignored, not refused {at_}", lit "{\"stage\":\"strict\"}"),
   (s!"untested premise shared with the property: WARN line {at_}", leanFirstReq (factsOf [.untestedShared])),
   (s!"a line break in a theorem name is printed as a space {at_}", leanFirstReq (factsOf [.newlineName, .noKill])),
   (s!"empty request: every source missing {at_}", lit "{}"),
   ("unknown sign-off role is refused",
     lit "{\"signoffs\":[{\"decl\":\"P\",\"stmtHash\":\"h\",\"role\":\"lead\",\"agree\":true}]}"),
   ("registry row without a status is refused", lit "{\"registry\":[{\"id\":\"p\"}]}")]

def rgReq (ts : List String) : Json := Json.mkObj [("tokens", .arr (ts.toArray.map Json.str))]

def renderGuardCases (_ : Unit := ()) : List (String × Json) := [
  ("no commit: nothing refused", rgReq [""]),
  ("source and docs only: passes", rgReq ["commit c1", "\nA", "apps/site/src/a.ts", "M", "docs/team/tools/land.md", ""]),
  ("a render added then removed in a later commit: still refused (history-wide)",
    rgReq ["commit c2", "\nD", "results/hero.png", "commit c1", "\nA", "results/hero.png", "A", "results/run.json", ""]),
  ("media under snapshot/: passes", rgReq ["commit c1", "\nA", "snapshot/fastwork.co/a.jpg", "A", "snapshot/fastwork.co/f.woff2", ""]),
  ("a lookalike snapshots/ directory: refused", rgReq ["commit c1", "\nA", "snapshots/a.png", ""]),
  ("snapshot/ nested below another directory: refused", rgReq ["commit c1", "\nA", "results/snapshot/a.png", ""]),
  ("upper-case extension: refused", rgReq ["commit c1", "\nA", "results/A.JPG", ""]),
  ("a trailing space after the extension: refused", rgReq ["commit c1", "\nA", "results/hero.png ", ""]),
  ("font, video and audio: each refused", rgReq ["commit c1", "\nA", "a/f.ttf", "A", "b/v.mp4", "A", "c/s.wav", ""]),
  ("a modified media path: refused", rgReq ["commit c1", "\nM", "results/a.webp", ""]),
  ("a type change to a media path: refused", rgReq ["commit c1", "\nT", "results/a.svg", ""]),
  ("an unknown status letter: refused", rgReq ["commit c1", "\nX", "results/a.gif", ""]),
  ("a removal alone: passes", rgReq ["commit c1", "\nD", "results/a.png", ""]),
  ("a merge's first-parent diff with a render: refused", rgReq ["commit m1", "\nA", "src/a.ts", "A", "results/b.avif", "commit c1", "\nA", "src/a.ts", ""]),
  ("an empty commit between two: the later path keeps its own commit", rgReq ["commit c3", "commit c2", "\nA", "results/a.png", ""]),
  ("a path that reads like a header is a path", rgReq ["commit c1", "\nA", "commit x.png", ""]),
  ("a path with a tab and a space: refused", rgReq ["commit c1", "\nA", "results/a b\tc.png", ""]),
  ("a compressed render x.png.gz: passes (extension only)", rgReq ["commit c1", "\nA", "results/x.png.gz", ""]),
  ("a directory with a dot and a file without one: passes", rgReq ["commit c1", "\nA", "a.png/Makefile", ""]),
  ("missing tokens: refused", Json.mkObj [])]

def rv (looks steps : String) (answer : String := "null") : Json :=
  Json.mkObj [("looks", lit looks), ("steps", lit steps), ("answer", lit answer)]

def reviewCases (_ : Unit := ()) : List (String × Json) :=
  let mat := "{\"chromium\":{\"state\":\"ready\",\"run\":\"1\",\"artifact\":\"frames-chromium\",\"expires\":\"2026-11-19\"},\"webkit\":{\"state\":\"pending\",\"task\":\"t\"}}"
  let row (f d dec rev : String) := s!"\{\"flag\":\"{f}\",\"date\":\"{d}\",\"decision\":\"{dec}\",\"review\":\"{rev}\"}"
  let pend := s!"[\{\"flag\":\"nav:earn-no-transition\",\"date\":\"2026-10-21\",\"decision\":\"kept\",\"review\":\"pending\",\"material\":{mat}}]"
  let two := s!"[{row "nav:earn-no-transition" "2026-10-21" "kept" "pending"},{row "hero:x" "2026-10-22" "kept" "done"},{row "nav:earn-no-transition" "2026-10-23" "accepted" "pending"}]"
  let st (id : String) (ans : String) (o : String) := s!"\{\"id\":\"{id}\",\"answer\":{ans},\"open\":{o}}"
  let e := "nav:earn-no-transition"
  let w (word : String) := s!"\{\"flag\":\"{e}\",\"word\":\"{word}\"}"
  [("a pending look decision with no step yet: one open item, the step is to be posted", rv pend "[]"),
   ("the step is on the board, waiting: open, not posted again", rv pend s!"[{st "review-nav:earn-no-transition" "null" "true"}]"),
   ("started then done, or cancelled (the step is closed with no answer): the item is open and a new step review-...#1 is to be posted", rv pend s!"[{st "review-nav:earn-no-transition" "null" "false"}]"),
   ("a step closed with no answer: keep is refused until the new step is posted", rv pend s!"[{st "review-nav:earn-no-transition" "null" "false"}]" (w "keep")),
   ("the new step is open after a cancelled one: keep is accepted on it", rv pend s!"[{st "review-nav:earn-no-transition" "null" "false"},{st "review-nav:earn-no-transition#1" "null" "true"}]" (w "keep")),
   ("two steps closed with no answer: the next id is #2", rv pend s!"[{st "review-nav:earn-no-transition" "null" "false"},{st "review-nav:earn-no-transition#1" "null" "false"}]"),
   ("answered keep: closed as keep", rv pend s!"[{st "review-nav:earn-no-transition" "\"keep\"" "false"}]"),
   ("answered reject: closed as reject", rv pend s!"[{st "review-nav:earn-no-transition" "\"reject\"" "false"}]"),
   ("answered reject on the second step: closed as reject", rv pend s!"[{st "review-nav:earn-no-transition" "null" "false"},{st "review-nav:earn-no-transition#1" "\"reject\"" "false"}]"),
   ("an answer that is no verdict word does not close the item; a new step is to be posted", rv pend s!"[{st "review-nav:earn-no-transition" "\"maybe\"" "false"}]"),
   ("a step of another flag closes nothing", rv pend s!"[{st "review-hero:x" "\"keep\"" "false"}]"),
   ("a decided look change is no item; a repeated pending row gives one item", rv two "[]"),
   ("no pending decision: no item, nothing open", rv s!"[{row "nav:a" "d" "kept" "done"}]" "[]"),
   ("keep on an open step is accepted", rv pend s!"[{st "review-nav:earn-no-transition" "null" "true"}]" (w "keep")),
   ("reject on an open step is accepted", rv pend s!"[{st "review-nav:earn-no-transition" "null" "true"}]" (w "reject")),
   ("keep without a step on the board is refused (the step is posted first)", rv pend "[]" (w "keep")),
   ("a decided item is not answered again", rv pend s!"[{st "review-nav:earn-no-transition" "\"keep\"" "false"}]" (w "reject")),
   ("a flag without a pending decision is refused", rv pend "[]" "{\"flag\":\"nav:other\",\"word\":\"keep\"}"),
   ("a word that is not keep or reject is refused", rv pend s!"[{st "review-nav:earn-no-transition" "null" "true"}]" (w "yes")),
   ("a bad flag key is refused", rv pend "[]" "{\"flag\":\"nocolon\",\"word\":\"keep\"}"),
   ("a decision word that is unknown is refused", rv "[{\"flag\":\"nav:a\",\"date\":\"d\",\"decision\":\"yes\",\"review\":\"pending\"}]" "[]"),
   ("without looks the rows are Fw.Preset.Gen.lookDecisions", Json.mkObj [("steps", lit "[]")])]

def rpv (looks steps events : String) (ask : String := "null") (extra : List (String × Json) := []) : Json :=
  Json.mkObj ([("looks", lit looks), ("steps", lit steps), ("events", lit events), ("ask", lit ask)] ++ extra)

def reviewPreviewCases (_ : Unit := ()) : List (String × Json) :=
  let pend := "[{\"flag\":\"nav:earn-no-transition\",\"date\":\"2026-10-21\",\"decision\":\"kept\",\"review\":\"pending\"}]"
  let st (id : String) (ans : String) (o : String) := s!"\{\"id\":\"{id}\",\"answer\":{ans},\"open\":{o}}"
  let open_ := s!"[{st "review-nav:earn-no-transition" "null" "true"}]"
  let done := s!"[{st "review-nav:earn-no-transition" "\"keep\"" "false"}]"
  let ev (d : String) := s!"\{\"flag\":\"nav:earn-no-transition\",\"device\":\"{d}\"}"
  let ask (v : String) (w : Nat) := s!"\{\"flag\":\"nav:earn-no-transition\",\"view\":\"{v}\",\"width\":{w}}"
  let kev (d : String) (tag : String) := s!"[\{\"flag\":\"nav:earn-no-transition\",\"device\":\"{d}\",\"key\":\"review-previewed-nav:earn-no-transition-{d}{tag}\"}]"
  let round2 := s!"[{st "review-nav:earn-no-transition" "null" "false"},{st "review-nav:earn-no-transition#1" "null" "true"}]"
  let closed1 := s!"[{st "review-nav:earn-no-transition" "null" "false"}]"
  let names (search flag : String) := [("names", Json.mkObj [("search", .str search), ("flag", .str flag)])]
  [("nothing previewed: both devices are missing, with an ask line each", rpv pend open_ "[]"),
   ("round 2 (step #1 open): a preview keyed for round 1 is not inherited", rpv pend round2 (kev "desktop" "")),
   ("round 2 click: the event key carries the round (#1), so it is no duplicate of round 1's", rpv pend round2 "[]" (ask "flag" 390)),
   ("round 2: a preview keyed #1 counts", rpv pend round2 (kev "desktop" "#1")),
   ("round 1 only (step open): a preview keyed for round 1 counts", rpv pend open_ (kev "desktop" "")),
   ("round 1: a preview keyed for round 2 (#1) is not shown", rpv pend open_ (kev "desktop" "#1")),
   ("round 2 not posted yet: the old round's event (keyed round 1) shows nothing", rpv pend closed1 (kev "phone" "")),
   ("round 2 not posted yet: a click recorded in the unposted window (key #1) shows in round 2", rpv pend closed1 (kev "phone" "#1")),
   ("an untagged old event (no key) shows in round 1", rpv pend open_ s!"[{ev "desktop"}]"),
   ("an untagged old event (no key) is not shown in round 2", rpv pend round2 s!"[{ev "desktop"}]"),
   ("the search names the flag by a whole entry", rpv pend open_ "[]" "null" (names "?fw=nav:earn-no-transition" "nav:earn-no-transition")),
   ("nav:earn is not named by a search for nav:earn-no-transition", rpv pend open_ "[]" "null" (names "?fw=nav:earn-no-transition" "nav:earn")),
   ("nav:earn-no-transition is not named by a search for nav:earn", rpv pend open_ "[]" "null" (names "?fw=nav:earn" "nav:earn-no-transition")),
   ("a comma list names each of its whole entries", rpv pend open_ "[]" "null" (names "?fw=hero:a,nav:earn,nav:earn-no-transition" "nav:earn")),
   ("no search names no flag", rpv pend open_ "[]" "null" (names "" "nav:earn")),
   ("previewed on the desktop only: the phone is missing", rpv pend open_ s!"[{ev "desktop"}]"),
   ("previewed on both: nothing missing, no ask line", rpv pend open_ s!"[{ev "phone"},{ev "desktop"}]"),
   ("an event of another flag counts for nothing", rpv pend open_ "[{\"flag\":\"nav:other\",\"device\":\"phone\"}]"),
   ("flag view from a phone-wide viewport: ?fw=<flag>, rewrite arm, phone", rpv pend open_ "[]" (ask "flag" 390)),
   ("flag view at the breakpoint (600): still a phone", rpv pend open_ "[]" (ask "flag" 600)),
   ("flag view one px above the breakpoint (601): desktop", rpv pend open_ "[]" (ask "flag" 601)),
   ("faithful view: no search, rewrite arm", rpv pend open_ "[]" (ask "faithful" 1280)),
   ("compare view: the flag search on the compare page", rpv pend open_ "[]" (ask "compare" 1280)),
   ("a decided review gets no preview", rpv pend done "[]" (ask "flag" 390)),
   ("no step on the board: the item is open, the click is planned", rpv pend "[]" "[]" (ask "flag" 390)),
   ("a flag without a pending decision gets no preview", rpv pend open_ "[]" "{\"flag\":\"nav:other\",\"view\":\"flag\",\"width\":390}"),
   ("an unknown view is refused", rpv pend open_ "[]" (ask "original" 390)),
   ("a bad flag key is refused", rpv pend open_ "[]" "{\"flag\":\"nocolon\",\"view\":\"flag\",\"width\":390}")]

def rfb (events : String) (flag : Option String := none) : Json :=
  Json.mkObj ([("events", lit events)] ++ (match flag with | some f => [("flag", Json.str f)] | none => []))

def reviewFeedbackCases (_ : Unit := ()) : List (String × Json) :=
  let p (f i t : String) (ts : Nat) := s!"\{\"type\":\"review.feedback\",\"flag\":\"{f}\",\"id\":\"{i}\",\"text\":\"{t}\",\"ts\":{ts}}"
  let r (f to t : String) (ts : Nat) := s!"\{\"type\":\"review.feedback.reply\",\"flag\":\"{f}\",\"to\":\"{to}\",\"text\":\"{t}\",\"ts\":{ts}}"
  let a := "nav:earn-no-transition"
  let b := "hero:cta-pulse"
  [("no events: no threads", rfb "[]"),
   ("one comment is open", rfb s!"[{p a "fb-1" "look at the font" 100}]"),
   ("a reply answers exactly the comment it names", rfb s!"[{p a "fb-1" "one" 100},{p a "fb-2" "two" 110},{r a "fb-1" "done" 120}]"),
   ("a repeated id changes nothing", rfb s!"[{p a "fb-1" "one" 100},{p a "fb-1" "again" 110}]"),
   ("a reply to an unknown id is ignored", rfb s!"[{p a "fb-1" "one" 100},{r a "fb-9" "x" 110}]"),
   ("a reply on the wrong flag is ignored", rfb s!"[{p a "fb-1" "one" 100},{r b "fb-1" "x" 110}]"),
   ("a second reply to an answered comment is ignored", rfb s!"[{p a "fb-1" "one" 100},{r a "fb-1" "first" 110},{r a "fb-1" "second" 120}]"),
   ("a blank text is ignored", rfb s!"[{p a "fb-1" "  " 100}]"),
   ("events of other types are ignored", rfb "[{\"type\":\"step.start\",\"step\":\"x\"}]"),
   ("two flags are two threads, in the order of the first comment", rfb s!"[{p b "fb-1" "hero" 100},{p a "fb-2" "nav" 110}]"),
   ("with a flag only that thread", rfb s!"[{p b "fb-1" "hero" 100},{p a "fb-2" "nav" 110}]" (some a)),
   ("a flag with no comment gets an empty thread", rfb "[]" (some a)),
   ("a text of 2000 astral characters (the cap) is accepted", rfb s!"[{p a "fb-1" (String.ofList (List.replicate 2000 '😀')) 100}]"),
   ("a text of 2001 astral characters (one over the cap) is ignored", rfb s!"[{p a "fb-1" (String.ofList (List.replicate 2001 '😀')) 100}]")]

def stp (events steps : String) : Json := Json.mkObj [("events", lit events), ("steps", lit steps)]

def stepTopicsCases (_ : Unit := ()) : List (String × Json) :=
  let tp (id title sum : String) (ts : Nat) := s!"\{\"type\":\"step.topic\",\"topic\":\"{id}\",\"title\":\"{title}\",\"summary\":\"{sum}\",\"ts\":{ts}}"
  let q (f i t : String) (ts : Nat) := s!"\{\"type\":\"review.feedback\",\"flag\":\"{f}\",\"id\":\"{i}\",\"text\":\"{t}\",\"ts\":{ts}}"
  let r (f to t : String) (ts : Nat) := s!"\{\"type\":\"review.feedback.reply\",\"flag\":\"{f}\",\"to\":\"{to}\",\"text\":\"{t}\",\"ts\":{ts}}"
  let st (id : String) (topic : Option String) (status audience : String) (last : Nat) :=
    s!"\{\"id\":\"{id}\",\"topic\":{match topic with | some t => "\"" ++ t ++ "\"" | none => "null"},\"status\":\"{status}\",\"audience\":\"{audience}\",\"lastAt\":{last}}"
  [("no events and no steps: no groups, no threads", stp "[]" "[]"),
   ("a topic with an open step: the group lists the step and counts its time as activity",
    stp s!"[{tp "smoothness" "Smoothness" "Hero exit first." 100}]" s!"[{st "s1" (some "smoothness") "waiting" "user" 500}]"),
   ("more recent activity first: the topic with the newer step stands before the older one",
    stp s!"[{tp "a" "A" "one" 100},{tp "b" "B" "two" 200}]" s!"[{st "s1" (some "a") "waiting" "user" 900},{st "s2" (some "b") "started" "user" 300}]"),
   ("equal activity keeps definition order",
    stp s!"[{tp "a" "A" "one" 100},{tp "b" "B" "two" 100}]" "[]"),
   ("a step without a topic, and one with an undefined topic, form the group of the rest, after topics with work",
    stp s!"[{tp "a" "A" "one" 100}]" s!"[{st "s1" none "waiting" "user" 900},{st "s2" (some "gone") "waiting" "user" 950},{st "s3" (some "a") "waiting" "user" 200}]"),
   ("a quiet topic (no open step, no open question) stands after the group of the rest",
    stp s!"[{tp "quiet" "Quiet" "nothing open" 900},{tp "a" "A" "one" 100}]" s!"[{st "s1" none "waiting" "user" 50},{st "s2" (some "a") "waiting" "user" 60}]"),
   ("an open question on a quiet topic puts it among the topics with work",
    stp s!"[{tp "quiet" "Quiet" "nothing open" 900},{q "topic:quiet" "fb-1" "what is next?" 950}]" "[]"),
   ("the lead's reply to the question makes the topic quiet again",
    stp s!"[{tp "quiet" "Quiet" "nothing open" 900},{q "topic:quiet" "fb-1" "what is next?" 950},{r "topic:quiet" "fb-1" "nothing" 960}]" "[]"),
   ("a new definition of a topic replaces its title, summary and time and keeps its place",
    stp s!"[{tp "a" "A" "old" 100},{tp "b" "B" "two" 150},{tp "a" "A2" "new" 300}]" "[]"),
   ("an invalid topic event (blank title) changes nothing",
    stp s!"[{tp "a" "A" "one" 100},{tp "a" "  " "two" 200},{tp "" "T" "x" 300}]" "[]"),
   ("only open steps for the user are grouped: closed and lead steps are left out",
    stp s!"[{tp "a" "A" "one" 100}]" s!"[{st "s1" (some "a") "done" "user" 500},{st "s2" (some "a") "waiting" "lead" 500},{st "s3" (some "a") "answered" "user" 500}]"),
   ("threads: step and topic subjects only, in the order of the first comment; review flags are left out",
    stp s!"[{tp "a" "A" "one" 100},{q "nav:x" "fb-1" "review" 200},{q "step:s1" "fb-2" "why" 210},{q "topic:a" "fb-3" "how" 220},{r "step:s1" "fb-2" "because" 230}]" s!"[{st "s1" (some "a") "waiting" "user" 500}]")]

def rpM (run : String) : Json := Json.mkObj [("kind", "measured"), ("run", run)]

def rpI (why : String) : Json := Json.mkObj [("kind", "inferred"), ("why", why)]

def rpt (id : String := "hero-exit") (tag : Option Json := some (rpM "39634194664")) (value : String := "34.0")
    (layer : Option (String × Option Json) := none) (strips : Option String := some "https://github.com/OWNER/REPO/actions/runs/39634194664")
    (arm2 : String := "rewrite") (search2 : String := "?fw=hero:exit") (word : String := "adopt") (why : String := "Layout time falls 29 times") : Json :=
  let cell (arm v : String) (t : Option Json) := Json.mkObj ([("arm", Json.str arm), ("value", lit v)] ++ (match t with | some j => [("tag", j)] | none => []))
  let layers := (match layer with
    | some (v, t) => [Json.mkObj ([("layer", Json.str "hero"), ("verdict", Json.str v)] ++ (match t with | some j => [("tag", j)] | none => []))]
    | none => [])
  Json.mkObj ([("id", Json.str id), ("proposal", "hero-exit"), ("title", "Hero exit on WebKit"),
    ("arms", Json.arr #[Json.mkObj [("name", "original"), ("search", "")], Json.mkObj [("name", Json.str arm2), ("search", Json.str search2)]]),
    ("lanes", Json.arr #[Json.mkObj [("name", "webkit 1280"), ("layers", Json.arr layers.toArray),
      ("rows", Json.arr #[Json.mkObj [("metric", "frame interval p50"), ("unit", "ms"),
        ("cells", Json.arr #[cell "original" value tag, cell "rewrite" "17.0" (some (rpM "39634194664"))])],
        Json.mkObj [("metric", "render-work share"), ("unit", "%"),
        ("cells", Json.arr #[cell "original" "42.6" (some (rpM "39634194664")), cell "rewrite" "18.6" (some (rpI "A/A copy reads 16.7"))])]])]]),
    ("recommendation", Json.mkObj [("word", Json.str word), ("why", Json.str why)])] ++
    (match strips with | some u => [("strips", Json.str u)] | none => []))

def rq (reports : List Json) (steps : String := "[]") (answer : String := "null") : Json :=
  Json.mkObj [("reports", Json.arr reports.toArray), ("steps", lit steps), ("answer", lit answer)]

def reportCases (_ : Unit := ()) : List (String × Json) :=
  let st (id : String) (ans : String) (o : String) := s!"\{\"id\":\"{id}\",\"answer\":{ans},\"open\":{o}}"
  let open_ := s!"[{st "report-hero-exit" "null" "true"}]"
  let done (w : String) := s!"[{st "report-hero-exit" s!"\"{w}\"" "false"}]"
  let ans (w c : String) := s!"\{\"id\":\"hero-exit\",\"word\":\"{w}\",\"comment\":\"{c}\"}"
  [("a fully tagged report is shown and its step is still to be posted", rq [rpt]),
   ("a report whose step is open is open", rq [rpt] open_),
   ("a report whose step holds approve is approve", rq [rpt] (done "approve")),
   ("a step closed without a verdict is closed", rq [rpt] (done "later")),
   ("a number without a tag is refused", rq [rpt (tag := none)]),
   ("MEASURED without a run id is refused", rq [rpt (tag := some (rpM ""))]),
   ("MEASURED with a run that is no number is refused", rq [rpt (tag := some (rpM "abc"))]),
   ("INFERRED without its reason is refused", rq [rpt (tag := some (rpI "  "))]),
   ("a tag of another kind is refused", rq [rpt (tag := some (Json.mkObj [("kind", "guessed")]))]),
   ("a value that is no number is refused", rq [rpt (value := "\"fast\"")]),
   ("a layer verdict without a tag is refused", rq [rpt (layer := some ("E", none))]),
   ("a layer verdict outside E, Q, L is refused", rq [rpt (layer := some ("X", some (rpM "39634194664")))]),
   ("a tagged layer verdict Q is shown", rq [rpt (layer := some ("Q", some (rpM "39634194664")))]),
   ("two arms with one name are refused", rq [rpt (arm2 := "original")]),
   ("an arm search that is no query is refused", rq [rpt (search2 := "fw=hero")]),
   ("a strips link that is not https is refused", rq [rpt (strips := some "file:///tmp/x")]),
   ("a report without strips is shown", rq [rpt (strips := none)]),
   ("a recommendation outside adopt, hold, drop is refused", rq [rpt (word := "maybe")]),
   ("a recommendation without a reason is refused", rq [rpt (why := " ")]),
   ("an id with a capital letter is refused", rq [rpt (id := "Hero")]),
   ("one bad report does not hide a good one", rq [rpt (tag := none), rpt (id := "second")]),
   ("approve with no comment writes no feedback", rq [rpt] open_ (ans "approve" "")),
   ("hold with a comment writes feedback on report:<id>", rq [rpt] open_ (ans "hold" "check the 390 px strip")),
   ("reject with a blank comment writes no feedback", rq [rpt] open_ (ans "reject" "  ")),
   ("a word outside approve, hold, reject is refused", rq [rpt] open_ (ans "keep" "")),
   ("an answered report refuses a second answer", rq [rpt] (done "approve") (ans "reject" "")),
   ("an unposted report refuses an answer", rq [rpt] "[]" (ans "approve" "")),
   ("a step closed without a verdict refuses an answer", rq [rpt] (done "later") (ans "approve" "")),
   ("an answer for a report that is not shown is refused", rq [rpt (tag := none)] open_ (ans "approve" "")),
   ("a comment over the feedback cap is refused", rq [rpt] open_ (ans "approve" (String.ofList (List.replicate 2001 'x'))))]

def armsReg (changes : String) : String :=
  r#"{"parts":[{"id":"hero","slot":"hero","impls":["plain"],"variants":[{"name":"faithful","kind":"faithful"},{"name":"scene-pause","kind":"optimized","visClass":"E","lean":"Fw.Parts.HeroScenePause"}]},"# ++
  r#"{"id":"hero.exit","slot":"hero","impls":["plain"],"variants":[{"name":"faithful","kind":"faithful"},{"name":"threaded","kind":"optimized","lean":"Fw.Parts.HeroExitOpt"}]},"# ++
  r#"{"id":"hero.countdown","slot":"hero","impls":["mui","plain"],"variants":[{"name":"faithful","kind":"faithful"},{"name":"strip","kind":"optimized"},{"name":"hidden-pause","kind":"optimized","lean":"Fw.Parts.HeroCountdownHidden"},{"name":"one-chain","kind":"optimized","lean":"Fw.Parts.HeroCountdownOneChain"}]},"# ++
  r#"{"id":"nav","slot":"nav","impls":["plain"],"variants":[{"name":"faithful","kind":"faithful"},{"name":"earn-no-transition","kind":"proposal","visClass":"L","lean":"Fw.Parts.NavEarnOpt"}]}],"# ++
  r#""presets":[],"changes":"# ++ changes ++ "}"

def armsReq (arms : String) (changes : String := "[]") : Json :=
  lit ("{\"registry\":" ++ armsReg changes ++ ",\"ledger\":[],\"arms\":" ++ arms ++ "}")

def heroPause : String :=
  r#"[{"id":"hero-pause","label":"pause the hero","picks":[{"part":"hero","variant":"scene-pause"},{"part":"hero.countdown","variant":"hidden-pause"}]}]"#

def layersCases : List (String × Json) := [
  ("an empty arm and the original arm open the default page", armsReq r#"[{},{"original":true}]"#),
  ("scene-pause is E with its proof module as hypothesis", armsReq r#"[{"picks":[{"part":"hero","variant":"scene-pause"}]}]"#),
  ("hidden-pause has no visClass, so the arm is Q", armsReq r#"[{"picks":[{"part":"hero.countdown","variant":"hidden-pause"}]}]"#),
  ("two independent pauses compose into one link in page order",
    armsReq r#"[{"picks":[{"part":"hero.countdown","variant":"hidden-pause"},{"part":"hero","variant":"scene-pause"}]}]"#),
  ("a Change by id expands to its picks", armsReq r#"[{"changes":["hero-pause"]}]"# heroPause),
  ("an unknown Change id is refused", armsReq r#"[{"changes":["nope"]}]"#),
  ("strip is a branch inside a shared file: not extractable", armsReq r#"[{"picks":[{"part":"hero.countdown","variant":"strip"}]}]"#),
  ("a variant whose part lists no files is not extractable", armsReq r#"[{"picks":[{"part":"hero.exit","variant":"threaded"}]}]"#),
  ("a proposal with visClass L is graded L and not extractable", armsReq r#"[{"picks":[{"part":"nav","variant":"earn-no-transition"}]}]"#),
  ("an unknown part or variant is refused", armsReq r#"[{"picks":[{"part":"hero","variant":"nope"}]},{"picks":[{"part":"nope","variant":"x"}]}]"#),
  ("two variants of one part are refused: set twice, and they clash",
    armsReq r#"[{"picks":[{"part":"hero.countdown","variant":"hidden-pause"},{"part":"hero.countdown","variant":"one-chain"}]}]"#),
  ("a pick on a part a Change sets is refused, and the fix drops the pick",
    armsReq r#"[{"changes":["hero-pause"],"picks":[{"part":"hero","variant":"faithful"}]}]"# heroPause),
  ("the original arm with a pick is refused", armsReq r#"[{"original":true,"picks":[{"part":"hero","variant":"scene-pause"}]}]"#),
  ("the composite option of hero_copy opens an fwl link, graded L", armsReq r#"[{"layers":[{"layer":"hero_copy","opts":"c"}]}]"#),
  ("an option the layer does not offer is refused", armsReq r#"[{"layers":[{"layer":"hero_copy","opts":"s"}]}]"#),
  ("an unknown layer is refused", armsReq r#"[{"layers":[{"layer":"nope","opts":"c"}]}]"#),
  ("a composite layer next to a pick in its part clashes",
    armsReq r#"[{"picks":[{"part":"hero","variant":"scene-pause"}],"layers":[{"layer":"hero_copy","opts":"c"}]}]"#),
  ("a registry whose Change fails alone is refused as a whole",
    armsReq "[{}]" r#"[{"id":"strip","picks":[{"part":"hero.countdown","variant":"strip"}]}]"#)]

def declReg : Json :=
  let ids := (Fw.Parts.FootprintData.layerDecls.map (·.1)).eraseDups
  Json.mkObj [("presets", Json.arr #[]), ("parts", Json.arr (ids.map fun p => Json.mkObj [("id", .str p),
    ("variants", Json.arr #["faithful"]), ("impls", Json.arr #["plain"]),
    ("layers", Json.arr ((Fw.Parts.FootprintData.layerDecls.filter (·.1 == p)).map (Json.str ·.2.1)).toArray)]).toArray)]

def layersSearchCases : List (String × Json) :=
  let reg := lit r#"{"parts":[{"id":"hero","variants":["faithful","scene-pause"],"impls":["plain"],"layers":["hero_copy"]},{"id":"hero.countdown","variants":["faithful","hidden-pause"],"impls":["mui","plain"]}],"presets":[]}"#
  let s (q : String) : Json := Json.mkObj [("registry", reg), ("search", .str q)]
  [("a declared layer option is accepted", s "?fwl=hero_copy:c"),
   ("fw and fwl together, fw first in the canonical form", s "?fwl=hero_copy:c&fw=hero:scene-pause"),
   ("an unknown layer is refused", s "?fwl=nope:c"),
   ("a layer entry without options is refused", s "?fwl=hero_copy"),
   ("a layer id with a character outside okChar is refused", s "?fwl=hero_c/py:c"),
   ("a percent-encoded layer id is refused, not decoded", s "?fwl=hero%5Fcopy:c"),
   ("an encoded fwl key is refused, not decoded", s "?f%77l=hero_copy:c"),
   ("an encoded fwl key and value are refused", s "?%66wl=hero%5Fcopy:c"),
   ("two layers keep URL order in the canonical form", Json.mkObj [("registry", declReg), ("search", .str "?fwl=nav_earn:s,hero_copy:c")]),
   ("a plus in a layer id is refused, not read as a space", s "?fwl=hero+copy:c"),
   ("an encoded fw entry next to a good fwl is refused whole", s "?fw=hero:scene%2Dpause&fwl=hero_copy:c")] ++
  Fw.Parts.FootprintData.layerDecls.map fun (_, l, _) =>
    (s!"declared layer {l}", Json.mkObj [("registry", declReg), ("search", .str s!"?fwl={l}:c")])

def named (_ : Unit := ()) : List (String × String × String × List (String × Json)) := [
  ("ops", "lean-first", "ops.leanFirst", leanFirstCases),
  ("console", "reviewFeedback", "console.reviewFeedback", reviewFeedbackCases),
  ("console", "steps-topics", "console.stepTopics", stepTopicsCases),
  ("land", "render-guard", "console.landRenderGuard", renderGuardCases),
  ("console", "review", "console.review", reviewCases),
  ("console", "report", "console.report", reportCases),
  ("console", "reviewPreview", "console.reviewPreview", reviewPreviewCases),
  ("console", "layers", "console.compose", layersCases),
  ("console", "layers-search", "console.buildsSearch", layersSearchCases)]

def withOp (op : String) : Json → Json
  | .obj kvs => .obj (kvs.insert "op" (.str op))
  | j => j

def respond (op : String) (req : Json) : Json :=
  match Json.parse (Fw.Wire.handleLine (withOp op req).compress) with
  | .ok (.obj kvs) => .obj (kvs.erase "id")
  | .ok j => j
  | .error e => Json.mkObj [("error", .str s!"reply is not JSON: {e}")]

def fileText (op : String) (cs : List (String × Json)) : String :=
  String.join (cs.map fun (name, req) =>
    (Json.mkObj [("name", .str name), ("request", withOp op req), ("response", respond op req)]).compress ++ "\n")

def dir : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ops"

def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let mut stale := 0
  for (sub, stem, op, cs) in cases.map (fun (op, cs) => ("ops", op, op, cs)) ++
      extra.map (fun (sub, op, cs) => (sub, op, op, cs)) ++ named do
    let p := root / ".." / "packages" / "contracts" / "golden" / sub / s!"{stem}.jsonl"
    if write then IO.FS.createDirAll (root / ".." / "packages" / "contracts" / "golden" / sub)
    let text := fileText op cs
    if write then
      IO.FS.writeFile p text
    else
      let cur ← try IO.FS.readFile p catch _ => pure ""
      if cur != text then
        IO.println s!"ops golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/OpsGolden.lean)"
        stale := stale + 1
  let n := cases.foldl (fun a c => a + c.2.length) 0 + extra.foldl (fun a c => a + c.2.2.length) 0 +
    named.foldl (fun a c => a + c.2.2.2.length) 0
  IO.println s!"ops golden: {cases.length + extra.length + named.length} files, {n} cases, {if write then "written" else s!"{stale} stale"}"
  return stale

end Fw.Wire.Ops.Golden
