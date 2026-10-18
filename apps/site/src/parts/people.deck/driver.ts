import type { MotionClock } from '../../engine/clock';
import { after } from '../people/shared';
import {
  DEBOUNCE_MS,
  fe,
  fit,
  gotoTop,
  nearest,
  pe,
  progress,
  ranges,
  settled,
  SNAP_ORIGIN,
  SNAP_SCALE,
  SNAP_OFFSET,
  step,
  tgt,
} from './logic';

/** Narrow views of the DOM the driver reads and writes (the real elements in the part, fakes in tests). */
export interface Box {
  getBoundingClientRect(): { top: number; left: number };
  offsetHeight: number;
  clientWidth: number;
  offsetLeft: number;
  offsetWidth: number;
  scrollLeft: number;
  style: { height: string; transform: string; transformOrigin: string; setProperty(name: string, value: string): void };
  scrollTo(opts: { left: number; behavior: 'auto' | 'smooth' }): void;
  querySelector(sel: string): Box | null;
  querySelectorAll(sel: string): ArrayLike<Box & { dataset: { profession?: string } }>;
}

export interface DeckEnv {
  showcase: Box; // section#profile-showcase
  sticky: Box; // the sticky child
  chrome: Box; // row of tabs and deck
  tabs: Box; // tablist
  deck: Box; // the shells
  reduced(): boolean;
  /** the 860 combo (touch layout) */
  mobileMatches(): boolean;
  /** (min-width: 861px) */
  wideMatches(): boolean;
  vh(): number;
  vw(): number;
  scrollY(): number;
  scrollTo(top: number): void;
  /** `scrollend` on the deck (N2:10981) */
  onDeckScrollEnd(fn: () => void): () => void;
  /** one `scrollend` on the window (N2:10832) */
  onWindowScrollEnd(fn: () => void): () => void;
  ids: readonly string[];
  getActive(): string;
  setActive(id: string): void;
  setRailIn(on: boolean): void;
  setMobile(on: boolean): void;
  setDragging(on: boolean): void;
}

/**
 * The profile showcase driver (N2:10751-10990): on wide viewports the showcase section is as tall as its sticky child plus
 * the scroll ranges; each frame it reads the section's top, derives the shell's target scale, offset and origin, lerps three
 * values (rate 0.2, snap 0.0008 / 0.4 / 0.15) and writes `--profile-scale` on the sticky child and a transform on the active
 * shell; it picks the profession from the progress through the profession range. On the touch layout it keeps the tab rail and
 * the shell row in step. All maths is `logic.ts` (Lean `Fw.Parts.PeopleDeck`).
 */
