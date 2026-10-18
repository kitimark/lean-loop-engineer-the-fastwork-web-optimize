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
//        writes <out>/<p>.verdict.json: R against A (the verdict) and A' against A (the control)
//   node src/faithful.mjs lean [--runs ...] [--out lean/Fw/Faithful/Measured.lean] [--check]
//        writes the Lean file with the measured cells and one theorem per profile and zone (decided by `decide`)
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

/** A profile without a rewrite baseline (its CI run produced no counts, see results/faithful/swipe-touch-v1.finding.json) has no verdict. */
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

/** `faithful.verdict` of `r` against `a` (baseline files) under the class table. */
export const verdictOf = (classes, a, r) => call([{ op: 'faithful.verdict', classes, a: regionOf(a), r: regionOf(r) }])[0];

const cellRows = (z) => Object.entries(z.cells)
  .filter(([, c]) => c.status === 'fail' || c.status === 'unbanded' && c.a !== c.r)
  .map(([type, c]) => ({ type, ...c }));

/** The report of one verdict: per zone the shape, tally, failed cells and unbanded differences. */
export function summarize(v) {
  return {
    pass: v.pass, failedZones: v.failedZones,
    zones: v.zones.map((z) => ({ id: z.id, present: z.present, shape: z.shape, pass: z.pass, framesA: z.framesA, framesR: z.framesR,
      pxA: z.pxA, pxR: z.pxR, tally: z.tally, failed: z.failed,
      offBand: cellRows(z).filter((c) => c.status === 'fail').map(({ type, family, lo, hi, a, r }) => ({ type, family, loA: lo, hiA: hi, a, r })),
      unbandedDiffs: cellRows(z).filter((c) => c.status === 'unbanded').map(({ type, a, r }) => ({ type, a, r })) })),
  };
}

function verdictMode() {
  const runs = resolve(arg('--runs', join(ROOT, 'results/faithful/runs')));
  const outDir = resolve(arg('--out', join(ROOT, 'results/faithful')));
  const profiles = (arg('--profile') ? [arg('--profile')] : PROFILES).filter((p) => hasR(p, runs));
  for (const p of profiles) {
    const d = load(p, runs);
    const verdict = verdictOf(d.classes, d.A, d.R);
    const control = d.C ? verdictOf(d.classes, d.A, d.C) : null;
    const file = {
      schema: 'fw.faithful.verdict/1',
      note: 'PL5 band verdict per zone (y04000, y04500, tail) and count type, rewrite R against the frozen original baseline A (Lean Fw.Faithful, ' +
        'fwcore faithful.verdict). Chromium only, one CI run per arm; raw counts are work, not milliseconds. A result outside a band is a finding.',
      profile: p, region: REGION, classTable: d.classTable, files: d.paths,
      sourceA: d.A.source, sourceR: d.R.source, sourceControl: d.C?.source ?? null,
      verdict: summarize(verdict), control: control ? summarize(control) : null,
      reply: verdict, controlReply: control,
    };
    const text = JSON.stringify(file, null, 1) + '\n';
    const path = join(outDir, `${p}.verdict.json`);
    if (args.includes('--check')) {
      if (!existsSync(path) || readFileSync(path, 'utf8') !== text) { console.error(`DIFFERS: ${path}`); process.exit(1); }
      console.log(`identical: ${path}`);
    } else {
      mkdirSync(outDir, { recursive: true });
      writeFileSync(path, text);
      console.log(`wrote ${path}: R ${verdict.pass ? 'PASS' : 'FAIL ' + verdict.failedZones.join(',')}` +
        (control ? `; control A'/A ${control.pass ? 'pass' : 'FAIL ' + control.failedZones.join(',')}` : ''));
    }
  }
}

const ident = (s) => s.replace(/[^A-Za-z0-9]+(.)?/g, (_, c) => (c ? c.toUpperCase() : ''));
const lvl = { deterministic: '.det', stable: '.stable', quarantined: '.quar' };

