import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import * as nodeModule from 'node:module';
import vm from 'node:vm';

// Run the real ArkTS file logic with the platform file and trash services isolated.
function documentFiles(content, trash) {
  const bytes = new TextEncoder().encode(content);
  const fileIo = {
    OpenMode: { READ_ONLY: 0 },
    openSync: () => ({ fd: 1 }),
    closeSync: () => {},
    statSync: () => ({ size: bytes.length }),
    readSync: (_fd, buffer) => {
      new Uint8Array(buffer).set(bytes);
      return bytes.length;
    }
  };
  const cryptoFramework = {
    createMd: () => {
      const hash = createHash('sha256');
      return {
        updateSync: ({ data }) => hash.update(data),
        digestSync: () => ({ data: hash.digest() })
      };
    }
  };
  const filename = new URL('../../entry/src/main/ets/storage/DocumentFiles.ets', import.meta.url);
  const source = readFileSync(filename, 'utf8')
    .replace(/^import .*;\s*$/gm, '')
    .replace(/^export /gm, '');
  const context = {
    fileIo, fileShare: { OperationMode: { READ_MODE: 1, WRITE_MODE: 2 } },
    cryptoFramework, fileManagerService: { deleteToTrash: trash },
    Uint8Array, ArrayBuffer, Error
  };
  return vm.runInNewContext(`${nodeModule.stripTypeScriptTypes(source)}\nDocumentFiles`, context);
}

const requiresTypeStripper = { skip: typeof nodeModule.stripTypeScriptTypes !== 'function' };

function info(content) {
  return {
    uri: 'file://docs/example.md', writable: true,
    fingerprint: createHash('sha256').update(content).digest('hex')
  };
}

test('moves the unchanged authorized file to the system trash', requiresTypeStripper, async () => {
  const calls = [];
  const files = documentFiles('original', async (uri) => { calls.push(uri); });
  await files.moveToTrash(info('original'));
  assert.deepEqual(calls, ['file://docs/example.md']);
});

test('does not delete a changed or read-only file', requiresTypeStripper, async () => {
  const calls = [];
  const files = documentFiles('changed', async (uri) => { calls.push(uri); });
  await assert.rejects(files.moveToTrash(info('original')));
  await assert.rejects(files.moveToTrash({ ...info('changed'), writable: false }));
  await assert.rejects(files.moveToTrash({ ...info('changed'), uri: '' }));
  assert.deepEqual(calls, []);
});

test('propagates a rejected trash operation without retrying permanent deletion', requiresTypeStripper, async () => {
  let calls = 0;
  const files = documentFiles('original', async () => { calls++; throw new Error('not permitted'); });
  await assert.rejects(files.moveToTrash(info('original')), /not permitted/);
  assert.equal(calls, 1);
});
