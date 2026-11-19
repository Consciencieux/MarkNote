import test from 'node:test';
import assert from 'node:assert/strict';
import { Compartment, EditorState } from '@codemirror/state';
import { EditorSession } from '../src/editor-session.ts';

test('save waits for IME commit and its acknowledgement, and prevents switching sessions', async () => {
  const previousDocument = globalThis.document;
  globalThis.document = { documentElement: {} };
  try {
    const sent = [];
    const port = { start() {}, close() {}, postMessage(value) { sent.push(JSON.parse(value)); } };
    const view = {
      compositionStarted: false, contentDOM: new EventTarget(), state: EditorState.create(),
      setState(state) { this.state = state; }, dispatch() {}, focus() {},
      requestMeasure(request) { request.read(); }
    };
    const session = new EditorSession(view, new Compartment(), (init) => EditorState.create({ doc: init.source }));
    session.attach(port);
    const send = (message) => port.onmessage({ data: JSON.stringify(message) });
    const init = { type: 'init', sessionId: 'doc', epoch: 1, revision: 0, source: '', format: 'plain',
      theme: 'off', language: 'zh', direction: 'ltr', anchor: 0, head: 0 };
    send(init);
    view.compositionStarted = true;
    send({ type: 'flush', sessionId: 'doc', epoch: 1, requestId: 'save' });
    send({ ...init, sessionId: 'next' });
    assert.equal(sent.at(-1).type, 'session-busy');
    await Promise.resolve();
    assert.equal(sent.some((message) => message.type === 'flushed'), false);

    const transaction = view.state.update({ changes: { from: 0, insert: '中' }, selection: { anchor: 1 } });
    view.state = transaction.state;
    session.record({ docChanged: true, changes: transaction.changes, state: transaction.state });
    view.compositionStarted = false;
    view.contentDOM.dispatchEvent(new Event('compositionend'));
    await new Promise((resolve) => setTimeout(resolve, 10));
    assert.equal(sent.some((message) => message.type === 'flushed'), false);
    send({ type: 'ack', sessionId: 'doc', epoch: 1, sequence: 1, revision: 1 });
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.deepEqual(sent.find((message) => message.type === 'flushed'),
      { type: 'flushed', sessionId: 'doc', epoch: 1, requestId: 'save', revision: 1 });
  } finally {
    globalThis.document = previousDocument;
  }
});

test('theme configuration accepts only known themes for the active session', () => {
  const previousDocument = globalThis.document;
  globalThis.document = { documentElement: {} };
  try {
    const themes = [];
    const port = { start() {}, close() {}, postMessage() {} };
    const view = { composing: false, setState() {} };
    const session = new EditorSession(view, new Compartment(), () => EditorState.create(), (theme) => themes.push(theme));
    session.attach(port);
    const send = (message) => port.onmessage({ data: JSON.stringify(message) });
    send({ type: 'init', sessionId: 'doc', epoch: 1, revision: 0, source: '', format: 'plain',
      theme: 'github', language: 'zh', direction: 'ltr', anchor: 0, head: 0 });
    send({ type: 'configure-theme', sessionId: 'old', epoch: 1, theme: 'off', appearance: 'light' });
    send({ type: 'configure-theme', sessionId: 'doc', epoch: 1, theme: 'unexpected', appearance: 'light' });
    send({ type: 'configure-theme', sessionId: 'doc', epoch: 1, theme: 'off', appearance: 'light' });
    assert.deepEqual(themes, ['off']);
  } finally {
    globalThis.document = previousDocument;
  }
});