/** The Lean source of the measured cells and the per-zone theorems. */
export function leanSource(runsDir) {
  const out = [];
  out.push('import Fw.Faithful.Zone', '/-!',
    '# The measured PL5 verdict of the end-of-page region (generated, task faithful-checks)', '',
    'Generated by `packages/measure-chromium/src/faithful.mjs lean` from the frozen original baseline, the rewrite baseline of one CI run',
    'and the class table of `classes.frozen.json`; never edited by hand. One theorem per profile and zone states the pass bit and the',
    'failing types that `Fw.Faithful.zoneVerdict` computes from those cells (decided by `decide`). A zone outside its band is stated as',
    'it is, with the failing types listed; the theorem is not a claim that the zone passes.', '-/',
    'namespace Fw.Faithful.Measured', 'open Fw.Measure', '');
  out.push('/-- A cell.', '', '$$\\mathrm{zc}(\\tau, \\mathrm{lo}, \\mathrm{hi}, b) = (\\tau, \\mathrm{lo}, \\mathrm{hi}, b)$$', '-/',
    'abbrev zc (t : String) (lo hi b : Int) : ZCell := ⟨t, lo, hi, b⟩', '');
  for (const p of PROFILES.filter((q) => hasR(q, runsDir))) {
    const d = load(p, runsDir);
    const verdict = verdictOf(d.classes, d.A, d.R);
    const P = ident(p);
    const entries = Object.keys(d.classes).sort().map((t) => {
      const e = d.classes[t];
      return `  ("${t}", { cls := ${lvl[e.class]}, k := ${e.k}, t := ${e.t}, tBound := ${e.tBound === undefined || e.tBound === null ? 'none' : `some ${e.tBound}`} })`;
    });
    out.push(`/-- The class table of the original arm of profile \`${p}\` (\`classes.frozen.json\`, sha256 ${d.classTable.sha256.slice(0, 12)}).`, '',
      `$$T_{\\mathrm{${p}}} = [(\\tau, e_\\tau)]_{\\tau}$$`, '-/',
      `def ${P}Table : Freeze.Table := [`, entries.join(',\n') + ']', '');
    const zdef = (name, arm, z) => {
      const n = (v) => (v < 0 ? `(${v})` : `${v}`);
      const cells = Object.keys(z.types).sort().map((t) => `zc "${t}" ${n(z.types[t].lo)} ${n(z.types[t].hi)} ${n(z.types[t].base)}`);
      return [`/-- Zone \`${z.id}\` of ${arm} in profile \`${p}\`: ${z.frames} frames, ${z.scrolledPx} px.`, '',
        `$$\\mathrm{${name.replace(/[A-Z]/g, (c) => c)}} = (\\texttt{${z.id}}, ${z.frames}, ${z.scrolledPx}, \\text{cells})$$`, '-/',
        `def ${name} : ZBase := ⟨"${z.id}", ${z.frames}, ${n(z.scrolledPx)}, [`, '  ' + cells.join(',\n  ') + ']⟩', ''];
    };
    const aZ = regionOf(d.A), rZ = regionOf(d.R);
    for (const z of aZ) out.push(...zdef(`${P}A${ident(z.id)}`, 'the original (frozen baseline)', z));
    for (const z of rZ) out.push(...zdef(`${P}R${ident(z.id)}`, 'the rewrite (integrated head)', z));
    out.push(`/-- The original's region zones of \`${p}\`.`, '', `$$As_{\\mathrm{${p}}} = [\\ldots]$$`, '-/',
      `def ${P}A : List ZBase := [${aZ.map((z) => `${P}A${ident(z.id)}`).join(', ')}]`, '',
      `/-- The rewrite's region zones of \`${p}\`.`, '', `$$Rs_{\\mathrm{${p}}} = [\\ldots]$$`, '-/',
      `def ${P}R : List ZBase := [${rZ.map((z) => `${P}R${ident(z.id)}`).join(', ')}]`, '');
    for (const z of verdict.zones) {
      const failed = `[${z.failed.map((t) => `"${t}"`).join(', ')}]`;
      out.push(`/-- **Zone \`${z.id}\` of \`${p}\`, measured.** The verdict \`Fw.Faithful.zoneVerdict\` computes from the cells above: ` +
        `${z.pass ? 'it passes' : 'it does not pass'}; failing types ${z.failed.length ? z.failed.map((t) => '`' + t + '`').join(', ') : 'none'}; ` +
        `present ${z.present}, shape ${z.shape}.`, '',
        `$$\\operatorname{pass}(\\operatorname{zoneVerdict}_{T}(As, Rs, \\texttt{${z.id}})) = ${z.pass ? '\\top' : '\\bot'} \\ \\land\\ \\operatorname{failed} = ${z.failed.length ? '\\{' + z.failed.map((t) => '\\texttt{' + t.replace(/_/g, '\\_') + '}').join(', ') + '\\}' : '\\emptyset'}$$`, '-/',
        `theorem ${P}_${ident(z.id)} :`,
        `    (zoneVerdict ${P}Table ${P}A ${P}R "${z.id}").pass = ${z.pass} ∧`,
        `    (zoneVerdict ${P}Table ${P}A ${P}R "${z.id}").failed = ${failed} := by`, '  decide +kernel', '');
    }
  }
  out.push('end Fw.Faithful.Measured', '');
  return out.join('\n');
}

function leanMode() {
  const runs = resolve(arg('--runs', join(ROOT, 'results/faithful/runs')));
  const path = resolve(arg('--out', join(ROOT, 'lean/Fw/Faithful/Measured.lean')));
  const text = leanSource(runs);
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
