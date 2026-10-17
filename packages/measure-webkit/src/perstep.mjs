// Per-step determinism experiment: the same stepped scroll under several drivers (modes), R passes each from a fresh
// load, then a class table per (mode, window, count type, level). Orchestration + formatting only; every comparison is
// reduce.mjs. Windows: `step` = rows between the step marks; `win` = rows from the step's first Composite on
// (experiment (c), computed from the same raw records).
import { loadFresh } from './page.mjs';
import { loadStamp } from './load.mjs';
import { openTab } from './wip.mjs';
import { scrollRun } from './scrollrun.mjs';
import { COUNT_TYPES, TOL, classify, zones, reduceWindows } from './reduce.mjs';

/** One discarded load + scroll (retried once after a reconnect: a Simulator evaluate sometimes stalls right after a reload). */
export async function warmUpLoad(ctx, { clock, settleMs, step, framesPerStep, log, w = 0, warmup = 1 }) {
  for (let attempt = 1; ; attempt++) {
    try {
      await loadFresh(ctx.c, { clock, settleMs, timers: 'live' });
      const s = await scrollRun(ctx.c, { step, framesPerStep, mode: 'base' });
      log(`warm-up ${w + 1}/${warmup} (discarded): style ${s.reduced.total.RecalculateStyles} raf ${s.reduced.total.FireAnimationFrame}`);
      return;
    } catch (e) {
      if (attempt >= 2) throw e;
      log(`  warm-up attempt ${attempt} failed (${e.message}); reconnecting`);
      try { ctx.c.close(); } catch { /* closed */ }
      ctx.setClient(await openTab(ctx.url));
    }
  }
}

/** R passes x modes in one Simulator session; returns [{pass, mode, scroll}] (scroll = scrollRun's object). */
export async function perStepPasses(ctx, { modes, runs, clock, settleMs, step, framesPerStep, log, warmup = 0 }) {
  const out = [];
  // discarded loads at the start of the session: the first load in a freshly booted Simulator runs fewer rAFs and
  // restyles than every later one (MEASURED: FireAnimationFrame 703 vs 729), so it is not a sample of the steady state
  for (let w = 0; w < warmup; w++) await warmUpLoad(ctx, { clock, settleMs, step, framesPerStep, log, w, warmup });
  for (let pass = 0; pass < runs; pass++) {
    for (const mode of modes) {
      let scroll;
      const load = { start: loadStamp() };
      for (let attempt = 1; ; attempt++) {
        try {
          await loadFresh(ctx.c, { clock, settleMs, timers: mode.includes('hold') ? 'hold' : 'live' });
          scroll = await scrollRun(ctx.c, { step, framesPerStep, mode });
          break;
        } catch (e) {
          if (attempt >= 2) throw e;
          log(`  ${mode} attempt ${attempt} failed (${e.message}); reconnecting and retrying from a fresh load`);
          try { ctx.c.close(); } catch { /* closed */ }
          ctx.setClient(await openTab(ctx.url));
        }
      }
      const t = scroll.reduced.total;
      log(`pass ${pass + 1}/${runs} ${mode}: ${scroll.ys.length} steps, wall ${scroll.scrollWallMs} ms, style ${t.RecalculateStyles} layout ${t.Layout} paint ${t.Paint} composite ${t.Composite} timer ${t.TimerFire} raf ${t.FireAnimationFrame}${scroll.noComposite?.length ? ` noComposite@${scroll.noComposite.join(',')}` : ''}`);
      load.end = loadStamp();
      log(`  host load1 ${load.start.load1} -> ${load.end.load1}, cpu idle ${load.start.idle}% -> ${load.end.idle}%`);
      out.push({ pass, mode, scroll, load });
    }
  }
  return out;
}

/** The (mode, window) reductions of one scroll object. */
export function reductions(scroll) {
  return { step: scroll.reduced, win: reduceWindows(scroll.records, scroll.marks, scroll.endTime) };
}

/** Class rows for each mode and window over all given passes (entries {mode, scroll}). */
export function classifyModes(entries) {
  const rows = [];
  const modes = [...new Set(entries.map((e) => e.mode))];
  for (const mode of modes) {
    const mine = entries.filter((e) => e.mode === mode);
    if (mine.length < 2) continue;
    const reds = mine.map((e) => reductions(e.scroll));
    for (const window of ['step', 'win']) {
      const rs = reds.map((r) => r[window]);
      const ys = mine[0].scroll.ys;
      const zs = mine.map((e, i) => zones(e.scroll.ys, rs[i].perStep, rs[i].perStepPaintArea));
      const add = (metric, level, runs, tol) => rows.push({ mode, window, metric, level, passes: mine.length, ...classify(runs, tol) });
      for (const [j, t] of COUNT_TYPES.entries()) {
        add(t, 'total', rs.map((r) => [r.total[t]]), TOL.total);
        add(t, 'per 500 px zone', zs.map((z) => z.map((o) => o.counts[j])), TOL.zone);
        add(t, 'per step', rs.map((r) => r.perStep.map((row) => row[j])), TOL.step);
        add(t, 'per step, exact', rs.map((r) => r.perStep.map((row) => row[j])), TOL.exact);
      }
      void ys;
    }
  }
  return rows;
}

const LEVELS = ['total', 'per 500 px zone', 'per step', 'per step, exact'];
const SHORT = { deterministic: 'det', stable: 'stable', quarantined: 'QUAR' };

/** Markdown: per mode+window, one row per count type with the class at each level and the exact per-step differing cells. */
export function perStepTable(rows) {
  const lines = [];
  const keys = [...new Set(rows.map((r) => `${r.mode}|${r.window}`))];
  for (const key of keys) {
    const [mode, window] = key.split('|');
    const mine = rows.filter((r) => r.mode === mode && r.window === window);
    lines.push(`\n#### mode \`${mode}\`, window \`${window}\` (${mine[0].passes} passes)\n`);
    lines.push('| count | total | per 500 px | per step (tol 1) | per step exact: differing cells of N | max spread |');
    lines.push('|---|---|---|---|---|---|');
    for (const t of COUNT_TYPES) {
      const by = Object.fromEntries(LEVELS.map((l) => [l, mine.find((r) => r.metric === t && r.level === l)]));
      const ex = by['per step, exact'];
      lines.push(`| ${t} | ${SHORT[by.total.cls]} | ${SHORT[by['per 500 px zone'].cls]} | ${SHORT[by['per step'].cls]} | ${ex.differingCells} of ${ex.cells} | ${ex.maxSpread} |`);
    }
  }
  return lines.join('\n');
}
