// Seek-overhead fixture runs: N accelerated (transform + opacity) CSS animations, K steps of two native rAFs,
// once free-running and once with every animation seeked (`animation.currentTime = t_k`) at each step.
// WebKit's `WebAnimation::setCurrentTime` invalidates style for the animation on each seek
// (WebAnimation.cpp l.587-620 @fba976461fc0, cited in PLAN §4.2), so the seeked arm is expected to show per-step
// RecalculateStyles that the free-running arm does not. The difference is the harness-induced share of a count.
// Output schema `fw.webkit.seek/1`: rows {n, layerCount, layersWithAnimationReason, free, seeked}, each arm
// {arm, animations, steps, marks, endTime, records, reduced} (raw part + reduce.mjs reduction).
import { sleep } from './sim.mjs';
import { navigateTab } from './wip.mjs';
import { startTimeline } from './timeline.mjs';
import { markTimes, markTime, reduceSteps } from './reduce.mjs';
import { RAF_HELPER } from './page.mjs';
import { takeCensus } from './census.mjs';

const ARM_JS = (arm, steps, framesPerStep) => `(async () => {
  ${RAF_HELPER}
  const seek = ${arm === 'seeked'};
  if (seek) document.getAnimations().forEach((a) => a.pause());
  performance.mark('wk:begin');
  for (let k = 0; k < ${steps}; k++) {
    performance.mark('wk:s' + k);
    if (seek) { const t = k * 1000 / 60; for (const a of document.getAnimations()) a.currentTime = t; }
    for (let f = 0; f < ${framesPerStep}; f++) await raf();
  }
  performance.mark('wk:end');
  return document.getAnimations().length;
})()`;

async function runArm(c, arm, { steps, framesPerStep }) {
  const tl = await startTimeline(c);
  const animations = await c.runAsync(ARM_JS(arm, steps, framesPerStep), { pollMs: 1000 });
  await sleep(300);
  const records = await tl.stop();
  const marks = markTimes(records, 'wk:s', steps);
  const endTime = markTime(records, 'wk:end');
  if (marks.some((t) => t === null) || endTime === null) throw new Error('step marks missing from the Timeline');
  return { arm, animations, steps, marks, endTime, records, reduced: reduceSteps(records, marks, endTime) };
}

/**
 * Run the fixture for each N in `ns`. `fixtureBase` is the served URL of fixtures/seek.html (no query).
 * Returns {conn, rows}: the last connection (the tab navigates, so the caller's connection dies) and one row per N
 * with both arms and the layer census evidence (layers with the `animation` compositing reason = accelerated).
 */
export async function seekExperiment(c, fixtureBase, { ns = [0, 10, 50, 100], steps = 60, framesPerStep = 2, settleMs = 1500, log = () => {} } = {}) {
  const rows = [];
  let conn = c;
  for (const n of ns) {
    const url = `${fixtureBase}?n=${n}`;
    conn = await navigateTab(conn, url);
    if ((await conn.evaluate('window.__fixtureN')) !== n) throw new Error(`fixture did not load with n=${n}`);
    await sleep(settleMs);
    const cen = await takeCensus(conn, { paintWindowMs: 500, withNames: false });
    const free = await runArm(conn, 'free', { steps, framesPerStep });
    const seeked = await runArm(conn, 'seeked', { steps, framesPerStep });
    rows.push({ n, layerCount: cen.layerCount, layersWithAnimationReason: cen.layers.filter((l) => l.reasons.includes('animation')).length, free, seeked });
    log(`n=${n}: style/step free ${(free.reduced.total.RecalculateStyles / steps).toFixed(2)} seeked ${(seeked.reduced.total.RecalculateStyles / steps).toFixed(2)}`);
  }
  return { conn, rows };
}
