import { useState } from 'react';
import { bg, fileOf, reviewerAvatar, thumbOf } from '../people/assets';
import type { Profile, Service } from '../people/data';
import type { PanelData, ReviewItem } from '../people/panels.data';
import css from './panels.module.css';
import * as L from './panels.logic';

const VERDICT_TEXT: Record<L.Verdict, string> = { excellent: 'Excellent', veryGood: 'Very good', good: 'Good', fair: 'Fair', poor: 'Poor' };
const DIMENSIONS = [
  ['responseSpeed', 'Response speed'],
  ['serviceQuality', 'Service quality'],
  ['skill', 'Skill and expertise'],
  ['value', 'Value for money'],
] as const;

const sel = (key: string) => `start-selling.profile-showcase.${key}`;

function Star({ size, color }: { size: number; color?: string }) {
  return <span className={css.star} aria-hidden="true" style={{ width: size, height: size, color }} />;
}

function ServiceMeta({ s }: { s: Service }) {
  const [amount, ...unit] = s.price.split('/');
  return (
    <span className={css.meta}>
      <span className={css.price}>
        <span className={css.amount}>{amount?.trim()}</span>
        {unit.length > 0 ? <span>{`/ ${unit.join('/').trim()}`}</span> : null}
      </span>
      <span className={css.dot} aria-hidden="true">
        ·
      </span>
      <span>{`Sold ${s.sold}`}</span>
      <span className={css.dot} aria-hidden="true">
        ·
      </span>
      <span className={css.rating}>
        <Star size={14} /> {s.rating.toFixed(1)}
        {s.reviewCount ? <span>{`(${s.reviewCount})`}</span> : null}
      </span>
    </span>
  );
}

/** The Services tab: every service of the profile as a card (nodes/2.DyWL8TcE.js 10609-10647). */
export function ServicesPanel({ p }: { p: Profile }) {
  return (
    <ul className={css.svcGrid}>
      {p.services.map((s) => (
        <li key={s.id}>
          <button type="button" className={css.svcCard} data-selenium={sel(`button.service.${p.id}_${s.id}`)}>
            <span className={css.svcThumb}>
              <span className={css.svcThumbImg} style={bg(thumbOf(p, s))} />
            </span>
            <span className={css.svcTitle}>{s.title}</span>
            <ServiceMeta s={s} />
          </button>
        </li>
      ))}
    </ul>
  );
}

function Summary({ r }: { r: PanelData['reviews'] }) {
  const v = L.verdict({ score: r.score });
  return (
    <div className={css.summary}>
      <div className={css.score}>
        <p className={css.number}>
          {`${r.score.toFixed(1)} `}
          <span className={css.of}>of 5</span>
        </p>
        <p className={css.verdict}>{VERDICT_TEXT[v]}</p>
        <p className={css.stars} aria-hidden="true">
          {[0, 1, 2, 3, 4].map((i) => (
            <Star key={i} size={20} color={L.filled({ score: r.score, i }) ? '#f2b33d' : '#e5e5e5'} />
          ))}
        </p>
      </div>
      <dl className={css.dimensions}>
        {DIMENSIONS.map(([k, label]) => (
          <div key={k} className={css.dimension}>
            <dt>
              <span className={css.icon} aria-hidden="true">
                <DimIcon kind={k} />
              </span>
              {` ${label}`}
            </dt>
            <dd>{r.dimensions[k].toFixed(1)}</dd>
          </div>
        ))}
      </dl>
    </div>
  );
}

function DimIcon({ kind }: { kind: (typeof DIMENSIONS)[number][0] }) {
  return (
    <svg viewBox="0 0 24 24">
      {kind === 'responseSpeed' ? (
        <polygon points="13,3 5,13.5 11,13.5 10,21 18,10.5 12,10.5" />
      ) : kind === 'serviceQuality' ? (
        <>
          <circle cx="12" cy="12" r="8.5" />
          <polyline points="8,12.5 11,15.5 16,9" />
        </>
      ) : kind === 'skill' ? (
        <polygon points="12,3.5 14.6,9 20.5,9.7 16.1,13.7 17.3,19.5 12,16.6 6.7,19.5 7.9,13.7 3.5,9.7 9.4,9" />
      ) : (
        <>
          <polygon points="3.5,5.5 12.5,3.5 20.5,11.5 11.5,20.5 3.5,12.5" />
          <circle cx="8" cy="8" r="1.25" />
        </>
      )}
    </svg>
  );
}

