import { readFileSync } from 'node:fs';
import { defineConfig } from 'vitest/config';

const budget = JSON.parse(readFileSync(new URL('../../packages/contracts/golden/sched/node-budget.gen.json', import.meta.url), 'utf8')) as { workers: number };

export default defineConfig({
  test: { include: ['src/**/*.test.ts', 'test/**/*.test.ts'], environment: 'node', maxWorkers: budget.workers },
});
