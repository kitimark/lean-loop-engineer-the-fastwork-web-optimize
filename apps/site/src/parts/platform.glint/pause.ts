export interface SvgClock {
  pauseAnimations(): void;
  unpauseAnimations(): void;
  getCurrentTime(): number;
  setCurrentTime(seconds: number): void;
}

export const AWAY_RATIO = 0;

export interface PauseState {
  paused: boolean;
  off: number;
}

export type Act = 'none' | 'pause' | 'resume-seek';

export interface PauseOut {
  state: PauseState;
  act: Act;
  seekMs: number | null;
}

export function pauseStep({ state, ev, t, read }: { state: PauseState; ev: 'hide' | 'reveal'; t: number; read: number }): PauseOut {
  if (ev === 'hide') {
    return state.paused ? { state, act: 'none', seekMs: null } : { state: { paused: true, off: read - t }, act: 'pause', seekMs: null };
  }
  return state.paused ? { state: { paused: false, off: state.off }, act: 'resume-seek', seekMs: t + state.off } : { state, act: 'none', seekMs: null };
}

export const ticks = ({ paused, armed }: { paused: boolean; armed: boolean }): number => (paused ? 0 : armed ? 1 : 0);

export function createPause(svgs: () => readonly SvgClock[], now: () => number) {
  let states: PauseState[] = [];
  const run = (ev: 'hide' | 'reveal') => {
    const list = svgs();
    if (states.length !== list.length) states = list.map(() => ({ paused: false, off: 0 }));
    const t = now();
    list.forEach((svg, i) => {
      const out = pauseStep({ state: states[i]!, ev, t, read: ev === 'hide' ? svg.getCurrentTime() * 1000 : 0 });
      states[i] = out.state;
      if (out.act === 'pause') svg.pauseAnimations();
      else if (out.act === 'resume-seek') {
        svg.unpauseAnimations();
        svg.setCurrentTime(Math.max(0, out.seekMs! / 1000));
      }
    });
  };
  return {
    away: () => run('hide'),
    back: () => run('reveal'),
    ratio: (ratio: number) => run(ratio === AWAY_RATIO ? 'hide' : 'reveal'),
    get paused() {
      return states.some((s) => s.paused);
    },
  };
}
