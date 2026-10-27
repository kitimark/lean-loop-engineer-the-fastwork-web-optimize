import css from './stage.module.css';
import { STAGE_ON } from './logic';

export function StageTrack({ variant }: { variant: string }) {
  return variant === STAGE_ON ? <div className={css.track} data-fw="stage-track" aria-hidden="true" /> : null;
}
