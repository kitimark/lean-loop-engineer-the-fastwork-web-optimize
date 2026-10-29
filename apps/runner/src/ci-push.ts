import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { renderGuard } from "./land.ts";
import { ancestors, readIntent, type LandIntent } from "./land-intent.ts";
import { landBranch, markerMessage, type StartCtx } from "./land-remote.ts";

export const MAIN_REF = "refs/heads/main";
export const BASE = "origin/main";
const ZERO = /^0+$/;
const ROOT = resolve(import.meta.dirname, "../../..");

export type LaneReason = "ok" | "same-tree" | "missing" | "no-measuring";
export type LaneVerdict = { reason: LaneReason; required: string[]; missing: string[]; measuring: string[] };

/** Lean `lanesTrailer`: the lane names after `[lanes:` up to `]` (lower case; comma, space, tab and line feed separate; no `]` asks nothing). */
export function lanesTrailer(msg: string): string[] {
  const lower = msg.replace(/[A-Z]/g, (c) => c.toLowerCase());
  return lower.split("[lanes:").slice(1).flatMap((seg) => {
    const parts = seg.split("]");
    return parts.length >= 2 ? parts[0]!.split(/[, \t\n]+/).filter((x) => x !== "") : [];
  });
}

/** Lean `requiredLanes`: the trailers of all commit messages, each name once, first seen first. */
export function requiredLanes(msgs: string[]): string[] {
  return [...new Set(msgs.flatMap(lanesTrailer))];
}

/** Lean `reason` over its facts: `runs` the names of the lanes the tip starts, `nonMeasuring` the lane names of the seeder workflows,
 *  `sameTree` no branch file differs from main. */
export function laneReason(msgs: string[], runs: string[], nonMeasuring: string[], sameTree: boolean): LaneVerdict {
  const required = requiredLanes(msgs);
  const missing = required.filter((n) => !runs.includes(n));
  const measuring = runs.filter((n) => !nonMeasuring.includes(n));
  const reason: LaneReason = sameTree ? "same-tree" : missing.length ? "missing" : measuring.length === 0 ? "no-measuring" : "ok";
  return { reason, required, missing, measuring };
}

type Lane = { file: string; name: string; token: string; byDefault: boolean };
type Guard = {
  loadIntent(root: string): { lanes: { prefix: string; lanes: Lane[] } };
  preciseInputs(root: string, file: string): string[] | null;
  decide(a: Record<string, unknown>): { run: boolean };
};
const sh = (cwd: string, ...a: string[]) => execFileSync("git", a, { cwd, encoding: "utf8", maxBuffer: 64 << 20, stdio: ["ignore", "pipe", "pipe"] }).trim();
const linesOf = (t: string) => (t === "" ? [] : t.split("\n"));

export type PushFacts = { sha: string; parents: string[]; tree: string; mergeTree: string; msg: string; ancestors: number[] };
export type LandCheck = "ok" | "branch" | "marker" | "parent" | "tree" | "message" | "lanes" | "process";

/** Lean `requested`: the message, ASCII upper case lowered, contains the token `[ci:<name>]`. */
export const requested = (name: string, msg: string): boolean => msg.replace(/[A-Z]/g, (c) => c.toLowerCase()).includes(`[ci:${name}]`);

const landMarker = (i: LandIntent): string => markerMessage({ task: i.task, mergeSha: i.merge, legs: i.legs ? { ...i.legs, cc: [] } : undefined } as StartCtx);

/** Lean `landCheck`: the first identity check the push of `ref` with facts `f` fails against the land intent `i`, or "ok";
 *  `laneNames` are the names of Lean `lanes`. */
export function landCheck(i: LandIntent, ref: string, f: PushFacts, laneNames: string[]): LandCheck {
  if (ref !== `refs/heads/${landBranch(i.task, i.merge, i.again)}`) return "branch";
  if (f.sha !== i.marker) return "marker";
  if (f.parents.length !== 1 || f.parents[0] !== i.merge) return "parent";
  if (f.tree !== f.mergeTree) return "tree";
  if (f.msg !== landMarker(i)) return "message";
  if (!laneNames.every((n) => !requested(n, f.msg) || n === "land")) return "lanes";
  if (!f.ancestors.includes(i.pid)) return "process";
  return "ok";
}

