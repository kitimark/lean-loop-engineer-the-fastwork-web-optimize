# Preset gate triage: why `?preset=v2-proved` fails the Chromium breakpoint gate (2026-10-19)

Status tags: MEASURED = CI run cited; CONFIRMED = source read, file:line@HEAD (main 0f0e95a7); INFERRED = reasoning.
Scope: Chromium only (accepted limit; the WebKit arm of the preset is a follow-up). Unit of decision: each failing row.

## Runs (breakpoint-gate, workflow_dispatch on ci/preset-gate-triage, engines=chromium, sha 0f0e95a7)

| run | arm (FW_SEARCH, smoke log) | verdict | failing items (probes) |
|---|---|---|---|
| 39189945037 (earlier, sha 8a6b34ba, before morph-tween-inherit) | `?preset=v2-proved` | fail | hero.countdown `face` 64 vs 0; nav `actions` 1 vs 4, `bar` 1 vs 2; platform `--morph-fade` "1" vs "calc(1 - min(1, 0 / 0.55))" |
| 39197237678 | `?preset=v2-proved`, full universe 7056 readings | fail: 392 bad, 28 cells not ok | hero.countdown `face` 64 vs 0 (196); nav `actions` 1 vs 4 (196), `bar` 1 vs 2 (196); platform passes 14/14 |
| 39197247960 | `?fw=morph.mount:shift`, narrowed (morph.mount, hero.countdown, nav, platform) | fail | nav `actions` 1 vs 4, `bar` 1 vs 2 (116); morph.mount, hero.countdown, platform pass |
| 39197258964 | `?fw=hero.countdown:strip`, narrowed (hero.countdown, nav, platform) | fail | hero.countdown `face` 64 vs 0 (116); nav, platform pass |

Dispatches used: 3 of 4 (the earlier preset gate is not counted). The fourth was not needed.
Orig/rewrite order in the gate tables is original first. The 4 `commission` hysteresis items in 39197237678 are excused by Lean
`Fw.Gate.Exit.commission_resize_scope` (lean/Fw/Gate/Exit.lean:207; not a preset effect, no verdict weight).

## Per row

### 1. hero.countdown `face` count 64 vs 0, 14/14 columns: cause `hero.countdown:strip`
- Attribution MEASURED: the strip arm alone reproduces it (39197258964), the shift arm does not (39197247960).
- Mechanism CONFIRMED: apps/site/src/parts/hero.countdown/index.tsx:32-34 renders one `[data-strip]` node per digit in strip; the ten
  `[data-face]` nodes exist only in the else branch (index.tsx:41-45). The anchor `face` selects `[data-face]` (packages/gate-breakpoints/src/anchors.json:218-228,
  dims [], skipSets layoutDerived, skipProps transform), so the role is judged on its count alone.
- Visual or DOM-structural: DOM-structural only. Nothing else in the part fails (every other hero.countdown item passes in the strip arm), and
  Lean proves the picture is the same: `Fw.Parts.HeroCountdownOpt.strip_visSame` (lean/Fw/Parts/HeroCountdownOpt.lean:288; class E for every
  environment and instant) over `strip_digit_same` (:264) and `strip_glyph_same` (:206).
- Is the gate role count the right check for a same-visual variant? No. The item is `roleItems` (lean/Fw/Gate/Items.lean:314-326) with
  `countStatus` (lean/Fw/Gate/Compare.lean:321): a count must be equal and positive, for every variant. Neither `Items.lean` nor the four
  `Fw.Gate.Coverage.Exempt` reasons (Coverage.lean:42) knows about a variant that changes the element structure on purpose; a count is a
  structure check, `VisSame` is the picture check. There is no gate-side theorem that says "variant V is exempt from the count of role R".
- Recommendation: keep `hero.countdown:strip` in Λ, conditional on a new gate exemption proved in Lean (lead decides). Needed: a
  per-(part, variant) role map in `Fw.Gate.Items` (the `face` role is replaced by a `strip` role whose count must equal the digit count, and
  the face count is not judged) plus a theorem that the verdict of every other item is unchanged (like `partItems_skip_invariant`, Items.lean:647).
  The visual half is already proved (`strip_visSame`). Without that gate theorem: unlink, because the row fails 14/14.

