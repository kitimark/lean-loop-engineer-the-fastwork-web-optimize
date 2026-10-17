export function readPayload(): Record<string, unknown> | null;
export function consoleDir(cwd?: unknown): string | null;
export function safeName(s: unknown): string;
export function appendLine(file: string, obj: unknown): void;
export function secret(dir: string): string;
export function sha256(s: string): string;
export function capMac(sec: string, agentId: string | null, agentType: string, toolUseId: string, cmdHash: string): string;
