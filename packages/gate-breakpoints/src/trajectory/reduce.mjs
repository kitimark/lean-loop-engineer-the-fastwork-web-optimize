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

/** Lean `reach`: one bucket (a tenth of the morph, x 10000). */
export const REACH = 1000;
/** Lean `beyond`: `m` is farther than REACH below every sample of `ms`, or above every one. */
export const beyond = (ms, m) => ms.every((x) => x + REACH < m) || ms.every((x) => m + REACH < x);

/** Lean `windowOf`: the original's samples a rewrite sample at `m` is compared with, or null (no counterpart: a coverage failure). */
export const windowOf = (orig, m) => {
  if (m === null || m === undefined) return null;
  if (orig.some((s) => s.m === null || s.m === undefined)) return null;
  const ms = orig.map((s) => s.m);
  if (beyond(ms, m)) return null;
  return window(ms, m).map((i) => orig[i]).filter((s) => s !== undefined);
};

/** Lean `judgeIn`: no window is `fail:coverage`. */
export const judgeIn = (kind, win, r) => (win === null ? fail('coverage') : judgeAgainst(kind, win, r));

/** Lean `bucket`: the tenth of a morph value (floor((m + 500) / 1000), clamped to 0..10); 11 for no morph value. */
export const bucket = (m) => (m === null || m === undefined ? 11 : Math.min(10, Math.max(0, Math.floor((m + 500) / 1000))));

/** Lean `needsSample`: the interior buckets of a push. */
export const needsSample = (b) => b >= 1 && b <= 9;

/** Lean `bucketVerdict`. `ph` is 'push' or 'hold'. */
export function bucketVerdict(ph, kind, orig, rew, b) {
  const rs = rew.filter((r) => bucket(r.m) === b);
  if (rs.length === 0) return ph === 'push' && needsSample(b) ? fail('coverage') : skip('noSample');
  return combine(rs.map((r) => judgeIn(kind, windowOf(orig, r.m), r)));
}

/** Lean `byM`: twelve verdicts, one per bucket. */
export const byM = (ph, kind, orig, rew) => Array.from({ length: 12 }, (_, b) => [b, bucketVerdict(ph, kind, orig, rew, b)]);

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

// ---- against the faithful arm (Lean `rel`, `laneRed`) -----------------------------------------------------------------------

/** Lean `rel`: one unit of the candidate against the same unit of the faithful arm. A unit the baseline lacks is not a failure there. */
export function rel(cand, base) {
  const c = isFail(cand), b = base !== undefined && isFail(base);
  if (c) return b ? 'both' : 'new';
  return b ? 'cleared' : 'ok';
}
/** Lean `laneRed`: the candidate is red when some unit is new. */
export const laneRed = (rels) => rels.includes('new');

// ---- which arm was measured (Lean `armCheck`, `runCheck`) ---------------------------------------------------------------------

/** Lean `armCheck`: 'ok' or 'refused:config'. An arm is { site, want, config, mode }, each of the last three a string or null. */
export function armCheck(a) {
  if (a.site === 'orig') return (a.config ?? null) === null && (a.mode ?? null) === null ? 'ok' : 'refused:config';
  const { want, config, mode } = { want: a.want ?? null, config: a.config ?? null, mode: a.mode ?? null };
  return want !== null && config !== null && mode !== null && want !== '' && config === want && mode === 'hydrate' ? 'ok' : 'refused:config';
}
/** Lean `runCheck`: a run is measured as asked iff it has arms and each is. */
export const runCheck = (arms) => (arms.length > 0 && arms.every((a) => armCheck(a) === 'ok') ? 'ok' : 'refused:config');

// ---- timing (Lean `quantile`, `readsDominate`) --------------------------------------------------------------------------------

/** Lean `quantile`: the nearest-rank quantile, p from 1 to 100; null for no samples. */
export function quantile(xs, p) {
  if (xs.length === 0) return null;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(Math.ceil((p * s.length) / 100) - 1, s.length - 1)];
}
/** Lean `readsDominate`. */
export const readsDominate = (readP50, gapP50) => gapP50 > 0 && gapP50 <= 2 * readP50;

// ---- reading the raw output of run.mjs (TS stand-in: the loops; the decisions are the functions above) ------------------

/** The phases of the end-of-page path and whether the wheel moves the morph in them (Lean `Phase`). */
export const PHASES = [['open', 'push'], ['open-hold', 'hold'], ['close', 'push'], ['close-hold', 'hold']];

/** A property is read in every frame of a push with the lean read set when the registry marks it `lean` (the discrete ones and the logo rectangle). */
export const isLeanProp = (p) => p.lean === true;

const sampleOf = (row, ni, pi, withM) => ({
  m: withM && row.m !== null && row.m !== undefined ? row.m : null,
  quiet: isQuiet(row.since),
  els: (row.nodes[ni] ?? []).map((e) => (e[pi] === undefined ? null : e[pi])),
});

