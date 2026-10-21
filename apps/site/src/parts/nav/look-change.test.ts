import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { parts, presets } from '../../registry';

/** The look-change list against packages/contracts/golden/preset/look-change.candidates.jsonl (Fw.Preset.Gen.lookText). */
const lines = readFileSync(
  resolve(__dirname, '../../../../../packages/contracts/golden/preset/look-change.candidates.jsonl'),
  'utf8',
)
  .split('\n')
  .filter((l) => l.length > 0)
  .map(
    (l) =>
      JSON.parse(l) as {
        flag: string;
        kind: string;
        visClass: string;
        member: boolean;
        userDecision: { date: string; decision: string; review: string; material: unknown } | null;
      },
  );

const looks = parts.flatMap((p) =>
  Object.entries(p.variants)
    .filter(([, d]) => d.visClass === 'L')
    .map(([v, d]) => ({ flag: `${p.id}:${v}`, kind: d.kind })),
);

describe('look-change candidates', () => {
  it('the golden lists exactly the registered class L variants, each a proposal', () => {
    expect(lines.map((l) => l.flag)).toEqual(looks.map((l) => l.flag).sort());
    for (const l of lines) {
      expect(l.visClass, l.flag).toBe('L');
      expect(l.kind, l.flag).toBe(looks.find((x) => x.flag === l.flag)?.kind);
      expect(l.kind, l.flag).toBe('proposal');
    }
  });

  it('no candidate is in v2-proved', () => {
    const fw = presets['v2-proved']!.fw;
    for (const l of lines) {
      const [part, v] = l.flag.split(':');
      expect(fw[part!], l.flag).not.toBe(v);
      expect(l.member, l.flag).toBe(false);
    }
  });

  it('nav:earn-no-transition is a look change the user kept on 2026-10-21, visual review pending, with its material', () => {
    expect(lines.find((l) => l.flag === 'nav:earn-no-transition')?.userDecision).toEqual({
      date: '2026-10-21',
      decision: 'kept',
      review: 'pending',
      material: {
        chromium: { state: 'ready', run: '39473950464', artifact: 'frames-chromium', expires: '2026-11-19' },
        webkit: { state: 'ready', run: '39530106935', artifact: 'frames-apple-390, frames-apple-1280', expires: '2026-11-20' },
      },
    });
  });

  it('every decision is one of kept, rejected, accepted with a review state of pending or done', () => {
    for (const l of lines) {
      if (!l.userDecision) continue;
      expect(['kept', 'rejected', 'accepted'], l.flag).toContain(l.userDecision.decision);
      expect(['pending', 'done'], l.flag).toContain(l.userDecision.review);
    }
  });
});
