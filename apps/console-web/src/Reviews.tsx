import { useCallback, useEffect, useRef, useState } from "react";
import { apiFetch } from "@/lib/auth";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

// Rendering only. Which reviews are pending, open or decided is Lean `console.review` (console-api `GET /api/reviews`); Keep and Reject
// post the decision, which Lean accepts or refuses. The page link comes from the owner's private `.local/reviews.json`.
export type Strips = { state: "ready" | "pending"; run?: string; artifact?: string; expires?: string; task?: string };
/** A strip as Lean `console.review` returns it; its state (ready, expired, missing) is decided there. */
export type StripItem = {
  engine: string; state: "ready" | "expired" | "missing"; width?: number; push?: "open" | "close"; file?: string;
  run?: string; artifact?: string; expires?: string; note?: string; diff?: string; redo?: string;
};
export type ReviewItem = {
  strips?: StripItem[];
  flag: string; step: string; state: "open" | "keep" | "reject"; date: string; words: string; audience: string;
  changed: { id: string | null; candidate: string; visual: string | null; chromium: string | null; webkit: string | null } | null;
  material: { chromium: Strips; webkit: Strips } | null;
  link: string | null;
};
export type ReviewsData = { ok: boolean; open: number; options: string[]; items: ReviewItem[] };
export type Verdict = "keep" | "reject";

/** The flags whose review is open: Compose marks their variants. */
export function openFlags(d: ReviewsData | null): string[] {
  return d ? d.items.filter((i) => i.state === "open").map((i) => i.flag) : [];
}

/** The label of the Reviews tab in the nav: a badge with the count while items are open. */
export function ReviewsTabLabel({ data }: { data: ReviewsData | null }) {
  return <>Reviews{data && data.open > 0 ? <Badge className="ml-1" data-testid="reviews-badge" aria-label={`${data.open} open`}>{data.open}</Badge> : null}</>;
}

/** The reviews, reloaded when the board moves (`seq`): the data and a reload for after a decision. */
export function useReviews(seq: number | undefined): { data: ReviewsData | null; reload: () => Promise<void> } {
  const [data, setData] = useState<ReviewsData | null>(null);
  const reload = useCallback(async () => {
    try {
      const r = await apiFetch("/api/reviews");
      if (r.ok) setData((await r.json()) as ReviewsData);
    } catch { /* the badge keeps its last value */ }
  }, []);
  useEffect(() => { void reload(); }, [reload, seq]);
  return { data, reload };
}

function Material({ label, s }: { label: string; s: Strips }) {
  return (
    <li className="break-words" data-testid={`material-${label.toLowerCase()}`}>
      <span className="font-medium">{label} strips:</span>{" "}
      {s.state === "ready"
        ? <>ready (CI run <span className="font-mono">{s.run}</span>, artifact <span className="font-mono">{s.artifact}</span>{s.expires ? `, expires ${s.expires}` : ""})</>
        : <>pending{s.task ? ` (task ${s.task})` : ""}</>}
    </li>
  );
}

const PUSH: Record<string, string> = { open: "Button leaves", close: "Button comes back" };
const ENGINE: Record<string, string> = { chromium: "Chromium", webkit: "WebKit" };

/** The address of a strip image (the file name is one Lean listed; the route checks it again). */
export function stripUrl(flag: string, file: string): string { return `/api/reviews/${encodeURIComponent(flag)}/strips/${encodeURIComponent(file)}`; }

/** The image of a strip. It is fetched with the owner token (an <img> cannot send one) when it nears the screen. */
function StripImage({ flag, s }: { flag: string; s: StripItem }) {
  const box = useRef<HTMLDivElement>(null);
  const [src, setSrc] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [near, setNear] = useState(typeof IntersectionObserver === "undefined");
  useEffect(() => {
    const el = box.current;
    if (near || !el) return;
    const io = new IntersectionObserver((es) => { if (es.some((e) => e.isIntersecting)) setNear(true); }, { rootMargin: "300px" });
    io.observe(el);
    return () => io.disconnect();
  }, [near]);
  useEffect(() => {
    if (!near || !s.file) return;
    let url: string | null = null; let dead = false;
    apiFetch(stripUrl(flag, s.file)).then(async (r) => {
      if (!r.ok) { const j = (await r.json().catch(() => null)) as { reason?: string } | null; throw new Error(j?.reason ?? `status ${r.status}`); }
      url = URL.createObjectURL(await r.blob());
      if (dead) URL.revokeObjectURL(url); else setSrc(url);
    }).catch((e: Error) => { if (!dead) setErr(e.message); });
    return () => { dead = true; if (url) URL.revokeObjectURL(url); };
  }, [near, flag, s.file]);
  const zoom = s.width === 390 ? 1.6 : 2.2;
  return (
    <div ref={box} className="max-w-full overflow-x-auto rounded border bg-white" tabIndex={0} role="group" aria-label={`frame strip ${s.width} ${s.push}`} data-testid="strip-scroll">
      {src ? <img src={src} alt={`${PUSH[s.push ?? ""] ?? ""}, ${s.width} px: original row above the flag row`} className="block h-auto max-w-none" style={{ width: `${zoom * 100}%` }} />
        : <p className="p-3 text-xs text-muted-foreground">{err ? `The strip could not be loaded: ${err}` : "Loading the strip..."}</p>}
    </div>
  );
}

