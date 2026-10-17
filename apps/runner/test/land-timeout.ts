// Land tests start tens of child processes per test (version control, fwcore). vitest's 5 s default made them fail under
// CPU load (check-dag runs checks in parallel). Nothing asserts wall-clock time; the bound only catches a hung child.
import { vi } from "vitest";
vi.setConfig({ testTimeout: 120_000, hookTimeout: 120_000 });
