// Renders one artwork read from the snapshot by scripts/svg-extract.mjs (src/svg.gen.json, never committed).
import { createElement, type SVGProps } from 'react';
import gen from './svg.gen.json';

export interface Art {
  svg: Record<string, string>;
  kids: Array<{ tag: string; attrs: Record<string, string> }>;
}

type Single = 'nav.globe' | 'icon.bell' | 'icon.calendar' | 'platform.star' | 'platform.pin' | 'platform.shield' | 'brand.mark' | 'commission.chevron' | 'hero.cue' | 'drawer.close';
type Frames = 'commission.underline' | 'commission.zero';

const store = gen.art as unknown as Record<Single, Art> & Record<Frames, Art[]>;

/** The artwork named `name`. */
export const art = (name: Single): Art => store[name];
/** The boil frames of the artwork named `name`, in the original's order. */
export const frames = (name: Frames): readonly Art[] => store[name];

const prop = (k: string) => (k.startsWith('aria-') || k === 'pathLength' || k === 'preserveAspectRatio' ? k : k.replace(/-([a-z])/g, (_, c: string) => c.toUpperCase()));

function props(a: Record<string, string>) {
  const o: Record<string, string> = {};
  for (const [k, v] of Object.entries(a)) o[prop(k)] = v;
  return o;
}

/** An `<svg>` with the original's own attributes and shapes; `rest` (className, ref, ...) is applied over them. */
export function GenSvg({ art: a, ...rest }: { art: Art } & SVGProps<SVGSVGElement>) {
  return (
    <svg {...props(a.svg)} {...rest}>
      {a.kids.map((k, i) => createElement(k.tag, { key: i, ...props(k.attrs) }))}
    </svg>
  );
}
