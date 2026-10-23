import { PERIODS, KINDS, FRAMES_60, MIN_FAITHFUL, BUSY_MIN, validAt, cell, bgOf, swapNeighbours, pooled } from './swap.mjs';

export function countOf(cap, k, p, ty) {
  if (!cap) return undefined;
  const ok = validAt(cap.ws, k) && (p.startsWith('swap:') || k + 1 < cap.ws.length);
  if (!ok) return null;
  return cap.cells.find((x) => x[0] === p && x[1] === ty)?.[2] ?? null;
}

export function bgOfCapture(cap, k, periods = PERIODS) {
  if (!cap) return 'unknown';
  const ns = swapNeighbours(k, periods).map((j) => countOf(cap, j, `rest:${j}`, 'Layout')).filter((n) => typeof n === 'number');
  return bgOf(ns);
}

export const jobBase = (pass) => {
  const j = pass.job;
  if (!j) return 'unknown';
  return `${j.jobId ?? `${j.run ?? '?'}.${j.attempt ?? '?'}/${j.vm ?? j.job ?? '?'}`}`;
};

export const jobKey = (pass, slot) => `${jobBase(pass)}/p${pass.job?.pass ?? '?'}/${slot}`;

export function cellsOf(passes, periods = PERIODS, only = null) {
  const out = [];
  for (const phase of ['swap', 'rest']) {
    if (only && phase === 'rest') continue;
    for (let k = 0; k < (phase === 'swap' ? periods : periods - 1); k++) {
      for (const ty of KINDS) {
        if (only && ty !== 'Layout' && ty !== 'Paint') continue;
        const p = `${phase}:${k}`;
        const a1 = [], a2 = [], c = [], a1Job = [], a2Job = [], cropJob = [], a1Bg = [], a2Bg = [], cropBg = [];
        let dropped = 0;
        const take = (cap, into, jobs, bgs, pass, slot) => {
          const n = countOf(cap, k, p, ty);
          if (n === undefined) return;
          if (n === null) { dropped++; return; }
          const bg = phase === 'swap' ? bgOfCapture(cap, k, periods) : 'unknown';
          if (only && bg !== only) return;
          into.push(n); jobs.push(jobKey(pass, slot)); bgs.push(bg);
        };
        for (const s of passes) {
          const caps = s.captures;
          take(caps['faithful-a'], a1, a1Job, a1Bg, s, 'a');
          take(caps['faithful-b'], a2, a2Job, a2Bg, s, 'b');
          take(caps['crop-a'], c, cropJob, cropBg, s, 'a');
          take(caps['crop-b'], c, cropJob, cropBg, s, 'b');
        }
        out.push({ phase: p, kind: ty, bg: only ?? 'all', a1, a2, crop: c, a1Job, a2Job, cropJob, a1Bg, a2Bg, cropBg, dropped, cell: cell(a1, a2, c, dropped) });
      }
    }
  }
  return out;
}

export const diagRows = (passes) => passes.filter((s) => s.diag).map((s) => ({ phase: 'diag', kind: 'Diag', job: jobKey(s, 'diag'), ...s.diag }));

export const windowCells = (passes, periods = PERIODS, only = null) =>
  only ? cellsOf(passes, periods, only) : [...cellsOf(passes, periods), ...cellsOf(passes, periods, 'idle'), ...cellsOf(passes, periods, 'busy'), ...diagRows(passes)];

const range = (xs) => (xs.length === 0 ? '-' : `${Math.min(...xs)}${Math.min(...xs) === Math.max(...xs) ? '' : `-${Math.max(...xs)}`} (n=${xs.length})`);

export function median(xs) {
  if (xs.length === 0) return null;
  const s = [...xs].sort((a, b) => a - b), m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}
const med = (xs) => (xs.length === 0 ? '-' : `${median(xs)} (n=${xs.length})`);
const byBg = (vals, bgs, bg) => vals.filter((_, i) => bgs[i] === bg);

export const swapPassesOf = (docs) => docs.flatMap((d) => d.passes.map((p) => p.cost?.swap).filter(Boolean));

