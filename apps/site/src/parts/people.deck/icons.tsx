/**
 * The deck's inline icons: star, clock, play badge, mute. Every shape is read from the snapshot by svg-extract and drawn
 * through GenSvg; no geometry is written here.
 */
import { GenSvg, art } from '../../GenSvg';

export function StarIcon({ size = 16, color = '#2b313b', className }: { size?: number; color?: string; className?: string }) {
  return (
    <GenSvg
      art={art('people.star')}
      className={className}
      width={size}
      height={size}
      style={{ color, fill: 'currentColor', flex: 'none', display: 'inline-block', verticalAlign: '-2px' }}
    />
  );
}

export function ClockIcon({ className }: { className?: string }) {
  return <GenSvg art={art('people.clock')} className={className} />;
}

export function PlayIcon({ className }: { className?: string }) {
  return <GenSvg art={art('people.play')} className={className} />;
}

export function MuteIcon({ className }: { className?: string }) {
  return <GenSvg art={art('people.mute')} className={className} />;
}

const DIM_ART = { responseSpeed: 'review.bolt', serviceQuality: 'review.shield', skill: 'review.star', value: 'review.tag' } as const;

export function DimensionIcon({ kind }: { kind: keyof typeof DIM_ART }) {
  return <GenSvg art={art(DIM_ART[kind])} />;
}
