import test from 'node:test';
import assert from 'node:assert/strict';
import { loadArktsModules } from './helpers/arkts-loader.mjs';

const formats = {
  markdown: { id: 'markdown', starter: '' },
  plain: { id: 'plain', starter: '' },
  svg: { id: 'svg', starter: '<svg></svg>' }
};
const registry = {
  byId: (id) => formats[id],
  byFilename: (name) => name.endsWith('.md') ? formats.markdown : formats.plain,
  defaultName: (format) => format.id === 'markdown' ? 'a.md' : 'a.txt',
  resolve: (name, _type, unknown) => name.endsWith('.md') ? formats.markdown : unknown ? formats.plain : null
};

async function service(overrides = {}, time = { setTimeout, clearTimeout }) {
  const writes = [];
  const drafts = [];
  const clears = [];
  const recoveryErrors = [];
  let encodings = 0;
  const prepared = { bytes: new Uint8Array([1]), newline: '\n', lineEndings: '' };
  let releaseWrite = null;
  const files = {
    prepare: async () => ({ writable: true, persistent: true }),
    chooseSave: async () => 'file://a.md',
    read: async (uri) => ({
      info: { uri, name: 'a.md', newline: '\n', lineEndings: '', encoding: 'utf-8', hasBom: false,
        fingerprint: 'disk', formatId: 'markdown', writable: true, persistent: true },
      text: 'disk'
    }),
    encodedForWrite: () => {
      encodings++;
      return prepared;
    },
    validateForWrite: () => {},
    moveToTrash: async () => {},
    write: async (info, text, conflict, encoded, onWriteStart) => {
      writes.push({ text, conflict, encoded });
      onWriteStart?.();
      if (overrides.holdWrite) await new Promise((resolve) => { releaseWrite = resolve; });
      if (overrides.failWrite) throw new Error('partial write');
      return { info: { ...info, fingerprint: 'written' }, text };
    },
    ...overrides.files
  };
  const local = {
    writeDraft: async (_context, draft) => {
      if (overrides.failDraft) throw new Error('disk full');
      drafts.push({ ...draft });
    },
    clearDraft: async () => { clears.push('clear'); },
    ...overrides.local
  };
  const api = loadArktsModules(
    ['model/Document.ets', 'document/DraftCoordinator.ets', 'document/DocumentService.ets'],
    '({ DocumentService, DocumentInfo })',
    {
      setTimeout: time.setTimeout, clearTimeout: time.clearTimeout, DocumentFiles: files, LocalState: local, FormatRegistry: registry,
      AppText: { text: (name) => name }, $r: (name) => name,
      userNotice: (message) => { const error = new Error(message); error.name = 'UserNotice'; return error; }
    }
  );
  api.DocumentService.initializeRecovery({});
  const info = new api.DocumentInfo();
  info.uri = 'file://a.md';
  info.name = 'a.md';
  info.newline = '\n';
  info.encoding = 'utf-8';
  info.fingerprint = 'original';
  info.formatId = 'markdown';
  info.writable = true;
  info.persistent = true;
  api.DocumentService.bindRecoveryError((_sessionId, error) => { recoveryErrors.push(error.message); });
  await api.DocumentService.adopt({ info, text: 'base' });
  if (overrides.skipEdit !== true) api.DocumentService.edit('edited');
  return {
    api: api.DocumentService, writes, drafts, clears, recoveryErrors, prepared,
    encodings: () => encodings, release: () => releaseWrite?.()
  };
}

test('save-as to the original URI does not bypass conflict checking', async () => {
  const opened = await service();
  await opened.api.save({}, true);
  assert.equal(opened.writes[0].conflict, true);
});

test('saving an unchanged original file does not write or truncate it', async () => {
  const opened = await service({ skipEdit: true, failWrite: true });
  const result = await opened.api.save({}, false);
  assert.equal(result.saved, true);
  assert.equal(opened.writes.length, 0);
  assert.equal(opened.encodings(), 0);
});

test('save-as still writes an unchanged document', async () => {
  const opened = await service({ skipEdit: true });
  const result = await opened.api.save({}, true);
  assert.equal(result.saved, true);
  assert.equal(opened.writes.length, 1);
  assert.equal(opened.drafts[0].writeUncertain, true);
});

test('failure before the provider starts writing does not mark the original file uncertain', async () => {
  const opened = await service({ files: { write: async () => { throw new Error('conflict'); } } });
  await assert.rejects(opened.api.save({}, false), /conflict/);
  assert.equal(opened.api.current().writeUncertain, false);
  assert.equal(opened.api.current().source, 'edited');
});

