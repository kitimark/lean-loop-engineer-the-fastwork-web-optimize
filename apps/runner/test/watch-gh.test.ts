import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { GH_STATUS_URL, bodyText, collectGh, ghFlagged, parseGhSummary } from "../src/watch-gh.ts";
import { coreCaller } from "../src/watch.ts";

const here = dirname(fileURLToPath(import.meta.url));
const fx = (n: string): unknown => JSON.parse(readFileSync(join(here, "fixtures/gh-status", n), "utf8"));
const bin = process.env.FW_CORE_BIN ?? join(here, "../../../lean/.lake/build/bin/fwcore");
const core = coreCaller(existsSync(bin) ? [bin] : []);
const runCore = existsSync(bin) ? it : it.skip;

const healthGolden = readFileSync(join(here, "../../../packages/contracts/golden/obs/health.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown> & { system: Record<string, unknown> }; response: { alerts: { code: string; detail: string }[] } });

describe("parseGhSummary (recorded githubstatus fixtures)", () => {
  it("operational: three states, no incident", () => {
    expect(parseGhSummary(fx("operational.json"))).toEqual({ actions: "operational", pages: "operational", webhooks: "operational", incidents: [] });
  });
  it("2026-10-19 incident: Actions, Pages and Webhooks degraded, the incident with its newest update", () => {
    const g = parseGhSummary(fx("degraded-2026-10-19.json"));
    expect([g.actions, g.pages, g.webhooks]).toEqual(["degraded_performance", "degraded_performance", "degraded_performance"]);
    expect(g.incidents).toHaveLength(1);
    const i = g.incidents[0]!;
    expect(i.name).toBe("Degraded availability for GitHub Actions, GitHub Pages and Webhooks");
    expect([i.status, i.impact, i.actions]).toEqual(["investigating", "critical", true]);
    expect(i.createdAt).toBe(Date.parse("2026-10-19T15:49:25.828Z"));
    expect(i.updatedAt).toBe(Date.parse("2026-10-19T16:30:29.646Z"));
    expect(i.body.startsWith("We’re seeing recovery following mitigation")).toBe(true);
    expect(i.body).not.toMatch(/<|>/);
    expect([...i.body].length).toBeLessThanOrEqual(200);
  });
  it("a malformed body or an unknown state reads as unknown", () => {
    expect(parseGhSummary(null).actions).toBe("unknown");
    expect(parseGhSummary({ components: [{ name: "Actions", status: "on_fire" }] }).actions).toBe("unknown");
    expect(parseGhSummary({ components: [] })).toEqual({ actions: "unknown", pages: "unknown", webhooks: "unknown", incidents: [] });
  });
  it("incidents that touch no kept component or are resolved are dropped; a Pages-only incident has actions=false", () => {
    const comps = [{ name: "Actions", status: "operational" }];
    const inc = (name: string, over: object) => ({ name, status: "investigating", impact: "minor", created_at: "2026-10-19T10:00:00Z",
      updated_at: "2026-10-19T10:05:00Z", incident_updates: [], ...over });
    const g = parseGhSummary({ components: comps, incidents: [
      inc("Issues slow", { components: [{ name: "Issues" }] }),
      inc("Pages slow", { components: [{ name: "Pages" }] }),
      inc("Old", { components: [{ name: "Actions" }], resolved_at: "2026-10-19T11:00:00Z" }),
    ] });
    expect(g.incidents.map((i) => [i.name, i.actions])).toEqual([["Pages slow", false]]);
  });
  it("bodyText strips tags and keeps 200 characters", () => {
    expect(bodyText("a<br /><br />b  c")).toBe("a b c");
    expect([...bodyText("x".repeat(300))]).toHaveLength(200);
  });
});

describe("collectGh", () => {
  it("reads the summary once with a 10 s timeout and carries prevDegraded", async () => {
    const calls: [string, number][] = [];
    const g = await collectGh(true, async (u, t) => { calls.push([u, t]); return fx("operational.json"); });
    expect(calls).toEqual([[GH_STATUS_URL, 10_000]]);
    expect(g).toEqual({ actions: "operational", pages: "operational", webhooks: "operational", prevDegraded: true, incidents: [] });
  });
  it("a failed fetch reads as unknown, keeps prevDegraded and never throws", async () => {
    const g = await collectGh(true, async () => { throw new Error("network down"); });
    expect(g).toEqual({ actions: "unknown", pages: "unknown", webhooks: "unknown", prevDegraded: true, incidents: [] });
    expect((await collectGh(false, async () => { throw new Error("HTTP 503"); })).prevDegraded).toBe(false);
  });
  it("ghFlagged reads the logged system alert codes", () => {
    expect(ghFlagged({ system: { alerts: ["ci.slow", "sys.ghDegraded"] } })).toBe(true);
    expect(ghFlagged({ system: { alerts: ["ci.slow"] } })).toBe(false);
    expect(ghFlagged(null)).toBe(false);
  });
});

const sys = (gh: object) => ({ diskFreeGB: 100, worktrees: 3,
  ci: [{ workflow: "lean", branch: "ci/x", status: "queued", conclusion: null, startedAt: 1_792_000_000_000 - 30 * 60_000 }], gh });
const ask = (gh: object) => core({ op: "obs.health", now: 1_792_000_000_000, system: sys(gh) }) as Promise<{ alerts: { code: string; detail: string }[]; system: { alerts: string[] } }>;

describe("fwcore decides the flag from the collected reading", () => {
  runCore("degraded fixture: sys.ghDegraded, and the slow run names the incident", async () => {
    const r = await ask(await collectGh(false, async () => fx("degraded-2026-10-19.json")));
    expect(r.system.alerts).toContain("sys.ghDegraded");
    const slow = r.alerts.find((a) => a.code === "ci.slow")!;
    expect(slow.detail).toContain("Degraded availability for GitHub Actions, GitHub Pages and Webhooks");
    expect(slow.detail).toContain("since 15:49 UTC");
    expect(r.alerts.find((a) => a.code === "sys.ghDegraded")!.detail).toContain("degraded_performance");
  });
  runCore("operational fixture: no flag, the slow run is plain", async () => {
    const r = await ask(await collectGh(true, async () => fx("operational.json")));
    expect(r.system.alerts).not.toContain("sys.ghDegraded");
    expect(r.alerts.find((a) => a.code === "ci.slow")!.detail).toBe("queued for 30 min");
  });
  runCore("fetch failure: the previous flag stays, a clear pass stays clear", async () => {
    const down = async () => { throw new Error("down"); };
    expect((await ask(await collectGh(true, down))).system.alerts).toContain("sys.ghDegraded");
    expect((await ask(await collectGh(false, down))).system.alerts).not.toContain("sys.ghDegraded");
  });
});

describe("a carried run list names its age (watch-ci-stale: finished runs read as in_progress for 22 min)", () => {
  runCore("fresh list: plain detail; list 22 min old: the age ends the detail; the limit itself adds nothing", async () => {
    expect((await ask({ ciAgeMs: 0 })).alerts.find((a) => a.code === "ci.slow")!.detail).toBe("queued for 30 min");
    expect((await ask({ ciAgeMs: 240_000 })).alerts.find((a) => a.code === "ci.slow")!.detail).toBe("queued for 30 min");
    expect((await ask({ ciAgeMs: 22 * 60_000 + 5000 })).alerts.find((a) => a.code === "ci.slow")!.detail).toBe("queued for 30 min (CI data 22 min old)");
  });
});

describe("the Lean golden agrees with the collector", () => {
  it("the golden degraded request holds the reading the collector yields for the recorded incident", async () => {
    const row = healthGolden.find((g) => g.name.startsWith("gh-status: Actions degraded_performance"))!;
    expect(row.request.system.gh).toEqual(await collectGh(false, async () => fx("degraded-2026-10-19.json")));
  });
});
