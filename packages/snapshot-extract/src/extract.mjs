// One extraction run in one engine: the original (served from snapshot/site exactly like the breakpoint gate serves it) and
// our port (the prerendered default page), at every whole-pixel environment of the gate's matrix. Writes one JSON file.
// Reuses the gate's engines, servers, page waits and probe definitions; nothing of them is edited.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { LAUNCHERS } from '../../gate-breakpoints/src/engines.mjs';
import { PIN_SRC, mountPanel, prepareInPage, waitReady } from '../../gate-breakpoints/src/page.mjs';
import { snapshotRoot, siteDist, startServer, PKG } from '../../gate-breakpoints/src/serve.mjs';
import { loadAnchors, loadGen, probeEnv } from '../../gate-breakpoints/src/spec.mjs';
import { BASE, INHERITED, collectFonts, collectReference } from './page.mjs';
import { SCHEMA, buildRows } from './reduce.mjs';

const log = (...a) => process.stderr.write(a.join(' ') + '\n');
const CAP_MS = { orig: 20000, rewrite: 15000 };
/** Original parts whose elements exist only after a page action; collected in a second pass (as the gate does). */
const ORIG_LATE = { 'morph.columns': mountPanel };

/** The environments: the matrix probes at whole-pixel widths, one per distinct (width, device width, hover, pointer, motion, scheme). */
export function referenceEnvs(gen) {
  const seen = new Map();
  for (const p of gen.matrix.probes) {
    if (!Number.isInteger(p.width)) continue;
    const key = [p.width, p.deviceWidth, p.hover, p.pointer, p.reducedMotion, p.colorScheme].join('/');
    if (!seen.has(key)) seen.set(key, p);
  }
  return Array.from(seen.values()).map((p, i) => ({ id: i, probe: p.id, ...probeEnv(p) }));
}

async function pool(items, n, fn) {
  const results = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
    for (;;) {
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

export async function runExtract({ engineName, outDir, concurrency = 4, envFilter = null, withSelector = true }) {
  const { gen } = loadGen();
  const anchors = loadAnchors();
  const lock = JSON.parse(readFileSync(resolve(PKG, '../../snapshot.lock.json'), 'utf8'));
  let envs = referenceEnvs(gen);
  if (envFilter) envs = envs.filter((e) => envFilter.includes(e.id));
  const order = Object.entries(anchors.parts).flatMap(([part, p]) => p.roles.map((r) => ({ part, role: r.role })));
  const rolesFor = (site) => Object.entries(anchors.parts).flatMap(([part, p]) => p.roles.map((r) => ({ part, role: r.role, selector: r[site] })));
  const prepare = {
    orig: Object.values(anchors.parts).flatMap((p) => (p.prepare && p.prepare.orig) || []),
    rewrite: Object.values(anchors.parts).flatMap((p) => (p.prepare && p.prepare.rewrite) || []),
  };
  const lateParts = new Set(Object.keys(anchors.parts).filter((pid) => ORIG_LATE[pid]));

  const noPort = !!process.env.FW_EXTRACT_NO_PORT; // debug only: skip the port arm (no site build needed)
  const servers = { orig: await startServer(snapshotRoot()), ...(noPort ? {} : { rewrite: await startServer(siteDist()) }) };
  const engine = await LAUNCHERS[engineName]();

  async function collect(env, site, props, fonts) {
    const s = await engine.open(env, { origin: servers[site].origin, path: '/', init: PIN_SRC });
    try {
      await s.evaluate(waitReady, { site, capMs: CAP_MS[site] });
      if (prepare[site].length > 0) await s.evaluate(prepareInPage, { steps: prepare[site], capMs: CAP_MS[site] });
      const roles = rolesFor(site);
      const mk = (rs) => ({ roles: rs, props, inherited: INHERITED, base: BASE, withSelector });
      let cells;
      if (site !== 'orig' || lateParts.size === 0) cells = await s.evaluate(collectReference, mk(roles));
      else {
        cells = await s.evaluate(collectReference, mk(roles.filter((r) => !lateParts.has(r.part))));
        for (const pid of lateParts) await s.evaluate(ORIG_LATE[pid]);
        cells = cells.concat(await s.evaluate(collectReference, mk(roles.filter((r) => lateParts.has(r.part)))));
      }
      const f = fonts ? await s.evaluate(collectFonts) : null;
      return { cells, fonts: f };
    } finally { await s.close().catch(() => {}); }
  }

  const fontEnv = envs.find((e) => e.width === 1440 && e.hover === 'hover' && e.reducedMotion === 'no-preference' && e.colorScheme === 'light') ?? envs[0];
  const done = { orig: 0, rewrite: 0 };
  async function arm(site, props) {
    const per = await pool(envs, concurrency, (env) => withRetry(`${site} ${env.width}`, async () => {
      const r = await collect(env, site, props, env.id === fontEnv.id);
      if (++done[site] % 20 === 0) log(`  ${engineName} ${site}: ${done[site]}/${envs.length}`);
      return r;
    }));
    return { perEnv: per.map((r) => r.cells), fonts: per.find((_r, i) => envs[i].id === fontEnv.id).fonts };
  }

  const orig = await arm('orig', null);
  const origRows = buildRows(orig.perEnv, order, { withSelector });
  // the port is read on exactly the properties the original's roles have
  const port = noPort ? { perEnv: envs.map(() => []), fonts: { used: [], faces: [], rules: [] } } : await arm('rewrite', origRows.props);
  const portRows = buildRows(port.perEnv, order, { withSelector });

  const header = {
    t: 'header',
    schema: SCHEMA,
    engine: engineName,
    browser: await engine.version(),
    snapshot: lock.snapshot,
    gen: gen.schema,
    pinnedDate: '2026-10-01T00:00:00+07:00',
    envs,
    fontEnv: fontEnv.id,
  };
  await engine.close();
  await Promise.all(Object.values(servers).map((s) => s.close()));

  mkdirSync(outDir, { recursive: true });
  const file = join(outDir, `extract-${engineName}.json`);
  writeFileSync(file, JSON.stringify({ header, orig: origRows.rows, port: portRows.rows, fonts: { orig: orig.fonts, port: port.fonts } }) + '\n');
  log(`wrote ${file} (${origRows.rows.length} orig rows, ${portRows.rows.length} port rows)`);
  return file;
}