test('an interrupted write retains both the latest edit and the attempted snapshot after undo', async () => {
  const time = clock();
  const opened = await service({ holdWrite: true, failWrite: true }, time);
  const pending = opened.api.save({}, false);
  await new Promise((resolve) => setImmediate(resolve));
  opened.api.edit('base');
  time.advance(2000);
  await new Promise((resolve) => setImmediate(resolve));
  opened.release();
  await assert.rejects(pending, /partial write/);
  time.advance(2000);
  await new Promise((resolve) => setImmediate(resolve));
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(opened.api.current().source, 'base');
  assert.equal(opened.api.current().savedText, 'base');
  assert.equal(opened.api.current().writeUncertain, true);
  const recovery = opened.drafts.at(-1);
  assert.equal(recovery.text, 'base');
  assert.equal(recovery.pendingWriteText, 'edited');
  assert.equal(recovery.writeUncertain, true);
  assert.equal(opened.clears.length, 0);
});

test('checkpoint failure prevents an external write', async () => {
  const opened = await service({ failDraft: true });
  await assert.rejects(opened.api.save({}, false), /disk full/);
  assert.equal(opened.writes.length, 0);
});

test('provider write failure leaves complete recovery text', async () => {
  const opened = await service({ failWrite: true });
  await assert.rejects(opened.api.save({}, false), /partial write/);
  assert.equal(opened.drafts[0].text, 'edited');
  assert.equal(opened.drafts[0].savedText, 'base');
});

test('typing during a save keeps the newer text and the captured baseline', async () => {
  const opened = await service({ holdWrite: true });
  const id = opened.api.current().id;
  const pending = opened.api.save({}, false);
  await new Promise((resolve) => setImmediate(resolve));
  opened.api.edit('B');
  await opened.api.startNew('plain');
  const blocked = await opened.api.save({}, false);
  assert.equal(blocked.saved, false);
  opened.release();
  const result = await pending;
  assert.equal(result.saved, true);
  assert.equal(result.stillDirty, true);
  assert.equal(opened.api.current().id, id);
  assert.equal(opened.api.current().source, 'B');
  assert.equal(opened.api.current().savedText, 'edited');
  assert.equal(opened.writes[0].text, 'edited');
});

test('opaque file URI is resolved using the provider filename', async () => {
  const opened = await service();
  assert.equal(await opened.api.openUri('file://12345', '', true, true), true);
  assert.equal(opened.api.current().info.formatId, 'markdown');
});

test('rejected late confirmation does not replace the current session', async () => {
  const opened = await service();
  const owner = opened.api.current();
  assert.equal(await opened.api.openUri('file://b.md', '', true, true, async () => false), false);
  assert.equal(opened.api.current(), owner);
});

test('undo back to the saved text drops the pending draft', async () => {
  const time = clock();
  const opened = await service({ skipEdit: true }, time);
  opened.api.edit('B');
  time.advance(449);
  opened.api.edit('base');
  time.advance(2000);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(opened.drafts.length, 0);
  assert.equal(opened.clears.length, 1);
});

test('replacing a discarded document clears its recovery file before a templated document', async () => {
  const opened = await service();
  assert.equal(await opened.api.startNew('svg'), true);
  assert.equal(opened.api.current().source, '<svg></svg>');
  assert.equal(opened.clears.length, 1);
  assert.equal(opened.api.current().savedText, '');
});

test('a failed recovery cleanup does not hide a completed save and keeps a deleted document open', async () => {
  const opened = await service({
    local: { clearDraft: async () => { throw new Error('unlink failed'); } }
  });
  const saved = await opened.api.save({}, false);
  assert.equal(saved.saved, true);
  assert.equal(opened.writes.length, 1);
  assert.equal(opened.encodings(), 1);
  assert.equal(opened.writes[0].encoded, opened.prepared);
  assert.deepEqual(opened.recoveryErrors, ['unlink failed']);
  opened.api.edit('again');
  const deleted = await opened.api.moveToTrash();
  assert.equal(deleted.deleted, true);
  assert.equal(deleted.recoveryCleanupFailed, true);
  assert.equal(deleted.retainedEdits, true);
  assert.equal(opened.api.current().editing, true);
  assert.equal(opened.api.current().info.uri, '');
  assert.equal(opened.drafts.at(-1).uri, '');
  assert.equal(opened.recoveryErrors.length, 2);
});

