import ButtonBase from '@mui/material/ButtonBase';
import Typography from '@mui/material/Typography';
import { useEffect, useRef, type MutableRefObject, type ReactNode } from 'react';
import { GenSvg, art } from '../../GenSvg';
import { createPanelWriter } from './driver';
import { PANEL } from './content';
import { THREADED } from './threaded.logic';
import css from './morph.module.css';

export const CONST_BOUNDS = 'const-bounds';

export type PanelWriter = ReturnType<typeof createPanelWriter>;

export interface MorphPanelProps {
  variant: string;
  impl?: 'mui' | 'plain';
  initialMorph?: number;
  writerRef?: MutableRefObject<PanelWriter | null>;
  backdrop?: ReactNode;
  countdown?: ReactNode;
  onAction?: () => void;
}

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
  }, []);

  const mui = impl === 'mui';
  return (
      <div
        ref={panelRef}
        className={variant === CONST_BOUNDS || variant === THREADED ? `${css.panel} ${css.cb}` : css.panel}
        data-fw="morph-panel"
        data-fw-layer="morph.panel_panel"
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
              {PANEL.title}
            </Typography>
          ) : (
            <p className={css.title} data-fw-role="title">
              {PANEL.title}
            </p>
          )}
          <div className={css.countdown} data-fw-role="countdown">
            {countdown}
          </div>
          <div className={css.ctaStack} data-fw-role="cta-stack">
            {mui ? (
              <ButtonBase ref={ctaRef} className={css.cta} focusRipple={false} tabIndex={-1} data-fw-role="cta" data-selenium="start-selling.header.button.other-role" onClick={onAction}>
                <BellIcon />
                {PANEL.cta}
              </ButtonBase>
            ) : (
              <button ref={ctaRef} type="button" className={css.cta} tabIndex={-1} data-fw-role="cta" data-selenium="start-selling.header.button.other-role" onClick={onAction}>
                <BellIcon />
                {PANEL.cta}
              </button>
            )}
            <a
              href={PANEL.rsvpHref}
              target="_blank"
              rel="noopener"
              className={css.rsvp}
              data-fw-role="link"
              data-selenium="start-selling.header.link.demo-day"
            >
              <CalendarIcon />
              {PANEL.rsvp}
            </a>
          </div>
        </div>
        <footer className={css.footer} data-fw-role="footer">
          <p>{PANEL.operated}</p>
          <div className={css.footerEnd} data-fw-role="footer-end">
            <p>{PANEL.copyright}</p>
            <span className={css.grad} data-fw-role="grad" aria-hidden="true" />
            <a href={PANEL.privacyHref} data-selenium="start-selling.header.link.privacy">
              {PANEL.privacy}
            </a>
          </div>
        </footer>
      </div>
  );
}

function BellIcon() {
  return <GenSvg art={art('icon.bell')} className={css.ctaIcon} />;
}

function CalendarIcon() {
  return <GenSvg art={art('icon.calendar')} className={css.ctaIcon} />;
}
