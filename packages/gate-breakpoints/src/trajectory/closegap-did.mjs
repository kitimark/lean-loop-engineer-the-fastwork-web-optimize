// Parser for the run-level test of task scoped-gap-did: raw trajectory files -> one line per run with its identification and its close cells.
//   node src/trajectory/closegap-did.mjs <run id>=<raw-playwright-webkit.json> [...]   (prints the cells file, jsonl)
// The statistic and the permutation p are computed by Lean (`Fw.Gate.RunPerm`, golden/gate/run-perm.jsonl). The functions below the parser are
// a TS stand-in of Lean `identify`, `runNano`, `count`, `verdict` and `mde`, checked against that golden in test/closegap-did.test.mjs.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { closeCells } from './closegap.mjs';

export const WIDTHS = [390, 640, 641, 1280];
export const ROLE = { orig: 0, base: 1, cand: 2 };
export const SCOPED = '?fw=hero.exit:scoped';
export const FAITHFUL = '?fw=hero.exit:faithful';

/** One line of the cells file: the run, the identity its file reports, and `[width, role, g]` of every close cell. */
export function parseRun(raw, run) {
  const cells = closeCells(raw, run).filter((c) => WIDTHS.includes(c.width)).map((c) => [c.width, ROLE[c.role], c.g]);
  return { run, search: raw.search, hash: raw.hash, baseHash: raw.baseHash, cells };
}

/** Lean `identify`: the arm from search and hashes. */
export function identify(search, hash, baseHash) {
  if (search === SCOPED && hash !== baseHash) return 'scoped';
  if (search === FAITHFUL && hash === baseHash) return 'faithful';
  return null;
}

const mean = (a) => a.reduce((x, y) => x + y, 0) / a.length;

/** Lean `runNano`: D in units of 1e-9, null when a width lacks an arm. */
export function runNano(cells) {
  const ds = [];
  for (const w of WIDTHS) {
    const c = cells.filter((x) => x[0] === w && x[1] === 2).map((x) => Math.log(x[2]));
    const o = cells.filter((x) => x[0] === w && x[1] !== 2).map((x) => Math.log(x[2]));
    if (!c.length || !o.length) return null;
    ds.push(mean(c) - mean(o));
  }
  return Math.round(mean(ds) * 1e9);
}

/** Lean `count`: labelings (all ways to name k of n runs scoped) whose scoped sum is at least the observed one; k from the labels. */
export function count(vals, labels) {
  const n = vals.length, k = labels.filter((l) => l === 'scoped').length;
  const obs = vals.reduce((s, v, i) => s + (labels[i] === 'scoped' ? v : 0), 0);
  let c = 0, total = 0;
  const go = (i, left, sum) => {
    if (left === 0) { total++; if (sum >= obs) c++; return; }
    if (n - i < left) return;
    go(i + 1, left - 1, sum + vals[i]);
    go(i + 1, left, sum);
  };
  go(0, k, 0);
  return { count: c, total };
}

/** Lean `verdict`. */
export const verdict = (c, total) => (20 * c < total ? 'confirmed' : 'not-shown');

/** Lean `pooledSd` and `mde`. */
export function mde(a, b) {
  const ss = (xs) => { const m = mean(xs); return xs.reduce((s, x) => s + (x - m) ** 2, 0); };
  const sd = Math.sqrt((ss(a) + ss(b)) / (a.length + b.length - 2));
  return { sd, mde: (1.8595 + 0.8889) * sd * Math.sqrt(1 / a.length + 1 / b.length) };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const rows = process.argv.slice(2).map((arg) => { const [run, f] = arg.split('='); return parseRun(JSON.parse(readFileSync(f, 'utf8')), run); });
  rows.sort((a, b) => (a.run < b.run ? -1 : 1));
  for (const r of rows) console.log(JSON.stringify(r));
}
