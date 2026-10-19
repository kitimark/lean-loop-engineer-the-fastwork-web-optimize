import { describe, expect, it } from 'vitest';
import contracts from '../../../../packages/contracts/golden/parts/contracts.gen.json';
import { parts } from '../registry';
import { parseOnly } from '../registry/only';
import { pinEnv, type EnvTarget } from './fixedEnv';
import { hostOf, hostsOf } from './hosts';
import { planStage } from './plan';
import { applyInputs, declaredInputs, type ContractRow } from './inputs';

const rows = contracts.parts as ContractRow[];

describe('fixed env', () => {
  it('pins y/vw/vh and restores', () => {
    const win = { scrollY: 5, innerWidth: 1000, innerHeight: 700 } as EnvTarget;
    const p = pinEnv(win, { y: 300, vw: 390, vh: 844 });
    expect([win.scrollY, win.innerWidth, win.innerHeight]).toEqual([300, 390, 844]);
    expect(p.mismatch).toBe(true);
    p.restore();
    expect([win.scrollY, win.innerWidth, win.innerHeight]).toEqual([5, 1000, 700]);
  });
  it('reports a matching viewport', () => {
    expect(pinEnv({ scrollY: 0, innerWidth: 390, innerHeight: 844 }, { y: 0, vw: 390, vh: 844 }).mismatch).toBe(false);
  });
});

describe('declared inputs', () => {
  it('sets only inputs whose owner is not mounted', () => {
    const w = (ms: string[]) => declaredInputs(ms, rows).writes.map((x) => `${x.kind}:${x.name}/${x.owner}`);
    expect(w(['hero.orbit'])).toContain('cssVar:--exit-opacity/hero.exit');
    expect(w(['hero.orbit', 'hero.exit'])).not.toContain('cssVar:--exit-opacity/hero.exit');
  });
  it('lists unset inputs instead of inventing a value', () => {
    expect(declaredInputs(['hero.orbit'], rows).unset).toContain('className:data-splash/hero.exit');
  });
  it('reports inputs owned by page-level parts or the scene as unset', () => {
    expect(declaredInputs(['nav'], rows).unset).toContain('morphPhase');
    expect(declaredInputs(['platform.sweep'], rows).unset).toContain('scenePaused');
  });
  it('asks a neighbour stub for rect inputs of unmounted owners', () => {
    expect(declaredInputs(['nav', 'nav.hitTest'], rows).neighbours).toEqual(['hero.exit', 'people.deck']);
  });
  it('applies writes through a finder and counts missing owners', () => {
    const calls: string[] = [];
    const el = { style: { setProperty: (n: string, v: string) => calls.push(`${n}=${v}`) }, setAttribute() {}, classList: { remove() {} } } as unknown as HTMLElement;
    const missing = applyInputs(
      [
        { kind: 'cssVar', owner: 'a', name: '--x', value: '1' },
        { kind: 'cssVar', owner: 'b', name: '--y', value: '2' },
      ],
      (o) => (o === 'a' ? el : null),
    );
    expect(calls).toEqual(['--x=1']);
    expect(missing).toEqual(['cssVar:--y/b=2']);
  });
});

describe('hosts', () => {
  it('every stageable part has a host', () => {
    for (const r of contracts.parts) if (!r.pageLevel) expect(hostOf(r.id), r.id).not.toBeNull();
  });
  it('page-level parts have none', () => {
    for (const r of contracts.parts) if (r.pageLevel) expect(hostOf(r.id), r.id).toBeNull();
  });
  it('every contract part is a registered part', () => {
    const ids = new Set(parts.map((p) => p.id));
    for (const r of contracts.parts) if (r.id !== 'people') expect(ids.has(r.id), r.id).toBe(true); // people: composed section, no part.json
  });
  it('a group stage mounts several hosts, never a page-level part', () => {
    const r = parseOnly('?only=g2');
    expect(r.kind).toBe('ok');
    if (r.kind === 'ok') {
      expect(r.stage.members).not.toContain('morph.tween');
      expect(hostsOf(r.stage.members).length).toBeGreaterThan(1);
    }
  });
  it('page-level targets are refused', () => {
    for (const r of contracts.parts) if (r.pageLevel) expect(parseOnly(`?only=${r.id}`)).toEqual({ kind: 'err', code: 'pageLevel' });
  });
});

describe('plan', () => {
  it('a sub-part stage mounts its whole host and says so', () => {
    const p = planStage({ members: ['hero.accent'], env: { y: 0, vw: 1280, vh: 800 } });
    expect(p.mounted).toContain('hero.exit');
    expect(p.hosts).toEqual(['hero']);
    expect(p.scrollEngine).toBe('faithful');
  });
  it('never mounts a page-level part', () => {
    for (const r of contracts.parts) if (r.pageLevel) for (const g of ['g1', 'g2', 'g3', 'g4', 'g5']) {
      const o = parseOnly(`?only=${g}`);
      if (o.kind === 'ok') expect(planStage(o.stage).mounted).not.toContain(r.id);
    }
  });
});
