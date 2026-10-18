/**
 * The dialog's open flag (`isOpen` in the original, owned by the page root and passed down): any trigger calls
 * `openSignup()`. A discrete flag, never a per-frame value. The server snapshot is closed.
 */
let open = false;
const subs = new Set<() => void>();

const set = (v: boolean) => {
  if (open === v) return;
  open = v;
  for (const s of subs) s();
};

export const signupStore = {
  get: () => open,
  subscribe: (fn: () => void) => {
    subs.add(fn);
    return () => {
      subs.delete(fn);
    };
  },
};
export const openSignup = () => set(true);
export const closeSignup = () => set(false);
