// The image audit runner: for each (width, DPR) load one arm in one engine, walk the page from top to bottom in half-viewport stops
// (so lazy images load and IntersectionObserver-mounted parts exist) and read every image and its effects at every stop
// (inpage.mjs). It decides nothing and times nothing; reduce.mjs turns the readings into the table.
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { LAUNCHERS } from '../engines.mjs';
import { rewriteFor, siteDist, snapshotRoot, startServer } from '../serve.mjs';
import { composeRewrite, loadDrawn } from './arm.mjs';
import { collectImages, kitSource, morphEnd, scrollStop } from './inpage.mjs';

/** The Lean breakpoint widths: the whole-pixel widths of the gate matrix (breakpoints.gen.json matrix.probes), sorted. */
export function leanWidths(gen) {
  return [...new Set(gen.matrix.probes.map((p) => p.width).filter((w) => Number.isInteger(w)))].sort((a, b) => a - b);
}

export const envFor = (width, dpr, height = 900) => ({
  width, height, deviceWidth: width, deviceHeight: height, dpr, hover: 'hover', pointer: 'fine', reducedMotion: 'no-preference', colorScheme: 'light',
});

/** Scroll stops of a document of height h in a viewport of height vh: the top, every half viewport, the bottom. */
export function stopsFor(h, vh) {
  const max = Math.max(0, h - vh);
  const ys = [];
  // quarter viewports through the first two (the hero exit runs there), then half viewports
  for (let y = 0; y < max; y += y < 2 * vh ? Math.round(vh / 4) : Math.round(vh / 2)) ys.push(y);
  ys.push(max);
  return [...new Set(ys)];
}

/** Merge the per-stop readings of one load into one record per image (the keys are the in-page ids). */
export function mergeStops(stops) {
  const by = new Map();
  stops.forEach((st, si) => {
    for (const it of st.items) {
      let m = by.get(it.id);
      if (!m) {
        m = { ...it, effects: [], stopsSeen: 0, stopsInView: 0, firstInView: null, visMin: it.vis, visMax: it.vis, everInView: false };
        delete m.inView;
        by.set(it.id, m);
      }
      m.stopsSeen++;
      if (it.complete === false && m.complete !== false) continue;
      if (m.complete === false && it.complete !== false) { Object.assign(m, { nat: it.nat, complete: it.complete, box: it.box, img: it.img, none: it.none, url: it.url }); }
      // an effect counts at every stop where the image is laid out (a filter a script sets one frame later still shows up);
      // the ones seen only while the image is off screen carry `offscreen`
      if (!it.none && !it.inView) {
        const seen0 = new Set(m.effects.map((e) => `${e.at}|${e.up}|${e.e}`));
        for (const e of it.effects) if (!seen0.has(`${e.at}|${e.up}|${e.e}`)) m.effects.push({ ...e, stops: [], offscreen: true });
        for (const e of it.effects) m.effects.find((x) => x.at === e.at && x.up === e.up && x.e === e.e).stops.push(si);
      }
      if (it.inView) {
        m.stopsInView++;
        if (!m.everInView) { m.everInView = true; m.firstInView = si; Object.assign(m, { box: it.box, img: it.img, none: it.none, nat: it.nat, top: it.top }); }
        m.visMin = Math.min(m.visMin, it.vis);
        m.visMax = Math.max(m.visMax, it.vis);
        if (it.rw !== undefined) {
          m.rwMin = Math.min(m.rwMin ?? it.rw, it.rw); m.rwMax = Math.max(m.rwMax ?? it.rw, it.rw);
          m.rhMin = Math.min(m.rhMin ?? it.rh, it.rh); m.rhMax = Math.max(m.rhMax ?? it.rh, it.rh);
        }
        const seen = new Set(m.effects.map((e) => `${e.at}|${e.up}|${e.e}`));
        for (const e of it.effects) if (!seen.has(`${e.at}|${e.up}|${e.e}`)) m.effects.push({ ...e, stops: [] });
        for (const e of it.effects) m.effects.find((x) => x.at === e.at && x.up === e.up && x.e === e.e).stops.push(si);
      }
      if (!m.everInView) { m.fw = it.fw; m.cls = it.cls; }
      // the drawn size the arm and the table work from is the largest the image has at any stop (the morph columns grow at the
      // end state, which only the last stop shows): box and drawn size are taken together from that stop
      if (!it.none && it.complete !== false && it.img && (!m.big || it.img[0] * it.img[1] > m.big.img[0] * m.big.img[1])) m.big = { img: it.img, box: it.box, nat: it.nat, stop: si };
    }
  });
  for (const m of by.values()) {
    if (m.big) { m.img = m.big.img; m.box = m.big.box; m.bigStop = m.big.stop; delete m.big; }
  }
  return [...by.values()];
}

