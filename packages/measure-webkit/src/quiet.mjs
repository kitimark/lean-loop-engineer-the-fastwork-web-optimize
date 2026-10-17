// webkit-quiet: is the per-step jitter of the WebKit counts host load, or the engine?
// Dose-response design, one Simulator session: after the discarded warm-up load, `reps` rounds; each round runs every arm once,
// in a rotated order (so an arm is not always first or last), each pass from its own fresh load. An arm = `burners` busy-loop
// processes on the Mac while the stepped scroll runs (0 = the plain pass). Per pass the host is recorded outside the page:
// `top` at 1 Hz (CPU idle, load, top processes) and the harness timer lag (scrollrun.mjs). Orchestration and recording only;
// the comparisons are reduce.mjs / fwcore, the rule is Fw.Measure.Quiet.
import { loadFresh } from './page.mjs';
import { loadStamp } from './load.mjs';
import { reconnect } from './wip.mjs';
import { attempts } from './timeouts.mjs';
import { scrollRun } from './scrollrun.mjs';
import { warmUpLoad } from './perstep.mjs';
import { topSampler, burners } from './hostmon.mjs';

/** Arm order of round r: the list rotated by r (round 0 = as given). */
export const rotate = (arms, r) => arms.map((_, i) => arms[(i + r) % arms.length]);

export async function quietPasses(ctx, { arms, reps, clock, settleMs, step, framesPerStep, log, warmup = 1, mode = 'base' }) {
  for (let w = 0; w < warmup; w++) await warmUpLoad(ctx, { clock, settleMs, step, framesPerStep, log, w, warmup });
  const passes = [];
  for (let rep = 0; rep < reps; rep++) {
    for (const nb of rotate(arms, rep)) {
      let scroll, host;
      const load = { start: loadStamp() };
      for (let attempt = 1; ; attempt++) {
        let b = null, sampler = null;
        try {
          await loadFresh(ctx.c, { clock, settleMs, timers: mode.includes('hold') ? 'hold' : 'live' });
          sampler = topSampler();
          b = burners(nb);
          scroll = await scrollRun(ctx.c, { step, framesPerStep, mode });
          b.stop(); b = null;
          host = { top: await sampler.stop() };
          break;
        } catch (e) {
          b?.stop();
          await sampler?.stop();
          if (attempt >= attempts()) throw e;
          log(`  arm ${nb} attempt ${attempt} failed (${e.message}); reconnecting and retrying from a fresh load`);
          await reconnect(ctx, { log });
        }
      }
      load.end = loadStamp();
      const idle = host.top.filter((s) => s.t >= scroll.wall.start && s.t <= scroll.wall.end + 1500).map((s) => s.idle);
      const meanIdle = idle.length ? Math.round(idle.reduce((a, b) => a + b, 0) / idle.length * 10) / 10 : null;
      const t = scroll.reduced.total;
      log(`round ${rep + 1}/${reps} burners ${nb}: ${scroll.ys.length} steps, wall ${scroll.scrollWallMs} ms, top idle ${meanIdle}% (${idle.length} samples), layout ${t.Layout} paint ${t.Paint} raf ${t.FireAnimationFrame} timer ${t.TimerFire}`);
      passes.push({ rep, arm: nb, scroll, host, load });
    }
  }
  return passes;
}
