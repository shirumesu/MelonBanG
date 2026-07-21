export type PlaybackStatus =
  | "idle"
  | "preparing"
  | "ready"
  | "playing"
  | "paused"
  | "ended"
  | "stopped"
  | "failed";

export type PlaybackSourceKind = "file" | "hls";
export type PlaybackDeliveryMode = "direct" | "remux" | "transcode";

export type PlaybackSourceView = {
  kind: PlaybackSourceKind;
  deliveryMode: PlaybackDeliveryMode;
  timelineOffsetSeconds: number;
  url: string;
  mimeType: string | null;
  title: string;
};

export type SubtitleTrackView = {
  id: string;
  label: string;
  language: string | null;
  source: "external" | "embedded";
  format: "vtt" | "srt" | "ass" | "ssa" | "unknown";
  renderMode: "native-vtt" | "ass" | "unsupported";
  url: string | null;
  fontUrls: string[];
  default: boolean;
  errorMessage: string | null;
};

export type DanmakuItemView = {
  timeSeconds: number;
  text: string;
  mode: "scroll" | "top" | "bottom";
  color: string | null;
  sourceId?: DanmakuSourceId;
};

export type DanmakuSourceId = "dandanplay" | "bilibili" | "bahamut";

export type DanmakuSourceStatus = "idle" | "loading" | "ready" | "error";

export type DanmakuSourceView = {
  id: DanmakuSourceId;
  label: string;
  enabled: boolean;
  status: DanmakuSourceStatus;
  count: number;
  matchLabel: string | null;
  errorMessage: string | null;
};

export type DanmakuEpisodeSearchInput = {
  sessionId: string;
  anime: string;
};

export type DanmakuEpisodeSearchResult = {
  animeId: number;
  animeTitle: string;
  type: string;
  typeDescription: string | null;
  episodeId: number;
  episodeTitle: string;
};

export type SelectDanmakuEpisodeInput = {
  sessionId: string;
  episodeId: number;
};

export type LoadDanmakuSourceInput = {
  sessionId: string;
  providerId: Exclude<DanmakuSourceId, "dandanplay">;
  locator: string;
};

export type SetDanmakuSourceEnabledInput = {
  sessionId: string;
  providerId: DanmakuSourceId;
  enabled: boolean;
};

export type StartPlaybackFromDownloadInput = {
  downloadId: string;
  fileId?: string;
};

export type EpisodePlaybackInput = {
  subjectId: number;
  episodeId: number;
};

export type PlaybackProgressSnapshot = {
  subjectId: number;
  episodeId: number;
  positionSeconds: number;
  durationSeconds: number | null;
  completed: boolean;
  updatedAt: string;
};

export type PlaybackProgressInput = {
  sessionId: string;
  positionSeconds: number;
  durationSeconds: number | null;
  timelineOffsetSeconds: number;
  paused: boolean;
  ended: boolean;
};

export type SeekPlaybackInput = {
  sessionId: string;
  positionSeconds: number;
};

export type PlaybackSessionView = {
  id: string;
  downloadId: string | null;
  fileId: string | null;
  subjectId: number | null;
  episodeId: number | null;
  title: string;
  status: PlaybackStatus;
  source: PlaybackSourceView | null;
  subtitles: SubtitleTrackView[];
  danmaku: DanmakuItemView[];
  danmakuSources: DanmakuSourceView[];
  positionSeconds: number;
  durationSeconds: number | null;
  errorMessage: string | null;
  createdAt: string;
  updatedAt: string;
};

export interface PlaybackBridge {
  startFromDownload(input: StartPlaybackFromDownloadInput): Promise<PlaybackSessionView>;
  startEpisode(input: EpisodePlaybackInput): Promise<PlaybackSessionView>;
  getEpisodeProgress(input: EpisodePlaybackInput): Promise<PlaybackProgressSnapshot | null>;
  getSession(): Promise<PlaybackSessionView | null>;
  loadDanmaku(sessionId: string): Promise<PlaybackSessionView>;
  searchDanmakuEpisodes(input: DanmakuEpisodeSearchInput): Promise<DanmakuEpisodeSearchResult[]>;
  selectDanmakuEpisode(input: SelectDanmakuEpisodeInput): Promise<PlaybackSessionView>;
  loadDanmakuSource(input: LoadDanmakuSourceInput): Promise<PlaybackSessionView>;
  setDanmakuSourceEnabled(input: SetDanmakuSourceEnabledInput): Promise<PlaybackSessionView>;
  seek(input: SeekPlaybackInput): Promise<PlaybackSessionView>;
  updateProgress(input: PlaybackProgressInput): Promise<PlaybackSessionView>;
  stop(sessionId: string): Promise<void>;
  onEvent(callback: (session: PlaybackSessionView | null) => void): () => void;
}
