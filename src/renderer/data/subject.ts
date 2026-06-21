export type SubjectStatus = "wish" | "watching" | "hold" | "done" | "drop";

export type SubjectStat = {
  key: "wish" | "watching" | "hold" | "done" | "drop";
  label: string;
  count: string;
  pct: number;
};

export type VoiceActor = {
  kanji: string;
  gradient: string;
  name: string;
  role: string;
};

export type StaffMember = {
  initial: string;
  gradient: string;
  name: string;
  role: string;
};

export type SubjectComment = {
  name: string;
  initial: string;
  gradient: string;
  stars: number;
  statusTag: "看过" | "在看";
  time: string;
  text: string;
  likes: number;
};

export type Discussion = {
  title: string;
  author: string;
  replies: string;
  date: string;
};

const grad = (from: string, to: string): string => `linear-gradient(135deg, ${from}, ${to})`;

export const SUBJECT_DEMO = {
  kanji: "夏",
  title: "夏日终幕的我们",
  alt: "夏の終わり、僕らの約束 · Summer's End, Our Promise",
  seasonLabel: "2026 SUMMER",
  tags: ["TV 动画", "原创", "青春", "日常", "治愈", "动画工房"] as const,
  current: 10,
  total: 24,
  schedule: "每周五 24:00 更新 · 2026-07-04 开播",
  score: 8.7,
  rank: 42,
  ratingCount: "1,284",
  currentEp: 7,
  watchedUntil: 6,
  unairedAfter: 10,
  defaultStatus: "watching" as SubjectStatus,
  pvTags: ["正式 PV", "PV 第2弹", "角色 PV・凪", "无字幕 OP", "ED 试听"],
  stats: [
    { key: "wish", label: "想看", count: "1,540", pct: 12.3 },
    { key: "watching", label: "在看", count: "3,210", pct: 25.7 },
    { key: "hold", label: "搁置", count: "986", pct: 7.9 },
    { key: "done", label: "看过", count: "5,902", pct: 47.3 },
    { key: "drop", label: "抛弃", count: "842", pct: 6.7 }
  ] satisfies SubjectStat[],
  synopsis: [
    "升入高三的那个夏天，转学生・凪与青梅竹马・栞、还有总是独来独往的天文部部长・遥，因为一场偶然的烟火大会再次相遇。为了完成三年前那个未能实现的约定，她们决定在毕业前一起做一件「永远不会忘记的事」。蝉鸣、海风、深夜的便利店，还有逐渐说不出口的心事——这是一部关于离别、成长，以及「如何好好告别」的青春群像剧。",
    "故事发生在一个海风咸涩的南方小镇。三年前，凪因家庭原因突然转学离开，与栞不告而别。如今她回到这座小镇，却发现一切早已物是人非。天文部面临废部危机，遥独自守着陈旧的天文望远镜，观测着永远无法抵达的星辰。三人因一场意外的烟火大会重聚，决定在高中最后的夏天完成一个未竟的约定——拍摄一部属于自己的独立电影。",
    "随着拍摄的推进，那些被埋藏的秘密逐渐浮出水面。凪当初离开的真正原因，栞这三年来未曾寄出的信件，以及遥与星空之间不为人知的牵绊。在蝉鸣最盛的八月，她们必须面对自己内心最真实的声音。",
    "本作以细腻的笔触描绘了青春期特有的敏感与脆弱，同时也展现了友情在面对时间与距离时的坚韧。每一话都以一种夏日意象为主题——花火、线香、风铃、西瓜、浴衣、台风——构建出一幅完整而动人的夏日画卷。"
  ],
  voiceActors: [
    { kanji: "凪", gradient: grad("#9be7c4", "#3aa17e"), name: "凪", role: "主角 · 高桥 李依" },
    { kanji: "栞", gradient: grad("#c0a8ff", "#7d5fe0"), name: "栞", role: "主角 · 早见 沙织" },
    { kanji: "遥", gradient: grad("#86c5ff", "#3f74c4"), name: "遥", role: "主角 · 佐仓 绫音" },
    { kanji: "海", gradient: grad("#ffb7b2", "#e66767"), name: "海斗", role: "配角 · 内山 昂辉" },
    { kanji: "千", gradient: grad("#ffd6e0", "#f48fb1"), name: "千景", role: "配角 · 水濑 祈" }
  ] satisfies VoiceActor[],
  staff: [
    { initial: "监", gradient: grad("#b6a4f0", "#6aa6f0"), name: "水濑 凉介", role: "监督" },
    { initial: "脚", gradient: grad("#ffb3c7", "#ff6b9d"), name: "花泽 美咲", role: "系列构成" },
    { initial: "人", gradient: grad("#ffcc80", "#ff9800"), name: "田中 将贺", role: "角色设计" },
    { initial: "音", gradient: grad("#ffd56b", "#ff7a5b"), name: "梶浦 由记", role: "音乐" },
    { initial: "美", gradient: grad("#b2dfdb", "#4db6ac"), name: "筱原 睦美", role: "美术监督" },
    { initial: "社", gradient: grad("#a9c7ff", "#6a6ae0"), name: "动画工房", role: "动画制作" }
  ] satisfies StaffMember[],
  comments: [
    {
      name: "宅宅鸿",
      initial: "宅",
      gradient: grad("#ffb3c7", "#ff6b9d"),
      stars: 5,
      statusTag: "看过",
      time: "21h 23m ago",
      text: "key社の世界第一可爱！这季作画稳得离谱，每一帧都能当壁纸。",
      likes: 42
    },
    {
      name: "012606",
      initial: "0",
      gradient: grad("#86c5ff", "#3f74c4"),
      stars: 4,
      statusTag: "在看",
      time: "22h 1m ago",
      text: "EP07 海边那段的演出真的绝了，BGM 一起的时候直接破防。冈崎线之后让刚开始工作的我看了感慨万千，别失去真正重要的东西。",
      likes: 18
    },
    {
      name: "Mi",
      initial: "M",
      gradient: grad("#c0a8ff", "#7d5fe0"),
      stars: 5,
      statusTag: "在看",
      time: "22h 29m ago",
      text: "请用眼泪付款。",
      likes: 7
    },
    {
      name: "SP_ZZH",
      initial: "S",
      gradient: grad("#9be7c4", "#3aa17e"),
      stars: 3,
      statusTag: "在看",
      time: "1d 8h ago",
      text: "原创动画能写成这样不容易，就是中段节奏稍微拖了点，希望最后几话能收得漂亮。",
      likes: 3
    },
    {
      name: "晴海蓝",
      initial: "晴",
      gradient: grad("#ffd56b", "#ff7a5b"),
      stars: 5,
      statusTag: "看过",
      time: "2026-06-18 23:41",
      text: "「我也很没用，但是两个人在一起的话就会变得更加坚强」——这一句直接封神。",
      likes: 29
    }
  ] satisfies SubjectComment[],
  discussions: [
    { title: "难以理解的误解与批评", author: "愿世长安", replies: "10 replies", date: "2026-03-21" },
    { title: '浅谈大家心目中"神作"的槽点', author: "饿龙ou", replies: "82 replies", date: "2026-03-14" },
    {
      title: "（真的不要只看我标题啊！）第二季作画的一点疑问",
      author: "泽渡真琴",
      replies: "249 replies",
      date: "2026-05-02"
    },
    {
      title: "【转载】全世界评分最高动画 TOP100！",
      author: "飞天精灵鼠",
      replies: "61 replies",
      date: "2026-04-28"
    },
    { title: "我说10话率高于50%的都是刷分刷上来的", author: "韩谕", replies: "10 replies", date: "2026-06-09" }
  ] satisfies Discussion[]
};

export type SubjectEpisode = { n: number; watched: boolean; current: boolean; unaired: boolean };

export function buildEpisodes(): SubjectEpisode[] {
  return Array.from({ length: SUBJECT_DEMO.total }, (_, i) => {
    const n = i + 1;
    return {
      n,
      watched: n <= SUBJECT_DEMO.watchedUntil,
      current: n === SUBJECT_DEMO.currentEp,
      unaired: n > SUBJECT_DEMO.unairedAfter
    };
  });
}

export const RATE_LABELS: Record<number, string> = {
  1: "不忍直视（请谨慎评价）",
  2: "很差",
  3: "差",
  4: "较差",
  5: "不过不失",
  6: "还行",
  7: "推荐",
  8: "力荐",
  9: "神作",
  10: "超神作（请谨慎评价）"
};
