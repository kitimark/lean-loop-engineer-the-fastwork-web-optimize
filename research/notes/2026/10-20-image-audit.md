---
id: 2026-10-20-image-audit
kind: note
title: "Image audit: natural against drawn size in the hero, morph and people regions, what WebKit does with them, and a drawn-size arm"
status: draft
created: 2026-10-20
authors: [agent:measure-engineer]
topics: [images, webkit, measurement, lag]
---

# Image audit (2026-10-20)

User question: do unoptimized images cause the Safari lag (hero cards leaving, end of the page)? This note answers with
a measured table, the WebKit source on decoding and repainting, and an arm that serves images at drawn size. It claims no
frame time: nothing here was timed.

RESULTS_PLACEHOLDER

## WebKit: what happens to a large image (source @862f17d)

`WC` = `Source/WebCore`, read in `.cache/upstream/WebKit@862f17d`. Files outside the sparse pin were read with `curl` at the
same sha (`ImageFrame.cpp`, `BitmapImageDescriptor.cpp`, `WebKit/Shared/CacheModel.cpp`,
`WTF/Scripts/Preferences/UnifiedWebPreferences.yaml`). The Lean statement of each fact is `lean/Fw/Engine/WebKitImage.lean`.

| # | Claim | Status | Source |
|---|---|---|---|
| D1 | A still image is "large" when its decoded size (w*h*4) is over 500 KB; animated over 100 KB | CONFIRMED | `WC/platform/graphics/BitmapImageSource.cpp:349-353` |
| D2 | Large-image async decoding is on by default (WebKit, WebCore, legacy) | CONFIRMED | `WTF/Scripts/Preferences/UnifiedWebPreferences.yaml:4565-4574`; history: bug 165177 (2016-11-30) split the setting, bug 174451 (2017-07) turned async off after the first tile paint |
| D3 | A small image decodes synchronously. A large one decodes synchronously when its renderer is in the viewport and asynchronously when it is not, or on the first paint of an element that never painted an image | CONFIRMED | `WC/rendering/RenderBoxModelObject.cpp:256-320` (default mode at 271-286, large-image case at 315-319), `WC/rendering/RenderElement.cpp:1799-1804` (visible = inside the window clip rect) |
| D4 | A synchronous decode builds the whole image at its native size (subsampled only by D6); an asynchronous decode builds a thumbnail at min(native area, drawn area) | CONFIRMED | `WC/platform/graphics/cg/ImageDecoderCG.cpp:676-698` (`CGImageSourceCreateImageAtIndex` against `CGImageSourceCreateThumbnailAtIndex`); drawn size from `WC/platform/graphics/BitmapImage.cpp:94-106` |
| D5 | A decoded frame is kept and reused by every later draw whose options it is compatible with: a full-size frame serves any request, a sized one serves requests up to its largest side; asking for a finer subsampling level than the cached one decodes again | CONFIRMED | `WC/platform/graphics/DecodingOptions.h:67-88`, `WC/platform/graphics/ImageFrame.cpp:113-124`, `BitmapImageSource.cpp:563-620` |
| D6 | iOS and macOS subsample only images of 5 Mpx or more: the maximum level is the first whose area is under 5*1024*1024, and it is 0 for anything smaller. Every image of the lag regions is under that, so none is subsampled | CONFIRMED | `WC/platform/graphics/BitmapImageDescriptor.cpp:229-280` |
| R1 | A draw hands the whole decoded frame to CoreGraphics (`CGContextDrawImage` with the destination rectangle); WebCore keeps no scaled copy. That CoreGraphics resamples the frame on each such draw is INFERRED (closed source); iOS marks decoded images `kCGImageCachingTemporary` so CG may cache what it drew, and what it caches is not visible in WebKit | CONFIRMED (hand-over) / INFERRED (per-draw resample) | `WC/platform/graphics/cg/GraphicsContextCG.cpp:283-433`, `ImageDecoderCG.cpp:699-709` |
| R2 | Interpolation quality: images whose layout size changes between paints are drawn at low quality for 500 ms; a transform leaves the layout size alone and draws at default quality | CONFIRMED | `WC/rendering/ImageQualityController.cpp:45-46,136-205` |
| R3 | A layer whose filters the compositor can run (no reference filter) paints without them: a change of `filter` is a layer property update (`FiltersChanged`), not a repaint of the content. A filter that cannot be composited paints the layer through the software filter | CONFIRMED | `WC/rendering/RenderLayer.cpp:1055-1070`, `WC/rendering/RenderLayerBacking.cpp:868-871`, `WC/platform/graphics/ca/GraphicsLayerCA.cpp:925-945` |
| R4 | `backdrop-filter` composites its layer | CONFIRMED | `WC/rendering/RenderLayerCompositor.cpp:3981-3984` |
| M1 | Decoded size counts against the memory cache. The primary-browser cache model has 128 MB in total on a device with at least 2 GB (Safari's model is INFERRED) | CONFIRMED (table) / INFERRED (model) | `WebKit/Shared/CacheModel.cpp:88-119` |
| M2 | Over the live capacity, the cache destroys the decoded data of live images, least recently used first, but not an image used less than 1 s ago; a destroyed image decodes again at its next draw | CONFIRMED | `WC/loader/cache/MemoryCache.cpp:53,209-233,275-328`, `WC/loader/cache/CachedImage.cpp:651-660` |

What the facts give, and what they do not:

- **Where a large photo costs.** At first paint in the viewport (D3) the whole image is decoded on the main thread at its native
  size (D4); a photo drawn small pays decode time in proportion to its natural pixels, once (D5). Below the fold the same photo
  decodes at the drawn size on a worker (D4), so the cost moves to the scroll that brings it into view only if a full-size frame is
  needed again. CONFIRMED for the branches, INFERRED for their cost.
- **Per frame.** An image in a layer that only has its opacity, transform or composited filter animated is not repainted (R3, and
  the compositor rule of `Fw.Engine.WebKit`), so its natural size does not enter a frame's cost; the layer's backing store
  has the drawn size. A repaint (a layout change, a software filter, a style change with a repaint difference) draws the
  frame again and, if CoreGraphics resamples (R1, INFERRED), reads natural pixels. The cost term is therefore natural pixels times
  the number of repaints, and whether any of the lag's frames repaint an image is the question this note does not answer.
- **Memory.** Decoded bytes are w*h*4 whatever the file size (M1), so a small JPEG can be a large frame; the audit's decoded column is that
  number.

Lean (`Fw.Engine.WebKitImage`): `modeFor` with one theorem per branch (`small_sync`, `large_firstPaint_async`,
`large_visible_sync`, `large_hidden_async`), `decodedPx` (`sync_decodes_all`, `async_decodes_drawn`), `no_subsampling_under_limit` (D6),
`repaints` with one theorem per kind of effect, and `cost` = decoded pixels times (1 + repaints when a repaint resamples)
with `cost_sync_resample`, `cost_async_resample`, `cost_mono_nat`, `cost_mono_reps`, `sync_saving` (the saving of a copy is
exactly the pixel difference times (1 + repaints)), `drawn_copy_le` and `async_source_equals_copy` (an image already decoded
asynchronously gains nothing from a copy). Premises: D1-D6 and R3 are source facts; **P-resample (R1) is INFERRED** and is the
only premise on which a frame cost depends.
