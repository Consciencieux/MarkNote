import { parseTikz } from '../../.cache/tikz-editor/dist/core/src/parser/index.js';
import { evaluateTikzFigure } from '../../.cache/tikz-editor/dist/core/src/semantic/evaluate.js';
import { emitSvg } from '../../.cache/tikz-editor/dist/core/src/svg/emit.js';

function renderPicture(source: string): string | null {
  const parsed = parseTikz(source);
  if (parsed.diagnostics.length > 0) return null;
  const evaluated = evaluateTikzFigure(parsed.figure, parsed.source, { maxForeachExpansions: 256 });
  if (evaluated.diagnostics.length > 0 || evaluated.scene.elements.length === 0) return null;
  const result = emitSvg(evaluated.scene, { padding: 4 });
  const { x, y, width, height } = result.viewBox;
  if (result.diagnostics.length > 0 || result.svg.length > 1_000_000 ||
      ![x, y, width, height].every(Number.isFinite) || width <= 0 || height <= 0) return null;
  // PGF measures in TeX points; the image's natural size is expressed in CSS pixels.
  const pxPerPoint = 96 / 72.27;
  return result.svg.replace(/^<svg\b/, `<svg width="${Math.ceil(width * pxPerPoint)}" height="${Math.ceil(height * pxPerPoint)}"`);
}

self.onmessage = (event: MessageEvent<string>): void => {
  let svg: string | null = null;
  try {
    svg = renderPicture(event.data);
  } catch {
    // A malformed or unsupported picture leaves the rest of the document readable.
  }
  self.postMessage(svg);
};
