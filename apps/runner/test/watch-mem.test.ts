import { appendFileSync, existsSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { collectFeedback, parseSamples, pathsFor, readSamples } from "../src/watch-collect.ts";
import { coreCaller, memCheck, slowWith } from "../src/watch.ts";
import { nextCursor, readFrom, windowRows } from "../src/watch-mem.ts";

const here = dirname(fileURLToPath(import.meta.url));
const bin = process.env.FW_CORE_BIN ?? join(here, "../../../lean/.lake/build/bin/fwcore");
const have = existsSync(bin);
const core = coreCaller(have ? [bin] : []);
type Case = { name: string; request: Record<string, unknown>; response: Record<string, unknown> };
const golden = (op: string): Case[] => readFileSync(join(here, `../../../packages/contracts/golden/ops/${op}.jsonl`), "utf8").trim().split("\n").map((l) => JSON.parse(l));

const dirs: string[] = [];
const tmp = () => { const d = mkdtempSync(join(tmpdir(), "fwmem-")); dirs.push(d); return d; };
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

describe("retention rules against the Lean goldens (Fw.Ops.WatchMem)", () => {
  it.each(golden("ops.watchWindow").map((c) => [c.name, c] as const))("window: %s", (_n, c) => {
    const ms = c.request.ms as number[];
    // fed one at a time, as the tailer feeds chunks of one
    let w: { at: number; seq: number }[] = [];
    ms.forEach((at, seq) => { w = windowRows(w, [{ at, seq }], c.request.cap as number); });
    expect({ keep: w.map((r) => r.seq) }).toEqual(c.response);
    // fed as one chunk
    expect({ keep: windowRows([], ms.map((at, seq) => ({ at, seq })), c.request.cap as number).map((r) => r.seq) }).toEqual(c.response);
  });
  it.each(golden("ops.watchCursor").map((c) => [c.name, c] as const))("cursor: %s", (_n, c) => {
    const r = c.request as { cursor: number; size: number; same: boolean; nl?: number };
    const from = readFrom(r.cursor, r.size, r.same);
    expect({ from, next: nextCursor(from, r.nl ?? null) }).toEqual(c.response);
  });
  it("window: chunked feeding equals one sort of everything, for random logs", () => {
    let seed = 7;
    const rnd = (n: number) => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; };
    for (let round = 0; round < 50; round++) {
      const ms = Array.from({ length: rnd(300) }, () => rnd(40));
      const cap = rnd(60);
      const rows = ms.map((at, seq) => ({ at, seq }));
      let w: typeof rows = [];
      for (let i = 0; i < rows.length;) { const k = 1 + rnd(25); w = windowRows(w, rows.slice(i, i + k), cap); i += k; }
      const whole = [...rows].sort((a, b) => a.at - b.at || a.seq - b.seq).slice(cap === 0 ? rows.length : -cap);
      expect(w).toEqual(whole);
      expect(w.length).toBeLessThanOrEqual(cap);
    }
  });
});

const sampleLine = (startMs: number, i: number) =>
  JSON.stringify({ tool: "lean", step: `step ${i % 7}`, durMs: 100 + (i % 13), host: i % 5 === 0 ? "ci" : "local", load: i % 4, startMs, exit: 0 });