/** Audit one arm in one engine over the (width, dpr) grid. `pool` loads run at once. */
export async function runAudit({ engine, arm, widths, dprs, out, pool = 2, drawn = null, extra = [], log = console.log }) {
  const launcher = LAUNCHERS[engine];
  if (!launcher) throw new Error(`unknown engine ${engine}`);
  const root = arm === 'original' ? snapshotRoot() : siteDist();
  const drawnArm = arm === 'drawn' ? loadDrawn(drawn ?? undefined) : null;
  if (arm === 'drawn' && !drawnArm) throw new Error('arm drawn needs --drawn <manifest.json>');
  const base = arm === 'original' ? null : rewriteFor(root).rewrite;
  const server = await startServer(root, null);
  const eng = await launcher();
  const cells = {};
  // the grid, plus explicit cells `extra` ([width, dpr]): layout does not depend on DPR, so the grid runs at one DPR and the
  // headline widths add the others
  // `extra` entries are [width, dpr] or { key, w, d, env } (a probe's own environment, as the visual diff opens it)
  const todo = [...widths.flatMap((w) => dprs.map((d) => ({ w, d }))), ...extra.map((x) => (Array.isArray(x) ? { w: x[0], d: x[1] } : x))];
  const keyOf = (t) => t.key ?? `w${t.w}@${t.d}`;
  const seen = new Set();
  for (let i = todo.length - 1; i >= 0; i--) { const k = keyOf(todo[i]); if (seen.has(k)) todo.splice(i, 1); else seen.add(k); }
  const t0 = Date.now();
  const one = async ({ w, d, env: own0, key }) => {
    const env = own0 ?? envFor(w, d);
    // a drawn arm answers /selling/x with the resized copy of its cell; every other path is the plain site
    let srv = server;
    let own = null;
    if (drawnArm) {
      own = await startServer(root, composeRewrite(base, drawnArm, { width: w, dpr: d }));
      srv = own;
    }
    let session = null;
    try {
      session = await eng.open(env, { origin: srv.origin, path: '/', init: kitSource() });
      const first = await session.evaluate(scrollStop, 0);
      const ys = stopsFor(first.h, first.vh);
      const stops = [];
      for (const y of ys) {
        await session.evaluate(scrollStop, y);
        const r = await session.evaluate(collectImages);
        stops.push({ y, ...r });
      }
      // the document may have grown while scrolling (mounted parts): one more stop at the final bottom
      const end = await session.evaluate(scrollStop, 1e9);
      const r = await session.evaluate(collectImages);
      stops.push({ y: end.y, ...r });
      // the end state of the morph: nothing but a wheel or touch gesture moves the tween, so a scroll never gets there; the nav
      // publishes `--morph` and `data-fw-morph` (morph.tween/index.tsx publish), written here with the value the tween ends on
      await session.evaluate(morphEnd);
      const rm = await session.evaluate(collectImages);
      stops.push({ y: end.y, morph: 1, ...rm });
      cells[key ?? `w${w}@${d}`] = {
        width: w, dpr: d, height: env.height, docHeight: end.h, stops: stops.map((s) => ({ y: s.y, dpr: s.dpr, vw: s.vw, vh: s.vh, morph: s.morph ?? 0 })),
        items: mergeStops(stops),
      };
    } finally {
      await session?.close().catch(() => {});
      await own?.close();
    }
  };
  let next = 0;
  const worker = async () => {
    while (next < todo.length) {
      const t = todo[next++];
      const s = Date.now();
      try { await one(t); log(`${engine} ${arm} ${keyOf(t)} ok ${Date.now() - s} ms`); } catch (e) { log(`${engine} ${arm} ${keyOf(t)} FAILED ${e.message}`); cells[keyOf(t)] = { width: t.w, dpr: t.d, error: String(e.message) }; }
    }
  };
  await Promise.all(Array.from({ length: pool }, worker));
  const version = await eng.version();
  await eng.close();
  await server.close();
  const file = { schema: 'fw.images.audit/1', engine, version, arm, root: arm === 'original' ? 'snapshot/site' : 'apps/site/dist/aot', widths, dprs, ms: Date.now() - t0, cells };
  mkdirSync(out, { recursive: true });
  const name = join(out, `images-${engine}-${arm}.json`);
  writeFileSync(name, JSON.stringify(file));
  return { name, file };
}
