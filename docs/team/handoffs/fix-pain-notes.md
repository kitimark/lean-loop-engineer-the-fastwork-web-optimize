# Handoff: fix-pain-notes (branch worktree-agent-ab529d4b942d003d9, CI ref ci/fix-pain-notes)

## Result
Gate runs (breakpoint-gate, parts=pain.notes, both engines): 39083069444, 39083596374 (2 of 3 used). WebKit passes. Chromium note x/y: 145 probes -> 16 probes (sweep desktop-1512-320-1512 stops #15 @860 and #42 @861).
Real port difference, not gate-settle's "resize-lag"; it is a geometry cell, so the body-colour finding does not apply.

## Lean row
| cell | property | original value + source | cause class | fix |
|---|---|---|---|---|
| pain.notes note x/y/w/h | position after a resize | the whole Pain section is registered with the scene scheduler `dE(check,{deferRendering:true,element:section,rootMargin:"150% 0px"})` (nodes/2.DyWL8TcE.js:4736, 2681-2783); out of range it gets `data-start-selling-render=deferred` -> `content-visibility:auto` (assets/2.gBuqKVzi.css:11760-11763); a skipped subtree gets no ResizeObserver callbacks, so the original keeps the last layout (1512 percentages seen at 1280: x 308.5, ours was 249.9) | missing behaviour (scene gate + content-visibility skip) | Lean `PainNotes.sceneActive`, `Render.after`, `resize_follows_scene`, `deferred_never_observes`; scene.ts + notes.module.css; goldens sceneActive/renderObserves |

## Changed
lean/Fw/Parts/PainNotes.lean, PainNotesGolden.lean, golden/parts/pain.notes.jsonl; apps/site/src/parts/pain.notes/{scene.ts,scene.test.ts,logic.ts,index.tsx,driver.ts,notes.module.css}. Also: scroll check only while the scene is active (JS 2672); the narrow-list change lays out in the same task with flushSync (JS 4709).

## Open (outside this dir)
Remaining 16 probes: everything below the hero is 120 px lower than the original at every stop (people.card section y 901 orig vs 1021 ours; commission, pain canvas likewise; the gate does not flag it). At 860 the original canvas top is 2192.5 (< 900*2.5 = 2250: in range, rendered); ours 2312.5 (out of range, still skipped, notes 0x0). Fix the 120 px between hero/morph.countdown and people (hero or App.tsx stand-in, not pain.notes) and this cell should flip. The carrying element is not found yet.
