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
// The same script also turns the ADR sources (the adr-*.md files that sit
// next to this app, at docs/adr-*.md) into content/2.design pages.

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
  return {
    moduleName: head.name,
    moduleDoc: head.lines.join('\n').trim(),
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
export function renderPage({ moduleName, moduleDoc, entries }) {
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

  return (
    `${frontmatter}\n\n${AI_SLOP_STAMP}\n\n${moduleDoc}\n` +
    section('Types', grouped.type) +
    section('Functions', grouped.function) +
    '\n'
  )
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
  ].join('\n')
}

// agent: claude — turn one plain-markdown ADR (an ExDoc extra from
// docs/adr-*.md) into a site page. The transform is small on purpose: the
// ADR file is the single source of truth, the site only reframes it.
export function renderAdrPage(raw) {
  const lines = raw.split('\n')
  let title = ''
  const body = []
  let chipLine = null
  let inNotice = false
  for (const line of lines) {
    const h1 = line.match(/^# (.+)$/)
    if (h1 && !title) {
      title = h1[1].trim()
      continue
    }
    // The canonical notice is a blockquote that can wrap over lines.
    // Collect all of it, then re-emit it as one chip line for the site.
    if (!chipLine && /^> \*\*AI SLOP\*\*/.test(line)) {
      inNotice = true
      chipLine = line.replace(/^> \*\*AI SLOP\*\*\s*—?\s*/, '[AI SLOP]{.ai-slop} ')
      continue
    }
    if (inNotice) {
      if (/^> ?/.test(line)) {
        chipLine += ' ' + line.replace(/^> ?/, '').trim()
        continue
      }
      inNotice = false
    }
    body.push(line)
  }
  // Description: the first plain paragraph line (not a heading, quote,
  // fence, or table), unwrapped and stripped of backticks.
  const plain = body.find((l) => l.trim() && !/^(#|>|```|\||-|\*)/.test(l.trim()))
  const description = (plain ?? '').replaceAll('`', '').trim()
  // ADR sources cross-link each other in the ExDoc form (adr-00X-....md,
  // which ExDoc rewrites to .html). The site serves them under /design/.
  const sitedBody = body.join('\n').replace(/\]\((adr-[\w-]+)\.md\)/g, '](/design/$1)')
  return [
    '---',
    `title: ${JSON.stringify(title)}`,
    `description: ${JSON.stringify(description)}`,
    '---',
    '',
    chipLine ?? AI_SLOP_STAMP,
    '',
    sitedBody.trim(),
    '',
  ].join('\n')
}

// agent: claude — the imperative shell. Two jobs:
//   1. Turn the ExDoc markdown of the library (repo root `doc/`, the
//      output of `mix docs`) into content/3.api pages.
//   2. Turn the ADR sources (docs/adr-*.md, next to this app) into
//      content/2.design pages.
// When the ExDoc output is missing (for example on a build machine without
// Elixir, such as Vercel), the existing generated pages are kept instead
// of failing.
function main() {
  const docsRoot = join(dirname(fileURLToPath(import.meta.url)), '..')
  const repoRoot = join(docsRoot, '..')

  // --- API reference ------------------------------------------------------
  const exdocDir = join(repoRoot, 'doc')
  const pattern = /^Zocam(\..+)?\.md$/
  const apiDir = join(docsRoot, 'content', '3.api')

  if (!existsSync(exdocDir) && existsSync(apiDir)) {
    console.warn('[ingest-exdoc] missing ExDoc output (doc/); keeping content/3.api.')
  } else if (!existsSync(exdocDir)) {
    console.error('[ingest-exdoc] no ExDoc output found. Run `mix docs` in the repo root first.')
    process.exit(1)
  } else {
    rmSync(apiDir, { recursive: true, force: true })
    mkdirSync(apiDir, { recursive: true })
    const modules = []
    const files = readdirSync(exdocDir).filter((f) => pattern.test(f)).sort()
    for (const file of files) {
      const parsed = parseModuleDoc(readFileSync(join(exdocDir, file), 'utf8'))
      modules.push({ moduleName: parsed.moduleName, summary: extractSummary(parsed.moduleDoc) })
      writeFileSync(join(apiDir, `${moduleSlug(parsed.moduleName)}.md`), renderPage(parsed))
    }
    modules.sort((a, b) => a.moduleName.localeCompare(b.moduleName))
    writeFileSync(join(apiDir, 'index.md'), renderIndex(modules))
    writeFileSync(join(apiDir, '.navigation.yml'), 'title: "API Reference"\nicon: i-lucide-braces\n')
    console.log(`[ingest-exdoc] wrote ${modules.length} module pages to content/3.api/`)
  }

  // --- Design pages (ADRs) ------------------------------------------------
  // The ADR sources sit at the root of this docs app (docs/adr-*.md), so
  // the README links and the ExDoc extras in mix.exs keep working.
  const adrSrcDir = docsRoot
  const designDir = join(docsRoot, 'content', '2.design')
  const adrFiles = readdirSync(adrSrcDir).filter((f) => /^adr-\d+.*\.md$/.test(f)).sort()
  mkdirSync(designDir, { recursive: true })
  // Remove only the generated ADR pages; index.md is written by hand.
  for (const f of readdirSync(designDir)) {
    if (/\.adr-.*\.md$/.test(f)) rmSync(join(designDir, f))
  }
  adrFiles.forEach((file, i) => {
    const page = renderAdrPage(readFileSync(join(adrSrcDir, file), 'utf8'))
    writeFileSync(join(designDir, `${i + 1}.${file}`), page)
  })
  console.log(`[ingest-exdoc] wrote ${adrFiles.length} ADR pages to content/2.design/`)
}

// agent: claude — run main only when executed as a script, not when imported
// by the tests. This is the standard "module guard" pattern.
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main()
