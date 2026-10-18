/**
 * The drawer's open flag: the original keeps it in the commission section and passes it down (`open`, `onClose`);
 * here any trigger calls `openDrawer()`. A discrete flag (changes on a click or a key), never a per-frame value.
 * Server snapshot is always closed (the original renders the drawer only while mounted).
 */
let open = false;
const subs = new Set<() => void>();

const set = (v: boolean) => {
  if (open === v) return;
  open = v;
  for (const s of subs) s();
};

export const drawerStore = {
  get: () => open,
  subscribe: (fn: () => void) => {
    subs.add(fn);
    return () => {
      subs.delete(fn);
    };
  },
};
export const openDrawer = () => set(true);
export const closeDrawer = () => set(false);
