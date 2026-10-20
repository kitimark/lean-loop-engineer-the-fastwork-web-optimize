// The driver of the trajectory probe: loads one arm in one engine at one width, walks the hero path and the end-of-page path in
// real time (native rAF, native timers, no frozen clock, no screenshot) and returns the RAW readings. Glue only.
import { LAUNCHERS } from '../engines.mjs';
import { PIN_SRC, waitReady } from '../page.mjs';
import { startServer, snapshotRoot, siteDist, rewriteFor } from '../serve.mjs';
import { HERO_NODES, HERO_STEPS, MORPH_NODES, PAGE_PROPS, envFor, resolveNodes } from './registry.mjs';
import { installKit } from './kit.mjs';

const INIT = `${PIN_SRC}\n(${installKit.toString()})();`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => process.stderr.write(a.join(' ') + '\n');

/** The phases of the push, after the rest at the end of the page: the wheel direction and the sampling stride. */
export const PUSH_PHASES = [
  { phase: 'open', dy: 120, stride: 1, ms: 1000 },
  { phase: 'open-hold', dy: 0, stride: 4, ms: 600 },
  { phase: 'close', dy: -120, stride: 1, ms: 1000 },
  { phase: 'close-hold', dy: 0, stride: 4, ms: 600 },
];

const forArm = (nodes, site) => nodes.map((n) => ({ id: n.id, sel: site === 'orig' ? n.orig : n.rewrite, props: n.props }));

async function open(engine, env, origin, site) {
  const s = await engine.open(env, { origin, path: '/', init: INIT, frozen: false });
  const ready = await s.evaluate(waitReady, { site, capMs: 20000 });
  return { s, ready };
}

/** The hero path of one arm: scroll steps with per-frame reads while moving and a read after each rest. */
export async function heroPath(engine, env, origin, site) {
  const { s, ready } = await open(engine, env, origin, site);
  try {
    const arg = { arm: site, nodes: forArm(resolveNodes(HERO_NODES), site), pageProps: PAGE_PROPS, navSel: null, steps: HERO_STEPS, moveFrames: 4, restMs: 300, settleCapMs: 4000 };
    const rows = await s.evaluate((a) => window.__traj.heroPath(a), arg);
    return { ready, rows };
  } finally { await s.close().catch(() => {}); }
}

/** The end-of-page path of one arm: approach, rest, a wheel push open and a push close, each held. */
export async function morphPath(engine, env, origin, site) {
  const { s, ready } = await open(engine, env, origin, site);
  try {
    const nodes = forArm(resolveNodes(MORPH_NODES), site);
    const navSel = nodes.find((n) => n.id === 'nav').sel;
    const base = { arm: site, nodes, pageProps: PAGE_PROPS, navSel, restMs: 600, settleCapMs: 4000 };
    const watched = await s.evaluate((sel) => window.__traj.watchNav(sel), navSel);
    const approach = await s.evaluate((a) => window.__traj.approach(a), base);
    const phases = {};
    for (const p of PUSH_PHASES) {
      await s.evaluate((a) => window.__traj.startSampler(a), { ...base, phase: p.phase, stride: p.stride });
      if (p.dy !== 0) await s.wheel(env.width / 2, env.height / 2, p.dy);
      await sleep(p.ms);
      phases[p.phase] = await s.evaluate(() => window.__traj.stopSampler());
    }
    return { ready, watched, approach, phases };
  } finally { await s.close().catch(() => {}); }
}

/**
 * Run the lane for one engine over `widths` against the original and the rewrite (`search` picks the rewrite's prerendered page).
 * A refused search throws (rewriteFor), like the gate's smoke step. Returns { engine, version, search, runs: [{ width, site, hero, morph }] }.
 */
export async function runLane({ engineName, widths, search = '', env = process.env }) {
  const variant = rewriteFor(siteDist(env), { ...env, FW_SEARCH: search });
  const servers = { orig: await startServer(snapshotRoot(env)), rewrite: await startServer(siteDist(env), variant.rewrite) };
  const engine = await LAUNCHERS[engineName]();
  const runs = [];
  try {
    for (const width of widths) {
      for (const site of ['orig', 'rewrite']) {
        const e = envFor(width);
        const t0 = Date.now();
        log(`trajectory ${engineName} ${width} ${site}: hero`);
        const hero = await heroPath(engine, e, servers[site].origin, site);
        log(`trajectory ${engineName} ${width} ${site}: morph`);
        const morph = await morphPath(engine, e, servers[site].origin, site);
        log(`trajectory ${engineName} ${width} ${site}: done in ${Date.now() - t0} ms`);
        runs.push({ width, site, hero, morph });
      }
    }
    return { engine: engineName, version: await engine.version(), search, hash: variant.hash, runs };
  } finally {
    await engine.close().catch(() => {});
    await servers.orig.close(); await servers.rewrite.close();
  }
}
