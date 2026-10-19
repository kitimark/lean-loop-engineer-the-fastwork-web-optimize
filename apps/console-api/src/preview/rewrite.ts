// Path rewrite for previews served below the console's own path (`/preview/<id>/r/…` and `/o/…`). The sites in the previews
// link their assets with root-absolute paths (`/assets/x.js`); under a path prefix these must point below the prefix. Only I/O
// glue (a text transform on the bytes of a response); it decides nothing. HTML and CSS are rewritten, other types are not.
// Inline <script> bodies stay byte-identical. A reference already below `/preview/` and protocol-relative `//host` references are left alone.

const ABS = "\\/(?!\\/|preview\\/)";

/** Rewrite the root-absolute references of an HTML or CSS body to start with `prefix` (e.g. `/preview/a1/r`). */
export function rewriteBody(contentType: string, text: string, prefix: string): string | null {
  const ct = contentType.toLowerCase();
  const css = (t: string) => t
    .replace(new RegExp(`(url\\(\\s*["']?)${ABS}`, "gi"), (_m, a: string) => `${a}${prefix}/`)
    .replace(new RegExp(`(@import\\s+["'])${ABS}`, "gi"), (_m, a: string) => `${a}${prefix}/`);
  const html = (t: string) => {
    let o = t.replace(new RegExp(`(\\s(?:href|src|action|poster|data-src|data-href)\\s*=\\s*["'])${ABS}`, "gi"), (_m, a: string) => `${a}${prefix}/`);
    o = o.replace(/(\ssrcset\s*=\s*)(["'])(.*?)\2/gis, (_m, a: string, q: string, v: string) =>
      `${a}${q}${v.replace(new RegExp(`(^|,\\s*)${ABS}`, "g"), (_x, s: string) => `${s}${prefix}/`)}${q}`);
    // a manifest fetch carries no cookie by default; the preview gate wants one
    o = o.replace(/<link\b[^>]*>/gi, (tag) => /\srel\s*=\s*["']?manifest\b/i.test(tag) && !/\scrossorigin\b/i.test(tag) ? tag.replace(/\s*\/?>$/, (e) => ` crossorigin="use-credentials"${e}`) : tag);
    return css(o); // inline <style> blocks and style="" attributes
  };
  if (ct.startsWith("text/css")) return css(text);
  if (!ct.startsWith("text/html")) return null;
  // The body of an inline <script> (no src) is never changed: a page's CSP may allow it by hash, and a changed byte blocks it.
  // Paths a script builds are routed by the Referer instead (proxy.ts `viaReferer`).
  const SCRIPT = /(<script\b(?:[^>"']|"[^"]*"|'[^']*')*>)([\s\S]*?)(<\/script\s*>)/gi;
  let out = ""; let last = 0;
  for (const m of text.matchAll(SCRIPT)) {
    const inline = !/\ssrc\s*=/i.test(m[1]!);
    out += html(text.slice(last, m.index + m[1]!.length)) + (inline ? m[2]! : html(m[2]!));
    last = m.index + m[1]!.length + m[2]!.length;
  }
  return out + html(text.slice(last));
}
