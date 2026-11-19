const MAX_EXTERNAL_URL_LENGTH = 2048;

/** Absolute http(s) URL without credentials. Empty when the address must stay inside the preview. */
export function safeExternalUrl(raw: string): string {
  if (typeof raw !== 'string') return '';
  const trimmed = raw.trim();
  if (trimmed.length === 0 || trimmed.length > MAX_EXTERNAL_URL_LENGTH) return '';
  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch {
    return '';
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return '';
  if (parsed.username !== '' || parsed.password !== '') return '';
  if (parsed.hostname === '') return '';
  if (parsed.href.length > MAX_EXTERNAL_URL_LENGTH) return '';
  return parsed.href;
}
