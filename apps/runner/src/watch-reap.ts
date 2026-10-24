import { fwcoreCall } from "./run.ts";
import { gather, heldLoops, heldSims, type Call, type Facts } from "./reap.ts";

export type HeldAlert = { code: string; subject: string; detail: string };

export function reapHeldAlerts(top: string, env: Record<string, string | undefined> = process.env,
  gatherFn: (top: string) => Facts | null = gather, call: () => Call = () => fwcoreCall(top)): HeldAlert[] {
  if (env.FW_WATCH_REAP === "0") return [];
  try {
    const f = gatherFn(top);
    if (f === null) return [];
    const c = call();
    return [
      ...heldLoops(f, c).map((h) => ({
        code: "agent.held", subject: h.subject,
        detail: `killOrphan pid=${h.pid} start=${h.start}: ${h.reason}; pnpm -s fw reap --stop applies it`,
      })),
      ...heldSims(f, c).map((h) => ({
        code: "agent.held", subject: `sim ${h.pid}`,
        detail: `simBooted pid=${h.pid} start=${h.start}: ${h.reason}; pnpm -s fw reap --stop applies it`,
      })),
    ];
  } catch {
    return [];
  }
}
