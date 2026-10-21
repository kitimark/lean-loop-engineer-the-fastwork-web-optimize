// Experiment reports in the Reviews tab (review-reports). Whether a report is shown (every number tagged MEASURED with a CI run id or
// INFERRED with its reason), what its step is and whether an answer is accepted (approve, hold, reject, plus a comment that becomes a
// `review.feedback` on the topic `report:<id>`) are Lean `console.report` (Fw.Console.Report). This file stores the report JSON next to
// the log (`<console dir>/reports/<id>.json`: a step body holds 2000 characters, a report is longer), posts the step Lean says is
// missing, and turns an accepted answer into the user's commands. It decides nothing.
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { isDeepStrictEqual } from "node:util";
import { join } from "node:path";
import type { Hono } from "hono";
import { z } from "zod";
import type { Store } from "../store.ts";
import { threads, type Thread } from "./feedback.ts";

/** A report as an experiment writes it (`results/<task>/report.json`); Lean parses and judges it, so the shape is only a pass-through. */
export type ReportJson = Record<string, unknown>;

/** An item as Lean `console.report` returns it. */
export interface ReportItem { id: string; step: string; title: string; body: string; state: "unposted" | "open" | "approve" | "hold" | "reject" | "closed"; post: boolean }
export interface Invalid { index: number; id?: string; reason: string }
interface LeanReply {
  items: ReportItem[]; invalid: Invalid[]; options: string[];
  answer: { ok: boolean; reason?: string; step?: string; word?: string; feedback?: { flag: string; text: string } } | null;
}

const dirOf = (store: Store) => join(store.dir, "reports");

/** The stored reports, in file-name order; a file that is not JSON is reported, not hidden. */
function readStored(store: Store): { reports: ReportJson[]; unreadable: Invalid[] } {
  const dir = dirOf(store);
  const reports: ReportJson[] = [];
  const unreadable: Invalid[] = [];
  if (!existsSync(dir)) return { reports, unreadable };
  for (const f of readdirSync(dir).filter((n) => n.endsWith(".json")).sort()) {
    try { reports.push(JSON.parse(readFileSync(join(dir, f), "utf8")) as ReportJson); }
    catch { unreadable.push({ index: -1, id: f.replace(/\.json$/, ""), reason: "the stored file is not JSON" }); }
  }
  return { reports, unreadable };
}

async function ask(store: Store, reports: ReportJson[], answer?: { id: string; word: string; comment?: string }): Promise<LeanReply> {
  const steps = (await store.board()).steps.map((s) => ({ id: s.id, answer: s.answer, open: s.status === "waiting" || s.status === "started" }));
  return (await store.core.ops("console.report", { reports, steps, ...(answer ? { answer } : {}) })) as unknown as LeanReply;
}

/** The outcome of a post: `ok` with the id, or the reason it was refused. */
export type PostResult = { ok: true; id: string; duplicate: boolean } | { ok: false; status: 409 | 422 | 500; reason: string };

/** Validate a report through Lean and post its step. A repeated post of the same report is a duplicate; another report under a used id is refused. */
export async function postReport(store: Store, report: ReportJson): Promise<PostResult> {
  let r: LeanReply;
  try { r = await ask(store, [report]); } catch (e) { return { ok: false, status: 422, reason: String((e as Error).message).replace(/^fwcore: /, "") }; }
  const bad = r.invalid[0];
  if (bad) return { ok: false, status: 422, reason: bad.reason };
  const item = r.items[0];
  if (!item) return { ok: false, status: 500, reason: "the core returned no item" };
  const file = join(dirOf(store), `${item.id}.json`);
  if (existsSync(file)) {
    let old: unknown = null;
    try { old = JSON.parse(readFileSync(file, "utf8")); } catch { /* an unreadable file counts as different */ }
    if (!isDeepStrictEqual(old, report)) return { ok: false, status: 409, reason: `a report with the id ${item.id} exists; post a changed report under a new id` };
  } else {
    mkdirSync(dirOf(store), { recursive: true });
    const tmp = `${file}.tmp`;
    writeFileSync(tmp, JSON.stringify(report, null, 2) + "\n");
    renameSync(tmp, file);
  }
  if (!item.post) return { ok: true, id: item.id, duplicate: true };
  const reply = await store.submit({ type: "step.post", key: `report-post-${item.step}`, actor: "script", step: item.step, card: null, title: item.title,
    kind: "choice", options: r.options, audience: "user", body: item.body });
  if (!reply.ok) return { ok: false, status: 422, reason: reply.reason ?? "refused" };
  return { ok: true, id: item.id, duplicate: false };
}

