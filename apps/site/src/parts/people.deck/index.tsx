import { useEffect, useRef, useState } from 'react';
import { getClock } from '../../engine/clock';
import { getScrollEngine } from '../../engine/scroll';
import { PROFILES } from '../people/data';
import { ORDER, watchActive } from '../people/shared';
import css from './deck.module.css';
import { createDeckDriver, type Box, type DeckEnv } from './driver';
import { matchList } from './media';
import { ProfilePanel } from './panel';

const IDS = PROFILES.map((p) => p.id);
type Driver = ReturnType<typeof createDeckDriver>;

/**
 * people.deck (`faithful` for the mechanics, delta for the panel content): the profile showcase. On wide viewports the
 * section is taller than the screen, the shell shrinks to its place and the tabs pick the profession as you scroll (driver.ts,
 * Lean `Fw.Parts.PeopleDeck`); on touch layouts it is a snap row of shells with a drag rail of tabs. The per-frame values go
 * to the DOM (`--profile-scale`, a transform on the active shell); React state holds only the profession, the rail flag and
 * the touch flag, which change at thresholds.
 */
export function PeopleDeck({ variant }: { variant: string }) {
  const [active, setActive] = useState(IDS[0]!);
  const [railIn, setRailIn] = useState(false);
  const [mobile, setMobile] = useState(false);
  const [dragging, setDragging] = useState(false);
  const activeRef = useRef(active);
  activeRef.current = active;
  const draggedRef = useRef(false);
  const driverRef = useRef<Driver | null>(null);
  const showcase = useRef<HTMLElement>(null);
  const sticky = useRef<HTMLDivElement>(null);
  const chrome = useRef<HTMLDivElement>(null);
  const tabs = useRef<HTMLDivElement>(null);
  const deck = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const els = [showcase.current, sticky.current, chrome.current, tabs.current, deck.current];
    if (els.some((e) => !e)) return;
    const [sc, st, ch, tb, dk] = els as HTMLElement[];
    const reduce = matchList('mq.rm-reduce');
    const touch = matchList('mq.c860');
    const wide = matchList('mq.w-ge-861');
    const env: DeckEnv = {
      showcase: sc as unknown as Box,
      sticky: st as unknown as Box,
      chrome: ch as unknown as Box,
      tabs: tb as unknown as Box,
      deck: dk as unknown as Box,
      reduced: () => reduce?.matches ?? false,
      mobileMatches: () => touch?.matches ?? false,
      wideMatches: () => wide?.matches ?? false,
      vh: () => window.innerHeight,
      vw: () => window.innerWidth,
      scrollY: () => window.scrollY,
      scrollTo: (top) => window.scrollTo({ top, behavior: 'smooth' }),
      onDeckScrollEnd: (fn) => {
        dk!.addEventListener('scrollend', fn);
        return () => dk!.removeEventListener('scrollend', fn);
      },
      onWindowScrollEnd: (fn) => {
        window.addEventListener('scrollend', fn, { once: true });
        return () => window.removeEventListener('scrollend', fn);
      },
      ids: IDS,
      getActive: () => activeRef.current,
      setActive: (id) => {
        activeRef.current = id;
        setActive(id);
      },
      setRailIn,
      setMobile,
      setDragging: (on) => {
        draggedRef.current = on;
        setDragging(on);
      },
    };
    const driver = createDeckDriver(env, getClock(), { activeClass: css.isActiveShell! });
    driverRef.current = driver;
    setMobile(touch?.matches ?? false);
    let isActive = false;
    const off = getScrollEngine().register('people.deck', ORDER.deck, () => {
      if (isActive) driver.request();
    });
    const stop = watchActive(sc!, (a) => {
      isActive = a;
      sc!.setAttribute('data-fw-scene', a ? 'active' : 'paused'); // the original's data-start-selling-scene (dE manageAnimations)
      if (a) driver.request();
    });
    const onTouch = () => driver.onMobileChange();
    const onReduce = () => driver.request();
    touch?.addEventListener('change', onTouch);
    reduce?.addEventListener('change', onReduce);
    driver.start();
    return () => {
      touch?.removeEventListener('change', onTouch);
      reduce?.removeEventListener('change', onReduce);
      stop();
      sc!.removeAttribute('data-fw-scene');
      off();
      driver.dispose();
      driverRef.current = null;
    };
  }, []);

  const activeIdx = IDS.indexOf(active);
  const cls = (...c: Array<string | false | undefined>) => c.filter(Boolean).join(' ');
  return (
    <section ref={showcase} id="profile-showcase" className={css.profile} aria-label="Fastwork profile showcase" data-fw="people-deck" data-fw-variant={variant}>
      <div ref={sticky} className={css.sticky} data-fw="people-sticky">
        <div ref={chrome} className={cls(css.chrome, railIn && css.isRailIn)}>
          <div
            ref={tabs}
            role="tablist"
            className={cls(css.tabs, railIn && css.isRailIn, dragging && css.isDragging)}
            aria-orientation={mobile ? 'horizontal' : 'vertical'}
            aria-label="Occupations"
            aria-hidden={!railIn || undefined}
            onPointerDown={(e) => driverRef.current?.pointerDown(e)}
            onPointerMove={(e) => {
              const r = driverRef.current?.pointerMove(e);
              if (r?.first) e.currentTarget.setPointerCapture(e.pointerId);
              if (r?.dragging) e.preventDefault();
            }}
            onPointerUp={(e) => {
              driverRef.current?.pointerUp(e);
              if (e.currentTarget.hasPointerCapture(e.pointerId)) e.currentTarget.releasePointerCapture(e.pointerId);
            }}
            onPointerCancel={(e) => driverRef.current?.pointerUp(e)}
          >
            {PROFILES.map((p, i) => (
              <button
                key={p.id}
                type="button"
                role="tab"
                aria-selected={p.id === active}
                data-profession-tab={p.id}
                className={cls(css.tab, p.id === active && css.isActive)}
                style={{ '--tab-i': i } as React.CSSProperties}
                data-selenium={`start-selling.profile-showcase.button.profession.${p.id}`}
                onClick={(e) => {
                  if (draggedRef.current) {
                    e.preventDefault();
                    return;
                  }
                  driverRef.current?.select(p.id);
                }}
              >
                <span>{p.label}</span>
              </button>
            ))}
          </div>
          <div ref={deck} className={css.deck} data-active={active} onScroll={() => driverRef.current?.onDeckScroll()}>
            {PROFILES.map((p, i) => {
              const mounted = p.id === active || (mobile && Math.abs(i - activeIdx) <= 1);
              return (
                <div key={p.id} className={cls(css.shell, p.id === active && css.isActiveShell)} data-profession={p.id}>
                  {mounted ? <ProfilePanel p={p} hidden={p.id !== active} /> : <div className={css.panel} aria-hidden="true" />}
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </section>
  );
}
