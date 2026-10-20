import { useCallback, useEffect, useState } from "react";
import { apiFetch } from "@/lib/auth";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { previewBase, refusedText } from "./TaskDetail";
import { addRecent, copyText, readRecent } from "./buildsOpen";

// Rendering only. Which rows exist, their order, status, target and search are Lean `console.builds` (via console-api
// `GET /api/builds`); a Preview click posts only the row id, and the server recomputes the commit and the search.
type Pv = { id: string; task: string; phase: "building" | "serving"; search?: string; target?: { sha: string } };
type Port = { id: string; task: string; group: string; sha: string; landedAt: number; title: string; slot: string };
type Opt = { id: string; kind: string; name: string; search: string; status: string; note: string | null; slot: string };
type Data = {
  mainSha: string; ports: Port[]; optimize: Opt[]; searches: string[]; canPreview?: boolean; previewPort?: number | null;
  previews: Pv[]; failed: { id: string; task: string; error: string }[];
};

const J = { "content-type": "application/json" };
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
/** One opened link: `url` is the server's full link (the console's LAN host when LAN is on, else loopback; no token or cookie). */
type Opened = { key: string; label: string; url: string };
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
  const [search, setSearch] = useState("");
  const [recent, setRecent] = useState<string[]>(() => readRecent());
  const [opened, setOpened] = useState<Opened[]>([]);
  const [busy, setBusy] = useState<string | null>(null);
  const [copied, setCopied] = useState<string | null>(null);
  const [reasons, setReasons] = useState<string[]>([]);
  const building = d?.previews.some((p) => p.phase === "building") ?? false;
  useEffect(() => {
    if (!building) return;
    const t = setInterval(() => void load(), 2000);
    return () => clearInterval(t);
  }, [building, load]);

  /** Open one row (`{row}`) or one pasted search (`{search}`). console-api decides everything: it checks the search, reuses or starts the
   *  build and returns the path. The tab is opened on the click (so a pop-up blocker allows it) and sent to the path when it is ready. */
  async function open(label: string, body: { row: string } | { search: string }, arm: "r" | "compare" = "r") {
    setMsg(null); setReasons([]); setBusy(label);
    const w = window.open("about:blank", "_blank");
    if (w) w.opener = null;
    const fail = (m: string) => { w?.close(); setMsg(m); };
    const until = Date.now() + 10 * 60_000; // one deadline for the whole open: 10 min covers a cold build
    try {
      while (Date.now() < until) {
        const r = await apiFetch("/api/builds/open", { method: "POST", headers: J, body: JSON.stringify({ ...body, arm }) });
        const j = await r.json();
        if (!j.ok) {
          if (Array.isArray(j.reasons)) setReasons(j.reasons.map(String));
          return fail(j.reason === "search refused" ? "That search is not valid; nothing was opened." : refusedText(String(j.reason)));
        }
        if (j.state === "open") {
          const href = `${previewBase(d?.previewPort)}${j.path}`;
          if (w) w.location.href = href;
          else setMsg(`Pop-up blocked: open ${href}`);
          setOpened((o) => [{ key: `${label}|${arm}`, label: `${label}${arm === "compare" ? " (compare)" : ""}`, url: String(j.url) }, ...o.filter((x) => x.key !== `${label}|${arm}`)].slice(0, 12));
          if ("search" in body) setRecent(addRecent(String(j.canonical)));
          return;
        }
        // pending: a build of this commit runs; wait until it serves (or is gone), then ask again
        const id = String(j.preview);
        while (Date.now() < until) {
          await sleep(2000);
          const l = await (await apiFetch("/api/previews")).json();
          const p = (l.previews ?? []).find((x: Pv) => x.id === id);
          if (p?.phase === "serving") break;
          if (!p) { const f = (l.failed ?? []).find((x: { id: string }) => x.id === id); return fail(f ? `The build failed: ${f.error}` : "The build stopped before it was ready."); }
        }
      }
      fail("Timed out waiting for the build.");
    } catch (e) { fail((e as Error).message); } finally { setBusy(null); void load(); }
  }
  async function copy(o: Opened) { setCopied((await copyText(o.url)) ? o.key : null); }
  if (!d) return <p className="text-muted-foreground">{msg ?? "Loading builds..."}</p>;
  const base = previewBase(d.previewPort);
  // A Builds slot (land-<task>, opt-<kind>-<name>) belongs to one row, so the slot and search find its preview; a
  // preview built from an older main stays listed with its commit.
  const state = (slot: string, search: string, sha: string) => {
    const p = d.previews.find((x) => x.task === slot && (x.search ?? "") === search);
    if (p?.phase === "serving") {
      const at = p.target?.sha && p.target.sha !== sha ? <span className="text-muted-foreground"> (at {p.target.sha.slice(0, 7)})</span> : null;
      return (
        <span className="space-x-2">
          <a className="underline" href={`${base}/preview/${p.id}/r/${search}`} target="_blank" rel="noreferrer">rewrite</a>
          <a className="underline" href={`${base}/preview/${p.id}/o/`} target="_blank" rel="noreferrer">original</a>
          <a className="underline" href={`${base}/preview/${p.id}/compare${search}`} target="_blank" rel="noreferrer">compare</a>
          {at}
        </span>
      );
    }
    if (p) return <span>building...</span>;
    const f = d.failed.filter((x) => x.task === slot).at(-1);
    return f ? <span className="text-destructive" title={f.error}>failed</span> : null;
  };
  // One Open per row. The server reuses a serving preview of the row's commit, waits for a building one, or starts one.
  const action = (row: string, label: string) => (
    <span className="space-x-1">
      <Button size="sm" variant="outline" disabled={!d.canPreview || busy !== null} onClick={() => void open(label, { row })}>{busy === label ? "Opening..." : "Open"}</Button>
      <Button size="sm" variant="ghost" disabled={!d.canPreview || busy !== null} onClick={() => void open(label, { row }, "compare")}>Open compare</Button>
    </span>
  );
  return (
    <div className="space-y-6" data-testid="builds">
      {msg ? <p className="text-xs text-destructive">{msg}</p> : null}
      <section data-testid="builds-search">
        <h2 className="mb-2 font-semibold">Open a search in main's build</h2>
        <form className="flex flex-wrap items-center gap-2" onSubmit={(e) => { e.preventDefault(); if (search.trim()) void open(search.trim(), { search: search.trim() }); }}>
          <input className="min-w-[24rem] flex-1 rounded border bg-background px-2 py-1 font-mono text-xs" aria-label="search to open" placeholder="?preset=v2-proved&fw=morph.mount:shift-dormant"
            value={search} maxLength={2000} spellCheck={false} onChange={(e) => setSearch(e.target.value)} />
          <Button size="sm" type="submit" disabled={!d.canPreview || busy !== null || !search.trim()}>Open</Button>
          <Button size="sm" type="button" variant="ghost" disabled={!d.canPreview || busy !== null || !search.trim()} onClick={() => void open(search.trim(), { search: search.trim() }, "compare")}>Open compare</Button>
        </form>
        {reasons.length > 0 ? <ul className="mt-1 list-disc pl-5 text-xs text-destructive" role="alert">{reasons.map((r) => <li key={r}>{r}</li>)}</ul> : null}
        {recent.length > 0 ? (
          <div className="mt-2 flex flex-wrap items-center gap-1 text-xs" data-testid="recent-searches">
            <span className="text-muted-foreground">Recent (this browser):</span>
            {recent.map((r) => (
              <button key={r} type="button" className="max-w-xs truncate rounded border px-1.5 py-0.5 font-mono" title={r || "(default page)"} disabled={!d.canPreview || busy !== null}
                onClick={() => { setSearch(r); void open(r, { search: r }); }}>{r || "(default page)"}</button>
            ))}
          </div>
        ) : null}
        {opened.length > 0 ? (
          <ul className="mt-2 space-y-1 text-xs" data-testid="opened-links">
            {opened.map((o) => (
              <li key={o.key} className="flex flex-wrap items-center gap-2">
                <span className="max-w-md truncate">{o.label}</span>
                <a className="underline" href={o.url} target="_blank" rel="noreferrer">link</a>
                <Button size="sm" variant="outline" onClick={() => void copy(o)}>{copied === o.key ? "Copied" : "Copy link"}</Button>
              </li>
            ))}
          </ul>
        ) : null}
      </section>
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
                  {action(p.id, p.task)}{state(p.slot, "", p.sha)}
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
                  {action(o.id, `${o.kind} ${o.name}`)}{state(o.slot, o.search, d.mainSha)}
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
