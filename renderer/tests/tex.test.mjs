import test from 'node:test';
import assert from 'node:assert/strict';
import { renderTexDocument } from '../src/renderers/tex.ts';

test('renders text, inline code, math and listings and returns source locations', () => {
  const source = '\\title{Example}\n\\begin{document}\n\\maketitle\n\\section{First}\nText \\texttt{a\\_b} $x^2$.\n\\begin{lstlisting}[language=python]\nprint(1)\n\\end{lstlisting}\n\\end{document}';
  const result = renderTexDocument(source);
  assert.match(result.html, /Example/);
  assert.match(result.html, /<code>a_b<\/code>/);
  assert.match(result.html, /print\(1\)/);
  assert.match(result.html, /math-inline/);
  assert.equal(result.headings[0].text, '1 First');
  assert.equal(result.headings[0].offset, source.indexOf('\\section'));
});

test('preserves UTF-16 heading positions and starred headings', () => {
  const source = '😀\n\\section*{Unnumbered}\n\\subsection{Child}';
  const { headings } = renderTexDocument(source);
  assert.equal(headings[0].offset, source.indexOf('\\section'));
  assert.equal(headings[1].offset, source.indexOf('\\subsection'));
});

test('keeps formula-only files on the KaTeX preview path', () => {
  const result = renderTexDocument(String.raw`\frac{a}{b} + \sqrt{x^2 + y^2}`);
  assert.match(result.html, /katex/);
  assert.deepEqual(result.headings, []);
});

test('renders structured document titles returned by MyST', () => {
  const result = renderTexDocument(String.raw`\title{Experiment\\Report}
\begin{document}\maketitle\section{Introduction}Text\end{document}`);
  assert.match(result.html, /Experiment/);
  assert.match(result.html, /Report/);
});

test('shows MyST section numbers and leaves starred sections unnumbered', () => {
  const result = renderTexDocument(String.raw`\section{First}\subsection{Child}\section*{Unnumbered}`);
  assert.match(result.html, /1\s+First/);
  assert.match(result.html, /1\.1\s+Child/);
  assert.match(result.html, />Unnumbered<\/h2>/);
});

test('renders grouped monospaced text without breaking the document', () => {
  const result = renderTexDocument(String.raw`\section{Text}which is set in {\ttfamily spie.cls}.`);
  assert.match(result.html, /<code>spie\.cls<\/code>/);
});

test('preserves standalone KaTeX math environments', () => {
  for (const source of [String.raw`\begin{aligned} a &= b+c \\ d &= e \end{aligned}`,
    String.raw`\begin{matrix}a & b\\c & d\end{matrix}`]) {
    const result = renderTexDocument(source);
    assert.match(result.html, /katex/);
    assert.doesNotMatch(result.html, /katex-error/);
  }
});
