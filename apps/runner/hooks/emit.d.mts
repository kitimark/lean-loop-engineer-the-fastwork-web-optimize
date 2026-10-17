export const VERBS: Set<string>;
export function verbOf(command: unknown): string | null;
export function record(p: Record<string, unknown>, now?: number): Record<string, unknown> | null;
