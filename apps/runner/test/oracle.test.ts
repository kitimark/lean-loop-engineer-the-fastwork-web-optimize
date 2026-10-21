import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { fwcoreCall } from "@fw/gh-budget";
import { ask, decisionLine, errorText, readLog, scrub, sha256, type Deps, type FwCall, type Json } from "@fw/oracle";
import { fastCore } from "../../../packages/gh-budget/test/util.ts";
import { oracleCli, thresholdsOf, type Io } from "../src/oracle.ts";
import { ARM_PREAMBLE } from "../src/oracle-score.ts";

const hasCore = (() => { try { fwcoreCall(process.cwd()); return true; } catch { return false; } })();
const call: FwCall = hasCore ? fastCore() : () => ({});
const golden = join(process.cwd(), "..", "..", "packages", "contracts", "golden", "oracle");
const fixtures = new Map<string, { reply: string; label: string; decide: Json }>(
  readFileSync(join(golden, "fixtures.jsonl"), "utf8").trim().split("\n").map((l) => {
    const j = JSON.parse(l) as { name: string; reply: string; label: string; decide: Json };
    return [j.name, j];
  }));
const fx = (n: string) => fixtures.get(n)!.reply;
const FAKE_KEY = "tsk_test_0123456789abcdef";
const HALF = { num: "1", den: "2" };
const ALL = { flake: HALF, infra: HALF, real: HALF };
const noKeychain = () => { throw new Error("keychain must not be read"); };

type Sent = { url: string; body: string; auth: string };
type Replier = (s: Sent & { n: number }) => Response | Promise<Response>;
function fakeFetch(replies: Replier): { fetch: typeof fetch; sent: Sent[] } {
  const sent: Sent[] = [];
  const f = (async (url: string | URL | Request, init?: RequestInit) => {
    const s = { url: String(url), body: String(init?.body), auth: String((init?.headers as Record<string, string>).authorization) };
    sent.push(s);
    return replies({ ...s, n: sent.length });
  }) as typeof fetch;
  return { fetch: f, sent };
}

function deps(over: Partial<Deps> = {}): Deps {
  return {
    core: call, fetch: fakeFetch(() => new Response(fx("confident-real"))).fetch, readKey: () => FAKE_KEY,
    logPath: join(mkdtempSync(join(tmpdir(), "oracle-")), "oracle.jsonl"), now: () => new Date("2026-10-18T06:00:00Z"),
    ...over,
  };
}

const state = { job: "build", step: "lake build", log: ["error at /Users/example/w/x.lean:3", "done"] };
const isHeld = (id: string) => (call({ op: "oracle.plan", rows: [{ id, label: "x" }], part: "holdout" }).ids as string[]).length === 1;
function idIn(held: boolean, n: number): string {
  for (let id = `r${n}`; ; id += "y") if (isHeld(id) === held) return id;
}
const row = (k: number, label: string, id = `r${k}`) => ({ id, state: { log: `error in row-${k}.` }, label });
const byRow = (ans: string[]) => fakeFetch(({ body }) => new Response(fx(ans[Number(/row-(\d+)\./.exec(body)![1])]!)));

describe.skipIf(!hasCore)("golden wire vectors replay through fwcore", () => {
  it("every oracle.* case", () => {
    const lines = readFileSync(join(golden, "wire.jsonl"), "utf8").trim().split("\n");
    expect(lines.length).toBeGreaterThan(20);
    for (const l of lines) {
      const c = JSON.parse(l) as { name: string; request: Json; response: Json };
      if (typeof c.response.error === "string") expect(() => call(c.request), c.name).toThrow(c.response.error);
      else expect(call(c.request), c.name).toEqual(c.response);
    }
  });
  it("fixture replies decide as recorded at threshold 1/2 for every option", () => {
    for (const [name, f] of fixtures) expect(call({ op: "oracle.decide", name: "ci-triage", thresholds: ALL, reply: f.reply }), name).toEqual(f.decide);
  });
});

