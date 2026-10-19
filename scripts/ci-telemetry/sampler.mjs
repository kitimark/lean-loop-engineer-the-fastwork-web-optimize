// ci-telemetry sampler: a background process that appends one probe line to <dir>/probes.jsonl every interval until it
// gets SIGTERM (or the file stop is written). Started by `cli.mjs start`; never throws into the job.
//   node sampler.mjs <dir> [intervalMs]
import { appendFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join } from "node:path";
import { takeProbe } from "./lib.mjs";

const dir = process.argv[2];
const every = Math.max(1000, Number(process.argv[3]) || 5000);
if (!dir) process.exit(2);
const exec = (cmd, args) => { try { return execFileSync(cmd, args, { encoding: "utf8", timeout: 4000, stdio: ["ignore", "pipe", "ignore"] }); } catch { return null; } };
const out = join(dir, "probes.jsonl");
let prev = null;
const tick = () => {
  try {
    if (existsSync(join(dir, "stop"))) process.exit(0);
    const { probe, cur } = takeProbe(prev, dir, exec);
    prev = cur;
    appendFileSync(out, JSON.stringify(probe) + "\n");
  } catch { /* a missed probe is not an error */ }
};
process.on("SIGTERM", () => { tick(); process.exit(0); });
tick();
setInterval(tick, every);
