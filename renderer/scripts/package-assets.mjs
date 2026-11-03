import { copyFileSync, existsSync, mkdirSync, readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { spawnSync } from 'node:child_process';
const root = resolve(import.meta.dirname, '..');
const built = join(root, 'dist', 'index.html');
const text = readFileSync(built, 'utf8');
if (!text.includes('MarknotePreview') || !text.includes('katex')) {
  throw new Error('Preview bundle incomplete: do not package an empty or partial renderer');
}
const result = spawnSync(process.execPath, [join(root, 'scripts', 'generate-notices.mjs')], {
  cwd: root, stdio: 'inherit'
});
if (result.status !== 0) throw new Error('Dependency notices generation failed: release build blocked');
const out = join(root, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'preview');
mkdirSync(out, { recursive: true });
copyFileSync(built, join(out, 'index.html'));
if (!existsSync(join(out, 'index.html'))) throw new Error('Renderer asset missing');
console.log('Offline ArkWeb preview copied to entry/src/main/resources/rawfile/preview/index.html');
