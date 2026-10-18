#!/usr/bin/env node
// Runs every premise test (src/tests.mjs) on one engine and writes out/<engine>.json:
//   { schema, engine, browser, tests: [{id, premise}], results: [{testId, engine, ok, observed?, error?}] }
// `fw premises --results out` (apps/runner/src/premises.ts) checks that file against the Lean registry golden.
//
//   node src/run.mjs --engine chromium|playwright-webkit [--out out] [--only prem.id,...]
//
// Chromium: Playwright's launcher on $CHROME_PATH (the pinned Chrome Headless Shell the gate-engine action installs);
// without it Playwright's own browser, or $PREMISE_CHANNEL (e.g. chrome) for a local debug run. WebKit: Playwright's build.
// The exit code is 0 even when a premise fails (the verdict is `fw premises`); 1 only when the harness itself breaks.
import { chromium, webkit } from 'playwright-core';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { TESTS } from './tests.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (name, dflt) => { const i = args.indexOf(`--${name}`); return i >= 0 && args[i + 1] ? args[i + 1] : dflt; };
const engineArg = opt('engine', 'chromium');
const engine = engineArg === 'playwright-webkit' || engineArg === 'webkit' ? 'webkit' : engineArg === 'chromium' ? 'chromium' : null;
if (!engine) { console.error('usage: node src/run.mjs --engine chromium|playwright-webkit [--out dir] [--only id,...]'); process.exit(64); }
const out = resolve(opt('out', join(here, '..', 'out')));
const only = opt('only', '') ? opt('only', '').split(',') : null;
const selected = TESTS.filter((t) => !only || only.includes(t.id));

const browser = engine === 'webkit'
  ? await webkit.launch()
  : await chromium.launch({ ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}), ...(process.env.PREMISE_CHANNEL ? { channel: process.env.PREMISE_CHANNEL } : {}) });
const results = [];
try {
  for (const t of selected) {
    const context = await browser.newContext({ viewport: { width: 800, height: 600 } });
    const page = await context.newPage();
    const pageErrors = [];
    page.on('pageerror', (e) => pageErrors.push(String(e)));
    const r = { testId: t.id, engine, ok: false };
    const t0 = Date.now();
    try {
      await page.goto(pathToFileURL(join(here, '..', 'pages', t.page)).href, { waitUntil: 'load' });
      r.observed = (await t.run({ page, engine })) ?? null;
      r.ok = pageErrors.length === 0;
      if (pageErrors.length) r.error = `page errors: ${pageErrors.join('; ')}`;
    } catch (e) {
      if (e && e.observed) r.observed = e.observed;
      r.error = String(e && e.message ? e.message : e).split('\n').slice(0, 6).join('\n');
    }
    r.ms = Date.now() - t0;
    results.push(r);
    console.log(`${r.ok ? 'ok  ' : 'FAIL'} ${engine.padEnd(8)} ${t.id}${r.ok ? '' : `\n     ${r.error}`}`);
    await context.close();
  }
  const doc = { schema: 1, engine, browser: browser.version(), playwrightCore: '1.64.1',
    tests: TESTS.map((t) => ({ id: t.id, premise: t.premise })), results };
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, `${engine}.json`), `${JSON.stringify(doc, null, 2)}\n`);
  console.log(`${engine} ${browser.version()}: ${results.filter((r) => r.ok).length}/${results.length} premises hold; wrote ${join(out, `${engine}.json`)}`);
} finally {
  await browser.close();
}
