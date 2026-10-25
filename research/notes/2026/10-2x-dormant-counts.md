# morph.mount:shift-dormant against the faithful mount, counted per zone on WebKit and Chromium

Question: the ledger row `morph.mount.shiftDormant` had WebKit `unknown` (only `shift` was measured on the Simulator) and
Chromium `trade`. What does the flag change in Layout, RecalculateStyles, FunctionCall, Composite, layer count and backing
memory per zone (hero, finish, rest), per engine, against the base? Tags: CONFIRMED, INFERRED, MEASURED.

## Answer

| engine | hero | finish | rest | engine verdict |
|---|---|---|---|---|
| WebKit Simulator, 3 VMs x 2 passes per arm | no-win | no-win | no-win | **no-win** |
| Chromium counts lane, 3 runs per arm | win (one cell) | no-win | no-win | win, small (hero only) |

- MEASURED. WebKit: not one of the 18 decided cells (6 metrics x 3 zones) beats or loses to the base. Base run
  40196215217 and flag run 40196227509 are the same commit (cb4bec8), profile swipe-v1, 430 x 775 viewport.
- MEASURED. Chromium: one cell beats, hero `trace.FunctionCall` 2188 / 2184 / 2184 for the base against 2140 / 2144 /
  2140 for the flag (-2.0 %, base spread 4). The other 17 cells are equal or differ by a step under 1 % (hero
  `UpdateLayoutTree` 788 against 787 is clear of a spread of 0 but is 0.1 %, so the rule counts it as no step). Base run
  40171939293 and flag run 40171969469, both at 1fac415, profile swipe-touch-v1.
- The rewrite default runs the **`faithful`** mount, not a shifted one. CONFIRMED: the preset `original` sets no flag
  (`apps/site/src/registry/presets/original.json`), and an unset part takes the first variant of its `part.json`
  (`apps/site/src/registry/resolve.ts:84`), which for `morph.mount` is `faithful`
  (`apps/site/src/parts/morph.mount/part.json:10`). So the base arm above is `faithful`, and shift-dormant is judged
  against it.

## Per zone, WebKit (decided cells; mean of the 3 VMs, sums over 2 passes)

| zone | Layout | RecalculateStyles | FunctionCall | Composite | layers | backing MB |
|---|---|---|---|---|---|---|
| hero | 370 to 387 (+4 %) | 353 to 367 (+4 %) | 1096 to 1355 (+24 %) | 118 to 118 | 441 to 444 | 251.5 to 254.8 |
| finish | 159 to 177 (+11 %) | 167 to 181 (+8 %) | 506 to 524 (+4 %) | 65 to 67 | 538 to 535 | 507.7 to 500.9 |
| rest | 709 to 698 (-1 %) | 794 to 790 (-1 %) | 1905 to 1962 (+3 %) | 240 to 240 | 276 to 275 | 202.5 to 202.5 |

Every cell is `same`: the arm's VMs are never clear of the base's by more than the base's VM-to-VM spread (for example
hero FunctionCall: base 999 to 1163, spread 164, arm 1205 to 1604, the arm's lowest VM is 42 above the base's highest,
less than the spread). The direction is up in the hero and finish zones for Layout, RecalculateStyles and FunctionCall,
the layer count and Composite are equal, and backing memory moves by at most 1.3 %. Paint, FireAnimationFrame,
EventDispatch and paint area are shown in the golden and decide nothing (quarantined classes or reported only).
Per-VM values: `packages/contracts/golden/parts/dormant-counts.jsonl` (field `base`, `armVms`, `spread`).

Cross-check, INFERRED (other commit, so not the pinned unit): flag run 40171948671 at 1fac415 against the same base is
also `same` in every cell of every zone (hero Layout 390 / 406 / 366 against 373 / 374 / 364).

## Mechanism and why

