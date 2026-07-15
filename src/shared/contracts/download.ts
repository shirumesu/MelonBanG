export type TorrentInput =
  | {
      kind: "magnet";
      uri: string;
    }
  | {
      kind: "torrentFile";
      name: string;
      bytes: Uint8Array;
    };

export type DownloadStatus =
  | "queued"
  | "metadata"
  | "downloading"
  | "paused"
  | "ready"
  | "completed"
  | "failed"
  | "removed";

export type DownloadFileView = {
  id: string;
  downloadId: string;
  path: string;
  name: string;
  sizeBytes: number;
  mediaKind: "video" | "subtitle" | "other";
  priority: number;
  progress: number;
  createdAt: string;
  updatedAt: string;
};

export type DownloadTaskView = {
  id: string;
  subjectId: number | null;
  episodeId: number | null;
  title: string;
  status: DownloadStatus;
  progress: number;
  downloadedBytes: number;
  totalBytes: number | null;
  downloadSpeedBytesPerSecond: number;
  uploadSpeedBytesPerSecond: number;
  peerCount: number;
  etaSeconds: number | null;
  selectedFileId: string | null;
  errorMessage: string | null;
  previewImageUrl: string | null;
  previewSourceName: string | null;
  previewSourceUrl: string | null;
  createdAt: string;
  updatedAt: string;
};

export type DownloadEpisodeContext = {
  subjectId: number;
  episodeId: number;
};

export type DownloadSnapshot = {
  tasks: DownloadTaskView[];
  files: DownloadFileView[];
};

export interface DownloadBridge {
  create(input: TorrentInput): Promise<DownloadTaskView>;
  list(): Promise<DownloadSnapshot>;
  pause(downloadId: string): Promise<DownloadTaskView>;
  resume(downloadId: string): Promise<DownloadTaskView>;
  remove(downloadId: string): Promise<void>;
  onUpdate(callback: (snapshot: DownloadSnapshot) => void): () => void;
}
