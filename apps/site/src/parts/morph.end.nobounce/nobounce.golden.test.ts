import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { cfgOf, hooksOf, type EndCfg } from '../morph.tween/end.hooks';
import { initEnd, step, type EndEv } from '../morph.tween/end.logic';
import { REST } from '../morph.tween/logic';
import { resolveSearch } from '../../registry';
import { NOBOUNCE_ATTR, NOBOUNCE_CSS, NOBOUNCE_ID, NOBOUNCE_ON, nobounceProps } from './index';

type Num = number | { num: string; den: string };
interface GoldEv {
  ev: string;
  y?: Num | null;
  delta?: Num;
  maxY?: Num;
  scrollY?: Num;
  arm?: boolean;
  now?: Num;
  reduced?: boolean;
}
interface Row {
  fn: string;
  in: { case?: string; bounce?: boolean; cfg?: EndCfg; init?: Num; events?: GoldEv[] };
  out: unknown;
}

const rows: Row[] = readFileSync(new URL('../../../../../packages/contracts/golden/parts/morph-end-nobounce.jsonl', import.meta.url), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Row);
const num = (n: Num): number => (typeof n === 'number' ? n : Number(n.num) / Number(n.den));
const opt = (n: Num | null | undefined): number | null => (n === null || n === undefined ? null : num(n));

function toEv(e: GoldEv): EndEv {
  const read = { scrollY: num(e.scrollY ?? 0), arm: e.arm ?? false, now: num(e.now ?? 0), reduced: e.reduced ?? false };
  switch (e.ev) {
    case 'touchstart':
      return { ev: 'touchstart', y: opt(e.y) };
    case 'touchmove':
      return { ev: 'touchmove', y: opt(e.y), ...read };
    case 'wheel':
      return { ev: 'wheel', delta: num(e.delta ?? 0), ...read };
    case 'scroll':
    case 'resize':
      return { ev: e.ev, y: num(e.y ?? 0), maxY: num(e.maxY ?? 0) };
    default:
      return { ev: 'tick', now: num(e.now ?? 0) };
  }
}

const cases = rows.filter((r) => r.fn === 'morph.end.nobounce');

function writes(row: Row): (number | null)[] {
  const h = hooksOf(row.in.cfg as EndCfg);
  let s = initEnd(num(row.in.init ?? 0), REST);
  return (row.in.events ?? []).map((ge) => {
    const [next, out] = step(h, s, toEv(ge));
    s = next;
    return out.write;
  });
}

describe('morph.end.nobounce golden', () => {
  it('constants match the part', () => {
    const c = rows.find((r) => r.fn === 'morph.end.nobounce.const')?.out as { id: string; css: string; attr: string; on: string };
    expect(c).toMatchObject({ id: NOBOUNCE_ID, css: NOBOUNCE_CSS, attr: NOBOUNCE_ATTR, on: NOBOUNCE_ON });
  });
  it('has the 3 cases under all 8 picks', () => {
    expect(cases).toHaveLength(24);
  });
  for (const row of cases) {
    const cfg = row.in.cfg as EndCfg;
    it(`${row.in.case} clamp=${cfg.clamp} flip=${cfg.flip} release=${cfg.release}: writes equal the golden`, () => {
      const want = (row.out as { write: Num | null }[]).map((o) => opt(o.write));
      expect(writes(row)).toEqual(want);
    });
    if (row.in.bounce === false) {
      it(`${row.in.case} clamp=${cfg.clamp} flip=${cfg.flip} release=${cfg.release}: no write above the end, a push at the end writes nothing`, () => {
        const w = writes(row);
        const maxY = 5227;
        expect(w.every((x) => x === null || x <= maxY)).toBe(true);
        if (row.in.case === 'push-at-end') expect(w.every((x) => x === null)).toBe(true);
      });
    }
  }
  it('with a bounce the page is written back to the pin (the contrast)', () => {
    const row = cases.find((r) => r.in.case === 'bounce-contrast' && !r.in.cfg?.clamp && !r.in.cfg?.release);
    expect(row && writes(row).filter((x) => x !== null)).toEqual([5227]);
  });
});

describe('morph.end.nobounce flag', () => {
  it('?fw= resolves to the part, default is faithful, drivers read no hook from it', () => {
    const on = resolveSearch(`?fw=${NOBOUNCE_ID}:${NOBOUNCE_ON}`);
    if (!on.ok) throw new Error(on.errors.join('; '));
    expect(on.config.variants[NOBOUNCE_ID]).toBe(NOBOUNCE_ON);
    expect(cfgOf(on.config.variants)).toEqual({ clamp: false, flip: false, release: false });
    const off = resolveSearch('');
    if (!off.ok) throw new Error(off.errors.join('; '));
    expect(off.config.variants[NOBOUNCE_ID]).toBe('faithful');
  });
  it('the page root carries the attribute with the flag on, nothing when off, and reset.css holds the rule', () => {
    expect(nobounceProps('on')).toEqual({ 'data-fw-nobounce': '' });
    expect(nobounceProps('faithful')).toEqual({});
    const css = readFileSync(new URL('../../styles/reset.css', import.meta.url), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/\s+/g, '');
    expect(css).toContain(NOBOUNCE_CSS.replace('none}', 'none;}'));
  });
});
