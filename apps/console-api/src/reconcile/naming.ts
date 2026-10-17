// Branch -> card naming rule (documented in docs/team/handoffs/con-land.md):
//   card/<CARD>            the builder is the card's owner
//   card/<CARD>/<agent>    the builder is <agent>
// Any other branch (main, worktree-agent-*, ...) maps to no card and is ignored.
export type BranchCard = { card: string; agent: string | null };

export function branchCard(ref: string): BranchCard | null {
  const m = /^card\/([^/]+)(?:\/([^/]+))?$/.exec(ref);
  return m ? { card: m[1]!, agent: m[2] ?? null } : null;
}
