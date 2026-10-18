/**
 * Pure logic of overlays.drawer (no DOM): the "why bring" drawer of the original.
 * Original: _app/immutable/nodes/2.DyWL8TcE.js:2893-2943 (EE: mount/show state machine, body overflow, Escape),
 * assets/2.gBuqKVzi.css:684-734, 899-914, 1145-1165, 1215-1218 (panel, backdrop, transitions).
 * Lean: lean/Fw/Parts/OverlayDrawer.lean (+ Bezier.lean). Golden vectors: packages/contracts/golden/parts/overlays.drawer.jsonl.
 */

/** Panel and backdrop transition length, ms (CSS 0.4s). */
export const TRANSITION_MS = 400;
/** Delay before a closed drawer is unmounted, ms (JS 2917). */
export const UNMOUNT_MS = 480;
/** Extra off-screen distance of the hidden panel at the side and mid layouts, px. */
export const HIDE_GAP = 48;

/** A CSS cubic-bezier timing function. */
export interface Bez {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}
/** CSS `ease-in-out`. */
export const EASE_IN_OUT: Bez = { x1: 0.42, y1: 0, x2: 0.58, y2: 1 };
/** The design system's `--ease-standard`. */
export const EASE_STANDARD: Bez = { x1: 0.24, y1: 1, x2: 0.4, y2: 1 };
const STEPS = 40;

const coord = (a: number, b: number, s: number): number => 3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s;

/** Lean `Bezier.ease`: 40 bisection steps on x(s) = t, then y(s). */
export function ease(c: Bez, t: number): number {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  let lo = 0;
  let hi = 1;
  for (let i = 0; i < STEPS; i++) {
    const m = (lo + hi) / 2;
    if (coord(c.x1, c.x2, m) < t) lo = m;
    else hi = m;
  }
  return coord(c.y1, c.y2, (lo + hi) / 2);
}

export interface St {
  mounted: boolean;
  shown: boolean;
  rafPending: boolean;
  timerAt: number | null;
}
export const REST: St = { mounted: false, shown: false, rafPending: false, timerAt: null };

/** The `open` prop changed to `b` at `now` (JS 2906-2920). Opening never resets `shown`. */
export function setOpen(s: St, b: boolean, now: number, reduced: boolean): St {
  if (b) return { mounted: true, shown: s.shown, rafPending: true, timerAt: null };
  if (s.mounted) return { mounted: true, shown: false, rafPending: s.rafPending, timerAt: now + (reduced ? 0 : UNMOUNT_MS) };
  return { ...s, timerAt: null };
}

/** The animation frame after an open (JS 2910-2912): `shown` is set whatever the prop is now. */
export function raf(s: St): St {
  return s.rafPending ? { mounted: s.mounted, shown: true, rafPending: false, timerAt: s.timerAt } : s;
}

/** The unmount timer is due (JS 2916-2919). */
export function tick(s: St, now: number): St {
  return s.timerAt !== null && s.timerAt <= now ? { mounted: false, shown: s.shown, rafPending: s.rafPending, timerAt: null } : s;
}

/** `Escape` on the window asks to close exactly when mounted (JS 2934-2943). */
export function escapeCloses(s: St, key: string): boolean {
  return key === 'Escape' && s.mounted;
}

/** Body overflow while the drawer is open (JS 2927-2933). */
export function bodyOverflow(open: boolean, prev: string): string {
  return open ? 'hidden' : prev;
}

export type Layout = 'side' | 'mid' | 'sheet';

/** CSS 899 `width<=860px` and 1133 `width<=640px`. */
export function layoutOf(w: number): Layout {
  return w <= 640 ? 'sheet' : w <= 860 ? 'mid' : 'side';
}

/** Hidden panel offset from its shown position, px, for a panel of pw x ph. */
export function hidden(layout: Layout, pw: number, ph: number): [number, number] {
  return layout === 'side' ? [pw + HIDE_GAP, 0] : layout === 'mid' ? [0, ph + HIDE_GAP] : [0, ph];
}

/** Transition progress `elapsed` ms after the class flips; reduced motion has `transition: none`. */
export function progress(elapsed: number, reduced: boolean): number {
  return reduced ? 1 : ease(EASE_IN_OUT, elapsed / TRANSITION_MS);
}

/** Panel translation `elapsed` ms after `shown` became `shown`. */
export function panelPos(layout: Layout, pw: number, ph: number, shown: boolean, elapsed: number, reduced: boolean): [number, number] {
  const p = progress(elapsed, reduced);
  const f = shown ? 1 - p : p;
  const h = hidden(layout, pw, ph);
  return [h[0] * f, h[1] * f];
}

/** Backdrop opacity `elapsed` ms after `shown` became `shown`. */
export function backdropAlpha(shown: boolean, elapsed: number, reduced: boolean): number {
  const p = progress(elapsed, reduced);
  return shown ? p : 1 - p;
}
