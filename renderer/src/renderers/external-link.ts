/** Absolute http(s) URL without credentials. Empty when the address must stay inside the preview. */
export function safeExternalUrl(raw: string): string {
  if (typeof raw !== 'string') return '';
  const trimmed = raw.trim();
  if (trimmed.length === 0) return '';
  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch {
    return '';
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return '';
  if (parsed.username !== '' || parsed.password !== '') return '';
  if (parsed.hostname === '') return '';
  return parsed.href;
}
