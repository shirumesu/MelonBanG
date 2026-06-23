declare module "webtorrent" {
  import type { Readable } from "node:stream";

  export type TorrentFile = {
    name: string;
    path: string;
    length: number;
    downloaded: number;
    progress: number;
    select(priority?: number): void;
    deselect(): void;
    createReadStream(options?: { start?: number; end?: number }): Readable;
  };

  export type Torrent = {
    infoHash: string;
    magnetURI: string;
    name: string;
    files: TorrentFile[];
    progress: number;
    downloaded: number;
    length: number;
    downloadSpeed: number;
    uploadSpeed: number;
    numPeers: number;
    done: boolean;
    on(event: "metadata" | "done" | "download", callback: () => void): Torrent;
    on(event: "error" | "warning", callback: (error: Error) => void): Torrent;
    pause(): void;
    resume(): void;
    destroy(callback?: (error?: Error) => void): void;
  };

  export default class WebTorrent {
    constructor(options?: Record<string, unknown>);
    add(
      torrentId: string | Uint8Array,
      options?: Record<string, unknown>,
      onTorrent?: (torrent: Torrent) => void
    ): Torrent;
    remove(
      torrentId: string | Torrent,
      options?: Record<string, unknown>,
      callback?: (error?: Error) => void
    ): void;
    destroy(callback?: (error?: Error) => void): void;
  }
}
