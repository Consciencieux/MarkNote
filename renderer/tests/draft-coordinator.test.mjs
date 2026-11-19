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

test('waits 450 ms, keeps only the newest automatic draft, and resolves a checkpoint after persistence', async () => {
  const time = clock();
  const writes = [];
  let pending = null;
  const api = coordinator(time, {
    LocalState: {
      writeDraft: (_context, draft) => new Promise((resolve) => { pending = { draft, resolve }; }),
      clearDraft: async () => {}
    }
  });
  const drafts = new api.DraftCoordinator({});
  drafts.activate(1);
  drafts.schedule(snapshot(api, 1, 'A'));
  time.advance(449);
  assert.equal(pending, null);
  time.advance(1);
  assert.equal(pending.draft.text, 'A');
  drafts.schedule(snapshot(api, 1, 'B'));
  drafts.schedule(snapshot(api, 1, 'C'));
  pending.resolve();
  pending = null;
  await new Promise((resolve) => setImmediate(resolve));
  time.advance(450);
  assert.equal(pending.draft.text, 'C');
  pending.resolve();
  const held = [];
  const checkpoint = drafts.checkpoint(snapshot(api, 1, 'saved'));
  let settled = false;
  checkpoint.then(() => { settled = true; });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(settled, false);
  pending.resolve();
  await checkpoint;
  assert.equal(writes.length, 0);
  void held;
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
