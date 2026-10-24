import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { startServer, snapshotRoot, siteDist, rewriteFor } from '../serve.mjs';
import { envFor } from './registry.mjs';
import { REC, RAMP, selectorsFor, SEQUENCES, variantCss, styleInit } from './transitions.mjs';

const log = (...a) => process.stderr.write(a.join(' ') + '\n');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export function client(base) {
  let sid = null;
  const call = async (method, path, body) => {
    const res = await fetch(`${base}${path}`, { method, headers: { 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
    const j = await res.json().catch(() => ({}));
    if (!res.ok || (j.value && j.value.error)) throw new Error(`${method} ${path}: ${j.value?.error ?? res.status} ${String(j.value?.message ?? '').slice(0, 200)}`);
    return j.value;
  };
  return {
    async open() {
      const v = await call('POST', '/session', { capabilities: { alwaysMatch: { browserName: 'safari' } } });
      sid = v.sessionId;
      return v.capabilities;
    },
    goto: (url) => call('POST', `/session/${sid}/url`, { url }),
    rect: (r) => call('POST', `/session/${sid}/window/rect`, r),
    sync: (script, args = []) => call('POST', `/session/${sid}/execute/sync`, { script, args }),
    async: (script, args = []) => call('POST', `/session/${sid}/execute/async`, { script, args }),
    async close() { if (sid) { await call('DELETE', `/session/${sid}`).catch(() => {}); sid = null; } },
  };
}

async function walkPage(c, arm, mode, width) {
  const sel = selectorsFor(arm.site);
  await c.goto('about:blank');
  await c.goto(`${arm.origin}/${arm.search ?? ''}`);
  for (let k = 0; k < 40; k++) {
    if (await c.sync('return document.readyState === "complete" && !!document.querySelector(arguments[0])', [sel.nav]).catch(() => false)) break;
    await sleep(250);
  }
  await sleep(3000);
  if (arm.variant) await c.sync(`${styleInit(variantCss(arm.variant, sel.earn))} return true;`);
  const diag = async () => c.sync(DIAG, [sel.nav, sel.earn]);
  const diagStart = await diag();
  await c.sync(`${REC} window.__sc = 0; window.addEventListener('scroll', () => { window.__sc += 1; }, { passive: true }); return true;`);
  await c.sync('window.scrollTo({ top: 0, left: 0, behavior: "instant" }); return true;');
  await sleep(900);
  const sequences = {};
  const record = async (seq, body) => {
    await c.sync('return window.__rec.start(arguments[0], arguments[1]);', [sel, mode]);
    await body();
    sequences[seq] = await c.sync('return window.__rec.stop();');
  };
  const ramp = (a) => c.async('const cb = arguments[arguments.length - 1]; window.__rec.ramp(arguments[0]).then(cb);', [a]);
  await record('hero-exit', async () => {
    await sleep(RAMP.preMs);
    await c.sync('return window.__rec.mark("ramp");');
    await ramp({ fromVh: 0, toVh: RAMP.toVh, ms: RAMP.ms });
    await sleep(RAMP.holdMs);
  });
  await record('hero-entry', async () => {
    await sleep(RAMP.preMs);
    await c.sync('return window.__rec.mark("ramp");');
    await ramp({ fromVh: RAMP.toVh, toVh: 0, ms: RAMP.ms });
    await sleep(RAMP.holdMs);
  });
  const inner = await c.sync('return [window.innerWidth, window.innerHeight];');
  return { sequences, inner, diag: { start: diagStart, end: await diag() } };
}

const DIAG = `const q = (m) => window.matchMedia(m).matches;
const n = document.querySelector(arguments[0]); const e = document.querySelector(arguments[1]);
return { reduce: q('(prefers-reduced-motion: reduce)'), hover: q('(hover: hover)'), fine: q('(pointer: fine)'), vis: document.visibilityState,
  focus: document.hasFocus(), navClass: n ? n.className : null, earnTr: e ? getComputedStyle(e).transitionProperty : null, y: window.scrollY, ua: navigator.userAgent,
  fw: window.__fw ? { mode: window.__fw.mode ?? null, config: window.__fw.configHash ?? null } : null, scrollEvents: window.__sc ?? null,
  scripts: performance.getEntriesByType('resource').filter((r) => /\\.js(\\?|$)/.test(r.name)).map((r) => [r.name.split('/').pop().slice(0, 24), r.responseStatus ?? null, Math.round(r.duration)]).slice(0, 12),
  body: document.body.innerText.length, svelte: !!document.querySelector('[class*="svelte-"]') };`;

export async function captureSafari({ port, width, reps, out, variants = [], search = '', env = process.env }) {
  mkdirSync(out, { recursive: true });
  const orig = await startServer(snapshotRoot(env));
  const rewrite = await startServer(siteDist(env));
  const flag = search ? rewriteFor(siteDist(env), { ...env, FW_SEARCH: search }) : null;
  if (search && !flag.rewrite) throw new Error(`no flagged config for ${search}`);
  const flagged = flag ? await startServer(siteDist(env), flag.rewrite) : null;
  const c = client(`http://127.0.0.1:${port}`);
  const runs = [];
  let caps = null;
  try {
    caps = await c.open();
    const e = envFor(width);
    await c.rect({ x: 0, y: 0, width, height: e.height + 120 });
    const arms = [{ site: 'orig', role: 'orig', origin: orig.origin }, { site: 'rewrite', role: 'faithful', origin: rewrite.origin },
      ...(flagged ? [{ site: 'rewrite', role: 'flag', origin: flagged.origin, search }] : []),
      ...variants.map((v) => ({ site: 'rewrite', role: `faithful+${v}`, origin: rewrite.origin, variant: v }))];
    for (const arm of arms) {
      const modes = arm.variant ? ['full', 'full'] : [...Array.from({ length: reps }, () => 'full'), 'light'];
      for (let k = 0; k < modes.length; k++) {
        const t0 = Date.now();
        const one = await walkPage(c, arm, modes[k], width);
        runs.push({ width, role: arm.role, mode: modes[k], rep: k, identity: 'ok', inner: one.inner, diag: one.diag, sequences: one.sequences });
        log(`safari ${width} ${arm.role} ${modes[k]} #${k}: ${Date.now() - t0} ms, inner ${one.inner.join('x')}, rows ${SEQUENCES.map((q) => one.sequences[q]?.rows.length ?? 0).join('/')}`);
      }
    }
  } finally {
    await c.close();
    await orig.close(); await rewrite.close();
    if (flagged) await flagged.close();
  }
  const version = caps ? `${caps.browserName} ${caps.browserVersion ?? ''}`.trim() : 'unknown';
  const file = join(out, `transitions-safari-${width}.json`);
  writeFileSync(file, JSON.stringify({ engine: 'safari', version, reps, ramp: RAMP, note: 'hero sequences only; window set by the driver', selectors: { orig: selectorsFor('orig'), rewrite: selectorsFor('rewrite') }, runs }));
  return file;
}

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(`--${k}`); return i >= 0 ? args[i + 1] : d; };
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const f = await captureSafari({ port: Number(opt('port', '4444')), width: Number(opt('width', '1280')), reps: Number(opt('reps', '3')), out: opt('out'), variants: opt('variants', '').split(',').filter(Boolean), search: opt('search', '') });
  log(`wrote ${f}`);
}
