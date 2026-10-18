import { PeopleCard } from '../people.card';
import { PeopleCarousel } from '../people.carousel';
import { PeopleDeck } from '../people.deck';
import { PeopleO } from '../people.o';

/**
 * The People section (P2): the four parts people.card, people.o, people.deck and people.carousel composed. Each part has its
 * own variant in the config; all are `faithful`.
 */
export function People({ variants }: { variants: Record<string, string> }) {
  const v = (id: string) => variants[id] ?? 'faithful';
  return (
    <PeopleCard
      variant={v('people.card')}
      o={<PeopleO variant={v('people.o')} />}
      deck={<PeopleDeck variant={v('people.deck')} />}
      pill={<PeopleCarousel variant={v('people.carousel')} />}
    />
  );
}
