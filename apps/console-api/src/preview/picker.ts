// TS stand-in for Lean `Fw.Console.Builds.picker` and `choose`; checked against `golden/console/console.buildsPicker.jsonl`
// (test/builds.test.ts). The serve-child process has no fwcore, so the compare page cannot call the op.

const PRESET = /^[a-z0-9-]+$/;
const FW = /^[A-Za-z0-9.:,\-_@]+$/;

const isPresetKey = (s: string) => s.startsWith("?preset=") && PRESET.test(s.slice(8));
const isFwKey = (s: string) => s.startsWith("?fw=") && FW.test(s.slice(4));

/** The searches a build's picker lists: default, presets, flags, each in key order. */
export const picker = (keys: readonly string[]): string[] =>
  [...keys.filter((k) => k === ""), ...keys.filter(isPresetKey), ...keys.filter(isFwKey)];

/** The search the compare view loads for a requested one. */
export const choose = (keys: readonly string[], cur: string): string => (picker(keys).includes(cur) ? cur : "");
