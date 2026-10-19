import { useEffect, useRef, useState, useSyncExternalStore, type FormEvent, type KeyboardEvent, type MouseEvent, type SyntheticEvent } from 'react';
import { GenSvg, art } from '../../GenSvg';
import { closeAllowed, FORM_INIT, openDir, react, settle, submit, sync, triggerOffset, valid, type Form } from './logic';
import css from './signup.module.css';
import { closeSignup, signupStore } from './store';

export { openSignup, closeSignup } from './store';

export interface SignupData {
  name: string;
  email: string;
}
export interface OverlaySignupProps {
  variant: string;
  /** sends the sign-up; without it a valid submit shows the "temporarily unavailable" error (as the original does) */
  onSignup?: (data: SignupData) => Promise<void>;
}

/** What the page's purpose for this dialog is (`purpose: info`: backdrop click and Escape close it). */
const PURPOSE = 'info' as const;

/**
 * overlays.signup (`faithful`): the waitlist dialog as a native modal `<dialog>` (top layer, `::backdrop`), like the
 * original's `dialog.sb-dialog`. Open/close, the direction of the enter animation, Escape, backdrop click, the close
 * guard and the submit flow come from `logic.ts` (Lean `Fw.Parts.OverlaySignup`); the enter animation is a CSS keyframe
 * animation (0.4 s), never per-frame JS. Plain elements, one CSS Module. Copy is the original's English.
 */
export function OverlaySignup({ variant, onSignup }: OverlaySignupProps) {
  const isOpen = useSyncExternalStore(signupStore.subscribe, signupStore.get, () => false);
  const dialog = useRef<HTMLDialogElement>(null);
  const nameInput = useRef<HTMLInputElement>(null);
  const opener = useRef<HTMLElement | null>(null);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [form, setForm] = useState<Form>(FORM_INIT);
  const formRef = useRef<Form>(FORM_INIT);
  const commit = (f: Form) => {
    formRef.current = f;
    setForm(f);
  };
  const ok = valid(name, email);

  // the element follows the prop (D313Dngs 1999-2008)
  useEffect(() => {
    const d = dialog.current;
    if (!d) return;
    const op = sync(isOpen, d.open);
    if (op === 'showModal') {
      const active = document.activeElement as HTMLElement | null;
      opener.current = active && active !== document.body ? active : null;
      const [dx, dy] = openDir(opener.current ? triggerOffset(opener.current.getBoundingClientRect(), window.innerWidth, window.innerHeight) : null);
      d.style.setProperty('--dialog-dir-x', `${dx}px`);
      d.style.setProperty('--dialog-dir-y', `${dy}px`);
      d.showModal();
    } else if (op === 'close') {
      d.close();
      opener.current?.focus();
      opener.current = null;
    }
  }, [isOpen]);

  useEffect(() => {
    if (!isOpen) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.body.style.overflow = prev;
    };
  }, [isOpen]);

  // focus the first field once opened (and not yet done)
  useEffect(() => {
    if (!isOpen || form.done) return;
    let live = true;
    queueMicrotask(() => {
      if (live) nameInput.current?.focus();
    });
    return () => {
      live = false;
    };
  }, [isOpen, form.done]);

  /** every close goes through the guard (`onBeforeClose`), then the prop */
  const requestClose = () => {
    if (closeAllowed(formRef.current.submitting)) closeSignup();
  };
  const layered = () => document.querySelector('[data-sb="layer"]') !== null;

  const onKeyDown = (e: KeyboardEvent<HTMLDialogElement>) => {
    if (e.key !== 'Escape') return;
    const r = react('escape', PURPOSE, true, e.nativeEvent.isComposing || e.keyCode === 229, layered());
    if (r.prevent) e.preventDefault();
    if (r.close) requestClose();
  };
  const onClick = (e: MouseEvent<HTMLDialogElement>) => {
    if (react('backdrop', PURPOSE, e.target === e.currentTarget, false, false).close) requestClose();
  };
  const onCancel = (e: SyntheticEvent<HTMLDialogElement>) => {
    const r = react('cancel', PURPOSE, e.target === e.currentTarget, false, layered());
    if (r.prevent) e.preventDefault();
    if (r.close) requestClose();
  };

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    const sent = submit(formRef.current, valid(name, email), onSignup !== undefined);
    commit(sent.form);
    if (!sent.send || !onSignup) return;
    try {
      await onSignup({ name: name.trim(), email: email.trim() });
      commit(settle(formRef.current, true));
    } catch {
      commit(settle(formRef.current, false));
    }
  };

  return (
    <dialog
      ref={dialog}
      className={css.dialog}
      data-fw="overlay-signup"
      data-fw-variant={variant}
      data-modal-name="waitlist-signup"
      aria-label="Join our waitlist"
      aria-modal="true"
      style={{ width: 'min(360px, calc(100vw - 48px))', maxHeight: '85vh' }}
      onKeyDown={onKeyDown}
      onClick={onClick}
      onCancel={onCancel}
    >
      <div className={css.inner}>
        <div className={css.signup}>
          <button type="button" className={css.close} aria-label="Close" disabled={form.submitting} onClick={requestClose}>
            ×
          </button>
          <div className={css.heading}>
            <GenSvg art={art('brand.mark')} className={css.mark} />
            <h2>{form.done ? "You're on the waitlist!" : 'Join our waitlist'}</h2>
            <p>{form.done ? "We'll email you when access is available." : 'Be one of the first to access the future'}</p>
          </div>
          {form.done ? (
            <button type="button" className={css.submit} onClick={requestClose}>
              Close
            </button>
          ) : (
            <form className={css.form} aria-busy={form.submitting} onSubmit={onSubmit}>
              <div className={css.fields}>
                <label className={css.label}>
                  <span>Name</span>
                  <input
                    ref={nameInput}
                    className={css.input}
                    name="name"
                    autoComplete="name"
                    required
                    maxLength={100}
                    placeholder="Your name"
                    disabled={form.submitting}
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                  />
                </label>
                <label className={css.label}>
                  <span>Email</span>
                  <input
                    className={css.input}
                    name="email"
                    type="email"
                    autoComplete="email"
                    placeholder={'you' + '@' + 'email.com'}
                    required
                    maxLength={254}
                    disabled={form.submitting}
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                  />
                </label>
              </div>
              {form.error ? (
                <p className={css.error} role="alert">
                  Signup is temporarily unavailable. Please try again later.
                </p>
              ) : null}
              <button type="submit" className={css.submit} disabled={!ok || form.submitting}>
                {form.submitting ? 'Submitting…' : 'Submit'}
              </button>
            </form>
          )}
        </div>
      </div>
    </dialog>
  );
}
