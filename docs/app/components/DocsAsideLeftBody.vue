<!-- agent: claude — whole file.
  Shadows the docus component of the same name: a Nuxt layer lets the app
  override any layer component by giving its file the same name. The docus
  version renders UContentNavigation (section heads as disabled buttons,
  index pages repeated as a first child); ours renders DocsSectionNav,
  where the head is the index link. The mobile menu (AppHeaderBody) shows
  the same nav, shadowed the same way.
-->
<script setup lang="ts">
import type { ContentNavigationItem } from '@nuxt/content'

// Docus provides the full navigation tree to every page under this key.
const navigation = inject<Ref<ContentNavigationItem[]>>('navigation')
</script>

<template>
  <DocsSectionNav :navigation="navigation ?? []" />
</template>
