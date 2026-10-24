import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const root = join(dirname(new URL(import.meta.url).pathname), '..');
const CALL = /(?:^|[\s;&|(])(?:job|serial) "/g;

export function joinedLines(text) {
  const out = [];
  text.split('\n').forEach((line, i) => {
    const code = line.replace(/\s#(?:\s.*)?$/, '').replace(/^\s*#.*$/, '');
    if ([...code.matchAll(CALL)].length > 1) out.push(i + 1);
  });
  return out;
}

export function run(path = join(root, 'lean/scripts/check.sh')) {
  const bad = joinedLines(readFileSync(path, 'utf8'));
  for (const n of bad) console.log(`lint-check-sh: ${path}:${n} holds more than one job/serial call`);
  console.log(`VERDICT lint-check-sh ${bad.length ? 'refused' : 'clean'}`);
  return bad.length ? 1 : 0;
}

if (process.argv[1] && new URL(import.meta.url).pathname === process.argv[1]) process.exit(run(process.argv[2]));
