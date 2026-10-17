import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { ApplyResponse, ApplyRequest, Command } from "../src/index.ts";
import { allJsonSchemas } from "../src/schemas.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = (p: string) => JSON.parse(readFileSync(join(root, p), "utf8"));

describe("golden fixtures", () => {
  it("every command type has a golden example that parses", () => {
    const cmds = read("fixtures/commands.golden.json") as unknown[];
    for (const c of cmds) expect(Command.safeParse(c).success, JSON.stringify(c)).toBe(true);
    const types = new Set(cmds.map((c) => (c as { type: string }).type));
    const all = Command.options.map((o) => o.shape.type.value);
    expect([...types].sort()).toEqual([...all].sort());
  });

  it("rejects unknown types and missing keys", () => {
    expect(Command.safeParse({ type: "card.set_status", key: "x", actor: "owner", card: "a" }).success).toBe(false);
    expect(Command.safeParse({ type: "card.approve", actor: "lead", card: "a" }).success).toBe(false);
  });

  it("console-apply golden cases parse (fwcore samples must match this shape)", () => {
    const cases = readFileSync(join(root, "golden/console-apply.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l)) as { request: unknown; response: unknown }[];
    expect(cases.length).toBeGreaterThan(10);
    for (const c of cases) {
      expect(ApplyRequest.safeParse(c.request).success).toBe(true);
      expect(ApplyResponse.safeParse(c.response).success).toBe(true);
    }
  });
});

describe("json schema export", () => {
  it("committed schema/*.json equals the zod export (run `pnpm --filter @fw/contracts gen`)", () => {
    const files = readdirSync(join(root, "schema")).sort();
    const gen = allJsonSchemas();
    expect(files).toEqual(Object.keys(gen).map((n) => `${n}.schema.json`).sort());
    for (const [n, s] of Object.entries(gen)) expect(read(`schema/${n}.schema.json`)).toEqual(s);
  });
});
