import { MESSAGE, initialView, observe, picture, round, trig0, visualScale, type Trig, type View } from './logic';

export interface ClassEl {
  classList: { toggle(cls: string, on: boolean): void };
}
export interface Els {
  /** `.fee-visual-scale`: observed for intersection; gets `--visual-scale`. */
  scale: { style: { setProperty(name: string, value: string): void } };
  /** the scale box's parent (`.commission-visual-column`): its width sets the scale. */
  parent: { clientWidth: number } | null;
  visual: ClassEl;
  beat: ClassEl;
  avatar: ClassEl;
  message: ClassEl;
  /** the `<p>` inside the bubble: holds the typed text and the caret. */
  text: { append(n: unknown): void };
  referral: ClassEl;
  amount: { textContent: string | null };
  percent: { textContent: string | null };
  fill: { style: { width: string } };
}
export interface Classes {
  resetting: string;
  scrollingOut: string;
  shown: string;
  caret: string;
}
export interface Clock {
  subscribe(tick: (t: number) => void, opts?: { own?: boolean }): () => void;
}
export interface Env {
  now(): number;
  reduced(): boolean;
  observe(target: unknown, opts: { threshold?: number[] }, cb: (e: { isIntersecting: boolean }) => void): () => void;
  observeResize(target: unknown, cb: () => void): () => void;
  createText(): { data: string; after(n: unknown): void };
  createCaret(cls: string): { remove(): void };
}

export interface Deps {
  els: Els;
  classes: Classes;
  clock: Clock;
  env: Env;
}

/**
 * The typing driver. The Lean timeline (`CommissionTyping.picture`) says what the screen shows at a time; this file
 * reads the clock, asks the timeline and writes the differences to the DOM. Visibility (observer thresholds 0, 0.05, 0.2)
 * starts and stops the clock subscription; the picture is held when the run is cancelled. Only changed fields are written
 * (the original re-renders the changed signals). Reduced motion is read when a run starts.
 */
export function mountTyping({ els, classes, clock, env }: Deps): () => void {
  let trig: Trig = trig0;
  let off: (() => void) | null = null;
  let painted: View = initialView;
  const textNode = env.createText();
  els.text.append(textNode);
  let caretNode: { remove(): void } | null = null;

  const paint = (v: View) => {
    const p = painted;
    if (v.resetting !== p.resetting) els.visual.classList.toggle(classes.resetting, v.resetting);
    if (v.out !== p.out) els.beat.classList.toggle(classes.scrollingOut, v.out);
    if (v.avatar !== p.avatar) els.avatar.classList.toggle(classes.shown, v.avatar);
    if (v.bubble !== p.bubble) els.message.classList.toggle(classes.shown, v.bubble);
    if (v.chars !== p.chars) textNode.data = MESSAGE.slice(0, v.chars);
    if (v.caret !== p.caret) {
      if (v.caret) {
        caretNode = env.createCaret(classes.caret);
        textNode.after(caretNode);
      } else {
        caretNode?.remove();
        caretNode = null;
      }
    }
    if (v.card !== p.card) els.referral.classList.toggle(classes.shown, v.card);
    if (round(v.earned) !== round(p.earned)) els.amount.textContent = `$${round(v.earned)}`;
    if (round(v.pct) !== round(p.pct)) els.percent.textContent = `${round(v.pct)}%`;
    if (v.progress !== p.progress) els.fill.style.width = `${v.progress * 100}%`;
    painted = v;
  };

  const stop = () => {
    off?.();
    off = null;
  };
  const stopIo = env.observe(els.scale, { threshold: [0, 0.05, 0.2] }, (e) => {
    const now = env.now();
    const r = observe(trig, e.isIntersecting, now, e.isIntersecting ? env.reduced() : false);
    trig = r.state;
    if (r.act === 'keep') return;
    stop();
    if (r.act === 'cancel') {
      paint(picture(trig, now));
      return;
    }
    paint(picture(trig, now));
    if (!trig.static) off = clock.subscribe((t) => paint(picture(trig, t)));
  });

  const rescale = () => {
    const w = els.parent?.clientWidth;
    if (w !== undefined) els.scale.style.setProperty('--visual-scale', String(visualScale(w)));
  };
  rescale();
  const stopRo = els.parent ? env.observeResize(els.parent, rescale) : () => undefined;

  return () => {
    stop();
    stopIo();
    stopRo();
    caretNode?.remove();
  };
}

