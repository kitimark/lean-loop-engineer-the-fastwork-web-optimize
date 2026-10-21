// Tables of the Linux WebKit probe, generated from the results JSON (never typed by hand), and the splice into the research note.
//
// Input: a list of result files { meta: {vm, runId, ...}, runs: [{ arm: {id, page, width, dpr, sw}, round: 'A'|'B', reduced }] }
// (cli.mjs `run` writes one file per VM; the committed copies live in results/linux-webkit/).
// TS stand-in: layout and medians only, no verdict.

export const BEGIN = '<!-- generated:linux-webkit-tables begin -->';
export const END = '<!-- generated:linux-webkit-tables end -->';

export function median(xs) {
  const v = xs.filter((x) => typeof x === 'number' && Number.isFinite(x)).sort((a, b) => a - b);
  if (!v.length) return null;
  const m = v.length >> 1;
  return v.length % 2 ? v[m] : (v[m - 1] + v[m]) / 2;
}

const fmt = (x, d = 1) => (x === null || x === undefined ? '-' : (Math.round(x * 10 ** d) / 10 ** d).toString());
const cell = (xs) => {
  const v = xs.filter((x) => typeof x === 'number');
  return v.length ? `${fmt(median(v))} (${fmt(Math.min(...v))}-${fmt(Math.max(...v))})` : '-';
};

/** Flat samples: { vm, runId, round, id, arm, r } for every successful run of every file. Failed runs are listed apart. */
export function samples(files) {
  const ok = [];
  const failed = [];
  for (const f of files) {
    for (const run of f.runs) {
      const row = { vm: f.meta.vm, runId: f.meta.runId, round: run.round, id: run.arm.id, arm: run.arm, r: run.reduced };
      (run.reduced.error ? failed : ok).push(row);
    }
  }
  return { ok, failed };
}

/** Arm ids in first-seen order. */
function armOrder(files) {
  const seen = [];
  for (const f of files) for (const run of f.runs) if (!seen.includes(run.arm.id)) seen.push(run.arm.id);
  return seen;
}

const count = (r, type) => r.timeline.total[type]?.n ?? 0;
const TYPES = ['Layout', 'RecalculateStyles', 'FunctionCall', 'FireAnimationFrame', 'Paint', 'Composite'];

function md(rows) {
  return rows.map((r) => `| ${r.join(' | ')} |`).join('\n');
}

/** Table 1: frame intervals (ms) per arm, median over all samples with (min-max) of the per-sample p50 and median of the other columns. */
export function intervalTable(files) {
  const { ok } = samples(files);
  const rows = [['arm', 'samples', 'idle rAF p50', 'idle rAF p90', 'scroll rAF p50', 'scroll rAF p90', 'scroll rAF max', 'wheel call p50 (ms)']];
  rows.push(rows[0].map(() => '---'));
  for (const id of armOrder(files)) {
    const s = ok.filter((x) => x.id === id);
    rows.push([`\`${id}\``, String(s.length), cell(s.map((x) => x.r.idle.p50)), fmt(median(s.map((x) => x.r.idle.p90))),
      cell(s.map((x) => x.r.scroll.p50)), fmt(median(s.map((x) => x.r.scroll.p90))), fmt(median(s.map((x) => x.r.scroll.max))), fmt(median(s.map((x) => x.r.wheel.p50)))]);
  }
  return md(rows);
}

/** Table 2: A/A. Per arm and VM, the two rounds side by side for the scroll rAF p50 and the Timeline record count; and the largest relative difference. */
export function aaTable(files) {
  const { ok } = samples(files);
  const vms = [...new Set(ok.map((x) => x.vm))].sort();
  const rows = [['arm', ...vms.map((v) => `vm${v} scroll p50 A / B`), ...vms.map((v) => `vm${v} Timeline records A / B`), 'largest abs(A-B) / mean (scroll p50)']];
  rows.push(rows[0].map(() => '---'));
  for (const id of armOrder(files)) {
    const per = vms.map((v) => {
      const a = ok.find((x) => x.id === id && x.vm === v && x.round === 'A');
      const b = ok.find((x) => x.id === id && x.vm === v && x.round === 'B');
      return { a, b };
    });
    const rel = per.filter((p) => p.a && p.b && p.a.r.scroll.p50 && p.b.r.scroll.p50).map((p) => Math.abs(p.a.r.scroll.p50 - p.b.r.scroll.p50) / ((p.a.r.scroll.p50 + p.b.r.scroll.p50) / 2));
    rows.push([`\`${id}\``,
      ...per.map((p) => `${fmt(p.a?.r.scroll.p50)} / ${fmt(p.b?.r.scroll.p50)}`),
      ...per.map((p) => `${p.a ? p.a.r.timeline.records : '-'} / ${p.b ? p.b.r.timeline.records : '-'}`),
      rel.length ? `${fmt(Math.max(...rel) * 100)} %` : '-']);
  }
  return md(rows);
}

