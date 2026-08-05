// agent: claude — whole file.
// Tests for the pure resolver core (app/utils/api-links.ts). The core is a
// factory: createApiLinks(modules, site) returns the resolver functions,
// with no import of the real manifest. The tests feed a small fixture, so
// they pin the rules, not the current state of the library.
//
// Node runs TypeScript directly (type stripping), so this file imports the
// .ts module with its full extension.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createApiLinks, type ApiModules } from '../app/utils/api-links.ts'

// A small manifest in the shape the ingest script writes.
const MODULES: ApiModules = {
  'Zocam.Point': {
    slug: 'zocam-point',
    types: { t: 't', month: 'month' },
    functions: { 'compose': 'compose', 'compose!': 'compose-1', 'month': 'month-1', 'new!': 'new' },
  },
  'Zocam.Span': {
    slug: 'zocam-span',
    types: { t: 't' },
    functions: { ground: 'ground', 'member?': 'member', 'new!': 'new', union: 'union' },
  },
  'Zocam.Span.Arc': { slug: 'zocam-span-arc', types: { t: 't' }, functions: {} },
  'Zocam': { slug: 'zocam', types: {}, functions: {} },
}

const site = createApiLinks(MODULES, { repoFor: () => 'yuri4n/zocam' })
const r = (text: string, path = '/design/adrs/002-set-primary-spans') => site.resolveApiRef(text, path)

test('a fully qualified reference finds its page and anchor', () => {
  assert.equal(r('Zocam.Point.compose/2'), '/api/zocam-point#compose')
  assert.equal(r('Zocam.Span.t()'), '/api/zocam-span#t')
  assert.equal(r('Zocam.Point.compose!/2'), '/api/zocam-point#compose-1')
})

test('on its own page, a reference becomes a bare hash', () => {
  assert.equal(r('Zocam.Span.ground/3', '/api/zocam-span'), '#ground')
  assert.equal(r('Zocam.Span', '/api/zocam-span'), null)
})

test('an alias resolves like in Elixir: the tail segments name the module', () => {
  assert.equal(r('Point.compose/2'), '/api/zocam-point#compose')
  assert.equal(r('Span'), '/api/zocam-span')
  assert.equal(r('Span.Arc'), '/api/zocam-span-arc')
  assert.equal(r('Arc'), '/api/zocam-span-arc')
  assert.equal(r('%Span{from: a}'), '/api/zocam-span')
})

test('an alias that two modules share stays plain text', () => {
  const amb = createApiLinks(
    {
      'A.Foo': { slug: 'a-foo', types: {}, functions: {} },
      'B.Foo': { slug: 'b-foo', types: {}, functions: {} },
    },
    { repoFor: () => 'yuri4n/zocam' },
  )
  assert.equal(amb.resolveApiRef('Foo', '/x'), null)
})

test('a project alias shadows a stdlib root, as an Elixir alias does', () => {
  const shadow = createApiLinks(
    { 'My.Stream': { slug: 'my-stream', types: {}, functions: { run: 'run' } } },
    { repoFor: () => 'yuri4n/zocam' },
  )
  assert.equal(shadow.resolveApiRef('Stream.run/1', '/x'), '/api/my-stream#run')
  // When the aliased module does not know the member, the alias probably
  // guessed wrong: the stdlib takes the reference back.
  assert.equal(shadow.resolveApiRef('Stream.map/2', '/x'), 'https://hexdocs.pm/elixir/Stream.html#map/2')
})

test('a stdlib member links to hexdocs; a bare stdlib root stays plain', () => {
  assert.equal(r('Enum.map/2'), 'https://hexdocs.pm/elixir/Enum.html#map/2')
  assert.equal(r('Date.t()'), 'https://hexdocs.pm/elixir/Date.html#t:t/0')
  assert.equal(r('Task'), null)
})

test('a bare entry with one owner links from any page', () => {
  assert.equal(r('ground/3'), '/api/zocam-span#ground')
  assert.equal(r('member?/2'), '/api/zocam-span#member')
  assert.equal(r('compose/2'), '/api/zocam-point#compose')
})

test('a bare entry that many modules own stays plain text', () => {
  assert.equal(r('new!/1'), null)
  assert.equal(r('t()'), null)
})

test('the () and /arity suffixes choose between a type and a function', () => {
  assert.equal(r('month()'), '/api/zocam-point#month')
  assert.equal(r('month/1'), '/api/zocam-point#month-1')
})

test('on an API page, the page module answers before the global owner', () => {
  assert.equal(r('union/2', '/api/zocam-span'), '#union')
  // The page module does not know the name, so the single owner answers.
  assert.equal(r('ground/3', '/api/zocam-point'), '/api/zocam-span#ground')
})

test('a file path links to the GitHub blob, a folder to the tree', () => {
  assert.equal(r('lib/zocam/point.ex'), 'https://github.com/yuri4n/zocam/blob/main/lib/zocam/point.ex')
  assert.equal(r('test/zocam'), 'https://github.com/yuri4n/zocam/tree/main/test/zocam')
  assert.equal(r('mix.exs'), 'https://github.com/yuri4n/zocam/blob/main/mix.exs')
})

test('a top folder with a closing slash links to its tree', () => {
  assert.equal(r('lib/'), 'https://github.com/yuri4n/zocam/tree/main/lib')
  assert.equal(r('docs/'), 'https://github.com/yuri4n/zocam/tree/main/docs')
  // Without the slash, one word is prose, not a path.
  assert.equal(r('lib'), null)
})

test('a glob links to the folder that holds the matches; an arity is not a path', () => {
  assert.equal(r('docs/adr-*.md'), 'https://github.com/yuri4n/zocam/tree/main/docs')
  assert.equal(site.resolvePathRef('foo/3'), null)
})

test('findRefRanges collects every reference of a fence, without overlaps', () => {
  const text = 'a = Point.compose!(x, y)\nsee lib/zocam/point.ex and ground/3'
  const ranges = site.findRefRanges(text, '/guide/spans')
  const hrefs = ranges.map((x) => x.href).sort()
  assert.deepEqual(hrefs, [
    '/api/zocam-point#compose-1',
    '/api/zocam-span#ground',
    'https://github.com/yuri4n/zocam/blob/main/lib/zocam/point.ex',
  ])
  // Ranges must not overlap: each covers its own slice of the text.
  const sorted = [...ranges].sort((a, b) => a.start - b.start)
  for (let i = 1; i < sorted.length; i++) assert.ok(sorted[i]!.start >= sorted[i - 1]!.end)
})
