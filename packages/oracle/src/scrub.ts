
export function scrub(text: string, secret?: string | null): string {
  let t = text;
  if (secret && secret.length >= 8) t = t.split(secret).join("<token>");
  return t.replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/g, "Bearer <token>");
}

export function errorText(e: unknown, secret?: string | null): string {
  return scrub(e instanceof Error ? e.message : String(e), secret).slice(0, 300);
}
