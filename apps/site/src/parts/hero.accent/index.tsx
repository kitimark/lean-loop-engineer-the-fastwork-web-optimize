import { useEffect, useRef } from 'react';
import { getClock } from '../../engine/clock';
import { startAccentChain } from './driver';
import { artOf, BASE_ART } from './data';
import { BASE_WIDTH, widthOf, type AccentState } from './logic';
import { matchList } from './media';
import css from './accent.module.css';

export interface HeroAccentProps {
  variant: string;
}

const widthCalc = (w: number) => `calc(${w} / 64 * 1em)`;
const stateClass = (s: AccentState) => (s === 'idle' ? css.idle : s === 'draw-out' ? css.drawingOut : css.drawingIn);
const FRAMES = [0, 1, 2] as const;
const frameCls = [css.frame0, css.frame1, css.frame2] as const;

/**
 * hero.accent: the hand-drawn word inside the headline. Server and first client render show the base word, idle. After
 * mount the timer chain (Lean `HeroAccent.chainAt`) writes the state class every 0.9 s or more and, at each word change,
 * the box width, paint insets, view box and stroke of the three frames, straight on the DOM (no React state, nothing per
 * frame). Strokes are the original's hand-drawn paths.
 */
export function HeroAccent({ variant }: HeroAccentProps) {
  const emRef = useRef<HTMLElement>(null);

  useEffect(() => {
    const em = emRef.current;
    if (!em) return;
    const reduce = matchList('mq.rm-reduce');
    if (reduce?.matches) return; // the original returns before any timer (N2:3680)
    const frame = em.querySelector<HTMLElement>('[data-frame]')!;
    const paint = em.querySelector<HTMLElement>('[data-paint]')!;
    const svgs = [...em.querySelectorAll<SVGSVGElement>('svg')];
    const clock = getClock();
    const chain = startAccentChain({
      clock,
      hooks: {
        onState(s) {
          em.className = `${css.accent} ${stateClass(s)}`;
        },
        onCursor(c) {
          const w = widthOf({ c });
          const art = artOf(c);
          em.style.width = widthCalc(w);
          frame.style.width = widthCalc(w);
          paint.style.top = art.inset.top;
          paint.style.right = art.inset.right;
          paint.style.bottom = art.inset.bottom;
          paint.style.left = art.inset.left;
          em.setAttribute('aria-label', art.label);
          svgs.forEach((svg, k) => {
            svg.setAttribute('viewBox', `0 0 ${art.viewBox[0]} ${art.viewBox[1]}`);
            svg.querySelector('path')!.setAttribute('d', art.paths[k]!);
          });
        },
      },
    });
    const io = new IntersectionObserver(([entry]) => chain.setVisible(!!entry?.isIntersecting), { rootMargin: '100% 0px' });
    io.observe(em);
    return () => {
      chain.stop();
      io.disconnect();
    };
  }, []);

  const [vw, vh] = BASE_ART.viewBox;
  const inset = BASE_ART.inset;
  return (
    <em
      ref={emRef}
      className={`${css.accent} ${css.idle}`}
      data-fw="hero-accent"
      data-fw-variant={variant}
      aria-label={BASE_ART.label}
      style={{ width: widthCalc(BASE_WIDTH), height: 'calc(74 / 64 * 1em)' }}
    >
      <span className={css.sizer} aria-hidden="true" />{' '}
      <span className={css.frame} aria-hidden="true" data-frame style={{ width: widthCalc(BASE_WIDTH) }}>
        <span className={css.paint} data-paint style={{ top: inset.top, right: inset.right, bottom: inset.bottom, left: inset.left }}>
          {FRAMES.map((k) => (
            <svg
              key={k}
              className={`${css.svg} ${css.idleFrame} ${frameCls[k]}`}
              viewBox={`0 0 ${vw} ${vh}`}
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path
                className={css.path}
                pathLength={1}
                stroke="currentColor"
                strokeWidth={6.5}
                strokeLinecap="round"
                strokeLinejoin="round"
                d={BASE_ART.paths[k]}
              />
            </svg>
          ))}
        </span>
      </span>
    </em>
  );
}
