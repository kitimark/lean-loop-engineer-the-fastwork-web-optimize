import { join } from 'node:path';
const REPO = process.env.REPO;
const { startServer } = await import(join(REPO, 'packages/gate-breakpoints/src/serve.mjs'));
const { chromium } = await import(join(REPO, 'packages/visual-diff/node_modules/playwright-core/index.mjs'));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const FW = process.env.FW || 'morph.geom:on,morph.tween:geom-timed';
const server = await startServer(join(REPO, 'apps/site/dist/aot'));
const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
const out = {};
for (const [w, h] of (process.env.SIZES || '390x844,430x932,1280x800').split(',').map((s) => s.split('x').map(Number))) {
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, hasTouch: true, isMobile: w < 800, deviceScaleFactor: 1 });
  const p = await ctx.newPage();
  await p.addInitScript(() => { window.__tt = []; window.__fwTakeTrace = (e) => window.__tt.push({ ...e, t: performance.now() }); });
  await p.goto(`${server.origin}/?fw=${FW}`, { waitUntil: 'load' });
  await p.evaluate(async () => { for (let i = 0; i < 100 && !(window.__fw && window.__fw.hydrated); i++) await new Promise((r) => setTimeout(r, 50)); });
  const c = await ctx.newCDPSession(p);
  const touch = (type, y) => c.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x: Math.round(w / 2), y }] });
  const max = () => p.evaluate(() => document.documentElement.scrollHeight - innerHeight);
  const pos = () => p.evaluate(() => scrollY);
  await p.evaluate((k) => window.scrollTo(0, document.documentElement.scrollHeight - innerHeight - k), 2.5 * h);
  await sleep(300);
  const top = Math.min(880, h - 50);
  const stroke = async (dir) => {
    let y = dir > 0 ? top : 100;
    await touch('touchStart', y);
    while (dir > 0 ? y - 10 >= 100 : y + 10 <= top) { y -= dir * 10; await touch('touchMove', y); await sleep(16); }
    await touch('touchEnd', y);
    await sleep(33);
  };
  const m = await max();
  let strokes = 0;
  while ((await pos()) < m - 1 && strokes < 30) { await stroke(1); strokes++; }
  for (let i = 0; i < 3; i++) await stroke(1);
  await sleep(1200);
  for (let i = 0; i < 2; i++) await stroke(-1);
  await sleep(1200);
  const tt = await p.evaluate(() => window.__tt);
  const pushes = [];
  for (const e of tt) {
    if (e.kind === 'push') pushes.push({ from: +e.from.toFixed(3), to: e.to, takeFrameMs: null });
    else if (pushes.length) pushes.at(-1).takeFrameMs = Math.round(e.el);
  }
  out[`${w}x${h}`] = { strokes, scrollEnd: await pos(), max: m, pushes };
  await ctx.close();
}
await browser.close();
server.close();
console.log(JSON.stringify(out));
