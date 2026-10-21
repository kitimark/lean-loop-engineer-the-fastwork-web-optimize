// jev-oracle: the oracle client and `fw oracle` against the real fwcore, a fake fetch serving the Lean-generated
// fixture replies (packages/contracts/golden/oracle/fixtures.jsonl), a fake keychain and a fake gh. No network, no key.
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { fwcoreCall, type Env } from "@fw/gh-budget";
import { ask, decisionLine, errorText, readLog, scrub, type Deps, type FwCall, type Json } from "../../../packages/oracle/src/index.ts";
import { jobFacts, jobsOfYaml, LEDGER, oracleCli, sourcer, thresholdsOf, type Io } from "../src/oracle.ts";

const hasCore = (() => { try { fwcoreCall(process.cwd()); return true; } catch { return false; } })();
const call: FwCall = hasCore ? fwcoreCall(process.cwd()) : () => ({});
const golden = join(process.cwd(), "..", "..", "packages", "contracts", "golden", "oracle");
const fixtures = new Map<string, { reply: string; label: string; decide: Json }>(
  readFileSync(join(golden, "fixtures.jsonl"), "utf8").trim().split("\n").map((l) => {
    const j = JSON.parse(l) as { name: string; reply: string; label: string; decide: Json };
    return [j.name, j];
  }));
const fx = (n: string) => fixtures.get(n)!.reply;
const FAKE_KEY = "tsk_test_0123456789abcdef";
const HALF = { num: "1", den: "2" };
/** The threshold table with 1/2 for every CI-triage option. */
const ALL = { flake: HALF, infra: HALF, real: HALF };

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
/** The fetched `--log-failed` text of run 7: every line of `state` is a whole line of it. */
const LOG7 = "build\tlake build\t2026-10-18T06:07:14Z error at /Users/example/w/x.lean:3\nbuild\tlake build\t2026-10-18T06:07:15Z done\n";
/** Every field of `state` from the log of run 7, whose one job runs on a GitHub-hosted runner. */
const LOGP = Object.fromEntries(Object.keys(state).map((k) =>
  [k, { kind: "githubRunnerLog" as const, runId: 7, jobs: [{ job: "build", runsOn: "ubuntu-24.04-arm" }], log: LOG7 }]));
/** A fake public head (what `origin/main` names) and a fake run head commit; no test reads the real refs. */
const PUB = "b".repeat(40);
const RUN_SHA = "c".repeat(40);
/** The workflow files at `RUN_SHA`: every job on a GitHub-hosted runner. */
const HOSTED_WF = { ".github/workflows/ci.yml": "jobs:\n  build:\n    runs-on: ubuntu-24.04-arm\n  mac:\n    runs-on: [macos-26]\n" };
/** A fake git: `origin/main` is `PUB` holding `ledger` at LEDGER; `RUN_SHA` holds the workflow files `wf`. */
function fakeGit(ledger = '{"title":"a title"}', wf: Record<string, string> = HOSTED_WF): (args: string[]) => string | undefined {
  return (args) => {
    if (args[0] === "rev-parse") return args.some((a) => a.startsWith("origin/main")) ? `${PUB}\n` : undefined;
    if (args[0] === "ls-tree") return args.includes(RUN_SHA) ? Object.keys(wf).join("\n") + "\n" : undefined;
    if (args[0] === "show") {
      const [sha, path] = args[1]!.split(":");
      if (sha === RUN_SHA) return wf[path!];
      if (sha === PUB && path === LEDGER) return ledger;
    }
    return undefined;
  };
}
/** The fake gh of one run: its head commit and its `--log-failed` text. */
const ghRun = (log: (runId: string) => string, headSha = RUN_SHA) => (a: string[]) =>
  a.includes("--json") ? JSON.stringify({ headSha }) : log(a[2]!);
