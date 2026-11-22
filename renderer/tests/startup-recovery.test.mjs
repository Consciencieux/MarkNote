import test from 'node:test';
import assert from 'node:assert/strict';
import { StartupRecovery } from '../../entry/src/main/ets/document/StartupRecovery.ts';
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
