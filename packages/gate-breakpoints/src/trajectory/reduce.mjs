// The pure side of the trajectory probe: TypeScript twin of lean/Fw/Gate/Trajectory.lean, checked against
// packages/contracts/golden/gate/trajectory.jsonl (test/trajectory.test.mjs). Every function below mirrors a Lean definition of the
// same name; `reduceRun` (the loop over nodes, properties and steps) is the only part Lean does not hold (a listed TS stand-in).
//
// A reading (Val) is null (absent), an array of integers (a number x 1000) or a string. A sample is { m, quiet, els }.

export const TOL = { discrete: 0, geometry: 1000, unit: 10, colour: 2000 };
export const QUIET_MS = 300;
export const ALLOWED_WIDTHS = [390, 640, 641, 1280];

export const isQuiet = (sinceMs) => sinceMs === null || sinceMs === undefined || sinceMs >= QUIET_MS;

const pass = 'pass';
const fail = (w) => `fail:${w}`;
const skip = (s) => `skip:${s}`;

const inBand = (t, win, xs) => xs.every((x, j) => {
  const c = win.map((w) => w[j] ?? 0);
  return Math.min(...c) - t <= x && x <= Math.max(...c) + t;
});
const sameNums = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);

/** One element: the rewrite's reading against the window of the original's readings. */
export function judgeVal(kind, win, r) {
  if (win.length === 0) return skip('noSample');
  if (r === null) return win.every((w) => w === null) ? pass : fail('missing');
  if (win.some((w) => w === null)) return fail('missing');
  if (typeof r === 'string') {
    if (!win.every((w) => typeof w === 'string')) return fail('type');
    return win.includes(r) ? pass : fail('differs');
  }
  if (!win.every((w) => Array.isArray(w))) return fail('type');
  if (win.some((w) => w.length !== r.length)) return fail('shape');
  if (kind === 'discrete') return win.some((w) => sameNums(w, r)) ? pass : fail('differs');
  return inBand(TOL[kind], win, r) ? pass : fail('apart');
}

/** Several verdicts as one: the first failure, else a pass if any passed, else a skip. */
export function combine(vs) {
  const f = vs.find((v) => v.startsWith('fail:'));
  if (f) return f;
  if (vs.includes(pass)) return pass;
  return vs.includes(skip('transient')) ? skip('transient') : skip('noSample');
}

/** All elements of a node: counts must match, then each element on its own. */
export function judgeEls(kind, win, r) {
  if (win.length === 0) return skip('noSample');
  if (win.some((w) => w.length !== r.length)) return fail('count');
  return combine(r.map((rv, i) => judgeVal(kind, win.map((w) => w[i] ?? null), rv ?? null)));
}

export function judgeAgainst(kind, win, r) {
  if (kind === 'colour' && !r.quiet) return skip('transient');
  return judgeEls(kind, win.map((s) => s.els), r.els);
}

const between = (a, b, m) => Math.min(a, b) <= m && m <= Math.max(a, b);

export function nearest(ms, m) {
  let best = 0;
  for (let k = 0; k < ms.length; k++) if (Math.abs(ms[k] - m) < Math.abs(ms[best] - m)) best = k;
  return best;
}

const pairHit = (ms, m, j) => (j + 1 < ms.length && between(ms[j], ms[j + 1], m)) || (j > 0 && between(ms[j - 1], ms[j], m));

/** The original's samples aligned to the morph value `m`: the ends of the enclosing pairs (else the nearest sample) and one sample on each side. */
export function window(ms, m) {
  if (ms.length === 0) return [];
  const idx = ms.map((_, j) => j);
  const hasPair = idx.some((j) => pairHit(ms, m, j));
  const near = nearest(ms, m);
  const core = idx.filter((j) => (hasPair ? pairHit(ms, m, j) : j === near));
  return idx.filter((i) => core.some((j) => i <= j + 1 && j <= i + 1));
}

export const windowOf = (orig, m) => {
  if (m === null) return orig;
  if (orig.some((s) => s.m === null)) return orig;
  return window(orig.map((s) => s.m), m).map((i) => orig[i]).filter((s) => s !== undefined);
};

/** Lean `Int` division rounds down, so the tenth of a morph value is floor((m + 500) / 1000), clamped to 0..10. */
export const bucket = (m) => (m === null ? 11 : Math.min(10, Math.max(0, Math.floor((m + 500) / 1000))));

export function byM(kind, orig, rew) {
  return Array.from({ length: 12 }, (_, b) => [b, combine(rew.filter((r) => bucket(r.m) === b).map((r) => judgeAgainst(kind, windowOf(orig, r.m), r)))]);
}

export function byStep(kind, orig, rew) {
  return orig.map(([step, o]) => {
    const r = rew.find(([s]) => s === step);
    return [step, r ? judgeAgainst(kind, [o], r[1]) : skip('noSample')];
  });
}

/** The widths of a run from the comma list of the `widths` input; null when refused. */
export function pickWidths(s) {
  if (s === '') return [...ALLOWED_WIDTHS];
  const parts = s.split(',');
  if (!parts.every((p) => /^[0-9]+$/.test(p))) return null;
  const ns = parts.map(Number);
  return ns.every((n) => ALLOWED_WIDTHS.includes(n)) && new Set(ns).size === ns.length ? ns : null;
}

export const isFail = (v) => v.startsWith('fail:');
export const laneFails = (vs) => vs.some(isFail);

// ---- reading the raw output of run.mjs (TS stand-in: the loops; the decisions are the functions above) ------------------

