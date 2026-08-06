// agent: claude — whole file.
// Tests for the ExDoc → Nuxt Content transform. Written first (TDD).
// Run with: node --test scripts/
//
// The fixture below imitates the real shape of ExDoc's markdown output:
//   # `Module.Name`        ← one h1 for the module, then the moduledoc
//   ## A moduledoc section ← moduledoc keeps its own h2 headings
//   # `type_name`          ← one h1 per type, followed by a ```elixir fence
//   # `function_name`      ← one h1 per function (arity is lost; duplicates happen)
import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  moduleSlug,
  parseModuleDoc,
  classifyEntry,
  shiftHeadings,
  extractSummary,
  renderPage,
  renderIndex,
  computeAnchors,
  moduleManifest,
} from './ingest-exdoc.mjs'

const FIXTURE = `# \`Zocam.Fake\`
[🔗](https://github.com/yuri4n/zocam/blob/main/lib/zocam/fake.ex#L1)

A fake module for tests.

It has a second paragraph that must not enter the summary.

## The unit graph

Indented code keeps its column, so this line is not a heading:

    # not a heading, it is code
    :year ── month ── day

# \`chain\`

\`\`\`elixir
@type chain() :: [segment(), ...]
\`\`\`

# \`union\`

\`\`\`elixir
@spec union(t(), t()) :: t()
\`\`\`

Joins two things.

## Examples

\`\`\`elixir
# a comment at column zero inside a fence is not a heading
union(a, b)
\`\`\`

# \`union\`

\`\`\`elixir
@spec union([t()]) :: t()
\`\`\`
`

test('moduleSlug flattens dots and downcases', () => {
  assert.equal(moduleSlug('Zocam.Intervals'), 'zocam-intervals')
  assert.equal(moduleSlug('Zocam'), 'zocam')
})

