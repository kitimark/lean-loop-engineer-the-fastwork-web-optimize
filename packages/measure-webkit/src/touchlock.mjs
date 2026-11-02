import { acrossDecisive, agreeNeeded, decisive } from '../../gate-breakpoints/src/smooth/reduce.mjs';
import { restRow, restTallyOf, restCmp, restReport, restMarkdown, restWindowsMarkdown, cmpVerdict } from './touchlock-rest.mjs';

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

export const openCalls = (r) => r.calls.filter((c) => c[1]).length;

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
    eventReversals: reversals(r.events), eventFights: fightsAt(s, r.events), jitter: frameFights > 0, lock: s, openCalls: openCalls(r),
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

export const MIN_SAMPLES = 3;

export const lockedOf = (ks) => ks.filter((k) => k[0] !== null).map((k) => k[1]);

export function lockedCmp(faith, cand) {
  if (faith.length === 0 || cand.length === 0) return 'undecided';
  const f = lockedOf(faith);
  const c = lockedOf(cand);
  if (f.length === 0 || c.length === 0) return 'n/a';
  return cmpKnown(f, c);
}

const PIN_VERDICT = Object.freeze({ lower: 'second', higher: 'first', overlap: 'same' });

export const pinVerdict = (c) => PIN_VERDICT[c] ?? 'insufficient';

export const acrossPin = (cs) => acrossDecisive(cs.map(pinVerdict));

export const QUIET10 = 1200;

export const SLACK10 = 10;

export function liveWrites(es) {
  let touching = false;
  let last = null;
  let n = 0;
  for (const [op, t, x] of es) {
    if (op === 'touch') { touching = x === 1; last = t; } else if (op === 'moved') last = t;
    else if (op === 'write') {
      if (touching || (last !== null && t + SLACK10 < last + QUIET10)) n++;
      last = t;
    }
  }
  return n;
}

export const pinLiveWrites = (entries) => liveWrites(entries.map((e) => [e[0], Math.round(e[1] * 10), e[4] ?? 0]));

export const rankedOf = (ks) => ({ ranked: lockedOf(ks).length, runs: ks.length });

export const RANKED_TEXT = 'lockedCmp ranks only the runs where the arm wrote while the morph was open (a stored lock), a selected subset; runs with no write are left out';

export const rankedText = (ranked) => `${RANKED_TEXT}: ${ARMS.map((id) => `${id} ${ranked[id].ranked} of ${ranked[id].runs}`).join(', ')}`;

export function traceCounts(names) {
  const n = (w) => names.filter((x) => x === w).length;
  const c = { inactive: n('inactive'), due: n('due'), touches: n('touch'), moved: n('moved'), wrote: n('write'), touching: n('touching'), live: n('live'), onTarget: n('onTarget'), reversal: n('reversal') };
  const declined = c.touching + c.live + c.onTarget + c.reversal;
  const readings = c.moved + c.wrote + declined;
  return { ...c, declined, readings, ran: c.inactive + readings > 0 };
}

export const known = (faith, cand) => faith.length >= MIN_SAMPLES && cand.length >= MIN_SAMPLES;

export const cmpKnown = (faith, cand) => (known(faith, cand) ? cmp(faith, cand) : 'undecided');

export const lookKnown = (faith, cand) => (known(faith, cand) ? look(faith, cand) : 'undecided');

export function tally(rs) {
  const ok = rs.filter((r) => refusal(r) === null);
  return { accepted: ok.length, jitter: ok.filter((r) => reduce(r).jitter).length };
}

export const ARMS = Object.freeze(['orig', 'base', 'lock', 'pin']);

export const LOCK_CSS = 'html.fw-lock{overflow:hidden!important;overscroll-behavior:none!important;touch-action:none!important}';

export const MAX_RESTARTS = 2;

export const serveTag = (restarts) => (restarts === 0 ? 'serve' : `serve-r${restarts}`);

