// The runner: loads both arms for every probe and sweep, in one engine, and writes the RAW facts as JSON.
// Output is deterministic by construction: no timestamps, no durations, canonical order, nothing from the machine
// except the browser's own version string. Progress goes to stderr only.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { LAUNCHERS } from './engines.mjs';
import { PIN_SRC, collectInPage, mountPanel, prepareInPage, waitReady, waitResize } from './page.mjs';
import { snapshotRoot, siteDist, startServer, rewriteFor, PKG } from './serve.mjs';
import { loadAnchors, loadGen, probeEnv, scopeFor, selectParts, sweepDefs } from './spec.mjs';

const log = (...a) => process.stderr.write(a.join(' ') + '\n');
const SITES = ['orig', 'rewrite'];
const FILTER = { orig: '\\.svelte-', rewrite: '-module_' };
const CAP_MS = { orig: 20000, rewrite: 15000 };
/** Parts whose original elements exist only after a page action. Their roles are collected in a second pass, after the
 *  action, so every other part is read in the state a fresh load has (the action is a scroll there and back). */
const ORIG_PREPARE = { 'morph.columns': mountPanel };

async function pool(items, n, fn) {
  const results = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
    while (true) {
      const i = next++;
      if (i >= items.length) return;
      results[i] = await fn(items[i], i);
    }
  }));
  return results;
}

async function withRetry(label, fn, tries = 3) {
  let last;
  for (let i = 0; i < tries; i++) {
    try { return await fn(); } catch (e) { last = e; log(`  retry ${label} (${i + 1}/${tries}): ${String(e.message).split('\n')[0]}`); }
  }
  throw last;
}

/** The engine port each launcher drives (Lean `Fw.Gate.Port`, wire names): the verdict rule needs it to name unreachable cells.
 *  Playwright WebKit is the Apple port on macOS and the GLib port (WebKitGTK/WPE) on Linux. */
export const portOf = (engineName, platform = process.platform) =>
  (engineName === 'chromium' ? 'chromium' : platform === 'darwin' ? 'webkit-apple' : 'webkit-glib');

/**
 * `gaps` (optional, used only by the gaps lane, src/gaps/): { launcher, mapProbe, collect, collectArg } replaces the engine
 * launcher, maps each matrix probe to the environment the lane builds (Lean's environment plus the mechanism fields, for
 * example a browser zoom), and adds one extra in-page report under `raw.gap`. The record keeps Lean's environment as `env`
 * (what the verdict rule is asked about) and the mapped one as `realized`. Null (the default) adds no `realized` and no `raw.gap`.
 */
