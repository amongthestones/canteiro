import { defineCollection, z } from 'astro:content';

const posts = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    draft: z.boolean().default(false),
    date: z.coerce.date(),
    description: z.string().optional(),
    tags: z.array(z.string()).default([]),
    cover: z.string().optional(),
  }),
});

const pages = defineCollection({
  type: 'content',
  schema: z.object({ title: z.string(), draft: z.boolean().default(false) }),
});

const asides = defineCollection({
  type: 'data',
  schema: z.object({ slug: z.string(), date: z.coerce.date(), text: z.string() }),
});

const kitchenTable = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    draft: z.boolean().default(false),
    date: z.coerce.date(),
    episodeNumber: z.number(),
    audioUrl: z.string(),
    duration: z.string(),
    guid: z.string(),
    mimeType: z.string().default('audio/mpeg'),
  }),
});

export const collections = { posts, pages, asides, 'kitchen-table': kitchenTable };
