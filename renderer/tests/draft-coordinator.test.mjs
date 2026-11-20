import test from 'node:test';
import assert from 'node:assert/strict';
import { loadArktsModules } from './helpers/arkts-loader.mjs';

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

function coordinator(time, local) {
  return loadArktsModules(
    ['model/Document.ets', 'document/DraftCoordinator.ets'],
    '({ DraftCoordinator, DraftSnapshot, RecoveryData })',
    {
      ...time, ...local,
      AppText: { text: (name) => String(name) },
      $r: (name) => name,
      userNotice: (message) => new Error(String(message))
    }
  );
}

function snapshot(api, sessionId, text, savedText = 'base') {
  const data = new api.RecoveryData();
  data.text = text;
  data.savedText = savedText;
  data.name = 'a.md';
  data.uri = 'file://a.md';
  const shot = new api.DraftSnapshot();
  shot.sessionId = sessionId;
  shot.revision = 1;
  shot.data = data;
  return shot;
}

test('a durable checkpoint supersedes an older pending automatic draft', async () => {
  const time = clock();
  const writes = [];
  const api = coordinator(time, { LocalState: {
    writeDraft: async (_context, draft) => { writes.push(draft.text); },
    clearDraft: async () => {}
  } });
  const drafts = new api.DraftCoordinator({});
  drafts.activate(1);
  drafts.schedule(snapshot(api, 1, 'old'));
  await drafts.checkpoint(snapshot(api, 1, 'current'));
  time.advance(2000);
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(writes, ['current']);
});

test('drops an old session timer, serializes clearing, and keeps working after a failure', async () => {
  const time = clock();
  const writes = [];
  const clears = [];
  let fail = true;
  let pending = null;
  const api = coordinator(time, {
    LocalState: {
      writeDraft: (_context, draft) => {
        if (fail) {
          fail = false;
          return Promise.reject(new Error('disk full'));
        }
        return new Promise((resolve) => { pending = { draft, resolve: () => { writes.push(draft); resolve(); } }; });
      },
      clearDraft: async () => { clears.push('clear'); }
    }
  });
  const drafts = new api.DraftCoordinator({});
  drafts.activate(1);
  await assert.rejects(drafts.checkpoint(snapshot(api, 1, 'A')), /disk full/);
  const again = drafts.checkpoint(snapshot(api, 1, 'B'));
  await new Promise((resolve) => setImmediate(resolve));
  pending.resolve();
  await again;
  assert.equal(writes.at(-1).text, 'B');
  drafts.schedule(snapshot(api, 1, 'C'));
  time.advance(450);
  await new Promise((resolve) => setImmediate(resolve));
  const clearing = drafts.clear(snapshot(api, 1, 'C'));
  drafts.schedule(snapshot(api, 1, 'D'));
  pending.resolve();
  assert.equal(await clearing, false);
  assert.equal(clears.length, 0);
  drafts.activate(2);
  drafts.schedule(snapshot(api, 1, 'old'));
  time.advance(450);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(writes.filter((item) => item.text === 'old').length, 0);
});

test('a failed in-flight draft is not written again after the recovery file is cleared', async () => {
  const time = clock();
  const writes = [];
  let rejectWrite = null;
  const api = coordinator(time, {
    LocalState: {
      writeDraft: (_context, draft) => {
        writes.push(draft.text);
        if (rejectWrite === null) return new Promise((_resolve, reject) => { rejectWrite = reject; });
        return Promise.resolve();
      },
      clearDraft: async () => { writes.push('clear'); }
    }
  });
  const drafts = new api.DraftCoordinator({});
  const errors = [];
  drafts.onError = (_sessionId, error) => { errors.push(error.message); };
  drafts.activate(1);
  drafts.schedule(snapshot(api, 1, 'A'));
  time.advance(450);
  await new Promise((resolve) => setImmediate(resolve));
  const clearing = drafts.clear(snapshot(api, 1, 'base'));
  rejectWrite(new Error('disk full'));
  assert.equal(await clearing, true);
  time.advance(500);
  await new Promise((resolve) => setImmediate(resolve));
  time.advance(1000);
  await new Promise((resolve) => setImmediate(resolve));
  time.advance(2000);
  await new Promise((resolve) => setImmediate(resolve));
  time.advance(4000);
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(writes, ['A', 'clear']);
  assert.deepEqual(errors, []);
});