describe("incremental readers equal the whole-file reads", () => {
  const sampleLog = (n: number, from = 0) => Array.from({ length: n }, (_, k) => sampleLine(1_000_000 + ((from + k) * 7919) % 5000, from + k)).join("\n") + "\n";

  it("readSamples after appends, a half-written line, a truncation and a replacement equals parseSamples of the file", () => {
    const dir = tmp(), file = join(dir, "timings.jsonl");
    const p = pathsFor("/x/r", { FW_CONSOLE_DIR: dir } as never);
    expect(readSamples(p)).toEqual([]);
    writeFileSync(file, sampleLog(4000));
    const same = () => expect(readSamples(p)).toEqual(parseSamples(readFileSync(file, "utf8")));
    same();
    expect(readSamples(p)).toHaveLength(3000);
    appendFileSync(file, sampleLog(50, 4000));
    same();
    const half = sampleLine(1_002_222, 1);
    appendFileSync(file, half.slice(0, 20));
    same();
    appendFileSync(file, half.slice(20) + "\n");
    same();
    writeFileSync(file, sampleLog(10));
    same();
    expect(readSamples(p)).toHaveLength(10);
    writeFileSync(join(dir, "new.jsonl"), sampleLog(5000, 3));
    renameSync(join(dir, "new.jsonl"), file);
    same();
    writeFileSync(file, "");
    expect(readSamples(p)).toEqual([]);
  });

  it("collectFeedback reads only the appended events and drops them on truncation", () => {
    const dir = tmp(), file = join(dir, "events.jsonl");
    const p = pathsFor("/x/r", { FW_CONSOLE_DIR: dir } as never);
    const fb = (id: string, ts: number) => JSON.stringify({ type: "review.feedback", id, flag: "f", text: "t", ts });
    writeFileSync(file, [fb("a", 1), JSON.stringify({ type: "other" }), fb("b", 2)].join("\n") + "\n");
    expect(collectFeedback(p).map((e) => e.ref)).toEqual(["a", "b"]);
    appendFileSync(file, fb("c", 3) + "\n");
    expect(collectFeedback(p).map((e) => e.ref)).toEqual(["a", "b", "c"]);
    writeFileSync(file, fb("z", 9) + "\n");
    expect(collectFeedback(p).map((e) => e.ref)).toEqual(["z"]);
  });

  it.skipIf(!have)("the slow verdicts of a recorded window are the same as from a whole-file read", async () => {
    const dir = tmp(), file = join(dir, "timings.jsonl");
    const lines: string[] = [];
    for (let i = 0; i < 3500; i++) lines.push(sampleLine(2_000_000 + (i * 31) % 997, i));
    lines.push(JSON.stringify({ tool: "lean", step: "step 1", durMs: 900_000, host: "local", load: 1, startMs: 2_000_999, exit: 0 }));
    writeFileSync(file, lines.join("\n") + "\n");
    const p = pathsFor("/x/r", { FW_CONSOLE_DIR: dir } as never);
    const viaCursor = await slowWith(p, core);
    const whole = await core({ op: "obs.slow", detail: true, samples: parseSamples(readFileSync(file, "utf8")) });
    expect(viaCursor.slow).toEqual(whole.slow);
    expect(viaCursor.slow.length).toBeGreaterThan(0);
  });
});

describe.skipIf(!have)("fwcore ops.watchWindow / watchCursor / watchRss goldens", () => {
  it.each([...golden("ops.watchWindow"), ...golden("ops.watchCursor"), ...golden("ops.watchRss")].map((c) => [c.name, c] as const))("%s", async (_n, c) => {
    const { id: _id, ...reply } = await core(c.request);
    expect(reply).toEqual(c.response);
  });
});

describe("memCheck: the watcher's own memory", () => {
  it.skipIf(!have)("a tick line below the bound, an alert above it", async () => {
    const ok = await memCheck(core, { rssKb: 100_000, heapKb: 20_000 });
    expect(ok).toEqual({ line: "TICK rss=98MB heap=20MB bound=512MB", alerts: [], mem: { rssKb: 100_000, heapKb: 20_000 } });
    const bad = await memCheck(core, { rssKb: 678_912, heapKb: 210_000 });
    expect(bad?.alerts).toEqual([{ code: "watch.rss", subject: "fw-watch", detail: "fw watch holds 663 MB resident, over the 512 MB bound" }]);
  });
  it("a failed fwcore call gives no line and no alert", async () => {
    expect(await memCheck(async () => { throw new Error("down"); }, { rssKb: 1, heapKb: 1 })).toBeNull();
  });
});
