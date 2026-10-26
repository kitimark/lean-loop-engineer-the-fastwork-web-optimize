import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { TOUCH_TAIL, profileTail, readArm, summarizeArm, markdown, PROFILE_ID } from './offscreen-windows.mjs';

const here = dirname(fileURLToPath(import.meta.url));

function args(argv) {
  const out = { flags: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--base') out.base = argv[++i];
    else if (a === '--flag') {
      const v = argv[++i] ?? '';
      const eq = v.indexOf('=');
      if (eq < 1) throw new Error(`--flag wants name=dir, got "${v}"`);
      out.flags.push([v.slice(0, eq), v.slice(eq + 1)]);
    } else if (a === '--json') out.json = argv[++i];
    else if (a === '--md') out.md = argv[++i];
    else throw new Error(`unknown argument ${a}`);
  }
  if (!out.base || out.flags.length === 0) throw new Error('usage: offscreen-windows-cli.mjs --base <dir> --flag <name>=<dir> [--flag ...] [--json f] [--md f]');
  return out;
}

try {
  const a = args(process.argv.slice(2));
  const tail = profileTail(JSON.parse(readFileSync(join(here, '..', 'profiles', `${PROFILE_ID}.json`), 'utf8')));
  if (tail !== TOUCH_TAIL) throw new Error(`profile tail ${tail} differs from the Lean constant ${TOUCH_TAIL}`);
  const base = readArm(a.base, tail);
  const arms = {}, runs = { base: base.map((r) => ({ path: r.path, end: r.end, windows: r.windows })) };
  for (const [name, dir] of a.flags) {
    const flag = readArm(dir, tail);
    arms[name] = summarizeArm(base, flag);
    runs[name] = flag.map((r) => ({ path: r.path, search: r.search, end: r.end, windows: r.windows }));
  }
  const { base: _b, ...flagRuns } = runs;
  const md = markdown(arms, base, flagRuns);
  if (a.json) writeFileSync(a.json, JSON.stringify({ arms, runs }, null, 1) + '\n');
  if (a.md) writeFileSync(a.md, md);
  process.stdout.write(md);
} catch (e) {
  console.error(`offscreen-windows: ${e.message}`);
  process.exit(2);
}
