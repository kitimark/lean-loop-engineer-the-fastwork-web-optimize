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
};
type Listing = { previews: Pv[]; failed: { id: string; task: string; error: string }[] };

export const wantsDetail = (id: string) => id.startsWith("port-") || id.startsWith("fix-");
const J = { "content-type": "application/json" };
export const urls = (p: Pick<Pv, "rp" | "op">) => ({
  rewrite: `http://127.0.0.1:${p.rp}/`, original: `http://127.0.0.1:${p.op}/`, compare: `http://127.0.0.1:${p.rp}/__fw/compare`,
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

  const mine = l.previews.find((p) => p.task === id) ?? null;
  const failed = l.failed.filter((f) => f.task === id).at(-1) ?? null;

  async function start() {
    setMsg(null);
    const r = await fetch("/api/previews", { method: "POST", headers: J, body: JSON.stringify({ task: id }) });
    const j = await r.json();
    if (!j.ok) setMsg(`refused: ${j.reason}`);
    await load();
  }
  async function stop(pid: string) {
    setMsg(null);
    const r = await fetch(`/api/previews/${pid}/stop`, { method: "POST", headers: J, body: "{}" });
    const j = await r.json();
    if (!j.ok) setMsg(`refused: ${j.reason}`);
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
            {!mine && d.preview.target.kind !== "none" && <button className="rounded border px-2 py-0.5" onClick={() => void start()}>Preview</button>}
            {mine && <button className="rounded border px-2 py-0.5" onClick={() => void stop(mine.id)}>Stop</button>}
          </div>
          {mine?.phase === "building" && <div>building (a few seconds to a minute)</div>}
          {mine?.phase === "serving" && (
            <ul>
              <li>task version: <a className="underline" href={urls(mine).rewrite} target="_blank" rel="noreferrer">{urls(mine).rewrite}</a></li>
              <li>original: <a className="underline" href={urls(mine).original} target="_blank" rel="noreferrer">{urls(mine).original}</a></li>
              <li>side by side: <a className="underline" href={urls(mine).compare} target="_blank" rel="noreferrer">{urls(mine).compare}</a></li>
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