describe.skipIf(!hasCore)("ask", () => {
  it("live call: the bytes sent are Lean's body, the key only in the header; the same request replays", async () => {
    const ff = fakeFetch(() => new Response(fx("confident-real")));
    const d = deps({ fetch: ff.fetch });
    const a = await ask(d, { question: "ci-triage", state, thresholds: ALL });
    expect(a.source).toBe("live");
    expect(a.decision).toEqual({ action: "advise", advice: { kind: "pick", value: "real" }, gate: { num: "24", den: "25" } });
    const body = String(call({ op: "oracle.request", name: "ci-triage", names: [], state }).bodyText);
    expect(ff.sent).toEqual([{ url: "https://api.typesafe.ai/v1/systemone", body, auth: `Bearer ${FAKE_KEY}` }]);
    expect(body).not.toContain("/Users/");
    expect(JSON.parse(body).model).toBe("jev-1.13.0");
    expect(readLog(d.logPath).map((e) => e.key)).toEqual([sha256(body)]);
    const log = readFileSync(d.logPath, "utf8");
    expect(log).not.toContain(FAKE_KEY);
    expect(log).not.toContain("/Users/");
    const b = await ask({ ...d, readKey: noKeychain }, { question: "ci-triage", state, thresholds: ALL });
    expect(b.source).toBe("replay");
    expect(b.decision).toEqual(a.decision);
    expect(ff.sent).toHaveLength(1);
  });
  it("uncalibrated (threshold null) escalates even a confident answer", async () => {
    const a = await ask(deps(), { question: "ci-triage", state, thresholds: null });
    expect(decisionLine(a.decision)).toBe("escalate: uncalibrated (no threshold yet) (gate 0.960)");
  });
  it("no key: escalate noKey, nothing sent, nothing logged", async () => {
    const ff = fakeFetch(() => new Response(fx("confident-real")));
    const d = deps({ fetch: ff.fetch, readKey: () => null });
    const a = await ask(d, { question: "ci-triage", state, thresholds: ALL });
    expect(a).toMatchObject({ source: "nokey", sent: false, decision: { action: "escalate", reason: { reason: "failure", failure: { kind: "noKey" } } } });
    expect(ff.sent).toHaveLength(0);
    expect(existsSync(d.logPath)).toBe(false);
  });
  it("a field the question does not declare is refused before the keychain is read", async () => {
    const ff = fakeFetch(() => new Response(fx("confident-real")));
    const a = await ask(deps({ fetch: ff.fetch, readKey: noKeychain }), { question: "ci-triage", state: { ...state, note: "x" }, thresholds: ALL });
    expect(a).toMatchObject({ source: "refused", sent: false, decision: { reason: { failure: { kind: "undeclared" } } } });
    expect(ff.sent).toHaveLength(0);
  });
  it("HTTP 429 and a timeout escalate; failures are logged but not replayed", async () => {
    const ff = fakeFetch(({ n }) => n === 1 ? new Response("slow down", { status: 429 }) : Promise.reject(new DOMException("t", "TimeoutError")));
    const d = deps({ fetch: ff.fetch });
    const a = await ask(d, { question: "ci-triage", state, thresholds: ALL });
    expect(a.decision).toEqual({ action: "escalate", reason: { reason: "failure", failure: { kind: "http", status: 429 } } });
    const b = await ask(d, { question: "ci-triage", state, thresholds: ALL });
    expect(b.decision).toEqual({ action: "escalate", reason: { reason: "failure", failure: { kind: "timeout" } } });
    expect(ff.sent).toHaveLength(2);
    expect(readLog(d.logPath).map((e) => e.failure?.kind)).toEqual(["http", "timeout"]);
  });
  it("malformed, schema and no-match replies escalate", async () => {
    for (const [name, kind] of [["not-json", "malformed"], ["missing-probability", "schema"], ["other-model", "schema"]] as const) {
      const a = await ask(deps({ fetch: fakeFetch(() => new Response(fx(name))).fetch }), { question: "ci-triage", state, thresholds: ALL });
      expect(a.decision, name).toMatchObject({ action: "escalate", reason: { reason: "failure", failure: { kind } } });
    }
    const u = await ask(deps({ fetch: fakeFetch(() => new Response(fx("confident-unknown"))).fetch }), { question: "ci-triage", state, thresholds: ALL });
    expect(u.decision).toMatchObject({ action: "escalate", reason: { reason: "uncalibrated" } });
  });
  it("the daily cap (200) and the run cap (60) refuse before the keychain is read", async () => {
    const d = deps({ readKey: noKeychain });
    writeFileSync(d.logPath, Array.from({ length: 200 }, (_, i) => JSON.stringify({ key: `k${i}`, question: "q", model: "m", day: "2026-10-18", at: "", ms: 0 })).join("\n") + "\n");
    const a = await ask(d, { question: "ci-triage", state, thresholds: ALL });
    expect(a).toMatchObject({ source: "refused", decision: { reason: { failure: { kind: "overBudget" } } } });
    const b = await ask(deps({ readKey: noKeychain }), { question: "ci-triage", state, thresholds: ALL, run: 60 });
    expect(b).toMatchObject({ source: "refused", decision: { reason: { failure: { kind: "overBudget" } } } });
  });
  it("a reply echoing the key is scrubbed before it is logged", async () => {
    const echo = fx("confident-real").replace("\"usage\"", `"note":"${FAKE_KEY}","usage"`);
    const d = deps({ fetch: fakeFetch(() => new Response(echo)).fetch });
    await ask(d, { question: "ci-triage", state, thresholds: ALL });
    expect(readFileSync(d.logPath, "utf8")).not.toContain(FAKE_KEY);
  });
  it("a reply over 64 KiB is logged capped and escalates as malformed", async () => {
    const d = deps({ fetch: fakeFetch(() => new Response("x".repeat(70_000))).fetch });
    const a = await ask(d, { question: "ci-triage", state, thresholds: ALL });
    const logged = readLog(d.logPath)[0]!.reply!;
    expect(Buffer.byteLength(logged, "utf8")).toBeLessThanOrEqual(65_536);
    expect(logged.endsWith(" [truncated]")).toBe(true);
    expect(decisionLine(a.decision)).toBe("escalate: failure malformed");
  });
  it("a pick that is not the most probable option is a schema failure; a threshold outside (0, 1] is refused", () => {
    for (const n of ["pick-not-max-flake", "pick-not-max-unknown"])
      expect(call({ op: "oracle.validate", name: "ci-triage", reply: fx(n) }), n).toMatchObject({ ok: false, failure: { kind: "schema" } });
    for (const t of [{ num: "0", den: "1" }, { num: "3", den: "2" }])
      expect(() => call({ op: "oracle.decide", name: "ci-triage", thresholds: { real: t }, reply: fx("confident-real") })).toThrow("outside (0, 1]");
  });
});

