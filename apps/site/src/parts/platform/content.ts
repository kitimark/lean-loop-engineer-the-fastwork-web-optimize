/**
 * English copy and data of the platform section (the original's English locale; the other locales are not ported).
 * Image paths are the original's public paths (the assets are not in this repository: they are served next to the
 * page at publish time). Order of the arrays is the order of the original.
 */
export const HEADING = 'One platform is everything you need';

export const REVIEWS = [
  { name: 'Hannah Kim', quote: '“The profile sold me. Delivery matched every review.”', avatar: '/selling/media/avatar-alt-2.jpg' },
  { name: 'Elena Rossi', quote: '“Fast replies, strong craft, and proof I could verify.”', avatar: '/selling/media/avatar-cat.png' },
  { name: 'Maya Chen', quote: '“Clear brief, polished delivery — I’d hire them again.”', avatar: '/selling/sellers/reviewers/r5.jpg' },
  { name: 'Linh Tran', quote: '“Honest reviews plus real samples — no guessing.”', avatar: '/selling/commission/client-avatar-3.png' },
] as const;

export const PROFILE = {
  name: 'boldddd',
  handle: '@bolddddd',
  followers: '· 5 followers',
  bio: 'Interior designer crafting meaningful spaces',
  location: 'Bangkok, Thailand',
  stats: ['Earned', 'Orders', 'Rehires', 'Reviews'],
  tiles: [
    { size: 'tileShort', src: '/selling/media/post-2.png', price: '฿6,500' },
    { size: 'tileMid', src: '/selling/media/service-kitchen.png', price: '฿8,900' },
    { size: 'tileTall', src: '/selling/media/post-3.png', price: '฿6,500' },
  ],
} as const;

export interface Service {
  thumb: string;
  avif?: string;
  title: string;
  desc: string;
  rating: string;
  price: string;
}
export interface Topic {
  query: string;
  services: Service[];
}

export const ASK_TITLE = 'What do you need help with?';
export const TOPICS: Topic[] = [
  {
    query: 'Contract needs a lawyer',
    services: [
      { thumb: '/selling/media/post-5.jpg', avif: '/selling/optimized/media/post-5.avif', title: 'Contract review', desc: 'Same-week review of agreements with clear redlines and next steps.', rating: '4.9 (28)', price: 'from $12,000' },
      { thumb: '/samples/docs/lawyer/lawyer-consult-cover.png', avif: '/selling/optimized/external/lawyer-consult-cover-240.avif', title: 'Legal consult', desc: 'A working session on contracts, risk, and structure.', rating: '4.8 (16)', price: 'from $7,500' },
    ],
  },
  {
    query: "Ads aren't getting clicks",
    services: [
      { thumb: '/selling/media/post-1.png', title: 'Paid ads sprint', desc: 'Rebuild creative, targeting, and landing so spend turns into leads.', rating: '4.9 (41)', price: 'from $8,500' },
      { thumb: '/selling/media/post-2.png', title: 'Ad creative pack', desc: 'Feed and story ads with hooks and variants ready to test.', rating: '4.8 (33)', price: 'from $5,500' },
    ],
  },
  {
    query: 'Website feels outdated',
    services: [
      { thumb: '/selling/platform/service-thumb-bot.jpg', title: 'Homepage refresh', desc: 'A clearer hero, offer, and proof for the first screen.', rating: '4.9 (54)', price: 'from $15,000' },
      { thumb: '/selling/platform/service-thumb-main.jpg', title: 'Landing page build', desc: 'One focused, fast, mobile-first campaign page.', rating: '4.8 (37)', price: 'from $11,000' },
    ],
  },
  {
    query: 'No idea what to post',
    services: [
      { thumb: '/selling/media/post-3.png', title: '30-day content plan', desc: 'Hooks, captions, and a calendar that make posting simple.', rating: '5.0 (46)', price: 'from $4,900' },
      { thumb: '/selling/media/cover-cafe.jpg', title: 'Content shoot day', desc: 'A batch of on-brand photos and clips for weeks of posts.', rating: '4.9 (31)', price: 'from $7,200' },
    ],
  },
];

export const FLAGS = [
  { id: 'kr', bordered: true },
  { id: 'us', bordered: true },
  { id: 'th', bordered: false },
  { id: 'jp', bordered: true },
  { id: 'eu', bordered: true },
  { id: 'uk', bordered: true },
] as const;
export const UK_LAYERS = ['flag-uk', 'flag-uk-2', 'flag-uk-3', 'flag-uk-4', 'flag-uk-5'] as const;

export const ORDERS = [
  { name: 'Northline Studio', meta: 'Landing page design + build · 20 Jul 2026', price: '$34,000', pay: ['Held', 'held'], work: ['New', 'new'] },
  { name: 'Elena Rossi', meta: 'Logo & brand identity · 21 Jul 2026', price: '$18,000', pay: ['Paid', 'paid'], work: ['In progress', 'progress'] },
  { name: 'Maya Chen', meta: 'Social media design pack · 18 Jul 2026', price: '$9,500', pay: ['Unpaid', 'unpaid'], work: ['New', 'new'] },
  { name: 'Harbor Coffee Co.', meta: 'Logo & brand identity · 12 Jul 2026', price: '$18,000', pay: ['Paid', 'paid'], work: ['Delivered', 'delivered'] },
] as const;

export const QUOTE = { kicker: 'Quotation', valid: 'Valid until: 21 Aug 2026', amount: '$12,000', pack: 'Social media design pack' } as const;

export const NETWORK = '/selling/platform/features/secure/network';
