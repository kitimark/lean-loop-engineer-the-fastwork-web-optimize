# phone-thermal-pin: a session that holds the phone at Serious, and what the clear really does

## Answer

- **The pin works (MEASURED, one phone, iOS 27.0.1).** `arms-run --pin Serious` induced Serious from Nominal, read it back at all five readings of a two-visit block
  (block start, between the frames lane and the counts lane, and after each visit; every one `go`, reason `onTarget`), and ran two base visits (292 s each).
  A short probe from Nominal read Serious 8 s after the owner started.
- **The premise "the condition ends when the owner process ends" is false (MEASURED).** An owner (`pymobiledevice3 developer dvt condition set ThermalSerious --userspace`)
  ended by SIGTERM left Serious reported for 34 minutes (14:46 to 15:19 UTC); a `condition clear` from a new connection changed nothing for 7 minutes; a later
  `condition set ThermalFair` replaced the left-over Serious at once (Fair read) and then also stayed after SIGTERM. The CLI `set` command does not call clear on
  exit (`cli/developer/dvt/__init__.py` condition_set: `condition_inducer.set`, then `OSUTILS.wait_return()`, CONFIRMED in the pinned 11.44.0 source). The
  research.md and check.md statement "process exit tears it down" was INFERRED and is refuted.
- **What clears it (MEASURED):** `disableActiveCondition` sent on the connection that set the condition, then a reply from the phone. The owner is now a small
  program of ours (`OWNER_PY` in `src/device-thermal-pin.mjs`, the pinned library's own `ConditionInducer`): set, hold, on SIGTERM clear, `list` (a reply after the
  clear), print `fw-pin cleared pid=N`, exit. Reported state after such a clear: Serious fell to Fair after about 2 minutes and to Nominal about 11 minutes after
  the clear (first probe, 15:34 to 15:46), and fell to Nominal about 2 minutes after the clear when nothing had heated the phone (second probe, 15:48 to 15:50).
  After the 10 minute block with real load the reported state stayed Serious for the whole 5 minute read-back: INFERRED real heat, not the condition: the owner acknowledged its clear (`fw-pin cleared`, pin-owner.log), but no reading after 16:13:53 UTC shows the fall; the clear-to-Nominal read-back is MEASURED only in the probes (15:34-15:46, 15:48-15:50) (end `heatRemains`).
- **Induced Serious and real Serious look the same to the engine on this page (MEASURED), and neither differs from the mixed-state base.** Frames lane, 5 reps of
  about 390 frames each; counts lane totals over 3 passes (table below). The real-Serious base visits are the three base visits of phone-thermal-check (frames lane
  started Nominal and ended Serious, counts lane Serious); the pinned visits are Serious at every reading. Intervals and counts agree to run-to-run spread. The one
  difference is the longest single frame (76 and 68 ms pinned against 58, 58 and 60 ms real; n = 2 against 3, one frame per visit, not claimed as a difference).
  So for this page induced Serious is as good as real Serious as a measurement state and **we cannot show that Serious, induced or real, changes frame cadence or counts
  here** (WebKit keeps 60 fps at Serious, display rate under the cap unmeasured, INFERRED from the WebKit source in check.md). The pin fixes the reported state and the
  owner; it does not prove a throttle on this page.

| visit | state at readings | median ms | p99 ms | longest ms | over34 | over50 | RecalcStyle | Layout | Paint | TimerFire | FunctionCall |
|---|---|---|---|---|---|---|---|---|---|---|---|
| real 00 | N, S / S, S | 17 | 31 | 58 | 14 | 5 | 1940 | 1855 | 4812 | 39 | 4533 |
| real 01 | N, S / S, S | 17 | 32 | 58 | 14 | 5 | 1916 | 1810 | 4624 | 39 | 4444 |
| real 03 | N, S / S, S | 17 | 32 | 60 | 13 | 5 | 1940 | 1840 | 4743 | 37 | 4315 |
| pin 00 | S, S / S, S | 17 | 31 | 76 | 14 | 5 | 1942 | 1869 | 4787 | 40 | 4594 |
| pin 01 | S, S / S, S | 17 | 33 | 68 | 11 | 5 | 1940 | 1863 | 4785 | 42 | 4401 |

(readings: frames lane start, end / counts lane start, end; N = Nominal, S = Serious)

## What was built

