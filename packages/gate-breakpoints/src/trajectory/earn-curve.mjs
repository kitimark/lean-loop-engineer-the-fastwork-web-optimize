import { mkdirSync, readFileSync, readdirSync, writeFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const GOLDEN = resolve(import.meta.dirname, '../../../contracts/golden/parts/nav.earn.curve.jsonl');

export function readGolden(path = GOLDEN) {
  const rows = readFileSync(path, 'utf8').split('\n').filter((l) => l.trim()).map((l) => JSON.parse(l));
  const grid = rows.find((r) => r.fn === 'grid').out;
  return { rows, grid, M: BigInt(grid.M), D: BigInt(grid.D) };
}

const bar = (M, c1, c2, k) => 3n * c1 * (M - k) * (M - k) * k + 3n * c2 * (M - k) * k * k + 100n * k * k * k;

export function ease(g, curve, a, c) {
  const [x1, y1, x2, y2] = curve.map((v) => BigInt(Math.round(v * 100)));
  let k = g.M;
  if (c > a) {
    k = 0n;
    for (let n = g.grid.gridBits - 1; n >= 0; n--) {
      const m = k + (1n << BigInt(n));
      if (bar(g.M, x1, x2, m) * c <= a * g.D) k = m;
    }
  }
  return bar(g.M, y1, y2, k);
}

export function num(g, run, toPx, tUs) {
  if (!run) return BigInt(toPx) * g.D;
  const t = BigInt(Math.max(0, Math.round(tUs)));
  const a = t > BigInt(run.delayUs) ? t - BigInt(run.delayUs) : 0n;
  return BigInt(run.fromPx) * g.D + (BigInt(run.toPx) - BigInt(run.fromPx)) * ease(g, run.curve, a, BigInt(run.durUs));
}

export const microPx = (g, n) => Number((n * 1000000000n) / g.D) / 1000;

const ceilDiv = (a, b) => (a + b - 1n) / b;

export function tolMicro(g, deltaPx, jUs, eUs, durUs) {
  const d = BigInt(deltaPx);
  const slack = ceilDiv(d * 261n * BigInt(jUs + eUs) * 1000000n, 100n * BigInt(durUs)) + ceilDiv(d * 783n * 1000000n, 100n * g.M);
  return Number(slack + ceilDiv(d * 150n * 1000000n, 100n * g.M) + BigInt(g.grid.readMicro));
}

export function leanRun(g, { width, seq, engine, arm, prop }) {
  const row = g.rows.find((r) => r.fn === 'run' && r.in.width === width && r.in.seq === seq && r.in.engine === engine && r.in.arm === arm && r.in.prop === prop);
  if (!row) throw new Error(`no Lean run for ${width}/${seq}/${engine}/${arm}/${prop}`);
  return row.out;
}

const PAD = { 390: 16, 1280: 24 };
const SEQ = { 'hero-entry': 'entry', 'hero-exit': 'exit' };
const PROPS = [['pl', 'padding-left'], ['pr', 'padding-right']];

const median = (a) => { const b = [...a].sort((x, y) => x - y); const m = b.length >> 1; return b.length % 2 ? b[m] : (b[m - 1] + b[m]) / 2; };

export function clock(rows, flip) {
  const live = rows.slice(flip).flatMap((x) => {
    const a = (x.an ?? []).find((e) => e[0] === 'earn' && e[1] === 'padding-left');
    return a && a[3] > 0 ? [x.t - a[3]] : [];
  });
  if (live.length === 0) return { startMs: rows[flip].t, jitterUs: 500, live: 0 };
  const startMs = median(live);
  return { startMs, jitterUs: Math.ceil(Math.max(...live.map((o) => Math.abs(o - startMs))) * 1000) + 500, live: live.length };
}

export function check(g, rows, { width, toPx, run, engine }) {
  const flip = rows.findIndex((x) => x.nav !== rows[0].nav);
  if (flip < 0) return { pass: false, why: 'no flip', frames: 0 };
  const c = clock(rows, flip);
  const eUs = g.grid.solverUs[engine];
  const deltaPx = run ? Math.abs(run.toPx - run.fromPx) : 0;
  const tol = run ? tolMicro(g, deltaPx, c.jitterUs, eUs, run.durUs) : g.grid.readMicro;
  let worst = null;
  let frames = 0;
  for (let i = flip; i < rows.length; i++) {
    const tUs = (rows[i].t - c.startMs) * 1000;
    const model = microPx(g, num(g, run, toPx, tUs));
    for (const [key, prop] of PROPS) {
      const v = Number.parseFloat(rows[i].cs?.[key]);
      if (!Number.isFinite(v)) continue;
      frames++;
      const diff = Math.abs(v * 1e6 - model);
      if (!worst || diff > worst.diffMicro) worst = { i, t: rows[i].t, tauMs: Math.round(tUs) / 1000, prop, measuredPx: v, modelPx: model / 1e6, diffMicro: Math.round(diff) };
    }
  }
  return { pass: frames > 0 && worst.diffMicro <= tol, width, frames, flip, startMs: c.startMs, live: c.live, jitterUs: c.jitterUs, eUs, tolMicro: tol, worst };
}

const ENGINE = { chromium: 'chromium', 'playwright-webkit': 'webkit', 'safari-1280': 'webkit' };
const ARM = { faithful: 'faithful', flag: 'variant' };

export const hasPaddingReads = (rows) => rows.some((x) => x.cs && x.nav !== undefined);

export function checkFile(g, json, browser) {
  const engine = ENGINE[browser];
  const out = [];
  for (const r of json.runs) {
    const arm = ARM[r.role];
    if (!arm) continue;
    for (const [name, seq] of Object.entries(SEQ)) {
      const rows = r.sequences?.[name]?.rows;
      if (!rows?.length) continue;
      if (!hasPaddingReads(rows)) {
        out.push({ browser, arm, mode: r.mode, rep: r.rep, width: r.width, seq, skipped: 'no padding reads' });
        continue;
      }
      const pad = PAD[r.width];
      const toPx = seq === 'entry' ? 0 : pad;
      const base = { width: r.width, seq, engine, toPx };
      const own = leanRun(g, { width: r.width, seq, engine, arm, prop: 'padding-left' });
      const curve = leanRun(g, { width: r.width, seq, engine: 'chromium', arm: 'faithful', prop: 'padding-left' });
      out.push({ browser, arm, mode: r.mode, rep: r.rep, width: r.width, seq, own: check(g, rows, { ...base, run: own }), curve: check(g, rows, { ...base, run: curve }) });
    }
  }
  return out;
}

export function checkDirs(g, runs) {
  const traces = [];
  for (const [runId, dir] of runs) {
    for (const sub of readdirSync(dir).filter((d) => d.startsWith('transitions-apple-')).sort()) {
      const raw = join(dir, sub, 'raw');
      if (!existsSync(raw)) continue;
      for (const f of readdirSync(raw).filter((x) => /^transitions-.+\.json$/.test(x)).sort()) {
        const browser = f.slice('transitions-'.length, -'.json'.length);
        if (!ENGINE[browser]) continue;
        for (const t of checkFile(g, JSON.parse(readFileSync(join(raw, f), 'utf8')), browser)) traces.push({ run: runId, artifact: sub, ...t });
      }
    }
  }
  return traces;
}

export function summarize(traces) {
  const groups = new Map();
  for (const t of traces.filter((x) => !x.skipped)) {
    const key = `${t.browser}|${t.arm}|${t.width}|${t.seq}`;
    const g = groups.get(key) ?? { browser: t.browser, arm: t.arm, width: t.width, seq: t.seq, traces: 0, ownPass: 0, curvePass: 0, worstOwnMicro: 0, worstCurveMicro: 0, maxTolMicro: 0 };
    g.traces++;
    if (t.own.pass) g.ownPass++;
    if (t.curve.pass) g.curvePass++;
    g.worstOwnMicro = Math.max(g.worstOwnMicro, t.own.worst?.diffMicro ?? 0);
    g.worstCurveMicro = Math.max(g.worstCurveMicro, t.curve.worst?.diffMicro ?? 0);
    g.maxTolMicro = Math.max(g.maxTolMicro, t.curve.tolMicro ?? 0);
    groups.set(key, g);
  }
  return [...groups.values()];
}

function main(argv) {
  const runs = [];
  let out = null;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--run') {
      const [id, dir] = argv[++i].split('=');
      runs.push([id, dir]);
    } else if (argv[i] === '--out') out = argv[++i];
  }
  if (!runs.length || !out) {
    console.error('usage: earn-curve.mjs --run <id>=<dir> [--run ...] --out <dir>');
    return 2;
  }
  const g = readGolden();
  const traces = checkDirs(g, runs);
  const groups = summarize(traces);
  mkdirSync(out, { recursive: true });
  const checked = traces.filter((t) => !t.skipped);
  const skipped = traces.filter((t) => t.skipped);
  writeFileSync(join(out, 'traces.json'), `${JSON.stringify(checked.map(({ run, artifact, browser, arm, mode, rep, width, seq, own, curve }) => ({ run, artifact, browser, arm, mode, rep, width, seq, own, curve })), null, 1)}\n`);
  const skip = { count: skipped.length, modes: [...new Set(skipped.map((t) => t.mode))], why: [...new Set(skipped.map((t) => t.skipped))] };
  writeFileSync(join(out, 'summary.json'), `${JSON.stringify({ runs: runs.map(([id]) => id), traces: checked.length, skipped: skip, groups }, null, 1)}\n`);
  console.log(`checked ${checked.length} traces, skipped ${skip.count} (${skip.modes.join(',')}: ${skip.why.join(',')})`);
  for (const s of groups) console.log(`${s.browser} ${s.arm} ${s.width} ${s.seq}: own ${s.ownPass}/${s.traces} curve ${s.curvePass}/${s.traces} worst ${s.worstCurveMicro} µpx tol ≤ ${s.maxTolMicro}`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) process.exitCode = main(process.argv.slice(2));
