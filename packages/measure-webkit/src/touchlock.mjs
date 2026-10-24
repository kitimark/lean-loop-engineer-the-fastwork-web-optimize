
export const MIN_OPEN_FRAMES = 10;

export function openPhase(xs) {
  let i = 0;
  while (i < xs.length && !xs[i][1]) i++;
  let j = i;
  while (j < xs.length && xs[j][1]) j++;
  return xs.slice(i, j);
}

export const storedLock = (calls) => calls.find((c) => c[1])?.[0] ?? null;

export const lockOf = (r) => storedLock(r.calls);

export const lockSteady = (r) => {
  const s = lockOf(r);
  return s === null || r.calls.filter((c) => c[1]).every((c) => c[0] === s);
};

export function dedup(l) {
  const out = [];
  for (const x of l) if (out.length === 0 || out[out.length - 1] !== x) out.push(x);
  return out;
}

export function turns(p, l) {
  let n = 0;
  for (let i = 2; i < l.length; i++) if ((l[i - 1] - l[i - 2]) * (l[i] - l[i - 1]) < 0 && p(l[i])) n++;
  return n;
}

const positions = (xs) => dedup(openPhase(xs).map((s) => s[0]));
export const reversals = (xs) => turns(() => true, positions(xs));
export const fights = (s, xs) => turns((c) => c === s, positions(xs));
export const displaced = (s, xs) => openPhase(xs).filter((x) => x[0] !== s).length;
export const fightsAt = (s, xs) => (s === null ? 0 : fights(s, xs));
export const displacedAt = (s, xs) => (s === null ? 0 : displaced(s, xs));

export function refusal(r) {
  const n = openPhase(r.frames).length;
  if (n === 0) return 'noOpen';
  if (n < MIN_OPEN_FRAMES) return 'tooShort';
  if (!lockSteady(r)) return 'lockMoved';
  return null;
}

export function reduce(r) {
  const s = lockOf(r);
  const frameFights = fightsAt(s, r.frames);
  return {
    openFrames: openPhase(r.frames).length, displacedFrames: displacedAt(s, r.frames),
    frameReversals: reversals(r.frames), frameFights, restores: displacedAt(s, r.events),
    eventReversals: reversals(r.events), eventFights: fightsAt(s, r.events), jitter: frameFights > 0, lock: s,
  };
}

const maxOf = (xs) => xs.reduce((a, b) => Math.max(a, b), 0);
const minOf = (xs) => xs.reduce((a, b) => Math.min(a, b), maxOf(xs));

export function cmp(faith, cand) {
  if (faith.length === 0 || cand.length === 0) return 'overlap';
  if (maxOf(cand) < minOf(faith)) return 'lower';
  if (maxOf(faith) < minOf(cand)) return 'higher';
  return 'overlap';
}

export const look = (faith, cand) => (faith.every((x) => x === 0) && cand.every((x) => x === 0) ? 'same' : 'change');

export function tally(rs) {
  const ok = rs.filter((r) => refusal(r) === null);
  return { accepted: ok.length, jitter: ok.filter((r) => reduce(r).jitter).length };
}

/** The Simulator pans lock-open pages with real touches; `lock` is the candidate: the same page with a CSS lock while the morph is open. */
export const ARMS = Object.freeze(['orig', 'base', 'lock']);

export const LOCK_CSS = 'html.fw-lock{overflow:hidden!important;overscroll-behavior:none!important;touch-action:none!important}';

export const MAX_RESTARTS = 2;

export const serveTag = (restarts) => (restarts === 0 ? 'serve' : `serve-r${restarts}`);

export const repOrder = (rep) => (rep % 2 === 0 ? ['base', 'lock', 'orig'] : ['lock', 'base', 'orig']);

export const afterWindow = (used, stalled) => (!stalled ? 'keep' : used < MAX_RESTARTS ? 'restart' : 'stop');

export const PAN = Object.freeze({ dragPt: 500, velocity: 500, holdMs: 0 });

export const START_GAP_PX = 250;

export const TAIL_MS = 3000;

const runOf = (row) => ({
  frames: row.frames.map((f) => [f[0], f[1]]), events: row.events.map((e) => [e[0], e[1]]), calls: (row.calls ?? []).map((c) => [c[0], c[1]]),
});

