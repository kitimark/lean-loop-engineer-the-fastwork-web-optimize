import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { installUnthrottle, UNTHROTTLE_ATTR, unthrottleCss } from './unthrottle';
import part from './part.json';

type Row = { fn: string; out: unknown };
const golden: Row[] = readFileSync(
  new URL('../../../../../packages/contracts/golden/parts/engine.scroll.unthrottle.jsonl', import.meta.url),
  'utf8',
)
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Row);
const row = (fn: string) => golden.find((r) => r.fn === fn)?.out;

describe('engine.scroll unthrottle', () => {
  it('writes the style text Lean generates', () => {
    expect(unthrottleCss()).toBe(row('css'));
  });

  it('installs the attributes Lean lists, and undoes its style and element', () => {
    const made: { tag: string; attrs: Record<string, string>; text: string; removed: boolean }[] = [];
    const node = (tag: string) => {
      const n = {
        tag,
        attrs: {} as Record<string, string>,
        text: '',
        removed: false,
        set textContent(s: string) {
          n.text = s;
        },
        setAttribute(k: string, v: string) {
          n.attrs[k] = v;
        },
        remove() {
          n.removed = true;
        },
      };
      made.push(n);
      return n;
    };
    const doc = {
      createElement: node,
      head: { appendChild: () => undefined },
      body: { appendChild: () => undefined },
    } as unknown as Document;
    const undo = installUnthrottle(doc);
    expect(made.map((m) => m.tag)).toEqual(['style', 'div']);
    expect(made[0].text).toBe(unthrottleCss());
    expect(made[1].attrs).toEqual(row('attrs'));
    expect(UNTHROTTLE_ATTR in (row('attrs') as object)).toBe(true);
    undo();
    expect(made.every((m) => m.removed)).toBe(true);
  });

  it('is an optimized variant; the diagnostic stays an ablation', () => {
    const v = part.variants as Record<string, { kind: string; diagnostic?: boolean }>;
    expect(v.unthrottle.kind).toBe('optimized');
    expect(v['throttle-lift'].diagnostic).toBe(true);
  });
});
