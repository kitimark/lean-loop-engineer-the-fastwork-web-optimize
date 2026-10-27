# Phone morph push, end of the page (2026-10-27)

Verdict under `Fw.Device.PhoneArms.pushLabel` (needs >= 3 visits per arm, interleaved, one thermal state). MEASURED: no push visit ran.

| arm | visits n | p95 | p99 | max | frames > 50 ms | style | layout | paint | rAF | label |
|---|---|---|---|---|---|---|---|---|---|---|
| base | 0 | - | - | - | - | - | - | - | - | unresolved |
| morph.geom:on | 0 | - | - | - | - | - | - | - | - | unresolved |
| morph.geom:on + morph.tween:geom-timed | 0 | - | - | - | - | - | - | - | - | unresolved |
| morph.stage:on | 0 | - | - | - | - | - | - | - | - | unresolved |

Loss: the push driver's XCUITest run reaches the test body on the phone, then waits forever at the first accessibility snapshot.
The push is a fixed XCUITest swipe (forward, hold, back, hold, forward), not the user's recorded finger path.
