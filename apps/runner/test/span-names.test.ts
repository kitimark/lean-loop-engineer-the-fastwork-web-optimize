import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { SUBCOMMANDS, spanStep } from "../src/fw-groups.ts";
import { slotStep, writesOwnSpans } from "../src/slot-span.ts";

const main = readFileSync(new URL("../src/fw-main.ts", import.meta.url), "utf8");
const branchGroups = new Set([...main.matchAll(/group === "([a-z-]+)"/g)].map((m) => m[1]!));

const usage = /throw new UsageError\(`usage: fw status[^`]*`/.exec(main)![0];
const usageGroups = [...usage.matchAll(/fw ([a-z-]+) ((?:[a-z-]+\|)*[a-z-]+)(?= |\||\\|`|$)/g)].map((m) => ({ g: m[1]!, alts: m[2]!.split("|").filter((a) => /^[a-z][a-z-]*$/.test(a)) }));
const LIST_OWNERS: Record<string, string[]> = { plan: ["plan"], ci: ["ci"], incidents: ["incidents"], step: ["lib", "step-threads"], card: ["card"], task: ["lib"], console: ["console"],
  review: ["review", "review-ready"], oracle: ["oracle"], polish: ["polish"], preview: ["preview"], slot: ["slot-span"] };

describe("fw span names come from the modules' own verb lists", () => {
  it("every `fw <g> a|b|...` group of the usage text is a SUBCOMMANDS key holding each alternative", () => {
    const multi = usageGroups.filter((u) => u.alts.length > 1 && u.g !== "land");
    expect(multi.map((u) => u.g)).toEqual(expect.arrayContaining(["console", "step", "task", "review", "polish"]));
    for (const u of multi) {
      expect(SUBCOMMANDS[u.g], `group ${u.g} is missing from SUBCOMMANDS`).toBeDefined();
      for (const a of u.alts) expect(SUBCOMMANDS[u.g], `${u.g} lacks ${a}`).toContain(a);
    }
  });
  it("every subcommand pair `fw g sub` in the usage text is in the table", () => {
    for (const u of usageGroups) if (SUBCOMMANDS[u.g]) for (const a of u.alts) expect(SUBCOMMANDS[u.g], `${u.g} lacks ${a}`).toContain(a);
  });
  it("every SUBCOMMANDS key has a non-empty list, imported from its module (no hand list in fw-groups.ts)", () => {
    const src = readFileSync(new URL("../src/fw-groups.ts", import.meta.url), "utf8");
    const table = src.slice(src.indexOf("export const SUBCOMMANDS"), src.indexOf("};", src.indexOf("export const SUBCOMMANDS")));
    expect(Object.keys(SUBCOMMANDS).sort()).toEqual(Object.keys(LIST_OWNERS).sort());
    for (const g of Object.keys(SUBCOMMANDS)) {
      expect(SUBCOMMANDS[g]!.length, g).toBeGreaterThan(0);
      expect(table, `${g} is not built from an imported list`).toMatch(new RegExp(`\\b${g}: [\\[.A-Z_a-z, ]*[A-Z]+_(VERBS|SUBS)`));
      expect(table, `${g} holds a string literal`).not.toMatch(new RegExp(`\\b${g}: [^\\n]*"`));
    }
    for (const owners of Object.values(LIST_OWNERS)) for (const o of owners) expect(src).toContain(`"./${o}.ts"`);
  });
  it("the oracle list holds score and arm-input", () => {
    expect(SUBCOMMANDS.oracle).toEqual(expect.arrayContaining(["score", "arm-input", "ask", "send"]));
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

describe("slot spans keep dry apart", () => {
  it("a wrapped --dry argv adds dry; slot run writes its own spans", () => {
    expect(slotStep(["run", "--kind", "land", "--cache", "--", "pnpm", "-s", "fw", "land", "b", "--dry"])).toBe("slot run land dry");
    expect(slotStep(["run", "--kind", "land", "--", "pnpm", "-s", "fw", "land", "b"])).toBe("slot run land");
    expect(slotStep(["status", "--dry"])).toBe("slot status");
    expect(writesOwnSpans(["run", "--kind", "test", "--", "pnpm", "test"])).toBe(true);
    expect(writesOwnSpans(["acquire", "--kind", "sim"])).toBe(false);
  });
});

