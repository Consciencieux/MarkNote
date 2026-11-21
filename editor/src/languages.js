import { cssLanguage } from '@codemirror/lang-css';
import { javascriptLanguage, typescriptLanguage } from '@codemirror/lang-javascript';
import { markdown, markdownLanguage } from '@codemirror/lang-markdown';
import { pythonLanguage } from '@codemirror/lang-python';
import { xml, xmlLanguage } from '@codemirror/lang-xml';
import { StreamLanguage } from '@codemirror/language';
import { c, cpp, java } from '@codemirror/legacy-modes/mode/clike';
import { json } from '@codemirror/legacy-modes/mode/javascript';
import { shell } from '@codemirror/legacy-modes/mode/shell';
import { stex } from '@codemirror/legacy-modes/mode/stex';
import { yaml } from '@codemirror/legacy-modes/mode/yaml';
import { tags } from '@lezer/highlight';
import { canonicalCodeLanguage } from '../../shared/code-languages.ts';

const latex = StreamLanguage.define(stex);
const fenceLanguages = new Map([
  ['bash', StreamLanguage.define(shell)],
  ['c', StreamLanguage.define(c)],
  ['cpp', StreamLanguage.define(cpp)],
  ['css', cssLanguage],
  ['java', StreamLanguage.define(java)],
  ['javascript', javascriptLanguage],
  ['json', StreamLanguage.define({ ...json, tokenTable: { property: tags.propertyName } })],
  ['latex', latex],
  ['markdown', markdownLanguage],
  ['python', pythonLanguage],
  ['typescript', typescriptLanguage],
  ['xml', xmlLanguage],
  ['yaml', StreamLanguage.define({ ...yaml, tokenTable: { atom: tags.propertyName } })]
]);

export function languageFor(format) {
  if (format === 'markdown') return markdown({ codeLanguages: info => fenceLanguages.get(canonicalCodeLanguage(info)) || null });
  if (format === 'svg') return xml();
  if (format === 'latex') return latex;
  return [];
}
