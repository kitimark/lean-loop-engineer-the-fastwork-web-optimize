const flagValue = (a: string[], f: string): string | undefined => { const i = a.indexOf(f); const v = i >= 0 ? a[i + 1] : undefined; return v && !v.startsWith("-") ? v : undefined; };

/** The step of the `fw` span of one `fw slot` call (`rest` = the arguments after `slot`): `slot run <kind>`, `slot acquire <kind>`,
 *  `slot held <kind>`, `slot admit`, `slot status`, ... so a queue wait, an admission check and a status read never share a history.
 *  No imports: scripts/slot-self.mjs loads it on the light path. */
export function slotStep(rest: string[]): string {
  const base = slotStepBase(rest);
  const dash = rest.indexOf("--");
  return rest[0] === "run" && dash >= 0 && rest.slice(dash + 1).includes("--dry") ? `${base} dry` : base;
}

/** Held on `globalThis`: slot.ts may load from another checkout (`slotMainPath`), whose copy of this module is a separate instance. */
const REPLAYED = "__fwSlotReplayed";
/** `slot run --cache` served a recorded result: the span of this process ends as `<step> cached` (see `slotStepEnd`). */
export function markReplayed(): void { (globalThis as Record<string, unknown>)[REPLAYED] = true; }
/** The step to record when the process ends: `slotStep` plus ` cached` after a cache replay (about 1 s, never the 130 s of a real run). */
export function slotStepEnd(rest: string[]): string { return (globalThis as Record<string, unknown>)[REPLAYED] ? `${slotStep(rest)} cached` : slotStep(rest); }

/** The subcommands `slotCli` dispatches; `slotCli` refuses any other and `fw-groups.ts` names spans from this list. */
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