function bgSection(cells, kind, label) {
  const rows = cells.filter((x) => x.bg === 'all' && x.kind === kind && x.phase.startsWith('swap:'));
  const lines = [`### ${kind} rows of a swap window by background (rest windows next to it: busy = at least ${BUSY_MIN} Layout rows)`, '',
    `| window | ${label} idle | ${label} busy | ${label} mixed | faithful idle | faithful busy |`, '|---|---|---|---|---|---|'];
  for (const x of rows) {
    const fv = [...x.a1, ...x.a2], fb = [...x.a1Bg, ...x.a2Bg];
    lines.push(`| ${x.phase} | ${med(byBg(x.crop, x.cropBg, 'idle'))} | ${med(byBg(x.crop, x.cropBg, 'busy'))} | ${med(byBg(x.crop, x.cropBg, 'mixed'))} | ${med(byBg(fv, fb, 'idle'))} | ${med(byBg(fv, fb, 'busy'))} |`);
  }
  return [...lines, ''];
}

function busyWindows(cells) {
  const rows = cells.filter((x) => x.bg === 'all' && x.kind === 'Layout' && x.phase.startsWith('swap:'));
  return rows.map((x) => {
    const n = (b) => x.cropBg.filter((y) => y === b).length;
    return { phase: x.phase, busy: n('busy'), idle: n('idle'), mixed: n('mixed'), unknown: n('unknown') };
  });
}

export function armLabel(docs, override = null) {
  if (override) return override;
  for (const d of docs) {
    const m = /[?&]fw=([^&]+)/.exec(d.search ?? '');
    if (m) return decodeURIComponent(m[1]);
  }
  return 'arm';
}

const POOL_GROUPS = [['faithful-a', ['faithful-a']], ['faithful-b', ['faithful-b']], ['arm', ['crop-a', 'crop-b']]];

export function pooledSummary(passes, periods = PERIODS) {
  const out = {};
  for (const [phase, count] of [['rest', periods - 1], ['swap', periods]]) {
    out[phase] = {};
    for (const [name, caps] of POOL_GROUPS) {
      const rows = [];
      let captures = 0;
      for (const s of passes) {
        for (const c of caps) {
          const ns = Array.from({ length: count }, (_, k) => countOf(s.captures[c], k, `${phase}:${k}`, 'Layout')).filter((n) => typeof n === 'number');
          if (ns.length) { captures++; rows.push(...ns); }
        }
      }
      out[phase][name] = pooled(rows, captures);
    }
  }
  return out;
}

const tenthsText = (t) => `${Math.floor(t / 10)}.${t % 10}`;

function pooledSection(pool, label) {
  const lines = [`### Pooled Layout rows (a window with at least ${BUSY_MIN} rows is busy; rows per capture and median over the pooled windows)`, '',
    '| windows | group | captures | windows | busy windows | rows per capture | median |', '|---|---|---|---|---|---|---|'];
  for (const phase of ['rest', 'swap']) {
    for (const [name] of POOL_GROUPS) {
      const p = pool[phase][name];
      lines.push(`| ${phase} | ${name === 'arm' ? label : name} | ${p.captures} | ${p.rows} | ${p.busyWindows} of ${p.rows} | ${tenthsText(p.tenthsPerCapture)} | ${p.median2 / 2} |`);
    }
  }
  return [...lines, ''];
}

const digit = (n, top) => (n <= 0 ? '.' : String(Math.min(9, Math.max(1, Math.ceil((n / top) * 9)))));

function diagSection(rows) {
  const lines = ['### Diagnostic captures (crop arm, no swap marks, 100 ms buckets)', ''];
  if (rows.length === 0) return [...lines, 'none captured', ''];
  for (const d of rows) {
    const top = Math.max(1, ...d.layout);
    lines.push(`Job ${d.job}: ${d.buckets} buckets; scale 1-9 of the bucket maximum (Layout max ${Math.max(...d.layout)}), '.' = 0`, '', '```',
      `Layout    ${d.layout.map((n) => digit(n, top)).join('')}`, `Paint     ${d.paint.map((n) => digit(n, Math.max(1, ...d.paint))).join('')}`);
    for (const [k, v] of Object.entries(d.owners).sort()) lines.push(`${k.slice(0, 9).padEnd(9)} ${v.map((n) => digit(n, Math.max(1, ...v))).join('')}  ${k} (total ${v.reduce((a, b) => a + b, 0)})`);
    lines.push('```', '');
    const keys = [...new Set([...Object.keys(d.before), ...Object.keys(d.after)])].sort();
    lines.push('Running animations (owner | name | kind | state | duration ms | iterations | properties), count before / after:', '');
    for (const k of keys) lines.push(`- ${k}: ${d.before[k] ?? 0} / ${d.after[k] ?? 0}`);
    lines.push('');
  }
  return lines;
}

