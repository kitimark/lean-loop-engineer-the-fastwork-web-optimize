import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { ask, ENDPOINT, readLog, sha256, type Deps, type Json } from "../src/index.ts";

const FAKE_KEY = "tsk_test_0123456789abcdef";
const BODY = '{"model":"jev-1.13.0","question":"ci-triage"}';
const reply = '{"model":"jev-1.13.0","answers":{"ci-triage":{"type":"choice","choice":"real","probabilities":{"real":0.97}}}}';

type Ev = { kind: "core"; op: string; req: Json } | { kind: "key" } | { kind: "fetch"; url: string; body: string; auth: string };

function world(pre: Json, opts: { key?: string | null; respond?: () => Promise<Response> } = {}): { d: Deps; ev: Ev[] } {
  const ev: Ev[] = [];
  const core = (req: Json): Json => {
    const op = String(req.op);
    ev.push({ kind: "core", op, req });
    if (op === "oracle.request") return { bodyText: BODY, state: {} };
    if (op === "oracle.pre" || op === "oracle.preRun") return pre;
    if (op === "oracle.store") return { text: req.text };
    if (op === "oracle.decide") return { action: "escalate", seen: "reply" in req ? { reply: req.reply } : { failure: req.failure } };
    throw new Error(`unexpected op ${op}`);
  };
  const f = (async (url: string | URL | Request, init?: RequestInit) => {
    ev.push({ kind: "fetch", url: String(url), body: String(init?.body),
      auth: String((init?.headers as Record<string, string>).authorization) });
    return opts.respond ? opts.respond() : new Response(reply);
  }) as typeof fetch;
  const d: Deps = {
    core, fetch: f, readKey: () => { ev.push({ kind: "key" }); return opts.key === undefined ? FAKE_KEY : opts.key; },
    logPath: join(mkdtempSync(join(tmpdir(), "oracle-")), "oracle.jsonl"), now: () => new Date("2026-10-18T06:00:00Z"),
  };
  return { d, ev };
}

const SEND = { pre: "send", bodyText: BODY };
const a0 = { question: "ci-triage", state: { log: "error at /Users/example/x" }, thresholds: null };
const at = (ev: Ev[], p: (e: Ev) => boolean) => ev.findIndex(p);

test("send: the key is read once, after oracle.pre, and the sent bytes are Lean's bodyText", async () => {
  const { d, ev } = world(SEND);
  const r = await ask(d, a0);
  assert.equal(r.source, "live");
  assert.equal(ev.filter((e) => e.kind === "key").length, 1);
  assert.ok(at(ev, (e) => e.kind === "core" && e.op === "oracle.pre") < at(ev, (e) => e.kind === "key"));
  const sent = ev.filter((e) => e.kind === "fetch");
  assert.equal(sent.length, 1);
  assert.deepEqual([sent[0]!.url, sent[0]!.body, sent[0]!.auth], [ENDPOINT, BODY, `Bearer ${FAKE_KEY}`]);
  const log = readLog(d.logPath);
  assert.equal(log.length, 1);
  assert.equal(log[0]!.key, sha256(BODY));
  assert.equal(log[0]!.reply, reply);
  assert.ok(!readFileSync(d.logPath, "utf8").includes(FAKE_KEY));
  assert.deepEqual(r.decision.seen, { reply });
});

test("replay: a logged request reads no key and sends nothing", async () => {
  const first = world(SEND);
  await ask(first.d, a0);
  const { d, ev } = world({ pre: "replay" });
  d.logPath = first.d.logPath;
  const r = await ask(d, a0);
  assert.equal(r.source, "replay");
  assert.equal(r.sent, false);
  assert.ok(!ev.some((e) => e.kind === "key" || e.kind === "fetch"));
  assert.equal(at(ev, (e) => e.kind === "core" && e.op === "oracle.pre" && e.req.logged === true) >= 0, true);
});

test("refuse: Lean's failure is decided on; no key read, nothing sent, nothing logged", async () => {
  const failure = { kind: "undeclared", detail: "note" };
  const { d, ev } = world({ pre: "refuse", failure });
  const r = await ask(d, a0);
  assert.equal(r.source, "refused");
  assert.deepEqual(r.decision.seen, { failure });
  assert.ok(!ev.some((e) => e.kind === "key" || e.kind === "fetch"));
  assert.equal(readLog(d.logPath).length, 0);
});

test("a pre body other than the request body throws before the key is read", async () => {
  const { d, ev } = world({ pre: "send", bodyText: BODY + " " });
  await assert.rejects(ask(d, a0), /differs/);
  assert.ok(!ev.some((e) => e.kind === "key" || e.kind === "fetch"));
});

test("no key in the keychain is failure noKey, nothing sent", async () => {
  const { d, ev } = world(SEND, { key: null });
  const r = await ask(d, a0);
  assert.equal(r.source, "nokey");
  assert.deepEqual(r.decision.seen, { failure: { kind: "noKey" } });
  assert.ok(!ev.some((e) => e.kind === "fetch"));
});

test("HTTP 429 and a timeout are failures, logged without the key", async () => {
  const h = world(SEND, { respond: async () => new Response("slow down " + FAKE_KEY, { status: 429 }) });
  const r1 = await ask(h.d, a0);
  assert.equal(r1.source, "failed");
  assert.deepEqual(r1.decision.seen, { failure: { kind: "http", status: 429 } });
  assert.ok(!readFileSync(h.d.logPath, "utf8").includes(FAKE_KEY));
  const t = world(SEND, { respond: async () => { throw new DOMException("t", "TimeoutError"); } });
  const r2 = await ask(t.d, a0);
  assert.deepEqual(r2.decision.seen, { failure: { kind: "timeout" } });
  assert.deepEqual(readLog(t.d.logPath)[0]!.failure, { kind: "timeout" });
});

test("a reply that echoes the key is stored and decided on scrubbed", async () => {
  const { d } = world(SEND, { respond: async () => new Response(`{"echo":"Bearer ${FAKE_KEY}","k":"${FAKE_KEY}"}`) });
  const r = await ask(d, a0);
  assert.ok(!String(r.reply).includes(FAKE_KEY));
  assert.ok(!readFileSync(d.logPath, "utf8").includes(FAKE_KEY));
});

test("replay run: the gate is oracle.preRun with the run's sends and tokens, and its estimate comes back", async () => {
  const { d, ev } = world({ ...SEND, tokens: BODY.length });
  const r = await ask(d, { ...a0, replayRun: { sent: 3, spent: 900 } });
  assert.equal(r.source, "live");
  assert.equal(r.tokens, BODY.length);
  const gate = ev.filter((e) => e.kind === "core" && (e.op === "oracle.pre" || e.op === "oracle.preRun"));
  assert.deepEqual(gate.map((e) => e.kind === "core" && [e.op, e.req.sent, e.req.spent]), [["oracle.preRun", 3, 900]]);
  assert.ok(at(ev, (e) => e.kind === "core" && e.op === "oracle.preRun") < at(ev, (e) => e.kind === "key"));
});

test("replay run refused by the run cap: no key read, nothing sent", async () => {
  const { d, ev } = world({ pre: "refuse", failure: { kind: "overBudget" } });
  const r = await ask(d, { ...a0, replayRun: { sent: 60, spent: 0 } });
  assert.equal(r.source, "refused");
  assert.equal(r.sent, false);
  assert.ok(!ev.some((e) => e.kind === "key" || e.kind === "fetch"));
});