describe("scrub", () => {
  it("removes the key and bearer credentials", () => {
    expect(scrub(`x ${FAKE_KEY} y`, FAKE_KEY)).toBe("x <token> y");
    expect(scrub("Authorization: Bearer abc.def-123")).toBe("Authorization: Bearer <token>");
    expect(errorText(new Error(`failed with ${FAKE_KEY}`), FAKE_KEY)).toBe("failed with <token>");
  });
});

describe.skipIf(!hasCore)("fw oracle", () => {
  function io(over: Partial<Io> = {}): Io & { lines: string[] } {
    const lines: string[] = [];
    return { deps: deps(), cwd: mkdtempSync(join(tmpdir(), "oracle-dir-")), names: [], out: (s) => lines.push(s), lines, ...over };
  }
  type Spec = [number, string, string, "choose" | "holdout"][];
  function replaySet(dir: string, spec: Spec): string[] {
    const rows: string[] = [];
    const answers: string[] = [];
    for (const [n, fixture, label, part] of spec) for (let i = 0; i < n; i++) {
      const k = rows.length;
      rows.push(JSON.stringify(row(k, label, idIn(part === "holdout", k))));
      answers.push(fixture);
    }
    writeFileSync(join(dir, "rows.jsonl"), rows.join("\n") + "\n");
    return answers;
  }
  it("ask: one advisory line; uncalibrated escalates, a stored table advises", async () => {
    const x = io();
    writeFileSync(join(x.cwd, "state.json"), JSON.stringify(state));
    expect(await oracleCli(["ask", "ci-triage", "--state", "state.json"], x.cwd, x)).toBe(0);
    expect(x.lines).toEqual(["oracle ci-triage: escalate: uncalibrated (no threshold yet) (gate 0.960) [live]"]);
    writeFileSync(join(x.cwd, "table.json"), JSON.stringify({ "ci-triage": { thresholds: ALL } }));
    expect(thresholdsOf(join(x.cwd, "table.json"), "ci-triage")).toEqual(ALL);
    expect(await oracleCli(["ask", "ci-triage", "--state", "state.json", "--thresholds", "table.json"], x.cwd, x)).toBe(0);
    expect(x.lines[1]).toBe("oracle ci-triage: advise real (gate 0.960) [replay]");
  });
  it("ask without --state is a usage error", async () => {
    expect(await oracleCli(["ask", "ci-triage"], process.cwd(), io())).toBe(64);
  });
  it("calibrate: no key exits 2 and leaves the table untouched", async () => {
    const x = io({ deps: deps({ readKey: () => null }) });
    writeFileSync(join(x.cwd, "rows.jsonl"), JSON.stringify(row(1, "real")) + "\n");
    writeFileSync(join(x.cwd, "table.json"), JSON.stringify({ "ci-triage": null }));
    expect(await oracleCli(["calibrate", "ci-triage", "--replay", "rows.jsonl", "--out", "table.json"], x.cwd, x)).toBe(2);
    expect(JSON.parse(readFileSync(join(x.cwd, "table.json"), "utf8"))).toEqual({ "ci-triage": null });
  });
  it("calibrate: the round-5 probe on the holdout part (flake advised 16 times, 5 right) certifies real only", async () => {
    const x = io();
    const ff = byRow(replaySet(x.cwd, [[5, "confident-flake", "flake", "choose"], [5, "confident-real", "real", "choose"],
      [5, "confident-flake", "flake", "holdout"], [11, "confident-flake", "real", "holdout"], [25, "confident-real", "real", "holdout"]]));
    x.deps = deps({ fetch: ff.fetch });
    expect(await oracleCli(["calibrate", "ci-triage", "--replay", "rows.jsonl", "--out", "table.json"], x.cwd, x)).toBe(0);
    expect(ff.sent).toHaveLength(51);
    const t = JSON.parse(readFileSync(join(x.cwd, "table.json"), "utf8"))["ci-triage"];
    expect(t).toMatchObject({ thresholds: { flake: null, infra: null }, holdout: { rows: 41 } });
    expect(t.thresholds.real).not.toBeNull();
  });
  it("calibrate over 70 rows: the run cap cuts the first run (no write, exit 2); --resume replays 60 and sends 10", async () => {
    const x = io();
    writeFileSync(join(x.cwd, "rows.jsonl"), Array.from({ length: 70 }, (_, i) => JSON.stringify(row(i, "real"))).join("\n") + "\n");
    const ff = fakeFetch(() => new Response(fx("confident-real")));
    x.deps = deps({ fetch: ff.fetch });
    expect(await oracleCli(["calibrate", "ci-triage", "--replay", "rows.jsonl", "--out", "table.json"], x.cwd, x)).toBe(2);
    expect(ff.sent).toHaveLength(60);
    expect(existsSync(join(x.cwd, "table.json"))).toBe(false);
    const y = io({ cwd: x.cwd, deps: x.deps });
    expect(await oracleCli(["calibrate", "ci-triage", "--replay", "rows.jsonl", "--resume", "--out", "table.json"], x.cwd, y)).toBe(0);
    expect(ff.sent).toHaveLength(70);
    expect(JSON.parse(readFileSync(join(x.cwd, "table.json"), "utf8"))["ci-triage"]).toMatchObject({ used: 70, rows: 70 });
    expect(y.lines[0]).toContain("replay 60, live 10");
  });
  it("calibrate --resume with more missing rows than the run cap sends nothing", async () => {
    const x = io();
    writeFileSync(join(x.cwd, "rows.jsonl"), Array.from({ length: 61 }, (_, i) => JSON.stringify(row(i, "real"))).join("\n") + "\n");
    const ff = fakeFetch(() => new Response(fx("confident-real")));
    x.deps = deps({ fetch: ff.fetch, readKey: noKeychain });
    expect(await oracleCli(["calibrate", "ci-triage", "--replay", "rows.jsonl", "--resume"], x.cwd, x)).toBe(2);
    expect(ff.sent).toHaveLength(0);
    expect(x.lines[0]).toContain("61 rows are not in the answer log");
  });
  it("calibrate with --limit (a cut set) prints but does not write", async () => {
    const x = io();
    writeFileSync(join(x.cwd, "rows.jsonl"), Array.from({ length: 3 }, (_, i) => JSON.stringify(row(i, "real"))).join("\n") + "\n");
    expect(await oracleCli(["calibrate", "ci-triage", "--replay", "rows.jsonl", "--limit", "2", "--out", "table.json"], x.cwd, x)).toBe(2);
    expect(existsSync(join(x.cwd, "table.json"))).toBe(false);
  });
  it("eval sends only the holdout part and reports MEASURED accuracy and coverage; it writes nothing", async () => {
    const x = io();
    const ans = replaySet(x.cwd, [[3, "confident-real", "real", "choose"], [3, "confident-real", "real", "holdout"],
      [1, "confident-flake", "infra", "holdout"], [1, "unsure-flake", "flake", "holdout"]]);
    const table = JSON.stringify({ "ci-triage": { thresholds: ALL } });
    writeFileSync(join(x.cwd, "table.json"), table);
    const ff = byRow(ans);
    x.deps = deps({ fetch: ff.fetch });
    expect(await oracleCli(["eval", "ci-triage", "--replay", "rows.jsonl", "--thresholds", "table.json"], x.cwd, x)).toBe(0);
    expect(ff.sent).toHaveLength(5);
    expect(x.lines).toEqual([`oracle eval ci-triage (MEASURED, holdout): thresholds ${JSON.stringify(ALL)}, accuracy 3/4 = 75.0 %, ` +
      "coverage 4/5 = 80.0 % (used 5, dropped 0; live 5)"]);
    expect(readFileSync(join(x.cwd, "table.json"), "utf8")).toBe(table);
  });
  it("eval without a table for the question exits 2 and sends nothing", async () => {
    const x = io();
    replaySet(x.cwd, [[2, "confident-real", "real", "holdout"]]);
    writeFileSync(join(x.cwd, "table.json"), "{}");
    const ff = fakeFetch(() => new Response(fx("confident-real")));
    x.deps = deps({ fetch: ff.fetch, readKey: noKeychain });
    expect(await oracleCli(["eval", "ci-triage", "--replay", "rows.jsonl", "--thresholds", "table.json"], x.cwd, x)).toBe(2);
    expect(ff.sent).toHaveLength(0);
  });
});

