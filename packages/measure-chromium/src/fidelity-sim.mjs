// Font fidelity, iOS Simulator side (task counts-font-fidelity). On the macOS runner with the lane's Simulator (iPhone 15 Pro
// Max, Safari, the inspector through ios_webkit_debug_proxy) it serves the snapshot read-only, loads the original page with the
// pinned clock and runs the same fidelityInPage as the other arms. Writes fidelity-sim.json (one view, key `sim`, at the width
// and height Safari gives the tab). Nothing here is phone time: a Simulator is a Mac process with the Mac's fonts.
// usage: FW_SNAPSHOT_SITE=<snapshot/site> node fidelity-sim.mjs --rows=<rows.json> --out=<dir> [--variant=sim]
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { withSession } from '../../measure-webkit/src/session.mjs';
import { loadFresh, pageInfo } from '../../measure-webkit/src/page.mjs';
import { fidelityInPage } from './fidelity-page.mjs';

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const s = a.replace(/^--/, ''); const i = s.indexOf('='); return i < 0 ? [s, true] : [s.slice(0, i), s.slice(i + 1)]; }));
if (!args.out || !args.rows) { console.error('usage: fidelity-sim.mjs --rows=<rows.json> --out=<dir> [--variant=sim]'); process.exit(2); }
const VARIANT = args.variant ?? 'sim';
const ROWS = JSON.parse(readFileSync(args.rows, 'utf8'));
const READY = '.hero-track .hero.is-ring-splash-done';
mkdirSync(args.out, { recursive: true });

const result = { schema: 'fw.font-fidelity/1', variant: VARIANT, browser: 'safari (iOS Simulator)', platform: 'darwin', views: {} };
let code = 0;
try {
  await withSession(async (ctx) => {
    await loadFresh(ctx.c, { clock: 'pinned', timers: 'live', settleMs: 3000 });
    const info = await pageInfo(ctx.c);
    const r = { view: 'sim', width: info.vw, height: info.vh, dpr: info.dpr, mobile: true, crash: false, error: null, ua: info.ua };
    const page = await ctx.c.runAsync(`(${fidelityInPage.toString()})(${JSON.stringify({ rows: ROWS, readySel: READY })})`, { pollMs: 500 });
    Object.assign(r, page);
    result.views.sim = r;
    console.error(`FIDELITY ${VARIANT} sim docH=${r.docH} inner=${r.innerW}x${r.innerH} dpr=${r.dpr}`);
  });
} catch (e) {
  result.views.sim = { view: 'sim', crash: false, error: String(e?.message ?? e).slice(0, 400) };
  console.error(`FIDELITY ${VARIANT} sim error: ${e?.message ?? e}`);
  code = 1;
} finally {
  writeFileSync(`${args.out}/fidelity-${VARIANT}.json`, `${JSON.stringify(result)}\n`);
}
process.exit(code);
