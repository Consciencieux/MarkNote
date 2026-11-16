/** 一段许可证文本的目标长度。更长的原文在段落或换行处切开，拼接后与原文相同。 */
export const LICENSE_CHUNK_CHARS: number = 4000;

const cachedText: Map<string, string> = new Map();
const pendingText: Map<string, Promise<string>> = new Map();

/**
 * 把许可证原文切成若干段，且 `chunks.join('') === text`。
 * 优先在目标长度前的空行处切开，其次在换行处切开；一段里没有换行时才按长度切开。
 */
export function splitLicenseText(text: string): string[] {
  const chunks: string[] = [];
  let start = 0;
  while (start < text.length) {
    const limit = Math.min(start + LICENSE_CHUNK_CHARS, text.length);
    let end = limit;
    if (limit < text.length) {
      const paragraph = text.lastIndexOf('\n\n', limit);
      const line = text.lastIndexOf('\n', limit);
      if (paragraph > start && paragraph + 2 <= limit) {
        end = paragraph + 2;
      } else if (line > start && line + 1 <= limit) {
        end = line + 1;
      }
    }
    chunks.push(text.slice(start, end));
    start = end;
  }
  return chunks;
}

/** 同一键的全文只读取一次。读取失败不写入缓存，下次进入可以再读。 */
export function loadLicenseText(key: string, read: () => Promise<string>): Promise<string> {
  const cached = cachedText.get(key);
  if (cached !== undefined) {
    return Promise.resolve(cached);
  }
  const pending = pendingText.get(key);
  if (pending !== undefined) {
    return pending;
  }
  const task = (async (): Promise<string> => {
    try {
      const text = await read();
      cachedText.set(key, text);
      return text;
    } finally {
      pendingText.delete(key);
    }
  })();
  pendingText.set(key, task);
  return task;
}

export function cachedLicenseText(key: string): string {
  return cachedText.get(key) ?? '';
}
