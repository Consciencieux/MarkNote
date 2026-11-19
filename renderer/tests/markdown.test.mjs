import test from 'node:test';
import assert from 'node:assert/strict';
import { renderMarkdown, renderMarkdownDeferred } from '../src/renderers/markdown.ts';

test('keeps unavailable images as placeholders without a source address', () => {
  const html = renderMarkdown('![示意图](https://example.com/a.png)\n\n![同目录](./images/a.png)');
  assert.match(html, /class="missing-image image-slot"/);
  assert.match(html, /data-mn-src="https:\/\/example.com\/a.png"/);
  assert.match(html, /data-mn-src="\.\/images\/a.png"/);
  assert.match(html, /\[图片：示意图\]/);
  assert.doesNotMatch(html, /<img/);
  assert.doesNotMatch(html, /\ssrc=/);
});

test('creates image slots for references but not code blocks', () => {
  const source = '![内联](a.png)\n\n![引用][id]\n\n```\n![代码](nope.png)\n```\n\n[id]: images/b.jpg\n\n`![行内代码](code.png)`';
  const html = renderMarkdown(source);
  assert.match(html, /data-mn-src="a\.png"/);
  assert.match(html, /data-mn-src="images\/b\.jpg"/);
  assert.doesNotMatch(html, /data-mn-src="(?:nope|code)\.png"/);
});

test('uses the encoded address markdown-it will render', () => {
  const html = renderMarkdown('![图](图片.png)\n\n![空格](<my pic.png>)');
  assert.match(html, /data-mn-src="%E5%9B%BE%E7%89%87\.png"/);
  assert.match(html, /data-mn-src="my%20pic\.png"/);
});