export async function runEngine({ engineName, outDir, concurrency = 4, probeFilter = null, sweepFilter = null, partFilter = null, gaps = null }) {
  const { gen, sha256: genSha } = loadGen();
  const anchors = loadAnchors();
  // Part selection (glue): only the chosen parts' elements are collected, so only their raw facts and property lists are
  // written. The header names the parts when some are skipped; a default run writes the same bytes as before the flag.
  const sel = selectParts(Object.keys(anchors.parts), partFilter);
  // Probe scope (glue): a narrowed run loads only the union of its parts' Lean scopes (src/scope.gen.json,
  // Fw.Gate.scope_sound); --probes/--sweeps narrow further. The header lists the scope so merge-gate knows what to expect.
  const scope = scopeFor(sel, gen);
  const activeParts = Object.fromEntries(sel.covered.map((pid) => [pid, anchors.parts[pid]]));
  const lock = JSON.parse(readFileSync(resolve(PKG, '../../snapshot.lock.json'), 'utf8'));
  const dist = siteDist();
  const buildInfo = JSON.parse(readFileSync(join(dist, 'build-info.json'), 'utf8'));
  const variantPage = rewriteFor(dist); // FW_SEARCH: a flagged config of the rewrite (default: none)
  const servers = { orig: await startServer(snapshotRoot()), rewrite: await startServer(dist, variantPage.rewrite) };
  const engine = await (gaps ? gaps.launcher : LAUNCHERS[engineName])();
  const cond = gen.conditions.map((c) => ({ tsId: c.tsId, css: c.css, legacyCss: c.legacyCss }));
  const neutral = gen.neutral.map((n) => ({ tsId: n.tsId, css: n.css }));
  const partsArg = Object.fromEntries(['orig', 'rewrite'].map((site) => [site, Object.fromEntries(
    Object.entries(activeParts).map(([pid, p]) => {
      // a box is collected only where it is compared or used as a reference: the original's headline is animated text
      const needed = new Set(p.roles.flatMap((r) => (r.dims.length > 0 ? [r.role, ...(r.boxRel ? [r.boxRel.role] : [])] : [])));
      return [pid, p.roles.map((r) => ({ role: r.role, selector: r[site], rect: needed.has(r.role) }))];
    }))]));

  async function load(env, site) {
    return engine.open(env, { origin: servers[site].origin, path: site === 'rewrite' ? '/' + variantPage.search : '/', init: PIN_SRC });
  }
  // anchors.json `prepare` (per part and arm): steps that bring up elements the page mounts lazily, run once after
  // the ready wait (morph.countdown); ORIG_PREPARE below is the other route (mount after the early parts are collected)
  const prepare = Object.fromEntries(SITES.map((site) => [site, Object.values(activeParts).flatMap((p) => (p.prepare && p.prepare[site]) || [])]));
  const evalReady = async (s, site) => {
    const settle = await s.evaluate(waitReady, { site, capMs: CAP_MS[site] });
    if (prepare[site].length > 0) settle.prepared = await s.evaluate(prepareInPage, { steps: prepare[site], capMs: CAP_MS[site] });
    return settle;
  };
  const lateIds = new Set(Object.keys(activeParts).filter((pid) => ORIG_PREPARE[pid]));
  const pick = (site, late) => Object.fromEntries(Object.entries(partsArg[site]).filter(([pid]) => (site === 'orig' && lateIds.has(pid)) === late));
  const collectArg = (site, env, props, parts) => ({
    site, conditions: cond, neutral, dprWanted: env.dpr, widthWanted: env.width, parts, props, filter: FILTER[site],
  });
  async function evalCollect(s, site, env, props) {
    if (site !== 'orig' || lateIds.size === 0) return s.evaluate(collectInPage, collectArg(site, env, props, partsArg[site]));
    const raw = await s.evaluate(collectInPage, collectArg(site, env, props, pick(site, false)));
    for (const pid of lateIds) await s.evaluate(ORIG_PREPARE[pid]);
    const late = await s.evaluate(collectInPage, collectArg(site, env, props, pick(site, true)));
    raw.parts = { ...raw.parts, ...late.parts };
    return raw;
  }

  // Phase 0: the property lists. Declared names depend on the stylesheets and the elements, not on the environment,
  // so one reference load per arm fixes them (the engine expands shorthands, so they are per engine).
  const refEnv = { width: 1440, height: 900, deviceWidth: 1440, deviceHeight: 900, dpr: 1, hover: 'hover', pointer: 'fine', reducedMotion: 'no-preference', colorScheme: 'light' };
  const declared = {};
  for (const site of SITES) {
    const s = await load(refEnv, site);
    await evalReady(s, site);
    declared[site] = (await evalCollect(s, site, refEnv, null)).parts;
    await s.close();
  }
  const props = {};
  for (const [pid, p] of Object.entries(activeParts)) {
    props[pid] = {};
    for (const r of p.roles) {
      const rw = declared.rewrite[pid][r.role].declared;
      const or = declared.orig[pid][r.role].declared;
      props[pid][r.role] = { restated: rw, originOnly: or.filter((x) => !rw.includes(x)) };
    }
  }
  const collectProps = Object.fromEntries(Object.entries(props).map(([pid, roles]) => [pid, Object.fromEntries(
    Object.entries(roles).map(([role, v]) => [role, [...v.restated, ...v.originOnly]]))]));

  async function sample(env, site) {
    return withRetry(`${site} ${env.width}x${env.height}`, async () => {
      const s = await load(env, site);
      try {
        const settle = await evalReady(s, site);
        const raw = await evalCollect(s, site, env, collectProps);
        if (gaps) raw.gap = await s.evaluate(gaps.collect, gaps.collectArg);
        return { settle, raw };
      } finally { await s.close().catch(() => {}); }
    });
  }

  // Phase 1: the matrix.
  const probes = gen.matrix.probes.filter((p) => (!probeFilter || probeFilter.some((o) => p.id.includes(o) || p.block === o))
    && (!scope || scope.probes.includes(p.id)));
  const tasks = probes.flatMap((p) => SITES.map((site) => ({ p, site })));
  let done = 0;
  const sampled = await pool(tasks, concurrency, async ({ p, site }) => {
    const r = await sample(gaps ? gaps.mapProbe(p) : probeEnv(p), site);
    if (++done % 20 === 0) log(`  ${engineName}: ${done}/${tasks.length} loads`);
    return r;
  });
  const probeRecords = probes.map((p, i) => ({
    id: p.id, block: p.block, env: probeEnv(p), ...(gaps ? { realized: gaps.mapProbe(p) } : {}),
    orig: sampled[2 * i], rewrite: sampled[2 * i + 1],
  }));

  // Phase 2: live-resize sweeps. Each arm of a sweep is one page that is only resized after the first load.
  const sweeps = sweepDefs(gen).filter((s) => (!sweepFilter || sweepFilter.some((o) => s.id.includes(o)))
    && (!scope || scope.sweeps.includes(s.id)));
  const sweepRecords = [];
  for (const sw of sweeps) {
    const perSite = await Promise.all(SITES.map(async (site) => withRetry(`sweep ${sw.id} ${site}`, async () => {
      const s = await load(sw.stops[0], site);
      try {
        const stops = [];
        await evalReady(s, site);
        for (let i = 0; i < sw.stops.length; i++) {
          if (i > 0) { await s.resize(sw.stops[i]); await s.evaluate(waitResize); }
          stops.push(await evalCollect(s, site, sw.stops[i], collectProps));
        }
        return stops;
      } finally { await s.close().catch(() => {}); }
    })));
    const last = sw.stops[sw.stops.length - 1];
    const fresh = await Promise.all(SITES.map((site) => sample(last, site)));
    sweepRecords.push({ id: sw.id, blurb: sw.blurb, stops: sw.stops, orig: perSite[0], rewrite: perSite[1], freshFinal: { orig: fresh[0], rewrite: fresh[1] } });
    log(`  ${engineName}: sweep ${sw.id} done (${sw.stops.length} stops)`);
  }

  const header = {
    schema: 'fw.gate-breakpoints.run/1',
    engine: engineName,
    browser: await engine.version(),
    gen: { sha256: genSha, schema: gen.schema, probes: gen.matrix.loadsPerEngine },
    snapshot: lock.snapshot,
    site: { buildId: buildInfo.buildId, configHash: buildInfo.configHash, muiCss: buildInfo.muiCss },
    port: portOf(engineName),
    pinnedDate: '2026-10-01T00:00:00+07:00',
    ...(sel.narrowed ? { parts: { covered: sel.covered, skipped: sel.skipped, ...(scope ? { scope } : {}) } } : {}),
    props,
  };
  await engine.close();
  await Promise.all(SITES.map((s) => servers[s].close()));

  mkdirSync(outDir, { recursive: true });
  const file = join(outDir, `${engineName}.json`);
  const lines = [
    '{"header":' + JSON.stringify(header) + ',',
    '"probes":[',
    probeRecords.map((r) => JSON.stringify(r)).join(',\n'),
    '],',
    '"sweeps":[',
    sweepRecords.map((r) => JSON.stringify(r)).join(',\n'),
    ']}',
  ];
  writeFileSync(file, lines.join('\n') + '\n');
  log(`wrote ${file}`);
  return file;
}
