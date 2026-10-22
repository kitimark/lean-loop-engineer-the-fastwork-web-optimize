// ci-span-skipped: land run 39722879593 (`gh run view --json workflowName,headSha,jobs`, trimmed to the gate-engine and browser-suite steps).
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { ciSpans, type GhRun } from "../src/timing.ts";
import { parseSamples } from "../src/watch-collect.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const fwcore = join(root, "lean/.lake/build/bin/fwcore");

const step = (name: string, conclusion: string, a: string, b: string) => ({ name, conclusion, startedAt: `2026-10-22T04:${a}Z`, completedAt: `2026-10-22T04:${b}Z` });
const leg = (l: string, a: string, b: string, steps: ReturnType<typeof step>[]) => ({ name: `land (${l})`, conclusion: "success", startedAt: `2026-10-22T04:${a}Z`, completedAt: `2026-10-22T04:${b}Z`, steps });
const skippedLeg = (l: string, a: string, b: string, at: string) =>
  leg(l, a, b, [step("Run ./.github/actions/gate-engine", "skipped", at, at), step(`browser suite: ${l}`, "skipped", at, at)]);
const ranLeg = (l: string, a: string, b: string, g0: string, g1: string, s1: string) =>
  leg(l, a, b, [step("Run ./.github/actions/gate-engine", "success", g0, g1), step(`browser suite: ${l}`, "success", g1, s1)]);
const run: GhRun = { workflowName: "land", headSha: "ce0ef03", jobs: [
  skippedLeg("check-sh", "32:08", "33:39", "33:37"),
  ranLeg("playwright-webkit", "32:08", "35:31", "32:52", "33:19", "35:27"),
  skippedLeg("suites-b", "32:08", "34:22", "34:18"),
  ranLeg("chromium", "32:09", "34:45", "32:52", "33:25", "34:42"),
  skippedLeg("suites-a", "32:08", "35:09", "35:06"),
] };

describe("skipped CI steps reach Lean as skipped samples", () => {
  const spans = ciSpans(39722879593, run);
  const samples = parseSamples(spans.map((s) => JSON.stringify(s)).join("\n"));
  it("ciSpans marks the six skipped steps (0 s, exit 0) and nothing else", () => {
    const sk = spans.filter((s) => s.skipped);
    expect(sk.map((s) => s.step).sort()).toEqual(["check-sh", "suites-a", "suites-b"].flatMap((l) =>
      [`land (${l})/Run ./.github/actions/gate-engine`, `land (${l})/browser suite: ${l}`]).sort());
    expect(sk.every((s) => s.durMs === 0 && s.exit === 0)).toBe(true);
    expect(spans.find((s) => s.step === "land (chromium)/Run ./.github/actions/gate-engine")).toMatchObject({ durMs: 33000, exit: 0 });
    expect(spans.filter((s) => !s.skipped).every((s) => !("skipped" in s))).toBe(true);
  });
  it("parseSamples carries skipped and exit as recorded", () => {
    expect(samples.length).toBe(spans.length);
    expect(samples.filter((s) => s.skipped).length).toBe(6);
    expect(samples.every((s) => s.exit === 0)).toBe(true);
    expect(parseSamples(JSON.stringify({ tool: "t", step: "s", durMs: 1, host: "ci", exit: null, skipped: "yes" }))).toEqual([{ tool: "t", step: "s", durMs: 1, host: "ci", load: 0 }]);
    expect(parseSamples(JSON.stringify({ tool: "t", step: "s", durMs: 1, host: "local", exit: 16 }))).toEqual([{ tool: "t", step: "s", durMs: 1, host: "local", load: 0, exit: 16 }]);
  });
  it.skipIf(!existsSync(fwcore))("fwcore obs.timing gives no verdict to a skipped sample", () => {
    const r = spawnSync(fwcore, [], { input: JSON.stringify({ id: 0, op: "obs.timing", samples }) + "\n", encoding: "utf8", timeout: 60_000 });
    const verdicts = (JSON.parse(r.stdout.trim().split("\n")[0]!) as { verdicts: { kind: string; step: string }[] }).verdicts.filter((v) => v.kind === "sample");
    expect(verdicts.map((v) => v.step)).toEqual(samples.filter((s) => !s.skipped).map((s) => s.step));
  });
});
