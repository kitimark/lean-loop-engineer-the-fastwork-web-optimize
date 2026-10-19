// `fw checks --affected --base <rev> [--tier local|remote] [--list]`: the land checks a change selects, split by tier, and
// the chosen tier run with one `VERDICT <pass|fail|skipped> <id>` line per check.
// Selection: `selectChecks` over `candidateChecks` (land.ts, TS stand-in checked against the `landSpeed.select` golden).
// Tier and lane verdict: fwcore ops `console.landTier` and `console.landLane` (Lean Fw.Console.LandTier; golden land-tier.jsonl).
// This file holds no decision. TS stand-in: the skipped-test counts are read from vitest / node:test summaries here.
import { execFileSync, spawn } from "node:child_process";
import { candidateChecks, FWCORE_USERS, selectChecks, type Check } from "./land.ts";
import { UsageError } from "./lib.ts";
import { fwcoreCall, type FwCall } from "./run.ts";

export const CHECKS_USAGE =
  "usage: fw checks --affected --base <rev> [--tier local|remote] [--list]\n" +
  "  prints the checks the diff <rev>..HEAD selects (Lean selection); --list stops there, else the chosen tier runs\n" +
  "  one line VERDICT <pass|fail|skipped> <id> per check; exit 0 iff every check passed (a skipped fwcore-user test fails)";

export type ChecksArgs = { base: string; tier?: "local" | "remote"; list: boolean };

export function parseChecksArgs(argv: string[]): ChecksArgs {
  const a: { base?: string; tier?: "local" | "remote"; list: boolean; affected: boolean } = { list: false, affected: false };
  for (let i = 0; i < argv.length; i++) {
    const f = argv[i]!;
    if (f === "--affected") a.affected = true;
    else if (f === "--list") a.list = true;
    else if (f === "--base" || f === "--tier") {
      const v = argv[++i];
      if (v === undefined || v.startsWith("--")) throw new UsageError(`flag ${f} needs a value\n${CHECKS_USAGE}`);
      if (f === "--base") a.base = v;
      else if (v === "local" || v === "remote") a.tier = v;
      else throw new UsageError(`--tier is local or remote, not ${v}\n${CHECKS_USAGE}`);
    } else throw new UsageError(`unknown argument ${f}\n${CHECKS_USAGE}`);
  }
  if (!a.affected) throw new UsageError(`--affected is required\n${CHECKS_USAGE}`);
  if (!a.base) throw new UsageError(`--base is required\n${CHECKS_USAGE}`);
  return { base: a.base, tier: a.tier, list: a.list };
}

export type Plan = { changed: string[]; selected: Check[]; local: string[]; remote: string[] };

/** The selected checks of `changed` in table order, split by the Lean tier (`console.landTier`). */
export function planFor(root: string, changed: string[], core: FwCall): Plan {
  const all = candidateChecks(root);
  const ids = new Set(selectChecks(all, changed));
  const selected = all.filter((c) => ids.has(c.id));
  const r = core({ op: "console.landTier", ids: selected.map((c) => c.id) }) as { local: string[]; remote: string[] };
  return { changed, selected, local: r.local, remote: r.remote };
}

export const changedBetween = (root: string, base: string): string[] =>
  execFileSync("git", ["diff", "--name-only", base, "HEAD"], { cwd: root, encoding: "utf8", maxBuffer: 1 << 28 }).split("\n").filter(Boolean);

/** Tests a runner output reports as skipped: vitest `Tests  3 passed | 2 skipped`, node:test `# skipped 2`. */
export function skippedCount(out: string): number {
  const node = [...out.matchAll(/^# skipped (\d+)/gm)].reduce((n, m) => n + Number(m[1]), 0);
  const vitest = [...out.matchAll(/^\s*Tests\s.*?\b(\d+) skipped\b/gm)].reduce((n, m) => n + Number(m[1]), 0);
  return node + vitest;
}

export type RunResult = { code: number; out: string };
export type Runner = (argv: string[], cwd: string) => Promise<RunResult>;

export const spawnRunner: Runner = (argv, cwd) =>
  new Promise((res) => {
    const p = spawn(argv[0]!, argv.slice(1), { cwd, stdio: ["ignore", "pipe", "pipe"] });
    let out = "";
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (out += d));
    p.on("error", (e) => res({ code: 127, out: out + String(e) }));
    p.on("close", (code) => res({ code: code ?? 1, out }));
  });

/** Run `checks` one after another; one VERDICT line each (the verdict is `console.landLane`). Returns the exit code. */
export async function runTier(checks: Check[], root: string, core: FwCall, run: Runner, log: (s: string) => void): Promise<number> {
  let bad = 0;
  const ci = process.env.GITHUB_ACTIONS === "true";
  for (const c of checks) {
    const t0 = Date.now();
    const r = await run(c.argv, root);
    const skipped = skippedCount(r.out);
    const v = core({ op: "console.landLane", exitOk: r.code === 0, coreUser: FWCORE_USERS.includes(c.id), skipped }) as { verdict: string; ok: boolean };
    log(`${ci ? "::group::" : ""}${c.id}: ${c.argv.join(" ")}`);
    log(r.out.trimEnd());
    if (ci) log("::endgroup::");
    log(`VERDICT ${v.verdict} ${c.id}`);
    log(`TIMING ${c.id} ${Math.round((Date.now() - t0) / 1000)}s skipped=${skipped}`);
    if (!v.ok) bad++;
  }
  return bad === 0 ? 0 : 1;
}

export async function checksCli(argv: string[], cwd: string, deps: { core?: FwCall; run?: Runner; log?: (s: string) => void; changed?: string[] } = {}): Promise<number> {
  const a = parseChecksArgs(argv);
  const root = execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd, encoding: "utf8" }).trim();
  const core = deps.core ?? fwcoreCall(cwd);
  const log = deps.log ?? ((s: string) => console.log(s));
  const p = planFor(root, deps.changed ?? changedBetween(root, a.base), core);
  const tierOf = (id: string) => (p.remote.includes(id) ? "remote" : "local");
  const chosen = p.selected.filter((c) => (a.tier ? tierOf(c.id) === a.tier : true));
  log(`checks: ${p.changed.length} changed files; selected ${p.selected.length}: ${p.selected.map((c) => `${tierOf(c.id)}:${c.id}`).join(" ") || "none"}`);
  if (a.list) { for (const c of chosen) log(`${tierOf(c.id)} ${c.id}`); return 0; }
  if (chosen.length === 0) { log(`checks: no ${a.tier ?? "selected"} checks`); return 0; }
  return runTier(chosen, root, core, deps.run ?? spawnRunner, log);
}
