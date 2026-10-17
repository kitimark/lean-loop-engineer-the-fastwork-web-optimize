// The gaps lane (Q33): the 8 cells the default gate cannot judge. Collecting (browsers, Simulator, WKWebView) and judging
// (fwcore, Lean) are separate steps so that CI can collect on Linux and macOS jobs and judge on one job.
//   node src/cli.mjs gaps collect --out out/gaps-a [--engines chromium,webkit] [--skip-mac] [--skip-sim] [--ci] [--owner NAME]
//        raw runs ({chromium,playwright-webkit}.json) and evidence.json; no judging, no fwcore needed
//   node src/cli.mjs gaps summary --out out/gaps-a              (judge the raw files with fwcore, write gaps.json and gaps.md)
//   node src/cli.mjs gaps run     ...                           (collect, then summary)
//   node src/cli.mjs gaps device-serve --out out/device-a [--port 8765] [--tok phone]    (phone session; src/gaps/DEVICE.md)
//   node src/cli.mjs gaps device-drive --sim out/gaps-a/evidence.json --out DIR    (phone driven over the Web Inspector; DEVICE.md steps 2-4)
//   node src/cli.mjs gaps device-judge --device FILE --sim out/gaps-a/evidence.json [--out DIR]
// Local `collect` of the Simulator steps needs the sim-lock held by --owner; `--ci` (GitHub runner, own VM) skips that check
// and creates the iPad device when the image has none. A step that cannot run on the machine (no WKWebView host, no device
// type) is recorded under evidence.skipped with its reason; it is never silently absent.
import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { runEngine } from '../run.mjs';
import { launchWebkit } from '../engines.mjs';
import { PKG } from '../serve.mjs';
import { loadAnchors, loadGen, probeEnv } from '../spec.mjs';
import { context, evaluate } from '../verdict.mjs';
import { gapFacts } from './inpage.mjs';
import { gapCells, gapEdges, GAP_BLOCKS, probeVariants, realizeChromium, realizeWebkit } from './cells.mjs';
import { launchChromiumGaps } from './engines.mjs';
import { createDevice, deleteDevice, ensureBooted, findStock, macAR, macZoom, playwrightDpr, shutdown, simulator } from './evidence.mjs';
import { judgeRun, modelCheck, pairOf } from './judge.mjs';
import { judgeDevice } from './devicejudge.mjs';
import { startProbeServer } from './probe.mjs';
import { deviceMain } from './device.mjs';
import { deviceDrive } from './devicedrive.mjs';

const log = (...a) => process.stderr.write(a.join(' ') + '\n');
const ENGINES = ['chromium', 'playwright-webkit'];
/** Page zooms of the macOS WKWebView lane: [width, pageZoom]. 1201 x 2 etc. are the Chromium 200% widths. */
const MAC_ZOOM_CASES = [[601, 1], [1201, 2], [1281, 2], [1721, 2], [2001, 2], [661, 1.1], [705, 1.1], [947, 1.1], [1101, 1.1], [751, 1.25], [541, 0.9]];
const EVIDENCE_SCHEMA = 'fw.gate-breakpoints.gaps-evidence/2';

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

/** Run a step; on failure record the reason under skipped[name] and carry on (the rest of the lane is still worth having). */
async function step(skipped, name, fn, fallback) {
  try { return await fn(); } catch (e) { skipped[name] = String(e.message ?? e).split('\n')[0]; log(`  ${name}: skipped (${skipped[name]})`); return fallback; }
}

