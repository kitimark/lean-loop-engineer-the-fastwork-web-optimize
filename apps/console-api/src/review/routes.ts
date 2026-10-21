// The review queue (user-review-queue): which kept look changes wait for the owner's visual review is Lean `console.review`
// (Fw.Console.Review). This file posts the step Lean says is missing, attaches the ledger's words and the review material, and
// turns an accepted Keep or Reject into a `step.answer` of the user. It decides nothing. GET changes no board state (the strip GET may fill the review cache from CI); the steps are posted by
// POST (before it asks Lean) and by `ensureReviewSteps` at startup.
import { execFile } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync } from "node:fs";
import { join } from "node:path";
import type { Hono } from "hono";
import { z } from "zod";
import type { Store } from "../store.ts";
import { readLedger } from "../preview/compose.ts";
import { previewInfo } from "./preview.ts";

/** The review material of a flag: what exists and where it can be fetched. Facts from `Fw.Preset.Gen.lookDecisions`, through Lean `console.review`. */
export interface Material {
  chromium: { state: "ready" | "pending"; run?: string; artifact?: string; expires?: string; task?: string };
  webkit: { state: "ready" | "pending"; run?: string; artifact?: string; expires?: string; task?: string };
}

const Links = z.record(z.string(), z.string().regex(/^https:\/\/\S+$/));

/** The private review page links of `.local/reviews.json` ({"<flag>": "<url>"}). A missing or unreadable file gives none. */
export function readLinks(root: string): Record<string, string> {
  const f = join(root, ".local/reviews.json");
  if (!existsSync(f)) return {};
  try {
    const r = Links.safeParse(JSON.parse(readFileSync(f, "utf8")));
    return r.success ? r.data : {};
  } catch { return {}; }
}

/** A strip of an item as Lean `console.review` returns it (`Fw.Console.ReviewStrips`). */
export interface StripOut {
  engine: string; state: "ready" | "expired" | "missing"; width?: number; push?: "open" | "close"; file?: string;
  run?: string; artifact?: string; expires?: string; note?: string; diff?: string; redo?: string;
}

/** Fetches one CI artifact into `dir` (an empty directory). Rejects with the reason. */
export type Downloader = (run: string, artifact: string, dir: string) => Promise<void>;

/** The default downloader: `gh run download <run> -n <artifact> -D <dir>`. One try; the caller never retries a refusal. */
export const ghDownload: Downloader = (run, artifact, dir) => new Promise((resolve, reject) => {
  execFile("gh", ["run", "download", run, "-n", artifact, "-D", dir], { timeout: 120_000 }, (err, _o, stderr) => {
    if (err) reject(new Error(String(stderr || err.message).trim().slice(0, 300))); else resolve();
  });
});

export interface ReviewOpts { download?: Downloader; today?: () => string }

interface LeanItem {
  strips?: StripOut[];
  flag: string; step: string; date: string; words: string; state: "open" | "keep" | "reject"; material: Material | null; post: boolean; title: string; body: string; audience: string;
}
interface LeanReply { items: LeanItem[]; open: number; options: string[]; answer: { ok: boolean; reason?: string; step?: string; word?: string } | null;
  serve?: { ok: boolean; reason?: string; run?: string; artifact?: string; path?: string } | null }

const utcDay = () => new Date().toISOString().slice(0, 10);

async function ask(store: Store, answer?: { flag: string; word: string }, extra: Record<string, unknown> = {}): Promise<LeanReply> {
  // `open` is the step status waiting or started (Lean StepStatus.isOpen); done, answered and cancelled steps are closed
  const steps = (await store.board()).steps.map((s) => ({ id: s.id, answer: s.answer, open: s.status === "waiting" || s.status === "started" }));
  return (await store.core.ops("console.review", { steps, ...(answer ? { answer } : {}), ...extra })) as unknown as LeanReply;
}

/** Post the steps Lean names as missing (single writer: the store); the reducer refuses a second post of one id. */
async function post(store: Store, r: LeanReply): Promise<LeanReply> {
  let posted = false;
  for (const i of r.items) {
    if (!i.post) continue;
    await store.submit({ type: "step.post", key: `review-post-${i.step}`, actor: "script", step: i.step, card: null, title: i.title,
      kind: "choice", options: r.options, audience: "user", body: i.body });
    posted = true;
  }
  return posted ? ask(store) : r;
}

/** Post the review steps Lean says are missing (startup and reconcile; never a GET). */
export async function ensureReviewSteps(store: Store): Promise<void> { await post(store, await ask(store)); }

/** One download per artifact at a time, kept under `<console dir>/review-cache/<run>/<artifact>/`. A failure is remembered for a
 *  while (a refusal for longer) and not retried before that. */
export class StripCache {
  private inflight = new Map<string, Promise<string>>();
  private failed = new Map<string, { at: number; why: string; ms: number }>();
  private base: string; private download: Downloader; private clock: () => number;
  constructor(base: string, download: Downloader, clock: () => number = Date.now) { this.base = base; this.download = download; this.clock = clock; }

