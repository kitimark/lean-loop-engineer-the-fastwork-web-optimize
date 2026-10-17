import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { ApplyResponse, ApplyRequest, LiveBoard, Command, Plan, ReducerEvent } from "../src/index.ts";
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

describe("plan golden (lean-plan, packages/contracts/golden/plan)", () => {
  type Reply = { board?: { plan: unknown } };
  for (const f of ["serve.jsonl", "work-graph.jsonl"]) {
    it(`${f}: every request command and board plan parses`, () => {
      const lines = readFileSync(join(root, "golden/plan", f), "utf8").trim().split("\n").map((l) => JSON.parse(l)) as
        { requests: { op: string; event?: unknown }[]; replies: Reply[] }[];
      let boards = 0;
      for (const c of lines) {
        // an event Lean accepted must parse; one it refused may be refused by zod at the door as well (length limits)
        c.requests.forEach((r, i) => {
          if (r.op !== "console.apply") return;
          const out = (c.replies[i] as { outcome?: { accepted: boolean } }).outcome;
          if (out?.accepted) expect(ReducerEvent.safeParse(r.event).success, JSON.stringify(r.event)).toBe(true);
        });
        for (const r of c.replies) {
          if (r.board) { expect(Plan.safeParse(r.board.plan).success).toBe(true); expect(LiveBoard.safeParse(r.board).success).toBe(true); boards++; }
        }
      }
      expect(boards).toBeGreaterThan(0);
    });
  }
});

describe("json schema export", () => {
  it("committed schema/*.json equals the zod export (run `pnpm --filter @fw/contracts gen`)", () => {
    const files = readdirSync(join(root, "schema")).sort();
    const gen = allJsonSchemas();
    expect(files).toEqual(Object.keys(gen).map((n) => `${n}.schema.json`).sort());
    for (const [n, s] of Object.entries(gen)) expect(read(`schema/${n}.schema.json`)).toEqual(s);
  });
});
