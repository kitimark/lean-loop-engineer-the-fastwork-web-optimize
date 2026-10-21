import { useCallback, useEffect, useState, type ReactNode } from "react";
import { Badge } from "@/components/ui/badge";
import { apiFetch } from "@/lib/auth";
import { ReviewFeedback, type FeedbackThread } from "./ReviewFeedback";

// Rendering and the send only (step-threads). Which steps group under which topic, the order of the groups, each thread and who may
// write are Lean (`Fw.Console.Steps`; console-api `GET /api/steps/topics`, `POST /api/steps/<step|topic>/<id>/question`).
export type StepGroup = {
  topic: string | null; title: string; summary: string; updatedAt: number | null;
  steps: string[]; openQuestions: number; activity: number; thread: FeedbackThread | null;
};
export type StepTopics = { groups: StepGroup[]; threads: FeedbackThread[] };

/** The groups and threads of console-api; reloaded when the log moves (`seq`). Null until the first answer. */
export function useStepTopics(seq: number | undefined): { data: StepTopics | null; reload: () => Promise<void> } {
  const [data, setData] = useState<StepTopics | null>(null);
  const reload = useCallback(async () => {
    try {
      const r = await apiFetch("/api/steps/topics");
      if (r.ok) setData((await r.json()) as StepTopics);
    } catch { /* the card keeps its last groups */ }
  }, []);
  useEffect(() => { void reload(); }, [reload, seq]);
  return { data, reload };
}

const when = (ms: number): string => new Date(ms).toISOString().replace("T", " ").slice(0, 16);

/** The words and route of the Questions section of one subject. */
export const questionWords = (kind: "step" | "topic", id: string) => ({
  url: `/api/steps/${kind}/${encodeURIComponent(id)}/question`, heading: "Questions", aria: "Your question for the lead",
  placeholder: kind === "topic" ? "What do you want explained about this topic?" : "What do you want explained about this step?",
  testid: "step-questions",
});

/** A collapsed Questions section: the thread of the subject and a box to ask more. Open when a question waits for an answer. */
export function QuestionBox({ kind, id, thread, onChanged }: { kind: "step" | "topic"; id: string; thread?: FeedbackThread | null; onChanged?: () => void }) {
  const n = thread?.comments.length ?? 0;
  const open = thread?.open ?? 0;
  return (
    <details className="min-w-0 basis-full" data-testid={`${kind}-questions-${id}`} open={open > 0}>
      <summary className="cursor-pointer text-xs text-muted-foreground">
        {n === 0 ? "Ask a question" : `Questions (${n}${open > 0 ? `, ${open} waiting for the lead` : ""})`}
      </summary>
      <div className="mt-2"><ReviewFeedback flag={`${kind}:${id}`} thread={thread} onChanged={onChanged} words={questionWords(kind, id)} /></div>
    </details>
  );
}

/** One group of the Your steps card: the topic title, the lead's summary and its time, then the steps, then the topic's questions.
 *  `renderStep` draws a step by id; the group order and membership are Lean's. */
export function TopicGroup({ group, renderStep, onChanged }: { group: StepGroup; renderStep: (id: string) => ReactNode; onChanged?: () => void }) {
  return (
    <section className="min-w-0 space-y-2 rounded border p-2" data-testid="topic-group" aria-label={group.title}>
      <header className="flex flex-wrap items-center gap-2">
        <h3 className="text-sm font-semibold">{group.title}</h3>
        <Badge variant="outline">{group.steps.length} open</Badge>
        {group.openQuestions > 0 ? <Badge variant="secondary" data-testid="topic-open-questions">{group.openQuestions} question{group.openQuestions === 1 ? "" : "s"} waiting</Badge> : null}
        {group.updatedAt !== null ? <time className="text-xs text-muted-foreground" dateTime={new Date(group.updatedAt).toISOString()}>updated {when(group.updatedAt)}</time> : null}
      </header>
      {group.summary ? <p className="whitespace-pre-wrap break-words text-sm" data-testid="topic-summary">{group.summary}</p> : null}
      <div className="space-y-2">{group.steps.map((id) => renderStep(id))}</div>
      {group.topic !== null ? <QuestionBox kind="topic" id={group.topic} thread={group.thread} onChanged={onChanged} /> : null}
    </section>
  );
}
