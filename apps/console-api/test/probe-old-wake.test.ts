// TEMPORARY PROBE (task drain-wake-flake round 2): the old wake test of 05d720ae, unchanged in its waits (3 s `until`), with
// instrumentation. It appends one JSON line per run to $DWF_LOG: pokes, passes, per-pass length, event-loop lag, which wait failed.
import { appendFileSync, mkdirSync, mkdtempSync, watch, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { monitorEventLoopDelay } from "node:perf_hooks";
import { afterEach, describe, it } from "vitest";
import { selectCore } from "../src/core/index.ts";
import { Drain } from "../src/spool/drain.ts";
import { startDrainWatch } from "../src/spool/drain-watch.ts";
import { workflowWatchTargets } from "../src/spool/workflow.ts";
import { Store } from "../src/store.ts";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
let stores: Store[] = [];
let stops: (() => void)[] = [];
afterEach(() => { stops.forEach((s) => s()); stops = []; stores.forEach((s) => s.close()); stores = []; });

describe("probe: old wake test", () => {
  it("a journal append and a new session dir wake the drain (05d720ae waits)", async () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-dw-"));
    const store = await Store.open(dir, selectCore(), () => 1_700_000_000_000);
    stores.push(store);
    mkdirSync(join(dir, "spool"));
    const wf = join(dir, "sess", "workflows");
    mkdirSync(join(wf, "scripts"), { recursive: true });
    const lag = monitorEventLoopDelay({ resolution: 10 });
    lag.enable();
    stops.push(() => lag.disable());
    const passes: { start: number; end: number | null; pokes: number }[] = [];
    const ref: { w?: ReturnType<typeof startDrainWatch> } = {};
    const d = new Drain(store, () => [wf]);
    const t0 = performance.now();
    const w = startDrainWatch(dir, async () => {
      const p = { start: performance.now() - t0, end: null as number | null, pokes: ref.w?.trigger.pokes ?? 0 };
      passes.push(p);
      try { return await d.run(); } finally { p.end = performance.now() - t0; }
    }, () => undefined, 60_000, () => workflowWatchTargets(dir, { FW_WORKFLOWS_DIR: wf }));
    ref.w = w;
    stops.push(w.stop);
    let wait = "start";
    const until = async (f: () => boolean, name: string, ms = 3000) => {
      wait = name;
      const s = performance.now();
      while (!f()) { if (performance.now() - s > ms) throw new Error("timeout"); await sleep(10); }
    };
    const log = (kind: string) => {
      const f = process.env.DWF_LOG;
      const row = { kind, wait, node: process.version, pokes: w.trigger.pokes, passes: w.trigger.passes, watches: w.watches.size,
        lagMaxMs: Math.round(lag.max / 1e6), lagP99Ms: Math.round(lag.percentile(99) / 1e6),
        passMs: passes.map((p) => (p.end === null ? null : Math.round(p.end - p.start))), passStart: passes.map((p) => Math.round(p.start)),
        passPokes: passes.map((p) => p.pokes) };
      if (f) appendFileSync(f, JSON.stringify(row) + "\n");
      else console.log("DWF-ROW " + JSON.stringify(row));
    };
    try {
      await until(() => w.trigger.passes >= 1, "first pass");
      const rd = join(dir, "sess", "subagents", "workflows", "wf_e37180a7-497");
      await sleep(100);
      const p0 = w.trigger.passes;
      mkdirSync(rd, { recursive: true });
      await until(() => w.trigger.passes > p0, "new session dir");
      const p1 = w.trigger.passes;
      await sleep(100);
      writeFileSync(join(rd, "journal.jsonl"), "{}\n");
      await until(() => w.trigger.passes > p1, "journal append");
      log("ok");
    } catch (e) { log("miss"); throw e; }
  });
});

describe("probe: raw recursive watch on a missing path", () => {
  it("records whether fs.watch throws and whether a later file under the path gives an event", async () => {
    const d = mkdtempSync(join(tmpdir(), "fw-raw-"));
    const missing = join(d, "a", "b");
    let threw: string | null = null, events = 0;
    let w: ReturnType<typeof watch> | null = null;
    try { w = watch(missing, { recursive: true, persistent: false }, () => { events++; }); } catch (e) { threw = (e as { code?: string }).code ?? String(e); }
    mkdirSync(join(missing, "c"), { recursive: true });
    await sleep(200);
    writeFileSync(join(missing, "c", "j.jsonl"), "{}\n");
    await sleep(500);
    w?.close();
    const row = { kind: "raw", node: process.version, platform: process.platform, threw, eventsAfterCreate: events };
    if (process.env.DWF_LOG) appendFileSync(process.env.DWF_LOG, JSON.stringify(row) + "\n"); else console.log("DWF-ROW " + JSON.stringify(row));
  });
});
