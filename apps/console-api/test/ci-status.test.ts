// Task circleci-status: the CircleCI health verdict (TS stand-in of Fw.Obs.CiStatus) replayed from the Lean golden, the
// summary parse on a recorded status page body, the poll cadence and the router-input route.
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Hono } from "hono";
import { afterEach, describe, expect, it } from "vitest";
import { selectCore } from "../src/core/index.ts";
import { Store } from "../src/store.ts";
import { mountOps } from "../src/ops/routes.ts";
import {
  CiStatusPoller, MAX_AGE_MS, POLL_MS, decide, parseSummary, type Comp, type StatusFetch, type Verdict,
} from "../src/ops/ci-status.ts";

const here = dirname(fileURLToPath(import.meta.url));
const golden = readFileSync(join(here, "../../../packages/contracts/golden/obs/ci-status.jsonl"), "utf8")
  .split("\n").filter(Boolean).map((l) => JSON.parse(l));
const fixture = JSON.parse(readFileSync(join(here, "fixtures/ci-status/summary-2026-10-20.json"), "utf8"));

describe("Lean golden (lean/Fw/Obs/CiStatus.lean)", () => {
  it("the constants are the Lean constants", () => {
    const c = golden.find((g) => g.kind === "consts");
    expect({ pollMs: POLL_MS, maxAgeMs: MAX_AGE_MS }).toEqual({ pollMs: c.pollMs, maxAgeMs: c.maxAgeMs });
  });
  const rows = golden.filter((g) => g.kind === "reading");
  it("has the cases", () => expect(rows.length).toBeGreaterThan(10));
  for (const g of rows) {
    it(g.name, () => {
      const q = g.request;
      expect(decide({
        docker: q.docker as Comp, machine: q.machine as Comp, pipelines: q.pipelines as Comp, api: q.api as Comp,
        macos: q.macos as Comp, prevArm: q.prevArm as Verdict, prevMac: q.prevMac as Verdict, readAt: q.readAt, now: q.now,
      })).toEqual(g.response);
    });
  }
});

describe("parseSummary", () => {
  it("reads the recorded page: macOS degraded, the Arm components operational, the open incident kept", () => {
    const p = parseSummary(fixture);
    expect(p.states).toEqual({ docker: "operational", machine: "operational", pipelines: "operational", api: "operational", macos: "degraded_performance" });
    expect(p.incidents.map((i) => [i.name, i.components])).toEqual([["Increased wait times for macOS jobs on m4pro.large", ["macOS Jobs"]]]);
  });
  it("an unreadable body or an unknown status reads as unknown", () => {
    expect(Object.values(parseSummary("x").states).every((s) => s === "unknown")).toBe(true);
    const odd = { components: [{ name: "Docker Jobs", status: "on_fire" }] };
    expect(parseSummary(odd).states.docker).toBe("unknown");
  });
  it("a resolved incident is not open", () => {
    const j = { components: [], incidents: [{ name: "n", status: "resolved", components: [{ name: "Docker Jobs" }] }] };
    expect(parseSummary(j).incidents).toEqual([]);
  });
});

/** A fake page: a queue of replies, a clock the test advances, a count of reads. */
function rig(replies: { status?: number; retryAfterS?: number; body?: unknown }[]) {
  let t = 1_000_000;
  let reads = 0;
  const get: StatusFetch = async () => {
    const r = replies[Math.min(reads, replies.length - 1)]!;
    reads++;
    return { status: r.status ?? 200, retryAfterS: r.retryAfterS ?? null, json: async () => r.body ?? fixture };
  };
  return { poller: new CiStatusPoller(get, () => t), advance: (ms: number) => { t += ms; }, reads: () => reads };
}

describe("CiStatusPoller", () => {
  it("first view reads the page: Arm usable, macOS not", async () => {
    const r = rig([{}]);
    const v = await r.poller.view();
    expect(v.arm).toEqual({ verdict: "healthy", usable: true });
    expect(v.macos).toEqual({ verdict: "degraded", usable: false });
    expect(v.fresh).toBe(true);
    expect(r.reads()).toBe(1);
  });
  it("reads at most once per poll interval, however often it is asked", async () => {
    const r = rig([{}]);
    for (let i = 0; i < 20; i++) { await r.poller.view(); r.advance(Math.floor(POLL_MS / 40)); }
    await r.poller.view();
    expect(r.reads()).toBe(1);
    r.advance(POLL_MS);
    await r.poller.view();
    await Promise.resolve();
    expect(r.reads()).toBe(2);
  });
  it("a 429 holds the next read until Retry-After and leaves the Arm lane not usable once the reading is stale", async () => {
    const r = rig([{}, { status: 429, retryAfterS: 600 }]);
    await r.poller.view();
    r.advance(POLL_MS);
    await r.poller.view(); // starts the 429 read in the background
    await new Promise((res) => setTimeout(res, 0));
    r.advance(POLL_MS);
    const mid = await r.poller.view();
    expect(r.reads()).toBe(2); // the 429's Retry-After (600 s) has not passed
    expect(mid.error).toBe("HTTP 429");
    expect(mid.arm.usable).toBe(false); // the failed read left the states unknown
    r.advance(MAX_AGE_MS);
    const old = await r.poller.view();
    expect(old.fresh).toBe(false);
  });
  it("a failed first read: unknown, not usable", async () => {
    const r = rig([{ status: 500 }]);
    const v = await r.poller.view();
    expect(v.arm).toEqual({ verdict: "unknown", usable: false });
    expect(v.readAt).toBeNull();
  });
  it("an outage on Docker Jobs degrades Arm and a later failed read keeps it degraded", async () => {
    const down = { components: fixture.components.map((c: { name: string }) => (c.name === "Docker Jobs" ? { ...c, status: "major_outage" } : c)), incidents: [] };
    const r = rig([{ body: down }, { status: 500 }]);
    expect((await r.poller.view()).arm.verdict).toBe("degraded");
    r.advance(POLL_MS);
    await r.poller.view();
    await new Promise((res) => setTimeout(res, 0));
    expect((await r.poller.view()).arm).toEqual({ verdict: "degraded", usable: false });
  });
});

describe("GET /api/ci-status (router input)", () => {
  let stores: Store[] = [];
  afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
  it("serves the view with arm.usable", async () => {
    const store = await Store.open(mkdtempSync(join(tmpdir(), "fw-cistatus-")), selectCore());
    stores.push(store);
    const app = new Hono();
    mountOps(app, store, rig([{}]).poller);
    const r = await app.request("/api/ci-status");
    const b = (await r.json()) as { arm: { usable: boolean }; macos: { usable: boolean }; url: string; states: { docker: string } };
    expect(r.status).toBe(200);
    expect(b.arm.usable).toBe(true);
    expect(b.macos.usable).toBe(false);
    expect(b.states.docker).toBe("operational");
    expect(b.url).toBe("https://status.circleci.com");
  });
});
