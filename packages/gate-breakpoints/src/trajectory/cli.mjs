// The trajectory probe's command line (task trajectory-probe; docs/team/tools/trajectory-probe.md).
//   node src/trajectory/cli.mjs run --engine chromium|playwright-webkit --out out/traj [--widths 390,640,641,1280] [--search '?fw=morph.tween:waapi']
//        [--paths hero,morph] [--reads full|lean] [--reps 1..5] [--strict]
//   node src/trajectory/cli.mjs merge --in <leg dir>,<leg dir> --engine <e> --out out/traj   (joins the legs of one engine and reduces the whole)
//   node src/trajectory/cli.mjs summary --out out/traj [--engine chromium|playwright-webkit] [--strict]   (re-reduces raw-<engine>.json files there)
// `run` refuses a widths list outside the Lean allowlist and a search the build did not prerender (rewriteFor throws, like the gate's
// smoke step). It walks, per width, the original, the faithful rewrite (default config) and the candidate (the search), writes
// raw-<engine>.json (the readings, with what each arm's page reported about its config), units-<engine>.json (one verdict per unit,
// and its relation to the faithful arm), summary-<engine>.md, prints the VERDICT lines, and exits
//   0  the probe completed (RED, UNDECIDED or CLEAN is a result, not an error; with --strict only CLEAN exits 0),
//   1  with --strict, RED,
//   2  refused: an arm was not measured as asked (`refused:config`), an input is outside its allowlist, `summary` found no
//      raw file, `merge` has no leg or legs that disagree, or the command is unknown; the run is void, never a pass,
//   3  with --strict, UNDECIDED: no verdict either way; rerun with more passes (Lean `laneExit`); `summary` over several engines exits the worst (Lean `exitJoin`).
// So 1 is only ever a strict RED.
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { mergeRaws } from './plan.mjs';
import { HERO_NODES, MORPH_NODES, PAGE_PROPS } from './registry.mjs';
import { exitJoin, laneExit, pickWidths, reduceRaw, verdictLines } from './reduce.mjs';

const REGISTRIES = { hero: HERO_NODES, morph: MORPH_NODES, page: PAGE_PROPS };

const REFUSED = laneExit(true, false, 'clean');

const refuse = (why) => { console.error(`trajectory: refused: ${why}`); return REFUSED; };

const arg = (argv, name, dflt = '') => { const i = argv.indexOf(name); return i < 0 ? dflt : (argv[i + 1] ?? dflt); };

/** The markdown of one engine's reduction: arm identity, relation to the faithful arm, the new groups, the timing. */
export function summaryMd(raw, red) {
  const head = `## trajectory ${raw.engine} (${raw.version ?? '?'}) search=${raw.search || '(default)'} reads=${raw.reads ?? 'full'} paths=${(raw.paths ?? ['hero', 'morph']).join('+')} reps=${raw.reps ?? 1}`;
  if (red.refused) return [`${head} REFUSED config`, '', `The run was not measured as asked, so it has no verdict: ${red.detail}`, ''].join('\n');
  const out = [`${head} ${red.lane.toUpperCase()}`, '',
    `arms: ${red.arms.length}, all with the config hash of their search and fwMode hydrate (rewrite) or no window.__fw (original)`, '',
    `units ${red.totals.units}: pass ${red.totals.pass}, fail ${red.totals.fail}, skip ${red.totals.skip}; coverage failures ${red.totals.coverageFail}`, '',
    '| against the faithful arm | units |', '|---|---|',
    `| new (fails here, not in the faithful arm) | ${red.rels.new} (content ${red.rels.new - red.totals.coverageNew}, coverage ${red.totals.coverageNew}) |`, `| both (fails in both: baseline red) | ${red.rels.both} |`,
    `| unmeasured (fails on content here, on coverage in the faithful arm: no verdict) | ${red.rels.unmeasured} |`,
    `| undecided (open@1 has no rewrite sample and the original's hit rate cannot tell late from missing, or the unit is new without one original pass and not new without another) | ${red.rels.undecided} (leave-one-out ${red.totals.moved}) |`,
    `| cleared (fails only in the faithful arm) | ${red.rels.cleared} |`, `| ok | ${red.rels.ok} |`, ''];
  for (const n of red.notes) out.push(`- note: ${n}`);
  const news = red.groups.filter((g) => g.newSteps.length > 0);
  if (news.length > 0) {
    out.push('', '| width | path | node.property | new units | steps |', '|---|---|---|---|---|');
    for (const g of news) out.push(`| ${g.width} | ${g.path} | ${g.node}.${g.prop} | ${g.newSteps.length}/${g.pass + g.fail + g.skip} | ${g.newSteps.slice(0, 5).join(', ')}${g.newSteps.length > 5 ? ', ...' : ''} |`);
  }
  if (red.timing.length > 0) {
    out.push('', '| arm | phase | samples | read p50 | read p90 | gap p50 | gap p90 | reads dominate |', '|---|---|---|---|---|---|---|---|');
    for (const t of red.timing) out.push(`| ${t.role} | ${t.phase} | ${t.n} | ${t.readP50} | ${t.readP90} | ${t.gapP50 ?? '-'} | ${t.gapP90 ?? '-'} | ${t.dominate ? 'yes' : 'no'} |`);
  }
  return out.join('\n') + '\n';
}

