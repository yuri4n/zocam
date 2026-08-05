<!-- agent: claude — whole file.
  The docs section navigation. We render it ourselves instead of using
  UContentNavigation for two reasons:

  - A section head must be a LINK to the section's index page. The Nuxt UI
    component renders heads as accordion <button>s, and disabled ones when
    the accordion cannot collapse.
  - The index page must not repeat as the first child ("first page").
    Here the head IS the index link, so the child disappears.

      navigation tree                     rendered nav
      ┌ Design (ADRs) ────────┐            Design (ADRs)  ◀ link to /design
      │ ├ index    (/design)  │  ──▶        ├ ADR-001     ◀ link
      │ ├ ADR-001             │             └ ADR-002     ◀ link
      │ └ ADR-002             │
      └───────────────────────┘
-->
<script setup lang="ts">
import type { ContentNavigationItem } from '@nuxt/content'

const props = defineProps<{ navigation: ContentNavigationItem[] }>()

// A head without an index page still needs a target: its first leaf.
function firstLeafPath(item: ContentNavigationItem): string {
  let current = item
  while (current.children?.length) current = current.children[0]!
  return current.path
}

// agent: claude — changed: a child can itself be a folder without a page
// (content/2.design/adrs/). Such a child has nothing to link to, so its
// leaves join the list in its place: the section stays one flat list.
function leaves(items: ContentNavigationItem[]): ContentNavigationItem[] {
  return items.flatMap((item) =>
    item.children?.length
      ? leaves(item.children.filter((child) => child.path !== item.path))
      : [item],
  )
}

const sections = computed(() =>
  (props.navigation ?? []).map((item) => {
    const children = leaves((item.children ?? []).filter((child) => child.path !== item.path))
    const hasIndex = (item.children ?? []).some((child) => child.path === item.path)
    return {
      title: item.title,
      icon: item.icon as string | undefined,
      to: hasIndex ? item.path : firstLeafPath(item),
      children,
    }
  }),
)
</script>

<template>
  <nav class="section-nav" aria-label="Documentation">
    <div v-for="section in sections" :key="section.to" class="section-nav-group">
      <NuxtLink :to="section.to" class="section-nav-head">
        <UIcon v-if="section.icon" :name="section.icon" class="section-nav-icon" />
        <span>{{ section.title }}</span>
      </NuxtLink>
      <ul v-if="section.children.length" class="section-nav-list">
        <li v-for="child in section.children" :key="child.path">
          <NuxtLink :to="child.path">{{ child.title }}</NuxtLink>
        </li>
      </ul>
    </div>
  </nav>
</template>
