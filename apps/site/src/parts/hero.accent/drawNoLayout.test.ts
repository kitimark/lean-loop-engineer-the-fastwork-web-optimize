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
      /\.accent:is\(\[data-fw-draw='nolayout'\], \[data-fw-draw='nolayout-full'\]\):is\(\.drawingIn, \.drawingOut\) \.path \{\s*stroke-dasharray: none;\s*stroke-dashoffset: 0;\s*animation: none;/,
    );
    expect(css).toMatch(
      /\.accent:is\(\[data-fw-draw='nolayout'\], \[data-fw-draw='nolayout-full'\]\)\.drawingIn \.frame0 \{\s*animation: 0\.9s cubic-bezier\(0\.4, 0, 0\.2, 1\) forwards clipIn;/,
    );
    expect(css).toMatch(
      /\.accent:is\(\[data-fw-draw='nolayout'\], \[data-fw-draw='nolayout-full'\]\)\.drawingOut \.frame0 \{\s*animation: 0\.9s cubic-bezier\(0\.4, 0, 0\.2, 1\) forwards clipOut;/,
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

describe('draw-nolayout-full against the Lean golden', () => {
  const slots = of('slot').filter((r) => r.arm === 'draw-nolayout-full');
  it('only the frame that sets the width needs layout, in both engines', () => {
    expect(slots.map((r) => [r.slot, r.changes, r.wkLayout, r.crLayout])).toEqual([
      ['draw-out', 1, false, false],
      ['draw-in-first', 2, true, true],
      ['draw-in-rest', 1, false, false],
    ]);
  });
  it('layout frames per cycle of 54 frames per phase', () => {
    const c = Object.fromEntries(of('cycle').map((r) => [r.arm as string, r]));
    expect(c['faithful']).toMatchObject({ wkLayoutFrames: 108, crLayoutFrames: 54 });
    expect(c['draw-nolayout']).toMatchObject({ wkLayoutFrames: 54, crLayoutFrames: 54 });
    expect(c['draw-nolayout-full']).toMatchObject({ wkLayoutFrames: 1, crLayoutFrames: 1 });
  });
  it('the width transition is dropped by one rule that only the full attribute selects', () => {
    expect(css.match(/\.accent\[data-fw-draw='nolayout-full'\]\.drawingIn \{/g)).toHaveLength(1);
    expect(css).toMatch(/\[data-fw-draw='nolayout-full'\]\.drawingIn \{\s*transition: none;\s*\}/);
    expect(css).toMatch(/\.drawingIn \{\s*transition: width 0\.9s cubic-bezier\(0\.4, 0, 0\.2, 1\);/);
  });
  it('the attribute decision and the registry', () => {
    expect(drawAttr('draw-nolayout-full')).toBe('nolayout-full');
    expect(renderToString(createElement(HeroAccent, { variant: 'draw-nolayout-full' }))).toContain(
      'data-fw-draw="nolayout-full"',
    );
    const v = (part.variants as Record<string, { kind: string; visClass?: string; provenance: { limit?: string } }>)[
      'draw-nolayout-full'
    ];
    expect(v).toMatchObject({ kind: 'proposal', visClass: 'L' });
    expect(v!.provenance.limit!.startsWith('look change')).toBe(true);
  });
});

describe('component and registry', () => {
  it('writes data-fw-draw=nolayout only for draw-nolayout', () => {
    expect(renderToString(createElement(HeroAccent, { variant: 'draw-nolayout' }))).toContain('data-fw-draw="nolayout"');
    expect(renderToString(createElement(HeroAccent, { variant: 'faithful' }))).not.toContain('data-fw-draw');
  });
  it('is registered as a T0 look-change proposal (class L)', () => {
    const v = (part.variants as Record<string, { kind: string; tier: string; visClass?: string; provenance: { limit?: string } }>)[
      'draw-nolayout'
    ];
    expect(v).toMatchObject({ kind: 'proposal', tier: 'T0', visClass: 'L' });
    expect(v!.provenance.limit!.startsWith('look change')).toBe(true);
  });
});