test('renders task markers as disabled checkboxes and leaves ordinary lists unchanged', () => {
  const html = renderMarkdown([
    '- [ ] A',
    '- [x] B',
    '- [X] C',
    '',
    '1. [ ] D',
    '',
    '- text',
    '- parent',
    '  - [x] child',
    '',
    '`[x]`',
    '',
    '```',
    '- [x] code',
    '```'
  ].join('\n'));
  assert.match(html, /<input type="checkbox" class="task-list-item-checkbox"[^>]*disabled="disabled"><label[^>]*> A<\/label>/);
  assert.match(html, /<input type="checkbox"[^>]*checked="checked"[^>]*disabled="disabled"><label[^>]*> B<\/label>/);
  assert.match(html, /<input type="checkbox"[^>]*checked="checked"[^>]*disabled="disabled"><label[^>]*> C<\/label>/);
  assert.match(html, /<ol class="task-list-container">[\s\S]*<label[^>]*> D<\/label>/);
  assert.match(html, /<ul class="task-list-container">[\s\S]*<label[^>]*> child<\/label>/);
  assert.match(html, /<li>text<\/li>/);
  assert.doesNotMatch(html, /task-list-item">text/);
  assert.match(html, /<code>\[x\]<\/code>/);
  assert.match(html, /<pre><code>- \[x\] code/);
  assert.doesNotMatch(html, /<pre>[\s\S]*type="checkbox"/);
  assert.doesNotMatch(html, /<code>[\s\S]*type="checkbox"/);
});

test('keeps a mermaid fence as a numbered placeholder', () => {
  const html = renderMarkdown('```mermaid\nflowchart LR\n  A-->B\n```\n\n```Mermaid\npie\n  "a" : 1\n```\n\n```js\nconst a = 1\n```');
  assert.match(html, /<section class="mermaid-block" data-mn-mermaid="0"><\/section>/);
  assert.match(html, /<section class="mermaid-block" data-mn-mermaid="1"><\/section>/);
  assert.doesNotMatch(html, /flowchart LR/);
  assert.match(html, /<pre><code class="language-js">[\s\S]*hljs-keyword[\s\S]*const[\s\S]*1/);
});

test('deferred preview preserves escaped code and queues only supported ordinary fences', () => {
  const result = renderMarkdownDeferred('```js\nconst a = "<x>";\n```\n\n```text\nhljs-keyword\n```\n\n```svg\n<svg></svg>\n```');
  assert.equal(result.jobs.length, 1);
  assert.equal(result.jobs[0].language, 'js');
  assert.equal(result.jobs[0].source, 'const a = "<x>";\n');
  assert.match(result.html, /data-mn-code="0"/);
  assert.match(result.html, /&lt;x&gt;/);
  assert.doesNotMatch(result.html, /hljs-keyword<\/span>/);
  assert.match(result.html, /svg-canvas/);
});

test('highlights fenced code and keeps drawing, math, and plain fences unchanged', () => {
  const latex = renderMarkdown('```LaTeX\n\\\\section{A} % note\n```');
  assert.match(latex, /<pre><code class="language-LaTeX">[\s\S]*hljs-keyword[\s\S]*hljs-comment/);
  assert.doesNotMatch(latex, /katex/);

  const htmlFence = renderMarkdown('```html\n<script>alert(1)</script>\n```');
  assert.match(htmlFence, /&lt;/);
  assert.doesNotMatch(htmlFence, /<script/i);

  const svgFence = renderMarkdown('```xml\n<svg onload="alert(1)"></svg>\n```');
  assert.match(svgFence, /hljs-name/);
  assert.match(svgFence, /&lt;/);
  assert.doesNotMatch(svgFence, /<svg[\s>]/i);
  assert.doesNotMatch(svgFence, /onload=/);

  const plain = renderMarkdown('```\nkeep me\n```');
  assert.match(plain, /<pre><code>keep me\n<\/code><\/pre>/);
  assert.doesNotMatch(plain, /hljs-/);

  const unknown = renderMarkdown('```ruby\nprint("all of this stays")\n```');
  assert.match(unknown, /print\(&quot;all of this stays&quot;\)/);
  assert.doesNotMatch(unknown, /hljs-/);

  const text = renderMarkdown('```text\nplain words\n```');
  assert.match(text, /<pre><code class="language-text">plain words\n<\/code><\/pre>/);
  assert.doesNotMatch(text, /hljs-/);

  const inline = renderMarkdown('`const a = 1`');
  assert.match(inline, /<code>const a = 1<\/code>/);
  assert.doesNotMatch(inline, /hljs-/);

  const body = 'const a = 1;\n' + 'x'.repeat(32769);
  const oversized = renderMarkdown(`\`\`\`js\n${body}\n\`\`\``);
  assert.equal((oversized.match(/x/g) ?? []).length, 32769);
  assert.match(oversized, /hljs-keyword/);

  const drawing = renderMarkdown('```svg\n<svg xmlns="http://www.w3.org/2000/svg"></svg>\n```\n\n```math\n\\\\frac{a}{b}\n```');
  assert.match(drawing, /<section class="svg-canvas">/);
  assert.match(drawing, /katex-display/);
  assert.doesNotMatch(drawing, /hljs-/);
});

test('keeps math fences as KaTeX and leaves latex and tex fences as code', () => {
  const svg = renderMarkdown('```svg\n<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"></svg>\n```');
  const mermaid = renderMarkdown('```mermaid\nflowchart LR\n  A-->B\n```');
  const math = renderMarkdown('```math\n\\\\frac{a}{b}\n```');
  const latex = renderMarkdown('```latex\n\\\\section{A}\n```');
  const tex = renderMarkdown('```tex\n% comment\n```');
  assert.match(svg, /<section class="svg-canvas">/);
  assert.match(mermaid, /<section class="mermaid-block"/);
  assert.match(math, /class='katex-display'|class="katex-display"/);
  assert.doesNotMatch(math, /<pre>/);
  assert.match(latex, /<pre><code class="language-latex">/);
  assert.doesNotMatch(latex, /katex/);
  assert.match(tex, /<pre><code class="language-tex">/);
  assert.doesNotMatch(tex, /katex/);
});
