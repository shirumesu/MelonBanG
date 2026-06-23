import { Star, StarHalf } from "lucide-react";
import { cn } from "@/lib/utils";

interface ReadOnlyRatingProps {
  score: number; // 1-10
  className?: string;
  showScore?: boolean;
}

/**
 * ReadOnlyRating - 只读星星评分显示
 * 1-10分映射到0.5-5星（每半颗星=1分）
 */
export function ReadOnlyRating({ score, className, showScore = true }: ReadOnlyRatingProps) {
  // score: 1-10 -> stars: 0.5-5
  const stars = score / 2;
  const fullStars = Math.floor(stars);
  const hasHalfStar = stars % 1 >= 0.5;

  return (
    <div className={cn("inline-flex items-center gap-1.5", className)}>
      <div className="flex items-center gap-0.5">
        {Array.from({ length: 5 }, (_, i) => {
          if (i < fullStars) {
            return (
              <Star key={i} className="text-gold-500 h-3.5 w-3.5 fill-current" strokeWidth={0} />
            );
          } else if (i === fullStars && hasHalfStar) {
            return (
              <div key={i} className="relative h-3.5 w-3.5">
                <Star className="text-line-strong absolute inset-0 h-3.5 w-3.5" strokeWidth={1.5} />
                <div className="absolute inset-0 overflow-hidden" style={{ width: "50%" }}>
                  <StarHalf className="text-gold-500 h-3.5 w-3.5 fill-current" strokeWidth={0} />
                </div>
              </div>
            );
          } else {
            return <Star key={i} className="text-line-strong h-3.5 w-3.5" strokeWidth={1.5} />;
          }
        })}
      </div>
      {showScore && <span className="text-ink-soft text-[12px] font-bold">{score}</span>}
    </div>
  );
}
