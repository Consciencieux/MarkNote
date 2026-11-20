import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import { EditorBridge } from '../../entry/src/main/ets/document/EditorBridge.ts';

function setup(initial = 'a🙂b') {
  let source = initial;
  const writes = [];
  const bridge = new EditorBridge('session-1', 1, 0, () => source, (value) => { source = value; writes.push(value); });
  return { bridge, writes, get source() { return source; } };
}

function change(sequence, baseRevision, changes, selection = { anchor: 0, head: 0 }) {
  return { type: 'change', sessionId: 'session-1', epoch: 1, sequence, baseRevision, changes, selection };
}

test('applies UTF-16 changes once and acknowledges duplicate delivery', () => {
  const model = setup();
  const first = change(1, 0, [{ from: 1, to: 3, insert: '中' }], { anchor: 2, head: 2 });
  assert.equal(model.bridge.receive(first).type, 'ack');
  assert.equal(model.source, 'a中b');
  assert.equal(model.bridge.receive(first).type, 'ack');
  assert.deepEqual(model.writes, ['a中b']);
});

test('rejects future and mismatched revisions without modifying the document', () => {
  const model = setup();
  assert.equal(model.bridge.receive(change(2, 1, [{ from: 0, to: 0, insert: 'X' }])).type, 'conflict');
  assert.equal(model.bridge.receive(change(1, 5, [{ from: 0, to: 0, insert: 'X' }])).type, 'conflict');
  assert.equal(model.source, 'a🙂b');
  assert.deepEqual(model.writes, []);
});

test('ignores old sessions and rejects invalid ranges and selections', () => {
  const model = setup();
  const stale = { ...change(1, 0, []), sessionId: 'old' };
  assert.equal(model.bridge.receive(stale).type, 'stale');
  assert.equal(model.bridge.receive(change(1, 0, [{ from: 0, to: 99, insert: '' }])).type, 'conflict');
  assert.equal(model.bridge.receive(change(1, 0, [{ from: 1, to: 3, insert: 'x' }], { anchor: 99, head: 0 })).type, 'conflict');
  assert.equal(model.source, 'a🙂b');
});

test('applies nonoverlapping edits against one revision and preserves ordering', () => {
  const model = setup('abcdef');
  const result = model.bridge.receive(change(1, 0, [
    { from: 1, to: 2, insert: 'X' }, { from: 4, to: 6, insert: 'Y' }
  ]));
  assert.equal(result.type, 'ack');
  assert.equal(model.source, 'aXcdY');
});

test('does not acknowledge a failed document update', () => {
  const bridge = new EditorBridge('session-1', 1, 0, () => 'abc', () => { throw new Error('write failed'); });
  assert.equal(bridge.receive(change(1, 0, [{ from: 0, to: 0, insert: 'x' }])).type, 'conflict');
  assert.equal(bridge.revision(), 0);
});

test('the actual host and page accept only the current document baseline', () => {
  function method(path, marker) {
    const text = readFileSync(new URL(path, import.meta.url), 'utf8');
    const start = text.indexOf(marker);
    assert.ok(start >= 0);
    const open = text.indexOf('{', start);
    let depth = 0;
    for (let i = open; i < text.length; i++) {
      if (text[i] === '{') depth++;
      else if (text[i] === '}' && --depth === 0) return text.slice(start, i + 1);
    }
    throw new Error(`Unclosed ${marker}`);
  }
  const owner = { source: 'abc', editing: true, revision: 17 };
  let current = owner;
  const service = {
    current: () => current,
    edit: (text) => { current.source = text; current.revision++; return true; },
  };
  const pageMethod = method('../../entry/src/main/ets/pages/DocumentView.ets', '  private updateSource(');
  const hostMethod = method('../../entry/src/main/ets/pages/DocumentCodeEditor.ets', '  private resetBridge(');
  const classes = stripTypeScriptTypes(`class Page { ${pageMethod} } class Host { ${hostMethod} } ({ Page, Host })`);
  const { Page, Host } = vm.runInNewContext(classes, { DocumentService: service, EditorBridge, Error });
  const page = new Page();
  page.sessionOwner = owner;
  page.submitAnalysis = () => {};
  const host = new Host();
  host.sessionId = 'session-1';
  host.activeEpoch = 1;
  host.sourceBuffer = owner.source;
  host.onChange = (...args) => page.updateSource(...args);
  host.resetBridge();
  assert.equal(host.bridge.receive(change(1, 0, [{ from: 3, to: 3, insert: 'd' }])).type, 'ack');
  assert.equal(owner.source, 'abcd');
  assert.equal(owner.revision, 18);
  owner.source = 'external';
  assert.equal(host.bridge.receive(change(2, 1, [{ from: 0, to: 0, insert: 'x' }])).type, 'conflict');
  assert.equal(owner.source, 'external');
  assert.equal(host.sourceBuffer, 'abcd');
  assert.equal(host.bridge.revision(), 1);
  current = { source: 'abcd', editing: true, revision: 99 };
  host.resetBridge();
  assert.equal(host.bridge.receive(change(1, 0, [{ from: 0, to: 0, insert: 'x' }])).type, 'conflict');
  assert.equal(current.source, 'abcd');
});
