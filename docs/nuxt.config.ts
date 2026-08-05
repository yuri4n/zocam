// agent: claude — whole file.
// The site is a thin Nuxt 4 app. All docs behavior comes from the `docus`
// layer (a Nuxt "layer" is a reusable app that another app extends — the
// layer pattern is class inheritance for whole apps).
//
// Theming does NOT happen here: Docus imports app/app.css automatically
// and reads app/app.config.ts. This file only sets app-level plumbing.
export default defineNuxtConfig({
  extends: ['docus'],

  // The board is dark by default; the visitor can still flip the toggle.
  colorMode: {
    preference: 'dark',
    fallback: 'dark',
  },

  app: {
    head: {
      link: [{ rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' }],
    },
  },
})
