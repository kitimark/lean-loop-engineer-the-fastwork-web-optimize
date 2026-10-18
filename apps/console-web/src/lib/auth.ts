// The owner token (console-lan-owner). It lives in localStorage of the console origin only: an origin includes the port, so
// JavaScript of a task preview (another port) cannot read it, and no cookie carries it. Every API call sends it as
// `Authorization: Bearer`; the server accepts owner rights from that header alone (Lean `owner_requires_bearer`).
export const TOKEN_KEY = "fw_owner_token";

export function getToken(): string | null {
  try { return localStorage.getItem(TOKEN_KEY); } catch { return null; }
}
export function setToken(t: string): void {
  try { localStorage.setItem(TOKEN_KEY, t); } catch { /* storage blocked: the page stays read-only */ }
}
export function clearToken(): void {
  try { localStorage.removeItem(TOKEN_KEY); } catch { /* nothing to clear */ }
}

/** The one-time owner link ends at `/#owner=<token>`: keep the token, then remove it from the address bar. */
export function adoptHashToken(loc: Pick<Location, "hash" | "pathname" | "search"> = window.location): boolean {
  const m = /^#owner=([A-Za-z0-9_-]{16,128})$/.exec(loc.hash);
  if (!m) return false;
  setToken(m[1]!);
  window.history.replaceState(null, "", `${loc.pathname}${loc.search}`);
  return true;
}

/** `fetch` with the owner token, when there is one. */
export function apiFetch(input: string, init: RequestInit = {}): Promise<Response> {
  const t = getToken();
  const headers = new Headers(init.headers);
  if (t) headers.set("authorization", `Bearer ${t}`);
  return fetch(input, { ...init, headers });
}