test('conflict recovery requires the exact editor snapshot and starts a new epoch', () => {
  const previousDocument = globalThis.document;
  globalThis.document = { documentElement: {} };
  try {
    const sent = [];
    const port = { start() {}, close() {}, postMessage(value) { sent.push(JSON.parse(value)); } };
    const view = {
      composing: false, state: EditorState.create(),
      setState(state) { this.state = state; }, dispatch() {}
    };
    const session = new EditorSession(view, new Compartment(), (init) => EditorState.create({ doc: init.source }));
    session.attach(port);
    const send = (message) => port.onmessage({ data: JSON.stringify(message) });
    send({ type: 'init', sessionId: 'doc', epoch: 1, revision: 0, source: '用户输入', format: 'plain',
      theme: 'off', language: 'zh', direction: 'ltr', anchor: 0, head: 0 });
    send({ type: 'conflict', sessionId: 'doc', epoch: 1, reason: 'revision-mismatch' });
    send({ type: 'recovery-request', sessionId: 'doc', epoch: 1 });
    assert.equal(sent.at(-1).source, '用户输入');
    send({ type: 'recovery-accepted', sessionId: 'doc', epoch: 1, nextEpoch: 2, revision: 0, source: 'stale' });
    assert.equal(session.isBlocked(), true);
    send({ type: 'recovery-accepted', sessionId: 'doc', epoch: 1, nextEpoch: 2, revision: 0, source: '用户输入' });
    assert.equal(session.isBlocked(), false);
    assert.equal(sent.find((message) => message.type === 'recovered').epoch, 2);
    const transaction = view.state.update({ changes: { from: 4, insert: '!' } });
    view.state = transaction.state;
    session.record({ docChanged: true, changes: transaction.changes, state: transaction.state });
    const change = sent.find((message) => message.type === 'change');
    assert.equal(change.epoch, 2);
    assert.equal(change.sequence, 1);
  } finally {
    globalThis.document = previousDocument;
  }
});

test('a cancelled switch cannot suspend the editor after IME composition ends', async () => {
  const previousDocument = globalThis.document;
  globalThis.document = { documentElement: {} };
  try {
    const sent = [];
    const port = { start() {}, close() {}, postMessage(value) { sent.push(JSON.parse(value)); } };
    const view = {
      compositionStarted: false, contentDOM: new EventTarget(), state: EditorState.create(),
      setState(state) { this.state = state; }, dispatch() {}, requestMeasure(request) { request.read(); }
    };
    const session = new EditorSession(view, new Compartment(), () => EditorState.create());
    session.attach(port);
    const send = (message) => port.onmessage({ data: JSON.stringify(message) });
    send({ type: 'init', sessionId: 'doc', epoch: 1, revision: 0, source: '', format: 'plain',
      theme: 'off', language: 'zh', direction: 'ltr', anchor: 0, head: 0 });
    view.compositionStarted = true;
    send({ type: 'flush', sessionId: 'doc', epoch: 1, requestId: 'switch', suspend: true });
    send({ type: 'command', sessionId: 'doc', epoch: 1, action: 'resume' });
    view.compositionStarted = false;
    view.contentDOM.dispatchEvent(new Event('compositionend'));
    await new Promise((resolve) => setTimeout(resolve, 10));
    assert.equal(session.isBlocked(), false);
    assert.equal(sent.some((message) => message.type === 'flush-failed' && message.requestId === 'switch'), true);
  } finally { globalThis.document = previousDocument; }
});

test('leaving freezes new edits before acknowledging the save barrier and can resume', async () => {
  const previousDocument = globalThis.document;
  globalThis.document = { documentElement: {} };
  try {
    const sent = [];
    const port = { start() {}, close() {}, postMessage(value) { sent.push(JSON.parse(value)); } };
    const view = { compositionStarted: false, state: EditorState.create(),
      setState(state) { this.state = state; }, dispatch() {} };
    const session = new EditorSession(view, new Compartment(), () => EditorState.create());
    session.attach(port);
    const send = (message) => port.onmessage({ data: JSON.stringify(message) });
    send({ type: 'init', sessionId: 'doc', epoch: 1, revision: 0, source: '', format: 'plain',
      theme: 'off', language: 'zh', direction: 'ltr', anchor: 0, head: 0 });
    const transaction = view.state.update({ changes: { from: 0, insert: 'x' } });
    view.state = transaction.state;
    session.record({ docChanged: true, changes: transaction.changes, state: transaction.state });
    send({ type: 'flush', sessionId: 'doc', epoch: 1, requestId: 'switch', suspend: true });
    await Promise.resolve();
    assert.equal(session.isBlocked(), true);
    assert.equal(sent.some((message) => message.type === 'flushed'), false);
    send({ type: 'ack', sessionId: 'doc', epoch: 1, sequence: 1, revision: 1 });
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.equal(sent.some((message) => message.type === 'flushed'), true);
    send({ type: 'command', sessionId: 'doc', epoch: 1, action: 'resume' });
    assert.equal(session.isBlocked(), false);
  } finally { globalThis.document = previousDocument; }
});
