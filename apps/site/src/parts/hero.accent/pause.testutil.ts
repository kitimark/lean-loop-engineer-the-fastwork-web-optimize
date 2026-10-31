/** Test doubles for the loop pause (test only): a fake Animation and a hand-driven IntersectionObserver. */
export class FakeAnim {
  playState: 'running' | 'paused' | 'idle' = 'running';
  log: string[] = [];
  constructor(
    public startTime: number | null,
    public infinite = true,
  ) {}
  get effect() {
    return { getTiming: () => ({ iterations: this.infinite ? Infinity : 1 }) };
  }
  pause() {
    this.playState = 'paused';
    this.log.push('pause');
  }
  play() {
    this.playState = 'running';
    this.log.push('play');
    this.startTime = 999;
  }
}

export function fakeIO() {
  const cbs: ((e: unknown[]) => void)[] = [];
  class IO {
    constructor(cb: (e: unknown[]) => void) {
      cbs.push(cb);
    }
    observe() {}
    disconnect() {}
  }
  const report = (target: unknown, hidden: boolean) =>
    cbs.forEach((cb) =>
      cb([{ target, isIntersecting: !hidden, intersectionRect: { width: hidden ? 0 : 10, height: hidden ? 0 : 10 }, intersectionRatio: hidden ? 0 : 1 }]),
    );
  return { IO: IO as unknown as typeof IntersectionObserver, report };
}
