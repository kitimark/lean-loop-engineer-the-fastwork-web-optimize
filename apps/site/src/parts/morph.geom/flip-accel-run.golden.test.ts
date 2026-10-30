import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { buildAnims, cssValue, keyframes, type Layout } from './tracks';

type Line = { fn: string; in: Record<string, unknown>; out: unknown };
const read = (rel: string) => readFileSync(resolve(__dirname, rel), 'utf8');
const lines = read('../../../../../packages/contracts/golden/parts/flip-accel-run.jsonl')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Line);
const css = read('./geom.css');

function sample(w: number): Layout {
  const ph = w <= 640;
  const cols = ph ? 3 : 5;
  return {
    eng: 'webkit',
    a: 0,
    b: 1,
    inset: ph ? 16 : 24,
    logoW: ph ? 120 : 160,
    lw: ph ? 120 : 144,
    w0: ph ? 152 : 176,
    gL: 0,
    imgs: Array.from({ length: cols }, () => [[0, 200], [200, 200], [400, 200]]),
  };
}

const ANIMATED = new Set(['opacity', 'filter', 'backdrop-filter', 'transform', 'translate', 'scale']);

function importantDecls(): string[] {
  const out = new Set<string>();
  for (const m of css.replace(/\/\*[\s\S]*?\*\//g, '').matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    const sels = m[1].split(',').map((s) => s.trim());
    for (const d of m[2].split(';')) {
      const [prop, val] = d.split(':').map((x) => x?.trim());
      if (!prop || !val?.endsWith('!important')) continue;
      const p = prop.replace(/^-webkit-/, '');
      if (!ANIMATED.has(p)) continue;
      for (const s of sels) {
        const el = /data-mg='(\w+)'/.exec(s)?.[1] ?? (/data-fw='nav'/.test(s) ? 'nav' : null);
        if (el) out.add(`${el}|${p}`);
      }
    }
  }
  return [...out].sort();
}

describe('morph.geom played keyframes against the Lean flip-accel-run golden (the two canBeAccelerated conditions)', () => {
  it('the !important declarations on animatable properties are the Lean list', () => {
    const lean = lines.filter((l) => l.fn === 'decl').map((l) => `${l.in.el}|${l.in.css}`).sort();
    expect(importantDecls()).toEqual(lean);
  });

  it('no track targets a cascade-overridden pair', () => {
    const lean = new Set(lines.filter((l) => l.fn === 'overridden' && l.out === true).map((l) => `${l.in.el}|${l.in.css}`));
    const rows = lines.filter((l) => l.fn === 'tracks');
    expect(rows.length).toBe(12);
    for (const r of rows) {
      const i = r.in as { w: number; h: number };
      const out = r.out as { n: number; cascade: number };
      const as = buildAnims({ w: i.w, h: i.h }, sample(i.w));
      const hit = as.filter((a) => lean.has(`${a.el}|${a.prop}`));
      expect(as.length, `${i.w}x${i.h}`).toBe(out.n);
      expect(hit.length, `${i.w}x${i.h}`).toBe(out.cascade);
    }
  });

  it('played values hold the golden function list: translate and scale in a transform, no matrix', () => {
    const arity = { translate: 2, scale: 2, transform: 4, opacity: 1, filter: 1, 'backdrop-filter': 1 } as const;
    for (const p of lines.filter((l) => l.fn === 'played')) {
      const prop = p.in.prop as keyof typeof arity;
      const text = cssValue(prop, Array.from({ length: arity[prop] }, (_, k) => k + 1));
      const fns = [...text.matchAll(/([a-z0-9]+)\(/g)].map((m) => m[1]).filter((f) => f !== 'blur');
      const out = p.out as { fns: string[]; discrete: boolean };
      expect(fns, prop).toEqual(out.fns);
      expect(/matrix/.test(text), prop).toBe(out.discrete);
    }
    for (const r of lines.filter((l) => l.fn === 'tracks')) {
      const i = r.in as { w: number; h: number };
      for (const a of buildAnims({ w: i.w, h: i.h }, sample(i.w))) {
        for (const k of keyframes(a)) expect(/matrix/.test(String(k[a.prop])), `${a.el} ${a.prop}`).toBe(false);
      }
    }
  });
});
