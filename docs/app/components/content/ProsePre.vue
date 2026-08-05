<!-- agent: claude — whole file.
  This is a proxy. Nuxt Content renders every fenced code block through a
  global component named ProsePre. Because our app-level component has
  priority over the one Nuxt UI registers, every fence passes through here.
  We intercept one language (mermaid) and forward everything else, props
  untouched, to the original Nuxt UI component.

      ```elixir fence ──▶ ProsePre (this proxy) ──▶ Nuxt UI Pre.vue
      ```mermaid fence ─▶ ProsePre (this proxy) ──▶ MermaidDiagram

  Added: after an elixir fence renders, we wrap the API references inside
  it (Zocam.Span.t(), compose/2, …) in links. This runs on the client
  only: the highlighted markup comes from the server, and the links are an
  enhancement on top of it (see app/utils/api-links.ts).
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

const route = useRoute()
const router = useRouter()
const wrap = ref<HTMLElement>()

onMounted(() => {
  if (props.language !== 'elixir' || !wrap.value) return
  const code = wrap.value.querySelector('pre code')
  if (code) linkifyCodeElement(code as HTMLElement, route.path, (to) => router.push(to))
})
</script>

<template>
  <MermaidDiagram v-if="props.language === 'mermaid'" :code="props.code ?? ''" />
  <div v-else ref="wrap" class="contents">
    <UProsePre v-bind="props">
      <slot />
    </UProsePre>
  </div>
</template>
