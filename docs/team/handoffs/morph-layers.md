# morph-layers handoff (branch worktree-wf_f4cccc1d-568-2)

State: round 3 done. Code at f59fdbf0 (pushed as ci/morph-layers); the commit after it adds only this handoff and the
note. `shift-dormant` stays out of v2-proved (decisions row `no-link`); the preset change is the lead's call.

Verified:
- Lean `Fw/Parts/MorphMountDormant.lean`: `dormant`, `animated_eq_mountO`, `animStart_eq_mountStart`; `Panel` model
  (timed history, mount bit), `armD`, `visSame_dormant` from `Hidden`; `clock_not_phaseFree` (shift's PhaseFree is
  false for the countdown); `phaseFree_of_untimed`; `layerize` / `Absorbed` / `layers_dormant_eq` / `census_dormant_eq`.
- Site: tracks get `animation-name: none` and the morph countdown driver is held (`HeroCountdown` `hold`) while dormant.
  Round 2 also held the digit shape; WebKit gate 39322625340 failed morph.countdown counts at touch-rm because of it.
- Probe dumps (Chromium, swipe-v1, artifact `chromium-counts-rewrite-r1`, `layers.json` + `phase.json`):
  ci/morph-layers-probe2 runs 39322953386 / 39322959537 / 39322964853 and ci/morph-layers-probe3 runs 39325816743 /
  39325823271. Dormant layers equal faithful in frames 0-116; interval and track animations start in frame 116 as in
  faithful; shift starts the 1 s interval at load.
- Counts at f59fdbf0 (runs 39325709978..39325741608): dormant layers = faithful; recalc 0 / -1; layout -3 / -4;
  elementCount +216 / +202 (swipe / touch medians).
- Gate 39325704868: every morph.* cell passes on both engines; only non-pass cell is the pre-existing WebKit
  phone-rotation `matchMedia =Lean` NC.
- `sh lean/scripts/check.sh`, apps/site typecheck+test, ci-paths and land-inputs tests green.

Open:
- Lead: replace `morph.mount:shift` with `shift-dormant` in v2-proved (recommended), or keep both off.
- The probe code (layer dump, interval recorder) lives only on the probe branches; not committed here.
- Extra restyled elements in frames 10-116 of both early-mount arms are not attributed.

Conventions: arms are told apart by `meta.search`. Reductions are described in the note (Attribution, Measurements).
Read first: research/notes/2026/10-20-morph-layers.md (Answer, Real-dump checks), then MorphMountDormant.lean.