| piece | where | checked by |
|---|---|---|
| target, observed, held, lock to go / wait / stop; no lane runs unless held and observed = target; Critical, above and below stop | Lean `Fw.Device.Thermal` section Pinned thermal state (`pinWhy`, `pinGate`, `pinGate_go_iff`, `pinGate_critical`, `pinGate_notHeld`, `pinGate_below_entered`) | golden `device/thermal.jsonl` `pin` lines, TS twin test |
| lanes of a visit, a visit counts only when pre, between-lanes and end are all `go`; a block is valid only if every state = target | `lanesRun`, `visitOk`, `blockValid` and their theorems | golden `lanes`, `visit`, `blockvalid` |
| stopping the owner: TERM first, KILL after 15 s, stuck after 5 s more; a signal only to the recorded pid and start time | `stopAct`, `mayKill` | golden `stop`, `kill` |
| session end: the condition is unset exactly when the owner is gone and acknowledged its own clear; else `unconfirmed` or `stuck` | `endVerdict`, `conditionSet`, `endVerdict_unset`, `endVerdict_set` | golden `end` |
| next run: stop a live owner, or one set-and-clear cycle for an owner that ended without an acknowledgement | `recoverAct`, `recoverAct_unacked` | golden `recover` |
| read-back after the clear: wait up to 300 s for the state to fall below the target | `clearWait`, `clearWaitMaxS` (raised from 180 after the 2 to 2.5 minute lag) | golden `clearwait` |

TS stand-ins (glue, no decision logic of their own): `ConditionOwner` spawn, `ps`, signals and log reading (`src/device-thermal-pin.mjs`); `pinnedSession` and the pinned
`runBlock` orchestration (`src/device-phone-pin.mjs`, `src/device-phone-run.mjs`); the rule that a session with no spawned process has nothing to clear.
The lane gate sits in `realDeps.visit` between the frames lane and the counts lane (follow-up 6 of phone-thermal-check).

## Corrections to research.md and check.md

- Stop with `kill -TERM`, never `-INT` (a background job ignores INT): kept. The owner handles TERM and INT, clears, and acknowledges.
- `--userspace` on every pymobiledevice3 command; `--native` is never used; `pymobiledevice3==11.44.0` via pipx. The owner program uses the same userspace tunnel
  (`userspace_tunnel.establish_userspace_rsd`), so it needs the venv python (`pipx environment --value PIPX_LOCAL_VENVS`, or `FW_PYMD3_PYTHON`).
- Profile id `ThermalSerious` CONFIRMED by `condition list --userspace` on this phone (group ThermalCondition: Fair, Serious, Critical).
- `condition list` shows `isActive` and `activeProfile` only for the asking connection (blank from a new connection while the phone reported Serious), so it is
  not a way to read whether a condition is set. The reported state is the only reader.

## Accepted limits

- One phone, one check session, three probes; the throttle magnitude on this page is not shown (above). A hot phone after real load stays at Serious after the clear
  (`heatRemains`); the next non-pinned session has to cool as before (the old gate and 300 s rule still apply there).
- An owner killed by SIGKILL, or one that died by itself, cannot confirm its clear: the end is `unconfirmed`, the run fails, and the next run (or `pin-stop --dir`) runs one
  set-and-clear cycle. Coexistence of the condition tunnel with the xctrace recordings held in all runs here (INFERRED for other readers); the
  ios_webkit_debug_proxy ran on 9461 beside the owner with no conflict seen.
- Battery temperature is recorded, not gated, in pinned mode.

## Open (follow-ups, not blockers)

- Session-trace theorem: `endVerdict_unset` holds by the definition of `conditionSet`; add a theorem over a session trace (phase, failure) -> end that never yields `conditionSet = true` without a stuck or unconfirmed failure.
- `held` in `src/device-phone-pin.mjs` is `owner.alive()` only; make it `alive() && readLog().includes('fw-pin held pid=N')` so the gap between spawn and the first set cannot count as held.
- `onSig` stops the owner and exits 130 with no read-back and no `pin.end` in `state.json`; write the stop and `conditionSet` note there.
- `--pin Fair|Serious` names the target; it has no default (tool doc).

## Provenance

- Raw files (local only): the worktree's `.local/phone/2026-10-25-pin/` (`raw/` visits and `state.json`, `probe/`, `probe-fair/`, `probe2/`, `run.log`, `cool*.log`).
  Real-Serious base: `.local/phone/2026-10-25-thermal/raw/` of the main checkout (`00-base`, `01-base`, `03-base`).
- Commands: `pin-probe --pin Serious --dir <d> --hold <s>`; `arms-run --only morph.countdown:strip --max-visits 2 --pin Serious --site apps/site/dist/aot --dir <raw>`.
  Site build config hash fc809c0b9227ef69 matched by both visits.
- pymobiledevice3 11.44.0 source read in the pipx venv: `cli/developer/dvt/__init__.py` (condition set, clear), `services/dvt/instruments/condition_inducer.py`
  (`disable_active_condition` has `expects_reply=False`), `osu/posix_util.py` `wait_return` (`signal.sigwait` on SIGINT and SIGTERM).
