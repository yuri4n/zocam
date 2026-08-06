// agent: claude — whole file.
// Transform ExDoc's markdown output (../doc/*.md) into Nuxt Content pages
// (content/3.api/*.md). This is an adapter: it converts one fixed format into
// another and holds no knowledge about the Elixir code itself.
//
//   doc/Zocam.Point.md              content/3.api/zocam-point.md
//   ┌──────────────────────┐         ┌────────────────────────────────┐
//   │ # `Zocam.Point`      │         │ ---                            │
//   │ moduledoc …          │  ────▶  │ title / description            │
//   │ # `chain`  (@type)   │         │ ---                            │
//   │ # `union`  (@spec)   │         │ moduledoc … ## Types ## Funcs  │
//   └──────────────────────┘         └────────────────────────────────┘
//
// ExDoc gives every symbol an h1 and loses arities. We rebuild a hierarchy:
// moduledoc keeps its h2 sections, entries become h3 under "## Types" or
// "## Functions", and entry-body headings shift down by 2 so they nest.
//
// Every parser here walks line by line and tracks one bit of state: "am I
// inside a ``` fence?". Lines inside fences are never headings. Indented
// code blocks need no state: their lines never start at column zero.
//
// This script has ONE job: the API reference. The design records under
// content/2.design/adrs/ are hand-written sources that are committed as
// they are. No step generates them.

