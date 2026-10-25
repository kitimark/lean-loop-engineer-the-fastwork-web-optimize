import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import { mountCommission, type Clock, type Env } from './driver';
import { cardLook, catchupPair, compact, planCatchup, planWrite } from './logic';
import { bands, inBand, SETTLE_EVENTS } from './window';

interface Ev {
  gate: boolean;
  rm: boolean;
  top: number;
  bottom: number;
  vh: number;
}

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
    onCompactChange: (f) => ((onCompact = f), () => undefined),
    observe: () => () => undefined,
    observeResize: () => () => undefined,
    lineBoxes: () => 1,
  };
  let cb: (() => void) | null = null;
  let onCompact: (() => void) | null = null;
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
  const media = (gate: boolean) => {
    cur = { ...cur, gate };
    onCompact?.();
    out.push(snap());
  };
  const body = (e: Ev) => {
    cur = e;
    cb!();
    out.push(snap());
  };
  return { out, media, body, off };
}

interface Tick {
  media: boolean | null;
  body: Ev | null;
  c1000: boolean;
}

const runTicks = (ticks: Tick[], bandGate: boolean) => {
  const r = rig([ticks[0]!.body!], bandGate);
  const per = [r.out[0]!];
  for (const t of ticks.slice(1)) {
    if (t.media !== null) r.media(t.media);
    if (t.body !== null) r.body(t.body);
    per.push(r.out[r.out.length - 1]!);
  }
  r.off();
  return per.map((s, k) => ({ ...s, look: cardLook(ticks[k]!.c1000, s.inl.enter, s.inl.shrink) }));
};

const run = (events: Ev[], bandGate: boolean) => {
  const r = rig(events, bandGate);
  const first = r.out.length;
  void first;
  r.off();
  return r.out;
};

goldenConformance('commission-gate', {
  planWrite: (i) => planWrite(i.gated as boolean, i.moving as boolean),
  planCatchup: (i) => planCatchup(i.gated as boolean),
  catchupPair: (i) => catchupPair({ n: i.n as number, r: i.r as number }),
  cardLook: (i) => cardLook(i.c1000 as boolean, i.enter as number, i.shrink as number),
  trace: (i) => {
    const events = i.events as Ev[];
    const v = run(events, true);
    const o = run(events, false);
    return {
      variantInl: v.map((s) => s.inl),
      variantWrites: v.map((s) => s.writes),
      origInl: o.map((s) => s.inl),
      origWrites: o.map((s) => s.writes),
    };
  },
  settleEvents: () => SETTLE_EVENTS,
  layoutRow: (i) => ({
    compact: compact(i.width as number, i.deviceWidth as number, i.touch as boolean),
    ...bands(i.cardTop as number, i.bottom as number, i.vh as number),
  }),
  inBand: (i) => inBand(bands(i.cardTop as number, i.bottom as number, i.vh as number), i.y as number),
  scrollTrace: (i) => {
    const ys = i.ys as number[];
    const events: Ev[] = ys.map((y) => ({ gate: true, rm: false, top: (i.cardTop as number) - y, bottom: (i.bottom as number) - y, vh: i.vh as number }));
    const v = run(events, true);
    const o = run(events, false);
    const b = bands(i.cardTop as number, i.bottom as number, i.vh as number);
    return {
      variantWrites: v.map((s) => s.writes),
      origWrites: o.map((s) => s.writes),
      skipped: v.map((s, k) => s.writes === (k === 0 ? 0 : v[k - 1]!.writes)),
      band: ys.map((y) => inBand(b, y)),
    };
  },
  mergedTrace: (i) => {
    const ticks = i.ticks as Tick[];
    const v = runTicks(ticks, true);
    const o = runTicks(ticks, false);
    return {
      variantInl: v.map((s) => s.inl),
      variantWrites: v.map((s) => s.writes),
      origInl: o.map((s) => s.inl),
      origWrites: o.map((s) => s.writes),
      variantLook: v.map((s) => s.look),
      origLook: o.map((s) => s.look),
    };
  },
});

