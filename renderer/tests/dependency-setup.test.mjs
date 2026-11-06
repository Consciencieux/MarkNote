import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { verifyDigest } from '../scripts/setup-tex-dependency.mjs';

test('accepts only the expected upstream source bytes', () => {
  const original = Buffer.from('upstream source\n');
  const hash = createHash('sha256').update(original).digest('hex');
  assert.doesNotThrow(() => verifyDigest(original, hash, 'source'));
  assert.throws(() => verifyDigest(Buffer.from('changed source\n'), hash, 'source'), /source.*SHA-256/);
});

test('blocks builds when installed dependency output is modified', t => {
  const root = mkdtempSync(join(tmpdir(), 'marknote-dependency-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const scripts = join(root, 'scripts');
  const dependency = join(root, 'node_modules', 'tex-to-myst');
  mkdirSync(scripts, { recursive: true });
  mkdirSync(join(dependency, 'dist'), { recursive: true });
  const script = join(scripts, 'setup-tex-dependency.mjs');
  copyFileSync(new URL('../scripts/setup-tex-dependency.mjs', import.meta.url), script);
  copyFileSync(new URL('../node_modules/tex-to-myst/package.json', import.meta.url), join(dependency, 'package.json'));
  for (const file of ['parser.js', 'verbatim.js']) {
    copyFileSync(new URL(`../node_modules/tex-to-myst/dist/${file}`, import.meta.url), join(dependency, 'dist', file));
  }
  const run = () => spawnSync(process.execPath, [script, '--verify'], { encoding: 'utf8' });
  assert.equal(run().status, 0);
  writeFileSync(join(dependency, 'dist', 'parser.js'), 'modified');
  const altered = run();
  assert.notEqual(altered.status, 0);
  assert.match(altered.stderr, /parser.*SHA-256 mismatch/);
});
