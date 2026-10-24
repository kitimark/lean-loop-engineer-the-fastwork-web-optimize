import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { readGolden } from '../../engine/golden.testutil';
import { EARN_LOGICAL_CLASS, EARN_LOGICAL_VARIANT } from './logic';

/** The `nav:earn-logical` variant against packages/contracts/golden/parts/nav.earn.webkit.jsonl (Fw.Parts.NavEarnWebkit). */
const golden = readGolden('nav.earn.webkit', 'main');
const css = readFileSync(resolve(__dirname, 'nav.module.css'), 'utf8');

interface Item {
  property: string;
  durMs: number;
  delayMs: number;
  curve: number[];
}

const RULES: Record<string, string> = {
  'faithful/hero': '  .nav:global(.is-hero-pill) .btn.earn',
  'faithful/base': '  .btn.earn',
  'variant/hero': '    .nav:global(.is-earn-logical.is-hero-pill):not(:global(.is-earn-still)) .btn.earn',
  'variant/base': '    .nav:global(.is-earn-logical):not(:global(.is-hero-pill), :global(.is-earn-still)) .btn.earn',
};

function body(selector: string): string {
  const at = css.indexOf(`\n${selector} {`);
  if (at < 0) throw new Error(`no rule ${selector} in nav.module.css`);
  return css.slice(css.indexOf('{', at) + 1, css.indexOf('}', at));
}

/** The `transition` list of a rule body, in order. */
function list(selector: string): Item[] {
  const decl = /transition:\s*([^;]+);/.exec(body(selector))?.[1] ?? '';
  return decl.split(/,(?![^(]*\))/).map((part) => {
    const m = /^\s*([\w-]+)\s+([\d.]+)s\s+cubic-bezier\(([^)]*)\)(?:\s+([\d.]+)s)?\s*$/.exec(part);
    if (!m) throw new Error(`unparsed transition entry: ${part}`);
    return { property: m[1], durMs: Math.round(Number(m[2]) * 1000), delayMs: Math.round(Number(m[4] ?? 0) * 1000), curve: m[3].split(',').map(Number) };
  });
}

/** Class-selector count of a selector (arguments of :global and :not included): the cascade weight that matters here. */
const weight = (selector: string): number => (selector.match(/\.[\w-]+/g) ?? []).length;

type Eng = 'chromium' | 'webkit';
const ALL = ['max-width', 'opacity', 'padding-top', 'padding-right', 'padding-bottom', 'padding-left'];
const CHANGED = new Set(['max-width', 'opacity', 'padding-left', 'padding-right']);

/** The physical property a list entry names under `dir` (ltr or rtl), for the entries the earn rules use. */
function physical(entry: string, dir: string): string[] {
  if (entry === 'padding-inline') return dir === 'ltr' ? ['padding-left', 'padding-right'] : ['padding-right', 'padding-left'];
  if (entry === 'padding-inline-start') return [dir === 'ltr' ? 'padding-left' : 'padding-right'];
  if (entry === 'padding-inline-end') return [dir === 'ltr' ? 'padding-right' : 'padding-left'];
  return [entry];
}

/** TS stand-in of Fw.Engine.TransitionStart.startedSet for these entries: WebKit drops the logical longhands of the
 * `padding-inline` shorthand (no animation wrapper), every other entry is made physical first. */
function started(engine: Eng, dir: string, items: Item[]): string[] {
  const keys = new Set(
    items.flatMap((it) => (engine === 'webkit' && it.property === 'padding-inline' ? [] : physical(it.property, dir))),
  );
  return ALL.filter((p) => keys.has(p) && CHANGED.has(p));
}

/** The duration and delay of the last entry that names `prop` (WebKit: not through `padding-inline`). */
function timing(engine: Eng, dir: string, items: Item[], prop: string): [number, number] | null {
  const hit = items.filter((it) => (engine === 'webkit' && it.property === 'padding-inline' ? false : physical(it.property, dir).includes(prop)));
  const last = hit[hit.length - 1];
  return last ? [last.durMs, last.delayMs] : null;
}

