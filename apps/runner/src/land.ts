// `fw land <branch>`: the only way to main. Every decision is made by console-api (Lean); this file runs
// git and the fast checks, sends typed commands, and prints a digest. It never pushes.
import { execFileSync, spawnSync } from "node:child_process";
import { Command } from "@fw/contracts";
import { branchCard } from "../../console-api/src/reconcile/naming.ts";

export type Http = {
  get(path: string): Promise<{ status: number; body: any }>;
  post(path: string, body: unknown): Promise<{ status: number; body: any }>;
};

export const httpFor = (base: string): Http => ({
  get: async (p) => { const r = await fetch(base + p); return { status: r.status, body: await r.json() }; },
  post: async (p, b) => {
    const r = await fetch(base + p, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(b) });
    return { status: r.status, body: await r.json() };
  },
});

export type LandOptions = {
  http: Http;
  /** any directory of the repo (main checkout or a worktree) */
  cwd: string;
  mainRef?: string;
  actor?: "lead" | "user";
  /** fast checks as argv arrays; default: lean/scripts/check.sh and pnpm test */
  checks?: string[][];
  env?: Record<string, string | undefined>;
};
export type LandResult = { ok: boolean; lines: string[] };

const git = (cwd: string, args: string[]) => execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
const tryGit = (cwd: string, args: string[]) => { try { git(cwd, args); return true; } catch { return false; } };

/** Directory where `ref` is checked out, or null. */
export function worktreeOf(cwd: string, ref: string): string | null {
  let dir: string | null = null;
  for (const l of git(cwd, ["worktree", "list", "--porcelain"]).split("\n")) {
    if (l.startsWith("worktree ")) dir = l.slice(9);
    if (l === `branch refs/heads/${ref}`) return dir;
  }
  return null;
}

// ---- STAND-IN (marked for Lean replacement) -------------------------------------------------
// PLAN 8.2 land-time path check. The Lean op `ops.pathCheck` (parallel agent lean-ops) is not here yet, so the
// decision lives in this one function: changed paths vs a deny list (+ optional allow list).
// Replace the body with a call to `fwcore ops.pathCheck`; the signature is the JSON contract to match.
export type PathCheck = { ok: boolean; violations: string[] };
export function pathCheck(changed: string[], opts: { deny?: string[]; allow?: string[] } = {}): PathCheck {
  const deny = opts.deny ?? [".fw-console/", ".git/", ".claude/settings", "lean/.lake/"];
  const allow = opts.allow ?? [];
  const bad = changed.filter((f) => deny.some((d) => f.startsWith(d)) || (allow.length > 0 && !allow.some((a) => f.startsWith(a))));
  return { ok: bad.length === 0, violations: bad };
}
// ---------------------------------------------------------------------------------------------

const DEFAULT_CHECKS = [["sh", "lean/scripts/check.sh"], ["pnpm", "test"]];

export async function land(branch: string, o: LandOptions): Promise<LandResult> {
  const lines: string[] = [];
  const fail = (m: string): LandResult => { lines.push(`REFUSED: ${m}`); return { ok: false, lines }; };
  const main = o.mainRef ?? "main";
  const bc = branchCard(branch);
  if (!bc) return fail(`branch ${branch} is not a card branch (card/<CARD>[/<agent>])`);
  if (!tryGit(o.cwd, ["rev-parse", "--verify", `refs/heads/${branch}`])) return fail(`no such branch ${branch}`);
  const mainDir = worktreeOf(o.cwd, main);
  if (!mainDir) return fail(`${main} is not checked out in any worktree`);
  if (git(mainDir, ["status", "--porcelain", "--untracked-files=no"])) return fail(`${main} checkout has uncommitted changes`);

  // 1. rebase onto main if needed (the new commits become new builds, so earlier evidence goes stale: Lean decides)
  if (!tryGit(o.cwd, ["merge-base", "--is-ancestor", main, branch])) {
    const dir = worktreeOf(o.cwd, branch);
    if (!dir) return fail(`${branch} is behind ${main} and is not checked out anywhere to rebase`);
    if (!tryGit(dir, ["rebase", main])) { tryGit(dir, ["rebase", "--abort"]); return fail(`rebase of ${branch} onto ${main} conflicts`); }
    lines.push(`rebased ${branch} onto ${main}`);
  }
  const sha = git(o.cwd, ["rev-parse", `refs/heads/${branch}`]);

  // 2. ask the console: reconcile git facts first, then read readiness (stage is computed by Lean)
  await o.http.post("/api/reconcile", {});
  const r = await o.http.get(`/api/land/${encodeURIComponent(bc.card)}`);
  if (r.status !== 200) return fail(`console: ${r.body.reason ?? r.status}`);
  const rd = r.body as { stage: string; head: string | null; landed: boolean; ready: boolean; next: { who: string; command: string } };
  if (rd.landed) return fail("card already landed");
  if (!rd.ready) return fail(`card ${bc.card} is at stage ${rd.stage}; next: ${rd.next.who}: ${rd.next.command}`);
  if (rd.head !== sha) return fail(`stale: console head ${rd.head?.slice(0, 7)} is not branch tip ${sha.slice(0, 7)}`);

  // 3. fast checks, in the branch's own checkout when it has one
  const runDir = worktreeOf(o.cwd, branch) ?? mainDir;
  for (const argv of o.checks ?? DEFAULT_CHECKS) {
    const p = spawnSync(argv[0]!, argv.slice(1), { cwd: runDir, stdio: "inherit", env: { ...process.env, ...o.env } });
    if (p.status !== 0) return fail(`check failed: ${argv.join(" ")}`);
    lines.push(`check ok: ${argv.join(" ")}`);
  }

  // 4. land-time path check (stand-in)
  const changed = git(o.cwd, ["diff", "--name-only", `${main}...${branch}`]).split("\n").filter(Boolean);
  const pc = pathCheck(changed);
  if (!pc.ok) return fail(`path check: ${pc.violations.join(", ")}`);
  lines.push(`path check ok (${changed.length} files)`);

  // 5. the land request: a decision the reducer may refuse (stale sha, not ready, wrong actor)
  const cmd = Command.parse({ type: "card.land_request", key: `card.land_request:${bc.card}:${sha}`, actor: o.actor ?? "lead", card: bc.card, sha });
  const lr = await o.http.post("/api/commands", cmd);
  if (!lr.body.ok) return fail(`land_request: ${lr.body.reason}`);

  // 6. fast-forward main. No push, ever.
  if (!tryGit(mainDir, ["merge", "--ff-only", branch])) return fail(`${main} cannot fast-forward to ${branch}`);

  // 7. the reconciler records card.landed; a violation here would mean the request did not match
  await o.http.post("/api/reconcile", {});
  const after = (await o.http.get(`/api/land/${encodeURIComponent(bc.card)}`)).body as { landed: boolean; violation: boolean };
  lines.push(`landed ${bc.card} ${sha.slice(0, 7)} on ${main}: ${after.landed ? "recorded" : "NOT recorded"}${after.violation ? " VIOLATION" : ""}`);
  return { ok: after.landed && !after.violation, lines };
}
