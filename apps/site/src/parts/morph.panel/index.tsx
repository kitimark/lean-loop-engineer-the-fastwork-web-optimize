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
}

/**
 * morph.panel: the expanded end-of-page panel, faithful: backdrop, veil, centre (title, countdown slot, call-to-action
 * stack), footer. Placeholder content only. The panel is absolutely positioned and fills its host, which carries
 * `--morph` (the nav in the original). Rendered in a fixed stand-in host here until the nav part owns it. Mounting it
 * lazily is morph.mount's job, tweening `--morph` morph.tween's, the columns and the countdown their parts'.
 */
export function MorphPanel({ variant, impl = 'mui', initialMorph = 0, writerRef, backdrop, countdown }: MorphPanelProps) {
  const panelRef = useRef<HTMLDivElement>(null);
  const ctaRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    const panel = panelRef.current;
    if (!panel) return;
    const w = createPanelWriter({ panel, cta: ctaRef.current });
    w.apply(initialMorph);
    if (writerRef) writerRef.current = w;
    return () => {
      if (writerRef) writerRef.current = null;
    };
    // initialMorph is the first value only
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const mui = impl === 'mui';
  return (
    <div className={css.host} data-fw="morph-panel-host">
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
              <ButtonBase ref={ctaRef} className={css.cta} focusRipple={false} tabIndex={-1} data-fw-role="cta">
                <Icon />
                Action
              </ButtonBase>
            ) : (
              <button ref={ctaRef} type="button" className={css.cta} tabIndex={-1} data-fw-role="cta">
                <Icon />
                Action
              </button>
            )}
            <a href="#morph-panel" className={css.rsvp} data-fw-role="link">
              <Icon />
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
    </div>
  );
}

function Icon() {
  return (
    <svg className={css.ctaIcon} viewBox="0 0 24 24" fill="none" strokeWidth="1.5" aria-hidden="true" focusable="false">
      <circle cx="12" cy="12" r="9" stroke="currentColor" />
    </svg>
  );
}
