# WebKit recount at one commit (task webkit-recount)

Date: 2026-10-27. Branch `worktree-wf_60f31c57-bb5-1`, CI branch `ci/webkit-recount` at sha 60ee5c3 (every arm and the base measure this one sha). All numbers MEASURED on the webkit-sim lane (iOS Simulator on a GitHub macOS VM, `--no-route`, target rewrite, 430 wide). Reader: `packages/measure-webkit/src/offscreen-webkit-cli.mjs` (zones z4500 = scroll y 4500 to 4950, z5000 = 5000 to the end cut, finish = 4500 to the end cut, whole = 0 to the end cut; Lean verdict with minVms 3; a side with fewer than 3 distinct VM ids is undecided, whatever the pass rule reads).

## Base (pooled, stated)

The base is pooled from several runs at the same sha, 3 distinct VM ids, 6 passes: retry run 40360267706 r1, first run 40349554405 r2 and r3 (first-run r1 lost at Determinism sessions: Safari opened no tab, stall watchdog at 748 s). Retry r2 of 40360267706 is a sensitivity extra and is not in the pool. All arms below are read against this one base.

## Answer

| arm | verdict per zone (z4500, z5000, finish, whole) | VMs base+arm | run ids |
| --- | --- | --- | --- |
| platform.marquee:probe-off | noGain, noGain, noGain, noGain (decided) | 3+3 | 40428340750 |
| hero.exit:contain | noGain x4 and noGain in 3 hero windows (decided) | 3+3 | 40372868559 |
| platform.entries:probe-off | undecided x4, n=3+2 (pass rule reads gain) | 3+2 | 40418142290 |
| platform.sweep:layer-sweep | undecided x4, n=3+2 (pass rule reads gain, Paint only) | 3+2 | 40366658003, 40408733016, 40441397213 |
| platform.entries:fill-release | undecided x4, n=3+2 (pass rule reads noGain) | 3+2 | 40349566685, 40364461242 |

Three of five arms stay undecided: the VM loss rate on this lane (load1 hundreds on 3 CPUs, see `10-2x-wk-sim-hang.md`) left them below 3 VMs. Their counts are listed as readings; no claim of gain or no-gain is made. Accepted limits of this task: at most one more dispatch (spent on layer-sweep, r3 lost again), no phone run, no seeking.

## platform.marquee:probe-off

Decided: noGain in all four zones.

Run 40428340750 (3 of 3 VMs good). Base and arm sides are VM counts after the `+`; counts are per scroll window, range over passes (base / arm).

| zone | steps | passes | VMs | verdict | pass rule only | Paint | Layout | RecalculateStyles | Composite | FireAnimationFrame | ObserverCallback |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| z4500 | 10 | 6+6 | 3+3 | noGain | noGain | 132-154 / 105-176 | 41-71 / 40-68 | 49-60 / 46-63 | 20 / 20 | 53 / 53 | 10-14 / 10-14 |
| z5000 | 5 | 6+6 | 3+3 | noGain | noGain | 59-66 / 47-67 | 26-34 / 16-35 | 32 / 21-34 | 10 / 10 | 22 / 22-26 | 4 / 4 |
| finish | 15 | 6+6 | 3+3 | noGain | noGain | 196-220 / 171-241 | 68-105 / 61-103 | 81-92 / 67-96 | 30 / 30 | 75 / 75-79 | 14-18 / 14-18 |
| whole | 105 | 6+6 | 3+3 | noGain | noGain | 1206-1304 / 1203-1346 | 596-651 / 597-655 | 649-678 / 637-693 | 209 / 209 | 664-667 / 666-671 | 61-66 / 62-67 |

## hero.exit:contain

Decided: noGain in all four zones and in the three hero windows (below).

Run 40372868559 (3 of 3 VMs good). Base and arm sides are VM counts after the `+`; counts are per scroll window, range over passes (base / arm).

