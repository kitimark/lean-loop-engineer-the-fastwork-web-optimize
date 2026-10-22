import { useEffect, useRef } from 'react';
import { GenSvg, art, frames } from '../../GenSvg';
import { getClock } from '../../engine/clock';
import { getScrollEngine } from '../../engine/scroll';
import { CommissionTyping } from '../commission.typing';
import { openDrawer } from '../overlays.drawer';
import { ARROW, ARROW_COMPACT, FACES, TEXT } from './data';
import { mountCommission } from './driver';
import { matchList } from './media';
import css from './commission.module.css';

export interface CommissionProps {
  variant: string;
  typingVariant?: string;
}

export function Commission({ variant, typingVariant = 'faithful' }: CommissionProps) {
  const section = useRef<HTMLElement>(null);
  const card = useRef<HTMLDivElement>(null);
  const runway = useRef<HTMLDivElement>(null);
  const header = useRef<HTMLDivElement>(null);
  const title = useRef<HTMLHeadingElement>(null);
  const muted = useRef<HTMLSpanElement>(null);
  const underline = useRef<HTMLSpanElement>(null);

  const arrow = useRef<HTMLImageElement>(null);

  useEffect(() => {
    const img = arrow.current;
    const compact = matchList('mq.c1000');
    if (!img || !compact) return;
    const swap = () => {
      img.src = compact.matches ? ARROW_COMPACT : ARROW;
    };
    swap();
    compact.addEventListener('change', swap);
    return () => compact.removeEventListener('change', swap);
  }, []);

  useEffect(() => {
    const els = {
      section: section.current,
      card: card.current,
      runway: runway.current,
      header: header.current,
      title: title.current,
      muted: muted.current,
      underline: underline.current,
    };
    if (!els.section || !els.card || !els.runway || !els.header || !els.title || !els.muted || !els.underline) return;
    const reduce = matchList('mq.rm-reduce');
    const compact = matchList('mq.c1000');
    return mountCommission({
      els: els as Parameters<typeof mountCommission>[0]['els'],
      classes: { entering: css.entering!, shrinking: css.shrinking!, titleWrapped: css.titleWrapped!, enter: css.enter!, idle: css.idle! },
      engine: getScrollEngine(),
      clock: getClock(),
      env: {
        vh: () => window.innerHeight,
        reduced: () => reduce?.matches ?? false,
        compact: () => compact?.matches ?? false,
        onReducedChange: (cb) => {
          reduce?.addEventListener('change', cb);
          return () => reduce?.removeEventListener('change', cb);
        },
        onCompactChange: (cb) => {
          compact?.addEventListener('change', cb);
          return () => compact?.removeEventListener('change', cb);
        },
        observe: (target, opts, cb) => {
          const io = new IntersectionObserver((entries) => {
            for (const e of entries) cb(e);
          }, opts);
          io.observe(target as Element);
          return () => io.disconnect();
        },
        observeResize: (target, cb) => {
          const ro = new ResizeObserver(() => cb());
          ro.observe(target as Element);
          return () => ro.disconnect();
        },
        lineBoxes: (target) => {
          const r = document.createRange();
          r.selectNodeContents(target as Node);
          return r.getClientRects().length;
        },
      },
    }, { bandGate: variant === 'band-gate' });
  }, []);

  return (
    <section ref={section} className={css.commission} aria-labelledby="commission-heading" data-fw="commission" data-fw-variant={variant}>
      <div className={css.track}>
        <div className={css.sticky}>
          <div ref={card} className={css.card} data-fw="commission-card">
            <div className={css.inner}>
              <div ref={header} className={css.header}>
                <h2 ref={title} id="commission-heading">
                  <span ref={muted} className={css.titleMuted}>
                    {TEXT.titleBase}
                  </span>{' '}
                  <span className={css.titleAccent}>
                    {TEXT.titleAccent}{' '}
                    <span ref={underline} className={css.underline} aria-hidden="true">
                      {frames('commission.underline').map((a, i) => (
                        <GenSvg key={i} art={a} className={`${css.underlineFrame} ${css[`frame${i}`]}`} />
                      ))}
                    </span>
                  </span>
                </h2>
              </div>
              <div className={css.rows}>
                <div className={`${css.row} ${css.isDirect}`}>
                  <div className={css.visualColumn}>
                    <div className={css.clientDiagram} aria-hidden="true">
                      <div className={css.clientPill}>
                        <span className={css.clientFaces}>
                          {[0, 1, 2].map((i) => (
                            <img key={i} loading="lazy" decoding="async" src={FACES[i]} alt="" />
                          ))}
                        </span>
                        <span>{TEXT.yourClient}</span>
                      </div>
                      <img ref={arrow} className={css.clientArrow} loading="lazy" decoding="async" src={ARROW} alt="" />
                      <span className={css.zeroMark} aria-hidden="true">
                        {frames('commission.zero').map((a, i) => (
                          <GenSvg key={i} art={a} className={`${css.zeroFrame} ${css[`frame${i}`]}`} />
                        ))}
                      </span>
                    </div>
                  </div>
                  <div className={`${css.copy} ${css.isDirectCopy}`}>
                    <h3>
                      <span>{TEXT.yourClientQuestion}</span> <strong>{TEXT.forever}</strong>
                    </h3>
                    <p>{TEXT.directBody}</p>
                    <button type="button" className={css.whyLink} onClick={openDrawer} data-selenium="start-selling.commission.button.why">
                      {TEXT.why}{' '}
                      <GenSvg art={art('commission.chevron')} className={css.whyChevron} />
                    </button>
                  </div>
                </div>
                <div className={css.divider}>
                  <span />
                </div>
                <div className={`${css.row} ${css.isReferral}`}>
                  <div className={css.visualColumn}>
                    <CommissionTyping variant={typingVariant} />
                  </div>
                  <div className={`${css.copy} ${css.isReferralCopy}`}>
                    <h3>
                      <span className={css.copyDesktop}>{TEXT.foundDesktop}</span> <span className={css.copyCompact}>{TEXT.foundCompact}</span>{' '}
                      <strong>{TEXT.referralOnly}</strong>
                    </h3>
                    <p>{TEXT.referralBody}</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
        <div ref={runway} className={css.runway} aria-hidden="true" />
      </div>
    </section>
  );
}
