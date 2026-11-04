import { Heading, documentOutline } from '../model/Document';
import { DocumentFormat, FormatRegistry } from './FormatRegistry';

/** Format-facing operations. The page keeps ArkUI state and asks here instead of reading extensions. */
export class DocumentService {
  static formatOf(filename: string): DocumentFormat {
    return FormatRegistry.byFilename(filename);
  }

  static headings(filename: string, source: string): Heading[] {
    if (!FormatRegistry.byFilename(filename).outline) return [];
    return documentOutline(source);
  }
}
