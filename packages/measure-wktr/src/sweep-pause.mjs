// TS stand-in of Lean Fw.Device.SweepPause (lean/Fw/Device/SweepPause.lean), replayed against packages/contracts/golden/device/sweep-pause.jsonl.
// The reducer from a WKTR accel report (arms sw-*) to the Lean Job is glue and is not golden-replayed.

const ROUND = ['sw-idle', 'sw-idle-p', 'sw-flip', 'sw-flip-p'];
const BACK = ['sw-idle', 'sw-idle-p', 'sw-flip-p', 'sw-flip'];
const timed = (xs) => xs.map((a) => `${a}-t`);
export const SWEEP_ARMS = ['sw-warm', ...ROUND, ...BACK, ...timed(ROUND), ...timed(BACK)];

export const C = { idleOnMin: 150, idleOffMax: 25, explainMin: 750, notMax: 250, minStyleUs: 100, minValid: 2 };

export const rpf100 = (a) => (a.frames === 0 ? 0 : Math.floor((a.recalcs * 100) / a.frames));
export const styleUsPerFrame = (a) => (a.styleFrames === 0 ? 0 : Math.floor(a.styleUs / a.styleFrames));
export const dropPm = (u, p) => (u === 0 ? 0 : Math.floor(((u - p) * 1000) / u));

export const rpfDrop = (j) => dropPm(rpf100(j.flipU), rpf100(j.flipP));
export const styleDrop = (j) => dropPm(styleUsPerFrame(j.flipU), styleUsPerFrame(j.flipP));
const hasFrames = (j) => j.flipU.frames > 0 && j.flipP.frames > 0 && j.idleU.frames > 0 && j.idleP.frames > 0;
const styleUsable = (j) => C.minStyleUs <= styleUsPerFrame(j.flipU);
const explainsB = (j) => C.explainMin <= rpfDrop(j) && styleUsable(j) && C.explainMin <= styleDrop(j);
const notSweepB = (j) => rpfDrop(j) < C.notMax && (!styleUsable(j) || styleDrop(j) < C.notMax);

export function why(j) {
  if (!hasFrames(j)) return 'no-frames';
  if (!(C.idleOnMin <= rpf100(j.idleU))) return 'idle-not-on';
  if (!(rpf100(j.idleP) <= C.idleOffMax)) return 'idle-not-off';
  if (explainsB(j)) return 'explains';
  if (notSweepB(j)) return 'not-sweep';
  return 'partial';
}

export const valid = (w) => w === 'explains' || w === 'not-sweep' || w === 'partial';

export function overall(jobs) {
  const ws = jobs.map(why).filter(valid);
  if (ws.length < C.minValid) return 'inconclusive';
  if (ws.every((w) => w === 'explains')) return 'explains';
  if (ws.every((w) => w === 'not-sweep')) return 'not-sweep';
  return 'partial';
}

export const VERDICT_NAME = { explains: 'sweep explains', partial: 'sweep partial', 'not-sweep': 'not the sweep', inconclusive: 'inconclusive' };
export const NEXT_NAME = {
  explains: 'geom-sweep-compositor and a phone session',
  partial: 'element counts per recalc, then geom-sweep-compositor for the sweep share',
  'not-sweep': 'element counts per recalc',
  inconclusive: 'rerun with more valid jobs',
};

const zero = () => ({ windows: 0, frames: 0, recalcs: 0, ms: 0, updSum: 0, flushRc: 0, styleUs: 0, layoutUs: 0 });

/** Per arm name: sums over the rows that ran a window. */
export function armSums(report) {
  const out = {};
  for (const row of report.rows) {
    const st = row.stages?.[0];
    if (!row.sw || !row.engaged || !st) continue;
    const a = (out[row.arm] ??= zero());
    a.windows++;
    a.frames += st.frames;
    a.recalcs += st.recalc ?? 0;
    a.ms += st.ms;
    a.updSum += st.updSum ?? 0;
    a.flushRc += st.flushRc ?? 0;
    a.styleUs += st.styleUs ?? 0;
    a.layoutUs += st.layoutUs ?? 0;
  }
  return out;
}

/** Lean Job of one report: recalcs from the plain arms, style and layout from the -t arms. */
export function jobOf(report) {
  const s = armSums(report);
  const arm = (name) => {
    const p = s[name] ?? zero();
    const t = s[`${name}-t`] ?? zero();
    return { frames: p.frames, recalcs: p.recalcs, styleFrames: t.frames, styleUs: t.styleUs, layoutUs: t.layoutUs };
  };
  return { flipU: arm('sw-flip'), flipP: arm('sw-flip-p'), idleU: arm('sw-idle'), idleP: arm('sw-idle-p') };
}

const f2 = (x) => (x === null ? 'n/a' : (Math.round(x * 100) / 100).toString());

export function sweepTally(report) {
  const s = armSums(report);
  const lines = [];
  for (const name of Object.keys(s).sort()) {
    const a = s[name];
    const idle = name.includes('idle');
    const perSec = a.ms ? 1000 / a.ms : null;
    lines.push(
      `${name}: windows ${a.windows} frames ${a.frames} (${f2(a.frames / a.windows)}/window) recalcs ${a.recalcs} per frame ${f2(a.recalcs / a.frames)} ms ${f2(a.ms / a.windows)}/window`
        + ` upd/frame ${f2(a.updSum / a.frames)} flushRc ${a.flushRc} style us ${a.styleUs} layout us ${a.layoutUs} style us per ${idle ? 'idle second' : 'flip'} ${f2(idle && perSec ? a.styleUs * perSec : a.styleUs / a.windows)}`,
    );
  }
  const idents = report.rows.filter((r) => r.sw).map((r) => `${r.arm}:${r.sw.ident?.n}/${(r.sw.states ?? []).join('+')}/${(r.sw.ttnt ?? []).join('+')}`);
  lines.push(`ident ${[...new Set(idents)].slice(0, 6).join(' ')}`);
  const j = jobOf(report);
  lines.push(`job ${JSON.stringify(j)}`);
  lines.push(`rpf100 flipU ${rpf100(j.flipU)} flipP ${rpf100(j.flipP)} idleU ${rpf100(j.idleU)} idleP ${rpf100(j.idleP)} style us/frame U ${styleUsPerFrame(j.flipU)} P ${styleUsPerFrame(j.flipP)} drops rpf ${rpfDrop(j)} style ${styleDrop(j)} why ${why(j)}`);
  return lines;
}
