import type { CSSProperties } from 'react';
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
 */
export function MorphColumns({ variant, scene = 'paused' }: MorphColumnsProps) {
  return (
    <div className={css.stage} data-fw="morph-columns" data-fw-variant={variant} data-scene={scene}>
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
