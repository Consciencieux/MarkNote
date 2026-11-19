import test from 'node:test';
import assert from 'node:assert/strict';
import { highlightFencedCode } from '../src/renderers/code-highlight.ts';

const SAMPLES = [
  ['latex', String.raw`\section{A} % note`, /hljs-keyword/, /hljs-comment/],
  ['tex', String.raw`\section{A} % note`, /hljs-keyword/, /hljs-comment/],
  ['markdown', '# Title', /hljs-section/, /hljs-section/],
  ['md', '# Title', /hljs-section/, /hljs-section/],
  ['xml', '<svg width="1"></svg>', /hljs-name/, /hljs-attr/],
  ['html', '<span class="a">x</span>', /hljs-name/, /hljs-attr/],
  ['json', '{"a": 1}', /hljs-attr/, /hljs-number/],
  ['javascript', 'const a = "b";', /hljs-keyword/, /hljs-string/],
  ['js', 'const a = "b";', /hljs-keyword/, /hljs-string/],
  ['typescript', 'const a: string = "b";', /hljs-keyword/, /hljs-string/],
  ['ts', 'const a: string = "b";', /hljs-keyword/, /hljs-string/],
  ['arkts', 'const a: string = "b";', /hljs-keyword/, /hljs-string/],
  ['python', 'def f():\n    return "a"', /hljs-keyword/, /hljs-string/],
  ['py', 'def f():\n    return "a"', /hljs-keyword/, /hljs-string/],
  ['bash', 'echo "hi" # note', /hljs-built_in/, /hljs-comment/],
  ['sh', 'echo "hi" # note', /hljs-built_in/, /hljs-comment/],
  ['shell', 'echo "hi" # note', /hljs-built_in/, /hljs-comment/],
  ['yaml', 'a: 1', /hljs-attr/, /hljs-number/],
  ['yml', 'a: 1', /hljs-attr/, /hljs-number/],
  ['css', 'a { color: #fff; }', /hljs-selector-tag/, /hljs-attribute/],
  ['c', 'int main() { return 0; }', /hljs-type/, /hljs-number/],
  ['cpp', 'int main() { return 0; }', /hljs-keyword/, /hljs-number/],
  ['c++', 'int main() { return 0; }', /hljs-keyword/, /hljs-number/],
  ['cxx', 'int main() { return 0; }', /hljs-keyword/, /hljs-number/],
  ['cc', 'int main() { return 0; }', /hljs-keyword/, /hljs-number/],
  ['java', 'class A { int x = 1; }', /hljs-keyword/, /hljs-number/]
];

test('highlights the registered languages and their aliases', () => {
  for (const [language, source, first, second] of SAMPLES) {
    const html = highlightFencedCode(source, language);
    assert.match(html, first, language);
    assert.match(html, second, language);
    assert.equal(html, highlightFencedCode(source, language.toUpperCase()), language);
  }
});

test('uses the same rules for an alias and its canonical language', () => {
  assert.equal(highlightFencedCode(String.raw`\section{A}`, 'tex'), highlightFencedCode(String.raw`\section{A}`, 'latex'));
  assert.equal(highlightFencedCode('const a: string = "b";', 'arkts'), highlightFencedCode('const a: string = "b";', 'typescript'));
  assert.equal(highlightFencedCode('echo "hi"', 'shell'), highlightFencedCode('echo "hi"', 'bash'));
});

test('leaves unknown and plain fences for markdown-it to escape', () => {
  const source = 'const a = "b";';
  assert.equal(highlightFencedCode(source, ''), '');
  assert.equal(highlightFencedCode(source, '   '), '');
  assert.equal(highlightFencedCode(source, 'text'), '');
  assert.equal(highlightFencedCode(source, 'plaintext'), '');
  assert.equal(highlightFencedCode(source, 'ruby'), '');
  assert.equal(highlightFencedCode(source, 'svg'), '');
  assert.equal(highlightFencedCode(source, '__proto__'), '');
});

test('highlights fences across the former length limit', () => {
  const prefix = 'const answer = 42;\n// ';
  for (const length of [32767, 32768, 32769, 65536]) {
    const source = prefix + 'x'.repeat(length - prefix.length);
    const html = highlightFencedCode(source, 'javascript');
    assert.match(html, /hljs-keyword/);
    assert.match(html, /hljs-comment/);
    assert.equal((html.match(/x/g) ?? []).length, length - prefix.length);
  }
});

test('escapes markup inside a fence instead of emitting a tag', () => {
  const html = highlightFencedCode('<script>alert(1)</script>', 'html');
  assert.match(html, /&lt;/);
  assert.match(html, /script/);
  assert.doesNotMatch(html, /<script/i);
});
