import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { register } from 'node:module';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';

const HERE = dirname(fileURLToPath(import.meta.url));
export const GOLDEN_PATH = join(HERE, '../../contracts/golden/parts/morph-mount-toolbar.gate.jsonl');
const PARTS = join(HERE, '../../../apps/site/src/parts/morph.mount');
export const HOOK_SYMBOLS = [
  'WTR::UIScriptControllerIOS::beginInteractiveObscuredInsetsChange',
  'WTR::UIScriptControllerIOS::endInteractiveObscuredInsetsChange',
  'WTR::UIScriptControllerCocoa::setObscuredInsets',
];
export const HOOK_NAMES = ['beginInteractiveObscuredInsetsChange', 'setObscuredInsets', 'endInteractiveObscuredInsetsChange'];

export function parseGolden(text) {
  const rows = text.split('\n').filter(Boolean).map((l) => JSON.parse(l));
  const g = { walk: null, exempt: new Map(), expect: new Map(), run: new Map(), geom: [], lifted: [] };
  for (const r of rows) {
    if (r.fn === 'gateWalk') g.walk = r.out;
    else if (r.fn === 'gateExempt') g.exempt.set(r.in.flag, r.out);
    else if (r.fn === 'gateExpect') g.expect.set(r.in.phase, r.out);
    else if (r.fn === 'gateRun') g.run.set(runKey(r.in.flag, r.in.phase, r.in.geoms), r.out);
    else if (r.fn === 'gateGeom') g.geom.push(r);
    else if (r.fn === 'gateLifted') g.lifted.push(r);
  }
  if (!g.walk || g.exempt.size === 0 || g.expect.size === 0 || g.run.size === 0) throw new Error('golden has no gate rows');
  return g;
}

export const runKey = (flag, phase, geoms) => `${flag}|${phase}|${geoms.map((b) => (b ? 1 : 0)).join('')}`;

export async function loadProduction() {
  register('./ts-ext-hooks.mjs', import.meta.url);
  const logic = await import(pathToFileURL(join(PARTS, 'logic.ts')).href);
  const gesture = await import(pathToFileURL(join(PARTS, 'gesture.ts')).href);
  return { armed: logic.armed, viewportHeight: logic.viewportHeight, step: gesture.step, gestureOpt: gesture.gestureOpt };
}

export function optOf(prod, flag) {
  return prod.gestureOpt(flag) ?? { first: false, once: false };
}

export function replay(prod, flag, geoms) {
  const o = optOf(prod, flag);
  let g = 'fresh';
  return geoms.map((geom) => {
    const r = prod.step(o, g, false, 1, geom, true);
    g = r.next;
    return r.take;
  });
}

const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  const n = s.length;
  return n === 0 ? NaN : n % 2 ? s[(n - 1) / 2] : (s[n / 2 - 1] + s[n / 2]) / 2;
};

export const liftedBy = (medianMs, boundMs) => medianMs < boundMs;

export function observedGeom(prod, rect, view) {
  return prod.armed({ height: rect.height, bottom: rect.bottom }, prod.viewportHeight(view.vvh, view.ih));
}

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const bits = (l) => l.map((b) => (b ? 1 : 0)).join('');

