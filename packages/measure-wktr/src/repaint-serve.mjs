// Serves a prerendered build of apps/site (dist/aot) with the repaint script as the first child of <head>, like server.mjs does
// for the snapshot. "/" is answered with the HTML of the config hash of `search` (configs.json); nothing is written to the build.
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { serveTree } from '../../measure-webkit/src/serve.mjs';
import { injectHarness } from './server.mjs';

/**
 * @param {string} distDir apps/site/dist/aot
 * @param {string} search the query of the arm ('' or '?preset=v2-proved'); must be prerendered
 * @param {string} harnessJs the script text
 * @returns {Promise<{port:number, url:string, hash:string, requests:string[], close:()=>Promise<void>}>}
 */
export async function serveBuilt(distDir, search, harnessJs) {
  const cfg = JSON.parse(readFileSync(join(distDir, 'configs.json'), 'utf8'));
  const hash = cfg.bySearch[search];
  if (!hash) throw new Error(`search "${search}" is not prerendered; known: ${Object.keys(cfg.bySearch).join(' | ')}`);
  const dir = mkdtempSync(join(tmpdir(), 'fw-wktr-built-'));
  writeFileSync(join(dir, 'harness.js'), harnessJs);
  writeFileSync(join(dir, 'index.html'), injectHarness(readFileSync(join(distDir, cfg.byHash[hash]), 'utf8')));
  const rewrite = (p) => (p === '/' || p === '/index.html' ? '/__fw/index.html' : null);
  const srv = await serveTree(distDir, { mounts: { '/__fw': dir }, rewrite });
  const close = srv.close;
  return { ...srv, hash, close: async () => { await close(); rmSync(dir, { recursive: true, force: true }); } };
}
