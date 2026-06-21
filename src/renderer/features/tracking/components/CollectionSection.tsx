import type { CollectionListItem } from "@shared/contracts/bangumi";
import { PosterCard } from "./PosterCard";

export function CollectionSection({ items }: { items: CollectionListItem[] }): JSX.Element {
  return (
    <div className="grid grid-cols-[repeat(auto-fill,minmax(168px,1fr))] gap-4">
      {items.map((item) => (
        <PosterCard key={item.subjectId} item={item} />
      ))}
    </div>
  );
}
