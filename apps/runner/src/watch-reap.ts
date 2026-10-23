// The watch alert for an orphan until-loop: Lean's `ops.reapHeld` (lean/Fw/Ops/Reap.lean, `held`) on the facts `fw reap` reads.
// The alert and `fw reap --stop` share one rule (`held_in_plan`: every alerted identity is a TERM target of the stop plan);
// this file gathers nothing of its own and decides nothing.
import { fwcoreCall } from "./run.ts";
import { gather, heldLoops, type Call, type Facts } from "./reap.ts";

export type HeldAlert = { code: string; subject: string; detail: string };

/** One `agent.held` alert per orphan loop Lean selects; `[]` when the facts cannot be read or Lean fails (a quiet pass).
 *  `FW_WATCH_REAP=0` turns it off with the stop. */
export function reapHeldAlerts(top: string, env: Record<string, string | undefined> = process.env,
  gatherFn: (top: string) => Facts | null = gather, call: () => Call = () => fwcoreCall(top)): HeldAlert[] {
  if (env.FW_WATCH_REAP === "0") return [];
  try {
    const f = gatherFn(top);
    if (f === null) return [];
    return heldLoops(f, call()).map((h) => ({
      code: "agent.held", subject: h.subject,
      detail: `killOrphan pid=${h.pid} start=${h.start}: ${h.reason}; pnpm -s fw reap --stop applies it`,
    }));
  } catch {
    return [];
  }
}
