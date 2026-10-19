import ButtonBase from '@mui/material/ButtonBase';
import Typography from '@mui/material/Typography';
import { useEffect, useRef, type MutableRefObject, type ReactNode } from 'react';
import { createPanelWriter } from './driver';
import css from './morph.module.css';

export type PanelWriter = ReturnType<typeof createPanelWriter>;

export interface MorphPanelProps {
  variant: string;
  /** `mui` (default) uses MUI Typography/ButtonBase; `plain` bare elements. Same CSS Module and driver. */
  impl?: 'mui' | 'plain';
  /** the first morph value the attributes are written for (the host's `--morph`); the tween owns later values */
  initialMorph?: number;
  /** receives the attribute writer (set in an effect): `writerRef.current?.apply(morph)` per tween frame, no React state */
  writerRef?: MutableRefObject<PanelWriter | null>;
  /** the image columns inside the backdrop (morph.columns) */
  backdrop?: ReactNode;
  /** the countdown inside the centre (morph.countdown) */
  countdown?: ReactNode;
  /** the call-to-action's click (the page opens the signup overlay) */
  onAction?: () => void;
}

/**
 * morph.panel: the expanded end-of-page panel, faithful: backdrop, veil, centre (title, countdown slot, call-to-action
 * stack), footer. Placeholder content only. The panel is absolutely positioned and fills its host, which carries
 * `--morph` (the nav in the original). Rendered as a child of the nav, which hosts it. Mounting it
 * lazily is morph.mount's job, tweening `--morph` morph.tween's, the columns and the countdown their parts'.
 */
export function MorphPanel({ variant, impl = 'mui', initialMorph = 0, writerRef, backdrop, countdown, onAction }: MorphPanelProps) {
  const panelRef = useRef<HTMLDivElement>(null);
  const ctaRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    const panel = panelRef.current;
    if (!panel) return;
    const w = createPanelWriter({ panel, cta: ctaRef.current });
    const hostMorph = Number.parseFloat(panel.closest<HTMLElement>('[data-fw-morph]')?.dataset.fwMorph ?? '');
    w.apply(Number.isFinite(hostMorph) ? hostMorph : initialMorph);
    if (writerRef) writerRef.current = w;
    return () => {
      if (writerRef) writerRef.current = null;
    };
    // initialMorph is the first value only
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const mui = impl === 'mui';
  return (
      <div
        ref={panelRef}
        className={css.panel}
        data-fw="morph-panel"
        data-fw-variant={variant}
        data-start-selling-scene="paused"
        aria-hidden="true"
      >
        <div className={css.backdrop} data-fw-role="backdrop" aria-hidden="true">
          {backdrop}
        </div>
        <div className={css.veil} data-fw-role="veil" aria-hidden="true" />
        <div className={css.center} data-fw-role="center">
          {mui ? (
            <Typography variant="body1" component="p" className={css.title} data-fw-role="title">
              Placeholder panel title
            </Typography>
          ) : (
            <p className={css.title} data-fw-role="title">
              Placeholder panel title
            </p>
          )}
          <div className={css.countdown} data-fw-role="countdown">
            {countdown}
          </div>
          <div className={css.ctaStack} data-fw-role="cta-stack">
            {mui ? (
              <ButtonBase ref={ctaRef} className={css.cta} focusRipple={false} tabIndex={-1} data-fw-role="cta" onClick={onAction}>
                <BellIcon />
                Action
              </ButtonBase>
            ) : (
              <button ref={ctaRef} type="button" className={css.cta} tabIndex={-1} data-fw-role="cta" onClick={onAction}>
                <BellIcon />
                Action
              </button>
            )}
            <a href="#morph-panel" className={css.rsvp} data-fw-role="link">
              <CalendarIcon />
              Link
            </a>
          </div>
        </div>
        <footer className={css.footer} data-fw-role="footer">
          <p>Placeholder line</p>
          <div className={css.footerEnd} data-fw-role="footer-end">
            <p>Placeholder line</p>
            <span className={css.grad} data-fw-role="grad" aria-hidden="true" />
            <a href="#morph-panel">Placeholder link</a>
          </div>
        </footer>
      </div>
  );
}

/** Solar "bell" and "calendar" linear glyphs, in the original's 24 x 24 box. */
function BellIcon() {
  return (
    <svg className={css.ctaIcon} viewBox="0 0 24 24" fill="none" strokeWidth="1.5" aria-hidden="true" focusable="false">
      <path
        d="M18.7491 9.70957V9.00496C18.7491 5.13623 15.7274 2 12 2C8.27256 2 5.25087 5.13623 5.25087 9.00496V9.70957C5.25087 10.5552 5.00972 11.3818 4.5578 12.0854L3.45036 13.8095C2.43882 15.3843 3.21105 17.5249 4.97036 18.0229C9.57274 19.3257 14.4273 19.3257 19.0296 18.0229C20.789 17.5249 21.5612 15.3843 20.5496 13.8095L19.4422 12.0854C18.9903 11.3818 18.7491 10.5552 18.7491 9.70957Z"
        stroke="currentColor"
      />
      <path d="M7.5 19C8.15503 20.7478 9.92246 22 12 22C14.0775 22 15.845 20.7478 16.5 19" stroke="currentColor" strokeLinecap="round" />
    </svg>
  );
}

function CalendarIcon() {
  return (
    <svg className={css.ctaIcon} viewBox="0 0 24 24" fill="none" strokeWidth="1.5" aria-hidden="true" focusable="false">
      <path
        d="M2 12C2 8.22876 2 6.34315 3.17157 5.17157C4.34315 4 6.22876 4 10 4H14C17.7712 4 19.6569 4 20.8284 5.17157C22 6.34315 22 8.22876 22 12V14C22 17.7712 22 19.6569 20.8284 20.8284C19.6569 22 17.7712 22 14 22H10C6.22876 22 4.34315 22 3.17157 20.8284C2 19.6569 2 17.7712 2 14V12Z"
        stroke="currentColor"
      />
      <path d="M7 4V2.5M17 4V2.5M2.5 9H21.5" stroke="currentColor" strokeLinecap="round" />
    </svg>
  );
}
