// What wakes the spool drain: file events under the spool dir, the health index and the session workflow dirs, then a safety
// tick (Lean `Fw.Console.ReconcileSched.dropped_event_drained`: a dropped event waits at most one tick plus two passes). Each
// wake is one full sweep (stat of every file), so a coalesced or dropped event name costs nothing. Glue; no decisions.
import { dirname, join } from "node:path";
import { Trigger } from "../trigger.ts";
import { Watches, type Target } from "../watch.ts";
import { workflowWatchTargets } from "./workflow.ts";

/** The drain's safety period: a missed file event is drained at most this late (plus the pass itself). */
export const DRAIN_SAFETY_MS = 10_000;

export function startDrainWatch(storeDir: string, run: () => Promise<unknown>, onError: (e: unknown) => void, safetyMs = DRAIN_SAFETY_MS,
  extra: () => Target[] = () => workflowWatchTargets(dirname(storeDir))) {
  const trigger = new Trigger({ run, safetyMs, settleMs: 50, onError });
  const targets = (): Target[] => [
    { path: join(storeDir, "spool"), recursive: false, accept: (n) => n.endsWith(".jsonl") },
    { path: storeDir, recursive: false, accept: (n) => n === "health.jsonl" },
    ...extra(),
  ];
  const watches: Watches = new Watches(targets, (t) => {
    if (t.discover) watches.sync(); // a new session, `workflows` or spool dir: watch it too
    trigger.poke();
  });
  watches.sync();
  trigger.start();
  const safety = setInterval(() => watches.sync(), safetyMs);
  safety.unref();
  trigger.request(); // the first sweep, as the old timer's first tick did
  return { trigger, watches, stop: () => { clearInterval(safety); trigger.stop(); watches.close(); } };
}
