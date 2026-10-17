// gen.test.mjs: tests of the mutant ids of gen.mjs (task mutant-ids-stable). Run: node --test FwTest/Mutants/gen.test.mjs
// Checks: ids are unique (also for duplicate names and long numerals), survive edits outside their declaration,
// every equivalent.tsv entry names exactly one mutant, and the shards partition the list.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mutants, mutantId, fnv } from './gen.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const LEAN = join(HERE, '..', '..');
const GEN = join(HERE, 'gen.mjs');
// the M0 set and skip list of scripts/mutants.sh
const M0 = 'Fw/Console.lean Fw/Serve.lean Fw/Ops/Meter.lean Fw/Ops/PathCheck.lean Fw/Ops/SpawnGuard.lean Fw/Ops/Usage.lean Fw/Ops/Wire.lean Fw/Spec/DeviceQueue.lean Fw/Wire.lean'.split(' ');
const SKIP = 'boardCases,boardGolden,sampleRequests';
const src = (f) => readFileSync(join(LEAN, f), 'utf8');
const ids = (s) => mutants(s).map((x) => x.id);

test('ids are unique in every M0 module', () => {
  for (const f of M0) {
    const xs = ids(src(f));
    assert.ok(xs.length > 0, f);
    assert.equal(new Set(xs).size, xs.length, f);
  }
});

test('id format: <decl>#<k>:<op>:<repl>', () => {
  assert.equal(mutantId('samples', 3, 'str', '""'), 'samples#3:str:""');
  assert.equal(mutantId('f', 1, 'list', ''), 'f#1:list:drop');
  assert.equal(mutantId('f', 1, 'ite', '¬(a && b && c)'), 'f#1:ite:x');
  assert.equal(mutantId('f', 2, 'num', '12345678901234'), 'f#2:num:12345678901234');
  for (const f of M0) for (const x of mutants(src(f))) assert.match(x.id, /^[^#\t\n]+#[1-9][0-9]*:[a-z]+:[^\t\n]*$/, `${f} ${x.id}`);
});

test('duplicate names, anonymous instances and long numerals do not collide', () => {
  const s = [
    'namespace A', 'def f (n : Nat) : Bool := n < 3', 'end A',
    'namespace B', 'def f (n : Nat) : Bool := n < 3', 'end B',
    'instance : Inhabited Nat := ⟨1⟩', 'instance : Inhabited Bool := ⟨true⟩',
    'def big : Nat := 12345678901234 + 12345678901234', '',
  ].join('\n');
  const xs = mutants(s);
  const got = xs.map((x) => x.id);
  assert.equal(new Set(got).size, got.length);
  for (const id of ['f@1#1:rel:≤', 'f@2#1:rel:≤', 'f@1#1:num:4', 'f@2#1:num:2', '_@1#1:num:2', '_@2#1:tf:false',
    'big#1:num:12345678901235', 'big#1:num:12345678901233', 'big#2:num:12345678901235', 'big#1:arith:-'])
    assert.ok(got.includes(id), `${id} in ${got.join(' ')}`);
});

test('an edit outside a declaration leaves its ids unchanged', () => {
  for (const f of M0) {
    const s = src(f), before = ids(s);
    // lines and a new def with mutants at the top (after the imports), a new def at the end
    const cut = s.search(/^(namespace|open|set_option|section|\/-)/m);
    assert.ok(cut >= 0, f);
    const extra = 'def zz (n : Nat) : Bool := n + 1 < 2 && true\n';
    const top = s.slice(0, cut) + '\n\n-- moved\ndef zzTop (n : Nat) : Bool := n + 1 < 2 && true\n\n' + s.slice(cut);
    const end = s + '\ndef zzEnd (n : Nat) : Bool := n + 1 < 2 && true\n';
    for (const t of [top, end]) {
      const after = new Set(ids(t));
      for (const id of before) assert.ok(after.has(id), `${f}: ${id} lost`);
      assert.equal(after.size, before.length + ids(extra).length, f);
    }
  }
});

test('lines shifted inside a declaration keep its ids', () => {
  const a = 'def h (n : Nat) : String :=\n  if n < 2 then "a" else "b"\n';
  const b = 'def h (n : Nat) : String :=\n\n  -- note\n  if n < 2 then\n    "a"\n  else "b"\n';
  assert.deepEqual(ids(a), ids(b));
});

test('every equivalent.tsv entry names exactly one current mutant', () => {
  const rows = readFileSync(join(HERE, 'equivalent.tsv'), 'utf8').split('\n').filter((l) => l && !l.startsWith('#'));
  assert.ok(rows.length > 0);
  for (const l of rows) {
    const [f, id, reason] = l.split('\t');
    assert.ok(M0.includes(f), `${f} not an M0 module`);
    assert.ok(reason && reason.length > 10, `${id}: reason`);
    assert.equal(mutants(src(f)).filter((x) => x.id === id).length, 1, `${f}\t${id} is stale`);
  }
});

test('list + shard: the shards partition the list (by FNV-1a of file<TAB>id)', () => {
  const list = execFileSync('node', [GEN, 'list', '--skip', SKIP, '--str-cap', '2', ...M0], { cwd: LEAN, encoding: 'utf8' });
  const lines = list.split('\n').filter(Boolean);
  const keys = lines.map((l) => l.split('\t').slice(0, 2).join('\t'));
  assert.equal(new Set(keys).size, keys.length, 'file+id unique in the list');
  const n = 16, seen = [];
  for (let i = 0; i < n; i++) {
    const out = execFileSync('node', [GEN, 'shard', String(i), String(n)], { input: list, encoding: 'utf8' });
    for (const l of out.split('\n').filter(Boolean)) {
      const [f, id] = l.split('\t');
      assert.equal(fnv(`${f}\t${id}`) % n, i);
      seen.push(l);
    }
  }
  assert.deepEqual([...seen].sort(), [...lines].sort());
});

test('apply finds a mutant by its new id', () => {
  const f = 'Fw/Ops/SpawnGuard.lean', s = src(f);
  const x = mutants(s).find((y) => y.id === 'hasInfix#1:num:2');
  assert.ok(x);
  assert.equal(s.slice(x.start, x.end), '1');
});
