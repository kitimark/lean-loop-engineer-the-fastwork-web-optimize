// The freeze session (I/O only): per pass the swap pass of both arms and the hero-exit zone scroll, unfrozen and frozen
// (hero.accent frozen from the harness, freeze.mjs) in the same Simulator session, the order of the two states alternating
// with the pass. Output shape fw.webkit.lag/1: passes[].cost.swap (unfrozen), .swapFrozen, .zone {free, frozen}.
import { reconnect } from '../wip.mjs';
import { TargetLostError } from '../inspector.mjs';
import { attempts } from '../timeouts.mjs';
import { swapPass, jobMeta } from './swapprobe.mjs';
import { zoneCapture } from './zoneprobe.mjs';

const STATES = Object.freeze({ free: { on: false }, frozen: { on: true } });

export const stateOrder = (i) => (i % 2 === 0 ? ['free', 'frozen'] : ['frozen', 'free']);
export const alignOrder = (i, j) => ((i + j) % 2 === 0 ? [true, false] : [false, true]);

async function retrying(ctx, name, log, fn) {
  for (let attempt = 1; ; attempt++) {
    await ctx.check?.();
    try { return await fn(); } catch (e) {
      if (attempt >= attempts()) throw e;
      log(`  ${name} attempt ${attempt} failed (${e.message}); reconnecting and repeating from a fresh load`);
      await reconnect(ctx, { log });
    }
  }
}

export async function freezeSession(ctx, { passes, clock, settleMs, step, framesPerStep, log, swap }, deps = {}) {
  const { swapPass: pass = swapPass, zoneCapture: zone = zoneCapture, retrying: retry = retrying } = deps;
  if (!swap) throw new Error('the freeze session needs the swap setup (--swap --cost on|only, target rewrite, a query)');
  const out = [], failed = [];
  let targetLost = false;
  const restore = async () => { ctx.setArm(swap.home.id); await ctx.c.evaluate(`history.replaceState(null, '', ${JSON.stringify('/' + swap.home.search)}); 1`); };
  for (let i = 0; i < passes; i++) {
    const cost = { zone: { free: [], frozen: [] } };
    try {
      for (const state of stateOrder(i)) {
        const key = state === 'free' ? 'swap' : 'swapFrozen';
        cost[key] = await pass(ctx, {
          clock, settleMs, arms: swap.arms, log, flip: i % 2 === 1, freeze: STATES[state], diagArms: ['crop', 'faithful'], pass: i + 1,
          retry: (name, fn) => retry(ctx, `${state} ${name}`, log, fn), restore,
        });
      }
      for (const [j, state] of stateOrder(i).entries()) {
        for (const align of alignOrder(i, j)) {
          try {
            const z = await retry(ctx, `zone ${state}`, log, () => zone(ctx, swap.arms.crop, { clock, settleMs, step, framesPerStep, freeze: STATES[state], align }));
            cost.zone[state].push({ ...z, job: { ...jobMeta(), pass: i + 1 } });
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
      if (cost.swap || cost.swapFrozen) out.push({ cost });
      break;
    }
    out.push({ cost });
    log(`pass ${i + 1}/${passes} freeze: swap ${cost.swap ? 'ok' : 'failed'}, swapFrozen ${cost.swapFrozen ? 'ok' : 'failed'}, zone ${cost.zone.free.length}+${cost.zone.frozen.length}`);
  }
  return { schema: 'fw.webkit.lag/1', step, framesPerStep, geometry: null, passes: out, failed, ...(targetLost ? { targetLost } : {}) };
}
