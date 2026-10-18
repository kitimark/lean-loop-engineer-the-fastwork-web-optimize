import { LOGO_PATHS } from './logo.paths';

/** The wordmark in the original's 122 px wide box: static markup, `currentColor` fill. */
export function NavLogo({ size = '122px' }: { size?: string }) {
  return (
    <svg width={size} viewBox="0 0 181 46" fill="currentColor" aria-hidden="true" focusable="false">
      <g>
        {LOGO_PATHS.map((d, i) => (
          <path key={i} d={d} />
        ))}
      </g>
    </svg>
  );
}
