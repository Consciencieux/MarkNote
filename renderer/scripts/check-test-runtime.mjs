import { stripTypeScriptTypes } from 'node:module';
if (typeof stripTypeScriptTypes !== 'function') {
  throw new Error('Node >=22.13 with module.stripTypeScriptTypes is required; do not skip native logic tests.');
}