export const repOrder = (rep) => (rep % 2 === 0 ? ['base', 'lock', 'pin', 'orig'] : ['pin', 'lock', 'base', 'orig']);

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
    const base = { n: i + 1, arm: r.arm, rep: r.rep ?? null, rest: restRow(r), pin: r.pin ? { seen: r.pin.seen, ...traceCounts(r.pin.entries.map((e) => e[0])), liveWrites: pinLiveWrites(r.pin.entries) } : null };
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
      locks: kept.map((k) => k.lock), calls: kept.map((k) => k.openCalls), unrestored: kept.filter((k) => k.openCalls === 0).length,
      fightRuns: kept.map((k) => [k.lock, k.frameFights]), eventFightRuns: kept.map((k) => [k.lock, k.eventFights]), restoreRuns: kept.map((k) => [k.lock, k.restores]),
    };
  }
  const { orig, base, lock, pin } = arms;
  return {
    arms,
    windows: windowsOf(rows),
    verdicts: {
      lockVsBase: { fights: lockedCmp(base.fightRuns, lock.fightRuns), restores: lockedCmp(base.restoreRuns, lock.restoreRuns), eventFights: lockedCmp(base.eventFightRuns, lock.eventFightRuns) },
      baseVsOrig: { fights: lockedCmp(orig.fightRuns, base.fightRuns), restores: lockedCmp(orig.restoreRuns, base.restoreRuns) },
      pinVsBase: { fights: lockedCmp(base.fightRuns, pin.fightRuns), restores: lockedCmp(base.restoreRuns, pin.restoreRuns), eventFights: lockedCmp(base.eventFightRuns, pin.eventFightRuns) },
      pinVsOrig: { fights: lockedCmp(orig.fightRuns, pin.fightRuns) },
      ranked: Object.fromEntries(ARMS.map((id) => [id, rankedOf(arms[id].fightRuns)])),
      rest: Object.fromEntries(ARMS.map((id) => [id, restTallyOf(rows, id)])),
      pinRest: restCmp(restTallyOf(rows, 'base'), restTallyOf(rows, 'pin')),
      look: lookKnown(base.displaced, lock.displaced),
      pinLook: lookKnown(base.displaced, pin.displaced),
      pinWrites: pin.accepted === 0 ? 'undecided' : pin.unrestored === 0 ? 'every run wrote' : `${pin.unrestored} of ${pin.accepted} runs never wrote (their fights are 0 by definition)`,
    },
  };
}

const table = (head, body) => [head, '|' + head.split('|').slice(1, -1).map(() => '---').join('|') + '|', ...body];

const lookText = (l) => (l === 'same' ? 'same look' : l === 'change' ? 'look change' : 'undecided');

