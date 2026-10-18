// LAN mode glue (console-lan-owner). Pure helpers only: which address is the LAN address, and is a socket address loopback.
// The decisions (who may reach what) are Lean `Fw.Console.Preview.Owner.allow` via `console.ownerGate`; this file only
// reads facts. The LAN address is found at runtime from the network interfaces: never committed, never in an event.
import type { NetworkInterfaceInfo } from "node:os";

/** RFC 1918 private IPv4 (10/8, 172.16/12, 192.168/16). */
export function isPrivateV4(a: string): boolean {
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(a);
  if (!m) return false;
  const [x, y] = [Number(m[1]), Number(m[2])];
  return x === 10 || (x === 172 && y >= 16 && y <= 31) || (x === 192 && y === 168);
}

/** Interfaces that are not the Wi-Fi/Ethernet the phone reaches (tunnels, bridges, VMs, containers, AirDrop). */
const SKIP = /^(utun|bridge|vmnet|vboxnet|docker|veth|awdl|llw|lo|gif|stf|ap|anpi)/;

/** The private IPv4 address of the first usable interface (en0 first, then other `en*`, then the rest), or null. */
export function pickLanAddr(ifaces: NodeJS.Dict<NetworkInterfaceInfo[]>): string | null {
  const rank = (n: string) => (n === "en0" ? 0 : n.startsWith("en") ? 1 : 2);
  const names = Object.keys(ifaces).filter((n) => !SKIP.test(n)).sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
  for (const n of names) {
    for (const i of ifaces[n] ?? []) {
      if (i.family === "IPv4" && !i.internal && isPrivateV4(i.address)) return i.address;
    }
  }
  return null;
}

/** A socket address is this machine's loopback (127/8, ::1, ::ffff:127/8). An unknown address is not loopback. */
export function isLoopback(addr: string | null | undefined): boolean {
  if (!addr) return false;
  const a = addr.startsWith("::ffff:") ? addr.slice(7) : addr;
  return a === "::1" || /^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(a);
}
