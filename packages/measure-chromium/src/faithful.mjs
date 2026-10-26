// The PL5 faithful check of the end-of-page region (task faithful-checks). GLUE ONLY: every decision is Lean's
// (fwcore `faithful.verdict`, Lean `Fw.Faithful`); this script reads and writes files.
//
// Inputs, per profile p:
//   A  = results/baselines/chromium/<p>/original.baseline.json   the frozen original baseline (3 shards)
//   R  = <runs>/<p>/rewrite.baseline.json                         the rewrite of the integrated head, same format
//   A' = <runs>/<p>/original.baseline.json                        control: the original of the same CI run
//   class table = classes.frozen.json profiles[p].arms.original.types
// <runs> holds the files `zone-baseline.mjs baseline --out <runs> --profile p --target rewrite|original` writes.
//
//   node src/faithful.mjs verdict [--profile swipe-v1] [--runs results/faithful/runs] [--out results/faithful] [--check]
//        for every profile (default PROFILES) writes <out>/<p>.verdict.json: R against A (the verdict) and A' against A (the control),
//        after Lean (`faithful.comparable`, Fw.Faithful.comparable) accepted the pair. A profile with no rewrite baseline prints
//        `NO DATA: <p>`, a pair Lean refuses prints `not comparable: <field>`; either is a named refusal, the file records it
//        (`verdict: null`) and the exit code is 1. The verdict is Lean's, the refusal is Lean's or a missing file, never silence.
//        A verdict Lean leaves undecided (no zone, or a zone without evidence: Fw.Faithful.judged) prints `UNDECIDED: <p>: <reason>`
//        and exits 1; the file records the verdict with its `undecided` reason.
//   node src/faithful.mjs lean [--runs ...] [--out lean/Fw/Faithful/Measured.lean] [--check]
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { call } from './fwcore.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
export const PROFILES = ['swipe-v1', 'swipe-touch-v1'];
export const REGION = ['y04000', 'y04500', 'tail'];
const args = process.argv.slice(2);
const arg = (f, d) => { const i = args.indexOf(f); return i < 0 ? d : args[i + 1]; };
const sha = (b) => createHash('sha256').update(b).digest('hex');
const readJson = (p) => JSON.parse(readFileSync(p, 'utf8'));

/** The three region zones of a baseline file, as the `a`/`r` lists of `faithful.verdict`. */
export const regionOf = (baseline) => baseline.zones.filter((z) => REGION.includes(z.id));

/** A profile without a rewrite baseline (its CI run produced no counts) has no verdict: `NO DATA`, never silence. */
const hasR = (profile, runsDir) => existsSync(join(runsDir, profile, 'rewrite.baseline.json'));

/** Everything one profile's verdict needs, read from files. */
export function load(profile, runsDir) {
  const classesPath = join(ROOT, 'packages/measure-chromium/classes.frozen.json');
  const classesText = readFileSync(classesPath);
  const table = JSON.parse(classesText).profiles?.[profile]?.arms?.original;
  if (!table) throw new Error(`classes.frozen.json has no profile ${profile} arm original`);
  const aPath = join(ROOT, 'results/baselines/chromium', profile, 'original.baseline.json');
  const rPath = join(runsDir, profile, 'rewrite.baseline.json');
  const cPath = join(runsDir, profile, 'original.baseline.json');
  return { profile, classes: table.types, classTable: { file: relative(ROOT, classesPath), sha256: sha(classesText), image: table.image },
    A: readJson(aPath), R: readJson(rPath), C: existsSync(cPath) ? readJson(cPath) : null,
    paths: { A: relative(ROOT, aPath), R: relative(ROOT, rPath), C: relative(ROOT, cPath) } };
}

/**
 * How a baseline was measured, as the `a`/`r` of `faithful.comparable`: from `baseline.source` (written by zone-baseline.mjs since
 * run 39146329183); the frozen original baseline A predates those fields, so its zones file (checked against `zonesSha256`) is read.
 */
export function metaOf(baseline) {
  let s = baseline.source;
  if (s.viewport === undefined || s.preset === undefined || s.browser === undefined) {
    const zp = join(ROOT, s.zonesFile);
    const text = readFileSync(zp);
    if (sha(text) !== s.zonesSha256) throw new Error(`${s.zonesFile} does not hash to the sha256 its baseline names`);
    s = { ...s, ...JSON.parse(text) };
  }
  const meta = { profile: baseline.profile, preset: s.preset, browser: s.browser, zoneHeightPx: s.zoneHeightPx, viewport: s.viewport };
  if (typeof s.innerWidthPx === 'number' && typeof s.innerHeightPx === 'number') meta.observed = { width: s.innerWidthPx, height: s.innerHeightPx };
  return meta;
}

