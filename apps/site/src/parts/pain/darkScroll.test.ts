import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { decodeRat } from '../../engine/golden.testutil';
import { mediaCondition } from '../../breakpoints';
import { flipAt, layerOwnsFlip, RANGE_VAR, SUPPORTS, translateY } from './darkScroll';

type Rgb = [number, number, number];
type Row = { kind: 'flip' | 'pixel'; [k: string]: number | string | Rgb };
const rows = readFileSync(resolve(__dirname, '../../../../../packages/contracts/golden/parts/pain-dark-scroll.jsonl'), 'utf8')
  .split('\n')
  .filter((l) => l.trim() !== '')
  .map((l) => decodeRat(JSON.parse(l)) as Row);
const css = readFileSync(resolve(__dirname, 'pain.module.css'), 'utf8');
const flat = css.replace(/\s+/g, ' ');

function block(text: string, open: string): string {
  const at = text.indexOf(open);
  if (at < 0) throw new Error(`no block ${open}`);
  let depth = 0;
  for (let i = text.indexOf('{', at); i < text.length; i++) {
    if (text[i] === '{') depth++;
    if (text[i] === '}' && --depth === 0) return text.slice(text.indexOf('{', at) + 1, i);
  }
  throw new Error(`unclosed ${open}`);
}

const narrow = block(css, `@media ${mediaCondition('mq.w-le-860')}`);
const supports = block(narrow, '@supports');
const layer = block(supports, '.darkLayer');
const decl = (body: string, name: string): string => new RegExp(`(?:^|[;\\s])${name}:\\s*([^;]+);`).exec(body)?.[1]?.trim() ?? '';

/** CSS Easing steps(1, jump-start) on the scroll progress of the layer's animation (test-only twin of Lean `layerOpacity`). */
function opacity(t: number, len: number, y: number): number {
  const before = y < t;
  const p = before ? 0 : y < t + len ? (y - t) / len : 1;
  let cur = Math.floor(p) + 1;
  if (before && Number.isInteger(p)) cur -= 1;
  if (p < 0 && cur < 0) cur = 0;
  if (p <= 1 && cur > 1) cur = 1;
  return cur;
}

describe('pain dark-scroll range start (Lean measuredFlip)', () => {
  it.each(rows.filter((r) => r.kind === 'flip'))('flip h=$h tr=$tr y0=$y0', (r) => {
    expect(flipAt({ rectTop: r.rectTop as number, scrollY: r.y0 as number, ty: r.ty as number })).toBeCloseTo(r.flip as number, 9);
  });
  it('is the header document top minus half a pixel at any scroll offset', () => {
    for (const y0 of [0, 17.25, 3000]) expect(flipAt({ rectTop: 1850 - y0, scrollY: y0, ty: 0 })).toBe(1849.5);
  });
});

describe('pain dark-scroll pixels (Lean pixel_eq)', () => {
  const white: Rgb = [255, 255, 255];
  it.each(rows.filter((r) => r.kind === 'pixel'))('w=$w h=$h y=$y', (r) => {
    const flip = (r.h as number) - 0.5;
    const o = opacity(flip, 1, r.y as number);
    expect(o).toBe(r.opacity);
    const dark: Rgb = [19, 25, 34];
    const px: Rgb = (r.w as number) <= 860 ? (white.map((c, i) => c + (dark[i]! - c) * o) as Rgb) : dark;
    expect(px).toEqual(r.var);
    expect(r.var).toEqual(r.orig);
  });
});

describe('pain dark-scroll CSS', () => {
  it('restates the @supports condition the code feature-tests', () => {
    expect(flat).toContain(`@supports (${SUPPORTS})`);
  });
  it('lives in the narrow band, so the edge is the generated 860 condition', () => {
    expect(narrow).toContain('@supports');
    expect(css.match(/@supports\s*\(/g)?.length).toBe(1);
  });
  it('keeps the section and the stage clear and the layer dark, behind the content, with no children', () => {
    const sticky = block(supports, ".pain[data-fw-variant='dark-scroll'] .sticky");
    expect(decl(sticky, 'background')).toBe('transparent');
    expect(decl(layer, 'background')).toBe('#131922');
    expect(decl(layer, 'z-index')).toBe('0');
    expect(decl(layer, 'inset')).toBe('0');
    expect(decl(layer, 'position')).toBe('absolute');
    expect(decl(layer, 'pointer-events')).toBe('none');
  });
  it('animates opacity only, steps(1, jump-start), on the root scroll timeline, filled both ways', () => {
    expect(decl(layer, 'animation-timing-function')).toBe('steps(1, jump-start)');
    expect(decl(layer, 'animation-timeline')).toBe('scroll(root block)');
    expect(decl(layer, 'animation-fill-mode')).toBe('both');
    expect(decl(layer, 'animation-duration')).toBe('auto');
    expect(block(css, '@keyframes painDark').replace(/\s+/g, ' ').trim()).toBe('from { opacity: 0; } to { opacity: 1; }');
  });
  it('reads the range start from the property the code writes, over a 1px range', () => {
    expect(decl(layer, 'animation-range-start')).toBe(`var(${RANGE_VAR}, 100000000px)`);
    expect(decl(layer, 'animation-range-end')).toBe(`calc(var(${RANGE_VAR}, 100000000px) + 1px)`);
  });
  it('is hidden by default and above the band', () => {
    expect(decl(block(css, '.darkLayer'), 'display')).toBe('none');
  });
});

describe('pain dark-scroll glue', () => {
  it('reads a translation from a computed transform', () => {
    expect(translateY('none')).toBe(0);
    expect(translateY('matrix(1, 0, 0, 1, 0, 48)')).toBe(48);
    expect(translateY('matrix(1, 0, 0, 1, 0, 12.5)')).toBe(12.5);
    expect(translateY('matrix3d(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 7, 0, 1)')).toBe(7);
    expect(translateY('')).toBe(0);
  });
  it('hands the flip to the layer only for the variant in an engine that runs it', () => {
    expect(layerOwnsFlip('dark-scroll', true)).toBe(true);
    expect(layerOwnsFlip('dark-scroll', false)).toBe(false);
    expect(layerOwnsFlip('faithful', true)).toBe(false);
    expect(layerOwnsFlip(null, true)).toBe(false);
  });
});
