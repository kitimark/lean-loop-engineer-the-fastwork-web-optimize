// Determinism experiment: the same census, scripted scroll and seek fixture, R times, each from a fresh page load
// in one Simulator boot; then classify every count type. Only orchestration and formatting live here; the
// comparison itself is reduce.mjs (the one pure module, slated for a Lean spec).
import { loadFresh, pageInfo, scrollHold } from './page.mjs';
import { loadStamp } from './load.mjs';
import { navigateTab, reconnect } from './wip.mjs';
import { attempts } from './timeouts.mjs';
import { PASS_RETRY_S, SCROLL_RETRY_S, afterFailure, afterPass, centi, stepGate } from './sim-host.mjs';
import { censusAt } from './census.mjs';
import { scrollRun } from './scrollrun.mjs';
import { seekExperiment } from './seek.mjs';
import { COUNT_TYPES, TOL, classify, symDiff, zones, layerKey } from './reduce.mjs';

/** Resolve `max` in a state list against the page's maxY. */
export const resolveStates = (spec, maxY) => String(spec).split(',').map((s) => (s.trim() === 'max' ? maxY : Number(s))).filter((n) => Number.isFinite(n));

/** The offsets pass 1 read, as a state list for the later passes: `max` is the page height of one load, and that height differs between loads. */
export const pinStates = (pass) => pass.census.map((c) => c.requestedY).join(',');

/**
 * Scroll to the top and let the page see it before a reload: a reload restores the saved scroll position, and a page that
 * loads deep mounts its scroll-mounted parts (the morph panel) and keeps them after the census scrolls back up.
 */
export const atTop = (c) => scrollHold(c, 0, { holdMs: 0 });

/** One pass of everything on one fresh load each (census states, then scroll, then optionally seek). */
export async function onePass(ctx, { states, clock, settleMs, holdMs, paintWindowMs, step, framesPerStep, seek, seekNs, log, mode = 'base' }) {
  // an earlier pass may have left the tab on the seek fixture: go back to the snapshot page first
  if (new URL(await ctx.c.evaluate('location.href')).pathname !== '/') ctx.setClient(await navigateTab(ctx.c, ctx.url));
  const load = { start: loadStamp() };
  let c = ctx.c;
  await atTop(c);
  await loadFresh(c, { clock, settleMs });
  const loadScrollY = await c.evaluate('Math.round(scrollY)');
  log(`  scroll position after the load: ${loadScrollY}`);
  const info = await pageInfo(c);
  const ys = resolveStates(states, info.maxY);
  const census = [];
  for (const y of ys) { const cen = await censusAt(c, y, { holdMs, paintWindowMs }); census.push(cen); log(`  census y=${cen.scrollY}: ${cen.layerCount} layers, ${(cen.memoryBytes / 1e6).toFixed(1)} MB, paint delta ${cen.paintDeltaTotal}`); }
  let scroll;
  const gate = stepGate();
  for (let attempt = 1; ; attempt++) {
    await ctx.check?.();
    try { await loadFresh(c, { clock, settleMs, timers: mode.includes('hold') ? 'hold' : 'live' }); scroll = await scrollRun(c, { step, framesPerStep, mode }); break; } catch (e) {
      if (!afterFailure(attempt, attempts(), gate.elapsedS(), SCROLL_RETRY_S, gate.boundS)) { log(`  scroll attempt ${attempt} failed and no retry fits (${attempt}/${attempts()} tries, ${gate.elapsedS()} s of ${gate.boundS ?? 'no'} s bound)`); throw e; }
      log(`  scroll attempt ${attempt} failed (${e.message}); reconnecting and retrying from a fresh load`);
      await reconnect(ctx, { log });
      c = ctx.c;
    }
  }
  const t = scroll.reduced.total;
  log(`  scroll: ${scroll.ys.length} steps, wall ${scroll.scrollWallMs} ms, style ${t.RecalculateStyles} layout ${t.Layout} paint ${t.Paint} composite ${t.Composite}`);
  let seekRes = null;
  if (seek) {
    const r = await seekExperiment(c, `${ctx.base}/__fixtures/seek.html`, { ns: seekNs, log: (s) => log(`  seek ${s}`) });
    ctx.setClient(r.conn);
    seekRes = r.rows;
  }
  load.end = loadStamp();
  log(`  host load1 ${load.start.load1} -> ${load.end.load1}, cpu idle ${load.start.idle}% -> ${load.end.idle}%`);
  return { info, census, scroll, seek: seekRes, load, loadScrollY };
}

/**
 * onePass, retried from a fresh load after a reconnect when it throws (a Simulator reply can stall for a minute on a
 * loaded host; each pass starts from its own fresh load, so a retried pass is the same measurement). Attempts: FW_WK_ATTEMPTS.
 */
