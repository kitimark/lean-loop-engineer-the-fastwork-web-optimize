import { useCallback, useEffect, useState } from "react";
import { apiFetch } from "@/lib/auth";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { previewBase, refusedText } from "./TaskDetail";

// Rendering only. Which rows exist, their order, status, target and search are Lean `console.builds` (via console-api
// `GET /api/builds`); a Preview click posts only the row id, and the server recomputes the commit and the search.
type Pv = { id: string; task: string; phase: "building" | "serving"; search?: string };
type Port = { id: string; task: string; group: string; sha: string; landedAt: number; title: string; slot: string };
type Opt = { id: string; kind: string; name: string; search: string; status: string; note: string | null; slot: string };
type Data = {
  mainSha: string; ports: Port[]; optimize: Opt[]; searches: string[]; canPreview?: boolean; previewPort?: number | null;
  previews: Pv[]; failed: { id: string; task: string; error: string }[];
};

const J = { "content-type": "application/json" };
const when = (s: number) => (s ? new Date(s * 1000).toISOString().slice(0, 16).replace("T", " ") : "");

export function BuildsView() {
  const [d, setD] = useState<Data | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const load = useCallback(async () => {
    try {
      const j = await (await apiFetch("/api/builds")).json();
      if (j.ok) setD(j); else setMsg(String(j.reason));
    } catch (e) { setMsg((e as Error).message); }
  }, []);
  useEffect(() => { void load(); }, [load]);
  const building = d?.previews.some((p) => p.phase === "building") ?? false;
  useEffect(() => {
    if (!building) return;
    const t = setInterval(() => void load(), 2000);
    return () => clearInterval(t);
  }, [building, load]);

  async function start(row: string) {
    setMsg(null);
    const r = await apiFetch("/api/previews", { method: "POST", headers: J, body: JSON.stringify({ build: row }) });
    const j = await r.json();
    if (!j.ok) setMsg(refusedText(String(j.reason)));
    await load();
  }
  if (!d) return <p className="text-muted-foreground">{msg ?? "Loading builds..."}</p>;
  const base = previewBase(d.previewPort);
  const state = (slot: string, search: string) => {
    const p = d.previews.find((x) => x.task === slot && (x.search ?? "") === search);
    if (p?.phase === "serving") return <a className="underline" href={`${base}/preview/${p.id}/compare${search}`} target="_blank" rel="noreferrer">open compare</a>;
    if (p) return <span>building...</span>;
    const f = d.failed.filter((x) => x.task === slot).at(-1);
    return f ? <span className="text-destructive" title={f.error}>failed</span> : null;
  };
  return (
    <div className="space-y-6" data-testid="builds">
      {msg ? <p className="text-xs text-destructive">{msg}</p> : null}
      <section>
        <h2 className="mb-2 font-semibold">Ports and fixes, as landed on main ({d.ports.length})</h2>
        <Table data-testid="builds-ports">
          <TableHeader><TableRow><TableHead>Task</TableHead><TableHead>Land commit</TableHead><TableHead>Landed (UTC)</TableHead><TableHead>Title</TableHead><TableHead /></TableRow></TableHeader>
          <TableBody>
            {d.ports.map((p) => (
              <TableRow key={p.id}>
                <TableCell><Badge variant="outline">{p.group}</Badge> {p.task}</TableCell>
                <TableCell className="font-mono text-xs">{p.sha.slice(0, 9)}</TableCell>
                <TableCell className="text-xs">{when(p.landedAt)}</TableCell>
                <TableCell className="max-w-md whitespace-normal break-words text-xs">{p.title}</TableCell>
                <TableCell className="space-x-2 text-xs">
                  <Button size="sm" variant="outline" disabled={!d.canPreview} onClick={() => void start(p.id)}>Preview</Button>{state(p.slot, "")}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </section>
      <section>
        <h2 className="mb-2 font-semibold">Optimizations, main @ {d.mainSha.slice(0, 9)} ({d.optimize.length})</h2>
        <Table data-testid="builds-optimize">
          <TableHeader><TableRow><TableHead>Kind</TableHead><TableHead>Name</TableHead><TableHead>Status</TableHead><TableHead>Note</TableHead><TableHead /></TableRow></TableHeader>
          <TableBody>
            {d.optimize.map((o) => (
              <TableRow key={o.id}>
                <TableCell><Badge variant="outline">{o.kind}</Badge></TableCell>
                <TableCell className="font-mono text-xs">{o.name}</TableCell>
                <TableCell className="text-xs">{o.status}</TableCell>
                <TableCell className="max-w-md whitespace-normal break-words text-xs">{o.note ?? ""}</TableCell>
                <TableCell className="space-x-2 text-xs">
                  <Button size="sm" variant="outline" disabled={!d.canPreview} onClick={() => void start(o.id)}>Preview</Button>{state(o.slot, o.search)}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        {d.canPreview ? null : <p className="mt-2 text-xs text-muted-foreground">Preview needs the owner sign-in.</p>}
      </section>
    </div>
  );
}
