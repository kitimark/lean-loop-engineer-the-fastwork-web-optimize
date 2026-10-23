#!/usr/bin/env node
// usage: node scripts/plan-time.mjs [--check] [--refresh <timings.jsonl>]
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const CLOSURE_COMMIT = '9a09d8066';
export const SAMPLES = 'results/plan-sync-time/samples.jsonl';
export const DOC = 'docs/team/tools/plan.md';
const BEGIN = '<!-- plan-time begin: node scripts/plan-time.mjs -->';
const END = '<!-- plan-time end -->';

const ord = (xs, rank) => (rank === 0 ? 0 : [...xs].sort((a, b) => a - b)[rank - 1]);
export const p50 = (xs) => ord(xs, Math.floor((xs.length + 1) / 2));
export const p90 = (xs) => ord(xs, Math.floor((9 * xs.length + 9) / 10));
const maxL = (xs) => xs.reduce((a, b) => Math.max(a, b), 0);
const row = (label, xs) => `| ${label} | ${xs.length} | ${p50(xs)} ms | ${p90(xs)} ms | ${maxL(xs)} ms |\n`;

/** Lean `Fw.Plan.WritesClosure.timeTable`, replayed by apps/runner/test/plan-closure.test.ts. */
export function timeTable(before, after) {
  const b = before.slice(Math.max(0, before.length - 30));
  return '| Window | n | p50 | p90 | max |\n|---|---|---|---|---|\n' + row(`last ${b.length} runs before the closure check`, b) +
    row('every run with it', after) + `\nINFERRED: the closure check adds about ${p50(after) - p50(b)} ms to a sync (p50 with it minus p50 before).\n`;
}

const day = (ms) => new Date(ms).toISOString().slice(0, 10);

export function block(samples) {
  const dur = (closure) => samples.filter((s) => s.closure === closure).map((s) => s.durMs);
  const span = samples.length ? `${day(samples[0].startMs)} to ${day(samples.at(-1).startMs)}` : 'none';
  return `${BEGIN}\nMEASURED (\`${SAMPLES}\`, ${span}: every exit-0 \`plan sync\` span of the tool \`fw\`\nin the main checkout's ` +
    `\`.fw-console/timings.jsonl\`, any load; a run is "with it" when its commit contains ${CLOSURE_COMMIT}):\n\n` +
    `${timeTable(dur(false), dur(true))}${END}`;
}

export const readSamples = (root) =>
  readFileSync(join(root, SAMPLES), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));

export function render(root) {
  const doc = readFileSync(join(root, DOC), 'utf8');
  const i = doc.indexOf(BEGIN), j = doc.indexOf(END);
  if (i < 0 || j < i) throw new Error(`${DOC}: no ${BEGIN} ... ${END} block`);
  return doc.slice(0, i) + block(readSamples(root)) + doc.slice(j + END.length);
}

function contains(root, commit) {
  try { execFileSync('git', ['merge-base', '--is-ancestor', CLOSURE_COMMIT, commit], { cwd: root, stdio: 'ignore' }); return true; }
  catch (e) { return e.status === 1 ? false : null; }
}

export function refresh(root, timingsFile) {
  const spans = readFileSync(timingsFile, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l))
    .filter((s) => s.tool === 'fw' && s.step === 'plan sync' && s.exit === 0 && s.host === 'local' && typeof s.commit === 'string');
  const known = new Map();
  const out = [];
  for (const s of spans.sort((a, b) => a.startMs - b.startMs)) {
    if (!known.has(s.commit)) known.set(s.commit, contains(root, s.commit));
    const closure = known.get(s.commit);
    if (closure !== null) out.push({ commit: s.commit, startMs: s.startMs, durMs: s.durMs, load: s.load, closure });
  }
  writeFileSync(join(root, SAMPLES), out.map((s) => JSON.stringify(s) + '\n').join(''));
  return { kept: out.length, dropped: spans.length - out.length };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const root = join(dirname(fileURLToPath(import.meta.url)), '..');
  const args = process.argv.slice(2);
  const r = args.indexOf('--refresh');
  if (r >= 0) {
    const { kept, dropped } = refresh(root, args[r + 1]);
    console.log(`plan-time: ${kept} samples written to ${SAMPLES}, ${dropped} dropped (commit not in this repo)`);
  }
  const next = render(root);
  if (args.includes('--check')) {
    const ok = next === readFileSync(join(root, DOC), 'utf8');
    console.log(ok ? `plan-time: ${DOC} matches ${SAMPLES}` : `plan-time: ${DOC} is stale (run node scripts/plan-time.mjs)`);
    process.exit(ok ? 0 : 1);
  }
  writeFileSync(join(root, DOC), next);
  console.log(`plan-time: ${DOC} written from ${SAMPLES}`);
}
