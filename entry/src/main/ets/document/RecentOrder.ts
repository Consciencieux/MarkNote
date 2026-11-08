export interface RecentEntry {
  uri: string;
  name: string;
  openedAt?: number;
  modifiedAt?: number;
  favorite?: boolean;
  recent?: boolean;
}

function extension(name: string): string {
  const type = name.toLowerCase().split('.').pop() ?? '';
  return type === 'markdown' ? 'md' : type;
}

export function updateRecentDocument(items: RecentEntry[], uri: string, name: string,
  now: number, modifiedAt: number, opened: boolean): RecentEntry[] {
  const result: RecentEntry[] = [];
  let existing: RecentEntry | undefined;
  for (const item of items) {
    if (item.uri === uri) existing = item;
    else result.push(item);
  }
  const updated: RecentEntry = {
    uri: uri,
    name: name,
    openedAt: opened ? now : (existing?.openedAt ?? 0),
    modifiedAt: modifiedAt > 0 ? modifiedAt : 0,
    favorite: existing?.favorite === true,
    recent: true
  };
  // Preserve the old order as a tie breaker for records without timestamps.
  if (existing) {
    const index = items.findIndex((item: RecentEntry): boolean => item.uri === uri);
    result.splice(index, 0, updated);
  } else {
    result.unshift(updated);
  }
  return result;
}

export function removeRecentDocument(items: RecentEntry[], uri: string, deleted: boolean): RecentEntry[] {
  const result: RecentEntry[] = [];
  for (const item of items) {
    if (item.uri !== uri) result.push(item);
    else if (!deleted && item.favorite === true) {
      result.push({ uri: item.uri, name: item.name, openedAt: item.openedAt ?? 0,
        modifiedAt: item.modifiedAt ?? 0, favorite: true, recent: false });
    }
  }
  return result;
}

export function toggleFavoriteDocument(items: RecentEntry[], uri: string, name: string,
  modifiedAt: number): RecentEntry[] {
  const result: RecentEntry[] = [];
  let found = false;
  for (const item of items) {
    if (item.uri !== uri) {
      result.push(item);
    } else {
      found = true;
      const favorite = item.favorite !== true;
      if (favorite || item.recent !== false) {
        result.push({ uri: item.uri, name: name, openedAt: item.openedAt ?? 0,
          modifiedAt: modifiedAt > 0 ? modifiedAt : 0, favorite: favorite, recent: item.recent !== false });
      }
    }
  }
  if (!found) result.unshift({ uri: uri, name: name, openedAt: 0, modifiedAt: modifiedAt,
    favorite: true, recent: true });
  return result;
}

export function sortRecentDocuments(items: RecentEntry[], order: string): RecentEntry[] {
  return items.slice().sort((a: RecentEntry, b: RecentEntry): number => {
    if (order === 'modified' || order === 'opened') {
      const left = order === 'modified' ? (a.modifiedAt ?? 0) : (a.openedAt ?? 0);
      const right = order === 'modified' ? (b.modifiedAt ?? 0) : (b.openedAt ?? 0);
      return right - left;
    }
    if (order === 'type') {
      const left = extension(a.name);
      const right = extension(b.name);
      const typeOrder = left.localeCompare(right);
      if (typeOrder !== 0) return typeOrder;
    }
    return a.name.localeCompare(b.name, 'zh-CN', { numeric: true });
  });
}
