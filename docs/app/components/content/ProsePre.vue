<!-- agent: claude — whole file.
  This is a proxy. Nuxt Content renders every fenced code block through a
  global component named ProsePre. Because our app-level component has
  priority over the one Nuxt UI registers, every fence passes through here.
  We intercept one language (mermaid) and forward everything else, props
  untouched, to the original Nuxt UI component.

      ```elixir fence ──▶ ProsePre (this proxy) ──▶ Nuxt UI Pre.vue
      ```mermaid fence ─▶ ProsePre (this proxy) ──▶ MermaidDiagram
-->
<script setup lang="ts">
import UProsePre from '@nuxt/ui/runtime/components/prose/Pre.vue'

const props = defineProps<{
  icon?: string
  code?: string
  language?: string
  filename?: string
  highlights?: number[]
  hideHeader?: boolean
  meta?: string
  class?: string
}>()
</script>

<template>
  <MermaidDiagram v-if="props.language === 'mermaid'" :code="props.code ?? ''" />
  <UProsePre v-else v-bind="props">
    <slot />
  </UProsePre>
</template>
