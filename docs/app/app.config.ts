// agent: claude — whole file.
// Runtime configuration read by the docus layer and by Nuxt UI.
// Colors are palette NAMES (Tailwind palettes), not hex values: Nuxt UI
// derives all shades from them. emerald = the zocam accent — the same
// board skin as the s7r site, in the color of the land the name is from.
export default defineAppConfig({
  seo: {
    title: 'Zocam',
    description: 'Composable time for Elixir: points, spans, and an interval algebra.',
  },
  header: {
    // The board name. The blinking cursor lives on the landing page only.
    title: 'ZOCAM_',
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
