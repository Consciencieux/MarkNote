import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createDocumentFileHarness, loadDocumentFiles } from './helpers/document-files.mjs';

function filesFor(initial, options = {}) {
  const harness = createDocumentFileHarness(initial, options);
  return { harness, files: loadDocumentFiles(harness, options.extras) };
}

function info(content, extra = {}) {
  return {
    uri: 'file://example.txt', writable: true, newline: '\n', lineEndings: '', encoding: 'utf-8',
    hasBom: false, formatId: 'plain', name: 'example.txt', persistent: true,
    fingerprint: createHash('sha256').update(content).digest('hex'), ...extra
  };
}

test('rejects oversized encoded content before altering an existing file', async () => {
  const original = 'original';
  const { harness, files } = filesFor(original);
  await assert.rejects(files.write(info(original), 'x'.repeat(8 * 1024 * 1024 + 1), true), /8 MiB/);
  assert.equal(harness.content(), original);
  assert.equal(harness.calls.includes('write'), false);
});

test('uses accessible file modification time even when no persistent grant exists', async () => {
  const { files } = filesFor('sample');
  assert.equal(await files.recentModifiedAt('file://example.txt'), 123456);
});

test('allows exactly 8 MiB and rejects larger UTF-8 output for save as', async () => {
  const { harness, files } = filesFor('original');
  await files.write(info('original', { fingerprint: '' }), 'x'.repeat(8 * 1024 * 1024), false);
  assert.equal(harness.size(), 8 * 1024 * 1024);
  await assert.rejects(files.write(info('original', { fingerprint: '' }), 'x'.repeat(8 * 1024 * 1024 - 1) + '中', false), /8 MiB/);
  assert.equal(harness.size(), 8 * 1024 * 1024);
});

test('reads and writes short chunks until the file is complete', async () => {
  const { files, harness } = filesFor('abcdef', { chunk: 2 });
  const opened = await files.read('file://example.txt');
  assert.equal(opened.text, 'abcdef');
  await files.write(info('abcdef', { fingerprint: opened.info.fingerprint }), 'xyz', false);
  assert.equal(harness.content(), 'xyz');
});

test('a zero-length write fails and still closes the file', async () => {
  const { files, harness } = filesFor('original', { stallWrite: true });
  await assert.rejects(files.write(info('original', { fingerprint: '' }), 'next', false), /write_interrupted/);
  assert.equal(harness.calls.filter((name) => name === 'close').length > 0, true);
});

test('an empty file keeps the empty SHA-256 fingerprint', async () => {
  const { files } = filesFor('');
  const opened = await files.read('file://example.txt');
  assert.equal(opened.info.fingerprint, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
});
