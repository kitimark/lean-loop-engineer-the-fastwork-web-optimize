// Debug recorder of the nav's width transition (task waapi-tail-webkit, phase 1). Off in every page unless the URL carries
// `?fw-debug=nav-transition`. It is not a flag: it is read by nothing but `navDebugOn`, it is not in the config, the hash or the
// registry, and the page it runs on resolves the same flags. TS stand-in: no Lean spec (debug only; no product decision).
//
// What it records, in the order the observers saw it (the array order is the order inside a frame), so one run can tell which style
// update held the class flip and which held each base `--morph` write:
//   raf   a frame start (rAF timestamp), only while the nav is "hot" (a nav row in the last HOT_MS); the loop runs only while hot
//   data  the nav's `data-fw-morph` changed (the observer at nav/index.tsx that flips `is-morphing` reacts to this write)
//   cls   `is-morphing` flipped (on = the class is now set)
//   base  the inline `--morph` changed (v = its text)
//   tr    transitionrun / transitionstart / transitionend / transitioncancel on the nav itself (not on a child)
//   size  the nav's border box after a layout (ResizeObserver; no style flush is forced by the recorder)
//   read  a read of the trajectory probe's sampler (getComputedStyle, getBoundingClientRect: a forced style flush), only while hot;
//         the kit calls `window.__fwDebug.navTransitionRead()` before each sample when the recorder exists
// data, cls and base come from ONE MutationObserver and give one row per MutationRecord, in the order of the records the engine
// queued (not a fixed order of the three attributes): a record gives a row only when the value after it differs from the last
// one logged (the value after a record is the old value of the next record of that attribute, or the current value for the last).
// Records of one callback share one `t` (the time of the callback, the end of the task that wrote); their order is the write order.
// `navTransitionRead` first takes the pending records (`takeRecords`), so a write that precedes the read in the same task is logged
// before the read row. The recorder never reads layout or computed style and never writes a style. Its own cost to the page: a
// rAF callback each frame while hot (none while cold), one ResizeObserver on the nav (kept for the whole page, INFERRED not to
// schedule a frame by itself), and the observers.

export const DEBUG_PARAM = 'fw-debug';
export const NAV_TRANSITION_DEBUG = 'nav-transition';
/** `window.__fwDebug.navTransition`: the rows; the trajectory probe saves them (packages/gate-breakpoints/src/trajectory/run.mjs). */
export const DEBUG_GLOBAL = '__fwDebug';
export const MORPHING_CLASS = 'is-morphing';
export const MORPH_PROP = '--morph';
/** `--morph` in the text of a `style` attribute (what a style MutationRecord's oldValue holds); `''` when the text has none. */
export function morphOfStyle(text: string | null): string {
  const m = /(?:^|;)\s*--morph\s*:\s*([^;]*?)\s*(?:;|$)/.exec(text ?? '');
  return m?.[1] ?? '';
}
/** Does the text of a `class` attribute hold the `is-morphing` token? */
export const hasMorphing = (text: string | null): boolean => (text ?? '').split(/\s+/).includes(MORPHING_CLASS);
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
  | { k: 'size'; t: number; w: number; h: number }
  | { k: 'read'; t: number };

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
  const bag = (env.store[DEBUG_GLOBAL] ??= {}) as { navTransition?: DebugLog; navTransitionRead?: () => void };
  bag.navTransition = log;
  let hotUntil = -Infinity;
  let looping = false;
  let frame = 0;
  // The frame loop runs only while hot: a nav row heats it (and starts it if cold), the first frame at or past `hotUntil` ends it.
  const tick = (ts: number) => {
    const t = env.now();
    if (t >= hotUntil) {
      looping = false;
      return;
    }
    push({ k: 'raf', t, ts }, false);
    frame = env.raf(tick);
  };
  const push = (row: Row, hot = true) => {
    if (log.rows.length >= MAX_ROWS) {
      log.dropped += 1;
      return;
    }
    log.rows.push(row);
    if (!hot) return;
    hotUntil = row.t + HOT_MS;
    if (!looping) {
      looping = true;
      frame = env.raf(tick);
    }
  };

  let morphing = hasMorphing(nav.getAttribute('class'));
  let base = morphOfStyle(nav.getAttribute('style'));
  let data = nav.getAttribute('data-fw-morph');

  // One row per MutationRecord, in record order. The value after record i is the oldValue of the next record of the same attribute,
  // or the attribute now (the queue is complete up to now, so no later write is in it).
  const apply = (records: MutationRecord[], t: number) => {
    records.forEach((r, i) => {
      const name = r.attributeName ?? '';
      const next = records.slice(i + 1).find((x) => x.attributeName === name);
      const after = next ? next.oldValue : nav.getAttribute(name);
      if (name === 'data-fw-morph') {
        if (after !== data) {
          data = after;
          push({ k: 'data', t, v: after });
        }
      } else if (name === 'class') {
        const on = hasMorphing(after);
        if (on !== morphing) {
          morphing = on;
          push({ k: 'cls', t, on });
        }
      } else if (name === 'style') {
        const v = morphOfStyle(after);
        if (v !== base) {
          base = v;
          push({ k: 'base', t, v });
        }
      }
    });
  };
  // Observers are created after the nav's own observer (index.tsx), so within one notify loop they run after its callback.
  const mo = new env.mutationObserver((records) => apply(records, env.now()));
  mo.observe(nav, { attributes: true, attributeOldValue: true, attributeFilter: ['class', 'style', 'data-fw-morph'] });

  // The sampler's read (kit.mjs `snap`): the queued records go first, then a `read` row while hot.
  bag.navTransitionRead = () => {
    const t = env.now();
    apply(mo.takeRecords(), t);
    if (t < hotUntil) push({ k: 'read', t }, false);
  };

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

  return () => {
    mo.disconnect();
    for (const type of TRANSITION_EVENTS) nav.removeEventListener(type, onTransition);
    ro?.disconnect();
    if (looping) env.cancelRaf(frame);
    looping = false;
    delete bag.navTransitionRead;
  };
}