for (const asNewFile of [false, true]) {
  test(`confirmed ${asNewFile ? 'save-as' : 'save'} updates recovery before cleanup can fail`, async () => {
    let persisted = null;
    const opened = await service({
      files: { chooseSave: async () => 'file://b.md' },
      local: {
        writeDraft: async (_context, value) => { persisted = { ...value }; },
        clearDraft: async () => { throw new Error('unlink failed'); }
      }
    });
    const result = await opened.api.save({}, asNewFile);
    assert.equal(result.saved, true);
    assert.equal(persisted.uri, asNewFile ? 'file://b.md' : 'file://a.md');
    assert.equal(persisted.savedText, 'edited');
    assert.equal(persisted.text, 'edited');
    assert.equal(persisted.fingerprint, 'written');
    assert.equal(persisted.writeUncertain, false);
  });
}

test('edits while recovery cleanup is in flight are reflected in the save result', async () => {
  let entered;
  let release;
  const waiting = new Promise((resolve) => { entered = resolve; });
  const opened = await service({ local: { clearDraft: async () => {
    entered();
    await new Promise((resolve) => { release = resolve; });
  } } });
  const pending = opened.api.save({}, false);
  await waiting;
  opened.api.edit('typed during cleanup');
  release();
  const result = await pending;
  assert.equal(opened.api.current().savedText, 'edited');
  assert.equal(opened.api.current().source, 'typed during cleanup');
  assert.equal(result.stillDirty, true);
  assert.equal(result.message, 'app.string.saved_dirty');
});

test('after an interrupted recovery update, restart identifies the verified save-as target', async () => {
  let savedDraft = null;
  let attempts = 0;
  const opened = await service({
    files: {
      chooseSave: async () => 'file://b.md',
      read: async (uri) => ({
        info: { uri, name: uri.endsWith('b.md') ? 'b.md' : 'a.md', newline: '\n', lineEndings: '',
          encoding: 'utf-8', hasBom: false, fingerprint: uri.endsWith('b.md') ? 'written' : 'original',
          formatId: 'markdown', writable: true, persistent: true },
        text: uri.endsWith('b.md') ? 'edited' : 'base'
      })
    },
    local: {
      writeDraft: async (_context, draft) => {
        if (++attempts > 1) throw new Error('recovery storage failed');
        savedDraft = { ...draft };
      },
      clearDraft: async () => { throw new Error('must not delete uncommitted record'); }
    }
  });
  const result = await opened.api.save({}, true);
  assert.equal(result.saved, true);
  assert.equal(result.message, 'app.string.saved_recovery_pending');
  assert.equal(savedDraft.uri, 'file://a.md');
  assert.equal(savedDraft.pendingWriteUri, 'file://b.md');
  assert.equal(await opened.api.restore(savedDraft), true);
  assert.equal(opened.api.current().info.uri, 'file://b.md');
  assert.equal(opened.api.current().savedText, 'edited');
  assert.equal(opened.api.current().writeUncertain, false);
});

test('unresolved save-as recovery cannot silently overwrite the old file', async () => {
  const opened = await service({ files: { read: async (uri) => {
    if (uri === 'file://b.md') throw new Error('target unavailable');
    return { info: { name: 'a.md', fingerprint: 'original' }, text: 'base' };
  } } });
  const draft = { name: 'a.md', uri: 'file://a.md', text: 'edited', savedText: 'base',
    newline: '\n', lineEndings: '', encoding: 'utf-8', hasBom: false, fingerprint: 'original',
    formatId: 'markdown', writable: true, persistent: true, writeUncertain: true,
    pendingWriteText: 'edited', pendingWriteUri: 'file://b.md' };
  assert.equal(await opened.api.restore(draft), true);
  assert.equal(opened.api.current().info.uri, 'file://a.md');
  assert.equal(opened.api.current().info.writable, false);
  assert.equal(opened.api.current().writeUncertain, true);
});

function clock() {
  const timers = [];
  let now = 0;
  let sequence = 1;
  return {
    setTimeout(fn, ms) {
      const id = sequence++;
      timers.push({ id, fn, at: now + ms });
      return id;
    },
    clearTimeout(id) {
      const index = timers.findIndex((item) => item.id === id);
      if (index >= 0) timers.splice(index, 1);
    },
    advance(ms) {
      now += ms;
      let fired = true;
      while (fired) {
        fired = false;
        const due = timers.filter((item) => item.at <= now).sort((left, right) => left.at - right.at);
        if (due.length === 0) return;
        const item = due[0];
        const index = timers.indexOf(item);
        if (index < 0) continue;
        timers.splice(index, 1);
        item.fn();
        fired = true;
      }
    }
  };
}
