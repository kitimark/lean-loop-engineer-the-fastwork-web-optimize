// The trajectory probe's command line (task trajectory-probe; docs/team/tools/trajectory-probe.md).
//   node src/trajectory/cli.mjs run --engine chromium|playwright-webkit --out out/traj [--widths 390,640,641,1280] [--search '?fw=morph.tween:waapi'] [--strict]
//   node src/trajectory/cli.mjs summary --out out/traj [--engine chromium|playwright-webkit] [--strict]   (re-reduces raw-<engine>.json files there)
// `run` refuses a widths list outside the Lean allowlist and a search the build did not prerender (rewriteFor throws, like the gate's
// smoke step). It writes raw-<engine>.json (the readings), units-<engine>.json (one verdict per unit) and summary-<engine>.md, prints
// the VERDICT lines, and exits 0 when the probe completed: a FAIL verdict is a result, not an error, unless --strict (then exit 1).
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { runLane } from './run.mjs';
import { HERO_NODES, MORPH_NODES, PAGE_PROPS } from './registry.mjs';
import { pickWidths, reduceRaw, verdictLines } from './reduce.mjs';

const REGISTRIES = { hero: HERO_NODES, morph: MORPH_NODES, page: PAGE_PROPS };

const arg = (argv, name, dflt = '') => { const i = argv.indexOf(name); return i < 0 ? dflt : (argv[i + 1] ?? dflt); };

/** The markdown of one engine's reduction: totals, notes and a table of the failing groups. */
export function summaryMd(raw, red) {
  const out = [`## trajectory ${raw.engine} (${raw.version ?? '?'}) search=${raw.search || '(default)'} ${red.fails ? 'FAIL' : 'PASS'}`, '',
    `units ${red.totals.units}: pass ${red.totals.pass}, fail ${red.totals.fail}, skip ${red.totals.skip}`, ''];
  for (const n of red.notes) out.push(`- note: ${n}`);
  const failing = red.groups.filter((g) => g.fail > 0);
  if (failing.length > 0) {
    out.push('', '| width | path | node.property | failing units | steps |', '|---|---|---|---|---|');
    for (const g of failing) out.push(`| ${g.width} | ${g.path} | ${g.node}.${g.prop} | ${g.fail}/${g.pass + g.fail + g.skip} | ${g.failing.slice(0, 5).join(', ')}${g.failing.length > 5 ? ', ...' : ''} |`);
  }
  return out.join('\n') + '\n';
}

function report(dir, raw, strict) {
  const red = reduceRaw(raw, REGISTRIES);
  writeFileSync(join(dir, `units-${raw.engine}.json`), JSON.stringify({ engine: raw.engine, search: raw.search, totals: red.totals, notes: red.notes, groups: red.groups, units: red.units }));
  const md = summaryMd(raw, red);
  writeFileSync(join(dir, `summary-${raw.engine}.md`), md);
  for (const l of verdictLines(raw.engine, raw.search, red)) console.log(l);
  if (process.env.GITHUB_STEP_SUMMARY) writeFileSync(process.env.GITHUB_STEP_SUMMARY, md, { flag: 'a' });
  return strict && red.fails ? 1 : 0;
}

export async function main(argv) {
  const [cmd] = argv;
  const out = arg(argv, '--out', 'out/trajectory');
  const strict = argv.includes('--strict');
  mkdirSync(out, { recursive: true });
  if (cmd === 'run') {
    const engineName = arg(argv, '--engine', 'chromium');
    const widths = pickWidths(arg(argv, '--widths'));
    if (widths === null) { console.error('trajectory: refused: widths must be a comma list of 390, 640, 641, 1280 without repeats'); return 1; }
    const raw = await runLane({ engineName, widths, search: arg(argv, '--search'), env: process.env });
    writeFileSync(join(out, `raw-${raw.engine}.json`), JSON.stringify(raw));
    return report(out, raw, strict);
  }
  if (cmd === 'summary') {
    const only = arg(argv, '--engine');
    const files = readdirSync(out).filter((f) => /^raw-.+\.json$/.test(f) && (only === '' || f === `raw-${only}.json`));
    if (files.length === 0) { console.error(`trajectory: no raw-<engine>.json in ${out}`); return 1; }
    let code = 0;
    for (const f of files) code = Math.max(code, report(out, JSON.parse(readFileSync(join(out, f), 'utf8')), strict));
    return code;
  }
  console.error('usage: cli.mjs run --engine <e> --out <dir> [--widths ...] [--search ...] [--strict] | summary --out <dir>');
  return 1;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) process.exit(await main(process.argv.slice(2)));
