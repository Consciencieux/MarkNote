import { TexParser } from 'tex-to-myst';
import { mystToHtml } from 'myst-to-html';
import { VFile } from 'vfile';
import { renderTexMath } from './tex-math.ts';

export interface TexHeading { level: number; text: string; offset: number; line: number }
export interface TexDocument { html: string; headings: TexHeading[]; diagnostics: string[] }
interface Node {
  type: string;
  value?: unknown;
  depth?: number;
  enumerator?: string;
  children?: Node[];
  position?: { start?: { offset?: number; line?: number } };
}

function textOf(node: Node): string {
  if (typeof node.value === 'string') return node.value;
  return (node.children ?? []).map(textOf).join('');
}

/** Convert once; outline positions come from the same MyST tree used for the preview. */
export function renderTexDocument(source: string): TexDocument {
  const file = new VFile();
  const parser = new TexParser(source, file);
  // Unmarked content is text. Keep the legacy math path only when the parser identifies
  // at least one math-mode command or environment and no document-specific nodes.
  const raw = parser.raw.content as Array<{ type: string; _renderInfo?: { inMathMode?: boolean } }>;
  const mathNode = (node: typeof raw[number]): boolean =>
    (node.type === 'macro' || node.type === 'environment') && node._renderInfo?.inMathMode === true;
  const bareFormula = raw.some(mathNode) && raw.every(node => node.type === 'string' || node.type === 'whitespace' ||
    node.type === 'parbreak' || mathNode(node));
  if (bareFormula) return { html: renderTexMath(source), headings: [], diagnostics: [] };
  const headings: TexHeading[] = [];
  function visit(node: Node): void {
    if (node.type === 'heading') {
      const start = node.position?.start;
      const label = textOf(node).trim();
      const text = node.enumerator && label ? `${node.enumerator} ${label}` : label;
      if (text && typeof start?.offset === 'number' && typeof start.line === 'number') {
        headings.push({ level: node.depth ?? 1, text, offset: start.offset, line: start.line });
      }
    }
    node.children?.forEach(visit);
  }
  const title = parser.data.maketitle && parser.data.frontmatter?.title;
  let titleHtml = '';
  if (typeof title === 'string' || Array.isArray(title)) {
    const titleNodes = typeof title === 'string' ? [{ type: 'text', value: title }] : title;
    const tree = { type: 'root', children: [{ type: 'heading', depth: 1, children: titleNodes }] };
    titleHtml = mystToHtml(tree as Parameters<typeof mystToHtml>[0]);
  }
  const html = titleHtml + mystToHtml(parser.ast as Parameters<typeof mystToHtml>[0], {
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
    });
  visit(parser.ast as Node);
  return { html, headings, diagnostics: file.messages.map(message => message.message) };
}
