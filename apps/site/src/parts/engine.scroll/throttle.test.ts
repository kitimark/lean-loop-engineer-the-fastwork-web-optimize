import { describe, expect, it } from 'vitest';
import { installThrottleLift, THROTTLE_LIFT_ATTR, throttleLiftCss } from './throttle';
import part from './part.json';

describe('engine.scroll throttle-lift', () => {
  it('animates a registered property with the root scroll timeline, timeline set after the shorthand', () => {
    const css = throttleLiftCss();
    expect(css).toContain('@property --fw-tl');
    expect(css).toContain('inherits: false');
    expect(css.indexOf('animation:')).toBeLessThan(css.indexOf('animation-timeline: scroll(root block)'));
    expect(css.indexOf('animation-duration: auto')).toBeLessThan(css.indexOf('animation-timeline'));
  });

  it('keeps the element out of sight and out of layout flow', () => {
    const css = throttleLiftCss();
    for (const d of ['position: fixed', 'opacity: 0', 'pointer-events: none']) expect(css).toContain(d);
  });

  it('is a diagnostic ablation, never a preset candidate', () => {
    const v = (part.variants as Record<string, { kind: string; diagnostic?: boolean }>)['throttle-lift'];
    expect(v.kind).toBe('ablation');
    expect(v.diagnostic).toBe(true);
    expect(part.variants.faithful.kind).toBe('faithful');
  });

  it('installs and undoes its style and element', () => {
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
    const undo = installThrottleLift(doc);
    expect(made.map((m) => m.tag)).toEqual(['style', 'div']);
    expect(made[0].text).toBe(throttleLiftCss());
    expect(made[1].attrs[THROTTLE_LIFT_ATTR]).toBe('');
    undo();
    expect(made.every((m) => m.removed)).toBe(true);
  });
});
