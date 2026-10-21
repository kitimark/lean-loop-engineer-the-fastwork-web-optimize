import { useCallback, useEffect, useState } from "react";
import { apiFetch } from "@/lib/auth";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { FeedbackThreadView, ReviewFeedback, makeCid, type FeedbackThread } from "./ReviewFeedback";

// Rendering and the send only (review-reports). Whether a report is shown (every number tagged MEASURED with a CI run id or INFERRED with
// its reason), what state its step is in and whether an answer is accepted are Lean `console.report` (Fw.Console.Report; console-api
// `GET /api/reports`, `POST /api/reports/<id>/answer`). The numbers are the experiment's text, shown as given (React escapes every string).
export type Tag = { kind: "measured"; run: string } | { kind: "inferred"; why: string };
export type RCell = { arm: string; value: number | string; tag?: Tag };
export type RRow = { metric: string; unit?: string; cells: RCell[] };
export type RLayer = { layer: string; verdict: string; tag?: Tag };
export type RLane = { name: string; rows: RRow[]; layers?: RLayer[] };
export type Report = {
  id: string; proposal: string; title: string; arms: { name: string; search?: string }[]; lanes: RLane[];
  strips?: string; recommendation: { word: string; why: string };
};
export type ReportItem = {
  id: string; step: string; title: string; state: "open" | "approve" | "hold" | "reject" | "closed"; post: boolean;
  report: Report; feedback?: FeedbackThread | null;
};
export type ReportsData = { ok: boolean; open: number; options: string[]; items: ReportItem[]; invalid: { index: number; id?: string; reason: string }[] };
export type Answer = "approve" | "hold" | "reject";

const ASK: Record<Answer, string> = { approve: "Approve this report?", hold: "Hold this report?", reject: "Reject this report?" };
const YES: Record<Answer, string> = { approve: "Yes, approve", hold: "Yes, hold", reject: "Yes, reject" };
const DONE: Record<string, string> = { approve: "You approved this report.", hold: "You put this report on hold.", reject: "You rejected this report.", closed: "This report's step was closed without an answer." };

/** Reports with an open step: the Reviews tab badge counts them with the look-change reviews. */
export function openReports(d: ReportsData | null): number { return d ? d.open : 0; }

/** The reports, reloaded when the board moves (`seq`). */
export function useReports(seq: number | undefined): { data: ReportsData | null; reload: () => Promise<void> } {
  const [data, setData] = useState<ReportsData | null>(null);
  const reload = useCallback(async () => {
    try {
      const r = await apiFetch("/api/reports");
      if (r.ok) setData((await r.json()) as ReportsData);
    } catch { /* the section keeps its last value */ }
  }, []);
  useEffect(() => { void reload(); }, [reload, seq]);
  return { data, reload };
}

/** A tag as the words the table prints: MEASURED with its run, or INFERRED with its reason. Lean has refused any other. */
export function tagWords(t: Tag | undefined): string {
  if (!t) return "no tag";
  return t.kind === "measured" ? `MEASURED run ${t.run}` : `INFERRED: ${t.why}`;
}

function TagChip({ tag }: { tag: Tag | undefined }) {
  return <span className={`mt-0.5 block break-words text-[11px] ${tag?.kind === "inferred" ? "text-amber-700" : "text-muted-foreground"}`} data-testid="tag">{tagWords(tag)}</span>;
}

/** The arms side by side: name and the search that opens it. */
function Arms({ arms }: { arms: Report["arms"] }) {
  return (
    <div className="grid min-w-0 grid-cols-2 gap-2" data-testid="report-arms">
      {arms.map((a) => (
        <div key={a.name} className="min-w-0 rounded border p-2" data-testid="report-arm">
          <p className="break-words text-sm font-medium">{a.name}</p>
          <p className="break-all font-mono text-[11px] text-muted-foreground">{a.search ? a.search : "(no search)"}</p>
        </div>
      ))}
    </div>
  );
}

