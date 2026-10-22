import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, join, normalize, sep } from "node:path";
import type { Hono } from "hono";
import type { Store } from "../store.ts";

export interface ExcerptSpec { id: string; side: string; file: string; anchor: string; span: number; note: string }

export type ExcerptOut =
  | (ExcerptSpec & { ok: true; first: number; last: number; lines: { n: number; text: string }[] })
  | (ExcerptSpec & { ok: false; reason: string });

export type Ops = (op: string, fields: Record<string, unknown>) => Promise<Record<string, unknown>>;

export function fileLines(root: string, file: string): string[] | { reason: string } {
  const rel = normalize(file);
  if (isAbsolute(rel) || rel.startsWith("..") || rel.split(sep).includes("..")) return { reason: "the file is outside the checkout" };
  const f = join(root, rel);
  if (!existsSync(f)) return { reason: `${file} does not exist in the checkout` };
  return readFileSync(f, "utf8").split("\n");
}

export async function readExcerpt(ops: Ops, root: string, flag: string, spec: ExcerptSpec): Promise<ExcerptOut> {
  const all = fileLines(root, spec.file);
  if (!Array.isArray(all)) return { ...spec, ok: false, reason: all.reason };
  const r = await ops("console.reviewExcerpt", { flag, excerpt: spec.id, lines: all });
  if (r.ok !== true) return { ...spec, ok: false, reason: String(r.reason ?? "the core gave no range") };
  const first = r.first as number, last = r.last as number;
  return { ...spec, ok: true, first, last, lines: all.slice(first - 1, last).map((text, i) => ({ n: first + i, text })) };
}

export function mountReviewInfo(app: Hono, store: Store, root: string) {
  app.get("/api/reviews/:flag/info", async (c) => {
    c.header("Cache-Control", "no-store");
    const flag = c.req.param("flag");
    const ops: Ops = (op, fields) => store.core.ops(op, fields);
    let r: Record<string, unknown>;
    let excerpts: ExcerptOut[];
    try {
      r = await ops("console.reviewInfo", { flag });
      if (r.ok !== true) return c.json({ ok: false, reason: String(r.reason ?? "no information") }, 404);
      excerpts = await Promise.all((r.excerpts as ExcerptSpec[]).map((s) => readExcerpt(ops, root, flag, s)));
    } catch (e) { return c.json({ ok: false, reason: `the core failed: ${(e as Error).message}` }, 500); }
    return c.json({ ...r, excerpts });
  });
}
