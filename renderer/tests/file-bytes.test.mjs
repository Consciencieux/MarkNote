import test from 'node:test';
import assert from 'node:assert/strict';
import { createDocumentFileHarness } from './helpers/document-files.mjs';
import { loadArktsModules } from './helpers/arkts-loader.mjs';

function loadWriteAll(harness) {
  return loadArktsModules(['storage/FileBytes.ets'], 'writeAll', {
    fileIo: harness.fileIo,
    userNotice: (message) => {
      const error = new Error(message);
      error.name = 'UserNotice';
      return error;
    }
  });
}

test('writeAll stores every byte when each write is shorter than the buffer', async () => {
  const harness = createDocumentFileHarness('', { chunk: 3 });
  const writeAll = loadWriteAll(harness);
  await writeAll(1, new TextEncoder().encode('abcdefg'), 'interrupted');
  assert.equal(harness.content(), 'abcdefg');
});

test('writeAll fails when a write accepts no bytes', async () => {
  const harness = createDocumentFileHarness('keep', { stallWrite: true });
  const writeAll = loadWriteAll(harness);
  await assert.rejects(writeAll(1, new TextEncoder().encode('next'), 'interrupted'), /interrupted/);
  assert.equal(harness.content(), 'keep');
});