describe('nav:earn-logical golden', () => {
  it('every golden fn is covered', () => {
    expect(new Set(golden.map((g) => g.fn))).toEqual(new Set(['list', 'started', 'reduced']));
  });

  it('the variant name and class are the ones the part registers', () => {
    expect(EARN_LOGICAL_VARIANT).toBe('earn-logical');
    expect(EARN_LOGICAL_CLASS).toBe('is-earn-logical');
    const part = JSON.parse(readFileSync(resolve(__dirname, 'part.json'), 'utf8')) as { variants: Record<string, { kind: string; visClass?: string }> };
    expect(part.variants[EARN_LOGICAL_VARIANT]).toMatchObject({ kind: 'proposal', visClass: 'L' });
  });

  it('each rule declares the transition list the model runs', () => {
    const rows = golden.filter((g) => g.fn === 'list');
    expect(rows).toHaveLength(4);
    for (const g of rows) {
      const key = `${g.in.arm as string}/${g.in.rule as string}`;
      expect(list(RULES[key]), key).toEqual(g.out);
    }
  });

  it('the variant rules differ from the faithful ones only in the padding entries', () => {
    for (const rule of ['hero', 'base']) {
      const f = list(RULES[`faithful/${rule}`]).filter((i) => !i.property.startsWith('padding'));
      const v = list(RULES[`variant/${rule}`]).filter((i) => !i.property.startsWith('padding'));
      expect(v, rule).toEqual(f);
      const pad = list(RULES[`variant/${rule}`]).filter((i) => i.property.startsWith('padding'));
      expect(pad.map((i) => i.property)).toEqual(['padding-inline-start', 'padding-inline-end']);
      const fp = list(RULES[`faithful/${rule}`]).find((i) => i.property === 'padding-inline')!;
      for (const i of pad) expect(i).toEqual({ ...fp, property: i.property });
    }
  });

  it('the variant rules win the cascade over every faithful earn transition rule they replace', () => {
    for (const rule of ['hero', 'base']) {
      for (const f of ['faithful/hero', 'faithful/base']) expect(weight(RULES[`variant/${rule}`])).toBeGreaterThan(weight(RULES[f]));
    }
  });

  it('the variant rules sit inside the no-preference media block, so reduce keeps the original transition: none', () => {
    const open = css.indexOf('@media (prefers-reduced-motion: no-preference) {');
    const close = css.indexOf('\n  }\n', open);
    expect(open).toBeGreaterThan(0);
    for (const k of ['variant/hero', 'variant/base']) {
      const at = css.indexOf(`\n${RULES[k]} {`);
      expect(at, k).toBeGreaterThan(open);
      expect(at, k).toBeLessThan(close);
    }
    const reduce = css.slice(css.indexOf('@media (prefers-reduced-motion: reduce) {'));
    expect(/\.btn\.earn\s*\{[^}]*transition:\s*none/.test(reduce)).toBe(true);
  });

  it('reduced motion: nothing starts and the computed list is the faithful none list, both arms, engines and directions', () => {
    const rows = golden.filter((g) => g.fn === 'reduced');
    expect(rows).toHaveLength(16);
    for (const g of rows) {
      expect(g.out, JSON.stringify(g.in)).toEqual({ starts: [], computed: ['none', '0s', 'ease', '0s', 'normal'] });
    }
  });

  it('started sets, first-frame padding and padding timing match the model in both engines and directions', () => {
    const rows = golden.filter((g) => g.fn === 'started');
    expect(rows).toHaveLength(16);
    for (const g of rows) {
      const engine = g.in.engine as Eng;
      const dir = g.in.dir as string;
      const items = list(RULES[`${g.in.arm as string}/${g.in.rule as string}`]);
      const out = g.out as { starts: string[]; firstFramePadWide: number; firstFramePadNarrow: number; paddingLeftTiming: [number, number] | null };
      const set = started(engine, dir, items);
      expect(new Set(set), JSON.stringify(g.in)).toEqual(new Set(out.starts));
      const eased = set.includes('padding-left');
      expect(out.firstFramePadWide, JSON.stringify(g.in)).toBe(eased ? 24 : 0);
      expect(out.firstFramePadNarrow, JSON.stringify(g.in)).toBe(eased ? 16 : 0);
      expect(timing(engine, dir, items, 'padding-left'), JSON.stringify(g.in)).toEqual(out.paddingLeftTiming);
    }
  });

  it('the pinned claims: WebKit starts the padding for entry and exit only with the variant; Chromium is the same in both arms', () => {
    const get = (engine: string, arm: string, rule: string) =>
      golden.find((g) => g.fn === 'started' && g.in.engine === engine && g.in.dir === 'ltr' && g.in.arm === arm && g.in.rule === rule)!.out as { starts: string[] };
    for (const rule of ['hero', 'base']) {
      expect(get('webkit', 'faithful', rule).starts).toEqual(['max-width', 'opacity']);
      expect(get('webkit', 'variant', rule).starts).toEqual(['max-width', 'opacity', 'padding-right', 'padding-left']);
      expect(get('chromium', 'variant', rule)).toEqual(get('chromium', 'faithful', rule));
      expect(get('webkit', 'variant', rule)).toEqual(get('chromium', 'faithful', rule));
    }
  });
});
