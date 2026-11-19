import test from 'node:test';
import assert from 'node:assert/strict';
import { basicSetup } from 'codemirror';
import { Compartment, EditorState } from '@codemirror/state';
import { undoDepth } from '@codemirror/commands';
import { highlightingFor } from '@codemirror/language';
import { tags } from '@lezer/highlight';
import { syntaxTheme } from '../src/syntax-theme.js';

test('turning syntax colors off retains content, selection and undo history', () => {
  const theme = new Compartment();
  let state = EditorState.create({ doc: 'Heading', extensions: [basicSetup, theme.of(syntaxTheme('github'))] });
  state = state.update({ changes: { from: 7, insert: '!' }, selection: { anchor: 3 } }).state;
  const before = state;
  state = state.update({ effects: theme.reconfigure(syntaxTheme('off')) }).state;
  assert.ok(highlightingFor(before, [tags.heading]));
  assert.equal(highlightingFor(state, [tags.heading]), null);
  assert.equal(state.doc.toString(), before.doc.toString());
  assert.equal(state.selection.main.anchor, before.selection.main.anchor);
  assert.equal(undoDepth(state), undoDepth(before));
});

test('light and dark palettes provide different syntax colors for each named theme', () => {
  for (const name of ['github', 'atom-one', 'visual-studio']) {
    const light = EditorState.create({ extensions: syntaxTheme(name, 'light') });
    const dark = EditorState.create({ extensions: syntaxTheme(name, 'dark') });
    assert.notEqual(highlightingFor(light, [tags.keyword]), highlightingFor(dark, [tags.keyword]));
  }
});
