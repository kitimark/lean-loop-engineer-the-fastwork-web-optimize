import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { ARMS, METRICS, contrast, crLabelOf, pushLabel } from './cols-verdict.mjs';

export const sumKey = (counts, key) => (counts.frames ?? []).reduce((s, f) => s + (f.counts?.[key] ?? 0), 0);

export function jobOf(counts) {
  return Object.fromEntries(METRICS.chromium.map((m) => [m.name, sumKey(counts, m.key)]));
}

export function takeStats(log = []) {
  const pushes = [];
  for (const e of log) {
    if (e.kind === 'push') pushes.push({ onDark: e.dark === true, took: false });
    else if (e.kind === 'take' && pushes.length) pushes[pushes.length - 1].took = true;
  }
  return { pushes: pushes.length, took: pushes.filter((p) => p.took).length, dark: pushes.filter((p) => p.onDark).length, labels: pushes.map((p) => pushLabel({ flipArm: true, ...p })) };
}

export function reduceDir(dir) {
  const jobs = {}; const logs = {}; const files = [];
  for (const a of ARMS) {
    const label = crLabelOf(a);
    jobs[a.id] = []; logs[a.id] = { took: 0, pushes: 0, dark: 0, jobs: [] };
    for (const d of readdirSync(dir).filter((n) => n.startsWith(`chromium-counts-${label}-`)).sort()) {
      const f = join(dir, d, 'counts.json');
      if (!existsSync(f)) continue;
      const counts = JSON.parse(readFileSync(f, 'utf8'));
      files.push(`${d}/counts.json`);
      jobs[a.id].push(jobOf(counts));
      const t = takeStats(counts.takeLog);
      logs[a.id].took += t.took; logs[a.id].pushes += t.pushes; logs[a.id].dark += t.dark; logs[a.id].jobs.push({ job: d, pushes: t.pushes, took: t.took, dark: t.dark });
    }
  }
  const contrasts = { base: contrast('chromium', jobs, 'base+off', logs), flip: contrast('chromium', jobs, 'timed-fixed+off', logs) };
  return { engine: 'chromium', files, jobs, logs, contrasts };
}

export function toMd(r) {
  const out = [`Chromium counts, ${r.files.length} jobs`, ''];
  for (const [name, c] of Object.entries(r.contrasts)) {
    out.push(`${name}: ${c.ref} vs ${c.off}: ${c.reading}${c.valid ? '' : ' (flip invalid)'}`);
    for (const m of c.cells) out.push(`  ${m.metric}: ref [${m.ref.join(', ')}] off [${m.off.join(', ')}] -> ${m.cell}`);
  }
  for (const [id, l] of Object.entries(r.logs)) if (l.pushes) out.push(`flip log ${id}: ${l.took}/${l.pushes} pushes took, ${l.dark} on dark at push`);
  return out.join('\n');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const dir = process.argv[2];
  if (!dir) { console.error('usage: cols-reduce.mjs <dir> [--out file.json]'); process.exit(2); }
  const r = reduceDir(dir);
  const oi = process.argv.indexOf('--out');
  if (oi > 0) writeFileSync(process.argv[oi + 1], JSON.stringify(r, null, 1) + '\n');
  console.log(toMd(r));
}
