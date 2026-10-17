import { z } from "zod";
import { jsonSchemas } from "./index.ts";

/** JSON Schema (draft 2020-12) of every contract, keyed by name. Committed under ../schema/. */
export function allJsonSchemas(): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(jsonSchemas).map(([name, s]) => [name, z.toJSONSchema(s, { target: "draft-2020-12" })]),
  );
}
