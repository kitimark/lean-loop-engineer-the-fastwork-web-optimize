import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { parseOnly, STAGE_PREMISE } from './only';

interface Vector {
  query: string;
  result: { kind: string; code?: string; target?: string; members?: string[]; y?: number; vw?: number; vh?: number; premise?: string };
}

const golden: Vector[] = readFileSync(new URL('../../../../packages/contracts/golden/parts/stage.jsonl', import.meta.url), 'utf8')
  .split('\n')
  .filter(Boolean)
  .map((l) => JSON.parse(l) as Vector);

describe('?only= against the Lean golden (Fw.Site.Stage)', () => {
  it('has vectors', () => expect(golden.length).toBeGreaterThan(20));
  for (const v of golden) {
    it(JSON.stringify(v.query), () => {
      const r = parseOnly(v.query);
      expect(r.kind).toBe(v.result.kind);
      if (r.kind === 'err') expect(r.code).toBe(v.result.code);
      if (r.kind === 'ok') {
        expect(r.stage.target).toBe(v.result.target);
        expect(r.stage.members).toEqual(v.result.members);
        expect(r.stage.env).toEqual({ y: v.result.y, vw: v.result.vw, vh: v.result.vh });
        expect(r.stage.premise).toBe(v.result.premise);
      }
    });
  }
  it('premise is the contract premise', () => expect(STAGE_PREMISE).toBe('declared-rows-unverified'));
});
