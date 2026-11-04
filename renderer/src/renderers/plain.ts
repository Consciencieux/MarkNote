function escapeText(source: string): string {
  return source.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

export function renderPlain(source: string): string {
  return `<pre class="plain">${escapeText(source)}</pre>`;
}
