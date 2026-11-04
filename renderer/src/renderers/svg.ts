import DOMPurify from 'dompurify';

function internalReference(value: string): boolean {
  const trimmed = value.trim().toLowerCase();
  return trimmed.startsWith('#') || trimmed.startsWith('data:');
}

let hooked = false;
export function installReferenceHook(): void {
  if (hooked) return;
  hooked = true;
  DOMPurify.addHook('uponSanitizeAttribute', (_node, data) => {
    if (data.attrName !== 'href' && data.attrName !== 'xlink:href') return;
    if (!internalReference(data.attrValue)) data.keepAttr = false;
  });
}

// Keep fragment ids such as url(#gradient) intact. Scripts, animation, foreign
// HTML and non-fragment links stay removed. CSP still blocks network loads.
export function sanitizeSvg(source: string): string {
  if (!DOMPurify.isSupported) return '<p class="error">当前浏览器无法安全渲染 SVG</p>';
  installReferenceHook();
  const parsed = new DOMParser().parseFromString(source, 'image/svg+xml');
  if (parsed.documentElement.localName.toLowerCase() !== 'svg' || parsed.querySelector('parsererror')) {
    return '<p class="error">SVG 文档格式错误</p>';
  }
  const clean = DOMPurify.sanitize(source, {
    USE_PROFILES: { svg: true, svgFilters: true },
    FORBID_TAGS: ['script', 'foreignObject', 'a', 'animate', 'animateMotion', 'animateTransform', 'set', 'iframe'],
    FORBID_ATTR: ['src', 'srcset', 'onload', 'onclick'],
    SANITIZE_NAMED_PROPS: false,
    KEEP_CONTENT: false
  });
  if (!/^\s*<svg(?:\s|>)/i.test(clean)) return '<p class="error">SVG 内容未通过安全检查</p>';
  return clean;
}
