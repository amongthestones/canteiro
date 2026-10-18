# Orchard Lane: a demo site for Canteiro

A small Astro blog with a podcast, made to try Canteiro on and to take its screenshots. Everything in it is made up.

It has posts (one a draft, one with a cover image), asides, three podcast episodes, two pages, two settings screens and an inbox with two drafts. Its `canteiro.json` turns on the inbox, uploads, podcasts and the extra Markdown syntax.

## Try it

```sh
cd demo
npm install
```

Then in Canteiro, File › Open Site… and choose the `demo` folder. `npm run dev` starts the site for Preview.

Publish needs a git repo of the site's own. To try it, copy the folder somewhere outside this repo first and run `git init` there.

Uploads point at a bucket called `demo-media`, which doesn't exist, so a dropped photo or MP3 stops with an error from R2.
