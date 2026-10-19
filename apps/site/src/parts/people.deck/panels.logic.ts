/**
 * Pure logic of the feed panels (Services, Reviews, About) of people.deck, restated from the original
 * (nodes/2.DyWL8TcE.js): tabs 6456 and 10719-10721, filters 6486-6496, faces 6500-6503 and 10478-10498, verdict 6475-6477,
 * stars 10287, toggle 10460, about sections 6676-6818, monogram 6478-6485, dates 6462-6471. Spec and proofs:
 * lean/Fw/Parts/PeopleDeckPanels.lean. Golden vectors: packages/contracts/golden/parts/people.deck.panels.jsonl.
 */

export type FeedTab = 'posts' | 'services' | 'reviews' | 'about';
export const FEED_TAB_IDS: readonly FeedTab[] = ['posts', 'services', 'reviews', 'about'];

/** The panel of a tab id; any other id falls to about. */
export function tabOf({ id }: { id: string }): FeedTab {
  return id === 'posts' ? 'posts' : id === 'services' ? 'services' : id === 'reviews' ? 'reviews' : 'about';
}

/** Filter ids: `all`, then each service that has reviews. */
export function filterIds({ services }: { services: Array<{ id: string; reviewCount: number }> }): string[] {
  return ['all', ...services.filter((s) => s.reviewCount > 0).map((s) => s.id)];
}

/** The service ids of the reviews a filter lists. */
export function shown({ filter, reviews }: { filter: string; reviews: string[] }): string[] {
  return filter === 'all' ? reviews : reviews.filter((r) => r === filter);
}

/** First occurrence of each avatar. */
const dedup = (l: string[]): string[] => l.filter((a, i) => l.indexOf(a) === i);

/** The avatars drawn: the first three distinct ones. */
export function faces({ avatars }: { avatars: string[] }): string[] {
  return dedup(avatars).slice(0, 3);
}

/** The "+n" chip count. */
export function more({ total, avatars }: { total: number; avatars: string[] }): number {
  return Math.max(0, total - Math.min(dedup(avatars).length, 3));
}

export type Verdict = 'excellent' | 'veryGood' | 'good' | 'fair' | 'poor';

export function verdict({ score }: { score: number }): Verdict {
  return score >= 4.5 ? 'excellent' : score >= 4 ? 'veryGood' : score >= 3.5 ? 'good' : score >= 2.5 ? 'fair' : 'poor';
}

/** Star `i` (0-based) of five is filled iff i < Math.round(score). */
export function filled({ score, i }: { score: number; i: number }): boolean {
  return i < Math.round(score);
}

export function flip({ b }: { b: boolean }): boolean {
  return !b;
}

/** Section ids of the about panel, in template order. */
export function sections({ education, certificates, languages, awards }: { education: number; certificates: number; languages: number; awards: number }): string[] {
  return [
    'experience',
    ...(education > 0 ? ['education'] : []),
    'skills',
    ...(certificates > 0 ? ['certificates'] : []),
    ...(languages > 0 ? ['languages'] : []),
    ...(awards > 0 ? ['awards'] : []),
  ];
}

/** Monogram of a name: first letter of the first two words that start with a letter or digit (ASCII). */
export function initials({ name }: { name: string }): string {
  return name
    .split(/\s+/)
    .filter((w) => /^[A-Za-z0-9]/.test(w))
    .slice(0, 2)
    .map((w) => w[0]!.toUpperCase())
    .join('');
}

const monthYear = new Intl.DateTimeFormat('en', { month: 'short', year: 'numeric' });
const fullDate = new Intl.DateTimeFormat('en', { day: 'numeric', month: 'short', year: 'numeric' });

/** "2024-03" as "Mar 2024". */
export function formatMonth(v: string): string {
  const [y, m] = v.split('-').map(Number);
  return monthYear.format(new Date(y!, (m || 1) - 1, 1));
}

/** "2026-09-04" as "Sep 4, 2026". */
export function formatDay(v: string): string {
  const [y, m, d] = v.split('-').map(Number);
  return fullDate.format(new Date(y!, (m || 1) - 1, d || 1));
}

/** Date range of an entry; an open end reads "Present". */
export function range(start: string, end: string | null | undefined): string {
  return `${formatMonth(start)} – ${end ? formatMonth(end) : 'Present'}`;
}