/**
 * Units of one width of one engine from the two arms' raw readings: [{ width, path, phase, node, prop, kind, step, verdict }].
 * `registries`: { hero, morph, page } as exported by registry.mjs (node lists and the page properties). A path that either arm
 * did not walk (`--paths hero`) has no units. In a push phase read with a lean set, only the lean properties are units.
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
  if (orig.hero && rewrite.hero) {
    const oHero = stepRows(orig.hero.rows), wHero = stepRows(rewrite.hero.rows);
    byStepOf('hero', 'path', registries.hero, oHero, wHero);
    byStepOf('hero', 'path', pageNode, pageRows(oHero), pageRows(wHero));
  }
  if (orig.morph && rewrite.morph) {
    byStepOf('morph', 'approach', registries.morph, orig.morph.approach, rewrite.morph.approach);
    for (const [phase, ph] of PHASES) {
      const oRows = orig.morph.phases[phase] ?? [], wRows = rewrite.morph.phases[phase] ?? [];
      const lean = (rewrite.morph.phaseReads?.[phase] ?? 'full') === 'lean';
      for (const n of registries.morph) {
        n.props.forEach((p, pi) => {
          if (lean && !isLeanProp(p)) return;
          const o = oRows.map((r) => sampleOf(r, n.id, pi, true));
          const w = wRows.map((r) => sampleOf(r, n.id, pi, true));
          push('morph', phase, n.id, p.id, p.kind, byM(ph, p.kind, o, w).map(([b, v]) => [`${phase}@${b}`, v]));
        });
      }
    }
  }
  return units;
}

/** The unit's identity across arms: the same width, path, phase, node, property and step. */
export const unitKey = (u) => `${u.width}|${u.path}|${u.phase}|${u.node}|${u.prop}|${u.step}`;

/** Every arm a raw run opened: { run, path, site, want, config, mode }. */
export function armsOf(raw) {
  const out = [];
  for (const r of raw.runs) {
    for (const path of ['hero', 'morph']) {
      if (!r[path]) continue;
      for (const a of [r[path].arm, ...(r[path].extraArms ?? [])]) out.push({ role: r.role ?? (r.site === 'orig' ? 'orig' : 'cand'), width: r.width, path, site: r.site, want: r.want ?? null, config: a?.config ?? null, mode: a?.mode ?? null });
    }
  }
  return out;
}

const roleOf = (r) => r.role ?? (r.site === 'orig' ? 'orig' : 'cand');

/** Milliseconds as whole tenths (Lean `quantile` takes naturals); the reports divide by ten. */
const tenths = (ms) => Math.max(0, Math.round(ms * 10));
const ms1 = (x) => (x === null ? null : x / 10);

/** Timing of the samples: per role and push/hold phase, the read cost (t1 - t0) and the gap between two samples. */
export function timingOf(raw) {
  const out = [];
  for (const role of ['orig', 'base', 'cand']) {
    const runs = raw.runs.filter((r) => roleOf(r) === role && r.morph);
    for (const [phase] of PHASES) {
      const reads = [], gaps = [];
      for (const r of runs) {
        const rows = (r.morph.phases[phase] ?? []).filter((x) => typeof x.t0 === 'number' && typeof x.t1 === 'number');
        rows.forEach((x, i) => { reads.push(tenths(x.t1 - x.t0)); if (i + 1 < rows.length && rows[i + 1].rep === x.rep) gaps.push(tenths(rows[i + 1].t0 - x.t0)); });
      }
      if (reads.length === 0) continue;
      const row = { role, phase, n: reads.length, readP50: quantile(reads, 50), readP90: quantile(reads, 90), gapP50: quantile(gaps, 50), gapP90: quantile(gaps, 90) };
      row.dominate = row.gapP50 !== null && readsDominate(row.readP50, row.gapP50);
      for (const k of ['readP50', 'readP90', 'gapP50', 'gapP90']) row[k] = ms1(row[k]);
      out.push(row);
    }
    const hero = raw.runs.filter((r) => roleOf(r) === role && r.hero);
    const hreads = hero.flatMap((r) => r.hero.rows.filter((x) => typeof x.t0 === 'number').map((x) => tenths(x.t1 - x.t0)));
    if (hreads.length > 0) out.push({ role, phase: 'hero', n: hreads.length, readP50: ms1(quantile(hreads, 50)), readP90: ms1(quantile(hreads, 90)), gapP50: null, gapP90: null, dominate: false });
  }
  return out;
}

/**
 * Everything the lane says about a raw run. First the arms: a run whose arms were not measured as asked is `refused` and has no
 * units (never a pass). Then the units of the candidate (against the original) and, unit by unit, against the same unit of the
 * faithful arm: `rel` new / both / cleared / ok. `red` = some unit is new.
 */
