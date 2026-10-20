// TEMPORARY probe (drain-wake-flake): timeline of fs events for the wake scenario, many rounds, logged not asserted.
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { it } from "vitest";
import { Watches } from "../src/watch.ts";
import { workflowWatchTargets } from "../src/spool/workflow.ts";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
it("probe", async () => {
  let miss = 0; const out: string[] = [];
  for (let i = 0; i < 20; i++) {
    const dir = mkdtempSync(join(tmpdir(), "probe-"));
    const wf = join(dir, "sess", "workflows");
    mkdirSync(join(wf, "scripts"), { recursive: true });
    const t0 = performance.now();
    const log: string[] = [];
    const at = () => (performance.now() - t0).toFixed(1);
    let stage = "init";
    const w: Watches = new Watches(() => workflowWatchTargets(dir, { FW_WORKFLOWS_DIR: wf }), (t) => {
      log.push(`${at()} ev[${stage}] ${t.path.slice(dir.length)} disc=${!!t.discover}`);
      if (t.discover) { w.sync(); log.push(`${at()} synced size=${w.size}`); }
    });
    w.sync();
    await sleep(100);
    stage = "mkdir";
    const rd = join(dir, "sess", "subagents", "workflows", "wf_x");
    mkdirSync(rd, { recursive: true });
    log.push(`${at()} mkdir done`);
    await sleep(100);
    stage = "write";
    writeFileSync(join(rd, "journal.jsonl"), "{}\n");
    log.push(`${at()} write done`);
    const n = log.length;
    let ok = false;
    for (let k = 0; k < 30 && !ok; k++) { await sleep(10); ok = log.slice(n).some((l) => l.includes("ev[write]")); }
    if (!ok) { miss++; out.push(`PROBE MISS round ${i}\n` + log.join("\n")); }
    else if (i === 0) out.push(`PROBE OK sample\n` + log.join("\n"));
    w.close();
    rmSync(dir, { recursive: true, force: true });
  }
  out.push(`PROBE SUMMARY misses=${miss}/20 platform=${process.platform} node=${process.version}`);
  throw new Error(out.slice(0, 4).concat(out.slice(-1)).join("\n"));
});
