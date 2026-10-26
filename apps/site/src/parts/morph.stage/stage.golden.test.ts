import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { ATTR_READERS } from '../morph.tween/waapi.logic';
import { createStageDriver } from './driver';
import { jackOn, maxYOf, narrowOf, NARROW_MAX, progress, RANGE_CSS, sameKey, sceneBottom, spanH, spanW, stateKey, STAGE_ATTR, STAGE_ID, STAGE_ON, trackT, TRACK_CSS, TRACK_CSS_NARROW, pointerNone } from './logic';
import { stageProps } from './index';

type Num = number | { num: string; den: string };
interface Row {
  fn: string;
  in: Record<string, unknown>;
  out: Record<string, unknown>;
}

const rows: Row[] = readFileSync(new URL('../../../../../packages/contracts/golden/parts/morph-stage.jsonl', import.meta.url), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Row);
const num = (n: unknown): number => (typeof n === 'number' ? n : Number((n as { num: string }).num) / Number((n as { den: string }).den));
const of = (fn: string) => rows.filter((r) => r.fn === fn);
const squash = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\s+/g, '');
const css = squash(readFileSync(new URL('./stage.module.css', import.meta.url), 'utf8'));
const rule = (text: string) => squash(text);

describe('morph.stage constants against the Lean golden', () => {
  const c = of('morph.stage.const')[0]!.out as Record<string, unknown>;
  it('names, flag values and the jack switch', () => {
    expect(STAGE_ID).toBe(c.id);
    expect(STAGE_ATTR).toBe(c.attr);
    expect(STAGE_ON).toBe(c.on);
    const jack = c.jackOn as Record<string, boolean>;
    for (const v of Object.keys(jack)) expect(jackOn(v)).toBe(jack[v]);
    expect(stageProps('faithful')).toEqual({});
    expect(stageProps('on')).toEqual({ [STAGE_ATTR]: '' });
  });
  it('the CSS strings equal the generated ones and the module holds them', () => {
    expect(RANGE_CSS).toBe(c.rangeCss);
    expect(TRACK_CSS).toBe(c.trackCss);
    expect(TRACK_CSS_NARROW).toBe(c.trackCssNarrow);
    expect(NARROW_MAX).toBe(num(c.narrowMaxWidth));
    expect(css).toContain(`--stage-t:${rule(TRACK_CSS)};`.replace(/,/g, ','));
    expect(css).toContain(`--stage-t:${rule(TRACK_CSS_NARROW)};`);
    expect(css).toContain(`@media(width<=${NARROW_MAX}px)`);
    expect(css).toContain(`animation-range-start:calc(100%-var(--stage-t));animation-range-end:100%;`);
    expect(squash(RANGE_CSS)).toBe('calc(100%-var(--stage-t))100%');
    expect(css).toContain('animation-timeline:scroll(rootblock);');
  });
  it('the keyframes equal the Lean end states', () => {
    const morph = c.morphKf as { offset: Num; value: Num }[];
    expect(morph.map((k) => [num(k.offset), num(k.value)])).toEqual([[0, 0], [1, 1]]);
    expect(css).toMatch(/@keyframesstageMorph\{from\{--morph:0;\}to\{--morph:1;\}\}/);
    const fade = c.fadeKf as { offset: Num; value: Num }[];
    expect(fade.map((k) => [num(k.offset), num(k.value)])).toEqual([[0, 1], [0.55, 0], [1, 0]]);
    expect(css).toMatch(/@keyframesstageFade\{0%\{--morph-fade:1;\}55%\{--morph-fade:0;\}100%\{--morph-fade:0;\}\}/);
  });
  it('the readers and the pointer cut are the tween variant readers', () => {
    const readers = c.readers as { sel: string; cmp: string; theta: Num }[];
    expect(readers.map((r) => ({ sel: r.sel, cmp: r.cmp, theta: num(r.theta) }))).toEqual(ATTR_READERS.map((r) => ({ ...r })));
    expect(num(c.pointerTheta)).toBe(209 / 400);
  });
});

describe('morph.stage track length T', () => {
  for (const r of of('morph.stage.track')) {
    const w = { vw: num(r.in.vw), vh: num(r.in.vh), narrow: r.in.narrow as boolean };
    it(`T at ${w.vw}x${w.vh}`, () => {
      expect(narrowOf(w.vw)).toBe(w.narrow);
      expect(spanH(w)).toBe(num(r.out.spanH));
      expect(spanW(w)).toBe(num(r.out.spanW));
      expect(trackT(w)).toBe(num(r.out.t));
      expect(trackT(w)).toBeGreaterThanOrEqual(Math.max(spanH(w), spanW(w), num(r.out.blur)));
    });
  }
});

describe('morph.stage progress, keyframes and state cuts', () => {
  for (const r of of('morph.stage.progress')) {
    const f = { y: num(r.in.y), maxY: num(r.in.maxY), t: num(r.in.t) };
    it(`y ${f.y} of [${f.maxY - f.t}, ${f.maxY}]`, () => {
      const p = progress(f);
      expect(p).toBeCloseTo(num(r.out.p), 12);
      expect(p).toBeCloseTo(num(r.out.morph), 12);
      expect(stateKey(p)).toEqual(r.out.key);
      expect(pointerNone(p)).toBe(r.out.pointerNone);
      expect(p > 1 / 1000).toBe(r.out.active);
    });
  }
});

describe('morph.stage sweeps: the reader writes only on a state change', () => {
  for (const r of of('morph.stage.sweep')) {
    const maxY = num(r.in.maxY);
    const t = num(r.in.t);
    const up = r.in.up as boolean;
    it(`${r.in.case as string}`, () => {
      const ys = Array.from({ length: t + 2 }, (_, i) => maxY - t - 1 + i);
      if (!up) ys.reverse();
      let y = ys[0]!;
      const writes: { y: number; key: boolean[] }[] = [];
      let published = 0;
      let pointerWrites = 0;
      const d = createStageDriver({
        read: () => ({ y, maxY, t }),
        publish: () => void published++,
        pointer: () => void pointerWrites++,
      });
      let prev = stateKey(0);
      for (const yy of ys) {
        y = yy;
        const w = d.frame();
        const key = stateKey(progress({ y, maxY, t }));
        if (w) {
          w();
          writes.push({ y, key });
        }
        expect(w !== undefined).toBe(!sameKey(prev, key));
        prev = key;
      }
      const want = r.out.writes as { y: Num; key: boolean[] }[];
      const seen = up ? writes : writes.slice(1);
      expect(seen.map((x) => x.y)).toEqual(want.map((x) => num(x.y)));
      expect(seen.map((x) => x.key)).toEqual(want.map((x) => x.key));
      expect(published).toBe(writes.length);
      expect(pointerWrites).toBeLessThanOrEqual(2);
    });
  }
});

describe('morph.stage held scene', () => {
  for (const r of of('morph.stage.scene')) {
    const [pb, t, vh, y] = [num(r.in.platformBottom), num(r.in.t), num(r.in.vh), num(r.in.y)];
    it(`scroll ${y}`, () => {
      expect(maxYOf(pb, t, vh)).toBe(num(r.out.maxY));
      expect(maxYOf(pb, t, vh) - t).toBe(num(r.out.rangeStart));
      expect(sceneBottom(pb, t, vh, y)).toBe(num(r.out.sceneBottom));
    });
  }
});
