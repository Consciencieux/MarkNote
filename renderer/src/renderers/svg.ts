import DOMPurify from 'dompurify';
import { previewError, previewText } from '../preview-text.ts';

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

/** Templates stay detached; image context isolates SVG styles and fragment IDs. */
const svgTemplates = new WeakMap<HTMLImageElement, SVGSVGElement>();

export function refreshIsolatedSvg(container: ParentNode): void {
  for (const image of container.querySelectorAll<HTMLImageElement>('img.isolated-svg')) {
    const template = svgTemplates.get(image);
    if (!template) continue;
    const copy = template.cloneNode(true) as SVGSVGElement;
    const appearance = getComputedStyle(image);
    // Presentation attributes provide inherited defaults without overriding SVG's own styles.
    if (!copy.hasAttribute('color')) copy.setAttribute('color', appearance.color);
    if (!copy.hasAttribute('font-family')) copy.setAttribute('font-family', appearance.fontFamily);
    copy.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
    image.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(new XMLSerializer().serializeToString(copy));
  }
}

/** Do not call for KaTeX's inline layout SVGs. */
export function isolateSvg(container: ParentNode, selector: string = 'svg'): void {
  for (const svg of container.querySelectorAll<SVGSVGElement>(selector)) {
    const image = document.createElement('img');
    image.className = 'isolated-svg';
    image.alt = svg.getAttribute('aria-label') || svg.querySelector('title')?.textContent || previewText().imageName;
    svgTemplates.set(image, svg.cloneNode(true) as SVGSVGElement);
    svg.replaceWith(image);
  }
  refreshIsolatedSvg(container);
}

// Keep fragment ids such as url(#gradient) intact. Scripts, animation, foreign
// HTML and non-fragment links stay removed. CSP still blocks network loads.
export function sanitizeSvg(source: string): string {
  if (!DOMPurify.isSupported) return previewError(previewText().svgUnsafe);
  installReferenceHook();
  const parsed = new DOMParser().parseFromString(source, 'image/svg+xml');
  if (parsed.documentElement.localName.toLowerCase() !== 'svg' || parsed.querySelector('parsererror')) {
    return previewError(previewText().svgInvalid);
  }
  const clean = DOMPurify.sanitize(source, {
    USE_PROFILES: { svg: true, svgFilters: true },
    FORBID_TAGS: ['script', 'foreignObject', 'a', 'animate', 'animateMotion', 'animateTransform', 'set', 'iframe'],
    FORBID_ATTR: ['src', 'srcset', 'onload', 'onclick'],
    SANITIZE_NAMED_PROPS: false,
    KEEP_CONTENT: false
  });
  if (!/^\s*<svg(?:\s|>)/i.test(clean)) return previewError(previewText().svgRejected);
  return clean;
}
