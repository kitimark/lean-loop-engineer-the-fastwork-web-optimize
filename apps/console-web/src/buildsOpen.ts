/** Glue for the Builds "Open" actions: no decision logic. Whether a search is valid, which preview to reuse and the link text are
 *  decided by fwcore in console-api (`POST /api/builds/open`); this file keeps recent searches in this browser and copies text. */
export const RECENT_KEY = "fw-console.builds.recentSearches";
export const RECENT_MAX = 10;

/** Recent searches live in this browser's localStorage only; they never go to the server. */
export function readRecent(store: Pick<Storage, "getItem"> = localStorage): string[] {
  try {
    const v = JSON.parse(store.getItem(RECENT_KEY) ?? "[]");
    return Array.isArray(v) ? v.filter((x): x is string => typeof x === "string").slice(0, RECENT_MAX) : [];
  } catch { return []; }
}
export function addRecent(search: string, store: Pick<Storage, "getItem" | "setItem"> = localStorage): string[] {
  const next = [search, ...readRecent(store).filter((x) => x !== search)].slice(0, RECENT_MAX);
  try { store.setItem(RECENT_KEY, JSON.stringify(next)); } catch { /* storage full or blocked: the list just is not kept */ }
  return next;
}

/** Copy text: the async clipboard where the page may use it, else a hidden textarea (plain-http LAN pages have no async clipboard). */
export async function copyText(text: string): Promise<boolean> {
  try {
    if (navigator.clipboard && window.isSecureContext) { await navigator.clipboard.writeText(text); return true; }
  } catch { /* fall through */ }
  const ta = document.createElement("textarea");
  ta.value = text; ta.setAttribute("readonly", ""); ta.style.position = "fixed"; ta.style.opacity = "0";
  document.body.appendChild(ta); ta.select();
  let ok = false;
  try { ok = document.execCommand("copy"); } catch { ok = false; }
  ta.remove();
  return ok;
}
