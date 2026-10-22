import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { Target } from "@fw/gh-budget";
import { declaresNonce, dispatchArgs, fwcoreCall, keyDigest, parseRunArgs, planRun, runMain, sha256, type FwCall, type Gh } from "../src/run.ts";
import { UsageError } from "../src/lib.ts";
import { titleOf } from "../src/run-pick.ts";

const SHA = "0123456789abcdef0123456789abcdef01234567";
const waits: Target[] = [];
const base = () => ({ nonce: () => "n0nce1234", now: () => 1_800_000_000, wait: async (t: Target) => { waits.push(t); return { code: 0 as const, lines: ["run 55 chromium-counts success"] }; } });

describe("parseRunArgs", () => {
  it("reads flags, commas and repeats", () => {
    const a = parseRunArgs(["--fw", "a:x,b:y", "--fw", "c:z", "--preset", "p", "--target", "rewrite", "--engines", "chromium,webkit", "--dry", "--image", "chromium=runner:x"]);
    expect(a).toMatchObject({ target: "rewrite", preset: "p", fw: ["a:x", "b:y", "c:z"], engines: ["chromium", "webkit"], dry: true, images: { chromium: "runner:x" } });
  });
  it("needs engines, a target, values and known flags", () => {
    expect(() => parseRunArgs([])).toThrow(UsageError);
    expect(() => parseRunArgs(["--engines", "chromium"])).toThrow(/--target is required/);
    expect(() => parseRunArgs(["--engines", "chromium", "--target"])).toThrow(UsageError);
    expect(() => parseRunArgs(["--engines"])).toThrow(UsageError);
    expect(() => parseRunArgs(["--engines", "chromium", "--nope"])).toThrow(UsageError);
    expect(() => parseRunArgs(["--engines", "chromium", "--runs", "x"])).toThrow(UsageError);
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

  it("--dry plans two jobs and runs no gh", async () => {
    const logs: string[] = [];
    const gh: Gh = async () => { throw new Error("gh must not run in --dry"); };
    const code = await runMain(parseRunArgs(["--engines", "chromium,webkit", "--target", "original", "--dry"]), { ...base(), call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: (l) => logs.push(l) });
    expect(code).toBe(0);
    expect(logs.join("\n")).toMatch(/chromium/);
    expect(logs.join("\n")).toMatch(/webkit/);
  });

  it("a request the workflow cannot express is refused before any dispatch: webkit-sim has no profile input", async () => {
    const logs: string[] = [];
    const gh: Gh = async () => { throw new Error("no gh"); };
    const code = await runMain(parseRunArgs(["--engines", "webkit", "--target", "original", "--profile", "swipe-wheel-v1"]), { ...base(), call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: (l) => logs.push(l) });
    expect(code).toBe(2);
    expect(logs.join("\n")).toMatch(/refused: webkit \(profile\)/);
  });

  it("webkit-sim takes target, preset and fw: the rewrite with flags is dispatched with them", async () => {
    const logs: string[] = [];
    const calls: string[][] = [];
    const gh: Gh = async (a) => { calls.push(a); if (a[0] === "run" && a[1] === "list") return "[]"; throw new Error("stop after the dispatch"); };
    await expect(runMain(parseRunArgs(["--engines", "webkit", "--target", "rewrite", "--preset", "strip-demo", "--fw", "hero.countdown:strip", "--ref", "ci/wk"]), { ...base(), call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: (l) => logs.push(l) })).rejects.toThrow(/stop after/);
    expect(calls.find((c) => c[0] === "workflow")).toEqual(["workflow", "run", "webkit-sim.yml", "--ref", "ci/wk", "-f", "fw=hero.countdown:strip", "-f", "preset=strip-demo", "-f", "target=rewrite", "-f", "nonce=n0nce1234"]);
  });

  it("--ref measures a base ref at its own commit: the run is awaited and checked at the ref's sha, not the checkout's", async () => {
    const BASE = "fedcba9876543210fedcba9876543210fedcba98";
    const calls: string[][] = [];
    const gh: Gh = async (a) => { calls.push(a); if (a[0] === "run" && a[1] === "list") return "[]"; if (a[0] === "run" && a[1] === "view") return JSON.stringify({ headSha: BASE }); if (a[0] === "run" && a[1] === "download") { mkdirSync(a[4]!, { recursive: true }); return ""; } return ""; };
    waits.length = 0;
    await runMain(parseRunArgs(["--engines", "chromium", "--target", "original", "--ref", "ci/base"]), { ...base(), call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: () => {}, refSha: (r) => (r === "ci/base" ? BASE : undefined) }).catch(() => 0);
    expect(waits.at(-1)).toMatchObject({ kind: "branch", branch: "ci/base", sha: BASE });
    expect(calls.find((c) => c[0] === "workflow")?.slice(0, 5)).toEqual(["workflow", "run", "chromium-counts.yml", "--ref", "ci/base"]);
    await expect(runMain(parseRunArgs(["--engines", "chromium", "--target", "original", "--ref", "ci/none", "--dry"]), { ...base(), call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: () => {}, refSha: () => undefined })).rejects.toThrow(/cannot resolve --ref/);
  });

  it("an original run with flags is a problem (fwcore), not a dispatch", async () => {
    const logs: string[] = [];
    const gh: Gh = async () => { throw new Error("no gh"); };
    const code = await runMain(parseRunArgs(["--engines", "chromium", "--target", "original", "--fw", "hero.countdown:strip"]), { ...base(), call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: (l) => logs.push(l) });
    expect(code).toBe(2);
    expect(logs.join("\n")).toMatch(/problem: target: original takes no preset or flags/);
  });

  it("the target is sent to chromium-counts and is part of the key: original and rewrite never share a run key", async () => {
    const store = mk();
    const o = planRun(call, parseRunArgs(["--engines", "chromium", "--target", "original"]), SHA, store).reply.jobs[0]!;
    const r = planRun(call, parseRunArgs(["--engines", "chromium", "--target", "rewrite"]), SHA, store).reply.jobs[0]!;
    expect(o.inputs.target).toBe("original");
    expect(r.inputs.target).toBe("rewrite");
    expect(o.key).toContainEqual(["target", "original"]);
    expect(keyDigest(o.key as [string, string][])).not.toBe(keyDigest(r.key as [string, string][]));
    expect(dispatchArgs(r, "ci/x")).toContain("target=rewrite");
  });

  it("chromium-counts expresses preset and fw: a dry run is not refused", async () => {
    const logs: string[] = [];
    const gh: Gh = async () => { throw new Error("no gh"); };
    const code = await runMain(parseRunArgs(["--engines", "chromium", "--target", "rewrite", "--preset", "original", "--fw", "nav.hitTest:hit-skip,hero.countdown:strip", "--dry"]), { ...base(), call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: (l) => logs.push(l) });
    expect(logs.join("\n")).not.toMatch(/refused|BLOCKED/);
    expect(code).toBe(0);
  });

  it("dispatches, downloads and files artifacts; a second run is a cache hit", async () => {
    const store = mk(), tmp = mk();
    const calls: string[][] = [];
    let listed = 0;
    const gh: Gh = async (a) => {
      calls.push(a);
      if (a[0] === "run" && a[1] === "list") return JSON.stringify([]);
      if (a[0] === "run" && a[1] === "view") return JSON.stringify({ headSha: SHA });
      if (a[0] === "run" && a[1] === "download") {
        const d = a[a.indexOf("-D") + 1]!;
        mkdirSync(join(d, "trace"), { recursive: true });
        writeFileSync(join(d, "counts-run1.json"), "{}");
        writeFileSync(join(d, "trace", "run1.json"), "[1]");
      }
      return "";
    };
    const args = parseRunArgs(["--engines", "chromium", "--target", "original", "--ref", "ci/t"]);
    const logs: string[] = [];
    expect(await runMain(args, { ...base(), call, gh, store, sha: SHA, branch: "main", tmp, log: (l) => logs.push(l) })).toBe(0);
    expect(calls.some((c) => c[0] === "workflow")).toBe(true);
    expect(waits.at(-1)).toMatchObject({ kind: "branch", branch: "ci/t", sha: SHA });
    expect(calls.some((c) => c[1] === "watch")).toBe(false);
    expect(calls.map((c) => c.slice(0, 2).join(" "))).toEqual(["workflow run", "run view", "run download"]);
    expect(readdirSync(tmp)).toEqual([]);
    expect(waits.at(-1)).toMatchObject({ want: { kind: "dispatch", workflow: "chromium-counts", nonce: "n0nce1234" } });
    const planned = planRun(call, args, SHA, store);
    const key = planned.reply.jobs[0]!.key as [string, string][];
    expect(existsSync(join(store, "runs", keyDigest(key), "manifest.json"))).toBe(true);
    const m = JSON.parse(readFileSync(join(store, "runs", keyDigest(key), "manifest.json"), "utf8"));
    expect(m.entries.map((e: { name: string }) => e.name)).toEqual(["counts-run1.json", "trace/run1.json"]);
    expect(m.target).toBe("original");
    expect(calls.find((c) => c[0] === "workflow")).toContain("target=original");
    expect(planRun(call, { ...args, target: "rewrite" }, SHA, store).reply.jobs[0]!.cache).toBe("miss");
    expect(existsSync(join(store, "objects", sha256("{}").slice(0, 2), sha256("{}").slice(2)))).toBe(true);
    expect(planned.reply.jobs[0]!.cache).toBe("hit");

    const before = calls.length;
    const logs2: string[] = [];
    expect(await runMain(args, { ...base(), call, gh, store, sha: SHA, branch: "main", tmp, log: (l) => logs2.push(l) })).toBe(0);
    expect(calls.length).toBe(before);
    expect(logs2.join("\n")).toMatch(/cached/);
  });

  it("a run that measured another commit is refused", async () => {
    const gh: Gh = async (a) => (a[1] === "list" ? JSON.stringify([{ databaseId: 9 }]) : a[1] === "view" ? JSON.stringify({ headSha: "f".repeat(40) }) : "");
    await expect(runMain(parseRunArgs(["--engines", "chromium", "--target", "original", "--from-run", "chromium=9"]), { ...base(), call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: () => {} })).rejects.toThrow(/measured/);
  });
});

describe("breakpoint-gate lane", () => {
  const hasCore2 = hasCore;
  it("parses --gate and refuses count-lane flags", () => {
    expect(parseRunArgs(["--gate", "--engines", "chromium", "--fw", "morph.tween:waapi"])).toMatchObject({ gate: true, engines: ["chromium"], fw: ["morph.tween:waapi"] });
    expect(() => parseRunArgs(["--gate", "--target", "rewrite"])).toThrow(/no --target/);
    expect(() => parseRunArgs(["--gate", "--engines", "chromium,webkit"])).toThrow(/one --engines value/);
  });
  describe.skipIf(!hasCore2)("against fwcore", () => {
    const call: FwCall = hasCore2 ? fwcoreCall(process.cwd()) : () => ({});
    const mk = () => mkdtempSync(join(tmpdir(), "fw-run-"));
    it("--dry prints the three inputs; no gh", async () => {
      const logs: string[] = [];
      const gh: Gh = async () => { throw new Error("no gh"); };
      expect(await runMain(parseRunArgs(["--gate", "--fw", "morph.tween:waapi", "--dry"]), { ...base(), call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: (l) => logs.push(l) })).toBe(0);
      expect(logs.join("\n")).toMatch(/breakpoint-gate\.yml\s+inputs engines=both fw=morph\.tween:waapi preset=/);
    });
    it("preset with fw is a problem, nothing dispatched", async () => {
      const logs: string[] = [];
      const gh: Gh = async () => { throw new Error("no gh"); };
      expect(await runMain(parseRunArgs(["--gate", "--preset", "v2-proved", "--fw", "a.b:c"]), { ...base(), call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: (l) => logs.push(l) })).toBe(2);
      expect(logs.join("\n")).toMatch(/problem: preset: exclusive with fw/);
    });
    it("dispatches with -f engines/preset/fw on the ref and reports the run id", async () => {
      const logs: string[] = [];
      const calls: string[][] = [];
      const gh: Gh = async (a) => { calls.push(a); if (a[0] === "run" && a[1] === "list") return "[]"; if (a[0] === "run" && a[1] === "view") return JSON.stringify({ headSha: SHA }); return ""; };
      expect(await runMain(parseRunArgs(["--gate", "--engines", "chromium", "--preset", "v2-proved", "--ref", "ci/g"]), { ...base(), call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: (l) => logs.push(l) })).toBe(0);
      expect(calls.find((c) => c[0] === "workflow")).toEqual(["workflow", "run", "breakpoint-gate.yml", "--ref", "ci/g", "-f", "engines=chromium", "-f", "fw=", "-f", "preset=v2-proved", "-f", "nonce=n0nce1234"]);
      expect(waits.at(-1)).toMatchObject({ workflow: "breakpoint-gate", want: { kind: "dispatch", workflow: "breakpoint-gate", nonce: "n0nce1234" } });
      expect(logs.join("\n")).toMatch(/gate: run 55 succeeded/);
    });
  });
});

describe("trajectory-probe lane", () => {
  it("parses --trajectory and --widths, refuses count-lane flags and a lone --widths", () => {
    expect(parseRunArgs(["--trajectory", "--engines", "chromium", "--widths", "390,641"])).toMatchObject({ trajectory: true, engines: ["chromium"], widths: "390,641" });
    expect(() => parseRunArgs(["--trajectory", "--target", "rewrite"])).toThrow(/no --target/);
    expect(() => parseRunArgs(["--trajectory", "--gate"])).toThrow(/separate lanes/);
    expect(() => parseRunArgs(["--gate", "--widths", "390"])).toThrow(/belongs to --trajectory/);
  });
  describe.skipIf(!hasCore)("against fwcore", () => {
    const call: FwCall = hasCore ? fwcoreCall(process.cwd()) : () => ({});
    const mk = () => mkdtempSync(join(tmpdir(), "fw-run-"));
    it("--dry prints the four inputs; no gh", async () => {
      const logs: string[] = [];
      const gh: Gh = async () => { throw new Error("no gh"); };
      expect(await runMain(parseRunArgs(["--trajectory", "--fw", "morph.tween:waapi", "--widths", "390", "--diagnostic", "--dry"]), { ...base(), call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: (l) => logs.push(l) })).toBe(0);
      expect(logs.join("\n")).toMatch(/trajectory-probe\.yml\s+inputs engines=both fw=morph\.tween:waapi preset= widths=390/);
    });
    it("a width outside the allowlist is a problem, nothing dispatched", async () => {
      const logs: string[] = [];
      const gh: Gh = async () => { throw new Error("no gh"); };
      expect(await runMain(parseRunArgs(["--trajectory", "--widths", "800"]), { ...base(), call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: (l) => logs.push(l) })).toBe(2);
      expect(logs.join("\n")).toMatch(/refused: --widths 800 must be a comma list/);
    });
    it("dispatches with -f on the ref and reports the run id", async () => {
      const logs: string[] = [];
      const calls: string[][] = [];
      const gh: Gh = async (a) => { calls.push(a); if (a[0] === "run" && a[1] === "list") return JSON.stringify([{ databaseId: 55, displayTitle: titleOf("abcd1234"), event: "workflow_dispatch" }]); if (a[0] === "run" && a[1] === "view") return JSON.stringify({ headSha: SHA }); return ""; };
      expect(await runMain(parseRunArgs(["--trajectory", "--engines", "chromium", "--preset", "v2-proved", "--ref", "ci/t"]), { ...base(), call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: (l) => logs.push(l), nonce: () => "abcd1234", sleep: async () => {} })).toBe(0);
      expect(calls.find((c) => c[0] === "workflow")?.slice(0, 5)).toEqual(["workflow", "run", "trajectory-probe.yml", "--ref", "ci/t"]);
      expect(logs.join("\n")).toMatch(/trajectory: run 55 succeeded/);
    });
  });
});

describe("fw run --trajectory finds its run by nonce", () => {
  const call: FwCall = () => ({ fw: [], job: { blocked: null, inputs: { engines: "chromium", fw: "", preset: "", widths: "390" }, workflow: "trajectory-probe.yml" }, problems: [] });
  const mk = () => mkdtempSync(join(tmpdir(), "fw-run-"));
  const args = () => parseRunArgs(["--trajectory", "--engines", "chromium", "--widths", "390", "--diagnostic", "--ref", "ci/t"]);
  const row = (id: number, nonce: string, event = "workflow_dispatch") => ({ databaseId: id, displayTitle: titleOf(nonce), event });
  const deps = (gh: Gh, logs: string[], nonce: string, waited: Target[] = []) => ({ now: () => 1_800_000_000, wait: async (t: Target) => { waited.push(t); return { code: 0 as const, lines: ["run 7 trajectory-probe success"] }; },
    call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: (l: string) => logs.push(l), nonce: () => nonce, sleep: async () => {} });

  it("sends the nonce as an input and waits for the run whose title echoes it, not the newest one", async () => {
    const calls: string[][] = [];
    const waited: Target[] = [];
    const logs: string[] = [];
    const gh: Gh = async (a) => { calls.push(a); if (a[1] === "list") return JSON.stringify([{ databaseId: 900, displayTitle: "ci: x", event: "push" }, row(899, "zzzz9999"), row(898, "abcd1234")]); if (a[1] === "view") return JSON.stringify({ headSha: SHA }); return ""; };
    expect(await runMain(args(), deps(gh, logs, "abcd1234", waited))).toBe(0);
    expect(calls.find((c) => c[0] === "workflow")).toEqual(["workflow", "run", "trajectory-probe.yml", "--ref", "ci/t", "-f", "engines=chromium", "-f", "fw=", "-f", "preset=", "-f", "widths=390", "-f", "diagnostic=true", "-f", "nonce=abcd1234"]);
    expect(calls.find((c) => c[1] === "list")).toContain("workflow_dispatch");
    expect(waited).toEqual([{ kind: "run", runId: 898 }]);
    expect(logs.join("\n")).toMatch(/the run with nonce abcd1234 is 898/);
  });
  it("looks again every 120 s while the run is absent, then gives up", async () => {
    const naps: number[] = [];
    let lists = 0;
    const gh: Gh = async (a) => { if (a[1] === "list") { lists++; return JSON.stringify([row(1, "other999")]); } return ""; };
    await expect(runMain(args(), { ...deps(gh, [], "abcd1234"), sleep: async (s) => { naps.push(s); } })).rejects.toThrow(/no run titled/);
    expect(lists).toBe(5);
    expect(naps.every((s) => s >= 120)).toBe(true);
  });
  it("two runs with the nonce are refused, not guessed", async () => {
    const gh: Gh = async (a) => (a[1] === "list" ? JSON.stringify([row(3, "abcd1234"), row(2, "abcd1234")]) : "");
    await expect(runMain(args(), deps(gh, [], "abcd1234"))).rejects.toThrow(/matches several runs \(3, 2\)/);
  });
});

describe("fw run on a ref whose workflow file has no nonce input", () => {
  const OLD = "name: trajectory-probe\non:\n  workflow_dispatch:\n    inputs:\n      engines:\n        type: string\n      widths:\n        type: string\n";
  const NEW = OLD + "      nonce:\n        type: string\n";
  it("declaresNonce reads the workflow_dispatch inputs only", () => {
    expect(declaresNonce(NEW)).toBe(true);
    expect(declaresNonce(OLD)).toBe(false);
    expect(declaresNonce("on:\n  push:\n    paths: [a]\n")).toBe(false);
    expect(declaresNonce(OLD + "env:\n  nonce: x\njobs:\n  a:\n    steps:\n      - with:\n          nonce: y\n")).toBe(false);
    expect(declaresNonce("on:\n  workflow_dispatch:\n    inputs:\n      # nonce:\n      other:\n        type: string\n")).toBe(false);
  });
  const call: FwCall = () => ({ fw: [], job: { blocked: null, inputs: { engines: "chromium", fw: "", preset: "", widths: "390" }, workflow: "trajectory-probe.yml" }, problems: [] });
  const mk = () => mkdtempSync(join(tmpdir(), "fw-run-"));
  const run = async (text: string | undefined) => {
    const calls: string[][] = [];
    const waited: Target[] = [];
    const logs: string[] = [];
    const gh: Gh = async (a) => { calls.push(a); if (a[1] === "list") return a.includes("--event") ? JSON.stringify([{ databaseId: 7, displayTitle: titleOf("abcd1234"), event: "workflow_dispatch" }]) : "[]"; if (a[1] === "view") return JSON.stringify({ headSha: SHA }); return ""; };
    const code = await runMain(parseRunArgs(["--trajectory", "--engines", "chromium", "--widths", "390", "--diagnostic", "--ref", "ci/old"]), { now: () => 1_800_000_000,
      wait: async (t: Target) => { waited.push(t); return { code: 0 as const, lines: ["run 7 trajectory-probe success"] }; },
      call, gh, store: mk(), sha: SHA, branch: "main", tmp: mk(), log: (l) => logs.push(l), nonce: () => "abcd1234", sleep: async () => {}, refWorkflowText: () => text });
    return { code, calls, waited, logs: logs.join("\n") };
  };
  it("an old ref: no nonce input is sent, the run is the old pick, and the log says so", async () => {
    const r = await run(OLD);
    expect(r.code).toBe(0);
    expect(r.calls.find((c) => c[0] === "workflow")).toEqual(["workflow", "run", "trajectory-probe.yml", "--ref", "ci/old", "-f", "engines=chromium", "-f", "fw=", "-f", "preset=", "-f", "widths=390"]);
    expect(r.waited.at(-1)).not.toHaveProperty("want");
    expect(r.logs).toMatch(/has no nonce input in trajectory-probe\.yml.*old pick, not identity/);
    expect(r.logs).toMatch(/ci\/old has no diagnostic input in trajectory-probe\.yml/);
  });
  it("a ref whose file declares the diagnostic input is sent it with the nonce", async () => {
    const r = await run(NEW + "      diagnostic:\n        type: boolean\n");
    expect(r.code).toBe(0);
    expect(r.calls.find((c) => c[0] === "workflow")).toEqual(["workflow", "run", "trajectory-probe.yml", "--ref", "ci/old", "-f", "engines=chromium", "-f", "fw=", "-f", "preset=", "-f", "widths=390", "-f", "diagnostic=true", "-f", "nonce=abcd1234"]);
    expect(r.logs).not.toMatch(/no diagnostic input/);
  });
  it("a file that cannot be read at the ref is treated as having no nonce input", async () => {
    const r = await run(undefined);
    expect(r.calls.find((c) => c[0] === "workflow")).not.toContain("nonce=abcd1234");
  });
  it("a ref with the input keeps the identity path", async () => {
    const r = await run(NEW);
    expect(r.calls.find((c) => c[0] === "workflow")).toContain("nonce=abcd1234");
  });
});

describe("goldens: dispatch args per lane", () => {
  const root = join(process.cwd(), "..", "..");
  const gold = (stem: string) => readFileSync(join(root, "packages", "contracts", "golden", "store", `${stem}.jsonl`), "utf8").trim().split("\n").map((l) => JSON.parse(l) as { name: string; response: { jobs?: { workflow: string; inputs: Record<string, string>; blocked: string | null }[]; job?: { workflow: string; inputs: Record<string, string>; blocked: string | null } | null } });
  const declared = (wf: string): string[] => {
    const out: string[] = []; let st = 0;
    for (const l of readFileSync(join(root, ".github", "workflows", wf), "utf8").split("\n")) {
      const t = l.trimStart(); if (!t || t.startsWith("#")) continue;
      const n = l.length - t.length;
      if (st === 0) { if (n === 2 && t === "workflow_dispatch:") st = 1; }
      else if (st === 1) { if (n === 4 && t === "inputs:") st = 2; else if (n <= 2) st = 3; }
      else if (st === 2) { if (n <= 4) st = 3; else if (n === 6 && t.endsWith(":")) out.push(t.slice(0, -1)); }
    }
    return out;
  };
  const jobs = [...gold("plan").flatMap((c) => c.response.jobs ?? []), ...gold("gate").flatMap((c) => (c.response.job ? [c.response.job] : [])), ...gold("trajectory").flatMap((c) => (c.response.job ? [c.response.job] : []))];
  it("all four workflows appear in the goldens", () => {
    expect(new Set(jobs.map((j) => j.workflow))).toEqual(new Set(["chromium-counts.yml", "webkit-sim.yml", "breakpoint-gate.yml", "trajectory-probe.yml"]));
  });
  it("every sent input is declared by the workflow file", () => {
    for (const j of jobs) for (const k of Object.keys(j.inputs)) expect(declared(j.workflow), `${j.workflow} ${k}`).toContain(k);
  });
  it("blocked only where the lane lacks the input (webkit: profile; chromium and gate: never)", () => {
    for (const j of jobs) if (j.blocked) expect([j.workflow, j.blocked]).toEqual(["webkit-sim.yml", "profile"]);
    expect(jobs.some((j) => j.blocked)).toBe(true);
  });
  it("replays the args of one case per lane", () => {
    const by = (wf: string) => jobs.find((j) => j.workflow === wf && j.inputs.target !== "rewrite" && !j.blocked)!;
    expect(dispatchArgs(by("webkit-sim.yml"), "ci/x")).toEqual(["workflow", "run", "webkit-sim.yml", "--ref", "ci/x", "-f", "fw=", "-f", "preset=original", "-f", "target=original"]);
    expect(dispatchArgs(by("chromium-counts.yml"), "ci/x").slice(0, 5)).toEqual(["workflow", "run", "chromium-counts.yml", "--ref", "ci/x"]);
    expect(dispatchArgs(jobs.find((j) => j.workflow === "breakpoint-gate.yml")!, "ci/x")).toEqual(["workflow", "run", "breakpoint-gate.yml", "--ref", "ci/x", "-f", "engines=both", "-f", "fw=", "-f", "preset="]);
  });
});
