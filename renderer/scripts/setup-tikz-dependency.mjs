import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { verifyDigest } from './setup-tex-dependency.mjs';

const root = resolve(import.meta.dirname, '..');
const version = '1.3.0';
const commit = '5cfca4fa21044cd6552b065bf2bbea8d5f2585d0';
const archiveHash = '2c40952a1eab8d1fa0d44bf2d3f889bf1c744ed8660db888cd78ad9103b4fbc7';
const licenseHash = 'ec9e01ac409e182b74ac1733876b9f8a6cf9519c01fcf3363fb4e4b5b2f6a513';
const buildRecipe = createHash('sha256').update(readFileSync(fileURLToPath(import.meta.url))).digest('hex');
const cache = join(root, '.cache');
const installed = join(cache, 'tikz-editor');
const archive = join(cache, `tikz-editor-${commit}.tar.gz`);
const entries = {
  core: ['parser/index', 'semantic/evaluate', 'svg/emit'],
  'lezer-tex': ['index'],
  'lezer-tikz': ['index']
};
const modules = Object.entries(entries).flatMap(([pkg, names]) => names.map(name => `${pkg}/src/${name}`));

export function tikzDependencyNotices() {
  if (readFileSync(join(installed, 'build-recipe'), 'utf8') !== buildRecipe) {
    throw new Error('TikZ Editor build recipe changed');
  }
  const license = readFileSync(join(installed, 'LICENSE'));
  verifyDigest(license, licenseHash, 'TikZ Editor LICENSE');
  for (const name of modules) {
    const output = join(installed, 'dist', name);
    if (!existsSync(`${output}.js`) || !existsSync(`${output}.d.ts`)) throw new Error(`Missing TikZ module: ${name}`);
  }
  return Object.keys(entries).map(pkg => {
    const manifest = JSON.parse(readFileSync(join(installed, 'packages', pkg, 'package.json'), 'utf8'));
    const name = `@tikz-editor/${pkg}`;
    if (manifest.name !== name || manifest.version !== version || (manifest.license ?? 'MIT') !== 'MIT') {
      throw new Error(`Unexpected ${name} manifest`);
    }
    return { name, version, license: 'MIT', text: license.toString('utf8'), notice: '' };
  });
}

function run(program, args) {
  const result = spawnSync(program, args, { stdio: 'inherit' });
  if (result.error || result.status !== 0) throw new Error(`${program} failed: ${result.error ?? result.status}`);
}

async function install() {
  mkdirSync(cache, { recursive: true });
  if (existsSync(archive)) {
    verifyDigest(readFileSync(archive), archiveHash, 'TikZ Editor archive');
  } else {
    const url = `https://codeload.github.com/DominikPeters/tikz-editor/tar.gz/${commit}`;
    const response = await fetch(url, { signal: AbortSignal.timeout(90000) });
    if (!response.ok) throw new Error(`GitHub returned HTTP ${response.status} for the TikZ Editor archive`);
    const bytes = Buffer.from(await response.arrayBuffer());
    verifyDigest(bytes, archiveHash, 'TikZ Editor archive');
    writeFileSync(archive, bytes);
  }

  // Use the checked-in Lezer parsers and compile only the document preview entry points.
  const temp = mkdtempSync(join(cache, '.tikz-editor-'));
  try {
    const upstream = `tikz-editor-${commit}`;
    run('tar', ['-xzf', archive, '-C', temp, '--strip-components=1', `${upstream}/LICENSE`,
      ...Object.keys(entries).map(pkg => `${upstream}/packages/${pkg}`)]);
    const sources = join(temp, 'packages');
    // Import the same resource analyzer from its defining module so the SVG fallback uses
    // system fonts without bundling the optional TeX font and hyphenation data.
    for (const name of ['graphics/diagnostics', 'semantic/nodes/evaluate', 'semantic/nodes/matrix']) {
      const file = join(sources, 'core', 'src', `${name}.ts`);
      const original = readFileSync(file, 'utf8');
      const narrowed = original.replace('/text/tex/index.js"', '/text/tex/ir.js"');
      if (narrowed === original) throw new Error(`Missing TikZ resource analyzer import in ${name}`);
      writeFileSync(file, narrowed);
    }
    run(process.execPath, [join(root, 'node_modules', 'typescript', 'bin', 'tsc'), '--ignoreConfig',
      '--noCheck', '--skipLibCheck', '--declaration', '--target', 'ES2022', '--module', 'ES2022',
      '--moduleResolution', 'Bundler', '--newLine', 'lf', '--rootDir', sources, '--outDir', join(temp, 'dist'),
      ...modules.map(name => join(sources, `${name}.ts`))]);
    writeFileSync(join(temp, 'build-recipe'), buildRecipe);
    rmSync(installed, { recursive: true, force: true });
    renameSync(temp, installed);
    tikzDependencyNotices();
    console.log(`Prepared TikZ Editor ${version} from ${commit}.`);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
}

if (process.argv[1] && realpathSync(resolve(process.argv[1])) === realpathSync(fileURLToPath(import.meta.url))) {
  try {
    if (process.argv[2] === '--verify') tikzDependencyNotices();
    else await install();
  } catch (error) {
    console.error(`TikZ Editor setup failed: ${error.message}. If invalid, remove ${archive} and retry npm ci.`);
    process.exitCode = 1;
  }
}
