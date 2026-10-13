// Prints the site's Keystatic config as JSON: the sidebar groups, every
// collection and singleton with its path and format, and each field's type,
// label, description, options and limits, in the order the config lists them.
// Canteiro builds its forms from this, so the field list lives in one place:
// the site's keystatic.config.ts.
//
// Usage: node schema-dump.mjs <site folder>
// Loads the config through the site's own Vite, so it needs the site's
// node_modules. Takes about a quarter second.

import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = resolve(process.argv[2] ?? process.cwd());

// Import the site's Vite, not one next to this script.
const require = createRequire(join(root, 'package.json'));
const vitePkgPath = require.resolve('vite/package.json');
const vitePkg = JSON.parse(readFileSync(vitePkgPath, 'utf8'));
const entry = vitePkg.exports['.'].import;
const entryPath = typeof entry === 'string' ? entry : entry.default;
const { createServer } = await import(pathToFileURL(join(dirname(vitePkgPath), entryPath)).href);

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

// Astro's content schema holds rules Keystatic can't express, like "a post
// has one kind" (a list capped at one). Load it with a stand-in for the
// astro:content module so its zod schemas can be read.
const astroContent = {
  name: 'astro-content-stub',
  enforce: 'pre',
  resolveId(id) {
    if (id === 'astro:content') return '\0astro-content-stub';
  },
  load(id) {
    if (id === '\0astro-content-stub') return `export { z } from 'astro/zod'; export const defineCollection = (c) => c;`;
  },
};

const vite = await createServer({
  root, configFile: false, logLevel: 'silent', server: { middlewareMode: true }, appType: 'custom',
  optimizeDeps: { noDiscovery: true, include: [] }, plugins: [tagFields, astroContent],
});
const { default: cfg } = await vite.ssrLoadModule('/keystatic.config.ts');
let astroCollections = {};
try {
  astroCollections = (await vite.ssrLoadModule('/src/content/config.ts')).collections ?? {};
} catch {
  // No Astro schema, or one this can't load: Keystatic's rules still apply.
}
await vite.close();

// The zod object behind a collection, past .refine() and friends.
function zodShape(schema) {
  let s = schema;
  while (s?._def?.schema || s?._def?.innerType) s = s._def.schema ?? s._def.innerType;
  return typeof s?.shape === 'function' ? s.shape() : s?.shape;
}

// Limits per Astro collection and field: { posts: { categories: { maxItems: 1 } } }.
const limits = {};
for (const [name, collection] of Object.entries(astroCollections)) {
  const shape = zodShape(collection?.schema);
  if (!shape) continue;
  for (const [key, field] of Object.entries(shape)) {
    let f = field;
    while (f?._def?.innerType) f = f._def.innerType;
    const max = f?._def?.maxLength?.value;
    if (f?._def?.typeName === 'ZodArray' && max != null) (limits[name] ??= {})[key] = { maxItems: max };
  }
}

// A Keystatic path (src/content/episodes/myshow/*) names its Astro
// collection by the folder after src/content/.
const astroName = (path) => path.match(/^src\/content\/([^/*]+)/)?.[1];

// JSON objects lose their order in most decoders, and a form needs it, so
// every map of fields becomes a list with the key inside.
const list = (obj, fn) => Object.entries(obj).map(([key, v]) => ({ key, ...fn(v) }));

function field(f) {
  // Settings are the helper's last argument. For object and conditional it's
  // the child fields, read below instead. Functions (itemLabel) drop out.
  const settings = ['object', 'conditional'].includes(f.type) ? {} : JSON.parse(JSON.stringify(f.settings ?? {}));
  const out = { type: f.type, label: f.label, ...settings };
  if (f.fields) out.fields = list(f.fields, field);
  if (f.element) out.element = field(f.element);
  if (f.discriminant) {
    out.discriminant = field(f.discriminant);
    out.values = list(f.values, field);
  }
  if (f.collection) out.collection = f.collection;
  return out;
}

const item = (kind) => (c) => {
  const extra = limits[astroName(c.path)] ?? {};
  return {
    kind, label: c.label, path: c.path, format: c.format ?? 'yaml',
    slugField: c.slugField, previewUrl: c.previewUrl, columns: c.columns,
    fields: list(c.schema, field).map((f) => ({ ...f, ...extra[f.key] })),
  };
};

console.log(JSON.stringify({
  navigation: cfg.ui?.navigation ? Object.entries(cfg.ui.navigation).map(([name, keys]) => ({ name, keys })) : null,
  items: [...list(cfg.collections ?? {}, item('collection')), ...list(cfg.singletons ?? {}, item('singleton'))],
}));
