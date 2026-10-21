import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { ApplyResponse, ApplyRequest, LiveBoard, Command, Plan, ReducerEvent, ObsRecord } from "../src/index.ts";
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

describe("obs records (spool)", () => {
  it("a SpawnGuard record with the spawn-guard-workflows fields parses (strict schema)", () => {
    const rec = { agent_id: "a1", agent_type: "lean-prover", hook_event_name: "SpawnGuard", tool_name: "Agent", tool_use_id: "t1",
      duration_ms: null, is_error: false, verb: "allow", agent_name: "watch-fix", seen_by: "subagent-start", role: "lean-prover",
      want_kind: "subagent", got_kind: "subagent", isolation: true, depth: 1, has_name: true, ts: 1 };
    expect(ObsRecord.safeParse(rec).success).toBe(true);
    expect(ObsRecord.safeParse({ ...rec, surprise: 1 }).success).toBe(false); // still strict
  });
});

describe("review.feedback text cap: the unit is Lean's (characters = code points), golden console/reviewFeedback", () => {
  const cases = readFileSync(join(root, "golden/console/reviewFeedback.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l)) as
    { name: string; request: { events: { text: string; flag: string; id: string; type: string }[] }; response: { threads: { comments: unknown[] }[] } }[];
  const cmd = (type: string, text: string) => ({ type, key: "k1", actor: type === "review.feedback" ? "user" : "lead", flag: "nav:a", ...(type === "review.feedback" ? { id: "fb-1" } : { to: "fb-1" }), text });
  it("Lean accepts 2000 astral characters (4000 UTF-16 units) and ignores 2001; the zod command parses exactly the same texts", () => {
    const accepted = cases.find((c) => c.name.startsWith("a text of 2000 astral"))!;
    const refused = cases.find((c) => c.name.startsWith("a text of 2001 astral"))!;
    const at = accepted.request.events[0]!.text, over = refused.request.events[0]!.text;
    expect([...at].length).toBe(2000); expect(at.length).toBe(4000);
    expect([...over].length).toBe(2001);
    expect(accepted.response.threads[0]!.comments).toHaveLength(1); // Lean: accepted
    expect(refused.response.threads).toEqual([]);                   // Lean: refused
    for (const type of ["review.feedback", "review.feedback.reply"]) {
      expect(Command.safeParse(cmd(type, at)).success, `${type} at the cap`).toBe(true);
      expect(Command.safeParse(cmd(type, over)).success, `${type} over the cap`).toBe(false);
      expect(Command.safeParse(cmd(type, "")).success, `${type} empty`).toBe(false);
    }
  });
  it("the cap counts characters, not UTF-16 units, for plain text too: 2000 'a' parse, 2001 do not", () => {
    expect(Command.safeParse(cmd("review.feedback", "a".repeat(2000))).success).toBe(true);
    expect(Command.safeParse(cmd("review.feedback", "a".repeat(2001))).success).toBe(false);
  });
});

describe("step topics", () => {
  const post = { type: "step.post", key: "k1", actor: "lead", step: "s1", card: null, title: "t", kind: "action", options: null };
  const topic = { type: "step.topic", key: "k2", actor: "lead", topic: "smoothness", title: "Smoothness", summary: "Hero exit first." };
  it("a step may carry a topic id, null or none", () => {
    expect(Command.safeParse({ ...post, topic: "smoothness" }).success).toBe(true);
    expect(Command.safeParse({ ...post, topic: null }).success).toBe(true);
    expect(Command.safeParse(post).success).toBe(true);
    expect(Command.safeParse({ ...post, topic: "" }).success).toBe(false);
  });
  it("a topic definition needs a title of at most 120 characters and a summary of at most 2000", () => {
    expect(Command.safeParse(topic).success).toBe(true);
    expect(Command.safeParse({ ...topic, title: "a".repeat(120) }).success).toBe(true);
    expect(Command.safeParse({ ...topic, title: "a".repeat(121) }).success).toBe(false);
    expect(Command.safeParse({ ...topic, summary: "a".repeat(2001) }).success).toBe(false);
    expect(Command.safeParse({ ...topic, summary: "" }).success).toBe(false);
  });
});
