import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { serveTree } from '../../measure-webkit/src/serve.mjs';
import { injectHarness } from './server.mjs';

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
