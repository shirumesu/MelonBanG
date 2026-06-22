export function parseAiringTimestamp(value: string | undefined): number {
  if (!value) {
    return Number.NaN;
  }

  const shanghaiMatch = /^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2})$/.exec(value);
  if (shanghaiMatch) {
    return Date.parse(`${shanghaiMatch[1]}T${shanghaiMatch[2]}:00+08:00`);
  }

  return Date.parse(value);
}
