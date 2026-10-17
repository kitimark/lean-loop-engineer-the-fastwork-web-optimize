// Style-injection census. Loads a prerendered build in headless Chrome, waits for hydration, calls
// __fw.markMeasureStart(), then runs a scripted scroll and (second phase) discrete triggers (tab, menu, drawer,
// dialog). Counts every CSSOM / <style> / adoptedStyleSheets / Emotion cache.insert after the mark.
//   node scripts/census.mjs [--engine aot|runtime|both] [--runs N] [--chrome PATH] [--json out.json]
// PASS (aot) = 0 after the mark in the scroll phase AND in the trigger phase. The `runtime` build is the
// negative control: it must NOT pass (the census has to be able to see a plain-Emotion build insert styles).
import { createReadStream, existsSync } from 'node:fs';
import { readFile, stat, writeFile } from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';
import { webkit } from 'playwright-core';
import { checkMedia } from './media-check.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const arg = (name, dflt) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : dflt;
};
const engines = arg('engine', 'both') === 'both' ? ['aot', 'runtime'] : [arg('engine')];
const runs = Number(arg('runs', '1'));
const chromePath =
  arg('chrome') ?? process.env.CHROME_PATH ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const query = arg('query', '');
const engineName = arg('browser', 'chrome'); // chrome (puppeteer-core) | webkit (playwright-core)
if (engineName === 'chrome' && !existsSync(chromePath)) throw new Error(`Chrome not found at ${chromePath} (use --chrome or CHROME_PATH)`);

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json' };
function serve(dir) {
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x');
    let file = path.join(dir, decodeURIComponent(url.pathname));
    if (!file.startsWith(dir)) return void res.writeHead(403).end();
    if (url.pathname === '/favicon.ico') return void res.writeHead(204).end();
    if (url.pathname.endsWith('/')) file = path.join(file, 'index.html');
    try {
      if (!(await stat(file)).isFile()) throw new Error('nf');
      res.writeHead(200, { 'content-type': MIME[path.extname(file)] ?? 'application/octet-stream' });
      createReadStream(file).pipe(res);
    } catch {
      res.writeHead(404).end('not found');
    }
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const hooks = await readFile(path.join(root, 'scripts/census-hooks.js'), 'utf8');

async function censusOnce(browser, engine, port) {
  const wk = engineName === 'webkit';
  const page = wk ? await browser.newPage({ viewport: { width: 430, height: 932 } }) : await browser.newPage();
  if (!wk) await page.setViewport({ width: 430, height: 932, deviceScaleFactor: 1 });
  const consoleErrors = [];
  page.on('console', (m) => m.type() === 'error' && consoleErrors.push(m.text()));
  page.on('pageerror', (e) => consoleErrors.push(String(e)));
  if (wk) await page.addInitScript(hooks);
  else await page.evaluateOnNewDocument(hooks);

  await page.goto(`http://127.0.0.1:${port}/${query}`, { waitUntil: 'load' });
  await page.waitForFunction(() => window.__fw?.hydrated === true, ...(wk ? [null, { timeout: 10000 }] : [{ timeout: 10000 }]));
  await sleep(800); // W-rest: let hydration effects and the countdown settle
  const flush = () => page.evaluate(() => window.__census.flush());
  await flush();

  await page.evaluate(() => window.__fw.markMeasureStart());

  // Phase "scroll": scripted scroll down and back, one step per frame.
  await page.evaluate(async () => {
    const step = () => new Promise((r) => requestAnimationFrame(() => r()));
    const max = document.documentElement.scrollHeight - innerHeight;
    for (let y = 0; y <= max; y += 40) {
      scrollTo(0, y);
      await step();
    }
    for (let y = max; y >= 0; y -= 80) {
      scrollTo(0, y);
      await step();
    }
  });
  await sleep(300);
  await flush();
  const afterScroll = await page.evaluate(() => (window.__census.phase = 'trigger', window.__census.snapshot()));

  // Phase "trigger": discrete flips (S4/S12): tab change, menu, drawer, dialog (each opened, then closed).
  const click = async (sel) => {
    await page.click(sel);
    await sleep(450);
    await flush();
  };
  await click('#tab-1');
  await click('#tab-2');
  for (const sel of ['#open-menu', '#open-drawer', '#open-dialog']) {
    await click(sel);
    await page.keyboard.press('Escape');
    await sleep(450);
    await flush();
  }
  await sleep(300);
  await flush();

  const out = await page.evaluate(() => {
    const c = window.__census;
    return {
      events: c.events,
      start: c.start,
      end: c.snapshot(),
      fw: {
        mode: window.__fw.mode,
        configHash: window.__fw.configHash,
        buildId: window.__fw.buildId,
        hydrationErrors: window.__fw.hydrationErrors,
        styleMisses: window.__fw.styleMisses,
      },
      overlaysOpen: document.querySelectorAll('[role="dialog"], [role="menu"]').length,
    };
  });
  await page.close();

  const post = out.events.filter((e) => e.armed);
  const by = (phase) => post.filter((e) => e.phase === phase);
  const misses = out.fw.styleMisses.filter((m) => m.afterMark);
  return {
    engine,
    mode: out.fw.mode,
    configHash: out.fw.configHash,
    load: { events: out.events.filter((e) => !e.armed).length, cacheInserts: out.fw.styleMisses.length - misses.length },
    scroll: { events: by('scroll'), count: by('scroll').length },
    trigger: { events: by('trigger'), count: by('trigger').length },
    cacheInsertsAfterMark: misses.length,
    cacheInsertIds: misses.map((m) => m.id),
    cacheInsertStyles: misses.map((m) => m.styles),
    rulesAtMark: out.start?.rules,
    rulesAfterScroll: afterScroll.rules,
    rulesAtEnd: out.end.rules,
    sheetsAtMark: out.start?.sheets,
    sheetsAtEnd: out.end.sheets,
    hydrationErrors: out.fw.hydrationErrors,
    consoleErrors,
  };
}

const browser =
  engineName === 'webkit'
    ? await webkit.launch()
    : await puppeteer.launch({ executablePath: chromePath, headless: true });
const report = { browser: engineName, chrome: engineName === 'webkit' ? `WebKit ${browser.version()}` : await browser.version(), runs, results: [] };
let exit = 0;
try {
  for (const engine of engines) {
    const dir = path.join(root, 'dist', engine);
    if (!existsSync(path.join(dir, 'index.html'))) throw new Error(`dist/${engine} missing: run the build first`);
    const server = await serve(dir);
    const port = server.address().port;
    for (let i = 0; i < runs; i++) report.results.push(await censusOnce(browser, engine, port));
    server.close();
  }
} finally {
  await browser.close();
}

const pad = (s, n) => String(s).padEnd(n);
console.log(`${report.chrome}, ${runs} run(s) per build, viewport 430x932, query "${query}"\n`);
console.log(pad('engine', 9) + pad('mode', 10) + pad('scroll', 8) + pad('trigger', 9) + pad('cache.insert', 14) + pad('rules mark->end', 18) + 'verdict');
for (const r of report.results) {
  const total = r.scroll.count + r.trigger.count + r.cacheInsertsAfterMark;
  const verdict =
    r.engine === 'aot'
      ? r.scroll.count === 0 && r.trigger.count === 0 && r.cacheInsertsAfterMark === 0 && r.hydrationErrors.length === 0
        ? 'PASS'
        : 'FAIL'
      : total > 0
        ? 'CONTROL CAUGHT (non-zero, as expected)'
        : 'CONTROL MISSED (census is blind)';
  r.verdict = verdict;
  if (verdict === 'FAIL' || verdict === 'CONTROL MISSED (census is blind)') exit = 1;
  console.log(
    pad(r.engine, 9) + pad(r.mode, 10) + pad(r.scroll.count, 8) + pad(r.trigger.count, 9) +
      pad(r.cacheInsertsAfterMark, 14) + pad(`${r.rulesAtMark}->${r.rulesAtEnd}`, 18) + verdict,
  );
  if (r.hydrationErrors.length) console.log('   hydration errors:', r.hydrationErrors);
  if (r.consoleErrors.length) console.log('   console errors:', r.consoleErrors.slice(0, 3));
  if (process.env.CENSUS_VERBOSE) for (const s of r.cacheInsertStyles) console.log('   miss:', s);
  const kinds = {};
  for (const e of [...r.scroll.events, ...r.trigger.events]) kinds[`${e.phase}:${e.kind}`] = (kinds[`${e.phase}:${e.kind}`] ?? 0) + 1;
  if (Object.keys(kinds).length) console.log('   events:', JSON.stringify(kinds));
}
if (engines.includes('aot')) {
  const m = await checkMedia(root, 'aot');
  console.log(`\n@media check (dist/aot): ${m.ok ? 'PASS' : 'FAIL'}`);
  console.log('   in breakpoints.gen.json:', JSON.stringify(m.fromGen));
  console.log('   MUI feature queries (mui-internal-media.json):', JSON.stringify(m.fromInternal));
  if (!m.ok) {
    console.log('   NOT ALLOWED:', JSON.stringify(m.unknown));
    exit = 1;
  }
  report.media = m;
}
const outFile = arg('json');
if (outFile) await writeFile(outFile, JSON.stringify(report, null, 2));
process.exit(exit);
