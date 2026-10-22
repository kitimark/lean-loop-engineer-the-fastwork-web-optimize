// watch-incremental: the transcript fold resumed from saved state equals the whole-file read (Lean Fw.Obs.Fold:
// `pass_eq_full`), the cache decision and the line cut are the Lean golden (obs/watch-fold.jsonl), and the spool memo
// changes nothing. Fixtures are made up.
import { appendFileSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, statSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { codeHash, cutAt, decide, foldFile } from "../src/watch-cache.ts";
import { FOLD_SCHEMA, finishInfo, finishSignals, foldText, initFold, loadFold, saveFold } from "../src/watch-fold.ts";
import { collectAgents, pathsFor, readTranscript, signalsOf, summarizeTranscript } from "../src/watch-collect.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const dirs: string[] = [];
const tmp = () => { const d = mkdtempSync(join(tmpdir(), "fw-fold-")); dirs.push(d); return d; };
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

type Case = { name: string; kind: string; [k: string]: any };
const golden: Case[] = readFileSync(join(root, "packages/contracts/golden/obs/watch-fold.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));

describe("the Lean golden vectors", () => {
  it("has both kinds", () => {
    expect(golden.filter((c) => c.kind === "cut").length).toBeGreaterThan(5);
    expect(golden.filter((c) => c.kind === "decide").length).toBeGreaterThan(5);
  });
  for (const c of golden.filter((g) => g.kind === "cut")) {
    it(`cut: ${c.name}`, () => {
      const buf = Buffer.from(c.text, "utf8");
      const k = cutAt(buf);
      expect(k).toBe(c.consumed);
      expect(buf.length - k).toBe(c.tail);
      expect(c.text.split("\n").filter(Boolean).length).toBe(c.lines);
    });
  }
  for (const c of golden.filter((g) => g.kind === "decide")) {
    it(`decide: ${c.name}`, () => {
      const m = decide(c.entry, c.now, () => c.anchorSame);
      expect(m.mode).toBe(c.expect.mode);
      if (c.expect.mode === "resume") expect((m as { offset: number }).offset).toBe(c.expect.offset);
    });
  }
  it("does not read the anchor when an earlier check failed", () => {
    const e = { schema: 1, code: "c", ino: 1, offset: 5 };
    expect(decide(e, { schema: 2, code: "c", ino: 1, size: 9 }, () => { throw new Error("read"); }).mode).toBe("full");
  });
});

const T0 = Date.parse("2026-01-01T00:00:00Z");
const iso = (s: number) => new Date(T0 + s * 1000).toISOString();
const rec = (o: object) => JSON.stringify(o);
const use = (s: number, id: string, name: string, input: object = {}) =>
  rec({ type: "assistant", timestamp: iso(s), message: { id: `m${s}`, model: "m-1", usage: { input_tokens: s, output_tokens: 2, cache_read_input_tokens: 3, cache_creation_input_tokens: 4 }, role: "assistant", content: [{ type: "tool_use", id, name, input }] } });
const result = (s: number, id: string, text: string, extra: object = {}) =>
  rec({ type: "user", timestamp: iso(s), message: { role: "user", content: [{ type: "tool_result", tool_use_id: id, content: text, ...(extra as any).err }] }, ...extra });
const say = (s: number, text: string) =>
  rec({ type: "assistant", timestamp: iso(s), message: { role: "assistant", stop_reason: "end_turn", content: [{ type: "text", text }] } });
const note = (s: number, id: string) =>
  rec({ type: "attachment", timestamp: iso(s), attachment: { type: "queued_command", prompt: `<task-notification><task-id>${id}</task-id><status>completed</status><summary>done é</summary></task-notification>` } });
const lines = [
  rec({ type: "user", timestamp: iso(0), origin: { kind: "human" }, message: { role: "user", content: "go" } }),
  use(1, "u1", "Bash", { command: "sleep 1 &" }), result(2, "u1", "Command running in background with ID: bg1. Output is being written to: /x/bg1.output", { toolUseResult: { backgroundTaskId: "bg1" } }),
  use(3, "u2", "Agent"), result(4, "u2", "ok", { toolUseResult: { status: "async_launched", agentId: "ch1" } }),
  use(5, "u3", "Read"), result(6, "u3", "boom", { err: { is_error: true } }),
  "not json {", "", note(7, "bg1"), use(8, "u4", "StructuredOutput"),
  result(9, "u4", "ok", { toolEndsTurn: true, toolUseResult: { success: true } }), say(10, "done é中"),
];
const whole = lines.join("\n") + "\n";
const view = (st: ReturnType<typeof initFold>) => JSON.stringify([finishInfo(st, { finished: true }, T0), finishSignals("a", st).facts, st.sig.lastAt]);

describe("fold = the old whole-text functions", () => {
  it("summarizeTranscript and signalsOf are the folds", () => {
    const st = foldText(initFold(true), whole);
    expect(summarizeTranscript(whole, { finished: true }, T0)).toEqual(finishInfo(st, { finished: true }, T0));
    expect(signalsOf("a", whole).facts).toEqual(finishSignals("a", st).facts);
    expect(signalsOf("a", whole).commands.get("bg1")).toBe("sleep 1 &");
    expect(foldText(initFold(false), whole).sig.commands.size).toBe(0);
  });
  it("append lemma: folding the two halves of any line cut equals folding the whole", () => {
    const full = view(foldText(initFold(false), whole));
    for (let k = 0; k <= lines.length; k++) {
      const head = lines.slice(0, k).map((l) => l + "\n").join(""), rest = whole.slice(head.length);
      expect(view(foldText(foldText(initFold(false), head), rest))).toBe(full);
    }
  });
  it("the saved form round-trips and holds no command text", () => {
    const st = foldText(initFold(true), whole);
    const j = JSON.stringify(saveFold(st));
    expect(j).not.toContain("sleep 1");
    expect(view(loadFold(JSON.parse(j))!)).toBe(view(foldText(initFold(false), whole)));
    expect(loadFold({ sum: 1 })).toBeNull();
  });
});

describe("foldFile resumes at any byte cut", () => {
  it("every byte offset gives the whole-file result, the next pass reads only the new bytes", () => {
    const d = tmp(), f = join(d, "agent-a.jsonl"), cache = join(d, "cache");
    const bytes = Buffer.from(whole, "utf8");
    const full = view(foldText(initFold(false), whole));
    for (let k = 0; k <= bytes.length; k += 7) {
      rmSync(cache, { recursive: true, force: true });
      writeFileSync(f, bytes.subarray(0, k));
      const a = foldFile(f, statSync(f).size, statSync(f).ino, cache);
      expect(view(a.state)).toBe(view(foldText(initFold(false), bytes.subarray(0, k).toString("utf8"))));
      appendFileSync(f, bytes.subarray(k));
      const b = foldFile(f, statSync(f).size, statSync(f).ino, cache);
      expect(view(b.state)).toBe(full);
      if (k > 0 && cutAt(bytes.subarray(0, k)) > 0) { expect(b.how).toBe("resumed"); expect(b.read).toBeLessThan(bytes.length); }
    }
  });
  it("a torn last line is not saved, and counts once it is whole", () => {
    const d = tmp(), f = join(d, "agent-a.jsonl"), cache = join(d, "cache");
    writeFileSync(f, lines.slice(0, 3).join("\n") + "\n" + use(20, "u9", "Bash").slice(0, 30));
    const a = foldFile(f, statSync(f).size, statSync(f).ino, cache);
    expect(a.state.sum.toolUses).toBe(1);
    appendFileSync(f, use(20, "u9", "Bash").slice(30) + "\n");
    const b = foldFile(f, statSync(f).size, statSync(f).ino, cache);
    expect(b.how).toBe("resumed");
    expect(b.state.sum.toolUses).toBe(2);
  });
  it("a complete last line without a newline counts in the pass but is read again next time", () => {
    const d = tmp(), f = join(d, "agent-a.jsonl"), cache = join(d, "cache");
    writeFileSync(f, lines.slice(0, 3).join("\n") + "\n" + use(20, "u9", "Bash"));
    expect(foldFile(f, statSync(f).size, statSync(f).ino, cache).state.sum.toolUses).toBe(2);
    appendFileSync(f, "\n");
    const b = foldFile(f, statSync(f).size, statSync(f).ino, cache);
    expect(b.state.sum.toolUses).toBe(2);
    expect(b.how).toBe("resumed");
  });
  it("reads a line larger than the chunk and a multi-byte character cut by it", () => {
    const d = tmp(), f = join(d, "agent-a.jsonl");
    const big = rec({ type: "assistant", timestamp: iso(1), message: { role: "assistant", content: [{ type: "text", text: "é".repeat(5_000_000) }] } });
    writeFileSync(f, big + "\n" + use(2, "u1", "Read") + "\n");
    const r = foldFile(f, statSync(f).size, statSync(f).ino, null);
    expect(r.state.sum.toolUses).toBe(1);
    expect(r.state.sum.endedTurn).toBe(false);
  });
});

describe("a saved state that does not fit is not used", () => {
  const setup = () => {
    const d = tmp(), f = join(d, "agent-a.jsonl"), cache = join(d, "cache");
    writeFileSync(f, whole);
    foldFile(f, statSync(f).size, statSync(f).ino, cache);
    return { d, f, cache };
  };
  const again = (f: string, cache: string) => foldFile(f, statSync(f).size, statSync(f).ino, cache);
  it("the file shrank", () => {
    const { f, cache } = setup();
    writeFileSync(f, lines.slice(0, 2).join("\n") + "\n");
    const r = again(f, cache);
    expect(r.how).toBe("full");
    expect(r.state.sum.toolUses).toBe(1);
  });
  it("the file was replaced (another inode) by a longer one", () => {
    const { d, f, cache } = setup();
    const g = join(d, "other");
    writeFileSync(g, whole.replace(/"u3"/g, '"zz"') + whole);
    renameSync(g, f);
    const r = again(f, cache);
    expect(r.how).toBe("full");
    expect(view(r.state)).toBe(view(foldText(initFold(false), readFileSync(f, "utf8"))));
  });
  it("the bytes before the offset changed in place (same inode, longer file)", () => {
    const { f, cache } = setup();
    const i = whole.lastIndexOf("done");
    const b = Buffer.from(whole.slice(0, i) + "DONE" + whole.slice(i + 4) + whole);
    writeFileSync(f, b); // same inode: truncated and rewritten
    const r = again(f, cache);
    expect(r.how).toBe("full");
    expect(view(r.state)).toBe(view(foldText(initFold(false), b.toString("utf8"))));
  });
  it("accepted limit: a change more than 64 bytes before the offset is not seen (transcripts only grow)", () => {
    const { f, cache } = setup();
    writeFileSync(f, whole.replace("done", "DONE") + whole);
    expect(again(f, cache).how).toBe("resumed");
  });
  it("another schema or another code hash", () => {
    for (const patch of [{ schema: FOLD_SCHEMA + 1 }, { code: "0".repeat(16) }]) {
      const { f, cache } = setup();
      const file = join(cache, readdirSync(cache)[0]!);
      writeFileSync(file, JSON.stringify({ ...JSON.parse(readFileSync(file, "utf8")), ...patch }));
      expect(again(f, cache).how).toBe("full");
    }
    expect(codeHash()).toMatch(/^[0-9a-f]{16}$/);
  });
  it("a broken cache file", () => {
    const { f, cache } = setup();
    writeFileSync(join(cache, readdirSync(cache)[0]!), "{not json");
    expect(again(f, cache).how).toBe("full");
  });
});

describe("the collector over the cache and the spool memo", () => {
  const sp = (agent: string, e: string, ts: number) => rec({ hook_event_name: e, agent_id: agent, ts, tool_name: "Bash", tool_use_id: "t" + ts, duration_ms: 1, is_error: false });
  it("a changed spool file is read again, a deleted one disappears, and the transcript is resumed", () => {
    const d = tmp();
    const p = pathsFor(join(d, "repo"), { FW_CONSOLE_DIR: join(d, "c"), FW_PROJECTS_DIR: join(d, "proj") }, d);
    mkdirSync(join(p.consoleDir, "spool"), { recursive: true });
    const now = Date.now();
    const spool = join(p.consoleDir, "spool", "aq.jsonl");
    writeFileSync(spool, sp("aq", "PostToolUse", now - 5000) + "\n");
    const names = () => collectAgents(p, now, new Map()).map((a) => `${a.id}:${a.tools}`);
    expect(names()).toEqual(["aq:1"]);
    expect(names()).toEqual(["aq:1"]);
    appendFileSync(spool, sp("aq", "PostToolUse", now - 4000) + "\n");
    expect(names()).toEqual(["aq:2"]);
    const old = new Date(now - 3600_000 * 30);
    writeFileSync(spool, sp("aq", "PostToolUse", now - 4000) + "\n");    utimesSync(spool, old, old);
    expect(names()).toEqual(["aq:1"]);
    rmSync(spool);
    expect(names()).toEqual([]);
  });
  it("readTranscript with and without the cache agree, and the cache dir is written", () => {
    const d = tmp(), f = join(d, "agent-zz.jsonl");
    writeFileSync(f, whole);
    const p = pathsFor(join(d, "repo"), { FW_CONSOLE_DIR: join(d, "c"), FW_PROJECTS_DIR: join(d, "proj") }, d);
    const a = readTranscript(f, "zz", p)!;
    expect(readdirSync(join(p.consoleDir, "watch-cache")).length).toBe(1);
    appendFileSync(f, use(30, "u7", "Read") + "\n");
    const b = readTranscript(f, "zz", p)!;
    const st = foldText(initFold(false), readFileSync(f, "utf8"));
    expect(b.tr.toolUses).toBe(a.tr.toolUses + 1);
    expect(JSON.stringify([b.tr, b.sig])).toBe(JSON.stringify([finishInfo(st, null, null), finishSignals("zz", st).facts]));
  });
});

type Ev = { k: "assistant"; msg: string; calls: { id: string; tool: string; at: number }[] } | { k: "result"; id: string };
const evLine = (e: Ev, i: number): string => e.k === "assistant"
  ? JSON.stringify({ type: "assistant", timestamp: new Date(e.calls[0]?.at ?? 1000 + i).toISOString(),
      message: { id: e.msg, role: "assistant", content: e.calls.length ? e.calls.map((c) => ({ type: "tool_use", id: c.id, name: c.tool, input: {} })) : [{ type: "text", text: "x" }] } })
  : JSON.stringify({ type: "user", timestamp: new Date(1000 + i).toISOString(), message: { role: "user", content: [{ type: "tool_result", tool_use_id: e.id, content: "ok" }] } });
const evLines = (evs: Ev[]): string[] => evs.flatMap((e, i) => e.k === "assistant" && e.calls.length > 1
  ? e.calls.map((c, j) => evLine({ ...e, calls: [c] }, i * 10 + j)) : [evLine(e, i)]);
const inflightGolden: { name: string; events: Ev[]; expect: { tool: string; since: number } | null }[] =
  readFileSync(join(root, "packages/contracts/golden/obs/watch-inflight.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));

describe("the Lean in-flight golden vectors", () => {
  it("has the cases", () => expect(inflightGolden.length).toBeGreaterThan(8));
  for (const c of inflightGolden) {
    it(`inflight: ${c.name}`, () => {
      const text = evLines(c.events).join("\n") + "\n";
      const st = foldText(initFold(false), text);
      const info = finishInfo(st, null);
      expect(info.inflight ? { tool: info.inflight.tool, since: info.inflight.since } : null).toEqual(c.expect);
      expect(finishSignals("a", st).openCall).toBe(c.expect !== null);
    });
    it(`inflight resumes at every line cut: ${c.name}`, () => {
      const ls = evLines(c.events).map((l) => l + "\n"), whole = foldText(initFold(false), ls.join(""));
      for (let k = 0; k <= ls.length; k++) {
        const st = loadFold(JSON.parse(JSON.stringify(saveFold(foldText(initFold(false), ls.slice(0, k).join(""))))))!;
        expect(view(foldText(st, ls.slice(k).join("")))).toBe(view(whole));
      }
    });
  }
});

describe("a tool_use with no tool_result record (inc-orphan-tool-call)", () => {
  const T = Date.parse("2026-01-01T00:00:00Z");
  const at = (s: number) => new Date(T + s * 1000).toISOString();
  const asst = (s: number, id: string, content: object[]) => rec({ type: "assistant", timestamp: at(s), message: { id, role: "assistant", content } });
  const bash = (s: number, id: string, call: string) => asst(s, id, [{ type: "tool_use", id: call, name: "Bash", input: {} }]);
  const back = (s: number, call: string) => rec({ type: "user", timestamp: at(s), message: { role: "user", content: [{ type: "tool_result", tool_use_id: call, content: "ok" }] } });
  const run = (ls: string[]) => finishInfo(foldText(initFold(false), ls.join("\n") + "\n"), null);
  it("holds in flight until the agent's next assistant message, then not", () => {
    const orphan = [bash(0, "m1", "c1")];
    expect(run(orphan).inflight).toEqual({ tool: "Bash", verb: null, since: T });
    expect(run([...orphan, bash(337, "m2", "c2"), back(338, "c2")]).inflight).toBeNull();
    expect(run([...orphan, bash(337, "m2", "c2")]).inflight).toEqual({ tool: "Bash", verb: null, since: T + 337000 });
  });
  it("a closing text message ends the turn though the orphan never got a result", () => {
    const i = run([bash(0, "m1", "c1"), rec({ type: "assistant", timestamp: at(5), message: { id: "m2", role: "assistant", stop_reason: "end_turn", content: [{ type: "text", text: "done" }] } })]);
    expect(i.inflight).toBeNull();
    expect(i.endedTurn).toBe(true);
  });
  it("parallel calls of one message stay open together, each until its own result", () => {
    const par = [asst(0, "m1", [{ type: "tool_use", id: "p1", name: "Bash", input: {} }, { type: "tool_use", id: "p2", name: "Read", input: {} }])];
    expect(run(par).inflight?.tool).toBe("Read");
    expect(run([...par, back(1, "p2")]).inflight?.tool).toBe("Bash");
    expect(run([...par, back(1, "p2"), back(2, "p1")]).inflight).toBeNull();
  });
  it("FOLD_SCHEMA moved with the saved shape", () => expect(FOLD_SCHEMA).toBe(2));
});
