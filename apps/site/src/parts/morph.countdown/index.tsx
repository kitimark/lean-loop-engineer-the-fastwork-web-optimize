import { HeroCountdown } from '../hero.countdown';
import css from './morph.module.css';

export interface MorphCountdownProps {
  variant: string;
  /** `mui` (default) or `plain`; passed to the shared clock. */
  impl?: 'mui' | 'plain';
}

/**
 * morph.countdown: the second countdown, inside the morph panel's centre column (original N2:12879 markup, instance at
 * N2:13160 with `inverse: true`). It is the hero.countdown clock unchanged (same logic, driver, scheduling and CSS
 * module, so the Lean goldens of hero.countdown cover it) in a centred row with a 32 px top margin. Variant `strip`
 * needs hero.countdown:strip (part.json `requires`) and reuses its one-strip-per-digit driver. The panel host
 * (morph.panel) decides when it mounts; the original mounts the panel when the platform section is within 200% of the
 * viewport (N2:13084).
 */
export function MorphCountdown({ variant, impl = 'mui' }: MorphCountdownProps) {
  return (
    <div className={css.wrap} data-fw="morph-countdown" data-fw-variant={variant}>
      <HeroCountdown variant={variant} impl={impl} inverse fwId="morph-countdown-clock" />
    </div>
  );
}
