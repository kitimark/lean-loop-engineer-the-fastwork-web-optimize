import { pathToFileURL } from 'node:url';

const MINUTE_MS = 60000;

export const JOB = Object.freeze({ timeoutMs: 2700000, postMs: 540000, graceMs: 120000, slackMs: 60000 });

export const deadlineAt = (j) => j.timeoutMs - j.postMs - j.graceMs - j.slackMs;

export const cappedDeadline = (j, elapsed, cap) => (cap == null ? deadlineAt(j) : Math.min(deadlineAt(j), elapsed + cap));

export const stepMinutes = (j, elapsed, dl) => Math.floor(Math.max(0, dl + j.graceMs - elapsed) / MINUTE_MS);

export const runsWalk = (j, elapsed, dl, needMin) => needMin <= stepMinutes(j, elapsed, dl);

export const startsWindow = (dl, now, reserve) => now + reserve <= dl;

export const remaining = (dl, now) => Math.max(0, dl - now);

export const MIN_WALK_MINUTES = 2;

export const WINDOW_RESERVE_MS = 30000;

/** Resolves 'done' when `p` settles first, 'deadline' when the clock reaches `dl` first; a later rejection of `p` is swallowed. */
export async function untilDeadline(p, dl, now = Date.now) {
  let timer;
  const gone = new Promise((resolve) => { timer = setTimeout(() => resolve('deadline'), remaining(dl, now())); });
  p.catch(() => {});
  try { return await Promise.race([p.then(() => 'done'), gone]); } finally { clearTimeout(timer); }
}

/** Outputs of the "Walk budget" workflow step, in ms since the epoch, from the job start the first step recorded. */
export function planWalk({ jobStartMs, nowMs, capMin }, j = JOB) {
  const elapsed = nowMs - jobStartMs;
  const dl = cappedDeadline(j, elapsed, capMin == null ? null : capMin * MINUTE_MS);
  return { run: runsWalk(j, elapsed, dl, MIN_WALK_MINUTES), stepMinutes: stepMinutes(j, elapsed, dl), deadlineMs: jobStartMs + dl };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const args = process.argv.slice(2);
  const flag = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };
  const jobStartMs = Number(flag('--job-start-ms'));
  if (!Number.isFinite(jobStartMs) || jobStartMs <= 0) { console.error('walk-budget needs --job-start-ms <epoch ms>'); process.exit(2); }
  const cap = flag('--cap-min');
  const p = planWalk({ jobStartMs, nowMs: Number(flag('--now-ms') ?? Date.now()), capMin: cap ? Number(cap) : null });
  console.log(`run=${p.run}\nstep_minutes=${p.stepMinutes}\ndeadline_ms=${p.deadlineMs}`);
}
