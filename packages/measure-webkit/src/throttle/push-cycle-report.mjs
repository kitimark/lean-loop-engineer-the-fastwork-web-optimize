import { excludeReason } from './finish-report.mjs';
import { CYCLES, trend, verdictInputs, h1Verdict, h2Verdict, indexSeries, recordCycles, sepArm, SEP_MIN_PASSES } from './push-cycle.mjs';

export const ARM_ORDER = Object.freeze(['original', 'rewrite', 'user']);

const median = (xs) => {
  const s = xs.filter((x) => x !== null && x !== undefined).sort((a, b) => a - b);
  return s.length ? s[Math.floor(s.length / 2)] : null;
};

export function armTable(jobs) {
  const all = jobs.flatMap((j) => (j.passes ?? []).map((p) => ({ ...p, vm: p.vm ?? j.vm, arm: p.profile === 'dwell' ? `${p.arm}@dwell` : p.arm })));
  const present = [...new Set(all.map((p) => p.arm))];
  const arms = [...ARM_ORDER.filter((a) => present.includes(a)), ...present.filter((a) => !ARM_ORDER.includes(a)).sort()];
  return arms.map((arm) => {
    const mine = all.filter((p) => p.arm === arm);
    const usable = mine.filter((p) => excludeReason(p) === null);
    const recs = usable.map((p) => p.rec);
    const cyc = recs.map(recordCycles);
    const nK = Math.max(CYCLES, ...cyc.map((c) => c.length));
    const perK = Array.from({ length: nK }, (_, k) => {
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

/** Per base arm: the Lean cycle-vs-clock verdict over the usable full and dwell passes of every job, and the census reading of the dwell passes. */
export function sepTable(jobs) {
  const all = jobs.flatMap((j) => (j.passes ?? []).map((p) => ({ ...p, vm: p.vm ?? j.vm }))).filter((p) => p.profile);
  const arms = [...new Set(all.map((p) => p.arm))];
  return arms.map((arm) => {
    const mine = all.filter((p) => p.arm === arm);
    const usable = mine.filter((p) => excludeReason(p) === null);
    const lost = (profile) => mine.filter((p) => p.profile === profile && excludeReason(p) !== null).map((p) => `${p.vm} ${excludeReason(p)}`);
    const s50 = sepArm(usable, 50), s34 = sepArm(usable, 34);
    const end = (profile) => usable.filter((p) => p.profile === profile).map((p) => p.census?.at(-1)?.bytes).filter((x) => x != null);
    return { arm, full: usable.filter((p) => p.profile === 'full').length, dwell: usable.filter((p) => p.profile === 'dwell').length,
      jobs: new Set(usable.map((p) => p.vm)).size, lost: { full: lost('full'), dwell: lost('dwell') }, s50, s34, endBytes: { full: end('full'), dwell: end('dwell') } };
  });
}

function sepMd(rows) {
  const out = ['', '## Cycle versus clock (Lean Fw.Measure.PushCycle.sepVerdict; slow frames > 50 ms per cycle, cycles 3 to 5, counted window = open stretch + 8 s)', ''];
  out.push('| Arm | Full passes | Dwell passes | Period full ms | Period dwell ms | Stretch r (permille) | Rate by cycle index | Rate by clock-matched index | Rate of dwell passes | Verdict (> 50 ms) | Verdict (> 34 ms) |', '|---|---|---|---|---|---|---|---|---|---|---|');
  for (const r of rows) out.push(`| ${r.arm} | ${r.full} | ${r.dwell} | ${r.s50.input.periodFull} | ${r.s50.input.periodDwell} | ${r.s50.r} | ${r.s50.rates.idx} | ${r.s50.rates.clk} | ${r.s50.rates.dwell} | ${r.s50.verdict} | ${r.s34.verdict} |`);
  out.push('', `Minimum ${SEP_MIN_PASSES} usable passes per side; a side below it is undecided, never a win. Lost passes: ${rows.map((r) => `${r.arm} full [${r.lost.full.join('; ') || 'none'}] dwell [${r.lost.dwell.join('; ') || 'none'}]`).join(', ')}.`, '');
  out.push('### Census after each cycle of the dwell passes (H4: does memory grow per cycle)', '', '| Arm | Layers | Backing bytes | Layers created | Trend per dwell pass: layers / bytes / created | Mean bytes before / after (full pass) | Mean bytes after (dwell pass) |', '|---|---|---|---|---|---|---|');
  const mean = (xs) => (xs.length ? Math.round(xs.reduce((a, b) => a + b, 0) / xs.length) : 'n/a');
  for (const r of rows) {
    const t = r.s50.trends;
    out.push(`| ${r.arm} | ${r.s50.census.layers} | ${r.s50.census.bytes} | ${r.s50.census.created} | ${t.layers.join(',')} / ${t.bytes.join(',')} / ${t.created.join(',')} | ${mean(r.endBytes.full)} | ${mean(r.endBytes.dwell)} |`);
  }
  out.push('', 'Reading: yes = every dwell pass rises (first cycle below the mean of the rest), no = none rises, mixed = some, few = under 3 passes (Lean `across`).', '');
  return out;
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
  const sep = sepTable(jobs);
  if (sep.length) out.push(...sepMd(sep));
  return out.join('\n');
}
