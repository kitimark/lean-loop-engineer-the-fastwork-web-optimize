import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createElement } from 'react';
import { renderToString } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { HeroAccent } from './index';
import part from './part.json';
import { drawAttr } from './drawOne';

const root = resolve(__dirname, '../../../../..');
const css = readFileSync(resolve(__dirname, 'accent.module.css'), 'utf8');
const rows = readFileSync(resolve(root, 'packages/contracts/golden/parts/hero.accent.nolayout.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Record<string, unknown>);
const of = (kind: string) => rows.filter((r) => r.kind === kind);

describe('draw-nolayout against the Lean golden (Fw.Engine.StyleDiffAccent)', () => {
  it('the attribute decision', () => {
    for (const r of of('attr')) expect(drawAttr(r.variant as string) ?? null).toBe(r.attr);
  });
  it('the keyframes carry the Lean clip insets', () => {
    for (const r of of('keyframe')) {
      const m = css.match(
        new RegExp(`@keyframes ${r.name} \\{\\s*0% \\{\\s*clip-path: ([^;]+);\\s*\\}\\s*to \\{\\s*clip-path: ([^;]+);`),
      );
      expect(m, String(r.name)).not.toBeNull();
      expect([m![1], m![2]]).toEqual([r.from, r.to]);
    }
  });
  it('the arm changes one clip-path per frame, and no stroke offset', () => {
    const frames = of('frame').filter((r) => r.arm === 'draw-nolayout');
    expect(frames.map((r) => [r.phase, r.changes, r.wkLayout, r.crLayout])).toEqual([
      ['draw-out', 1, false, false],
      ['draw-in', 2, true, true],
    ]);
    expect(css).toMatch(
      /\[data-fw-draw='nolayout'\]:is\(\.drawingIn, \.drawingOut\) \.path \{\s*stroke-dasharray: none;\s*stroke-dashoffset: 0;\s*animation: none;/,
    );
    expect(css).toMatch(
      /\[data-fw-draw='nolayout'\]\.drawingIn \.frame0 \{\s*animation: 0\.9s cubic-bezier\(0\.4, 0, 0\.2, 1\) forwards clipIn;/,
    );
    expect(css).toMatch(
      /\[data-fw-draw='nolayout'\]\.drawingOut \.frame0 \{\s*animation: 0\.9s cubic-bezier\(0\.4, 0, 0\.2, 1\) forwards clipOut;/,
    );
  });
  it('the two clip keyframes animate clip-path and nothing else', () => {
    const body = css.match(/@keyframes clipIn[\s\S]*?@keyframes idle0/)![0];
    const props = [...body.matchAll(/^\s+([a-z-]+):/gm)].map((m) => m[1]);
    expect(props).toEqual(['clip-path', 'clip-path', 'clip-path', 'clip-path']);
  });
  it('the table: dashoffset lays out in WebKit only, clip-path in neither, width in both', () => {
    const t = Object.fromEntries(of('cand').map((r) => [r.name as string, r]));
    expect(t['stroke-dashoffset']).toMatchObject({ wkLayout: true, crLayout: false });
    expect(t['clip-path inset()']).toMatchObject({ wkLayout: false, crLayout: false });
    expect(t['width']).toMatchObject({ wkLayout: true, crLayout: true });
  });
});

describe('component and registry', () => {
  it('writes data-fw-draw=nolayout only for draw-nolayout', () => {
    expect(renderToString(createElement(HeroAccent, { variant: 'draw-nolayout' }))).toContain('data-fw-draw="nolayout"');
    expect(renderToString(createElement(HeroAccent, { variant: 'faithful' }))).not.toContain('data-fw-draw');
  });
  it('is registered as an optimized T0 look-change variant', () => {
    const v = (part.variants as Record<string, { kind: string; tier: string; provenance: { limit?: string } }>)[
      'draw-nolayout'
    ];
    expect(v).toMatchObject({ kind: 'optimized', tier: 'T0' });
    expect(v!.provenance.limit!.startsWith('look change')).toBe(true);
  });
});
