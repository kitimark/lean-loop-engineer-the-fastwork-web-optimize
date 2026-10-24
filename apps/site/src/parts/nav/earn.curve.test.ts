import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { readGolden } from '../../engine/golden.testutil';

const golden = readGolden('nav.earn.curve', 'main');
const css = readFileSync(resolve(__dirname, 'nav.module.css'), 'utf8');

interface Run {
  fromPx: number;
  toPx: number;
  durUs: number;
  delayUs: number;
  curve: number[];
}

const VARIANT: Record<string, string> = {
  entry: '    .nav:global(.is-earn-logical.is-hero-pill):not(:global(.is-earn-still)) .btn.earn',
  exit: '    .nav:global(.is-earn-logical):not(:global(.is-hero-pill), :global(.is-earn-still)) .btn.earn',
};

const PAD: Record<number, number> = { 390: 16, 1280: 24 };

function padEntries(selector: string): { durUs: number; delayUs: number; curve: number[] }[] {
  const at = css.indexOf(`\n${selector} {`);
  if (at < 0) throw new Error(`no rule ${selector} in nav.module.css`);
  const decl = /transition:\s*([^;]+);/.exec(css.slice(css.indexOf('{', at) + 1, css.indexOf('}', at)))?.[1] ?? '';
  return decl
    .split(/,(?![^(]*\))/)
    .map((part) => /^\s*(padding-inline-(?:start|end))\s+([\d.]+)s\s+cubic-bezier\(([^)]*)\)(?:\s+([\d.]+)s)?\s*$/.exec(part))
    .filter((m): m is RegExpExecArray => m !== null)
    .map((m) => ({ durUs: Math.round(Number(m[2]) * 1e6), delayUs: Math.round(Number(m[4] ?? 0) * 1e6), curve: m[3].split(',').map(Number) }));
}

const grid = golden.find((g) => g.fn === 'grid')!.out as { gridBits: number; M: number; D: string; readMicro: number; solverUs: Record<string, number> };
const M = BigInt(grid.M);
const D = BigInt(grid.D);

function hundredths(curve: number[]): bigint[] {
  return curve.map((v) => BigInt(Math.round(v * 100)));
}

function bar(c1: bigint, c2: bigint, k: bigint): bigint {
  return 3n * c1 * (M - k) * (M - k) * k + 3n * c2 * (M - k) * k * k + 100n * k * k * k;
}

function ease(curve: number[], a: bigint, c: bigint): bigint {
  const [x1, y1, x2, y2] = hundredths(curve);
  let k = M;
  if (c > a) {
    k = 0n;
    for (let n = grid.gridBits - 1; n >= 0; n--) {
      const m = k + (1n << BigInt(n));
      if (bar(x1, x2, m) * c <= a * D) k = m;
    }
  }
  return bar(y1, y2, k);
}

function num(r: Run | null, toPx: number, t: bigint): bigint {
  if (!r) return BigInt(toPx) * D;
  const a = t > BigInt(r.delayUs) ? t - BigInt(r.delayUs) : 0n;
  return BigInt(r.fromPx) * D + (BigInt(r.toPx) - BigInt(r.fromPx)) * ease(r.curve, a, BigInt(r.durUs));
}

const ceilDiv = (a: bigint, b: bigint): bigint => (a + b - 1n) / b;

function slackMicro(delta: number, w: number, durUs: number): bigint {
  const d = BigInt(delta);
  return ceilDiv(d * 261n * BigInt(w) * 1000000n, 100n * BigInt(durUs)) + ceilDiv(d * 783n * 1000000n, 100n * M);
}

