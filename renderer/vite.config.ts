import { defineConfig } from 'vite';
import { viteSingleFile } from 'vite-plugin-singlefile';

// ArkWeb rawfile: one offline HTML, all JS/CSS and KaTeX fonts embedded.
// This avoids resource-scheme cross-origin issues and CDN access.
export default defineConfig({
  base: './',
  plugins: [viteSingleFile({ removeViteModuleLoader: true })],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    assetsInlineLimit: 100_000_000,
    cssCodeSplit: false,
    sourcemap: false
  }
});
