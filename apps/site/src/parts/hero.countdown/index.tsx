import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { getClock } from '../../engine/clock';
import { createCountdownDriver, oneChainClock, startFaithful, type DigitHandle, type Writable } from './driver';
import { gatedInstance, installHiddenGate } from './hidden';
import { digitPlaces, remainingSeconds, unitsFromSeconds } from './logic';
import { matchList } from './media';
import css from './hero.module.css';

const LABELS = ['days', 'hours', 'mins', 'seconds'] as const;

export interface HeroCountdownProps {
  variant: string;
  impl?: 'mui' | 'plain';
  inverse?: boolean;
  fwId?: string;
  hold?: boolean;
}

const cls = (...c: (string | false | undefined)[]) => c.filter(Boolean).join(' ');

function Digits({ n, strip, layer }: { n: number; strip: boolean; layer: boolean }) {
  return (
    <span className={css.number} data-value>
      {Array.from({ length: n }, (_, k) => (
        <span key={`${n}-${k}`} className={css.digit} data-digit data-place={10 ** (n - k - 1)}>
          <span className={css.spacer} aria-hidden="true" data-spacer>
            0
          </span>
          {strip ? (
            <span className={css.strip} aria-hidden="true" data-strip data-fw-layer={layer ? 'hero.countdown_strip' : undefined}>
              {Array.from({ length: 12 }, (_, j) => (
                <span key={j} className={css.entry}>
                  {(j + 9) % 10}
                </span>
              ))}
            </span>
          ) : (
            Array.from({ length: 10 }, (_, f) => (
              <span key={f} className={css.face} aria-hidden="true" data-face data-fw-layer={layer ? 'hero.countdown_face' : undefined}>
                {f}
              </span>
            ))
          )}
        </span>
      ))}
    </span>
  );
}

export function HeroCountdown({ variant, impl = 'mui', inverse = false, fwId = 'hero-countdown', hold = false }: HeroCountdownProps) {
  const strip = variant === 'strip';
  const hiddenPause = gatedInstance(variant, fwId);
  const rootRef = useRef<HTMLDivElement>(null);
  const [shape, setShape] = useState<number[] | null>(null);

  useEffect(() => {
    setShape(unitsFromSeconds(remainingSeconds(Date.now())).map((v, i) => digitPlaces(v, i > 0).length));
  }, []);

  useEffect(() => {
    const root = rootRef.current;
    if (!root || !shape || hold) return;
    const nodes = [...root.querySelectorAll<HTMLElement>('[data-digit]')];
    const gate = hiddenPause ? installHiddenGate(root) : null;
    const face = (el: HTMLElement): Writable => (gate ? gate.wrap(el) : el);
    const handles: DigitHandle[] = [];
    let k = 0;
    shape.forEach((n, unit) => {
      for (let d = 0; d < n; d++, k++) {
        const el = nodes[k]!;
        const parts = strip
          ? [el.querySelector<HTMLElement>('[data-strip]')!]
          : [...el.querySelectorAll<HTMLElement>('[data-face]')].map(face);
        handles.push({ unit, place: Number(el.dataset.place), nodes: parts });
      }
    });
    const reduce = matchList('mq.rm-reduce');
    const driver = createCountdownDriver({
      variant: strip ? 'strip' : 'faithful',
      digits: handles,
      dateNow: Date.now,
      reduced: () => reduce?.matches ?? false,
    });
    const ro = new ResizeObserver((entries) => {
      for (const e of entries) {
        const i = nodes.indexOf((e.target as HTMLElement).parentElement as HTMLElement);
        const h = (e.target as HTMLElement).offsetHeight;
        if (strip) nodes[i]!.style.setProperty('--cell', `${h}px`);
        driver.setCell(i, h);
      }
    });
    nodes.forEach((el) => ro.observe(el.querySelector('[data-spacer]')!));
    const onRefresh = (changed: boolean) => {
      if (!changed) return;
      const next = driver.shape();
      if (next.length !== shape.length || next.some((v, i) => v !== shape[i])) setShape(next);
    };
    const unsub = startFaithful({ clock: variant === 'one-chain' ? oneChainClock(getClock()) : getClock(), driver, perfNow: () => performance.now(), onRefresh });
    return () => {
      unsub();
      ro.disconnect();
      gate?.stop();
    };
  }, [shape, strip, hiddenPause, variant, hold]);

  const Root = (impl === 'mui' ? MuiRoot : PlainRoot) as typeof PlainRoot;
  const Label = impl === 'mui' ? MuiLabel : PlainLabel;
  return (
    <Root
      rootRef={rootRef}
      className={cls(css.countdown, inverse && css.inverse)}
      variant={variant}
      fwId={fwId}
    >
      {LABELS.map((label, i) => (
        <div key={label} className={css.unit} aria-hidden="true">
          <span className={css.value}>
            {shape ? <Digits n={shape[i]!} strip={strip} layer={fwId === 'hero-countdown'} /> : <span className={css.placeholder}>{i > 0 ? '00' : '0'}</span>}
          </span>
          <Label>{label}</Label>
        </div>
      ))}
    </Root>
  );
}

interface RootProps {
  rootRef: React.Ref<HTMLDivElement>;
  className: string;
  variant: string;
  fwId: string;
  children: ReactNode;
}
const rootAttrs = { role: 'timer', 'aria-live': 'off' as const, 'aria-label': 'Time until launch' };

function PlainRoot({ rootRef, className, variant, fwId, children }: RootProps) {
  return (
    <div ref={rootRef} className={className} data-fw={fwId} data-fw-variant={variant} {...rootAttrs}>
      {children}
    </div>
  );
}
function MuiRoot({ rootRef, className, variant, fwId, children }: RootProps) {
  return (
    <Box ref={rootRef} className={className} data-fw={fwId} data-fw-variant={variant} {...rootAttrs}>
      {children}
    </Box>
  );
}
function PlainLabel({ children }: { children: ReactNode }) {
  return <span className={css.label}>{children}</span>;
}
function MuiLabel({ children }: { children: ReactNode }) {
  return (
    <Typography variant="caption" component="span" className={css.label}>
      {children}
    </Typography>
  );
}
