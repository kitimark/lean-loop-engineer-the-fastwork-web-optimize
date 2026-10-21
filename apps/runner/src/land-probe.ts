// A land of the current commit through the real overflow path, without the merge queue (task land-lane-circleci). It is the live proof
// of the overflow: the same plan, adapters and group wait a land uses, started by hand on a probe branch. Run from the repo root:
//   FW_LAND_FORCE_FULL=1 node apps/runner/src/land-probe.ts [--task probe] [--base <rev>]
// With FW_LAND_FORCE_FULL=1 GitHub counts as full (a test flag), so every leg goes to CircleCI and its verdict is what lands (or refuses).
// Without it the plan is whatever the real slot count says. The probe pushes `ci/land-<task>-<sha7>` (plain `git push origin <branch>`,
// never main), waits at 120 s or slower, and prints the verdict, the branch and the pipeline and run ids. It runs no local tier.
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { realEnv } from "@fw/gh-budget";
import { CiStatusPoller } from "../../console-api/src/ops/ci-status.ts";
import { awaitGroups, circleciAdapter, githubAdapter, makePusher, remoteDigest, spawnWait, type Adapter, type StartCtx } from "./land-remote.ts";
import { forceFullFromEnv, ghStatusOnce, planOverflow, readSlots, realCircle } from "./land-overflow.ts";
import { chargedGh, fwcoreCall } from "./run.ts";

const root = resolve(execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim());
const git = (args: string[]) => execFileSync("git", args, { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
const argv = process.argv.slice(2);
const task = argv[argv.indexOf("--task") + 1] ?? "probe";
const log = (l: string) => process.stderr.write(`${l}\n`);

const mergeSha = git(["rev-parse", "HEAD"]);
// the revision the checks are selected against: the first parent of HEAD (as a land does), or `--base <rev>` (e.g. main, to select what a land of this whole branch would)
const baseArg = argv.indexOf("--base");
const base = baseArg >= 0 ? git(["rev-parse", argv[baseArg + 1] ?? ""]) : git(["rev-parse", `${mergeSha}^1`]);
const call = fwcoreCall(root);
// The digest a leg of the lane prints: the `LANE digest=` line of `fw checks` for the same base (land.yml reads the same line).
const listing = execFileSync("pnpm", ["-s", "fw", "checks", "--affected", "--base", base, "--tier", "remote", "--list"], { cwd: root, encoding: "utf8" });
const digest = /^LANE digest=(\S+)$/m.exec(listing)?.[1];
if (!digest) throw new Error("no LANE digest line in the checks listing");
const ids = listing.split("\n").flatMap((l) => (/^remote (\S+)$/.exec(l) ? [/^remote (\S+)$/.exec(l)![1]!] : []));
if (remoteDigest(call, ids) !== digest) throw new Error("the digest of the listed ids is not the printed digest");
const want = { sha: mergeSha, laneId: "land", laneDigest: digest };

const legs = readFileSync(join(root, "lean", "land-legs.txt"), "utf8").split(/\s+/).filter(Boolean);
const env = realEnv(root);
const gh = chargedGh(env);
const push = makePusher({ git });
const cc = await realCircle(root, join(root, ".fw-console", "circleci"), log);
const poller = new CiStatusPoller();
const plan = await planOverflow({
  call, legs, now: Date.now, forceFull: forceFullFromEnv(),
  slots: () => readSlots(gh, Date.now, join(env.dir, "overflow-slots.json")), ghStatus: () => ghStatusOnce(),
  ccStatus: async () => { const v = await poller.view(); return { arm: v.arm.verdict, readAt: v.readAt }; },
  keys: cc.keys, budget: cc.budget,
});
if (!plan) throw new Error("no plan");
log(`overflow ${plan.reason}: GitHub ${plan.gh.join(",") || "-"}, CircleCI ${plan.cc.join(",") || "-"} (${plan.note ?? ""})`);

// Say where each provider started, so the ids are on record.
const seen = (a: Adapter): Adapter => ({ ...a, async start(c: StartCtx) { const h = await a.start(c); log(`started ${a.provider}: branch ${h.branch} marker ${h.marker.slice(0, 7)}${h.pipelineId ? ` pipeline ${h.pipelineId}` : ""}`); return h; } });
const adapters: Partial<Record<"github" | "circleci", Adapter>> = {
  github: seen(githubAdapter({ call, git, wait: spawnWait(root), gh }, push)),
  circleci: seen(circleciAdapter(cc.deps(call, push))),
};
mkdirSync(join(root, ".fw-console"), { recursive: true });
const out = await awaitGroups({
  call, adapters, ctx: { task, mergeSha, want }, split: { all: legs, gh: plan.gh, cc: plan.cc },
  local: Promise.resolve(true), log, span: () => {}, sliceS: 600, deadlineS: 3600,
});
for (const r of out.runs) log(`run ${r.provider}: ${r.state} sha=${r.sha.slice(0, 7)} digest=${r.laneDigest.slice(0, 12)}`);
log(`VERDICT ${out.verdict.kind}${"reason" in out.verdict ? ` ${(out.verdict as { reason: string }).reason}` : ""}`);
process.exit(out.verdict.kind === "accept" ? 0 : 1);
