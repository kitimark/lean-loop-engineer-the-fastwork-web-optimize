// `fw review ready --report <file|-> [--task id]` and `fw review verdict --findings <file|-> [--audited yes] [--task id]`
// (task review-flow-v2): the gates of the build-review workflow. Both decisions are Lean (`Fw.Plan.ReviewReady`, fwcore ops
// `plan.reviewReady` and `plan.reviewVerdict`); this file reads JSON, calls fwcore and prints one `VERDICT` line (last) that a
// script routes on. No decision logic here: the per-item lines are fwcore asked about each item alone.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { UsageError, parseFlags } from "./lib.ts";
import { coreCandidates, coreCaller, type CoreCall } from "./watch.ts";

export const READY_USAGE = "usage: fw review ready --report <file|-> [--task <id>]   (report: {items:[{id,status,evidence}], runs?:[{id,state}], dry:\"VERDICT dry <id>\"}; exit 0 review, 21 wait, 22 dispatch, 23 returnToBuilder)\n" +
  "       fw review verdict --findings <file|-> [--audited yes] [--task <id>]   (findings: [{severity,...}] or {findings:[...]}; exit 0 accept, 1 refuse)";

export type Ready = "review" | "dispatch" | "wait" | "returnToBuilder";
export const READY_EXIT: Record<Ready, number> = { review: 0, wait: 21, dispatch: 22, returnToBuilder: 23 };
type Item = { id: string; status: string; evidence: string };
type Report = { items?: Item[]; runs?: { id: string; state: string }[]; dry?: string };

export interface Deps { core?: CoreCall; log?: (l: string) => void; stdin?: () => string }

function readJson(src: string | undefined, what: string, deps: Deps): unknown {
  if (!src) throw new UsageError(`missing ${what}`);
  const text = src === "-" ? (deps.stdin ?? (() => readFileSync(0, "utf8")))() : readFileSync(src, "utf8");
  try { return JSON.parse(text); } catch (e) { throw new UsageError(`${what}: not JSON (${e instanceof Error ? e.message : e})`); }
}

function coreOf(cwd: string, deps: Deps): CoreCall {
  if (deps.core) return deps.core;
  const root = execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd, encoding: "utf8" }).trim();
  const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, encoding: "utf8" }).trim();
  return coreCaller(coreCandidates(root, join(common, "..")));
}

export async function readyCli(argv: string[], cwd: string, deps: Deps = {}): Promise<number> {
  const out = deps.log ?? ((l: string) => console.log(l));
  const [verb, ...rest] = argv;
  const { flags } = parseFlags(rest);
  const task = flags.task ?? "-";
  const call = coreOf(cwd, deps);
  if (verb === "ready") {
    const rep = readJson(flags.report, "--report", deps) as Report;
    const items = Array.isArray(rep.items) ? rep.items : [];
    const req = (its: Item[], dry: string) => ({ op: "plan.reviewReady", items: its, runs: rep.runs ?? [], dry });
    const ready = (await call(req(items, rep.dry ?? ""))).ready as Ready;
    if (ready !== "review") {
      // which items hold it up: fwcore asked about each item alone with a passing dry line
      for (const i of items) {
        const r = (await call(req([i], "VERDICT dry x"))).ready as Ready;
        if (r !== "review") out(`  item ${i.id} (${i.status}): ${r}`);
      }
      if (!(rep.dry ?? "").startsWith("VERDICT dry ")) out("  dry: the report carries no `VERDICT dry <id>` line of fw land --dry");
      if (items.length === 0) out("  items: the report lists none");
    }
    out(`VERDICT review-ready ${task} ${ready}`);
    return READY_EXIT[ready];
  }
  if (verb === "verdict") {
    const raw = readJson(flags.findings, "--findings", deps) as unknown;
    const list = (Array.isArray(raw) ? raw : (raw as { findings?: unknown[] })?.findings ?? []) as { severity?: string }[];
    const r = await call({ op: "plan.reviewVerdict", severities: list.map((f) => String(f.severity ?? "")), audited: flags.audited === "yes" });
    const verdict = r.verdict as string;
    if (r.recheck) out(`  ${r.fixes} fix-before-land finding(s): the lead applies them and a checker re-checks the text before land`);
    out(`VERDICT review-verdict ${task} ${verdict}`);
    return verdict === "accept" ? 0 : 1;
  }
  throw new UsageError(READY_USAGE);
}
