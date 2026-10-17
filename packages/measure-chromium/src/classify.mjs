// Determinism classes of every count type over N runs, decided by fwcore (Lean Fw.Measure.classify; nothing decided here).
//   node src/classify.mjs out/swipe-v1/a/counts.json out/swipe-v1/b/counts.json [more...] [--kMax 4] [--tMax 24] [--json]
// deterministic: no frame differs between any two runs; stable(k, t): at most k frames differ and run totals differ by
// at most t, with k <= kMax and t <= tMax; quarantined otherwise. k and t are the observed maxima over all run pairs.
import { readFileSync } from 'node:fs';
import { classify } from './fwcore.mjs';

const argv = process.argv.slice(2).filter((a) => a !== '--');
const num = (name, dflt) => { const i = argv.indexOf(`--${name}`); return i >= 0 ? Number(argv[i + 1]) : dflt; };
const files = argv.filter((a) => a.endsWith('.json'));
const runs = files.map((f) => JSON.parse(readFileSync(f, 'utf8')));
const classes = classify(runs.map((r) => ({ frames: r.frames })), num('kMax', 4), num('tMax', 24));
if (argv.includes('--json')) { console.log(JSON.stringify(classes)); process.exit(0); }
const w = Math.max(...Object.keys(classes).map((t) => t.length));
console.log(`${'type'.padEnd(w)}  class          k     t   (${files.length} runs)`);
for (const [t, c] of Object.entries(classes)) console.log(`${t.padEnd(w)}  ${c.class.padEnd(13)} ${String(c.k).padStart(3)} ${String(c.t).padStart(5)}`);
