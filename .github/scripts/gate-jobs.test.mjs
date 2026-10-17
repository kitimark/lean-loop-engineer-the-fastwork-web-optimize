// node --test .github/scripts/gate-jobs.test.mjs   (run from the repo root)
// Checks the glue of the gate speed-up against the Lean golden: the job matrix (gate-jobs.mjs), the cache keys
// (cache-key.mjs) and the merge of jobs that carry both probes and sweeps (merge-gate.mjs).
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..', '..');
const sched = readFileSync(join(root, 'packages/contracts/golden/gate/schedule.jsonl'), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
const cacheG = readFileSync(join(root, 'packages/contracts/golden/ops/cache.jsonl'), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
const node = (script, args) => spawnSync(process.execPath, [join(root, '.github/scripts', script), ...args], { cwd: root, encoding: 'utf8' });

test('golden schedule: every line is a valid, bounded and never-worse split', () => {
  assert.equal(sched.length, 36);
  for (const g of sched) {
    for (const side of [g.chosen, g.current]) {
      const durs = side.jobs.map((j) => j.ms);
      assert.equal(side.sum, durs.reduce((a, b) => a + b, 0), g.name);
      assert.equal(side.max, Math.max(...durs), g.name);
      assert.equal(side.bound, g.r * side.sum + (g.m - 1) * side.max, `${g.name}: Graham numerator`);
      assert.ok(g.m * side.makespan <= side.bound, `${g.name}: m*makespan <= bound`);
      assert.equal(side.wallOk, true, `${g.name}: wall between its lower and upper bound`);
      assert.equal(side.wall, g.fixed.pre + side.makespan + g.fixed.post, `${g.name}: wall = pre + makespan + post`);
      for (const eng of ['chromium', 'playwright-webkit']) {
        const js = side.jobs.filter((j) => j.engine === eng);
        assert.equal(js.reduce((a, j) => a + j.probes, 0), 124, `${g.name} ${eng}: 124 probes`);
        assert.deepEqual(js.flatMap((j) => j.sweeps).sort(), ['desktop', 'pain', 'phone', 'touch'], `${g.name} ${eng}: each sweep once`);
        const t = g.times[eng];
        for (const j of js) {
          const want = t.setup + j.probes * t.perProbe + j.sweeps.reduce((a, s) => a + t.sweeps[s], 0);
          assert.equal(j.ms, want, `${g.name} ${eng} slot ${j.slot}: duration`);
        }
      }
    }
    assert.ok(g.chosen.bound <= g.current.bound, `${g.name}: chosen no worse than current`);
    assert.equal(g.neverWorse, true);
  }
});

test('gate-jobs: every golden line gives a matrix that covers all probes and sweeps once', () => {
  for (const g of sched) {
    const r = node('gate-jobs.mjs', ['--params', g.params, '--runs', String(g.r), '--free', String(g.m)]);
    assert.equal(r.status, 0, `${g.name}: ${r.stderr}`);
    const out = JSON.parse(r.stdout);
    assert.equal(out.include.length, g.chosen.jobCount, g.name);
    for (const eng of ['chromium', 'playwright-webkit']) {
      const mine = out.include.filter((j) => j.engine === eng);
      assert.equal(mine.flatMap((j) => (j.probes === 'none' ? [] : j.probes.split(','))).length, 124);
      assert.equal(mine.flatMap((j) => (j.sweeps === 'none' ? [] : j.sweeps.split(','))).length, 4);
    }
  }
});

test('gate-jobs: --engines narrows, --parts narrows to the Lean scope and drops empty jobs, unknown input fails', () => {
  const one = node('gate-jobs.mjs', ['--engines', 'chromium']);
  assert.equal(one.status, 0, one.stderr);
  assert.ok(JSON.parse(one.stdout).include.every((j) => j.engine === 'chromium'));
  const parts = ['engine.scroll', 'nav.hitTest', 'hero.countdown', 'hero.exit'];
  for (const p of parts) {
    const r = node('gate-jobs.mjs', ['--parts', p]);
    assert.equal(r.status, 0, `${p}: ${r.stderr}`);
    const out = JSON.parse(r.stdout);
    assert.ok(out.include.length >= 2 && out.include.length <= 14, `${p}: ${out.include.length} jobs`);
  }
  assert.equal(node('gate-jobs.mjs', ['--parts', 'no.such']).status, 2);
  assert.equal(node('gate-jobs.mjs', ['--runs', '4']).status, 2);
  assert.equal(node('gate-jobs.mjs', ['--free', '7']).status, 2);
  assert.equal(node('gate-jobs.mjs', ['--params', 'nope']).status, 2);
});

test('cache golden: a declared change changes the key, an undeclared one does not, and cache-key.mjs agrees', () => {
  const caches = [...new Set(cacheG.filter((c) => c.role === 'base').map((c) => c.cache))];
  assert.deepEqual(caches.sort(), ['apt-debs', 'browsers', 'hs-zip']);
  for (const name of caches) {
    const lines = cacheG.filter((c) => c.cache === name && c.role !== 'trace');
    const base = lines.find((c) => c.role === 'base');
    const args = (env, decl) => decl.flatMap((n) => ['--set', `${n}=${env[n]}`]);
    const keyOf = (l) => {
      const r = node('cache-key.mjs', ['--cache', name, ...args(l.env, base.decl)]);
      assert.equal(r.status, 0, r.stderr);
      return r.stdout.trim();
    };
    const canonOf = (l) => node('cache-key.mjs', ['--cache', name, '--canonical', ...args(l.env, base.decl)]).stdout.replace(/\n$/, '');
    for (const l of lines) assert.equal(canonOf(l), l.canonical, `${l.name}: canonical string equals Lean's`);
    const baseKey = keyOf(base);
    assert.match(baseKey, new RegExp(`^${base.prefix}-[0-9a-f]{40}$`));
    for (const l of lines.filter((x) => x.role === 'declaredChange')) assert.notEqual(keyOf(l), baseKey, l.name);
    for (const l of lines.filter((x) => x.role === 'undeclaredChange')) assert.equal(keyOf(l), baseKey, l.name);
    // a key that misses a declared input, or carries an undeclared one, is refused
    assert.equal(node('cache-key.mjs', ['--cache', name, ...args(base.env, base.decl.slice(1))]).status, 1);
    assert.equal(node('cache-key.mjs', ['--cache', name, ...args(base.env, base.decl), '--set', 'runId=1']).status, 1);
  }
  assert.equal(node('cache-key.mjs', ['--cache', 'nope']).status, 2);
});

test('cache golden: the replayed trace hits only on a world seen before, with the fresh result', () => {
  const tr = cacheG.filter((c) => c.role === 'trace');
  assert.deepEqual(tr.map((t) => t.hit), [false, true, false, false, true]);
  for (const t of tr) assert.equal(t.result, t.fresh, t.name);
});

// merge-gate: jobs that carry probes and sweeps together.
const specMod = await import(pathToFileURL(join(root, 'packages/gate-breakpoints/src/spec.mjs')).href);
const { gen } = specMod.loadGen();
const ids = gen.matrix.probes.map((p) => p.id);
const sweepIds = specMod.sweepDefs(gen).map((s) => s.id);
const header = { schema: 'fw.gate-breakpoints.run/1', browser: 'x', gen: { probes: ids.length }, props: [] };
const run = (probes, sweeps) => ({ header, probes: probes.map((id) => ({ id })), sweeps: sweeps.map((id) => ({ id })) });
function merge(files, extra = []) {
  const dir = mkdtempSync(join(tmpdir(), 'gate-merge-'));
  try {
    const paths = files.map((f, i) => { const p = join(dir, `f${i}.json`); writeFileSync(p, JSON.stringify(f)); return p; });
    const out = join(dir, 'out.json');
    const r = spawnSync(process.execPath, [join(root, '.github/scripts/merge-gate.mjs'), '--out', out, ...extra, ...paths], { cwd: root, encoding: 'utf8' });
    return { r, merged: r.status === 0 ? JSON.parse(readFileSync(out, 'utf8')) : null };
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

test('merge-gate: probes and sweeps from any job, written in gen and spec order', () => {
  const half = Math.floor(ids.length / 2);
  const a = run(ids.slice(half).reverse(), [sweepIds[3], sweepIds[0]]);
  const b = run(ids.slice(0, half), [sweepIds[2], sweepIds[1]]);
  const { r, merged } = merge([a, b]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(merged.probes.map((p) => p.id), ids);
  assert.deepEqual(merged.sweeps.map((s) => s.id), sweepIds);
});

test('merge-gate: a missing, duplicated or foreign probe or sweep fails', () => {
  const half = Math.floor(ids.length / 2);
  const ok = (sw1, sw2, p1 = ids.slice(half), p2 = ids.slice(0, half)) => merge([run(p1, sw1), run(p2, sw2)]);
  assert.equal(ok([sweepIds[0], sweepIds[1]], [sweepIds[2], sweepIds[3]]).r.status, 0);
  assert.equal(ok([sweepIds[0]], [sweepIds[2], sweepIds[3]]).r.status, 1, 'a sweep missing');
  assert.equal(ok([sweepIds[0], sweepIds[1]], [sweepIds[1], sweepIds[2], sweepIds[3]]).r.status, 1, 'a sweep twice');
  assert.equal(ok([sweepIds[0], sweepIds[1], 'nope'], [sweepIds[2], sweepIds[3]]).r.status, 1, 'a foreign sweep');
  assert.equal(ok([sweepIds[0], sweepIds[1]], [sweepIds[2], sweepIds[3]], ids.slice(half), ids.slice(1, half)).r.status, 1, 'a probe missing');
  assert.equal(ok([sweepIds[0], sweepIds[1]], [sweepIds[2], sweepIds[3]], ids.slice(half - 1), ids.slice(0, half)).r.status, 1, 'a probe twice');
  const odd = merge([{ ...run(ids, sweepIds), header: { ...header, browser: 'y' } }, run([], [])]);
  assert.equal(odd.r.status, 1, 'headers differ');
});
