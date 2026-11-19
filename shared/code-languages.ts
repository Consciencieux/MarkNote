/** Canonical fence language names shared by preview and editor. */
const ALIASES = new Map<string, string>([
  ['latex', 'latex'], ['tex', 'latex'], ['markdown', 'markdown'], ['md', 'markdown'],
  ['xml', 'xml'], ['html', 'xml'], ['json', 'json'], ['javascript', 'javascript'],
  ['js', 'javascript'], ['typescript', 'typescript'], ['ts', 'typescript'], ['arkts', 'typescript'],
  ['python', 'python'], ['py', 'python'], ['bash', 'bash'], ['sh', 'bash'], ['shell', 'bash'],
  ['yaml', 'yaml'], ['yml', 'yaml'], ['css', 'css'], ['c', 'c'], ['cpp', 'cpp'],
  ['c++', 'cpp'], ['cxx', 'cpp'], ['cc', 'cpp'], ['java', 'java']
]);

export function canonicalCodeLanguage(value: string): string | undefined {
  return ALIASES.get(value.trim().toLowerCase());
}
