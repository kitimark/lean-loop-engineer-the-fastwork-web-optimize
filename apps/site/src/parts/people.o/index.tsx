import { useEffect, useRef, useState } from 'react';
import { getClock } from '../../engine/clock';
import { getScrollEngine } from '../../engine/scroll';
import { avatarOf, bg, postOf } from '../people/assets';
import { O_ORDER, byId } from '../people/data';
import { after, ORDER } from '../people/shared';
import { createOpener, type OFlags } from './driver';
import { cardLeft, cardTop, cardWidth, THRESHOLD } from './logic';
import { matchList } from './media';
import { keep as keepHeld, regime, type Held } from './preview';
import css from './o.module.css';

export interface PeopleOProps {
  variant: string;
  /** shown without the screen-reader "o" (the original's `standalone` option; unused on the home page) */
  standalone?: boolean;
  onGetStarted?: () => void;
}

const HIDE_MS = 140;

/**
 * people.o (`faithful`): the "o" of "people". When the heading is 35 % in view the ring draws six faces after 1.3 s and opens
 * 120 ms later; hovering or focusing a face (wider than 860 px, once open) shows a seller card next to it. All state changes
 * at event or timer times; the card position is written to the element's style, not through React state. Faces are
 * neutral fills (the photos are not shipped); the "o" glyph is the snapshot's o.svg, served by URL.
 */
