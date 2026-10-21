// The information panel of a look-change review: the gain table, the code the flag changes, the mechanism and the formulas are
// Lean `console.reviewInfo` (Fw.Console.ReviewInfo). This file only reads the named line ranges from the checkout at request
// time (I/O glue) and refuses a range whose anchor text has moved. It decides nothing.
import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, join, normalize, sep } from "node:path";
import type { Hono } from "hono";
import type { Store } from "../store.ts";

/** An excerpt as Lean names it. */
export interface ExcerptSpec { id: string; side: string; file: string; first: number; last: number; anchor: string; note: string }

/** An excerpt as the panel gets it: the lines with their numbers, or why they could not be read. */
export type ExcerptOut =
  | (ExcerptSpec & { ok: true; lines: { n: number; text: string }[] })
  | (ExcerptSpec & { ok: false; reason: string });

/** Read `spec`'s lines from `root`. The range must lie inside the checkout and still contain the anchor. */
export function readExcerpt(root: string, spec: ExcerptSpec): ExcerptOut {
  const rel = normalize(spec.file);
  if (isAbsolute(rel) || rel.startsWith("..") || rel.split(sep).includes("..")) return { ...spec, ok: false, reason: "the file is outside the checkout" };
  const f = join(root, rel);
  if (!existsSync(f)) return { ...spec, ok: false, reason: `${spec.file} does not exist in the checkout` };
  const all = readFileSync(f, "utf8").split("\n");
  if (spec.first < 1 || spec.last < spec.first || spec.last > all.length) return { ...spec, ok: false, reason: `lines ${spec.first}-${spec.last} are outside ${spec.file}` };
  const lines = all.slice(spec.first - 1, spec.last).map((text, i) => ({ n: spec.first + i, text }));
  if (!lines.some((l) => l.text.includes(spec.anchor))) {
    return { ...spec, ok: false, reason: `the anchor "${spec.anchor}" is no longer in ${spec.file}:${spec.first}-${spec.last}; the Lean range needs an update` };
  }
  return { ...spec, ok: true, lines };
}

/** `GET /api/reviews/<flag>/info`: the panel of a flag. Behind the owner gate like every /api route (mounted on the same app). */
export function mountReviewInfo(app: Hono, store: Store, root: string) {
  app.get("/api/reviews/:flag/info", async (c) => {
    c.header("Cache-Control", "no-store");
    const flag = c.req.param("flag");
    let r: Record<string, unknown>;
    try { r = await store.core.ops("console.reviewInfo", { flag }); }
    catch (e) { return c.json({ ok: false, reason: `the core failed: ${(e as Error).message}` }, 500); }
    if (r.ok !== true) return c.json({ ok: false, reason: String(r.reason ?? "no information") }, 404);
    const specs = r.excerpts as ExcerptSpec[];
    return c.json({ ...r, excerpts: specs.map((s) => readExcerpt(root, s)) });
  });
}
