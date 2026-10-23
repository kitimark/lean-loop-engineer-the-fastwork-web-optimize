// Why is the bundled morph arm pixel-identical to the threaded arm at m0.25?
//   node results/gpu-safari/lane/probe-fade.mjs   (macOS Safari, inside a `measure` slot; writes results/gpu-safari/mac-bundled-vs-threaded.json)
// Per arm (faithful, threaded, bundled) and state m: push, pause the effects at elapsedAt(m), read the platform's rect,
// computed opacity and filter, its `--morph-fade`, and how much of its box lies in the viewport. Numbers only, no pixels.
import { writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { openLane, loadArm, sleep } from './session.mjs';
import { FREEZE_EXPR } from '../../../packages/measure-webkit/src/pathpix-page.mjs';
import { PUSH_EXPR, STEP_EXPR, wantEffects } from './sim-capture.mjs';
import { FLAG_ARMS, FAITHFUL, MORPH_M, elapsedAt } from './plan.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..', '..');
const out = join(ROOT, 'results', 'gpu-safari', 'mac-bundled-vs-threaded.json');
const siteDir = join(ROOT, 'apps', 'site', 'dist', 'aot');

const PLATFORM = `(() => {
  const p = document.querySelector('[data-fw="platform"]');
  if (!p) return JSON.stringify({ found: false });
  const r = p.getBoundingClientRect(), cs = getComputedStyle(p);
  const vx = Math.max(0, Math.min(r.right, innerWidth) - Math.max(r.left, 0)), vy = Math.max(0, Math.min(r.bottom, innerHeight) - Math.max(r.top, 0));
  return JSON.stringify({ found: true, rect: [r.left, r.top, r.width, r.height].map((v) => Math.round(v * 100) / 100), inViewportShare: r.width * r.height > 0 ? Math.round(1e4 * vx * vy / (r.width * r.height)) / 1e4 : 0,
    opacity: cs.opacity, filter: cs.filter, morphFade: cs.getPropertyValue('--morph-fade').trim(), morph: getComputedStyle(document.querySelector('[data-fw="nav"]')).getPropertyValue('--morph').trim(),
    animations: p.getAnimations().map((a) => ({ playState: a.playState, progress: a.effect.getComputedTiming().progress })), scrollY: Math.round(scrollY), innerHeight });
})()`;

const arms = [FAITHFUL, ...FLAG_ARMS.filter((a) => a.zone === 'morph')];
const mk = (a) => ({ id: a.id, site: 'rewrite', tree: { dir: siteDir, search: a.search }, search: a.search });
const lane = await openLane({ arms: arms.map(mk), width: 430, height: 932 });
const ex = (e) => lane.wd.expr(e);
const rows = [];
try {
  for (const arm of arms) {
    await loadArm(lane, mk(arm), { settleMs: 2500 });
    const maxY = Number(await ex('document.documentElement.scrollHeight - innerHeight'));
    await ex(`(async () => { scrollTo({ top: ${maxY}, behavior: 'instant' }); await new Promise((r) => requestAnimationFrame(() => r())); return 1; })()`);
    await ex(FREEZE_EXPR); await sleep(400);
    const rest = JSON.parse(await ex(PLATFORM));
    const push = JSON.parse(await ex(PUSH_EXPR));
    for (const m of MORPH_M) {
      const step = JSON.parse(await ex(STEP_EXPR(elapsedAt(m), m)));
      if (step.anims.length !== wantEffects(arm)) throw new Error(`arm ${arm.id}: ${step.anims.length} effects`);
      await sleep(300);
      rows.push({ arm: arm.id, m, elapsedMs: elapsedAt(m), effects: step.anims.length, rest, platform: JSON.parse(await ex(PLATFORM)) });
    }
  }
} finally {
  await lane.close();
}
writeFileSync(out, JSON.stringify({ schema: 'fw.gpu-safari-fade-probe/1', lane: 'macos-safari', rows }, null, 1) + '\n');
for (const r of rows) console.error(`${r.arm} m${r.m}: effects ${r.effects} opacity ${r.platform.opacity} filter ${r.platform.filter} fade var ${r.platform.morphFade} in view ${r.platform.inViewportShare} rect ${r.platform.rect}`);
process.exit(0);
