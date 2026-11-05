/**
 * Literal text search over the editor buffer.
 *
 * These are pure string operations with no dependency on the UI, so they can be reasoned about and
 * checked on their own instead of only through a running app.
 */

/** A match found in the source text. */
export class SearchHit {
  start: number;
  length: number;

  constructor(start: number, length: number) {
    this.start = start;
    this.length = length;
  }
}

export class TextSearch {
  /**
   * First occurrence at or after `from`, wrapping to the start of the document.
   * Returns null when the query is empty or absent.
   */
  static next(source: string, query: string, from: number): SearchHit | null {
    if (query.length === 0) return null;
    let start = from < source.length ? source.indexOf(query, from) : -1;
    if (start < 0) start = source.indexOf(query);
    if (start < 0) return null;
    return new SearchHit(start, query.length);
  }

  /** The match following `current`, or the first match when nothing is selected yet. */
  static following(source: string, query: string, current: number): SearchHit | null {
    const from = current >= 0 ? current + query.length : 0;
    return TextSearch.next(source, query, from);
  }

  /**
   * Replace the match at `start` when the text there still equals the query.
   * Returns null when the position no longer matches, so the caller can search again.
   */
  static replaceAt(source: string, start: number, query: string, replacement: string): string | null {
    if (query.length === 0 || start < 0) return null;
    if (source.slice(start, start + query.length) !== query) return null;
    return source.slice(0, start) + replacement + source.slice(start + query.length);
  }
}
