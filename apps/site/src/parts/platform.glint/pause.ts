/**
 * `platform.glint:offscreen-pause`: pause the SMIL clock of a dash svg while the stage is away and seek it from the
 * document clock on return, so the glint keeps the uninterrupted phase. Spec and proofs:
 * lean/Fw/Parts/PlatformGlintPause.lean (`P.step`, `same_run`, `visible_same_phase`, `variant_no_ticks_away`).
 * Golden vectors: packages/contracts/golden/parts/platform-glint-pause.jsonl.
 */

/** The four svg calls the variant uses (WebKit SVGSVGElement.cpp:551-593). Times in seconds as the DOM has them. */
export interface SvgClock {
  pauseAnimations(): void;
  unpauseAnimations(): void;
  getCurrentTime(): number;
  setCurrentTime(seconds: number): void;
}

/** The observer ratio that counts as away: not intersecting. */
export const AWAY_RATIO = 0;

/** Driver state for one svg: paused, and the offset `clock - document time` (ms) stored at the pause. */
export interface PauseState {
  paused: boolean;
  off: number;
}

export type Act = 'none' | 'pause' | 'resume-seek';

export interface PauseOut {
  state: PauseState;
  act: Act;
  /** target of `setCurrentTime` in ms on `resume-seek` */
  seekMs: number | null;
}

/**
 * One report at document time `t` ms; `read` is the svg clock in ms (read only on hide).
 * Hide while running: store `read - t`, pause. Reveal while paused: unpause, then seek to `t + off`. A repeat does nothing.
 */
export function pauseStep({ state, ev, t, read }: { state: PauseState; ev: 'hide' | 'reveal'; t: number; read: number }): PauseOut {
  if (ev === 'hide') {
    return state.paused ? { state, act: 'none', seekMs: null } : { state: { paused: true, off: read - t }, act: 'pause', seekMs: null };
  }
  return state.paused ? { state: { paused: false, off: state.off }, act: 'resume-seek', seekMs: t + state.off } : { state, act: 'none', seekMs: null };
}

/** SMIL fires its timer once per rendering update at most, and not at all while paused or with nothing scheduled. */
export const ticks = ({ paused, armed }: { paused: boolean; armed: boolean }): number => (paused ? 0 : armed ? 1 : 0);

/**
 * The glue: one `PauseState` per svg. `away()` and `back()` are called from the observer callback (ratio 0 / ratio above 0)
 * before the glint driver sees the ratio, so the clock runs again before the glint can play. Glue only; the decision is `pauseStep`.
 */
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
    /** the observer's report: `ratio` is 0 when not intersecting */
    ratio: (ratio: number) => run(ratio === AWAY_RATIO ? 'hide' : 'reveal'),
    get paused() {
      return states.some((s) => s.paused);
    },
  };
}
