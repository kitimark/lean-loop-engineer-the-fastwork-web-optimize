// Debug recorder of the nav's width transition (task waapi-tail-webkit, phase 1). Off in every page unless the URL carries
// `?fw-debug=nav-transition`. It is not a flag: it is read by nothing but `navDebugOn`, it is not in the config, the hash or the
// registry, and the page it runs on resolves the same flags. TS stand-in: no Lean spec (debug only; no product decision).
//
// What it records, in the order it happens (the array order is the real order inside a frame), so one run can tell which style
// update held the class flip and which held each base `--morph` write:
//   raf   a frame start (rAF timestamp), only while the nav is "hot" (a nav row in the last HOT_MS)
//   data  the nav's `data-fw-morph` changed (the observer at nav/index.tsx that flips `is-morphing` reacts to this write)
//   cls   `is-morphing` flipped (on = the class is now set)
//   base  the inline `--morph` changed (v = its text)
//   tr    transitionrun / transitionstart / transitionend / transitioncancel on the nav itself (not on a child)
//   size  the nav's border box after a layout (ResizeObserver; no style flush is forced by the recorder)
// A row is read by MutationObserver, so its `t` is the end of the task that wrote, not the write itself. The recorder never reads
// layout or computed style and never writes a style, so it does not move the style-change boundaries it measures.

export const DEBUG_PARAM = 'fw-debug';
export const NAV_TRANSITION_DEBUG = 'nav-transition';
/** `window.__fwDebug.navTransition`: the rows; the trajectory probe saves them (packages/gate-breakpoints/src/trajectory/run.mjs). */
export const DEBUG_GLOBAL = '__fwDebug';
export const MORPHING_CLASS = 'is-morphing';
export const MORPH_PROP = '--morph';
/** A page walks for tens of seconds; rows are only worth keeping around a push. */
export const HOT_MS = 1500;
export const MAX_ROWS = 6000;
export const TRANSITION_EVENTS = ['transitionrun', 'transitionstart', 'transitionend', 'transitioncancel'] as const;

export type Row =
  | { k: 'raf'; t: number; ts: number }
  | { k: 'data'; t: number; v: string | null }
  | { k: 'cls'; t: number; on: boolean }
  | { k: 'base'; t: number; v: string }
  | { k: 'tr'; t: number; type: string; prop: string; el: number; ts: number }
  | { k: 'size'; t: number; w: number; h: number };

export interface DebugLog {
  rows: Row[];
  /** rows refused after MAX_ROWS */
  dropped: number;
}

/** True iff the search carries `fw-debug=nav-transition` (one or more `fw-debug` params, each a comma list). */
export function navDebugOn(search: string): boolean {
  return new URLSearchParams(search)
    .getAll(DEBUG_PARAM)
    .flatMap((v) => v.split(','))
    .includes(NAV_TRANSITION_DEBUG);
}

/** The environment of the recorder: the page's own globals in the browser, fakes in the tests. */
export interface DebugEnv {
  now: () => number;
  raf: (cb: (ts: number) => void) => number;
  cancelRaf: (id: number) => void;
  /** where the log lives; the page's `window` */
  store: Record<string, unknown>;
  mutationObserver: typeof MutationObserver;
  resizeObserver?: typeof ResizeObserver;
}

export function browserEnv(): DebugEnv {
  return {
    now: () => performance.now(),
    raf: (cb) => requestAnimationFrame(cb),
    cancelRaf: (id) => cancelAnimationFrame(id),
    store: window as unknown as Record<string, unknown>,
    mutationObserver: MutationObserver,
    resizeObserver: typeof ResizeObserver === 'undefined' ? undefined : ResizeObserver,
  };
}

/**
 * Installs the recorder on `nav` when `search` asks for it; returns its disposer, or null (and touches nothing: no global, no
 * listener, no observer, no frame loop) when it does not. Called once per mount from the nav's effect.
 */
export function installNavTransitionDebug(search: string, nav: HTMLElement, env: DebugEnv = browserEnv()): (() => void) | null {
  if (!navDebugOn(search)) return null;
  const log: DebugLog = { rows: [], dropped: 0 };
  const bag = (env.store[DEBUG_GLOBAL] ??= {}) as { navTransition?: DebugLog };
  bag.navTransition = log;
  let hotUntil = -Infinity;
  const push = (row: Row, hot = true) => {
    if (log.rows.length >= MAX_ROWS) {
      log.dropped += 1;
      return;
    }
    log.rows.push(row);
    if (hot) hotUntil = row.t + HOT_MS;
  };

  let morphing = nav.classList.contains(MORPHING_CLASS);
  let base = nav.style.getPropertyValue(MORPH_PROP);
  let data = nav.getAttribute('data-fw-morph');

  // Observers are created after the nav's own observer (index.tsx), so within one microtask checkpoint they run after its callback.
  const mo = new env.mutationObserver(() => {
    const t = env.now();
    const d = nav.getAttribute('data-fw-morph');
    if (d !== data) {
      data = d;
      push({ k: 'data', t, v: d });
    }
    const on = nav.classList.contains(MORPHING_CLASS);
    if (on !== morphing) {
      morphing = on;
      push({ k: 'cls', t, on });
    }
    const b = nav.style.getPropertyValue(MORPH_PROP);
    if (b !== base) {
      base = b;
      push({ k: 'base', t, v: b });
    }
  });
  mo.observe(nav, { attributes: true, attributeFilter: ['class', 'style', 'data-fw-morph'] });

  const onTransition = (e: Event) => {
    if (e.target !== nav) return;
    const te = e as Event & { propertyName?: string; elapsedTime?: number };
    push({ k: 'tr', t: env.now(), type: e.type, prop: te.propertyName ?? '', el: te.elapsedTime ?? 0, ts: e.timeStamp });
  };
  for (const type of TRANSITION_EVENTS) nav.addEventListener(type, onTransition);

  let ro: ResizeObserver | undefined;
  if (env.resizeObserver) {
    ro = new env.resizeObserver((entries) => {
      const e = entries[entries.length - 1];
      const box = e?.borderBoxSize?.[0];
      const t = env.now();
      if (!e || !box || t >= hotUntil) return;
      push({ k: 'size', t, w: box.inlineSize, h: box.blockSize }, false);
    });
    ro.observe(nav, { box: 'border-box' });
  }

  let frame = 0;
  const tick = (ts: number) => {
    const t = env.now();
    if (t < hotUntil) push({ k: 'raf', t, ts }, false);
    frame = env.raf(tick);
  };
  frame = env.raf(tick);

  return () => {
    mo.disconnect();
    for (const type of TRANSITION_EVENTS) nav.removeEventListener(type, onTransition);
    ro?.disconnect();
    env.cancelRaf(frame);
  };
}
