/**
 * Audit the shipped rawfile catalogs against the generated source catalog.
 *
 *   node scripts/i18n-audit.mjs
 *
 * Exits non-zero if any catalog is missing keys, has extra keys, or contains a
 * non-string value. Empty translations are reported but allowed: they are
 * intentional for date fragments and classifier suffixes.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = dirname(here);
const source = JSON.parse(readFileSync(join(here, 'i18n-source.json'), 'utf8'));
const sourceSet = new Set(source);
const dir = join(root, 'entry/src/main/resources/rawfile/i18n');

let failed = false;
const catalogs = readdirSync(dir).filter((name) => name.endsWith('.json')).sort();
for (const file of catalogs) {
  const language = file.slice(0, -5);
  if (language === 'zh-Hans') {
    continue;
  }
  const catalog = JSON.parse(readFileSync(join(dir, file), 'utf8'));
  const keys = Object.keys(catalog);
  const missing = source.filter((key) => catalog[key] === undefined);
  const extra = keys.filter((key) => !sourceSet.has(key));
  const nonString = keys.filter((key) => typeof catalog[key] !== 'string');
  const empty = keys.filter((key) => catalog[key] === '');
  const problems = missing.length + extra.length + nonString.length;
  console.log(`${language}: ${keys.length}/${source.length}` +
    ` missing=${missing.length} extra=${extra.length}` +
    ` nonString=${nonString.length} empty=${empty.length}` +
    (problems === 0 ? ' OK' : ' FAIL'));
  if (missing.length > 0) {
    console.log(`  missing e.g. ${JSON.stringify(missing.slice(0, 3))}`);
  }
  if (extra.length > 0) {
    console.log(`  extra e.g. ${JSON.stringify(extra.slice(0, 3))}`);
  }
  if (empty.length > 0) {
    console.log(`  empty e.g. ${JSON.stringify(empty.slice(0, 3))}`);
  }
  if (problems > 0) {
    failed = true;
  }
}
console.log(`${catalogs.length} catalogs checked`);
process.exit(failed ? 1 : 0);
