// TS STAND-IN of Lean `Fw.Console.ReconcileSched` (theorems pending_le_one_*, answered_after_*, wait_le_two),
// checked against packages/contracts/golden/console/reconcile-sched.jsonl.
export type Sched = { started: number; finished: number; pending: number };

export const init: Sched = { started: 0, finished: 0, pending: 0 };

export const req = (s: Sched): Sched =>
  s.finished < s.started ? { ...s, pending: Math.min(1, s.pending + 1) } : { ...s, started: s.started + 1 };

export const fin = (s: Sched): Sched => {
  if (!(s.finished < s.started)) return s;
  return s.pending === 0 ? { ...s, finished: s.finished + 1 } : { started: s.started + 1, finished: s.finished + 1, pending: 0 };
};

export const ticket = (s: Sched): number => s.started;
