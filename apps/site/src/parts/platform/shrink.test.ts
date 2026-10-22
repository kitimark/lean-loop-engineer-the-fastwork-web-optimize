import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import { createShrink } from './driver';
import { cardLook, planShrink } from './logic';

/** Golden vectors of Lean `PlatformShrinkOpt` (`platform-shrink.jsonl`, from `PlatformGolden.shrinkMqLines`). */
goldenConformance('platform-shrink', {
  planShrink: (i) => planShrink({ gated: i.gated as boolean, s: i.s as number, last: i.last as number }),
  cardLook: (i) => cardLook({ c860: i.c860 as boolean, le720: i.le720 as boolean, v: i.v as number }),
});

function rig(gate: (() => boolean) | undefined) {
  const writes: string[] = [];
  let bottom = 1000;
  const frame = createShrink(
    {
      cardBottom: () => bottom,
      setShrink: (x) => writes.push(`shrink ${x.toFixed(3)}`),
      setShrinking: (on) => writes.push(`cls ${on}`),
    },
    { reduced: () => false, vh: () => 1000 },
    gate === undefined ? {} : { gate },
  );
  return { frame, writes, move: (b: number) => (bottom = b) };
}

describe('platform variant mq (Lean PlatformShrinkOpt)', () => {
  it('outside the band it is the faithful driver', () => {
    const a = rig(() => false);
    const b = rig(undefined);
    for (const y of [1000, 800, 600, 400, 300, 300, 900]) {
      a.move(y);
      b.move(y);
      a.frame();
      b.frame();
    }
    expect(a.writes).toEqual(b.writes);
    expect(a.writes.some((w) => w.startsWith('shrink'))).toBe(true);
  });
  it('in the band: no shrink write, the class switch unchanged (writes_le, cls_agree)', () => {
    const a = rig(() => true);
    const b = rig(undefined);
    for (const y of [1000, 800, 600, 400, 300, 300, 900]) {
      a.move(y);
      b.move(y);
      a.frame();
      b.frame();
    }
    expect(a.writes.some((w) => w.startsWith('shrink'))).toBe(false);
    expect(a.writes).toEqual(b.writes.filter((w) => !w.startsWith('shrink')));
  });
  it('leaving the band writes the current value on the very next frame (inl_ungated)', () => {
    let inBand = true;
    const a = rig(() => inBand);
    for (const y of [800, 500, 500]) {
      a.move(y);
      a.frame();
    }
    expect(a.writes.some((w) => w.startsWith('shrink'))).toBe(false);
    inBand = false;
    a.frame(); // the media-change handler runs the frame
    expect(a.writes.filter((w) => w.startsWith('shrink'))).toEqual(['shrink 0.784']);
    a.frame();
    expect(a.writes.filter((w) => w.startsWith('shrink'))).toHaveLength(1);
  });
});

describe('platform.module.css premise of the variant', () => {
  const css = readFileSync(resolve(__dirname, 'platform.module.css'), 'utf8');
  const lines = css.split('\n');
  it('--platform-shrink itself is read only by the scale at line 8 and the card radius at line 31', () => {
    const readers = lines.flatMap((l, i) => (/var\(--platform-shrink[,)]/.test(l) ? [i + 1] : []));
    expect(readers).toEqual([8, 31]);
  });
  it('--platform-shrink-scale and -radius are read only by the card (lines 31, 32)', () => {
    const readers = lines.flatMap((l, i) => (/var\(--platform-shrink-(scale|radius)/.test(l) ? [i + 1] : []));
    expect(readers).toEqual([31, 32]);
  });
  it('no other file of the part reads it', () => {
    for (const f of ['stage.module.css', 'sweep.module.css', 'visuals.module.css', 'Visuals.tsx']) {
      expect(readFileSync(resolve(__dirname, f), 'utf8')).not.toMatch(/--platform-shrink/);
    }
  });
  it('the c860 band pins scale 1 and radius 0 on the section and removes the card transform and radius', () => {
    const at = lines.findIndex((l, i) => i > 290 && /^\s*@media \(width<=860px\), \(device-width<=500px\)/.test(l));
    expect(at + 1).toBe(303);
    const block = lines.slice(at, at + 12).join('\n');
    expect(block).toMatch(/--platform-shrink-scale: 1;/);
    expect(block).toMatch(/--platform-shrink-radius: 0px;/);
    expect(block).toMatch(/border-radius: 0;/);
    expect(block).toMatch(/transform: none;/);
  });
});
