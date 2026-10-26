import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { WAIT_UNCOVERED, githubAdapter, remoteDigest, type GhRunView, type GithubDeps, type Want } from "../src/land-remote.ts";
import { fwcoreCall } from "../src/run.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const call = fwcoreCall(root);
const SHA = "a".repeat(40);
const MARKER = "b".repeat(40);
const DIGEST = remoteDigest(call, ["apps/runner"]);
const want: Want = { sha: SHA, laneId: "land", laneDigest: DIGEST };
const OUT6 = "wait: the poller's list does not cover run 777 (the poller dropped its watch as uncovered 2 times within 1200 s); read it once with `gh run view 777`";

const leg = (conclusion: string) => ({ name: "land (check-sh)", status: conclusion === "" ? "in_progress" : "completed", conclusion,
  steps: [{ name: `lane: sha=${SHA} digest=${DIGEST}`, conclusion: "success" }] });
const view = (status: string, conclusion: string, legConclusion: string): GhRunView => ({
  workflowName: "land", headSha: MARKER, status, conclusion: conclusion === "" ? null : conclusion,
  jobs: [{ name: "guard", status: "completed", conclusion: "success", steps: [] }, leg(legConclusion)],
});

function setup(read: GhRunView | Error, cached: GhRunView | null) {
  const asked: string[][] = [];
  let cacheUsed = 0;
  const d: GithubDeps = {
    git: () => "", call,
    wait: async () => ({ code: WAIT_UNCOVERED, out: OUT6 }),
    gh: async (args) => { asked.push(args); if (read instanceof Error) throw read; return JSON.stringify(read); },
    cache: () => { cacheUsed++; return cached; },
  };
  const a = githubAdapter(d, async () => ({ branch: "ci/land-t", marker: MARKER }));
  const handle = { provider: "github" as const, branch: "ci/land-t", marker: MARKER };
  const ctx = { task: "t", mergeSha: SHA, want, checks: ["apps/runner"] };
  return { poll: () => a.poll(handle, ctx, 1), asked: () => asked, cacheUsed: () => cacheUsed };
}

describe("waiter exit 6: the poller's list never covers the run", () => {
  it("the constant is the waiter's exit code", () => {
    expect(WAIT_UNCOVERED).toBe(6);
  });

  it("reads the run record with gh run view and never the poller's cached file", async () => {
    const stale = view("in_progress", "", "");
    const { poll, asked, cacheUsed } = setup(view("completed", "success", "success"), stale);
    const r = await poll();
    expect(cacheUsed()).toBe(0);
    expect(asked()[0]).toEqual(expect.arrayContaining(["run", "view", "777"]));
    expect(r.run.state).toBe("pass");
    expect(r.note).toMatch(/does not cover it \(waiter exit 6\)/);
  });

  it("a run still going in its record stays running", async () => {
    const { poll } = setup(view("in_progress", "", ""), null);
    expect((await poll()).run.state).toBe("running");
  });

  it("an unreadable record counts as unavailable and the note keeps both reasons", async () => {
    const { poll } = setup(new Error("gh: HTTP 403"), null);
    const r = await poll();
    expect(r.run.state).toBe("unavailable");
    expect(r.note).toMatch(/exit 6\); .*record not read \(gh: HTTP 403\)/);
  });
});
