import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { SUBCOMMANDS, spanStep } from "../src/fw-groups.ts";
import { slotStep } from "../src/slot-span.ts";
import { runPhases } from "../src/run-phases.ts";

const main = readFileSync(new URL("../src/fw-main.ts", import.meta.url), "utf8");
const branches = main.split(/\} else if \(group === /).slice(1).map((b) => ({ group: /^"([a-z-]+)"/.exec(b)![1]!, head: b.split("\n")[0]!, body: b }));
const branchGroups = new Set([...main.matchAll(/group === "([a-z-]+)"/g)].map((m) => m[1]!));

describe("fw span names come from the CLI table", () => {
  it("every dispatch branch of fw-main.ts that reads rest[0] is a group of the table", () => {
    const reading = branches.filter((b) => /rest\[0\]/.test(b.body.split(/\n  \} else if \(group/)[0]!)).map((b) => b.group);
    const missing = [...new Set(reading)].filter((g) => !(g in SUBCOMMANDS));
    expect(missing).toEqual([]);
  });
  it("every `group === g && rest[0] === s` pair named in fw-main.ts is in the table", () => {
    const pairs = [...main.matchAll(/group === "([a-z-]+)" && \(?rest\[0\] === "([a-z-]+)"/g)].map((m) => [m[1]!, m[2]!] as const);
    expect(pairs.length).toBeGreaterThan(5);
    expect(pairs.filter(([g, s]) => !SUBCOMMANDS[g]?.includes(s))).toEqual([]);
  });
  it("every group in the table is a group fw-main.ts dispatches", () => {
    expect(Object.keys(SUBCOMMANDS).filter((g) => !branchGroups.has(g))).toEqual([]);
  });
  it("names group plus subcommand, flags and unknown groups stay the group", () => {
    expect(spanStep("ci", ["wait", "--branch", "x"])).toBe("ci wait");
    expect(spanStep("polish", ["plan"])).toBe("polish plan");
    expect(spanStep("polish", ["--staged"])).toBe("polish staged");
    expect(spanStep("preview", ["grant"])).toBe("preview grant");
    expect(spanStep("status", [])).toBe("status");
    expect(spanStep("ci", ["--help"])).toBe("ci");
  });
  it("a dry land is its own step", () => {
    expect(spanStep("land", ["b", "--task", "t", "--dry"])).toBe("land dry");
    expect(spanStep("land", ["b", "--task", "t"])).toBe("land");
  });
});

describe("slot span names", () => {
  it("key by subcommand and kind", () => {
    expect(slotStep(["run", "--kind", "check", "--cache", "--", "sh", "x", "--kind", "y"])).toBe("slot run check");
    expect(slotStep(["run", "--kind", "test", "--", "pnpm"])).toBe("slot run test");
    expect(slotStep(["acquire", "--kind", "sim", "--lease", "60"])).toBe("slot acquire sim");
    expect(slotStep(["admit", "--kind", "build"])).toBe("slot admit");
    expect(slotStep(["status", "--json"])).toBe("slot status");
    expect(slotStep(["run", "--", "x"])).toBe("slot run");
    expect(slotStep([])).toBe("slot");
    expect(spanStep("slot", ["run", "--kind", "land", "--", "x"])).toBe("slot run land");
  });
});

describe("fw run phases", () => {
  const rec = () => {
    const out: { step: string; exit: number | null | undefined; extra?: object }[] = [];
    const begin = (_t: string, step: string) => (exit?: number | null, extra?: object) => { out.push({ step, exit, extra }); };
    return { out, begin };
  };
  const done = { code: 0, lines: ["run 123 success"] };
  it("splits a dispatch into dispatch, wait (with the run id) and file", async () => {
    const { out, begin } = rec();
    const ph = runPhases(begin as never, false);
    const gh = ph.gh((async () => "") as never), wait = ph.wait((async () => done) as never);
    await gh(["workflow", "run", "x.yml"]);
    await wait({ kind: "run", runId: 1 } as never, 10);
    await gh(["run", "download", "123"]);
    ph.finish(0);
    expect(out.map((o) => o.step)).toEqual(["run dispatch", "run wait", "run file"]);
    expect(out[1]!.extra).toEqual({ runId: 123 });
  });
  it("a wait slice that timed out (code 3) stays in the same wait span; a second job starts a new dispatch", async () => {
    const { out, begin } = rec();
    const ph = runPhases(begin as never, false);
    let n = 0;
    const gh = ph.gh((async () => "") as never), wait = ph.wait((async () => (n++ === 0 ? { code: 3, lines: [] } : done)) as never);
    await gh(["workflow", "run", "x.yml"]);
    await wait({} as never, 10); await wait({} as never, 10);
    await gh(["workflow", "run", "y.yml"]);
    ph.finish(2);
    expect(out.map((o) => o.step)).toEqual(["run dispatch", "run wait", "run file", "run dispatch", "run wait"]);
    expect(out[4]!.exit).toBe(2);
  });
  it("a run waited with --from-run has no dispatch call: the first wait ends the dispatch span", async () => {
    const { out, begin } = rec();
    const ph = runPhases(begin as never, false);
    await ph.wait((async () => done) as never)({} as never, 10);
    ph.finish(0);
    expect(out.map((o) => o.step)).toEqual(["run dispatch", "run wait", "run file"]);
  });
  it("a dry run is one run dry span", () => {
    const { out, begin } = rec();
    const ph = runPhases(begin as never, true);
    ph.finish(0);
    expect(out.map((o) => o.step)).toEqual(["run dry"]);
  });
});