export function createDeckDriver(env: DeckEnv, clock: MotionClock, opts: { activeClass: string }) {
  const activeSel = `.${opts.activeClass}`;
  let scale = 1.22; // `r`
  let offset = 0; // `i`
  let origin = 50; // `l`
  let mobile = env.mobileMatches(); // `T`
  let programmatic = false; // `E`: a tab click is scrolling the page
  let snapping = false; // `O`: the deck is being centred by script
  let cancelFrame: (() => void) | null = null;
  let debounce: (() => void) | null = null;
  let debounceFrame: (() => void) | null = null;
  let drag: { id: number; x: number; left: number; moved: boolean } | null = null;
  let disposed = false;

  const useScroll = () => !env.reduced() && !mobile && env.wideMatches();
  const r = () => ranges({ vh: env.vh(), n: env.ids.length });
  const activeShell = () => env.deck.querySelector(activeSel);

  function setHeight() {
    if (!useScroll()) {
      env.showcase.style.height = '';
      return;
    }
    env.showcase.style.height = `${env.sticky.offsetHeight + r().total}px`;
  }

  function reset() {
    env.showcase.style.height = '';
    env.sticky.style.setProperty('--profile-scale', '1');
    const s = activeShell();
    if (s) {
      s.style.transform = '';
      s.style.transformOrigin = '';
    }
    env.setRailIn(true);
  }

  function frame() {
    cancelFrame?.();
    cancelFrame = null;
    mobile = env.mobileMatches();
    env.setMobile(mobile);
    setHeight();
    if (!useScroll()) {
      reset();
      return;
    }
    const { shrink, prof, total } = r();
    const y = progress({ top: env.showcase.getBoundingClientRect().top, total });
    const chromeW = env.chrome.clientWidth;
    const b = fit({ vw: env.vw(), deckW: chromeW });
    const shell = activeShell();
    const left = shell?.offsetLeft ?? 248;
    const width = shell?.offsetWidth ?? Math.max(1, chromeW - 248);
    const delta = fe({ deckW: chromeW, left, width, s: b, o: 50 });
    const t = tgt({ y, shrink, prof, fit: b, delta });
    scale = step({ snap: SNAP_SCALE, v: scale, t: t.scale });
    offset = step({ snap: SNAP_OFFSET, v: offset, t: t.offset });
    origin = step({ snap: SNAP_ORIGIN, v: origin, t: t.origin });
    const a = settled({ snap: SNAP_SCALE, v: scale, t: t.scale });
    const j = settled({ snap: SNAP_OFFSET, v: offset, t: t.offset });
    const m = settled({ snap: SNAP_ORIGIN, v: origin, t: t.origin });
    env.sticky.style.setProperty('--profile-scale', scale.toFixed(3));
    if (shell) {
      if (Math.abs(scale - 1) < SNAP_SCALE && Math.abs(offset) < SNAP_OFFSET) {
        shell.style.transform = '';
        shell.style.transformOrigin = '';
      } else {
        shell.style.transformOrigin = `${origin.toFixed(2)}% 0`;
        shell.style.transform = `translate3d(${offset.toFixed(2)}px, 0, 0) scale(${scale})`;
      }
    }
    env.setRailIn(t.railIn);
    if (!programmatic) {
      const cur = Math.max(0, env.ids.indexOf(env.getActive()));
      const pick = t.railIn ? pe({ cnt: env.ids.length, k: t.k, cur }) : 0;
      const id = env.ids[pick];
      if (id !== undefined && id !== env.getActive()) env.setActive(id);
    }
    if (!(a && j && m)) request();
  }

  function request() {
    if (disposed) return;
    cancelFrame ??= clock.subscribe(frame, { own: true });
  }

  /** Keep the tab and shell rails centred on the active profession (N2:10769-10786 `he`). */
  function centre(id: string, snapDeck: boolean) {
    queueMicrotask(() => {
      if (disposed) return;
      const tab = env.tabs.querySelector(`[data-profession-tab="${id}"]`);
      if (tab) {
        const left = env.tabs.scrollLeft + tab.getBoundingClientRect().left - env.tabs.getBoundingClientRect().left - (env.tabs.clientWidth - tab.offsetWidth) / 2;
        env.tabs.scrollTo({ left, behavior: 'smooth' });
      }
      if (!snapDeck) return;
      const shell = env.deck.querySelector(`[data-profession="${id}"]`);
      if (!shell) return;
      const left = shell.offsetLeft - (env.deck.clientWidth - shell.offsetWidth) / 2;
      if (Math.abs(env.deck.scrollLeft - left) < 8) return;
      snapping = true;
      env.deck.scrollTo({ left, behavior: 'auto' });
      after(clock, 50, () => {
        snapping = false;
      });
    });
  }

  /** The shell nearest to the deck's scroll centre becomes active (N2:10921-10934 `be`). */
  function pickNearest() {
    if (!mobile || snapping) return;
    const shells = Array.from(env.deck.querySelectorAll('[data-profession]'));
    const mid = env.deck.scrollLeft + env.deck.clientWidth / 2;
    const idx = nearest({ target: mid, centers: shells.map((s) => s.offsetLeft + s.offsetWidth / 2) });
    const id = shells[idx]?.dataset.profession;
    if (id && id !== env.getActive() && env.ids.includes(id)) {
      env.setActive(id);
      centre(id, false);
    }
  }

  const stopScrollEnd = env.onDeckScrollEnd(pickNearest);

  return {
    /** scroll engine callback / section became active / media changed (`m`) */
    request,
    /** first frame on mount (N2:10986 `n = rAF(f)`) */
    start: request,
    onMobileChange() {
      mobile = env.mobileMatches();
      env.setMobile(mobile);
      centre(env.getActive(), mobile);
      request();
    },
    /** a tab was clicked (N2:10810-10835 `ge`) */
    select(id: string) {
      env.setActive(id);
      if (!useScroll()) {
        if (mobile) centre(id, true);
        return;
      }
      setHeight();
      const idx = env.ids.indexOf(id);
      if (idx < 0) return;
      const { shrink, prof } = r();
      const top = gotoTop({ showcaseY: env.scrollY() + env.showcase.getBoundingClientRect().top, shrink, prof, cnt: env.ids.length, idx });
      programmatic = true;
      env.scrollTo(top);
      let done = false;
      const finish = () => {
        if (done) return;
        done = true;
        programmatic = false;
      };
      const off = env.onWindowScrollEnd(() => {
        off();
        finish();
      });
      after(clock, 900, finish);
    },
    /** deck scroll (touch layout): debounce 150 ms and one rAF (N2:10936-10944 `xe`) */
    onDeckScroll() {
      if (!mobile || snapping) return;
      debounce?.();
      debounce = after(clock, DEBOUNCE_MS, pickNearest);
      if (!debounceFrame) {
        debounceFrame = clock.subscribe(
          () => {
            debounceFrame?.();
            debounceFrame = null;
            pickNearest();
          },
          { own: true },
        );
      }
    },
    /** tab rail drag (touch layout) (N2:10851-10880) */
    pointerDown(e: { pointerId: number; clientX: number; pointerType: string; button: number }) {
      if (!mobile) return;
      if (e.pointerType !== 'mouse' || e.button === 0) drag = { id: e.pointerId, x: e.clientX, left: env.tabs.scrollLeft, moved: false };
      env.setDragging(false);
    },
    /** returns true when the move is a drag (the caller prevents default and captures the pointer) */
    pointerMove(e: { pointerId: number; clientX: number }): { dragging: boolean; first: boolean } {
      if (!drag || drag.id !== e.pointerId) return { dragging: false, first: false };
      const dx = e.clientX - drag.x;
      let first = false;
      if (!drag.moved && Math.abs(dx) > 4) {
        drag.moved = true;
        first = true;
        env.setDragging(true);
      }
      if (drag.moved) env.tabs.scrollLeft = drag.left - dx;
      return { dragging: drag.moved, first };
    },
    pointerUp(e: { pointerId: number }) {
      if (!drag || drag.id !== e.pointerId) return;
      drag = null;
      after(clock, 1, () => env.setDragging(false));
    },
    get dragged() {
      return drag?.moved ?? false;
    },
    dispose() {
      disposed = true;
      cancelFrame?.();
      cancelFrame = null;
      debounce?.();
      debounceFrame?.();
      stopScrollEnd();
      env.showcase.style.height = '';
    },
    get state() {
      return { scale, offset, origin, mobile };
    },
  };
}
