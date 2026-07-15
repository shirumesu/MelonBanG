import type { DownloadTaskView } from "./download";

export type SourceSearchInput = {
  subjectId: number;
  episodeId?: number;
  keyword: string;
  keywords?: string[];
};

export type SourceCandidateView = {
  candidateId: string;
  providerId: string;
  providerName: string;
  providerItemId: string;
  title: string;
  detailUrl: string;
  publishedAt: string | null;
  sizeBytes: number | null;
  downloadKind: "magnet" | "torrentFile";
};

export type SourceProviderDiagnostic = {
  providerId: string;
  providerName: string;
  status: "ok" | "error";
  resultCount: number;
  message?: string;
};

export type SourceSearchResult = {
  candidates: SourceCandidateView[];
  providers: SourceProviderDiagnostic[];
  searchedAt: string;
};

export type SourceEnqueueInput = {
  candidateId: string;
};

export interface SourceBridge {
  search(input: SourceSearchInput): Promise<SourceSearchResult>;
  enqueue(input: SourceEnqueueInput): Promise<DownloadTaskView>;
}
