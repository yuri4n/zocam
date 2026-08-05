// agent: claude — whole file.
// The shell around the pure resolver core (api-links.ts). This is the ONE
// place that binds the core to this site's data and identity:
//
//   - the real manifest that the ingest script writes, and
//   - who we are on GitHub (every repository path is ours).
//
// The components (ProseCode.vue, ProsePre.vue) use these exports through
// Nuxt auto-import, so their names must not change.

import manifest from '~/assets/api-manifest.json'
import { createApiLinks, type ApiModules } from './api-links'

const site = createApiLinks(manifest as ApiModules, {
  repoFor: () => 'yuri4n/zocam',
})

export const resolveApiRef = site.resolveApiRef
export const resolvePathRef = site.resolvePathRef
export const findRefRanges = site.findRefRanges
export const linkifyCodeElement = site.linkifyCodeElement
