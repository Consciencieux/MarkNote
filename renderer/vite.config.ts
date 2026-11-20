import { defineConfig } from 'vite';
import { viteSingleFile } from 'vite-plugin-singlefile';

// MyST only imports escapeHtml from this internal path. markdown-it 14 uses .mjs.
const mystUtilsPath = decodeURIComponent(new URL(
  './node_modules/myst-to-html/node_modules/markdown-it/lib/common/utils.mjs', import.meta.url).pathname);
const mystUtils = /^\/[A-Za-z]:\//.test(mystUtilsPath) ? mystUtilsPath.slice(1) : mystUtilsPath;

// ArkWeb rawfile: one offline HTML, all JS/CSS and KaTeX fonts embedded.
// This avoids resource-scheme cross-origin issues and CDN access.
export default defineConfig({
  base: './',
  resolve: { alias: { 'markdown-it/lib/common/utils.js': mystUtils } },
  plugins: [viteSingleFile({ removeViteModuleLoader: true })],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    assetsInlineLimit: 100_000_000,
    cssCodeSplit: false,
    sourcemap: false
  }
});
