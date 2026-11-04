import type { } from 'vite/client';
declare global {
  interface Window {
    MarknotePreview: { readonly update: (data: { kind: 'markdown' | 'plain' | 'svg' | 'tex-math'; source: string; theme: 'system' | 'light' | 'dark' }) => void };
  }
}
export {};
