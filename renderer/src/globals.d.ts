import type { } from 'vite/client';
declare global {
  interface Window {
    MarknotePreview: { readonly update: (data: { kind: 'markdown' | 'svg' | 'latex'; source: string; theme: 'system' | 'light' | 'dark' }) => void };
  }
}
export {};