export async function onePassRetrying(ctx, opts) {
  const gate = stepGate();
  for (let attempt = 1; ; attempt++) {
    await ctx.check?.();
    let pass;
    try { pass = await onePass(ctx, opts); } catch (e) {
      if (!afterFailure(attempt, attempts(), gate.elapsedS(), PASS_RETRY_S, gate.boundS)) { opts.log(`  pass attempt ${attempt} failed and no retry fits (${attempt}/${attempts()} tries, ${gate.elapsedS()} s of ${gate.boundS ?? 'no'} s bound)`); throw e; }
      opts.log(`  pass attempt ${attempt} failed (${e.message}); reconnecting and repeating the pass from a fresh load`);
      await reconnect(ctx, { log: opts.log });
      continue;
    }
    const v = afterPass(centi(pass.load.start.load1), centi(pass.load.end.load1), attempt, attempts(), gate.elapsedS(), PASS_RETRY_S, gate.boundS);
    if (v === 'count') return pass;
    if (v === 'refuse') throw new Error(`host load1 ${pass.load.start.load1} -> ${pass.load.end.load1} is past the ceiling and no repeat fits: the pass is not counted`);
    opts.log(`  host load1 ${pass.load.start.load1} -> ${pass.load.end.load1} is past the ceiling; repeating the pass from a fresh load`);
  }
}

/** Sorted layer-reason names seen in the census of any of the passes (rows `layers with reason X` exist per name). */
export const reasonNames = (passes) => [...new Set(passes.flatMap((p) => p.census.flatMap((c) => Object.keys(c.reasonCounts))))].sort();

/**
 * Classification rows from R passes. `reasons` fixes the set of reason rows (default: the reasons seen in these passes);
 * `merge` passes the union over all sessions so that every session yields the same rows in the same order.
 */
export function classifyPasses(passes, { reasons = reasonNames(passes) } = {}) {
  const rows = [];
  const add = (family, metric, level, runs, tol) => rows.push({ family, metric, level, ...classify(runs, tol) });
  const ys = passes[0].census.map((c) => c.requestedY);
  const census = (f) => passes.map((p) => p.census.map(f));
  add('census', 'layerCount', 'per state', census((c) => c.layerCount), TOL.census);
  ys.forEach((y, s) => {
    add('census', 'layerCount', `y=${y}`, passes.map((p) => [p.census[s].layerCount]), TOL.census);
    add('census', 'backing memory bytes (sum)', `y=${y}`, passes.map((p) => [p.census[s].memoryBytes]), TOL.memory);
  });
  add('census', 'backing memory bytes (sum)', 'per state', census((c) => c.memoryBytes), TOL.memory);
  for (const r of reasons) add('census', `layers with reason ${r}`, 'per state', census((c) => c.reasonCounts[r] || 0), TOL.census);
  add('census', 'paintCount (sum, cumulative)', 'per state', census((c) => c.paintCountTotal), TOL.paint);
  add('census', `paintCount delta in a ${passes[0].census[0].paintWindowMs} ms window`, 'per state', census((c) => c.paintDeltaTotal), TOL.paint);
  const keys = passes.map((p) => p.census.map((c) => c.layers.map(layerKey)));
  const diffs = passes.map((_, i) => ys.map((__, s) => (i === 0 ? 0 : symDiff(keys[0][s], keys[i][s]))));
  add('census', 'layer set (name, bounds, bytes, reasons)', 'per state, symmetric difference vs run 1', diffs, TOL.exact);
  const red = passes.map((p) => p.scroll.reduced);
  const types = [...COUNT_TYPES, 'paintArea'];
  for (const t of types) add('scroll', t, 'total', red.map((r) => [r.total[t]]), TOL.total);
  const zs = passes.map((p) => zones(p.scroll.ys, p.scroll.reduced.perStep, p.scroll.reduced.perStepPaintArea));
  for (const [j, t] of COUNT_TYPES.entries()) add('scroll', t, 'per 500 px zone', zs.map((z) => z.map((o) => o.counts[j])), TOL.zone);
  add('scroll', 'paintArea', 'per 500 px zone', zs.map((z) => z.map((o) => o.paintArea)), TOL.zone);
  for (const [j, t] of COUNT_TYPES.entries()) add('scroll', t, 'per step', red.map((r) => r.perStep.map((row) => row[j])), TOL.step);
  add('scroll', 'paintArea', 'per step', red.map((r) => r.perStepPaintArea), { absTol: 0, relTol: 0.1 });
  if (passes.every((p) => p.seek)) {
    passes[0].seek.forEach((row, i) => {
      for (const arm of ['free', 'seeked']) {
        for (const t of ['RecalculateStyles', 'Layout', 'Paint', 'Composite']) {
          add('seek', `n=${row.n} ${arm} ${t}`, 'total', passes.map((p) => [p.seek[i][arm].reduced.total[t]]), TOL.total);
        }
      }
    });
  }
  return rows;
}

export function markdownTable(rows) {
  const lines = ['| family | count type | level | class | cells | differing | max spread |', '|---|---|---|---|---|---|---|'];
  for (const r of rows) lines.push(`| ${r.family} | ${r.metric} | ${r.level} | **${r.cls}** | ${r.cells} | ${r.differingCells ?? '-'} | ${r.maxSpread ?? '-'} |`);
  return lines.join('\n');
}