export function reduceRaw(raw, registries) {
  const arms = armsOf(raw);
  const refusedArms = arms.filter((a) => armCheck(a) !== 'ok');
  const timing = timingOf(raw);
  if (runCheck(arms) !== 'ok') {
    const detail = arms.length === 0 ? 'no arm was opened' : refusedArms.slice(0, 4).map((a) => `${a.role} w=${a.width} ${a.path}: config ${a.config ?? 'none'} mode ${a.mode ?? 'none'} want ${a.want ?? 'none'}`).join('; ');
    return { refused: true, detail, arms, units: [], groups: [], totals: null, rels: null, notes: [], fails: false, red: false, timing };
  }
  const units = [];
  const notes = [];
  const widths = [...new Set(raw.runs.map((r) => r.width))];
  for (const width of widths) {
    const find = (role) => raw.runs.find((r) => r.width === width && roleOf(r) === role);
    const orig = find('orig'), cand = find('cand'), base = find('base');
    if (!orig || !cand) { notes.push(`width ${width}: an arm is missing`); continue; }
    if (!base) notes.push(`width ${width}: no faithful arm, every failure counts as new`);
    for (const run of [orig, cand, ...(base ? [base] : [])]) {
      if (run.hero && !run.hero.ready?.ready) notes.push(`width ${width} ${roleOf(run)}: hero page not ready`);
      if (run.morph && !run.morph.watched) notes.push(`width ${width} ${roleOf(run)}: nav not found`);
      const open = (run.hero?.rows ?? []).filter((r) => r.frame === 'rest' && r.settled === false).length;
      if (open > 0) notes.push(`width ${width} ${roleOf(run)}: ${open} hero steps did not settle`);
    }
    const baseVerdicts = new Map(base ? reduceWidth({ width, orig, rewrite: base, registries }).map((u) => [unitKey(u), u.verdict]) : []);
    for (const u of reduceWidth({ width, orig, rewrite: cand, registries })) {
      const b = baseVerdicts.get(unitKey(u));
      units.push({ ...u, base: b ?? null, rel: rel(u.verdict, b) });
    }
  }
  const groups = new Map();
  for (const u of units) {
    const key = `${u.width}\u0000${u.path}\u0000${u.node}\u0000${u.prop}`;
    const g = groups.get(key) ?? { width: u.width, path: u.path, node: u.node, prop: u.prop, kind: u.kind, pass: 0, fail: 0, skip: 0, new: 0, both: 0, cleared: 0, failing: [], newSteps: [] };
    if (u.verdict === pass) g.pass++; else if (isFail(u.verdict)) { g.fail++; g.failing.push(`${u.step}=${u.verdict.slice(5)}`); } else g.skip++;
    if (u.rel === 'both' || u.rel === 'cleared') g[u.rel]++;
    if (u.rel === 'new') g.newSteps.push(`${u.step}=${u.verdict.slice(5)}`);
    groups.set(key, g);
  }
  const rels = { ok: 0, both: 0, cleared: 0, new: 0 };
  for (const u of units) rels[u.rel]++;
  const totals = { units: units.length, pass: 0, fail: 0, skip: 0, coverageFail: 0, coverageNew: 0 };
  for (const u of units) {
    totals[u.verdict === pass ? 'pass' : isFail(u.verdict) ? 'fail' : 'skip']++;
    if (u.verdict === fail('coverage')) { totals.coverageFail++; if (u.rel === 'new') totals.coverageNew++; }
  }
  return { refused: false, detail: '', arms, units, groups: [...groups.values()], totals, rels, notes, fails: laneFails(units.map((u) => u.verdict)), red: laneRed(units.map((u) => u.rel)), timing };
}

/** VERDICT lines: refusal; else one per group with a new failure, then the total, then the timing rows. */
export function verdictLines(engine, search, red) {
  const s = search || '(default)';
  if (red.refused) return [`VERDICT trajectory ${engine} search=${s} REFUSED config: ${red.detail}`];
  const lines = [];
  for (const g of red.groups.filter((x) => x.newSteps.length > 0)) {
    lines.push(`VERDICT trajectory ${engine} w=${g.width} ${g.path} ${g.node}.${g.prop} NEW ${g.newSteps.length}/${g.pass + g.fail + g.skip} units: ${g.newSteps.slice(0, 6).join(' ')}${g.newSteps.length > 6 ? ' ...' : ''}`);
  }
  lines.push(`VERDICT trajectory ${engine} search=${s} ${red.red ? 'RED' : 'CLEAN'} new=${red.rels.new} both=${red.rels.both} cleared=${red.rels.cleared} ok=${red.rels.ok} units=${red.totals.units} fail=${red.totals.fail} coverage=${red.totals.coverageFail} coverage_new=${red.totals.coverageNew}`);
  for (const t of red.timing) lines.push(`TIMING trajectory ${engine} ${t.role} ${t.phase} n=${t.n} read p50=${t.readP50} p90=${t.readP90} ms gap p50=${t.gapP50 ?? '-'} p90=${t.gapP90 ?? '-'} ms${t.dominate ? ' READS-DOMINATE' : ''}`);
  return lines;
}