const PHASES = ['open', 'open-hold', 'close', 'close-hold'];

/** The kind of every property of the registry, by node id. */
function kindsOf(registry) {
  const out = {};
  for (const n of registry) for (const p of n.props) out[`${n.id}\u0000${p.id}`] = p.kind;
  return out;
}

const sampleOf = (row, ni, pi, withM) => ({
  m: withM && row.m !== null && row.m !== undefined ? row.m : null,
  quiet: isQuiet(row.since),
  els: (row.nodes[ni] ?? []).map((e) => (e[pi] === undefined ? null : e[pi])),
});

/**
 * Units of one width of one engine from the two arms' raw readings: [{ width, path, phase, node, prop, kind, step, verdict }].
 * `registries`: { hero, morph, page } as exported by registry.mjs (node lists and the page properties).
 */
export function reduceWidth({ width, orig, rewrite, registries }) {
  const units = [];
  const push = (path, phase, node, prop, kind, rows) => { for (const [step, verdict] of rows) units.push({ width, path, phase, node, prop, kind, step, verdict }); };
  const stepRows = (rows) => rows.filter((r) => r.frame === 'rest');
  const byStepOf = (path, phase, nodes, oRows, rRows) => {
    for (const n of nodes) {
      n.props.forEach((p, pi) => {
        const o = oRows.map((r) => [r.step, sampleOf(r, n.id, pi, false)]);
        const w = rRows.map((r) => [r.step, sampleOf(r, n.id, pi, false)]);
        push(path, phase, n.id, p.id, p.kind, byStep(p.kind, o, w));
      });
    }
  };
  const pageRows = (rows) => rows.map((r) => ({ ...r, nodes: { page: [r.page] } }));
  const pageNode = [{ id: 'page', props: registries.page }];
  const oHero = stepRows(orig.hero.rows), wHero = stepRows(rewrite.hero.rows);
  byStepOf('hero', 'path', registries.hero, oHero, wHero);
  byStepOf('hero', 'path', pageNode, pageRows(oHero), pageRows(wHero));
  byStepOf('morph', 'approach', registries.morph, orig.morph.approach, rewrite.morph.approach);
  for (const phase of PHASES) {
    const oRows = orig.morph.phases[phase] ?? [], wRows = rewrite.morph.phases[phase] ?? [];
    for (const n of registries.morph) {
      n.props.forEach((p, pi) => {
        const o = oRows.map((r) => sampleOf(r, n.id, pi, true));
        const w = wRows.map((r) => sampleOf(r, n.id, pi, true));
        push('morph', phase, n.id, p.id, p.kind, byM(p.kind, o, w).map(([b, v]) => [`${phase}@${b}`, v]));
      });
    }
  }
  return units;
}

/** Everything the lane says about a raw run: its units, the failing groups and the totals. */
export function reduceRaw(raw, registries) {
  const units = [];
  const widths = [...new Set(raw.runs.map((r) => r.width))];
  const notes = [];
  for (const width of widths) {
    const orig = raw.runs.find((r) => r.width === width && r.site === 'orig');
    const rewrite = raw.runs.find((r) => r.width === width && r.site === 'rewrite');
    if (!orig || !rewrite) { notes.push(`width ${width}: an arm is missing`); continue; }
    for (const run of [orig, rewrite]) {
      if (!run.hero.ready?.ready) notes.push(`width ${width} ${run.site}: hero page not ready`);
      if (!run.morph.watched) notes.push(`width ${width} ${run.site}: nav not found`);
      const open = run.hero.rows.filter((r) => r.frame === 'rest' && r.settled === false).length;
      if (open > 0) notes.push(`width ${width} ${run.site}: ${open} hero steps did not settle`);
    }
    units.push(...reduceWidth({ width, orig, rewrite, registries }));
  }
  const groups = new Map();
  for (const u of units) {
    const key = `${u.width}\u0000${u.path}\u0000${u.node}\u0000${u.prop}`;
    const g = groups.get(key) ?? { width: u.width, path: u.path, node: u.node, prop: u.prop, kind: u.kind, pass: 0, fail: 0, skip: 0, failing: [] };
    if (u.verdict === pass) g.pass++; else if (isFail(u.verdict)) { g.fail++; g.failing.push(`${u.step}=${u.verdict.slice(5)}`); } else g.skip++;
    groups.set(key, g);
  }
  const totals = { units: units.length, pass: 0, fail: 0, skip: 0 };
  for (const u of units) totals[u.verdict === pass ? 'pass' : isFail(u.verdict) ? 'fail' : 'skip']++;
  return { units, groups: [...groups.values()], totals, notes, fails: laneFails(units.map((u) => u.verdict)) };
}

/** VERDICT lines: one per failing group, then the total. */
export function verdictLines(engine, search, red) {
  const lines = [];
  for (const g of red.groups.filter((x) => x.fail > 0)) {
    lines.push(`VERDICT trajectory ${engine} w=${g.width} ${g.path} ${g.node}.${g.prop} FAIL ${g.fail}/${g.pass + g.fail + g.skip} units: ${g.failing.slice(0, 6).join(' ')}${g.failing.length > 6 ? ' ...' : ''}`);
  }
  lines.push(`VERDICT trajectory ${engine} search=${search || '(default)'} ${red.fails ? 'FAIL' : 'PASS'} units=${red.totals.units} pass=${red.totals.pass} fail=${red.totals.fail} skip=${red.totals.skip}`);
  return lines;
}
