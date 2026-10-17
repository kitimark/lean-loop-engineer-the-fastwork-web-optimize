import { existsSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

/**
 * Shared golden conformance harness (test only). Reads `packages/contracts/golden/parts/<id>.jsonl` (functions the TS
 * part exports; must exist) and `<id>.spec.jsonl` (Lean-only functions; when the file exists the TS must implement
 * every fn in it too). No line is skipped: a line whose `fn` has no entry in `impl` fails.
 *
 * Rat wire form `{"num":"<int>","den":"<int>"}` is decoded to a number in inputs and outputs. Numbers compare with
 * |actual - expected| <= 1e-9; booleans and strings (springStep's `done` among them) compare exactly.
 */
export const GOLDEN_TOLERANCE = 1e-9;

export function decodeRat(v: unknown): unknown {
  if (Array.isArray(v)) return v.map(decodeRat);
  if (v !== null && typeof v === 'object') {
    const o = v as Record<string, unknown>;
    if (Object.keys(o).length === 2 && typeof o.num === 'string' && typeof o.den === 'string') return Number(BigInt(o.num)) / Number(BigInt(o.den));
    return Object.fromEntries(Object.entries(o).map(([key, x]) => [key, decodeRat(x)]));
  }
  return v;
}

/** First difference as a message, or null when equal (tolerance on numbers only). */
export function diff(actual: unknown, expected: unknown, path = '$'): string | null {
  if (typeof expected === 'number') {
    if (typeof actual !== 'number') return `${path}: expected number ${expected}, got ${JSON.stringify(actual)}`;
    return Math.abs(actual - expected) <= GOLDEN_TOLERANCE ? null : `${path}: ${actual} vs ${expected}`;
  }
  if (Array.isArray(expected)) {
    if (!Array.isArray(actual) || actual.length !== expected.length) return `${path}: array ${JSON.stringify(actual)} vs ${JSON.stringify(expected)}`;
    for (let i = 0; i < expected.length; i++) {
      const d = diff(actual[i], expected[i], `${path}[${i}]`);
      if (d) return d;
    }
    return null;
  }
  if (expected !== null && typeof expected === 'object') {
    if (actual === null || typeof actual !== 'object') return `${path}: expected object, got ${JSON.stringify(actual)}`;
    const e = expected as Record<string, unknown>;
    const a = actual as Record<string, unknown>;
    const ek = Object.keys(e).sort();
    const ak = Object.keys(a).sort();
    if (ek.join() !== ak.join()) return `${path}: keys ${ak.join()} vs ${ek.join()}`;
    for (const key of ek) {
      const d = diff(a[key], e[key], `${path}.${key}`);
      if (d) return d;
    }
    return null;
  }
  return Object.is(actual, expected) ? null : `${path}: ${JSON.stringify(actual)} vs ${JSON.stringify(expected)}`;
}

export interface GoldenLine {
  fn: string;
  in: Record<string, unknown>;
  out: unknown;
}

function goldenUrl(partId: string, kind: 'main' | 'spec'): URL {
  return new URL(`../../../../packages/contracts/golden/parts/${partId}${kind === 'spec' ? '.spec' : ''}.jsonl`, import.meta.url);
}

export function readGolden(partId: string, kind: 'main' | 'spec'): GoldenLine[] {
  const url = goldenUrl(partId, kind);
  const lines = readFileSync(url, 'utf8').split('\n').filter((l) => l.trim());
  if (lines.length === 0) throw new Error(`empty golden file ${url.pathname}`);
  return lines.map((l) => JSON.parse(l) as GoldenLine);
}

export type GoldenImpl = Record<string, (input: Record<string, any>) => unknown>; // eslint-disable-line @typescript-eslint/no-explicit-any

/** Register one test per golden line of both files. `impl` maps fn -> caller taking the decoded `in` object. */
export function goldenConformance(partId: string, impl: GoldenImpl): void {
  for (const kind of ['main', 'spec'] as const) {
    if (kind === 'spec' && !existsSync(goldenUrl(partId, 'spec'))) continue;
    describe(`${partId} golden conformance (${kind})`, () => {
      const lines = readGolden(partId, kind); // throws (fails the suite) when the main file is missing
      it.each(lines.map((l, i) => [i + 1, l] as const))('line %i', (_i, v) => {
        const f = impl[v.fn];
        expect(f, `no TS implementation for golden fn ${v.fn}`).toBeTypeOf('function');
        const actual = f!(decodeRat(v.in) as Record<string, unknown>);
        expect(diff(actual, decodeRat(v.out)), `${v.fn} ${JSON.stringify(v.in)}`).toBeNull();
      });
    });
  }
}
