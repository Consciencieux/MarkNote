import type { } from 'vite/client';
export interface PreviewUpdate {
  kind: 'markdown' | 'plain' | 'svg' | 'tex-math';
  source: string;
  theme: 'system' | 'light' | 'dark';
  revision?: number;
  documentId?: number;
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
