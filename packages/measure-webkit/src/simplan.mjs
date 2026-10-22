// The plan of the webkit-sim workflow, decided by Lean (fwcore op `measure.simPlan`, lean/Fw/Measure/SimPlan.lean): which arms
// run, the query the rewrite is served with, the job matrix, and the refusals. This file builds the request from the
// dispatch inputs (environment), asks fwcore and writes the reply as workflow outputs. It decides nothing.
//
//   TARGET=both VMS=1 SESSIONS=1 PRESET=original FW=hero.countdown:strip EXPERIMENT=determinism SHA=<40 hex> \
//     FWCORE=<path> node src/simplan.mjs        (appends key=value lines to the step-output file when it is set)
import { appendFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { fwcoreCall } from './handoff.mjs';

/** The fwcore request for the dispatch inputs in `env`. */
export function planRequest(env) {
  return {
    op: 'measure.simPlan', id: 'sim-plan',
    target: env.TARGET ?? '', vms: env.VMS ?? '', sessions: env.SESSIONS ?? '', preset: env.PRESET ?? '',
    fw: env.FW ?? '', experiment: env.EXPERIMENT ?? '', sha: env.SHA ?? '',
  };
}

/** The workflow outputs of an accepted reply: `matrix` ({include: [...]} of the cells), `search`, `original`, `rewrite`, `both`, and the time bounds `step_min`, `job_min`, `stall_ms`, and the watchdog's `watchdog_min` and `term_grace_ms`. */
export function outputsOf(reply) {
  return {
    matrix: JSON.stringify({ include: reply.matrix }),
    search: reply.search,
    original: String(reply.original), rewrite: String(reply.rewrite), both: String(reply.both),
    step_min: String(reply.stepTimeoutMin), job_min: String(reply.jobTimeoutMin), stall_ms: String(reply.stallMs),
    watchdog_min: String(reply.watchdogMin), term_grace_ms: String(reply.termGraceMs),
  };
}

/** Ask fwcore; throws with Lean's problems when the request is refused. */
export async function simPlan(env, call = fwcoreCall) {
  const [reply] = await call([planRequest(env)]);
  if (reply.error) throw new Error(`fwcore: ${reply.error}`);
  if (reply.problems.length) throw new Error(`webkit-sim plan refused:\n  ${reply.problems.join('\n  ')}`);
  return outputsOf(reply);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  simPlan(process.env).then((o) => {
    const lines = Object.entries(o).map(([k, val]) => `${k}=${val}`);
    console.log(lines.join('\n'));
    const out = process.env.GITHUB_OUTPUT;
    if (out) appendFileSync(out, lines.join('\n') + '\n');
  }, (e) => { console.error(e.message); process.exit(1); });
}
