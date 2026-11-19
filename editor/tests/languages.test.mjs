import test from 'node:test';
import assert from 'node:assert/strict';
import { EditorState } from '@codemirror/state';
import { ensureSyntaxTree } from '@codemirror/language';
import { languageFor } from '../src/languages.js';

function treeFor(format, source) {
  const state = EditorState.create({ doc: source, extensions: [languageFor(format)] });
  const tree = ensureSyntaxTree(state, source.length, 5000);
  assert.ok(tree, `parsing timed out: ${format}`);
  return tree;
}

test('markdown parses headings, emphasis and embedded javascript', () => {
  const source = '# Heading\n\n*italic*\n\n```js\nconst answer = 42\n```';
  const tree = treeFor('markdown', source);
  assert.match(tree.toString(), /ATXHeading1/);
  assert.match(tree.toString(), /Emphasis/);
  assert.match(tree.toString(), /FencedCode/);
  assert.equal(tree.resolveInner(source.indexOf('answer') + 2).name, 'VariableDefinition');
});

test('xml and latex use maintained language modes', () => {
  assert.match(treeFor('svg', '<svg width="10"/>').toString(), /Element/);
  assert.match(treeFor('latex', '\\section{Hello}\n% comment').toString(), /Document/);
});

test('shared aliases select nested language parsers and unknown names remain plain', () => {
  for (const alias of ['js', 'ts', 'arkts', 'py', 'tex', 'html']) {
    const source = `\`\`\`${alias}\n${alias === 'tex' ? '\\section{A}' : alias === 'html' ? '<a/>' : 'answer'}\n\`\`\``;
    const node = treeFor('markdown', source).resolveInner(source.indexOf('\n') + 2);
    assert.notEqual(node.name, 'CodeText', alias);
  }
  const source = '```unknown\nanswer\n```';
  assert.equal(treeFor('markdown', source).resolveInner(source.indexOf('answer') + 2).name, 'CodeText');
});

test('plain text has no language extension', () => {
  assert.deepEqual(languageFor('plain'), []);
});

test('markdown parsing remains active beyond the former character limit', () => {
  const source = `${'ordinary text\n'.repeat(3000)}# Heading at end`;
  assert.ok(source.length > 32768);
  assert.match(treeFor('markdown', source).toString(), /ATXHeading1/);
});
