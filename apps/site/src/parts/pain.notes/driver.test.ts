import { describe, expect, it } from 'vitest';
import { createNotesDriver, type NotesEnv } from './driver';
import type { Note } from './logic';

function fakeEnv(over: Partial<NotesEnv> = {}) {
  const log: string[] = [];
  let interval: (() => void) | null = null;
  let frame: (() => void) | null = null;
  let last: { base: Note[]; extras: Note[]; dragging: string | null } = { base: [], extras: [], dragging: null };
  const env: NotesEnv = {
    stageRect: () => ({ top: 0, width: 780, height: 528 }),
    copyRect: () => ({ top: -200, height: 100, width: 100 }),
    cardTop: () => null,
    innerHeight: () => 900,
    narrow: () => false,
    reduced: () => false,
    c860: () => false,
    interval: (_ms, cb) => {
      interval = cb;
      log.push('interval+');
      return () => {
        interval = null;
        log.push('interval-');
      };
    },
    frame: (cb) => {
      frame = cb;
      return () => {
        frame = null;
      };
    },
    commit: (v) => {
      last = v;
    },
    writeNote: (id, l, t, z) => log.push(`write ${id} ${l.toFixed(2)} ${t.toFixed(2)} ${z}`),
    ...over,
  };
  return {
    env,
    log,
    runFrame: () => frame?.(),
    runInterval: () => interval?.(),
    view: () => last,
  };
}

describe('pain.notes driver', () => {
  it('lays out the five base notes on the first frame', () => {
    const f = fakeEnv();
    const d = createNotesDriver(f.env, 1);
    d.start();
    expect(f.view().base.length).toBe(0);
    f.runFrame();
    expect(f.view().base.length).toBe(5);
  });
  it('lays out the eleven narrow notes at <= 860 px, and adds no extras there', () => {
    const f = fakeEnv({ narrow: () => true, stageRect: () => ({ top: 0, width: 390, height: 800 }) });
    const d = createNotesDriver(f.env, 1);
    d.start();
    f.runFrame();
    expect(f.view().base.length).toBe(11);
    d.intersect(true, 1);
    d.tick();
    expect(f.view().extras.length).toBe(0);
  });
  it('a wide canvas (>= 1100 px) uses the scored placement and still stops at 12', () => {
    const f = fakeEnv({ stageRect: () => ({ top: 0, width: 1440, height: 900 }) });
    const d = createNotesDriver(f.env, 3);
    d.start();
    f.runFrame();
    d.intersect(true, 1);
    for (let i = 0; i < 15; i++) f.runInterval();
    expect(f.view().extras.length).toBe(12);
  });
  it('does not lay out a hidden stage (width 0)', () => {
    const f = fakeEnv({ stageRect: () => ({ top: 0, width: 0, height: 0 }) });
    const d = createNotesDriver(f.env, 1);
    d.start();
    f.runFrame();
    expect(f.view().base.length).toBe(0);
  });
  it('arms the 3 s interval while visible, adds up to 12 extras, then holds', () => {
    const f = fakeEnv();
    const d = createNotesDriver(f.env, 5);
    d.start();
    f.runFrame();
    d.intersect(true, 0.5);
    expect(d.model().armed).toBe(true);
    for (let i = 0; i < 20; i++) f.runInterval();
    expect(f.view().extras.length).toBe(12);
    expect(new Set(f.view().extras.map((n) => n.id)).size).toBe(12);
  });
  it('visibility below 12 % disarms and clears the extras', () => {
    const f = fakeEnv();
    const d = createNotesDriver(f.env, 5);
    d.start();
    f.runFrame();
    d.intersect(true, 0.5);
    f.runInterval();
    f.runInterval();
    expect(f.view().extras.length).toBe(2);
    d.intersect(true, 0.1);
    expect(d.model().armed).toBe(false);
    expect(f.view().extras.length).toBe(0);
  });
  it('the commission card coming up clears the extras on scroll and on the tick', () => {
    let card: number | null = null;
    const f = fakeEnv({ cardTop: () => card });
    const d = createNotesDriver(f.env, 5);
    d.start();
    f.runFrame();
    d.intersect(true, 1);
    f.runInterval();
    expect(f.view().extras.length).toBe(1);
    card = 800;
    d.onScroll();
    expect(f.view().extras.length).toBe(0);
    d.tick();
    expect(f.view().extras.length).toBe(0);
  });
  it('narrow and reduced motion add nothing', () => {
    for (const over of [{ narrow: () => true }, { reduced: () => true }]) {
      const f = fakeEnv(over);
      const d = createNotesDriver(f.env, 5);
      d.intersect(true, 1);
      d.tick();
      expect(f.view().extras.length).toBe(0);
    }
  });
  it('drag: gate, clamp inside the stage, z 40 stays, writes go to the element, state only at start and end', () => {
    const f = fakeEnv();
    const d = createNotesDriver(f.env, 1);
    d.start();
    f.runFrame();
    expect(d.pointerDown('base-0', { pointerId: 1, clientX: 100, clientY: 100, button: 2, mouse: true })).toBe(false);
    expect(d.pointerDown('base-0', { pointerId: 1, clientX: 100, clientY: 100, button: 0, mouse: true })).toBe(true);
    expect(f.view().dragging).toBe('base-0');
    d.pointerMove({ clientX: -5000, clientY: -5000 });
    expect(f.log.some((l) => l.startsWith('write base-0 0.00 0.00 40'))).toBe(true);
    d.pointerEnd();
    expect(f.view().dragging).toBeNull();
    expect(d.model().base[0]!.z).toBe(40);
  });
  it('drag is off under the touch/narrow condition', () => {
    const f = fakeEnv({ c860: () => true });
    const d = createNotesDriver(f.env, 1);
    d.start();
    f.runFrame();
    expect(d.pointerDown('base-0', { pointerId: 1, clientX: 0, clientY: 0, button: 0, mouse: false })).toBe(false);
  });
  it('arrow keys move by 1.5 % and stay inside the stage', () => {
    const f = fakeEnv();
    const d = createNotesDriver(f.env, 1);
    d.start();
    f.runFrame();
    const before = d.model().base[1]!.left;
    expect(d.key('base-1', 'ArrowRight')).toBe(true);
    expect(d.model().base[1]!.left).toBeCloseTo(before + 1.5, 9);
    expect(d.key('base-1', 'Enter')).toBe(false);
  });
  it('a tick while dragging does nothing', () => {
    const f = fakeEnv();
    const d = createNotesDriver(f.env, 1);
    d.start();
    f.runFrame();
    d.intersect(true, 1);
    d.pointerDown('base-0', { pointerId: 1, clientX: 0, clientY: 0, button: 0, mouse: true });
    d.tick();
    expect(f.view().extras.length).toBe(0);
  });
});
