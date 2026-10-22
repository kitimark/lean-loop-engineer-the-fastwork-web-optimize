const flagValue = (a: string[], f: string): string | undefined => { const i = a.indexOf(f); const v = i >= 0 ? a[i + 1] : undefined; return v && !v.startsWith("-") ? v : undefined; };

/** The step of the `fw` span of one `fw slot` call (`rest` = the arguments after `slot`): `slot run <kind>`, `slot acquire <kind>`,
 *  `slot held <kind>`, `slot admit`, `slot status`, ... so a queue wait, an admission check and a status read never share a history.
 *  No imports: scripts/slot-self.mjs loads it on the light path. */
export function slotStep(rest: string[]): string {
  const sub = rest[0];
  if (!sub || sub.startsWith("-")) return "slot";
  if (sub === "run" || sub === "acquire" || sub === "held") {
    const k = flagValue(rest.slice(0, rest.includes("--") ? rest.indexOf("--") : undefined), "--kind");
    return k ? `slot ${sub} ${k}` : `slot ${sub}`;
  }
  return `slot ${sub}`;
}