  /** The directory of an artifact; fetched on first use. `run` and `artifact` come from Lean rows, never from a request. */
  async dir(run: string, artifact: string): Promise<string> {
    const final = join(this.base, run, artifact);
    if (existsSync(final)) return final;
    const key = `${run}/${artifact}`;
    const f = this.failed.get(key);
    if (f && this.clock() - f.at < f.ms) throw new Error(f.why);
    let p = this.inflight.get(key);
    if (!p) {
      p = (async () => {
        const tmp = join(this.base, run, `.${artifact}.tmp`);
        rmSync(tmp, { recursive: true, force: true });
        mkdirSync(tmp, { recursive: true });
        try { await this.download(run, artifact, tmp); renameSync(tmp, final); return final; }
        catch (e) {
          rmSync(tmp, { recursive: true, force: true });
          const why = (e as Error).message;
          this.failed.set(key, { at: this.clock(), why, ms: /403/.test(why) ? 900_000 : 60_000 });
          throw e;
        } finally { this.inflight.delete(key); }
      })();
      this.inflight.set(key, p);
    }
    return p;
  }
}

export function mountReviews(app: Hono, store: Store, root: string, opts: ReviewOpts = {}) {
  const today = opts.today ?? utcDay;
  const cache = new StripCache(join(store.dir, "review-cache"), opts.download ?? ghDownload);
  /** `GET /api/reviews`: read-only. The Lean items with what changed, the material and the private link (when `.local/reviews.json` has one). */
  app.get("/api/reviews", async (c) => {
    c.header("Cache-Control", "no-store");
    const r = await ask(store, undefined, { today: today() });
    const ledger = readLedger(root).findings;
    const links = readLinks(root);
    const pv = await previewInfo(store);
    return c.json({
      ok: true, open: r.open, options: r.options,
      items: r.items.map((i) => {
        const row = ledger.find((x) => x.flag === i.flag);
        return {
          flag: i.flag, step: i.step, state: i.state, date: i.date, words: i.words, audience: i.audience,
          changed: row ? { id: row.id ?? null, candidate: row.candidate, visual: row.visual ?? null, chromium: row.chromium ?? null, webkit: row.webkit ?? null } : null,
          material: i.material,
          strips: i.strips ?? [],
          link: links[i.flag] ?? null,
          preview: pv[i.flag] ?? null,
        };
      }),
    });
  });

  /** `GET /api/reviews/<flag>/strips/<file>`: a strip image. Lean `console.review` (`serve`) is the allowlist: it names the CI run,
   *  artifact and path of a row, or refuses; nothing of the request reaches the filesystem. Behind the owner gate like every /api route. */
  app.get("/api/reviews/:flag/strips/:file", async (c) => {
    let r: LeanReply;
    try { r = await ask(store, undefined, { today: today(), serve: { flag: c.req.param("flag"), file: c.req.param("file") } }); }
    catch (e) { return c.json({ ok: false, reason: `the core failed: ${(e as Error).message}` }, 500); }
    const s = r.serve;
    if (!s || !s.ok || !s.run || !s.artifact || !s.path) return c.json({ ok: false, reason: s?.reason ?? "not a servable strip" }, 404);
    let file: string;
    try { file = join(await cache.dir(s.run, s.artifact), s.path); }
    catch (e) { return c.json({ ok: false, reason: `the CI artifact could not be fetched: ${(e as Error).message}` }, 502); }
    if (!existsSync(file)) return c.json({ ok: false, reason: "the artifact has no such file" }, 404);
    c.header("Cache-Control", "private, no-cache");
    c.header("Content-Type", "image/png");
    return c.body(readFileSync(file));
  });

  /** `POST /api/reviews/<flag>` {decision: keep|reject}: Lean accepts or refuses; an accepted answer is the user's `step.answer`. */
  app.post("/api/reviews/:flag", async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ ok: false, reason: "body is not JSON" }, 400); }
    const parsed = z.object({ decision: z.string().max(20) }).safeParse(body);
    if (!parsed.success) return c.json({ ok: false, reason: "expected {decision: keep|reject}" }, 400);
    const flag = c.req.param("flag");
    await post(store, await ask(store));
    let a: LeanReply["answer"];
    try { a = (await ask(store, { flag, word: parsed.data.decision })).answer; } catch (e) {
      return c.json({ ok: false, reason: String((e as Error).message).replace(/^fwcore: /, "") }, 422); // Lean refused the request (a flag that is no key)
    }
    if (!a || !a.ok || !a.step || !a.word) return c.json({ ok: false, reason: a?.reason ?? "refused" }, 422);
    const reply = await store.submit({ type: "step.answer", key: `review-answer-${a.step}-${a.word}`, actor: "user", step: a.step, answer: a.word });
    return c.json(reply, reply.ok ? 200 : 422);
  });
}
