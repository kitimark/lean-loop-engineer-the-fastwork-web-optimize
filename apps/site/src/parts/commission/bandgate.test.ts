import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import { mountCommission, type Clock, type Env } from './driver';
import { cardLook, planWrite } from './logic';

interface Ev {
  gate: boolean;
  rm: boolean;
  top: number;
  bottom: number;
  vh: number;
}

/** A driver on fake elements, one body per event (the first at mount, the others through the engine callback). */
function rig(events: Ev[], bandGate: boolean) {
  const props = new Map<string, string>();
  let writes = 0;
  let cur = events[0]!;
  const section = {
    style: {
      setProperty: (n: string, v: string) => {
        if (n.startsWith('--commission-')) {
          writes += 1;
          props.set(n, v);
        }
      },
      height: '',
    },
    classList: { toggle: () => undefined },
    setAttribute: () => undefined,
    toggleAttribute: () => false,
    getAttribute: () => null,
    getBoundingClientRect: () => ({ top: 0, bottom: cur.bottom }),
  };
  const stub = { style: { setProperty: () => undefined, height: '' }, classList: { toggle: () => undefined }, setAttribute: () => undefined, toggleAttribute: () => false, getAttribute: () => null };
  const clock: Clock = { subscribe: () => () => undefined, interval: () => () => undefined };
  const env: Env = {
    vh: () => cur.vh,
    reduced: () => cur.rm,
    compact: () => cur.gate,
    onReducedChange: () => () => undefined,
    observe: () => () => undefined,
    observeResize: () => () => undefined,
    lineBoxes: () => 1,
  };
  let cb: (() => void) | null = null;
  const off = mountCommission(
    {
      els: { section, card: { getBoundingClientRect: () => ({ top: cur.top, bottom: 0 }) }, runway: stub, header: {}, title: stub, muted: {}, underline: stub },
      classes: { entering: 'entering', shrinking: 'shrinking', titleWrapped: 'wrapped', enter: 'enter', idle: 'idle' },
      engine: { register: (_id, _o, f) => ((cb = () => void f({ vh: cur.vh })), () => undefined) },
      clock,
      env,
    },
    { bandGate },
  );
  const snap = () => ({
    inl: { enter: Number(props.get('--commission-enter-shrink') ?? 1), shrink: Number(props.get('--commission-shrink') ?? 1) },
    writes,
  });
  const out = [snap()];
  for (const e of events.slice(1)) {
    cur = e;
    cb!();
    out.push(snap());
  }
  off();
  return out;
}

goldenConformance('commission-gate', {
  planWrite: (i) => planWrite(i.gated as boolean),
  cardLook: (i) => cardLook(i.c1000 as boolean, i.enter as number, i.shrink as number),
  trace: (i) => {
    const events = i.events as Ev[];
    const v = rig(events, true);
    const o = rig(events, false);
    return {
      variantInl: v.map((s) => s.inl),
      variantWrites: v.map((s) => s.writes),
      origInl: o.map((s) => s.inl),
      origWrites: o.map((s) => s.writes),
    };
  },
});

describe('commission variant band-gate (Lean CommissionOpt)', () => {
  const ev = (gate: boolean, bottom: number): Ev => ({ gate, rm: false, top: 0, bottom, vh: 1000 });
  it('outside the band it is the faithful driver (two writes per event)', () => {
    const run = [ev(false, 850), ev(false, 600), ev(false, 500)];
    expect(rig(run, true)).toEqual(rig(run, false));
  });
  it('in the band: no write, the CSS pair is held (gated_run)', () => {
    const s = rig([ev(true, 850), ev(true, 600), ev(true, 500)], true);
    expect(s.map((x) => x.writes)).toEqual([0, 0, 0]);
    expect(s[2]!.inl).toEqual({ enter: 1, shrink: 1 });
  });
  it('leaving the band writes the faithful pair on the very next event (exit_catchup)', () => {
    const run = [ev(true, 850), ev(true, 600), ev(false, 600), ev(false, 500)];
    const v = rig(run, true);
    const o = rig(run, false);
    expect(v[2]!.inl).toEqual(o[2]!.inl);
    expect(v[2]!.writes).toBe(2);
    expect(v[3]!.inl).toEqual(o[3]!.inl);
    expect(o[3]!.writes).toBe(8);
  });
});

describe('commission.module.css premise of the variant', () => {
  const css = readFileSync(resolve(__dirname, 'commission.module.css'), 'utf8');
  const lines = css.split('\n');
  it('the two properties are read only by the shrink scale (line 9), the radius (48) and no other rule', () => {
    const readers = lines.flatMap((l, i) => (/var\(--commission-(enter-)?shrink[,)]/.test(l) ? [i + 1] : []));
    expect(readers).toEqual([9, 48]);
  });
  it('--commission-shrink-scale and -radius are read only by the card (lines 48, 51)', () => {
    const readers = lines.flatMap((l, i) => (/var\(--commission-shrink-(scale|radius)/.test(l) ? [i + 1] : []));
    expect(readers).toEqual([48, 51]);
  });
  it('the c1000 band pins scale 1 and radius 0 and removes the card transform and radius', () => {
    const at = lines.findIndex((l) => /^\s*@media \(width<=1000px\), \(device-width<=500px\), \(hover: none\)/.test(l));
    expect(at + 1).toBe(436);
    const block = lines.slice(at, at + 18).join('\n');
    expect(block).toMatch(/--commission-shrink-scale: 1;/);
    expect(block).toMatch(/--commission-shrink-radius: 0px;/);
    expect(block).toMatch(/border-radius: 0;/);
    expect(block).toMatch(/transform: none;/);
  });
  it('no other file of the part reads the properties', () => {
    for (const f of ['index.tsx', 'data.ts']) {
      expect(readFileSync(resolve(__dirname, f), 'utf8')).not.toMatch(/--commission-(enter-)?shrink/);
    }
  });
});