/** One lane: a metric table with a column per arm, then the layer verdicts. */
function Lane({ lane, arms }: { lane: RLane; arms: Report["arms"] }) {
  return (
    <div className="min-w-0 space-y-2" data-testid="report-lane">
      <h4 className="break-words text-sm font-medium">{lane.name}</h4>
      <div className="max-w-full overflow-x-auto" tabIndex={0} role="group" aria-label={`metrics of ${lane.name}`}>
        <table className="w-full table-fixed border-collapse text-xs" data-testid="report-table">
          <thead>
            <tr className="border-b text-left">
              <th scope="col" className="w-[34%] p-1 font-medium">Metric</th>
              {arms.map((a) => <th key={a.name} scope="col" className="break-words p-1 font-medium">{a.name}</th>)}
            </tr>
          </thead>
          <tbody>
            {lane.rows.map((r) => (
              <tr key={r.metric} className="border-b align-top" data-testid="report-row">
                <th scope="row" className="break-words p-1 text-left font-normal">{r.metric}{r.unit ? <span className="text-muted-foreground"> ({r.unit})</span> : null}</th>
                {arms.map((a) => {
                  const c = r.cells.find((x) => x.arm === a.name);
                  return (
                    <td key={a.name} className="min-w-0 p-1" data-testid="report-cell">
                      {c ? <><span className="break-words font-mono text-sm">{String(c.value)}</span><TagChip tag={c.tag} /></> : <span className="text-muted-foreground">-</span>}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {(lane.layers ?? []).length > 0 ? (
        <ul className="space-y-1 text-xs" data-testid="report-layers">
          {(lane.layers ?? []).map((l) => (
            <li key={l.layer} className="break-words"><span className="font-medium">Layer {l.layer}:</span> pixel verdict <span className="font-mono">{l.verdict}</span> <span className="text-muted-foreground">({tagWords(l.tag)})</span></li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}

/** One report: arms, tables, the strips link, the recommendation, its thread and the answer with its confirm step. */
export function ReportCard({ item, confirming, comment, busy, error, onComment, onAsk, onConfirm, onCancel, onChanged }: {
  item: ReportItem; confirming: Answer | null; comment: string; busy: boolean; error: string | null;
  onComment: (t: string) => void; onAsk: (a: Answer) => void; onConfirm: () => void; onCancel: () => void; onChanged?: () => void;
}) {
  const r = item.report;
  const open = item.state === "open";
  return (
    <div className="min-w-0 space-y-3 rounded border p-3" data-testid="report-card" aria-label={`Report ${item.id}`}>
      <div className="flex flex-wrap items-center gap-2">
        <h3 className="break-words text-sm font-semibold">{r.title}</h3>
        <Badge variant={open ? "secondary" : "outline"} data-testid="report-state">{open ? "report, waiting for you" : item.state}</Badge>
      </div>
      <p className="break-words text-xs text-muted-foreground">Proposal <span className="font-mono">{r.proposal}</span>, report <span className="font-mono">{item.id}</span></p>
      <Arms arms={r.arms} />
      {r.lanes.map((l) => <Lane key={l.name} lane={l} arms={r.arms} />)}
      {r.strips && /^https:\/\/\S+$/.test(r.strips)
        ? <p className="break-words text-sm"><a className="underline" href={r.strips} target="_blank" rel="noreferrer" data-testid="report-strips">Open the frame strips (CI artifact)</a><span className="text-xs text-muted-foreground"> CI artifacts expire.</span></p>
        : <p className="text-xs text-muted-foreground" data-testid="report-no-strips">No frame strips are linked.</p>}
      <p className="break-words text-sm" data-testid="report-recommendation"><span className="font-medium">Recommendation: {r.recommendation.word}.</span> {r.recommendation.why}</p>
      {open ? <FeedbackThreadView thread={item.feedback} /> : null}
      {open ? (
        confirming ? (
          <div className="space-y-2" role="group" aria-label="confirm" data-testid="report-confirm">
            <p className="text-sm">{ASK[confirming]}</p>
            {comment.trim() ? <p className="break-words text-xs text-muted-foreground">Your comment goes to the lead: {comment}</p> : null}
            <div className="flex flex-wrap gap-2">
              <Button className="min-h-11 flex-1 sm:flex-none" disabled={busy} onClick={onConfirm}>{busy ? "Saving..." : YES[confirming]}</Button>
              <Button className="min-h-11 flex-1 sm:flex-none" variant="outline" disabled={busy} onClick={onCancel}>Cancel</Button>
            </div>
          </div>
        ) : (
          <div className="space-y-2">
            <textarea className="min-h-16 w-full rounded border bg-background p-2 text-sm" aria-label="Comment for the lead (optional)" placeholder="Comment for the lead (optional)"
              value={comment} onChange={(e) => onComment(e.target.value)} data-testid="report-comment" />
            <div className="flex flex-wrap gap-2">
              <Button className="min-h-11 flex-1 sm:flex-none" onClick={() => onAsk("approve")}>Approve</Button>
              <Button className="min-h-11 flex-1 sm:flex-none" variant="outline" onClick={() => onAsk("hold")}>Hold</Button>
              <Button className="min-h-11 flex-1 sm:flex-none" variant="outline" onClick={() => onAsk("reject")}>Reject</Button>
            </div>
          </div>
        )
      ) : (
        <>
          <p className="text-sm font-medium" role="status" data-testid="report-decision">{DONE[item.state] ?? item.state}</p>
          <ReviewFeedback flag={`report:${item.id}`} thread={item.feedback} {...(onChanged ? { onChanged } : {})}
            words={{ heading: "Comments to the lead", testid: "report-feedback" }} />
        </>
      )}
      {error ? <p className="break-words text-xs text-destructive" role="alert">{error}</p> : null}
    </div>
  );
}

/** The panel: the open reports first, then the answered ones. Nothing is rendered when there is no report. */
export function ReportsPanel({ data, confirm, comment, busy, error, onComment, onAsk, onConfirm, onCancel, onChanged }: {
  data: ReportsData; confirm: { id: string; word: Answer } | null; comment: string; busy: boolean; error: { id: string; text: string } | null;
  onComment: (t: string) => void; onAsk: (id: string, a: Answer) => void; onConfirm: () => void; onCancel: () => void; onChanged?: () => void;
}) {
  const items = [...data.items.filter((i) => i.state === "open"), ...data.items.filter((i) => i.state !== "open")];
  return (
    <section className="min-w-0 space-y-3" data-testid="reports" aria-label="Reports">
      <h2 className="font-semibold">Reports</h2>
      {items.length === 0 ? <p className="text-sm text-muted-foreground" data-testid="no-reports">No experiment report waits for you.</p> : null}
      {items.map((i) => (
        <ReportCard key={i.id} item={i} confirming={confirm?.id === i.id ? confirm.word : null} comment={confirm?.id === i.id || i.state === "open" ? comment : ""}
          busy={busy && confirm?.id === i.id} error={error?.id === i.id ? error.text : null} onComment={onComment}
          onAsk={(a) => onAsk(i.id, a)} onConfirm={onConfirm} onCancel={onCancel} {...(onChanged ? { onChanged } : {})} />
      ))}
      {data.invalid.length > 0 ? (
        <ul className="space-y-1 text-xs text-destructive" data-testid="reports-invalid">
          {data.invalid.map((v, k) => <li key={`${v.id ?? v.index}-${k}`} className="break-words">Report {v.id ?? `#${v.index}`} is not shown: {v.reason}</li>)}
        </ul>
      ) : null}
    </section>
  );
}

/** The Reports section of the Reviews tab: loads the reports and sends an answer (the user's step.answer; a comment becomes review.feedback on report:<id>). */
export function ReportsSection({ seq }: { seq?: number | undefined }) {
  const { data, reload } = useReports(seq);
  const [confirm, setConfirm] = useState<{ id: string; word: Answer } | null>(null);
  const [comment, setComment] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<{ id: string; text: string } | null>(null);
  const [cid, setCid] = useState<string>(() => makeCid());
  async function send() {
    if (!confirm) return;
    setBusy(true); setError(null);
    try {
      const r = await apiFetch(`/api/reports/${encodeURIComponent(confirm.id)}/answer`, {
        method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ word: confirm.word, comment, cid }),
      });
      const j = (await r.json()) as { ok: boolean; reason?: string };
      if (!j.ok) setError({ id: confirm.id, text: `Refused: ${j.reason ?? r.status}` });
      else { setComment(""); setCid(makeCid()); }
      setConfirm(null);
      await reload();
    } catch (e) { setError({ id: confirm.id, text: (e as Error).message }); } finally { setBusy(false); }
  }
  if (!data || (data.items.length === 0 && data.invalid.length === 0)) return null;
  return <ReportsPanel data={data} confirm={confirm} comment={comment} busy={busy} error={error} onComment={setComment}
    onAsk={(id, word) => { setError(null); setConfirm({ id, word }); }} onConfirm={() => void send()} onCancel={() => setConfirm(null)} onChanged={() => void reload()} />;
}
