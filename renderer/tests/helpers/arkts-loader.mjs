import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';

function sourceOf(relativePath) {
  if (typeof stripTypeScriptTypes !== 'function') {
    throw new Error('Node cannot strip TypeScript types');
  }
  const file = new URL(`../../../entry/src/main/ets/${relativePath}`, import.meta.url);
  return stripTypeScriptTypes(readFileSync(file, 'utf8')
    .replace(/^import .*;\s*$/gm, '')
    .replace(/^export /gm, ''));
}

/** Load one ArkTS file. relativePath is under entry/src/main/ets. */
export function loadArkts(relativePath, exportsExpression, bindings = {}) {
  return vm.runInNewContext(`${sourceOf(relativePath)}\n${exportsExpression}`, bindings);
}

/** Load several ArkTS files into one realm so they can call each other after imports are removed. */
export function loadArktsModules(relativePaths, exportsExpression, bindings = {}) {
  const context = vm.createContext(bindings);
  for (const relativePath of relativePaths) vm.runInContext(`${sourceOf(relativePath)}\n`, context);
  return vm.runInContext(exportsExpression, context);
}
