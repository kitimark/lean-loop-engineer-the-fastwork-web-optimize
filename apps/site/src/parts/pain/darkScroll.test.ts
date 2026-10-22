import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { decodeRat } from '../../engine/golden.testutil';
import { mediaCondition } from '../../breakpoints';
import { layerOwnsFlip, RANGE_LEN, RANGE_VAR, rangeStart, SUPPORTS, translateY, WINDOW } from './darkScroll';

type Rgb = [number, number, number];
type Row = { kind: 'flip' | 'pixel'; [k: string]: number | string | Rgb };
const rows = readFileSync(resolve(__dirname, '../../../../../packages/contracts/golden/parts/pain-dark-scroll.jsonl'), 'utf8')
  .split('\n')
  .filter((l) => l.trim() !== '')
  .map((l) => decodeRat(JSON.parse(l)) as Row);
const css = readFileSync(resolve(__dirname, 'pain.module.css'), 'utf8');
const flat = css.replace(/\s+/g, ' ');

function block(text: string, open: string, nth = 0): string {
  let at = text.indexOf(open);
  for (let k = 0; k < nth && at >= 0; k++) at = text.indexOf(open, at + 1);
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
const layer = block(supports, "::before");
const decl = (body: string, name: string): string => new RegExp(`(?:^|[;\\s])${name}:\\s*([^;]+);`).exec(body)?.[1]?.trim() ?? '';

function opacity(s: number, len: number, x: number, y: number): number {
  const p = y < s ? 0 : y < s + len ? (y - s) / len : 1;
  if (p < x) return 0;
  const q = (p - x) / (1 - x);
  let cur = Math.floor(q) + 1;
  if (q <= 1 && cur > 1) cur = 1;
  return cur;
}

describe('pain dark-scroll range start (Lean measuredStart)', () => {
  it.each(rows.filter((r) => r.kind === 'flip'))('flip h=$h tr=$tr y0=$y0', (r) => {
    expect(rangeStart({ rectTop: r.rectTop as number, scrollY: r.y0 as number, ty: r.ty as number })).toBeCloseTo(r.start as number, 9);
  });
  it('is the header document top minus half a pixel minus the window at any scroll offset', () => {
    for (const y0 of [0, 17.25, 3000]) expect(rangeStart({ rectTop: 1850 - y0, scrollY: y0, ty: 0 })).toBe(1849.5 - WINDOW);
  });
});

describe('pain dark-scroll pixels (Lean pixel_eq)', () => {
  const white: Rgb = [255, 255, 255];
  it.each(rows.filter((r) => r.kind === 'pixel'))('w=$w h=$h y=$y', (r) => {
    const o = opacity(r.start as number, RANGE_LEN, WINDOW / RANGE_LEN, r.y as number);
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
  it('leaves every existing background alone: two dark pseudo-elements, no element and no restyle', () => {
    expect(supports).not.toMatch(/transparent/);
    expect(decl(layer, 'background')).toBe('#131922');
    expect(decl(layer, 'position')).toBe('absolute');
    expect(decl(layer, 'pointer-events')).toBe('none');
    expect(narrow).toContain('background: #fff;');
  });
  it('covers the hold under the stage and the stage above its own background, both behind the content', () => {
    const hold = block(supports, ".pain[data-fw-variant='dark-scroll']::before {");
    expect(decl(hold, 'height')).toBe('200svh');
    expect(decl(hold, 'inset')).toBe('auto 0 0');
    expect(decl(hold, 'z-index')).toBe('0');
    const stage = block(supports, ".pain[data-fw-variant='dark-scroll'] .sticky::before {", 1);
    expect(decl(stage, 'inset')).toBe('0');
    expect(decl(stage, 'z-index')).toBe('-1');
    expect(flat).toContain('height: 200svh;');
  });
  it('animates opacity only, steps(1, jump-start), on the root scroll timeline, filled both ways', () => {
    expect(decl(layer, 'animation-timing-function')).toBe('linear');
    expect(decl(layer, 'animation-timeline')).toBe('scroll(root block)');
    expect(decl(layer, 'animation-fill-mode')).toBe('both');
    expect(decl(layer, 'animation-duration')).toBe('auto');
    expect(block(css, '@keyframes painDark').replace(/\s+/g, ' ').trim()).toBe(
      `0% { opacity: 0; } ${(WINDOW / RANGE_LEN) * 100}% { opacity: 0; animation-timing-function: steps(1, jump-start); } 100% { opacity: 1; }`,
    );
  });
  it('reads the range start from the property the code writes, over the 32768px range', () => {
    expect(decl(layer, 'animation-range-start')).toBe(`var(${RANGE_VAR}, 100000000px)`);
    expect(decl(layer, 'animation-range-end')).toBe(`calc(var(${RANGE_VAR}, 100000000px) + ${RANGE_LEN}px)`);
  });
  it('exists only inside the band and the @supports, as pseudo-elements (no child is added)', () => {
    expect(css.match(/\](?: \.sticky)?::before/g)?.length).toBe(4);
    expect(decl(layer, 'content')).toBe("''");
    expect(supports).toContain(".pain[data-fw-variant='dark-scroll']::before");
    expect(supports).toContain(".pain[data-fw-variant='dark-scroll'] .sticky::before");
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
