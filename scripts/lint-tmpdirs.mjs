import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { SCOPE } from './lint-wallclock.mjs';

const root = join(dirname(new URL(import.meta.url).pathname), '..');

const CLEANUP_WINDOW = 600;
const MAKE = /\bmkdtemp(Sync)?\s*\(/g;
const KEYWORD = /\b(afterAll|afterEach|after|finally|onTestFinished|teardown|cleanup)\b|\bt\.after\b|process\.on\(\s*['"]exit['"]/g;
const REMOVE = /\b(rmSync|rmdirSync|rm|rmdir|rimraf)\s*\(/;

export function makes(text) {
  const out = [];
  for (const m of text.matchAll(MAKE)) out.push(text.slice(0, m.index).split('\n').length);
  return out;
}

export function cleansUp(text) {
  for (const k of text.matchAll(KEYWORD)) if (REMOVE.test(text.slice(k.index, k.index + CLEANUP_WINDOW))) return true;
  return false;
}

export function finding(text) {
  const lines = makes(text);
  return lines.length > 0 && !cleansUp(text) ? lines : [];
}

export function trackedTests() {
  const out = execFileSync('git', ['ls-files', '-z'], { cwd: root, encoding: 'utf8', maxBuffer: 1 << 26 });
  return out.split('\0').filter((f) => SCOPE.some((r) => r.test(f)));
}

export function lint(files, read = (f) => readFileSync(join(root, f), 'utf8')) {
  const res = [];
  for (const file of files) {
    let text;
    try { text = read(file); } catch { continue; }
    const lines = finding(text);
    if (lines.length) res.push({ file, lines });
  }
  return res;
}

export function run(argv, print = console.log, files = trackedTests(), read = undefined) {
  const res = lint(files, read);
  for (const r of res) print(`lint-tmpdirs: ${r.file}:${r.lines.join(',')} creates a temp dir and never removes it in a cleanup context`);
  print(`lint-tmpdirs: ${res.length} of ${files.length} test files without cleanup`);
  return argv.includes('--strict') && res.length > 0 ? 1 : 0;
}

if (import.meta.url === `file://${process.argv[1]}`) process.exit(run(process.argv.slice(2)));
