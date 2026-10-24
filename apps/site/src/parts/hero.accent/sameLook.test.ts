import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import part from './part.json';

const root = resolve(__dirname, '../../../../..');
const rows = readFileSync(resolve(root, 'packages/contracts/golden/parts/hero.accent.nolayout.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Record<string, unknown>);
const of = (kind: string) => rows.filter((r) => r.kind === kind);

describe('same-look search against the Lean golden (Fw.Engine.StyleDiffAccent)', () => {
  it('decides each candidate on its own', () => {
    expect(Object.fromEntries(of('search').map((r) => [r.cand, r.verdict]))).toEqual({
      dasharray: 'layout',
      'path-d': 'layout',
      sprite: 'look',
      'paint-api': 'unavailable',
      'clip-final': 'look',
      canvas: 'pending',
      glide: 'pending',
      jump: 'look',
    });
  });
  it('only layout-free candidates stay pending', () => {
    for (const r of of('search').filter((r) => r.verdict === 'pending')) {
      expect([r.cand, r.wkLayout, r.crLayout]).toEqual([r.cand, false, false]);
    }
  });
  it('no search candidate ships as a variant', () => {
    const variants = Object.keys(part.variants);
    for (const r of of('search')) expect(variants).not.toContain(r.cand);
  });
  it('the canvas and glide pair leaves one WebKit layout frame per cycle', () => {
    expect(of('combo').map((r) => [r.stroke, r.width, r.wkLayoutFrames])).toEqual([
      ['dashoffset', 'width', 108],
      ['dashoffset', 'glide', 108],
      ['canvas', 'width', 54],
      ['canvas', 'glide', 1],
    ]);
  });
});
