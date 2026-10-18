// Path rewrite for previews served below the console's own path (`/preview/<id>/r/…` and `/o/…`). The sites in the previews
// link their assets with root-absolute paths (`/assets/x.js`); under a path prefix these must point below the prefix. Only I/O
// glue (a text transform on the bytes of a response); it decides nothing. HTML and CSS are rewritten, other types are not.
// A reference already below `/preview/` and protocol-relative `//host` references are left alone.

const ABS = "\\/(?!\\/|preview\\/)";

/** Rewrite the root-absolute references of an HTML or CSS body to start with `prefix` (e.g. `/preview/a1/r`). */
export function rewriteBody(contentType: string, text: string, prefix: string): string | null {
  const ct = contentType.toLowerCase();
  const css = (t: string) => t
    .replace(new RegExp(`(url\\(\\s*["']?)${ABS}`, "gi"), (_m, a: string) => `${a}${prefix}/`)
    .replace(new RegExp(`(@import\\s+["'])${ABS}`, "gi"), (_m, a: string) => `${a}${prefix}/`);
  if (ct.startsWith("text/css")) return css(text);
  if (!ct.startsWith("text/html")) return null;
  let out = text.replace(new RegExp(`(\\s(?:href|src|action|poster|data-src|data-href)\\s*=\\s*["'])${ABS}`, "gi"), (_m, a: string) => `${a}${prefix}/`);
  out = out.replace(/(\ssrcset\s*=\s*)(["'])(.*?)\2/gis, (_m, a: string, q: string, v: string) =>
    `${a}${q}${v.replace(new RegExp(`(^|,\\s*)${ABS}`, "g"), (_x, s: string) => `${s}${prefix}/`)}${q}`);
  out = out.replace(new RegExp(`(\\bimport\\(\\s*["'])${ABS}`, "g"), (_m, a: string) => `${a}${prefix}/`);
  return css(out); // inline <style> blocks and style="" attributes
}
