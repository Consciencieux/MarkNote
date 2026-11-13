/** Strings supplied by ArkUI for one preview update. Missing fields keep the base Chinese copy. */
export interface PreviewText {
  lang: string;
  empty: string;
  failed: string;
  unsafe: string;
  markdownFailed: string;
  svgUnsafe: string;
  svgInvalid: string;
  svgRejected: string;
  mathFailed: string;
  imageName: string;
  imageSlot: string;
}

const FALLBACK: PreviewText = {
  lang: 'zh-Hans',
  empty: '内容将在这里预览',
  failed: '预览失败，请检查文稿内容。',
  unsafe: '当前浏览器不支持安全渲染',
  markdownFailed: 'Markdown 排版失败，请检查文稿。',
  svgUnsafe: '当前浏览器无法安全渲染 SVG',
  svgInvalid: 'SVG 文档格式错误',
  svgRejected: 'SVG 内容未通过安全检查',
  mathFailed: '公式渲染失败，请检查数学语法。',
  imageName: '图片',
  imageSlot: '[图片：%s]'
};

let current: PreviewText = FALLBACK;

export function previewText(): PreviewText {
  return current;
}

function textOf(value: unknown, fallback: string): string {
  return typeof value === 'string' && value.length > 0 && value.length <= 400 ? value : fallback;
}

/** Apply a preview payload and return a stamp used to detect language changes. */
export function usePreviewText(input: unknown): string {
  const source = input !== null && typeof input === 'object' ? input as Record<string, unknown> : {};
  const lang = typeof source.lang === 'string' && /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8}){0,3}$/.test(source.lang) ?
    source.lang : FALLBACK.lang;
  current = {
    lang,
    empty: textOf(source.empty, FALLBACK.empty),
    failed: textOf(source.failed, FALLBACK.failed),
    unsafe: textOf(source.unsafe, FALLBACK.unsafe),
    markdownFailed: textOf(source.markdownFailed, FALLBACK.markdownFailed),
    svgUnsafe: textOf(source.svgUnsafe, FALLBACK.svgUnsafe),
    svgInvalid: textOf(source.svgInvalid, FALLBACK.svgInvalid),
    svgRejected: textOf(source.svgRejected, FALLBACK.svgRejected),
    mathFailed: textOf(source.mathFailed, FALLBACK.mathFailed),
    imageName: textOf(source.imageName, FALLBACK.imageName),
    imageSlot: textOf(source.imageSlot, FALLBACK.imageSlot)
  };
  return Object.values(current).join('\n');
}

export function escapePreviewText(value: string): string {
  return value.replace(/[&<>"']/g, (character: string): string => {
    if (character === '&') return '&amp;';
    if (character === '<') return '&lt;';
    if (character === '>') return '&gt;';
    if (character === '"') return '&quot;';
    return '&#39;';
  });
}

export function previewError(message: string): string {
  return `<p class="error">${escapePreviewText(message)}</p>`;
}

/** Visible image placeholder. `%s` is the alt text. */
export function imageLabel(alt: string): string {
  const text = previewText();
  const name = alt.length > 0 ? alt : text.imageName;
  return text.imageSlot.includes('%s') ? text.imageSlot.replace('%s', name) : `${text.imageSlot}${name}`;
}

/** HTML-escaped form of `imageLabel`. */
export function imagePlaceholder(alt: string): string {
  return escapePreviewText(imageLabel(alt));
}
