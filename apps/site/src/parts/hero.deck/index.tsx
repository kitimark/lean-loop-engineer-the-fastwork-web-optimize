import type { CSSProperties } from 'react';
import { HeroCard } from '../hero.orbit/card';
import { CARDS, DECK } from '../hero.orbit/data';
import css from './deck.module.css';

export interface HeroDeckProps {
  variant: string;
}

export function HeroDeck({ variant }: HeroDeckProps) {
  return (
    <div className={css.deck} data-fw="hero-deck" data-fw-variant={variant} aria-label="Featured portfolio cards">
      {DECK.map((d) => (
        <HeroCard
          key={d.slot}
          data-fw-layer="hero.deck_article"
          className={css[d.slot]}
          name={CARDS[d.piece]!.name}
          role={CARDS[d.piece]!.role}
          cover={CARDS[d.piece]!.cover}
          avatar={CARDS[d.piece]!.avatar}
          style={{ '--orbit-rot': `${d.rotate}deg` } as CSSProperties}
        />
      ))}
    </div>
  );
}
