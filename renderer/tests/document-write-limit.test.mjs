import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import * as nodeModule from 'node:module';
import vm from 'node:vm';

// Exercise the real write path while replacing the device-only file APIs with an in-memory file.
function createFile(initial) {
  let bytes = new TextEncoder().encode(initial);
  let cursor = 0;
  const fileIo = {
    OpenMode: { READ_ONLY: 0, READ_WRITE: 1 },
    openSync: () => { cursor = 0; return { fd: 1 }; },
    open: async () => ({ fd: 1 }), stat: async () => ({ mtime: 123456 }), close: async () => {},
    closeSync: () => {}, statSync: () => ({ size: bytes.length }),
    readSync: (_fd, buffer) => {
      const length = Math.min(buffer.byteLength, bytes.length - cursor);
      new Uint8Array(buffer).set(bytes.subarray(cursor, cursor + length));
      cursor += length;
      return length;
    },
    writeSync: (_fd, buffer) => {
      const incoming = new Uint8Array(buffer);
      const result = new Uint8Array(Math.max(bytes.length, cursor + incoming.length));
      result.set(bytes); result.set(incoming, cursor); bytes = result; cursor += incoming.length;
      return incoming.length;
    },
    truncateSync: (_fd, size) => { bytes = bytes.slice(0, size); }, fsyncSync: () => {}
  };
  const cryptoFramework = { createMd: () => {
    const hash = createHash('sha256');
    return { updateSync: ({ data }) => hash.update(data), digestSync: () => ({ data: hash.digest() }) };
  } };
  const TextEncoding = {
    encode: text => ({ bytes: new TextEncoder().encode(text), newline: '\n', lineEndings: '' }),
    decode: value => ({ text: new TextDecoder().decode(value), encoding: 'utf-8', hasBom: false })
  };
  const filename = new URL('../../entry/src/main/ets/storage/DocumentFiles.ets', import.meta.url);
  const source = readFileSync(filename, 'utf8').replace(/^import .*;\s*$/gm, '').replace(/^export /gm, '');
  const context = { fileIo, TextEncoding, cryptoFramework,
    fileShare: { OperationMode: { READ_MODE: 1, WRITE_MODE: 2 },
      checkPersistentPermission: async () => [false] }, Uint8Array, ArrayBuffer, Error,
    $r: (name) => name,
    AppText: { text: (name) => name === 'app.string.save_too_large' || name === 'app.string.too_large' ?
      'Documents cannot exceed 8 MiB' : String(name) } };
  return { files: vm.runInNewContext(`${nodeModule.stripTypeScriptTypes(source)}\nDocumentFiles`, context),
    content: () => Buffer.from(bytes).toString(), size: () => bytes.length };
}

const needsStripper = { skip: typeof nodeModule.stripTypeScriptTypes !== 'function' };
test('rejects oversized encoded content before altering an existing file', needsStripper, () => {
  const original = 'original';
  const file = createFile(original);
  const info = { uri: 'file://example.txt', writable: true, newline: '\n', lineEndings: '',
    fingerprint: createHash('sha256').update(original).digest('hex') };
  assert.throws(() => file.files.write(info, 'x'.repeat(8 * 1024 * 1024 + 1), true), /8 MiB/);
  assert.equal(file.content(), original);
});

test('uses accessible file modification time even when no persistent grant exists', needsStripper, async () => {
  const file = createFile('sample');
  assert.equal(await file.files.recentModifiedAt('file://example.txt'), 123456);
});

test('allows exactly 8 MiB and rejects larger UTF-8 output for save as', needsStripper, () => {
  const file = createFile('original');
  const info = { uri: 'file://copy.txt', writable: true, newline: '\n', lineEndings: '', fingerprint: '' };
  file.files.write(info, 'x'.repeat(8 * 1024 * 1024), false);
  assert.equal(file.size(), 8 * 1024 * 1024);
  assert.throws(() => file.files.write(info, 'x'.repeat(8 * 1024 * 1024 - 1) + '中', false), /8 MiB/);
  assert.equal(file.size(), 8 * 1024 * 1024);
});
