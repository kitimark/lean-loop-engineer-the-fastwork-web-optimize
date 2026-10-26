import { useEffect, useRef, useState } from 'react';
import { GenShape, GenSvg, art } from '../../GenSvg';
import { getClock } from '../../engine/clock';
import { createAskDriver, createCountUp, observeVisible } from '../platform.entries/driver';
import type { View } from '../platform.entries/logic';
import { PROFILE_TARGET } from '../platform.entries/logic';
import { createGlintDriver } from '../platform.glint/driver';
import { createPause } from '../platform.glint/pause';
import { holdElements, X1, X2 } from '../platform.glint/logic';
import { ASK_TITLE, FLAGS, NETWORK, ORDERS, PROFILE, QUOTE, REVIEWS, TOPICS, UK_LAYERS, type Service } from './content';
import { matchList } from './media';
import v from './visuals.module.css';

/** Which sub-parts are the faithful ones (anything else leaves the visual static, the hook for later variants). */
export interface Subs {
  entries: boolean;
  entriesFill?: boolean;
  glint: boolean;
  glintPause?: boolean;
  glintHold?: boolean;
  marquee: boolean;
}

const cx = (...c: Array<string | false | undefined>) => c.filter(Boolean).join(' ');
const reducedNow = () => matchList('mq.rm-reduce')?.matches ?? false;

/** Toggles a class on an element from a callback; direct DOM write, never React state. */
function toggle(el: Element | null, name: string, on: boolean) {
  el?.classList.toggle(name, on);
}

function Star() {
  return (
    <GenSvg art={art('platform.star')} />
  );
}

// ---- row 1: profile phone with the reviews marquee -------------------------------------------------------------------

