import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = resolve(import.meta.dirname, '..');
const commit = '26c56a8dd27e7eb78e7c3b46eb2cd3bf30cfff1a';
const base = `https://raw.githubusercontent.com/Consciencieux/mystmd/${commit}/packages/tex-to-myst/src`;
const files = [
  { name: 'parser', source: '54aca68c3fa912c9febd281cd526478bac56c0cd3941897092023137b889c8ac',
    compiled: 'c3fc4f6e122c5db5138981a240affc734bf89744cf290a53f9ede1564e836ec3' },
  { name: 'verbatim', source: '2e51d395e6fb3e170f8283d936860644cc45441674b8724c708b1c004e8daa4f',
    compiled: 'f1a7f3d745ed3d67b031ceef0bb1a648fccb4d65e60a699c0c122eea221994c0' }
];
const packageDir = join(root, 'node_modules', 'tex-to-myst');
const cache = join(root, '.cache', `tex-to-myst-${commit}`);

export function verifyDigest(bytes, expected, label) {
  if (createHash('sha256').update(bytes).digest('hex') !== expected) {
    throw new Error(`${label}: SHA-256 mismatch`);
  }
}

function verifyInstalled() {
  const pkg = JSON.parse(readFileSync(join(packageDir, 'package.json'), 'utf8'));
  if (pkg.name !== 'tex-to-myst' || pkg.version !== '1.0.48') throw new Error('Unexpected tex-to-myst version');
  for (const file of files) verifyDigest(readFileSync(join(packageDir, 'dist', `${file.name}.js`)), file.compiled, file.name);
}

async function install() {
  const pkg = JSON.parse(readFileSync(join(packageDir, 'package.json'), 'utf8'));
  if (pkg.name !== 'tex-to-myst' || pkg.version !== '1.0.48') throw new Error('Unexpected tex-to-myst version');
  const compiler = JSON.parse(readFileSync(join(root, 'node_modules', 'typescript', 'package.json'), 'utf8'));
  if (compiler.version !== '7.0.2') throw new Error('Unexpected TypeScript version');
  mkdirSync(cache, { recursive: true });
  const temp = mkdtempSync(join(tmpdir(), 'marknote-tex-dependency-'));
  try {
    for (const file of files) {
      const cached = join(cache, `${file.name}.ts`);
      let bytes;
      if (existsSync(cached)) {
        bytes = readFileSync(cached);
      } else {
        const response = await fetch(`${base}/${file.name}.ts`, { signal: AbortSignal.timeout(30000) });
        if (!response.ok) throw new Error(`GitHub returned HTTP ${response.status} for ${file.name}.ts`);
        bytes = Buffer.from(await response.arrayBuffer());
      }
      verifyDigest(bytes, file.source, `${file.name}.ts`);
      writeFileSync(cached, bytes);
      writeFileSync(join(temp, `${file.name}.ts`), bytes);
    }
    const tsc = join(root, 'node_modules', '.bin', process.platform === 'win32' ? 'tsc.cmd' : 'tsc');
    const args = files.map(file => join(temp, `${file.name}.ts`)).concat([
      '--ignoreConfig', '--noCheck', '--skipLibCheck', '--target', 'ES2022', '--module', 'ES2022',
      '--newLine', 'lf', '--outDir', temp
    ]);
    const result = process.platform === 'win32'
      ? spawnSync(process.env.ComSpec || 'cmd.exe', ['/d', '/s', '/c', tsc, ...args], { encoding: 'utf8' })
      : spawnSync(tsc, args, { encoding: 'utf8' });
    if (result.error || result.status !== 0) throw new Error(`TypeScript compilation failed: ${result.error || result.stderr || result.stdout}`);
    for (const file of files) verifyDigest(readFileSync(join(temp, `${file.name}.js`)), file.compiled, `${file.name}.js`);
    for (const file of files) {
      const target = join(packageDir, 'dist', `${file.name}.js`);
      const next = `${target}.marknote-new`;
      writeFileSync(next, readFileSync(join(temp, `${file.name}.js`)));
      renameSync(next, target);
    }
    verifyInstalled();
    console.log(`Prepared tex-to-myst 1.0.48 with fixes from ${commit}.`);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
}

if (process.argv[1] && realpathSync(resolve(process.argv[1])) === realpathSync(fileURLToPath(import.meta.url))) {
  try {
    if (process.argv[2] === '--verify') verifyInstalled();
    else await install();
  } catch (error) {
    console.error(`tex-to-myst setup failed: ${error.message}. Remove ${cache} if its files are invalid, then retry npm ci with GitHub access.`);
    process.exitCode = 1;
  }
}
