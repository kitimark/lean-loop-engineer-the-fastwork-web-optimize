import { useState } from 'react';
import { avatarOf, bg, coverOf, postOf, thumbOf } from '../people/assets';
import type { Profile } from '../people/data';
import css from './deck.module.css';
import { AboutPanel, ReviewsPanel, ServicesPanel } from './feedPanels';
import { ClockIcon, MuteIcon, PlayIcon, StarIcon } from './icons';
import { FEED_TAB_IDS, tabOf, type FeedTab } from './panels.logic';
import { PANELS } from '../people/panels.data';

const FEED_LABELS: Record<FeedTab, string> = { posts: 'Portfolio', services: 'Services', reviews: 'Reviews', about: 'About' };
const FEED_TABS = FEED_TAB_IDS.map((id) => [id, FEED_LABELS[id]] as const);

/** One profile panel (nodes/2.DyWL8TcE.js 10857-11140 and the feed widgets): header, stats, cover, feed tabs and the posts tab. */
export function ProfilePanel({ p, hidden }: { p: Profile; hidden: boolean }) {
  const [tab, setTab] = useState<FeedTab>('posts');
  const followers = `${p.followers} followers`;
  return (
    <div className={css.panel} role="tabpanel" aria-hidden={hidden || undefined}>
      <div className={css.body}>
        <p className={css.crumb}>{`${p.name}'s Profile`}</p>
        <div className={css.hero}>
          <div className={css.identity}>
            <div className={css.avatarWrap}>
              <span className={css.avatar} style={bg(avatarOf(p))} />
              <span className={css.online} aria-hidden="true" />
            </div>
            <div className={css.meta}>
              <h3 className={css.name}>{p.name}</h3>
              <div className={css.handleRow}>
                <span className={css.handle}>{p.handle}</span>{' '}
                <span className={css.claim}>
                  <span className={css.claimIcon} /> Claim
                </span>{' '}
                <span className={css.social}>{`· ${followers}`}</span> <span className={css.followers}>{followers}</span>
              </div>
              <p className={css.bio}>{p.bio}</p>
              <p className={`${css.location} ${css.isCompact}`}>
                <span className={css.pin} /> {p.location}
              </p>
              <div className={css.stats} aria-label="Profile stats">
                <div>
                  <strong>{p.stats.earned}</strong> <span>Earned</span>
                </div>
                <div>
                  <strong>{String(p.stats.orders)}</strong> <span>Orders</span>
                </div>
                <div>
                  <strong>{String(p.stats.rehires)}</strong> <span>Rehires</span>
                </div>
                <div>
                  <strong>{`★${p.stats.rating.toFixed(1)}`}</strong> <span>Reviews</span>
                </div>
              </div>
            </div>
          </div>
          <div className={css.coverBlock}>
            <span className={css.cover} style={bg(coverOf(p))} />
            <div className={css.coverMeta}>
              <ul className={css.tags}>
                {p.tags.slice(0, 3).map((t) => (
                  <li key={t}>{t}</li>
                ))}
              </ul>
              <p className={css.location}>
                <span className={css.pin} /> {p.location}
              </p>
            </div>
          </div>
        </div>
        <section className={css.feed} aria-label="Profile feed">
          <div className={css.feedTabs} role="tablist" aria-label="Profile sections">
            {FEED_TABS.map(([id, label]) => (
              <button
                key={id}
                type="button"
                role="tab"
                aria-selected={tab === id}
                data-selenium={`start-selling.profile-showcase.button.feed-tab.${p.id}_${id}`}
                className={tab === id ? css.isActive : undefined}
                onClick={() => setTab(tabOf({ id }))}
              >
                {label}
              </button>
            ))}
          </div>
          <div className={css.feedBody} role="tabpanel">
            {tab === 'posts' ? (
              <div className={css.feedPanel}>
                <div className={css.posts}>
                  <div className={css.masonry}>
                    {p.posts.map((post) => (
                      <div key={post.id} className={css.tile}>
                        {post.kind === 'article' ? (
                          <button
                            type="button"
                            className={`${css.postCard} ${css.isArticle}`}
                            data-selenium={`start-selling.profile-showcase.button.post.${p.id}_${post.id}`}
                          >
                            <span className={css.articleCover}>
                              <span className={css.postFill} style={bg(postOf(p, post))} />
                            </span>
                            <span className={css.byline}>
                              <span className={css.bylineAvatar}>
                                <span className={css.postFill} style={bg(avatarOf(p))} />
                              </span>{' '}
                              <span className={css.author}>{p.name}</span>{' '}
                              <span className={css.dot} aria-hidden="true">
                                ·
                              </span>{' '}
                              <span className={css.read}>
                                <ClockIcon className={css.clock} /> {`${post.readMinutes} min read`}
                              </span>
                            </span>
                            <span className={css.articleTitle}>{post.title}</span>
                            <span className={css.excerpt}>{post.excerpt}</span>
                          </button>
                        ) : post.kind !== 'audio' ? (
                          <button
                            type="button"
                            className={css.postCard}
                            data-selenium={`start-selling.profile-showcase.button.post.${p.id}_${post.id}`}
                            style={{ aspectRatio: post.ratio ?? '16 / 10' }}
                          >
                            <span className={css.postFill} style={bg(postOf(p, post))} />
                            {post.price ? <span className={css.postPrice}>{post.price}</span> : null}
                            {post.video ? (
                              <span className={css.videoBadge} aria-hidden="true">
                                <PlayIcon />
                              </span>
                            ) : null}
                          </button>
                        ) : (
                          <button
                            type="button"
                            className={`${css.postCard} ${css.isAudio}`}
                            data-selenium={`start-selling.profile-showcase.button.post.${p.id}_${post.id}`}
                          >
                            <span className={css.vinylWrap}>
                              <span className={css.vinyl}>
                                <span className={`${css.record} ${css.spinning}`}>
                                  <span className={css.label} style={bg(postOf(p, post))} />
                                  <span className={css.hole} />
                                </span>
                                <span className={css.gloss} aria-hidden="true" />
                              </span>
                            </span>
                            <span className={css.fade} aria-hidden="true" />
                            <span className={css.mute} aria-hidden="true">
                              <MuteIcon className={css.muteIcon} />
                            </span>
                          </button>
                        )}
                      </div>
                    ))}
                  </div>
                  <aside className={css.rail}>
                    <div className={css.rail}>
                      <div className={css.railHead}>
                        <h3>Services</h3>
                        <button type="button" className={css.viewAll} data-selenium={`start-selling.profile-showcase.button.view-all-services.${p.id}`} onClick={() => setTab('services')}>
                          View all
                        </button>
                      </div>
                      <ul>
                        {p.services.map((s) => {
                          const [amount, ...unit] = s.price.split('/');
                          return (
                            <li key={s.id}>
                              <button type="button" className={css.row} data-selenium={`start-selling.profile-showcase.button.service.${p.id}_${s.id}`}>
                                <span className={css.thumb} style={bg(thumbOf(p, s))} />
                                <span className={css.copy}>
                                  <span className={css.rowTitle}>{s.title}</span>
                                  <span className={css.meta2}>
                                    <span className={css.price}>
                                      <span className={css.amount}>{amount?.trim()}</span>
                                      {unit.length > 0 ? ` / ${unit.join('/').trim()}` : ''}
                                    </span>{' '}
                                    <span className={css.dot} aria-hidden="true">
                                      ·
                                    </span>{' '}
                                    <span>{`Sold ${s.sold}`}</span>{' '}
                                    <span className={css.dot} aria-hidden="true">
                                      ·
                                    </span>{' '}
                                    <span className={css.rating}>
                                      <StarIcon size={14} /> {s.rating.toFixed(1)} <span>({s.reviewCount})</span>
                                    </span>
                                  </span>
                                </span>
                              </button>
                            </li>
                          );
                        })}
                      </ul>
                    </div>
                  </aside>
                </div>
              </div>
            ) : (
              <div className={css.feedPanel}>
                {tab === 'services' ? <ServicesPanel p={p} /> : null}
                {tab === 'reviews' && PANELS[p.id] ? <ReviewsPanel p={p} data={PANELS[p.id]!} /> : null}
                {tab === 'about' && PANELS[p.id] ? <AboutPanel p={p} data={PANELS[p.id]!} /> : null}
              </div>
            )}
          </div>
        </section>
      </div>
    </div>
  );
}
