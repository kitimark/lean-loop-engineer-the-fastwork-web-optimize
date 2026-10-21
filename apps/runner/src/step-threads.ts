// `fw step topic|reply|questions ...` (step-threads): the lead defines a topic, answers a user's question on a step or topic, and
// lists the open questions. Only argument mapping and printing: Lean (`Fw.Console.Steps`, through the reducer) decides who may
// define a topic, which `to` is open and how long a text may be. The commands go through the capability door; the lists are read-only.
import { Actor, Command } from "@fw/contracts";
import { UsageError, parseFlags, stepCommand } from "./lib.ts";

export const STEP_THREADS_USAGE = "usage: fw step topic --id <topic> --title <text> --summary <text>   (the lead's current summary of a topic)\n" +
  "       fw step post <step> --title <text> --topic <topic> ...   (group a step under a topic)\n" +
  "       fw step reply --id <step|topic> --to <comment id> --text <text> [--kind step|topic]   (answer a question; closes its alert)\n" +
  "       fw step questions [--all]   (print the open questions on steps and topics; --all adds the answered ones)";

const need = (v: string | undefined, what: string): string => {
  if (!v) throw new UsageError(`missing ${what}`);
  return v;
};

/** `fw step topic --id t --title T --summary S` -> the `step.topic` command (key from the id and summary, so a retry is a duplicate). */
export function topicCommand(argv: string[], env: Record<string, string | undefined>): Command {
  const { flags } = parseFlags(argv);
  const topic = need(flags.id, "--id <topic>");
  const summary = need(flags.summary, "--summary <text>");
  return Command.parse({ type: "step.topic", key: flags.key ?? `step-topic:${topic}:${Date.now().toString(36)}`,
    actor: Actor.parse(flags.as ?? env.FW_ACTOR ?? "lead"), topic, title: need(flags.title, "--title <text>"), summary });
}

/** `fw step <verb> ... [--topic t]`: the step command of `stepCommand`; a `post` also carries the topic when `--topic` is given. */
export function stepWithTopic(argv: string[], env: Record<string, string | undefined>): Command {
  const { flags } = parseFlags(argv.slice(1));
  const rest = argv[0] === "post" && flags.topic !== undefined ? argv.filter((a, i, all) => a !== "--topic" && all[i - 1] !== "--topic") : argv;
  const cmd = stepCommand(rest, env);
  return cmd.type === "step.post" && flags.topic !== undefined ? Command.parse({ ...cmd, topic: flags.topic }) : cmd;
}

export interface Thread { flag: string; open: number; comments: { id: string; text: string; at: number; status: string; reply: { text: string; at: number } | null }[] }

/** The thread (its flag `step:<id>` or `topic:<id>`) that holds comment `to` on subject `id`; `kind` narrows it when both exist. */
export function subjectOf(threads: Thread[], id: string, to: string, kind?: string): string {
  const flags = (kind ? [kind] : ["step", "topic"]).map((k) => `${k}:${id}`);
  const hit = threads.filter((t) => flags.includes(t.flag) && t.comments.some((c) => c.id === to));
  if (hit.length === 1) return hit[0]!.flag;
  if (hit.length > 1) throw new UsageError(`${id} is both a step and a topic; add --kind step or --kind topic`);
  throw new UsageError(`no question ${to} on ${kind ? `${kind} ` : "a step or topic "}${id}`);
}

/** `fw step reply --id x --to c --text t`: the `review.feedback.reply` command on the subject that holds comment `c`. */
export async function replyCommand(argv: string[], env: Record<string, string | undefined>, base: string): Promise<Command> {
  const { flags } = parseFlags(argv);
  const id = need(flags.id, "--id <step|topic>");
  const to = need(flags.to, "--to <comment id>");
  const text = need(flags.text, "--text <text>");
  if (flags.kind !== undefined && flags.kind !== "step" && flags.kind !== "topic") throw new UsageError("--kind is step or topic");
  const flag = subjectOf((await fetchThreads(base)).threads, id, to, flags.kind);
  return Command.parse({ type: "review.feedback.reply", key: flags.key ?? `review-feedback-reply:${to}`,
    actor: Actor.parse(flags.as ?? env.FW_ACTOR ?? "lead"), flag, to, text });
}

async function fetchThreads(base: string): Promise<{ threads: Thread[] }> {
  const r = await fetch(`${base}/api/steps/topics`);
  const body = (await r.json()) as { ok: boolean; reason?: string; threads?: Thread[] };
  if (!body.ok) throw new Error(`refused: ${body.reason ?? r.status}`);
  return { threads: body.threads ?? [] };
}

/** The text `fw step questions` prints: one block per question; the answered ones only with `all`. */
export function renderQuestions(threads: Thread[], all: boolean): string {
  const out: string[] = [];
  for (const t of threads) {
    for (const c of t.comments) {
      if (!all && c.status !== "open") continue;
      out.push(`${t.flag}  ${c.id}  ${c.status}  ${new Date(c.at).toISOString()}\n  ${c.text.replace(/\n/g, "\n  ")}`);
      if (c.reply) out.push(`  reply (${new Date(c.reply.at).toISOString()}): ${c.reply.text.replace(/\n/g, "\n  ")}`);
    }
  }
  return out.length ? out.join("\n") : "no open questions";
}

/** `fw step questions [--all]`: GET the threads from console-api and print them. */
export async function questionsCli(argv: string[], base: string): Promise<string> {
  return renderQuestions((await fetchThreads(base)).threads, argv.includes("--all"));
}
