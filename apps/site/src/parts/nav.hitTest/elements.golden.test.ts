import { expect } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import { ALLOW_SELECTOR, EXCLUDE_SELECTOR, INCLUDE_SELECTOR, isOnDark, SHRINKING_SELECTOR } from './logic';
import { probeElements, probeFaithful, type ProbeEnv } from './probe';

interface WireBox {
  insideNav: boolean;
  src: 'root' | 'auto' | 'none';
  allow: boolean;
  inExclude: boolean;
  inInclude: boolean;
  inShrinking: boolean;
}

interface FakeEl {
  box: WireBox;
  closest(sel: string): FakeEl | null;
}

function el(box: WireBox): FakeEl {
  const flag: Record<string, boolean> = {
    [ALLOW_SELECTOR]: box.allow,
    [EXCLUDE_SELECTOR]: box.inExclude,
    [INCLUDE_SELECTOR]: box.inInclude,
    [SHRINKING_SELECTOR]: box.inShrinking,
  };
  const self: FakeEl = { box, closest: (sel) => (flag[sel] ? self : null) };
  return self;
}

const HTML = el({ insideNav: false, src: 'auto', allow: false, inExclude: false, inInclude: false, inShrinking: false });

function scene(rootHit: boolean, stack: WireBox[]) {
  const els = stack.map(el);
  const nav = {
    style: { pointerEvents: '' },
    classList: { contains: () => false },
    dataset: {},
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 390, height: 64 }),
    contains: (e: FakeEl) => e.box.insideNav,
  };
  const root = () => nav.style.pointerEvents !== 'none' && rootHit;
  const used = (b: WireBox) => (b.src === 'root' ? root() : b.src === 'auto');
  const hits = () => els.filter((e) => used(e.box));
  const env: ProbeEnv = {
    doc: {
      elementFromPoint: () => (hits()[0] ?? null) as unknown as Element,
      elementsFromPoint: () => [...hits(), HTML] as unknown as Element[],
      querySelector: () => null,
    },
    win: { getComputedStyle: (() => ({})) as unknown as Window['getComputedStyle'], innerHeight: 844 },
  };
  return { nav: nav as unknown as HTMLElement, env, style: nav.style };
}

goldenConformance('nav.hitTest.elements', {
  probes: (i) => {
    const s = scene(i.rootHit, i.stack);
    const faithful = probeFaithful(s.nav, s.env);
    expect(s.style.pointerEvents).toBe('');
    const elements = probeElements(s.nav, s.env);
    return {
      premises: premises(i.stack),
      faithful,
      elements,
      onDarkFaithful: isOnDark(faithful, i.morph),
      onDarkElements: isOnDark(elements, i.morph),
    };
  },
});

function premises(stack: WireBox[]): boolean {
  return stack.every((b) =>
    b.insideNav ? (!b.allow || b.src !== 'root') && (b.src !== 'auto' || b.allow) : b.src !== 'root',
  );
}
