import { useEffect, useRef } from 'react';
import { getClock } from '../../engine/clock';
import { mountTyping } from './driver';
import { matchList } from './media';
import css from './typing.module.css';

export interface CommissionTypingProps {
  variant: string;
}

/** Placeholder pictures (the original's avatars are not copied): a flat grey square, scaled by the avatar's own box. */
const PHOTO =
  "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='1' height='1'%3E%3Crect width='1' height='1' fill='%23cfd4dc'/%3E%3C/svg%3E";

/**
 * commission.typing: the fee visual of the referral row (432 x 224 design box scaled to its column). The markup is static;
 * `driver.ts` types the message and counts the numbers from the Lean timeline while the box is on screen.
 */
export function CommissionTyping({ variant }: CommissionTypingProps) {
  const scale = useRef<HTMLDivElement>(null);
  const visual = useRef<HTMLDivElement>(null);
  const beat = useRef<HTMLDivElement>(null);
  const avatar = useRef<HTMLSpanElement>(null);
  const message = useRef<HTMLDivElement>(null);
  const text = useRef<HTMLParagraphElement>(null);
  const referral = useRef<HTMLDivElement>(null);
  const amount = useRef<HTMLElement>(null);
  const percent = useRef<HTMLElement>(null);
  const fill = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    const els = {
      scale: scale.current,
      visual: visual.current,
      beat: beat.current,
      avatar: avatar.current,
      message: message.current,
      text: text.current,
      referral: referral.current,
      amount: amount.current,
      percent: percent.current,
      fill: fill.current,
    };
    if (!els.scale || !els.visual || !els.beat || !els.avatar || !els.message || !els.text || !els.referral || !els.amount || !els.percent || !els.fill) return;
    const reduce = matchList('mq.rm-reduce');
    return mountTyping({
      els: { ...els, parent: els.scale.parentElement } as Parameters<typeof mountTyping>[0]['els'],
      classes: { resetting: css.resetting!, scrollingOut: css.scrollingOut!, shown: css.shown!, caret: css.caret! },
      clock: getClock(),
      env: {
        now: () => performance.now(),
        reduced: () => reduce?.matches ?? false,
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
        createText: () => document.createTextNode(''),
        createCaret: (cls) => {
          const s = document.createElement('span');
          s.className = cls;
          return s;
        },
      },
    });
  }, []);

  return (
    <div ref={scale} className={css.scale} data-fw="commission-typing" data-fw-variant={variant}>
      <div ref={visual} className={css.visual} aria-hidden="true">
        <div ref={beat} className={css.beat}>
          <span ref={avatar} className={`${css.avatar} ${css.isLarge}`}>
            <img loading="lazy" decoding="async" src={PHOTO} alt="" />
          </span>
          <div className={css.stack}>
            <div ref={message} className={css.message}>
              <p ref={text} />
            </div>
            <div ref={referral} className={css.referral}>
              <p className={css.label}>Referral Fee</p>
              <div className={css.card}>
                <div className={css.cardRow}>
                  <div className={css.earned}>
                    <span className={css.earnedLine}>
                      <span>Earned from</span>
                      <span className={css.chip}>
                        <span className={`${css.avatar} ${css.isSmall}`}>
                          <img loading="lazy" decoding="async" src={PHOTO} alt="" />
                        </span>
                        John
                      </span>
                    </span>
                    <span className={css.amount}>
                      <strong ref={amount}>$0</strong>
                      <span>/100</span>
                    </span>
                  </div>
                  <strong ref={percent} className={css.percent}>
                    18%
                  </strong>
                </div>
                <div className={css.progress}>
                  <span ref={fill} style={{ width: '0%' }}>
                    <i />
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
