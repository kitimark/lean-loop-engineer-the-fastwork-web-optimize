# Handoff: fix-people-webkit

Base: integration head 30734ae (ci/integrate-ports). No port code changed: all three WebKit tails are sampling effects, not port bugs. No gate run (nothing to re-gate; the lead waived extra runs).

## Verdicts
- Rounding premise (float Length +1/64 px at heights >= 1024): REFUTED for all cells. card and deck differ by far more than 1/64. people.o differs by exactly 1/64 at 932x430 (height 430, not >= 1024) and is a CSS height transition tail: MEASURED locally in Playwright WebKit 1.64.1, both arms settle to 38.828125px (fresh load and after 932/430 rotation, 1.5 s); at 400 ms the original itself reads 38.8125.
- people.card / people.deck: per-frame lerp tails (rate 0.22 / 0.2, snap 0.0008). The sweep reads them a fixed wall time after the previous stop's mount preparation scrolled away and back; value depends on frame cost. The original is heavier per frame (INFERRED: local original showed a 300 ms frame gap and half the lerp steps per ms of the rewrite); the rewrite has converged to the same target. Class for all: gate misreads it. Suggested shared change (not made): wait until the lerp is quiet (value unchanged over N frames) or until `getAnimations()` is empty AND two frames after the last height change, in `page.mjs waitResize`.
- Side finding (hero owners, not mine): people.card rect y at 900px height is 949 (original) vs 1069 (rewrite), 152 px more at 1201 touch; not compared by the gate, so the hero track is probably taller in the rewrite.

## Table (original values restated; source file = snapshot/site-pretty/_app/immutable/...)
| cell | property | original value | source in snapshot | port old value | class | formula |
|---|---|---|---|---|---|---|
| people.card sweep desktop #16@721x900, #22@481x900, touch #1,#2,#3 | section `--future-shrink` | 0.03264 / 0.00126 / 0.18185 / 0.09085 / 0.08989 | nodes/2.DyWL8TcE.js:11296-11333 (lerp 11309-11310, coverage 11285-11290) | 0 | gate misreads | s' = s + (t - s)*0.22 per frame (reduced: 1); s' = t when abs(t - s') < 0.0008; t = smoothstep(cov); cov = 0 if cardBottom >= 0.85*vh, 1 if <= 0.35*vh, else (0.85*vh - cardBottom)/(0.5*vh) |
| people.card touch #1,#3 | card border-*-radius (4 corners) | 5.819152px | assets/2.gBuqKVzi.css:2358-2418 (radius = 32px * shrink) | 0px | gate misreads | radius = 32 * s |
| people.card touch #1,#3 | section `--future-shrink-scale` | calc(1 - .083333 * 0.18184851588671536) | same rule (scale = 1 - 0.083333*s) | calc(1 - .083333 * 0) | gate misreads | 1 - 0.083333*s |
| people.deck touch #3@1201x900 | sticky `--profile-scale` | 1.199 | nodes/2.DyWL8TcE.js:10799-10802, 10938-10950 | 1.220 | gate misreads | r' = r + (x - r)*0.2, snap 0.0008, written toFixed(3); x = b + (1-b)*ease(y/shrinkRange) while y < 1.45*vh, else 1; b = min(1.22, max(1, innerWidth-112)/max(1, chromeW-248)) |
| people.deck touch #3 | shell w / h, panel w | 950.996 / 983.375 / 931.808 | derived (box includes the transform) | 967.460 / 1000.400 / 947.940 | gate misreads | box = base * scale (base = 793.0 at 1201) |
| people.o phone-rotation #3@932x430 | o and stage `height` | 38.828125px (settled in both) | assets/2.gBuqKVzi.css:2460-2476 (height 1.0417em, transition height 0.92s cubic-bezier(0.22,1,0.36,1)) | 38.8125px (in-flight read) | gate misreads | h = floor64(1.0417 * fs); fs = clamp(36px, 4vw, 48px) = 37.28px at 932 (36px at <= 640 via the phone rule) -> 38.828125 |

## Method (local debug, not a result)
Scratch probes (probe*.mjs in the session scratchpad): original served from snapshot/site, rewrite from apps/site/dist/aot; WebKit via packages/gate-breakpoints playwright-core. Shrink tail after an instant scroll away and back lasted about 1.1 s in the original and about 0.5 s in the rewrite.
