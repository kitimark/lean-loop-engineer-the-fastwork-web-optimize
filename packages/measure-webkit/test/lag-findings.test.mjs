// Every number of the note's Findings is the value of an anchored cell of the generated block (identity, not inference).
// An anchor line is `value | table | row | arm | column`; the table is a `### ` heading prefix, plus ` / <first header cell>` for a
// pipe table; a bullet line (`- <arm>: ...`) of a section is addressed by the heading alone, the row being the item label.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { blockOf } from '../src/lag/note.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const NOTE = readFileSync(join(here, '../../../research/notes/2026/10-21-webkit-lag-probe.md'), 'utf8');
const ARMS = ['original', 'faithful'];
const NUM = /\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?/g;

/** Numbers of a text with the thousands separators removed. */
export const numbers = (text) => (text.match(NUM) ?? []).map((x) => x.replaceAll(',', ''));

/** Tokens a Finding states without a block cell: INFERRED sums of two block values and quotes of round 1. One entry per token. */
export const ALLOWED = [
  { finding: 3, token: '43', why: 'INFERRED: the people (12) and pain (31) shares of the rewrite added' },
  { finding: 6, token: '91', why: 'INFERRED: the nav (65) and morph panel (26) shares of the rewrite added' },
  { finding: 6, token: '0.8', why: 'round-1 quote: "the rewrite paints less (about 0.8x)", which this block does not show' },
];

/** The `### ` sections of the block: `{ heading, lines }`. */
export function sections(block) {
  return block.split(/^### /m).slice(1).map((s) => { const [heading, ...lines] = s.split('\n'); return { heading, lines }; });
}

/** The pipe tables of a section: `{ head: [cells], rows: [[cells]] }`. */
function tablesOf(lines) {
  const out = [];
  let cur = null;
  for (const l of lines) {
    if (l.startsWith('|')) {
      const cells = l.trim().slice(1, -1).split('|').map((c) => c.trim());
      if (!cur) { cur = { head: cells, rows: [] }; out.push(cur); } else if (!cells.every((c) => /^-+$/.test(c))) cur.rows.push(cells);
    } else cur = null;
  }
  return out;
}

const section = (block, prefix) => {
  const hit = sections(block).filter((s) => s.heading.startsWith(prefix));
  assert.equal(hit.length, 1, `section ${prefix}: ${hit.length} matches`);
  return hit[0];
};

/** The text of the cell an anchor names, or throws. */
export function cellOf(block, { table, row, arm, column }) {
  const [heading, first] = table.split(' / ');
  const sec = section(block, heading);
  if (first === undefined) {
    const line = sec.lines.find((l) => l.startsWith(`- ${arm}:`));
    assert.ok(line, `${table}: no bullet for ${arm}`);
    const at = line.indexOf(row);
    assert.ok(at >= 0, `${table}: no item ${row} for ${arm}`);
    return line.slice(at + row.length).split(/, |; /)[0];
  }
  const tab = tablesOf(sec.lines).find((t) => t.head[0] === first);
  assert.ok(tab, `${table}: no table`);
  const rows = tab.rows.filter((r) => r[0] === row);
  const mine = rows.length > 1 ? rows.filter((r) => (r[2] ?? '').startsWith(`${arm} `)) : rows;
  assert.equal(mine.length, 1, `${table} / ${row} / ${arm}: ${mine.length} rows`);
  const head = tab.head;
  const where = (f) => head.map((h, i) => [h, i]).filter(([h]) => f(h)).map(([, i]) => i);
  let idx = where((h) => h === column);
  let part = null;
  if (idx.length === 0) { idx = where((h) => h.startsWith(`${column} `) && h.endsWith(ARMS.join(' / '))); if (idx.length) part = ARMS.indexOf(arm); }
  if (idx.length === 0) idx = where((h) => h.includes(column) && h.includes(arm) && !h.includes(' / '));
  if (idx.length === 0 && first === 'state') idx = where((h) => h.startsWith(column));
  if (idx.length === 0 && column === 'cell') idx = where((h) => h === arm);
  assert.equal(idx.length, 1, `${table} / ${column} / ${arm}: ${idx.length} columns in ${head.join(' | ')}`);
  const text = mine[0][idx[0]];
  return part === null ? text : text.split(' / ')[part];
}

/** The Findings: `{ n, text, anchors }` per numbered item, and the text before the first item. */
export function findings(note) {
  const body = note.slice(note.indexOf('\n## Findings'));
  const end = body.indexOf('\n## ', 5);
  const sec = body.slice(0, end < 0 ? undefined : end);
  const parts = sec.split(/^(?=\d+\. )/m);
  const intro = parts.shift();
  const items = parts.map((p) => {
    const n = Number(p.match(/^(\d+)\. /)[1]);
    const a = p.match(/<!-- anchors\n([\s\S]*?)-->/);
    const anchors = (a ? a[1].trim().split('\n') : []).filter(Boolean).map((l) => {
      const [value, table, row, arm, column] = l.split(' | ').map((x) => x.trim());
      return { value, table, row, arm, column };
    });
    const text = p.replace(/<!-- anchors[\s\S]*?-->/, '').replace(/^\d+\. /, '').replace(/`[^`]*`/g, '').replace(/px\^2/g, '');
    return { n, text, anchors };
  });
  return { intro, items };
}

const block = blockOf(NOTE);
const F = findings(NOTE);
const isNum = (v) => /^[\d,]+(\.\d+)?$/.test(v);

test('the note has the generated block and nine Findings, the intro states no number', () => {
  assert.ok(block && block.length > 5000);
  assert.deepEqual(F.items.map((x) => x.n), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
  assert.deepEqual(numbers(F.intro.replace(/## Findings/, '')), []);
});

test('every anchor names a cell of the block that holds its value', () => {
  let checked = 0;
  for (const f of F.items) {
    for (const a of f.anchors) {
      const arms = a.arm === 'both' ? ARMS : [a.arm];
      for (const arm of arms) {
        const cell = cellOf(block, { ...a, arm });
        if (isNum(a.value)) assert.ok(numbers(cell).includes(a.value.replaceAll(',', '')), `Finding ${f.n}: ${a.value} is not in [${cell}] (${a.table} / ${a.row} / ${arm} / ${a.column})`);
        else assert.ok(cell.includes(a.value), `Finding ${f.n}: "${a.value}" is not in [${cell}] (${a.table} / ${a.row} / ${arm} / ${a.column})`);
        checked++;
      }
    }
  }
  assert.ok(checked > 60, `${checked} anchored cells`);
});

test('every number of a Finding is anchored once, or listed as an INFERRED sum or a round-1 quote', () => {
  for (const f of F.items) {
    const prose = numbers(f.text).sort();
    const anchored = f.anchors.filter((a) => isNum(a.value)).map((a) => a.value.replaceAll(',', ''));
    const allowed = ALLOWED.filter((x) => x.finding === f.n).map((x) => x.token);
    assert.deepEqual(prose, [...anchored, ...allowed].sort(), `Finding ${f.n}`);
  }
});

test('the allowlist holds only tokens that are not block cells', () => {
  for (const x of ALLOWED) {
    const f = F.items.find((i) => i.n === x.finding);
    assert.ok(f && numbers(f.text).includes(x.token), `Finding ${x.finding} no longer states ${x.token}`);
    assert.ok(x.why.length > 20);
  }
});
