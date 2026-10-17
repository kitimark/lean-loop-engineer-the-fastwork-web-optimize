// node src/cli.mjs extract --engine chromium|playwright-webkit [--out DIR] [--envs 0,1,2] [--concurrency N]
// node src/cli.mjs merge   --engine E --in a.json,b.json,c.json --out DIR      (stable rows of N runs -> dataset files)
// node src/cli.mjs report  --in DIR [--out DIR]                                (port against reference, fonts)
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { parseArgs } from 'node:util';
import { snapshotRoot } from '../../gate-breakpoints/src/serve.mjs';
import { runExtract } from './extract.mjs';
import { cleanSource, fromJsonl, inOrder, stableRows, toJsonl } from './reduce.mjs';
import { compare, fontReport, renderMarkdown, rootTable, summarize } from './report.mjs';

const { positionals, values: v } = parseArgs({
  allowPositionals: true,
  options: {
    engine: { type: 'string' }, out: { type: 'string', default: 'out' }, in: { type: 'string' }, envs: { type: 'string' },
    concurrency: { type: 'string', default: '4' },
  },
});
const cmd = positionals[0];
const engineFile = (e) => (e === 'chromium' ? 'chromium' : 'webkit');

if (cmd === 'extract') {
  if (!v.engine) throw new Error('--engine required');
  await runExtract({ engineName: v.engine, outDir: v.out, concurrency: Number(v.concurrency), envFilter: v.envs ? v.envs.split(',').map(Number) : null });
} else if (cmd === 'merge') {
  const runs = v.in.split(',').map((f) => JSON.parse(readFileSync(f, 'utf8')));
  const heads = new Set(runs.map((r) => JSON.stringify(r.header)));
  if (heads.size !== 1) throw new Error(`runs disagree on the header (${heads.size} variants): same snapshot, browser and environments are required`);
  const header = runs[0].header;
  mkdirSync(v.out, { recursive: true });
  const name = engineFile(header.engine);
  const res = {};
  for (const arm of ['orig', 'port']) {
    const { stable, unstable } = stableRows(runs.map((r) => r[arm]));
    const ordered = inOrder(stable, runs[0][arm]);
    res[arm] = { rows: ordered, unstable };
    const head = { ...header, t: 'header', arm: arm === 'orig' ? 'original' : 'port', runs: runs.length, rows: ordered.length, unstableRows: unstable.length };
    const file = arm === 'orig' ? `reference-${name}.jsonl` : `port-${name}.jsonl`;
    // committed form: no selector text
    const clean = ordered.map((r) => (r.t === 'cell' ? { ...r, s: r.s.map((g) => ({ ...g, x: g.x === null ? null : cleanSource(g.x) })) } : r));
    writeFileSync(join(v.out, file), toJsonl([head, ...clean]));
    writeFileSync(join(v.out, `${arm === 'orig' ? 'reference' : 'port'}-full-${name}.jsonl`), toJsonl([head, ...ordered]));
    writeFileSync(join(v.out, `${arm === 'orig' ? 'reference' : 'port'}-unstable-${name}.json`), JSON.stringify(unstable, null, 1) + '\n');
    process.stderr.write(`${file}: ${ordered.length} stable rows, ${unstable.length} unstable of ${ordered.length + unstable.length}\n`);
  }
  const fontsSame = new Set(runs.map((r) => JSON.stringify(r.fonts))).size === 1;
  writeFileSync(join(v.out, `fonts-${name}.json`), JSON.stringify({ engine: header.engine, runsAgree: fontsSame, ...runs[0].fonts }, null, 1) + '\n');
} else if (cmd === 'report') {
  const dir = v.in;
  const out = v.out;
  mkdirSync(out, { recursive: true });
  const root = snapshotRoot();
  const md = ['# Port against the reference', '', 'Reference = the unmodified original; port = our prerendered default page. Values are computed styles at the gate environments.', ''];
  const all = {};
  for (const name of ['chromium', 'webkit']) {
    const refFile = join(dir, `reference-${name}.jsonl`);
    if (!existsSync(refFile)) continue;
    const ref = fromJsonl(readFileSync(refFile, 'utf8'));
    const port = fromJsonl(readFileSync(join(dir, `port-${name}.jsonl`), 'utf8'));
    const n = ref[0].envs.length;
    const fonts = JSON.parse(readFileSync(join(dir, `fonts-${name}.json`), 'utf8'));
    // a family is shipped when the original has a @font-face rule for it and every file the rule names is in the snapshot
    const rulesByFamily = new Map();
    for (const r of fonts.orig.rules) rulesByFamily.set(r.family, [...(rulesByFamily.get(r.family) ?? []), r]);
    const ships = (family) => {
      const rules = rulesByFamily.get(family);
      if (!rules) return false;
      return rules.every((r) => r.urls.length > 0 && r.urls.every((u) => u === 'data:' || existsSync(join(root, u))));
    };
    const cmp = compare(ref.slice(1), port.slice(1), n);
    const sum = summarize(cmp);
    const env = ref[0].envs.find((e) => e.width === 1440 && e.hover === 'hover' && e.reducedMotion === 'no-preference' && e.colorScheme === 'light')?.id ?? 0;
    const rt = rootTable(ref.slice(1), port.slice(1), n, env);
    const fr = fontReport(fonts, ships);
    all[name] = { summary: sum, root: rt, fonts: fr, diffs: cmp.diffs };
    md.push(renderMarkdown(name, sum, rt, fr));
  }
  writeFileSync(join(out, 'report.md'), md.join('\n'));
  writeFileSync(join(out, 'report.json'), JSON.stringify(all, null, 1) + '\n');
  process.stderr.write(`wrote ${join(out, 'report.md')}\n`);
} else {
  throw new Error('usage: extract | merge | report');
}
