// node src/cli.mjs run    --engine chromium|playwright-webkit --out DIR [--probes id,id,...] [--parts a,b,...] [--concurrency 2]
// node src/cli.mjs fonts  --engine chromium|playwright-webkit --out DIR [--probes id,id,...] [--concurrency 2]   (port check 5; exit 1 on a failing probe)
// node src/cli.mjs fonts-compare --in A.fonts.json,B.fonts.json   (the counts of runs of one head side by side)
// node src/cli.mjs report --in DIR[,DIR...] [--out BASE]    (prints the markdown table; BASE.md and BASE.json when --out)
// node src/cli.mjs nav-scroll --engine chromium|playwright-webkit --out DIR [--widths w860,w861,w1280,w1440,w1920]   (nav scroll-hide probe)
// node src/cli.mjs nav-scroll-report --in DIR[,DIR...] [--out BASE | --summary]   (--summary prints only the cross-run tables)
// node src/cli.mjs people-layout --engine chromium|playwright-webkit --out DIR [--widths w1920,w1440,w1280,w861,w401] [--reps 2]   (people-section layout probe)
// node src/cli.mjs people-layout-report --in DIR[,DIR...] [--out BASE]   (arm-against-arm tables of the probe records)
// Default probes: the breakpoint set in probes.default.json (ids of the gate's Lean matrix, apps/site/src/breakpoints.gen.json).
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const cmd = argv[0];
const arg = (n, d) => { const i = argv.indexOf(`--${n}`); return i < 0 ? d : argv[i + 1]; };

if (cmd === 'run') {
  const { runVisual } = await import('./run.mjs');
  const defaults = JSON.parse(readFileSync(join(HERE, '..', 'probes.default.json'), 'utf8')).probes;
  const probeIds = arg('probes', defaults.join(',')).split(',').map((x) => x.trim()).filter(Boolean);
  const partFilter = argv.includes('--parts') ? arg('parts', '').split(',').map((x) => x.trim()).filter(Boolean) : null;
  await runVisual({ engineName: arg('engine', 'chromium'), outDir: resolve(arg('out', 'out/run')), probeIds, partFilter, fw: arg('fw', process.env.FW_FLAGS ?? ''), concurrency: Number(arg('concurrency', '2')), assets: arg('assets', 'none') });
  process.exit(0);
} else if (cmd === 'nav-scroll') {
  const { runNavScroll, WIDTHS } = await import('./navscroll.mjs');
  const widthIds = arg('widths', WIDTHS.map((w) => w.id).join(',')).split(',').map((x) => x.trim()).filter(Boolean);
  await runNavScroll({ engineName: arg('engine', 'chromium'), outDir: resolve(arg('out', 'out/navscroll')), widthIds });
  process.exit(0);
} else if (cmd === 'nav-scroll-report') {
  const { report, summaryReport } = await import('./navscroll-report.mjs');
  const dirs = arg('in', 'out/navscroll').split(',').map((d) => resolve(d));
  process.stdout.write(argv.includes('--summary') ? summaryReport(dirs) : report(dirs, arg('out') ? resolve(arg('out')) : null));
} else if (cmd === 'people-layout') {
  const { runPeopleLayout, WIDTHS } = await import('./people-layout.mjs');
  const widthIds = arg('widths', WIDTHS.map((w) => w.id).join(',')).split(',').map((x) => x.trim()).filter(Boolean);
  await runPeopleLayout({ engineName: arg('engine', 'chromium'), outDir: resolve(arg('out', 'out/people-layout')), widthIds, reps: Number(arg('reps', '2')) });
  process.exit(0);
} else if (cmd === 'people-layout-report') {
  const { report } = await import('./people-layout-analyze.mjs');
  const dirs = arg('in', 'out/people-layout').split(',').map((d) => resolve(d));
  process.stdout.write(report(dirs, arg('out') ? resolve(arg('out')) : null));
} else if (cmd === 'fonts') {
  const { runFonts, fontsTable } = await import('./fonts.mjs');
  const defaults = JSON.parse(readFileSync(join(HERE, '..', 'probes.default.json'), 'utf8')).probes;
  const probeIds = arg('probes', defaults.join(',')).split(',').map((x) => x.trim()).filter(Boolean);
  const engineName = arg('engine', 'chromium');
  const { results } = await runFonts({ engineName, outDir: resolve(arg('out', 'out/fonts')), probeIds, concurrency: Number(arg('concurrency', '2')) });
  process.stdout.write(fontsTable(engineName, results));
  process.exit(results.every((r) => r.pass) ? 0 : 1);
} else if (cmd === 'fonts-compare') {
  const { fontsCompare } = await import('./fonts.mjs');
  process.stdout.write(fontsCompare(arg('in', '').split(',').filter(Boolean).map((f) => resolve(f))));
} else if (cmd === 'report') {
  const { report } = await import('./report.mjs');
  const dirs = arg('in', 'out/run').split(',').map((d) => resolve(d));
  process.stdout.write(report(dirs, arg('out') ? resolve(arg('out')) : null));
} else {
  console.error('usage: cli.mjs run|report|nav-scroll|nav-scroll-report ...');
  process.exit(2);
}
