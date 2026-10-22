// `fw card open|approve|screen|review|swipe|request ...` -> typed Command. Whether it is allowed (actor, state) is
// the reducer's call; the CLI only builds the request, with a derived key so retries are idempotent.
import { Actor, Command } from "@fw/contracts";
import { UsageError, parseFlags } from "./lib.ts";

export const DEFAULT_ACTOR: Record<string, Actor> = { open: "owner", approve: "lead", screen: "script", review: "reviewer", swipe: "script", request: "lead" };
const need = (v: string | undefined, what: string): string => {
  if (!v) throw new UsageError(`missing ${what}`);
  return v;
};
const bool = (v: string | undefined, what: string): boolean => {
  if (v === "true" || v === "yes") return true;
  if (v === "false" || v === "no") return false;
  throw new UsageError(`${what} must be true|false`);
};

export const CARD_USAGE = "usage: fw card open <card> --owner <o> [--device true] | approve <card> | screen <card> <sha> --pass true|false | review <card> <sha> --by <who> --accept true|false | swipe <card> <sha> --better true|false | request <card> <sha>";

/** The verbs `cardCommand` accepts: the keys of DEFAULT_ACTOR. */
export const CARD_VERBS = Object.keys(DEFAULT_ACTOR);

export function cardCommand(argv: string[], env: Record<string, string | undefined>): Command {
  const [verb, ...rest] = argv;
  if (!verb || !CARD_VERBS.includes(verb)) throw new UsageError(CARD_USAGE);
  const { pos, flags } = parseFlags(rest);
  const actor = Actor.parse(flags.as ?? env.FW_ACTOR ?? DEFAULT_ACTOR[verb]);
  const card = need(pos[0], "<card>");
  const sha = () => need(pos[1], "<sha>");
  const key = (type: string, ...parts: string[]) => flags.key ?? [`card.${type}`, card, ...parts].join(":");
  switch (verb) {
    case "open": return Command.parse({ type: "card.open", key: key("open"), actor, card, owner: need(flags.owner, "--owner <o>"), needsDevice: flags.device ? bool(flags.device, "--device") : false });
    case "approve": return Command.parse({ type: "card.approve", key: key("approve"), actor, card });
    case "screen": return Command.parse({ type: "card.screen", key: key("screen", sha()), actor, card, sha: sha(), pass: bool(flags.pass, "--pass") });
    case "review": return Command.parse({ type: "card.review", key: key("review", sha()), actor, card, sha: sha(), signedBy: need(flags.by, "--by <who>"), accept: bool(flags.accept, "--accept") });
    case "swipe": return Command.parse({ type: "card.swipe", key: key("swipe", sha()), actor, card, sha: sha(), better: bool(flags.better, "--better") });
    default: return Command.parse({ type: "card.land_request", key: key("land_request", sha()), actor, card, sha: sha() });
  }
}
