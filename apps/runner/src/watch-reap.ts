import { type HeldEntry, type ReapPass } from "./reap.ts";

export type HeldAlert = { code: string; subject: string; detail: string };

const subjectOf = (h: HeldEntry, sim: boolean): string => sim ? `sim ${h.pid}` : (h.wt ?? `pid-${h.pid}`);

/** The `agent.held` alerts of one watch pass: the entries Lean's Reap plan holds (loops and booted Simulators). */
export function reapHeldAlerts(pass: ReapPass | null): HeldAlert[] {
  if (pass === null) return [];
  const one = (h: HeldEntry, sim: boolean, what: string): HeldAlert => ({
    code: "agent.held", subject: subjectOf(h, sim),
    detail: `${what} pid=${h.pid} start=${h.start}: ${h.reason}; pnpm -s fw reap --stop applies it`,
  });
  return [...pass.held.map((h) => one(h, false, "killOrphan")), ...pass.heldSim.map((h) => one(h, true, "simBooted"))];
}
