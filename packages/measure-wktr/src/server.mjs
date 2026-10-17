// Serves the read-only original snapshot with ONE difference: the document at `/` gets
// `<script src="/__fw/harness.js"></script>` as the first child of <head> (a copy of index.html is written to a private
// temp dir; the snapshot is never written). The script is allowed by the page's own Content-Security-Policy
// (`script-src 'self' ...`), an inline script would not be. Everything else is measure-webkit's static server
// (no-store, ranges, the analytics loader answered with an empty script).
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { serveTree } from '../../measure-webkit/src/serve.mjs';

export const SCRIPT_TAG = '<script src="/__fw/harness.js"></script>';

/** Insert the harness tag right after the opening <head ...> tag. Throws if there is none (the page changed). */
export function injectHarness(html) {
  const m = /<head(\s[^>]*)?>/i.exec(html);
  if (!m) throw new Error('index.html has no <head> tag');
  const at = m.index + m[0].length;
  return html.slice(0, at) + SCRIPT_TAG + html.slice(at);
}

/**
 * @param {string} siteRoot snapshot/site
 * @param {string} harnessJs the script text
 * @returns {Promise<{port:number, url:string, requests:string[], close:()=>Promise<void>}>}
 */
export async function serveOriginal(siteRoot, harnessJs) {
  const dir = mkdtempSync(join(tmpdir(), 'fw-wktr-'));
  writeFileSync(join(dir, 'harness.js'), harnessJs);
  writeFileSync(join(dir, 'index.html'), injectHarness(readFileSync(join(siteRoot, 'index.html'), 'utf8')));
  const rewrite = (p) => (p === '/' || p === '/index.html' ? '/__fw/index.html' : null);
  const srv = await serveTree(siteRoot, { mounts: { '/__fw': dir }, rewrite });
  const close = srv.close;
  return { ...srv, close: async () => { await close(); rmSync(dir, { recursive: true, force: true }); } };
}
