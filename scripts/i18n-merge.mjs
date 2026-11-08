/**
 * Merge translated chunks into the rawfile catalogs the app loads.
 *
 *   node scripts/i18n-merge.mjs <chunks-dir>
 *
 * `<chunks-dir>/<language>/<n>.json` is a JSON object mapping Chinese source
 * strings to translations. Every key must appear in `scripts/i18n-source.json`
 * (generated from the wrapped literals); missing translations are reported and
 * left to fall back to English at runtime.
 */
import { readFileSync, readdirSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = dirname(here);
const source = JSON.parse(readFileSync(join(here, 'i18n-source.json'), 'utf8'));
const sourceSet = new Set(source);
const outDir = join(root, 'entry/src/main/resources/rawfile/i18n');

const chunksDir = process.argv[2];
if (!chunksDir) {
  console.error('usage: node scripts/i18n-merge.mjs <chunks-dir>');
  process.exit(2);
}

let failed = false;
for (const language of readdirSync(chunksDir)) {
  const dir = join(chunksDir, language);
  let files;
  try {
    files = readdirSync(dir).filter((name) => name.endsWith('.json')).sort();
  } catch {
    continue;
  }
  if (files.length === 0) {
    continue;
  }
  const merged = {};
  for (const file of files) {
    const part = JSON.parse(readFileSync(join(dir, file), 'utf8'));
    for (const [key, value] of Object.entries(part)) {
      if (!sourceSet.has(key)) {
        console.warn(`${language}/${file}: key not in source catalog: ${JSON.stringify(key)}`);
        continue;
      }
      if (typeof value !== 'string') {
        console.warn(`${language}/${file}: non-string translation for ${JSON.stringify(key)}`);
        continue;
      }
      merged[key] = value;
    }
  }
  const missing = source.filter((key) => merged[key] === undefined);
  if (missing.length > 0) {
    console.warn(`${language}: ${missing.length} missing, e.g. ${JSON.stringify(missing.slice(0, 3))}`);
  }
  if (missing.length > source.length * 0.02) {
    console.error(`${language}: too many missing translations, not writing`);
    failed = true;
    continue;
  }
  if (!existsSync(outDir)) {
    console.error(`missing output directory: ${outDir}`);
    process.exit(1);
  }
  writeFileSync(join(outDir, `${language}.json`),
    JSON.stringify(merged, null, 0) + '\n', 'utf8');
  console.log(`${language}: ${Object.keys(merged).length}/${source.length} strings`);
}

process.exit(failed ? 1 : 0);
