import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createDocumentFileHarness, loadDocumentFiles } from './helpers/document-files.mjs';

function documentFiles(content, trash) {
  const harness = createDocumentFileHarness(content);
  const files = loadDocumentFiles(harness, { fileManagerService: { deleteToTrash: trash } });
  return files;
}

function info(content) {
  return {
    uri: 'file://docs/example.md', writable: true,
    fingerprint: createHash('sha256').update(content).digest('hex')
  };
}

test('moves the unchanged authorized file to the system trash', async () => {
  const calls = [];
  const files = documentFiles('original', async (uri) => { calls.push(uri); });
  await files.moveToTrash(info('original'));
  assert.deepEqual(calls, ['file://docs/example.md']);
});

test('does not delete a changed or read-only file', async () => {
  const calls = [];
  const files = documentFiles('changed', async (uri) => { calls.push(uri); });
  await assert.rejects(files.moveToTrash(info('original')));
  await assert.rejects(files.moveToTrash({ ...info('changed'), writable: false }));
  await assert.rejects(files.moveToTrash({ ...info('changed'), uri: '' }));
  assert.deepEqual(calls, []);
});

test('propagates a rejected trash operation without retrying permanent deletion', async () => {
  let calls = 0;
  const files = documentFiles('original', async () => { calls++; throw new Error('not permitted'); });
  await assert.rejects(files.moveToTrash(info('original')), /not permitted/);
  assert.equal(calls, 1);
});
