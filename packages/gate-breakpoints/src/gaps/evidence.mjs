// Evidence collectors of the gaps lane for the engines that cannot reach a cell: Playwright WebKit at several DPRs, the
// macOS system WebKit at several page zooms (a small Swift WKWebView host), and the iOS Simulator (iPhone, iPad). Each
// returns records { mech, port, req, ...probeRecord } holding raw facts only (no decisions here; judge.mjs asks Lean).
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { launchWebkit } from '../engines.mjs';
import { PIN_SRC, collectInPage, waitReady } from '../page.mjs';
import { portOf } from '../run.mjs';
import { PKG, siteDist, snapshotRoot, startServer } from '../serve.mjs';
import { gapFacts } from './inpage.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => process.stderr.write(a.join(' ') + '\n');

/** The record the probe page would POST, built from a Playwright page instead (same two in-page functions). */
async function recordViaEvaluate(session, cfg) {
  const gap = await session.evaluate(gapFacts, { edges: cfg.edges });
  const col = await session.evaluate(collectInPage, { site: 'probe', conditions: cfg.conditions, neutral: cfg.neutral, dprWanted: 0, widthWanted: 0, parts: {}, props: null, filter: '^$' });
  return { gap, truth: col.truth, truthLegacy: col.truthLegacy, neutral: col.neutral, observed: col.observed, viewport: col.viewport };
}

/** Playwright WebKit (the Apple port on macOS, the GLib port on Linux) at whole widths N+1 and several DPRs, plus hasTouch off/on. */
export async function playwrightDpr({ server, cfg }) {
  const engine = await launchWebkit();
  const port = portOf('playwright-webkit');
  const out = [];
  try {
    for (const n of cfg.edges) {
      for (const dpr of [1, 1.1, 1.25, 2]) {
        const env = { width: n + 1, height: 900, deviceWidth: n + 1, deviceHeight: 900, dpr, hover: 'hover', pointer: 'fine', reducedMotion: 'no-preference', colorScheme: 'light' };
        const s = await engine.open(env, { origin: `http://127.0.0.1:${server.port}`, path: '/probe.html?tok=pw', init: () => {} });
        try { out.push({ mech: 'playwright-webkit/dpr', port, req: { width: env.width, dpr, hasTouch: false }, ...(await recordViaEvaluate(s, cfg)) }); } finally { await s.close(); }
      }
    }
    for (const [hover, pointer] of [['hover', 'fine'], ['none', 'fine'], ['hover', 'coarse'], ['none', 'coarse']]) {
      const env = { width: 1024, height: 768, deviceWidth: 1024, deviceHeight: 768, dpr: 2, hover, pointer, reducedMotion: 'no-preference', colorScheme: 'light' };
      const s = await engine.open(env, { origin: `http://127.0.0.1:${server.port}`, path: '/probe.html?tok=pw', init: () => {} });
      try { out.push({ mech: 'playwright-webkit/pair', port, req: { hover, pointer, hasTouch: hover === 'none' }, ...(await recordViaEvaluate(s, cfg)) }); } finally { await s.close(); }
    }
  } finally { await engine.close(); }
  return out;
}

/** Compile the Swift host once into out/ (gitignored). */
export function buildWkzoom() {
  const bin = join(PKG, 'out', 'gaps-bin', 'wkzoom');
  if (existsSync(bin)) return bin;
  mkdirSync(dirname(bin), { recursive: true });
  const r = spawnSync('swiftc', ['-O', join(HERE, 'wkzoom.swift'), '-o', bin], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`swiftc failed: ${(r.stderr || '').split('\n').slice(0, 5).join(' | ')}`);
  return bin;
}

/** macOS system WebKit through a WKWebView with pageZoom. cases: [[width, pageZoom]]. Kills only the host PIDs it started. */
export async function macZoom({ server, cases, height = 900 }) {
  const bin = buildWkzoom();
  const out = [];
  for (const [w, z] of cases) {
    const tok = `mac-${w}-${z}`;
    const child = spawn(bin, [`http://127.0.0.1:${server.port}/probe.html?tok=${tok}`, String(w), String(height), String(z), '30'], { stdio: 'ignore' });
    try {
      const recs = await server.waitFor(tok, 1, 25000);
      out.push({ mech: 'macos-wkwebview/pageZoom', port: 'webkit-apple', req: { width: w, pageZoom: z }, ...recs[0] });
    } finally { child.kill(); }
    await sleep(300);
  }
  return out;
}

/**
 * Informative A=R row on macOS system WebKit at pageZoom 2, window width 1201 (the 200% browser zoom of the Chromium cells,
 * request 600.5): WebKit maps the fractional viewport (visualViewport 600.5) to the next whole media width (601). Loads the
 * original and the rewrite in the WKWebView host, waits for each to settle, and collects the same matchMedia facts as the
 * gate (no part elements). One record { mech, port, req, orig: { settle, raw }, rewrite: { settle, raw } }; Lean compares the
 * two arms (summary), nothing is decided here.
 */
