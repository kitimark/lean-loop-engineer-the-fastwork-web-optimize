/** Glue for the Compose tab: no decision logic. Which variants exist, their classes, whether a combination is allowed and its canonical
 *  search are Lean `console.compose` (console-api `GET /api/compose`); whether a search opens, which preview serves it and the link are Lean
 *  `console.buildsOpen` (`POST /api/builds/open`). This file turns picks into a query, and drives the open request until the preview serves. */
export type Picks = Record<string, string>;
export type Fetcher = (input: string, init?: RequestInit) => Promise<Response>;

/** `?pick=part:variant,...` for the picks that differ from a part's default (the server ignores a pick of a default). */
export function pickQuery(picks: Picks): string {
  const e = Object.entries(picks).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)).map(([p, v]) => `${p}:${v}`);
  return e.length ? `?pick=${encodeURIComponent(e.join(",")).replace(/%3A/g, ":").replace(/%2C/g, ",")}` : "";
}

export type OpenResult = { ok: true; url: string; path: string; canonical: string } | { ok: false; message: string; reasons: string[] };
type Hooks = {
  fetch: Fetcher; sleep?: (ms: number) => Promise<void>; now?: () => number;
  /** Called with the preview URL when the preview serves (the caller sends the already-opened tab there). */
  onOpen?: (href: string, j: { url: string; path: string; canonical: string }) => void;
  previewBase: string; refused: (reason: string) => string;
};

/** Ask the server to open `search` (arm `r` or `compare`); while a build of the commit runs, wait for it. Same protocol as the Builds tab. */
export async function openSearch(search: string, arm: "r" | "compare", h: Hooks): Promise<OpenResult> {
  const sleep = h.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  const now = h.now ?? Date.now;
  const until = now() + 10 * 60_000;
  const J = { "content-type": "application/json" };
  while (now() < until) {
    const j = await (await h.fetch("/api/builds/open", { method: "POST", headers: J, body: JSON.stringify({ search, arm }) })).json();
    if (!j.ok) {
      return { ok: false, reasons: Array.isArray(j.reasons) ? j.reasons.map(String) : [],
        message: j.reason === "search refused" ? "That combination is not valid; nothing was opened." : h.refused(String(j.reason)) };
    }
    if (j.state === "open") {
      h.onOpen?.(`${h.previewBase}${j.path}`, j);
      return { ok: true, url: String(j.url), path: String(j.path), canonical: String(j.canonical) };
    }
    const id = String(j.preview);
    while (now() < until) {
      await sleep(2000);
      const l = await (await h.fetch("/api/previews")).json();
      const p = (l.previews ?? []).find((x: { id: string; phase: string }) => x.id === id);
      if (p?.phase === "serving") break;
      if (!p) {
        const f = (l.failed ?? []).find((x: { id: string }) => x.id === id);
        return { ok: false, reasons: [], message: f ? `The build failed: ${f.error}` : "The build stopped before it was ready." };
      }
    }
  }
  return { ok: false, reasons: [], message: "Timed out waiting for the build." };
}

/** Newest-wins guard for replies: `next()` hands out a ticket before a request; `isLatest(ticket)` is true only for the newest ticket,
 *  so a late reply of an older request is dropped. */
export function newestWins() {
  let n = 0;
  return { next: () => ++n, isLatest: (ticket: number) => ticket === n };
}

/** A decision shown on the page answers the picks only when the query it was fetched for is the current query. */
export function answersNow(answeredQuery: string | null, currentQuery: string): boolean {
  return answeredQuery !== null && answeredQuery === currentQuery;
}

export const COPY_FAILED = "Copy failed: long-press the link below";

/** Copy an already-known link. It calls `copy` before any await, so a phone browser still sees the tap that started it. Returns the
 *  message to show when the copy failed (plain-http LAN pages have no clipboard API and Safari may refuse the fallback). */
export async function copyKnown(url: string, copy: (text: string) => Promise<boolean>): Promise<{ copied: boolean; message: string | null }> {
  const ok = await copy(url);
  return { copied: ok, message: ok ? null : COPY_FAILED };
}
