import { useCallback, useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";

/** Task detail + owner-only Preview. All facts come from console-api (`/api/tasks/:id/detail`, `/api/previews`); the
 *  target, admission and expiry are decided by fwcore there. This file only shows them and posts the two commands. */
type Target = { kind: string; ref: string | null; sha: string | null };
type Pv = { id: string; task: string; rp: number; op: number; phase: "building" | "serving"; deadline: number; target: Target };
type Detail = {
  ok: true; kind: string; title: string; state: string | null; owner: string | null; deps: string[]; blockers: string[];
  writes: string[]; parts: string[];
  git: { head: string | null; headSource: string; branch: string | null; onMain: boolean; containedIn: string[] };
  handoff: { ref: string; excerpt: string; lines: number } | null;
  preview: { target: Target; running: Pv | null };
  previewPort?: number | null; // the preview port (another origin than the console)
  canPreview?: boolean; // this browser holds the owner cookie (set by the one-time owner link the console prints)
};
type Listing = { previewPort?: number | null; previews: Pv[]; failed: { id: string; task: string; error: string }[] };

export const wantsDetail = (id: string) => id.startsWith("port-") || id.startsWith("fix-");
const J = { "content-type": "application/json" };
/** What a refusal means to the owner; `notOwner` is the missing owner cookie or Origin (open the console's owner link). */
export const refusedText = (reason: string) =>
  reason === "notOwner" ? "refused: this browser is not signed in as owner; log in as owner (the login page, or the owner link the console printed in its terminal)" : `refused: ${reason}`;
/** Preview links point at the preview port (console port + 1): another origin than the console, so preview JavaScript cannot
 *  act as the owner. `base` is `<protocol>//<host>:<previewPort>`, built from the page's own host (so it works from the phone). */
export const previewBase = (port: number | null | undefined, loc?: { protocol: string; hostname: string }) =>
  { if (!port) return ""; const l = loc ?? window.location; return `${l.protocol}//${l.hostname}:${port}`; };
export const urls = (p: Pick<Pv, "id">, base = "") => ({
  rewrite: `${base}/preview/${p.id}/r/`, original: `${base}/preview/${p.id}/o/`, compare: `${base}/preview/${p.id}/compare`,
});
export const targetText = (t: Target) =>
  t.kind === "none" ? "no work to preview yet" : t.kind === "main" ? "already on main" :
  t.kind === "integration" ? `integration branch ${t.ref} @ ${t.sha}` : `its own branch @ ${t.sha}`;

export function TaskDetail({ id, version }: { id: string; version?: number }) {
  const [open, setOpen] = useState(false);
  const [d, setD] = useState<Detail | null>(null);
  const [l, setL] = useState<Listing>({ previews: [], failed: [] });
  const [msg, setMsg] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const [a, b] = await Promise.all([fetch(`/api/tasks/${id}/detail`), fetch("/api/previews")]);
      const da = await a.json();
      if (da.ok) setD(da); else setMsg(String(da.reason));
      const lb = await b.json();
      if (lb.ok) setL(lb);
    } catch (e) { setMsg((e as Error).message); }
  }, [id]);

  useEffect(() => { if (open) void load(); }, [open, load, version]);
  const building = l.previews.some((p) => p.task === id && p.phase === "building");
  useEffect(() => {
    if (!open || !building) return;
    const t = setInterval(() => void load(), 2000);
    return () => clearInterval(t);
  }, [open, building, load]);

  const pbase = previewBase(l.previewPort ?? d?.previewPort);
  const mine = l.previews.find((p) => p.task === id) ?? null;
  const failed = l.failed.filter((f) => f.task === id).at(-1) ?? null;

  async function start() {
    setMsg(null);
    const r = await fetch("/api/previews", { method: "POST", headers: J, body: JSON.stringify({ task: id }) });
    const j = await r.json();
    if (!j.ok) setMsg(refusedText(String(j.reason)));
    await load();
  }
  async function stop(pid: string) {
    setMsg(null);
    const r = await fetch(`/api/previews/${pid}/stop`, { method: "POST", headers: J, body: "{}" });
    const j = await r.json();
    if (!j.ok) setMsg(refusedText(String(j.reason)));
    await load();
  }

  return (
    <details className="mt-1 text-xs" data-testid="task-detail" onToggle={(e) => setOpen((e.currentTarget as HTMLDetailsElement).open)}>
      <summary className="cursor-pointer text-muted-foreground">details and preview</summary>
      {open && !d && <p>{msg ?? "loading"}</p>}
      {d && (
        <div className="mt-1 space-y-1">
          <div className="flex flex-wrap gap-1">
            <Badge variant="outline">{d.kind}</Badge>
            {d.state && <Badge variant="secondary">{d.state}</Badge>}
            {d.parts.map((p) => <Badge key={p} variant="outline">part {p}</Badge>)}
          </div>
          {d.writes.length > 0 && <div>writes: <code>{d.writes.join(", ")}</code></div>}
          {d.deps.length > 0 && <div>deps: {d.deps.join(", ")}</div>}
          <div>
            git: {d.git.head ? <code>{d.git.head}</code> : "no commit found"} ({d.git.headSource}
            {d.git.branch ? `, ${d.git.branch}` : ""}){d.git.onMain ? ", on main" : ""}
            {d.git.containedIn.length > 0 ? `, in ${d.git.containedIn.join(", ")}` : ""}
          </div>
          {d.handoff && (
            <details><summary>handoff ({d.handoff.lines} lines, from {d.handoff.ref})</summary>
              <pre className="max-h-48 overflow-auto whitespace-pre-wrap">{d.handoff.excerpt}</pre></details>
          )}
          <div className="flex flex-wrap items-center gap-2">
            <span>preview: {targetText(d.preview.target)}</span>
            {d.canPreview === false && <span data-testid="owner-hint">to start or stop a preview, <a className="underline" href="/owner/login">log in as owner</a> (or open the owner link the console printed in its terminal, once, in this browser)</span>}
            {d.canPreview !== false && !mine && d.preview.target.kind !== "none" && <button className="rounded border px-2 py-0.5" onClick={() => void start()}>Preview</button>}
            {d.canPreview !== false && mine && <button className="rounded border px-2 py-0.5" onClick={() => void stop(mine.id)}>Stop</button>}
          </div>
          {mine?.phase === "building" && <div>building (a few seconds to a minute)</div>}
          {mine?.phase === "serving" && (
            <ul>
              <li>task version: <a className="underline" href={urls(mine, pbase).rewrite} target="_blank" rel="noreferrer">{urls(mine, pbase).rewrite}</a></li>
              <li>original: <a className="underline" href={urls(mine, pbase).original} target="_blank" rel="noreferrer">{urls(mine, pbase).original}</a></li>
              <li>side by side: <a className="underline" href={urls(mine, pbase).compare} target="_blank" rel="noreferrer">{urls(mine, pbase).compare}</a></li>
              <li>expires {new Date(mine.deadline).toLocaleTimeString()}</li>
            </ul>
          )}
          {!mine && failed && <div role="alert">last preview failed: {failed.error}</div>}
          {msg && <div role="alert">{msg}</div>}
        </div>
      )}
    </details>
  );
}