/** Whether Lean puts id `id` in the holdout part (`oracle.plan` with `part`). */
const isHeld = (id: string) => (call({ op: "oracle.plan", rows: [{ id, label: "x" }], part: "holdout" }).ids as string[]).length === 1;
/** An id in the wanted part: `r<n>`, or `r<n>y` when that flips it (`y` has an odd code point). */
const idIn = (held: boolean, n: number) => (isHeld(`r${n}`) === held ? `r${n}` : `r${n}y`);
/** The fake log of run `k`, and the replay row `collect` would store for it (state derived by Lean, redacted). */
const runLog = (k: number | string) => `j\ts\t2026-10-18T06:07:14Z error in run ${k}\n`;
function ciRow(k: number, label: string, id?: string): Json {
  const st = call({ op: "oracle.triage.state", lines: runLog(k).split("\n") }).state;
  return { ...(id ? { id } : {}), runId: k, headSha: RUN_SHA, state: call({ op: "oracle.request", name: "ci-triage", names: [], state: st }).state, label };
}

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
  it("live call: redacted body, key only in the header, logged without the key; the same request replays", async () => {
    const ff = fakeFetch(() => new Response(fx("confident-real")));
    const d = deps({ fetch: ff.fetch });
    const a = await ask(d, { question: "ci-triage", state, thresholds: ALL, provenance: LOGP });
    expect(a.source).toBe("live");
    expect(a.decision).toEqual({ action: "advise", advice: { kind: "pick", value: "real" }, gate: { num: "24", den: "25" } });
    expect(ff.sent).toHaveLength(1);
    expect(ff.sent[0]!.url).toBe("https://api.typesafe.ai/v1/systemone");
    expect(ff.sent[0]!.auth).toBe(`Bearer ${FAKE_KEY}`);
    expect(ff.sent[0]!.body).not.toContain("/Users/");
    expect(ff.sent[0]!.body).not.toContain(FAKE_KEY);
    expect(JSON.parse(ff.sent[0]!.body).model).toBe("jev-1.13.0");
    const log = readFileSync(d.logPath, "utf8");
    expect(log).not.toContain(FAKE_KEY);
    expect(log).not.toContain("/Users/");
    const b = await ask(d, { question: "ci-triage", state, thresholds: ALL, provenance: LOGP });
    expect(b.source).toBe("replay");
    expect(b.decision).toEqual(a.decision);
    expect(ff.sent).toHaveLength(1);
  });
  it("uncalibrated (threshold null) escalates even a confident answer", async () => {
    const a = await ask(deps(), { question: "ci-triage", state, thresholds: null, provenance: LOGP });
    expect(a.decision.action).toBe("escalate");
    expect(decisionLine(a.decision)).toBe("escalate: uncalibrated (no threshold yet) (gate 0.960)");
  });
  it("no key: escalate noKey, nothing sent, nothing logged", async () => {
    const ff = fakeFetch(() => new Response(fx("confident-real")));
    const d = deps({ fetch: ff.fetch, readKey: () => null });
    const a = await ask(d, { question: "ci-triage", state, thresholds: ALL, provenance: LOGP });
    expect(a).toMatchObject({ source: "nokey", sent: false, decision: { action: "escalate", reason: { reason: "failure", failure: { kind: "noKey" } } } });
    expect(ff.sent).toHaveLength(0);
    expect(existsSync(d.logPath)).toBe(false);
  });
  it("HTTP 429 and a timeout escalate; failures are logged but not replayed", async () => {
    const ff = fakeFetch(({ n }) => n === 1 ? new Response("slow down", { status: 429 }) : Promise.reject(new DOMException("t", "TimeoutError")));
    const d = deps({ fetch: ff.fetch });
    const a = await ask(d, { question: "ci-triage", state, thresholds: ALL, provenance: LOGP });
    expect(a.decision).toEqual({ action: "escalate", reason: { reason: "failure", failure: { kind: "http", status: 429 } } });
    const b = await ask(d, { question: "ci-triage", state, thresholds: ALL, provenance: LOGP });
    expect(b.decision).toEqual({ action: "escalate", reason: { reason: "failure", failure: { kind: "timeout" } } });
    expect(ff.sent).toHaveLength(2);
    expect(readLog(d.logPath).map((e) => e.failure?.kind)).toEqual(["http", "timeout"]);
  });
  it("malformed, schema and no-match replies escalate", async () => {
    for (const [name, kind] of [["not-json", "malformed"], ["missing-probability", "schema"], ["other-model", "schema"]] as const) {
      const a = await ask(deps({ fetch: fakeFetch(() => new Response(fx(name))).fetch }), { question: "ci-triage", state, thresholds: ALL, provenance: LOGP });
      expect(a.decision, name).toMatchObject({ action: "escalate", reason: { reason: "failure", failure: { kind } } });
    }
    const u = await ask(deps({ fetch: fakeFetch(() => new Response(fx("confident-unknown"))).fetch }), { question: "ci-triage", state, thresholds: ALL, provenance: LOGP });
    expect(u.decision).toMatchObject({ action: "escalate", reason: { reason: "uncalibrated" } });
  });
  it("the daily cap (200) and the run cap (60) refuse before the keychain is read", async () => {
    const d = deps({ readKey: () => { throw new Error("keychain must not be read"); } });
    writeFileSync(d.logPath, Array.from({ length: 200 }, (_, i) => JSON.stringify({ key: `k${i}`, question: "q", model: "m", day: "2026-10-18", at: "", ms: 0 })).join("\n") + "\n");
    const a = await ask(d, { question: "ci-triage", state, thresholds: ALL, provenance: LOGP });
    expect(a).toMatchObject({ source: "refused", decision: { reason: { failure: { kind: "overBudget" } } } });
    const b = await ask(deps({ readKey: () => { throw new Error("no"); } }), { question: "ci-triage", state, thresholds: ALL, run: 60, provenance: LOGP });
    expect(b).toMatchObject({ source: "refused", decision: { reason: { failure: { kind: "overBudget" } } } });
  });
  it("a reply echoing the key is scrubbed before it is logged", async () => {
    const echo = fx("confident-real").replace("\"usage\"", `"note":"${FAKE_KEY}","usage"`);
    const d = deps({ fetch: fakeFetch(() => new Response(echo)).fetch });
    await ask(d, { question: "ci-triage", state, thresholds: ALL, provenance: LOGP });
    expect(readFileSync(d.logPath, "utf8")).not.toContain(FAKE_KEY);
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
  function io(over: Partial<Io> & { gh?: (args: string[]) => string }): Io & { lines: string[] } {
    const lines: string[] = [];
    const dir = over.dir ?? mkdtempSync(join(tmpdir(), "oracle-dir-"));
    const ghDir = mkdtempSync(join(tmpdir(), "oracle-gh-"));
    let t = 1_792_281_600;
    const env: Env = {
      dir: ghDir, core: call, gh: "gh", now: () => t, sleepUntil: async (u) => { t = Math.max(t, u); },
      exec: (args) => ({ status: 0, stdout: (over.gh ?? ghRun(runLog))(args), stderr: "< HTTP/2.0 200 OK\n" }),
    };
    return { deps: deps(), env: () => env, dir, names: [], out: (s) => lines.push(s), lines, git: fakeGit(), ...over };
  }
  it("triage <runId>: one advisory line; uncalibrated escalates", async () => {
    const x = io({ gh: ghRun(() => "build\tlake build\t2026-10-18T06:07:14Z error: unsolved goals\n") });
    expect(await oracleCli(["triage", "123"], process.cwd(), x)).toBe(0);
    expect(x.lines).toEqual(["oracle ci-triage 123: escalate: uncalibrated (no threshold yet) (gate 0.960) [live]"]);
  });
  it("triage with a stored threshold advises", async () => {
    const dir = mkdtempSync(join(tmpdir(), "oracle-dir-"));
    writeFileSync(join(dir, "thresholds.json"), JSON.stringify({ "ci-triage": { thresholds: ALL } }));
    expect(thresholdsOf(dir, "ci-triage")).toEqual(ALL);
    const x = io({ dir });
    expect(await oracleCli(["triage", "123"], process.cwd(), x)).toBe(0);
    expect(x.lines).toEqual(["oracle ci-triage 123: advise real (gate 0.960) [live]"]);
  });
  it("triage refuses a non-numeric run id", async () => {
    const x = io({});
    expect(await oracleCli(["triage", "abc"], process.cwd(), x)).toBe(64);
  });
  it("calibrate: no key leaves the threshold untouched", async () => {
    const dir = mkdtempSync(join(tmpdir(), "oracle-dir-"));
    writeFileSync(join(dir, "ci-triage.jsonl"), JSON.stringify({ ...ciRow(1, "real"), labelSource: "t" }) + "\n");
    writeFileSync(join(dir, "thresholds.json"), JSON.stringify({ "ci-triage": null }));
    const x = io({ dir, deps: deps({ readKey: () => null }) });
    expect(await oracleCli(["calibrate", "ci-triage"], process.cwd(), x)).toBe(2);
    expect(JSON.parse(readFileSync(join(dir, "thresholds.json"), "utf8"))).toEqual({ "ci-triage": null });
  });
  type Spec = [number, string, string, "choose" | "holdout"][];
  /** The same groups in both parts. */
  const both = (gs: [number, string, string][]): Spec => [...gs.map(([n, f, l]) => [n, f, l, "choose"] as Spec[number]),
    ...gs.map(([n, f, l]) => [n, f, l, "holdout"] as Spec[number])];
  // rows labeled in order, each in its part (its id), with the fixture it is answered with
  function replaySet(dir: string, spec: Spec): string[] {
    const rows: string[] = [];
    const answers: string[] = [];
    for (const [n, fixture, label, part] of spec) for (let i = 0; i < n; i++) {
      const k = rows.length + 1;
      rows.push(JSON.stringify(ciRow(k, label, idIn(part === "holdout", k))));
      answers.push(fixture);
    }
    writeFileSync(join(dir, "ci-triage.jsonl"), rows.join("\n") + "\n");
    return answers;
  }
  it("calibrate: 5 confident hits per option and 2 unsure flake misses in each part: flake 24/25, infra and real at the unsure gate", async () => {
    const dir = mkdtempSync(join(tmpdir(), "oracle-dir-"));
    const ans = replaySet(dir, both([[5, "confident-flake", "flake"], [5, "confident-infra", "infra"], [5, "confident-real", "real"], [2, "unsure-flake", "real"]]));
    const ff = fakeFetch(({ n }) => new Response(fx(ans[n - 1]!)));
    const x = io({ dir, deps: deps({ fetch: ff.fetch }) });
    expect(await oracleCli(["calibrate", "ci-triage"], process.cwd(), x)).toBe(0);
    const t = JSON.parse(readFileSync(join(dir, "thresholds.json"), "utf8"))["ci-triage"];
    expect(t).toMatchObject({ thresholds: { flake: { num: "24", den: "25" }, infra: { num: "1", den: "5" }, real: { num: "1", den: "5" } },
      choose: { rows: 17, covered: 15, hits: 15 }, holdout: { rows: 17, covered: 15, hits: 15 }, used: 34, rows: 34,
      model: "jev-1.13.0", status: "MEASURED" });
    expect(ff.sent).toHaveLength(34);
  });
  it("calibrate: the round-1 set (10 confident real, 2 unsure, no flake or infra rows): only real gets a threshold", async () => {
    const dir = mkdtempSync(join(tmpdir(), "oracle-dir-"));
    const ans = replaySet(dir, both([[10, "confident-real", "real"], [2, "unsure-flake", "real"]]));
    const x = io({ dir, deps: deps({ fetch: fakeFetch(({ n }) => new Response(fx(ans[n - 1]!))).fetch }) });
    expect(await oracleCli(["calibrate", "ci-triage"], process.cwd(), x)).toBe(0);
    expect(JSON.parse(readFileSync(join(dir, "thresholds.json"), "utf8"))["ci-triage"]).toMatchObject({ thresholds: { flake: null, infra: null, real: { num: "1", den: "5" } }, used: 24 });
  });
  it("calibrate: thresholds the holdout part contradicts are not certified (the choose part alone would give them)", async () => {
    const dir = mkdtempSync(join(tmpdir(), "oracle-dir-"));
    const ans = replaySet(dir, [[5, "confident-flake", "flake", "choose"], [5, "confident-real", "real", "choose"],
      [5, "confident-flake", "real", "holdout"], [5, "confident-real", "flake", "holdout"]]);
    const x = io({ dir, deps: deps({ fetch: fakeFetch(({ n }) => new Response(fx(ans[n - 1]!))).fetch }) });
    expect(await oracleCli(["calibrate", "ci-triage"], process.cwd(), x)).toBe(0);
    expect(JSON.parse(readFileSync(join(dir, "thresholds.json"), "utf8"))["ci-triage"]).toMatchObject(
      { thresholds: { flake: null, infra: null, real: null }, choose: { rows: 10 }, holdout: { rows: 10 } });
  });
  it("calibrate sends every labeled row; eval only the holdout part, and reports MEASURED accuracy and coverage", async () => {
    const dir = mkdtempSync(join(tmpdir(), "oracle-dir-"));
    const ans = replaySet(dir, [[3, "confident-real", "real", "choose"], [3, "confident-real", "real", "holdout"],
      [1, "confident-flake", "infra", "holdout"], [1, "unsure-flake", "flake", "holdout"]]);
    const cal = fakeFetch(({ n }) => new Response(fx(ans[n - 1]!)));
    const x = io({ dir, deps: deps({ fetch: cal.fetch }) });
    expect(await oracleCli(["calibrate", "ci-triage"], process.cwd(), x)).toBe(0);
    expect(cal.sent).toHaveLength(8);
    writeFileSync(join(dir, "thresholds.json"), JSON.stringify({ "ci-triage": { thresholds: ALL } }));
    const ev = fakeFetch(({ n }) => new Response(fx(ans[n + 2]!)));
    const y = io({ dir, deps: deps({ fetch: ev.fetch }) });
    expect(await oracleCli(["eval", "ci-triage"], process.cwd(), y)).toBe(0);
    expect(ev.sent).toHaveLength(5);
    expect(y.lines).toEqual([`oracle eval ci-triage (MEASURED, holdout): thresholds ${JSON.stringify(ALL)}, accuracy 3/4 = 75.0 %, ` +
      "coverage 4/5 = 80.0 % (used 5, dropped 0; live 5)"]);
    expect(JSON.parse(readFileSync(join(dir, "thresholds.json"), "utf8"))).toEqual({ "ci-triage": { thresholds: ALL } });
  });
  it("eval without a threshold covers nothing", async () => {
    const dir = mkdtempSync(join(tmpdir(), "oracle-dir-"));
    replaySet(dir, [[2, "confident-real", "real", "holdout"]]);
    const x = io({ dir });
    expect(await oracleCli(["eval", "ci-triage"], process.cwd(), x)).toBe(0);
    expect(x.lines[0]).toContain("accuracy 0/0 = n/a, coverage 0/2 = 0.0 %");
  });
});

