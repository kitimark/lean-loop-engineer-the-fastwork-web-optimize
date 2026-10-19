import type { Post, Profile, Service } from './data';

/**
 * Photo URLs of the People section: the avatars, covers, post tiles and service thumbs, bundled by the build from the
 * unmodified snapshot (snapshot/site/selling/sellers/<id>/, the directory name is the profile id). The file names are the
 * original's: nodes/2.DyWL8TcE.js 4863-4871 (directories) and the per-profile lists below them (4872-6125).
 */
const files = import.meta.glob<string>(
  '../../../../../snapshot/site/selling/sellers/{sound-composer,photographer,video-editor,graphic-designer,ai-automation,web-developer}/{avatar,cover,post-*,service-*}.jpg',
  { eager: true, import: 'default' },
);

const byName = new Map<string, string>();
for (const [path, url] of Object.entries(files)) byName.set(path.replace(/^.*\/sellers\//, ''), url);

const url = (dir: string, file: string): string | undefined => byName.get(`${dir}/${file}`);

/** post ids whose file name is not `post-<id>.jpg` (the photographer's first tile is the service photo) */
const POST_FILE: Record<string, string> = { 'photographer/strawberry': 'service-strawberry.jpg' };

/** a service thumb is another file of the same seller (the original's `thumb`) */
const THUMB: Record<string, string> = {
  'sound-composer/short-film-scoring': 'service-scoring.jpg',
  'sound-composer/feature-score': 'service-feature.jpg',
  'sound-composer/soundtrack-release': 'service-ost.jpg',
  'photographer/commercial-shoot': 'post-ysl.jpg',
  'photographer/fashion-shoot': 'post-strawberry.jpg',
  'photographer/event-content': 'post-football.jpg',
  'video-editor/shorts-edit': 'service-eye.jpg',
  'video-editor/cinematic-edit': 'post-neon-smile.jpg',
  'graphic-designer/illustration': 'post-star-coffee.jpg',
  'graphic-designer/graphic-design': 'post-hunq.jpg',
  'ai-automation/ai-automation-setup': 'service-setup.jpg',
  'ai-automation/custom-ai-chatbot': 'service-chatbot.jpg',
  'web-developer/one-page': 'service-dd-transport.jpg',
  'web-developer/full-site': 'post-greengo.jpg',
};

/** article tiles show the article's cover */
const ARTICLE: Record<string, string> = {
  'graphic-designer/cine-cafe': 'post-cinecafe.jpg',
  'ai-automation/local-llm': 'post-slabs.jpg',
  'web-developer/slow-website': 'post-slow-website.jpg',
};

export const avatarOf = (p: Pick<Profile, 'id'>): string | undefined => url(p.id, 'avatar.jpg');
export const coverOf = (p: Pick<Profile, 'id'>): string | undefined => url(p.id, 'cover.jpg');

export function postOf(p: Pick<Profile, 'id'>, post: Pick<Post, 'id' | 'kind'>): string | undefined {
  const key = `${p.id}/${post.id}`;
  if (post.kind === 'audio') return coverOf(p);
  const file = post.kind === 'article' ? ARTICLE[key] : (POST_FILE[key] ?? `post-${post.id}.jpg`);
  return file ? url(p.id, file) : undefined;
}

export function thumbOf(p: Pick<Profile, 'id'>, s: Pick<Service, 'id'>): string | undefined {
  const file = THUMB[`${p.id}/${s.id}`];
  return file ? url(p.id, file) : undefined;
}

/** the carousel ring: the six showcase avatars in the original's showcase order (2.DyWL8TcE.js 6144-6146, 11270) */
export const RING_ORDER = ['sound-composer', 'photographer', 'video-editor', 'graphic-designer', 'ai-automation', 'web-developer'] as const;

/** inline `background-image` for an element; the class holds the neutral fill, size and position */
export const bg = (u: string | undefined): { backgroundImage: string } | undefined => (u ? { backgroundImage: `url("${u}")` } : undefined);