function ReviewCard({ p, review, service }: { p: Profile; review: ReviewItem; service: Service | undefined }) {
  const [open, setOpen] = useState(false);
  return (
    <article className={css.review}>
      <p className={css.rcScore}>
        <Star size={18} color="#f2b33d" /> <span>{review.score.toFixed(1)}</span>
      </p>
      <blockquote className={`${css.quote} ${open ? css.isExpanded : ''}`}>
        <p>{`“${review.text}”`}</p>
      </blockquote>
      <button type="button" className={css.toggle} aria-expanded={open} data-selenium={sel(`button.review-toggle.${p.id}_${review.id}`)} onClick={() => setOpen((o) => L.flip({ b: o }))}>
        {open ? 'Show less' : 'Show more'}
      </button>
      {review.images.length > 0 ? (
        <ul className={css.images}>
          {review.images.map((img) => (
            <li key={img}>
              <img src={fileOf(p, img)} alt="" loading="lazy" decoding="async" draggable={false} />
            </li>
          ))}
        </ul>
      ) : null}
      <footer className={css.author}>
        <img className={css.avatar} src={reviewerAvatar(review.author.avatar)} alt="" loading="lazy" decoding="async" draggable={false} />
        <div className={css.who}>
          <p className={css.name}>
            <strong>{review.author.name}</strong>
            {service ? (
              <>
                {' '}
                <span className={css.sep} aria-hidden="true">
                  –
                </span>{' '}
                <span className={css.service}>{service.title}</span>
              </>
            ) : null}
          </p>
          <p className={css.date}>{L.formatDay(review.date)}</p>
        </div>
      </footer>
    </article>
  );
}

/** The Reviews tab: score summary, digest of the recent reviews, service filters and the review cards (10472-10603). */
export function ReviewsPanel({ p, data }: { p: Profile; data: PanelData }) {
  const [filter, setFilter] = useState('all');
  const r = data.reviews;
  const ids = L.filterIds({ services: p.services });
  const items = r.items.filter((i) => L.shown({ filter, reviews: [i.serviceId] }).length > 0);
  const avatars = r.items.map((i) => i.author.avatar);
  const faces = L.faces({ avatars });
  const more = L.more({ total: r.total, avatars });
  const title = `Summary from ${r.total} reviews`;
  const labelOf = (id: string) => (id === 'all' ? 'All reviews' : (p.services.find((s) => s.id === id)?.title ?? id));
  const countOf = (id: string) => (id === 'all' ? r.total : (p.services.find((s) => s.id === id)?.reviewCount ?? 0));
  return (
    <div className={css.reviews}>
      <div className={css.overview}>
        <span className={css.role}>As a seller</span>
        <Summary r={r} />
        <section className={css.digest} aria-label={title}>
          <header>
            <span className={css.faces} aria-hidden="true">
              {faces.map((a) => (
                <img key={a} src={reviewerAvatar(a)} alt="" />
              ))}
              {more > 0 ? <span className={css.more}>{`+${more}`}</span> : null}
            </span>
            <div className={css.digestCopy}>
              <h3>{title}</h3>
              <p>Generated from recent reviews</p>
            </div>
          </header>
          <ul>
            {r.summary.map((line) => (
              <li key={line}>{line}</li>
            ))}
          </ul>
        </section>
      </div>
      <div className={css.list}>
        <div className={css.filters} role="tablist" aria-label="Reviews">
          {ids.map((id) => (
            <button
              key={id}
              type="button"
              role="tab"
              aria-selected={filter === id}
              data-selenium={sel(`button.review-filter.${p.id}_${id}`)}
              className={filter === id ? css.isActive : undefined}
              onClick={() => setFilter(id)}
            >
              {`${labelOf(id)} (${countOf(id)})`}
            </button>
          ))}
        </div>
        {items.map((review) => (
          <ReviewCard key={review.id} p={p} review={review} service={p.services.find((s) => s.id === review.serviceId)} />
        ))}
      </div>
    </div>
  );
}

