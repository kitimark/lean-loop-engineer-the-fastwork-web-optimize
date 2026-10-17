// fw incidents lint: golden vectors of fwcore `plan.incidentLint` (Fw.Plan.Incident), the fact collection, and the real
// ledger. The golden responses come from the fwcore binary; regenerate with
//   FW_WRITE_INCIDENT_GOLDEN=1 pnpm --filter ./apps/runner exec vitest run test/incidents.test.ts
import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { existingFiles, gitOnMain, incidentsCli, renderIncidents, taskRows, type IncidentReply } from "../src/incidents.ts";
import { coreCandidates, coreCaller } from "../src/watch.ts";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "../../..");
const goldenFile = join(root, "packages/contracts/golden/plan/incident-lint.jsonl");
const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd: root, encoding: "utf8" }).trim();
const bin = coreCandidates(root, join(common, "..")).find((b) => {
  try { return execFileSync(b, ["--ops"], { encoding: "utf8" }).includes("plan.incidentLint"); } catch { return false; }
});

// ---- golden cases (requests only; responses are fwcore's) ----
const tasks = [
  { id: "a", evidence: "1c64c85", agent: null }, { id: "b", evidence: null, agent: "b" },
  { id: "c", evidence: null, agent: null }, { id: "d", evidence: "ca48604", agent: "d" },
];
const facts = { tasks, commits: ["1c64c85", "ca48604"], files: ["docs/team/incidents/ledger.json"] };
const good = {
  id: "inc-good", at: "2026-10-18T00:00+07:00", title: "t", symptom: "s", cause: "CONFIRMED (code read): x",
  evidence: [{ kind: "commit", ref: "1c64c85", note: "n" }, { kind: "ci", ref: "39057124869", note: "n" },
    { kind: "file", ref: "docs/team/incidents/ledger.json", note: "n" }],
  repro: "r", fix: { task: "a", also: ["d"] }, regression: "g",
};
const req = (incidents: unknown, extra: Record<string, unknown> = {}) => ({ op: "plan.incidentLint", incidents, ...facts, ...extra });
const cases: [string, Record<string, unknown>][] = [
  ["good: commit, ci and file evidence on main, fix and also tasks done: fixed, no finding", req([good])],
  ["fixing: an also task is claimed (agent, no evidence)", req([{ ...good, fix: { task: "a", also: ["b"] } }])],
  ["open: the fix task is neither done nor claimed", req([{ ...good, fix: { task: "c" } }])],
  ["no fix.task: missingFixTask; a claimed also task still makes it fixing", req([{ ...good, fix: { also: ["b"] } }])],
  ["fix null: no fix task, open", req([{ ...good, fix: null }])],
  ["unknown fix and also tasks are named in the detail", req([{ ...good, fix: { task: "zz", also: ["c", "yy"] } }])],
  ["no evidence, blank repro, missing regression", req([{ ...good, evidence: [], repro: " \n", regression: undefined }])],
  ["evidence key missing: noEvidence", req([{ ...good, evidence: undefined }])],
  ["bad refs: commit not hex, ci not a run id, home-path file; unknown kind", req([{ ...good, evidence: [
    { kind: "commit", ref: "HEAD" }, { kind: "ci", ref: "run-7" }, { kind: "file", ref: "~/notes.md" }, { kind: "photo", ref: "p" }] }])],
  ["commit not on main and file missing (well-formed refs, not in the fact sets)", req([{ ...good, evidence: [
    { kind: "commit", ref: "abcdef0" }, { kind: "file", ref: "docs/none.md" }] }])],
  ["event and proc refs are warnings only: ok", req([{ ...good, evidence: [{ kind: "event", ref: "480" }, { kind: "proc", ref: "until grep -q x f; sleep 3" }] }])],
  ["empty event ref is a bad ref", req([{ ...good, evidence: [{ kind: "event", ref: "" }] }])],
  ["evidence item without kind or ref: unknownKind", req([{ ...good, evidence: [{ note: "n" }] }])],
  ["a status field is an error and is never read (status: fixed on an open incident)", req([{ ...good, fix: { task: "c" }, status: "fixed" }])],
  ["a null status field is still a status field", req([{ ...good, status: null }])],
  ["cause without a status prefix; lowercase does not count", req([{ ...good, cause: "confirmed: x" }])],
  ["INFERRED and MEASURED are status prefixes", req([{ ...good, cause: "INFERRED x" }, { ...good, id: "inc-m", cause: "MEASURED (run 1) y" }])],
  ["duplicate ids: both records report dupId", req([good, { ...good, fix: { task: "c" } }])],
  ["order: two incidents", req([good, { ...good, id: "inc-open", fix: { task: "c" }, evidence: [] }])],
  ["order: the same two incidents reversed give the same results, reversed", req([{ ...good, id: "inc-open", fix: { task: "c" }, evidence: [] }, good])],
  ["more facts never add a finding: no commits and no files known", req([good], { commits: [], files: [] })],
  ["no tasks: every fix task is missing", req([good], { tasks: [] })],
  ["empty ledger: ok", req([])],
  ["refused: missing incidents", { op: "plan.incidentLint", tasks }],
  ["refused: missing tasks", { op: "plan.incidentLint", incidents: [good] }],
  ["refused: an incident without id", req([{ ...good, id: undefined }])],
  ["refused: a non-string ref", req([{ ...good, evidence: [{ kind: "commit", ref: 7 }] }])],
];