const PostReq = z.object({ report: z.record(z.string(), z.unknown()) });
const AnswerReq = z.object({ word: z.string().max(20), comment: z.string().max(20_000).optional(), cid: z.string().regex(/^[A-Za-z0-9-]{8,60}$/).optional() });

export function mountReports(app: Hono, store: Store) {
  /** `GET /api/reports`: the reports Lean shows (a step that is not posted yet is left out), each with its stored JSON and its feedback thread. Read-only. */
  app.get("/api/reports", async (c) => {
    c.header("Cache-Control", "no-store");
    const { reports, unreadable } = readStored(store);
    const r = await ask(store, reports);
    const byId = new Map(reports.map((x) => [String((x as { id?: unknown }).id), x]));
    const fb = new Map<string, Thread>((await threads(store)).map((t) => [t.flag, t]));
    const items = r.items.filter((i) => i.state !== "unposted").map((i) => ({
      ...i, report: byId.get(i.id), feedback: fb.get(`report:${i.id}`) ?? { flag: `report:${i.id}`, open: 0, comments: [] },
    }));
    return c.json({ ok: true, open: items.filter((i) => i.state === "open").length, options: r.options, items, invalid: [...r.invalid, ...unreadable] });
  });

  /** `POST /api/reports` {report}: validate through Lean and post the step (agents and the lead, through `fw review report post`). */
  app.post("/api/reports", async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ ok: false, reason: "body is not JSON" }, 400); }
    const req = PostReq.safeParse(body);
    if (!req.success) return c.json({ ok: false, reason: "expected {report}" }, 400);
    const res = await postReport(store, req.data.report);
    return res.ok ? c.json(res) : c.json({ ok: false, reason: res.reason }, res.status);
  });

  /** `POST /api/reports/<id>/answer` {word, comment?, cid?}: Lean accepts or refuses; an accepted answer is the user's `step.answer`, and a
   *  comment is the user's `review.feedback` on `report:<id>` (a repeated `cid` is one comment). */
  app.post("/api/reports/:id/answer", async (c) => {
    c.header("Cache-Control", "no-store");
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ ok: false, reason: "body is not JSON" }, 400); }
    const req = AnswerReq.safeParse(body);
    if (!req.success) return c.json({ ok: false, reason: "expected {word, comment?}" }, 400);
    const id = c.req.param("id");
    let a: LeanReply["answer"];
    try { a = (await ask(store, readStored(store).reports, { id, word: req.data.word, comment: req.data.comment ?? "" })).answer; }
    catch (e) { return c.json({ ok: false, reason: String((e as Error).message).replace(/^fwcore: /, "") }, 422); }
    if (!a || !a.ok || !a.step || !a.word) return c.json({ ok: false, reason: a?.reason ?? "refused" }, 422);
    const reply = await store.submit({ type: "step.answer", key: `report-answer-${a.step}-${a.word}`, actor: "user", step: a.step, answer: a.word });
    if (!reply.ok) return c.json(reply, 422);
    if (a.feedback) {
      const fid = `fb-${req.data.cid ?? `${Date.now().toString(36)}-${Math.random().toString(16).slice(2, 10)}`}`;
      const fr = await store.submit({ type: "review.feedback", key: `review-feedback-${a.feedback.flag}-${fid}`, actor: "user", flag: a.feedback.flag, id: fid, text: a.feedback.text } as never);
      if (!fr.ok) return c.json({ ok: false, reason: `the answer was recorded; the comment was refused: ${fr.reason}` }, 422);
    }
    return c.json({ ok: true, word: a.word });
  });
}
