// Synthetic hung-gh probe (task dispatch-latency-followups, item 5): re-runs the holder/waiter pair of
// research/notes/2026/10-2x-dispatch-latency.md. A fake gh sleeps `--sleep` s. A holder process takes the gh-budget lock
// and calls it; `--waiter-delay` s later this process asks for the lock. The real gh-budget code runs (lock, kill at the
// timeout); the fwcore decision is a stand-in that always says issue. No GitHub call is made.
import { spawn } from "node:child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { chargedOnce } from "../packages/gh-budget/src/charged.ts";

const arg = (n, d) => { const i = process.argv.indexOf(`--${n}`); return i < 0 ? d : Number(process.argv[i + 1]); };
const timeoutMs = arg("timeout-ms", 20000), lockWaitMs = arg("lock-wait-ms", 60000), sleepS = arg("sleep", 90), delayS = arg("waiter-delay", 1);

const owner = !process.env.GH_HUNG_PROBE_ROOT;
const root = process.env.GH_HUNG_PROBE_ROOT ?? mkdtempSync(join(tmpdir(), "gh-hung-probe-"));
if (owner) {
  writeFileSync(join(root, "gh"), `#!/bin/sh\nsleep ${sleepS}\n`);
  chmodSync(join(root, "gh"), 0o755);
}
const core = (req) => (req.op === "ci.budget.reserve" ? { decision: "issue", kind: "oneoff", cost: 1, state: {} } : { state: {}, headers: {} });
const env = { dir: join(root, "state"), gh: join(root, "gh"), now: () => Date.now() / 1000, core, sleepUntil: async () => {} };
const call = (e = env) => chargedOnce(e, (state, now) => core({ op: "ci.budget.reserve", now, state, cost: 1 }), () => ["run", "list"], timeoutMs, lockWaitMs);

const t0 = Date.now();
if (process.argv.includes("--holder")) {
  const r = call(); // the thread blocks in spawnSync until the timeout kills the fake gh
  console.log(JSON.stringify({ killedAfterMs: Date.now() - t0, error: r.ran ? r.error : r.reason }));
} else {
  const child = spawn(process.execPath, [new URL(import.meta.url).pathname, "--holder", ...process.argv.slice(2)],
    { stdio: ["ignore", "pipe", "inherit"], env: { ...process.env, GH_HUNG_PROBE_ROOT: root } });
  let out = "";
  child.stdout.on("data", (d) => { out += d; });
  await new Promise((r) => setTimeout(r, delayS * 1000));
  const w0 = Date.now();
  const waiter = call({ ...env, exec: () => ({ status: 0, stdout: "", stderr: "" }) });
  const waiterGotLockAfterMs = Date.now() - w0;
  await new Promise((r) => child.on("close", r));
  if (owner) rmSync(root, { recursive: true, force: true });
  console.log(JSON.stringify({ timeoutMs, lockWaitMs, holder: JSON.parse(out), waiterGotLockAfterMs, waiter: waiter.ran ? "ran" : waiter.decision }));
}
