// The driver of the trajectory probe: loads one arm in one engine at one width, walks the hero path and the end-of-page path in
// real time (native rAF, native timers, no frozen clock, no screenshot) and returns the RAW readings. Glue only.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { LAUNCHERS } from '../engines.mjs';
import { PIN_SRC, waitReady } from '../page.mjs';
import { startServer, snapshotRoot, siteDist, rewriteFor } from '../serve.mjs';
import { HERO_NODES, HERO_STEPS, MORPH_NODES, PAGE_PROPS, envFor, resolveNodes } from './registry.mjs';
import { debugFor, fieldOf, readDebug, withDebug } from './debug.mjs';
import { installKit } from './kit.mjs';
import { runCheck } from './reduce.mjs';
import { pooledReps, retriesRole, settleReps } from './plan.mjs';

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

/**
 * Opens one arm. The rewrite is loaded at `/` + the search: the page resolves its flags from `location.search` (entry-client.tsx),
 * so the flagged HTML alone would run the default config (incident inc-variant-gate-flags-off). What the page reports about itself
 * (`window.__fw.configHash` and `.mode`; the original has no `window.__fw`) is returned in `arm` and written into the raw artifact;
 * Lean's `armCheck` decides on it (reduce.mjs), never this function. `debug` (debug.mjs) names a page recorder to switch on for a
 * rewrite arm: it only adds `fw-debug=<name>` to the URL, which the page's flag resolution ignores (same config hash).
 */
async function open(engine, env, origin, site, search, debug = '') {
  const s = await engine.open(env, { origin, path: site === 'rewrite' ? '/' + withDebug(search, debug) : '/', init: INIT, frozen: false });
  const ready = await s.evaluate(waitReady, { site, capMs: 20000 });
  const arm = await s.evaluate(() => (window.__fw ? { config: window.__fw.configHash ?? null, mode: window.__fw.mode ?? null } : { config: null, mode: null }));
  return { s, ready, arm };
}

/** The hero path of one arm: scroll steps with per-frame reads while moving and a read after each rest. */
export async function heroPath(engine, env, origin, site, search = '') {
  const { s, ready, arm } = await open(engine, env, origin, site, search);
  try {
    const a = { arm: site, nodes: forArm(resolveNodes(HERO_NODES), site), pageProps: PAGE_PROPS, navSel: null, steps: HERO_STEPS, moveFrames: 4, restMs: 300, settleCapMs: 4000 };
    const rows = await s.evaluate((x) => window.__traj.heroPath(x), a);
    return { ready, arm, rows };
  } finally { await s.close().catch(() => {}); }
}

export const pushReading = (phases) => ({ opening: (phases.open ?? []).map((r) => r.m ?? null), closing: (phases.close ?? []).map((r) => r.m ?? null) });

/**
 * The end-of-page path of one arm: approach, rest, a wheel push open and a push close, each held. With `reads: 'lean'` the two
 * pushes read only the lean properties of the registry in every frame (the holds and the approach read everything).
 * The tween is driven by time, so one push lands about two frames per tenth of the morph value and sometimes none. With `reps`
 * above 1 the whole path is walked on a fresh page that many times and the rows of each phase are pooled (every row carries
 * its `rep`; the approach is the first rep's). Every rep's arm identity is kept (`arm` is the first, `extraArms` the rest).
 * The reducer never pairs neighbours across reps (Lean `windowOf`, `windowOf_pass_iff`): a rewrite sample is compared with the
 * union of the windows of the original's reps, each aligned on its own.
 */
export async function morphPath(engine, env, origin, site, search = '', reads = 'full', reps = 1, debug = '', against = null) {
  let out = null;
  const debugReps = [];
  const walk = async (rep) => {
    const { debugRows, ...one } = await morphPass(engine, env, origin, site, search, reads, debug);
    if (debug !== '') debugReps.push({ rep, name: debug, rows: debugRows });
    for (const rows of Object.values(one.phases)) for (const r of rows) r.rep = rep;
    if (out === null) { out = { ...one, reps, extraArms: [] }; return one; }
    out.extraArms.push(one.arm);
    for (const [ph, rows] of Object.entries(one.phases)) out.phases[ph] = (out.phases[ph] ?? []).concat(rows);
    return one;
  };
  for (let rep = 0; rep < reps; rep++) await walk(rep);
  if (against !== null) {
    const { extra } = await settleReps(against.base, pushReading(out.phases), async (i) => {
      log(`trajectory morph: extra rep ${i + 1} (a push bucket of the faithful arm has no row of this arm)`);
      return pushReading((await walk(reps + i)).phases);
    });
    out.extra = extra;
    out.reps = pooledReps(reps, extra);
  }
  // The recorder's rows of every rep (null rows: the page did not install it), next to the readings; the reducer never reads them.
  if (debug !== '') out.debugReps = debugReps;
  return out;
}