export function Profile({ subs }: { subs: Subs }) {
  const root = useRef<HTMLDivElement>(null);
  const nums = useRef<Array<HTMLElement | null>>([]);
  useEffect(() => {
    const el = root.current;
    if (!el) return;
    const reduced = reducedNow();
    if (reduced || !subs.entries) {
      toggle(el, v.isStatic!, true);
      return;
    }
    const w = [
      (n: number) => `฿${n}K`,
      (n: number) => String(n),
      (n: number) => String(n),
      (n: number) => ` ${n}`,
    ];
    const T = [PROFILE_TARGET.earnedK, PROFILE_TARGET.orders, PROFILE_TARGET.rehires, PROFILE_TARGET.reviews];
    const count = createCountUp(
      {
        clock: getClock(),
        targets: T.map((n, i) => ({
          n,
          write: (x: number) => {
            const node = nums.current[i];
            if (node?.lastChild) node.lastChild.nodeValue = w[i]!(x);
          },
        })),
      },
      reducedNow,
    );
    let seen = false;
    const off = observeVisible(el, (vis) => {
      toggle(el, v.isEnter!, vis);
      if (vis && !seen) count.start(performance.now());
      else if (!vis) count.cancel();
      seen = vis;
    });
    return () => {
      off();
      count.cancel();
    };
  }, [subs.entries]);
  const numClass = (i: number) => (n: HTMLElement | null) => {
    nums.current[i] = n;
  };
  return (
    <div ref={root} className={cx(v.profile, subs.entriesFill && v.fillRelease)} data-fw-visual="profile" aria-hidden="true">
      <div className={v.phone}>
        <div className={v.profileHead}>
          <div className={v.profileId}>
            <img className={v.avatar} loading="lazy" decoding="async" src="/selling/media/avatar-cat.png" alt="" width="57" height="57" />
            <div>
              <p className={v.name}>{PROFILE.name}</p>
              <p className={v.handle}>
                {PROFILE.handle} <span>{PROFILE.followers}</span>
              </p>
            </div>
          </div>
          <p className={v.bio}>{PROFILE.bio}</p>
          <p className={v.loc}>
            <GenSvg art={art('platform.pin')} />{' '}
            {PROFILE.location}
          </p>
        </div>
        <div className={v.stats}>
          <div>
            <strong ref={numClass(0)}>฿0K</strong>{' '}
            <span>{PROFILE.stats[0]}</span>
          </div>
          <span className={v.rule} />
          <div>
            <strong ref={numClass(1)}>0</strong>{' '}
            <span>{PROFILE.stats[1]}</span>
          </div>
          <span className={v.rule} />
          <div>
            <strong ref={numClass(2)}>0</strong>{' '}
            <span>{PROFILE.stats[2]}</span>
          </div>
          <span className={v.rule} />
          <div>
            <strong ref={numClass(3)}>
              <Star /> 0
            </strong>{' '}
            <span>{PROFILE.stats[3]}</span>
          </div>
        </div>
        <div className={v.masonry}>
          <div className={v.col}>
            <Tile t={PROFILE.tiles[0]} />
            <Tile t={PROFILE.tiles[1]} />
          </div>
          <div className={v.col}>
            <Tile t={PROFILE.tiles[2]} />
          </div>
        </div>
      </div>
      <div className={v.reviews}>
        <div className={v.track} data-marquee={subs.marquee ? 'faithful' : 'off'}>
          {['a', 'b'].map((k) => (
            <div key={k} className={v.credSet}>
              {REVIEWS.map((r, i) => (
                <div key={r.name} className={v.credCard} style={{ ['--cred-enter-delay' as string]: `${i * 70}ms` }}>
                  <div className={v.credRating}>
                    <img loading="lazy" decoding="async" src="/selling/platform/features/credibility/star.svg" alt="" width="16" height="16" />
                    <span>5.0</span>
                  </div>
                  <div className={v.credBody}>
                    <p className={v.credQuote}>{r.quote}</p>
                    <div className={v.credAuthor}>
                      <img loading="lazy" decoding="async" src={r.avatar} alt="" width="40" height="40" />
                      <span>{r.name}</span>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function Tile({ t }: { t: (typeof PROFILE.tiles)[number] }) {
  return (
    <div className={cx(v.tile, v[t.size])}>
      <img loading="lazy" decoding="async" src={t.src} alt="" />
      <span className={v.price}>{t.price}</span>
    </div>
  );
}

// ---- row 2: search ---------------------------------------------------------------------------------------------------

function ServiceCard({ s, i }: { s: Service; i: number }) {
  return (
    <div className={v.service} style={{ ['--ask-service-index' as string]: i }}>
      <span className={v.thumb}>
        <picture>
          {s.avif ? <source srcSet={s.avif} type="image/avif" /> : null}
          <img loading="lazy" decoding="async" src={s.thumb} alt="" width="120" height="120" />
        </picture>
      </span>
      <div className={v.serviceBody}>
        <p className={v.serviceTitle}>{s.title}</p>
        <p className={v.serviceDesc}>{s.desc}</p>
        <p className={v.serviceRating}>
          <Star /> {s.rating}
        </p>
        <p className={v.servicePrice}>{s.price}</p>
      </div>
    </div>
  );
}

const EMPTY_VIEW: View = { len: 0, topic: 0, shown: 0, leaving: false, results: false, caret: false };

export function Ask({ subs }: { subs: Subs }) {
  const root = useRef<HTMLDivElement>(null);
  const field = useRef<HTMLSpanElement>(null);
  const [view, setView] = useState<View>(EMPTY_VIEW);
  const [enter, setEnter] = useState(false);
  const [isStatic, setStatic] = useState(false);
  useEffect(() => {
    const el = root.current;
    if (!el) return;
    if (reducedNow() || !subs.entries) {
      setStatic(true);
      if (field.current) field.current.textContent = TOPICS[0]!.query;
      setView({ ...EMPTY_VIEW, results: true });
      return;
    }
    const driver = createAskDriver({
      clock: getClock(),
      queries: TOPICS.map((t) => t.query),
      write: (text, caret) => {
        if (field.current) {
          if (field.current.textContent !== text) field.current.textContent = text;
          toggle(field.current, v.caret!, caret);
        }
      },
      onView: setView,
    });
    const off = observeVisible(el, (vis) => {
      setEnter(vis);
      if (vis) driver.start();
      else driver.stop();
    });
    return () => {
      off();
      driver.stop();
    };
  }, [subs.entries]);
  const shown = TOPICS[view.shown]!.services;
  const out = TOPICS[(view.shown + TOPICS.length - 1) % TOPICS.length]!.services;
  return (
    <div ref={root} className={cx(v.ask, subs.entriesFill && v.fillRelease, isStatic && v.isStatic, enter && v.isEnter, view.results && v.isResults, view.leaving && v.isLeaving)} data-fw-visual="ask" aria-hidden="true">
      <div className={v.askBox}>
        <div className={v.askHero}>
          <p className={v.askTitle}>{ASK_TITLE}</p>
          <div className={v.askField}>
            <GenSvg art={art('platform.search')} />{' '}
            <span ref={field} />
          </div>
        </div>
        <div className={v.askList}>
          {shown.map((s, i) => (
            <ServiceCard key={s.title} s={s} i={i} />
          ))}
          {view.leaving ? (
            <div className={v.askListOut}>
              {out.map((s, i) => (
                <ServiceCard key={`out-${s.title}`} s={s} i={i} />
              ))}
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}

// ---- row 3: secure payment network ---------------------------------------------------------------------------------

const KEYTIMES = '0;0.2;0.4;0.6;0.8;1';

function HoldRing({ side, idBase }: { side: 'left' | 'right'; idBase: string }) {
  return (
    <>
      {holdElements(side, idBase).map((e) => {
        const common = { id: e.id, attributeName: e.attributeName, to: e.to, dur: e.dur, fill: e.fill, begin: e.begin, 'data-fw-anchor': e.anchor ? '' : undefined };
        return e.tag === 'set' ? <set key={e.id} {...common} /> : <animate key={e.id} {...common} from={e.from} />;
      })}
    </>
  );
}

function Dash({ side, playing, hold }: { side: 'left' | 'right'; playing: boolean; hold?: boolean }) {
  const ref = useRef<SVGSVGElement>(null);
  const id = `secure-network-dash-${side}`;
  useEffect(() => {
    if (!playing) return;
    // the original calls beginElement() on every <animate> right after they render: the SMIL clock restarts there
    for (const a of ref.current?.querySelectorAll(hold ? '[data-fw-anchor]' : 'animate') ?? []) {
      try {
        (a as SVGAnimationElement).beginElement();
      } catch {
        /* unsupported */
      }
    }
  }, [playing, hold]);
  return (
    <span className={cx(v.dash, side === 'left' ? v.dashLeft : v.dashRight)} data-fw-dash={side}>
      <svg ref={ref} className={v.dashSvg} width="94" height="3.2" viewBox="0 0 94 3.2" fill="none" overflow="visible" aria-hidden="true">
        <defs>
          <linearGradient id={id} gradientUnits="userSpaceOnUse" x1={side === 'right' ? 200 : -200} x2={side === 'right' ? 320 : -80} y1="0" y2="0">
            <stop offset="0%" stopColor="#84b5ff" stopOpacity="0" />
            <stop offset="20%" stopColor="#84b5ff" stopOpacity="1" />
            <stop offset="40%" stopColor="#0569ff" stopOpacity="1" />
            <stop offset="60%" stopColor="#ae8eff" stopOpacity="1" />
            <stop offset="80%" stopColor="#ffcca5" stopOpacity="1" />
            <stop offset="100%" stopColor="#ffcca5" stopOpacity="0" />
            {playing && hold ? <HoldRing side={side} idBase={`fwglint${side}`} /> : null}
            {playing && !hold ? (
              <>
                <animate attributeName="x1" begin="indefinite" repeatCount="indefinite" keyTimes={KEYTIMES} dur="5s" values={X1[side].join(';')} />
                <animate attributeName="x2" begin="indefinite" repeatCount="indefinite" keyTimes={KEYTIMES} dur="5s" values={X2[side].join(';')} />
              </>
            ) : null}
          </linearGradient>
        </defs>
        <GenShape art={art(side === 'left' ? 'platform.dashLeft' : 'platform.dashRight')} className={cx(v.highlight, playing && v.highlightActive)} stroke={`url(#${id})`} />
      </svg>
    </span>
  );
}

export function Secure({ subs }: { subs: Subs }) {
  const root = useRef<HTMLDivElement>(null);
  const [playing, setPlaying] = useState(false);
  useEffect(() => {
    const el = root.current;
    if (!el) return;
    const reduce = matchList('mq.rm-reduce');
    toggle(el, v.isStatic!, reduce?.matches ?? false);
    if (!subs.entries && !subs.glint) {
      toggle(el, v.isStatic!, true);
      return;
    }
    const clock = getClock();
    const glint = subs.glint
      ? createGlintDriver({
          clock,
          now: () => performance.now(),
          reduced: reducedNow,
          onState: (s) => setPlaying(s.v),
        })
      : null;
    const pause = subs.glintPause
      ? createPause(() => Array.from(el.querySelectorAll<SVGSVGElement>('[data-fw-dash] svg')), () => performance.now())
      : null;
    let ratio = 0;
    const io = new IntersectionObserver(
      ([e]) => {
        ratio = e?.isIntersecting ? e.intersectionRatio : 0;
        const visible = ratio >= 0.35;
        toggle(el, v.isPlay!, visible && !(reduce?.matches ?? false));
        pause?.ratio(ratio);
        glint?.ratio(ratio);
      },
      { threshold: [0, 0.35, 0.6] },
    );
    io.observe(el);
    const onReduce = () => {
      toggle(el, v.isStatic!, reduce?.matches ?? false);
      toggle(el, v.isPlay!, ratio >= 0.35 && !(reduce?.matches ?? false));
      glint?.reducedChanged(reduce?.matches ?? false);
    };
    reduce?.addEventListener('change', onReduce);
    return () => {
      io.disconnect();
      reduce?.removeEventListener('change', onReduce);
      glint?.dispose();
    };
  }, [subs.entries, subs.glint, subs.glintPause]);
  return (
    <div ref={root} className={cx(v.secure, subs.entriesFill && v.fillRelease)} data-fw-visual="secure" aria-hidden="true">
      <img className={v.rings} loading="lazy" decoding="async" src={`${NETWORK}/hex-rings.svg`} alt="" width="542" height="600" draggable={false} />
      <Dash side="left" playing={playing} hold={subs.glintHold} />
      <Dash side="right" playing={playing} hold={subs.glintHold} />
      <img className={cx(v.face, v.faceLeft)} loading="lazy" decoding="async" src={`${NETWORK}/portrait-left.png`} alt="" width="96" height="96" draggable={false} />
      <img className={cx(v.face, v.faceRight)} loading="lazy" decoding="async" src={`${NETWORK}/portrait-right.png`} alt="" width="96" height="96" draggable={false} />
      <div className={v.shield}>
        <div className={v.shieldArt}>
          <span className={v.shieldFillWrap}>
            <img className={v.shieldImg} loading="lazy" decoding="async" src={`${NETWORK}/shield-fill.svg`} alt="" draggable={false} />
          </span>
          <span className={v.shieldBorderWrap}>
            <span className={v.shieldBorderInset}>
              <img className={v.shieldImg} loading="lazy" decoding="async" src={`${NETWORK}/shield-border.svg`} alt="" draggable={false} />
            </span>
          </span>
          <span className={v.shieldSheenWrap}>
            <span className={v.shieldSheenInset}>
              <img className={v.shieldImg} loading="lazy" decoding="async" src={`${NETWORK}/shield-sheen.svg`} alt="" draggable={false} />
            </span>
          </span>
          <span className={v.shieldLogo}>
            <span className={v.logoMark}>
              <GenSvg art={art('platform.shield')} />
            </span>
          </span>
        </div>
      </div>
      <div className={v.flags}>
        {FLAGS.map((f) => (
          <span key={f.id} className={cx(v.flag, f.bordered && v.flagBordered, f.id === 'us' && v.flagUs)} style={{ width: 40, height: 40 }}>
            {f.id === 'kr' ? (
              <>
                <span className={v.krFill}>
                  <img loading="lazy" decoding="async" src={`${NETWORK}/flag-kr-base.svg`} alt="" draggable={false} />
                </span>
                <span className={cx(v.krArm, v.krArmA)}>
                  <span>
                    <img loading="lazy" decoding="async" src={`${NETWORK}/flag-kr-trigram-a.svg`} alt="" draggable={false} />
                  </span>
                </span>
                <span className={cx(v.krArm, v.krArmB)}>
                  <span>
                    <img loading="lazy" decoding="async" src={`${NETWORK}/flag-kr-trigram-b.svg`} alt="" draggable={false} />
                  </span>
                </span>
              </>
            ) : f.id === 'uk' ? (
              UK_LAYERS.map((l) => <img key={l} loading="lazy" decoding="async" src={`${NETWORK}/${l}.svg`} alt="" draggable={false} />)
            ) : (
              <img loading="lazy" decoding="async" src={`${NETWORK}/flag-${f.id}.svg`} alt="" draggable={false} />
            )}
          </span>
        ))}
      </div>
    </div>
  );
}

// ---- row 4: orders and the quotation card -------------------------------------------------------------------------

export function Invoice({ subs }: { subs: Subs }) {
  const root = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = root.current;
    if (!el) return;
    const reduce = matchList('mq.rm-reduce');
    toggle(el, v.isStatic!, (reduce?.matches ?? false) || !subs.entries);
    if (!subs.entries) return;
    let vis = false;
    const apply = () => toggle(el, v.isPlay!, vis && !(reduce?.matches ?? false));
    const off = observeVisible(el, (x) => {
      vis = x;
      apply();
    });
    const onReduce = () => {
      toggle(el, v.isStatic!, reduce?.matches ?? false);
      apply();
    };
    reduce?.addEventListener('change', onReduce);
    return () => {
      off();
      reduce?.removeEventListener('change', onReduce);
    };
  }, [subs.entries]);
  return (
    <div ref={root} className={cx(v.invoice, subs.entriesFill && v.fillRelease)} data-fw-visual="invoice" aria-hidden="true">
      <div className={v.sheet}>
        <ul className={v.orderList}>
          {ORDERS.map((o, i) => (
            <li key={o.name} className={v.order} style={{ ['--orders-card-delay' as string]: `${i * 140}ms` }}>
              <div className={v.orderCopy}>
                <p className={v.orderName}>{o.name}</p>
                <p className={v.orderMeta}>{o.meta}</p>
              </div>
              <div className={v.orderAside}>
                <p className={v.orderPrice}>{o.price}</p>
                <div className={v.orderFlags}>
                  <span className={cx(v.dot, v[`dot${cap(o.pay[1])}`])} />
                  <span className={cx(v.chip, v[`chip${cap(o.pay[1])}`])}>{o.pay[0]}</span>
                  <span className={cx(v.chip, v[`chip${cap(o.work[1])}`])}>{o.work[0]}</span>
                </div>
              </div>
            </li>
          ))}
        </ul>
      </div>
      <div className={v.cardEnter}>
        <div className={v.quote}>
          <p className={v.kicker}>{QUOTE.kicker}</p>
          <p className={v.valid}>{QUOTE.valid}</p>
          <p className={v.amount}>{QUOTE.amount}</p>
          <p className={v.pack}>{QUOTE.pack}</p>
          <div className={v.stubWrap}>
            <div className={v.stub}>
              <span className={cx(v.bar, v.barCap)} />
              <span className={cx(v.bar, v.barLong)} />
              <span className={cx(v.bar, v.barMid)} />
              <span className={cx(v.bar, v.barMid)} />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

const cap = (s: string) => s[0]!.toUpperCase() + s.slice(1);
