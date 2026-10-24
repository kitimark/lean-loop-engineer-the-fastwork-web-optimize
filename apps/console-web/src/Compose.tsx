import { useCallback, useEffect, useRef, useState } from "react";
import { apiFetch } from "@/lib/auth";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { previewBase, refusedText } from "./TaskDetail";
import { copyText } from "./buildsOpen";
import { answersNow, copyKnown, newestWins, openSearch, pickQuery, type Picks } from "./composeOpen";

export type CVar = { name: string; kind: string; isDefault: boolean; class: string; why: string; rows: number[]; refusal: string | null; gpu?: string | null; gpuEngines?: string | null };
export type CPart = { id: string; slot: string; group: string; pageLevel: boolean; variants: CVar[]; other: number[] };
export type CRow = {
  index: number; candidate: string; status: string; chromium: string; webkit: string; visual: string; mechanism: string;
  leanFor: string[]; leanAgainst: string[]; lesson: string; next: string; evidence: string; runs: string[]; notes: { task: string; text: string }[];
};
export type CPreset = { name: string; picks: { part: string; variant: string }[]; ok: boolean; link: string | null; reasons: string[]; notes: string[] };
export type CData = {
  regions: string[]; parts: CPart[]; presets: CPreset[]; rules: Record<string, string>; rows: Record<string, CRow>;
  decision: { ok: boolean; link: string | null; reasons: string[]; notes: string[] };
  canPreview?: boolean; previewPort?: number | null;
};

const BADGE: Record<string, "default" | "secondary" | "destructive" | "outline"> = {
  original: "outline", proved: "default", "look-change": "secondary", "ledger-proved": "secondary", measured: "secondary", refuted: "destructive", unrated: "outline",
};

export function byRegion(parts: CPart[]): { region: string; parts: CPart[] }[] {
  const out: { region: string; parts: CPart[] }[] = [];
  for (const p of parts) {
    const last = out[out.length - 1];
    if (last && last.region === p.slot) last.parts.push(p); else out.push({ region: p.slot, parts: [p] });
  }
  return out;
}

function Lines({ label, items }: { label: string; items: string[] }) {
  if (items.length === 0) return null;
  return <div><dt className="font-medium">{label}</dt>{items.map((t) => <dd key={t} className="break-words">{t}</dd>)}</div>;
}

export function Explain({ row }: { row: CRow }) {
  return (
    <div className="space-y-1 rounded border p-2 text-xs" data-testid="explain-row">
      <p className="break-words font-medium">{row.candidate} <Badge variant={row.status === "refuted" ? "destructive" : "outline"}>{row.status}</Badge></p>
      <dl className="space-y-1">
        {row.mechanism ? <div><dt className="font-medium">Mechanism</dt><dd className="break-words">{row.mechanism}</dd></div> : null}
        {row.visual ? <div><dt className="font-medium">Visual</dt><dd className="break-words">{row.visual}</dd></div> : null}
        {row.chromium ? <div><dt className="font-medium">Chromium</dt><dd className="break-words">{row.chromium}</dd></div> : null}
        {row.webkit ? <div><dt className="font-medium">WebKit</dt><dd className="break-words">{row.webkit}</dd></div> : null}
        <Lines label="Lean, for" items={row.leanFor} />
        <Lines label="Lean, against" items={row.leanAgainst} />
        {row.lesson ? <div><dt className="font-medium">Lesson</dt><dd className="break-words">{row.lesson}</dd></div> : null}
        {row.next ? <div><dt className="font-medium">Next</dt><dd className="break-words">{row.next}</dd></div> : null}
        {row.notes.map((n) => <div key={n.text}><dt className="font-medium">Note ({n.task})</dt><dd className="break-words">{n.text}</dd></div>)}
        {row.runs.length > 0 ? <div><dt className="font-medium">Runs cited</dt><dd className="break-all font-mono">{row.runs.join(", ")}</dd></div> : null}
      </dl>
    </div>
  );
}

