// The probe page and its report server. The page is our own (nothing of the snapshot): it runs the same two in-page
// functions as the gate (page.mjs collectInPage for the 30 conditions and 4 neutral queries, inpage.mjs gapFacts for the
// exact media width, the gap queries and the 15 pointer queries) and POSTs one JSON record per call to /report.
// Used by the iOS Simulator lane, the macOS WKWebView zoom lane, the Playwright WebKit DPR lane and the device session.
import http from 'node:http';
import { collectInPage } from '../page.mjs';
import { gapFacts } from './inpage.mjs';

/** The page. cfg = { conditions, neutral, edges }. Query: ?tok=<token>&label=<text>. Sends on load, on resize and on tap. */
export function probeHtml(cfg) {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>fw gaps probe</title>
<style>body{font:14px/1.4 -apple-system,sans-serif;margin:12px}pre{white-space:pre-wrap;word-break:break-all;font-size:11px}button,input{font-size:16px}</style>
</head><body>
<div>label <input id="label" size="14"> <button id="send">send</button></div>
<div id="state">starting</div><pre id="out"></pre>
<script>
const CFG = ${JSON.stringify(cfg)};
const gapFacts = ${gapFacts.toString()};
const collectInPage = ${collectInPage.toString()};
const q = new URLSearchParams(location.search);
const tok = q.get('tok') || 'none';
document.getElementById('label').value = q.get('label') || '';
let seq = 0, timer = null;
async function send(why) {
  const gap = gapFacts({ edges: CFG.edges });
  const col = collectInPage({ site: 'probe', conditions: CFG.conditions, neutral: CFG.neutral, dprWanted: 0, widthWanted: 0, parts: {}, props: null, filter: '^$' });
  const rec = { tok, seq: seq++, why, label: document.getElementById('label').value, ua: navigator.userAgent, gap, truth: col.truth, truthLegacy: col.truthLegacy, neutral: col.neutral, observed: col.observed, viewport: col.viewport };
  (window.__gapRecords = window.__gapRecords || []).push(rec); // also readable over Web Inspector
  document.getElementById('out').textContent = JSON.stringify({ seq: rec.seq, why, label: rec.label, gap }, null, 1);
  try {
    const r = await fetch('/report', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(rec) });
    document.getElementById('state').textContent = 'sent #' + rec.seq + ' ' + r.status;
  } catch (e) { document.getElementById('state').textContent = 'POST failed: ' + e; }
}
const later = (why) => { clearTimeout(timer); timer = setTimeout(() => send(why), 700); };
window.addEventListener('resize', () => later('resize'));
if (window.visualViewport) window.visualViewport.addEventListener('resize', () => later('vv-resize'));
document.getElementById('send').addEventListener('click', () => send('tap'));
window.addEventListener('load', () => later('load'));
</script></body></html>
`;
}

/**
 * Server for the probe page: GET /probe.html, POST /report (collects records), GET /records?tok= (JSON list).
 * host '127.0.0.1' for the Simulator and the Mac; the device session passes '0.0.0.0' (LAN) and prints the address at
 * run time only. Returns { port, records(tok), waitFor(tok, n, ms), close }.
 */
export async function startProbeServer({ cfg, host = '127.0.0.1', port = 0 }) {
  const store = new Map();
  const waiters = [];
  const html = probeHtml(cfg);
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    if (req.method === 'GET' && url.pathname === '/probe.html') {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' }).end(html);
    } else if (req.method === 'POST' && url.pathname === '/report') {
      const chunks = [];
      req.on('data', (c) => chunks.push(c));
      req.on('end', () => {
        try {
          const rec = JSON.parse(Buffer.concat(chunks).toString('utf8'));
          const list = store.get(rec.tok) ?? [];
          list.push(rec);
          store.set(rec.tok, list);
          for (const w of waiters.slice()) w.check();
          res.writeHead(204).end();
        } catch { res.writeHead(400).end(); }
      });
    } else if (req.method === 'GET' && url.pathname === '/records') {
      res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(store.get(url.searchParams.get('tok')) ?? []));
    } else {
      res.writeHead(404).end();
    }
  });
  await new Promise((r) => server.listen(port, host, r));
  const records = (tok) => store.get(tok) ?? [];
  const waitFor = (tok, n, ms) => new Promise((resolve, reject) => {
    const w = {
      check: () => { if (records(tok).length >= n) { done(); resolve(records(tok)); } },
    };
    const t = setTimeout(() => { done(); reject(new Error(`no ${n} report(s) for ${tok} within ${ms} ms (got ${records(tok).length})`)); }, ms);
    const done = () => { clearTimeout(t); const i = waiters.indexOf(w); if (i >= 0) waiters.splice(i, 1); };
    waiters.push(w);
    w.check();
  });
  return { port: server.address().port, records, waitFor, close: () => new Promise((r) => { server.closeAllConnections?.(); server.close(r); }) };
}
