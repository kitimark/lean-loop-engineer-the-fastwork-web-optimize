import { reconnect } from '../wip.mjs';
import { TargetLostError } from '../inspector.mjs';
import { attempts } from '../timeouts.mjs';
import { swapPass, jobMeta } from './swapprobe.mjs';
import { zoneCapture } from './zoneprobe.mjs';

export const statesOf = (mode) => Object.freeze({ free: { on: false, ...(mode ? { mode } : {}) }, frozen: { on: true, ...(mode ? { mode } : {}) } });

export const stateOrder = (i) => (i % 2 === 0 ? ['free', 'frozen'] : ['frozen', 'free']);
export const vmShift = (env = process.env) => Number(/\d+/.exec(env.VM ?? '')?.[0] ?? 0);
export const alignOrder = (i, j) => ((i + j) % 2 === 0 ? [true, false] : [false, true]);

export async function retrying(ctx, name, log, fn) {
  for (let attempt = 1; ; attempt++) {
    await ctx.check?.();
    try { return await fn(); } catch (e) {
      if (attempt >= attempts()) throw e;
      log(`  ${name} attempt ${attempt} failed (${e.message}); reconnecting and repeating from a fresh load`);
      await reconnect(ctx, { log });
    }
  }
}

export async function freezeSession(ctx, { passes, clock, settleMs, step, framesPerStep, log, swap, save, freezeMode }, deps = {}) {
  const STATES = statesOf(freezeMode);
  const { swapPass: pass = swapPass, zoneCapture: zone = zoneCapture, retrying: retry = retrying, shift = vmShift() } = deps;
  if (!swap) throw new Error('the freeze session needs the swap setup (--swap --cost on|only, target rewrite, a query)');
  const out = [], failed = [];
  let targetLost = false;
  const result = () => ({ schema: 'fw.webkit.lag/1', step, framesPerStep, geometry: null, passes: out.filter((p) => p.cost.swap || p.cost.swapFrozen), failed, ...(targetLost ? { targetLost } : {}) });
  const keep = () => save?.(result());
  const restore = async () => { ctx.setArm(swap.home.id); await ctx.c.evaluate(`history.replaceState(null, '', ${JSON.stringify('/' + swap.home.search)}); 1`); };
  for (let i = 0; i < passes; i++) {
    const cost = { zone: { free: [], frozen: [] } };
    out.push({ cost });
    try {
      for (const state of stateOrder(i + shift)) {
        const key = state === 'free' ? 'swap' : 'swapFrozen';
        cost[key] = await pass(ctx, {
          onStart: (o) => { cost[key] = o; }, onUnit: keep,
          clock, settleMs, arms: swap.arms, log, flip: i % 2 === 1, freeze: STATES[state], diagArms: ['crop', 'faithful'], pass: i + 1,
          retry: (name, fn) => retry(ctx, `${state} ${name}`, log, fn), restore,
        });
      }
      for (const [j, state] of stateOrder(i + shift).entries()) {
        for (const align of alignOrder(i + shift, j)) {
          try {
            const z = await retry(ctx, `zone ${state}`, log, () => zone(ctx, swap.arms.crop, { clock, settleMs, step, framesPerStep, freeze: STATES[state], align }));
            cost.zone[state].push({ ...z, job: { ...jobMeta(), pass: i + 1 } });
            keep();
            log(`  zone ${state}${align ? ' aligned' : ''}: layout ${z.layout} paint ${z.paint} (accent ${z.accentStart}, ${z.accentChanges} class changes)`);
          } catch (e) {
            if (e instanceof TargetLostError) throw e;
            failed.push(`pass ${i + 1} zone ${state}: ${e.message}`);
            log(`  ${failed.at(-1)}`);
          }
        }
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
    log(`pass ${i + 1}/${passes} freeze: swap ${cost.swap ? 'ok' : 'failed'}, swapFrozen ${cost.swapFrozen ? 'ok' : 'failed'}, zone ${cost.zone.free.length}+${cost.zone.frozen.length}`);
  }
  return result();
}
