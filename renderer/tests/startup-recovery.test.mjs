import test from 'node:test';
import assert from 'node:assert/strict';
import { StartupRecovery } from '../../entry/src/main/ets/document/StartupRecovery.ts';
import { loadArkts } from './helpers/arkts-loader.mjs';

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
  await assert.rejects(malformed.readDraft({ filesDir: '/app' }), /invalid draft/);
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