| zone | steps | passes | VMs | verdict | pass rule only | Paint | Layout | RecalculateStyles | Composite | FireAnimationFrame | ObserverCallback |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| z4500 | 10 | 6+6 | 3+3 | noGain | noGain | 132-154 / 130-149 | 41-71 / 47-59 | 49-60 / 47-56 | 20 / 20 | 53 / 53 | 10-14 / 10 |
| z5000 | 5 | 6+6 | 3+3 | noGain | noGain | 59-66 / 55-67 | 26-34 / 22-34 | 32 / 30-32 | 10 / 10 | 22 / 22-23 | 4 / 4 |
| finish | 15 | 6+6 | 3+3 | noGain | noGain | 196-220 / 185-214 | 68-105 / 69-93 | 81-92 / 79-88 | 30 / 30 | 75 / 75-76 | 14-18 / 14 |
| whole | 105 | 6+6 | 3+3 | noGain | noGain | 1206-1304 / 1246-1356 | 596-651 / 593-638 | 649-678 / 650-684 | 209 / 209 | 664-667 / 667-668 | 61-66 / 62-69 |

Hero windows (`results/hero-relayout-boundary/read-webkit.mjs` reduction, 6+6 passes, 3+3 VMs, all noGain, every counter same):

| window | scroll y | Layout base / flag | RecalculateStyles base / flag | Paint base / flag |
| --- | --- | --- | --- | --- |
| hero-exit | 0-1000 | 140-160 / 139-158 | 139-153 / 136-154 | 362-430 / 367-424 |
| after-exit | 1001-2500 | 171-202 / 166-195 | 154-170 / 157-168 | 259-347 / 287-358 |
| whole | 0-5200 | 596-651 / 593-638 | 649-678 / 650-684 | 1206-1304 / 1246-1356 |

## platform.entries:probe-off

Undecided in all four zones: n = 3+2 VMs, below minVms 3. Loss: run 40418142290 r1 (Safari terminate over 20 s, simctl reboot failed, exit 4; no session file). The pass rule alone reads gain; a reading, not a verdict.

Run 40418142290 (r2, r3 good, r1 lost). No second dispatch: the one extra run went to layer-sweep. Base and arm sides are VM counts after the `+`; counts are per scroll window, range over passes (base / arm).

| zone | steps | passes | VMs | verdict | pass rule only | Paint | Layout | RecalculateStyles | Composite | FireAnimationFrame | ObserverCallback |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| z4500 | 10 | 6+4 | 3+2 | undecided (n=3+2) | gain | 132-154 / 99-115 | 41-71 / 33-44 | 49-60 / 44-48 | 20 / 20 | 53 / 50-51 | 10-14 / 5 |
| z5000 | 5 | 6+4 | 3+2 | undecided (n=3+2) | gain | 59-66 / 50-55 | 26-34 / 18-25 | 32 / 21-31 | 10 / 10 | 22 / 21-26 | 4 / 1 |
| finish | 15 | 6+4 | 3+2 | undecided (n=3+2) | gain | 196-220 / 149-170 | 68-105 / 51-69 | 81-92 / 65-79 | 30 / 30 | 75 / 71-77 | 14-18 / 6 |
| whole | 105 | 6+4 | 3+2 | undecided (n=3+2) | gain | 1206-1304 / 1204-1233 | 596-651 / 558-581 | 649-678 / 616-641 | 209 / 209 | 664-667 / 655-659 | 61-66 / 45-47 |

Pass-rule differing counters: z4500 RecalculateStyles, Paint, FireAnimationFrame, ObserverCallback, ScheduleStyleRecalculation less; whole adds Layout and InvalidateLayout less. Composite same (209).

## platform.sweep:layer-sweep

Undecided in all four zones: n = 3+2 VMs. Only two distinct VM ids (r1, r2) ever produced a session; r3 was lost in both retries. The pass rule alone reads gain, Paint less only; a reading, not a verdict.

