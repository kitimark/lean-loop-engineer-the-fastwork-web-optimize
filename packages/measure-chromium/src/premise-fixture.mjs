// Engine premise fixture page (task engine-premise-measure). Generated from the Lean golden (golden/ops/engine-premises.jsonl):
// one box per `set` step, in a grid of fixed-size cells (so no box moves another), and the step table the driver runs.
//
//   node src/premise-fixture.mjs --engine chromium --out <dir>     writes <dir>/index.html
//
// The page does exactly what the step says, once per frame: set one inline property (`set`), register one rAF callback
// (`raf`), call document.elementFromPoint (`hit`), or nothing (`idle`). Chromium: the driver calls window.__fwStep(n) inside
// frame n's mark window (run.mjs input mode "page"). WebKit: the WKTR harness calls it from its rAF (packages/measure-wktr).
// Pure apart from the CLI; no site code, no decisions (what to do and what to expect are the golden's).
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, resolve } from 'node:path';
import { loadGolden } from './premise-verdict.mjs';

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** The step table the page runs: one entry per golden step, `id` is the box of a `set` step. */
export function stepTable(golden, engine) {
  return golden.steps[engine].map((s) => (s.act === 'set' ? { a: 'set', id: `e${s.step}`, p: s.prop, v: s.to } : { a: s.act }));
}

/** The page's HTML. */
export function pageHtml(golden, engine) {
  const steps = golden.steps[engine];
  const boxes = steps.filter((s) => s.act === 'set')
    .map((s) => `<div class="c"><div id="e${s.step}" style="${esc(golden.page.baseStyle + s.style)}">A</div></div>`).join('\n');
  const table = JSON.stringify(stepTable(golden, engine));
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Engine premise fixture (${engine})</title>
<style>body { margin: 0; } #g { display: flex; flex-wrap: wrap; width: 400px; } .c { position: relative; width: 30px; height: 30px; margin: 1px; }</style>
</head><body><div id="g">
${boxes}
<div class="c"><div id="w" style="${esc(golden.page.baseStyle)}position:relative;">A</div></div>
</div>
<script>
  // Generated from golden/ops/engine-premises.jsonl; one entry per step.
  window.__fwSteps = ${table};
  // Throwaway changes before the first step (warm-up frames of the Chromium driver; the WebKit driver does not call this).
  window.__fwWarm = function (i) { document.getElementById('w').style.transform = 'translateX(' + (i + 1) + 'px)'; };
  window.__fwStep = function (n) {
    const s = window.__fwSteps[n];
    if (!s) return 'no step ' + n;
    if (s.a === 'set') document.getElementById(s.id).style.setProperty(s.p, s.v);
    else if (s.a === 'raf') requestAnimationFrame(function () {});
    else if (s.a === 'hit') document.elementFromPoint(10, 10);
    return s.a;
  };
</script></body></html>
`;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const argv = process.argv.slice(2);
  const opt = (n, d) => { const i = argv.indexOf(`--${n}`); return i >= 0 ? argv[i + 1] : d; };
  const engine = opt('engine', 'chromium');
  const out = opt('out', null);
  const golden = loadGolden();
  if (argv.includes('--count')) { console.log(golden.steps[engine].length); process.exit(0); } // the number of steps (frames) of the engine's run
  if (!out) { console.error('usage: premise-fixture.mjs --engine chromium|webkit (--out <dir> | --count)'); process.exit(2); }
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, 'index.html'), pageHtml(golden, engine));
  console.error(`wrote ${join(out, 'index.html')} (${golden.steps[engine].length} steps)`);
}
