import Card from '@mui/material/Card';
import Typography from '@mui/material/Typography';
import { useEffect, useRef } from 'react';
import { getClock } from '../../engine/clock';
import css from './hero.module.css';

/** Placeholder countdown. Faithful stacks several faces per digit (as the original layers them); strip has one. */
const FACES: Record<string, number> = { faithful: 4, strip: 1 };
const TOTAL_SECONDS = 3600;
const INITIAL = '0:59:59'; // static text, identical on server and client; the clock takes over after mount

export function HeroCountdown({ variant }: { variant: string }) {
  const rootRef = useRef<HTMLDivElement>(null);
  const faces = FACES[variant] ?? 1;

  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;
    const start = performance.now();
    let last = -1;
    // Driver: one writer on the MotionClock, writes text on the consuming nodes, no React state.
    return getClock().subscribe((now) => {
      const left = Math.max(0, TOTAL_SECONDS - Math.floor((now - start) / 1000));
      if (left === last) return;
      last = left;
      const text = `${Math.floor(left / 3600)}:${String(Math.floor((left % 3600) / 60)).padStart(2, '0')}:${String(left % 60).padStart(2, '0')}`;
      const digits = root.querySelectorAll<HTMLElement>('[data-digit]');
      digits.forEach((d, i) => {
        for (const face of d.children) face.textContent = text[i] ?? '';
      });
    });
  }, [variant]);

  return (
    <Card ref={rootRef} className={css.root} data-fw="hero-countdown" data-fw-variant={variant} elevation={0}>
      <Typography variant="overline" component="p">
        Offer ends in
      </Typography>
      <div className={css.digits} aria-label="countdown">
        {[...INITIAL].map((ch, i) => (
          <span key={i} className={css.digit} data-digit>
            {Array.from({ length: faces }, (_, f) => (
              <span key={f} className={css.face} aria-hidden={f < faces - 1 ? 'true' : undefined}>
                {ch}
              </span>
            ))}
          </span>
        ))}
      </div>
    </Card>
  );
}
