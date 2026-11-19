import { createHash } from 'node:crypto';
import { loadArktsModules } from './arkts-loader.mjs';

/**
 * In-memory fileIo and SHA-256 stand-ins for DocumentFiles.
 * hold/release pause one operation without sleeping. failNext rejects that operation once.
 */
export function createDocumentFileHarness(initial, options = {}) {
  let bytes = typeof initial === 'string' ? new TextEncoder().encode(initial) : Uint8Array.from(initial);
  let cursor = 0;
  const calls = [];
  const gates = new Map();
  let fail = '';
  const chunk = options.chunk ?? Number.MAX_SAFE_INTEGER;
  const harness = {
    calls,
    content: () => Buffer.from(bytes).toString(),
    size: () => bytes.length,
    hold(operation) {
      let releaseGate = () => {};
      const promise = new Promise((resolve) => { releaseGate = resolve; });
      gates.set(operation, { promise, releaseGate });
    },
    release(operation) {
      const gate = gates.get(operation);
      if (!gate) return;
      gates.delete(operation);
      gate.releaseGate();
    },
    failNext(operation) { fail = operation; },
    fileIo: null,
    cryptoFramework: null
  };
  async function gate(operation) {
    calls.push(operation);
    if (fail === operation) {
      fail = '';
      throw new Error(`${operation} failed`);
    }
    const pending = gates.get(operation);
    if (pending) await pending.promise;
  }
  harness.fileIo = {
    OpenMode: { READ_ONLY: 0, READ_WRITE: 1, CREATE: 64, WRITE_ONLY: 2 },
    open: async () => { await gate('open'); cursor = 0; return { fd: 1, name: options.name ?? 'example.md' }; },
    close: async () => { await gate('close'); },
    stat: async () => { await gate('stat'); return { size: bytes.length, mtime: options.mtime ?? 123456 }; },
    read: async (_fd, buffer) => {
      await gate('read');
      const view = new Uint8Array(buffer);
      const length = Math.min(view.byteLength, Math.max(0, bytes.length - cursor), chunk);
      if (length <= 0) return 0;
      view.set(bytes.subarray(cursor, cursor + length));
      cursor += length;
      return length;
    },
    write: async (_fd, buffer) => {
      await gate('write');
      if (options.stallWrite) return 0;
      const incoming = new Uint8Array(buffer);
      const length = Math.min(incoming.byteLength, chunk);
      if (length <= 0) return 0;
      const result = new Uint8Array(Math.max(bytes.length, cursor + length));
      result.set(bytes);
      result.set(incoming.subarray(0, length), cursor);
      bytes = result;
      cursor += length;
      return length;
    },
    truncate: async (_fd, size) => {
      await gate('truncate');
      bytes = bytes.slice(0, size);
      if (cursor > bytes.length) cursor = bytes.length;
    },
    fsync: async () => { await gate('fsync'); },
    rename: async () => { await gate('rename'); },
    unlink: async () => { await gate('unlink'); },
    readText: async () => { await gate('readText'); return new TextDecoder().decode(bytes); },
    mkdir: async () => { await gate('mkdir'); }
  };
  harness.cryptoFramework = {
    createMd: () => {
      const hash = createHash('sha256');
      return {
        update: async ({ data }) => { hash.update(data); },
        digest: async () => ({ data: hash.digest() })
      };
    }
  };
  return harness;
}

const textUtil = {
  TextEncoder: { create: () => ({ encodeInto: (value) => new TextEncoder().encode(value) }) },
  TextDecoder: {
    create: (encoding) => ({
      decodeToString: (value) => new TextDecoder(encoding === 'utf-8' ? 'utf-8' : encoding, { fatal: true }).decode(value)
    })
  }
};

/** Load the real DocumentFiles implementation against a harness. */
export function loadDocumentFiles(harness, extras = {}) {
  return loadArktsModules(
    ['model/Document.ets', 'document/TextEncoding.ets', 'storage/DocumentFiles.ets'],
    'DocumentFiles',
    {
      fileIo: harness.fileIo,
      cryptoFramework: harness.cryptoFramework,
      util: textUtil,
      fileShare: extras.fileShare ?? {
        OperationMode: { READ_MODE: 1, WRITE_MODE: 2 },
        checkPersistentPermission: async () => [false],
        activatePermission: async () => {},
        persistPermission: async () => {},
        revokePermission: async () => {}
      },
      fileManagerService: extras.fileManagerService ?? { deleteToTrash: async () => {} },
      FormatRegistry: { openFilters: () => [], saveChoices: () => [] },
      AppText: {
        text: (name) => name === 'app.string.save_too_large' || name === 'app.string.too_large' ?
          'Documents cannot exceed 8 MiB' : String(name)
      },
      $r: (name) => name,
      userNotice: (message) => {
        const error = new Error(message);
        error.name = 'UserNotice';
        return error;
      }
    }
  );
}
