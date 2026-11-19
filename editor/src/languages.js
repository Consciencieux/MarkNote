import { markdown } from '@codemirror/lang-markdown';
import { javascript } from '@codemirror/lang-javascript';
import { python } from '@codemirror/lang-python';
import { xml } from '@codemirror/lang-xml';
import { LanguageDescription, LanguageSupport, StreamLanguage } from '@codemirror/language';
import { stex } from '@codemirror/legacy-modes/mode/stex';
import { canonicalCodeLanguage } from '../../shared/code-languages.ts';

// Explicitly bundle the prototype's languages. Unknown fences remain plain text.
const codeLanguages = new Map([
  ['javascript', LanguageDescription.of({ name: 'javascript', support: javascript() })],
  ['typescript', LanguageDescription.of({ name: 'typescript', support: javascript({ typescript: true }) })],
  ['python', LanguageDescription.of({ name: 'python', support: python() })],
  ['xml', LanguageDescription.of({ name: 'xml', support: xml() })],
  ['latex', LanguageDescription.of({ name: 'latex', support: new LanguageSupport(StreamLanguage.define(stex)) })]
]);

export function languageFor(format) {
  if (format === 'markdown') return markdown({ codeLanguages: (info) => codeLanguages.get(canonicalCodeLanguage(info)) || null });
  if (format === 'svg') return xml();
  if (format === 'latex') return StreamLanguage.define(stex);
  return [];
}
