// Prints the site's Keystatic config as JSON: every collection and singleton,
// its path and format, and each field's type, label, description, options and
// limits. The native editor builds its forms from this, so the field list lives
// in one place: keystatic.config.ts.
//
// Run from the among-the-stones folder (it needs that repo's node_modules):
//   cp scripts/schema-dump.mjs <site>/.schema-dump.mjs && cd <site> && node .schema-dump.mjs > schema.json
// Takes about a quarter second.

import { createServer } from 'vite';
const root = process.cwd();
// The field objects don't say what they are, and drop some settings
// (multiline, length limits). So swap in a copy of `fields` that tags each one
// with the helper that made it (fields.date -> 'date') and keeps its settings.
const tagFields = {
  name: 'tag-fields',
  enforce: 'pre',
  transform(code, id) {
    if (!id.endsWith('/keystatic.config.ts')) return;
    return code.replace(/import \{([^}]*)\bfields\b([^}]*)\} from '@keystatic\/core';/, (_, a, b) =>
      `import {${a}fields as realFields${b}} from '@keystatic/core';
const fields = Object.fromEntries(Object.entries(realFields).map(([n, make]) =>
  [n, typeof make === 'function' ? (...args) => ({ ...make(...args), type: n, settings: args.at(-1) }) : make]));`);
  },
};
const vite = await createServer({ root, configFile: false, logLevel: 'silent', server: { middlewareMode: true }, appType: 'custom', optimizeDeps: { noDiscovery: true, include: [] }, plugins: [tagFields] });
const { default: cfg } = await vite.ssrLoadModule('/keystatic.config.ts');
await vite.close();
function field(f) {
  // Settings are the helper's last argument. For object and conditional it's
  // the child fields, read below instead. Functions (itemLabel) drop out.
  const settings = ['object', 'conditional'].includes(f.type) ? {} : JSON.parse(JSON.stringify(f.settings ?? {}));
  const out = { type: f.type, label: f.label, ...settings };
  if (f.fields) out.fields = Object.fromEntries(Object.entries(f.fields).map(([k, v]) => [k, field(v)]));
  if (f.element) out.element = field(f.element);
  if (f.discriminant) {
    out.discriminant = field(f.discriminant); out.values = Object.fromEntries(Object.entries(f.values).map(([k, v]) => [k, field(v)])); }
  if (f.collection) out.collection = f.collection;
  return out;
}
const entry = (c) => ({ label: c.label, path: c.path, format: c.format, slugField: c.slugField, previewUrl: c.previewUrl, schema: Object.fromEntries(Object.entries(c.schema).map(([k, v]) => [k, field(v)])) });
const out = {
  collections: Object.fromEntries(Object.entries(cfg.collections).map(([k, c]) => [k, entry(c)])),
  singletons: Object.fromEntries(Object.entries(cfg.singletons).map(([k, c]) => [k, entry(c)])),
};
console.log(JSON.stringify(out, null, 1));
