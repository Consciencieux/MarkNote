import { defineConfig } from 'vite';
import { viteSingleFile } from 'vite-plugin-singlefile';
import { resolve } from 'node:path';

export default defineConfig({
  plugins: [viteSingleFile()],
  build: {
    target: 'es2022',
    outDir: 'dist-app',
    rollupOptions: { input: resolve('production.html') }
  }
});
