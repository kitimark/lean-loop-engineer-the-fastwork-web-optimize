import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { readGolden } from '../../engine/golden.testutil';
import * as L from './logic';

/** The `nav:earn-no-transition` flag against packages/contracts/golden/parts/nav-earn.jsonl (Fw.Parts.NavEarnOpt). */
const golden = readGolden('nav-earn', 'main');
const css = readFileSync(resolve(__dirname, 'nav.module.css'), 'utf8');
const PROPS = ['maxW', 'pad', 'opacity'] as const;

interface Cell {
  css: number;
  faithful: number;
  arm: number;
  dirtyF: boolean;
  dirtyA: boolean;
}

/** The body of the first rule whose line is exactly `selector {` (indentation included). */
function rule(selector: string): string {
  const at = css.indexOf(`\n${selector} {`);
  if (at < 0) throw new Error(`no rule ${selector} in nav.module.css`);
  return css.slice(css.indexOf('{', at) + 1, css.indexOf('}', at));
}

/** The `transition` list of a rule body as property, delay, duration and curve. */
function transitions(body: string): Map<string, { delayMs: number; durMs: number; curve: number[] }> {
  const decl = /transition:\s*([^;]+);/.exec(body)?.[1] ?? '';
  const out = new Map<string, { delayMs: number; durMs: number; curve: number[] }>();
  for (const part of decl.split(/,(?![^(]*\))/)) {
    const m = /^\s*([\w-]+)\s+([\d.]+)s\s+cubic-bezier\(([^)]*)\)(?:\s+([\d.]+)s)?\s*$/.exec(part);
    if (!m) throw new Error(`unparsed transition entry: ${part}`);
    out.set(m[1], { durMs: Number(m[2]) * 1000, delayMs: Number(m[4] ?? 0) * 1000, curve: m[3].split(',').map(Number) });
  }
  return out;
}

describe('nav:earn-no-transition golden', () => {
  it('every golden fn is covered', () => {
    expect(new Set(golden.map((g) => g.fn))).toEqual(new Set(['transitionsOn', 'transition', 'work', 'frame']));
  });

  it('earnTransitionOn equals transitionsOn', () => {
    for (const g of golden.filter((x) => x.fn === 'transitionsOn')) {
      expect(L.earnTransitionOn({ flag: g.in.flag as boolean, morphing: g.in.morphing as boolean })).toBe(g.out);
    }
  });

  it('the earn rule declares the transitions the model runs', () => {
    const declared = transitions(rule('  .btn.earn'));
    const rows = golden.filter((x) => x.fn === 'transition');
    expect(rows).toHaveLength(declared.size);
    for (const g of rows) {
      const d = declared.get(g.in.property as string);
      expect(d, `${g.in.property as string} is not in the earn transition list`).toBeDefined();
      const o = g.out as { delayMs: number; durMs: number; curve: number[] };
      expect(d!.delayMs).toBeCloseTo(o.delayMs, 9);
      expect(d!.durMs).toBeCloseTo(o.durMs, 9);
      d!.curve.forEach((c, i) => expect(c).toBeCloseTo(o.curve[i], 9));
    }
  });

  it('the flag class drops every earn transition', () => {
    expect(L.EARN_STILL_VARIANT).toBe('earn-no-transition');
    expect(rule(`  .nav:global(.${L.EARN_STILL_CLASS}) .btn.earn`)).toMatch(/^\s*transition:\s*none;\s*$/);
  });

  it('frames: the TS morphing cut matches the model; with transitions off the arm shows the CSS value', () => {
    const frames = golden.filter((x) => x.fn === 'frame');
    expect(frames.length).toBeGreaterThan(0);
    for (const g of frames) {
      const o = g.out as Record<string, unknown> & { m: number; morphing: boolean };
      if (Math.abs(o.m - L.MORPHING_CUT) > 1e-4) expect(L.view({ past: true, ready: true, localeOpen: false, hit: false, stuck: false, m: o.m }).morphing).toBe(o.morphing);
      if (L.earnTransitionOn({ flag: true, morphing: o.morphing })) continue;
      for (const p of PROPS) expect((o[p] as Cell).arm).toBe((o[p] as Cell).css);
    }
  });

  it('work rows count the dirty frames of the frame rows', () => {
    for (const g of golden.filter((x) => x.fn === 'work')) {
      const cells = golden
        .filter((x) => x.fn === 'frame' && x.in.viewport === g.in.viewport && x.in.push === g.in.push)
        .map((x) => (x.out as Record<string, Cell>)[g.in.property as string]);
      const o = g.out as { faithful: number; arm: number };
      expect(cells.filter((c) => c.dirtyF).length).toBe(o.faithful);
      expect(cells.filter((c) => c.dirtyA).length).toBe(o.arm);
      expect(o.arm).toBeLessThanOrEqual(o.faithful);
    }
  });
});
