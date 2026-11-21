import type { } from 'vite/client';
export interface ImageRequest { id: number; key: string; widthPx: number; heightPx: number }

export interface PreviewUpdate {
  kind: 'markdown' | 'plain' | 'svg' | 'tex-math';
  source: string;
  theme: 'system' | 'light' | 'dark';
  codeTheme?: 'off' | 'github' | 'atom' | 'vs';
  revision?: number;
  documentId?: number;
  /** outline asks LaTeX for headings only. Absent or render keeps the full preview. */
  mode?: 'outline' | 'render';
  /** Localized preview copy. Absent fields keep the base Chinese text. */
  text?: {
    lang?: string;
    rtl?: boolean;
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
      readonly loadImages: (generation: number) => void;
      readonly sizeImage: (id: number, width: number, height: number) => void;
      readonly release: () => void;
      readonly imageWindow: (top: number, height: number, generation: number) => ImageRequest[] | null;
    };
  }
}
