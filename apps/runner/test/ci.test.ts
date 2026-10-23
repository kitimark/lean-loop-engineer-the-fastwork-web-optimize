import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { describe, expect, it } from "vitest";
import { ciMain, ciRun, ciState, runStateWord, parseCiArgs, type CiFacts, type CiRunInfo } from "../src/ci.ts";
import { UsageError } from "../src/lib.ts";
import { fwcoreCall, type FwCall, type Gh } from "../src/run.ts";

const SHA = "0123456789abcdef0123456789abcdef01234567";
const IMG = "sha256:" + "ab".repeat(32);
const job = (name: string, conclusion = "success") => ({ name, conclusion });
const run = (over: Partial<CiRunInfo> = {}): CiRunInfo => ({
  runId: "42", workflowName: "chromium-counts", status: "completed", conclusion: "success", headSha: SHA,
  jobs: [job("plan"), job("counts (original, r1)"), job("counts (original, r2)"), job("counts (rewrite, r1)"), job("counts (rewrite, r2)"), job("classify")], ...over,
});
const ALL = ["chromium-counts-original-r1", "chromium-counts-original-r2", "chromium-counts-rewrite-r1", "chromium-counts-rewrite-r2"];

describe("parseCiArgs", () => {
  it("defaults and flags", () => {
    expect(() => parseCiArgs([])).toThrow(UsageError);
    expect(() => parseCiArgs(["--workflow", "lean"])).toThrow(UsageError);
    expect(parseCiArgs(["--branch", "ci/x"])).toEqual({ workflow: "chromium-counts", branch: "ci/x" });
    expect(parseCiArgs(["42"])).toEqual({ runId: "42", workflow: "chromium-counts" });
    expect(parseCiArgs(["123", "--branch", "ci/x", "--store", "/s"])).toEqual({ runId: "123", workflow: "chromium-counts", branch: "ci/x", store: "/s" });
    expect(() => parseCiArgs(["--nope"])).toThrow(UsageError);
    expect(() => parseCiArgs(["--branch"])).toThrow(UsageError);
    expect(() => parseCiArgs(["abc"])).toThrow(UsageError);
  });
});

const hasCore = (() => { try { fwcoreCall(process.cwd()); return true; } catch { return false; } })();

