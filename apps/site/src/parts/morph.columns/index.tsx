import { useEffect, useRef, type CSSProperties } from 'react';
import { seekAnimations, timelineNow } from '../engine.scene';
import { createSceneClock } from '../engine.scene/logic';
import { watchHidden } from '../engine.scene/observe';
import '../engine.scene/scene.module.css';
import { COLUMNS } from './data';
import { IdleHold, idleRemoved } from './idle';
import css from './morph.module.css';
import { scaleApplies, scaleVars } from './scale';

export interface MorphColumnsProps {
  variant: string;
  /** morph.mount `shift-dormant` (Lean `MorphMountDormant.dormant`): the tracks carry no animation while true. */
  dormant?: boolean;
}

const SCENE_ATTR = 'data-start-selling-scene';

/**
 * morph.columns: the five marquee columns of the morph panel's backdrop, rendered as the backdrop's children (the
 * panel owns the backdrop box; the stage here adds none). Static markup; the 16 s up/down motion is the original's CSS
 * keyframes (no JS, no state, no per-frame write). The 21 pictures are the snapshot's own files.
 *
 * Variant `hidden-pause` (Lean `Fw.Parts.HiddenPause`): one IntersectionObserver on the backdrop (the stage's parent),
 * threshold from the Lean constant. While the visible fraction is at most that, a play-state attribute pauses the
 * tracks (nothing removed); on the way back the tracks are seeked to `origClock` (the clock of an animation that ran
 * only while the scene was active), in the observer callback, before paint. The scene state is the panel's
 * `data-start-selling-scene` attribute, followed by a MutationObserver (it changes at one value of the morph only).
 *
 * Variant `final-scale` (Lean `Fw.Parts.MorphColumnsScale`, look-change class L): at widths up to 1000 px the columns
 * keep the final-width layout and a transform computed from `--morph` in CSS gives them the base layout's edges; this
 * effect writes three constants per viewport width (on mount and resize), nothing per frame.
 */
export function MorphColumns({ variant, dormant = false }: MorphColumnsProps) {
  const stageRef = useRef<HTMLDivElement>(null);
  const clockRef = useRef<ReturnType<typeof createSceneClock> | null>(null);
  const hiddenPause = variant === 'hidden-pause';
  const idleNone = variant === 'idle-none';
  const finalScale = variant === 'final-scale';

  useEffect(() => {
    const stage = stageRef.current;
    const panel = stage?.closest<HTMLElement>(`[${SCENE_ATTR}]`);
    if (!hiddenPause || !stage || !panel) return;
    const read = () => panel.getAttribute(SCENE_ATTR) === 'active';
    const set = () => {
      const now = timelineNow();
      if (!clockRef.current) clockRef.current = createSceneClock(now, read());
      else clockRef.current.setActive(now, read());
    };
    set();
    const mo = new MutationObserver(set);
    mo.observe(panel, { attributes: true, attributeFilter: [SCENE_ATTR] });
    return () => mo.disconnect();
  }, [hiddenPause]);

  useEffect(() => {
    const stage = stageRef.current;
    const host = stage?.parentElement;
    if (!hiddenPause || !stage || !host) return;
    let wasHidden = false;
    return watchHidden([host], 'fraction', (_el, hidden) => {
      if (hidden) {
        stage.setAttribute('data-fw-hidden', '');
        wasHidden = true;
        return;
      }
      stage.removeAttribute('data-fw-hidden');
      if (wasHidden && clockRef.current) {
        wasHidden = false;
        seekAnimations(stage, clockRef.current.read(timelineNow()));
      }
    });
  }, [hiddenPause]);

  useEffect(() => {
    const stage = stageRef.current;
    const panel = stage?.closest<HTMLElement>(`[${SCENE_ATTR}]`);
    if (!idleNone || !stage || !panel) return;
    const hold = new IdleHold();
    let removed = false;
    const sync = () => {
      const want = idleRemoved(panel.getAttribute(SCENE_ATTR));
      if (want === removed) return;
      removed = want;
      if (want) {
        hold.keep(stage.getAnimations({ subtree: true }));
        stage.setAttribute('data-fw-idle', '');
      } else {
        stage.removeAttribute('data-fw-idle');
        hold.restore(stage.getAnimations({ subtree: true }));
      }
    };
    sync();
    const mo = new MutationObserver(sync);
    mo.observe(panel, { attributes: true, attributeFilter: [SCENE_ATTR] });
    return () => {
      mo.disconnect();
      stage.removeAttribute('data-fw-idle');
    };
  }, [idleNone]);

  useEffect(() => {
    const stage = stageRef.current;
    if (!finalScale || !stage) return;
    let last = -1;
    const write = () => {
      const w = window.innerWidth;
      if (w === last) return;
      last = w;
      if (!scaleApplies(w)) {
        stage.removeAttribute('data-fw-cs');
        return;
      }
      const v = scaleVars(w);
      stage.style.setProperty('--cs-cf', String(v.cf));
      stage.style.setProperty('--cs-a', String(v.a));
      stage.style.setProperty('--cs-d', String(v.d));
      stage.setAttribute('data-fw-cs', '');
    };
    write();
    window.addEventListener('resize', write);
    return () => {
      window.removeEventListener('resize', write);
      stage.removeAttribute('data-fw-cs');
    };
  }, [finalScale]);

  return (
    <div ref={stageRef} className={css.stage} data-fw="morph-columns" data-fw-variant={variant} data-fw-dormant={dormant ? '' : undefined}>
      {COLUMNS.map((c, i) => (
        <div key={i} className={css.col} style={{ '--col-offset': c.offset, '--col-i': i } as CSSProperties}>
          <div className={css.track}>
            {c.heights.map((h, j) => (
              <img key={j} src={c.srcs[j]} alt="" loading="eager" decoding="async" style={{ height: `${h}px` }} />
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