export function markdown(s) {
  const head = '| arm | windows | push failed | push failure reasons | refused | accepted | jitter runs | frame fights per run | frame reversals per run | displaced frames per run | restores per run | event fights per run | stored lock per run | open scrollTo calls per run | runs with no open call |';
  const lines = table(head, ARMS.map((id) => {
    const a = s.arms[id];
    return `| ${id} | ${a.windows} | ${a.failed} | ${JSON.stringify(a.failures)} | ${JSON.stringify(a.refused)} | ${a.accepted} | ${a.jitterRuns} | ${a.fights.join(' ')} | ${a.reversals.join(' ')} | ${a.displaced.join(' ')} | ${a.restores.join(' ')} | ${a.eventFights.join(' ')} | ${a.locks.map((l) => l ?? 'none').join(' ')} | ${a.calls.join(' ')} | ${a.unrestored} |`;
  }));
  const wins = s.windows ?? [];
  if (wins.length) {
    lines.push('', ...table('| window | arm | rep | state | reason | open frames | reversals | fights | displaced | restores | stored lock | rest | gap to goal (px) | settle after lift (ms) |',
      wins.map((w) => `| ${w.n} | ${w.arm} | ${w.rep ?? ''} | ${w.state} | ${w.reason ?? ''} | ${w.openFrames ?? ''} | ${w.reversals ?? ''} | ${w.fights ?? ''} | ${w.displaced ?? ''} | ${w.restores ?? ''} | ${w.state === 'open' ? (w.lock ?? 'none') : ''} | ${w.rest?.cls ?? ''} | ${w.rest ? w.rest.gap10 / 10 : ''} | ${w.rest?.settle10 == null ? '' : Math.round(w.rest.settle10 / 10)} |`)));
    const traced = wins.filter((w) => w.pin);
    if (traced.length) {
      lines.push('', ...table('| window | arm | pin calls seen | inactive | touches | due | moved | writes | declined: touching | live | onTarget | reversal | live writes | ran |',
        traced.map((w) => `| ${w.n} | ${w.arm} | ${w.pin.seen ?? ''} | ${w.pin.inactive} | ${w.pin.touches} | ${w.pin.due} | ${w.pin.moved} | ${w.pin.wrote} | ${w.pin.touching} | ${w.pin.live} | ${w.pin.onTarget} | ${w.pin.reversal} | ${w.pin.liveWrites} | ${w.pin.ran ? 'yes' : 'no'} |`)));
    }
  }
  const v = s.verdicts;
  lines.push('', rankedText(v.ranked));
  lines.push('', `lock vs base: fights ${v.lockVsBase.fights}, restores ${v.lockVsBase.restores}, event fights ${v.lockVsBase.eventFights}; base vs orig: fights ${v.baseVsOrig.fights}, restores ${v.baseVsOrig.restores}; look class of the candidate: ${lookText(v.look)}`);
  lines.push('', `rest position (Lean restOf; windows that reached the end and rested within 10 px of it, of the windows that reached it): ${ARMS.map((id) => `${id} ${v.rest[id].rested} of ${v.rest[id].reached}`).join(', ')}; pin vs base by position: ${v.pinRest} (${cmpVerdict(v.pinRest)})`);
  lines.push('', `pin vs base: fights ${v.pinVsBase.fights}, restores ${v.pinVsBase.restores}, event fights ${v.pinVsBase.eventFights}; pin vs orig: fights ${v.pinVsOrig.fights}; look class of the pin: ${lookText(v.pinLook)}; pin writes: ${v.pinWrites}`);
  return lines.join('\n');
}

export function acrossReport(jobs) {
  const per = jobs.map(({ label, rows }) => {
    const s = summarize(rows);
    const pinWins = s.windows.filter((w) => w.arm === 'pin' && w.pin);
    const cmp = s.verdicts.pinVsBase.fights;
    return { label, rows, cmp, verdict: pinVerdict(cmp), base: s.arms.base.fights, pin: s.arms.pin.fights, locked: s.verdicts.ranked,
      pinWindows: pinWins.length, writes: pinWins.reduce((a, w) => a + w.pin.wrote, 0), liveWrites: pinWins.reduce((a, w) => a + w.pin.liveWrites, 0) };
  });
  const cs = per.map((j) => j.cmp);
  const rest = restReport(per.map((j) => ({ label: j.label, rows: j.rows, liveWrites: j.liveWrites })));
  return { jobs: per.map(({ rows, ...j }) => j), decisive: decisive(cs.map(pinVerdict)), need: agreeNeeded(decisive(cs.map(pinVerdict))), across: acrossPin(cs), rest, windows: per.map((j) => ({ label: j.label, rows: j.rows })) };
}

export function acrossMarkdown(a) {
  const body = a.jobs.map((j) => `| ${j.label} | ${j.cmp} | ${j.verdict} | ${j.base.join(' ') || '-'} | ${j.pin.join(' ') || '-'} | ${j.locked.base.ranked} of ${j.locked.base.runs} | ${j.locked.pin.ranked} of ${j.locked.pin.runs} | ${j.pinWindows} | ${j.writes} | ${j.liveWrites} |`);
  return [...table('| job | pin vs base fights | verdict (first = base fewer) | base fights | pin fights | base locked | pin locked | pin windows | pin writes | pin live writes |', body),
    '', `across jobs (pin vs base, Lean acrossPin): ${a.across}; decisive jobs ${a.decisive} of ${a.jobs.length}, minSamples ${MIN_SAMPLES}, agreement needed ${a.need}`,
    '', restMarkdown(a.rest), '', ...restWindowsMarkdown(a.windows)].join('\n');
}