async function collect(opts) {
  const { outDir } = opts;
  const { gen } = loadGen();
  mkdirSync(outDir, { recursive: true });
  const want = (e) => opts.engines.includes(e);
  const common = { outDir, concurrency: 2, probeFilter: [...GAP_BLOCKS], sweepFilter: [] };
  const collectArg = { edges: gapEdges(gen) };
  if (want('chromium')) await runEngine({ ...common, engineName: 'chromium', gaps: { launcher: launchChromiumGaps, mapProbe: realizeChromium, collect: gapFacts, collectArg } });
  if (want('webkit')) await runEngine({ ...common, engineName: 'playwright-webkit', gaps: { launcher: launchWebkit, mapProbe: realizeWebkit, collect: gapFacts, collectArg } });

  const cfg = probeCfg(gen);
  const evidence = { schema: EVIDENCE_SCHEMA, platform: process.platform, playwrightDpr: [], macZoom: [], macAR: null, simulator: {}, skipped: {} };
  const sk = evidence.skipped;
  const server = await startProbeServer({ cfg });
  try {
    if (want('webkit')) {
      log('  evidence: Playwright WebKit DPR and pairs');
      evidence.playwrightDpr = await playwrightDpr({ server, cfg });
    }
    if (want('webkit') && process.platform === 'darwin') {
      if (opts.skipMac) sk.macos = 'skipped by --skip-mac';
      else {
        log('  evidence: macOS WKWebView pageZoom');
        evidence.macZoom = await step(sk, 'macos-pageZoom', () => macZoom({ server, cases: MAC_ZOOM_CASES }), []);
        log('  evidence: macOS WKWebView A=R row (pageZoom 2, width 1201)');
        evidence.macAR = await step(sk, 'macos-AR', () => macAR({ cfg }), null);
      }
      if (opts.skipSim) sk.simulator = 'skipped by --skip-sim';
      else if (!opts.ci && !simLockHeld(opts.owner)) throw new Error(`the sim-lock is not held by "${opts.owner}": run \`sh scripts/sim-lock.sh acquire ${opts.owner}\` in the same shell command, or pass --skip-sim`);
      else await simulatorEvidence({ opts, server, gen, evidence });
    } else if (process.platform !== 'darwin') sk.apple = `not collected on ${process.platform}: the macOS and Simulator arms need an Apple host`;
  } finally { await server.close(); }
  writeFileSync(join(outDir, 'evidence.json'), stable(evidence) + '\n');
  log(`wrote ${join(outDir, 'evidence.json')}${Object.keys(sk).length ? `; skipped: ${JSON.stringify(sk)}` : ''}`);
}

async function simulatorEvidence({ opts, server, gen, evidence }) {
  const sk = evidence.skipped;
  const variants = probeVariants(gen);
  const iphone = await step(sk, 'sim-iphone-device', async () => {
    const d = findStock('fw-iphone-27');
    if (!d) throw new Error('no device "fw-iphone-27" on the iOS 27.0 runtime');
    return { label: 'iphone', udid: d.udid, keep: true };
  }, null);
  const ipad = await step(sk, 'sim-ipad-device', async () => {
    const stock = findStock(opts.ipad);
    if (stock) return { label: 'ipad', udid: stock.udid, keep: false };
    if (!opts.ci) throw new Error(`no stock device "${opts.ipad}" (create one in CI only)`);
    const made = createDevice('fw-gaps-ipad', /^iPad Pro 1[13]/);
    if (made.reason) throw new Error(made.reason);
    return { label: 'ipad', udid: made.udid, keep: false, created: true };
  }, null);
  for (const d of [iphone, ipad].filter(Boolean)) {
    let booted = false;
    await step(sk, `sim-${d.label}`, async () => {
      booted = ensureBooted(d.udid);
      log(`  evidence: iOS Simulator ${d.label}`);
      const scale = Number(process.env.FW_SIM_TIMEOUT_SCALE ?? 1);
      const budgetMs = Number(process.env.FW_SIM_ARM_BUDGET_MS ?? Infinity);
      evidence.simulator[d.label] = await simulator({ server, device: d, variants, loads: 2, scale, budgetMs, onFail: (tok, why) => { sk[tok] = why; } });
    }, null);
    if (booted && !d.keep) shutdown(d.udid);
    if (d.created) deleteDevice(d.udid);
  }
}

function readJson(p) { return JSON.parse(readFileSync(p, 'utf8')); }

