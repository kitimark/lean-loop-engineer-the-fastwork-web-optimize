import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createElement } from 'react';
import { renderToString } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { HeroAccent } from './index';
import part from './part.json';
import { animatedCount, animates, drawAlpha, drawAttr, strokeAnimated, type DrawPhase, type DrawVariant } from './drawOne';

const root = resolve(__dirname, '../../../../..');
const css = readFileSync(resolve(__dirname, 'accent.module.css'), 'utf8');
const lean = readFileSync(resolve(root, 'lean/Fw/Parts/HeroAccentOpt.lean'), 'utf8');

interface Row {
  variant: DrawVariant;
  phase: DrawPhase;
  copy?: number;
  alpha?: number | null;
  animated?: boolean;
  count?: number;
}
const rows = readFileSync(resolve(root, 'packages/contracts/golden/parts/hero.accent.drawone.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Row);

describe('draw-one decision against the Lean golden', () => {
  it('16 rows: 12 decisions, 4 counts', () => {
    expect(rows.filter((r) => r.copy !== undefined)).toHaveLength(12);
    expect(rows.filter((r) => r.count !== undefined)).toHaveLength(4);
  });
  for (const r of rows) {
    if (r.copy !== undefined) {
      it(`${r.variant} ${r.phase} copy ${r.copy}`, () => {
        expect(strokeAnimated({ variant: r.variant, phase: r.phase, j: r.copy! })).toBe(r.animated);
        if (r.phase === 'drawing') expect(drawAlpha({ j: r.copy! })).toBe(r.alpha);
      });
    } else {
      it(`${r.variant} ${r.phase} count`, () => {
        expect(animatedCount({ variant: r.variant, phase: r.phase })).toBe(r.count);
      });
    }
  }
});

describe('the CSS carries the Lean premise and decision', () => {
  it('copies 1 and 2 are opacity 0 and copy 0 is opacity 1 in the draw window (premise of hidden_pause_eq)', () => {
    expect(css).toMatch(/:is\(\.drawingIn, \.drawingOut\) \.idleFrame \{\s*opacity: 0;/);
    expect(css).toMatch(/:is\(\.drawingIn, \.drawingOut\) \.frame0 \{\s*opacity: 1;/);
  });
  it('the draw-one rule stops the animation on every copy but frame0, the one the premise leaves opaque', () => {
    const m = css.match(
      /\.accent\[data-fw-draw='one'\]:is\(\.drawingIn, \.drawingOut\) \.idleFrame:not\(\.(frame\d)\) \.path \{\s*animation: none;\s*\}/,
    );
    expect(m).not.toBeNull();
    const kept = Number(m![1]!.slice('frame'.length));
    for (const j of [0, 1, 2]) {
      expect(animates({ variant: 'draw-one', j })).toBe(j === kept);
      expect(animates({ variant: 'faithful', j })).toBe(true);
    }
  });
  it('the attribute is read by one rule only, which does not touch the idle boil', () => {
    expect(css.match(/data-fw-draw='one'/g)).toHaveLength(1);
    const rule = css.match(/\.accent\[data-fw-draw='one'\][^{]*\{[^}]*\}/)![0];
    expect(rule).not.toMatch(/\.idle(?![A-Za-z])/);
  });
});

describe('component and registry', () => {
  it('writes data-fw-draw=one only for draw-one', () => {
    expect(drawAttr('draw-one')).toBe('one');
    expect(drawAttr('faithful')).toBeUndefined();
    expect(drawAttr('steps')).toBeUndefined();
    expect(renderToString(createElement(HeroAccent, { variant: 'draw-one' }))).toContain('data-fw-draw="one"');
    expect(renderToString(createElement(HeroAccent, { variant: 'faithful' }))).not.toContain('data-fw-draw');
  });
  it('is registered as an optimized T0 variant', () => {
    const v = (part.variants as Record<string, { kind: string; tier: string }>)['draw-one'];
    expect(v).toMatchObject({ kind: 'optimized', tier: 'T0' });
  });
  it('definitions come from the Lean source', () => {
    expect(lean).toContain('def drawAlpha (j : Nat) : Rat := if j = 0 then 1 else 0');
    expect(lean).toContain('| .drawOne, j => decide (drawAlpha j ≠ 0)');
  });
});
