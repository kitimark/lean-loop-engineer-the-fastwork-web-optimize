import type { CSSProperties, HTMLAttributes, ReactNode } from 'react';
import { ONLINE_ICON } from './data';
import css from './card.module.css';

export const cardClass = css.card;

export interface HeroCardProps extends HTMLAttributes<HTMLElement> {
  className?: string;
  style?: CSSProperties;
  /** Seller name and the role · place line. */
  name: string;
  role: string;
  cover: string;
  avatar: string;
  children?: ReactNode;
}

/**
 * One portfolio card (cover, avatar row, name and role): the original's `article.orbit-card` markup, with the seller's
 * pictures and text. Shared by hero.orbit and hero.deck; the ring and the deck add their own classes and state.
 */
export function HeroCard({ className, name, role, cover, avatar, ...rest }: HeroCardProps) {
  return (
    <article className={className ? `${css.card} ${className}` : css.card} {...rest}>
      <div className={css.hit}>
        <span className={css.profile}>
          <span className={css.cover}>
            <picture>
              <img src={cover} alt="" decoding="async" draggable={false} />
            </picture>
          </span>{' '}
          <span className={css.body}>
            <span className={css.avatarRow}>
              <span className={css.avatar}>
                <picture>
                  <img src={avatar} alt="" decoding="async" draggable={false} />
                </picture>{' '}
                <img className={css.online} src={ONLINE_ICON} alt="" draggable={false} />
              </span>
            </span>{' '}
            <span className={css.info}>
              <span className={css.name}>{name}</span> <span className={css.role}>{role}</span>
            </span>
          </span>
        </span>
      </div>
    </article>
  );
}
