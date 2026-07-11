export type RssItem = {
  title: string;
  link: string;
  publishedAt: string | null;
  enclosureUrl: string;
  enclosureLength: number | null;
  enclosureType: string | null;
};

const maxRssItems = 500;

export function parseRssItems(xml: string): RssItem[] {
  if (!/<rss(?:\s|>)/i.test(xml) || !/<channel(?:\s|>)/i.test(xml)) {
    throw new Error("响应不是有效的 RSS 2.0 文档。");
  }

  const itemBlocks = extractElementBlocks(xml, "item", maxRssItems);
  return itemBlocks.flatMap((block) => {
    const title = readElementText(block, "title").trim();
    const link = readElementText(block, "link").trim();
    const publishedAt =
      readElementText(block, "pubDate").trim() ||
      readElementText(block, "torrent:pubDate").trim() ||
      null;
    const enclosureTag = readOpeningTag(block, "enclosure");
    const enclosureUrl = readAttribute(enclosureTag, "url").trim();
    if (!title || !link || !enclosureUrl) {
      return [];
    }

    const rawLength = Number(readAttribute(enclosureTag, "length"));
    return [
      {
        title,
        link,
        publishedAt,
        enclosureUrl,
        enclosureLength: Number.isSafeInteger(rawLength) && rawLength > 0 ? rawLength : null,
        enclosureType: readAttribute(enclosureTag, "type").trim() || null
      }
    ];
  });
}

function extractElementBlocks(xml: string, tagName: string, limit: number): string[] {
  const lower = xml.toLowerCase();
  const openPrefix = `<${tagName.toLowerCase()}`;
  const closeTag = `</${tagName.toLowerCase()}>`;
  const blocks: string[] = [];
  let cursor = 0;

  while (blocks.length < limit) {
    const start = lower.indexOf(openPrefix, cursor);
    if (start < 0) {
      break;
    }
    const openEnd = lower.indexOf(">", start + openPrefix.length);
    const end = openEnd < 0 ? -1 : lower.indexOf(closeTag, openEnd + 1);
    if (openEnd < 0 || end < 0) {
      throw new Error(`RSS <${tagName}> 元素没有正确闭合。`);
    }
    blocks.push(xml.slice(openEnd + 1, end));
    cursor = end + closeTag.length;
  }

  return blocks;
}

function readElementText(block: string, tagName: string): string {
  const lower = block.toLowerCase();
  const openPrefix = `<${tagName.toLowerCase()}`;
  const start = lower.indexOf(openPrefix);
  if (start < 0) {
    return "";
  }
  const openEnd = lower.indexOf(">", start + openPrefix.length);
  const end = openEnd < 0 ? -1 : lower.indexOf(`</${tagName.toLowerCase()}>`, openEnd + 1);
  if (openEnd < 0 || end < 0) {
    return "";
  }
  return decodeXmlText(block.slice(openEnd + 1, end));
}

function readOpeningTag(block: string, tagName: string): string {
  const lower = block.toLowerCase();
  const start = lower.indexOf(`<${tagName.toLowerCase()}`);
  const end = start < 0 ? -1 : lower.indexOf(">", start + tagName.length + 1);
  return start >= 0 && end >= 0 ? block.slice(start, end + 1) : "";
}

function readAttribute(tag: string, attributeName: string): string {
  const pattern = new RegExp(`(?:^|\\s)${attributeName}\\s*=\\s*(["'])([\\s\\S]*?)\\1`, "i");
  const match = pattern.exec(tag);
  return match ? decodeXmlText(match[2] ?? "") : "";
}

function decodeXmlText(value: string): string {
  const unwrapped = value.trim().replace(/^<!\[CDATA\[([\s\S]*)\]\]>$/i, "$1");
  return unwrapped.replace(/&(#x[\da-f]+|#\d+|amp|lt|gt|quot|apos);/gi, (entity, name: string) => {
    const normalized = name.toLowerCase();
    if (normalized === "amp") return "&";
    if (normalized === "lt") return "<";
    if (normalized === "gt") return ">";
    if (normalized === "quot") return '"';
    if (normalized === "apos") return "'";
    const codePoint = normalized.startsWith("#x")
      ? Number.parseInt(normalized.slice(2), 16)
      : Number.parseInt(normalized.slice(1), 10);
    return Number.isSafeInteger(codePoint) ? String.fromCodePoint(codePoint) : entity;
  });
}
