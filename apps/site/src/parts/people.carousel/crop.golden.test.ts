import { readFileSync } from 'node:fs';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { decodeRat } from '../../engine/golden.testutil';
import { PeopleCarousel } from './index';
import { cropTranslate, swapRole } from './logic';

type Row = Record<string, number>;
const rows = readFileSync(new URL('../../../../../packages/contracts/golden/parts/people-carousel-crop.jsonl', import.meta.url), 'utf8')
  .split('\n')
  .filter((l) => l.trim() !== '')
  .map((l) => decodeRat(JSON.parse(l)) as Row);
const css = readFileSync(new URL('./carousel.module.css', import.meta.url), 'utf8');

function keyframes(name: string): string {
  const at = css.indexOf(`@keyframes ${name} {`);
  if (at < 0) throw new Error(`no keyframes ${name}`);
  const open = css.indexOf('{', at);
  let depth = 0;
  let end = open;
  for (; end < css.length; end++) {
    if (css[end] === '{') depth++;
    if (css[end] === '}' && --depth === 0) break;
  }
  return css.slice(open + 1, end);
}

const LAYOUT_PROPS = ['width', 'flex-basis', 'margin', 'border-width', 'clip-path'];

describe('people.carousel crop (Lean Fw.Parts.PeopleCarouselCrop)', () => {
  it('the follower translate is the original shift at every golden progress', () => {
    expect(rows).toHaveLength(27);
    for (const r of rows) {
      expect(cropTranslate({ p: r.p! })).toBe(r.shiftCrop);
      expect(r.shiftCrop).toBe(r.shiftOrig);
    }
  });
  it('the snapped position is within half a device pixel', () => {
    for (const r of rows) expect(Math.abs(r.devErr!)).toBeLessThanOrEqual(0.5);
  });
  it('the keyframes end at the golden translate', () => {
    const end = rows.find((r) => r.p === 1)!;
    expect(keyframes('avatarsShift')).toContain(`translate: -${end.shiftCrop}px 0`);
  });
  it('the crop keyframes animate transform, opacity and translate only', () => {
    for (const name of ['avatarsCropExit', 'avatarsShift']) {
      for (const prop of LAYOUT_PROPS) expect(keyframes(name)).not.toContain(prop);
    }
    expect(keyframes('avatarsCropExit')).toContain('opacity');
    expect(keyframes('avatarsCropExit')).toContain('transform');
  });
  it('the WkAnim.clean premise: each crop rule has a cubic-bezier with both y in [0, 1], each crop keyframes has 2 stops', () => {
    for (const cls of ['cropExit', 'cropShift', 'cropEnter']) {
      const at = css.indexOf(`.avatar.${cls} {`);
      expect(at).toBeGreaterThanOrEqual(0);
      const rule = css.slice(css.indexOf('{', at), css.indexOf('}', at));
      const beziers = [...rule.matchAll(/cubic-bezier\(([^)]*)\)/g)];
      expect(beziers.length).toBeGreaterThan(0);
      for (const m of beziers) {
        const [, y1, , y2] = m[1]!.split(',').map(Number);
        for (const y of [y1!, y2!]) {
          expect(y).toBeGreaterThanOrEqual(0);
          expect(y).toBeLessThanOrEqual(1);
        }
      }
    }
    for (const name of ['avatarsCropExit', 'avatarsShift', 'avatarsPop']) {
      expect(keyframes(name).match(/(^|\s)(\d+%|from|to)\s*\{/g)).toHaveLength(2);
    }
  });
  it('the leaver slot stays 32 px in the crop and collapses in the original', () => {
    for (const r of rows) {
      expect(r.leaverCrop).toBe(32);
      expect(r.leaverOrig).toBe(32 * (1 - r.p!));
    }
  });
  it('the roles of a swap row', () => {
    expect([0, 1, 2, 3, 4].map((i) => swapRole({ i, len: 5 }))).toEqual(['exit', 'shift', 'shift', 'shift', 'enter']);
  });
});

describe('people.carousel crop markup', () => {
  const html = (variant: string): string => renderToStaticMarkup(createElement(PeopleCarousel, { variant }));
  it('rests alike in both variants', () => {
    const strip = (h: string): string => h.replace(/data-fw-variant="[^"]*"/, '');
    expect(strip(html('crop'))).toBe(strip(html('faithful')));
  });
});
