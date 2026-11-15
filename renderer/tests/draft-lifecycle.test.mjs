import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as nodeModule from 'node:module';
import vm from 'node:vm';

function loadLifecycle(clock) {
  const filename = new URL('../../entry/src/main/ets/document/DraftLifecycle.ets', import.meta.url);
  const source = readFileSync(filename, 'utf8').replace(/^import .*;\s*$/gm, '').replace(/^export /gm, '');
  const context = {
    setTimeout: clock.setTimeout,
    clearTimeout: clock.clearTimeout,
    Error
  };
  return vm.runInNewContext(`${nodeModule.stripTypeScriptTypes(source)}
({ DraftLifecycle, mayClearDraft, mayWriteDraft, normalizeDraft })`, context);
}

function clock() {
  const pending = [];
  return {
    pending,
    setTimeout(fn, delay) {
      const id = pending.length + 1;
      pending.push({ id, fn, delay, cleared: false });
      return id;
    },
    clearTimeout(id) {
      const item = pending.find((entry) => entry.id === id);
      if (item) item.cleared = true;
    },
    fire() {
      for (const item of pending) {
        if (!item.cleared && !item.ran) {
          item.ran = true;
          item.fn();
        }
      }
    }
  };
}

const needsStripper = { skip: typeof nodeModule.stripTypeScriptTypes !== 'function' };

test('cancel drops a pending draft write and does not write by itself', needsStripper, () => {
  const time = clock();
  const api = loadLifecycle(time);
  const life = new api.DraftLifecycle();
  let writes = 0;
  life.bind('A', 1);
  life.schedule(450, () => { writes++; });
  life.cancel();
  time.fire();
  assert.equal(writes, 0);
  assert.equal(time.pending[0].cleared, true);
});

test('a disposed page callback cannot overwrite the next document draft', needsStripper, () => {
  const time = clock();
  const api = loadLifecycle(time);
  const life = new api.DraftLifecycle();
  let draft = 'B';
  life.bind('A', 1);
  life.schedule(450, () => { draft = 'A'; });
  const queued = time.pending[0].fn;
  life.dispose();
  queued();
  assert.equal(draft, 'B');
  time.fire();
  assert.equal(draft, 'B');
});

test('rebinding to the next document blocks the previous callback', needsStripper, () => {
  const time = clock();
  const api = loadLifecycle(time);
  const life = new api.DraftLifecycle();
  let draft = '';
  life.bind('A', 2);
  life.schedule(450, (sessionId) => { draft = sessionId; });
  life.bind('B', 1);
  time.fire();
  assert.equal(draft, '');
});

test('an older revision cannot replace a newer persisted draft of the same document', needsStripper, () => {
  const time = clock();
  const api = loadLifecycle(time);
  assert.equal(api.mayWriteDraft('A', 2, 'A', 5), false);
  assert.equal(api.mayWriteDraft('A', 5, 'A', 2), true);
  assert.equal(api.mayWriteDraft('B', 1, '', 0), true);
});

test('a finished save for document A does not clear document B', needsStripper, () => {
  const time = clock();
  const api = loadLifecycle(time);
  assert.equal(api.mayClearDraft('A', 'B', 'B'), false);
  assert.equal(api.mayClearDraft('A', 'A', 'B'), false);
  assert.equal(api.mayClearDraft('A', 'A', 'A'), true);
  assert.equal(api.mayClearDraft('', 'A', 'A'), false);
});

test('an old draft without session fields is kept and migrated', needsStripper, () => {
  const time = clock();
  const api = loadLifecycle(time);
  const draft = api.normalizeDraft({ text: 'hello', savedText: '', name: 'note.md', uri: 'file://note.md' });
  assert.equal(draft.formatVersion, 1);
  assert.equal(draft.sessionId, '');
  assert.equal(draft.revision, 0);
  assert.equal(draft.text, 'hello');
  assert.equal(draft.savedText, '');
});
