import test from 'node:test';
import assert from 'node:assert/strict';
import { encodePreviewLinkRequest } from '../src/preview-link-message.ts';

test('serializes a checked web link with the current preview identity', () => {
  const encoded = encodePreviewLinkRequest('https://example.com/p?a=1&b=2', 4, 2);
  assert.equal(encoded, JSON.stringify({
    kind: 'open-link', url: 'https://example.com/p?a=1&b=2', revision: 4, documentId: 2
  }));
});

test('rejects an unsafe address or a non-integer preview identity', () => {
  assert.equal(encodePreviewLinkRequest('javascript:alert(1)', 1, 1), null);
  assert.equal(encodePreviewLinkRequest('https://example.com', 1.5, 1), null);
  assert.equal(encodePreviewLinkRequest('https://example.com', -1, 1), null);
  assert.equal(encodePreviewLinkRequest('https://example.com', 1, Number.NaN), null);
});
