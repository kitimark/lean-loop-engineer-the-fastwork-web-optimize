#!/usr/bin/env node
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';

export function slimCell(c) {
  return {
    key: c.key, i: c.i, y: c.y, kind: c.kind, grade: c.grade, why: c.why, ifAccepted: c.ifAccepted, absGrade: c.absGrade, live: c.live,
    inside: c.cell.inside, out: c.cell.out, floor: c.floor, p1: c.cell.p1, compA: c.cell.claim.compA, compB: c.cell.claim.compB, strip: c.strip ?? null,
  };
}

export function slimLane(label, artifact, cells, man) {
  return {
    schema: 'fw.path-pix.exit.cells/1', label, artifact, run: cells.run, engine: cells.engine, lane: cells.lane, flag: cells.flag, compositing: cells.compositing,
    ua: man.ua ?? null, browser: man.browser ?? null, vw: cells.vw, dpr: cells.dpr, exit: cells.exit, offsets: cells.offsets, handover: man.handover ?? null, fonts: man.fonts ?? null,
    cut: cells.cut, armsRun: cells.armsRun, driverMoved: cells.driverMoved ?? null, liveness: cells.liveness.map((l) => ({ arm: l.arm, i: l.i, y: l.y, accepted: l.accepted, live: l.live })),
    skipped: cells.skipped, frames: cells.frames.map((f) => ({ arm: f.arm, i: f.i, sameA: f.sameA, sameB: f.sameB, changed: f.changed, maxDelta: f.maxDelta })),
    cells: cells.cells.map(slimCell),
  };
}

const count = (cs, f) => cs.filter(f).length;

export function engineTable(engine, lanes) {
  const out = [`#### ${engine}`, '', '| replicate | run | kind | cells | E | E1 | Q | L | invalid | L text | L outside | L inside | if strips accepted: E/E1/Q/L/invalid |', '|---|---|---|---|---|---|---|---|---|---|---|---|---|'];
  for (const l of lanes) for (const k of ['A/A', 'P']) {
    const cs = l.cells.filter((c) => c.kind === k);
    const g = (x) => count(cs, (c) => c.grade === x), a = (x) => count(cs, (c) => c.ifAccepted === x), w = (x) => count(cs, (c) => c.why === x);
    out.push(`| ${l.label} | ${l.run} | ${k} | ${cs.length} | ${g('E')} | ${g('E1')} | ${g('Q')} | ${g('L')} | ${g('invalid')} | ${w('text')} | ${w('outside')} | ${w('inside')} | ${a('E')}/${a('E1')}/${a('Q')}/${a('L')}/${a('invalid')} |`);
  }
  const keys = [...new Set(lanes.flatMap((l) => l.cells.map((c) => `${c.key}\u0000${c.i}`)))].map((s) => s.split('\u0000')).sort((x, y) => (x[0] < y[0] ? -1 : x[0] > y[0] ? 1 : x[1] - y[1]));
  out.push('', `| consumer | offset | y | ${lanes.map((l) => `${l.label} P grade (why) [if accepted] in/out chg-max; A/A in/out`).join(' | ')} |`, `|---|---|---|${lanes.map(() => '---').join('|')}|`);
  for (const [key, i] of keys) {
    const cols = lanes.map((l) => {
      const p = l.cells.find((c) => c.key === key && c.i === Number(i) && c.kind === 'P'), f = l.cells.find((c) => c.key === key && c.i === Number(i) && c.kind === 'A/A');
      if (!p) return '-';
      const r = (x) => `${x.changed}-${x.maxDelta}`;
      return `${p.grade}${p.why ? ` (${p.why})` : ''} [${p.ifAccepted}] ${r(p.inside)}/${r(p.out)}; A/A ${f ? `${r(f.inside)}/${r(f.out)}` : '-'}`;
    });
    const y = lanes.map((l) => l.cells.find((c) => c.key === key && c.i === Number(i))?.y).find((v) => v !== undefined);
    out.push(`| ${key} | ${i} | ${y} | ${cols.join(' | ')} |`);
  }
  return out.join('\n');
}

export function lookList(lanes) {
  const out = ['| replicate | artifact | strip | consumer | offset | why |', '|---|---|---|---|---|---|'];
  for (const l of lanes) for (const c of l.cells) if (c.kind === 'P' && c.grade === 'L' && c.strip) out.push(`| ${l.label} | ${l.artifact} | ${c.strip} | ${c.key} | ${c.i} | ${c.why} |`);
  return out.join('\n');
}

if (process.argv[1] && import.meta.url === new URL(`file://${resolve(process.argv[1])}`).href) {
  const args = process.argv.slice(2);
  const o = args.indexOf('--out');
  const outDir = o >= 0 ? resolve(args[o + 1]) : null;
  const specs = args.filter((a, i) => !a.startsWith('--') && args[i - 1] !== '--out');
  if (!outDir || !specs.length) { console.error('usage: node src/pathpix-exit-report.mjs --out <dir> <label>:<artifact>=<laneDir> ...'); process.exit(2); }
  mkdirSync(outDir, { recursive: true });
  const lanes = specs.map((s) => {
    const [head, dir] = s.split('=');
    const [label, artifact] = head.split(':');
    const cells = JSON.parse(readFileSync(join(dir, 'cells.json'), 'utf8')), man = JSON.parse(readFileSync(join(dir, 'manifest.json'), 'utf8'));
    const lane = slimLane(label, artifact ?? label, cells, man);
    writeFileSync(join(outDir, `${label}.json`), JSON.stringify(lane) + '\n');
    return lane;
  });
  const engines = [...new Set(lanes.map((l) => l.engine))];
  const md = [...engines.map((e) => engineTable(e, lanes.filter((l) => l.engine === e))), '', '#### L cells with a strip', '', lookList(lanes)].join('\n');
  console.log(md);
}
