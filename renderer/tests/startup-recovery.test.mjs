import test from 'node:test';
import assert from 'node:assert/strict';
import { StartupRecovery } from '../../entry/src/main/ets/document/StartupRecovery.ts';
import { loadArkts } from './helpers/arkts-loader.mjs';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';

function localState(readText) {
  return loadArkts('storage/LocalState.ets', 'LocalState', {
    fileIo: { readText }, Error, JSON, Promise,
    AppText: { text: (value) => value }, $r: (name) => name
  });
}

test('missing recovery file is distinct from a read failure or malformed content', async () => {
  const missing = localState(async () => { throw Object.assign(new Error('missing'), { code: 13900002 }); });
  assert.equal(await missing.readDraft({ filesDir: '/app' }), null);
  const unreadable = localState(async () => { throw new Error('permission denied'); });
  await assert.rejects(unreadable.readDraft({ filesDir: '/app' }), /permission denied/);
  const malformed = localState(async () => '{not json');
  await assert.rejects(malformed.readDraft({ filesDir: '/app' }), (error) =>
    error.name === 'InvalidDraftError' && error.message === 'invalid draft');
});

test('quarantines a damaged draft without replacing an earlier backup', async () => {
  const files = new Map([
    ['/app/unsaved-draft.json', '{broken'],
    ['/app/unsaved-draft-corrupt-0.json', 'earlier'],
  ]);
  const storage = loadArkts('storage/LocalState.ets', 'LocalState', {
    fileIo: {
      access: async (path) => files.has(path),
      rename: async (from, to) => { files.set(to, files.get(from)); files.delete(from); }
    }, Error, JSON, Promise
  });
  const backup = await storage.quarantineDraft({ filesDir: '/app' });
  assert.equal(backup, '/app/unsaved-draft-corrupt-1.json');
  assert.equal(files.get(backup), '{broken');
  assert.equal(files.get('/app/unsaved-draft-corrupt-0.json'), 'earlier');
  assert.equal(files.has('/app/unsaved-draft.json'), false);
});

test('a failed quarantine leaves the original recovery file untouched', async () => {
  const files = new Map([['/app/unsaved-draft.json', '{broken']]);
  const storage = loadArkts('storage/LocalState.ets', 'LocalState', {
    fileIo: { access: async (path) => files.has(path), rename: async () => { throw new Error('disk error'); } },
    Error, JSON, Promise
  });
  await assert.rejects(storage.quarantineDraft({ filesDir: '/app' }), /disk error/);
  assert.equal(files.get('/app/unsaved-draft.json'), '{broken');
});

test('startup proceeds only after the user accepts and quarantine succeeds', async () => {
  const text = readFileSync(new URL('../../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
  const start = text.indexOf('  private async resumeDraft(');
  const end = text.indexOf('\n  /**', start);
  const method = text.slice(start, end);
  let confirmed = false;
  let backedUp = 0;
  let failBackup = false;
  const invalid = new Error('invalid draft');
  invalid.name = 'InvalidDraftError';
  const LocalState = {
    readDraft: async () => { throw invalid; },
    isInvalidDraft: (error) => error.name === 'InvalidDraftError',
    quarantineDraft: async () => { if (failBackup) throw new Error('backup failed'); backedUp++; }
  };
  const View = vm.runInNewContext(stripTypeScriptTypes(`class View { ${method} } View`),
    { LocalState, DocumentService: {}, Error, Promise, $r: (value) => value });
  const view = new View();
  view.context = { filesDir: '/app' };
  view.disposed = false;
  view.confirmDamagedDraft = async () => confirmed;
  view.toast = () => {};
  assert.equal(await view.resumeDraft(), false);
  assert.equal(backedUp, 0);
  confirmed = true;
  failBackup = true;
  await assert.rejects(view.resumeDraft(), /backup failed/);
  assert.equal(backedUp, 0);
  failBackup = false;
  assert.equal(await view.resumeDraft(), true);
  assert.equal(backedUp, 1);
});

test('an unconfirmed write remains recoverable even when the visible text matches the baseline', async () => {
  const data = { name: 'a.md', uri: 'file://a.md', text: 'base', savedText: 'base',
    writeUncertain: true, pendingWriteText: 'edited' };
  const storage = localState(async () => JSON.stringify(data));
  const restored = await storage.readDraft({ filesDir: '/app' });
  assert.equal(restored.text, 'base');
  assert.equal(restored.pendingWriteText, 'edited');
  assert.equal(restored.writeUncertain, true);
});

test('startup failures block replacement and a later retry can recover', async () => {
  let attempts = 0;
  const errors = [];
  const gate = new StartupRecovery(async () => {
    attempts++;
    if (attempts === 1) throw new Error('unreadable');
    return true;
  }, (error) => errors.push(error.message));
  assert.equal(await gate.ensure(), false);
  assert.equal(await gate.ensure(), true);
  assert.equal(await gate.ensure(), true);
  assert.equal(attempts, 2);
  assert.deepEqual(errors, ['unreadable']);
});

test('concurrent startup requests share the same recovery attempt', async () => {
  let attempts = 0;
  let release;
  const gate = new StartupRecovery(() => {
    attempts++;
    return new Promise((resolve) => { release = resolve; });
  }, () => {});
  const first = gate.ensure();
  const second = gate.ensure();
  assert.equal(attempts, 1);
  release(true);
  assert.deepEqual(await Promise.all([first, second]), [true, true]);
});