Runs 40366658003 r1, 40408733016 r1 and r2, 40441397213 r1 (4 sessions, 8 passes). Lost: 40366658003 r2 (inspector dead, simctl shutdown ETIMEDOUT) and r3 (warm-up Runtime.evaluate timeouts); 40408733016 r3 (Timeline.stop timeout); 40441397213 r3 (simctl shutdown ETIMEDOUT, Determinism sessions) and r2 (cancelled at artifact upload, no files). Base and arm sides are VM counts after the `+`; counts are per scroll window, range over passes (base / arm).

| zone | steps | passes | VMs | verdict | pass rule only | Paint | Layout | RecalculateStyles | Composite | FireAnimationFrame | ObserverCallback |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| z4500 | 10 | 6+8 | 3+2 | undecided (n=3+2) | gain | 132-154 / 66-105 | 41-71 / 46-67 | 49-60 / 42-59 | 20 / 20 | 53 / 53 | 10-14 / 10-12 |
| z5000 | 5 | 6+8 | 3+2 | undecided (n=3+2) | gain | 59-66 / 30-48 | 26-34 / 23-33 | 32 / 24-32 | 10 / 10 | 22 / 22-26 | 4 / 4 |
| finish | 15 | 6+8 | 3+2 | undecided (n=3+2) | gain | 196-220 / 112-143 | 68-105 / 72-100 | 81-92 / 66-90 | 30 / 30 | 75 / 75-79 | 14-18 / 14-16 |
| whole | 105 | 6+8 | 3+2 | undecided (n=3+2) | gain | 1206-1304 / 1032-1180 | 596-651 / 609-675 | 649-678 / 632-673 | 209 / 209 | 664-667 / 665-671 | 61-66 / 62-68 |

## platform.entries:fill-release

Undecided in all four zones: n = 3+2 VMs after the one allowed retry. Loss: r1 lost at Determinism sessions in 40349566685 and again in 40364461242 (event loop blocked in a host lsof call, stall watchdog at 731 s). The pass rule alone reads noGain.

Runs 40349566685 (r2, r3) and retry 40364461242 (r2 repeats the same VM id, counts once). Base and arm sides are VM counts after the `+`; counts are per scroll window, range over passes (base / arm).

| zone | steps | passes | VMs | verdict | pass rule only | Paint | Layout | RecalculateStyles | Composite | FireAnimationFrame | ObserverCallback |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| z4500 | 10 | 6+4 | 3+2 | undecided (n=3+2) | noGain | 132-154 / 145-161 | 41-71 / 60-71 | 49-60 / 55-63 | 20 / 20 | 53 / 53 | 10-14 / 10 |
| z5000 | 5 | 6+4 | 3+2 | undecided (n=3+2) | noGain | 59-66 / 65-67 | 26-34 / 26-29 | 32 / 32-34 | 10 / 10 | 22 / 22 | 4 / 4 |
| finish | 15 | 6+4 | 3+2 | undecided (n=3+2) | noGain | 196-220 / 212-227 | 68-105 / 88-100 | 81-92 / 87-97 | 30 / 30 | 75 / 75 | 14-18 / 14 |
| whole | 105 | 6+4 | 3+2 | undecided (n=3+2) | noGain | 1206-1304 / 1208-1302 | 596-651 / 615-630 | 649-678 / 664-689 | 209 / 209 | 664-667 / 663-667 | 61-66 / 62-65 |

## Follow-ups (below the pinned unit)

- The three undecided arms need a 3rd distinct VM id. r3 died in every layer-sweep attempt (Determinism sessions, simctl ETIMEDOUT); entries:probe-off and fill-release lost r1. A retry with `--runs 3` and a quiet queue, or the Mac Safari lane, would settle them.
- Files: `results/webkit-recount/*.json` (reader `--json` output per arm; `hero-exit-contain.json` for the windows), ledger rows `platform.entries.probe-off`, `platform.marquee.probe-off`, `platform.sweep.layer-sweep`, `platform.entries.fill-release`, `hero.exit.contain` (field `webkit`).
