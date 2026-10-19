// Fail-fast smoke test for one breakpoint-gate engine before a 16-load shard starts. Glue only.
//   node .github/scripts/gate-smoke.mjs --engine chromium|playwright-webkit
// The gate's page protocol has a 180 s timeout per call. If an engine hangs on a page (MEASURED once: in an arm64 Linux
// Docker container the original page never answers Runtime.callFunctionOn after Emulation.setDeviceMetricsOverride to a
// width of 1000 px or more, while 430 px and the rewrite are fine), a shard would burn its whole job budget. This first checks
// that FW_SEARCH names a prerendered page (configs.json), then opens both
// arms at a narrow and a wide desktop width through the gate's own engine adapter and answers within 20 s each, or exits 1.
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { pathToFileURL } from 'node:url';

const SRC = resolve(dirname(fileURLToPath(import.meta.url)), '../../packages/gate-breakpoints/src');

const argv = process.argv.slice(2);
const engineName = argv[argv.indexOf('--engine') + 1];
if (!['chromium', 'playwright-webkit'].includes(engineName)) { console.error('usage: gate-smoke.mjs --engine chromium|playwright-webkit'); process.exit(2); }
const src = (f) => import(pathToFileURL(resolve(SRC, f)).href);
const { startServer, snapshotRoot, siteDist, rewriteFor } = await src('serve.mjs');
const { PIN_SRC } = await src('page.mjs');

const within = (p, ms, what) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error(`${what}: no answer in ${ms / 1000} s`)), ms))]);
const base = { height: 900, dpr: 1, hover: 'hover', pointer: 'fine', reducedMotion: 'no-preference', colorScheme: 'light' };
let variant;
try {
  variant = rewriteFor(siteDist());
} catch (e) {
  console.error(`FAIL FW_SEARCH does not resolve: ${e.message}`);
  process.exit(1);
}
console.log(`ok   FW_SEARCH "${variant.search}" ${variant.hash ? `-> config ${variant.hash}` : '(default page)'}`);
const engines = await src('engines.mjs');
const servers = { orig: await startServer(snapshotRoot()), rewrite: await startServer(siteDist(), variant.rewrite) };
const engine = await engines.LAUNCHERS[engineName]();
let bad = 0;
for (const width of [430, 1440]) {
  for (const site of ['orig', 'rewrite']) {
    const env = { ...base, width, deviceWidth: width, deviceHeight: base.height };
    const label = `${engineName} ${site} ${width}px`;
    try {
      const s = await within(engine.open(env, { origin: servers[site].origin, path: '/', init: PIN_SRC }), 30000, `${label} open`);
      const v = await within(s.evaluate(() => 1 + 1), 20000, `${label} evaluate`);
      if (v !== 2) throw new Error(`${label}: evaluate returned ${v}`);
      await s.close().catch(() => {});
      console.log(`ok   ${label}`);
    } catch (e) {
      bad++;
      console.error(`FAIL ${e.message}`);
    }
  }
}
await within(engine.close(), 20000, 'close').catch(() => {});
process.exit(bad ? 1 : 0);
