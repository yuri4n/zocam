<!-- agent: claude — whole file.
  This is a proxy, like ProsePre. Nuxt Content renders every INLINE code
  span through a global component named ProseCode; our app-level component
  has priority over the Nuxt UI one. When the chip text names a module,
  type, or function of the API (app/assets/api-manifest.json knows them),
  the chip becomes a link. Everything else forwards untouched.

      `scope: :year`      ──▶ ProseCode (this proxy) ──▶ Nuxt UI Code.vue
      `Zocam.Span.of/1`   ──▶ ProseCode ──▶ NuxtLink( Nuxt UI Code.vue )
-->
<script setup lang="ts">
import UProseCode from '@nuxt/ui/runtime/components/prose/Code.vue'

const props = defineProps<{
  lang?: string
  color?: string
  class?: string
  ui?: object
}>()

const slots = useSlots()
const route = useRoute()

// Inline code holds exactly one text child, so the chip text is the
// concatenation of the slot's string children.
const text = computed(() =>
  (slots.default?.() ?? [])
    .map((n) => (typeof n.children === 'string' ? n.children : ''))
    .join(''),
)

const target = computed(() => resolveApiRef(text.value, route.path))
// External targets (GitHub, hexdocs) open in a new tab; site routes stay
// inside the SPA router.
const external = computed(() => target.value?.startsWith('http') ?? false)
</script>

<template>
  <NuxtLink
    v-if="target"
    :to="target"
    class="code-ref"
    :target="external ? '_blank' : undefined"
    :rel="external ? 'noopener' : undefined"
  >
    <UProseCode v-bind="props"><slot /></UProseCode>
  </NuxtLink>
  <UProseCode v-else v-bind="props"><slot /></UProseCode>
</template>
