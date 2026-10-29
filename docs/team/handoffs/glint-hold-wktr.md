# glint-hold-wktr handoff

State (branch `worktree-wf_c9b48971-43c-1`, push 1 at a84ebecd8 on `ci/glint-hold-wktr`, 2 of 3 pushes left; results not read yet when this was first written).

Built
- `lean/Fw/Device/GlintHold.lean`: predicted style recalcs per 100 frames under hold-freeze from the hold schedule (a frame that follows a SMIL tick recalcs at the base rate, one that follows none at the all-paused floor; `pred = f + (b-f)*q/n`), the verdict rule (unread, premise, no-contrast, uninformative, cuts as predicted, cuts less, cuts more, no cut), the overall rule over jobs, and the golden `packages/contracts/golden/device/glint-hold.jsonl` (check.sh job "device-glint-hold golden check"). Decided before any data.
- TS stand-in (temporary, replays the golden in `packages/measure-wktr/test/glint-hold.test.mjs`): `packages/measure-wktr/src/glint-hold.mjs`; glue `reportToCells`, `glintLines`, `src/glint-cli.mjs` (offline per-job and overall verdicts from result dirs).
- Probe: `mid-page.mjs` wraps `SVGAnimationElement.beginElement` (per dash svg, SMIL ms since the begin burst, `g` in frame records), arm variant `rs-<kind>-smil` (pause every svg timeline), `rs.wins` per window. Modes `glint-base-thr-off` and `glint-hold-thr-off` in `accel-cli.mjs` (pref OFF header, 5 s idle, 6 flips).
- Temporary wktr.yml edits (accel step modes, accel build `--config` for the geom pair with hold-freeze) must be reverted before the dry land.

Read first: the note `research/notes/2026/10-2x-glint-hold-wktr.md` once written, then the Lean file header.
Conventions: no local WKTR (no archive on this Mac); runs only via `pnpm -s fw ci push --branch ci/glint-hold-wktr --lanes wktr`; polls via `fw ci wait`.
