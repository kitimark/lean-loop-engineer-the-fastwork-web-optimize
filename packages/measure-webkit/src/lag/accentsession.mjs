import { TargetLostError } from '../inspector.mjs';
import { swapCapture, jobMeta } from './swapprobe.mjs';
import { zoneCapture } from './zoneprobe.mjs';
import { retrying, vmShift } from './freezesession.mjs';
import { laneUnits, unitFits } from './swap.mjs';

export const ESTIMATE_MS = 180000;
const DRAW = (on) => ({ on, mode: 'draw' });

export function parseUnit(unit) {
  const m = /^(swap|zone):(faithful|nolayout|full)(-frozen)?-([ab])$/.exec(unit);
  if (!m) throw new Error(`unknown lane unit ${JSON.stringify(unit)}`);
  return { kind: m[1], arm: m[2], frozen: !!m[3], slot: m[4], name: unit.slice(m[1].length + 1) };
}

export async function accentSession(ctx, { passes, clock, settleMs, step, framesPerStep, log, accent, save }, deps = {}) {
  const { swapCapture: swap = swapCapture, zoneCapture: zone = zoneCapture, retrying: retry = retrying, shift = vmShift(), now = Date.now, estimateMs = ESTIMATE_MS } = deps;
  if (!accent) throw new Error('the accent session needs the accent setup (--accent --cost on|only with --site)');
  const out = [], failed = [];
  let targetLost = false;
  const result = () => ({ schema: 'fw.webkit.lag/1', step, framesPerStep, geometry: null, passes: out.filter((p) => Object.keys(p.cost.accent.captures).length + Object.keys(p.cost.accent.zones).length > 0), failed, ...(targetLost ? { targetLost } : {}) });
  const keep = () => save?.(result());
  const restore = async () => { ctx.setArm(accent.home.id); await ctx.c.evaluate(`history.replaceState(null, '', ${JSON.stringify('/' + accent.home.search)}); 1`); };
  const t0 = now();
  for (let i = 0; i < passes; i++) {
    const rec = { schema: 'fw.webkit.lag.accent/1', job: { ...jobMeta(), pass: i + 1 }, units: laneUnits(shift), captures: {}, zones: {}, failed: [], skipped: [] };
    out.push({ cost: { accent: rec } });
    let longest = 0;
    try {
      for (const [j, unit] of rec.units.entries()) {
        if (!unitFits(now() - t0, Math.max(estimateMs, longest))) {
          rec.skipped = rec.units.slice(j);
          log(`  lane budget: skipping ${rec.skipped.length} units from ${unit}`);
          break;
        }
        const u = parseUnit(unit), began = now();
        try {
          const arm = accent.arms[u.arm];
          if (u.kind === 'swap') {
            rec.captures[u.name] = await retry(ctx, unit, log, () => swap(ctx, arm, { clock, settleMs, freeze: u.frozen ? DRAW(true) : null }));
            const c = rec.captures[u.name];
            log(`  ${unit}: ${c.ws.length} windows (${c.why}), valid ${c.valid.filter(Boolean).length}, layout in swaps ${c.cells.filter((x) => x[0].startsWith('swap:') && x[1] === 'Layout').map((x) => x[2]).join(',')}`);
          } else {
            const align = u.slot === 'a';
            const z = await retry(ctx, unit, log, () => zone(ctx, arm, { clock, settleMs, step, framesPerStep, freeze: DRAW(u.frozen), align }));
            rec.zones[u.name] = { ...z, job: { ...jobMeta(), pass: i + 1 } };
            log(`  ${unit}: layout ${z.layout} paint ${z.paint} over ${z.frames} frames (accent ${z.accentStart}, ${z.accentChanges} class changes)`);
          }
        } catch (e) {
          if (e instanceof TargetLostError) throw e;
          rec.failed.push(`${unit}: ${e.message}`);
          failed.push(`pass ${i + 1} ${unit}: ${e.message}`);
          log(`  ${failed.at(-1)}`);
        }
        longest = Math.max(longest, now() - began);
        keep();
      }
      await restore();
    } catch (e) {
      targetLost = e instanceof TargetLostError;
      failed.push(`pass ${i + 1}: ${e.message}`);
      log(`  ${failed.at(-1)}`);
      keep();
      break;
    }
    keep();
    log(`pass ${i + 1}/${passes} accent: ${Object.keys(rec.captures).length} swap + ${Object.keys(rec.zones).length} zone captures, ${rec.failed.length} failed, ${rec.skipped.length} skipped`);
  }
  return result();
}