describe.skipIf(!hasCore)("round-2 review fixes", () => {
  it("a pick that is not the most probable option is a schema failure (both reviewer replies)", () => {
    for (const n of ["pick-not-max-flake", "pick-not-max-unknown"]) {
      const v = call({ op: "oracle.validate", name: "ci-triage", reply: fx(n) });
      expect(v, n).toMatchObject({ ok: false, failure: { kind: "schema" } });
    }
  });
  it("a threshold outside (0, 1] is refused", () => {
    for (const t of [{ num: "0", den: "1" }, { num: "3", den: "2" }])
      expect(() => call({ op: "oracle.decide", name: "ci-triage", thresholds: { real: t }, reply: fx("confident-real") })).toThrow("outside (0, 1]");
  });
  it("a reply over 64 KiB is logged capped and escalates as malformed", async () => {
    const big = "x".repeat(70_000);
    const d = deps({ fetch: fakeFetch(() => new Response(big)).fetch });
    const a = await ask(d, { question: "ci-triage", state, thresholds: ALL, provenance: LOGP });
    const logged = readLog(d.logPath)[0]!.reply!;
    expect(Buffer.byteLength(logged, "utf8")).toBeLessThanOrEqual(65_536);
    expect(logged.endsWith(" [truncated]")).toBe(true);
    expect(decisionLine(a.decision)).toBe("escalate: failure malformed");
  });
  it("the mistake-class replay set: CONFIRMED ledger rows, title/symptom/rootCause only, no split key, both parts", () => {
    const rows = readFileSync(join(golden, "mistake-class.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l) as Json & { state: Json });
    expect(rows.length).toBeGreaterThan(100);
    for (const r of rows) expect(Object.keys(r.state).sort()).toEqual(["rootCause", "symptom", "title"]);
    for (const r of rows) expect(Object.keys(r).sort()).toEqual(["id", "label", "state"]);
    const q = call({ op: "oracle.question", name: "mistake-class" }) as { perOption: number; spec: Json };
    expect(q.perOption).toBe(1);
    const held = (call({ op: "oracle.plan", rows, part: "holdout" }).ids as string[]).length;
    expect(held).toBeGreaterThan(0);
    expect(held).toBeLessThan(rows.length);
  });
});

describe.skipIf(!hasCore)("round-3: provenance, the Lean body, no partial threshold", () => {
  function io(over: Partial<Io> & { gh?: (args: string[]) => string }): Io & { lines: string[] } {
    const lines: string[] = [];
    let t = 1_792_281_600;
    const env: Env = {
      dir: mkdtempSync(join(tmpdir(), "oracle-gh-")), core: call, gh: "gh", now: () => t, sleepUntil: async (u) => { t = Math.max(t, u); },
      exec: (args) => ({ status: 0, stdout: (over.gh ?? ghRun(runLog))(args), stderr: "< HTTP/2.0 200 OK\n" }),
    };
    return { deps: deps(), env: () => env, dir: mkdtempSync(join(tmpdir(), "oracle-dir-")), names: [], out: (s) => lines.push(s), lines,
      git: fakeGit(), ...over };
  }
  it("a state without provenance is refused before the keychain is read; nothing is sent", async () => {
    const ff = fakeFetch(() => new Response(fx("confident-real")));
    const a = await ask(deps({ fetch: ff.fetch, readKey: () => { throw new Error("keychain must not be read"); } }),
      { question: "ci-triage", state, thresholds: ALL, provenance: {} });
    expect(a).toMatchObject({ source: "refused", sent: false, decision: { reason: { failure: { kind: "unsourced" } } } });
    expect(ff.sent).toHaveLength(0);
  });
  it("a self-hosted job, a job without runs-on, a line not in the log or a field the question does not declare is unsourced", async () => {
    const withJobs = (jobs: Json[]) => Object.fromEntries(Object.keys(state).map((k) => [k, { ...LOGP.log!, jobs }]));
    for (const jobs of [[{ runsOn: "ubuntu-24.04-arm" }, { runsOn: "self-hosted" }], [{ runsOn: "macos-26" }, { job: "call" }],
      [{ runsOn: "${{ matrix.os }}" }], [{ runsOn: "macos-26\nself-hosted" }], [{ runsOn: { group: "g" } }], []]) {
      const a = await ask(deps(), { question: "ci-triage", state, thresholds: ALL, provenance: withJobs(jobs) });
      expect(a.decision, JSON.stringify(jobs)).toMatchObject({ reason: { failure: { kind: "unsourced" } } });
    }
    const c = await ask(deps(), { question: "ci-triage", state: { ...state, log: ["error at /Users/example/w/x.lean:4"] }, thresholds: ALL, provenance: LOGP });
    expect(c.decision).toMatchObject({ reason: { failure: { kind: "unsourced" } } });
    const b = await ask(deps(), { question: "ci-triage", state: { note: "x" }, thresholds: ALL, provenance: { note: LOGP.log! } });
    expect(b.decision).toMatchObject({ reason: { failure: { kind: "unsourced" } } });
  });
  it("round 5: a question accepts only its own provenance kind", async () => {
    const m = await ask(deps(), { question: "mistake-class", state: { title: "done" }, thresholds: null, provenance: { title: LOGP.log! } });
    expect(m.decision).toMatchObject({ reason: { failure: { kind: "unsourced" } } });
    const c = call({ op: "oracle.pre", name: "ci-triage", state: { log: "done" }, today: "2026-10-18", publicHead: PUB,
      provenance: { log: { kind: "committedPublic", path: LEDGER, sha: PUB } }, files: [{ path: LEDGER, sha: PUB, content: "done" }] });
    expect(c).toMatchObject({ pre: "refuse", failure: { kind: "unsourced" } });
  });
  it("round 5: job facts from YAML; anything but a hosted label list is not public", () => {
    const f = jobsOfYaml("w.yml", [
      "jobs:", "  a:", "    runs-on: ubuntu-24.04-arm", "  b:", "    runs-on: [macos-26]", "  c:", "    runs-on: ${{ matrix.os }}",
      "  d:", "    runs-on: |", "      ubuntu-latest", "      self-hosted", "  e:", "    runs-on:", "      group: g", "  f:",
      "    uses: ./.github/workflows/x.yml", ""].join("\n"));
    expect(f).toEqual([{ file: "w.yml", job: "a", runsOn: "ubuntu-24.04-arm" }, { file: "w.yml", job: "b", runsOn: ["macos-26"] },
      { file: "w.yml", job: "c", runsOn: "${{ matrix.os }}" }, { file: "w.yml", job: "d", runsOn: "ubuntu-latest\nself-hosted\n" },
      { file: "w.yml", job: "e", runsOn: { group: "g" } }, { file: "w.yml", job: "f" }]);
    const hosted = (jobs: Json[]) => call({ op: "oracle.hosted", jobs }).hosted;
    expect(hosted(f.slice(0, 2))).toBe(true);
    for (const j of f.slice(2)) expect(hosted([f[0]!, j]), JSON.stringify(j)).toBe(false);
    expect(jobsOfYaml("x.yml", "jobs: [a, b]")).toEqual([{ file: "x.yml" }]);
    expect(jobsOfYaml("x.yml", "on: push\n")).toEqual([{ file: "x.yml" }]);
    expect(jobsOfYaml("x.yml", "jobs:\n  a: {\n")).toEqual([{ file: "x.yml" }]);
    expect(hosted(jobsOfYaml("x.yml", "on: push\n"))).toBe(false);
  });
  it("round 5: the job facts span every workflow file at the run's head; one self-hosted job anywhere makes the log not public", async () => {
    const x = io({});
    expect(call({ op: "oracle.hosted", jobs: jobFacts(x, RUN_SHA) }).hosted).toBe(true);
    expect(jobFacts(x, "f".repeat(40))).toEqual([]);
    const y = io({ git: fakeGit(undefined, { ...HOSTED_WF, ".github/workflows/bench.yml": "jobs:\n  b:\n    runs-on: [self-hosted, macOS]\n" }) });
    expect(await oracleCli(["triage", "123"], process.cwd(), y)).toBe(0);
    expect(y.lines).toEqual(["oracle ci-triage 123: escalate: failure unsourced [refused]"]);
  });
  it("the bytes sent are exactly the body Lean built from the redacted state", async () => {
    const ff = fakeFetch(() => new Response(fx("confident-real")));
    await ask(deps({ fetch: ff.fetch }), { question: "ci-triage", state, thresholds: ALL, provenance: LOGP });
    const pre = call({ op: "oracle.pre", name: "ci-triage", state, provenance: LOGP, today: "2026-10-18" });
    expect(pre.pre).toBe("send");
    expect(ff.sent[0]!.body).toBe(pre.bodyText);
    expect(ff.sent[0]!.body).toBe(call({ op: "oracle.request", name: "ci-triage", state }).bodyText);
  });
  it("every mistake-class row is sourced from the ledger at the public head (a fake origin/main holding the ledger)", async () => {
    const rows = readFileSync(join(golden, "mistake-class.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l) as { state: Json });
    const ledger = readFileSync(join(golden, "..", "..", "..", "..", LEDGER), "utf8");
    const src = await sourcer(io({ git: fakeGit(ledger) }))("mistake-class", rows[0]!.state, {});
    expect(src.files[0]).toMatchObject({ path: LEDGER, sha: PUB });
    expect(src.publicHead).toBe(PUB);
    for (const r of rows.slice(0, 20)) {
      const p = call({ op: "oracle.pre", name: "mistake-class", state: r.state, ...src, provenance: Object.fromEntries(Object.keys(r.state).map((k) => [k, src.provenance.title])), today: "2026-10-18" });
      expect(p.pre).toBe("send");
    }
    const forged = call({ op: "oracle.pre", name: "mistake-class", state: { title: "not in the ledger" }, ...src, today: "2026-10-18" });
    expect(forged).toMatchObject({ pre: "refuse", failure: { kind: "unsourced" } });
  });
  it("triage: the job facts come from the workflows at the run's head commit; an unknown commit is unsourced", async () => {
    const x = io({ gh: ghRun(runLog, "f".repeat(40)) });
    expect(await oracleCli(["triage", "123"], process.cwd(), x)).toBe(0);
    expect(x.lines).toEqual(["oracle ci-triage 123: escalate: failure unsourced [refused]"]);
  });
  it("calibrate over 70 rows: the run cap cuts the first run (no write, exit 2); --resume replays 60 and sends 10", async () => {
    const dir = mkdtempSync(join(tmpdir(), "oracle-dir-"));
    const rows = Array.from({ length: 70 }, (_, i) => JSON.stringify(ciRow(i + 1, "real")));
    writeFileSync(join(dir, "ci-triage.jsonl"), rows.join("\n") + "\n");
    const ff = fakeFetch(() => new Response(fx("confident-real")));
    const d = deps({ fetch: ff.fetch });
    const x = io({ dir, deps: d });
    expect(await oracleCli(["calibrate", "ci-triage"], process.cwd(), x)).toBe(2);
    expect(ff.sent).toHaveLength(60);
    expect(existsSync(join(dir, "thresholds.json"))).toBe(false);
    expect(x.lines[0]).toContain("not written");
    const y = io({ dir, deps: d });
    expect(await oracleCli(["calibrate", "ci-triage", "--resume"], process.cwd(), y)).toBe(0);
    expect(ff.sent).toHaveLength(70);
    expect(JSON.parse(readFileSync(join(dir, "thresholds.json"), "utf8"))["ci-triage"]).toMatchObject({ used: 70, rows: 70 });
    expect(y.lines[0]).toContain("replay 60, live 10");
  });
  it("calibrate --resume with more missing rows than the run cap sends nothing", async () => {
    const dir = mkdtempSync(join(tmpdir(), "oracle-dir-"));
    writeFileSync(join(dir, "ci-triage.jsonl"), Array.from({ length: 61 }, (_, i) =>
      JSON.stringify(ciRow(i + 1, "real"))).join("\n") + "\n");
    const ff = fakeFetch(() => new Response(fx("confident-real")));
    const x = io({ dir, deps: deps({ fetch: ff.fetch }) });
    expect(await oracleCli(["calibrate", "ci-triage", "--resume"], process.cwd(), x)).toBe(2);
    expect(ff.sent).toHaveLength(0);
    expect(x.lines[0]).toContain("61 rows are not in the answer log");
  });
  it("calibrate with --limit (a cut set) prints but does not write", async () => {
    const dir = mkdtempSync(join(tmpdir(), "oracle-dir-"));
    writeFileSync(join(dir, "ci-triage.jsonl"), Array.from({ length: 3 }, (_, i) =>
      JSON.stringify(ciRow(i + 1, "real"))).join("\n") + "\n");
    const x = io({ dir });
    expect(await oracleCli(["calibrate", "ci-triage", "--limit", "2"], process.cwd(), x)).toBe(2);
    expect(existsSync(join(dir, "thresholds.json"))).toBe(false);
  });
  it("round 4: the ledger is read at origin/main, never HEAD; a commit other than the public head is notPublic", async () => {
    const other = "a".repeat(40), pub = "b".repeat(40);
    const seen: string[][] = [];
    const git = (args: string[]) => {
      seen.push(args);
      if (args[0] === "rev-parse") return args.some((a) => a.startsWith("origin/main")) ? `${pub}\n` : `${other}\n`;
      if (args[0] === "show") return '{"title":"a title"}';
      return undefined;
    };
    const src = await sourcer(io({ git }))("mistake-class", { title: "a title" }, {});
    expect(src).toMatchObject({ files: [{ path: LEDGER, sha: pub }], publicHead: pub });
    expect(seen.some((a) => a.includes("HEAD"))).toBe(false);
    const pre = (sha: string, head?: string) => call({ op: "oracle.pre", name: "mistake-class", state: { title: "a title" },
      provenance: { title: { kind: "committedPublic", path: LEDGER, sha } }, files: [{ path: LEDGER, sha, content: '{"title":"a title"}' }],
      ...(head ? { publicHead: head } : {}), today: "2026-10-18" });
    expect(pre(pub, pub).pre).toBe("send");
    expect(pre(other, pub)).toMatchObject({ pre: "refuse", failure: { kind: "notPublic" } });
    expect(pre(pub)).toMatchObject({ pre: "refuse", failure: { kind: "notPublic" } });
  });
  it("round 4: a state line must be a whole line or a whole string value of the file", () => {
    const pre = (title: string) => call({ op: "oracle.pre", name: "mistake-class", state: { title },
      provenance: { title: { kind: "committedPublic", path: LEDGER, sha: PUB } },
      files: [{ path: LEDGER, sha: PUB, content: '{"t":"a \\"quoted\\" title", "u":"b"}' }], publicHead: PUB, today: "2026-10-18" });
    expect(pre('a "quoted" title').pre).toBe("send");
    for (const part of ["quoted", "title", ", ", "b\""]) expect(pre(part), part).toMatchObject({ pre: "refuse", failure: { kind: "unsourced" } });
  });
  it("round 4: calibrate writes only when every labeled id has an answer", async () => {
    const dir = mkdtempSync(join(tmpdir(), "oracle-dir-"));
    writeFileSync(join(dir, "ci-triage.jsonl"), Array.from({ length: 6 }, (_, i) =>
      JSON.stringify(ciRow(i + 1, "real"))).join("\n") + "\n");
    const ff = fakeFetch(({ n }) => n === 3 ? new Response("busy", { status: 500 }) : new Response(fx("confident-real")));
    const x = io({ dir, deps: deps({ fetch: ff.fetch }) });
    expect(await oracleCli(["calibrate", "ci-triage"], process.cwd(), x)).toBe(2);
    expect(ff.sent).toHaveLength(6);
    expect(x.lines[0]).toContain("used 5/6");
    expect(x.lines[0]).toContain("not written");
    expect(existsSync(join(dir, "thresholds.json"))).toBe(false);
  });
  it("round 4: the reviewer's round-3 probe never makes flake advisable (per-option, no pooling)", () => {
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
