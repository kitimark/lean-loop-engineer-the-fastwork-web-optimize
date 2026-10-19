// Port completeness check 5 (fonts) in a browser: per gate viewport, both arms are loaded and every text leaf with its computed
// first font family, weight and style, and the loaded faces of document.fonts, are read (fontsInPage) and judged by the
// Lean rule (lean/Fw/Port/Fonts.lean; golden-checked twin scripts/port/fonts.mjs). The rewrite is served as built.
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { PIN_SRC, waitReady } from '../../gate-breakpoints/src/page.mjs';
import { siteDist, snapshotRoot, startServer } from '../../gate-breakpoints/src/serve.mjs';
import { loadGen, probeEnv } from '../../gate-breakpoints/src/spec.mjs';
import { check, excl, fontsInPage, rowsOf } from '../../../scripts/port/fonts.mjs';
import { LAUNCHERS } from './engines.mjs';

const CAP_MS = { orig: 20000, rewrite: 15000 };
const FACE_WAIT_MS = 10000;
const log = (...a) => process.stderr.write(a.join(' ') + '\n');

/** One arm at one viewport: load, (real pages) wait for readiness, read leaves and faces. */
export async function readArm(engine, env, { site, origin, path = '/', real = true }) {
  const s = await engine.open(env, { origin, path, init: real ? PIN_SRC : () => {} });
  try {
    if (real) await s.page.evaluate(waitReady, { site, capMs: CAP_MS[site] });
    return await s.page.evaluate(fontsInPage, { rows: rowsOf(site), waitMs: FACE_WAIT_MS });
  } finally { await s.close().catch(() => {}); }
}

const cap = (l, n = 40) => l.slice(0, n);

/** The verdict of one viewport for the two arms' reports. */
export function judge(id, O, R) {
  const v = check(excl, O, R);
  return {
    id, pass: v.pass,
    counts: { leaves: { orig: O.leaves.length, rewrite: R.leaves.length }, missing: v.missing.length, extra: v.extra.length, missingFaces: v.missingFaces.length, extraFaces: v.extraFaces.length },
    missing: cap(v.missing), extra: cap(v.extra), missingFaces: v.missingFaces, extraFaces: v.extraFaces,
    loaded: { orig: [...new Set(O.faces.filter((f) => f.status === 'loaded').map((f) => `${f.family} ${f.weight} ${f.style}`))], rewrite: [...new Set(R.faces.filter((f) => f.status === 'loaded').map((f) => `${f.family} ${f.weight} ${f.style}`))] },
  };
}

/** Run the check for the probes (ids of the gate's Lean matrix) on `engineName`; `targets` = { orig: {origin, path}, rewrite: {...}, real }. */
export async function fontsAtProbes({ engine, probes, targets, concurrency = 2 }) {
  const out = new Array(probes.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(concurrency, probes.length) }, async () => {
    for (;;) {
      const i = next++;
      if (i >= probes.length) return;
      const p = probes[i];
      const env = probeEnv(p);
      try {
        const [O, R] = await Promise.all(['orig', 'rewrite'].map((site) => readArm(engine, env, { site, ...targets[site], real: targets.real })));
        out[i] = judge(p.id, O, R);
      } catch (e) {
        out[i] = { id: p.id, pass: false, error: String(e.message).split('\n')[0] };
      }
      log(`  fonts ${engine.name}: ${p.id} ${out[i].pass ? 'pass' : out[i].error ? 'error' : 'FAIL'}`);
    }
  }));
  return out;
}

export async function runFonts({ engineName, outDir, probeIds, concurrency = 2 }) {
  const { gen } = loadGen();
  const probes = probeIds.map((id) => gen.matrix.probes.find((p) => p.id === id) ?? (() => { throw new Error(`unknown probe ${id}`); })());
  const servers = { orig: await startServer(snapshotRoot()), rewrite: await startServer(siteDist()) };
  const engine = await LAUNCHERS[engineName]();
  try {
    const results = await fontsAtProbes({
      engine, probes, concurrency,
      targets: { real: true, orig: { origin: servers.orig.origin, path: '/' }, rewrite: { origin: servers.rewrite.origin, path: '/' } },
    });
    const file = join(outDir, `${engineName}.fonts.json`);
    mkdirSync(outDir, { recursive: true });
    writeFileSync(file, JSON.stringify({ schema: 'fw.port.fonts/1', engine: engineName, browser: await engine.version(), probes: results }, null, 1) + '\n');
    log(`wrote ${file}`);
    return { file, results };
  } finally {
    await engine.close();
    await Promise.all(Object.values(servers).map((s) => s.close()));
  }
}

/** Markdown table of the results (step summary), then the first lost and added leaves and the face differences of each failing probe. */
export function fontsTable(engineName, results) {
  const rows = results.map((r) => `| ${r.id} | ${r.pass ? 'pass' : r.error ? 'error' : 'FAIL'} | ${r.counts ? `${r.counts.missing} / ${r.counts.extra} / ${r.counts.missingFaces} / ${r.counts.extraFaces}` : r.error} |`);
  const leaf = (u) => `${u.sec} "${u.text.slice(0, 40)}" ${u.family} ${u.weight} ${u.style}`;
  const detail = results.filter((r) => r.counts && !r.pass).flatMap((r) => [
    `- ${r.id}`,
    ...r.missing.slice(0, 6).map((u) => `  - lost ${leaf(u)}`),
    ...r.extra.slice(0, 6).map((u) => `  - added ${leaf(u)}`),
    ...r.missingFaces.map((t) => `  - face lost ${t.join(' ')}`),
    ...r.extraFaces.map((t) => `  - face added ${t.join(' ')}`),
  ]);
  return [`### Port check 5 (fonts), ${engineName}`, '', '| probe | verdict | leaves lost / added / faces lost / added |', '|---|---|---|', ...rows, '', ...detail, ''].join('\n');
}
