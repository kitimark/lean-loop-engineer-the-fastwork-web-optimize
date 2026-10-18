/**
 * The text of the notes: the original's `pain.notes[k]` dictionary entries for the keys in the pool (JS 4418; English
 * strings in nodes/2.DyWL8TcE.js:896-1090), indexed by key 12..23. English only; the locale dictionary is not ported.
 */
export const NOTE_TEXT: Record<number, string> = {
  12: 'I use 3 different messengers to talk with different clients.',
  13: "The client still hasn't paid...",
  14: 'Where should I keep my paperwork?',
  15: 'How do I create a website for my portfolio?',
  16: "I don't have reviews to build my credibility...",
  17: 'How does my client pay me?',
  18: 'I hate platform commission...',
  19: 'How do I find my next order?',
  20: 'Another quotation to make...',
  21: 'Tax season is coming...',
  22: "What's even left after the commission fee?",
  23: 'Need to draft a quotation',
};

/** The heading and body of the section (JS 864, 878-886), English. */
export const PAIN_HEADING = 'Freelancing is hard enough...';
export const PAIN_BODY = 'Let us handle the problem for you';

/** The accessible name of a note (JS 4784 `pain.dragNote`), English. */
export const dragNoteLabel = (text: string): string => `Drag note: ${text}`;
