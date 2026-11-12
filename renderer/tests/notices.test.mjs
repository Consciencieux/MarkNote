import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, copyFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';

function fixture(t, { version = '1.0.0', hashMismatch = false, path = 'license.txt', licenseId = 'MIT',
  includeNotice = true, omitLicense = false, shipLicense = false } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'marknote-notices-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const renderer = join(root, 'renderer');
  const scripts = join(renderer, 'scripts');
  const vendor = join(root, 'third_party', 'upstream-licenses');
  const pkg = join(renderer, 'node_modules', 'example');
  for (const dir of [scripts, vendor, pkg]) mkdirSync(dir, { recursive: true });
  copyFileSync(new URL('../scripts/generate-notices.mjs', import.meta.url), join(scripts, 'generate-notices.mjs'));
  writeFileSync(join(root, 'LICENSE'), 'Project license');
  writeFileSync(join(renderer, 'package.json'), JSON.stringify({ dependencies: { example: version } }));
  const packageJson = { name: 'example', version, license: licenseId };
  if (omitLicense) delete packageJson.license;
  writeFileSync(join(pkg, 'package.json'), JSON.stringify(packageJson));
  const license = 'Original upstream permission text';
  if (shipLicense) writeFileSync(join(pkg, 'license'), license);
  const notice = 'Original upstream attribution';
  const sha = text => createHash('sha256').update(text).digest('hex');
  writeFileSync(join(vendor, 'license.txt'), license);
  writeFileSync(join(vendor, 'notice.txt'), notice);
  writeFileSync(join(vendor, 'manifest.json'), JSON.stringify([{
    name: 'example', version: '1.0.0', license: licenseId, file: path,
    sha256: hashMismatch ? 'bad' : sha(license),
    ...(includeNotice ? { noticeFile: 'notice.txt', noticeSha256: sha(notice) } : {})
  }]));
  return { root, renderer, script: join(scripts, 'generate-notices.mjs'), license, notice };
}
function run(f) { return spawnSync(process.execPath, [f.script], { encoding: 'utf8' }); }

test('collects version-matched upstream license and additional notice', t => {
  const f = fixture(t);
  const result = run(f);
  assert.equal(result.status, 0, result.stderr);
  const output = readFileSync(join(f.root, 'entry/src/main/resources/rawfile/licenses/THIRD_PARTY_NOTICES.txt'), 'utf8');
  assert.ok(output.includes(f.license));
  assert.ok(output.includes(f.notice));
});

test('blocks a missing version and a modified license', t => {
  const missing = run(fixture(t, { version: '2.0.0' }));
  assert.notEqual(missing.status, 0);
  assert.match(missing.stderr, /Missing license text: example@2\.0\.0/);
  const tampered = run(fixture(t, { hashMismatch: true }));
  assert.notEqual(tampered.status, 0);
  assert.match(tampered.stderr, /Upstream license hash mismatch/);
});

test('rejects a fallback path outside the verified license directory', t => {
  const result = run(fixture(t, { path: '../license.txt' }));
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Missing license text/);
});


test('requires a verified attribution notice for CC BY', t => {
  const complete = run(fixture(t, { licenseId: 'CC-BY-3.0' }));
  assert.equal(complete.status, 0, complete.stderr);
  const missing = run(fixture(t, { licenseId: 'CC-BY-3.0', includeNotice: false }));
  assert.notEqual(missing.status, 0);
  assert.match(missing.stderr, /attribution/i);
});

test('requires a reviewed declaration when package.json omits its license', t => {
  const missing = run(fixture(t, { omitLicense: true, shipLicense: true, version: '2.0.0' }));
  assert.notEqual(missing.status, 0);
  assert.match(missing.stderr, /Review required/);
  const reviewed = run(fixture(t, { omitLicense: true, shipLicense: true }));
  assert.equal(reviewed.status, 0, reviewed.stderr);
  const tampered = run(fixture(t, { omitLicense: true, shipLicense: true, hashMismatch: true }));
  assert.notEqual(tampered.status, 0);
  assert.match(tampered.stderr, /hash mismatch/);
});

test('requires a verified change summary for Python 2.0', t => {
  const complete = run(fixture(t, { licenseId: 'Python-2.0' }));
  assert.equal(complete.status, 0, complete.stderr);
  const missing = run(fixture(t, { licenseId: 'Python-2.0', includeNotice: false }));
  assert.notEqual(missing.status, 0);
  assert.match(missing.stderr, /change summary/i);
});
