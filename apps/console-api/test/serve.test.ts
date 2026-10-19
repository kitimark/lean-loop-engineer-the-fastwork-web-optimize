// Stateful fwcore session: replay equivalence (replay = apply one by one = the stateless fold) and timings.
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { emptyPlan, emptyState, type ReducerEvent, type State } from "@fw/contracts";
import { selectCore } from "../src/core/index.ts";
import { logLines } from "../src/core/lean.ts";

/** One synthetic card life with k build rounds (8 + 4k events), the same shape as lean/FwTest/Serve.lean `cardLife`. */
function cardLife(i: number, k: number): ReducerEvent[] {
  const c = `c${i}`, ts = 1000 + i, last = `s${k - 1}`;
  const out: ReducerEvent[] = [
    { key: `${c}o`, ts, type: "card.open", actor: "owner", card: c, owner: "o", needsDevice: false },
    { key: `${c}a`, ts, type: "card.approve", actor: "lead", card: c },
  ];
  for (let j = 0; j < k; j++) {
    out.push(
      { key: `${c}b${j}`, ts, type: "card.build", actor: "git", card: c, sha: `s${j}`, agent: "o" },
      { key: `${c}rs${j}`, ts, type: "run.start", actor: "script", run: `${c}r${j}`, card: c, kind: "screen" },
      { key: `${c}rf${j}`, ts, type: "run.finish", actor: "script", run: `${c}r${j}`, ok: true },
      { key: `${c}sc${j}`, ts, type: "card.screen", actor: "script", card: c, sha: `s${j}`, pass: true },
    );
  }
  out.push(
    { key: `${c}p`, ts, type: "step.post", actor: "script", step: `${c}S`, card: c, title: "Plug in", kind: "action", options: null },
    { key: `${c}st`, ts, type: "step.start", actor: "user", step: `${c}S` },
    { key: `${c}sd`, ts, type: "step.done", actor: "user", step: `${c}S` },
    { key: `${c}rv`, ts, type: "card.review", actor: "reviewer", card: c, sha: last, signedBy: "r", accept: true },
    { key: `${c}lr`, ts, type: "card.land_request", actor: "lead", card: c, sha: last },
    { key: `${c}l`, ts, type: "card.landed", actor: "git", card: c, sha: last },
  );
  return out;
}
const synth = (cards: number, k: number) => Array.from({ length: cards }, (_, i) => cardLife(i, k)).flat();
const lines = (es: ReducerEvent[]) => es.map((e, i) => JSON.stringify({ ...e, seq: i + 1 }));

const cores: ReturnType<typeof selectCore>[] = [];
const fresh = () => { const c = selectCore(process.env, undefined, () => undefined); cores.push(c); return c; };
afterAll(() => cores.forEach((c) => c.close()));

describe("fwcore serve: replay equivalence", () => {
  it("replay of a log = applying it one event at a time = the stateless fold (same board)", async () => {
    const es = [...synth(12, 3), ...synth(3, 2).map((e) => ({ ...e, key: `${e.key}x` }))]; // re-opens: refused
    const a = fresh();
    const t = await a.open(() => lines(es));
    expect(t.accepted + t.duplicate + t.refused).toBe(es.length);
    expect(t.refused).toBeGreaterThan(0);
    const b = fresh();
    await b.open(() => []);
    let state: State = emptyState();
    for (const e of es) {
      const r = await b.apply(e);
      const pure = await b.applyPure(state, e);
      expect(r.outcome).toEqual(pure.outcome);
      if (!r.outcome.accepted) expect(r.changed).toEqual({ cards: [], steps: [], runs: [] });
      state = pure.state;
    }
    const now = 1000 + 30 * 60 * 1000 + 5;
    const ba = await a.board(now, 7);
    expect(await b.board(now, 7)).toEqual(ba);
    expect({ ...(await b.boardPure(state, now, 7)), plan: emptyPlan() }).toEqual(ba);
  }, 30_000);
  it("changed rows: an accepted event reports the rows it touched in the new state", async () => {
    const c = fresh();
    await c.open(() => lines(synth(1, 1).slice(0, 3))); // open, approve, build
    const r = await c.apply({ key: "rs", ts: 9, type: "run.start", actor: "script", run: "R", card: "c0", kind: "gate" });
    expect(r.outcome).toEqual({ accepted: true, duplicate: false });
    expect(r.changed.cards.map((x) => [x.id, x.lastAt])).toEqual([["c0", 1000]]);
    expect(r.changed.runs.map((x) => [x.id, x.status])).toEqual([["R", "running"]]);
    const f = await c.apply({ key: "rf", ts: 2000, type: "run.finish", actor: "script", run: "R", ok: false });
    expect(f.changed.cards.map((x) => x.lastAt)).toEqual([2000]);
    expect(f.changed.runs.map((x) => x.status)).toEqual(["failed"]);
    expect((await c.apply({ key: "rf", ts: 2001, type: "run.finish", actor: "script", run: "R", ok: true })).changed)
      .toEqual({ cards: [], steps: [], runs: [] }); // duplicate
  });
});

describe("fwcore serve: timings (100k synthetic events)", () => {
  it("replays 100k events from events.jsonl, then applies and queries", async () => {
    const es = synth(4167, 4); // 4,167 cards × 24 events = 100,008 events
    const dir = mkdtempSync(join(tmpdir(), "fw-serve-"));
    const path = join(dir, "events.jsonl");
    writeFileSync(path, lines(es).join("\n") + "\n");
    const c = fresh();
    const t0 = performance.now();
    const t = await c.open(() => logLines(path));
    const replayMs = performance.now() - t0;
    expect(t).toEqual({ accepted: es.length, duplicate: 0, refused: 0 });
    const rtt: number[] = [];
    for (let i = 0; i < 1000; i++) {
      const s = performance.now();
      const r = await c.apply({ key: `n${i}`, ts: 5000, type: "card.open", actor: "owner", card: `n${i}`, owner: "o", needsDevice: false });
      rtt.push((performance.now() - s) * 1000);
      expect(r.outcome.accepted).toBe(true);
    }
    rtt.sort((x, y) => x - y);
    const q0 = performance.now();
    const b = await c.board(5000, es.length + 1000);
    const queryMs = performance.now() - q0;
    expect(b.cards).toHaveLength(4167 + 1000);
    console.log(`fwcore serve: replay ${es.length} events ${replayMs.toFixed(0)} ms; ` +
      `apply round trip p50 ${rtt[500]!.toFixed(0)} µs, p90 ${rtt[900]!.toFixed(0)} µs; query (${b.cards.length} cards) ${queryMs.toFixed(0)} ms`);
    // A load-independent sanity bound, not a regression detector: replay of n/10 events into a fresh core is timed in the
    // same run, so load scales both sides alike. Child-process spawn cost dominates the small run, so this does not detect
    // an O(n^2) apply path; replay slowdowns are the CI timing lane's job (Fw.Obs.Timing). K = 3 is slack for noise.
    const K = 3;
    const small = synth(417, 4); // 417 cards x 24 events = 10,008 events
    const c2 = fresh();
    const s0 = performance.now();
    await c2.open(() => lines(small));
    const smallMs = performance.now() - s0;
    const linearBound = 10 * smallMs * K;
    expect(replayMs).toBeLessThan(linearBound);
  }, 60_000);
});
