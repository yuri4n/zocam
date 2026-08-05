<!-- agent: claude — whole file.
  Renders one mermaid diagram in the browser, with a zoom lightbox.

  - The mermaid library is large, so it loads lazily (dynamic import) and
    only on pages that contain a diagram. On the server the raw source
    renders as a fallback; the client draws the SVG after hydration.
  - A click on the figure opens a full-screen overlay: the mouse wheel
    zooms, a drag pans, Escape or a click on the backdrop closes.
  - Captions are NOT added here: the project rules require a three-part
    caption written in the content, directly below each figure.
-->
<script setup lang="ts">
const props = defineProps<{ code: string }>()

const svg = ref('')
const colorMode = useColorMode()

// Each render call needs a unique element id; a module-level counter is
// enough because ids only must not repeat within one page load.
let renderSeq = 0

async function draw() {
  const { default: mermaid } = await import('mermaid')
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    theme: colorMode.value === 'dark' ? 'dark' : 'neutral',
    fontFamily: "'IBM Plex Mono', ui-monospace, monospace",
    themeVariables: {
      // The board accent, matched to ui.colors.primary = emerald.
      primaryColor: colorMode.value === 'dark' ? '#064e3b' : '#a7f3d0',
      primaryBorderColor: '#10b981',
      lineColor: '#10b981',
    },
  })
  const { svg: rendered } = await mermaid.render(`mmd-${++renderSeq}`, props.code)
  svg.value = rendered
}

onMounted(draw)
// Redraw when the visitor flips light/dark: mermaid bakes colors into the SVG.
watch(() => colorMode.value, draw)

// ── Zoom state ──────────────────────────────────────────────────────────
// One scale factor and one translation vector; CSS transform applies both.
const open = ref(false)
const scale = ref(1)
const tx = ref(0)
const ty = ref(0)

let dragging = false
let moved = false
let lastX = 0
let lastY = 0

function openZoom() {
  scale.value = 1
  tx.value = 0
  ty.value = 0
  open.value = true
}
function close() {
  open.value = false
}
function zoomBy(factor: number) {
  scale.value = Math.min(8, Math.max(0.3, scale.value * factor))
}
function reset() {
  scale.value = 1
  tx.value = 0
  ty.value = 0
}
function onWheel(e: WheelEvent) {
  zoomBy(e.deltaY < 0 ? 1.15 : 1 / 1.15)
}
function onDown(e: PointerEvent) {
  dragging = true
  moved = false
  lastX = e.clientX
  lastY = e.clientY
}
function onMove(e: PointerEvent) {
  if (!dragging) return
  moved = true
  tx.value += e.clientX - lastX
  ty.value += e.clientY - lastY
  lastX = e.clientX
  lastY = e.clientY
}
function onUp() {
  dragging = false
}
// A click on the backdrop closes the overlay — but not at the end of a drag.
function onBackdropClick(e: MouseEvent) {
  if (!moved && e.target === e.currentTarget) close()
}
function onKey(e: KeyboardEvent) {
  if (e.key === 'Escape') close()
}
watch(open, (isOpen) => {
  if (isOpen) window.addEventListener('keydown', onKey)
  else window.removeEventListener('keydown', onKey)
})
onBeforeUnmount(() => window.removeEventListener('keydown', onKey))
</script>

<template>
  <ClientOnly>
    <!-- The SVG comes from mermaid with securityLevel: strict (sanitized). -->
    <figure
      class="mermaid-figure"
      role="button"
      tabindex="0"
      title="Click to zoom"
      @click="openZoom"
      @keydown.enter="openZoom"
    >
      <div v-html="svg" />
    </figure>

    <Teleport to="body">
      <div
        v-if="open"
        class="mermaid-zoom"
        role="dialog"
        aria-label="Zoomed diagram"
        @click="onBackdropClick"
        @wheel.prevent="onWheel"
        @pointerdown="onDown"
        @pointermove="onMove"
        @pointerup="onUp"
        @pointerleave="onUp"
      >
        <div
          class="mermaid-zoom-canvas"
          :style="{ transform: `translate(${tx}px, ${ty}px) scale(${scale})` }"
          v-html="svg"
        />
        <div class="mermaid-zoom-controls">
          <button type="button" @click.stop="zoomBy(1.25)">+</button>
          <button type="button" @click.stop="zoomBy(1 / 1.25)">−</button>
          <button type="button" @click.stop="reset()">reset</button>
          <button type="button" @click.stop="close()">esc</button>
        </div>
      </div>
    </Teleport>

    <template #fallback>
      <pre class="mermaid-figure">{{ code }}</pre>
    </template>
  </ClientOnly>
</template>
