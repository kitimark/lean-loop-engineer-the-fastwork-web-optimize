#!/usr/bin/env node
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { FOREIGN_REASON, probesHit } from './pathpix-exit.mjs';

export function slimCell(c) {
  return {
    key: c.key, i: c.i, y: c.y, kind: c.kind, grade: c.grade, why: c.why, ifAccepted: c.ifAccepted, absGrade: c.absGrade, live: c.live, accentPinned: c.accentPinned, invalidWhy: c.invalidWhy,
    inside: c.cell.inside, out: c.cell.out, floor: c.floor, p1: c.cell.p1, compA: c.cell.claim.compA, compB: c.cell.claim.compB, strip: c.strip ?? null, where: c.where ?? null, shared: c.shared ?? null, sharedWith: c.sharedWith ?? 0, sharedTo: c.sharedTo ?? null, consensus: c.consensus ?? null,
  };
}

export function slimLane(label, artifact, cells, man) {
  return {
    schema: 'fw.path-pix.exit.cells/1', label, probes: (man.samples?.A ?? []).find(Boolean)?.probes ?? null,
    probesAt: (man.samples?.A ?? []).filter(Boolean).map((r) => ({ i: r.i, y: r.y, scrollY: r.scrollY, probes: r.probes ?? null })), artifact, run: cells.run, engine: cells.engine, lane: cells.lane, flag: cells.flag, compositing: cells.compositing,
    ua: man.ua ?? null, browser: man.browser ?? null, vw: cells.vw, dpr: cells.dpr, exit: cells.exit, offsets: cells.offsets, maxY: cells.maxY ?? null, clock: cells.clock ?? null, handover: man.handover ?? null, fonts: man.fonts ?? null,
    cut: cells.cut, armsRun: cells.armsRun, driverMoved: cells.driverMoved ?? null, liveness: cells.liveness.map((l) => ({ arm: l.arm, i: l.i, y: l.y, accepted: l.accepted, accentPinned: l.accentPinned, live: l.live })),
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

const HERO = 'hero_copy';
const raw = (x) => `${x.changed}-${x.maxDelta}`;

export const lSource = (p) => (p.grade !== 'L' ? null : p.ifAccepted !== 'L' ? 'strips not accepted' : p.out.changed > 0 ? 'outside the mask' : 'inside, above the floor');

const cellAt = (l, key, i, kind) => l.cells.find((c) => c.key === key && c.i === i && c.kind === kind);
const skipAt = (l, key, i, kind) => l.skipped.find((x) => (x.key === key || x.key === undefined) && x.i === i && (x.kind === kind || x.kind === 'all'))?.why ?? null;

export function heroCopyTable(engine, lanes, key = HERO) {
  const offsets = lanes[0]?.offsets ?? [];
  const out = [`#### ${engine}: ${key} per job and offset`, '', `| offset | ask y | ${lanes.map((l) => `${l.label} A/A in/out | ${l.label} P in/out | ${l.label} P grade (source) [if strips accepted]`).join(' | ')} |`, `|---|---|${lanes.map(() => '---|---|---').join('|')}|`];
  offsets.forEach((y, i) => {
    const cols = lanes.flatMap((l) => {
      const f = cellAt(l, key, i, 'A/A'), p = cellAt(l, key, i, 'P');
      const sk = (kind) => skipAt(l, key, i, kind);
      const aa = f ? `${raw(f.inside)}/${raw(f.out)}${f.grade === 'invalid' ? ` (invalid: ${f.invalidWhy})` : ''}` : `skipped: ${sk('A/A') ?? 'no cell'}`;
      if (!p) return [aa, `skipped: ${sk('P') ?? 'no cell'}`, '-'];
      const src = lSource(p);
      return [aa, `${raw(p.inside)}/${raw(p.out)}`, `${p.grade}${p.grade === 'invalid' ? ` (${p.invalidWhy ?? 'not live'})` : src ? ` (${src})` : ''} [${p.ifAccepted}]`];
    });
    out.push(`| ${i} | ${y} | ${cols.join(' | ')} |`);
  });
  return out.join('\n');
}

export function heroCopySummary(engine, lanes, key = HERO) {
  const ps = lanes.flatMap((l) => l.cells.filter((c) => c.key === key && c.kind === 'P'));
  const fs = lanes.flatMap((l) => l.cells.filter((c) => c.key === key && c.kind === 'A/A'));
  const g = (x) => count(ps, (c) => c.grade === x), src = (x) => count(ps, (c) => lSource(c) === x);
  const skips = lanes.flatMap((l) => l.skipped.filter((x) => x.key === key));
  const reasons = [...new Set(skips.map((x) => x.why))].map((w) => `${w} x${count(skips, (x) => x.why === w)}`);
  return [`#### ${engine}: ${key} summary over ${lanes.length} jobs`, '',
    '| P cells | E | E1 | Q | L | invalid | L: strips not accepted | L: inside, above the floor | L: outside the mask | A/A cells | A/A with a change inside | A/A with a change outside | skipped (reason) |', '|---|---|---|---|---|---|---|---|---|---|---|---|---|',
    `| ${ps.length} | ${g('E')} | ${g('E1')} | ${g('Q')} | ${g('L')} | ${g('invalid')} | ${src('strips not accepted')} | ${src('inside, above the floor')} | ${src('outside the mask')} | ${fs.length} | ${count(fs, (c) => c.inside.changed > 0)} | ${count(fs, (c) => c.out.changed > 0)} | ${reasons.join('; ') || 'none'} |`].join('\n');
}

const receiverText = (l, c, key) => {
  const r = cellAt(l, key, c.i, c.kind);
  if (!r) return `${key}: no cell`;
  const src = r.kind === 'P' ? lSource(r) : null;
  return `${key}: ${r.grade}${src ? ` (${src})` : ''}, inside ${raw(r.inside)}`;
};

export function heroCopyShared(lanes, key = HERO) {
  const out = [`Reason: ${FOREIGN_REASON}`, '', '| job | offset | kind | changed pixels left to other layers (chg-max) | receiving cells in the same job, offset and kind: grade (source), inside chg-max | changes outside every mask: box (device px) | probe elements the outside box touches |', '|---|---|---|---|---|---|---|'];
  for (const l of lanes) for (const c of l.cells) {
    if (c.key !== key || !c.shared || (c.shared.changed === 0 && !(c.where && c.where.outBbox))) continue;
    const rec = c.shared.changed === 0 ? '-' : c.sharedTo ? c.sharedTo.map((k) => receiverText(l, c, k)).join('; ') : 'not recorded';
    const pr = c.where?.outProbes ? (c.where.outProbes.length ? c.where.outProbes.map(([n, a, b, d, e]) => `${n} ${a},${b},${d},${e}`).join('; ') : 'none') : '-';
    out.push(`| ${l.label} | ${c.i} | ${c.kind} | ${raw(c.shared)} | ${rec} | ${c.where?.outBbox ? `${raw(c.out)} at ${c.where.outBbox.join(',')}` : '-'} | ${pr} |`);
  }
  return out.join('\n');
}

export const probeOffsets = (l) => {
  const hit = [...new Set(l.cells.filter((c) => c.out.changed > 0).map((c) => c.i))].sort((a, b) => a - b);
  return hit.length ? hit : (l.probesAt ?? []).slice(0, 1).map((r) => r.i);
};

export function probeTable(lanes) {
  const out = ['| job | offset | ask y | scrollY | probe element | device box x0,y0,x1,y1 (arm A at that offset) |', '|---|---|---|---|---|---|'];
  for (const l of lanes) {
    const rows = probeOffsets(l).map((i) => (l.probesAt ?? []).find((r) => r.i === i)).filter(Boolean);
    if (!rows.length) out.push(`| ${l.label} | - | - | - | not recorded | - |`);
    for (const r of rows) {
      const hits = r.probes ? probesHit(r.probes, [-1e9, -1e9, 1e9, 1e9], l.dpr) : [];
      if (!hits.length) out.push(`| ${l.label} | ${r.i} | ${r.y} | ${r.scrollY} | none recorded | - |`);
      for (const [n, a, b, c, d] of hits) out.push(`| ${l.label} | ${r.i} | ${r.y} | ${r.scrollY} | ${n} | ${a},${b},${c},${d} |`);
    }
  }
  return out.join('\n');
}

const VERDICTS = ['E', 'E1', 'Q', 'L', 'invalid', 'varied'];

export function consensusSummary(engine, lanes) {
  const out = [`#### ${engine}: consensus of the identical arms, P cells per job`, '', `| job | A3 captured | P cells | counted | varied | quiet | ${VERDICTS.join(' | ')} | no consensus data |`, `|---|---|---|---|---|---|${VERDICTS.map(() => '---').join('|')}|---|`];
  for (const l of lanes) {
    const ps = l.cells.filter((c) => c.kind === 'P'), cs = ps.filter((c) => c.consensus);
    const seen = (x) => count(cs, (c) => c.consensus.seen === x), v = (x) => count(cs, (c) => c.consensus.verdict === x);
    out.push(`| ${l.label} | ${l.armsRun?.includes('A3') ? 'yes' : 'no'} | ${ps.length} | ${seen('counted')} | ${seen('varied')} | ${seen('quiet')} | ${VERDICTS.map(v).join(' | ')} | ${ps.length - cs.length} |`);
  }
  return out.join('\n');
}

export function consensusCells(lanes) {
  const out = ['| job | consumer | offset | ask y | P grade | verdict | P inside / out (chg-max) | A vs A2 inside / out | A vs A3 inside / out | inside | outside |', '|---|---|---|---|---|---|---|---|---|---|---|'];
  const pair = (x) => (x ? `${raw(x.inside)} / ${raw(x.out)}` : 'not captured');
  for (const l of lanes) for (const c of l.cells) {
    if (c.kind !== 'P' || !c.consensus || c.consensus.seen === 'quiet') continue;
    out.push(`| ${l.label} | ${c.key} | ${c.i} | ${c.y} | ${c.grade} | ${c.consensus.verdict} | ${raw(c.inside)} / ${raw(c.out)} | ${pair(c.consensus.a2)} | ${pair(c.consensus.a3)} | ${c.consensus.inside} | ${c.consensus.out} |`);
  }
  return out.join('\n');
}

const partList = (parts) => {
  const n = new Map();
  for (const p of parts) n.set(p, (n.get(p) ?? 0) + 1);
  return [...n].map(([p, k]) => (k > 1 ? `${p} x${k}` : p)).join(', ') || 'none named';
};

export function heroCopyWhere(lanes, key = HERO) {
  const out = ['| job | offset | kind | inside chg-max | box (device px) | parts the box touches |', '|---|---|---|---|---|---|'];
  for (const l of lanes) for (const c of l.cells) if (c.key === key && c.inside.changed > 0 && c.where) out.push(`| ${l.label} | ${c.i} | ${c.kind} | ${raw(c.inside)} | ${c.where.bbox ? c.where.bbox.join(',') : '-'} | ${partList(c.where.parts)} |`);
  return out.join('\n');
}

export function pinTable(lanes) {
  const out = ['| job | run | Date.now in every row | cells | accent-unpinned | misplaced | occluded skips |', '|---|---|---|---|---|---|---|'];
  for (const l of lanes) {
    const cs = l.cells;
    out.push(`| ${l.label} | ${l.run} | ${l.clock ? (l.clock.constant ? `constant (${l.clock.values.join(',')})` : `moves (${l.clock.values.join(',')})`) : 'not recorded'} | ${cs.length} | ${count(cs, (c) => c.invalidWhy === 'accent-unpinned')} | ${count(cs, (c) => c.invalidWhy === 'misplaced')} | ${count(l.skipped, (x) => /^occluded/.test(x.why))} |`);
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
  const hero = engines.flatMap((e) => { const ls = lanes.filter((l) => l.engine === e); return [consensusSummary(e, ls), '', heroCopySummary(e, ls), '', heroCopyTable(e, ls), '', `#### ${e}: ${HERO} changes inside the mask`, '', heroCopyWhere(ls), '', `#### ${e}: ${HERO} pixels counted by another layer`, '', heroCopyShared(ls), '']; });
  const md = [...engines.map((e) => engineTable(e, lanes.filter((l) => l.engine === e))), '', ...hero, '#### Consensus: every P cell with a change against arm A', '', consensusCells(lanes), '', '#### Page clock, accent pin and row placement per job', '', pinTable(lanes), '', ...(lanes.some((l) => l.probesAt?.length) ? ['#### Probe elements outside the graded layers, at the offsets with a change outside every mask', '', probeTable(lanes.filter((l) => l.probesAt?.length)), ''] : []), '#### L cells with a strip', '', lookList(lanes)].join('\n');
  console.log(md);
}
