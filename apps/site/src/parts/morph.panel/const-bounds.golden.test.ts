import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { decodeRat } from '../../engine/golden.testutil';

type Row = Record<string, number | number[] | string>;
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
const frame = decls(panelCss, '.frame');
const cb = decls(panelCss, '.cb');

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
  env.set('--morph', String(m));
  env.set('--nav-expand', '1');
  for (const [k, v] of frame) env.set(k, v);
  return env;
}

describe('morph.panel const-bounds: the CSS restates the Lean rows', () => {
  const boxes = rows.filter((r) => r.kind === 'box');
  const paints = rows.filter((r) => r.kind === 'paint');
  it('has the rows', () => {
    expect(boxes.length).toBe(72);
    expect(paints.length).toBe(72);
  });
  it('declares the panel box and the frame from the nav variables', () => {
    expect(cb.get('width')).toBe('var(--panel-w, 100%)');
    expect(cb.get('height')).toBe('var(--panel-h, 100%)');
    expect(frame.get('width')).toBe('var(--cb-w)');
    expect(frame.get('height')).toBe('var(--cb-h)');
  });
  it('lays the panel, the frame and the offsets out as the Lean boxes', () => {
    for (const r of boxes) {
      const [vw, vh, m] = [r.vw as number, r.vh as number, r.m as number];
      const env = envOf(vw, m);
      const navW = px('var(--cb-w)', env, vw, vh, 0);
      const navH = px('var(--cb-h)', env, vw, vh, 0);
      expect(navW).toBeCloseTo(r.navW as number, 9);
      expect(navH).toBeCloseTo(r.navH as number, 9);
      const panelW = px(cb.get('width')!, env, vw, vh, navW);
      const panelH = px(cb.get('height')!, env, vw, vh, navH);
      expect(panelW).toBeCloseTo(r.newW as number, 9);
      expect(panelH).toBeCloseTo(r.newH as number, 9);
      expect(px(cb.get('left')!, env, vw, vh, navW)).toBeCloseTo(r.orgX as number, 9);
      expect(px(cb.get('top')!, env, vw, vh, navH)).toBeCloseTo(r.orgY as number, 9);
      expect(px(frame.get('left')!, env, vw, vh, panelW)).toBeCloseTo(r.offX as number, 9);
      expect(px(frame.get('top')!, env, vw, vh, panelH)).toBeCloseTo(r.offY as number, 9);
    }
  });
  it('paints every sampled point where the original does, from the CSS offsets', () => {
    for (const r of paints) {
      const [vw, vh, m, s] = [r.vw as number, r.vh as number, r.m as number, r.scale as number];
      const env = envOf(vw, m);
      const navW = px('var(--cb-w)', env, vw, vh, 0);
      const panelW = px(cb.get('width')!, env, vw, vh, navW);
      const org = px(cb.get('left')!, env, vw, vh, navW);
      const off = px(frame.get('left')!, env, vw, vh, panelW);
      const orig = r.orig as number[];
      [0, navW / 2, navW].forEach((p, i) => {
        const painted = org + s * (off + p - panelW / 2) + panelW / 2;
        expect(painted).toBeCloseTo(orig[i]!, 9);
        expect(painted).toBeCloseTo((r.new as number[])[i]!, 9);
      });
    }
  });
});
