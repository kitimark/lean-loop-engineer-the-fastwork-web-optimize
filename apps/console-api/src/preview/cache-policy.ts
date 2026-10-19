// TS stand-in for Lean `Fw.Console.PreviewCache` (`kind`, `cacheControl`, `compressible`), checked against the golden
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

function stem(path: string): string {
  const name = lastSegment(path);
  const e = ext(path);
  return e === "" ? name : [...name].slice(0, [...name].length - [...e].length).join("");
}

function hashedStem(s: string): boolean {
  const cs = [...s];
  const n = cs.length;
  if (n <= 8) return false;
  const sep = cs[n - 9];
  const t = cs.slice(n - 8);
  if (sep !== "-" && sep !== ".") return false;
  if (!t.every((c) => /[A-Za-z0-9_]/.test(c))) return false;
  const digit = t.some((c) => /[0-9]/.test(c)), alpha = t.some((c) => /[A-Za-z]/.test(c));
  return (digit && alpha) || (t.slice(1).some((c) => /[A-Z]/.test(c)) && t.some((c) => /[a-z]/.test(c)));
}

export function kind(path: string): Kind {
  if (ext(path) === ".html") return "html";
  if (path.startsWith(IMMUTABLE_DIR) || hashedStem(stem(path))) return "hashed";
  return "other";
}

export const cacheControl = (k: Kind): string => (k === "hashed" ? "public, max-age=31536000, immutable" : "no-cache");

const COMPRESSIBLE = new Set([".html", ".css", ".js", ".mjs", ".json", ".svg", ".txt"]);
export const compressible = (path: string): boolean => COMPRESSIBLE.has(ext(path));

/** The reply of Lean `console.previewCache` for one path. */
export function cachePolicy(path: string) {
  const k = kind(path);
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
