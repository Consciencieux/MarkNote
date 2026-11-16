import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  LICENSE_CHUNK_CHARS, cachedLicenseText, loadLicenseText, splitLicenseText
} from '../../entry/src/main/ets/pages/LicenseText.ts';

test('splitting keeps every character and prefers paragraph breaks', () => {
  const text = `${'甲'.repeat(100)}\n\n${'乙'.repeat(LICENSE_CHUNK_CHARS + 50)}`;
  const chunks = splitLicenseText(text);
  assert.equal(chunks.join(''), text);
  assert.equal(chunks[0], `${'甲'.repeat(100)}\n\n`);
  assert.ok(chunks.length > 2);
  assert.ok(chunks.every((chunk) => chunk.length > 0 && chunk.length <= LICENSE_CHUNK_CHARS));
});

test('a short license stays in one chunk', () => {
  assert.deepEqual(splitLicenseText(''), []);
  assert.deepEqual(splitLicenseText('MIT'), ['MIT']);
});

test('the packaged third-party notices can be rebuilt from their chunks', () => {
  const text = readFileSync(
    new URL('../../entry/src/main/resources/rawfile/licenses/THIRD_PARTY_NOTICES.txt', import.meta.url),
    'utf8');
  const chunks = splitLicenseText(text);
  assert.equal(chunks.join(''), text);
  assert.ok(chunks.length > 1);
  assert.ok(chunks.every((chunk) => chunk.length > 0 && chunk.length <= LICENSE_CHUNK_CHARS));
});

test('a failed read is not cached and a later read can succeed', async () => {
  let calls = 0;
  const key = 'license-text-test-retry';
  await assert.rejects(loadLicenseText(key, async () => {
    calls += 1;
    throw new Error('unreadable');
  }));
  assert.equal(cachedLicenseText(key), '');
  const text = await loadLicenseText(key, async () => {
    calls += 1;
    return 'ready';
  });
  assert.equal(text, 'ready');
  assert.equal(await loadLicenseText(key, async () => 'again'), 'ready');
  assert.equal(calls, 2);
});
