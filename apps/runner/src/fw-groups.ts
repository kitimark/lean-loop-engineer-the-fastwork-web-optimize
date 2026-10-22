import { CARD_VERBS } from "./card.ts";
import { CI_SUBS } from "./ci.ts";
import { CONSOLE_SUBS } from "./console.ts";
import { INCIDENTS_SUBS } from "./incidents.ts";
import { STEP_VERBS, TASK_VERBS } from "./lib.ts";
import { ORACLE_SUBS } from "./oracle.ts";
import { PLAN_SUBS } from "./plan.ts";
import { POLISH_VERBS } from "./polish.ts";
import { PREVIEW_SUBS } from "./preview.ts";
import { READY_VERBS } from "./review-ready.ts";
import { REVIEW_VERBS } from "./review.ts";
import { SLOT_SUBS, slotStep } from "./slot-span.ts";
import { STEP_THREAD_VERBS } from "./step-threads.ts";

export const SUBCOMMANDS: Readonly<Record<string, readonly string[]>> = {
  plan: PLAN_SUBS,
  ci: CI_SUBS,
  incidents: INCIDENTS_SUBS,
  step: [...STEP_VERBS, ...STEP_THREAD_VERBS],
  card: CARD_VERBS,
  task: TASK_VERBS,
  console: CONSOLE_SUBS,
  review: [...REVIEW_VERBS, ...READY_VERBS],
  oracle: ORACLE_SUBS,
  polish: POLISH_VERBS,
  preview: PREVIEW_SUBS,
  slot: SLOT_SUBS,
};

export function spanStep(group: string, rest: string[]): string {
  const sub = rest[0];
  if (group === "slot") return slotStep(rest);
  if (group === "polish" && sub === "--staged") return "polish staged";
  if (!sub || !SUBCOMMANDS[group]?.includes(sub)) return group === "land" && rest.includes("--dry") ? "land dry" : group;
  return `${group} ${sub}`;
}
