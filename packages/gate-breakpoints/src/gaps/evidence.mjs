// Evidence collectors of the gaps lane for the engines that cannot reach a cell: Playwright WebKit at several DPRs, the
// macOS system WebKit at several page zooms (a small Swift WKWebView host), and the iOS Simulator (iPhone, iPad). Each
// returns records { mech, req, ...probeRecord } holding raw facts only (no decisions here; judge.mjs decides).
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { launchWebkit } from '../engines.mjs';
import { collectInPage } from '../page.mjs';
import { PKG } from '../serve.mjs';
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

/** Playwright WebKit (WebKit 27.2 on this Mac) at whole widths N+1 and several DPRs, plus hasTouch off/on. */
export async function playwrightDpr({ server, cfg }) {
  const engine = await launchWebkit();
  const out = [];
  try {
    for (const n of cfg.edges) {
      for (const dpr of [1, 1.1, 1.25, 2]) {
        const env = { width: n + 1, height: 900, deviceWidth: n + 1, deviceHeight: 900, dpr, hover: 'hover', pointer: 'fine', reducedMotion: 'no-preference', colorScheme: 'light' };
        const s = await engine.open(env, { origin: `http://127.0.0.1:${server.port}`, path: '/probe.html?tok=pw', init: () => {} });
        try { out.push({ mech: 'playwright-webkit/dpr', req: { width: env.width, dpr, hasTouch: false }, ...(await recordViaEvaluate(s, cfg)) }); } finally { await s.close(); }
      }
    }
    for (const [hover, pointer] of [['hover', 'fine'], ['none', 'fine'], ['hover', 'coarse'], ['none', 'coarse']]) {
      const env = { width: 1024, height: 768, deviceWidth: 1024, deviceHeight: 768, dpr: 2, hover, pointer, reducedMotion: 'no-preference', colorScheme: 'light' };
      const s = await engine.open(env, { origin: `http://127.0.0.1:${server.port}`, path: '/probe.html?tok=pw', init: () => {} });
      try { out.push({ mech: 'playwright-webkit/pair', req: { hover, pointer, hasTouch: hover === 'none' }, ...(await recordViaEvaluate(s, cfg)) }); } finally { await s.close(); }
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
      out.push({ mech: 'macos-wkwebview/pageZoom', req: { width: w, pageZoom: z }, ...recs[0] });
    } finally { child.kill(); }
    await sleep(300);
  }
  return out;
}

const simctl = (args) => spawnSync('xcrun', ['simctl', ...args], { encoding: 'utf8' });

/** iOS Simulator Safari. The caller holds the sim-lock. `loads` fresh Safari launches, each its own token. */
export async function simulator({ server, device, loads = 2, hostAddr = '127.0.0.1' }) {
  const out = [];
  for (let i = 0; i < loads; i++) {
    const tok = `sim-${device.label}-${i}`;
    simctl(['terminate', device.udid, 'com.apple.mobilesafari']);
    await sleep(500);
    const r = simctl(['openurl', device.udid, `http://${hostAddr}:${server.port}/probe.html?tok=${tok}`]);
    if (r.status !== 0) throw new Error(`simctl openurl failed: ${(r.stderr || '').trim().split('\n').pop()}`);
    const recs = await server.waitFor(tok, 1, 60000);
    await sleep(1500); // let a trailing resize record arrive; the judge uses the record with why == "load"
    out.push({ mech: 'ios-simulator-safari', req: { device: device.label, load: i }, ...server.records(tok).find((x) => x.why === 'load') ?? recs[0], later: server.records(tok).length - 1 });
  }
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

/** Find a stock device by name on the iOS 27.0 runtime (never creates or deletes one). */
export function findStock(name, runtimeSuffix = 'iOS-27-0') {
  const st = JSON.parse(simctl(['list', '-j', 'devices']).stdout);
  const hits = Object.entries(st.devices).filter(([rt]) => rt.endsWith(runtimeSuffix)).flatMap(([, ds]) => ds).filter((d) => d.name === name && d.isAvailable !== false);
  if (hits.length !== 1) throw new Error(`expected one "${name}" on ${runtimeSuffix}, found ${hits.length}`);
  return hits[0];
}
