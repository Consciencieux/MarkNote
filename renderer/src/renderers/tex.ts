import { DEFAULT_HANDLERS, TexParser } from 'tex-to-myst';
import { mystToHtml } from 'myst-to-html';
import { VFile } from 'vfile';
import { imageLabel } from '../preview-text.ts';
import { renderTexMath } from './tex-math.ts';

export interface TexHeading { level: number; text: string; offset: number }
export interface TexDocument { html: string; headings: TexHeading[]; diagnostics: string[]; tikzPictures: string[] }
interface Node {
  type: string;
  value?: unknown;
  depth?: number;
  enumerated?: boolean;
  enumerator?: string;
  children?: Node[];
  position?: { start?: { offset?: number } };
}

/** Match myst-to-html heading numbers when the preview HTML pass is skipped. */
function numberHeadings(root: Node): void {
  const headings: Node[] = [];
  const depths = new Set<number>();
  function collect(node: Node): void {
    if (node.type === 'heading') {
      headings.push(node);
      if (node.enumerated !== false && typeof node.depth === 'number') depths.add(node.depth);
    }
    node.children?.forEach(collect);
  }
  collect(root);
  let counts: Array<number | null> = [1, 2, 3, 4, 5, 6].map((depth) => depths.has(depth) ? 0 : null);
  for (const heading of headings) {
    if (heading.enumerator || heading.enumerated === false || typeof heading.depth !== 'number') continue;
    const index = heading.depth - 1;
    counts = counts.map((count, position) => {
      if (count === null || position < index) return count;
      if (position === index) return count + 1;
      return 0;
    });
    const visible = counts.filter((count) => count !== null) as number[];
    while (visible.length > 0 && visible[visible.length - 1] === 0) visible.pop();
    heading.enumerator = visible.join('.');
  }
}

function textOf(node: Node): string {
  if (typeof node.value === 'string') return node.value;
  return (node.children ?? []).map(textOf).join('');
}

interface SourcePoint { offset?: unknown }
interface SourceRange { start?: SourcePoint | null; end?: SourcePoint | null }
interface GraphicOption { type: string; content?: unknown; position?: SourceRange | null }
interface GraphicArgument { openMark: string; content: GraphicOption[] }

/** Slice only nonempty spans inside the original source. */
function sourceInRange(source: string, position: SourceRange | null | undefined): string | undefined {
  if (position == null || position.start == null || position.end == null) return;
  const from = position.start.offset;
  const to = position.end.offset;
  if (typeof from !== 'number' || typeof to !== 'number' || !Number.isInteger(from) || !Number.isInteger(to)) return;
  if (from < 0 || from >= to || to > source.length) return;
  return source.slice(from, to);
}

function graphicWidth(source: string, args: GraphicArgument[] | undefined): string | undefined {
  const argument = args?.find(item => item.openMark === '[');
  if (!argument) return;
  // The LaTeX AST keeps braced values together, so only top-level commas split options.
  const options = [''];
  for (const token of argument.content) {
    if (token.type === 'comment') continue;
    if (token.type === 'string' && token.content === ',') options.push('');
    else options[options.length - 1] += sourceInRange(source, token.position) ?? '';
  }
  const assignment = options.reverse().find(option => /^\s*width\s*=/.test(option));
  const length = assignment?.replace(/^\s*width\s*=\s*/, '').trim().replace(/^\{(.*)\}$/s, '$1').trim();
  if (!length) return;
  const match = /^(\d+(?:\.\d*)?|\.\d+)?\s*(\\(?:linewidth|textwidth|columnwidth)|cm|mm|in|pt|bp)$/.exec(length);
  if (!match) return;
  const [, magnitude, unit] = match;
  const amount = Number(magnitude ?? 1);
  if (!Number.isFinite(amount) || amount <= 0) return;
  if (unit.startsWith('\\')) return String(Math.min(amount, 1) * 100) + '%';
  if (magnitude !== undefined) return String(amount) + (unit === 'bp' ? 'pt' : unit);
}

