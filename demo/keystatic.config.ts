import { config, fields, collection, singleton } from '@keystatic/core';

// A small blog with a podcast, made to try Canteiro on. Open this folder
// with File › Open Site… after `npm install`.

const body = (label: string) => fields.markdoc({ label, extension: 'md', options: { image: false } });

const draft = () =>
  fields.checkbox({ label: 'Draft', description: 'Hidden on the live site.', defaultValue: true });

const TAGS = ['garden', 'walking', 'kitchen', 'village', 'weather', 'books'];

export default config({
  storage: { kind: 'local' },
  ui: {
    brand: { name: 'Orchard Lane' },
    navigation: {
      Content: ['posts', 'asides', 'episodes-kitchen-table', 'pages'],
      Settings: ['site', 'kitchenTable'],
    },
  },
  collections: {
    posts: collection({
      label: 'Posts',
      slugField: 'title',
      path: 'src/content/posts/*',
      format: { contentField: 'content' },
      entryLayout: 'content',
      previewUrl: '/posts/{slug}/',
      schema: {
        title: fields.slug({ name: { label: 'Title' } }),
        draft: draft(),
        date: fields.datetime({ label: 'Date', defaultValue: { kind: 'now' } }),
        description: fields.text({
          label: 'Description',
          description: 'For search results and share cards.',
          validation: { length: { max: 160 } },
        }),
        tags: fields.multiselect({ label: 'Tags', options: TAGS.map((t) => ({ label: t, value: t })) }),
        cover: fields.image({ label: 'Cover', directory: 'src/assets/posts', publicPath: '../../assets/posts/' }),
        content: body('Content'),
      },
    }),
    asides: collection({
      label: 'Asides',
      slugField: 'slug',
      path: 'src/content/asides/*',
      format: { data: 'yaml' },
      schema: {
        slug: fields.text({ label: 'Address' }),
        date: fields.datetime({ label: 'Date', defaultValue: { kind: 'now' } }),
        text: fields.text({ label: 'Text', multiline: true }),
      },
    }),
    'episodes-kitchen-table': collection({
      label: 'Kitchen Table episodes',
      slugField: 'title',
      path: 'src/content/kitchen-table/*',
      format: { contentField: 'content' },
      schema: {
        title: fields.slug({ name: { label: 'Title' } }),
        draft: draft(),
        date: fields.datetime({ label: 'Date', defaultValue: { kind: 'now' } }),
        episodeNumber: fields.integer({ label: 'Episode number' }),
        audioUrl: fields.url({ label: 'Audio URL' }),
        duration: fields.text({ label: 'Duration', description: 'hh:mm:ss' }),
        guid: fields.text({ label: 'GUID', description: 'Never change it after publishing.' }),
        mimeType: fields.text({ label: 'Audio type', defaultValue: 'audio/mpeg' }),
        content: body('Show notes'),
      },
    }),
    pages: collection({
      label: 'Pages',
      slugField: 'title',
      path: 'src/content/pages/*',
      format: { contentField: 'content' },
      schema: {
        title: fields.slug({ name: { label: 'Title' } }),
        draft: draft(),
        content: body('Content'),
      },
    }),
  },
  singletons: {
    site: singleton({
      label: 'Site',
      path: 'src/data/site',
      schema: {
        title: fields.text({ label: 'Site title' }),
        description: fields.text({ label: 'Description', multiline: true }),
        author: fields.text({ label: 'Author' }),
      },
    }),
    kitchenTable: singleton({
      label: 'Kitchen Table Settings',
      path: 'src/data/kitchen-table-settings',
      schema: {
        title: fields.text({ label: 'Show title' }),
        description: fields.text({ label: 'Description', multiline: true }),
        category: fields.select({
          label: 'Category',
          options: [
            { label: 'Food', value: 'Arts > Food' },
            { label: 'Home & Garden', value: 'Leisure > Home & Garden' },
          ],
          defaultValue: 'Arts > Food',
        }),
        explicit: fields.checkbox({ label: 'Explicit' }),
      },
    }),
  },
});
