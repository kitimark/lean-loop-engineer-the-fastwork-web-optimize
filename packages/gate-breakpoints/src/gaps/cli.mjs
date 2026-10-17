// The gaps lane (Q33): the 8 cells the default gate cannot judge.
//   node src/cli.mjs gaps run     --out out/gaps-a [--skip-sim] [--skip-mac] [--owner gap-harness] [--ipad "iPad Pro 13-inch (M5)"]
//   node src/cli.mjs gaps summary --out out/gaps-a              (re-judge the raw files, write gaps.json and gaps.md)
//   node src/cli.mjs gaps device-serve --out out/device-a [--port 8765] [--label-hint portrait-100]   (phone session; src/gaps/DEVICE.md)
//   node src/cli.mjs gaps device-judge --device FILE --sim out/gaps-a/evidence.json [--out DIR]
// `run` needs the sim-lock held by --owner (the Simulator steps only; `--skip-sim` runs without it).
import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { runEngine } from '../run.mjs';
import { launchWebkit } from '../engines.mjs';
import { PKG } from '../serve.mjs';
import { loadAnchors, loadGen } from '../spec.mjs';
import { gapFacts } from './inpage.mjs';
import { gapCells, gapEdges, GAP_BLOCKS, realizeEnv } from './cells.mjs';
import { launchChromiumGaps } from './engines.mjs';
import { ensureBooted, findStock, macZoom, playwrightDpr, shutdown, simulator } from './evidence.mjs';
import { judgeAll } from './judge.mjs';
import { judgeDevice } from './devicejudge.mjs';
import { startProbeServer } from './probe.mjs';
import { deviceMain } from './device.mjs';

const log = (...a) => process.stderr.write(a.join(' ') + '\n');
const ENGINES = ['chromium', 'playwright-webkit'];
/** Page zooms of the macOS WKWebView lane: [width, pageZoom]. 1201 x 2 etc. are the Chromium 200% widths. */
const MAC_ZOOM_CASES = [[601, 1], [1201, 2], [1281, 2], [1721, 2], [2001, 2], [661, 1.1], [705, 1.1], [947, 1.1], [1101, 1.1], [751, 1.25], [541, 0.9]];

const probeCfg = (gen) => ({
  conditions: gen.conditions.map((c) => ({ tsId: c.tsId, css: c.css, legacyCss: c.legacyCss })),
  neutral: gen.neutral.map((n) => ({ tsId: n.tsId, css: n.css })),
  edges: gapEdges(gen),
});

const stable = (v) => JSON.stringify(v, (k, x) => (x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.entries(x).sort(([a], [b]) => (a < b ? -1 : 1))) : x), 1);

function simLockHeld(owner) {
  const r = spawnSync('sh', [resolve(PKG, '../../scripts/sim-lock.sh'), 'status'], { encoding: 'utf8' });
  return r.stdout.startsWith(`held by ${owner} `);
}

async function runLane(opts) {
  const { outDir } = opts;
  const { gen } = loadGen();
  const cells = gapCells(gen);
  mkdirSync(outDir, { recursive: true });
  const filter = [...GAP_BLOCKS];
  const common = { outDir, concurrency: 2, probeFilter: filter, sweepFilter: [] };
  // 1. the 8 probes, original vs rewrite, both engines (Chromium with the zoom launcher, WebKit with the gate's launcher)
  await runEngine({ ...common, engineName: 'chromium', gaps: { launcher: launchChromiumGaps, mapProbe: realizeEnv, collect: gapFacts, collectArg: { edges: gapEdges(gen) } } });
  await runEngine({ ...common, engineName: 'playwright-webkit', gaps: { launcher: launchWebkit, mapProbe: realizeEnv, collect: gapFacts, collectArg: { edges: gapEdges(gen) } } });
  // 2. evidence for the WebKit side
  const cfg = probeCfg(gen);
  const server = await startProbeServer({ cfg });
  const evidence = { schema: 'fw.gate-breakpoints.gaps-evidence/1', playwrightDpr: [], macZoom: [], simulator: {} };
  try {
    log('  evidence: Playwright WebKit DPR and pairs');
    evidence.playwrightDpr = await playwrightDpr({ server, cfg });
    if (!opts.skipMac) { log('  evidence: macOS WKWebView pageZoom'); evidence.macZoom = await macZoom({ server, cases: MAC_ZOOM_CASES }); }
    if (!opts.skipSim) {
      if (!simLockHeld(opts.owner)) throw new Error(`the sim-lock is not held by "${opts.owner}": run \`sh scripts/sim-lock.sh acquire ${opts.owner}\` in the same shell command, or pass --skip-sim`);
      const devices = [{ label: 'iphone', udid: opts.iphoneUdid ?? findStock('fw-iphone-27').udid, keep: true }, { label: 'ipad', udid: findStock(opts.ipad).udid, keep: false }];
      for (const d of devices) {
        const booted = ensureBooted(d.udid);
        try {
          log(`  evidence: iOS Simulator ${d.label}`);
          evidence.simulator[d.label] = await simulator({ server, device: d, loads: 2 });
        } finally { if (booted && !d.keep) shutdown(d.udid); }
      }
    }
  } finally { await server.close(); }
  writeFileSync(join(outDir, 'evidence.json'), stable(evidence) + '\n');
  writeSummary(outDir);
}