function Logo({ p, logo, name }: { p: Profile; logo: string | undefined; name: string }) {
  const src = fileOf(p, logo);
  return src ? (
    <span className={css.logo} aria-hidden="true">
      <img src={src} alt="" loading="lazy" decoding="async" />
    </span>
  ) : (
    <span className={`${css.logo} ${css.isMonogram}`} aria-hidden="true">
      {L.initials({ name })}
    </span>
  );
}

/** The About tab: work experience, education, skills and the optional certificates, languages and awards (6553-6825). */
export function AboutPanel({ p, data }: { p: Profile; data: PanelData }) {
  const a = data.about;
  const shown = L.sections({ education: a.education.length, certificates: a.certificates.length, languages: a.languages.length, awards: a.awards.length });
  return (
    <div className={css.about}>
      {shown.map((id) => {
        switch (id) {
          case 'experience':
            return (
              <section key={id}>
                <h3>Work experience</h3>
                <ul>
                  {a.experience.map((e) => (
                    <li key={e.id} className={css.entry}>
                      <Logo p={p} logo={e.logo} name={e.company} />
                      <div className={css.detail}>
                        <p className={css.headline}>
                          <span>{`${e.role} · ${e.company}`}</span>
                          {e.end === null ? <span className={css.badge}>Current</span> : null}
                        </p>
                        <p className={css.dates}>{L.range(e.start, e.end)}</p>
                        {e.summary ? <p className={css.abSummary}>{e.summary}</p> : null}
                      </div>
                    </li>
                  ))}
                </ul>
              </section>
            );
          case 'education':
            return (
              <section key={id}>
                <h3>Education</h3>
                <ul>
                  {a.education.map((e) => {
                    const parts = [e.field, e.start && e.end ? L.range(e.start, e.end) : undefined].filter(Boolean).join(' · ');
                    return (
                      <li key={e.id} className={css.entry}>
                        <Logo p={p} logo={e.logo} name={e.school} />
                        <div className={css.detail}>
                          <p className={css.headline}>
                            <span>{`${e.school} · ${e.degree}`}</span>
                          </p>
                          {parts ? <p className={css.dates}>{parts}</p> : null}
                        </div>
                      </li>
                    );
                  })}
                </ul>
              </section>
            );
          case 'skills':
            return (
              <section key={id}>
                <h3>Skills</h3>
                <ul className={css.chips}>
                  {a.skills.map((s) => (
                    <li key={s}>{s}</li>
                  ))}
                </ul>
              </section>
            );
          case 'certificates':
            return (
              <section key={id}>
                <h3>Certificates</h3>
                <ul>
                  {a.certificates.map((c) => (
                    <li key={c.id} className={css.entry}>
                      <Logo p={p} logo={c.logo} name={c.issuer} />
                      <div className={css.detail}>
                        <p className={css.headline}>
                          <span>{c.title}</span>
                        </p>
                        <p className={css.dates}>{`Issued ${L.formatMonth(c.issued)} · Associated with ${c.issuer}`}</p>
                      </div>
                    </li>
                  ))}
                </ul>
              </section>
            );
          case 'languages':
            return (
              <section key={id}>
                <h3>Languages</h3>
                <ul className={css.plain}>
                  {a.languages.map((l) => (
                    <li key={l.id}>
                      <span className={css.headline}>
                        <span>{l.name}</span>
                      </span>
                      <span className={css.dates}>{l.level}</span>
                    </li>
                  ))}
                </ul>
              </section>
            );
          default:
            return (
              <section key={id}>
                <h3>Licenses and awards</h3>
                <ul className={css.plain}>
                  {a.awards.map((w) => (
                    <li key={w}>
                      <span className={css.headline}>
                        <span>{w}</span>
                      </span>
                    </li>
                  ))}
                </ul>
              </section>
            );
        }
      })}
    </div>
  );
}
