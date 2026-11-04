import katex from 'katex';

export function renderTexMath(source: string): string {
  if (/\\(?:documentclass|usepackage|begin\s*\{document\})/.test(source)) {
    return '<p class="error">当前支持 TeX 数学公式（含环境），尚未集成完整 LaTeX 文档编译器。</p>';
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
