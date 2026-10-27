import type { EffectSink } from './driver';

export type TimedSink = EffectSink & { take(from: number, to: number, start: number): boolean };

let current: TimedSink | null = null;

/** Where the timed geometry (built by `morph.geom`, which owns that DOM) meets the tween driver; `take` is false while none is set. */
export const timedBus = {
  set(sink: TimedSink | null): void {
    current = sink;
  },
  sink: {
    take: (from, to, start) => current?.take(from, to, start) ?? false,
    push: (from, to, start) => current?.push(from, to, start),
    settle: (m) => current?.settle(m),
    dispose: () => current?.dispose(),
  } satisfies TimedSink as TimedSink,
};
