# phone-thermal-check: the thermal state gates the phone session, and morph.countdown:strip measured

## Answer

- **morph.countdown:strip measured on the phone (MEASURED, one phone, one new session of 4 visits: base, base, strip, base; no stall, no fault, 1 attempt each).**
  Counts and frames are the same as the base in every zone (hero Layout 193 vs 194, Paint 502 vs 517, FunctionCall 422 vs 422; Lean label
  counts same, frames same). The census shows the one effect: layers at the five scroll stops fall from 110, 116, 136, 142, 124 (base) to 38, 42, 64,
  69, 52 (strip), a "beats" cell at every stop, with the backing store the same except +2 MB at y 0 (41.6 vs 39.5 MB, "worse"). That agrees in
  direction with the Simulator result (a trade: finish layers 128 to 56, runs 39775198022 vs 39775174615). The earlier stall (phone-end-counts, three tries)
  did not recur; the harness differs in two ways (wip.mjs follows `Target.didCommitProvisionalTarget`; every block is gated on the thermal state),
  so which of them mattered is not separated (INFERRED: the thermal gate, because a base visit also lost a scroll pass to a `runAsync` timeout, below).
- **Every 7 minute visit ends at Serious thermal state (MEASURED, 4 of 4 visits): Nominal at the start, Fair or Serious by the first lane
  readout, Serious at the end.** The battery temperature stayed at 33 C for the whole session (80 percent, not charging), so it did not see any of it:
  a battery-temperature rule alone would never have stopped a block. The phone returned to Nominal after 8 to 16 minutes (Serious at 12:14, Fair 12:19 to
  12:22, Nominal 12:22; second wait 12:36 to 12:52; third 13:03 to 13:19, all UTC), so the 5 minute cool of the old plan was too short every time.
- **The stop rule worked as the Lean theorems say (MEASURED): at most one pass ran after each trigger, and each next block started only after 300 s of Nominal
  readings.** Four blocks of one visit each; 41 thermal readings; the session took 85 minutes of wall time against 33 planned.
- **A scroll pass failed once inside base visit 1 (`runAsync timed out`, the harness retried from a fresh load; the visit took 526 s, not 400).** The
  base cells with low counts (hero Layout 145, Paint 343) all come from that visit's third pass (same index in all cells, MEASURED), cause INFERRED:
  the retried pass counts a shorter run. This widens the base spread (hero Layout 53, Paint 197) and makes the "same" labels for counts less strict than
  the identical cells suggest; the layer and byte cells are not affected. The stall is therefore not strip-specific (INFERRED link to the earlier
  strip stall: the phone was Serious in both).

## Thermal source (CONFIRMED by the probe below; meanings INFERRED)

- iOS does not give the thermal state to a USB client directly. `xcrun xctrace record --instrument 'Thermal State' --device <id> --all-processes
  --time-limit 1s --output X.trace --no-prompt` records it, and `xcrun xctrace export --input X.trace --xpath
  '/trace-toc/run[1]/data/table[@schema="device-thermal-state-intervals"]'` exports rows like
  `<thermal-state id="4" fmt="Nominal">Nominal</thermal-state>`; later rows may carry `<thermal-state ref="4"/>` (the parser resolves the id). One read takes about 7 s.
- **Gotcha (MEASURED):** xctrace exits 13 ("Timed out waiting for device to boot") unless CoreDevice lists the phone as connected; running
  `xcrun devicectl device info lockState` first makes it work. The reader does that, and reads `result.passcodeRequired` from the same call (false
  observed; true is read as locked, INFERRED).
- Apple's ProcessInfo.ThermalState (https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum): nominal, fair, serious, critical.
  The fetch returned only the title; the meanings (fair: slightly elevated, serious: system reduces performance, critical: needs cooling at once) are from
  memory (INFERRED).
- Battery: `AverageBattVirtualTemp` from the device readout, an integer, unit C (INFERRED). It is a proxy for the battery pack, not the SoC.
- iOS 27.0.1 on the one phone; other models and versions are not covered.

## Rules in Lean (`Fw.Device.Thermal`, `Fw.Device.PhoneArms`)

| rule | proved | golden |
|---|---|---|
| gate: go only at Nominal, battery under first + 2 C, readable, unlocked | `gate_go_iff`, `gate_serious`, `gate_critical`, `gate_fair` | `device/thermal.jsonl` |
| a block runs at most one pass after the trigger; never starts at Serious or Critical | `passesRun_le_stop`, `blockPasses_le_serious`, `blockPasses_one_after_trigger` | same |
| resume only at Nominal after a 300 s gap; pause ends at 3600 s | `resume_needs_go`, `resume_needs_gap`, `resume_too_soon`, `pauseOver_iff` | same |
| usbReset (log evidence or off the list while on the bus), wait up to 180 s | `usbVerdict_*`, `classify_*`, `usbWait_*` | `device/phone-arms.jsonl` |
| foreign proxy: refuse on 9221/9222 or an attaching proxy | `proxyVerdict_*`, `proxiesClear_*` | same |
| hand reset only as a lead note; fault list never shrinks | `resetPlan_*`, `handReset_append_only`, `appendOnly_iff` | same |

TS stand-ins (no Lean, tested): `wip.mjs` `targetStep` (provisional target swap), the xctrace/ps/lsof/log parsing, `runBlock` orchestration.
`wip.mjs` fix: a provisional page target is not the command target until `Target.didCommitProvisionalTarget`; commands sent to the replaced page fail at once
with `swapped: true` instead of waiting 15 s (WebKit Target.json and TargetManager.js@862f17dc, whose frontend buffers provisional messages until the commit).

## Accepted limits

- One phone, one session. Scripted scrolling does not move the Safari toolbar. If strip stalls again the Playwright WebKit CI check is a follow-up task.
- The thermal state is read as iOS exposes it through the xctrace instrument, at block start and after each visit, not continuously; a state that rises and
  falls inside a visit is only seen through the lane readouts (Nominal, Fair, Serious, Serious).
- The thermal state is Serious at the end of every visit, so frames cells (over34 base 0 to 176) mix throttled and unthrottled periods; counts and the census are not clock dependent.
- Nothing here separates the effect of the harness change from the effect of the thermal pauses on the strip stall.

## Provenance

- Raw files (local only, never committed): the worktree's `.local/phone/2026-10-25-thermal/` (`raw/` per-visit counts and frames, `state.json` with the 41 readings,
  `run.log`, `thermal-before.json` Nominal 12:06 UTC, `thermal-after.json` Serious 13:32 UTC right after the last visit, `reduced/summary.json`, `reduced/tables.md`).
- Site build: `apps/site/dist/aot` built in this worktree (config hash base fc809c0b9227ef69, strip 610bc60b95bddcdb, both matched by every visit).
- Command: `node src/device-cli.mjs arms-run --only morph.countdown:strip --site ../../apps/site/dist/aot --dir <raw> --blocked <file> --all`, then `arms-reduce`.