describe.skipIf(!hasCore)("Lean decisions the reviewer probed", () => {
  it("the round-3 probe never makes flake advisable (per option, no pooling)", () => {
    const g = (fixture: string, label: string, n: number) => Array.from({ length: n }, () => ({ fixture, label }));
    const set = [...g("confident-flake", "flake", 5), ...g("confident-flake", "real", 11), ...g("confident-infra", "infra", 5),
      ...g("confident-real", "real", 90)];
    const c = call({ op: "oracle.calibrate", name: "ci-triage", replay: set.map((r, i) => ({ id: `r${i}`, label: r.label })),
      answers: set.map((r, i) => ({ id: `r${i}`, reply: fx(r.fixture) })) });
    expect(c.thresholds).toMatchObject({ flake: null });
    expect(c.write).toBe(true);
    const d = call({ op: "oracle.decide", name: "ci-triage", thresholds: c.thresholds, reply: fx("confident-flake") });
    expect(d).toMatchObject({ action: "escalate", reason: { reason: "uncalibrated" } });
  });
  it("redaction: the reviewer's round-2 strings", () => {
    const r = (text: string) => call({ op: "oracle.redact", names: ["alice"], text }).text;
    expect(r("-Users-example-source-fastwork/x")).toBe("~/x");
    expect(r("user_alice wrote")).toBe("user_<user> wrote");
    expect(r("authored-by-alice")).toBe("authored-by-<user>");
    expect(r("MacBook-Pro-of-alice.local")).toBe("MacBook-Pro-of-<user>.local");
    expect(r("C:\\Users\\alice\\src")).toBe("C:~\\src");
    expect(r("malice alice2")).toBe("malice alice2");
  });
});