- The base (`faithful`) mounts the panel at the original trigger, so it never carries the panel's timed state before
  then. shift-dormant mounts the panel early and keeps it asleep: the marquee tracks have no animation and no countdown
  driver until the original trigger. CONFIRMED (ledger row, Lean `Fw.Parts.MorphMountDormant.dormant_iff`,
  `visSame_dormant`).
- So the two arms differ in one thing during the swipe, the early-mounted, invisible panel (about +200 resolved
  elements, ledger MEASURED on Chromium). By construction it removes no work and adds no layer: a sleeping track is not promoted
  (`layers_dormant_eq`, `census_dormant_eq`), so the model predicts equal layers and at most a little more style, layout or
  script work. MEASURED here: layers and Composite equal on WebKit in every zone, Chromium `census.layers` 24160 against
  24159 / 24160 in the hero.
- WebKit has nothing to win: the layer cost that `shift` adds (9 drawing layers per frame, ledger) is already absent
  in the base. shift-dormant only gives it back, so its best case on WebKit is equal to the base, and the data show
  that. The higher hero FunctionCall on WebKit is inside the spread, and the lower one on Chromium is 2 %; the early
  mount's script work is a candidate for both, but no run isolates it (OPEN, not a mechanism claim). No other cell
  moves, so neither is a layout or layer effect.
- Lean why, `lean/Fw/Parts/DormantCounts.lean`, golden `packages/contracts/golden/parts/dormant-counts.jsonl` replayed by
  `check.sh` (`--check`): a win needs a cell where every arm sample lies below every base sample by more than the base
  spread and by at least 1 % (`zoneOutcome_win_cell`, `judge_beats`); a trade needs both a winning and a losing cell
  (`zoneOutcome_trade_cells`); a no-win is no winning cell and a losing or equal one (`outcomeOf_noWin_iff`); a cell with
  fewer than two base samples is unresolved (`cellVerdict_unresolved_short`); the three zones add up to each sample's total
  (`value_split`). The data decide `no-win` for WebKit in all three zones.

## Method

- One sample is one Simulator VM (its two passes summed) or one Chromium counts run. Bins of 500 px, zones by
  `Fw.Device.Session.zoneOf` on each sample's own viewport and last scroll position (the last position differs by VM: 5231
  or 5267). The census states (scroll 0, 1500, 3000, 4500, last) fall in hero, hero, rest, finish, finish.
- Reducer (glue): `results/dormant-counts/reduce.mjs`; reduced input `results/dormant-counts/zones.json`, which
  `Fw.Parts.DormantCounts.gen ["--from", path]` copies into the first line of the golden. `--check` (the check.sh job)
  decides again from that line, so it reads only the golden. The verdicts come from Lean only.
- Run 40196227509 had its filing (`fw run --from-run`) still pending when this was written; its three VM artifacts (r1 to
  r3, all success) were read from `gh run download`, so n is 3. The other arms are read from the filed store. Earlier
  attempts of this run lost Simulator VMs to the Determinism-session stall (owned by macos-vm-evidence); the final
  attempt has all three.

## Ledger and limits

- `research/findings/ledger.json` row `morph.mount.shiftDormant`: webkit cell `no-win`, chromium cell restated (win, hero
  only), one `notes` row (task dormant-counts). The row's earlier Chromium `trade` came from the resource model (about +200
  resolved elements), a prediction the counts do not show (UpdateLayoutTree 788 against 787 in the hero).
- The resource verdict (`resource-redecide`, trade on both engines) is not changed by this note; its inputs are CPU
  predictions and the phone rows, this note is Simulator and Chromium event counts. The phone rows are all `same`
  (`10-25-phone-end-counts.md`).
- `part.json` has no `visClass` for `shift-dormant`, so the row needs no `visClass` field and the flag is not in the
  look-change class.
- Limit: the Chromium verdict uses the runs filed at 1fac415, not cb4bec8. The Chromium census is summed over frames, so
  its layer cells are large totals, not layer counts.
