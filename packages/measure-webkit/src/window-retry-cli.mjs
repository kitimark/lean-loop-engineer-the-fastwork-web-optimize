import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { OUTCOMES, redoTally } from './window-retry.mjs';

const JOB_SLOTS = 12;
const NAMES = [...OUTCOMES, 'noTime', 'noDriver'];

const arg = (flag) => { const i = process.argv.indexOf(flag); return i < 0 ? null : process.argv[i + 1]; };
const root = arg('--root');
if (!root) { console.error('usage: window-retry-cli.mjs --root <artifact dir of one run>'); process.exit(2); }

const dirs = readdirSync(root);
const all = {};
const lines = [];
for (let n = 1; n <= JOB_SLOTS; n++) {
  const dir = [`smoothness-webkit-sim-${n}-retry`, `smoothness-webkit-sim-${n}`].find((d) => dirs.includes(d));
  const f = dir ? `${root}/${dir}/touch-lock.json` : null;
  if (!f || !existsSync(f)) { lines.push(`job ${n}: no artifact`); continue; }
  const t = JSON.parse(readFileSync(f, 'utf8'));
  const tally = redoTally(t.rows);
  for (const [k, v] of Object.entries(tally)) all[k] = (all[k] ?? 0) + v;
  const ran = t.rows.filter((r) => r.redo && r.redo.ms != null);
  const ms = ran.reduce((s, r) => s + r.redo.ms, 0);
  lines.push(`job ${n}: ${t.rows.length} windows, ${JSON.stringify(tally)}, redo time ${Math.round(ms / 1000)} s of ${t.wallSeconds} s${t.incomplete ? `, incomplete: ${String(t.incomplete).slice(0, 70)}` : ''}`);
}
console.log(lines.join('\n'));
console.log(`redo outcomes by name: ${NAMES.map((k) => `${k} ${all[k] ?? 0}`).join(', ')}`);
