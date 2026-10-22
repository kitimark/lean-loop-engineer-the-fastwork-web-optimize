import { useEffect, useRef } from 'react';
import { PAIN_BODY, PAIN_HEADING } from '../pain.notes/data';
import { PainNotes } from '../pain.notes';
import css from './pain.module.css';
import { installRangeStart } from './darkScroll';

export interface PainProps {
  variant: string;
  /** The variant of the notes board inside the section (part `pain.notes`). */
  notesVariant?: string;
}

/**
 * pain (`faithful`): the Pain section (P3). A sticky 100svh stage with the copy and the notes board, then 200svh of
 * hold; pulled up over the previous section by 100svh. Static markup and CSS; the sticky notes live in the canvas, which
 * is the part `pain.notes`. The empty board spacer in the column only gives the section its height.
 * Geometry spec: Lean `Fw.Parts.Pain`. The dark flip at <= 860 px is a class (`is-pain-dark`) the people part sets.
 */
export function Pain({ variant, notesVariant = 'faithful' }: PainProps) {
  const ref = useRef<HTMLElement>(null);
  const darkScroll = variant === 'dark-scroll';
  useEffect(() => {
    const el = ref.current;
    if (!darkScroll || !el) return;
    return installRangeStart(el);
  }, [darkScroll]);
  return (
    <section ref={ref} className={css.pain} aria-labelledby="pain-heading" data-fw="pain" data-fw-variant={variant}>
      <div className={css.sticky}>
        <PainNotes variant={notesVariant} />
        <div className={css.inner}>
          <div className={css.copy} data-fw="pain-copy">
            <h2 id="pain-heading">{PAIN_HEADING}</h2>
            <p>{PAIN_BODY}</p>
          </div>
          <div className={css.board} aria-hidden="true">
            <div className={css.stage} />
          </div>
        </div>
      </div>
      <div className={css.hold} aria-hidden="true" />
    </section>
  );
}