/** `faithful.comparable` of the pair (Lean `Fw.Faithful.comparable`): `{comparable, field}`; `field` names the first failing check. */
export const comparableOf = (a, r) => call([{ op: 'faithful.comparable', a, r }])[0];

/** `faithful.verdict` of `r` against `a` (baseline files) under the class table. */
export const verdictOf = (classes, a, r) => call([{ op: 'faithful.verdict', classes, a: regionOf(a), r: regionOf(r) }])[0];

const cellRows = (z) => Object.entries(z.cells)
  .filter(([, c]) => c.status === 'fail' || c.status === 'unbanded' && c.a !== c.r)
  .map(([type, c]) => ({ type, ...c }));

export const stateOf = (v) => (v.pass ? 'PASS' : v.undecided !== undefined ? `UNDECIDED (${v.undecided})` : `FAIL ${v.failedZones.join(',')}`);

export const undecidedZones = (v) => v.zones.filter((z) => z.undecided).map((z) => z.id);

export function summarize(v) {
  return {
    pass: v.pass, failedZones: v.failedZones, undecided: v.undecided,
    zones: v.zones.map((z) => ({ id: z.id, present: z.present, shape: z.shape, pass: z.pass, undecided: z.undecided, framesA: z.framesA, framesR: z.framesR,
      pxA: z.pxA, pxR: z.pxR, tally: z.tally, failed: z.failed,
      offBand: cellRows(z).filter((c) => c.status === 'fail').map(({ type, family, lo, hi, a, r }) => ({ type, family, loA: lo, hiA: hi, a, r })),
      unbandedDiffs: cellRows(z).filter((c) => c.status === 'unbanded').map(({ type, a, r }) => ({ type, a, r })) })),
  };
}

/** The profile's inputs and Lean's comparability answers, or the named refusal (`NO DATA`, `not comparable`). */
export function prepare(p, runs) {
  if (!hasR(p, runs)) return { refusal: { kind: 'no-data', text: `NO DATA: ${p}: no rewrite baseline in ${relative(ROOT, join(runs, p))} (its CI run produced no counts)` } };
  const d = load(p, runs);
  const metas = { A: metaOf(d.A), R: metaOf(d.R), C: d.C ? metaOf(d.C) : null };
  const cmpR = comparableOf(metas.A, metas.R);
  if (!cmpR.comparable) {
    return { d, metas, cmpR, refusal: { kind: 'not-comparable', field: cmpR.field, text: `not comparable: ${cmpR.field}: ${p} rewrite against the frozen original (Lean Fw.Faithful.comparable)` } };
  }
  return { d, metas, cmpR, cmpC: metas.C ? comparableOf(metas.A, metas.C) : null };
}

const NOTE = 'PL5 band verdict per zone (y04000, y04500, tail) and count type, rewrite R against the frozen original baseline A (Lean Fw.Faithful, ' +
  'fwcore faithful.verdict), after Lean Fw.Faithful.comparable accepted the pair (profile, preset, zone height, browser, profile viewport, and the ' +
  'viewport the page reported). Chromium only, one CI run per arm; raw counts are work, not milliseconds. A result outside a band is a finding.';

/** The verdict file of one profile, and its refusal (null when Lean decided). */
export function judge(p, runs) {
  const q = prepare(p, runs);
  const base = { schema: 'fw.faithful.verdict/2', note: NOTE, profile: p, region: REGION };
  if (q.refusal) {
    return { refusal: q.refusal, file: { ...base, verdict: null, refusal: { kind: q.refusal.kind, field: q.refusal.field ?? null, text: q.refusal.text },
      meta: q.metas ?? null, comparable: q.cmpR ?? null } };
  }
  const { d, metas, cmpR, cmpC } = q;
  const verdict = verdictOf(d.classes, d.A, d.R);
  const control = cmpC?.comparable ? verdictOf(d.classes, d.A, d.C) : null;
  const file = {
    ...base, classTable: d.classTable, files: d.paths,
    sourceA: d.A.source, sourceR: d.R.source, sourceControl: d.C?.source ?? null,
    meta: metas, comparable: { rewrite: cmpR, control: cmpC },
    verdict: summarize(verdict), control: control ? summarize(control) : null,
    controlRefusal: d.C === null ? 'no control baseline' : cmpC.comparable ? null : `not comparable: ${cmpC.field}`,
    reply: verdict, controlReply: control,
  };
  return { refusal: null, file, undecided: verdict.undecided ?? null, summary: `R ${stateOf(verdict)}` +
    (control ? `; control A'/A ${control.pass ? 'pass' : stateOf(control)}` : `; control: ${file.controlRefusal}`) };
}

