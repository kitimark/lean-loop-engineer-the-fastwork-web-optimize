/**
 * The deck's inline icons: star, clock, play badge, mute. Elements, sizes and view boxes follow the original; the drawn
 * geometry is a stand-in of our own until svg-extract lands (then these read svg.gen.json). Path data of the original is
 * never committed outside snapshot/.
 */
const STAR_POINTS = (() => {
  const pts: string[] = [];
  for (let k = 0; k < 10; k++) {
    const r = k % 2 === 0 ? 10 : 4.6;
    const a = (Math.PI * k) / 5 - Math.PI / 2;
    pts.push(`${(12 + r * Math.cos(a)).toFixed(2)},${(12.6 + r * Math.sin(a)).toFixed(2)}`);
  }
  return pts.join(' ');
})();

export function StarIcon({ size = 16, color = '#2b313b', className }: { size?: number; color?: string; className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" width={size} height={size} aria-hidden="true" style={{ color, flex: 'none', display: 'inline-block', verticalAlign: '-2px' }}>
      <polygon points={STAR_POINTS} fill="currentColor" />
    </svg>
  );
}

export function ClockIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 16 16" aria-hidden="true">
      <circle cx="8" cy="8" r="6" />
      <polyline points="8,4.5 8,8 10.5,9.5" />
    </svg>
  );
}

export function PlayIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24">
      <polygon points="8,5 19,12 8,19" />
    </svg>
  );
}

export function MuteIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24">
      <polygon points="11,5 6.5,9 3,9 3,15 6.5,15 11,19" />
      <polyline points="16.2,9.2 21.8,14.8" />
      <polyline points="21.8,9.2 16.2,14.8" />
    </svg>
  );
}