export async function macAR({ cfg, width = 1201, pageZoom = 2, height = 900 }) {
  const bin = buildWkzoom();
  const servers = { orig: await startServer(snapshotRoot()), rewrite: await startServer(siteDist()) };
  const CAP = { orig: 20000, rewrite: 15000 };
  const dir = mkdtempSync(join(tmpdir(), 'fw-gaps-ar-'));
  const rec = { mech: 'macos-wkwebview/pageZoom-AR', port: 'webkit-apple', req: { width, pageZoom, height } };
  try {
    for (const site of ['orig', 'rewrite']) {
      const plan = {
        init: PIN_SRC,
        calls: [
          { fn: waitReady.toString(), arg: { site, capMs: CAP[site] } },
          { fn: collectInPage.toString(), arg: { site, conditions: cfg.conditions, neutral: cfg.neutral, dprWanted: 0, widthWanted: 0, parts: {}, props: null, filter: '^$' } },
          { fn: gapFacts.toString(), arg: { edges: cfg.edges } },
        ],
      };
      const file = join(dir, `${site}.json`);
      writeFileSync(file, JSON.stringify(plan));
      const out = await runHost(bin, [`${servers[site].origin}/`, String(width), String(height), String(pageZoom), '90', file], 100000);
      const [settle, raw, gap] = JSON.parse(out);
      rec[site] = { settle, raw: { ...raw, gap } };
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
    await Promise.all(Object.values(servers).map((x) => x.close()));
  }
  return rec;
}

/** Run the Swift host to completion and return its stdout; kills only the child it started. */
function runHost(bin, args, ms) {
  return new Promise((resolve, reject) => {
    const child = spawn(bin, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '', err = '';
    child.stdout.on('data', (d) => { out += d; });
    child.stderr.on('data', (d) => { err += d; });
    const t = setTimeout(() => { child.kill(); reject(new Error(`wkzoom timed out after ${ms} ms`)); }, ms);
    child.on('exit', (code) => { clearTimeout(t); if (code === 0) resolve(out); else reject(new Error(`wkzoom exit ${code}: ${err.trim().split('\n').pop()}`)); });
  });
}

const simctl = (args) => spawnSync('xcrun', ['simctl', ...args], { encoding: 'utf8' });

/**
 * iOS Simulator Safari. The caller holds the sim-lock (or is a CI job). `loads` fresh Safari launches of the plain probe page,
 * then one load per probe variant (cells.mjs probeVariants: fractional meta viewports, the iOS rounding path), each its own
 * token. The record kept is the last one after the page settled.
 */
export async function simulator({ server, device, variants = [], loads = 2, hostAddr = '127.0.0.1' }) {
  const out = [];
  const one = async (tok, query, req) => {
    simctl(['terminate', device.udid, 'com.apple.mobilesafari']);
    await sleep(500);
    const r = simctl(['openurl', device.udid, `http://${hostAddr}:${server.port}/probe.html?tok=${tok}${query ? `&${query}` : ''}`]);
    if (r.status !== 0) throw new Error(`simctl openurl failed: ${(r.stderr || '').trim().split('\n').pop()}`);
    await server.waitFor(tok, 1, 60000);
    await sleep(2000); // let the trailing records arrive; the last one is the settled page
    const recs = server.records(tok);
    out.push({ mech: 'ios-simulator-safari', port: 'webkit-apple', req, ...recs[recs.length - 1], later: recs.length - 1 });
  };
  for (let i = 0; i < loads; i++) await one(`sim-${device.label}-${i}`, '', { device: device.label, load: i });
  for (const v of variants) await one(`sim-${device.label}-${v.id}`, v.query, { device: device.label, variant: v.id, aimed: v.aimed });
  return out;
}

/** Boot a Simulator device if it is not booted; returns whether this call booted it (so the caller can shut it down). */
export function ensureBooted(udid) {
  const st = JSON.parse(simctl(['list', '-j', 'devices']).stdout);
  const d = Object.values(st.devices).flat().find((x) => x.udid === udid);
  if (!d) throw new Error('device not found');
  if (d.state === 'Booted') return false;
  log(`  booting ${udid.slice(0, 8)} ...`);
  const b = simctl(['boot', udid]);
  if (b.status !== 0) throw new Error(`simctl boot failed: ${(b.stderr || '').trim().split('\n').pop()}`);
  const s = spawnSync('xcrun', ['simctl', 'bootstatus', udid, '-b'], { encoding: 'utf8', timeout: 300000 });
  if (s.status !== 0) throw new Error('bootstatus failed');
  return true;
}

export const shutdown = (udid) => simctl(['shutdown', udid]);

/** Find a stock device by name on the iOS 27.0 runtime (never creates or deletes one); null when there is none. */
export function findStock(name, runtimeSuffix = 'iOS-27-0') {
  const st = JSON.parse(simctl(['list', '-j', 'devices']).stdout);
  const hits = Object.entries(st.devices).filter(([rt]) => rt.endsWith(runtimeSuffix)).flatMap(([, ds]) => ds).filter((d) => d.name === name && d.isAvailable !== false);
  if (hits.length > 1) throw new Error(`expected one "${name}" on ${runtimeSuffix}, found ${hits.length}`);
  return hits[0] ?? null;
}

/**
 * Create a device of the named type on the iOS 27.0 runtime (CI only: the caller deletes it). Returns null with a reason when the
 * runtime or the device type is not installed.
 */
export function createDevice(label, typeName, runtimeSuffix = 'iOS-27-0') {
  const types = JSON.parse(simctl(['list', '-j', 'devicetypes']).stdout).devicetypes;
  const t = types.find((x) => (typeName instanceof RegExp ? typeName.test(x.name) : x.name === typeName));
  if (!t) return { reason: `device type ${typeName} not installed` };
  const rts = JSON.parse(simctl(['list', '-j', 'runtimes']).stdout).runtimes;
  const rt = rts.find((x) => x.isAvailable && x.identifier.endsWith(runtimeSuffix));
  if (!rt) return { reason: `runtime ${runtimeSuffix} not installed` };
  const r = simctl(['create', label, t.identifier, rt.identifier]);
  if (r.status !== 0) return { reason: `simctl create failed: ${(r.stderr || '').trim().split('\n').pop()}` };
  return { udid: r.stdout.trim(), name: label, created: true };
}

export const deleteDevice = (udid) => simctl(['delete', udid]);
