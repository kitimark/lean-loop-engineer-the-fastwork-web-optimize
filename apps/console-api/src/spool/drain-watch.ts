// What wakes the spool drain: file events under the spool dir, the health index and the session workflow dirs, then a safety
// tick (Lean `Fw.Console.ReconcileSched.dropped_event_drained`: a dropped event waits at most one tick plus two passes; the
// wake bound of a pass start is `wakeStartBound`). A watch opened by `sync` is followed by a poke, so a file written before
// the watch existed is seen by the sweep it starts. Each
// wake is one full sweep (stat of every file), so a coalesced or dropped event name costs nothing. Glue; no decisions.
import { dirname, join } from "node:path";
import { Trigger } from "../trigger.ts";
import { Watches, type Target } from "../watch.ts";
import { workflowWatchTargets } from "./workflow.ts";

/** The drain's safety period: a missed file event is drained at most this late (plus the pass itself). */
export const DRAIN_SAFETY_MS = 10_000;

/** Pokes within this window share one request. */
export const DRAIN_SETTLE_MS = 50;

/** The latest a poke at `t` (or a safety tick, with `settle` the period) starts the pass that answers it: the settle window plus
 *  the length of the pass running at `t`. TS STAND-IN of Lean `Fw.Console.ReconcileSched.wakeStartBound` (theorems
 *  `poke_wake_le`, `tick_wake_le`), checked on `golden/console/wake-bound.jsonl`. */
export const wakeStartBound = (settle: number, pass: number): number => settle + pass;

/** The latest that pass is done, when it runs at most `pass` (Lean `wakeDoneBound`, `poke_done_le`). */
export const wakeDoneBound = (settle: number, pass: number): number => settle + 2 * pass;

export function startDrainWatch(storeDir: string, run: () => Promise<unknown>, onError: (e: unknown) => void, safetyMs = DRAIN_SAFETY_MS,
  extra: () => Target[] = () => workflowWatchTargets(dirname(storeDir))) {
  const trigger = new Trigger({ run, safetyMs, settleMs: DRAIN_SETTLE_MS, onError });
  const targets = (): Target[] => [
    { path: join(storeDir, "spool"), recursive: false, accept: (n) => n.endsWith(".jsonl") },
    { path: storeDir, recursive: false, accept: (n) => n === "health.jsonl" },
    ...extra(),
  ];
  const watches: Watches = new Watches(targets, (t) => {
    if (t.discover) watches.sync(); // a new session, `workflows` or spool dir: watch it too, then the poke sweeps what was there before
    trigger.poke();
  });
  watches.sync();
  trigger.start();
  // a watch opened here saw none of the files that exist already: ask for a sweep after it
  const safety = setInterval(() => { const n = watches.size; watches.sync(); if (watches.size > n) trigger.request(); }, safetyMs);
  safety.unref();
  trigger.request(); // the first sweep, as the old timer's first tick did
  return { trigger, watches, stop: () => { clearInterval(safety); trigger.stop(); watches.close(); } };
}
