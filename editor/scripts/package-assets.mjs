import { copyFileSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const source = join(root, 'dist-app', 'production.html');
const html = readFileSync(source, 'utf8');
if (!html.includes('__marknote_editor_port__') || /<script\b[^>]*\bsrc\s*=|<link\b[^>]*\brel="modulepreload"/.test(html)) {
  throw new Error('Editor bundle is incomplete or references external scripts');
}
const output = join(root, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'editor');
mkdirSync(output, { recursive: true });
copyFileSync(source, join(output, 'index.html'));
console.log(`Offline editor copied to ${output}`);
