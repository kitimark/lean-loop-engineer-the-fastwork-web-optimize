/**
 * Content of the People section: the six professions in showcase order (the original's profile list, nodes/2.DyWL8TcE.js
 * 4872-6125, 6144-6146 for the order). Text and numbers restated; the photos (avatar, cover, posts, service thumbs) are
 * not shipped: the rewrite draws neutral fills at the same boxes (assets stay in the read-only snapshot).
 */
export interface Service {
  id: string;
  title: string;
  price: string;
  sold: number;
  rating: number;
  reviewCount: number;
}
export interface Post {
  kind: 'photo' | 'audio' | 'article' | 'video';
  id: string;
  /** CSS aspect-ratio of a photo post (inline on the card); audio posts are square */
  ratio?: string;
  /** price badge of a photo post */
  price?: string;
  /** play badge of a video post */
  video?: boolean;
  /** article posts */
  title?: string;
  excerpt?: string;
  readMinutes?: number;
}
export interface Profile {
  id: string;
  label: string;
  name: string;
  handle: string;
  followers: string;
  bio: string;
  location: string;
  tags: string[];
  stats: { earned: string; orders: number; rehires: number; rating: number };
  services: Service[];
  posts: Post[];
}

export const PROFILES: Profile[] = [
  {
    id: "sound-composer",
    label: "Sound Composer",
    name: "Chapavich Temnitikul",
    handle: "@phil_wc",
    followers: "142K",
    bio: "Film composer with six Best Original Score awards, scoring features, series and documentaries across Thailand and Asia.",
    location: "Bangkok, Thailand",
    tags: ["Film Scoring","Original Soundtrack","Sound Design"],
    stats: { earned: "฿5M+", orders: 104, rehires: 45, rating: 4.8 },
    services: [
      { id: "short-film-scoring", title: "Custom Short Film & Commercial Scoring", price: "฿15,000", sold: 18, rating: 4.8, reviewCount: 14 },
      { id: "feature-score", title: "Feature Film / Series Original Score & Sound Design", price: "฿500,000", sold: 12, rating: 5, reviewCount: 10 },
      { id: "soundtrack-release", title: "Original Soundtrack & Ambient Music Production", price: "฿20,000", sold: 7, rating: 4.9, reviewCount: 6 },
    ],
    posts: [
      { kind: "photo", id: "you-me-me", ratio: "17 / 24" },
      { kind: "photo", id: "maynila", ratio: "2 / 3" },
      { kind: "photo", id: "orchestra", ratio: "3 / 2" },
      { kind: "audio", id: "showreel" },
    ],
  },
  {
    id: "photographer",
    label: "Photographer",
    name: "Karn Kraipasit",
    handle: "@karn_kraipasit",
    followers: "48K",
    bio: "Creative / Social Media / Production House / Website / KOL / Event",
    location: "Bangkok, Thailand",
    tags: ["Photography","Production House","Social Media"],
    stats: { earned: "฿4.2M", orders: 96, rehires: 38, rating: 4.9 },
    services: [
      { id: "commercial-shoot", title: "Commercial & Product Photography", price: "฿35,000", sold: 24, rating: 4.9, reviewCount: 18 },
      { id: "fashion-shoot", title: "Fashion & Lookbook Shoot", price: "฿45,000", sold: 9, rating: 5, reviewCount: 7 },
      { id: "event-content", title: "Event & Social Media Content", price: "฿18,000 / day", sold: 31, rating: 4.8, reviewCount: 22 },
    ],
    posts: [
      { kind: "photo", id: "strawberry", ratio: "5 / 7" },
      { kind: "photo", id: "tuna", ratio: "5 / 7" },
      { kind: "photo", id: "football", ratio: "5 / 3" },
      { kind: "photo", id: "tuna-cut", ratio: "3 / 4" },
      { kind: "photo", id: "runway", ratio: "5 / 7" },
      { kind: "photo", id: "loreal", ratio: "5 / 7" },
    ],
  },
  {
    id: "video-editor",
    label: "Video Editor",
    name: "Pannatorn Manobal",
    handle: "@BankEditor",
    followers: "36K",
    bio: "VTR, Music Video, Aftermovie, Short film, Trailer, Teaser, Reels",
    location: "Bangkok, Thailand",
    tags: ["Music Video","Aftermovie","Short Film"],
    stats: { earned: "฿4.2M", orders: 96, rehires: 38, rating: 4.9 },
    services: [
      { id: "shorts-edit", title: "Fashion/commercial shorts edit", price: "฿13,000", sold: 24, rating: 4.9, reviewCount: 18 },
      { id: "cinematic-edit", title: "Cinematic vdo edit", price: "฿25,000", sold: 9, rating: 5, reviewCount: 7 },
    ],
    posts: [
      { kind: "photo", id: "graffiti", ratio: "2 / 1", video: true },
      { kind: "photo", id: "chainmail", ratio: "9 / 16", video: true },
      { kind: "photo", id: "oym", ratio: "9 / 16", video: true },
      { kind: "photo", id: "neon-smile", ratio: "16 / 9", video: true },
      { kind: "photo", id: "club", ratio: "3 / 5", video: true },
    ],
  },
  {
    id: "graphic-designer",
    label: "Graphic Designer",
    name: "Tae Rawiphan",
    handle: "@Rawi",
    followers: "142K",
    bio: "Art Director / Graphic Designer / Packaging Design",
    location: "Bangkok, Thailand",
    tags: ["Graphic Design","Illustration","Branding"],
    stats: { earned: "฿2.8M", orders: 88, rehires: 5, rating: 4.8 },
    services: [
      { id: "illustration", title: "Illustration", price: "฿10,000 / day", sold: 9, rating: 4.8, reviewCount: 5 },
      { id: "graphic-design", title: "Graphic Designer", price: "฿10,000 / day", sold: 12, rating: 4.9, reviewCount: 5 },
    ],
    posts: [
      { kind: "photo", id: "star-coffee", ratio: "3 / 4", price: "฿5,000" },
      { kind: "photo", id: "hunq", ratio: "1 / 1", price: "฿5,000" },
      { kind: "article", id: "cine-cafe", title: "Cine cafe", excerpt: "Create unique, custom illustrations designed to enhance the atmosphere and visual identity of restaurants, cafes, and other hospitality spaces.", readMinutes: 2 },
      { kind: "photo", id: "nefertem", ratio: "1 / 1" },
      { kind: "photo", id: "dream-team", ratio: "3 / 4" },
      { kind: "photo", id: "fraction", ratio: "1 / 1" },
    ],
  },
  {
    id: "ai-automation",
    label: "AI Automation",
    name: "JOB AGICAFET",
    handle: "@Jobagicafet",
    followers: "99",
    bio: "AI Agents that get work done.",
    location: "Bangkok, Thailand",
    tags: ["AI Agents","Automation","LLM","Chatbots"],
    stats: { earned: "฿25M", orders: 100, rehires: 10, rating: 4.9 },
    services: [
      { id: "ai-automation-setup", title: "AI Automation Set up", price: "฿10,000", sold: 45, rating: 4.8, reviewCount: 12 },
      { id: "custom-ai-chatbot", title: "Custom AI Chatbot", price: "฿35,000", sold: 20, rating: 4.9, reviewCount: 8 },
    ],
    posts: [
      { kind: "article", id: "local-llm", title: "Efficient Local LLM on one DGX Spark.", excerpt: "Upload a document, ask in plain language, and get answers that cite their exact page.", readMinutes: 4 },
      { kind: "photo", id: "spark", ratio: "4 / 3" },
      { kind: "photo", id: "marketing", ratio: "12 / 13", price: "฿35,000" },
      { kind: "photo", id: "symposium", ratio: "3 / 4" },
    ],
  },
  {
    id: "web-developer",
    label: "Web Developer",
    name: "BigzWeb",
    handle: "@BigzWeb",
    followers: "142K",
    bio: "Website · Application · Full-Stack + AI Development — All-in-One Team",
    location: "Bangkok, Thailand",
    tags: ["Web Development","E-Commerce","Performance"],
    stats: { earned: "฿5M+", orders: 104, rehires: 45, rating: 4.8 },
    services: [
      { id: "one-page", title: "One-Page Website, Sales Page", price: "฿15,000", sold: 18, rating: 4.8, reviewCount: 14 },
      { id: "full-site", title: "E-Commerce Websites, Corporate Websites, Real Estate Platforms, and More", price: "฿35,000", sold: 12, rating: 5, reviewCount: 10 },
    ],
    posts: [
      { kind: "photo", id: "haus-clinic", ratio: "4 / 5" },
      { kind: "photo", id: "greengo", ratio: "1 / 1" },
      { kind: "article", id: "slow-website", title: "How Much Does a Slow Website Cost your Business — And How to Check and Fix It Yourself", excerpt: "Think about the last time you clicked a website and saw a blank screen. How many seconds did you wait before leaving?", readMinutes: 7 },
      { kind: "photo", id: "speed-addict", ratio: "9 / 16" },
    ],
  },
];

/** Order of the six faces inside the "o" (nodes/2.DyWL8TcE.js 6160-6167). */
export const O_ORDER = ['ai-automation', 'photographer', 'sound-composer', 'graphic-designer', 'video-editor', 'web-developer'] as const;

export const byId = (id: string): Profile => PROFILES.find((p) => p.id === id)!;

/** Copy of the section (the English strings of the original's catalogue). */
export const COPY = {
  titleLead: 'People still need',
  titleWord: 'people',
  bodyLead: "Clients don't just buy outputs. They buy expertise, experience, taste, and trust.",
  bodyRest: "That's why your portfolio matters more than ever.",
  community: '3,788 people showcasing their work',
  getStarted: 'Join waitlist',
};