describe.skipIf(!hasCore)("fw oracle send (jev-replay)", () => {
  const classes = ["c-orphan-wait", "c-order-derived", "c-shared-no-lock", "c-quota"];
  function quotaReply(): string {
    const body = String(call({ op: "oracle.request", name: "incident-class", names: [], state: { title: "t" } }).bodyText);
    const names = [...new Set([...body.matchAll(/"(c-[a-z-]+|none)"/g)].map((m) => m[1]!))];
    const rest = 0.1 / (names.length - 1);
    const probabilities = Object.fromEntries(names.map((n) => [n, n === "c-quota" ? 0.9 : rest]));
    return JSON.stringify({ model: "jev-1.13.0", answers: { "incident-class": { type: "choice", choice: "c-quota",
      probabilities, confidence: 0.5 } }, usage: { input_tokens: 300, output_tokens: 1 } });
  }
  function d1Dir(n: number): string {
    const dir = mkdtempSync(join(tmpdir(), "jev-"));
    const rows = Array.from({ length: n }, (_, k) => JSON.stringify({ id: `inc-${k}`, set: "d1",
      label: classes[k % classes.length], title: `row-${k}.`, symptom: "s", cause: `seen in wf_${k}abc`, split: "x" }));
    rows.push(JSON.stringify({ id: "inc-x", set: "d1", label: null, title: "t", symptom: "s", cause: "c" }));
    writeFileSync(join(dir, "d1.jsonl"), rows.join("\n") + "\n");
    return dir;
  }
  function io(over: Partial<Io> = {}): Io & { lines: string[] } {
    const lines: string[] = [];
    return { deps: deps(), cwd: process.cwd(), names: [], out: (s) => lines.push(s), lines, ...over };
  }
  it("70 rows: the run cap stops the first run at 60 sends (exit 2); the second replays 60 and sends 10", async () => {
    const reply = quotaReply();
    expect(reply).toContain("c-orphan-wait");
    const ff = fakeFetch(() => new Response(reply));
    const d = deps({ fetch: ff.fetch });
    const dir = d1Dir(70);
    const x = io({ deps: d });
    expect(await oracleCli(["send", "--set", "d1", "--dir", dir], x.cwd, x)).toBe(2);
    expect(ff.sent).toHaveLength(60);
    expect(x.lines[0]).toMatch(/^oracle send d1 \(incident-class\): 60\/70 answered \(live 60, refused 1\); sent 60, /);
    expect(x.lines[0]).toContain("stopped: overBudget");
    expect(ff.sent.some((s) => /wf_\d+abc/.test(s.body))).toBe(false);
    const y = io({ deps: d });
    expect(await oracleCli(["send", "--set", "d1", "--dir", dir], y.cwd, y)).toBe(0);
    expect(ff.sent).toHaveLength(70);
    expect(y.lines[0]).toMatch(/^oracle send d1 \(incident-class\): 70\/70 answered \(replay 60, live 10\); sent 10, /);
    expect(readLog(d.logPath)).toHaveLength(70);
  });
  it("--part and --limit cut the rows Lean picks", async () => {
    const ff = fakeFetch(() => new Response(quotaReply()));
    const x = io({ deps: deps({ fetch: ff.fetch }) });
    expect(await oracleCli(["send", "--set", "d1", "--dir", d1Dir(20), "--part", "holdout", "--limit", "2"], x.cwd, x)).toBe(0);
    expect(ff.sent).toHaveLength(2);
    expect(x.lines[0]).toContain(": 2/2 answered (live 2)");
  });
  it("no key: stops at the first row, sends nothing, exit 2", async () => {
    const ff = fakeFetch(() => new Response(quotaReply()));
    const x = io({ deps: deps({ fetch: ff.fetch, readKey: () => null }) });
    expect(await oracleCli(["send", "--set", "d1", "--dir", d1Dir(3)], x.cwd, x)).toBe(2);
    expect(ff.sent).toHaveLength(0);
    expect(x.lines[0]).toContain("stopped: no key");
  });
  it("score: the Jev arm from the answer log, another arm from its file; both arms land in one results file", async () => {
    const reply = quotaReply();
    const d = deps({ fetch: fakeFetch(() => new Response(reply)).fetch });
    const dir = d1Dir(8);
    const x = io({ deps: d, cwd: dir });
    expect(await oracleCli(["send", "--set", "d1", "--dir", dir, "--limit", "6"], x.cwd, x)).toBe(0);
    expect(await oracleCli(["score", "--set", "d1", "--dir", dir, "--out", "r.json"], x.cwd, x)).toBe(2);
    expect(x.lines[1]).toMatch(/^oracle score d1 jev \(incident-class\): right [12]\/6, missing 2; wrote /);
    const ids = Array.from({ length: 8 }, (_, k) => `inc-${k}`);
    writeFileSync(join(dir, "haiku.jsonl"), ids.map((id, k) => JSON.stringify({ id, choice: classes[k % classes.length],
      inputTokens: 1000, outputTokens: 20, ms: 900 })).join("\n") + "\n");
    expect(await oracleCli(["score", "--set", "d1", "--dir", dir, "--arm", "haiku", "--answers", "haiku.jsonl", "--out", "r.json"],
      x.cwd, x)).toBe(0);
    const r = JSON.parse(readFileSync(join(dir, "r.json"), "utf8"));
    expect(r).toMatchObject({ set: "d1", question: "incident-class", labeled: 8, selected: 8 });
    expect(r.rows).toBeUndefined();
    expect(r.arms.jev).toMatchObject({ arm: "jev", missing: 2, all: { rows: 6 }, inputTokens: 1800, outputTokens: 6 });
    expect(r.arms.haiku).toMatchObject({ arm: "haiku", missing: 0, all: { rows: 8, right: 8 }, inputTokens: 8000,
      dollars: { num: "11", den: "12500" }, msMedian: 900 });
    const jevQuota = r.arms.jev.all.options.find((o: { option: string }) => o.option === "c-quota");
    expect(r.arms.jev.all.right).toBe(jevQuota.right);
    expect(jevQuota.chosen).toBe(6);
  });
  it("score: a bad arm, or --answers with the Jev arm, is a usage error", async () => {
    const x = io({ deps: deps({ readKey: noKeychain }) });
    expect(await oracleCli(["score", "--set", "d1", "--arm", "gpt"], x.cwd, x)).toBe(64);
    expect(await oracleCli(["score", "--set", "d1", "--answers", "a.jsonl"], x.cwd, x)).toBe(64);
    expect(await oracleCli(["score", "--set", "d1", "--arm", "haiku"], x.cwd, x)).toBe(64);
  });
  it("arm-input: one prompt per picked row, with the preamble and the redacted state of the Jev body", async () => {
    const dir = d1Dir(3);
    const x = io({ deps: deps({ readKey: noKeychain }), cwd: dir });
    expect(await oracleCli(["arm-input", "--set", "d1", "--dir", dir, "--out", "p.jsonl"], x.cwd, x)).toBe(0);
    const p = readFileSync(join(dir, "p.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l) as { id: string; prompt: string });
    expect(p.map((r) => r.id).sort()).toEqual(["inc-0", "inc-1", "inc-2"]);
    expect(p[0]!.prompt.startsWith(ARM_PREAMBLE)).toBe(true);
    expect(p[0]!.prompt).toContain('"question": "incident-class"');
    expect(p[0]!.prompt).toContain("wf_<id>");
  });
  it("a missing dataset or a bad --limit sends nothing", async () => {
    const x = io({ deps: deps({ readKey: noKeychain }) });
    expect(await oracleCli(["send", "--set", "d1", "--dir", mkdtempSync(join(tmpdir(), "jev-"))], x.cwd, x)).toBe(2);
    expect(x.lines[0]).toMatch(/^oracle send: no dataset /);
    expect(await oracleCli(["send", "--set", "d1", "--limit", "-1"], x.cwd, x)).toBe(64);
    expect(await oracleCli(["send"], x.cwd, x)).toBe(64);
  });
});
