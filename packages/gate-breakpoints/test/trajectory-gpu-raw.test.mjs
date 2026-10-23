import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { rawLines, trimRaw } from '../src/trajectory/cells-gpu-cli.mjs';

const dir = fileURLToPath(new URL('../../contracts/fixtures/trajectory-gpu/', import.meta.url));
const names = readdirSync(dir).filter((f) => /^raw-\d+\.json$/.test(f)).sort();
const load = (n) => JSON.parse(readFileSync(dir + n, 'utf8'));
const lines = (n) => rawLines(n.replace(/^raw-|\.json$/g, ''), load(n));
const cand = (raw) => raw.runs.filter((u) => u.role === 'cand');

test('the fixture holds the A/A runs with distinct hold shapes (39823047557, 39852684450, 39861846900), trimmed to what cellsOfRaw reads', () => {
  assert.deepEqual(names, ['raw-39823047557.json', 'raw-39852684450.json', 'raw-39861846900.json']);
  for (const n of names) {
    const raw = load(n);
    assert.deepEqual(trimRaw(raw), raw, `${n} is the output of trimRaw`);
    assert.equal(raw.engine, 'chromium');
    assert.equal(raw.hash, raw.baseHash, 'an A/A artifact');
    assert.deepEqual(raw.runs.map((u) => `${u.width}${u.role}`), ['390base', '390cand', '640base', '640cand']);
    for (const u of raw.runs) assert.deepEqual(Object.keys(u).sort(), ['carousel', 'morph', 'pain', 'role', 'width']);
  }
});

test('trimRaw refuses a number the Lean reader would round differently', () => {
  const raw = structuredClone(load(names[0]));
  raw.runs[0].carousel[0].v[0] += 0.5;
  assert.throws(() => trimRaw(raw), /non-integer/);
});

test('one unit per phase per width: six units per width and run, all graded', () => {
  for (const n of names) {
    const ls = lines(n);
    assert.equal(ls.length, 12, n);
    for (const w of [390, 640]) {
      const ours = ls.filter((l) => l.split(' ')[1] === String(w)).map((l) => l.split(' ').slice(2, 4).join(' '));
      assert.deepEqual(ours, ['nav-clip open', 'panel-effect open', 'nav-clip close', 'panel-effect close', 'pain-dark scroll', 'carousel swap']);
    }
    for (const l of ls) assert.match(l, /^\d+ \d+ \S+ \S+ [EQL] /, `${n}: a graded unit ${l}`);
  }
});

test('the shapes the hand-written goldens lacked are in the fixture', () => {
  const holds = (n) => lines(n).filter((l) => l.includes(' carousel ')).map((l) => l.match(/holds=(\S+)/)[1]);
  assert.deepEqual(holds('raw-39823047557.json'), ['2,2,0/2,2,0', '2,2,0/2,2,0'], 'three swaps, the recording opens mid-swap');
  assert.deepEqual(holds('raw-39852684450.json'), ['2,2,0,0/1,1,0,0', '2,2,0,0/1,1,0,0'], 'a hold one frame shorter in the candidate arm');
  assert.deepEqual(holds('raw-39861846900.json'), ['2,2,0,0/2,2,0,0', '1,1,0,0/2,2,0,0'], 'the longer hold on the other arm at 640');
  for (const n of names) for (const l of lines(n)) if (l.includes(' E ') && l.includes(' carousel ')) assert.match(l, /swaps=(\d),\1 /);
});

const graded = (raw, cell, part, width) => rawLines('m', raw).find((l) => l.startsWith(`m ${width} ${cell} ${part} `)).split(' ')[4];

test('a mutated copy of a real raw leaves E, so the equal grade lists are not all-E by construction', () => {
  const base = load('raw-39852684450.json');
  const mut = (f) => { const r = structuredClone(base); for (const u of cand(r)) f(u); return r; };
  const noBlur = mut((u) => { for (const ph of ['open', 'close']) for (const r of u.morph.phases[ph]) r.nodes.panel[0][1] = [0]; });
  assert.equal(graded(noBlur, 'panel-effect', 'close', 640), 'L');
  const stale = mut((u) => { for (const ph of ['open', 'close']) { const rows = u.morph.phases[ph]; for (let i = rows.length - 1; i > 0; i--) if (rows[i].rep === rows[i - 1].rep) rows[i].nodes.panel = rows[i - 1].nodes.panel; } });
  assert.equal(graded(stale, 'panel-effect', 'open', 390), 'Q');
  const moved = mut((u) => { for (const r of u.morph.phases.open) r.nodes.nav[0][0][0] += 700; });
  assert.equal(graded(moved, 'nav-clip', 'open', 640), 'L');
  const flipped = mut((u) => { for (const r of u.pain.up) r.cls = !r.cls; });
  assert.equal(graded(flipped, 'pain-dark', 'scroll', 390), 'L');
  const cut = mut((u) => { u.carousel.length = 120; });
  assert.equal(graded(cut, 'carousel', 'swap', 390), 'L');
});
