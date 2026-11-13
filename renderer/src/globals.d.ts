import type { } from 'vite/client';
export interface PreviewUpdate {
  kind: 'markdown' | 'plain' | 'svg' | 'tex-math';
  source: string;
  theme: 'system' | 'light' | 'dark';
  revision?: number;
  documentId?: number;
  /** Localized preview copy. Absent fields keep the base Chinese text. */
  text?: {
    lang?: string;
    empty?: string;
    failed?: string;
    unsafe?: string;
    markdownFailed?: string;
    svgUnsafe?: string;
    svgInvalid?: string;
    svgRejected?: string;
    mathFailed?: string;
    imageName?: string;
    imageSlot?: string;
  };
}

declare global {
  interface Window {
    MarknotePreview: {
      readonly update: (data: PreviewUpdate) => void;
      readonly imageWindow: (top: number, height: number) => string[];
      readonly setImage: (key: string, dataUrl: string) => void;
    };
  }
}