export const namedLines = (p, j) => [...(j.refusal ? [j.refusal.text] : []), ...(j.undecided ? [`UNDECIDED: ${p}: ${j.undecided}`] : [])];

export function verdictRun({ runs, out, profiles = PROFILES, check = false }) {
  const lines = [];
  let code = 0;
  for (const p of profiles) {
    const j = judge(p, runs);
    const path = join(out, `${p}.verdict.json`);
    const text = JSON.stringify(j.file, null, 1) + '\n';
    const named = namedLines(p, j);
    lines.push(...named);
    if (named.length > 0) code = 1;
    if (check) {
      if (!existsSync(path) || readFileSync(path, 'utf8') !== text) { lines.push(`DIFFERS: ${path}`); code = 1; }
      else if (!j.refusal) lines.push(`identical: ${path}`);
    } else {
      mkdirSync(out, { recursive: true });
      writeFileSync(path, text);
      lines.push(`wrote ${path}${j.refusal ? ': no verdict (refusal recorded)' : `: ${j.summary}`}`);
    }
  }
  return { lines, code };
}

function verdictMode() {
  const runs = resolve(arg('--runs', join(ROOT, 'results/faithful/runs')));
  const out = resolve(arg('--out', join(ROOT, 'results/faithful')));
  const { lines, code } = verdictRun({ runs, out, profiles: arg('--profile') ? [arg('--profile')] : PROFILES, check: args.includes('--check') });
  for (const l of lines) (/^(NO DATA|not comparable|DIFFERS|UNDECIDED)/.test(l) ? console.error : console.log)(l);
  process.exit(code);
}

const ident = (s) => s.replace(/[^A-Za-z0-9]+(.)?/g, (_, c) => (c ? c.toUpperCase() : ''));
const lvl = { deterministic: '.det', stable: '.stable', quarantined: '.quar' };