export function judgeReport(golden, prod, report, archive = null) {
  const checks = [];
  const add = (id, ok, detail) => checks.push({ id, ok: !!ok, detail });
  const flag = report.flag;
  const hooks = report.hooks ?? {};
  add('hooks', HOOK_NAMES.every((n) => hooks[n] === 'function') && (archive === null || HOOK_SYMBOLS.every((s) => (archive[s] ?? 0) > 0)),
    `runtime ${JSON.stringify(hooks)}${archive ? `; archive ${JSON.stringify(archive)}` : ''}`);
  const steps = report.steps ?? [];
  const nd = golden.walk.down.length - 1;
  const down = [golden.walk.down[0], ...steps.slice(0, nd).map((s) => s.inset)];
  const up = steps.slice(nd).map((s) => s.inset);
  const pl = report.params?.platform ?? {};
  add('walk', same(down, golden.walk.down) && same(up, golden.walk.up) && pl.heightNum === golden.walk.heightNum && pl.heightDen === golden.walk.heightDen && pl.gap === golden.walk.gap,
    `down ${down} up ${up} platform ${JSON.stringify(pl)}`);
  const base = report.facts?.base, rect0 = report.facts?.rect0;
  const obs = {
    down: base && rect0 && steps.length >= nd ? [observedGeom(prod, rect0, base), ...steps.slice(0, nd).map((s) => observedGeom(prod, s.rect, s.after))] : [],
    up: steps.length > nd ? steps.slice(nd).map((s) => observedGeom(prod, s.rect, s.after)) : [],
  };
  for (const phase of ['down', 'up']) {
    const exp = golden.expect.get(phase);
    add(`geoms-${phase}`, same(obs[phase], exp.geoms), `observed ${bits(obs[phase])} golden ${bits(exp.geoms)} (viewport heights ${steps.map((s) => s.after?.vvh).join(',')})`);
    const got = replay(prod, flag, obs[phase]);
    const want = golden.run.get(runKey(flag, phase, obs[phase]));
    const wantExp = golden.run.get(runKey(flag, phase, exp.geoms));
    add(`takes-${phase}`, want && wantExp && same(got, want) && same(got, wantExp), `production ${bits(got)} golden(observed arms) ${want ? bits(want) : 'no row'} golden(expected arms) ${wantExp ? bits(wantExp) : 'no row'}`);
  }
  const timeout = report.params?.timeoutMs ?? 600;
  const waits = steps.slice(1).map((s) => (s.latencyMs == null ? timeout : s.latencyMs));
  const med = median(waits);
  const exempt = golden.exempt.get(flag);
  add('exempt', exempt !== undefined && Number.isFinite(med) && liftedBy(med, golden.walk.liftedBelowMs) === exempt,
    `median wait ${Number.isFinite(med) ? med.toFixed(1) : 'none'} ms of ${waits.length} sets after the first (bound ${golden.walk.liftedBelowMs} ms), golden exempt ${exempt}; page animations ${JSON.stringify(report.lift)}`);
  return { flag, pass: report.meta?.pass ?? null, ok: checks.every((c) => c.ok), medianWaitMs: med, waitsMs: waits, checks };
}

export function judgeAll(golden, prod, reports, archive = null, minPasses = 2) {
  const results = reports.map((r) => judgeReport(golden, prod, r, archive));
  const flags = [...golden.exempt.keys()];
  const perFlag = flags.map((f) => {
    const rs = results.filter((r) => r.flag === f);
    return { flag: f, reports: rs.length, passed: rs.filter((r) => r.ok).length, ok: rs.length >= minPasses && rs.every((r) => r.ok) };
  });
  return { ok: perFlag.every((f) => f.ok), perFlag, results };
}

export function readReports(dir) {
  return readdirSync(dir).filter((f) => /^toolbar-.+-\d+\.json$/.test(f)).sort().map((f) => JSON.parse(readFileSync(join(dir, f), 'utf8')));
}

async function main() {
  const { values: v, positionals } = parseArgs({
    allowPositionals: true,
    options: { golden: { type: 'string', default: GOLDEN_PATH }, hooks: { type: 'string' }, out: { type: 'string' }, 'min-passes': { type: 'string', default: '2' } },
  });
  const dirs = positionals.map((p) => resolve(p));
  if (dirs.length === 0) throw new Error('usage: gate.mjs <dir>... [--golden f] [--hooks hooks.json] [--out gate.json]');
  const golden = parseGolden(readFileSync(v.golden, 'utf8'));
  const prod = await loadProduction();
  const archive = v.hooks ? JSON.parse(readFileSync(v.hooks, 'utf8')) : null;
  const reports = dirs.flatMap((d) => readReports(d).map((r) => ({ ...r, meta: { ...r.meta, dir: d } })));
  const res = judgeAll(golden, prod, reports, archive, Number(v['min-passes']));
  for (const r of res.results) {
    for (const c of r.checks) console.log(`${c.ok ? 'ok  ' : 'FAIL'} ${r.flag} pass ${r.pass} ${c.id}: ${c.detail}`);
  }
  for (const f of res.perFlag) console.log(`flag ${f.flag}: ${f.passed} of ${f.reports} reports pass${f.ok ? '' : ' (gate not held)'}`);
  console.log(`VERDICT toolbar-gate ${res.ok ? 'pass' : 'fail'}`);
  if (v.out) writeFileSync(v.out, JSON.stringify(res, null, 1));
  if (!res.ok) process.exitCode = 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main().catch((e) => { console.error(String(e?.stack || e)); process.exit(1); });