### 2. nav `actions` 1 vs 4 and `bar` 1 vs 2, 14/14 columns: cause `morph.mount:shift`
- Attribution MEASURED: the shift arm alone reproduces it (39197247960); the strip arm passes nav.
- Mechanism CONFIRMED: `shift` mounts the morph panel at a still moment (apps/site/src/parts/morph.mount/index.tsx:107-125, `warmStill` after 150 ms, logic.ts:84-88);
  the gate loads at the top and waits, so the panel is mounted at probe time (the faithful arm mounts it only at an intersect or push, so it is absent). The nav hosts the
  panel as its last child (apps/site/src/parts/nav/index.tsx:154 `{children}`; panel root `<div data-fw="morph-panel">`, morph.panel/index.tsx:50-56, with children `backdrop`,
  `veil`, `center` at :59-63). The rewrite selectors are structural: `bar` is `[data-fw="nav"] > div` (anchors.json:836-838) and `actions` is `[data-fw="nav"] > div > div` (:872-874).
  So bar = bar div + panel root = 2, actions = actions div + 3 panel children = 4. The numbers match the measured 2 and 4 (INFERRED from the count arithmetic; the elements were not listed).
- Visual or DOM-structural: DOM-structural; the nav's own boxes and styles pass. The visual claim is `Fw.Parts.MorphMountOpt.visSame_mount` (lean/Fw/Parts/MorphMountOpt.lean:187),
  with premises `PhaseFree` (:146) and `HiddenBefore` (:155), and `mountV_of_mountO` (:102). Both premises are definitions with no instance proved for the concrete panel
  (no other Lean file uses them); that gap is the visual-diff lane's job, not this gate's.
- Is the count the right check? The count is right, the selector is wrong: the roles `bar` and `actions` mean the nav's own elements, and the selector also catches the
  hosted part `morph.panel`. This is a gate-spec defect and not a same-visual-variant problem; the same over-match exists in the faithful arm after a real mount and was never seen because the gate never scrolls.
- Recommendation: keep `morph.mount:shift` in Λ with no Lean exemption; fix the two anchors to exclude the hosted panel (for example
  `[data-fw="nav"] > div:not([data-fw="morph-panel"])` and `... > div:not([data-fw="morph-panel"]) > div`; anchors.json is hand-written data, packages/gate-breakpoints/src/anchors.json,
  read by Items.lean). Then re-run the shift arm (one dispatch). Not done here (the task writes only this note).

### 3. platform `--morph-fade` "1" vs "calc(1 - min(1, 0 / 0.55))", 10/14 columns: cause `morph.tween:waapi`, already fixed
- Attribution: the single-flag waapi arm was not dispatched (not needed). MEASURED by before/after: the row fails in 39189945037 (sha 8a6b34ba) and passes 14/14 in 39197237678 (0f0e95a7)
  with the same preset; `git diff 8a6b34ba 0f0e95a7 -- apps/site` changes only morph.tween (index.tsx, waapi.logic.ts, waapi.golden.test.ts). Neither the strip nor the shift arm fails platform.
- Mechanism CONFIRMED: `preparePlatform` writes `FADE_CSS` (waapi.logic.ts:47, morph.tween/index.tsx:111-113) as an inline custom property; unregistered it computes to the substituted text, the original's
  driver writes a number (driver.ts:56). Fix: `--morph-fade` registered as `<number>`, inherits, initial 1 (waapi.logic.ts:30-36, commits f1dd18a5, efa737cf; Lean `origInheritsOf` / MT-R).
- Visual or structural: neither; a serialization of the computed custom property. The computed value is a number again.
- Recommendation: keep `morph.tween:waapi` in Λ; nothing left to prove for this row.

## Remaining flags
The other preset flags (engine.scene, engine.scroll, morph.columns, morph.countdown, nav.hitTest, pain.notes, people.card) have no failing row in 39197237678.

## Follow-ups (below the unit of decision)
- Gate-side variant role map plus theorem (row 1) and anchor selector fix (row 2), then re-gate the preset (one dispatch).
- WebKit arm of the preset.
- Instance `PhaseFree` and `HiddenBefore` for the concrete morph panel.