const flatArms = (run, kind, cells) => run.probes.filter((p) => cells.find((c) => c.id === p.id && c.kind === kind))
  .flatMap((p) => ['orig', 'rewrite'].map((a) => ({ mech: 'playwright-webkit/run', req: { probe: p.id, arm: a }, gap: p[a].raw.gap })));

/** Judge the raw files of one out dir with Lean (fwcore) and write gaps.json and gaps.md. */
export function writeSummary(outDir) {
  const { gen, sha256 } = loadGen();
  const anchors = loadAnchors();
  const cells = gapCells(gen);
  const parts = Object.keys(anchors.parts);
  const deviceEdges = gen.edgePairs.deviceWidth;
  const runs = Object.fromEntries(ENGINES.filter((e) => existsSync(join(outDir, `${e}.json`))).map((e) => [e, readJson(join(outDir, `${e}.json`))]));
  const ev = existsSync(join(outDir, 'evidence.json')) ? readJson(join(outDir, 'evidence.json')) : { playwrightDpr: [], macZoom: [], macAR: null, simulator: {}, skipped: {} };

  // 1. the 8 cells on each engine: Lean's gate.state with the engine's port (pass / fail / not-comparable / unreachable:<reason>)
  const engines = Object.fromEntries(Object.entries(runs).map(([e, run]) => [e, judgeRun({ cells, engine: e, run, anchors, deviceEdges, parts })]));

  // 2. the model check on what the WebKit pages reported: Lean's reach rule on the observed facts, per mechanism
  const groups = new Map();
  const add = (key, port, records) => { if (records.length > 0) groups.set(key, { port, records: [...(groups.get(key)?.records ?? []), ...records] }); };
  const wk = runs['playwright-webkit'];
  if (wk) for (const kind of ['fractional', 'cross']) add(`playwright-webkit/run ${kind}`, wk.header.port, flatArms(wk, kind, cells));
  for (const r of ev.playwrightDpr) add(r.mech, r.port, [r]);
  for (const r of ev.macZoom) add(r.mech, r.port, [r]);
  for (const [d, recs] of Object.entries(ev.simulator)) {
    add(`ios-simulator-safari ${d} (plain loads)`, 'webkit-apple', recs.filter((r) => r.req.load !== undefined));
    add(`ios-simulator-safari ${d} (meta-viewport variants)`, 'webkit-apple', recs.filter((r) => r.req.variant !== undefined));
  }
  const models = [...groups].map(([mech, g]) => ({ mech, port: g.port, ...modelCheck(g.port, g.records.filter((r) => r.gap)) }));

  // 3. the informative A=R row (macOS WKWebView, pageZoom 2, window 1201): the fractional cell's expectation, port left open
  let ar = null;
  if (ev.macAR) {
    const cell = cells.find((c) => c.kind === 'fractional');
    const ctx = context({ anchors, parts: [], props: null, deviceEdges, port: null });
    const { states } = evaluate(ctx, [{ requested: probeEnv(cell.probe), orig: ev.macAR.orig, rewrite: ev.macAR.rewrite, expect: cell.probe.expect, expectNeutral: cell.probe.expectNeutral }]);
    const arm = (a) => ({ mediaWidth: a.raw.gap?.mediaWidth ?? null, vvWidth: a.raw.gap?.vvWidth ?? null, innerWidth: a.raw.gap?.innerWidth ?? null, dpr: a.raw.gap?.dpr ?? null });
    ar = { cell: cell.id, req: ev.macAR.req, verdict: states[0].verdict, achieved: states[0].achieved, deviations: states[0].dev, rows: states[0].rows, orig: arm(ev.macAR.orig), rewrite: arm(ev.macAR.rewrite) };
  }

  // 4. variants (informative): what width the iOS viewport code produced for each meta-viewport request
  const variantRows = Object.entries(ev.simulator).flatMap(([d, recs]) => recs.filter((r) => r.req.variant !== undefined)
    .map((r) => ({ device: d, variant: r.req.variant, aimed: r.req.aimed, mediaWidth: r.gap?.mediaWidth ?? null, vvWidth: r.gap?.vvWidth ?? null, innerWidth: r.gap?.innerWidth ?? null })));

  // 5. the Simulator records through the phone-session rule (dry run of the device check; plain loads only)
  const iphone = (ev.simulator.iphone ?? []).filter((r) => r.req.load !== undefined);
  const simulatorCheck = Object.fromEntries(Object.entries(ev.simulator).map(([d, recs]) => [d, judgeDevice({ device: recs.filter((r) => r.req.load !== undefined), sim: iphone, gen })]));

  const result = { schema: 'fw.gate-breakpoints.gaps/2', genSha256: sha256, platform: ev.platform ?? null, engines, models, ar, variants: variantRows, simulatorCheck, skipped: ev.skipped ?? {} };
  writeFileSync(join(outDir, 'gaps.json'), stable(result) + '\n');
  writeFileSync(join(outDir, 'gaps.md'), renderMd(result, gen, runs, ev));
  log(`wrote ${join(outDir, 'gaps.json')} and gaps.md; ${Object.entries(engines).map(([e, j]) => `${e}: ${JSON.stringify(Object.fromEntries(Object.entries(j.blocks).map(([b, t]) => [b, t.verdict])))}`).join('; ')}`);
  return result;
}

