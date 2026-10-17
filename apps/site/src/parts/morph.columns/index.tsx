import { useEffect, useRef, type CSSProperties } from 'react';
import { seekAnimations, timelineNow } from '../engine.scene';
import { createSceneClock } from '../engine.scene/logic';
import { watchHidden } from '../engine.scene/observe';
import '../engine.scene/scene.module.css';
import { BLANK_GIF, COLUMNS } from './data';
import css from './morph.module.css';

export interface MorphColumnsProps {
  variant: string;
  /** The panel's scene state (original: `data-start-selling-scene`, active only while morph > 0.001). Rest is `paused`. */
  scene?: 'active' | 'paused';
}

/**
 * morph.columns: the five marquee columns of the morph panel's backdrop. Static markup; the 16 s up/down motion is the
 * original's CSS keyframes (no JS, no state, no per-frame write). Placeholder pictures and host stage; the panel,
 * the mount and the tween are other parts (morph.panel, morph.mount, morph.tween).
 *
 * Variant `hidden-pause` (Lean `Fw.Parts.HiddenPause`): one IntersectionObserver on the stage, threshold from the Lean
 * constant. While the visible fraction is at most that, a play-state attribute pauses the tracks (nothing removed);
 * on the way back the tracks are seeked to `origClock` (the clock of an animation that ran only while the scene was
 * active), in the observer callback, before paint. `faithful` is unchanged.
 */
export function MorphColumns({ variant, scene = 'paused' }: MorphColumnsProps) {
  const stageRef = useRef<HTMLDivElement>(null);
  const clockRef = useRef<ReturnType<typeof createSceneClock> | null>(null);
  const hiddenPause = variant === 'hidden-pause';
  const active = scene === 'active';

  useEffect(() => {
    if (!hiddenPause) return;
    const now = timelineNow();
    if (!clockRef.current) clockRef.current = createSceneClock(now, active);
    else clockRef.current.setActive(now, active);
  }, [hiddenPause, active]);

  useEffect(() => {
    const stage = stageRef.current;
    if (!hiddenPause || !stage) return;
    let wasHidden = false;
    return watchHidden([stage], 'fraction', (_el, hidden) => {
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

  return (
    <div ref={stageRef} className={css.stage} data-fw="morph-columns" data-fw-variant={variant} data-scene={scene}>
      <div className={css.backdrop} aria-hidden="true">
        {COLUMNS.map((c, i) => (
          <div key={i} className={css.col} style={{ '--col-offset': c.offset } as CSSProperties}>
            <div className={css.track}>
              {c.heights.map((h, j) => (
                <img key={j} src={BLANK_GIF} alt="" loading="eager" decoding="async" style={{ height: `${h}px` }} />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
