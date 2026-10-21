// Secrets out of any text that may reach a terminal, a log line or an error: the key itself (when known) and anything
// shaped like a bearer credential. This is a last line of defence; the key is never put into such text on purpose.

/** Replace every occurrence of `secret` (when given and non-trivial) and every `Bearer <credential>` by `<token>`. */
export function scrub(text: string, secret?: string | null): string {
  let t = text;
  if (secret && secret.length >= 8) t = t.split(secret).join("<token>");
  return t.replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/g, "Bearer <token>");
}

/** The message of an unknown thrown value, scrubbed. */
export function errorText(e: unknown, secret?: string | null): string {
  return scrub(e instanceof Error ? e.message : String(e), secret).slice(0, 300);
}