function report(dir, raw, strict) {
  const red = reduceRaw(raw, REGISTRIES);
  writeFileSync(join(dir, `units-${raw.engine}.json`), JSON.stringify({ engine: raw.engine, search: raw.search, refused: red.refused, detail: red.detail, totals: red.totals, rels: red.rels, notes: red.notes, groups: red.groups, timing: red.timing, units: red.units.map(({ fam, ...u }) => (u.rel === u.relAll ? u : { ...u, fam })) }));
  const md = summaryMd(raw, red);
  writeFileSync(join(dir, `summary-${raw.engine}.md`), md);
  for (const l of verdictLines(raw.engine, raw.search, red)) console.log(l);
  if (process.env.GITHUB_STEP_SUMMARY) writeFileSync(process.env.GITHUB_STEP_SUMMARY, md, { flag: 'a' });
  return laneExit(red.refused, strict, red.lane);
}

/** The paths input: hero, morph or hero,morph; null when refused. */
export function pickPaths(s) {
  if (s === '' || s === 'hero,morph' || s === 'both') return ['hero', 'morph'];
  return s === 'hero' || s === 'morph' ? [s] : null;
}

export async function main(argv) {
  const [cmd] = argv;
  const out = arg(argv, '--out', 'out/trajectory');
  const strict = argv.includes('--strict');
  mkdirSync(out, { recursive: true });
  if (cmd === 'run') {
    const engineName = arg(argv, '--engine', 'chromium');
    const widths = pickWidths(arg(argv, '--widths'));
    if (widths === null) return refuse('widths must be a comma list of 390, 640, 641, 1280 without repeats');
    const paths = pickPaths(arg(argv, '--paths'));
    if (paths === null) return refuse('paths must be hero, morph or hero,morph');
    const reads = arg(argv, '--reads', 'full');
    if (reads !== 'full' && reads !== 'lean') return refuse('reads must be full or lean');
    const reps = Number(arg(argv, '--reps', '3'));
    if (!Number.isInteger(reps) || reps < 1 || reps > 5) return refuse('reps must be 1 to 5');
    const { runLane } = await import('./run.mjs'); // lazy: summary and merge run with plain node (no playwright installed)
    const raw = await runLane({ engineName, widths, search: arg(argv, '--search'), paths, reads, reps, env: process.env });
    writeFileSync(join(out, `raw-${raw.engine}.json`), JSON.stringify(raw));
    return report(out, raw, strict);
  }
  if (cmd === 'summary') {
    const only = arg(argv, '--engine');
    const files = readdirSync(out).filter((f) => /^raw-.+\.json$/.test(f) && (only === '' || f === `raw-${only}.json`));
    if (files.length === 0) return refuse(`no raw-<engine>.json in ${out}`);
    let code = 0;
    for (const f of files) code = exitJoin(code, report(out, JSON.parse(readFileSync(join(out, f), 'utf8')), strict));
    return code;
  }
  if (cmd === 'merge') {
    // Joins the legs of one engine (each leg's directory holds its raw-<engine>.json) and reduces the whole as one run.
    const dirs = arg(argv, '--in').split(',').filter(Boolean);
    const engineName = arg(argv, '--engine');
    if (dirs.length === 0 || engineName === '') return refuse('merge needs --in <leg dirs> and --engine');
    let raw;
    try {
      raw = mergeRaws(dirs.map((d) => JSON.parse(readFileSync(join(d, `raw-${engineName}.json`), 'utf8'))));
    } catch (e) {
      return refuse(e.message);
    }
    writeFileSync(join(out, `raw-${raw.engine}.json`), JSON.stringify(raw));
    return report(out, raw, strict);
  }
  return refuse('usage: cli.mjs run --engine <e> --out <dir> [--widths ...] [--search ...] [--paths ...] [--reads ...] [--strict] | summary --out <dir> | merge --in <leg dirs, comma separated> --engine <e> --out <dir>');
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) process.exit(await main(process.argv.slice(2)));
