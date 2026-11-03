import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';

// Produce the notices shipped inside the HAP from *installed production packages*.
// Unknown / missing licenses abort the build instead of silently omitting a grant.
const root = resolve(import.meta.dirname, '..');
const manifest = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
const packages = new Map();
const accepted = /^(?:MIT|ISC|BSD-2-Clause|BSD-3-Clause|Apache-2\.0|0BSD|Unlicense|CC0-1\.0)$/;

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
function licenseFile(dir) {
  const filenames = readdirSync(dir);
  const found = filenames.find(f => /^(?:licen[sc]e|copying)(?:\.(?:md|txt))?$/i.test(f));
  if (!found) throw new Error(`Missing license text: ${dir}`);
  return readFileSync(join(dir, found), 'utf8');
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
  const text = licenseFile(dir);
  if (!text.trim()) throw new Error(`Empty license: ${pkg.name}`);
  const noticeName = readdirSync(dir).find(f => /^notice(?:\.txt|\.md)?$/i.test(f));
  const notice = noticeName ? readFileSync(join(dir, noticeName), 'utf8') : '';
  packages.set(dir, { name: pkg.name, version: pkg.version, license: expression, text, notice });
  for (const child of Object.keys(pkg.dependencies || {})) visit(dir, child);
}
for (const name of Object.keys(manifest.dependencies)) visit(root, name);
const all = [...packages.values()].sort((a, b) => a.name.localeCompare(b.name));
// KaTeX math fonts have an independent SIL OFL-1.1 grant. Its software MIT
// license does not replace the font license. A missing upstream OFL blocks release.
const katexDir = locate(root, 'katex');
const fontLicenseCandidates = [
  join(katexDir, 'dist', 'fonts', 'OFL.txt'),
  join(katexDir, 'fonts', 'OFL.txt')
];
const fontLicensePath = fontLicenseCandidates.find(existsSync);
if (!fontLicensePath) throw new Error('KaTeX font license dist/fonts/OFL.txt not found; release build blocked');
const fontLicense = readFileSync(fontLicensePath, 'utf8');
if (!fontLicense.includes('SIL OPEN FONT LICENSE')) throw new Error('Unexpected KaTeX font license content');
const sections = [
  'Marknote — Third-party software notices',
  'For software and font assets incorporated into the offline renderer.',
  'DOMPurify is distributed under the Apache License 2.0 branch of its dual license.',
  'KaTeX math fonts are distributed separately under SIL Open Font License 1.1.',
  'The rights to Marknote-owned code are separate from the following third-party grants.',
  'Built from the exact production dependencies installed for this release.',
  ''
];
for (const p of all) {
  sections.push('='.repeat(75), `${p.name}@${p.version}`, `License: ${p.license}`, '', p.text.trim(), '');
  if (p.notice.trim()) sections.push('Upstream NOTICE:', p.notice.trim(), '');
}
sections.push('='.repeat(75), 'KaTeX math fonts (embedded in CSS as font assets)',
  'License: SIL Open Font License 1.1', '', fontLicense.trim(), '');
const output = join(root, '..', 'entry', 'src', 'main', 'resources', 'rawfile', 'licenses');
mkdirSync(output, { recursive: true });
const file = join(output, 'THIRD_PARTY_NOTICES.txt');
writeFileSync(file, sections.join('\n') + '\n', 'utf8');
console.log(`Wrote ${file} (${all.length} runtime packages; ${sections.join('\n').length} characters)`);
