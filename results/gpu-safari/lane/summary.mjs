// Prints one line per arm and state from the committed results/gpu-safari/<arm>.json files: the table of the note. Reads only; decides nothing.
//   node results/gpu-safari/lane/summary.mjs [dir]
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = resolve(process.argv[2] ?? join(dirname(fileURLToPath(import.meta.url)), '..'));
const mb = (b) => (b == null ? '-' : Math.round(b / 1e6));
const gpu = (s) => (s?.gpu && !s.gpu.error ? `${s.gpu.regions}/${mb(s.gpu.virtualBytes)}` : '-');
const rows = [];
for (const f of readdirSync(dir).filter((n) => n.endsWith('.json') && !n.startsWith('mac-') && n !== 'people-o-preview-translate.json').sort()) {
  const j = JSON.parse(readFileSync(join(dir, f), 'utf8'));
  if (!Array.isArray(j.states)) continue;
  for (const s of j.states) {
    const own = s.own;
    rows.push([
      j.arm, s.id, `grade ${s.grade}`,
      `in ${s.counts.inside.changed}/${s.counts.inside.maxDelta}`, `out ${s.counts.out.changed}`,
      `ring ${s.counts.ring.edge.changed} int ${s.counts.ring.interior.changed}`,
      `aa ${s.counts.control.raw.changed}`,
      `later loads ${s.loads.laterNearest ?? s.loads.nearest} vs floor ${s.loads.floor ?? s.loads.spread} ${s.loads.within ? 'within' : 'ABOVE'}`,
      own ? `own ${own.inside.changed} aa ${own.control.changed} ring ${own.ring.edge.changed}` : '',
      s.glass ? `glass d ${JSON.stringify(s.glass.armDelta?.median)} aa ${JSON.stringify(s.glass.controlDelta?.median)}` : '',
      s.pushSeen ? `effects ${s.pushSeen.faithful?.anims.length ?? '-'}/${s.pushSeen.arm?.anims.length ?? '-'}/${s.pushSeen.control?.anims.length ?? '-'}` : '',
      `layers ${s.census.faithful.layerCount}/${s.census.arm.layerCount}/${s.census.control.layerCount}/${s.census.order?.layerCount ?? '-'}`,
      `mem ${mb(s.census.faithful.memoryBytes)}/${mb(s.census.arm.memoryBytes)}/${mb(s.census.control.memoryBytes)}/${mb(s.census.order?.memoryBytes)}`,
      `iosurf gpu ${gpu(s.iosurface.faithful)} ${gpu(s.iosurface.arm)} ${gpu(s.iosurface.control)} ${gpu(s.iosurface.order)}`,
    ]);
  }
}
for (const r of rows) console.log(r.filter(Boolean).join(' | '));
