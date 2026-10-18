// Workflow stage pattern (task workflow-salvage): a builder agent that exits without a structured result gets its
// worktree committed as WIP and a handback event, then the stage goes on to verify. Rules and proofs:
// lean/Fw/Ops/Salvage.lean; golden packages/contracts/golden/ops/salvage.jsonl.
// TS STAND-IN: `decide` mirrors Fw.Ops.Salvage.decide until the op ops.salvage is wired into fwcore (Wire.lean was
// outside this task's write list); the golden test pins it. Replace with the fwcore call then. Everything else is glue.

export type Facts = { task: string; hasResult: boolean; dirty: boolean; ahead: number };
export type Out = { salvage: boolean; commit: boolean; allowEmpty: boolean; handback: boolean; state: string; message: string };

const idOk = (t: string): boolean => /^[a-z0-9-]+$/.test(t);

export function decide(f: Facts): Out {
  if (f.hasResult) return { salvage: false, commit: false, allowEmpty: false, handback: false, state: "", message: "" };
  return {
    salvage: true,
    commit: true,
    allowEmpty: !f.dirty,
    handback: true,
    state: f.dirty ? "dirty" : f.ahead > 0 ? "committed" : "empty",
    message: `WIP salvage ${idOk(f.task) ? f.task : "unknown"}: builder exited without a result`,
  };
}

/** The effects the glue needs; injected so a test can record them. */
export type Effects = {
  facts: (task: string) => { dirty: boolean; ahead: number };
  commitWip: (message: string, allowEmpty: boolean) => string;
  handback: (task: string, tip: string, state: string) => void;
};

export type Salvaged = { salvaged: false } | { salvaged: true; tip: string; state: string };

/** Call after a builder returns: `result` is its structured result or null. Never retries, never judges the work. */
export function salvageStage(task: string, result: unknown | null | undefined, fx: Effects): Salvaged {
  const hasResult = result !== null && result !== undefined;
  const g = hasResult ? { dirty: false, ahead: 0 } : fx.facts(task);
  const out = decide({ task, hasResult, ...g });
  if (!out.salvage) return { salvaged: false };
  const tip = out.commit ? fx.commitWip(out.message, out.allowEmpty) : "";
  if (out.handback) fx.handback(task, tip, out.state);
  return { salvaged: true, tip, state: out.state };
}
