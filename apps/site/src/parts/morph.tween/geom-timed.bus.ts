import type { EffectSink } from './driver';

export type TimedSink = EffectSink & { take(from: number, to: number, start: number): boolean };

let current: TimedSink | null = null;

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
