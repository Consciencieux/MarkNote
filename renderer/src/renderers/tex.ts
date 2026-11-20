import { TexParser } from 'tex-to-myst';
import { mystToHtml } from 'myst-to-html';
import { VFile } from 'vfile';
import { renderTexMath } from './tex-math.ts';

export interface TexHeading { level: number; text: string; offset: number }
export interface TexDocument { html: string; headings: TexHeading[]; diagnostics: string[] }
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

/** Convert once; outline positions come from the same MyST tree used for the preview. */
export function renderTexDocument(source: string, renderHtml: boolean = true): TexDocument {
  const file = new VFile();
  const parser = new TexParser(source, file);
  // Unmarked content is text. Keep the legacy math path only when the parser identifies
  // at least one math-mode command or environment and no document-specific nodes.
  const raw = parser.raw.content as Array<{ type: string; _renderInfo?: { inMathMode?: boolean } }>;
  const mathNode = (node: typeof raw[number]): boolean =>
    (node.type === 'macro' || node.type === 'environment') && node._renderInfo?.inMathMode === true;
  const bareFormula = raw.some(mathNode) && raw.every(node => node.type === 'string' || node.type === 'whitespace' ||
    node.type === 'parbreak' || mathNode(node));
  if (bareFormula) return { html: renderHtml ? renderTexMath(source) : '', headings: [], diagnostics: [] };
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
        }
      } }
    }) : '';
  visit(parser.ast as Node);
  return { html: renderHtml ? titleHtml + body : '', headings, diagnostics: file.messages.map(message => message.message) };
}
