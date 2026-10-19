import { appendFileSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.ts";
import { selectCore } from "../src/core/index.ts";
import { Store } from "../src/store.ts";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });

// synthetic fixture: the output is what fwcore would say; the API must pass it through unchanged
const line = (at: number) => JSON.stringify({
  at,
  input: {
    now: at,
    agents: [
      { id: "a1", name: "alpha", kind: "teammate", lastAt: at - 60000, errTail: 0, inflight: { tool: "Bash", since: at - 1000 }, ctxTokens: 1234 },
      { id: "a2", task: "beta-task", kind: "subagent", lastAt: at - 9000000, errTail: 3 },
    ],
    system: { diskFreeGB: 7, memPressure: "normal", simLock: { holder: "x", since: at - 5 }, docker: [{ name: "c1", startedAt: 1 }],
      worktrees: 3, ci: [{ workflow: "w", branch: "b", status: "completed", conclusion: "failure", startedAt: 2 }], stale: ["ci"] },
  },
  output: {
    agents: [{ id: "a1", state: "active", alerts: [] }, { id: "a2", state: "stalled", alerts: ["agent.stalled"] }],
    system: { alerts: ["ci.failed", "sys.diskLow"] },
    counts: { active: 1, idle: 0, parked: 0, stalled: 1, gone: 2, done: 0 },
    alerts: [{ code: "agent.stalled", subject: "beta-task", detail: "d1", critical: true }, { code: "ci.failed", subject: "w", detail: "d2" }],
  },
});

async function get(write?: (dir: string) => void) {
  const dir = mkdtempSync(join(tmpdir(), "fw-health-"));
  const store = await Store.open(dir, selectCore());
  stores.push(store);
  write?.(dir);
  const r = await createApp(store).request("/api/health");
  return { status: r.status, body: (await r.json()) as any };
}

describe("service info (console-stale)", () => {
  const service = { commit: "21c8c42", startedAt: 1_760_000_000_000 };
  async function getWith(path: string, write?: (dir: string) => void) {
    const dir = mkdtempSync(join(tmpdir(), "fw-health-"));
    const store = await Store.open(dir, selectCore());
    stores.push(store);
    write?.(dir);
    return (await createApp(store, undefined, undefined, undefined, undefined, service).request(path)).json() as Promise<any>;
  }
  it("/api/health carries the code commit and start time next to the check", async () => {
    const b = await getWith("/api/health", (d) => writeFileSync(join(d, "health.jsonl"), line(1000) + "\n"));
    expect(b.service).toEqual(service);
    expect(b.at).toBe(1000);
  });
  it("/api/health stays null before any check; /api/service answers regardless", async () => {
    expect(await getWith("/api/health")).toBeNull();
    expect(await getWith("/api/service")).toEqual(service);
  });
});

describe("GET /api/health", () => {
  it("null before any check", async () => {
    expect(await get()).toEqual({ status: 200, body: null });
  });
  it("serves the newest line with Lean's alert order and states untouched", async () => {
    const r = await get((d) => {
      writeFileSync(join(d, "health.jsonl"), line(1000) + "\n");
      appendFileSync(join(d, "health.jsonl"), line(2000) + "\n" + '{"torn":');
    });
    expect(r.status).toBe(200);
    expect(r.body.at).toBe(2000);
    expect(r.body.alerts.map((a: { code: string }) => a.code)).toEqual(["agent.stalled", "ci.failed"]);
    expect(r.body.systemAlerts).toEqual(["ci.failed", "sys.diskLow"]);
    expect(r.body.agents.map((a: { label: string; state: string }) => [a.label, a.state])).toEqual([["alpha", "active"], ["beta-task", "stalled"]]);
    expect(r.body.agents[0].inflight.tool).toBe("Bash");
    expect(r.body.system.stale).toEqual(["ci"]);
    expect(r.body.counts.stalled).toBe(1);
    expect(r.body.counts.gone).toBe(2);
    expect(r.body.alerts.map((a: { critical: boolean }) => a.critical)).toEqual([true, false]); // absent -> false
  });
});

describe("GitHub status (gh-status)", () => {
  const inc = { name: "Degraded availability for GitHub Actions, GitHub Pages and Webhooks", status: "investigating", impact: "critical",
    createdAt: 1_792_424_965_828, updatedAt: 1_792_427_429_646, body: "We are seeing recovery.", actions: true };
  const withGh = (gh: object | undefined, codes: string[], alerts: object[] = []) => {
    const l = JSON.parse(line(1_792_430_000_000));
    l.input.system.gh = gh;
    l.output.system.alerts = codes;
    l.output.alerts = alerts;
    return JSON.stringify(l);
  };
  it("passes the collected reading through and takes the flag from fwcore's alert", async () => {
    const alert = { code: "sys.ghDegraded", subject: "github", detail: `Actions degraded_performance: ${inc.name}` };
    const r = await get((d) => writeFileSync(join(d, "health.jsonl"),
      withGh({ actions: "degraded_performance", pages: "degraded_performance", webhooks: "operational", incidents: [inc] }, ["sys.ghDegraded"], [alert]) + "\n"));
    expect(r.body.gh).toEqual({ actions: "degraded_performance", pages: "degraded_performance", webhooks: "operational",
      incidents: [inc], degraded: true, alert: alert.detail });
  });
  it("an operational reading is not degraded; an unknown reading with no alert stays unflagged", async () => {
    const ok = await get((d) => writeFileSync(join(d, "health.jsonl"),
      withGh({ actions: "operational", pages: "operational", webhooks: "operational", incidents: [] }, []) + "\n"));
    expect(ok.body.gh).toMatchObject({ actions: "operational", degraded: false, alert: null, incidents: [] });
    const unk = await get((d) => writeFileSync(join(d, "health.jsonl"), withGh({ actions: "unknown" }, []) + "\n"));
    expect(unk.body.gh).toMatchObject({ actions: "unknown", pages: "unknown", degraded: false });
  });
  it("a line without a reading (written before gh-status) has gh null", async () => {
    const r = await get((d) => writeFileSync(join(d, "health.jsonl"), line(1000) + "\n"));
    expect(r.body.gh).toBeNull();
  });
});