// The selection rule is fwcore's `store.ciRun` (lean/Fw/Store/Ci.lean; golden cases in packages/contracts/golden/store/ciRun.jsonl).
describe.skipIf(!hasCore)("store.ciRun through fwcore (table)", () => {
  const call: FwCall = hasCore ? fwcoreCall(process.cwd()) : () => ({});
  const facts = (names: string[], search = ""): CiFacts[] => names.map((name) => ({ name, profile: "swipe-v1", image: IMG, search: name.includes("rewrite") ? search : "" }));
  const cases: [string, CiRunInfo, string[], string[], string[] | "ok"][] = [
    ["complete run", run(), ALL, ["original", "rewrite"], "ok"],
    ["failed run", run({ conclusion: "failure" }), ALL, ["original", "rewrite"], ["run 42 concluded failure, not success"]],
    ["cancelled run", run({ conclusion: "cancelled" }), ALL, ["original", "rewrite"], ["run 42 concluded cancelled, not success"]],
    ["in progress", run({ status: "in_progress", conclusion: "" }), ALL, ["original", "rewrite"], ["run 42 is in_progress, not completed"]],
    ["other workflow", run({ workflowName: "webkit-sim" }), ALL, ["original", "rewrite"], ["run 42 is workflow webkit-sim, not chromium-counts"]],
    ["missing shard artifact", run(), ALL.slice(0, 3), ["original", "rewrite"], ["missing shard artifact chromium-counts-rewrite-r2"]],
    ["failed shard job", run({ jobs: [job("counts (original, r1)", "failure"), job("counts (original, r2)")] }), ALL.slice(0, 2), ["original"], ["shard chromium-counts-original-r1: job failure"]],
    ["missing classes dir", run(), ALL, ["original"], ["missing chromium-classes/rewrite"]],
    ["no shard jobs", run({ jobs: [job("plan")] }), [], [], ["run 42 has no counts shard jobs"]],
  ];
  for (const [name, r, have, dirs, want] of cases) {
    it(name, () => {
      const s = ciRun(call, r, { artifacts: facts(have), classes: dirs });
      if (want === "ok") expect(s).toMatchObject({ accept: true, refusals: [] });
      else expect(s).toEqual({ accept: false, refusals: want, targets: [] });
    });
  }
  it("before the download: shards per target, sorted, with their entry dirs, no key inputs", () => {
    const s = ciRun(call, run());
    expect(s.accept).toBe(true);
    expect(s.targets.map((t) => [t.target, t.classes, t.shards, t.meta])).toEqual([
      ["original", "original", [{ artifact: ALL[0], dir: "r1" }, { artifact: ALL[1], dir: "r2" }], undefined],
      ["rewrite", "rewrite", [{ artifact: ALL[2], dir: "r1" }, { artifact: ALL[3], dir: "r2" }], undefined]]);
  });
  it.each([
    ["", "original", []], ["?preset=strip-demo", "strip-demo", []], ["?fw=hero.countdown:strip", "original", ["hero.countdown:strip"]],
    ["?preset=p&fw=b:y,a:x", "p", ["a:x", "b:y"]],
  ])("rewrite query %s gives preset and flags; the original keeps the default", (q, preset, fw) => {
    const s = ciRun(call, run(), { artifacts: facts(ALL, q), classes: ["original", "rewrite"] });
    expect(s.targets.map((t) => t.meta && [t.meta.target, t.meta.preset, t.meta.fw])).toEqual([["original", "original", []], ["rewrite", preset, fw]]);
    expect(s.targets[0]!.key).not.toEqual(s.targets[1]!.key);
  });
  it("shards that disagree are refused", () => {
    const fs = facts(ALL);
    fs[1] = { ...fs[1]!, profile: "swipe-wheel-v1" };
    expect(ciRun(call, run(), { artifacts: fs, classes: ["original", "rewrite"] }).refusals).toEqual(["original shards disagree on profile, query, target or image"]);
  });
});

