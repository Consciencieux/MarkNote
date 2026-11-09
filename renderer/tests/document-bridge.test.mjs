import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as nodeModule from 'node:module';
import vm from 'node:vm';

const needsStripper = { skip: typeof nodeModule.stripTypeScriptTypes !== 'function' };

function bridge() {
  const source = readFileSync(new URL('../../entry/src/main/ets/pages/DocumentBridge.ets', import.meta.url), 'utf8')
    .replace(/^export /gm, '');
  const Bridge = vm.runInNewContext(`${nodeModule.stripTypeScriptTypes(source)}\nDocumentBridge`,
    { Promise, setTimeout, clearTimeout });
  return new Bridge();
}

test('external open waits for both loaded content and visible destination', needsStripper, async () => {
  const subject = bridge();
  const ready = subject.whenVisible(200);
  subject.markShown();
  subject.markAttached();
  assert.equal(await ready, true);
  assert.equal(await subject.whenVisible(), true);
});

test('a hidden destination must be shown again before opening', needsStripper, async () => {
  const subject = bridge();
  subject.markAttached();
  subject.markShown();
  subject.markHidden();
  const ready = subject.whenVisible(200);
  subject.markShown();
  assert.equal(await ready, true);
});

test('destroying a destination cancels a pending request', needsStripper, async () => {
  const subject = bridge();
  const ready = subject.whenVisible(200);
  subject.markAttached();
  subject.markDetached();
  assert.equal(await ready, false);
});

test('an unreachable destination times out and can be retried', needsStripper, async () => {
  const subject = bridge();
  assert.equal(await subject.whenVisible(10), false);
  const ready = subject.whenVisible(200);
  subject.markAttached();
  subject.markShown();
  assert.equal(await ready, true);
});

test('an interrupted wait resolves false', needsStripper, async () => {
  const subject = bridge();
  const ready = subject.whenVisible(200);
  subject.cancelWait();
  assert.equal(await ready, false);
});