/** Convert once; outline positions come from the same MyST tree used for the preview. */
export function renderTexDocument(source: string, renderHtml: boolean = true): TexDocument {
  const file = new VFile();
  const tikzPictures: string[] = [];
  const parser = new TexParser(source, file, { handlers: {
    ...DEFAULT_HANDLERS,
    macro_includegraphics(node, state, parent) {
      DEFAULT_HANDLERS.macro_includegraphics(node, state, parent);
      if (!renderHtml) return;
      const image = state.top().children?.at(-1);
      if (image?.type === 'image') image.previewWidth = graphicWidth(source, node.args);
    },
    env_tikzpicture(node, state) {
      if (!renderHtml) return;
      const picture = sourceInRange(source, node.position);
      if (picture === undefined) return;
      state.closeParagraph();
      state.addLeaf('tikzPicture', { index: tikzPictures.length });
      tikzPictures.push(picture);
    }
  } });
  // Unmarked content is text. Keep the legacy math path only when the parser identifies
  // at least one math-mode command or environment and no document-specific nodes.
  const raw = parser.raw.content as Array<{ type: string; _renderInfo?: { inMathMode?: boolean } }>;
  const mathNode = (node: typeof raw[number]): boolean =>
    (node.type === 'macro' || node.type === 'environment') && node._renderInfo?.inMathMode === true;
  const bareFormula = raw.some(mathNode) && raw.every(node => node.type === 'string' || node.type === 'whitespace' ||
    node.type === 'parbreak' || mathNode(node));
  if (bareFormula) return { html: renderHtml ? renderTexMath(source) : '', headings: [], diagnostics: [], tikzPictures };
  const headings: TexHeading[] = [];
  function visit(node: Node): void {
    if (node.type === 'heading') {
      const start = node.position?.start;
      const label = textOf(node).trim();
      const text = node.enumerator && label ? `${node.enumerator} ${label}` : label;
      if (text && typeof start?.offset === 'number') {
        headings.push({ level: node.depth ?? 1, text, offset: start.offset });
      }
    }
    node.children?.forEach(visit);
  }
  const title = parser.data.maketitle && parser.data.frontmatter?.title;
  let titleHtml = '';
  if (renderHtml && (typeof title === 'string' || Array.isArray(title))) {
    const titleNodes = typeof title === 'string' ? [{ type: 'text', value: title }] : title;
    const tree = { type: 'root', children: [{ type: 'heading', depth: 1, children: titleNodes }] };
    titleHtml = mystToHtml(tree as Parameters<typeof mystToHtml>[0]);
  }
  if (!renderHtml) numberHeadings(parser.ast as Node);
  const body = renderHtml ? mystToHtml(parser.ast as Parameters<typeof mystToHtml>[0], {
      hast: { handlers: {
        heading(state, heading) {
          const node = heading as typeof heading & { enumerator?: string; identifier?: string };
          const children = state.all(heading);
          if (node.enumerator) children.unshift({ type: 'text', value: `${node.enumerator} ` });
          const element = { type: 'element' as const, tagName: `h${heading.depth}`,
            properties: { id: node.identifier }, children };
          state.patch(heading, element);
          return state.applyData(heading, element);
        },
        image(_state, node, parent) {
          const { url, alt, align, previewWidth } = node as unknown as {
            url: string; alt?: string; align?: string; previewWidth?: string;
          };
          const label = alt || url.split('/').pop() || '';
          const className = ['missing-image', 'image-slot', 'tex-image-slot'];
          if (previewWidth) className.push('tex-image-sized');
          if (align === 'center' || (parent as { align?: string } | undefined)?.align === 'center') {
            className.push('tex-image-centered');
          }
          return {
            type: 'element', tagName: 'span',
            properties: {
              className, dataMnSrc: url, dataMnAlt: label,
              style: previewWidth ? 'width:' + previewWidth : undefined
            },
            children: [{ type: 'text', value: imageLabel(label) }]
          };
        },
        tikzPicture(_state, picture) {
          const { index } = picture as unknown as { index: number };
          return { type: 'element', tagName: 'div', properties: { className: ['tikz-block'], dataMnTikz: index },
            children: [] };
        }
      } }
    }) : '';
  visit(parser.ast as Node);
  return { html: titleHtml + body, headings, diagnostics: file.messages.map(message => message.message), tikzPictures };
}
