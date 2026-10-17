// Replay of the Lean fixtures (packages/contracts/golden/ci-budget/fixtures) through the glue with a fake gh.
// The simulated clock jumps from event to event (Lean's replay steps each second; both ask fwcore for every
// decision). Checks: the glue never calls gh on wait/stop, the number of gh calls equals the number of issued
// decisions, the fake server never refuses for an empty bucket, no trace content leaks, the window bounds hold, the
// fixture's own expectations hold, and for `sweep` fixtures every N makes the same calls.
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { ghCharged } from "../src/charged.ts";
import { pollOnce } from "../src/poller.ts";
import { stepEvent } from "../src/state.ts";
import { goldenDir, mkWorld, type Call } from "./util.ts";

type Fx = {
  scenario: { name: string; start: number; seconds: number; waiters?: number; oneoffEvery?: number; oneoffCost?: number; burst?: number; burstAt?: number; sweep?: number[];
    expect?: { counts?: { from: number; until: number; kind: string; min?: number; max?: number }[]; ticksPerHourMax?: number } };
  overrides: { at: number; lines: string[] }[];
  drains: { at: number; remaining: number }[];
};

function parseFixture(text: string): Fx {
  const ls = text.split("\n").filter(Boolean).map((l) => JSON.parse(l) as Record<string, unknown>);
  const rest = ls.slice(1);
  return {
    scenario: (ls[0] as { scenario: Fx["scenario"] }).scenario,
    overrides: rest.filter((j) => Array.isArray(j.lines)).map((j) => ({ at: j.at as number, lines: j.lines as string[] })),
    drains: rest.filter((j) => typeof j.serverRemaining === "number").map((j) => ({ at: j.at as number, remaining: j.serverRemaining as number })),
  };
}

type Issued = { t: number; kind: "tick" | "oneoff"; cost: number };
const LEAK = /someone-private|login|authorization|content-type|x-github-request-id|^\*|^>/i;

async function replay(fx: Fx, N: number) {
  const sc = fx.scenario;
  const w = mkWorld(sc.start);
  w.config({ start: sc.start, listCost: 2, overrides: fx.overrides, drains: fx.drains,
    runs: Array.from({ length: N }, (_, i) => ({ databaseId: i + 1, createdAt: sc.start, completeAt: 1e12, conclusion: "success" })) });
  const env = w.env;
  const issued: Issued[] = [];
  const problems: string[] = [];
  for (let r = 0; r < N; r++) stepEvent(env, { register: { runId: r + 1, createdAt: sc.start } });

  const every = sc.oneoffEvery ?? 0;
  const pending: { ready: number; cost: number }[] = [];
  if (every > 0) for (let i = 0; i < sc.seconds; i += every) pending.push({ ready: sc.start + i, cost: sc.oneoffCost ?? 1 });
  if ((sc.burst ?? 0) > 0) for (let i = 0; i < sc.burst!; i++) pending.push({ ready: sc.burstAt!, cost: 1 });
  pending.sort((a, b) => a.ready - b.ready);
  const queue: { ready: number; cost: number }[] = [];
  let nextAt = sc.start;
  const end = sc.start + sc.seconds;
  const before = () => w.calls().length;

  let t = sc.start;
  while (t < end) {
    w.sim.set(t);
    while (pending.length && pending[0]!.ready <= t) queue.push(pending.shift()!);
    while (queue.length && queue[0]!.ready <= t) {
      process.env.FAKE_GH_COST = String(queue[0]!.cost);
      const n0 = before();
      const res = await ghCharged(env, ["run", "view", "1", "--json", "status"], { cost: queue[0]!.cost });
      if (res.ran) {
        assert.equal(before(), n0 + 1, "one issue is one gh call");
        issued.push({ t, kind: "oneoff", cost: res.cost });
        for (const l of res.lines) if (LEAK.test(l)) problems.push(`leaked line: ${l}`);
        queue.shift();
        nextAt = t; // the observation may move the poller's guards
      } else {
        assert.equal(before(), n0, `gh was called although fwcore said ${res.decision}`);
        if (res.decision === "wait") { queue[0]!.ready = Math.max(res.until, t + 1); break; }
        problems.push(`reserve stopped at ${t}: ${res.reason}`);
        queue.shift();
      }
    }
    while (t >= nextAt) {
      const n0 = before();
      const p = await pollOnce(env);
      if (p.ticked) {
        assert.equal(before(), n0 + 1, "one tick is one gh call");
        issued.push({ t, kind: "tick", cost: 2 });
        nextAt = t >= p.wakeAt ? t + 1 : p.wakeAt; // a tick: ask again next second (fwcore answers with the interval)
        break;
      }
      assert.equal(before(), n0, "gh was called on a poller wait/stop");
      nextAt = Math.max(p.wakeAt, t + 1);
    }
    const cands = [end, nextAt, pending[0]?.ready, queue[0]?.ready].filter((x): x is number => x !== undefined && x > t);
    t = Math.min(...cands);
  }

  const calls = w.calls();
  assert.equal(calls.length, issued.length, "gh calls == issued decisions");
  assert.equal(calls.filter((c) => c.empty).length, 0, "the fake server never refused for an empty bucket");
  return { calls, issued, problems, w };
}

function windowMax(calls: Call[], span: number): number {
  return Math.max(0, ...calls.map((c) => calls.filter((d) => d.t <= c.t && c.t < d.t + span).reduce((s, d) => s + d.cost, 0)));
}

const dir = join(goldenDir, "fixtures");
for (const f of readdirSync(dir).filter((n) => n.endsWith(".jsonl")).sort()) {
  test(`fixture ${f}`, { timeout: 600_000 }, async () => {
    const fx = parseFixture(readFileSync(join(dir, f), "utf8"));
    const Ns = fx.scenario.sweep ?? [fx.scenario.waiters ?? 1];
    const runs: Awaited<ReturnType<typeof replay>>[] = [];
    for (const N of Ns) runs.push(await replay(fx, N));
    for (const [i, r] of runs.entries()) {
      assert.deepEqual(r.problems, [], `N=${Ns[i]}`);
      assert.ok(windowMax(r.calls, 3600) <= 3000, `hour window ${windowMax(r.calls, 3600)} > B`);
      assert.ok(windowMax(r.calls, 60) <= 60, `minute window ${windowMax(r.calls, 60)} > B1`);
      for (const c of fx.scenario.expect?.counts ?? []) {
        const n = r.issued.filter((x) => c.from <= x.t && x.t < c.until && (c.kind === "any" || c.kind === x.kind)).length;
        assert.ok(n >= (c.min ?? 0) && n <= (c.max ?? 1e9), `N=${Ns[i]}: ${n} ${c.kind} issues in [${c.from}, ${c.until}), expected ${c.min}..${c.max}`);
      }
      if (fx.scenario.expect?.ticksPerHourMax !== undefined) {
        const ticks = r.calls.filter((c) => c.args[1] === "list");
        assert.ok(windowMax(ticks, 3600) / 2 <= fx.scenario.expect.ticksPerHourMax, "ticks per hour");
      }
    }
    // N does not change what is asked of GitHub
    const key = (r: (typeof runs)[number]) => JSON.stringify(r.issued);
    for (const r of runs) assert.equal(key(r), key(runs[0]!), "same issued calls for every N");
  });
}