export function PeopleO({ variant, standalone = false, onGetStarted }: PeopleOProps) {
  const [flags, setFlags] = useState<OFlags>({ stack: false, expanded: false });
  const [hover, setHover] = useState<number | null>(null);
  const flagsRef = useRef(flags);
  flagsRef.current = flags;
  const anchorRef = useRef<HTMLElement | null>(null);
  const previewRef = useRef<HTMLDivElement | null>(null);
  const rootRef = useRef<HTMLSpanElement>(null);
  const hideRef = useRef<(() => void) | null>(null);
  const narrowRef = useRef<MediaQueryList | null>(null);
  const heldRef = useRef<Held | null>(null);
  const translateFlag = variant === 'preview-translate';
  const blockFlag = variant === 'block' && !standalone;

  const place = () => {
    const a = anchorRef.current;
    const p = previewRef.current;
    if (!a || !p) return;
    const r = a.getBoundingClientRect();
    if (translateFlag) {
      const y = window.scrollY;
      const input: Held = { vw: window.innerWidth, vh: window.innerHeight, x: r.left, s: r.width, t: r.top, b: r.bottom, y0: y };
      const held = heldRef.current;
      const d = window.devicePixelRatio || 1;
      if (held && keepHeld({ d, held, input, y })) {
        const tr = regime(held) === 'aboveClamped' ? 0 : held.y0 - y;
        p.style.translate = tr === 0 ? '' : `0 ${tr}px`;
        return;
      }
      heldRef.current = input;
      p.style.translate = '';
    }
    p.style.left = `${cardLeft({ vw: window.innerWidth, x: r.left, s: r.width })}px`;
    p.style.top = `${cardTop({ vh: window.innerHeight, y: r.top, z: r.bottom })}px`;
    p.style.width = `${cardWidth({ vw: window.innerWidth })}px`;
  };

  useEffect(() => {
    const reduce = matchList('mq.rm-reduce');
    const narrow = matchList('mq.w-le-860');
    const heading = document.getElementById('future-heading');
    const clock = getClock();
    const opener = createOpener({
      clock,
      reduced: reduce?.matches ?? false,
      standalone,
      onFlags: setFlags,
      onReset: () => {
        hideRef.current?.();
        hideRef.current = null;
        setHover(null);
        anchorRef.current = null;
      },
    });
    const io = new IntersectionObserver(([e]) => opener.visibility(!!e?.isIntersecting), { threshold: THRESHOLD });
    if (heading) io.observe(heading);
    // the card follows its face on scroll and resize (N2:6251 `dE(A, { manageAnimations: false })`)
    const off = getScrollEngine().register('people.o', ORDER.o, () => place());
    narrowRef.current = narrow;
    return () => {
      io.disconnect();
      opener.dispose();
      hideRef.current?.();
      hideRef.current = null;
      off();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [standalone]);

  const show = (i: number, el: HTMLElement) => {
    if (!flagsRef.current.expanded || (narrowRef.current?.matches ?? false)) return;
    hideRef.current?.();
    hideRef.current = null;
    anchorRef.current = el;
    setHover(i);
  };
  const hide = () => {
    hideRef.current?.();
    hideRef.current = after(getClock(), HIDE_MS, () => {
      hideRef.current = null;
      anchorRef.current = null;
      setHover(null);
    });
  };
  const keep = () => {
    hideRef.current?.();
    hideRef.current = null;
  };

  useEffect(() => {
    heldRef.current = null;
    if (hover !== null) place();
  }, [hover]);

  const sellers = O_ORDER.map(byId);
  const cur = hover === null ? null : sellers[hover]!;
  const [city, ...rest] = cur ? cur.location.split(',') : [''];
  return (
    <>
      <span
        ref={rootRef}
        className={[css.o, flags.stack && css.isStack, flags.expanded && css.isExpanded, blockFlag && css.isBlock, standalone && css.isStandalone].filter(Boolean).join(' ')}
        data-fw="people-o"
        data-fw-variant={variant}
        data-o-stack={flags.stack ? 'true' : 'false'}
      >
        <span className={css.stage}>
          <img loading="lazy" decoding="async" className={css.vector} src="/selling/people-wordmark/o.svg" alt="" width={26} height={26} draggable={false} aria-hidden="true" />{' '}
          <span className={css.stack}>
            {sellers.map((p, i) => (
              <button
                key={p.id}
                type="button"
                className={hover === i ? `${css.face} ${css.isHovered}` : css.face}
                style={{ '--o-face': i } as React.CSSProperties}
                aria-label={`Preview ${p.name}`}
                aria-expanded={hover === i}
                disabled={!flags.expanded}
                data-selenium={`start-selling.people.button.preview.${p.id}`}
                onMouseEnter={(e) => show(i, e.currentTarget)}
                onFocus={(e) => show(i, e.currentTarget)}
                onClick={(e) => show(i, e.currentTarget)}
                onMouseLeave={hide}
                onBlur={hide}
              >
                <span className={css.faceFill} style={bg(avatarOf(p))} />
              </button>
            ))}
          </span>
        </span>
      </span>{' '}
      {!standalone && <span className={css.srOnly}>o</span>}
      {cur && (
        <div ref={previewRef} className={css.preview} role="tooltip" onMouseEnter={keep} onMouseLeave={hide}>
          <article className={css.sellerCard}>
            <div className={css.sellerHero}>
              <div className={css.sellerStrip}>
                {cur.posts.slice(0, 3).map((post) => (
                  <div key={post.id} className={css.sellerTile} style={bg(postOf(cur, post))} />
                ))}
              </div>
            </div>
            <div className={css.sellerContent}>
              <span className={css.sellerAvatar} style={bg(avatarOf(cur))} />
              <div className={css.sellerIdentity}>
                <strong>{cur.name}</strong>
                <p>
                  {city?.trim()}
                  {rest.length > 0 ? ', Thailand' : ''}
                </p>
              </div>
              <dl aria-label="Seller statistics">
                <div>
                  <dt>Earned</dt>
                  <dd>{cur.stats.earned}</dd>
                </div>
                <div>
                  <dt>Orders</dt>
                  <dd>{String(cur.stats.orders)}</dd>
                </div>
                <div>
                  <dt>Reviews</dt>
                  <dd>{`★ ${cur.stats.rating.toFixed(1)}`}</dd>
                </div>
              </dl>
              <button type="button" className={css.sellerMessage} data-selenium="start-selling.people.button.message" onClick={onGetStarted}>
                Message
              </button>
              <p className={css.sellerBio}>{cur.bio}</p>
              <ul className={css.sellerTags}>
                {cur.tags.slice(0, 3).map((t) => (
                  <li key={t}>{t}</li>
                ))}
              </ul>
            </div>
          </article>
        </div>
      )}
    </>
  );
}
