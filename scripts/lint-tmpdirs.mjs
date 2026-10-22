// Flags a tracked test file that creates a temp directory (mkdtemp / mkdtempSync) and never removes anything in a cleanup
// context (afterAll, afterEach, after, finally, t.after, onTestFinished, an exit handler). Task disk-gc-tmp, incident
// inc-tmp-trace-leak: ~103000 fw* temp dirs from test suites filled the user temp folder.
// LISTED TS STAND-IN: a file-level heuristic (a removal call within CLEANUP_WINDOW characters after a cleanup keyword);
// it decides nothing about deletion (that is Lean `Fw.Ops.DiskGc` class 7), it only reports.
//   node scripts/lint-tmpdirs.mjs            list the findings (exit 0; fixing them is a follow-up)
//   node scripts/lint-tmpdirs.mjs --strict   exit 1 when there is a finding
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { SCOPE } from './lint-wallclock.mjs';

const root = join(dirname(new URL(import.meta.url).pathname), '..');

const CLEANUP_WINDOW = 600;
const MAKE = /\bmkdtemp(Sync)?\s*\(/g;
const KEYWORD = /\b(afterAll|afterEach|after|finally|onTestFinished|teardown|cleanup)\b|\bt\.after\b|process\.on\(\s*['"]exit['"]/g;
const REMOVE = /\b(rmSync|rmdirSync|rm|rmdir|rimraf)\s*\(/;

/** Line numbers (1-based) of the temp directories a text creates. */
export function makes(text) {
  const out = [];
  for (const m of text.matchAll(MAKE)) out.push(text.slice(0, m.index).split('\n').length);
  return out;
}

/** The text removes something inside a cleanup context. */
export function cleansUp(text) {
  for (const k of text.matchAll(KEYWORD)) if (REMOVE.test(text.slice(k.index, k.index + CLEANUP_WINDOW))) return true;
  return false;
}

/** The finding of one file: the lines that create a temp dir when the file has no cleanup, else none. */
export function finding(text) {
  const lines = makes(text);
  return lines.length > 0 && !cleansUp(text) ? lines : [];
}

/** The tracked test files. */
export function trackedTests() {
  const out = execFileSync('git', ['ls-files', '-z'], { cwd: root, encoding: 'utf8', maxBuffer: 1 << 26 });
  return out.split('\0').filter((f) => SCOPE.some((r) => r.test(f)));
}

/** Findings over `files`: `[{ file, lines }]`. */
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
