import { PAIN_BODY, PAIN_HEADING } from '../pain.notes/data';
import { PainNotes } from '../pain.notes';
import css from './pain.module.css';

export interface PainProps {
  variant: string;
  /** The variant of the notes board inside the section (part `pain.notes`). */
  notesVariant?: string;
}

/**
 * pain (`faithful`): the Pain section (P3). A sticky 100svh stage with the copy and the notes board, then 200svh of
 * hold; pulled up over the previous section by 100svh. Static markup and CSS only (the notes board is `pain.notes`).
 * Geometry spec: Lean `Fw.Parts.Pain`. The dark flip at <= 860 px is a class (`is-pain-dark`) the people part sets.
 */
export function Pain({ variant, notesVariant = 'faithful' }: PainProps) {
  return (
    <section className={css.pain} aria-labelledby="pain-heading" data-fw="pain" data-fw-variant={variant}>
      <div className={css.sticky}>
        <div className={css.canvas} />
        <div className={css.inner}>
          <div className={css.copy} data-fw="pain-copy">
            <h2 id="pain-heading">{PAIN_HEADING}</h2>
            <p>{PAIN_BODY}</p>
          </div>
          <PainNotes variant={notesVariant} />
        </div>
      </div>
      <div className={css.hold} aria-hidden="true" />
    </section>
  );
}
