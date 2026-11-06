import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { createHash } from 'node:crypto';

// Produce the notices shipped inside the HAP from *installed production packages*.
// Unknown / missing licenses abort the build instead of silently omitting a grant.
const root = resolve(import.meta.dirname, '..');
const manifest = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
const packages = new Map();
// Some upstream packages publish no LICENSE in their npm archive. These entries point to
// original license texts and version-specific declarations, verified offline by package version and hash.
const fallbackRoot = join(root, '..', 'third_party', 'upstream-licenses');
const fallbacks = JSON.parse(readFileSync(join(fallbackRoot, 'manifest.json'), 'utf8'));

// PSF-2.0 is used by the locked argparse@3.0.4 dependency. Its complete upstream LICENSE
// is emitted below with the other production notices.
const accepted = /^(?:MIT|ISC|BSD-2-Clause|BSD-3-Clause|Apache-2\.0|0BSD|Unlicense|CC0-1\.0|CC-BY-3\.0|Python-2\.0|PSF-2\.0)$/;

function locate(from, name) {
  let at = from;
  for (;;) {
    const dir = join(at, 'node_modules', ...name.split('/'));
    if (existsSync(join(dir, 'package.json'))) return dir;
    const up = dirname(at);
    if (up === at) break;
    at = up;
  }
  throw new Error(`Missing installed package: ${name} (required by ${from})`);
}
function licenseFile(dir, pkg, expression) {
  const filenames = readdirSync(dir);
  // Package managers also ship complete grants as e.g. LICENSE-MIT.txt. Restrict the suffix to
  // the declared SPDX family so a README can never become a substitute notice.
  const found = filenames.find(f => /^(?:licen[sc]e|copying)(?:[-_.](?:mit|isc|bsd(?:-[23]-clause)?|apache-2\.0|psf-2\.0))?(?:\.(?:md|txt))?$/i.test(f));
  if (found) return readFileSync(join(dir, found), 'utf8');
  const entry = fallbacks.find(p => p.name === pkg.name && p.version === pkg.version && p.license === expression);
  if (!entry || !/^[A-Za-z0-9_.-]+$/.test(entry.file)) throw new Error(`Missing license text: ${pkg.name}@${pkg.version}`);
  const bytes = readFileSync(join(fallbackRoot, entry.file));
  if (createHash('sha256').update(bytes).digest('hex') !== entry.sha256) {
    throw new Error(`Upstream license hash mismatch: ${pkg.name}@${pkg.version}`);
  }
  return bytes.toString('utf8');
}
function visit(from, name) {
  const dir = locate(from, name);
  if (packages.has(dir)) return;
  const pkg = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8'));
  let expression = pkg.license;
  if (expression === '(MPL-2.0 OR Apache-2.0)' || expression === 'MPL-2.0 OR Apache-2.0') {
    expression = 'Apache-2.0';
  }
  if (!accepted.test(expression || '')) {
    throw new Error(`Review required: ${pkg.name}@${pkg.version} uses ${JSON.stringify(pkg.license)}`);
  }
  const text = licenseFile(dir, pkg, expression);
  if (!text.trim()) throw new Error(`Empty license: ${pkg.name}`);
  const noticeName = readdirSync(dir).find(f => /^notice(?:\.txt|\.md)?$/i.test(f));
  let notice = noticeName ? readFileSync(join(dir, noticeName), 'utf8') : '';
  const fallback = fallbacks.find(p => p.name === pkg.name && p.version === pkg.version && p.license === expression);
  if (fallback?.noticeFile) {
    if (!/^[A-Za-z0-9_.-]+$/.test(fallback.noticeFile)) throw new Error(`Invalid notice path: ${pkg.name}`);
    const bytes = readFileSync(join(fallbackRoot, fallback.noticeFile));
    if (createHash('sha256').update(bytes).digest('hex') !== fallback.noticeSha256) {
      throw new Error(`Upstream notice hash mismatch: ${pkg.name}@${pkg.version}`);
    }
    notice += (notice ? '\n\n' : '') + bytes.toString('utf8');
  }
  if ((expression === 'CC-BY-3.0' || fallback?.file === 'SPDX-MIT.txt') &&
    (!fallback?.noticeFile || !notice.trim())) {
    throw new Error(`Missing verified attribution: ${pkg.name}@${pkg.version}`);
  }
  if (expression === 'Python-2.0' && (!fallback?.noticeFile || !notice.trim())) {
    throw new Error(`Missing verified change summary: ${pkg.name}@${pkg.version}`);
  }
  packages.set(dir, { name: pkg.name, version: pkg.version, license: expression, text, notice });
  for (const child of Object.keys(pkg.dependencies || {})) visit(dir, child);
}
for (const name of Object.keys(manifest.dependencies)) visit(root, name);
const all = [...packages.values()].sort((a, b) => a.name.localeCompare(b.name));
// KaTeX's official katex-fonts source distributes the fonts under MIT. The KaTeX package's
// complete MIT LICENSE is already collected as its production dependency notice; do not invent
// a separate OFL requirement for a package that does not ship one.
const sections = [
  'MarkNote — Third-party software notices',
  'For software and font assets incorporated into the offline renderer.',
  'DOMPurify is distributed under the Apache License 2.0 branch of its dual license.',
  'KaTeX and its bundled fonts are covered by the package MIT notice.',
  'The rights to MarkNote-owned code are separate from the following third-party grants.',
  'Built from the exact production dependencies installed for this release.',
  ''
];
for (const p of all) {
  sections.push('='.repeat(75), `${p.name}@${p.version}`, `License: ${p.license}`, '', p.text.trim(), '');
  if (p.notice.trim()) sections.push('Upstream NOTICE:', p.notice.trim(), '');
}
const projectLicense = join(root, '..', 'LICENSE');
if (!existsSync(projectLicense)) throw new Error('Missing project LICENSE');
const projectLicenseBytes = readFileSync(projectLicense);
const output = join(root, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'licenses');
mkdirSync(output, { recursive: true });
const file = join(output, 'THIRD_PARTY_NOTICES.txt');
writeFileSync(file, sections.join('\n') + '\n', 'utf8');
const shippedLicense = join(output, 'LICENSE');
writeFileSync(shippedLicense, projectLicenseBytes);
console.log(`Wrote ${file} (${all.length} runtime packages; ${sections.join('\n').length} characters)`);
console.log(`Copied project LICENSE to ${shippedLicense}`);
