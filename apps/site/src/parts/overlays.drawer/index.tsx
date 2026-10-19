import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { getClock } from '../../engine/clock';
import { GenSvg, art } from '../../GenSvg';
import css from './drawer.module.css';
import { bodyOverflow, escapeCloses, raf, REST, setOpen, tick, type St } from './logic';
import { matchList } from './media';
import { closeDrawer, drawerStore } from './store';

export { openDrawer, closeDrawer } from './store';

export interface OverlayDrawerProps {
  variant: string;
  /** "Join waitlist" in the footer: closes the drawer, then this (the original's `onGetStarted`) */
  onGetStarted?: () => void;
}

/** 1x1 transparent GIF: stands in for the icon and divider images (assets are not restated). */
const PIXEL = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

const BENEFITS: ReadonlyArray<readonly [string, string]> = [
  ['Build your reputation', 'Turn every client project into reviews and credibility that help you win the next one.'],
  ['Protect your payment', 'Work with confidence knowing the payment is secured before you start.'],
  ['Keep business in one place', 'Manage conversations, projects, documents, payments, even your taxes! Without jumping between tools.'],
];

/**
 * overlays.drawer (`faithful`): the "why bring your client" drawer. Mount, show and unmount follow the Lean state machine
 * (`logic.ts`, `Fw.Parts.OverlayDrawer`): the open flag mounts it, one animation frame later `is-open` slides it in
 * (CSS transitions, 0.4 s), a close slides it out and the unmount follows 480 ms later (0 ms under reduced motion).
 * No per-frame work in JS: the motion is the browser's CSS transition. Plain elements, one CSS Module.
 */
export function OverlayDrawer({ variant, onGetStarted }: OverlayDrawerProps) {
  const open = useSyncExternalStore(drawerStore.subscribe, drawerStore.get, () => false);
  const [st, setSt] = useState<St>(REST);
  const stRef = useRef<St>(REST);
  const cancelTimer = useRef<(() => void) | null>(null);
  const cancelFrame = useRef<(() => void) | null>(null);
  const closeButton = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    const clock = getClock();
    const commit = (n: St) => {
      stRef.current = n;
      setSt(n);
    };
    cancelTimer.current?.(); // clearTimeout of the previous close
    cancelTimer.current = null;
    const now = performance.now();
    const reduced = matchList('mq.rm-reduce')?.matches ?? false;
    const next = setOpen(stRef.current, open, now, reduced);
    if (next.mounted !== stRef.current.mounted || next.shown !== stRef.current.shown || next.rafPending !== stRef.current.rafPending) commit(next);
    else stRef.current = next;
    if (open) {
      // one animation frame later: shown + focus on the close button (not cancelled by a later close, as in the original)
      const off = clock.subscribe(
        () => {
          off();
          cancelFrame.current = null;
          commit(raf(stRef.current));
          closeButton.current?.focus({ preventScroll: true });
        },
        { own: true },
      );
      cancelFrame.current = off;
    } else if (next.timerAt !== null) {
      const due = next.timerAt;
      const off = clock.interval(Math.max(0, due - now), () => {
        off();
        cancelTimer.current = null;
        commit(tick(stRef.current, due));
      });
      cancelTimer.current = off;
    }
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = bodyOverflow(true, prev);
    return () => {
      document.body.style.overflow = prev;
    };
  }, [open]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (escapeCloses(stRef.current, e.key)) closeDrawer();
    };
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('keydown', onKey);
      cancelTimer.current?.();
      cancelFrame.current?.();
    };
  }, []);

  if (!st.mounted) return null;
  return (
    <div role="presentation" className={st.shown ? `${css.root} ${css.open}` : css.root} data-fw="overlay-drawer" data-fw-variant={variant}>
      <button type="button" className={css.backdrop} aria-label="Close dialog" onClick={closeDrawer} />
      <div className={css.panel} role="dialog" aria-modal="true" aria-labelledby="why-bring-title">
        <button type="button" className={css.close} aria-label="Close" ref={closeButton} onClick={closeDrawer}>
          <GenSvg art={art('drawer.close')} />
        </button>
        <div className={css.body}>
          <div className={css.header}>
            <GenSvg art={art('brand.mark')} className={css.mark} />
            <div className={css.intro}>
              <h2 id="why-bring-title">Why bring your client to Fastwork?</h2>
              <p>Discover the benefits of bringing your clients with you.</p>
            </div>
          </div>
          <ul className={css.list}>
            {BENEFITS.map(([title, body], i) => (
              <ListItem key={title} first={i === 0} title={title} body={body} />
            ))}
          </ul>
          <div className={css.footer}>
            <p>So, why work anywhere else?</p>
            <button
              type="button"
              onClick={() => {
                closeDrawer();
                onGetStarted?.();
              }}
            >
              Join waitlist
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function ListItem({ first, title, body }: { first: boolean; title: string; body: string }) {
  return (
    <>
      {first ? null : (
        <li className={css.divider} aria-hidden="true">
          <img src={PIXEL} alt="" loading="lazy" decoding="async" />
        </li>
      )}
      <li className={css.item}>
        <img src={PIXEL} alt="" width={24} height={24} loading="lazy" decoding="async" />
        <div>
          <strong>{title}</strong>
          <p>{body}</p>
        </div>
      </li>
    </>
  );
}
