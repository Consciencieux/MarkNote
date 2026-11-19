export interface SyntaxColors {
  keyword: string; title: string; string: string; comment: string; name: string; number: string;
}

const light: Record<string, SyntaxColors> = {
  github: { keyword: '#cf222e', title: '#8250df', string: '#0a3069', comment: '#6e7781', name: '#116329', number: '#0550ae' },
  atom: { keyword: '#a626a4', title: '#4078f2', string: '#50a14f', comment: '#a0a1a7', name: '#e45649', number: '#986801' },
  vs: { keyword: '#0000ff', title: '#795e26', string: '#a31515', comment: '#008000', name: '#0000ff', number: '#098658' }
};
const dark: Record<string, SyntaxColors> = {
  github: { keyword: '#ff7b72', title: '#d2a8ff', string: '#a5d6ff', comment: '#8b949e', name: '#7ee787', number: '#79c0ff' },
  atom: { keyword: '#c678dd', title: '#61afef', string: '#98c379', comment: '#abb2bf', name: '#e06c75', number: '#d19a66' },
  vs: { keyword: '#569cd6', title: '#dcdcaa', string: '#ce9178', comment: '#6a9955', name: '#4ec9b0', number: '#b5cea8' }
};

/** Semantic colors only: no background, geometry, typography, or selection styling. */
export function syntaxColors(name: string, appearance: string): SyntaxColors {
  const palettes = appearance === 'dark' ? dark : light;
  const key = name === 'atom-one' ? 'atom' : name === 'visual-studio' ? 'vs' : name;
  return Object.hasOwn(palettes, key) ? palettes[key] : palettes.github;
}