/** `null` when no land intent names the pushed commit, else Lean `landCheck` over the facts read from git and `ps`. */
export async function landAdmission(cwd: string, sha: string, remote: string, root: string = ROOT): Promise<{ task: string; check: LandCheck } | null> {
  const i = readIntent(sh(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"), sha);
  if (!i) return null;
  const g = (await import(pathToFileURL(join(root, ".github/scripts/changed-inputs.mjs")).href)) as Guard;
  const laneNames = g.loadIntent(root).lanes.lanes.map((l) => l.name);
  const tree = (rev: string) => { try { return sh(cwd, "rev-parse", `${rev}^{tree}`); } catch { return ""; } };
  const f: PushFacts = { sha, parents: sh(cwd, "rev-list", "--parents", "-n", "1", sha).split(" ").slice(1), tree: tree(sha), mergeTree: tree(i.merge),
    msg: sh(cwd, "log", "-1", "--format=%B", sha), ancestors: ancestors() };
  return { task: i.task, check: landCheck(i, remote, f, laneNames) };
}

/** The seeder workflow files, from the head line of the Lean push lane golden. */
function seederFiles(root: string): string[] {
  const first = readFileSync(join(root, "packages/contracts/golden/ci/pushlane.jsonl"), "utf8").split("\n")[0]!;
  return (JSON.parse(first) as { seeders: string[] }).seeders;
}

/** The `REFUSED` text for one ci ref, or "" when the lane check passes or cannot decide (it then prints a note). Reads `root` for the
 *  Lean golden and the lane inputs, `cwd` for the branch. */
export async function laneRefusal(cwd: string, base: string, sha: string, remote: string, root: string = ROOT): Promise<string> {
  try {
    const g = (await import(pathToFileURL(join(root, ".github/scripts/changed-inputs.mjs")).href)) as Guard;
    const { lanes: il } = g.loadIntent(root);
    const seeders = seederFiles(root);
    const msgs = sh(cwd, "log", "-z", "--format=%B", `${base}..${sha}`).split("\0").filter((m) => m.trim() !== "");
    const mb = sh(cwd, "merge-base", base, sha);
    const differs = new Set(linesOf(sh(cwd, "diff", "--name-only", "--no-renames", base, sha)));
    const files = linesOf(sh(cwd, "diff", "--name-only", "--no-renames", mb, sha)).filter((f) => differs.has(f));
    let landed = false;
    try { sh(cwd, "merge-base", "--is-ancestor", sha, base); landed = true; } catch { /* not an ancestor */ }
    const tipMsg = msgs[0] ?? "";
    const runs = il.lanes
      .filter((l) => g.decide({ event: "push", ref: remote, files, globs: g.preciseInputs(root, l.file) ?? [], msg: tipMsg, lane: { ...l, prefix: il.prefix }, tip: true, landed }).run)
      .map((l) => l.name);
    const nonMeasuring = il.lanes.filter((l) => seeders.includes(l.file)).map((l) => l.name);
    const v = laneReason(msgs, runs, nonMeasuring, files.length === 0);
    if (v.reason === "ok") return "";
    const tok = (n: string) => il.lanes.find((l) => l.name === n)?.token ?? `${il.prefix}${n}]`;
    const name = remote.replace(/^refs\/(heads\/)?/, "");
    const what = { "same-tree": `no file on the branch differs from ${base} (an empty commit runs no lane)`,
      missing: `the task requires ${v.missing.join(", ")} (a [lanes: ...] trailer), which would not start`,
      "no-measuring": "the tip message names no lane whose inputs changed, so only the seeder lane would run" }[v.reason];
    const fix = { "same-tree": "commit the change the lane should measure, then push",
      missing: v.missing.map((n) => (il.lanes.some((l) => l.name === n) ? `put ${tok(n)} in the tip message and change a file ${n} reads` : `${n} is no lane (lanes: ${il.lanes.map((l) => l.name).join(", ")})`)).join("; "),
      "no-measuring": `name a lane in the tip message, e.g. ${tok(il.lanes.find((l) => !l.byDefault)?.name ?? "wktr")}, and change a file it reads` }[v.reason];
    return `REFUSED: ci push lane check: ${name} (${sha.slice(0, 7)}): ${what}\n  lanes that would run: ${runs.length ? runs.join(", ") : "none"}\n  ${fix}`;
  } catch (e) {
    console.error(`ci push lane check skipped (cannot decide): ${String((e as Error).message ?? e).split("\n")[0]}`);
    return "";
  }
}

/** The REFUSED lines for a pre-push stdin (`<local ref> <local sha> <remote ref> <remote sha>` per line); empty means the push may go. */
export async function ciPushRefusals(stdin: string, cwd: string, base: string = BASE): Promise<string[]> {
  const out: string[] = [];
  for (const line of stdin.split("\n")) {
    const [, sha, remote] = line.trim().split(/\s+/);
    if (!sha || !remote || remote === MAIN_REF || ZERO.test(sha)) continue;
    const rg = renderGuard(cwd, base, sha);
    if ("error" in rg) { out.push(`REFUSED: ci push render guard: ${rg.error}`); continue; }
    if (rg.hits.length)
      out.push(`REFUSED: ci push render guard: ${base}..${remote.replace(/^refs\/(heads\/)?/, "")} (${sha.slice(0, 7)}) writes media outside snapshot/, and a later removal leaves the blob in history:${rg.hits.map((h) => `\n  ${h.path} (${h.media}) in ${h.commit}`).join("")}\nmove the other changes to a new branch from ${base} without these commits, or add the path with its reason to Fw.Land.RenderGuard.allowlist`);
    if (remote.startsWith("refs/heads/ci/")) {
      let land: { task: string; check: LandCheck } | null = null;
      try { land = await landAdmission(cwd, sha, remote); } catch (e) { console.error(`ci push land intent not read: ${String((e as Error).message ?? e).split("\n")[0]}`); }
      if (land?.check === "ok") {
        console.error(`ci push lane check: ${remote.slice("refs/heads/".length)} (${sha.slice(0, 7)}) is fw land's push for ${land.task} (land intent verified)`);
        continue;
      }
      const r = await laneRefusal(cwd, base, sha, remote);
      if (r) out.push(land ? `${r}\n  land intent of ${land.task} not verified: ${land.check}` : r);
    }
  }
  return out;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const chunks: Buffer[] = [];
  for await (const c of process.stdin) chunks.push(c as Buffer);
  const refused = await ciPushRefusals(Buffer.concat(chunks).toString("utf8"), process.cwd());
  for (const l of refused) console.error(l);
  process.exit(refused.length ? 1 : 0);
}