describe.skipIf(!hasCore)("ciMain against fwcore", () => {
  const call: FwCall = hasCore ? fwcoreCall(process.cwd()) : () => ({});
  const mk = () => mkdtempSync(join(tmpdir(), "fwci-"));
  const put = (p: string, s: string) => { mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, s); };
  /** A gh double: `run view` returns `info`, `run download` writes the artifacts of `shards`/`classes`. */
  function fakeGh(info: object, shards: string[], classes: string[], calls: string[][] = [], search = ""): Gh {
    return async (a) => {
      calls.push(a);
      if (a[0] === "run" && a[1] === "view") return JSON.stringify(info);
      if (a[0] === "run" && a[1] === "download") {
        const dir = a[a.indexOf("-D") + 1]!;
        for (const s of shards) {
          const t = s.split("-")[2]!;
          put(join(dir, s, "counts.json"), JSON.stringify({ profile: { id: "swipe-v1" }, meta: { target: t, search: t === "rewrite" ? search : "" } }));
          put(join(dir, s, "image-id.txt"), IMG + "\n");
        }
        for (const c of classes) put(join(dir, "chromium-classes", c, "classes.json"), `{"t":"${c}"}`);
        return "";
      }
      throw new Error(`unexpected gh ${a.join(" ")}`);
    };
  }
  const info = { workflowName: "chromium-counts", status: "completed", conclusion: "success", headSha: SHA, jobs: run().jobs };
  const deps = (gh: Gh, store: string, logs: string[]) => ({ call, gh, store, tmp: mk(), log: (l: string) => logs.push(l) });
  const files = (d: string): string[] => (existsSync(d) ? readdirSync(d, { recursive: true, withFileTypes: true }).filter((e) => e.isFile()).map((e) => join(e.parentPath, e.name)) : []);

  it("stores one key per target, and a second pull of the same run changes nothing", async () => {
    const store = mk(), logs: string[] = [];
    expect(await ciMain({ runId: "42", workflow: "chromium-counts", branch: "main" }, deps(fakeGh(info, ALL, ["original", "rewrite"]), store, logs))).toBe(0);
    expect(logs.filter((l) => l.includes(" stored,"))).toHaveLength(2);
    const before = files(store).sort();
    expect(before.filter((f) => f.endsWith("manifest.json"))).toHaveLength(2);
    const manifests = before.filter((f) => f.endsWith("manifest.json")).map((f) => JSON.parse(readFileSync(f, "utf8")));
    expect(manifests.map((m) => m.target).sort()).toEqual(["original", "rewrite"]);
    expect(manifests[0]).toMatchObject({ engine: "chromium", preset: "original", fw: [], profile: "swipe-v1", gitSha: SHA, image: IMG, runId: "42" });
    expect(manifests[0].entries.map((e: { name: string }) => e.name)).toEqual(expect.arrayContaining(["ci.json", "classes/classes.json", "r1/counts.json", "r2/image-id.txt"]));
    const logs2: string[] = [];
    expect(await ciMain({ runId: "42", workflow: "chromium-counts", branch: "main" }, deps(fakeGh(info, ALL, ["original", "rewrite"]), store, logs2))).toBe(0);
    expect(logs2.filter((l) => l.endsWith("(5 artifacts)") || l.includes(" unchanged "))).toHaveLength(2);
    expect(files(store).sort()).toEqual(before);
  });

  it("takes preset and flags of the rewrite from its query", async () => {
    const store = mk();
    const q = "?preset=strip-demo&fw=hero.countdown:strip";
    const rw = { ...info, jobs: [job("counts (rewrite, r1)"), job("counts (rewrite, r2)")] };
    expect(await ciMain({ runId: "42", workflow: "chromium-counts", branch: "main" }, deps(fakeGh(rw, ALL.slice(2), ["rewrite"], [], q), store, []))).toBe(0);
    const m = JSON.parse(readFileSync(files(store).find((f) => f.endsWith("manifest.json"))!, "utf8"));
    expect(m).toMatchObject({ target: "rewrite", preset: "strip-demo", fw: ["hero.countdown:strip"] });
  });

  it("refuses a failed run before downloading anything", async () => {
    const calls: string[][] = [], logs: string[] = [];
    expect(await ciMain({ runId: "42", workflow: "chromium-counts", branch: "main" }, deps(fakeGh({ ...info, conclusion: "failure" }, ALL, [], calls), mk(), logs))).toBe(2);
    expect(logs).toEqual(["refused: run 42 concluded failure, not success"]);
    expect(calls.some((c) => c[1] === "download")).toBe(false);
  });

  it("refuses a run with a missing shard and stores nothing", async () => {
    const store = mk(), logs: string[] = [];
    expect(await ciMain({ runId: "42", workflow: "chromium-counts", branch: "main" }, deps(fakeGh(info, ALL.slice(0, 3), ["original", "rewrite"]), store, logs))).toBe(2);
    expect(logs).toEqual(["refused: missing shard artifact chromium-counts-rewrite-r2"]);
    expect(files(store)).toEqual([]);
  });

  it("without a run id it takes the latest run of the workflow on the branch", async () => {
    const logs: string[] = [], calls: string[][] = [];
    const inner = fakeGh(info, ALL, ["original", "rewrite"], calls);
    const gh: Gh = async (a) => (a[0] === "run" && a[1] === "list" ? JSON.stringify([{ databaseId: 77 }]) : await inner(a));
    expect(await ciMain({ workflow: "chromium-counts", branch: "main" }, deps(gh, mk(), logs))).toBe(0);
    expect(calls.find((c) => c[1] === "view")![2]).toBe("77");
  });

  it("a different run with the same key is not overwritten", async () => {
    const store = mk();
    expect(await ciMain({ runId: "42", workflow: "chromium-counts", branch: "main" }, deps(fakeGh(info, ALL, ["original", "rewrite"]), store, []))).toBe(0);
    const logs: string[] = [];
    expect(await ciMain({ runId: "43", workflow: "chromium-counts", branch: "main" }, deps(fakeGh(info, ALL, ["original", "rewrite"]), store, logs))).toBe(2);
    expect(logs[0]).toMatch(/already stored from run 42/);
  });
});

