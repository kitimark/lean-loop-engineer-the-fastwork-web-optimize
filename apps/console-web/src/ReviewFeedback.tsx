import { useRef, useState } from "react";
import { apiFetch } from "@/lib/auth";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

// Rendering and the send only (review-feedback). Which comments a flag has, whether each is open or answered, who may write and how long
// a text may be are Lean (`Fw.Console.ReviewFeedback`; console-api `GET /api/reviews`, `POST /api/reviews/<flag>/feedback`). Every text
// is shown as plain text (React escapes it), never as HTML.
export type FeedbackComment = { id: string; text: string; at: number; status: "open" | "answered"; reply: { text: string; at: number } | null };
export type FeedbackThread = { flag: string; open: number; comments: FeedbackComment[] };

/** A client id for a retry-safe send. `crypto.randomUUID` is missing on the plain-http LAN page, so it is built from the clock and `Math.random`. */
export const makeCid = (): string => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10).padEnd(8, "0")}`;

const when = (ms: number): string => new Date(ms).toISOString().replace("T", " ").slice(0, 16);

/** The thread: each comment with its time, a status chip and the lead's reply. */
export function FeedbackThreadView({ thread }: { thread: FeedbackThread | null | undefined }) {
  const cs = thread?.comments ?? [];
  if (cs.length === 0) return <p className="text-xs text-muted-foreground" data-testid="feedback-empty">No comments yet.</p>;
  return (
    <ul className="min-w-0 space-y-2" data-testid="feedback-thread">
      {cs.map((c) => (
        <li key={c.id} className="min-w-0 space-y-1 rounded border p-2 text-sm" data-testid="feedback-comment">
          <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
            <time dateTime={new Date(c.at).toISOString()}>{when(c.at)}</time>
            <Badge variant={c.status === "open" ? "secondary" : "outline"} data-testid="feedback-status">{c.status}</Badge>
          </div>
          <p className="whitespace-pre-wrap break-words" data-testid="feedback-text">{c.text}</p>
          {c.reply ? (
            <div className="min-w-0 border-l-2 pl-2" data-testid="feedback-reply">
              <p className="text-xs text-muted-foreground">Lead replied {when(c.reply.at)}</p>
              <p className="whitespace-pre-wrap break-words">{c.reply.text}</p>
            </div>
          ) : null}
        </li>
      ))}
    </ul>
  );
}

/** The Feedback section of a review card: a box to write a comment for more research, and the thread below. */
export function ReviewFeedback({ flag, thread, onChanged }: { flag: string; thread?: FeedbackThread | null; onChanged?: () => void }) {
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const cid = useRef<string | null>(null);
  async function send() {
    if (!text.trim()) { setErr("Write a comment first."); return; }
    cid.current ??= makeCid();
    setBusy(true); setErr(null);
    try {
      const r = await apiFetch(`/api/reviews/${encodeURIComponent(flag)}/feedback`, {
        method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ text, cid: cid.current }),
      });
      const j = (await r.json().catch(() => null)) as { ok?: boolean; reason?: string } | null;
      if (!j?.ok) { setErr(`Refused: ${j?.reason ?? r.status}`); return; }
      cid.current = null; setText(""); onChanged?.();
    } catch (e) { setErr(`Not sent: ${(e as Error).message}`); } finally { setBusy(false); }
  }
  return (
    <section className="min-w-0 space-y-2" data-testid="review-feedback" aria-label={`Feedback on ${flag}`}>
      <h4 className="text-sm font-medium">Feedback{thread && thread.open > 0 ? ` (${thread.open} open)` : ""}</h4>
      <textarea className="min-h-20 w-full rounded border bg-background p-2 text-sm" aria-label="Your feedback for more research" placeholder="What should the next research look at?"
        value={text} maxLength={2000} disabled={busy} onChange={(e) => { setText(e.target.value); cid.current = null; }} data-testid="feedback-input" />
      <Button className="min-h-11 w-full sm:w-auto" disabled={busy} onClick={() => void send()} data-testid="feedback-send">{busy ? "Sending..." : "Send"}</Button>
      {err ? <p className="break-words text-xs text-destructive" role="alert" data-testid="feedback-error">{err}</p> : null}
      <FeedbackThreadView thread={thread} />
    </section>
  );
}