async function morphPass(engine, env, origin, site, search, reads, debug) {
  const { s, ready, arm } = await open(engine, env, origin, site, search, debug);
  try {
    const nodes = forArm(resolveNodes(MORPH_NODES), site);
    const navSel = nodes.find((n) => n.id === 'nav').sel;
    const base = { arm: site, nodes, pageProps: PAGE_PROPS, navSel, restMs: 600, settleCapMs: 4000 };
    const watched = await s.evaluate((sel) => window.__traj.watchNav(sel), navSel);
    const approach = await s.evaluate((a) => window.__traj.approach(a), base);
    const phases = {};
    const phaseReads = {};
    for (const p of PUSH_PHASES) {
      const lean = reads === 'lean' && p.dy !== 0;
      phaseReads[p.phase] = lean ? 'lean' : 'full';
      await s.evaluate((a) => window.__traj.startSampler(a), { ...base, pageProps: lean ? [] : PAGE_PROPS, phase: p.phase, stride: p.stride, lean });
      if (p.dy !== 0) await s.wheel(env.width / 2, env.height / 2, p.dy);
      await sleep(p.ms);
      phases[p.phase] = await s.evaluate(() => window.__traj.stopSampler());
    }
    const debugRows = debug === '' ? null : await s.evaluate(readDebug, fieldOf(debug));
    return { ready, arm, watched, approach, phases, phaseReads, debugRows };
  } finally { await s.close().catch(() => {}); }
}

/** The arms of a role, as armCheck reads them. */
const armsOfRun = (run) => ['hero', 'morph'].filter((p) => run[p]).flatMap((p) => [run[p].arm, ...(run[p].extraArms ?? [])].map((a) => ({ site: run.site, want: run.want, config: a.config, mode: a.mode })));

/**
 * Run the lane for one engine over `widths`: at each width the original, the faithful rewrite (default config, role `base`) and
 * the candidate (`search` picks its prerendered page, role `cand`). `paths` picks the hero path, the morph path or both. A refused
 * search throws (rewriteFor), like the gate's smoke step. The arm identity is checked (Lean armCheck, reduce.mjs) as soon as an
 * arm has been walked: on a refusal the walk stops, and the raw artifact up to there is returned with `refused: true` (reduceRaw
 * refuses it again from the same readings).
 * Returns { engine, version, search, hash, baseHash, paths, reads, refused, runs: [{ width, site, role, search, want, hero, morph }] }.
 */
export async function runLane({ engineName, widths, search = '', paths = ['hero', 'morph'], reads = 'full', reps = 3, env = process.env }) {
  const variant = rewriteFor(siteDist(env), { ...env, FW_SEARCH: search });
  const configs = JSON.parse(readFileSync(join(siteDist(env), 'configs.json'), 'utf8'));
  const baseHash = configs.bySearch[''];
  const want = variant.hash ?? baseHash;
  const debug = debugFor(env); // '' unless FW_DEBUG names a recorder (debug.mjs)
  if (debug !== '') log(`trajectory ${engineName}: page recorder "${debug}" on the rewrite arms`);
  const origin = await startServer(snapshotRoot(env));
  // The faithful arm is served the default page; only the candidate gets the page prerendered for its search (a flagged page
  // served to the default search would client-render, and armCheck refuses a client render).
  const faithful = await startServer(siteDist(env));
  const rewrite = variant.rewrite ? await startServer(siteDist(env), variant.rewrite) : faithful;
  const engine = await LAUNCHERS[engineName]();
  const runs = [];
  let refused = false;
  try {
    outer: for (const width of widths) {
      const e = envFor(width);
      const arms = [
        { site: 'orig', role: 'orig', search: '', want: null, origin: origin.origin },
        { site: 'rewrite', role: 'base', search: '', want: baseHash, origin: faithful.origin },
        { site: 'rewrite', role: 'cand', search, want, origin: rewrite.origin },
      ];
      for (const a of arms) {
        const t0 = Date.now();
        const run = { width, site: a.site, role: a.role, search: a.search, want: a.want };
        if (paths.includes('hero')) { log(`trajectory ${engineName} ${width} ${a.role}: hero`); run.hero = await heroPath(engine, e, a.origin, a.site, a.search); }
        if (paths.includes('morph')) {
          log(`trajectory ${engineName} ${width} ${a.role}: morph`);
          const peer = (role) => runs.find((r) => r.width === width && r.role === role)?.morph;
          const against = retriesRole(a.role, peer('base') != null) ? { base: pushReading(peer('base').phases) } : null;
          run.morph = await morphPath(engine, e, a.origin, a.site, a.search, reads, reps, a.site === 'rewrite' ? debug : '', against);
        }
        runs.push(run);
        log(`trajectory ${engineName} ${width} ${a.role}: done in ${Date.now() - t0} ms`);
        if (runCheck(armsOfRun(run)) !== 'ok') { refused = true; log(`trajectory ${engineName} ${width} ${a.role}: REFUSED config (${JSON.stringify(armsOfRun(run))})`); break outer; }
      }
    }
    return { engine: engineName, version: await engine.version(), search, hash: want, baseHash, paths, reads, reps, debug, refused, runs };
  } finally {
    await engine.close().catch(() => {});
    await origin.close(); await faithful.close();
    if (rewrite !== faithful) await rewrite.close();
  }
}
