import { DEFAULT_ACTOR } from "./card.ts";
import { slotStep } from "./slot-span.ts";

/** Every `fw` group that takes a subcommand, with its subcommands: the one table that names spans (`fw <group> <sub>`). A test
 *  reads fw-main.ts and fails when a branch there reads `rest[0]` for a group missing here, or a subcommand it names is missing. */
export const SUBCOMMANDS: Readonly<Record<string, readonly string[]>> = {
  plan: ["sync", "show", "lint", "overlap"],
  ci: ["wait", "budget", "circleci", "push", "telemetry", "pool", "state"],
  incidents: ["lint"],
  step: ["post", "start", "answer", "done", "cancel", "topic", "reply", "questions"],
  card: Object.keys(DEFAULT_ACTOR),
  task: ["handback", "integrate", "park", "unpark"],
  console: ["start", "stop", "restart", "status", "logs"],
  review: ["reply", "feedback", "report", "ready", "verdict"],
  oracle: ["ask", "calibrate", "eval", "send"],
  polish: ["plan", "cuts", "commit", "staged"],
  preview: ["grant"],
  slot: ["run", "acquire", "renew", "release", "status", "sim", "held", "admit"],
};

/** The step name of the `fw` span of one invocation: `group sub` for a group with subcommands (`slot` via `slotStep`, with its
 *  kind), `group` otherwise; `land --dry` is `land dry`, `polish --staged` is `polish staged`. */
export function spanStep(group: string, rest: string[]): string {
  const sub = rest[0];
  if (group === "slot") return slotStep(rest);
  if (group === "polish" && sub === "--staged") return "polish staged";
  if (!SUBCOMMANDS[group] || !sub || sub.startsWith("-")) return group === "land" && rest.includes("--dry") ? "land dry" : group;
  return `${group} ${sub}`;
}
