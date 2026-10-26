import { excludeReason } from './finish-report.mjs';
import { CYCLES, trend, verdictInputs, h1Verdict, h2Verdict, indexSeries, recordCycles } from './push-cycle.mjs';

export const ARM_ORDER = Object.freeze(['original', 'rewrite', 'user']);

const median = (xs) => {
  const s = xs.filter((x) => x !== null && x !== undefined).sort((a, b) => a - b);
  return s.length ? s[Math.floor(s.length / 2)] : null;
};

export function armTable(jobs) {
  const all = jobs.flatMap((j) => (j.passes ?? []).map((p) => ({ ...p, vm: p.vm ?? j.vm })));
  const present = [...new Set(all.map((p) => p.arm))];
  const arms = [...ARM_ORDER.filter((a) => present.includes(a)), ...present.filter((a) => !ARM_ORDER.includes(a)).sort()];
  return arms.map((arm) => {
    const mine = all.filter((p) => p.arm === arm);
    const usable = mine.filter((p) => excludeReason(p) === null);
    const recs = usable.map((p) => p.rec);
    const cyc = recs.map(recordCycles);
    const perK = Array.from({ length: CYCLES }, (_, k) => {
      const at = cyc.map((c) => c[k]).filter(Boolean);
      const sumOf = (f) => at.reduce((a, c) => a + (c[f] ?? 0), 0);
      return {
        k, passes: at.length, frames: sumOf('frames'), slow34: sumOf('slow34'), slow50: sumOf('slow50'),
        medianGap: median(at.map((c) => c.medianGap)), viewportChanges: sumOf('viewportChanges'), resizes: sumOf('resizes'),
        vvResizes: sumOf('vvResizes'), fights: at.reduce((a, c) => a + (c.lock?.fights ?? 0), 0), displaced: at.reduce((a, c) => a + (c.lock?.displaced ?? 0), 0),
      };
    });
    const v34 = verdictInputs(recs, 34), v50 = verdictInputs(recs, 50);
    return {
      arm, passes: mine.length, usable: usable.length, jobs: new Set(usable.map((p) => p.vm)).size,
      excluded: mine.map(excludeReason).filter(Boolean), perK,
      trend34: trend(indexSeries(recs, 'slow34').sums), trend50: trend(indexSeries(recs, 'slow50').sums),
      h1_34: { inputs: v34.h1, verdict: h1Verdict(v34.h1) }, h1_50: { inputs: v50.h1, verdict: h1Verdict(v50.h1) },
      h2: { inputs: v34.h2, verdict: h2Verdict(v34.h2) },
    };
  });
}

export function reportMd(jobs) {
  const rows = armTable(jobs);
  const dwell = jobs.find((j) => j.drag)?.drag?.holdMs;
  const out = [`# Push cycles on the Simulator (real touches), dwell ${dwell ?? '?'} ms, ${CYCLES} cycles per pass`, ''];
  for (const r of rows) {
    out.push(`## ${r.arm}: ${r.usable} usable of ${r.passes} passes, ${r.jobs} jobs${r.excluded.length ? `; excluded: ${[...new Set(r.excluded)].join(', ')}` : ''}`, '');
    out.push('| Cycle k | Passes | Frames | Slow >34 ms | Slow >50 ms | Median gap ms | Viewport changes | resize events | visualViewport resizes | Fights | Displaced |', '|---|---|---|---|---|---|---|---|---|---|---|');
    for (const c of r.perK) out.push(`| ${c.k} | ${c.passes} | ${c.frames} | ${c.slow34} | ${c.slow50} | ${c.medianGap ?? 'n/a'} | ${c.viewportChanges} | ${c.resizes} | ${c.vvResizes} | ${c.fights} | ${c.displaced} |`);
    out.push('', `Trend of slow frames over the cycle index: >34 ms ${r.trend34}, >50 ms ${r.trend50} (the Lean model never rises).`);
    out.push(`H1 (slow frames near a viewport change): >34 ms ${r.h1_34.verdict}, >50 ms ${r.h1_50.verdict}; inputs ${JSON.stringify(r.h1_34.inputs)}.`);
    out.push(`H2 (fights per open, later against first): ${r.h2.verdict}; inputs ${JSON.stringify(r.h2.inputs)}.`, '');
  }
  return out.join('\n');
}
