import type { TorrentInput } from "../../shared/contracts/download";

const whatsLinkApiUrl = "https://whatslink.info/api/v1/link";
const whatsLinkSourceUrl = "https://whatslink.info/";
const requestTimeoutMs = 8000;

export type DownloadPreviewMetadata = {
  title?: string;
  totalBytes?: number;
  imageUrl?: string;
  sourceName: "whatslink.info";
  sourceUrl: typeof whatsLinkSourceUrl;
};

export class WhatsLinkClient {
  async getPreview(input: TorrentInput): Promise<DownloadPreviewMetadata | null> {
    if (input.kind !== "magnet") {
      return null;
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), requestTimeoutMs);

    try {
      const requestUrl = new URL(whatsLinkApiUrl);
      requestUrl.searchParams.set("url", input.uri);
      const response = await fetch(requestUrl, {
        headers: {
          accept: "application/json"
        },
        signal: controller.signal
      });

      if (!response.ok) {
        return null;
      }

      return parseWhatsLinkResponse(await response.json());
    } catch {
      return null;
    } finally {
      clearTimeout(timeout);
    }
  }
}

export function parseWhatsLinkResponse(value: unknown): DownloadPreviewMetadata | null {
  if (!isRecord(value)) {
    return null;
  }

  if (typeof value.error === "string" && value.error.trim()) {
    return null;
  }

  const title = typeof value.name === "string" && value.name.trim() ? value.name.trim() : undefined;
  const totalBytes =
    typeof value.size === "number" && Number.isFinite(value.size) && value.size > 0
      ? Math.round(value.size)
      : undefined;
  const imageUrl = getFirstScreenshotUrl(value.screenshots);

  if (!title && !totalBytes && !imageUrl) {
    return null;
  }

  return {
    title,
    totalBytes,
    imageUrl,
    sourceName: "whatslink.info",
    sourceUrl: whatsLinkSourceUrl
  };
}

function getFirstScreenshotUrl(value: unknown): string | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }

  for (const item of value) {
    if (!isRecord(item) || typeof item.screenshot !== "string") {
      continue;
    }

    const screenshot = item.screenshot.trim();
    if (isHttpUrl(screenshot)) {
      return screenshot;
    }
  }

  return undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isHttpUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "https:" || url.protocol === "http:";
  } catch {
    return false;
  }
}
