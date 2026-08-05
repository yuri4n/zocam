// agent: claude — whole file.
// The site is a thin Nuxt 4 app. All docs behavior comes from the `docus`
// layer (a Nuxt "layer" is a reusable app that another app extends — the
// layer pattern is class inheritance for whole apps).
//
// Theming does NOT happen here: Docus imports app/app.css automatically
// and reads app/app.config.ts. This file only sets app-level plumbing.
export default defineNuxtConfig({
  extends: ['docus'],

  // agent: claude — page counts for the public site.
  //
  // A "module" is the Nuxt plugin format. This one adds the small Vercel
  // Web Analytics script to every page, thus we do not write a component
  // or a plugin ourselves. It counts page views and visitors. It writes no
  // cookie and it keeps no identifier of the person, thus the site needs
  // no consent banner.
  //
  // Two facts about this site make the module behave in a special way:
  //
  //  1. The site is static (`nuxt generate`). The script is a client-side
  //     script, thus a static build is sufficient. Vercel's Edge Network
  //     serves the script from /_vercel/insights/script.js, a path that
  //     exists only on a Vercel deployment.
  //  2. Because that path exists only there, the script sends nothing from
  //     a local `pnpm dev` run. This is correct: development traffic must
  //     not pollute the numbers.
  //
  // The module is one half of the switch. The other half is on Vercel:
  // the project must have Web Analytics on (dashboard, or the command
  // `vercel project web-analytics`). With the module only, the script
  // loads and reports nothing.
  modules: ['@vercel/analytics'],

  // agent: claude — a fixed dev port, because another project depends on it.
  //
  // Nuxt defaults to 3000 and steps to 3001, 3002, … when the port is busy.
  // A moving port is fine for a site that stands alone. This one does not:
  // when s7r compiles the zocam checkout instead of the Hex release, its
  // docs link every `Zocam.*` chip to THIS server, and it must know where
  // to point before either server starts. A guessed port is a broken link.
  //
  // 4311 is arbitrary but stable, and far from the 3000 range that other
  // dev servers take first. s7r holds the same number as its fallback (see
  // its nuxt.config.ts). The two files must agree; nothing enforces it,
  // because enforcing it would mean reading across the repository boundary.
  devServer: { port: 4311 },

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