const f = (x) => (x === null || x === undefined ? '-' : String(x));
const pair = (p) => (p ? `${f(p.hover)}/${f(p.pointer)}` : '-');
const envText = (e) => (e ? `${e.width}x${e.height} dpr ${e.dpr} ${e.hover}/${e.pointer}` : '-');

function renderMd(result, gen, runs, ev) {
  const md = ['# Gaps lane: the 8 Q33 cells', '',
    'Every state is Lean\'s (gate.state with the engine\'s port): `pass` / `fail` (environment reached, judged like every gate cell), `unreachable:<reason>` (the port cannot build the requested environment; the reason is the one proved in Fw.Gate.Reach) and `not-comparable`.', ''];
  for (const [engine, run] of Object.entries(runs)) md.push(`- ${engine} (port ${f(run.header.port)}): ${run.header.browser}`);
  md.push('', '| cell | engine | state | reach | requested (Lean) | realized | page saw (orig / rewrite) |', '|---|---|---|---|---|---|---|');
  for (const [engine, j] of Object.entries(result.engines)) {
    for (const c of j.cells) {
      const m = c.measured;
      const saw = c.kind === 'fractional'
        ? `media ${f(m.orig.mediaWidth)} / ${f(m.rewrite.mediaWidth)}, vv ${f(m.orig.vvWidth)}, inner ${f(m.orig.innerWidth)}, dpr ${f(m.orig.dpr)}`
        : `pair ${pair(m.orig.pair)} / ${pair(m.rewrite.pair)}`;
      const realized = c.realized ? `${envText(c.realized)}${c.realized.zoom && c.realized.zoom !== 1 ? `, zoom ${c.realized.zoom}, override ${c.realized.override.width}x${c.realized.override.height}` : ''}` : '-';
      md.push(`| ${c.id} | ${engine} | **${c.verdict}** | ${f(c.reach)} | ${envText(c.env)} | ${realized} | ${saw} |`);
    }
  }
  md.push('', '## Blocks (Lean tally)', '', '| engine | block | verdict | failing | total | unreachable |', '|---|---|---|---|---|---|');
  for (const [engine, j] of Object.entries(result.engines)) for (const [b, t] of Object.entries(j.blocks)) md.push(`| ${engine} | ${b} | ${t.verdict} | ${t.failing} | ${t.total} | ${t.unreachable} |`);
  md.push('', '## Does the reach model hold on what WebKit pages reported? (Lean: gate.reach, then the cell rule)', '', '| mechanism | port | verdict | records | contradicted | unreadable |', '|---|---|---|---|---|---|');
  for (const m of result.models) md.push(`| ${m.mech} | ${m.port} | ${m.verdict} | ${m.records} | ${m.contradicted.length} | ${m.unreadable} |`);
  if (result.ar) {
    const a = result.ar;
    md.push('', '## Informative: macOS WKWebView A=R row (pageZoom 2, window width 1201, never in a count)', '',
      `Cell ${a.cell} expectation, port left open. Verdict ${a.verdict}, environment achieved: ${a.achieved}. Original: media ${f(a.orig.mediaWidth)}, vv ${f(a.orig.vvWidth)}, inner ${f(a.orig.innerWidth)}, dpr ${f(a.orig.dpr)}. Rewrite: media ${f(a.rewrite.mediaWidth)}, vv ${f(a.rewrite.vvWidth)}, inner ${f(a.rewrite.innerWidth)}, dpr ${f(a.rewrite.dpr)}.`,
      '', `Deviations from the request: ${JSON.stringify(a.deviations)}`, '', `Rows: ${JSON.stringify(a.rows)}`);
  }
  if (result.variants.length > 0) {
    md.push('', '## Informative: Simulator meta-viewport variants (the iOS rounding path)', '', '| device | variant | aimed | media width | vv width | inner width |', '|---|---|---|---|---|---|');
    for (const v of result.variants) md.push(`| ${v.device} | ${v.variant} | ${v.aimed} | ${f(v.mediaWidth)} | ${f(v.vvWidth)} | ${f(v.innerWidth)} |`);
  }
  md.push('', '## Simulator records through the phone-session rule (dry run of the device check)', '');
  for (const [d, r] of Object.entries(result.simulatorCheck)) md.push(`- ${d}: ${r.pass ? 'PASS' : 'FAIL'}; ${r.checks.map((x) => `${x.ok ? 'ok' : 'NOT ok'} ${x.id}${x.ok && typeof x.detail === 'string' ? ` (${x.detail})` : ''}`).join('; ')}`);
  if (Object.keys(result.skipped).length > 0) {
    md.push('', '## Not collected here (with the reason)', '');
    for (const [k, v] of Object.entries(result.skipped)) md.push(`- ${k}: ${v}`);
  }
  md.push('', '## Evidence on the WebKit side', '');
  const rec = (title, rs, show) => { md.push(`${title} (${rs.length} records)`, '', '| request | saw |', '|---|---|'); for (const r of rs) md.push(`| ${JSON.stringify(r.req)} | ${show(r)} |`); md.push(''); };
  const shw = (r) => `media ${f(r.gap.mediaWidth)}, vv ${f(r.gap.vvWidth)}, inner ${f(r.gap.innerWidth)}, screen ${f(r.gap.screenWidth)}, dpr ${f(r.gap.dpr)}, pair ${pair(pairOf(r.gap.pointer))}`;
  rec('Playwright WebKit', ev.playwrightDpr, shw);
  rec('macOS system WebKit (WKWebView pageZoom)', ev.macZoom, shw);
  for (const [d, rs] of Object.entries(ev.simulator)) rec(`iOS Simulator ${d}`, rs, shw);
  return md.join('\n') + '\n';
}

export async function gapsMain(args, outDir) {
  const sub = args[0];
  const arg = (n, d) => { const i = args.indexOf(`--${n}`); return i < 0 ? d : args[i + 1]; };
  const flag = (n) => args.includes(`--${n}`);
  const engines = arg('engines', 'chromium,webkit').split(',');
  const opts = { outDir, engines, skipSim: flag('skip-sim'), skipMac: flag('skip-mac'), ci: flag('ci'), owner: arg('owner', 'gap-harness'), ipad: arg('ipad', 'iPad Pro 13-inch (M5)') };
  if (sub === 'collect') await collect(opts);
  else if (sub === 'run') { await collect(opts); writeSummary(outDir); }
  else if (sub === 'summary') writeSummary(outDir);
  else if (sub === 'device-serve' || sub === 'device-judge') await deviceMain(sub, args, outDir);
  else if (sub === 'device-drive') await deviceDrive(args, outDir); // the phone driven through the Web Inspector (measurement phone only)
  else {
    console.error('usage: cli.mjs gaps collect|summary|run|device-serve|device-judge|device-drive --out DIR [...]');
    process.exit(2);
  }
}
