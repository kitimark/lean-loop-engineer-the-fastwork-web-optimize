// TEMPORARY probe (drain-wake-flake): the real wake scenario with a timeline of events and passes, logged not asserted.
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { it } from "vitest";
import { selectCore } from "../src/core/index.ts";
import { Drain } from "../src/spool/drain.ts";
import { startDrainWatch } from "../src/spool/drain-watch.ts";
import { workflowWatchTargets } from "../src/spool/workflow.ts";
import { Store } from "../src/store.ts";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
it("probe", async () => {
  const out: string[] = [];
  let miss = 0, maxPass = 0;
  for (let i = 0; i < 12; i++) {
    const dir = mkdtempSync(join(tmpdir(), "fw-pr-"));
    const store = await Store.open(dir, selectCore(), () => 1_700_000_000_000);
    mkdirSync(join(dir, "spool"));
    const wf = join(dir, "sess", "workflows");
    mkdirSync(join(wf, "scripts"), { recursive: true });
    const d = new Drain(store, () => [wf]);
    const t0 = performance.now();
    const log: string[] = [];
    const at = () => (performance.now() - t0).toFixed(0);
    const w = startDrainWatch(dir, async () => {
      const s = performance.now(); log.push(`${at()} pass-start`);
      try { return await d.run(); } finally { const dt = performance.now() - s; maxPass = Math.max(maxPass, dt); log.push(`${at()} pass-end ${dt.toFixed(0)}ms`); }
    }, () => undefined, 60_000, () => workflowWatchTargets(dir, { FW_WORKFLOWS_DIR: wf }));
    const origPoke = w.trigger.poke.bind(w.trigger);
    w.trigger.poke = () => { log.push(`${at()} poke`); origPoke(); };
    while (w.trigger.passes < 1) await sleep(10);
    await sleep(100);
    const p0 = w.trigger.passes;
    log.push(`${at()} p0=${p0} mkdir`);
    const rd = join(dir, "sess", "subagents", "workflows", "wf_e37180a7-497");
    mkdirSync(rd, { recursive: true });
    const m0 = performance.now();
    while (w.trigger.passes <= p0 && performance.now() - m0 < 3000) await sleep(10);
    const p1 = w.trigger.passes;
    log.push(`${at()} p1=${p1} after-mkdir wait`);
    await sleep(100);
    log.push(`${at()} write`);
    writeFileSync(join(rd, "journal.jsonl"), "{}\n");
    const m1 = performance.now();
    while (w.trigger.passes <= p1 && performance.now() - m1 < 3000) await sleep(10);
    const ok = w.trigger.passes > p1;
    log.push(`${at()} ${ok ? "woke" : "MISS"} passes=${w.trigger.passes}`);
    if (!ok) { miss++; out.push(`round ${i}\n` + log.join("\n")); }
    else if (i === 0) out.push(`sample\n` + log.join("\n"));
    w.stop(); store.close();
  }
  out.push(`PROBE SUMMARY misses=${miss}/12 maxPassMs=${maxPass.toFixed(0)} node=${process.version}`);
  throw new Error("PROBE\n" + out.slice(0, 4).concat(out.slice(-1)).join("\n"));
});
