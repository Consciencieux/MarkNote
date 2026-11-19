import { safeExternalUrl } from './renderers/external-link.ts';

export interface PreviewLinkRequest {
  kind: 'open-link';
  url: string;
  revision: number;
  documentId: number;
}

/** JSON for the existing preview message port, or null when the click must be ignored. */
export function encodePreviewLinkRequest(url: string, revision: number, documentId: number): string | null {
  const safe = safeExternalUrl(url);
  if (!safe) return null;
  if (!Number.isInteger(revision) || revision < 0) return null;
  if (!Number.isInteger(documentId) || documentId < 0) return null;
  const request: PreviewLinkRequest = { kind: 'open-link', url: safe, revision, documentId };
  return JSON.stringify(request);
}
