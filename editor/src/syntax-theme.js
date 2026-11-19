import { HighlightStyle, syntaxHighlighting } from '@codemirror/language';
import { tags } from '@lezer/highlight';
import { syntaxColors } from '../../shared/syntax-colors.ts';

export function syntaxTheme(name, appearance = 'light') {
  if (name === 'off') return syntaxHighlighting(HighlightStyle.define([]));
  const p = syntaxColors(name, appearance);
  return syntaxHighlighting(HighlightStyle.define([
    { tag: [tags.heading, tags.strong, tags.emphasis], color: p.title },
    { tag: [tags.keyword, tags.processingInstruction, tags.meta], color: p.keyword },
    { tag: [tags.string, tags.special(tags.string)], color: p.string },
    { tag: [tags.comment, tags.lineComment, tags.blockComment], color: p.comment },
    { tag: [tags.tagName, tags.attributeName], color: p.name },
    { tag: tags.function(tags.variableName), color: p.title },
    { tag: [tags.number, tags.bool, tags.literal], color: p.number }
  ]));
}
