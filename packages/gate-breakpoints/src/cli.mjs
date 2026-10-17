// node src/cli.mjs run     --engine chromium|playwright-webkit|both --out out/<label> [--concurrency 4] [--probes id,block,...] [--sweeps id,...|none]
// node src/cli.mjs summary --out out/<label>      (reads <engine>.json files there, writes summary.json and summary.md)
import { resolve } from 'node:path';
import { PKG } from './serve.mjs';

const argv = process.argv.slice(2);
const cmd = argv[0];
const arg = (n, d) => { const i = argv.indexOf(`--${n}`); return i < 0 ? d : argv[i + 1]; };
const out = resolve(PKG, arg('out', 'out/run'));

if (cmd === 'run') {
  const { runEngine } = await import('./run.mjs');
  const e = arg('engine', 'both');
  const engines = e === 'both' ? ['chromium', 'playwright-webkit'] : [e];
  const list = (v) => (v === undefined ? null : v === 'none' ? [] : v.split(','));
  for (const engineName of engines) {
    await runEngine({ engineName, outDir: out, concurrency: Number(arg('concurrency', '4')), probeFilter: list(arg('probes')), sweepFilter: list(arg('sweeps')) });
  }
  process.exit(0); // the engines are closed; leftover handles (keep-alive sockets) must not hold the process
} else if (cmd === 'summary') {
  const { summarize } = await import('./summary.mjs');
  summarize(out);
} else {
  console.error('usage: cli.mjs run|summary --out DIR [...]');
  process.exit(2);
}
