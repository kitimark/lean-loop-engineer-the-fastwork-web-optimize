# End-of-page variants: inventory, new proposals and a same-look set

Research run 2026-10-26 (three read-only agents: inventory, proposals from engine source, adversarial critique).
Scroll mechanism designs are in research/notes/2026/10-26-end-scroll-designs.md. Effects below are INFERRED until a
task measures them.

## Kept proposals (ranked by expected WebKit end-of-page gain per unit of work)
| rank | variant | change | mechanism (source) | look |
|---|---|---|---|---|
| 1 | platform.sweep:layer-tiled (revision of layer-sweep, not a new flag) | the layer copies the original's repeat tiling (two tiles wide, translate -2w to 0) and takes the device-pixel-snapped word width once per resize | removes the WebKit 35/255 t=0 difference, which is the original's own repeat seam (MEASURED in 10-2x-platform-sweep-layer.md), and the Chromium snapped dest rect (background_image_geometry.cc:392-401,754@f842f52, INFERRED) | target E at bound 12 |
| 2 | platform.glint:hold-freeze | the two 5 s repeating SMIL `<animate>` per dash become ramp-only animates with fill=freeze between ramps (3 of 5 segments hold a value) | an active non-`<set>` SMIL animation ticks every frame even when the value holds (WebKit SVGSMILElement.cpp:1074-1088@862f17d; Chromium svg_smil_element.cc:1285-1301@f842f52); glint-off took WebKit z5000 Paint 54-66 to 40-44 | E (values equal at every t) |
| 3 | platform:faded-pause | when the morph fade reaches 0, pause the platform section's animations (data-fw-scene=paused, SMIL pauseAnimations) and seek them on resume | Chromium still records paint for an effectively invisible layer (paint_layer_painter.cc:168-191@f842f52); base end 60-119 PaintImage 240 disappears with the sweep off (run 40237508223) | E if no descendant escapes the opacity group |
| 4 | platform.entries:settle | commit the after-phase of finished entry animations to the existing static rule | covered by the running task fill-release-platform | E (blur(0) to none needs a pixel check) |

Dropped: nav.hitTest:io-band (removing one reader frees no pass while another reader flushes, ledger row
`observers`), engine.scene:cv-far (covered by hero:scene-pause; not same-look), platform:shrink-timeline (no WebKit
end gain: the phone band already pins the card, platform:mq no-win), morph.end:identity-filters (duplicates
morph.panel:rest).

## Same-look end-of-page set (flags proved or measured as wins, class E/Q)
engine.scroll:unthrottle (already the preset), nav.hitTest:hit-skip + nav.hitTest:elements-skip (compose),
morph.columns:idle-none (phone layers 136 to 124, backing 111 to 94 MB), hero:scene-pause (WebKit win). Add a kept
proposal only after its own CI pass. Look changes for the user's review: platform.sweep:layer-sweep (or layer-tiled),
morph.mount touch-first / open-once / overscroll-lock, morph.end.release, and the scroll designs.

## Conflicts (one writer per element and property)
layer-sweep vs layer-tiled (same layer); sweep offscreen-pause vs faded-pause (both write data-fw-scene on #platform:
one writer must OR them); glint hold-freeze vs glint offscreen-pause vs faded-pause (same SMIL clock); entries settle
vs faded-pause (resume seek must skip settled entries); fade-threaded vs morph.tween waapi vs faded-pause (same
--morph-fade writer).
