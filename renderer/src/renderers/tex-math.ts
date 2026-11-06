import katex from 'katex';

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
    return '<p class="error">公式渲染失败，请检查数学语法。</p>';
  }
}
