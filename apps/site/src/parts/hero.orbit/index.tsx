import { useEffect, useRef, type CSSProperties } from 'react';
import { getClock } from '../../engine/clock';
import { HeroCard } from './card';
import { CARDS, PIECES } from './data';
import { createOrbitDriver } from './driver';
import { CANVAS_H, CANVAS_W, CHIP, enterDelay, place, ringIndex, scatter, type Piece } from './logic';
import { matchList } from './media';
import css from './orbit.module.css';

export interface HeroOrbitProps {
  variant: string;
}

const RING = ringIndex(PIECES);

/**
 * Inline variables of a card at server render (the original's `L`, N2:4101-4120): position in percent of the canvas, size,
 * design left and right gaps, rest rotation, start rotation and offset on the ring, start scale, entrance delay, scatter.
 * Computed from the Lean-checked functions; the driver rewrites the three start variables during the splash.
 */
export function cardStyle(p: Piece, ring: number): CSSProperties {
  const leftPct = (p.left / CANVAS_W) * 100;
  const topPct = (p.top / CANVAS_H) * 100;
  const start = place({ left: p.left, top: p.top, width: p.width, height: p.height, idx: ring, n: CANVAS_W, e: 0, expanded: false });
  const left = (leftPct / 100) * CANVAS_W;
  const right = CANVAS_W - left - p.width;
  const sc = scatter({ left: p.left, top: p.top });
  return {
    left: `${leftPct}%`,
    top: `${topPct}%`,
    width: `${p.width}px`,
    height: `${p.height}px`,
    '--orbit-left-px': `${left}px`,
    '--orbit-right-px': `${right}px`,
    '--orbit-rot': `${p.rotate}deg`,
    '--orbit-start-rot': `${start.rotTenths / 10}deg`,
    '--orbit-enter-x': `${start.x}px`,
    '--orbit-enter-y': `${start.y}px`,
    '--ring-scale': `${CHIP / p.width}`,
    '--orbit-enter-delay': `${enterDelay({ k: p.unit })}ms`,
    '--scatter-x': `${sc.x}vw`,
    '--scatter-y': `${sc.y}vh`,
  } as CSSProperties;
}

/** A hovered card comes to the front: its z-index becomes one above the highest card's (N2:4121-4129). */
function raise(e: React.PointerEvent<HTMLElement>) {
  const cards = [...e.currentTarget.parentElement!.children] as HTMLElement[];
  const top = Math.max(1, ...cards.map((c) => Number(c.style.zIndex || 1)));
  e.currentTarget.style.zIndex = String(top + 1);
}

/**
 * hero.orbit: the ring of ten cards and its load splash. Server render: hero in `prep`, cards at their start offsets. After
 * mount the driver (Lean `HeroOrbit`) runs the splash on the clock, then sets `data-done`; under reduced motion or at
 * width <= 600 the splash is skipped.
 */
export function HeroOrbit({ variant }: HeroOrbitProps) {
  const orbitRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const orbit = orbitRef.current;
    const hero = orbit?.closest<HTMLElement>('[data-splash]');
    if (!orbit || !hero) return;
    const cards = [...orbit.querySelectorAll<HTMLElement>('[data-orbit-id]')];
    const reduce = matchList('mq.rm-reduce');
    const narrow = matchList('mq.w-le-600');
    const driver = createOrbitDriver({
      clock: getClock(),
      orbit,
      hero,
      cards,
      pieces: PIECES,
      ring: RING,
      innerWidth: () => window.innerWidth,
      perfNow: () => performance.now(),
      skip: () => (reduce?.matches ?? false) || (narrow?.matches ?? false),
    });
    driver.reset();
    const onNarrow = () => {
      if (narrow?.matches) driver.finish();
    };
    const onShow = (e: PageTransitionEvent) => {
      if (e.persisted) driver.reset();
    };
    narrow?.addEventListener('change', onNarrow);
    window.addEventListener('pageshow', onShow);
    return () => {
      driver.stop();
      narrow?.removeEventListener('change', onNarrow);
      window.removeEventListener('pageshow', onShow);
    };
  }, []);

  return (
    <div ref={orbitRef} className={css.orbit} data-fw="hero-orbit" data-fw-variant={variant} data-orbit="" aria-label="Featured portfolio cards">
      <div className={css.stage}>
        <div className={css.stage3d}>
          {PIECES.map((p, i) => (
            <HeroCard
              key={p.id}
              name={CARDS[i]!.name}
              role={CARDS[i]!.role}
              cover={CARDS[i]!.cover}
              avatar={CARDS[i]!.avatar}
              data-fw-layer="hero.orbit_card"
              data-orbit-id={p.id}
              data-orbit-side={p.left / CANVAS_W * 100 < 50 ? 'left' : 'right'}
              data-piece={p.id}
              style={cardStyle(p, RING[i]!)}
              onPointerEnter={raise}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
