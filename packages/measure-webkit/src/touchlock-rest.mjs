import { acrossDecisive, agreeNeeded, decisive } from '../../gate-breakpoints/src/smooth/reduce.mjs';

export const REST_TOL10 = 100;

export const REST_MARGIN = 3;

export const MIN_REACHED = 3;

export const goalOf = (w) => (w.target10 == null ? w.max10 : Math.min(w.target10, w.max10));

export const gapOf = (w) => Math.abs(w.final10 - goalOf(w));

export function restOf(w) {
  const g = goalOf(w);
  if (w.peak10 + REST_TOL10 < g) return 'notReached';
  if (gapOf(w) <= REST_TOL10) return 'atEnd';
  return g < w.final10 ? 'over' : 'short';
}

export function targetOf(seen) {
  for (let i = seen.length - 1; i >= 0; i--) if (seen[i] != null) return seen[i];
  return null;
}

export function arrival(final, fs) {
  let i = fs.length;
  while (i > 0 && Math.abs(fs[i - 1][0] - final) <= REST_TOL10) i--;
  return i < fs.length ? fs[i][1] : null;
}

export const touchEnd10 = (ev0, firstScroll, swipe) => Math.max(0, ev0 + 10 * swipe - 10 * firstScroll);

export function settle10(touchEnd, final, fs) {
  const a = arrival(final, fs);
  return touchEnd == null || a == null ? null : Math.max(0, a - touchEnd);
}

export function tallyRest(classes) {
  const notReached = classes.filter((c) => c === 'notReached').length;
  return { rested: classes.filter((c) => c === 'atEnd').length, reached: classes.length - notReached };
}

export function restCmp(base, pin) {
  if (base.reached < MIN_REACHED || pin.reached < MIN_REACHED) return 'undecided';
  const prod = pin.reached * base.reached;
  const d = REST_MARGIN * (pin.rested * base.reached - base.rested * pin.reached);
  if (prod <= d) return 'pinBetter';
  if (d <= -prod) return 'pinWorse';
  return 'same';
}

const CMP_VERDICT = Object.freeze({ pinBetter: 'second', pinWorse: 'first', same: 'same', undecided: 'insufficient' });

export const cmpVerdict = (c) => CMP_VERDICT[c];

export const jobVerdict = ([cmp, live]) => (live > 0 && cmp === 'pinBetter' ? 'insufficient' : cmpVerdict(cmp));

export const acrossRest = (jobs) => acrossDecisive(jobs.map(jobVerdict));

export const restDecisive = (jobs) => decisive(jobs.map(jobVerdict));

export const restNeed = (jobs) => agreeNeeded(restDecisive(jobs));

export function winOf(row) {
  if (!row.frames?.length || row.maxY10 == null || row.finalY10 == null) return null;
  const seen = (row.pin?.entries ?? []).map((e) => (e[3] == null ? null : Math.round(e[3] * 10)));
  return { max10: row.maxY10, final10: row.finalY10, peak10: row.frames.reduce((m, f) => Math.max(m, f[0]), -Infinity), target10: targetOf(seen) };
}

export function touchEndOf(row) {
  const ev0 = row.events?.[0]?.[2];
  const fs = row.q2?.firstScrollMs;
  const sw = row.obs?.swipeAt;
  return ev0 == null || fs == null || sw == null ? null : touchEnd10(Math.round(ev0 * 10), fs, sw);
}

export function restRow(row) {
  const w = winOf(row);
  if (!w) return null;
  const settle = settle10(touchEndOf(row), w.final10, row.frames.map((f) => [f[0], Math.round(f[2] * 10)]));
  return { cls: restOf(w), gap10: gapOf(w), goal10: goalOf(w), final10: w.final10, settle10: settle };
}

export const restTallyOf = (rows, arm) => tallyRest(rows.filter((r) => r.arm === arm).map(restRow).filter(Boolean).map((r) => r.cls));

export function restReport(jobs, arms = ['base', 'lock', 'pin']) {
  const per = jobs.map(({ label, rows, liveWrites }) => {
    const t = Object.fromEntries(arms.map((a) => [a, restTallyOf(rows, a)]));
    const cmp = restCmp(t.base, t.pin);
    return { label, tally: t, cmp, live: liveWrites, verdict: jobVerdict([cmp, liveWrites]), vsLock: restCmp(t.lock, t.pin) };
  });
  const js = per.map((j) => [j.cmp, j.live]);
  return { jobs: per, decisive: restDecisive(js), need: restNeed(js), across: acrossRest(js) };
}

const frac = (t) => `${t.rested} of ${t.reached}`;

export function restMarkdown(r) {
  const head = '| job | base rests at the end | lock | pin | pin vs base | pin live writes | verdict (second = pin rests better) | pin vs lock |';
  const rows = r.jobs.map((j) => `| ${j.label} | ${frac(j.tally.base)} | ${frac(j.tally.lock)} | ${frac(j.tally.pin)} | ${j.cmp} | ${j.live} | ${j.verdict} | ${j.vsLock} |`);
  return [head, '|---|---|---|---|---|---|---|---|', ...rows, '',
    `across jobs (pin vs base by rest position, Lean acrossRest): ${r.across}; decisive jobs ${r.decisive} of ${r.jobs.length}, agreement needed ${r.need}, tolerance ${REST_TOL10 / 10} px, margin ${REST_MARGIN}, floor ${MIN_REACHED} reached windows per arm`].join('\n');
}

export function restWindowsMarkdown(rows) {
  const head = '| job | arm | rep | rest | gap to goal (px) | final (px) | goal (px) | settle after lift (ms) |';
  const body = [];
  for (const { label, rows: rs } of rows) {
    for (const r of rs) {
      const x = restRow(r);
      if (x) body.push(`| ${label} | ${r.arm} | ${r.rep} | ${x.cls} | ${x.gap10 / 10} | ${x.final10 / 10} | ${x.goal10 / 10} | ${x.settle10 == null ? '' : Math.round(x.settle10 / 10)} |`);
    }
  }
  return [head, '|---|---|---|---|---|---|---|---|', ...body];
}