function readJson(p) { return JSON.parse(readFileSync(p, 'utf8')); }

export function writeSummary(outDir) {
  const { gen, sha256 } = loadGen();
  const anchors = loadAnchors();
  const cells = gapCells(gen);
  const runs = Object.fromEntries(ENGINES.filter((e) => existsSync(join(outDir, `${e}.json`))).map((e) => [e, readJson(join(outDir, `${e}.json`))]));
  const ev = existsSync(join(outDir, 'evidence.json')) ? readJson(join(outDir, 'evidence.json')) : { playwrightDpr: [], macZoom: [], simulator: {} };
  const webkitRun = runs['playwright-webkit'];
  const arms = (kind) => (webkitRun ? webkitRun.probes.filter((p) => cells.find((c) => c.id === p.id && c.kind === kind)).flatMap((p) => ['orig', 'rewrite'].map((a) => ({ mech: 'playwright-webkit/run', req: { probe: p.id, arm: a }, gap: p[a].raw.gap }))) : []);
  const sim = Object.values(ev.simulator).flat();
  const nonSim = (r) => r.gap;
  const evidence = {
    fractional: [...arms('fractional'), ...ev.playwrightDpr.filter((r) => r.mech === 'playwright-webkit/dpr'), ...ev.macZoom, ...sim].filter(nonSim),
    cross: [...arms('cross'), ...ev.playwrightDpr.filter((r) => r.mech === 'playwright-webkit/pair'), ...ev.macZoom, ...sim].filter(nonSim),
  };
  const parts = Object.keys(anchors.parts);
  const judged = judgeAll({ cells, runs, evidence, anchors, deviceEdges: gen.edgePairs.deviceWidth, parts });
  // The Simulator records go through the phone session's pass rule too (the iPad against the iPhone, the iPhone against itself
  // and Lean): this is the dry run of the device check, and it shows which Simulator records have a Lean vector.
  const iphone = ev.simulator.iphone ?? [];
  const simulatorCheck = Object.fromEntries(Object.entries(ev.simulator).map(([d, recs]) => [d, judgeDevice({ device: recs, sim: iphone, gen })]));
  const result = { schema: 'fw.gate-breakpoints.gaps/1', genSha256: sha256, counts: judged.counts, cells: judged.cells, evidenceSizes: { fractional: evidence.fractional.length, cross: evidence.cross.length }, simulatorCheck };
  writeFileSync(join(outDir, 'gaps.json'), stable(result) + '\n');
  writeFileSync(join(outDir, 'gaps.md'), renderMd(result, gen, runs, ev));
  log(`wrote ${join(outDir, 'gaps.json')} and gaps.md; counts ${JSON.stringify(judged.counts)}`);
  return result;
}

const f = (x) => (x === null || x === undefined ? '-' : String(x));
const pair = (p) => (p ? `${f(p.hover)}/${f(p.pointer)}` : '-');

