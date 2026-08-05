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
  renderAdrPage,
} from './ingest-exdoc.mjs'

const FIXTURE = `# \`Zocam.Fake\`

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

// ADR sources are plain markdown next to this app (ExDoc extras). The site
// turns each into an MDC page: h1 → frontmatter, provenance blockquote →
// the AI SLOP chip line, everything else untouched.
const ADR_FIXTURE = `# ADR-009: A fake decision

> **AI SLOP** — an AI agent wrote this page. [yuri4n](https://github.com/yuri4n), a senior
> engineer, gave the direction and did the review. The review is human, thus errors can stay.

## Status

Accepted (2026-08-04).

## Context

We must pick one thing over another thing (see [ADR-002](adr-002-set-primary-spans.md)).

> **Note:** ordinary blockquotes stay blockquotes.
`

test('renderAdrPage lifts the h1 into frontmatter and swaps the provenance mark for the chip', () => {
  const page = renderAdrPage(ADR_FIXTURE)
  assert.match(page, /^---\ntitle: "ADR-009: A fake decision"\n/)
  // Description comes from the first real paragraph, not the provenance quote.
  assert.match(page, /description: "Accepted \(2026-08-04\)\."/)
  // The h1 is gone; sections keep their levels.
  assert.ok(!page.includes('# ADR-009'))
  assert.match(page, /## Status/)
  // The two-line canonical blockquote becomes one chip line, joined.
  assert.match(
    page,
    /\[AI SLOP\]\{\.ai-slop\} an AI agent wrote this page\. \[yuri4n\]\(https:\/\/github\.com\/yuri4n\), a senior engineer, gave the direction and did the review\./,
  )
  assert.ok(!page.includes('> **AI SLOP**'))
  // Ordinary blockquotes survive.
  assert.match(page, /> \*\*Note:\*\*/)
  // Relative ADR links (the ExDoc form) become site routes.
  assert.match(page, /\[ADR-002\]\(\/design\/adr-002-set-primary-spans\)/)
})
