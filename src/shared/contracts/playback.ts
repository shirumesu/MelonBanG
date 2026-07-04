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

export type PlaybackSourceView = {
  kind: PlaybackSourceKind;
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
  renderMode: "native-vtt" | "unsupported";
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
};

export type StartPlaybackFromDownloadInput = {
  downloadId: string;
  fileId?: string;
};

export type BindEpisodeMediaInput = {
  subjectId: number;
  episodeId: number;
  downloadId: string;
  fileId?: string;
};

export type EpisodeMediaBindingInput = {
  subjectId: number;
  episodeId: number;
};

export type ClearEpisodeMediaBindingInput = {
  bindingId: string;
};

export type StartEpisodePlaybackInput = {
  subjectId: number;
  episodeId: number;
};

export type MediaBindingView = {
  id: string;
  subjectId: number;
  episodeId: number;
  downloadId: string;
  fileId: string;
  fileName: string | null;
  downloadTitle: string | null;
  available: boolean;
  createdAt: string;
  updatedAt: string;
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
  paused: boolean;
  ended: boolean;
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
  positionSeconds: number;
  durationSeconds: number | null;
  errorMessage: string | null;
  createdAt: string;
  updatedAt: string;
};

export interface PlaybackBridge {
  startFromDownload(input: StartPlaybackFromDownloadInput): Promise<PlaybackSessionView>;
  bindEpisodeMedia(input: BindEpisodeMediaInput): Promise<MediaBindingView>;
  getEpisodeMediaBinding(input: EpisodeMediaBindingInput): Promise<MediaBindingView | null>;
  clearEpisodeMediaBinding(input: ClearEpisodeMediaBindingInput): Promise<void>;
  startEpisode(input: StartEpisodePlaybackInput): Promise<PlaybackSessionView>;
  getEpisodeProgress(input: EpisodeMediaBindingInput): Promise<PlaybackProgressSnapshot | null>;
  getSession(): Promise<PlaybackSessionView | null>;
  updateProgress(input: PlaybackProgressInput): Promise<PlaybackSessionView>;
  stop(sessionId: string): Promise<void>;
  onEvent(callback: (session: PlaybackSessionView | null) => void): () => void;
}
