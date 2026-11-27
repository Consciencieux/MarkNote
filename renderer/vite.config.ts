import { defineConfig } from 'vite';
import { viteSingleFile } from 'vite-plugin-singlefile';

function localPath(relative: string): string {
  const pathname = decodeURIComponent(new URL(relative, import.meta.url).pathname);
  return /^\/[A-Za-z]:\//.test(pathname) ? pathname.slice(1) : pathname;
}

// ArkWeb rawfile: one offline HTML, all JS/CSS and KaTeX fonts embedded.
// This avoids resource-scheme cross-origin issues and CDN access.
export default defineConfig({
  base: './',
  resolve: { alias: {
    // MyST only imports escapeHtml from this internal path. markdown-it 14 uses .mjs.
    'markdown-it/lib/common/utils.js': localPath('./node_modules/myst-to-html/node_modules/markdown-it/lib/common/utils.mjs'),
    '@tikz-editor/lezer-tex': localPath('./.cache/tikz-editor/dist/lezer-tex/src/index.js'),
    '@tikz-editor/lezer-tikz': localPath('./.cache/tikz-editor/dist/lezer-tikz/src/index.js')
  } },
  plugins: [viteSingleFile({ removeViteModuleLoader: true })],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    assetsInlineLimit: 100_000_000,
    cssCodeSplit: false,
    sourcemap: false
  }
});
