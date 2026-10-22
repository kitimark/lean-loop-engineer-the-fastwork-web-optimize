import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { decodeRat } from '../../engine/golden.testutil';

type Row = Record<string, number | number[] | string | boolean>;
const rows = readFileSync(new URL('../../../../../packages/contracts/golden/parts/morph-const-bounds.jsonl', import.meta.url), 'utf8')
  .split('\n')
  .filter((l) => l.trim() !== '')
  .map((l) => decodeRat(JSON.parse(l)) as Row);
const read = (name: string) => readFileSync(new URL(name, import.meta.url), 'utf8');
const panelCss = read('./morph.module.css');
const navCss = read('../nav/nav.module.css');

function decls(css: string, sel: string, from = 0): Map<string, string> {
  const at = css.indexOf(`${sel} {`, from);
  if (at < 0) throw new Error(`no rule ${sel}`);
  const body = css.slice(css.indexOf('{', at) + 1, css.indexOf('\n  }', at));
  const out = new Map<string, string>();
  for (const m of body.matchAll(/(--[\w-]+|[a-z-]+):\s*([^;]*?);/gs)) out.set(m[1]!, m[2]!.replace(/\s+/g, ' ').trim());
  return out;
}

const navBase = decls(navCss, '.nav');
const navPhone = decls(navCss, '.nav', navCss.indexOf('@media (width<=640px)'));
const MORPHING = ':global(.is-morphing) .cb';
const cb = decls(panelCss, MORPHING);
const backdrop = decls(panelCss, `${MORPHING} > .backdrop`);
const veil = decls(panelCss, `${MORPHING} > .veil`);
const center = decls(panelCss, `${MORPHING} > .center`);
const footer = decls(panelCss, `${MORPHING} > .footer`);

/** Evaluate a restated CSS length (calc, min, var, vw, vh, px, %) to px; `pct` is what 100% means. */
function px(expr: string, env: Map<string, string>, vw: number, vh: number, pct: number): number {
  let e = expr;
  for (let i = 0; i < 20 && /var\(/.test(e); i++) {
    e = e.replace(/var\((--[\w-]+)(?:,\s*([^()]+))?\)/g, (_, name: string, fb?: string) => `(${env.get(name) ?? fb ?? 'NaN'})`);
  }
  e = e
    .replace(/100vw/g, String(vw))
    .replace(/100vh/g, String(vh))
    .replace(/(\d+(?:\.\d+)?)px/g, '$1')
    .replace(/100%/g, String(pct))
    .replace(/calc\(/g, '(')
    .replace(/min\(/g, 'Math.min(');
  return new Function(`return (${e});`)() as number;
}

function envOf(vw: number, m: number): Map<string, string> {
  const env = new Map(navBase);
  if (vw <= 640) for (const [k, v] of navPhone) env.set(k, v);
  env.set('--morphing-test', '1');
  env.set('--morph', String(m));
  env.set('--nav-expand', '1');
  for (const [k, v] of cb) if (k.startsWith('--')) env.set(k, v);
  return env;
}

describe('morph.panel const-bounds: the CSS restates the Lean rows', () => {
  const boxes = rows.filter((r) => r.kind === 'box');
  const paints = rows.filter((r) => r.kind === 'paint');
  it('has the rows', () => {
    expect(boxes.length).toBe(81);
    expect(paints.length).toBe(81);
  });
  it('applies only while the nav carries is-morphing (m > 1/1000)', () => {
    for (const r of boxes) expect(r.morphing, String(r.m)).toBe((r.m as number) > 0.001);
    expect(panelCss).toContain(':global(.is-morphing) .cb {');
    expect(panelCss).not.toMatch(/^\s*\.cb\s*\{/m);
  });
  it('lays the panel and every child out as the Lean boxes', () => {
    for (const r of boxes.filter((q) => q.morphing === true)) {
      const [vw, vh, m] = [r.vw as number, r.vh as number, r.m as number];
      const env = envOf(vw, m);
      const at = (e: string, pct = 0) => px(e, env, vw, vh, pct);
      expect(at('var(--cb-w)')).toBeCloseTo(r.navW as number, 9);
      expect(at('var(--cb-h)')).toBeCloseTo(r.navH as number, 9);
      expect(at(cb.get('width')!)).toBeCloseTo(r.newW as number, 9);
      expect(at(cb.get('height')!)).toBeCloseTo(r.newH as number, 9);
      expect(at(cb.get('left')!)).toBeCloseTo(r.orgX as number, 9);
      expect(at(cb.get('top')!)).toBeCloseTo(r.orgY as number, 9);
      expect(at('var(--cb-x)')).toBeCloseTo(r.offX as number, 9);
      expect(at('var(--cb-y)')).toBeCloseTo(r.offY as number, 9);
      expect(at(backdrop.get('left')!)).toBeCloseTo(r.bdLeft as number, 9);
      expect(at(backdrop.get('width')!)).toBeCloseTo(r.bdW as number, 9);
      expect(at(backdrop.get('top')!)).toBeCloseTo(r.offY as number, 9);
      expect(at(backdrop.get('height')!)).toBeCloseTo(r.navH as number, 9);
      expect(at(veil.get('left')!)).toBeCloseTo(r.offX as number, 9);
      expect(at(veil.get('width')!)).toBeCloseTo(r.navW as number, 9);
      expect(at(veil.get('top')!)).toBeCloseTo(r.offY as number, 9);
      expect(at(veil.get('height')!)).toBeCloseTo(r.navH as number, 9);
      expect(at(center.get('width')!)).toBeCloseTo(r.navW as number, 9);
      expect(at(footer.get('left')!)).toBeCloseTo(r.offX as number, 9);
      expect(at(footer.get('right')!)).toBeCloseTo(r.offX as number, 9);
      expect(at(footer.get('bottom')!)).toBeCloseTo(r.offY as number, 9);
      expect((r.newW as number) - at(footer.get('left')!) - at(footer.get('right')!)).toBeCloseTo(r.navW as number, 9);
      expect(r.varW).toBe(r.newW);
      expect(r.varH).toBe(r.newH);
    }
    for (const r of boxes.filter((q) => q.morphing === false)) {
      expect(r.varW).toBe(r.navW);
      expect(r.varH).toBe(r.navH);
    }
  });
  it('paints every sampled point where the original does, from the CSS offsets', () => {
    for (const r of paints.filter((q) => (q.m as number) > 0.001)) {
      const [vw, vh, m, s] = [r.vw as number, r.vh as number, r.m as number, r.scale as number];
      const env = envOf(vw, m);
      const at = (e: string) => px(e, env, vw, vh, 0);
      const navW = at('var(--cb-w)');
      const panelW = at(cb.get('width')!);
      const org = at(cb.get('left')!);
      const off = at('var(--cb-x)');
      const orig = r.orig as number[];
      [0, navW / 2, navW].forEach((p, i) => {
        const painted = org + s * (off + p - panelW / 2) + panelW / 2;
        expect(painted).toBeCloseTo(orig[i]!, 9);
        expect(painted).toBeCloseTo((r.new as number[])[i]!, 9);
      });
    }
  });
});
