import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { dispatchArgs, fwcoreCall, keyDigest, newestRun, parseRunArgs, planRun, runMain, sha256, type FwCall, type Gh } from "../src/run.ts";
import { UsageError } from "../src/lib.ts";

const SHA = "0123456789abcdef0123456789abcdef01234567";

describe("parseRunArgs", () => {
  it("reads flags, commas and repeats", () => {
    const a = parseRunArgs(["--fw", "a:x,b:y", "--fw", "c:z", "--preset", "p", "--engines", "chromium,webkit", "--dry", "--image", "chromium=runner:x"]);
    expect(a).toMatchObject({ preset: "p", fw: ["a:x", "b:y", "c:z"], engines: ["chromium", "webkit"], dry: true, images: { chromium: "runner:x" } });
  });
  it("needs engines, values and known flags", () => {
    expect(() => parseRunArgs([])).toThrow(UsageError);
    expect(() => parseRunArgs(["--engines"])).toThrow(UsageError);
    expect(() => parseRunArgs(["--engines", "chromium", "--nope"])).toThrow(UsageError);
    expect(() => parseRunArgs(["--engines", "chromium", "--runs", "x"])).toThrow(UsageError);
  });
});

describe("newestRun", () => {
  it("waits until the newest run differs from the one before dispatch", () => {
    const seq = ["7", "7", "8"];
    const gh: Gh = () => JSON.stringify([{ databaseId: Number(seq.shift() ?? "8") }]);
    expect(newestRun(gh, "w.yml", "main", "7", 0)).toBe("8");
  });
  it("gives up when nothing new appears", () => {
    const gh: Gh = () => JSON.stringify([]);
    expect(() => newestRun(gh, "w.yml", "main", null, 0)).toThrow(/no new run/);
  });
});

describe("dispatchArgs", () => {
  it("passes inputs as -f k=v", () => {
    const job = { engine: "chromium", workflow: "chromium-counts.yml", inputs: { profile: "swipe-v1", runs: "3" }, key: [], image: "runner:x", blocked: null } as never;
    expect(dispatchArgs(job, "ci/x")).toEqual(["workflow", "run", "chromium-counts.yml", "--ref", "ci/x", "-f", "profile=swipe-v1", "-f", "runs=3"]);
  });
});

const hasCore = (() => { try { fwcoreCall(process.cwd()); return true; } catch { return false; } })();

describe.skipIf(!hasCore)("planRun and runMain against fwcore", () => {
  const call: FwCall = hasCore ? fwcoreCall(process.cwd()) : () => ({});
  const mk = () => mkdtempSync(join(tmpdir(), "fw-run-"));

  it("--dry plans two jobs and runs no gh", () => {
    const logs: string[] = [];
    const gh: Gh = () => { throw new Error("gh must not run in --dry"); };
    const code = runMain(parseRunArgs(["--engines", "chromium,webkit", "--dry"]), { call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: (l) => logs.push(l) });
    expect(code).toBe(0);
    expect(logs.join("\n")).toMatch(/chromium/);
    expect(logs.join("\n")).toMatch(/webkit/);
  });

  it("a request the workflow cannot express is refused before any dispatch", () => {
    const logs: string[] = [];
    const gh: Gh = () => { throw new Error("no gh"); };
    const code = runMain(parseRunArgs(["--engines", "chromium", "--fw", "hero.countdown:strip"]), { call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: (l) => logs.push(l) });
    expect(code).toBe(2);
    expect(logs.join("\n")).toMatch(/refused/);
  });

  it("dispatches, downloads and files artifacts; a second run is a cache hit", () => {
    const store = mk(), tmp = mk();
    const calls: string[][] = [];
    let listed = 0;
    const gh: Gh = (a) => {
      calls.push(a);
      if (a[0] === "run" && a[1] === "list") return JSON.stringify(listed++ === 0 ? [] : [{ databaseId: 55 }]);
      if (a[0] === "run" && a[1] === "view") return JSON.stringify({ headSha: SHA });
      if (a[0] === "run" && a[1] === "download") {
        const d = a[a.indexOf("-D") + 1]!;
        mkdirSync(join(d, "trace"), { recursive: true });
        writeFileSync(join(d, "counts-run1.json"), "{}");
        writeFileSync(join(d, "trace", "run1.json"), "[1]");
      }
      return "";
    };
    const args = parseRunArgs(["--engines", "chromium", "--ref", "ci/t"]);
    const logs: string[] = [];
    expect(runMain(args, { call, gh, store, sha: SHA, branch: "main", tmp, log: (l) => logs.push(l), pollMs: 0 })).toBe(0);
    expect(calls.some((c) => c[0] === "workflow")).toBe(true);
    const planned = planRun(call, args, SHA, store);
    const key = planned.reply.jobs[0]!.key as [string, string][];
    expect(existsSync(join(store, "runs", keyDigest(key), "manifest.json"))).toBe(true);
    const m = JSON.parse(readFileSync(join(store, "runs", keyDigest(key), "manifest.json"), "utf8"));
    expect(m.entries.map((e: { name: string }) => e.name)).toEqual(["counts-run1.json", "trace/run1.json"]);
    expect(existsSync(join(store, "objects", sha256("{}").slice(0, 2), sha256("{}").slice(2)))).toBe(true);
    expect(planned.reply.jobs[0]!.cache).toBe("hit");

    const before = calls.length;
    const logs2: string[] = [];
    expect(runMain(args, { call, gh, store, sha: SHA, branch: "main", tmp, log: (l) => logs2.push(l), pollMs: 0 })).toBe(0);
    expect(calls.length).toBe(before);
    expect(logs2.join("\n")).toMatch(/cached/);
  });

  it("a run that measured another commit is refused", () => {
    const gh: Gh = (a) => (a[1] === "list" ? JSON.stringify([{ databaseId: 9 }]) : a[1] === "view" ? JSON.stringify({ headSha: "f".repeat(40) }) : "");
    expect(() => runMain(parseRunArgs(["--engines", "chromium", "--from-run", "chromium=9"]), { call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: () => {} })).toThrow(/measured/);
  });
});
