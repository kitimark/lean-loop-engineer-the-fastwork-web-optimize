import { pathToFileURL } from 'node:url';

const MINUTE_MS = 60000;

export const JOB = Object.freeze({ timeoutMs: 3600000, postMs: 600000, graceMs: 120000, slackMs: 480000 });

export const GAPS = Object.freeze({ clockMs: 6000, driftMs: 50000, completeMs: 4000, overrunMs: 420000 });

export const MIN_KEPT = 5;

export const REPS_WANT = 6;

// Lean readyAllowMs: how long the harness waits for the touch driver; the plan clock is read after it answers.
export const READY_ALLOW_MS = 480000;

export const SETUP_WORST_MS = 900000;

export const LIFE_WINDOWS = 36;

export const BODY_MS = 29000;

export const TAIL_MS = 398000;

export const TAIL_EVERY = 20;

export const MARGIN = 2;

export const MIN_SAMPLES = 3;

export const JOBS_NEEDED = MIN_SAMPLES + MARGIN;

export const SHAPES = Object.freeze({ full: 2, endOnly: 1 });

export const blockMs = (n) => n * BODY_MS + Math.floor((n + TAIL_EVERY - 1) / TAIL_EVERY) * (TAIL_MS - BODY_MS);

export const windowsPerRep = (shape, arms) => SHAPES[shape] * arms;

export const repsFit = (dl, now, shape, arms) => {
  const w = windowsPerRep(shape, arms);
  if (w === 0) return 0;
  for (let k = LIFE_WINDOWS; k > 0; k--) if (blockMs(k * w) <= Math.max(0, dl - now)) return k;
  return 0;
};

export const repsLife = (shape, arms) => (windowsPerRep(shape, arms) === 0 ? 0 : Math.floor(LIFE_WINDOWS / windowsPerRep(shape, arms)));

export const planReps = (dl, now, shape, arms) => Math.min(repsLife(shape, arms), repsFit(dl, now, shape, arms), REPS_WANT);

export const outcome = (dl, now, shape, arms) => (repsLife(shape, arms) < MIN_KEPT ? 'lifeShort' : repsFit(dl, now, shape, arms) < MIN_KEPT ? 'budgetShort' : 'ok');

export const endsDone = (shape, n, arms, pos) => Math.floor(n / windowsPerRep(shape, arms)) + (SHAPES[shape] * (pos + 1) <= n % windowsPerRep(shape, arms) ? 1 : 0);

export const groupArms = (controls, cands, g) => controls + Math.floor((cands + g - 1) / g);

export const groupsFor = (dl, now, shape, controls, cands) => {
  for (let g = 1; g <= cands + 1; g++) if (outcome(dl, now, shape, groupArms(controls, cands, g)) === 'ok') return g;
  return null;
};

export const deadlineAt = (j) => j.timeoutMs - j.postMs - j.graceMs - j.slackMs;

export const cappedDeadline = (j, elapsed, cap) => (cap == null ? deadlineAt(j) : Math.min(deadlineAt(j), elapsed + cap));

export const stepMinutes = (j, elapsed, dl) => Math.floor(Math.max(0, dl + j.graceMs - elapsed) / MINUTE_MS);

export const runsWalk = (j, elapsed, dl, needMin) => needMin <= stepMinutes(j, elapsed, dl);

export const startsWindow = (dl, now, reserve) => now + reserve <= dl;

export const remaining = (dl, now) => Math.max(0, dl - now);

export const HARD_STOP_MS = 45000;

export const MIN_WALK_MINUTES = 2;

export const WINDOW_RESERVE_MS = 30000;

export async function untilDeadline(p, dl, now = Date.now) {
  let timer;
  const gone = new Promise((resolve) => { timer = setTimeout(() => resolve('deadline'), remaining(dl, now())); });
  p.catch(() => {});
  try { return await Promise.race([p.then(() => 'done'), gone]); } finally { clearTimeout(timer); }
}

export function planWalk({ jobStartMs, nowMs, capMin }, j = JOB) {
  const elapsed = nowMs - jobStartMs;
  const dl = cappedDeadline(j, elapsed, capMin == null ? null : capMin * MINUTE_MS);
  return { run: runsWalk(j, elapsed, dl, MIN_WALK_MINUTES), stepMinutes: stepMinutes(j, elapsed, dl), deadlineMs: jobStartMs + dl, hardStopSeconds: Math.max(1, Math.floor((jobStartMs + dl + HARD_STOP_MS - nowMs) / 1000)) };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const args = process.argv.slice(2);
  const flag = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };
  const jobStartMs = Number(flag('--job-start-ms'));
  if (!Number.isFinite(jobStartMs) || jobStartMs <= 0) { console.error('walk-budget needs --job-start-ms <epoch ms>'); process.exit(2); }
  const cap = flag('--cap-min');
  const p = planWalk({ jobStartMs, nowMs: Number(flag('--now-ms') ?? Date.now()), capMin: cap ? Number(cap) : null });
  console.log(`run=${p.run}\nstep_minutes=${p.stepMinutes}\ndeadline_ms=${p.deadlineMs}\nhard_stop_seconds=${p.hardStopSeconds}`);
}
