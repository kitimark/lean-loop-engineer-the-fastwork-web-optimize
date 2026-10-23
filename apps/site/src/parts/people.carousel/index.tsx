import { useEffect, useRef, useState } from 'react';
import { getClock } from '../../engine/clock';
import { watchActive } from '../people/shared';
import css from './carousel.module.css';
import { createLoop } from './driver';
import { avatarOf, RING_ORDER } from '../people/assets';
import { COPY } from '../people/data';
import { CROP_VARIANT, restWindow, START, swapRole, swapWindow, type State } from './logic';
import { matchList } from './media';

/**
 * people.carousel (`faithful`): the avatar ring of the community pill. Every 1020 ms (800 rest, 220 swap) a fresh swap row of
 * five avatars shows (the first leaves, the last enters, 0.22 s keyframes) and the ring advances. The state changes at timer
 * events, never per frame. Avatars are neutral fills (the photos are not shipped).
 */
export function PeopleCarousel({ variant }: { variant: string }) {
  const [s, setS] = useState<State>(START);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const reduce = matchList('mq.rm-reduce');
    if (reduce?.matches) return; // the loop never runs under reduced motion (N2:11289)
    const loop = createLoop({ clock: getClock(), onState: setS });
    const section = ref.current?.closest('[data-fw="people"]');
    const stop = section ? watchActive(section, loop.setActive) : (loop.setActive(true), () => undefined);
    loop.start();
    return () => {
      stop();
      loop.dispose();
    };
  }, []);

  const ids = s.swapping ? swapWindow({ x: s.x }) : restWindow({ x: s.x });
  const crop = variant === CROP_VARIANT;
  return (
    <div className={css.pill} data-fw="people-pill">
      <div className={css.proof}>
        <div ref={ref} className={`${css.avatars} ${css.carousel}`} aria-hidden="true" data-fw="people-carousel" data-fw-variant={variant}>
          {ids.map((ring, i) => {
            const role = swapRole({ i, len: ids.length });
            const exit = role === 'exit';
            const enter = role === 'enter';
            return (
              <img
                key={`${s.swapping ? 'swap' : 'rest'}-${ring}`}
                alt=""
                draggable={false}
                src={avatarOf({ id: RING_ORDER[ring]! })}
                className={
                  !s.swapping
                    ? css.avatar
                    : crop
                      ? `${css.avatar} ${exit ? css.cropExit : enter ? `${css.isEnter} ${css.cropEnter}` : css.cropShift}`
                      : exit
                        ? `${css.avatar} ${css.isExit}`
                        : enter
                          ? `${css.avatar} ${css.isEnter}`
                          : css.avatar
                }
              />
            );
          })}
        </div>
        <span>{COPY.community}</span>
      </div>
      <button type="button" data-selenium="start-selling.people.button.get-started">
        {COPY.getStarted}
      </button>
    </div>
  );
}