describe('nav:earn-logical padding curve golden', () => {
  it('every golden fn is covered', () => {
    expect(new Set(golden.map((g) => g.fn))).toEqual(new Set(['grid', 'run', 'sample', 'tol']));
  });

  it('the variant rules declare the run the WebKit variant rows start: 680 ms, no delay, the shared curve', () => {
    for (const g of golden.filter((r) => r.fn === 'run' && r.in.engine === 'webkit' && r.in.arm === 'variant')) {
      const out = g.out as Run;
      const pad = PAD[g.in.width as number];
      expect([out.fromPx, out.toPx], JSON.stringify(g.in)).toEqual(g.in.seq === 'entry' ? [pad, 0] : [0, pad]);
      const entries = padEntries(VARIANT[g.in.seq as string]);
      expect(entries).toHaveLength(2);
      for (const e of entries) expect(e).toEqual({ durUs: out.durUs, delayUs: out.delayUs, curve: out.curve });
    }
    expect(css).toContain('padding-inline: calc(var(--earn-layout) * 24px);');
    expect(css).toContain('padding-inline: calc(var(--earn-layout) * 16px);');
  });

  it('the WebKit variant run equals the Chromium faithful run, and faithful WebKit starts none', () => {
    const rows = golden.filter((g) => g.fn === 'run');
    expect(rows).toHaveLength(32);
    const key = (g: (typeof rows)[number], engine: string, arm: string) =>
      rows.find((r) => r.in.engine === engine && r.in.arm === arm && r.in.width === g.in.width && r.in.seq === g.in.seq && r.in.prop === g.in.prop)!;
    for (const g of rows.filter((r) => r.in.engine === 'webkit' && r.in.arm === 'variant')) {
      expect(g.out, JSON.stringify(g.in)).not.toBeNull();
      expect(g.out).toEqual(key(g, 'chromium', 'faithful').out);
      expect(g.out).toEqual(key(g, 'chromium', 'variant').out);
      expect(key(g, 'webkit', 'faithful').out, JSON.stringify(g.in)).toBeNull();
    }
  });

  it('a BigInt replay of the curve gives every sample exactly', () => {
    const rows = golden.filter((g) => g.fn === 'sample');
    expect(rows).toHaveLength(4 * 44);
    for (const g of rows) {
      const run = golden.find((r) => r.fn === 'run' && r.in.engine === 'webkit' && r.in.arm === 'variant' && r.in.prop === 'padding-left' && r.in.width === g.in.width && r.in.seq === g.in.seq)!.out as Run;
      const v = num(run, run.toPx, BigInt(g.in.tUs as number));
      const out = g.out as { num: string; microPx: number };
      expect(v.toString(), JSON.stringify(g.in)).toBe(out.num);
      expect(Number((v * 1000000n + D / 2n) / D)).toBe(out.microPx);
    }
  });

  it('samples run monotone from the start padding to the end padding and settle by 680 ms', () => {
    for (const w of [390, 1280]) {
      for (const seq of ['entry', 'exit']) {
        const rows = golden.filter((g) => g.fn === 'sample' && g.in.width === w && g.in.seq === seq).sort((a, b) => (a.in.tUs as number) - (b.in.tUs as number));
        const px = rows.map((g) => (g.out as { microPx: number }).microPx);
        const [from, to] = seq === 'entry' ? [PAD[w] * 1e6, 0] : [0, PAD[w] * 1e6];
        expect(px[0]).toBe(from);
        for (let i = 1; i < px.length; i++) expect(Math.sign(px[i] - px[i - 1]) * Math.sign(to - from)).toBeGreaterThanOrEqual(0);
        for (const g of rows.filter((r) => (r.in.tUs as number) >= 680000)) expect((g.out as { microPx: number }).microPx).toBe(to);
      }
    }
  });

  it('the tolerance rows follow the slack formula plus the grid gap and read rounding', () => {
    const rows = golden.filter((g) => g.fn === 'tol');
    expect(rows.length).toBeGreaterThan(0);
    for (const g of rows) {
      const { deltaPx, jUs, eUs, durUs } = g.in as { deltaPx: number; jUs: number; eUs: number; durUs: number };
      const slack = slackMicro(deltaPx, jUs + eUs, durUs);
      const gap = ceilDiv(BigInt(deltaPx) * 150n * 1000000n, 100n * M);
      expect(g.out).toEqual({ slackMicro: Number(slack), tolMicro: Number(slack + gap + BigInt(grid.readMicro)) });
    }
  });
});