/** Run request lines through one fwcore process; replies without the id. */
function fwcore(reqs: Record<string, unknown>[]): Record<string, unknown>[] {
  const out = spawnSync(bin!, [], { input: reqs.map((r) => JSON.stringify(r)).join("\n") + "\n", encoding: "utf8", env: { ...process.env, LEAN_ABORT_ON_PANIC: "1" } });
  return out.stdout.trim().split("\n").map((l) => { const { id: _, ...rest } = JSON.parse(l); return rest; });
}

describe("plan.incidentLint golden (packages/contracts/golden/plan/incident-lint.jsonl)", () => {
  it("fwcore with plan.incidentLint is built (cd lean && lake build)", () => expect(bin).toBeTruthy());

  it("the file holds exactly the cases above, and fwcore gives every stored response", () => {
    const reqs = cases.map(([, r]) => JSON.parse(JSON.stringify(r)) as Record<string, unknown>);
    const got = fwcore(reqs);
    if (process.env.FW_WRITE_INCIDENT_GOLDEN) {
      writeFileSync(goldenFile, cases.map(([name], i) => JSON.stringify({ name, request: reqs[i], response: got[i] })).join("\n") + "\n");
    }
    const lines = readFileSync(goldenFile, "utf8").trim().split("\n").map((l) => JSON.parse(l)) as { name: string; request: unknown; response: unknown }[];
    expect(lines.map((l) => l.name)).toEqual(cases.map(([n]) => n));
    expect(lines.map((l) => l.request)).toEqual(reqs);
    expect(got).toEqual(lines.map((l) => l.response));
  });

  it("covers good, bad and edge: fixed/fixing/open, ok and not ok, refusals", () => {
    const lines = readFileSync(goldenFile, "utf8").trim().split("\n").map((l) => JSON.parse(l)) as { response: Partial<IncidentReply> & { error?: string } }[];
    const st = new Set(lines.flatMap((l) => (l.response.incidents ?? []).map((i) => i.status)));
    expect([...st].sort()).toEqual(["fixed", "fixing", "open"]);
    expect(lines.some((l) => l.response.ok === true) && lines.some((l) => l.response.ok === false)).toBe(true);
    expect(lines.filter((l) => typeof l.response.error === "string").length).toBe(4);
    const codes = new Set(lines.flatMap((l) => (l.response.incidents ?? []).flatMap((i) => i.findings.map((f) => f.code))));
    for (const c of ["noEvidence", "unknownKind", "badRef", "commitNotOnMain", "fileMissing", "missingFixTask", "missingRepro",
      "missingRegression", "noStatusPrefix", "statusField", "dupId", "eventRef", "procRef"]) expect(codes.has(c), c).toBe(true);
  });

  it("order independence: the reversed pair gives the reversed results", () => {
    const lines = readFileSync(goldenFile, "utf8").trim().split("\n").map((l) => JSON.parse(l)) as { name: string; response: IncidentReply }[];
    const a = lines.find((l) => l.name === "order: two incidents")!.response;
    const b = lines.find((l) => l.name.startsWith("order: the same two"))!.response;
    expect(b.incidents).toEqual([...a.incidents].reverse());
    expect(b.ok).toBe(a.ok);
  });
});

