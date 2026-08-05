<!-- agent: claude — whole file.
  Shadows the docus component of the same name (see DocsAsideLeftBody for
  the pattern). This one is the navigation inside the mobile header menu;
  it must show the same links as the desktop aside.
-->
<script setup lang="ts">
import type { ContentNavigationItem } from '@nuxt/content'

const navigation = inject<Ref<ContentNavigationItem[]>>('navigation')
</script>

<template>
  <DocsSectionNav :navigation="navigation ?? []" />
</template>
