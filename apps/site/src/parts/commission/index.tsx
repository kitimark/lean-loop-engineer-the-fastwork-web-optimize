import { useEffect, useRef } from 'react';
import { getClock } from '../../engine/clock';
import { getScrollEngine } from '../../engine/scroll';
import { CommissionTyping } from '../commission.typing';
import { mediaCondition } from '../../breakpoints';
import { openDrawer } from '../overlays.drawer';
import { ARROW, ARROW_COMPACT, FACES, TEXT, UNDERLINE_PATHS, ZERO_PATHS } from './data';
import { mountCommission } from './driver';
import { matchList } from './media';
import css from './commission.module.css';

export interface CommissionProps {
  variant: string;
  /** variant of the part `commission.typing` rendered in the second row */
  typingVariant?: string;
}

/**
 * commission (P4): a rounded white card that shrinks in from the pain section and out to the platform section, with a
 * hand-drawn underline on the heading and two rows (bring your own client, a client from us). The shrink is the Lean
 * `frame` run by `driver.ts` on the scroll engine; the typing visual in the second row is the part `commission.typing`.
 * Plain elements and a CSS Module; pictures bundled from the snapshot. The "why bring a client" link opens the drawer of
 * overlays.drawer (`openDrawer`, a discrete flag).
 */
export function Commission({ variant, typingVariant = 'faithful' }: CommissionProps) {
  const section = useRef<HTMLElement>(null);
  const card = useRef<HTMLDivElement>(null);
  const runway = useRef<HTMLDivElement>(null);
  const header = useRef<HTMLDivElement>(null);
  const title = useRef<HTMLHeadingElement>(null);
  const muted = useRef<HTMLSpanElement>(null);
  const underline = useRef<HTMLSpanElement>(null);

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
    });
  }, []);

  return (
    <section ref={section} className={css.commission} aria-labelledby="commission-heading" data-fw="commission" data-fw-variant={variant}>
      <div className={css.track}>
        <div className={css.sticky}>
          <div ref={card} className={css.card}>
            <div className={css.inner}>
              <div ref={header} className={css.header}>
                <h2 ref={title} id="commission-heading">
                  <span ref={muted} className={css.titleMuted}>
                    {TEXT.titleBase}
                  </span>{' '}
                  <span className={css.titleAccent}>
                    {TEXT.titleAccent}{' '}
                    <span ref={underline} className={css.underline} aria-hidden="true">
                      {UNDERLINE_PATHS.map((d, i) => (
                        <svg key={i} className={`${css.underlineFrame} ${css[`frame${i}`]}`} viewBox="0 0 199.201 19.8599" preserveAspectRatio="none">
                          <path pathLength={1} d={d} />
                        </svg>
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
                      <picture>
                        <source media={mediaCondition('mq.c1000')} srcSet={ARROW_COMPACT} />
                        <img className={css.clientArrow} loading="lazy" decoding="async" src={ARROW} alt="" />
                      </picture>
                      <span className={css.zeroMark} aria-hidden="true">
                        {ZERO_PATHS.map((paths, i) => (
                          <svg key={i} className={`${css.zeroFrame} ${css[`frame${i}`]}`} viewBox="0 0 107.498 98.0007" fill="none" xmlns="http://www.w3.org/2000/svg">
                            {paths.map((d, j) => (
                              <path key={j} d={d} stroke="#2B313B" strokeWidth={j === 0 ? 8 : 4.8} strokeLinecap={j === 0 ? undefined : 'round'} />
                            ))}
                          </svg>
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
                      <svg className={css.whyChevron} viewBox="0 0 16 16" aria-hidden="true">
                        <path d="M6 3.33333L10 8L6 12.6667" />
                      </svg>
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