describe("fw ci state <run id> (review-flow-v2-followups: the gate agent reads run states by identity)", () => {
  const rows = [{ databaseId: 7, status: "in_progress", conclusion: null }, { databaseId: 8, status: "completed", conclusion: "success" }, { databaseId: 9, status: "completed", conclusion: "failure" }, { databaseId: 10, status: "queued", conclusion: "" }];
  const seen: string[][] = [];
  const gh: Gh = async (args) => { seen.push(args); return JSON.stringify(rows); };
  const read = async (id: string) => { const out: string[] = []; const code = await ciState(id, { gh, log: (l) => out.push(l) }); return { code, out }; };
  it("maps status and conclusion to running, complete, failed", async () => {
    expect(await read("7")).toEqual({ code: 0, out: ["7 running"] });
    expect(await read("8")).toEqual({ code: 0, out: ["8 complete"] });
    expect(await read("9")).toEqual({ code: 0, out: ["9 failed"] });
    expect(await read("10")).toEqual({ code: 0, out: ["10 running"] });
    expect(runStateWord("completed", "cancelled")).toBe("failed");
  });
  it("an id not in the list is unknown (exit 2); a non-numeric id is a usage error; only gh run list is called", async () => {
    expect(await read("99")).toEqual({ code: 2, out: ["99 unknown"] });
    await expect(read("x1")).rejects.toThrow(UsageError);
    expect(seen.every((a) => a[0] === "run" && a[1] === "list")).toBe(true);
  });
  it("a run older than the newest 100 is found by the longer list when the list is filtered (MEASURED: 100 runs span about an hour)", async () => {
    const calls: string[][] = [];
    const all = Array.from({ length: 1000 }, (_, i) => ({ databaseId: 5000 - i, status: "completed", conclusion: i === 250 ? "success" : "failure" }));
    const big: Gh = async (args) => { calls.push(args); return JSON.stringify(all.slice(0, Number(args[args.indexOf("--limit") + 1]))); };
    const out: string[] = [];
    expect(await ciState(String(5000 - 250), { gh: big, log: (l) => out.push(l), branch: "ci/x" })).toBe(0);
    expect(out).toEqual(["4750 complete"]);
    expect(calls.map((a) => a[a.indexOf("--limit") + 1])).toEqual(["100", "400"]);
    expect(calls.every((a) => a[0] === "run" && a[1] === "list")).toBe(true);
  });
  it("an id in none of the lists is unknown after the last limit; a short list stops at once; --branch and --workflow narrow", async () => {
    const calls: string[][] = [];
    const all = Array.from({ length: 1000 }, (_, i) => ({ databaseId: 9000 - i, status: "completed", conclusion: "success" }));
    const big: Gh = async (args) => { calls.push(args); return JSON.stringify(all.slice(0, Number(args[args.indexOf("--limit") + 1]))); };
    const out: string[] = [];
    expect(await ciState("1", { gh: big, log: (l) => out.push(l), branch: "ci/x", workflow: "wktr" })).toBe(2);
    expect(out).toEqual(["1 unknown"]);
    expect(calls.map((a) => a[a.indexOf("--limit") + 1])).toEqual(["100", "400", "1000"]);
    expect(calls[0]!.slice(0, 6)).toEqual(["run", "list", "--branch", "ci/x", "--workflow", "wktr"]);
    calls.length = 0;
    const small: Gh = async (args) => { calls.push(args); return JSON.stringify(all.slice(0, 7)); };
    expect(await ciState("1", { gh: small, log: () => {} })).toBe(2);
    expect(calls.length).toBe(1);
    // unfiltered: an id older than the full first list stops there (one list, no 400 and 1000)
    calls.length = 0; out.length = 0;
    expect(await ciState("1", { gh: big, log: (l) => out.push(l) })).toBe(2);
    expect(calls.map((a) => a[a.indexOf("--limit") + 1])).toEqual(["100"]);
    expect(out).toEqual(["1 unknown (older than the newest 100 runs; pass --branch or --workflow)"]);
  });
});
