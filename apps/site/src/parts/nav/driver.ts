import { earn, pastHero, readyChange, readyInit, stuck, view, READY_DELAY_MS, type Sticky, type View } from './logic';

export interface NavEnv {
  /** `prefers-reduced-motion: reduce`. */
  reduced(): boolean;
  /** `(max-width: 600px)`. */
  narrow(): boolean;
  /** The hero track rect (top, height), or null when there is none. */
  hero(): { top: number; height: number } | null;
  /** `window.innerHeight` (N2:13013). */
  innerHeight(): number;
  /** Measurements of the profile sticky item (N2:12921-12935). */
  sticky(): Sticky;
  /** The hero carries `is-ring-splash-done`. */
  splashDone(): boolean;
  /** The morph value the tween published (0 when none). */
  morph(): number;
  /** Write the owned classes and the earn attributes; called only when something changed. */
  apply(v: View, e: { tabOff: boolean; ariaHidden: boolean }): void;
  /** One-shot timer; returns its cancel. */
  after(ms: number, cb: () => void): () => void;
}

/**
 * The nav's chrome state (N2:12897-13018): past-the-hero, profile-sticky, chrome-ready, locale-open, and the morph value
 * read from the tween. Decisions are the pure functions in logic.ts (Lean `Nav`); this file only wires them to the
 * environment. `measure()` is the scroll callback: reads first, the returned writer commits. Nothing here runs per frame
 * apart from that callback; class writes happen only on change.
 */
export function createNavDriver(env: NavEnv) {
  let past = false;
  let isStuck = false;
  let ready = false;
  let localeOpen = false;
  let cancelTimer: (() => void) | null = null;
  let last = '';

  const render = () => {
    const m = env.morph();
    const v = view({ past, ready, localeOpen, hit: false, stuck: isStuck, m });
    const e = earn({ heroPill: v.heroPill, m });
    // onDark is nav.hitTest's: it is left out of the change key and never written here
    const key = `${+v.heroPill}${+v.ready}${+v.morphing}${+v.expanded}${+v.localeOpen}${+v.scrollHidden}${+e.tabOff}${+e.ariaHidden}`;
    if (key === last) return;
    last = key;
    env.apply(v, e);
  };

  const readState = () => {
    const h = env.hero();
    return {
      stuck: stuck(env.sticky()),
      past: pastHero({ present: h !== null, reduced: env.reduced(), top: h?.top ?? 0, height: h?.height ?? 0, vh: env.innerHeight() }),
    };
  };

  const setReady = () => {
    ready = true;
    cancelTimer?.();
    cancelTimer = null;
    render();
  };

  return {
    /** Mount (N2:12996-13018): chrome-ready rule, then the first measurement. */
    mount() {
      if (readyInit({ reduced: env.reduced(), phone: env.narrow() })) setReady();
      else cancelTimer = env.after(READY_DELAY_MS, setReady);
      const s = readState();
      past = s.past;
      isStuck = s.stuck;
      last = '';
      render();
    },
    /** The scroll-engine callback: reads now, returns the writer (or nothing when the state did not change). */
    measure(): (() => void) | undefined {
      const s = readState();
      if (s.past === past && s.stuck === isStuck) return undefined;
      return () => {
        past = s.past;
        isStuck = s.stuck;
        render();
      };
    },
    /** A media query changed (N2:12998-13004 `m`). */
    queryChanged() {
      const r = readyChange({ ready, reduced: env.reduced(), phone: env.narrow(), splash: env.splashDone() });
      if (r && !ready) setReady();
    },
    /** The tween published a new morph value. */
    morphChanged: render,
    /** The language menu opened or closed (N2:12771). */
    setLocaleOpen(open: boolean) {
      if (open === localeOpen) return;
      localeOpen = open;
      render();
    },
    dispose() {
      cancelTimer?.();
      cancelTimer = null;
    },
  };
}

export type NavDriver = ReturnType<typeof createNavDriver>;