function renderMd(result, gen, runs, ev) {
  const md = ['# Gaps lane: the 8 Q33 cells', '',
    'State per cell and engine: `pass` / `fail` (environment reached, judged like every gate cell), `unreachable` (no mechanism; measured evidence holds on every record), `not-comparable`.', ''];
  for (const [engine, run] of Object.entries(runs)) md.push(`- ${engine}: ${run.header.browser}`);
  md.push('', '| cell | engine | state | mechanism | Lean expects | page saw (orig / rewrite) |', '|---|---|---|---|---|---|');
  for (const c of result.cells) {
    const probe = gen.matrix.probes.find((p) => p.id === c.id);
    const lean = c.kind === 'fractional' ? `media width ${probe.width}; neither (width<=${Math.floor(probe.width)}) nor (width>=${Math.floor(probe.width) + 1})` : `pair ${probe.hover}/${probe.pointer} at ${probe.width}`;
    for (const [engine, j] of Object.entries(c.engines)) {
      const m = j.measured;
      const saw = c.kind === 'fractional'
        ? `media ${f(m.orig.mediaWidth)} / ${f(m.rewrite.mediaWidth)}, vv ${f(m.orig.vvWidth)}, inner ${f(m.orig.innerWidth)}, dpr ${f(m.orig.dpr)}`
        : `pair ${pair(m.orig.pair)} / ${pair(m.rewrite.pair)}`;
      md.push(`| ${c.id} | ${engine} | **${j.state}** | ${j.mechanism} | ${lean} | ${saw} |`);
    }
  }
  const rowKeys = [...new Set(result.cells.flatMap((c) => Object.values(c.engines).filter((j) => j.achieved).flatMap((j) => Object.keys(j.rows))))];
  md.push('', '## Rows of each reached cell (as in the gate table; - = row does not apply)', '', `| cell | engine | ${rowKeys.join(' | ')} |`, `|---|---|${rowKeys.map(() => '---').join('|')}|`);
  for (const c of result.cells) for (const [engine, j] of Object.entries(c.engines)) if (j.achieved) md.push(`| ${c.id} | ${engine} | ${rowKeys.map((k) => j.rows[k] ?? '-').join(' | ')} |`);
  md.push('', '## Simulator records through the phone-session rule (dry run of the device check)', '');
  for (const [d, r] of Object.entries(result.simulatorCheck)) md.push(`- ${d}: ${r.pass ? 'PASS' : 'FAIL'}; ${r.checks.map((x) => `${x.ok ? 'ok' : 'NOT ok'} ${x.id}${x.ok && typeof x.detail === 'string' ? ` (${x.detail})` : ''}`).join('; ')}`);
  md.push('', '## Evidence on the WebKit side', '');
  const rec = (title, rs, show) => { md.push(`${title} (${rs.length} records)`, '', '| request | saw |', '|---|---|'); for (const r of rs) md.push(`| ${JSON.stringify(r.req)} | ${show(r)} |`); md.push(''); };
  const shw = (r) => `media ${f(r.gap.mediaWidth)}, vv ${f(r.gap.vvWidth)}, inner ${f(r.gap.innerWidth)}, screen ${f(r.gap.screenWidth)}, dpr ${f(r.gap.dpr)}, pair ${pair(pairOf2(r.gap.pointer))}`;
  rec('Playwright WebKit', ev.playwrightDpr, shw);
  rec('macOS system WebKit (WKWebView pageZoom)', ev.macZoom, shw);
  for (const [d, rs] of Object.entries(ev.simulator)) rec(`iOS Simulator ${d}`, rs, shw);
  return md.join('\n') + '\n';
}
const pairOf2 = (p) => ({ hover: p.hover === true ? 'hover' : p.hoverNone === true ? 'none' : null, pointer: p.pointerFine === true ? 'fine' : p.pointerCoarse === true ? 'coarse' : p.pointerNone === true ? 'none' : null });

export async function gapsMain(args, outDir) {
  const sub = args[0];
  const arg = (n, d) => { const i = args.indexOf(`--${n}`); return i < 0 ? d : args[i + 1]; };
  const flag = (n) => args.includes(`--${n}`);
  if (sub === 'run') {
    await runLane({ outDir, skipSim: flag('skip-sim'), skipMac: flag('skip-mac'), owner: arg('owner', 'gap-harness'), ipad: arg('ipad', 'iPad Pro 13-inch (M5)') });
  } else if (sub === 'summary') {
    writeSummary(outDir);
  } else if (sub === 'device-serve' || sub === 'device-judge') {
    await deviceMain(sub, args, outDir);
  } else {
    console.error('usage: cli.mjs gaps run|summary|device-serve|device-judge --out DIR [...]');
    process.exit(2);
  }
}
