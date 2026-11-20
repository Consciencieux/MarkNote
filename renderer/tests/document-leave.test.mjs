import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';

// Exercise the actual page methods with controlled asynchronous boundaries.
function loadViewMethods(service) {
  const source = readFileSync(new URL('../../entry/src/main/ets/pages/DocumentView.ets', import.meta.url), 'utf8');
  function method(name) {
    const start = source.indexOf(`  private async ${name}(`);
    assert.ok(start >= 0);
    const open = source.indexOf('{', start);
    let depth = 0;
    for (let index = open; index < source.length; index++) {
      if (source[index] === '{') depth++;
      else if (source[index] === '}' && --depth === 0) return source.slice(start, index + 1);
    }
    throw new Error(`Unclosed method ${name}`);
  }
  const code = `class View { ${method('saveBeforeLeaving')}\n${method('closeToLibrary')} }\nView`;
  return vm.runInNewContext(stripTypeScriptTypes(code), { DocumentService: service, Error, Promise, $r: (x) => x });
}

function later() {
  let release;
  let reject;
  const promise = new Promise((resolve, fail) => { release = resolve; reject = fail; });
  return { promise, release, reject };
}

test('an old leave confirmation cannot close a newer document session', async () => {
  const first = { editing: true, revision: 1, source: 'a', savedText: 'a' };
  const next = { editing: true, revision: 1, source: 'b', savedText: 'b' };
  let current = first;
  let closed = 0;
  const service = { current: () => current, clearRecovery: async () => true, close: () => { closed++; } };
  const View = loadViewMethods(service);
  const view = new View();
  const gate = later();
  view.closing = false;
  view.editor = { command() {} };
  view.saveBeforeLeaving = () => gate.promise;
  const oldLeave = view.closeToLibrary();
  current = next;
  gate.release(true);
  assert.equal(await oldLeave, false);
  assert.equal(closed, 0);
  assert.equal(current, next);
});

test('a leave confirmation in flight cannot be started twice and resumes after cleanup fails', async () => {
  const owner = { editing: true, revision: 1, source: 'a', savedText: 'a' };
  const gate = later();
  let resumed = 0;
  const service = { current: () => owner, clearRecovery: () => gate.promise, close() {} };
  const View = loadViewMethods(service);
  const view = new View();
  view.closing = false;
  view.editor = { command: () => { resumed++; } };
  view.toast = () => {};
  view.saveBeforeLeaving = async () => true;
  const first = view.closeToLibrary();
  await Promise.resolve();
  assert.equal(await view.closeToLibrary(), false);
  gate.reject(new Error('cleanup failed'));
  assert.equal(await first, false);
  assert.equal(resumed, 1);
});

test('a flush completed for a previous session cannot open its confirmation dialog', async () => {
  const first = { editing: true, revision: 1, writeUncertain: false };
  const next = { editing: true, revision: 1, writeUncertain: false };
  let current = first;
  let dialogs = 0;
  const View = loadViewMethods({ current: () => current });
  const view = new View();
  const gate = later();
  view.deleting = false;
  view.saving = false;
  view.leaveConfirming = false;
  view.sessionOwner = first;
  view.editor = { flush: () => gate.promise, command() {} };
  view.isDirty = () => true;
  view.askSaveOrDiscard = async () => { dialogs++; return true; };
  const waiting = view.saveBeforeLeaving();
  current = next;
  gate.release(true);
  assert.equal(await waiting, false);
  assert.equal(dialogs, 0);
});

test('a clean document remains open when recovery cleanup cannot complete', async () => {
  const owner = { editing: true, revision: 1, source: 'a', savedText: 'a' };
  let closed = 0;
  const service = { current: () => owner, clearRecovery: async () => false, close: () => { closed++; } };
  const View = loadViewMethods(service);
  const view = new View();
  view.editor = { command() {} };
  view.toast = () => {};
  view.saveBeforeLeaving = async () => true;
  assert.equal(await view.closeToLibrary(), false);
  assert.equal(closed, 0);
});