/** One strip: width tag, push, time difference, note, legend and the scrollable image; a plain line for a missing or expired one. */
export function StripCard({ flag, s }: { flag: string; s: StripItem }) {
  const engine = ENGINE[s.engine] ?? s.engine;
  if (s.state === "missing") {
    return <p className="text-xs" data-testid="strip-missing">{engine} strips{s.width ? ` (${s.width}, ${s.push})` : ""}: none made for this change yet. To make them, push a ci/* commit with the message line <code className="font-mono">{s.redo}</code>, then update the material in Gen.lean (Fw.Preset.Gen.lookDecisions) with the new run.</p>;
  }
  const tag = `${s.width === 390 ? "Phone" : "Desktop"} ${s.width}`;
  const head = (
    <header className="flex flex-wrap items-center gap-x-3 gap-y-1">
      <Badge variant="secondary">{engine} · {tag}</Badge>
      <h4 className="text-sm font-semibold">{PUSH[s.push ?? ""] ?? s.push}</h4>
      {s.diff ? <span className="ml-auto text-sm font-semibold" data-testid="strip-diff">{s.diff}</span> : null}
    </header>
  );
  if (s.state === "expired") {
    return (
      <section className="min-w-0 space-y-1 rounded border p-2" data-testid="strip-expired">
        {head}
        <p className="break-words text-xs">This strip expired on {s.expires} (the CI artifact is gone). To re-make it, push a ci/* commit with the message line <code className="font-mono">{s.redo}</code>, then update the material in Gen.lean (Fw.Preset.Gen.lookDecisions) with the new run.</p>
      </section>
    );
  }
  return (
    <section className="min-w-0 space-y-2 rounded border p-2" data-testid="strip">
      {head}
      <p className="break-words text-sm" data-testid="strip-note">{s.note ? s.note : <span className="text-muted-foreground">no note yet</span>}</p>
      <p className="text-xs text-muted-foreground">Top row original, bottom row flag; frame number and ms under each shot. Scroll the strip sideways. Each arm is sampled at its own screenshot times, so compare the ms labels, not the column positions.</p>
      <StripImage flag={flag} s={s} />
    </section>
  );
}

const DONE: Record<Verdict, string> = { keep: "You kept it.", reject: "You rejected it." };

/** One review: what changed, the review material, and Keep / Reject with an in-page confirm step. */
export function ReviewCard({ item, confirming, busy, error, onAsk, onConfirm, onCancel }: {
  item: ReviewItem; confirming: Verdict | null; busy: boolean; error: string | null;
  onAsk: (v: Verdict) => void; onConfirm: () => void; onCancel: () => void;
}) {
  const decided = item.state !== "open";
  return (
    <div className="min-w-0 space-y-2 rounded border p-3" data-testid={`review-${item.flag}`}>
      <div className="flex flex-wrap items-center gap-2">
        <h3 className="break-all font-mono text-sm font-semibold">{item.flag}</h3>
        <Badge variant={decided ? "outline" : "secondary"}>{decided ? "decided" : "look change, review pending"}</Badge>
      </div>
      <p className="break-words text-xs text-muted-foreground">Recorded {item.date}: {item.words}</p>
      {item.changed ? (
        <dl className="space-y-1 text-xs" data-testid="changed">
          <div><dt className="font-medium">What changed</dt><dd className="break-words">{item.changed.candidate}</dd></div>
          {item.changed.visual ? <div><dt className="font-medium">Look</dt><dd className="break-words">{item.changed.visual}</dd></div> : null}
          {item.changed.chromium ? <div><dt className="font-medium">Chromium</dt><dd className="break-words">{item.changed.chromium}</dd></div> : null}
          {item.changed.webkit ? <div><dt className="font-medium">WebKit</dt><dd className="break-words">{item.changed.webkit}</dd></div> : null}
        </dl>
      ) : <p className="text-xs text-muted-foreground">No ledger row names this flag.</p>}
      {item.material ? (
        <ul className="space-y-1 text-xs" data-testid="material">
          <Material label="Chromium" s={item.material.chromium} />
          <Material label="WebKit" s={item.material.webkit} />
        </ul>
      ) : null}
      {(item.strips ?? []).length > 0 ? (
        <div className="min-w-0 space-y-2" data-testid="strips">
          <h4 className="text-sm font-medium">Frame strips</h4>
          {(item.strips ?? []).map((s, k) => <StripCard key={`${s.engine}-${s.width ?? k}-${s.push ?? ""}`} flag={item.flag} s={s} />)}
        </div>
      ) : null}
      {item.link
        ? <p className="text-sm"><span className="text-xs text-muted-foreground">Fallback: </span><a className="underline" href={item.link} target="_blank" rel="noreferrer" data-testid="review-link">Open the review page</a></p>
        : <p className="text-xs text-muted-foreground" data-testid="no-link">No review link on this machine; fetch the artifact named above from its CI run.</p>}
      {decided ? (
        <p className="text-sm font-medium" role="status" data-testid="decision">{DONE[item.state as Verdict]}</p>
      ) : confirming ? (
        <div className="space-y-2" role="group" aria-label="confirm" data-testid="confirm">
          <p className="text-sm">{confirming === "keep" ? "Keep this look change?" : "Reject this look change?"}</p>
          <div className="flex flex-wrap gap-2">
            <Button className="min-h-11 flex-1 sm:flex-none" disabled={busy} onClick={onConfirm}>{busy ? "Saving..." : confirming === "keep" ? "Yes, keep" : "Yes, reject"}</Button>
            <Button className="min-h-11 flex-1 sm:flex-none" variant="outline" disabled={busy} onClick={onCancel}>Cancel</Button>
          </div>
        </div>
      ) : (
        <div className="flex flex-wrap gap-2">
          <Button className="min-h-11 flex-1 sm:flex-none" onClick={() => onAsk("keep")}>Keep</Button>
          <Button className="min-h-11 flex-1 sm:flex-none" variant="outline" onClick={() => onAsk("reject")}>Reject</Button>
        </div>
      )}
      {error ? <p className="break-words text-xs text-destructive" role="alert">{error}</p> : null}
    </div>
  );
}

/** The panel: the open items first, then the decided ones. */
export function ReviewsPanel({ data, confirm, busy, error, onAsk, onConfirm, onCancel }: {
  data: ReviewsData; confirm: { flag: string; word: Verdict } | null; busy: boolean; error: { flag: string; text: string } | null;
  onAsk: (flag: string, v: Verdict) => void; onConfirm: () => void; onCancel: () => void;
}) {
  const items = [...data.items.filter((i) => i.state === "open"), ...data.items.filter((i) => i.state !== "open")];
  return (
    <section className="min-w-0 space-y-3" data-testid="reviews" aria-label="Your reviews">
      <h2 className="font-semibold">Your reviews</h2>
      {items.length === 0 ? <p className="text-sm text-muted-foreground" data-testid="no-reviews">Nothing waits for your review.</p> : null}
      {items.map((i) => (
        <ReviewCard key={i.flag} item={i} confirming={confirm?.flag === i.flag ? confirm.word : null} busy={busy && confirm?.flag === i.flag}
          error={error?.flag === i.flag ? error.text : null} onAsk={(v) => onAsk(i.flag, v)} onConfirm={onConfirm} onCancel={onCancel} />
      ))}
    </section>
  );
}

export function ReviewsView({ data, reload }: { data: ReviewsData | null; reload: () => Promise<void> }) {
  const [confirm, setConfirm] = useState<{ flag: string; word: Verdict } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<{ flag: string; text: string } | null>(null);
  async function send() {
    if (!confirm) return;
    setBusy(true); setError(null);
    try {
      const r = await apiFetch(`/api/reviews/${encodeURIComponent(confirm.flag)}`, {
        method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ decision: confirm.word }),
      });
      const j = (await r.json()) as { ok: boolean; reason?: string };
      if (!j.ok) setError({ flag: confirm.flag, text: `Refused: ${j.reason ?? r.status}` });
      setConfirm(null);
      await reload();
    } catch (e) { setError({ flag: confirm.flag, text: (e as Error).message }); } finally { setBusy(false); }
  }
  if (!data) return <p className="text-muted-foreground">Loading reviews...</p>;
  return <ReviewsPanel data={data} confirm={confirm} busy={busy} error={error} onAsk={(flag, word) => { setError(null); setConfirm({ flag, word }); }}
    onConfirm={() => void send()} onCancel={() => setConfirm(null)} />;
}
