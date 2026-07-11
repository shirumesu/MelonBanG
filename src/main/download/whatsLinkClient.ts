import type { TorrentInput } from "../../shared/contracts/download";

const whatsLinkApiUrl = "https://whatslink.info/api/v1/link";
const whatsLinkSourceUrl = "https://whatslink.info/";
const requestTimeoutMs = 8000;
const previewImageTimeoutMs = 12_000;
const maximumPreviewImageBytes = 2 * 1024 * 1024;
const supportedPreviewImageTypes = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);

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

      const preview = parseWhatsLinkResponse(await response.json());
      if (!preview?.imageUrl) {
        return preview;
      }

      const cachedImageUrl = await fetchPreviewImageDataUrl(preview.imageUrl);
      return {
        ...preview,
        imageUrl: cachedImageUrl ?? preview.imageUrl
      };
    } catch {
      return null;
    } finally {
      clearTimeout(timeout);
    }
  }
}

async function fetchPreviewImageDataUrl(imageUrl: string): Promise<string | null> {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), previewImageTimeoutMs);
    try {
      const response = await fetch(imageUrl, { signal: controller.signal });
      const contentType = response.headers.get("content-type")?.split(";", 1)[0]?.trim();
      const contentLength = Number(response.headers.get("content-length"));
      if (
        !response.ok ||
        !contentType ||
        !supportedPreviewImageTypes.has(contentType) ||
        (Number.isFinite(contentLength) && contentLength > maximumPreviewImageBytes)
      ) {
        continue;
      }

      const bytes = Buffer.from(await response.arrayBuffer());
      if (!bytes.length || bytes.length > maximumPreviewImageBytes) {
        return null;
      }
      return `data:${contentType};base64,${bytes.toString("base64")}`;
    } catch {
      // WhatsLink image delivery is occasionally transient; retry once before using the remote URL.
    } finally {
      clearTimeout(timeout);
    }
  }

  return null;
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
