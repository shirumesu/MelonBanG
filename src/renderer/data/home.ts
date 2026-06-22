export type Season = "summer" | "winter" | "spring" | "fall";

export type TimelineItem = {
  time: string;
  airingAt?: string;
  airingAtShanghai?: string;
  index: number;
  subjectId?: number;
  title: string;
  ep?: number;
  total?: number;
  done: boolean;
  coverUrl?: string;
  subtitle?: string;
  badgeLabel?: string;
  actionLabel?: string;
};