describe("fact collection", () => {
  it("taskRows: the board row wins, else the file row without an agent", () => {
    expect(taskRows({ tasks: [{ id: "a", evidence: "x" }, { id: "b" }] }, [{ id: "b", evidence: null, agent: "ag" }]))
      .toEqual([{ id: "a", evidence: "x", agent: null }, { id: "b", evidence: null, agent: "ag" }]);
    expect(taskRows({ tasks: [{ id: "a" }] }, null)).toEqual([{ id: "a", evidence: null, agent: null }]);
  });

  it("existingFiles: repo files only (absolute, escaping and missing refs are never facts)", () => {
    expect(existingFiles(root, ["docs/team/incidents/ledger.json", "/etc/hosts", "../x", "docs/none.md", ""]))
      .toEqual(["docs/team/incidents/ledger.json"]);
  });

  it("gitOnMain: a main commit yes, an unknown sha or an option-like ref no", () => {
    const on = gitOnMain(root);
    const head = execFileSync("git", ["rev-parse", "main"], { cwd: root, encoding: "utf8" }).trim();
    expect(on(head.slice(0, 7))).toBe(true);
    expect(on("0000000")).toBe(false);
    expect(on("--all")).toBe(false);
  });

  it("the CLI passes the raw records and only the verified facts to fwcore; exit follows ok", async () => {
    let seen: Record<string, unknown> = {};
    const reply = (ok: boolean): IncidentReply => ({ ok, errors: ok ? 0 : 1, warnings: 0, incidents: [] });
    const fake = (ok: boolean) => async (r: Record<string, unknown>) => { seen = r; return reply(ok) as never; };
    const deps = { board: async () => null, onMain: (r: string) => r === "1c64c85" };
    expect(await incidentsCli(["lint"], here, { ...deps, core: fake(true) })).toBe(0);
    const ledger = JSON.parse(readFileSync(join(root, "docs/team/incidents/ledger.json"), "utf8"));
    expect(seen.op).toBe("plan.incidentLint");
    expect(seen.incidents).toEqual(ledger.incidents);
    expect(seen.commits).toEqual(["1c64c85"]);
    expect(await incidentsCli(["lint"], here, { ...deps, core: fake(false) })).toBe(1);
    await expect(incidentsCli([], here)).rejects.toThrow(/usage/);
    await expect(incidentsCli(["show"], here)).rejects.toThrow(/usage/);
  });

  it("renderIncidents: one line per incident, then the totals", () => {
    const s = renderIncidents({ ok: false, errors: 1, warnings: 1, incidents: [
      { id: "i1", status: "open", findings: [{ code: "fileMissing", severity: "error", detail: "a.md" }, { code: "eventRef", severity: "warn", detail: "4" }] },
      { id: "i2", status: "fixed", findings: [] }] });
    expect(s.split("\n")).toHaveLength(3);
    expect(s).toMatch(/i1 +open +error fileMissing: a\.md; warn eventRef: 4/);
    expect(s).toMatch(/i2 +fixed +ok/);
  });
});

describe("the real ledger", () => {
  it("docs/team/incidents/ledger.json lints with 0 errors (real git facts, real fwcore, states from the work graph)", async () => {
    const r = await incidentsCli(["lint"], here, { board: async () => null, core: coreCaller(bin ? [bin] : []) });
    expect(r).toBe(0);
  });
});
