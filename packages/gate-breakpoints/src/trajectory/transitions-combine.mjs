import { mkdirSync, readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

export const METRICS = [['padL', 'maxJump'], ['padL', 'between'], ['padL', 'arriveMs'], ['earnW', 'maxJump'], ['langX', 'maxJump'], ['langX', 'between'], ['op', 'arriveMs']];

const med = (a) => { const b = [...a].sort((x, y) => x - y); const m = b.length >> 1; return b.length % 2 ? b[m] : (b[m - 1] + b[m]) / 2; };
const r2 = (v) => Math.round(v * 100) / 100;

export function combine(runs) {
  const rows = new Map();
  for (const { run, summaries } of runs) {
    for (const [key, s] of Object.entries(summaries)) {
      const [width, engine] = key.split('|');
      for (const c of s.cells) {
        const id = `${width}|${engine}|${c.role}|${c.seq}`;
        if (!rows.has(id)) rows.set(id, { width: Number(width), engine, role: c.role, seq: c.seq, runs: [], metrics: {} });
        const row = rows.get(id);
        row.runs.push(run);
        for (const [name, field] of METRICS) {
          const v = c.series[name]?.[field]?.median;
          if (typeof v !== 'number') continue;
          const k = `${name}.${field}`;
          (row.metrics[k] ??= []).push(v);
        }
        const cad = c.cadence?.median;
        if (typeof cad === 'number') (row.metrics['cadence.ms'] ??= []).push(cad);
      }
    }
  }
  return [...rows.values()].map((r) => ({
    width: r.width, engine: r.engine, role: r.role, seq: r.seq, runs: r.runs,
    metrics: Object.fromEntries(Object.entries(r.metrics).map(([k, v]) => [k, { n: v.length, min: r2(Math.min(...v)), median: r2(med(v)), max: r2(Math.max(...v)), perRun: v.map(r2) }])),
  }));
}

export function combinedText(rows) {
  const L = ['# per-run medians of separate CI jobs: median [min..max] over the runs', ''];
  const f = (m) => (m ? `${m.median} [${m.min}..${m.max}]` : '-');
  for (const r of rows.filter((x) => x.seq.startsWith('hero'))) {
    const m = r.metrics;
    L.push(`${r.width} ${r.engine.padEnd(18)} ${r.role.padEnd(17)} ${r.seq.padEnd(10)} runs ${r.runs.length}  padL jump ${f(m['padL.maxJump'])}, between ${f(m['padL.between'])}, arrives ${f(m['padL.arriveMs'])} ms | earnW jump ${f(m['earnW.maxJump'])} | langX jump ${f(m['langX.maxJump'])}, between ${f(m['langX.between'])} | opacity gone ${f(m['op.arriveMs'])} ms | frame ${f(m['cadence.ms'])} ms`);
  }
  return L.join('\n') + '\n';
}

export function readRuns(root) {
  const runs = [];
  const dirs = (p) => readdirSync(p, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name).sort();
  for (const run of dirs(root)) {
    const summaries = {};
    for (const width of dirs(join(root, run))) {
      const dir = join(root, run, width, 'summary');
      if (!existsSync(dir)) continue;
      for (const f of readdirSync(dir).filter((x) => /^transitions-.*\.summary\.json$/.test(x))) {
        const engine = f.replace(/^transitions-/, '').replace(/\.summary\.json$/, '').replace(/-\d+$/, '');
        summaries[`${width}|${engine}`] = JSON.parse(readFileSync(join(dir, f), 'utf8'));
      }
    }
    runs.push({ run, summaries });
  }
  return runs;
}

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(`--${k}`); return i >= 0 ? args[i + 1] : d; };
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const runs = readRuns(opt('in'));
  const rows = combine(runs);
  mkdirSync(opt('out'), { recursive: true });
  writeFileSync(join(opt('out'), 'across-runs.json'), JSON.stringify(rows, null, 1) + '\n');
  writeFileSync(join(opt('out'), 'across-runs.txt'), combinedText(rows));
  process.stderr.write(`combined ${rows.length} rows from ${runs.length} runs\n`);
}