/** The Lean source of the measured cells and the per-zone theorems. */
export function leanSource(runsDir) {
  const out = [];
  out.push('-- GENERATED by node packages/measure-chromium/src/faithful.mjs lean from results/faithful/runs: do not edit by hand',
    'import Fw.Faithful.Zone', 'import Fw.Faithful.Comparable',
    '/-! Per profile: the runs are comparable, and each zone has the pass bit and failing types `Fw.Faithful.zoneVerdict`',
    'computes; a zone theorem with `pass = false` states a failing zone;', 'the `_control_` theorems state the same for the control A\' against A. -/',
    'namespace Fw.Faithful.Measured', 'open Fw.Measure', '');
  out.push('abbrev zc (t : String) (lo hi b : Int) : ZCell := ⟨t, lo, hi, b⟩', '');
  for (const p of PROFILES) {
    const q = prepare(p, runsDir);
    if (q.refusal) throw new Error(q.refusal.text);
    const { d, metas, cmpC } = q;
    const verdict = verdictOf(d.classes, d.A, d.R);
    const control = d.C && cmpC?.comparable ? verdictOf(d.classes, d.A, d.C) : null;
    for (const v of [verdict, control]) {
      if (v && (v.undecided !== undefined || undecidedZones(v).length > 0)) throw new Error(`UNDECIDED: ${p}: ${stateOf(v)}`);
    }
    const P = ident(p);
    const entries = Object.keys(d.classes).sort().map((t) => {
      const e = d.classes[t];
      return `  ("${t}", { cls := ${lvl[e.class]}, k := ${e.k}, t := ${e.t}, tBound := ${e.tBound === undefined || e.tBound === null ? 'none' : `some ${e.tBound}`} })`;
    });
    out.push(`def ${P}Table : Freeze.Table := [`, entries.join(',\n') + ']', '');
    const zdef = (name, z) => {
      const n = (v) => (v < 0 ? `(${v})` : `${v}`);
      const cells = Object.keys(z.types).sort().map((t) => `zc "${t}" ${n(z.types[t].lo)} ${n(z.types[t].hi)} ${n(z.types[t].base)}`);
      return [`def ${name} : ZBase := ⟨"${z.id}", ${z.frames}, ${n(z.scrolledPx)}, [`, '  ' + cells.join(',\n  ') + ']⟩', ''];
    };
    const dprText = (v) => `(${Math.round(v.dpr * 1000)} / 1000 : Rat)`;
    const metaDef = (name, m) => [`def ${name} : Meta := ⟨"${m.profile}", "${m.preset}", "${m.browser}", ${m.zoneHeightPx}, ${m.viewport.width}, ${m.viewport.height}, ${dprText(m.viewport)}, ${m.viewport.mobile}, ${m.viewport.touch}, ` +
      `${m.observed ? `some ⟨${m.observed.width}, ${m.observed.height}⟩` : 'none'}⟩`, ''];
    out.push(...metaDef(`${P}MetaA`, metas.A), ...metaDef(`${P}MetaR`, metas.R));
    out.push(`theorem ${P}_comparable : comparable ${P}MetaA ${P}MetaR = none := by decide +kernel`, '');
    if (metas.C) {
      out.push(...metaDef(`${P}MetaC`, metas.C));
      out.push(`theorem ${P}_control_comparable : comparable ${P}MetaA ${P}MetaC = none := by decide +kernel`, '');
    }
    const aZ = regionOf(d.A), rZ = regionOf(d.R);
    for (const z of aZ) out.push(...zdef(`${P}A${ident(z.id)}`, z));
    for (const z of rZ) out.push(...zdef(`${P}R${ident(z.id)}`, z));
    out.push(`def ${P}A : List ZBase := [${aZ.map((z) => `${P}A${ident(z.id)}`).join(', ')}]`, '',
      `def ${P}R : List ZBase := [${rZ.map((z) => `${P}R${ident(z.id)}`).join(', ')}]`, '');
    if (control) {
      const cZ = regionOf(d.C);
      for (const z of cZ) out.push(...zdef(`${P}C${ident(z.id)}`, z));
      out.push(`def ${P}C : List ZBase := [${cZ.map((z) => `${P}C${ident(z.id)}`).join(', ')}]`, '');
    }
    for (const z of verdict.zones) {
      const failed = `[${z.failed.map((t) => `"${t}"`).join(', ')}]`;
      out.push(`theorem ${P}_${ident(z.id)} :`,
        `    (zoneVerdict ${P}Table ${P}A ${P}R "${z.id}").pass = ${z.pass} ∧`,
        `    (zoneVerdict ${P}Table ${P}A ${P}R "${z.id}").failed = ${failed} := by`, '  decide +kernel', '');
    }
    for (const z of control?.zones ?? []) {
      const failed = `[${z.failed.map((t) => `"${t}"`).join(', ')}]`;
      out.push(`theorem ${P}_control_${ident(z.id)} :`,
        `    (zoneVerdict ${P}Table ${P}A ${P}C "${z.id}").pass = ${z.pass} ∧`,
        `    (zoneVerdict ${P}Table ${P}A ${P}C "${z.id}").failed = ${failed} := by`, '  decide +kernel', '');
    }
  }
  out.push('end Fw.Faithful.Measured', '');
  return out.join('\n');
}

function leanMode() {
  const runs = resolve(arg('--runs', join(ROOT, 'results/faithful/runs')));
  const path = resolve(arg('--out', join(ROOT, 'lean/Fw/Faithful/Measured.lean')));
  let text;
  try { text = leanSource(runs); } catch (e) { console.error(e.message); process.exit(1); }
  if (args.includes('--check')) {
    if (!existsSync(path) || readFileSync(path, 'utf8') !== text) { console.error(`DIFFERS: ${path}`); process.exit(1); }
    console.log(`identical: ${path}`);
  } else {
    writeFileSync(path, text);
    console.log(`wrote ${path} (${text.split('\n').length} lines)`);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (args[0] === 'verdict') verdictMode();
  else if (args[0] === 'lean') leanMode();
  else { console.error('usage: faithful.mjs verdict|lean [--profile p] [--runs dir] [--out path] [--check]'); process.exit(2); }
}
