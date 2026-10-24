import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { createCountdownDriver, type Writable } from '../hero.countdown/driver';
import { TARGET_MS, faceOffsetPx, stripOffsetCells } from '../hero.countdown/logic';

type Q = string;
type Ev = { refresh: number; now: Q; reduced: boolean } | { frame: Q } | { cell: Q };
interface After {
  value: Q;
  target: number;
  animating: boolean;
  faithful: (Q | null)[];
  strip: (Q | null)[];
}
type Row =
  | { kind: 'offset'; spring: Q; cell: Q; faithful: Q[]; strip: Q[] }
  | { kind: 'drive'; scenario: string; events: Ev[]; after: After[] }
  | { kind: 'layers' };

const root = resolve(__dirname, '../../../../..');
const rows: Row[] = readFileSync(resolve(root, 'packages/contracts/golden/parts/morph.countdown.strip.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Row);

const q = (s: Q): number => {
  const [n, d] = s.split('/');
  return Number(n) / (d === undefined ? 1 : Number(d));
};
const close = (got: number | null, want: number | null) => {
  if (want === null || got === null) return expect(got).toBe(want);
  expect(Math.abs(got - want)).toBeLessThanOrEqual(1e-9 * Math.max(1, Math.abs(want)));
};
const px = (w: Writable): number | null => {
  if (w.style.transform === '') return null;
  const m = /^translateY\((.*)px\)$/.exec(w.style.transform);
  return m ? Number(m[1]) : NaN;
};

const replaySecondsOnes = (variant: 'faithful' | 'strip', events: Ev[]) => {
  const nodes: Writable[] = Array.from({ length: variant === 'strip' ? 1 : 10 }, () => ({ style: { transform: '' } }));
  let secs = 0;
  let reduced = false;
  const d = createCountdownDriver({
    variant,
    digits: [{ unit: 3, place: 1, nodes }],
    dateNow: () => TARGET_MS - secs * 1000,
    reduced: () => reduced,
  });
  return events.map((e) => {
    if ('refresh' in e) {
      secs = e.refresh;
      reduced = e.reduced;
      d.refresh(q(e.now));
    } else if ('frame' in e) d.step(0, q(e.frame));
    else d.setCell(0, q(e.cell));
    return { snap: d.snapshot()[0]!, dom: nodes.map(px) };
  });
};

describe('morph.countdown strip golden (Lean Fw.Parts.MorphCountdownStrip)', () => {
  const offsets = rows.filter((r) => r.kind === 'offset');
  const drives = rows.filter((r) => r.kind === 'drive');

  it('has rows of every kind', () => {
    expect(offsets.length).toBeGreaterThan(0);
    expect(drives.length).toBeGreaterThan(0);
    expect(rows.some((r) => r.kind === 'layers')).toBe(true);
  });

  it('face and strip offsets match logic.ts', () => {
    for (const r of offsets) {
      const a = q(r.spring);
      const c = q(r.cell);
      r.faithful.forEach((w, f) => close(faceOffsetPx(f, a, c), q(w)));
      close(stripOffsetCells(a) * c, q(r.strip[0]!));
    }
  });

  for (const r of drives) {
    for (const variant of ['faithful', 'strip'] as const) {
      it(`${r.scenario}: createCountdownDriver ${variant} writes the golden transforms`, () => {
        const got = replaySecondsOnes(variant, r.events);
        expect(got.length).toBe(r.after.length);
        got.forEach((g, i) => {
          const want = r.after[i]!;
          close(g.snap.value, q(want.value));
          expect(g.snap.target).toBe(want.target);
          expect(g.snap.animating).toBe(want.animating);
          const dom = want[variant];
          expect(g.dom.length).toBe(dom.length);
          g.dom.forEach((x, k) => close(x, dom[k] === null ? null : q(dom[k]!)));
        });
      });
    }
  }
});

describe('morph.countdown strip CSS premises of the layer model', () => {
  const css = readFileSync(resolve(root, 'apps/site/src/parts/hero.countdown/hero.module.css'), 'utf8');
  const rule = (sel: string) => {
    const m = new RegExp(`\\n\\s*\\.${sel} \\{([^}]*)\\}`).exec(css);
    if (!m) throw new Error(`.${sel} not found`);
    return m[1]!;
  };

  it('faces and strips are absolute will-change: transform boxes', () => {
    for (const sel of ['face', 'strip']) {
      expect(rule(sel)).toContain('will-change: transform');
      expect(rule(sel)).toContain('position: absolute');
    }
  });

  it('.digit and .value clip with overflow hidden and no border-radius', () => {
    for (const sel of ['digit', 'value']) {
      expect(rule(sel)).toContain('overflow: hidden');
      expect(rule(sel)).not.toContain('border-radius');
    }
  });

  it('.unit rounds without clipping', () => {
    expect(rule('unit')).toContain('border-radius');
    expect(rule('unit')).not.toContain('overflow');
  });
});
