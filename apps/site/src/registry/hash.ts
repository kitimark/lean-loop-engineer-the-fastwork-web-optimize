/** FNV-1a 64-bit over UTF-8, hex. Sync and dependency-free so it runs in the browser and in Node alike. */
export function fnv1a64(input: string): string {
  const bytes = new TextEncoder().encode(input);
  let h = 0xcbf29ce484222325n;
  const prime = 0x100000001b3n;
  const mask = 0xffffffffffffffffn;
  for (const b of bytes) {
    h ^= BigInt(b);
    h = (h * prime) & mask;
  }
  return h.toString(16).padStart(16, '0');
}