test('parseModuleDoc splits module doc and entries on h1, outside fences only', () => {
  const parsed = parseModuleDoc(FIXTURE)
  assert.equal(parsed.moduleName, 'Zocam.Fake')
  // The ExDoc source link is lifted out of the moduledoc: it becomes data,
  // not the first paragraph (it used to leak into the page description).
  assert.equal(parsed.sourceUrl, 'https://github.com/yuri4n/zocam/blob/main/lib/zocam/fake.ex#L1')
  assert.ok(!parsed.moduleDoc.includes('🔗'))
  // The moduledoc keeps its prose and its h2 section.
  assert.match(parsed.moduleDoc, /A fake module for tests\./)
  assert.match(parsed.moduleDoc, /## The unit graph/)
  // Indented code lines that start with # are NOT headings.
  assert.match(parsed.moduleDoc, /    # not a heading/)
  // Three entries: one type, two same-named functions (arities merged away).
  assert.equal(parsed.entries.length, 3)
  assert.deepEqual(parsed.entries.map((e) => e.name), ['chain', 'union', 'union'])
  // The fence comment "# a comment..." must not create a fourth entry.
  assert.match(parsed.entries[1].body, /# a comment at column zero/)
})

test('classifyEntry reads the first fence: @type/@opaque mean type', () => {
  const parsed = parseModuleDoc(FIXTURE)
  assert.equal(classifyEntry(parsed.entries[0]), 'type')
  assert.equal(classifyEntry(parsed.entries[1]), 'function')
  assert.equal(classifyEntry(parsed.entries[2]), 'function')
})

test('shiftHeadings demotes headings but never touches fenced lines', () => {
  const body = '## Examples\n\n```elixir\n# comment\n```\n'
  assert.equal(shiftHeadings(body, 2), '#### Examples\n\n```elixir\n# comment\n```\n')
})

test('extractSummary takes only the first paragraph, unwrapped, without backticks', () => {
  const summary = extractSummary('First line\nwraps here.\n\nSecond paragraph.\n')
  assert.equal(summary, 'First line wraps here.')
  assert.equal(extractSummary('Uses `Timex` inside.\n\nMore.\n'), 'Uses Timex inside.')
})

test('renderPage groups entries under Types and Functions with h3 names', () => {
  const page = renderPage(parseModuleDoc(FIXTURE))
  // Frontmatter with a quoted title and description.
  assert.match(page, /^---\ntitle: "Zocam.Fake"\ndescription: "A fake module for tests\."\n---\n/)
  // Every generated page carries the public AI SLOP provenance stamp.
  assert.match(page, /\[AI SLOP\]\{\.ai-slop\}/)
  // Group headings appear once each, types before functions.
  const typesAt = page.indexOf('## Types')
  const fnsAt = page.indexOf('## Functions')
  assert.ok(typesAt > 0 && fnsAt > typesAt)
  // Entry names become h3; the duplicate union stays duplicated.
  assert.match(page, /### `chain`/)
  assert.equal(page.match(/### `union`/g).length, 2)
  // Entry-body headings sit under the entry: h2 → h4.
  assert.match(page, /#### Examples/)
  // The lifted source link renders as a styled chip under the stamp.
  assert.match(
    page,
    /\[Source on GitHub ↗\]\(https:\/\/github\.com\/yuri4n\/zocam\/blob\/main\/lib\/zocam\/fake\.ex#L1\)\{\.source-link\}/,
  )
})

test('computeAnchors emulates the runtime heading ids, duplicates included', () => {
  const anchors = computeAnchors(renderPage(parseModuleDoc(FIXTURE)))
  const ids = anchors.map((a) => a.id)
  // Backticks vanish from the heading text before slugging.
  assert.ok(ids.includes('chain'))
  // The duplicate `union` entry gets the "-1" suffix, like github-slugger.
  assert.ok(ids.includes('union') && ids.includes('union-1'))
  // Lines inside fences are never headings.
  assert.ok(!ids.some((id) => id.includes('comment')))
})

test('moduleManifest maps each type and function to its page anchor', () => {
  const manifest = moduleManifest(parseModuleDoc(FIXTURE))
  assert.equal(manifest.slug, 'zocam-fake')
  assert.deepEqual(manifest.types, { chain: 'chain' })
  // Two arities of union share one name: the first anchor wins.
  assert.deepEqual(manifest.functions, { union: 'union' })
})

test('renderIndex writes one timetable row per module', () => {
  const index = renderIndex([
    { moduleName: 'Zocam', summary: 'The facade.' },
    { moduleName: 'Zocam.Fake', summary: 'A fake module for tests.' },
  ])
  assert.match(index, /\| \[Zocam\]\(\/api\/zocam\) \| The facade\. \|/)
  assert.match(index, /\| \[Zocam\.Fake\]\(\/api\/zocam-fake\) \| A fake module for tests\. \|/)
  // The index carries the public AI SLOP provenance stamp too.
  assert.match(index, /\[AI SLOP\]\{\.ai-slop\}/)
})

// agent: claude — the attribution rules treat the module table as a figure,
// so it needs a caption with three parts: the figure name, one line on what
// the figure shows, and the note that AI made it.
test('renderIndex captions the module table, directly below it', () => {
  const index = renderIndex([{ moduleName: 'Zocam.Fake', summary: 'A fake module for tests.' }])
  const caption = index
    .split('\n')
    .filter((line) => line.trim() !== '')
    .at(-1)
  // Part 1: the figure name opens the caption.
  assert.match(caption, /^_Figure 1 — /)
  // Part 2: one line that tells what the figure shows.
  assert.match(caption, /module/)
  // Part 3: the AI note closes the caption, in the canonical wording.
  assert.match(caption, /AI generated, human reviewed\._$/)
  // The caption sits below the table, not above it.
  assert.ok(index.indexOf('_Figure 1') > index.indexOf('| [Zocam.Fake]'))
})