import { readdirSync, readFileSync, writeFileSync, rmSync, mkdirSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

// agent: claude — "Zocam.Intervals" → "zocam-intervals".
// Dots would fight the router's extension parsing, so they become dashes.
export function moduleSlug(moduleName) {
  return moduleName.toLowerCase().replaceAll('.', '-')
}

// agent: claude — split a raw ExDoc markdown file into
// { moduleName, moduleDoc, entries: [{ name, body }] }.
// An entry starts at each h1 of the form  # `name`  found OUTSIDE fences.
export function parseModuleDoc(raw) {
  const lines = raw.split('\n')
  const H1 = /^# `(.+)`\s*$/
  let inFence = false
  const sections = [] // [{ name, lines }]
  let current = null
  for (const line of lines) {
    if (line.startsWith('```')) inFence = !inFence
    const m = !inFence && line.match(H1)
    if (m) {
      current = { name: m[1], lines: [] }
      sections.push(current)
    } else if (current) {
      current.lines.push(line)
    }
  }
  const [head, ...rest] = sections
  // agent: claude — changed: ExDoc writes the module source link as the
  // first moduledoc line, in the form "[🔗](https://…/file.ex#L7)". We lift
  // it out into data. Before this change it leaked into the summary and the
  // page body, where it rendered as raw text.
  const rawDoc = head.lines.join('\n').trim()
  const src = rawDoc.match(/^\[🔗\]\((\S+)\)\s*/)
  return {
    moduleName: head.name,
    sourceUrl: src ? src[1] : null,
    moduleDoc: src ? rawDoc.slice(src[0].length).trim() : rawDoc,
    entries: rest.map((s) => ({ name: s.name, body: s.lines.join('\n').trim() })),
  }
}

// agent: claude — an entry is a type when its first fence declares one.
// ExDoc always puts the @type/@opaque declaration in the first fence.
export function classifyEntry(entry) {
  const fence = entry.body.match(/```elixir\n([^\n]*)/)
  return fence && /^@(type|typep|opaque)\b/.test(fence[1]) ? 'type' : 'function'
}

// agent: claude — demote every heading by `delta` levels, fences untouched.
export function shiftHeadings(body, delta) {
  let inFence = false
  return body
    .split('\n')
    .map((line) => {
      if (line.startsWith('```')) inFence = !inFence
      const m = !inFence && line.match(/^(#{1,4})(\s.*)$/)
      return m ? '#'.repeat(Math.min(m[1].length + delta, 6)) + m[2] : line
    })
    .join('\n')
}

// agent: claude — the first paragraph, unwrapped to one line, backticks
// stripped. It becomes the plain-text description in the frontmatter.
export function extractSummary(moduleDoc) {
  const firstParagraph = moduleDoc.split(/\n\s*\n/)[0] ?? ''
  return firstParagraph.split('\n').join(' ').replaceAll('`', '').trim()
}

// agent: claude — assemble one Nuxt Content page from a parsed module.
export function renderPage({ moduleName, sourceUrl, moduleDoc, entries }) {
  const grouped = { type: [], function: [] }
  for (const entry of entries) grouped[classifyEntry(entry)].push(entry)

  const section = (title, list) =>
    list.length === 0
      ? ''
      : `\n## ${title}\n\n` +
        list.map((e) => `### \`${e.name}\`\n\n${shiftHeadings(e.body, 2)}`).join('\n\n')

  const frontmatter = [
    '---',
    `title: ${JSON.stringify(moduleName)}`,
    `description: ${JSON.stringify(extractSummary(moduleDoc))}`,
    '---',
  ].join('\n')

  // agent: claude — the lifted source link renders as a small chip under
  // the stamp; app.css styles the .source-link class per skin.
  const sourceLine = sourceUrl ? `\n\n[Source on GitHub ↗](${sourceUrl}){.source-link}` : ''

  return (
    `${frontmatter}\n\n${AI_SLOP_STAMP}${sourceLine}\n\n${moduleDoc}\n` +
    section('Types', grouped.type) +
    section('Functions', grouped.function) +
    '\n'
  )
}

// agent: claude — the anchor id that the site gives a heading at run time.
// Nuxt Content uses github-slugger: lowercase, punctuation dropped, spaces
// become dashes, and a repeated id gets "-1", "-2", … . computeAnchors
// emulates that here, at build time, so generated links can point at real
// anchors. This is the same "adapter" idea as the rest of this file: we
// re-create the other system's rule instead of asking it.
export function computeAnchors(markdown) {
  const seen = new Map()
  const anchors = [] // [{ level, text, id }]
  let inFence = false
  for (const line of markdown.split('\n')) {
    if (line.startsWith('```')) {
      inFence = !inFence
      continue
    }
    const m = !inFence && line.match(/^(#{1,6})\s+(.+)$/)
    if (!m) continue
    const text = m[2].replaceAll('`', '').trim()
    const base = text.toLowerCase().replace(/[^\p{L}\p{N}_\- ]+/gu, '').replace(/\s+/g, '-')
    const n = seen.get(base) ?? 0
    seen.set(base, n + 1)
    anchors.push({ level: m[1].length, text, id: n === 0 ? base : `${base}-${n}` })
  }
  return anchors
}

// agent: claude — one manifest row per module: the page slug plus the
// anchor of every type and every function heading. The site components
// read the merged JSON (app/assets/api-manifest.json) to turn code
// references such as `Zocam.Span.t()` into links.
export function moduleManifest(parsed) {
  const manifest = { slug: moduleSlug(parsed.moduleName), types: {}, functions: {} }
  let section = null
  for (const a of computeAnchors(renderPage(parsed))) {
    if (a.level === 2) {
      section = a.text === 'Types' ? 'types' : a.text === 'Functions' ? 'functions' : null
    } else if (a.level === 3 && section && !(a.text in manifest[section])) {
      manifest[section][a.text] = a.id
    }
  }
  return manifest
}

// agent: claude — the public provenance stamp, in the canonical wording that
// the project rules ("Attribution") require: AI authorship, one reviewer
// link, and the honest limit of a human review.
const AI_SLOP_STAMP =
  '[AI SLOP]{.ai-slop} An AI agent wrote the docstrings; `mix docs` generated this page. ' +
  '[yuri4n](https://github.com/yuri4n), a senior engineer, gave the direction and did the ' +
  'review. The review is human, thus errors can stay.'

// agent: claude — the API landing page: one timetable row per module.
// Unlike the s7r site, this site documents ONE library, so there is no
// Library column.
// agent: claude — changed (2026-08-05): the table is a figure, and the
// attribution rules give every figure a caption directly below it. The
// caption has three parts: the figure name, one line on what the figure
// shows, and the note that AI made it.
export function renderIndex(modules) {
  const rows = modules
    .map((m) => `| [${m.moduleName}](/api/${moduleSlug(m.moduleName)}) | ${m.summary} |`)
    .join('\n')
  return [
    '---',
    'title: "API Reference"',
    'description: "All public modules of zocam, generated from the Elixir docstrings by mix docs."',
    '---',
    '',
    AI_SLOP_STAMP,
    '',
    'To change this reference, edit the `@doc` and `@moduledoc` attributes',
    'in `lib/`, run `mix docs` in the repository root, and rebuild.',
    '',
    '| Module | Summary |',
    '| --- | --- |',
    rows,
    '',
    '_Figure 1 — Every public module of zocam, with the first line of its' +
      ' moduledoc. AI generated, human reviewed._',
    '',
  ].join('\n')
}

// agent: claude — the imperative shell. One job: turn the ExDoc markdown of
// the library (repo root `doc/`, the output of `mix docs`) into
// content/3.api pages.
// When the ExDoc output is missing (for example on a build machine without
// Elixir, such as Vercel), the existing generated pages are kept instead
// of failing.
function main() {
  const docsRoot = join(dirname(fileURLToPath(import.meta.url)), '..')
  const repoRoot = join(docsRoot, '..')

  const exdocDir = join(repoRoot, 'doc')
  const pattern = /^Zocam(\..+)?\.md$/
  const apiDir = join(docsRoot, 'content', '3.api')

  // agent: claude — changed (2026-08-05, bug fix): the manifest write lived
  // only in the "we have ExDoc output" branch below. On a machine without
  // Elixir the file could thus be absent, and the static import in
  // app/utils/api-refs.ts cannot resolve an absent file, so the site build
  // stopped before it started. The floor is now unconditional: `{}` is a
  // valid manifest that maps no module. We write it only when the file does
  // not exist, so the committed manifest is never replaced by an empty one.
  const assetsDir = join(docsRoot, 'app', 'assets')
  const manifestFile = join(assetsDir, 'api-manifest.json')
  mkdirSync(assetsDir, { recursive: true })
  if (!existsSync(manifestFile)) writeFileSync(manifestFile, '{}\n')

  if (!existsSync(exdocDir) && existsSync(apiDir)) {
    console.warn('[ingest-exdoc] missing ExDoc output (doc/); keeping content/3.api.')
  } else if (!existsSync(exdocDir)) {
    console.error('[ingest-exdoc] no ExDoc output found. Run `mix docs` in the repo root first.')
    process.exit(1)
  } else {
    rmSync(apiDir, { recursive: true, force: true })
    mkdirSync(apiDir, { recursive: true })
    const modules = []
    const manifest = {}
    const files = readdirSync(exdocDir).filter((f) => pattern.test(f)).sort()
    for (const file of files) {
      const parsed = parseModuleDoc(readFileSync(join(exdocDir, file), 'utf8'))
      modules.push({ moduleName: parsed.moduleName, summary: extractSummary(parsed.moduleDoc) })
      manifest[parsed.moduleName] = moduleManifest(parsed)
      writeFileSync(join(apiDir, `${moduleSlug(parsed.moduleName)}.md`), renderPage(parsed))
    }
    modules.sort((a, b) => a.moduleName.localeCompare(b.moduleName))
    writeFileSync(join(apiDir, 'index.md'), renderIndex(modules))
    writeFileSync(join(apiDir, '.navigation.yml'), 'title: "API Reference"\nicon: i-lucide-braces\n')
    // agent: claude — the API manifest feeds the link components (see
    // app/utils/api-links.ts). It is committed, like content/3.api, so a
    // build machine without Elixir keeps the last generated version.
    writeFileSync(manifestFile, JSON.stringify(manifest, null, 2) + '\n')
    console.log(`[ingest-exdoc] wrote ${modules.length} module pages to content/3.api/`)
  }
}

// agent: claude — run main only when executed as a script, not when imported
// by the tests. This is the standard "module guard" pattern.
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main()
