/** Keys of images intersecting the current reading window. */
export function visibleImageKeys(images: readonly { key: string; top: number; bottom: number }[],
  top: number, height: number): string[] {
  if (!(height > 0)) return [];
  const first = Math.max(0, top - height);
  const last = top + height * 2;
  return [...new Set(images.filter(image => image.bottom > first && image.top < last).map(image => image.key))];
}
