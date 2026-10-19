// TS stand-in for Lean `Fw.Console.PreviewCache` (`kind`, `cacheControl`, `compressible`; the manifest name set is an input), checked against the golden
// `packages/contracts/golden/console/console.previewCache.jsonl` by test/preview-speed.test.ts. A serve-child process has no
// fwcore, so the pure rule is mirrored here; replace by the Lean op when the child can reach fwcore.
import { brotliCompressSync, constants, gzipSync } from "node:zlib";
import { createHash } from "node:crypto";

export type Kind = "hashed" | "html" | "other";

const IMMUTABLE_DIR = "/_app/immutable/";
const lastSegment = (path: string) => path.split("/").at(-1) ?? "";

export function ext(path: string): string {
  const parts = lastSegment(path).split(".");
  return parts.length < 2 ? "" : "." + parts.at(-1)!.toLowerCase();
}

const MUI_NAME = /^\/mui\.[0-9a-f]{8}\.css$/;

/** Identity, not inference: immutable iff under /_app/immutable/, listed in the rewrite build's `.vite/manifest.json`
 *  (`names`, each as `/<name>`), or `mui.<sha8>.css` (apps/site/scripts/build.mjs). Html is always `html`. */
export function kind(path: string, names: ReadonlySet<string> = NO_NAMES): Kind {
  if (ext(path) === ".html") return "html";
  if (path.startsWith(IMMUTABLE_DIR) || names.has(path) || MUI_NAME.test(path)) return "hashed";
  return "other";
}

const NO_NAMES: ReadonlySet<string> = new Set();

/** The names a Vite manifest lists (`file`, `css`, `assets` of every entry), each as `/<name>`. */
export function manifestNames(manifest: unknown): Set<string> {
  const out = new Set<string>();
  if (typeof manifest !== "object" || manifest === null) return out;
  for (const e of Object.values(manifest as Record<string, unknown>)) {
    if (typeof e !== "object" || e === null) continue;
    const { file, css, assets } = e as { file?: unknown; css?: unknown; assets?: unknown };
    for (const n of [file, ...(Array.isArray(css) ? css : []), ...(Array.isArray(assets) ? assets : [])]) if (typeof n === "string") out.add("/" + n);
  }
  return out;
}

export const cacheControl = (k: Kind): string => (k === "hashed" ? "public, max-age=31536000, immutable" : "no-cache");

const COMPRESSIBLE = new Set([".html", ".css", ".js", ".mjs", ".json", ".svg", ".txt"]);
export const compressible = (path: string): boolean => COMPRESSIBLE.has(ext(path));

/** The reply of Lean `console.previewCache` for one path. */
export function cachePolicy(path: string, names: ReadonlySet<string> = NO_NAMES) {
  const k = kind(path, names);
  return { kind: k, cacheControl: cacheControl(k), immutable: k === "hashed", compress: compressible(path) };
}

/** Strong ETag over the bytes (the encoding is part of the validator: `-br`, `-gz`). */
export function etagOf(bytes: Buffer | string, enc: Encoding = "identity"): string {
  const h = createHash("sha256").update(bytes).digest("base64url");
  return `"${h}${enc === "identity" ? "" : enc === "br" ? "-br" : "-gz"}"`;
}

/** `If-None-Match` against an ETag (weak comparison, `*` matches). */
export function etagMatches(header: string | null | undefined, etag: string): boolean {
  if (!header) return false;
  if (header.trim() === "*") return true;
  const strip = (t: string) => t.trim().replace(/^W\//, "");
  return header.split(",").some((t) => strip(t) === etag);
}

export type Encoding = "identity" | "br" | "gzip";

/** The encoding to answer with: `br`, else `gzip`, else none, from an Accept-Encoding header. */
export function pickEncoding(header: string | null | undefined): Encoding {
  const q = new Map<string, number>();
  for (const part of (header ?? "").split(",")) {
    const [name, ...params] = part.trim().toLowerCase().split(";");
    if (!name) continue;
    const qp = params.map((p) => p.trim()).find((p) => p.startsWith("q="));
    q.set(name, qp ? Number(qp.slice(2)) : 1);
  }
  const ok = (n: string) => (q.get(n) ?? q.get("*") ?? 0) > 0;
  return ok("br") ? "br" : ok("gzip") ? "gzip" : "identity";
}

export function encode(body: Buffer, enc: Encoding): Buffer {
  if (enc === "br") return brotliCompressSync(body, { params: { [constants.BROTLI_PARAM_QUALITY]: 5, [constants.BROTLI_PARAM_SIZE_HINT]: body.length } });
  if (enc === "gzip") return gzipSync(body, { level: 9 });
  return body;
}

/** One body in its three encodings, compressed on first use and kept. */
export class Variants {
  private readonly enc = new Map<Encoding, { body: Buffer; etag: string }>();
  readonly raw: Buffer;
  constructor(raw: Buffer) { this.raw = raw; }
  get(enc: Encoding): { body: Buffer; etag: string } {
    let v = this.enc.get(enc);
    if (!v) { const body = encode(this.raw, enc); v = { body, etag: etagOf(this.raw, enc) }; this.enc.set(enc, v); }
    return v;
  }
}
