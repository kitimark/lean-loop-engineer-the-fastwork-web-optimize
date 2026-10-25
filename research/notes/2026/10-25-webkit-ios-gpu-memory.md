# WebKit on iOS: how much layer memory may one flag add?

Question: what GPU memory budget B should the resource verdict (`lean/Fw/Engine/ResourceVerdict.lean`) hold a flag's
layer backing to, and how does WebKit size that backing? Source: WebKit 862f17dcae0aace47ea0ec16e209d960abfd553c
(`862f17d` below). Tags: CONFIRMED (source cited), INFERRED (reasoned), MEASURED (run cited).

## Answer

- B = 210 MiB = 220,200,960 bytes (`budgetB`, INFERRED). That is a quarter of the 840 MiB jetsam fallback, and at most
  half of the 448 MiB conservative-policy threshold at that fallback (`budgetB_quarter`, `conservative_fallback`,
  `budgetB_le_half` in `lean/Fw/Engine/Resource.lean`).
- The phone base peaks at 197,145,405 bytes, about 90 % of B (MEASURED, results/phone/2026-10-25-end-counts). So a
  flag has about 23 MB of headroom before its verdict turns `overBudget`.
- One layer's backing is w·h·DPR²·4 bytes, or whole 512-device-px tiles once a side passes 1280 CSS px
  (`layerBytes`). A layer outside the coverage rect, with detaching allowed and no animation pin, holds no bytes
  (`detached_zero`).

| quantity | value | status | source |
|---|---|---|---|
| jetsam fallback when the limit query fails | 840 MB | CONFIRMED | `WTF/wtf/AvailableMemory.cpp:89-97@862f17d` |
| RAM size seen by WebKit | min(kernel RAM, jetsam limit), rounded up to 128 MB | CONFIRMED | `AvailableMemory.cpp:140-151`, `RAMSize.cpp:44-47@862f17d` |
| MB | 1024² bytes | CONFIRMED | `WTF/wtf/StdLibExtras.h:148-150@862f17d` |
| base threshold | min(3 GB, RAM size) | CONFIRMED | `WTF/wtf/MemoryPressureHandler.cpp:374-375@862f17d` |
| iOS conservative / strict fraction | 0.5 / 0.65 of the base | CONFIRMED | `MemoryPressureHandler.cpp:46-48,150-162@862f17d` |
| conservative threshold at the fallback | 896 MB / 2 = 448 MB | CONFIRMED (arithmetic on the rows above) | `conservative_fallback` |
| footprint past a threshold sets the policy | Conservative, then Strict | CONFIRMED | `MemoryPressureHandler.cpp:165-171@862f17d` |
| compositing policy under pressure or warning | Conservative | CONFIRMED | `WebCore/rendering/RenderLayerCompositor.cpp:705-718@862f17d` |
| tile coverage under pressure | visible rect only (no margin) | CONFIRMED | `WebCore/platform/graphics/ca/TileController.cpp:501-502@862f17d` |
| tile coverage otherwise | visible rect plus one tile margin | CONFIRMED | `TileController.cpp:504-505@862f17d` |
| tiled above (iOS) | 1280 CSS px × page scale; 1024 at low memory | CONFIRMED | `WebCore/platform/graphics/ca/GraphicsLayerCA.cpp:100-103,4853-4856@862f17d` |
| tile side | 512 device px (tile rects are scaled by contents scale) | CONFIRMED | `TileController.h:58`, `TileGrid.cpp:70,145-147,277-278@862f17d` |
| cap on one tiled layer | 156 MB | CONFIRMED | `GraphicsLayerCA.cpp:114-115@862f17d` |
| bytes per pixel | RGBA8 4; RGBA10 4 opaque, 5 non-opaque; RGBA16F 8 | CONFIRMED | `WebCore/platform/graphics/ContentsFormat.h:48-69@862f17d` |
| buffers per backing store | up to 3 (front, back, secondary back) | CONFIRMED | `WebKit/Shared/RemoteLayerTree/RemoteLayerBackingStore.h:253-255@862f17d` |
| pixel format from contents format | BGRX8/BGRA8, RGB10/RGB10A8, RGBA16F | CONFIRMED | `RemoteLayerBackingStore.mm:271-291@862f17d` |
| freed-buffer caches | IOSurface pool 64 MB, layer pool 48 MB | CONFIRMED | `WebCore/platform/graphics/cg/IOSurfacePool.h:89`, `ca/LayerPool.cpp:40@862f17d` |

## Why B is 210 MiB (INFERRED)

The phone's real jetsam limit is not readable from the page, so B starts from the fallback WebKit itself uses. Past
the conservative threshold WebKit switches the compositor to its conservative policy and cuts tile coverage to the
visible rect. Both change what the page looks like mid-scroll. Keeping layer backing to at most half that threshold
leaves the other half for the heap, decoded images, fonts and the freed-buffer pools. B is one Lean constant: change
`budgetB` and the golden and every verdict follow, and `win_mono_budget` shows that raising B never turns a win into a
non-win.

## Limits

- `layerBytes` counts one buffer at 4 bytes per pixel. A non-opaque RGBA10 layer takes 5, and a layer that is
  repainting holds up to 3 buffers, so the model is a lower bound on live bytes by up to 1.25 × 3 (INFERRED).
- The 840 MB fallback applies only when the jetsam query fails. A device with a larger limit has a higher threshold, so
  B is conservative there (INFERRED).
- The freed-buffer pools are caches the system can reclaim. B does not count them (INFERRED).

## Refuted claims, dropped

Earlier drafts claimed iOS thresholds of 1.5 / 1.95 GB, a conservative compositing check on `backface-visibility`,
that WebKit only logs memory pressure, a 4096² canvas limit and a 384 MB canvas cap. None of these is in the source at
862f17d, and the model uses none of them.
