// node src/cli.mjs run     --engine chromium|playwright-webkit|both --out out/<label> [--concurrency 4] [--probes id,block,...] [--sweeps id,...|none]
//                          [--parts engine.scroll,nav.hitTest,hero.countdown,hero.exit]   (pilot part ids of src/anchors.json; default all)
// node src/cli.mjs summary --out out/<label> [--parts id,...]   (reads <engine>.json files there, writes summary.json and summary.md;
//   --parts narrows the verdict to those parts, which the run must have covered; a narrowed run names covered and skipped parts)
import { resolve } from 'node:path';
import { PKG } from './serve.mjs';

const argv = process.argv.slice(2);
const cmd = argv[0];
const arg = (n, d) => { const i = argv.indexOf(`--${n}`); return i < 0 ? d : argv[i + 1]; };
const out = resolve(PKG, arg('out', 'out/run'));
// --parts a,b: undefined = all parts; an empty value is an error (selectParts throws), never "all".
const partsOpt = argv.includes('--parts') ? arg('parts', '').split(',').map((x) => x.trim()).filter(Boolean) : null;

if (cmd === 'run') {
  const { runEngine } = await import('./run.mjs');
  const e = arg('engine', 'both');
  const engines = e === 'both' ? ['chromium', 'playwright-webkit'] : [e];
  const list = (v) => (v === undefined ? null : v === 'none' ? [] : v.split(','));
  for (const engineName of engines) {
    await runEngine({ engineName, outDir: out, concurrency: Number(arg('concurrency', '4')), probeFilter: list(arg('probes')), sweepFilter: list(arg('sweeps')), partFilter: partsOpt });
  }
  process.exit(0); // the engines are closed; leftover handles (keep-alive sockets) must not hold the process
} else if (cmd === 'summary') {
  const { summarize } = await import('./summary.mjs');
  summarize(out, { parts: partsOpt });
} else {
  console.error('usage: cli.mjs run|summary --out DIR [...]');
  process.exit(2);
}