export function swapMd(cells, sources, { label = 'crop', model = true, passes = null } = {}) {
  const std = cells.filter((x) => x.bg === 'all' || x.bg === undefined);
  const lines = [`Sources: ${sources.join('; ')}`, '', ...(model ? [`Model (INFERRED from the Lean part model): a faithful swap shows ${FRAMES_60} Layout frames at 60 Hz, the crop none.`] : [`Arm column: ${label}.`])];
  const swapLayout = std.filter((x) => x.kind === 'Layout' && x.phase.startsWith('swap:'));
  const cropAll = swapLayout.flatMap((x) => x.crop);
  const cropIdle = swapLayout.flatMap((x) => byBg(x.crop, x.cropBg ?? [], 'idle'));
  if (cropAll.length) {
    lines.push(`Measured (the ${label}, Layout rows in a swap window, ${cropAll.length} samples): minimum ${Math.min(...cropAll)}, median ${median(cropAll)}${cropIdle.length ? `; idle background only (${cropIdle.length} samples): minimum ${Math.min(...cropIdle)}, median ${median(cropIdle)}` : ''}.`);
  }
  const jobs = new Set(std.flatMap((x) => [...(x.a1Job ?? []), ...(x.a2Job ?? []), ...(x.cropJob ?? [])]).map((j) => j.replace(/\/p\d+\/[a-z]+$/, '')));
  lines.push(`Jobs counted (${jobs.size}): ${[...jobs].sort().join(', ')}. Cells need at least ${MIN_FAITHFUL} samples in each faithful slot (unresolved:fewSamples otherwise).`, '');
  for (const ty of KINDS) {
    lines.push(`### ${ty}`, '', `| window | faithful a | faithful b (A/A floor) | ${label} | dropped | verdict |`, '|---|---|---|---|---|---|');
    for (const x of std.filter((y) => y.kind === ty)) lines.push(`| ${x.phase} | ${range(x.a1)} | ${range(x.a2)} | ${range(x.crop)} | ${x.dropped} | ${x.cell} |`);
    lines.push('');
  }
  const swaps = std.filter((x) => x.phase.startsWith('swap:'));
  const tally = (ty) => ['win', 'loss', 'unresolved'].map((w) => swaps.filter((x) => x.kind === ty && x.cell.startsWith(w)).length);
  lines.push('Swap windows decided one by one (win / loss / unresolved of ' + PERIODS + ' per kind):', '', '| kind | win | loss | unresolved |', '|---|---|---|---|');
  for (const ty of KINDS) lines.push(`| ${ty} | ${tally(ty).join(' | ')} |`);
  lines.push('');
  const bw = busyWindows(std);
  if (bw.length) {
    lines.push(`### Background of each swap window in the ${label} captures`, '', '| window | busy | idle | mixed | unknown |', '|---|---|---|---|---|');
    for (const b of bw) lines.push(`| ${b.phase} | ${b.busy} | ${b.idle} | ${b.mixed} | ${b.unknown} |`);
    lines.push('');
    lines.push(...bgSection(std, 'Layout', label), ...bgSection(std, 'Paint', label));
    for (const only of ['idle', 'busy']) {
      const sub = cells.filter((x) => x.bg === only);
      if (!sub.length) continue;
      lines.push(`### Cells on ${only}-background samples only (each window and kind decided on its own)`, '', '| window | Layout | Paint |', '|---|---|---|');
      for (const x of sub.filter((y) => y.kind === 'Layout')) lines.push(`| ${x.phase} | ${x.cell} (faithful n=${x.a1.length}+${x.a2.length}, ${label} n=${x.crop.length}) | ${sub.find((y) => y.phase === x.phase && y.kind === 'Paint').cell} |`);
      lines.push('');
    }
  }
  if (passes) lines.push(...pooledSection(pooledSummary(passes), label));
  lines.push(...diagSection(cells.filter((x) => x.kind === 'Diag')));
  return lines.join('\n');
}