const reasonOf = (status) => String(status ?? 'unknown').replace(/^(push|refused):/, '');

export function windowsOf(rows) {
  return rows.map((r, i) => {
    const base = { n: i + 1, arm: r.arm, rep: r.rep ?? null };
    if (!r.frames) return { ...base, state: String(r.status ?? '').startsWith('push:') ? 'push failed' : 'refused', reason: reasonOf(r.status) };
    const run = runOf(r);
    const why = refusal(run);
    if (why) return { ...base, state: 'refused', reason: why, openFrames: openPhase(run.frames).length };
    const k = reduce(run);
    return { ...base, state: 'open', reason: null, openFrames: k.openFrames, reversals: k.frameReversals, fights: k.frameFights, displaced: k.displacedFrames, restores: k.restores, lock: k.lock };
  });
}

export function summarize(rows) {
  const arms = {};
  for (const id of ARMS) {
    const mine = rows.filter((r) => r.arm === id);
    const runs = mine.filter((r) => r.frames);
    const refused = {};
    const kept = [];
    for (const r of runs) {
      const why = refusal(runOf(r));
      if (why) refused[why] = (refused[why] ?? 0) + 1;
      else kept.push(reduce(runOf(r)));
    }
    const failures = {};
    for (const r of mine.filter((x) => !x.frames)) failures[reasonOf(r.status)] = (failures[reasonOf(r.status)] ?? 0) + 1;
    arms[id] = {
      windows: mine.length, failed: mine.length - runs.length, failures, refused, accepted: kept.length, jitterRuns: kept.filter((k) => k.jitter).length,
      fights: kept.map((k) => k.frameFights), reversals: kept.map((k) => k.frameReversals), displaced: kept.map((k) => k.displacedFrames),
      restores: kept.map((k) => k.restores), eventFights: kept.map((k) => k.eventFights), eventReversals: kept.map((k) => k.eventReversals),
      locks: kept.map((k) => k.lock),
    };
  }
  const { orig, base, lock } = arms;
  return {
    arms,
    windows: windowsOf(rows),
    verdicts: {
      lockVsBase: { fights: cmp(base.fights, lock.fights), restores: cmp(base.restores, lock.restores), eventFights: cmp(base.eventFights, lock.eventFights) },
      baseVsOrig: { fights: cmp(orig.fights, base.fights), restores: cmp(orig.restores, base.restores) },
      look: look(base.displaced, lock.displaced),
    },
  };
}

const table = (head, body) => [head, '|' + head.split('|').slice(1, -1).map(() => '---').join('|') + '|', ...body];

export function markdown(s) {
  const head = '| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run |';
  const lines = table(head, ARMS.map((id) => {
    const a = s.arms[id];
    return `| ${id} | ${a.windows} | ${a.failed} | ${JSON.stringify(a.failures)} | ${JSON.stringify(a.refused)} | ${a.accepted} | ${a.jitterRuns} | ${a.fights.join(' ')} | ${a.reversals.join(' ')} | ${a.displaced.join(' ')} | ${a.restores.join(' ')} | ${a.eventFights.join(' ')} | ${a.locks.map((l) => l ?? 'none').join(' ')} |`;
  }));
  const wins = s.windows ?? [];
  if (wins.length) {
    lines.push('', ...table('| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock |',
      wins.map((w) => `| ${w.n} | ${w.arm} | ${w.rep ?? ''} | ${w.state} | ${w.reason ?? ''} | ${w.openFrames ?? ''} | ${w.reversals ?? ''} | ${w.fights ?? ''} | ${w.displaced ?? ''} | ${w.restores ?? ''} | ${w.state === 'open' ? (w.lock ?? 'none') : ''} |`)));
  }
  const v = s.verdicts;
  lines.push('', `lock vs base: fights ${v.lockVsBase.fights}, restores ${v.lockVsBase.restores}, event fights ${v.lockVsBase.eventFights}; base vs orig: fights ${v.baseVsOrig.fights}, restores ${v.baseVsOrig.restores}; look class of the candidate: ${v.look === 'same' ? 'same look' : 'look change'}`);
  return lines.join('\n');
}
