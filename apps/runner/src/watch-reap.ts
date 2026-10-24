import { fwcoreCall } from "./run.ts";
import { gather, heldLoops, type Call, type Facts } from "./reap.ts";

export type HeldAlert = { code: string; subject: string; detail: string };

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