export function PartCard({ part, chosen, rows, rules, onPick, reviewPending = [] }: { part: CPart; chosen: string; rows: Record<string, CRow>; rules: Record<string, string>; onPick: (v: string) => void; reviewPending?: string[] }) {
  const [open, setOpen] = useState(false);
  const cur = part.variants.find((v) => v.name === chosen) ?? part.variants[0]!;
  const cited = cur.rows.map((i) => rows[String(i)]).filter((r): r is CRow => !!r);
  const shown = cited.length > 0 ? cited : part.other.map((i) => rows[String(i)]).filter((r): r is CRow => !!r);
  return (
    <div className="min-w-0 space-y-2 rounded border p-3" data-testid={`part-${part.id}`}>
      <div className="flex flex-wrap items-center gap-2">
        <h3 className="break-all font-mono text-sm font-semibold">{part.id}</h3>
        <Badge variant="outline">{part.group}</Badge>
        {part.pageLevel ? <Badge variant="secondary">page-level</Badge> : null}
      </div>
      <div role="radiogroup" aria-label={`variant of ${part.id}`} className="space-y-1">
        {part.variants.map((v) => (
          <button key={v.name} type="button" role="radio" aria-checked={v.name === cur.name} data-variant={v.name} onClick={() => onPick(v.name)}
            className={`flex w-full min-w-0 flex-col items-start gap-1 rounded border px-2 py-2 text-left text-xs sm:flex-row sm:items-center ${v.name === cur.name ? "border-primary bg-muted" : ""}`}>
            <span className="flex flex-wrap items-center gap-2">
              <span className="font-mono">{v.name}</span>
              <Badge variant={BADGE[v.class] ?? "outline"}>{v.class}</Badge>
              {v.gpu ? <Badge variant="secondary" data-testid="gpu-pill">GPU</Badge> : null}
              {reviewPending.includes(`${part.id}:${v.name}`) ? <Badge variant="secondary" data-testid="review-pending">look change, review pending</Badge> : null}
              {v.isDefault ? <span className="text-muted-foreground">default</span> : null}
            </span>
            <span className="min-w-0 break-words text-muted-foreground">
              {v.refusal ?? v.why}
              {v.gpu ? <span className="block" data-testid="gpu-mechanism">GPU{v.gpuEngines ? ` (${v.gpuEngines})` : ""}: {v.gpu}</span> : null}
            </span>
          </button>
        ))}
      </div>
      <p className="break-words text-xs" data-testid="why">{rules[cur.class] ?? cur.why}{cur.gpu ? ` GPU${cur.gpuEngines ? ` (${cur.gpuEngines})` : ""}: ${cur.gpu}` : ""}</p>
      {shown.length > 0 ? (
        <div>
          <Button size="sm" variant="ghost" aria-expanded={open} onClick={() => setOpen(!open)}>{open ? "Hide the explanation" : "Show the explanation"}</Button>
          {open ? (
            <div className="space-y-2">
              {cited.length === 0 ? <p className="text-xs text-muted-foreground">No finding names this variant; the part's other findings:</p> : null}
              {shown.map((r) => <Explain key={r.index} row={r} />)}
            </div>
          ) : null}
        </div>
      ) : <p className="text-xs text-muted-foreground">No finding in the ledger names this part yet.</p>}
    </div>
  );
}

export function ComposeView({ reviewPending = [] }: { reviewPending?: string[] } = {}) {
  const [ans, setAns] = useState<{ d: CData; q: string } | null>(null);
  const [picks, setPicks] = useState<Picks>({});
  const [msg, setMsg] = useState<string | null>(null);
  const [reasons, setReasons] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [opened, setOpened] = useState<{ url: string; q: string } | null>(null);
  const [copied, setCopied] = useState(false);
  const [copyMsg, setCopyMsg] = useState<string | null>(null);
  const guard = useRef(newestWins());
  const q = pickQuery(picks);
  const load = useCallback(async () => {
    const ticket = guard.current.next();
    try {
      const d = (await (await apiFetch(`/api/compose${q}`)).json()) as CData;
      if (guard.current.isLatest(ticket)) setAns({ d, q });
    } catch (e) { if (guard.current.isLatest(ticket)) setMsg((e as Error).message); }
  }, [q]);
  useEffect(() => { void load(); }, [load]);
  const fresh = !!ans && answersNow(ans.q, q);

  async function open(arm: "r" | "compare") {
    if (!ans || !fresh || !ans.d.decision.ok || ans.d.decision.link === null) return;
    const d = ans.d, asked = q;
    setMsg(null); setReasons([]); setBusy(true); setCopied(false); setCopyMsg(null);
    const w = window.open("about:blank", "_blank");
    if (w) w.opener = null;
    try {
      const r = await openSearch(d.decision.link!, arm, {
        fetch: apiFetch, previewBase: previewBase(d.previewPort), refused: refusedText,
        onOpen: (href) => { if (w) w.location.href = href; else setMsg(`Pop-up blocked: open ${href}`); },
      });
      if (!r.ok) { w?.close(); setMsg(r.message); setReasons(r.reasons); return; }
      setOpened({ url: r.url, q: asked });
    } catch (e) { w?.close(); setMsg((e as Error).message); } finally { setBusy(false); }
  }
  function copy() {
    if (!opened || opened.q !== q) return;
    void copyKnown(opened.url, copyText).then((r) => { setCopied(r.copied); setCopyMsg(r.message); });
  }

  if (!ans) return <p className="text-muted-foreground">{msg ?? "Loading parts..."}</p>;
  return <ComposePanel d={ans.d} stale={!fresh} picks={picks} setPicks={setPicks} busy={busy} msg={msg} reasons={reasons}
    opened={opened && opened.q === q ? opened.url : null} copied={copied} copyMsg={copyMsg} reviewPending={reviewPending} onOpen={(arm) => void open(arm)} onCopy={copy} />;
}

export type PanelProps = {
  d: CData; stale?: boolean; picks: Picks; setPicks: (f: Picks | ((cur: Picks) => Picks)) => void; busy: boolean; msg: string | null; reasons: string[];
  opened: string | null; copied: boolean; copyMsg?: string | null; onOpen: (arm: "r" | "compare") => void; onCopy?: () => void; reviewPending?: string[];
};

export function ComposePanel({ d, stale = false, picks, setPicks, busy, msg, reasons, opened, copied, copyMsg = null, onOpen, onCopy, reviewPending = [] }: PanelProps) {
  const dflt = (p: CPart) => p.variants.find((v) => v.isDefault)?.name ?? "faithful";
  const set = (p: CPart, v: string) => setPicks((cur) => { const n = { ...cur }; if (v === dflt(p)) delete n[p.id]; else n[p.id] = v; return n; });
  const preset = (c: CPreset) => setPicks(Object.fromEntries(c.picks.filter((x) => { const p = d.parts.find((y) => y.id === x.part); return p && dflt(p) !== x.variant; }).map((x) => [x.part, x.variant])));
  const link = d.decision.link;
  const can = !!d.canPreview && d.decision.ok && !busy && !stale;
  const canCopy = !!opened && !stale && !!d.canPreview;
  return (
    <div className="min-w-0 space-y-4 pb-48" data-testid="compose">
      <section className="space-y-2">
        <h2 className="font-semibold">Pick a variant of each part, get a preview link</h2>
        <p className="text-xs text-muted-foreground">Every part starts at its original. A badge says what the ledger knows of a variant; refuted variants are refused, not hidden.</p>
        <div className="flex flex-wrap gap-2" data-testid="presets">
          <Button size="sm" variant="outline" onClick={() => setPicks({})}>Default (faithful)</Button>
          {d.presets.filter((c) => c.name !== "original").map((c) => (
            <Button key={c.name} size="sm" variant="outline" disabled={!c.ok} title={c.ok ? (c.link ?? "") : c.reasons.join("; ")} onClick={() => preset(c)}>{c.name}</Button>
          ))}
        </div>
      </section>
      {byRegion(d.parts).map((g) => (
        <section key={g.region} className="space-y-2" data-testid={`region-${g.region}`}>
          <h3 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">{g.region || "other"}</h3>
          <div className="grid gap-3 sm:grid-cols-2">
            {g.parts.map((p) => <PartCard key={p.id} part={p} chosen={picks[p.id] ?? dflt(p)} rows={d.rows} rules={d.rules} reviewPending={reviewPending} onPick={(v) => set(p, v)} />)}
          </div>
        </section>
      ))}
      <section className="fixed inset-x-0 bottom-0 z-10 border-t bg-background p-3" data-testid="compose-bar">
        <div className="mx-auto max-h-[40vh] max-w-5xl space-y-2 overflow-y-auto">
          <p className="break-all font-mono text-xs" data-testid="generated-search">{stale ? "updating…" : link === null ? "(refused)" : link === "" ? "(default page: no ?fw= entries)" : link}</p>
          {!stale && d.decision.reasons.length > 0 ? <ul className="list-disc pl-5 text-xs text-destructive" role="alert">{d.decision.reasons.map((r) => <li key={r} className="break-words">{r}</li>)}</ul> : null}
          {!stale && d.decision.notes.map((n) => <p key={n} className="break-words text-xs text-muted-foreground">{n}</p>)}
          {reasons.length > 0 ? <ul className="list-disc pl-5 text-xs text-destructive" role="alert">{reasons.map((r) => <li key={r}>{r}</li>)}</ul> : null}
          {msg ? <p className="break-words text-xs text-destructive">{msg}</p> : null}
          <div className="flex flex-wrap gap-2">
            <Button size="sm" disabled={!can} onClick={() => onOpen("r")}>{busy ? "Opening..." : "Open"}</Button>
            <Button size="sm" variant="outline" disabled={!can} onClick={() => onOpen("compare")}>Open compare</Button>
            <Button size="sm" variant="outline" disabled={!canCopy} title={opened ? "" : "Open the combination first"} onClick={() => onCopy?.()}>{copied && opened ? "Copied" : "Copy link"}</Button>
          </div>
          {!d.canPreview ? <p className="text-xs text-muted-foreground">Sign in as owner to open previews.</p> : null}
          {copyMsg && opened ? <p className="break-words text-xs text-destructive" role="alert">{copyMsg}</p> : null}
          {opened ? <p className="break-all text-xs">Opened: <a className="select-all underline" href={opened} target="_blank" rel="noreferrer">{opened}</a></p> : null}
        </div>
      </section>
    </div>
  );
}
