# Phone feel kit: blind A/B/C ratings on the real phone under the Serious pin

Task `phone-feel-kit`, branch `worktree-wf_a4f669cd-67c-1`. Status of every claim is marked MEASURED (the dry run below),
CONFIRMED (Lean theorem or test) or INFERRED.

## What it is

One held process, `device-cli.mjs feel start`, serves the arms on one LAN origin, holds the Serious thermal pin and
takes small local commands. The person on the phone never sees a flag name.

| Part | File | Status |
|---|---|---|
| Session spec: arms, blind order, rating, reducer, theorems | `lean/Fw/Device/Feel.lean` | CONFIRMED (lake build, check.sh) |
| Golden the TS follows | `packages/contracts/golden/device/feel.jsonl` (23 lines, `--check` in check.sh) | CONFIRMED |
| Pure TS core (order, reducer, next/rate/status) | `packages/measure-webkit/src/device-feel.mjs` | TS stand-in of Feel.lean, checked against the golden |
| I/O glue (control server, pin gate, arm switch, start/stop) | `packages/measure-webkit/src/device-feel-run.mjs` | glue, no decision logic except `makeGate`, which calls `pinGate` |
| CLI | `device-cli.mjs feel start | next | rate | status | stop` | |

Order (CONFIRMED in Lean): the three same-look arms (`base`, `v2-proved`, `v2-proved+glint-hold`) are shown twice each,
as `order = rot 3 r ++ rot 3 (r+1)` with `r = seed % 3`. Never the same arm twice in a row; each round shows every arm
once; labels go by first appearance, so the letters are always `A B C B C A`. Four labelled look-change arms follow
(`L1`..`L4`: `morph.end.nobounce`, `morph.stage`, `morph.geom`+`morph.tween:geom-timed`, `platform.sweep:layer-sweep`).

Rating: a whole number 1 (rough) to 5 (smooth) per visit. A cell compares an arm's visit to `base`'s visit of the same
round: better if at least 1 above, worse if at least 1 below, else same. The arm verdict is felt better / same / worse
when both visits agree, otherwise mixed. A look-change arm has one visit; its score is compared against both `base`
scores. `feel stop` prints the verdict table with arm names (the lead reads it, the person does not); `status` hides names
unless `--reveal`.

The Serious pin gate (`pinGate` from `device-thermal-pin.mjs`): `feel next` refuses to open an arm unless the owner is
alive, the phone is unlocked and the reported state equals the target. It waits (poll 5 s, bound 180 s) while the state
rises, and refuses on Critical, a locked phone, a dead owner or a fall below the target after the first go.

## Dry run (MEASURED, one device run, 2026-10-29, seed 0, 8 min from pin start to the cleared pin, of which 3 min 16 s was the drive script)

| Reading | Value |
|---|---|
| Pin before | Nominal |
| Pin reached Serious | about 8 s after the owner started, held for all 10 arms (every `next` re-read Serious) |
| Pin after stop | owner gone, clear confirmed, state read Fair; end verdict `cleared` |
| Arms opened | 10 of 10 (A B C B C A L1 L2 L3 L4), each rated with a synthetic 3 (no real feel claimed) |
| `hydrated` / hydration errors | true / none on all 10 |
| `configHash` equals expected hash | yes on all 10 |
| `search` applied | yes, the `?fw=` of each arm read back |
| scrollY at open | 0 on all 10 |
| docH / maxY | 6042 / 5267 on 9 arms; 6781 / 6006 on L2 (`morph.stage` adds 739 px) |
| viewport | 430 x 775 |
| Processes after stop | none of mine (session, owner, proxy) |

All dry-run verdicts are `same` because every score was 3, not a result.

INFERRED from L2: `morph.stage` changes the page height, so it is a layout change as well as a look change; the user
should expect a longer page on L2.

Defect fixed: `feel stop` answered "fetch failed" because the session closed the control server with
`closeAllConnections` before the reply was written; the client then stopped the owner itself, so the pin still cleared.
The server now closes after the reply is flushed (`startControl().close`, test "a stop that closes the control server still gets its
reply"). The dry run's stop used the old code; the fix is covered by the unit test only, not a device run (limit).

## Commands for the lead

Build the arms once from `apps/site` (a local build, not a measurement):

```
node scripts/build.mjs --engine aot --configs none \
  --config '?fw=engine.scroll:unthrottle,hero.exit:threaded' \
  --config '?fw=engine.scroll:unthrottle,hero.exit:threaded,platform.glint:hold-freeze' \
  --config '?fw=morph.end.nobounce:on' --config '?fw=morph.stage:on' \
  --config '?fw=morph.geom:on,morph.tween:geom-timed' --config '?fw=platform.sweep:layer-sweep'
```

Session, from `packages/measure-webkit`, phone connected and unlocked, no other `device-cli.mjs` running:

```
node src/device-cli.mjs feel start --site ../../apps/site/dist/aot --dir .local/phone/<date>-feel --pin Serious --seed <n> --fresh   # run_in_background
node src/device-cli.mjs feel next   --dir .local/phone/<date>-feel     # opens the next arm, prints label and what to do
node src/device-cli.mjs feel rate <label> <1-5> --dir .local/phone/<date>-feel
node src/device-cli.mjs feel status [--reveal] --dir .local/phone/<date>-feel
node src/device-cli.mjs feel stop   --dir .local/phone/<date>-feel     # prints the table, clears the pin, waits for the exit
```

`--resume` continues a stopped or crashed session's state; `--fresh` starts over. Recovery if the session process was
killed: `node src/device-cli.mjs pin-stop --dir .local/phone/<date>-feel`.

## Limits

- n = 2 visits per same-look arm; look-change arms have one visit and are labelled, not blind.
- Serious is induced (the developer thermal condition), not real heat; the reported state is what the page can feel, not
  a measured temperature.
- Scores run 1 to 5 per visit, not a smoother/same/worse pick, because the Lean cell rule compares numbers against base; the margin (1) is a stated constant (INFERRED).
- Seed rotation: A is first and last (positions 0 and 5), so use a different seed per session; seeds 0, 3, ... repeat.
- `kill -9` of the session leaves the pin set; `pin-stop` clears it, and the next `feel start` also recovers it.
- A run with arms missing from the build refuses at start and names them.
- No CI run: the kit needs the phone. The verdict comes from the user, relayed by the lead.