/** Table 3: Timeline record counts over the whole recording (3 s idle and 10 steps) per arm (median over samples). steps delimited = steps whose two stamps were found; steps settled = 10 - the steps that hit the settle cap. */
export function recordTable(files) {
  const { ok } = samples(files);
  const rows = [['arm', 'records', ...TYPES, 'TimeStamp', 'steps delimited', 'steps settled']];
  rows.push(rows[0].map(() => '---'));
  for (const id of armOrder(files)) {
    const s = ok.filter((x) => x.id === id);
    rows.push([`\`${id}\``, fmt(median(s.map((x) => x.r.timeline.records)), 0), ...TYPES.map((t) => fmt(median(s.map((x) => count(x.r, t))), 0)),
      fmt(median(s.map((x) => count(x.r, 'TimeStamp'))), 0), `${fmt(median(s.map((x) => x.r.timeline.stepsDelimited)), 0)} / 10`,
      `${fmt(median(s.map((x) => 10 - (x.r.scrollTimedOutSteps ?? 0))), 0)} / 10`]);
  }
  return md(rows);
}

/** Table 4: the Timeline reading step by step for one arm: rounds A and B of the first VM that has both. */
export function stepTable(files, armId) {
  const { ok } = samples(files);
  const vm = [...new Set(ok.map((x) => x.vm))].sort().find((v) => ['A', 'B'].every((r) => ok.some((x) => x.id === armId && x.vm === v && x.round === r)));
  if (vm === undefined) return `(no complete A/B pair for \`${armId}\`)`;
  const get = (round) => ok.find((x) => x.id === armId && x.vm === vm && x.round === round).r.timeline.perStep;
  const A = get('A');
  const B = get('B');
  const part = (s) => (s ? [fmt(s.window_ms), String(s.frames), ...['Layout', 'RecalculateStyles', 'FunctionCall', 'Paint', 'Composite'].map((t) => String(s.counts[t]?.n ?? 0))] : ['-', '-', '-', '-', '-', '-', '-']);
  const head = ['step', ...['A', 'B'].flatMap((x) => [`${x} window ms`, `${x} frames`, `${x} Layout`, `${x} Styles`, `${x} FnCall`, `${x} Paint`, `${x} Composite`])];
  const rows = [head, head.map(() => '---')];
  for (let i = 0; i < Math.max(A.length, B.length); i++) rows.push([String(i), ...part(A[i]), ...part(B[i])]);
  return `Arm \`${armId}\`, vm${vm}, run ${ok.find((x) => x.vm === vm)?.runId ?? '?'}\n\n${md(rows)}`;
}

/** Table 5: renderer string (a hint) and `WEBKIT_SHOW_FPS` output per arm that produced any. */
export function hintTable(files) {
  const { ok } = samples(files);
  const rows = [['arm', 'WebGL renderer string', 'FPS lines (first of first sample)']];
  rows.push(rows[0].map(() => '---'));
  const seen = new Set();
  for (const x of ok) {
    if (seen.has(x.id)) continue;
    if (!(x.arm.sw === 'fps' || x.id === 'orig-w390-d3' || x.id === 'blank-w390-d1')) continue;
    seen.add(x.id);
    rows.push([`\`${x.id}\``, (x.r.renderer ?? '-').replace(/\|/g, '/'), x.r.fps.length ? `${x.r.fps.length} lines; ${x.r.fps.slice(0, 2).join(' ; ').replace(/\|/g, '/')}` : 'none']);
  }
  return md(rows);
}

/** Runs that failed (error text), and the timeline error text when Timeline could not be read. */
export function problemList(files) {
  const { ok, failed } = samples(files);
  const lines = failed.map((x) => `- run ${x.runId} vm${x.vm} ${x.round} \`${x.id}\`: ${x.r.error}`);
  const tl = [...new Set(ok.filter((x) => x.r.timelineError).map((x) => `- Timeline: ${x.r.timelineError}`))];
  return [...lines, ...tl].join('\n') || 'none';
}

/** The whole generated block (what sits between BEGIN and END in the note). */
export function renderBlock(files, { headline = 'orig-w390-d3' } = {}) {
  const runIds = [...new Set(files.map((f) => f.meta.runId))].join(', ');
  const vms = files.length;
  return [
    `Generated by \`node packages/measure-webkit/src/linux/cli.mjs table\` from \`results/linux-webkit/*.json\`: ${vms} VM file(s) of run(s) ${runIds}; each arm ran twice per VM (A, B). Do not edit by hand.`,
    '',
    '### Frame intervals (ms between rAF callbacks)',
    '',
    'Median over all samples (VMs x rounds); the p50 columns add (min-max) of the per-sample p50.',
    '',
    intervalTable(files),
    '',
    '### A/A: the two rounds of each arm on the same VM',
    '',
    aaTable(files),
    '',
    '### Timeline records over the whole recording (3 s idle and 10 steps; median over samples)',
    '',
    'Records are counted as nested (a FunctionCall inside a FireAnimationFrame is two records). Each zone stamp is emitted twice (`performance.mark` and `console.timeStamp`), so TimeStamp = 2 x stamps.',
    '',
    recordTable(files),
    '',
    '### Timeline per settled step, A and B',
    '',
    stepTable(files, headline),
    '',
    '### Renderer string (the page sees only WebKit\'s masked name) and WEBKIT_SHOW_FPS',
    '',
    hintTable(files),
    '',
    '### Failed runs and Timeline errors',
    '',
    problemList(files),
  ].join('\n');
}

/** Put `block` between the markers of `note` (markers must exist once). */
export function splice(note, block) {
  const a = note.indexOf(BEGIN);
  const b = note.indexOf(END);
  if (a < 0 || b < a || note.indexOf(BEGIN, a + 1) >= 0) throw new Error('note: generated markers missing or repeated');
  return `${note.slice(0, a + BEGIN.length)}\n${block}\n${note.slice(b)}`;
}