describe('commission variant band-gate (Lean CommissionOpt)', () => {
  const ev = (gate: boolean, bottom: number): Ev => ({ gate, rm: false, top: 0, bottom, vh: 1000 });
  it('outside the band it is the faithful driver (two writes per event)', () => {
    const evs = [ev(false, 850), ev(false, 600), ev(false, 500)];
    expect(run(evs, true)).toEqual(run(evs, false));
  });
  it('in the band, while the follower moves: no write, the CSS pair is held (moving_run)', () => {
    const s = run([ev(true, 850), ev(true, 600), ev(true, 500)], true);
    expect(s.map((x) => x.writes)).toEqual([0, 0, 0]);
    expect(s[2]!.inl).toEqual({ enter: 1, shrink: 1 });
  });
  it('in the band, once the follower settles: the faithful pair is written (inl_settled)', () => {
    const evs = Array.from({ length: 80 }, () => ev(true, 900));
    const v = run(evs, true);
    const o = run(evs, false);
    expect(v[79]!.inl).toEqual(o[79]!.inl);
    expect(v[79]!.writes).toBeLessThan(o[79]!.writes);
    expect(v[10]!.writes).toBe(0);
  });
  it('leaving the band writes the faithful pair on the very next event (exit_catchup)', () => {
    const evs = [ev(true, 850), ev(true, 600), ev(false, 600), ev(false, 500)];
    const v = run(evs, true);
    const o = run(evs, false);
    expect(v[2]!.inl).toEqual(o[2]!.inl);
    expect(v[2]!.writes).toBe(2);
    expect(v[3]!.inl).toEqual(o[3]!.inl);
    expect(o[3]!.writes).toBe(8);
  });
  it('a change of the band without a body writes the pair and only that (media_catchup)', () => {
    const evs = [ev(true, 850), ev(true, 600)];
    const r = rig(evs, true);
    const o = rig(evs, false);
    r.media(false);
    o.media(false);
    r.off();
    o.off();
    expect(r.out[2]!.inl).toEqual(o.out[1]!.inl);
    expect(r.out[2]!.writes).toBe(2);
    expect(o.out[2]!.writes).toBe(o.out[1]!.writes);
  });
  it('a change into the band writes nothing', () => {
    const r = rig([ev(false, 850)], true);
    const before = r.out[0]!.writes;
    r.media(true);
    r.off();
    expect(r.out[1]!.writes).toBe(before);
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

describe('commission band-gate window (Lean CommissionOptWindow.skip_in_band)', () => {
  const lines = readFileSync(resolve(__dirname, '../../../../../packages/contracts/golden/parts/commission-gate.jsonl'), 'utf8')
    .split('\n')
    .filter((l) => l.trim())
    .map((l) => JSON.parse(l) as { fn: string; in: Record<string, unknown>; out: Record<string, boolean[]> });
  const traces = lines.filter((l) => l.fn === 'scrollTrace');
  it('the golden holds a scroll over each measured phone rect', () => {
    expect(traces.length).toBeGreaterThanOrEqual(2);
  });
  it.each(traces.map((t, n) => [n, t] as const))('trace %i: a skipped event has a band event among the last SETTLE_EVENTS', (_n, t) => {
    const { skipped, band } = t.out as { skipped: boolean[]; band: boolean[] };
    expect(skipped.some(Boolean)).toBe(true);
    skipped.forEach((s, k) => {
      if (!s) return;
      const from = Math.max(0, k - (SETTLE_EVENTS - 1));
      expect(band.slice(from, k + 1).some(Boolean)).toBe(true);
    });
  });
  it('the compact rows of the layout table are the c1000 band of the gate probes', () => {
    const rows = lines.filter((l) => l.fn === 'layoutRow');
    expect(rows.length).toBe(124);
    expect(rows.filter((r) => (r.out as unknown as { compact: boolean }).compact).length).toBe(83);
  });
});
