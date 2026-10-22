const flagValue = (a: string[], f: string): string | undefined => { const i = a.indexOf(f); const v = i >= 0 ? a[i + 1] : undefined; return v && !v.startsWith("-") ? v : undefined; };

export function slotStep(rest: string[]): string {
  const base = slotStepBase(rest);
  const dash = rest.indexOf("--");
  return rest[0] === "run" && dash >= 0 && rest.slice(dash + 1).includes("--dry") ? `${base} dry` : base;
}

const REPLAYED = "__fwSlotReplayed";
export function markReplayed(): void { (globalThis as Record<string, unknown>)[REPLAYED] = true; }
export function slotStepEnd(rest: string[]): string { return (globalThis as Record<string, unknown>)[REPLAYED] ? `${slotStep(rest)} cached` : slotStep(rest); }

export const SLOT_SUBS = ["run", "acquire", "renew", "release", "status", "sim", "held", "admit"] as const;

function slotStepBase(rest: string[]): string {
  const sub = rest[0];
  if (!sub || sub.startsWith("-")) return "slot";
  if (sub === "run" || sub === "acquire" || sub === "held") {
    const k = flagValue(rest.slice(0, rest.includes("--") ? rest.indexOf("--") : undefined), "--kind");
    return k ? `slot ${sub} ${k}` : `slot ${sub}`;
  }
  return `slot ${sub}`;
}
