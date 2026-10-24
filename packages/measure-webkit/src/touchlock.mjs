// Twin of lean/Fw/Measure/TouchLock.lean (golden packages/contracts/golden/measure/touch-lock.jsonl, replayed in test/touchlock.test.mjs).
// A sample is [y in tenths of a CSS px, 1 if the morph was open else 0].

export const MIN_OPEN_FRAMES = 10;

export function openPhase(xs) {
  let i = 0;
  while (i < xs.length && !xs[i][1]) i++;
  let j = i;
  while (j < xs.length && xs[j][1]) j++;
  return xs.slice(i, j);
}

export const lockOf = (xs) => openPhase(xs)[0]?.[0];

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

export function refusal(r) {
  const n = openPhase(r.frames).length;
  if (n === 0) return 'noOpen';
  if (n < MIN_OPEN_FRAMES) return 'tooShort';
  return null;
}

export function reduce(r) {
  const s = lockOf(r.frames) ?? 0;
  const frameFights = fights(s, r.frames);
  return {
    openFrames: openPhase(r.frames).length, displacedFrames: displaced(s, r.frames),
    frameReversals: reversals(r.frames), frameFights, restores: displaced(s, r.events),
    eventReversals: reversals(r.events), eventFights: fights(s, r.events), jitter: frameFights > 0,
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

export const FLICK = Object.freeze({ dragPt: 500, velocity: 1800, holdMs: 0 });

export const START_GAP_PX = 250;

export const TAIL_MS = 3000;

const runOf = (row) => ({ frames: row.frames.map((f) => [f[0], f[1]]), events: row.events.map((e) => [e[0], e[1]]) });

/** One entry per arm from the walk's rows; rows without a run (a failed push, a refused config) count as windows only. */
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
    const failed = mine.filter((r) => !r.frames).length;
    arms[id] = {
      windows: mine.length, failed, refused, accepted: kept.length, jitterRuns: kept.filter((k) => k.jitter).length,
      fights: kept.map((k) => k.frameFights), reversals: kept.map((k) => k.frameReversals), displaced: kept.map((k) => k.displacedFrames),
      restores: kept.map((k) => k.restores), eventFights: kept.map((k) => k.eventFights), eventReversals: kept.map((k) => k.eventReversals),
    };
  }
  const { orig, base, lock } = arms;
  return {
    arms,
    verdicts: {
      lockVsBase: { fights: cmp(base.fights, lock.fights), restores: cmp(base.restores, lock.restores), eventFights: cmp(base.eventFights, lock.eventFights) },
      baseVsOrig: { fights: cmp(orig.fights, base.fights), restores: cmp(orig.restores, base.restores) },
      look: look(base.displaced, lock.displaced),
    },
  };
}

export function markdown(s) {
  const head = '| arm | windows | push failed | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run |';
  const lines = [head, '|' + head.split('|').slice(1, -1).map(() => '---').join('|') + '|'];
  for (const id of ARMS) {
    const a = s.arms[id];
    lines.push(`| ${id} | ${a.windows} | ${a.failed} | ${JSON.stringify(a.refused)} | ${a.accepted} | ${a.jitterRuns} | ${a.fights.join(' ')} | ${a.reversals.join(' ')} | ${a.displaced.join(' ')} | ${a.restores.join(' ')} | ${a.eventFights.join(' ')} |`);
  }
  const v = s.verdicts;
  lines.push('', `lock vs base: fights ${v.lockVsBase.fights}, restores ${v.lockVsBase.restores}, event fights ${v.lockVsBase.eventFights}; base vs orig: fights ${v.baseVsOrig.fights}, restores ${v.baseVsOrig.restores}; look class of the candidate: ${v.look === 'same' ? 'same look' : 'look change'}`);
  return lines.join('\n');
}
