// Scale an event log for the fwcore query/replay timing and golden check (task fwcore-query-speed).
// usage: node lean/scripts/scale-log.mjs <events.jsonl> <copies> > scaled.jsonl
// Copy 0 is the input. Copy k>0 renames every id-like string field consistently (suffix "~k") and shifts seq and ts,
// so a copy is a disjoint task graph of the same shape. The output holds the ids of its input; nothing is committed
// from it (scale a scratch copy of the log, or a synthetic one).
import fs from "node:fs";

const [file, copiesArg] = process.argv.slice(2);
const copies = Number(copiesArg ?? 1);
const lines = fs.readFileSync(file, "utf8").split("\n").filter((l) => l.trim());
const evs = lines.map((l) => JSON.parse(l));
const maxSeq = Math.max(...evs.map((e) => e.seq ?? 0));
const tss = evs.map((e) => e.ts ?? 0);
const span = Math.max(...tss) - Math.min(...tss) + 1;
const ID = ["key", "step", "card", "task", "agent", "milestone", "name"];
const out = [];
for (let k = 0; k < copies; k++) {
  for (const e of evs) {
    if (k === 0) {
      out.push(JSON.stringify(e));
      continue;
    }
    const c = { ...e };
    for (const f of ID) if (typeof c[f] === "string") c[f] = `${c[f]}~${k}`;
    if (Array.isArray(c.deps)) c.deps = c.deps.map((d) => `${d}~${k}`);
    if (typeof c.seq === "number") c.seq += k * maxSeq;
    if (typeof c.ts === "number") c.ts += k * span;
    out.push(JSON.stringify(c));
  }
}
process.stdout.write(out.join("\n") + "\n");
