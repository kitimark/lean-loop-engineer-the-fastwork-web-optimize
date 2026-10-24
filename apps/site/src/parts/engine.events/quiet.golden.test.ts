import { createRoot } from 'react-dom/client';
import { goldenConformance } from '../../engine/golden.testutil';
import { admit, quietContainer } from './quiet';
import { quietTypes } from './quiet.gen';

/** A container that records what React registers on it; the real react-dom 19.3.1 builds the root. */
function register(variant: 'faithful' | 'quiet'): string[] {
  const log: string[] = [];
  const doc = { nodeType: 9, ownerDocument: null, addEventListener: () => {} };
  const container = {
    nodeType: 1,
    nodeName: 'DIV',
    ownerDocument: doc,
    addEventListener(type: string, _fn: unknown, options?: boolean | { capture?: boolean }) {
      const capture = options === true || (typeof options === 'object' && options.capture === true);
      log.push(`${type}:${capture ? 'c' : 'b'}`);
    },
  };
  if (variant === 'quiet') quietContainer(container as unknown as EventTarget);
  createRoot(container as unknown as Element);
  return log;
}

const records = (variant: 'faithful' | 'quiet', type: string): number => register(variant).filter((r) => r.startsWith(`${type}:`)).length;

goldenConformance('react-root-quiet', {
  quiet: () => [...quietTypes],
  registered: (i) => register(i.variant as 'faithful' | 'quiet'),
  admit: (i) => admit(i.type as string),
  records: (i) => records(i.variant as 'faithful' | 'quiet', i.type as string),
});
