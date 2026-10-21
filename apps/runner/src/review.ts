// `fw review reply|feedback ...` (review-feedback): the lead answers a user's comment on a review card, and reads the threads.
// Only argument mapping and printing: Lean (`Fw.Console.ReviewFeedback`, through the reducer) decides who may write, which `to`
// is open and how long a text may be. The reply is a typed command through the capability door; the threads are read-only.
import { Actor, Command } from "@fw/contracts";
import { UsageError, parseFlags } from "./lib.ts";

export const REVIEW_USAGE = "usage: fw review reply --flag <part:variant> --to <feedback id> --text <text>   (the lead answers a comment)\n" +
  "       fw review feedback [--flag <part:variant>] [--all]   (print the open comments; --all adds the answered ones)";

const need = (v: string | undefined, what: string): string => {
  if (!v) throw new UsageError(`missing ${what}`);
  return v;
};

/** `fw review reply --flag f --to id --text t` -> the `review.feedback.reply` command (key derived from the comment id, so a retry
 *  is a duplicate; the actor is the lead unless `--as`/FW_ACTOR says otherwise, and the capability door stamps the real one). */
export function reviewCommand(argv: string[], env: Record<string, string | undefined>): Command {
  const [verb, ...rest] = argv;
  if (verb !== "reply") throw new UsageError(REVIEW_USAGE);
  const { flags } = parseFlags(rest);
  const to = need(flags.to, "--to <feedback id>");
  return Command.parse({ type: "review.feedback.reply", key: flags.key ?? `review-feedback-reply:${to}`,
    actor: Actor.parse(flags.as ?? env.FW_ACTOR ?? "lead"), flag: need(flags.flag, "--flag <part:variant>"), to,
    text: need(flags.text, "--text <text>") });
}

interface Thread { flag: string; comments: { id: string; text: string; at: number; status: string; reply: { text: string; at: number } | null }[] }

/** The text `fw review feedback` prints: one block per comment; the answered ones only with `all`. */
export function renderFeedback(threads: Thread[], all: boolean): string {
  const out: string[] = [];
  for (const t of threads) {
    for (const c of t.comments) {
      if (!all && c.status !== "open") continue;
      out.push(`${t.flag}  ${c.id}  ${c.status}  ${new Date(c.at).toISOString()}\n  ${c.text.replace(/\n/g, "\n  ")}`);
      if (c.reply) out.push(`  reply (${new Date(c.reply.at).toISOString()}): ${c.reply.text.replace(/\n/g, "\n  ")}`);
    }
  }
  return out.length ? out.join("\n") : "no open feedback";
}

/** `fw review feedback`: GET the threads from console-api and print them. */
export async function feedbackCli(argv: string[], base: string): Promise<string> {
  const { flags } = parseFlags(argv.filter((a) => a !== "--all"));
  const url = flags.flag ? `${base}/api/reviews/${encodeURIComponent(flags.flag)}/feedback` : `${base}/api/reviews/feedback`;
  const r = await fetch(url);
  const body = (await r.json()) as { ok: boolean; reason?: string; threads?: Thread[]; thread?: Thread };
  if (!body.ok) throw new Error(`refused: ${body.reason ?? r.status}`);
  return renderFeedback(body.threads ?? (body.thread ? [body.thread] : []), argv.includes("--all"));
}
