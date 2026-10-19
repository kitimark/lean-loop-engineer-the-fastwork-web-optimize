import { useEffect, useId, useRef, useState } from 'react';
import { GenSvg, art } from '../../GenSvg';
import { getClock } from '../../engine/clock';
import { createMenuController, type MenuController } from './controller';
import { flags, type Phase } from './logic';
import css from './lang.module.css';

/** Option links and labels (hreflang set of the original page; labels are the languages' own names). */
export const LOCALES = [
  { code: 'en', href: '/', label: 'English' },
  { code: 'th', href: '/th/', label: 'ไทย' },
  { code: 'id', href: '/id/', label: 'Indonesia' },
] as const;
export type LocaleCode = (typeof LOCALES)[number]['code'];

export interface LangMenuProps {
  variant?: string;
  impl?: 'mui' | 'plain';
  /** the selected language */
  locale?: LocaleCode;
  /** called with the new language when a different one is picked */
  onSelect?: (code: LocaleCode) => void;
  /** the menu is mounted (opening, open or closing): the nav's `is-locale-open` */
  onOpenChange?: (open: boolean) => void;
}

const cx = (...a: (string | false)[]) => a.filter(Boolean).join(' ');

/**
 * nav.langMenu (`faithful`): the language switch and its menu. The phase machine is the pure `step` of logic.ts (Lean
 * `NavLangMenu`); the controller owns the 140 ms close timer (engine clock). React state holds the phase only: it changes
 * on a click, a key or the timer, never per frame. The enter/leave motion is the CSS keyframes. `impl: plain` shares the code
 * (nothing here is MUI).
 */
export function LangMenu({ locale = 'en', onSelect, onOpenChange }: LangMenuProps) {
  const [phase, setPhase] = useState<Phase>('closed');
  const ctl = useRef<MenuController | null>(null);
  if (!ctl.current) {
    ctl.current = createMenuController({
      after: (ms, cb) => {
        const off = getClock().interval(ms, () => {
          off();
          cb();
        });
        return off;
      },
      onPhase: setPhase,
    });
  }
  const wrap = useRef<HTMLDivElement>(null);
  const menuId = useId();
  const f = flags({ phase });

  useEffect(() => () => ctl.current?.dispose(), []);
  useEffect(() => {
    onOpenChange?.(f.navLocaleOpen);
  }, [f.navLocaleOpen, onOpenChange]);
  useEffect(() => {
    if (!f.listening) return;
    const down = (e: MouseEvent) => {
      if (!wrap.current?.contains(e.target as Node)) ctl.current?.dispatch('outside');
    };
    const key = (e: KeyboardEvent) => {
      if (e.key === 'Escape') ctl.current?.dispatch('outside');
    };
    document.addEventListener('mousedown', down);
    document.addEventListener('keydown', key);
    return () => {
      document.removeEventListener('mousedown', down);
      document.removeEventListener('keydown', key);
    };
  }, [f.listening]);

  const current = LOCALES.find((l) => l.code === locale) ?? LOCALES[0];
  return (
    <div ref={wrap} className={cx(css.wrap!, f.mounted && css.wrapOpen!)} data-fw="nav-lang">
      <button
        className={css.switch}
        type="button"
        aria-label={`Language: ${current.label}`}
        aria-haspopup="listbox"
        aria-expanded={f.isOpen}
        aria-controls={menuId}
        onClick={() => ctl.current?.dispatch('toggle')}
      >
        <span className={css.icon} aria-hidden="true">
          <GenSvg art={art('nav.globe')} />
        </span>
        <span className={css.code}>{locale.toUpperCase()}</span>
        <svg className={css.chevron} viewBox="0 0 16 16" aria-hidden="true">
          <path d="M4.5 6l3.5 3.5L11.5 6" />
        </svg>
      </button>
      {f.mounted && (
        <div id={menuId} role="listbox" aria-label="Language" className={cx(css.menu!, f.isOpen && css.menuOpen!, f.isClosing && css.menuClosing!)}>
          {LOCALES.map((l) => (
            <a
              key={l.code}
              role="option"
              className={css.option}
              href={l.href}
              hrefLang={l.code}
              aria-selected={l.code === locale}
              onClick={(e) => {
                if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button > 0) return;
                e.preventDefault();
                if (l.code !== locale) onSelect?.(l.code);
                ctl.current?.dispatch('select');
              }}
            >
              <span className={css.check} aria-hidden="true">
                {l.code === locale && (
                  <svg viewBox="0 0 24 24">
                    <circle cx="12" cy="12" r="10" />
                    <path d="M7.2 12.4l3.1 3.1 6.2-6.2" stroke="#fff" strokeWidth="1.8" fill="none" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                )}
              </span>
              <span className={css.label}>{l.label}</span>
            </a>
          ))}
        </div>
      )}
    </div>
  );
}
