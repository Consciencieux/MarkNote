import katex from 'katex';
import { previewError, previewText } from '../preview-text.ts';

export function renderTexMath(source: string): string {
  if (/\\(?:documentclass|usepackage|begin\s*\{document\})/.test(source)) {
    return '';
  }
  let formula = source.trim();
  if (formula.startsWith('$$') && formula.endsWith('$$')) formula = formula.slice(2, -2);
  if (formula.startsWith('\\[') && formula.endsWith('\\]')) formula = formula.slice(2, -2);
  try {
    return `<div class="math-canvas">${katex.renderToString(formula, {
      displayMode: true, throwOnError: false, trust: false,
      strict: 'warn', maxSize: 100, maxExpand: 1000, output: 'htmlAndMathml'
    })}</div>`;
  } catch {
    return previewError(previewText().mathFailed);
  }
}
