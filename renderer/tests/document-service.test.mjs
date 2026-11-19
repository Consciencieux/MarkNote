import test from 'node:test';
import assert from 'node:assert/strict';
import { loadArktsModules } from './helpers/arkts-loader.mjs';

const formats = {
  markdown: { id: 'markdown', starter: '' },
  plain: { id: 'plain', starter: '' }
};
const registry = {
  byId: (id) => formats[id],
  byFilename: (name) => name.endsWith('.md') ? formats.markdown : formats.plain,
  defaultName: (format) => format.id === 'markdown' ? 'a.md' : 'a.txt',
  resolve: (name, _type, unknown) => name.endsWith('.md') ? formats.markdown : unknown ? formats.plain : null
};

function service(overrides = {}) {
  const writes = [];
  const drafts = [];
  let releaseWrite = null;
  const files = {
    prepare: async () => ({ writable: true, persistent: true }),
    chooseSave: async () => 'file://a.md',
    read: async (uri) => ({
      info: { uri, name: 'a.md', newline: '\n', lineEndings: '', encoding: 'utf-8', hasBom: false,
        fingerprint: 'disk', formatId: 'markdown', writable: true, persistent: true },
      text: 'disk'
    }),
    validateForWrite: () => {},
    write: async (info, text, conflict) => {
      writes.push({ text, conflict });
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
    clearDraft: async () => {},
    ...overrides.local
  };
  const api = loadArktsModules(
    ['model/Document.ets', 'document/DraftCoordinator.ets', 'document/DocumentService.ets'],
    '({ DocumentService, DocumentInfo })',
    {
      setTimeout, clearTimeout, DocumentFiles: files, LocalState: local, FormatRegistry: registry,
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
  api.DocumentService.adopt({ info, text: 'base' });
  api.DocumentService.edit('edited');
  return { api: api.DocumentService, writes, drafts, release: () => releaseWrite?.() };
}

test('save-as to the original URI does not bypass conflict checking', async () => {
  const opened = service();
  await opened.api.save({}, true);
  assert.equal(opened.writes[0].conflict, true);
});

test('checkpoint failure prevents an external write', async () => {
  const opened = service({ failDraft: true });
  await assert.rejects(opened.api.save({}, false), /disk full/);
  assert.equal(opened.writes.length, 0);
});

test('provider write failure leaves complete recovery text', async () => {
  const opened = service({ failWrite: true });
  await assert.rejects(opened.api.save({}, false), /partial write/);
  assert.equal(opened.drafts[0].text, 'edited');
  assert.equal(opened.drafts[0].savedText, 'base');
});

test('typing during a save keeps the newer text and the captured baseline', async () => {
  const opened = service({ holdWrite: true });
  const id = opened.api.current().id;
  const pending = opened.api.save({}, false);
  await new Promise((resolve) => setImmediate(resolve));
  opened.api.edit('B');
  opened.api.startNew('plain');
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
  const opened = service();
  assert.equal(await opened.api.openUri('file://12345', '', true, true), true);
  assert.equal(opened.api.current().info.formatId, 'markdown');
});

test('rejected late confirmation does not replace the current session', async () => {
  const opened = service();
  const owner = opened.api.current();
  assert.equal(await opened.api.openUri('file://b.md', '', true, true, async () => false), false);
  assert.equal(opened.api.current(), owner);
});
