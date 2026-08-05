// agent: claude — whole file.
// Runtime configuration read by the docus layer and by Nuxt UI.
// Colors are palette NAMES (Tailwind palettes), not hex values: Nuxt UI
// derives all shades from them. emerald = the zocam accent. The skin is
// the neon terminal (black + neon green, see app.css); app.css pins
// --ui-primary to the exact neon value on top of this palette.
export default defineAppConfig({
  seo: {
    title: 'Zocam',
    description: 'Composable time for Elixir: points, spans, and an interval algebra.',
  },
  header: {
    // The title stays as the aria-label and the fallback; the header
    // itself shows the logo lockup (mark + wordmark, animated SVG).
    title: 'ZOCAM_',
    logo: {
      dark: '/logo-dark.svg',
      light: '/logo-light.svg',
      alt: 'zocam — composable time for Elixir',
      favicon: '/favicon.svg',
    },
  },
  // A quiet link to the reviewer. Docus renders socials as small header icons.
  socials: {
    github: 'https://github.com/yuri4n',
  },
  ui: {
    colors: {
      primary: 'emerald',
      neutral: 'neutral',
    },
  },
})
